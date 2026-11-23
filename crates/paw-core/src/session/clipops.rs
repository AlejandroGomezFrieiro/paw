//! Operations on audio clips: reverse, a gain on a part and pencil fixes,
//! which go in the clip's edit list (`edits.rs`); glue, which makes a new
//! file; and normalize, which only sets the clip's gain. None touches the
//! file a clip played before, and each is one undo step.

use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use paw_engine::AudioData;
use serde_json::{Value, json};

use super::{RenderOpts, Session, unique_path};
use crate::edits::AudioEdit;
use crate::model::{Clip, ClipContent, Id, MASTER_ID};

/// The refusal of a work on audio clips for clip `id`, which plays no audio
/// of its own to change.
fn not_audio(clip: &Clip, id: Id) -> anyhow::Error {
    match &clip.content {
        ClipContent::Custom(custom) if clip.playable().is_some() => anyhow::anyhow!(
            "clip {id} is a clip of the kind `{}`: its audio sound cannot be changed here",
            custom.kind
        ),
        ClipContent::Custom(custom) => anyhow::anyhow!(
            "clip {id} is a clip of the kind `{}` with no audio sound: this works on audio clips",
            custom.kind
        ),
        _ => anyhow::anyhow!("clip {id} is a MIDI clip: this works on audio clips"),
    }
}

impl Session {
    /// The file, offset and gain of an audio clip.
    fn audio_clip(&self, id: Id) -> Result<(Arc<Clip>, PathBuf, f64, f64)> {
        let clip = self
            .doc.project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?
            .clone();
        let Some(ClipContent::Audio { file, offset, gain, .. }) = clip.playable() else {
            return Err(not_audio(&clip, id));
        };
        let (file, offset, gain) = (file.clone(), *offset, *gain);
        Ok((clip, file, offset, gain))
    }

    /// How many seconds of its sound an audio clip plays, from `offset`.
    fn played_seconds(&self, clip: &Clip, offset: f64) -> f64 {
        // Its real extent in time, by the tempo map, in seconds of the file.
        let map = self.doc.project.tempo_map();
        let warp = crate::warp::of(clip, map).unwrap_or_else(|| crate::warp::Warp::even(1.0));
        let played = map.seconds_between(clip.start, clip.start + clip.length);
        warp.inverse(warp.forward(offset) + played) - offset
    }

    /// An audio clip's sound with its edit list made: its file as it is when
    /// it has none.
    fn edited_sound(&mut self, clip: &Clip, file: &std::path::Path) -> Result<Arc<AudioData>> {
        let data = self.audio.load(file)?;
        match clip.playable() {
            Some(ClipContent::Audio { edits, .. }) if !edits.is_empty() => {
                Ok(Arc::new(crate::edits::apply(&data, edits)))
            }
            _ => Ok(data),
        }
    }

    /// The samples an audio clip plays, from its offset for its length;
    /// silence past the end of the file.
    fn clip_samples(&mut self, id: Id) -> Result<(AudioData, Arc<Clip>, f64)> {
        let (clip, file, offset, gain) = self.audio_clip(id)?;
        let data = self.edited_sound(&clip, &file)?;
        let rate = data.sample_rate as f64;
        let from = (offset * rate).round() as usize;
        let seconds = self.played_seconds(&clip, offset);

        let frames = (seconds * rate).round() as usize;
        let take = |c: &[f32]| {
            let mut out: Vec<f32> = c.iter().skip(from).take(frames).copied().collect();
            out.resize(frames, 0.0);
            out
        };
        let part = AudioData {
            sample_rate: data.sample_rate,
            channels: [
                take(&data.channels[0]).into(),
                take(&data.channels[1]).into(),
            ],
        };
        Ok((part, clip, gain))
    }

    /// A new file in the project's media directory, named after a clip.
    fn new_media_file(&self, clip: &Clip, what: &str) -> Result<PathBuf> {
        let dir = self.media_dir();
        std::fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;
        Ok(unique_path(
            &dir,
            &format!("{}-{what}", super::file_safe(&clip.name)),
        ))
    }

    /// Play an audio clip backwards: a `reverse` in its edit list (or one
    /// taken away, when it was the last edit), and its offset where the same
    /// part of the sound is. Its fades change ends too. Returns `{ edits }`,
    /// how many edits the clip has.
    pub fn clip_reverse(&mut self, id: Id) -> Result<Value> {
        let (clip, file, offset, _) = self.audio_clip(id)?;
        let length = self.audio.load(&file)?.seconds();
        let played = self.played_seconds(&clip, offset);
        let back = (length - offset - played).max(0.0);
        let edits = self.doc.edit(|p| {
            let c = p.clip_mut(id).context("the clip went away")?;
            let ClipContent::Audio { offset, edits, .. } = &mut c.content else {
                return Err(not_audio(c, id));
            };
            if edits.last() == Some(&AudioEdit::Reverse) {
                edits.pop();
            } else {
                edits.push(AudioEdit::Reverse);
            }
            *offset = back;
            let n = edits.len();
            std::mem::swap(&mut c.fade_in, &mut c.fade_out);
            Ok(n)
        })?;
        Ok(json!({ "edits": edits }))
    }

    /// Add an edit to an audio clip's edit list, with its times counted from
    /// where the clip starts in its sound: a gain on a part, or samples drawn
    /// over its own (a pencil fix). Returns how many edits it has.
    pub fn clip_edit_add(&mut self, id: Id, mut edit: AudioEdit) -> Result<usize> {
        let (_, _, offset, _) = self.audio_clip(id)?;
        match &mut edit {
            AudioEdit::Reverse => {}
            AudioEdit::Gain { from, to, .. } => {
                *from += offset;
                *to += offset;
            }
            AudioEdit::Pencil { at, .. } => *at += offset,
        }
        crate::edits::check(std::slice::from_ref(&edit))?;
        self.doc.edit(|p| {
            let c = p.clip_mut(id).context("the clip went away")?;
            let ClipContent::Audio { edits, .. } = &mut c.content else {
                return Err(not_audio(c, id));
            };
            edits.push(edit);
            Ok(edits.len())
        })
    }

    /// Take away an audio clip's whole edit list: it plays its file again.
    /// Returns how many edits it had.
    pub fn clip_edits_clear(&mut self, id: Id) -> Result<usize> {
        let (clip, file, offset, _) = self.audio_clip(id)?;
        let Some(ClipContent::Audio { edits, .. }) = clip.playable() else {
            return Ok(0);
        };
        if edits.is_empty() {
            return Ok(0);
        }
        // Where the part it plays is in the file, with the reverses undone.
        let reversed = edits.iter().filter(|e| **e == AudioEdit::Reverse).count() % 2 == 1;
        let back = if reversed {
            let length = self.audio.load(&file)?.seconds();
            (length - offset - self.played_seconds(&clip, offset)).max(0.0)
        } else {
            offset
        };
        self.doc.edit(|p| {
            let c = p.clip_mut(id).context("the clip went away")?;
            let ClipContent::Audio { offset, edits, .. } = &mut c.content else {
                return Err(not_audio(c, id));
            };
            let n = edits.len();
            edits.clear();
            *offset = back;
            if reversed {
                std::mem::swap(&mut c.fade_in, &mut c.fade_out);
            }
            Ok(n)
        })
    }

    /// Bring the loudest sample an audio clip plays to `level` dB, by its
    /// gain. Returns the new gain.
    pub fn clip_normalize(&mut self, id: Id, level: f64) -> Result<f64> {
        if !level.is_finite() || level > 0.0 {
            bail!("normalize to a level in dB at or below 0, such as -1");
        }
        let (part, _, _) = self.clip_samples(id)?;
        let peak = part
            .channels
            .iter()
            .flatten()
            .fold(0f32, |m, s| if s.is_finite() { m.max(s.abs()) } else { m });
        if peak <= 0.0 {
            bail!("clip {id} is silent: there is nothing to bring to a level");
        }
        let gain = (level - paw_engine::gain_to_db(peak)).clamp(-120.0, 24.0);
        self.doc.edit(|p| {
            let c = p.clip_mut(id).context("the clip went away")?;
            let ClipContent::Audio { gain: g, .. } = &mut c.content else {
                return Err(not_audio(c, id));
            };
            *g = gain;
            Ok(())
        })?;
        Ok(gain)
    }

    /// Join audio clips of one track into one clip playing a new file: what
    /// they play together, with their gains, fades and overlaps, and without
    /// the track's devices, fader or pan. With one clip, it and every audio
    /// clip on its track that touches or overlaps it, one after another.
    pub fn clip_glue(&mut self, ids: &[Id]) -> Result<Value> {
        let first = *ids.first().context("no clips to glue")?;
        let (track, _) = self
            .doc.project
            .find_clip(first)
            .with_context(|| format!("no clip {first}"))?;
        let clips: Vec<Arc<Clip>> = self
            .doc.project
            .track(track)
            .context("no such track")?
            .clips
            .to_vec();
        let chosen = glue_choice(&clips, ids, first)?;
        let start = clips
            .iter()
            .filter(|c| chosen.contains(&c.id))
            .map(|c| c.start)
            .fold(f64::INFINITY, f64::min);
        let end = clips
            .iter()
            .filter(|c| chosen.contains(&c.id))
            .map(|c| c.start + c.length)
            .fold(f64::NEG_INFINITY, f64::max);

        let project = self.glue_project(track, &chosen)?;
        let first_clip = clips
            .iter()
            .find(|c| c.id == first)
            .context("no clip")?
            .clone();
        let path = self.new_media_file(&first_clip, "glued")?;
        let opts = RenderOpts {
            start,
            end: Some(end),
            tail: 0.0,
            bits: 32,
            tap: Some(super::render::Tap::Groups),
            ..RenderOpts::default()
        };
        self.render_snapshot(project, &path, &opts)?;
        self.render_wait()?;

        let glued = Arc::new(Clip {
            timebase: None,
            stretch: 1.0,
            pitch: 0.0,
            stretch_mode: Default::default(),
            source_tempo: None,
            warp: Vec::new(),
            formants: false,
            looped: false,
            loop_length: None,
            loop_start: 0.0,
            id: self.doc.new_id(),
            name: first_clip.name.clone(),
            start,
            length: end - start,
            muted: false,
            content: ClipContent::Audio {
                file: path.clone(),
                offset: 0.0,
                gain: 0.0,
                edits: Vec::new(),
            },
            fade_in: 0.0,
            fade_out: 0.0,
            meta: first_clip.meta.clone(),
            source: None,
            origin: None,
            link: None,
            overrides: Default::default(),
        });
        let id = glued.id;
        self.doc.edit(|p| {
            let t = p.track_mut(track).context("the track went away")?;
            let at = t
                .clips
                .iter()
                .position(|c| chosen.contains(&c.id))
                .unwrap_or(t.clips.len());
            t.clips.retain(|c| !chosen.contains(&c.id));
            t.clips.insert(at.min(t.clips.len()), glued);
            Ok(())
        })?;
        Ok(json!({ "id": id, "file": path, "glued": chosen.len() }))
    }
}

impl Session {
    /// A project of the chosen clips alone on a bare track, straight to a
    /// bare master.
    fn glue_project(&mut self, track: Id, chosen: &[Id]) -> Result<crate::model::Project> {
        self.capture_states();
        let mut project = self.doc.project.clone();
        project.tracks.retain(|t| t.id == track);
        if track == MASTER_ID {
            bail!("clips on the master track cannot be glued");
        }
        let t = Arc::make_mut(&mut project.tracks[0]);
        t.clips.retain(|c| chosen.contains(&c.id));
        t.devices.clear();
        t.lanes.clear();
        t.sends.clear();
        (t.volume, t.pan, t.mute, t.solo, t.output) = (0.0, 0.0, false, false, None);
        t.input = None;
        Ok(project)
    }
}

/// The clips to glue: the ones given, or with one clip, the run of audio
/// clips that touch or overlap it. Each must be an audio clip of its track.
fn glue_choice(clips: &[Arc<Clip>], ids: &[Id], first: Id) -> Result<Vec<Id>> {
    let audio = |c: &Clip| matches!(c.content, ClipContent::Audio { .. });
    let mut chosen: Vec<Id> = ids.to_vec();
    if ids.len() == 1 {
        // Grow the run both ways while a clip touches or overlaps it.
        let (mut lo, mut hi) = {
            let c = clips.iter().find(|c| c.id == first).context("no clip")?;
            (c.start, c.start + c.length)
        };
        loop {
            let before = chosen.len();
            for c in clips {
                if audio(c)
                    && !chosen.contains(&c.id)
                    && c.start <= hi + 1e-9
                    && c.start + c.length >= lo - 1e-9
                {
                    chosen.push(c.id);
                    lo = lo.min(c.start);
                    hi = hi.max(c.start + c.length);
                }
            }
            if chosen.len() == before {
                break;
            }
        }
    }
    for id in &chosen {
        let c = clips
            .iter()
            .find(|c| c.id == *id)
            .with_context(|| format!("clip {id} is not on the same track as clip {first}"))?;
        if !audio(c) {
            bail!("clip {id} is a MIDI clip: only audio clips are glued");
        }
    }
    if chosen.len() < 2 {
        bail!("nothing to glue: no other audio clip touches clip {first}");
    }
    Ok(chosen)
}
