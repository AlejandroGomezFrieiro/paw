//! Clips: their fields, notes, controls and audio.

#![allow(clippy::unwrap_used, reason = "fixed with the running work on the session, the API and the model of paw-core")]

use super::*;
use document::ClipChange;

impl Session {
    pub(crate) fn clip_view(&self, id: Id) -> Result<ClipView<'_>> {
        if let Some((part, index)) = self.doc.project.find_cue_clip(id) {
            let mut view = clip_json(&self.doc.project.part(part).unwrap().cues[index], part, self.files_there.after(self.doc.changes(), self.now));
            view.cue = Some(true);
            return Ok(view);
        }
        let (part, _) = self
            .doc.project
            .find_clip(id)
            .with_context(|| format!("no clip {id}"))?;
        let clip = self.doc.project.clip(id).unwrap();
        let mut view = clip_json(clip, part, self.files_there.after(self.doc.changes(), self.now));
        self.note_stretching(clip, &mut view);
        view.link_count = clip.link.as_deref().map(|name| self.doc.project.link_count(name));
        Ok(view)
    }

    /// The clips on a part that overlap `span` (`from`, `to` in beats; all
    /// of them with `None`), in timeline order, without their notes.
    pub(crate) fn clip_list_in(&self, part: Id, span: Option<(f64, f64)>) -> Result<Vec<ClipView<'_>>> {
        let t = self
            .doc.project
            .part(part)
            .with_context(|| format!("no part {part}"))?;
        let mut clips: Vec<&Arc<Clip>> = t
            .clips
            .iter()
            .filter(|c| span.is_none_or(|(from, to)| c.start < to && c.start + c.length > from))
            .collect();
        clips.sort_by(|a, b| a.start.total_cmp(&b.start));
        Ok(clips
            .into_iter()
            .map(|c| {
                let mut view = clip_json(c, part, self.files_there.after(self.doc.changes(), self.now));
                self.note_stretching(c, &mut view);
                view
            })
            .collect())
    }

    /// Add a clip to `part` ([`Document::clip_add`]). A `.midi2` clip
    /// file in `opts`, and the sound file of an audio clip, are read here.
    pub(crate) fn clip_add(&mut self, part: Id, mut opts: ClipOpts) -> Result<Id> {
        // The master refuses a clip before its file is read.
        document::check_clip_part(part)?;
        let source = Self::read_midi_source(&mut opts)?;
        // The clip keeps its sound file by the whole path.
        opts.file = opts.file.map(|file| std::path::absolute(&file).unwrap_or(file));
        let audio = &mut self.audio;
        self.doc.clip_add(part, opts, source, |file| Ok(audio.load(file)?.seconds()))
    }

    /// A MIDI clip file: a MIDI clip that refers to it, as long as it is
    /// not edited (`Clip::source`). Fills `opts` from the file.
    fn read_midi_source(opts: &mut ClipOpts) -> Result<Option<std::path::PathBuf>> {
        let Some(file) = opts
            .file
            .take_if(|f| f.extension().is_some_and(|e| e == "midi2"))
        else {
            return Ok(None);
        };
        let file = std::path::absolute(&file).unwrap_or(file);
        let bytes = std::fs::read(&file).with_context(|| format!("reading {}", file.display()))?;
        let read = crate::clipfile::decode(&bytes)
            .with_context(|| format!("reading {}", file.display()))?;
        opts.kind = Some(ClipKind::Midi);
        opts.notes = read.notes;
        opts.controls = read.controls;
        if opts.length.is_none() && read.length > 0.0 {
            opts.length = Some(read.length);
        }
        if opts.name.is_none() {
            opts.name = file.file_stem().map(|s| s.to_string_lossy().into_owned());
        }
        Ok(Some(file))
    }

    /// The waveform of the part of its file an audio clip plays, as `n`
    /// (min, max, rms) triples scaled by the clip's gain. Cached, so a view
    /// can ask for it every time it draws.
    pub(crate) fn clip_peaks(&mut self, id: Id, n: usize) -> Result<Vec<[f32; 3]>> {
        if n > MAX_PEAKS {
            bail!("a waveform has at most {MAX_PEAKS} points, not {n}");
        }
        let clip = self
            .doc.project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?
            .clone();
        let ClipContent::Audio { gain, .. } = &clip.content else {
            bail!(
                "clip {id} is a {} clip; only audio clips have a waveform",
                clip.content.kind()
            );
        };
        let gain = paw_engine::db_to_gain(*gain);
        let peaks = self.playing_peaks(&clip, n)?;
        Ok(peaks
            .iter()
            .map(|[lo, hi, rms]| [lo * gain, hi * gain, rms * gain])
            .collect())
    }

    /// The waveform of any stretch of a sound file, as [`clip_peaks`](Self::clip_peaks)
    /// gives a clip's: `seconds` of it from `offset`, as `n` (min, max, rms)
    /// triples. For what a clip does not play now, such as its other takes.
    pub(crate) fn media_peaks(
        &mut self,
        file: &Path,
        offset: f64,
        seconds: f64,
        n: usize,
    ) -> Result<Vec<[f32; 3]>> {
        if n > MAX_PEAKS {
            bail!("a waveform has at most {MAX_PEAKS} points, not {n}");
        }
        let (offset, seconds) = (finite("offset", offset)?, finite("seconds", seconds)?);
        if seconds <= 0.0 || n == 0 {
            return Ok(Vec::new());
        }
        let source = self.sources.record(file).map(|r| r.hash);
        Ok(self.audio.peaks(file, source, offset.max(0.0), seconds, n)?.to_vec())
    }

    /// How many beats of sound an audio clip's file holds from where the
    /// clip starts playing it: as long as the clip can be made.
    pub(crate) fn clip_source_length(&mut self, id: Id) -> Result<f64> {
        let clip = self
            .doc.project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?;
        let ClipContent::Audio { file, offset, .. } = &clip.content else {
            bail!("clip {id} is not an audio clip");
        };
        let (file, offset, start) = (file.clone(), *offset, clip.start);
        let map = self.doc.project.tempo_map().clone();
        let warp = crate::warp::of(clip, &map).unwrap_or_else(|| crate::warp::Warp::even(1.0));
        let data = self.audio.load(&file)?;
        let seconds = (warp.forward(data.seconds()) - warp.forward(offset)).max(0.0);

        Ok(map.beat(map.seconds(start) + seconds) - start)
    }

    /// Change clip `id` by a patch, one field after the other in the order
    /// of their keys ([`ClipPatch::changes`]).
    pub(crate) fn clip_patch(&mut self, id: Id, patch: ClipPatch) -> Result<()> {
        for change in patch.changes()? {
            self.clip_set(id, change)?;
        }
        Ok(())
    }

    /// Make one change of clip `id` ([`Document::clip_set`]). A value the
    /// clip already holds is no change; a new sound file is read first;
    /// the fields of how a clip plays are `set_playing`'s.
    fn clip_set(&mut self, id: Id, change: ClipChange) -> Result<()> {
        let project = &self.doc.project;
        let held = project.clip(id).is_some_and(|clip| {
            let part = project.find_clip(id).or_else(|| project.find_cue_clip(id)).map(|(part, _)| part);
            change.holds(clip, part)
        });
        if held {
            return Ok(());
        }
        match change {
            // Another file for an audio clip (another take) has to be one
            // that can be read, before the clip is changed.
            ClipChange::File(path) => {
                let path = std::path::absolute(&path).unwrap_or(path);
                self.audio.load(&path)?;
                self.doc.clip_set(id, ClipChange::File(path))
            }
            change if change.is_playing() => self.set_playing(id, change),
            change => self.doc.clip_set(id, change),
        }
    }
}
