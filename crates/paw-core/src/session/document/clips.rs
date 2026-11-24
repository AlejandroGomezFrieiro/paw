//! Clips: their fields, kinds, notes and controls, as the model holds
//! them. What reads a file (a clip file, a sound file) is the session's,
//! in `session/clips.rs`.

use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use serde::Deserialize;
use serde_json::{Map, Value};

use super::Document;
use super::values::{Patch, check_controls, check_fade, finite, sorted};
use crate::model::{
    Clip, ClipContent, ClipKindId, Control, CustomContent, Id, KindData, MASTER_ID, MediaRef, NestPlay, Note, Notes,
    Project, Signal, Stack, Sound, StretchMode, Timebase, Timeline, WarpMarker, check_clip_beat, check_notes,
};
use schemars::JsonSchema;
use crate::stretch::{PITCH_RANGE, RATIO_RANGE};

/// What a new clip holds: `midi`, `audio` or the name of a kind that an
/// extension defines, in Lua. A word that is no name fails with the text of
/// [`FromStr`](std::str::FromStr); whether an extension defined it is known
/// where the clip is added (`Document::clip_kinds`).
#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
#[serde(try_from = "String")]
pub(crate) enum ClipKind {
    Midi,
    Audio,
    /// A subproject placed here (`nest`, `play`, `offset` of [`ClipOpts`]).
    Nest,
    Custom(ClipKindId),
}

impl ClipKind {
    /// The built-in kind that decides how the clip may play: its own, or
    /// that of the sound of a custom clip (MIDI when it has none).
    pub(crate) fn playing(&self, sound: Option<&Sound>) -> ClipKind {
        match (self, sound.map(Sound::content)) {
            (ClipKind::Custom(_), Some(ClipContent::Audio { .. })) => ClipKind::Audio,
            (ClipKind::Custom(_), _) => ClipKind::Midi,
            (built_in, _) => built_in.clone(),
        }
    }
}

impl std::str::FromStr for ClipKind {
    type Err = anyhow::Error;

    fn from_str(word: &str) -> Result<Self> {
        Ok(match word {
            "midi" => Self::Midi,
            "audio" => Self::Audio,
            "nest" => Self::Nest,
            other => Self::Custom(other.parse::<ClipKindId>()?),
        })
    }
}

impl TryFrom<String> for ClipKind {
    type Error = anyhow::Error;

    fn try_from(word: String) -> Result<Self> {
        word.parse()
    }
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct ClipOpts {
    /// Inferred from `file` when absent.
    pub kind: Option<ClipKind>,
    pub name: Option<String>,
    pub start: f64,
    pub length: Option<f64>,
    pub notes: Vec<Note>,
    pub file: Option<PathBuf>,
    pub offset: f64,
    pub gain: f64,
    /// Beats an audio clip fades in and out over.
    pub fade_in: f64,
    pub fade_out: f64,
    /// Controller moves of a MIDI clip.
    pub controls: Vec<Control>,
    pub meta: Map<String, Value>,
    /// How it plays, as the clip's fields of these names have it: an
    /// audio clip's timebase, stretch and pitch, and looping.
    pub timebase: Option<Timebase>,
    pub stretch: Option<f64>,
    pub pitch: f64,
    pub stretch_mode: StretchMode,
    pub source_tempo: Option<f64>,
    pub warp: Vec<WarpMarker>,
    pub formants: bool,
    #[serde(rename = "loop")]
    pub looped: bool,
    pub loop_length: Option<f64>,
    pub loop_start: f64,
    /// A MIDI clip's modifiers (`model/modifiers.rs`), as `clip_get`
    /// gives them.
    pub modifiers: Stack,
    /// Keep it off the timeline, among the part's cues (`session/cues.rs`).
    pub cue: bool,
    /// A clip of a kind that an extension defines: its content (`data` is
    /// required, `length` too; `offset` is in the kind's timeline).
    pub version: Option<u32>,
    pub timeline: Timeline,
    pub data: Option<KindData>,
    pub media: Vec<MediaRef>,
    pub sound: Option<Sound>,
    pub signals: Vec<Signal>,
    /// A nest clip: the subproject it places, and what it plays of it
    /// (its mix when absent). `offset` is then beats into the subproject.
    pub nest: Option<crate::model::NestId>,
    pub play: Option<crate::model::NestPlay>,
}

/// What [`Document::clip_set_custom`] gives a custom clip: what its kind
/// compiled, replacing data, media, sound and signals together, so that it
/// is one edit. `version`, `timeline` and `offset` stay as they are when
/// absent.
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub(crate) struct CustomSet {
    pub data: Option<KindData>,
    pub version: Option<u32>,
    pub timeline: Option<Timeline>,
    pub offset: Option<f64>,
    pub media: Vec<MediaRef>,
    pub sound: Option<Sound>,
    pub signals: Vec<Signal>,
}

impl Document {
    /// Add a clip to `part` and give its id. `source` is the clip file
    /// that a MIDI clip refers to, already read into `opts`. The sound file
    /// of an audio clip (`opts.file`) is kept as given: the session makes
    /// its path whole. `sound_seconds` reads how long that file is.
    pub(crate) fn clip_add(
        &mut self,
        part: Id,
        mut opts: ClipOpts,
        source: Option<PathBuf>,
        sound_seconds: impl FnOnce(&Path) -> Result<f64>,
    ) -> Result<Id> {
        check_clip_part(part)?;
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
        let (content, natural, default_name) = self.clip_content(part, &kind, &mut opts, sound_seconds)?;
        let length = opts.length.unwrap_or(natural);
        check_clip_opts(playing.clone(), &opts, length)?;
        opts.modifiers = self.check_stack(std::mem::take(&mut opts.modifiers))?;
        let id = self.new_id();
        let cue = opts.cue;
        self.edit(|p| {
            let t = p
                .part_mut(part)
                .with_context(|| format!("no part {part}"))?;
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
                p.found_clip(id, part, at);
            }
            Ok(id)
        })
    }

    /// The content of a new clip, its natural length in beats and its
    /// default name. Takes the notes, controls and file out of `opts`.
    /// `sound_seconds` reads how long the sound file of an audio clip is.
    fn clip_content(
        &self,
        part: Id,
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
            ClipKind::Nest => self.nest_clip_content(part, opts),
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
    fn nest_clip_content(&self, part: Id, opts: &mut ClipOpts) -> Result<(ClipContent, f64, String)> {
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
            .part(part)
            .with_context(|| format!("no part {part}"))?
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
    pub(crate) fn clip_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            if let Some((part, index)) = p.find_cue_clip(id) {
                p.part_mut(part).unwrap().cues.remove(index);
                return Ok(());
            }
            let (part, index) = p.find_clip(id).with_context(|| format!("no clip {id}"))?;
            p.part_mut(part).unwrap().clips.remove(index);
            Ok(())
        })
    }
    /// The kinds of clip that extensions defined, by name.
    pub(crate) fn clip_kinds(&self) -> Vec<String> {
        self.clip_kinds.iter().map(ToString::to_string).collect()
    }
    /// Let clips of the kind `name` be added (`paw.clip_kinds.define`). The
    /// project keeps no list of kinds: its clips name theirs.
    pub(crate) fn clip_kind_define(&mut self, name: &str) -> Result<()> {
        self.clip_kinds.insert(name.parse()?);
        Ok(())
    }
    /// Stop adding clips of the kind `name`. Clips of it that the project
    /// has stay as they are, data and all.
    pub(crate) fn clip_kind_remove(&mut self, name: &str) -> Result<()> {
        self.clip_kinds.remove(&name.parse()?);
        Ok(())
    }
    /// The content of a custom clip, as it is saved.
    pub(crate) fn clip_custom(&self, id: Id) -> Result<Value> {
        let clip = self.project.clip(id).with_context(|| format!("no clip {id}"))?;
        match &clip.content {
            ClipContent::Custom(custom) => Ok(serde_json::to_value(custom)?),
            other => bail!("clip {id} is a {} clip, not a custom one", other.kind()),
        }
    }
    /// Replace what a custom clip's kind compiled: data, media, sound and
    /// signals together, as one edit.
    pub(crate) fn clip_set_custom(&mut self, id: Id, set: CustomSet) -> Result<()> {
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
    pub(crate) fn clip_notes(&self, id: Id) -> Result<&Notes> {
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
    pub(crate) fn clip_controls(&self, id: Id) -> Result<&[Control]> {
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
    pub(crate) fn clip_set_controls(&mut self, id: Id, new: Vec<Control>) -> Result<()> {
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
    pub(crate) fn clip_set_notes(&mut self, id: Id, new: Vec<Note>, append: bool) -> Result<()> {
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

    /// Make one change of clip `id`: the model's part of the session's
    /// `clip_set`. The session reads the sound file of a `File` change
    /// first, and sets the fields of how a clip plays itself.
    pub(crate) fn clip_set(&mut self, id: Id, change: ClipChange) -> Result<()> {
        // A stack is checked before the edit: its kinds are the document's.
        let change = match change {
            ClipChange::Modifiers(stack) => ClipChange::Modifiers(self.check_stack(stack)?),
            change => change,
        };
        self.edit(|p| {
            // A clip off the timeline has no `start` there.
            let cue = p.find_cue_clip(id).is_some();
            match change {
                ClipChange::Start(_) if cue => bail!("a clip off the timeline starts at 0"),
                ClipChange::Part(to) if cue => {
                    move_cue(p, id, to)?;
                    return Ok(());
                }
                ClipChange::Part(to) => return move_clip(p, id, to),
                _ => {}
            }
            let key = change.key();
            let c = p.clip_mut(id).with_context(|| format!("no clip {id}"))?;
            match (change, &mut c.content) {
                (ClipChange::Name(name), _) => c.name = name,
                (ClipChange::Start(start), _) => c.start = start.max(0.0),
                (ClipChange::Length(length), _) => {
                    if !length.is_finite() || length <= 0.0 {
                        bail!("clip length must be above 0");
                    }
                    check_clip_beat("the end of the clip", length)?;
                    c.length = length;
                }
                (ClipChange::Muted(muted), _) => c.muted = muted,
                (ClipChange::Meta(meta), _) => c.meta = meta,
                (ClipChange::File(path), ClipContent::Audio { file, .. }) => *file = path,
                (ClipChange::Offset(new), ClipContent::Audio { offset, .. }) => *offset = new.max(0.0),
                // Slipping a custom clip: where it starts in its data.
                (ClipChange::Offset(new), ClipContent::Custom(custom)) => custom.offset = finite("offset", new)?,
                (ClipChange::Gain(new), ClipContent::Audio { gain, .. }) => *gain = new.clamp(-120.0, 24.0),
                (ClipChange::FadeIn(beats), ClipContent::Audio { .. }) => c.fade_in = check_fade(beats)?,
                (ClipChange::FadeOut(beats), ClipContent::Audio { .. }) => c.fade_out = check_fade(beats)?,
                (ClipChange::Modifiers(stack), ClipContent::Midi { .. }) => c.stack = stack,
                _ => bail!("{} clips have no settable field `{key}`", c.content.kind()),
            }
            Ok(())
        })
    }

    /// Make every clip that refers to a file outside the project the
    /// project's own (`:collect`): the next save writes their files into
    /// its folder. Returns how many. `is_file` says whether a clip's file
    /// is there: a clip whose file is not is left as it is.
    pub(crate) fn clip_collect(&mut self, is_file: impl Fn(&Path) -> bool) -> usize {
        let ids: Vec<Id> = self
            .project
            .all_parts()
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

    /// Copy a clip, from the timeline or from the cues, into a part's cues,
    /// with its `meta`. Returns the copy's id.
    pub(crate) fn clip_to_cues(&mut self, id: Id, part: Id) -> Result<Id> {
        let clip = self
            .project
            .clip(id)
            .with_context(|| format!("no clip {id}"))?;
        let mut copy = (**clip).clone();
        copy.start = 0.0;
        copy.id = self.new_id();
        let copy_id = copy.id;
        self.edit(|p| {
            check_clip_part(part)?;
            let t = p
                .part_mut(part)
                .with_context(|| format!("no part {part}"))?;
            t.cues.push(Arc::new(copy));
            Ok(copy_id)
        })
    }
}

/// The master part has no clips.
pub(crate) fn check_clip_part(part: Id) -> Result<()> {
    if part == MASTER_ID {
        bail!("the master part has no clips: put them on a part");
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
    if kind != ClipKind::Midi && !opts.modifiers.is_empty() {
        bail!("only MIDI clips have modifiers");
    }
    let stretch = opts.stretch.unwrap_or(1.0);
    check_playing(kind.clone(), stretch, opts.pitch, opts.source_tempo)?;
    check_warp(kind, &opts.warp)?;
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
        stack: opts.modifiers,
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

/// What `paw.api.clip_set` changes in a clip: each field as `clip_get` gives
/// it, and what is left out stays. Nil clears a field that has a default
/// (`clip_set(id, "loop_length", nil)`), and is refused for the others.
#[derive(Debug, Default, Deserialize, JsonSchema)]
#[schemars(rename = "ClipChanges")]
#[serde(default, deny_unknown_fields)]
pub(crate) struct ClipPatch {
    /// Beats an audio clip fades in over.
    fade_in: Patch<f64>,
    /// Beats an audio clip fades out over.
    fade_out: Patch<f64>,
    /// The sound file of an audio clip: another take of it.
    #[schemars(with = "Option<String>")]
    file: Patch<PathBuf>,
    formants: Patch<bool>,
    /// The gain of an audio clip in dB, from -120 to 24.
    gain: Patch<f64>,
    length: Patch<f64>,
    #[serde(rename = "loop")]
    looped: Patch<bool>,
    loop_length: Patch<f64>,
    loop_start: Patch<f64>,
    #[schemars(extend("x-teal" = "Meta"))]
    meta: Patch<Map<String, Value>>,
    /// The modifiers of a MIDI clip, top to bottom. Nil or an empty list
    /// takes all of them away.
    modifiers: Patch<Stack>,
    muted: Patch<bool>,
    name: Patch<String>,
    offset: Patch<f64>,
    /// Move the clip to the end of this part.
    part: Patch<Id>,
    pitch: Patch<f64>,
    source_tempo: Patch<f64>,
    start: Patch<f64>,
    stretch: Patch<f64>,
    stretch_mode: Patch<StretchMode>,
    timebase: Patch<Timebase>,
    /// The markers of an audio clip; the `beat` of each is not read.
    #[schemars(with = "Option<Vec<crate::session::WarpView>>")]
    warp: Patch<Vec<WarpMarker>>,
}

impl ClipPatch {
    /// The changes of the patch, in the order of their keys.
    pub(crate) fn changes(self) -> Result<Vec<ClipChange>> {
        use ClipChange as C;
        let mut out = Vec::new();
        let mut set = |change: Option<ClipChange>| out.extend(change);
        set(self.fade_in.value("fade_in")?.map(C::FadeIn));
        set(self.fade_out.value("fade_out")?.map(C::FadeOut));
        set(self.file.value("file")?.map(C::File));
        set(self.formants.value("formants")?.map(C::Formants));
        set(self.gain.value("gain")?.map(C::Gain));
        set(self.length.value("length")?.map(C::Length));
        set(self.looped.value("loop")?.map(C::Loop));
        set(self.loop_length.change().map(C::LoopLength));
        set(self.loop_start.change().map(C::LoopStart));
        // An empty Lua table is an empty map: nil clears `meta` too.
        set(self.meta.change().map(|meta| C::Meta(meta.unwrap_or_default())));
        set(self.modifiers.change().map(|stack| C::Modifiers(stack.unwrap_or_default())));
        set(self.muted.value("muted")?.map(C::Muted));
        set(self.name.value("name")?.map(C::Name));
        set(self.offset.value("offset")?.map(C::Offset));
        set(self.part.value("part")?.map(C::Part));
        set(self.pitch.change().map(C::Pitch));
        set(self.source_tempo.change().map(C::SourceTempo));
        set(self.start.value("start")?.map(C::Start));
        set(self.stretch.change().map(C::Stretch));
        set(self.stretch_mode.value("stretch_mode")?.map(C::StretchMode));
        set(self.timebase.value("timebase")?.map(C::Timebase));
        set(self.warp.change().map(|warp| C::Warp(warp.unwrap_or_default())));
        Ok(out)
    }
}

/// One change of a clip, typed: what a field of a [`ClipPatch`] gives.
/// `None` is nil: the field goes back to its default.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum ClipChange {
    FadeIn(f64),
    FadeOut(f64),
    File(PathBuf),
    Formants(bool),
    Gain(f64),
    Length(f64),
    Loop(bool),
    LoopLength(Option<f64>),
    LoopStart(Option<f64>),
    Meta(Map<String, Value>),
    Modifiers(Stack),
    Muted(bool),
    Name(String),
    Offset(f64),
    Part(Id),
    Pitch(Option<f64>),
    SourceTempo(Option<f64>),
    Start(f64),
    Stretch(Option<f64>),
    StretchMode(StretchMode),
    Timebase(Timebase),
    Warp(Vec<WarpMarker>),
}

impl ClipChange {
    /// The key of the change, as Lua names the field.
    pub(crate) fn key(&self) -> &'static str {
        match self {
            Self::FadeIn(_) => "fade_in",
            Self::FadeOut(_) => "fade_out",
            Self::File(_) => "file",
            Self::Formants(_) => "formants",
            Self::Gain(_) => "gain",
            Self::Length(_) => "length",
            Self::Loop(_) => "loop",
            Self::LoopLength(_) => "loop_length",
            Self::LoopStart(_) => "loop_start",
            Self::Meta(_) => "meta",
            Self::Modifiers(_) => "modifiers",
            Self::Muted(_) => "muted",
            Self::Name(_) => "name",
            Self::Offset(_) => "offset",
            Self::Part(_) => "part",
            Self::Pitch(_) => "pitch",
            Self::SourceTempo(_) => "source_tempo",
            Self::Start(_) => "start",
            Self::Stretch(_) => "stretch",
            Self::StretchMode(_) => "stretch_mode",
            Self::Timebase(_) => "timebase",
            Self::Warp(_) => "warp",
        }
    }

    /// A change of how a clip plays: the session sets it
    /// (`Session::set_playing`), as it needs the sound file and the tempo.
    pub(crate) fn is_playing(&self) -> bool {
        matches!(
            self,
            Self::Formants(_)
                | Self::Loop(_)
                | Self::LoopLength(_)
                | Self::LoopStart(_)
                | Self::Pitch(_)
                | Self::SourceTempo(_)
                | Self::Stretch(_)
                | Self::StretchMode(_)
                | Self::Timebase(_)
                | Self::Warp(_)
        )
    }

    /// Clip `clip`, on part `part`, already holds what the change gives:
    /// setting it would change nothing, and makes no undo step.
    pub(crate) fn holds(&self, clip: &Clip, part: Option<Id>) -> bool {
        // A field that does not apply to the kind of the clip is never
        // held: setting it gives the error of its kind.
        let audio = match &clip.content {
            ClipContent::Audio { file, offset, gain, .. } => Some((file, *offset, *gain)),
            _ => None,
        };
        let midi = matches!(clip.content, ClipContent::Midi { .. });
        match self {
            Self::Name(name) => clip.name == *name,
            Self::Start(start) => clip.start == *start,
            Self::Length(length) => clip.length == *length,
            Self::Muted(muted) => clip.muted == *muted,
            Self::Meta(meta) => clip.meta == *meta,
            Self::Part(to) => part == Some(*to),
            Self::File(path) => audio.is_some_and(|(file, ..)| file == path),
            Self::Offset(offset) => audio.is_some_and(|(_, held, _)| held == *offset),
            Self::Gain(gain) => audio.is_some_and(|(.., held)| held == *gain),
            Self::FadeIn(beats) => audio.is_some() && clip.fade_in == *beats,
            Self::FadeOut(beats) => audio.is_some() && clip.fade_out == *beats,
            Self::Loop(on) => clip.looped == *on,
            Self::LoopLength(beats) => clip.loop_length == *beats,
            Self::LoopStart(beats) => clip.loop_start == beats.unwrap_or(0.0),
            Self::Formants(on) => audio.is_some() && clip.formants == *on,
            Self::Pitch(semitones) => audio.is_some() && clip.pitch == semitones.unwrap_or(0.0),
            Self::Stretch(ratio) => audio.is_some() && clip.stretch == ratio.unwrap_or(1.0),
            Self::StretchMode(mode) => audio.is_some() && clip.stretch_mode == *mode,
            Self::SourceTempo(bpm) => audio.is_some() && clip.source_tempo == *bpm,
            Self::Timebase(timebase) => audio.is_some() && clip.timebase.unwrap_or_default() == *timebase,
            Self::Modifiers(stack) => midi && clip.stack == *stack,
            // A change keeps no beat of a marker, so it cannot compare a
            // list with the view: a list of markers is always set.
            Self::Warp(_) => false,
        }
    }
}

/// Move clip `id`, on the timeline, to the end of part `to`.
fn move_clip(p: &mut Project, id: Id, to: Id) -> Result<()> {
    let (from, index) = p.find_clip(id).with_context(|| format!("no clip {id}"))?;
    check_clip_part(to)?;
    if p.part(to).is_none() {
        bail!("no part {to}");
    }
    let clip = p
        .part_mut(from)
        .context("the clip's part was found")?
        .clips
        .remove(index);
    let clips = &mut p.part_mut(to).context("the part was found")?.clips;
    clips.push(clip);
    let at = clips.len() - 1;
    p.found_clip(id, to, at);
    Ok(())
}

/// Move a cue clip to another part's cues: false when `id` is not one.
fn move_cue(p: &mut Project, id: Id, to: Id) -> Result<bool> {
    let Some((from, index)) = p.find_cue_clip(id) else {
        return Ok(false);
    };
    check_clip_part(to)?;
    if p.part(to).is_none() {
        bail!("no part {to}");
    }
    let clip = p.part_mut(from).unwrap().cues.remove(index);
    p.part_mut(to).unwrap().cues.push(clip);
    Ok(true)
}

/// Check how a new clip of `kind` is to play.
pub(crate) fn check_playing(
    kind: ClipKind,
    stretch: f64,
    pitch: f64,
    source_tempo: Option<f64>,
) -> Result<()> {
    if kind != ClipKind::Audio && (stretch != 1.0 || pitch != 0.0) {
        bail!("only audio clips are stretched or shifted");
    }
    check_ratio(stretch)?;
    check_pitch(pitch)?;
    if let Some(bpm) = source_tempo {
        check_tempo(bpm)?;
    }
    Ok(())
}

pub(crate) fn check_ratio(ratio: f64) -> Result<f64> {
    let (lo, hi) = RATIO_RANGE;
    if !(lo..=hi).contains(&ratio) {
        bail!("a clip is stretched to between {lo} and {hi} times its length, not {ratio}");
    }
    Ok(ratio)
}

pub(crate) fn check_pitch(semitones: f64) -> Result<f64> {
    if !semitones.is_finite() || semitones.abs() > PITCH_RANGE {
        bail!("a clip is shifted by at most {PITCH_RANGE} semitones either way, not {semitones}");
    }
    Ok(semitones)
}

pub(crate) fn check_tempo(bpm: f64) -> Result<f64> {
    if !(1.0..=999.0).contains(&bpm) {
        bail!("a tempo is between 1 and 999, not {bpm}");
    }
    Ok(bpm)
}

/// Check an audio clip's warp markers: in order of their moments of the
/// file, and of where they play them.
pub(crate) fn check_warp(kind: ClipKind, warp: &[WarpMarker]) -> Result<()> {
    if kind != ClipKind::Audio && !warp.is_empty() {
        bail!("only audio clips have warp markers");
    }
    for m in warp {
        if !m.source.is_finite() || !m.target.is_finite() || m.source < 0.0 {
            bail!("a warp marker is a moment of the file from 0 on, and where it plays");
        }
    }
    if warp
        .windows(2)
        .any(|w| w[1].source <= w[0].source || w[1].target <= w[0].target)
    {
        bail!("warp markers follow each other in the file and where they play it");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::PartOpts;

    /// A document with one part, and the part's id.
    fn one_part() -> (Document, Id) {
        let mut doc = Document::default();
        let part = doc.part_add(PartOpts::default()).unwrap();
        (doc, part)
    }

    #[test]
    fn an_audio_clip_is_as_long_as_its_sound_file_says() {
        let (mut doc, part) = one_part();
        let opts = ClipOpts { file: Some("/sounds/take.wav".into()), ..ClipOpts::default() };
        let id = doc.clip_add(part, opts, None, |_| Ok(4.0)).unwrap();
        // Four seconds at the default 120 BPM.
        assert_eq!(doc.project.clip(id).unwrap().length, 8.0);
    }

    #[test]
    fn collect_leaves_a_clip_whose_file_is_not_there() {
        let (mut doc, part) = one_part();
        let mut add = |name: &str| {
            let id = doc.clip_add(part, ClipOpts::default(), None, |_| unreachable!()).unwrap();
            let clip = doc.project.clip_mut(id).unwrap();
            clip.source = Some(format!("/clips/{name}.midi2").into());
            id
        };
        let (there, gone) = (add("there"), add("gone"));
        let taken = doc.clip_collect(|file| file.ends_with("there.midi2"));
        assert_eq!(taken, 1);
        assert_eq!(doc.project.clip(there).unwrap().source, None, "the clip whose file is there is the project's own");
        assert!(doc.project.clip(gone).unwrap().source.is_some(), "the clip whose file is gone still refers to it");
    }
}
