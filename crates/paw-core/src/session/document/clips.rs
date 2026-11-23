//! Clips: their fields, kinds, notes and controls, as the model holds
//! them. What reads a file (a clip file, a sound file) is the session's,
//! in `session/clips.rs`.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use serde_json::Value;

use super::Document;
use crate::model::{
    Clip, ClipContent, Control, CustomContent, Id, MASTER_ID, NestPlay, Note, Notes, Overrides, Project, Signal,
    check_clip_beat, check_notes,
};
use crate::session::{
    ClipKind, ClipOpts, CustomSet, check_controls, check_fade, cues, de, de_meta, finite, sorted, stretching,
};

impl Document {
    /// Add a clip to `track` and give its id. `source` is the clip file
    /// that a MIDI clip refers to, already read into `opts`;
    /// `sound_seconds` reads how long the sound file of an audio clip is.
    pub fn clip_add(
        &mut self,
        track: Id,
        mut opts: ClipOpts,
        source: Option<PathBuf>,
        sound_seconds: impl FnOnce(&Path) -> Result<f64>,
    ) -> Result<Id> {
        check_clip_track(track)?;
        let kind = opts.kind.take().unwrap_or(if opts.nest.is_some() {
            ClipKind::Nest
        } else if opts.file.is_some() {
            ClipKind::Audio
        } else {
            ClipKind::Midi
        });
        if kind != ClipKind::Nest && (opts.nest.is_some() || opts.play.is_some()) {
            bail!("only a subproject's clip has `nest` and `play`");
        }
        // What a custom clip may do besides (fade, stretch) its sound decides.
        let playing = kind.playing(opts.sound.as_ref());
        let (content, natural, default_name) = self.clip_content(track, &kind, &mut opts, sound_seconds)?;
        let length = opts.length.unwrap_or(natural);
        check_clip_opts(playing.clone(), &opts, length)?;
        let id = self.new_id();
        let cue = opts.cue;
        self.edit(|p| {
            let t = p
                .track_mut(track)
                .with_context(|| format!("no track {track}"))?;
            let clip = Arc::new(build_clip(
                id,
                playing,
                opts,
                content,
                default_name,
                length,
                source,
            ));
            if cue {
                t.cues.push(clip);
            } else {
                t.clips.push(clip);
                let at = t.clips.len() - 1;
                p.found_clip(id, track, at);
            }
            Ok(id)
        })
    }

    /// The content of a new clip, its natural length in beats and its
    /// default name. Takes the notes, controls and file out of `opts`.
    /// `sound_seconds` reads how long the sound file of an audio clip is.
    fn clip_content(
        &self,
        track: Id,
        kind: &ClipKind,
        opts: &mut ClipOpts,
        sound_seconds: impl FnOnce(&Path) -> Result<f64>,
    ) -> Result<(ClipContent, f64, String)> {
        let tempo = self.project.tempo_map().clone();
        match kind {
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
                Ok((
                    ClipContent::Midi {
                        notes: sorted(std::mem::take(&mut opts.notes)).into(),
                        controls: check_controls(std::mem::take(&mut opts.controls))?,
                    },
                    natural,
                    "midi".to_string(),
                ))
            }
            ClipKind::Audio => {
                let file = opts.file.take().context("audio clips need a `file`")?;
                if !opts.offset.is_finite() || opts.offset < 0.0 {
                    bail!("an audio clip's offset is a number of seconds from 0 up");
                }
                let gain = finite("clip gain", opts.gain)?.clamp(-120.0, 24.0);
                let file = std::path::absolute(&file).unwrap_or(file);
                // Its whole file from where it starts, in time.
                let seconds = (sound_seconds(&file)? - opts.offset).max(0.0) * opts.stretch.unwrap_or(1.0);
                let natural = tempo.beat(tempo.seconds(opts.start) + seconds) - opts.start;
                let name = file.file_stem().map(|s| s.to_string_lossy().into_owned());
                let content = ClipContent::Audio {
                    file,
                    offset: opts.offset,
                    gain,
                    edits: Vec::new(),
                };
                Ok((content, natural, name.unwrap_or_else(|| "audio".into())))
            }
            ClipKind::Nest => self.nest_clip_content(track, opts),
            ClipKind::Custom(id) => {
                if !self.clip_kinds.contains(id) {
                    bail!(
                        "no clip kind `{id}` is defined: an extension defines it with `paw.clip_kinds.define`"
                    );
                }
                if !opts.notes.is_empty() || !opts.controls.is_empty() {
                    bail!("a clip of the kind `{id}` has `data`, `sound` and `signals`, not notes");
                }
                if opts.file.is_some() {
                    bail!("a clip of the kind `{id}` lists its files as `media`, not `file`");
                }
                let data = opts
                    .data
                    .take()
                    .with_context(|| format!("a clip of the kind `{id}` needs `data`"))?;
                data.check_size()?;
                let length = opts
                    .length
                    .with_context(|| format!("a clip of the kind `{id}` needs a `length`"))?;
                if !opts.offset.is_finite() {
                    bail!("a clip's offset is a number");
                }
                let version = custom_version(opts.version)?;
                let signals = check_signals(std::mem::take(&mut opts.signals))?;
                let content = CustomContent {
                    kind: id.clone(),
                    version,
                    timeline: opts.timeline,
                    offset: opts.offset,
                    data,
                    media: std::mem::take(&mut opts.media),
                    sound: opts.sound.take(),
                    signals,
                };
                Ok((ClipContent::Custom(Box::new(content)), length, id.to_string()))
            }
        }
    }
    /// The content of a new nest clip, its natural length (the rest of its
    /// subproject from `offset`) and its name (the subproject's). A clip
    /// that would put a subproject inside itself is refused with the path.
    fn nest_clip_content(&self, track: Id, opts: &mut ClipOpts) -> Result<(ClipContent, f64, String)> {
        let nest = opts.nest.take().context("a subproject's clip needs `nest`, the subproject's id")?;
        let held = self
            .project
            .nest(nest)
            .with_context(|| format!("no subproject {nest}"))?;
        if !opts.offset.is_finite() || opts.offset < 0.0 {
            bail!("a subproject's clip starts at a beat of the subproject from 0 on");
        }
        if !opts.notes.is_empty() || !opts.controls.is_empty() || opts.file.is_some() {
            bail!("a subproject's clip plays the subproject: it has no notes or file of its own");
        }
        let content = ClipContent::Nest {
            nest,
            offset: opts.offset,
            play: opts.play.take().unwrap_or(NestPlay::Master),
        };
        let host = self
            .project
            .track(track)
            .with_context(|| format!("no track {track}"))?
            .nest;
        self.project.check_place(nest, host)?;
        // A subproject with a tempo of its own lasts its seconds in the song.
        let length = if host.is_none() && held.has_own_tempo() {
            let timing = held.timing(self.project.tempo_map(), None, opts.start, opts.offset);
            timing.song_beat(held.length) - opts.start
        } else {
            held.length - opts.offset
        };
        Ok((content, length.max(1e-3), held.name.clone()))
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
    /// The kinds of clip that extensions defined, by name.
    pub fn clip_kinds(&self) -> Vec<String> {
        self.clip_kinds.iter().map(ToString::to_string).collect()
    }
    /// Let clips of the kind `name` be added (`paw.clip_kinds.define`). The
    /// project keeps no list of kinds: its clips name theirs.
    pub fn clip_kind_define(&mut self, name: &str) -> Result<()> {
        self.clip_kinds.insert(name.parse()?);
        Ok(())
    }
    /// Stop adding clips of the kind `name`. Clips of it that the project
    /// has stay as they are, data and all.
    pub fn clip_kind_remove(&mut self, name: &str) -> Result<()> {
        self.clip_kinds.remove(&name.parse()?);
        Ok(())
    }
    /// The content of a custom clip, as it is saved.
    pub fn clip_custom(&self, id: Id) -> Result<Value> {
        let clip = self.project.clip(id).with_context(|| format!("no clip {id}"))?;
        match &clip.content {
            ClipContent::Custom(custom) => Ok(serde_json::to_value(custom)?),
            other => bail!("clip {id} is a {} clip, not a custom one", other.kind()),
        }
    }
    /// Replace what a custom clip's kind compiled: data, media, sound and
    /// signals together, as one edit.
    pub fn clip_set_custom(&mut self, id: Id, set: CustomSet) -> Result<()> {
        let data = set.data.context("a custom clip is set with its `data`")?;
        data.check_size()?;
        let version = set.version.map(|v| custom_version(Some(v))).transpose()?;
        if set.offset.is_some_and(|o| !o.is_finite()) {
            bail!("a clip's offset is a number");
        }
        let signals = check_signals(set.signals)?;
        self.edit(|p| {
            let clip = p.clip_mut(id).with_context(|| format!("no clip {id}"))?;
            let ClipContent::Custom(custom) = &mut clip.content else {
                bail!("clip {id} is a {} clip, not a custom one", clip.content.kind());
            };
            custom.data = data;
            custom.media = set.media;
            custom.sound = set.sound;
            custom.signals = signals;
            custom.version = version.unwrap_or(custom.version);
            custom.timeline = set.timeline.unwrap_or(custom.timeline);
            custom.offset = set.offset.unwrap_or(custom.offset);
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
            other => bail!("clip {id} is a clip of the kind `{}`", other.kind()),
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
            other => bail!("clip {id} is a clip of the kind `{}`", other.kind()),
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
                other => bail!("clip {id} is a clip of the kind `{}`", other.kind()),
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
                other => bail!("clip {id} is a clip of the kind `{}`", other.kind()),
            }
        })
    }

    /// Set `key` of clip `id` to `value`: the model's part of the
    /// session's `clip_set`. `new_file` is the sound file that `file` names,
    /// already read once by the session.
    pub fn clip_set(&mut self, id: Id, key: &str, value: Value, new_file: Option<PathBuf>) -> Result<()> {
        let field = ClipField::parse(key);
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
                    check_clip_beat("the end of the clip", length)?;
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
                // Slipping a custom clip: where it starts in its data.
                (Some(ClipField::Offset), ClipContent::Custom(custom)) => {
                    custom.offset = finite("offset", de(key, value)?)?;
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
                (Some(ClipField::Transpose), ClipContent::Midi { .. }) => {
                    c.overrides.transpose = override_value(key, value)?;
                }
                (Some(ClipField::Velocity), ClipContent::Midi { .. }) => {
                    c.overrides.velocity = override_value(key, value)?;
                }
                _ => bail!("{} clips have no settable field `{key}`", c.content.kind()),
            }
            Ok(())
        })
    }

    /// Make every clip that refers to a file outside the project the
    /// project's own (`:collect`): the next save writes their files into
    /// its folder. Returns how many. `is_file` says whether a clip's file
    /// is there: a clip whose file is not is left as it is.
    pub fn clip_collect(&mut self, is_file: impl Fn(&Path) -> bool) -> usize {
        let ids: Vec<Id> = self
            .project
            .all_tracks()
            .flat_map(|t| t.clips.iter().chain(&t.cues))
            .filter(|c| c.source.as_ref().is_some_and(|s| is_file(s)))
            .map(|c| c.id)
            .collect();
        for id in &ids {
            if let Some(clip) = self.project.clip_mut(*id) {
                clip.origin = clip.source.take();
            }
        }
        if !ids.is_empty() {
            self.undo.touched = true;
            self.dirty = true;
        }
        ids.len()
    }
}

/// The master track has no clips.
pub(in crate::session) fn check_clip_track(track: Id) -> Result<()> {
    if track == MASTER_ID {
        bail!("the master track has no clips: put them on a track");
    }
    Ok(())
}

/// The checks of a new clip's timing, fades, stretch and loop.
fn check_clip_opts(kind: ClipKind, opts: &ClipOpts, length: f64) -> Result<()> {
    if !length.is_finite() || length <= 0.0 || !opts.start.is_finite() || opts.start < 0.0 {
        bail!("clips need a start of at least 0 and a length above 0");
    }
    check_clip_beat("the end of the clip", length)?;
    check_fade(opts.fade_in)?;
    check_fade(opts.fade_out)?;
    if kind == ClipKind::Midi && (opts.fade_in > 0.0 || opts.fade_out > 0.0) {
        bail!("only audio clips fade");
    }
    if kind != ClipKind::Midi && (opts.transpose != 0 || opts.velocity != 0) {
        bail!("only MIDI clips have a transpose and a velocity change");
    }
    let stretch = opts.stretch.unwrap_or(1.0);
    stretching::check_playing(kind.clone(), stretch, opts.pitch, opts.source_tempo)?;
    stretching::check_warp(kind, &opts.warp)?;
    if opts.loop_length.is_some_and(|l| !l.is_finite() || l <= 0.0)
        || !opts.loop_start.is_finite()
    {
        bail!("a clip's loop is a length above 0 from a start");
    }
    Ok(())
}

/// A new clip, from its options and its content.
fn build_clip(
    id: Id,
    kind: ClipKind,
    opts: ClipOpts,
    content: ClipContent,
    default_name: String,
    length: f64,
    source: Option<std::path::PathBuf>,
) -> Clip {
    Clip {
        timebase: opts.timebase.filter(|_| kind == ClipKind::Audio),
        stretch: opts.stretch.unwrap_or(1.0),
        pitch: opts.pitch,
        stretch_mode: opts.stretch_mode,
        source_tempo: opts.source_tempo.filter(|_| kind == ClipKind::Audio),
        warp: opts.warp,
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
        link: None,
        overrides: Overrides { transpose: opts.transpose, velocity: opts.velocity },
    }
}

/// The version of a custom clip's data: 1 when not said.
fn custom_version(version: Option<u32>) -> Result<u32> {
    match version {
        Some(0) => bail!("the version of a kind's data counts from 1"),
        other => Ok(other.unwrap_or(1)),
    }
}

fn check_signals(signals: Vec<Signal>) -> Result<Arc<[Signal]>> {
    if signals.iter().any(|s| !s.at.is_finite()) {
        bail!("a signal happens at a number of beats or seconds");
    }
    Ok(signals.into())
}

/// A field that [`Document::clip_set`] changes: the key that Lua gives,
/// parsed once. Which fields a clip has depends on its kind, so an unknown
/// key fails where the clip is known.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::session) enum ClipField {
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
    Transpose,
    Velocity,
}

impl ClipField {
    pub(in crate::session) fn parse(key: &str) -> Option<Self> {
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
            "transpose" => Self::Transpose,
            "velocity" => Self::Velocity,
            _ => return None,
        })
    }
}

/// An override of a MIDI clip (`model/overrides.rs`): a whole number from
/// -127 to 127, nil for 0.
fn override_value(key: &str, value: Value) -> Result<i8> {
    if value.is_null() {
        return Ok(0);
    }
    // Lua gives numbers as floats.
    let amount: f64 = de(key, value)?;
    if amount.fract() != 0.0 || !(-127.0..=127.0).contains(&amount) {
        bail!("`{key}` is a whole number from -127 to 127, not {amount}");
    }
    Ok(amount as i8)
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
