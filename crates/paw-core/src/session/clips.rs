//! Clips: their fields, notes, controls and audio.

use super::*;

impl Session {
    pub fn clip_view(&self, id: Id) -> Result<Value> {
        if let Some((track, index)) = self.project.find_cue_clip(id) {
            let mut view = clip_json(&self.project.track(track).unwrap().cues[index], track);
            view["cue"] = json!(true);
            return Ok(view);
        }
        let (track, _) = self
            .project
            .find_clip(id)
            .with_context(|| format!("no clip {id}"))?;
        let clip = self.project.clip(id).unwrap();
        let mut view = clip_json(clip, track);
        self.note_stretching(clip, &mut view);
        Ok(view)
    }

    /// The clips on a track, in timeline order, without their notes.
    pub fn clip_list(&self, track: Id) -> Result<Value> {
        let t = self
            .project
            .track(track)
            .with_context(|| format!("no track {track}"))?;
        let mut clips: Vec<&Arc<Clip>> = t.clips.iter().collect();
        clips.sort_by(|a, b| a.start.total_cmp(&b.start));
        Ok(Value::Array(
            clips
                .into_iter()
                .map(|c| {
                    let mut view = clip_json(c, track);
                    self.note_stretching(c, &mut view);
                    view
                })
                .collect(),
        ))
    }

    pub fn clip_add(&mut self, track: Id, opts: ClipOpts) -> Result<Id> {
        if track == MASTER_ID {
            bail!("the master track has no clips: put them on a track");
        }
        let mut opts = opts;
        // A MIDI clip file: a MIDI clip that refers to it, as long as it
        // is not edited (`Clip::source`).
        let mut source = None;
        if let Some(file) = opts
            .file
            .take_if(|f| f.extension().is_some_and(|e| e == "midi2"))
        {
            let file = std::path::absolute(&file).unwrap_or(file);
            let bytes =
                std::fs::read(&file).with_context(|| format!("reading {}", file.display()))?;
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
            source = Some(file);
        }
        let kind = opts.kind.unwrap_or(if opts.file.is_some() {
            ClipKind::Audio
        } else {
            ClipKind::Midi
        });
        let tempo = self.project.tempo_map().clone();
        let (content, natural, default_name) = match kind {
            ClipKind::Midi => {
                check_notes(&opts.notes)?;
                let end = opts
                    .notes
                    .iter()
                    .map(|n| n.start + n.length)
                    .fold(0.0, f64::max);
                let bar = tempo.bar_length(opts.start);
                // Default to whole bars, long enough for the notes given.
                let natural = (end / bar).ceil().max(1.0) * bar;
                (
                    ClipContent::Midi {
                        notes: sorted(opts.notes).into(),
                        controls: check_controls(opts.controls)?,
                    },
                    natural,
                    "midi".to_string(),
                )
            }
            ClipKind::Audio => {
                let file = opts.file.context("audio clips need a `file`")?;
                if !opts.offset.is_finite() || opts.offset < 0.0 {
                    bail!("an audio clip's offset is a number of seconds from 0 up");
                }
                let gain = finite("clip gain", opts.gain)?.clamp(-120.0, 24.0);
                let file = std::path::absolute(&file).unwrap_or(file);
                let data = self.audio.load(&file)?;
                // Its whole file from where it starts, in time.
                let seconds = (data.seconds() - opts.offset).max(0.0) * opts.stretch.unwrap_or(1.0);
                let natural = tempo.beat(tempo.seconds(opts.start) + seconds) - opts.start;
                let name = file.file_stem().map(|s| s.to_string_lossy().into_owned());
                let content = ClipContent::Audio {
                    file,
                    offset: opts.offset,
                    gain,
                    edits: Vec::new(),
                };
                (content, natural, name.unwrap_or_else(|| "audio".into()))
            }
        };
        let length = opts.length.unwrap_or(natural);
        if !length.is_finite() || length <= 0.0 || !opts.start.is_finite() || opts.start < 0.0 {
            bail!("clips need a start of at least 0 and a length above 0");
        }
        check_fade(opts.fade_in)?;
        check_fade(opts.fade_out)?;
        if kind == ClipKind::Midi && (opts.fade_in > 0.0 || opts.fade_out > 0.0) {
            bail!("only audio clips fade");
        }
        let stretch = opts.stretch.unwrap_or(1.0);
        stretching::check_playing(kind, stretch, opts.pitch, opts.source_tempo)?;
        stretching::check_warp(kind, &opts.warp)?;
        if opts.loop_length.is_some_and(|l| !l.is_finite() || l <= 0.0)
            || !opts.loop_start.is_finite()
        {
            bail!("a clip's loop is a length above 0 from a start");
        }
        let id = self.new_id();
        self.edit(|p| {
            let t = p
                .track_mut(track)
                .with_context(|| format!("no track {track}"))?;
            let clip = Arc::new(Clip {
                timebase: opts.timebase.filter(|_| kind == ClipKind::Audio),
                stretch,
                pitch: opts.pitch,
                stretch_mode: opts.stretch_mode,
                source_tempo: opts.source_tempo.filter(|_| kind == ClipKind::Audio),
                warp: opts.warp.clone(),
                formants: opts.formants,
                looped: opts.looped && opts.loop_length.is_some(),
                loop_length: opts.loop_length,
                loop_start: opts.loop_start,
                id,
                name: opts.name.unwrap_or(default_name),
                // A clip off the timeline starts at 0 whatever `start` says.
                start: if opts.cue { 0.0 } else { opts.start },
                length,
                muted: false,
                content,
                fade_in: opts.fade_in,
                fade_out: opts.fade_out,
                meta: opts.meta,
                source,
                origin: None,
            });
            if opts.cue {
                t.cues.push(clip);
            } else {
                t.clips.push(clip);
                let at = t.clips.len() - 1;
                p.found_clip(id, track, at);
            }
            Ok(id)
        })
    }

    /// The waveform of the part of its file an audio clip plays, as `n`
    /// (min, max, rms) triples scaled by the clip's gain. Cached, so a view
    /// can ask for it every time it draws.
    pub fn clip_peaks(&mut self, id: Id, n: usize) -> Result<Vec<[f32; 3]>> {
        if n > MAX_PEAKS {
            bail!("a waveform has at most {MAX_PEAKS} points, not {n}");
        }
        let clip = self
            .project
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
    pub fn media_peaks(
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
        Ok(self.audio.peaks(file, offset.max(0.0), seconds, n)?.to_vec())
    }

    /// How many beats of sound an audio clip's file holds from where the
    /// clip starts playing it: as long as the clip can be made.
    pub fn clip_source_length(&mut self, id: Id) -> Result<f64> {
        let clip = self
            .project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?;
        let ClipContent::Audio { file, offset, .. } = &clip.content else {
            bail!("clip {id} is not an audio clip");
        };
        let (file, offset, start) = (file.clone(), *offset, clip.start);
        let map = self.project.tempo_map().clone();
        let warp = crate::warp::of(clip, &map).unwrap_or_else(|| crate::warp::Warp::even(1.0));
        let data = self.audio.load(&file)?;
        let seconds = (warp.forward(data.seconds()) - warp.forward(offset)).max(0.0);

        Ok(map.beat(map.seconds(start) + seconds) - start)
    }

    pub fn clip_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            if let Some((track, index)) = p.find_cue_clip(id) {
                p.track_mut(track).unwrap().cues.remove(index);
                return Ok(());
            }
            let (track, index) = p.find_clip(id).with_context(|| format!("no clip {id}"))?;
            p.track_mut(track).unwrap().clips.remove(index);
            Ok(())
        })
    }

    pub fn clip_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        // `None` for a field of a playing clip (`clip_set_playing`) or none.
        let field = ClipField::parse(key);
        let plain = matches!(
            field,
            Some(ClipField::Start | ClipField::Length | ClipField::Name | ClipField::Muted)
        );
        let quick = plain
            .then(|| {
                let (track, index) = self.project.find_clip(id)?;
                self.project.track(track)?.clips.get(index)
            })
            .flatten();
        let held = match quick {
            Some(c) => {
                let view = json!({ "start": c.start, "length": c.length, "name": c.name, "muted": c.muted });
                holds(&Ok(view), key, &value)
            }
            None => holds(&self.clip_view(id), key, &value),
        };
        if held {
            return Ok(());
        }
        // Another file for an audio clip (another take) has to be one that
        // can be read, before the clip is changed.
        let new_file = match (field, value.as_str()) {
            (Some(ClipField::File), Some(path)) => {
                let path = PathBuf::from(path);
                let path = std::path::absolute(&path).unwrap_or(path);
                self.audio.load(&path)?;
                Some(path)
            }
            _ => None,
        };
        if let Some(done) = self.clip_set_playing(id, key, &value) {
            return done;
        }
        self.edit(|p| {
            // A clip off the timeline has no `start` there.
            let cue = p.find_cue_clip(id).is_some();
            match field {
                Some(ClipField::Start) if cue => bail!("a clip off the timeline starts at 0"),
                Some(ClipField::Track) if cue => {
                    cues::move_cue(p, id, de(key, value)?)?;
                    return Ok(());
                }
                Some(ClipField::Track) => return move_clip(p, id, value),
                _ => {}
            }
            let c = p.clip_mut(id).with_context(|| format!("no clip {id}"))?;
            match (field, &mut c.content) {
                (Some(ClipField::Name), _) => c.name = de(key, value)?,
                (Some(ClipField::Start), _) => c.start = de::<f64>(key, value)?.max(0.0),
                (Some(ClipField::Length), _) => {
                    let length: f64 = de(key, value)?;
                    if !length.is_finite() || length <= 0.0 {
                        bail!("clip length must be above 0");
                    }
                    c.length = length;
                }
                (Some(ClipField::Muted), _) => c.muted = de(key, value)?,
                (Some(ClipField::Meta), _) => c.meta = de_meta(key, value)?,
                (Some(ClipField::File), ClipContent::Audio { file, .. }) => {
                    *file = new_file.context("an audio clip's file is a path")?;
                }
                (Some(ClipField::Offset), ClipContent::Audio { offset, .. }) => {
                    *offset = de::<f64>(key, value)?.max(0.0);
                }
                (Some(ClipField::Gain), ClipContent::Audio { gain, .. }) => {
                    *gain = de::<f64>(key, value)?.clamp(-120.0, 24.0);
                }
                (Some(ClipField::FadeIn), ClipContent::Audio { .. }) => {
                    c.fade_in = check_fade(de(key, value)?)?;
                }
                (Some(ClipField::FadeOut), ClipContent::Audio { .. }) => {
                    c.fade_out = check_fade(de(key, value)?)?;
                }
                _ => bail!("{} clips have no settable field `{key}`", c.content.kind()),
            }
            Ok(())
        })
    }

    pub fn clip_notes(&self, id: Id) -> Result<&Notes> {
        match &self
            .project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?
            .content
        {
            ClipContent::Midi { notes, .. } => Ok(notes),
            ClipContent::Audio { .. } => bail!("clip {id} is an audio clip"),
            ClipContent::Custom(custom) => bail!("clip {id} is a clip of the kind `{}`", custom.kind),
        }
    }

    /// The controller, pitch wheel and pressure moves of a MIDI clip.
    pub fn clip_controls(&self, id: Id) -> Result<&[Control]> {
        match &self
            .project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?
            .content
        {
            ClipContent::Midi { controls, .. } => Ok(controls),
            ClipContent::Audio { .. } => bail!("clip {id} is an audio clip"),
            ClipContent::Custom(custom) => bail!("clip {id} is a clip of the kind `{}`", custom.kind),
        }
    }

    pub fn clip_set_controls(&mut self, id: Id, new: Vec<Control>) -> Result<()> {
        let new = check_controls(new)?;
        self.edit(|p| {
            match &mut p
                .clip_mut(id)
                .with_context(|| format!("no clip {id}"))?
                .content
            {
                ClipContent::Midi { controls, .. } => {
                    *controls = new;
                    Ok(())
                }
                ClipContent::Audio { .. } => bail!("clip {id} is an audio clip"),
                ClipContent::Custom(custom) => bail!("clip {id} is a clip of the kind `{}`", custom.kind),
            }
        })
    }

    /// Replace a MIDI clip's notes, or add to them when `append` is set.
    pub fn clip_set_notes(&mut self, id: Id, new: Vec<Note>, append: bool) -> Result<()> {
        check_notes(&new)?;
        self.edit(|p| {
            match &mut p
                .clip_mut(id)
                .with_context(|| format!("no clip {id}"))?
                .content
            {
                ClipContent::Midi { notes, .. } => {
                    let mut all = if append { notes.to_vec() } else { Vec::new() };
                    all.extend(new);
                    // A list sent back whole with a few notes changed shares
                    // the rest with the clip before it, and with the undo
                    // history.
                    notes.assign(sorted(all));
                    Ok(())
                }
                ClipContent::Audio { .. } => bail!("clip {id} is an audio clip"),
                ClipContent::Custom(custom) => bail!("clip {id} is a clip of the kind `{}`", custom.kind),
            }
        })
    }
}

/// A field that [`Session::clip_set`] changes: the key that Lua gives,
/// parsed once. Which fields a clip has depends on its kind, so an unknown
/// key fails where the clip is known.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ClipField {
    Name,
    Start,
    Length,
    Muted,
    Meta,
    Track,
    File,
    Offset,
    Gain,
    FadeIn,
    FadeOut,
}

impl ClipField {
    fn parse(key: &str) -> Option<Self> {
        Some(match key {
            "name" => Self::Name,
            "start" => Self::Start,
            "length" => Self::Length,
            "muted" => Self::Muted,
            "meta" => Self::Meta,
            "track" => Self::Track,
            "file" => Self::File,
            "offset" => Self::Offset,
            "gain" => Self::Gain,
            "fade_in" => Self::FadeIn,
            "fade_out" => Self::FadeOut,
            _ => return None,
        })
    }
}

/// Move clip `id`, on the timeline, to the end of the track that `value` names.
fn move_clip(p: &mut Project, id: Id, value: Value) -> Result<()> {
    let (from, index) = p.find_clip(id).with_context(|| format!("no clip {id}"))?;
    let to: Id = de("track", value)?;
    if to == MASTER_ID {
        bail!("the master track has no clips: put them on a track");
    }
    if p.track(to).is_none() {
        bail!("no track {to}");
    }
    let clip = p
        .track_mut(from)
        .context("the clip's track was found")?
        .clips
        .remove(index);
    let clips = &mut p.track_mut(to).context("the track was found")?.clips;
    clips.push(clip);
    let at = clips.len() - 1;
    p.found_clip(id, to, at);
    Ok(())
}
