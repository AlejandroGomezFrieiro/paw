//! The project: plain data, cheap to clone.
//!
//! Tracks, devices and clips sit behind `Arc`, and edits go through
//! `Arc::make_mut`. A clone of a [`Project`] therefore shares everything that
//! did not change, which is what makes snapshot undo and pointer-comparing
//! diffs cheap.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::sync::Arc;

use paw_engine::{Ctl, EventKind, NoteCtl, SigPoint, TempoMap, TempoPoint};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

mod clips;
mod custom;
mod links;
pub(crate) mod nest;
mod notes;
pub use clips::Clips;
pub use custom::{
    ClipKindId, CustomContent, CustomError, DATA_LIMIT, KindData, KindValue, MediaRef, MediaRole,
    OscAddress, OscArg, PortName, RESERVED, Signal, SignalTo, Sound, Timeline, Word,
};
pub use nest::{MAX_DEPTH, Nest, NestId, NestMeter, NestPlay, NestTempo, Route, check_nest};
pub(crate) use links::Links;
pub use notes::Notes;

pub type Id = u64;

/// The master track's id in every project.
pub const MASTER_ID: Id = 0;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Project {
    pub name: String,
    /// Beats (quarter notes) per minute at the start of the song.
    pub tempo: f64,
    /// The time signature at the start of the song.
    pub sig_num: u32,
    pub sig_den: u32,
    /// The tempo ramps from the start to the first of `tempo_changes`.
    #[serde(default, skip_serializing_if = "is_false")]
    pub tempo_ramp: bool,
    /// Where the tempo changes after the start, in order. A song with one
    /// tempo and one signature has none of these, and its file is what it
    /// was before there were tempo maps.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tempo_changes: Vec<TempoChange>,
    /// Where the time signature changes after the start, in order.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub sig_changes: Vec<SigChange>,
    /// The song's key as `paw.harmony` names it (`"D minor"`), when one is
    /// set. The core keeps the text; `paw.harmony.parse_key` reads it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub key: Option<String>,
    /// The fields above as a map to convert with, rebuilt by
    /// [`refresh_tempo`](Project::refresh_tempo) and
    /// [`set_tempo_map`](Project::set_tempo_map) whenever they change.
    #[serde(skip)]
    map: Arc<TempoMap>,
    pub master: Arc<Track>,
    /// The song's tracks and the tracks of every nest (`Track::nest`), in
    /// order.
    pub tracks: Vec<Arc<Track>>,
    /// The nests (subprojects), by id: see `model/nest.rs`.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty", with = "nest::as_list")]
    pub nests: BTreeMap<NestId, Arc<Nest>>,
    /// Free-form data for extensions, saved with the project.
    #[serde(default)]
    pub meta: Map<String, Value>,
    /// Where clips were last found: see [`Project::find_clip`].
    #[serde(skip)]
    places: Places,
}

/// Where each clip was last seen, by id: its track and its place there.
/// Only a hint, checked before it is used, and shared by every copy of a
/// project (which mostly keep their clips where they were), so that finding
/// a clip does not cost a look through every clip of the project.
#[derive(Clone, Default)]
struct Places(Arc<std::sync::Mutex<std::collections::HashMap<Id, (Id, usize)>>>);

impl std::fmt::Debug for Places {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Places")
    }
}

impl Default for Project {
    fn default() -> Self {
        Self {
            name: "untitled".into(),
            tempo: 120.0,
            sig_num: 4,
            sig_den: 4,
            tempo_ramp: false,
            tempo_changes: Vec::new(),
            sig_changes: Vec::new(),
            key: None,
            map: Arc::new(TempoMap::default()),
            master: Arc::new(Track {
                name: "Master".into(),
                ..Track::new(MASTER_ID)
            }),
            tracks: Vec::new(),
            nests: BTreeMap::new(),
            meta: Map::new(),
            places: Places::default(),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Track {
    pub id: Id,
    pub name: String,
    /// Fader level in dB.
    pub volume: f64,
    /// -1 (left) to 1 (right).
    pub pan: f64,
    pub mute: bool,
    pub solo: bool,
    pub armed: bool,
    /// The track this one feeds, or `None` for the master track.
    pub output: Option<Id>,
    pub sends: Vec<Send>,
    pub devices: Vec<Arc<DeviceInst>>,
    pub clips: Clips,
    /// At most one lane per target.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub lanes: Vec<Arc<Lane>>,
    pub color: Option<String>,
    #[serde(default)]
    pub meta: Map<String, Value>,
    /// Audio input channels, counting from 1: `"1"` for a mono input, `"1/2"`
    /// for a stereo pair, `None` for none.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input: Option<InputChannels>,
    /// Hear the input even when the track is not armed.
    #[serde(default)]
    pub monitor: bool,
    /// Which MIDI input the track plays and records when it is armed and
    /// has no audio input; `None` for every port and channel.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub midi_input: Option<MidiInput>,
    /// The MIDI output port the track sends what it plays to (its clips'
    /// notes and controllers, and MIDI input passing through), and on which
    /// channel; `None` for none.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub midi_output: Option<MidiOutput>,
    /// How tall the track is drawn, as a share of the height all tracks
    /// have at the frontend's zoom; `None` for that height.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub height: Option<f64>,
    /// What moving a fader, the pan or a parameter of the track does to
    /// its automation while the song plays, and whether its lanes play.
    #[serde(default, skip_serializing_if = "AutoMode::is_read")]
    pub automation: AutoMode,
    /// Clips kept off the timeline, which play only when cued (see
    /// `session/cues.rs`). Each starts at 0 and repeats every `length`
    /// beats while it plays.
    #[serde(default, skip_serializing_if = "Clips::is_empty")]
    pub cues: Clips,
    /// How its notes' MIDI 2.0 attributes reach an instrument that does
    /// not take them: see `attr_map.rs`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attr_map: Option<crate::attr_map::AttrMap>,
    /// The track folder outside the project's folder that the track is
    /// read from: the project refers to it and keeps no copy. The first
    /// edit of the track makes it the project's own (`origin`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<PathBuf>,
    /// The track folder outside the project that the track was copied from.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<PathBuf>,
    /// The chain file (a `devices.json`) outside the project's folder that
    /// the devices are read from, kept as `source` is for the track.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub chain_source: Option<PathBuf>,
    /// The chain file outside the project that the devices were copied from.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub chain_origin: Option<PathBuf>,
    /// The nest (subproject) the track belongs to; `None` for the song's.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub nest: Option<NestId>,
}

/// The boundaries a cue waits for.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum Quantize {
    #[serde(rename = "off")]
    Off,
    #[serde(rename = "1/16")]
    Sixteenth,
    #[serde(rename = "1/8")]
    Eighth,
    #[serde(rename = "1/4")]
    Quarter,
    /// The signature's beat: an eighth in 6/8.
    #[serde(rename = "beat")]
    Beat,
    #[default]
    #[serde(rename = "bar")]
    Bar,
    #[serde(rename = "2bars")]
    TwoBars,
    #[serde(rename = "4bars")]
    FourBars,
}

impl Quantize {
    pub fn engine(self) -> paw_engine::launch::Quantize {
        use paw_engine::launch::Quantize as Q;
        match self {
            Quantize::Off => Q::Off,
            Quantize::Sixteenth => Q::Grid(0.25),
            Quantize::Eighth => Q::Grid(0.5),
            Quantize::Quarter => Q::Grid(1.0),
            Quantize::Beat => Q::Beat,
            Quantize::Bar => Q::Bars(1),
            Quantize::TwoBars => Q::Bars(2),
            Quantize::FourBars => Q::Bars(4),
        }
    }
}

/// How a track treats its automation.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AutoMode {
    /// The lanes play; moving a control writes nothing.
    #[default]
    Read,
    /// A control writes while it is held or being moved, and the lane
    /// takes over again when it is let go.
    Touch,
    /// A control writes from when it is first moved until the song stops.
    Latch,
    /// Everything the track's lanes move is written over from where the
    /// song starts playing until it stops, moved or not.
    Write,
    /// The lanes are kept but do not play.
    Off,
}

impl AutoMode {
    fn is_read(&self) -> bool {
        *self == AutoMode::Read
    }

    pub fn name(self) -> &'static str {
        match self {
            AutoMode::Read => "read",
            AutoMode::Touch => "touch",
            AutoMode::Latch => "latch",
            AutoMode::Write => "write",
            AutoMode::Off => "off",
        }
    }

    /// Moving a control in this mode writes into its lane.
    pub fn writes(self) -> bool {
        matches!(self, AutoMode::Touch | AutoMode::Latch | AutoMode::Write)
    }
}

/// MIDI from one port, by its name, and optionally one channel of it.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct MidiInput {
    /// The port's name as the system gives it (`paw.midi.inputs()`), or
    /// `None` for every port.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub port: Option<String>,
    /// From 1 to 16, or `None` for every channel.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel: Option<u8>,
}

/// MIDI to one output port, by its name, on a channel or on each
/// message's own, in a form for ports that take no MIDI 2.0.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct MidiOutput {
    /// The port's name as `paw.midi.outputs()` gives it.
    pub port: String,
    /// From 1 to 16, or `None` for the channel each message has.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub channel: Option<u8>,
    #[serde(default, skip_serializing_if = "OutForm::is_auto")]
    pub form: OutForm,
    /// The member channels of an MPE zone, 1 to 15; `None` for 15.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub members: Option<u8>,
}

/// What a MIDI output sends where the port takes no MIDI 2.0 (see
/// `paw_engine::midi_form`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OutForm {
    /// MIDI 2.0 where the port takes it, else plain MIDI 1.0.
    #[default]
    Auto,
    /// MIDI 1.0 as each message has it.
    Plain,
    /// MIDI Polyphonic Expression: a channel to each note.
    Mpe,
    /// Control changes 0 to 31 in fourteen bits.
    Cc14,
}

impl OutForm {
    pub fn is_auto(&self) -> bool {
        *self == OutForm::Auto
    }
}

impl MidiOutput {
    /// The form as the engine takes it.
    pub fn engine_form(&self) -> paw_engine::midi_form::Form {
        use paw_engine::midi_form::Form;
        match self.form {
            OutForm::Auto => Form::Auto,
            OutForm::Plain => Form::Plain,
            OutForm::Cc14 => Form::Cc14,
            OutForm::Mpe => Form::Mpe(self.members.unwrap_or(15)),
        }
    }
}

impl Track {
    pub fn new(id: Id) -> Self {
        Self {
            id,
            name: String::new(),
            volume: 0.0,
            pan: 0.0,
            mute: false,
            solo: false,
            armed: false,
            output: None,
            sends: Vec::new(),
            devices: Vec::new(),
            clips: Clips::new(),
            lanes: Vec::new(),
            color: None,
            meta: Map::new(),
            input: None,
            monitor: false,
            midi_input: None,
            midi_output: None,
            height: None,
            automation: AutoMode::Read,
            cues: Clips::new(),
            attr_map: None,
            source: None,
            origin: None,
            chain_source: None,
            chain_origin: None,
            nest: None,
        }
    }

    /// The names of the fields (as `track_get` names them) that differ from
    /// `before`, the same track in an earlier state. The lists of devices,
    /// clips, cues and lanes compare by identity, as the sync does.
    pub fn changed_fields(&self, before: &Track) -> Vec<&'static str> {
        fn same_arcs<T>(a: &[Arc<T>], b: &[Arc<T>]) -> bool {
            a.len() == b.len() && a.iter().zip(b).all(|(x, y)| Arc::ptr_eq(x, y))
        }
        let checks: [(&'static str, bool); 26] = [
            ("name", self.name == before.name),
            ("volume", self.volume == before.volume),
            ("pan", self.pan == before.pan),
            ("mute", self.mute == before.mute),
            ("solo", self.solo == before.solo),
            ("armed", self.armed == before.armed),
            ("output", self.output == before.output),
            ("sends", self.sends == before.sends),
            ("devices", same_arcs(&self.devices, &before.devices)),
            ("clips", self.clips.same(&before.clips)),
            ("lanes", same_arcs(&self.lanes, &before.lanes)),
            ("color", self.color == before.color),
            ("meta", self.meta == before.meta),
            ("input", self.input == before.input),
            ("monitor", self.monitor == before.monitor),
            ("midi_input", self.midi_input == before.midi_input),
            ("midi_output", self.midi_output == before.midi_output),
            ("height", self.height == before.height),
            ("automation", self.automation == before.automation),
            ("cues", self.cues.same(&before.cues)),
            ("attr_map", self.attr_map == before.attr_map),
            ("source", self.source == before.source),
            ("origin", self.origin == before.origin),
            ("chain_source", self.chain_source == before.chain_source),
            ("chain_origin", self.chain_origin == before.chain_origin),
            ("nest", self.nest == before.nest),
        ];
        checks.into_iter().filter(|(_, same)| !same).map(|(name, _)| name).collect()
    }
}

/// An audio input: one channel (`"3"`) or a stereo pair (`"3/4"`), counting
/// from 1 in text. A project stores these plain forms.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct InputChannels {
    /// The first channel, counting from 0.
    pub first: u8,
    /// How many channels: 1 or 2.
    pub count: u8,
}

impl std::str::FromStr for InputChannels {
    type Err = String;

    fn from_str(spec: &str) -> Result<Self, String> {
        let bad = || format!("bad input `{spec}`: give a channel like \"1\" or a pair like \"1/2\"");
        let number = |p: &str| p.trim().parse::<u8>().ok().filter(|n| (1..255).contains(n));
        let mut parts = spec.trim().split('/');
        let first = parts.next().and_then(number).ok_or_else(bad)?;
        match (parts.next(), parts.next()) {
            (None, _) => Ok(Self { first: first - 1, count: 1 }),
            (Some(second), None) if number(second) == Some(first + 1) => {
                Ok(Self { first: first - 1, count: 2 })
            }
            _ => Err(bad()),
        }
    }
}

impl std::fmt::Display for InputChannels {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let first = u16::from(self.first) + 1;
        if self.count == 1 { write!(f, "{first}") } else { write!(f, "{first}/{}", first + 1) }
    }
}

impl TryFrom<String> for InputChannels {
    type Error = String;

    fn try_from(spec: String) -> Result<Self, String> {
        spec.parse()
    }
}

impl From<InputChannels> for String {
    fn from(input: InputChannels) -> String {
        input.to_string()
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Send {
    pub target: Id,
    /// Send level in dB.
    pub level: f64,
    /// Taken after the track's devices but before its fader, pan and mute,
    /// so that the send does not follow the fader.
    #[serde(default, skip_serializing_if = "is_false")]
    pub pre: bool,
}

/// A tempo change along the song.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct TempoChange {
    pub beat: f64,
    pub bpm: f64,
    /// Ramp to the next change's tempo instead of holding this one.
    #[serde(default, skip_serializing_if = "is_false")]
    pub ramp: bool,
}

/// A time signature starting a bar at a beat.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct SigChange {
    pub beat: f64,
    pub num: u32,
    pub den: u32,
}

fn is_false(value: &bool) -> bool {
    !*value
}

fn is_zero(value: &f64) -> bool {
    *value == 0.0
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DeviceInst {
    pub id: Id,
    /// Which device this is, as registered in the device registry.
    pub kind: String,
    pub bypass: bool,
    pub params: BTreeMap<String, f64>,
    /// A plugin's saved state, base64 encoded.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    #[serde(default)]
    pub meta: Map<String, Value>,
    /// Counts the presets loaded into the device. When it differs between
    /// two versions of the project (a preset was loaded, or that was
    /// undone), `state` is loaded into the running plugin.
    #[serde(default, skip_serializing_if = "is_zero_u32")]
    pub loaded: u32,
    /// A plugin's name, kept so that it can be named where it is not
    /// installed.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    /// Not made at all: no process, no sound, passed over; its state and
    /// parameters are kept as they are.
    #[serde(default, skip_serializing_if = "is_false")]
    pub offline: bool,
    /// The track whose sound the device listens to as its side-chain, such
    /// as a kick that a compressor on a bass ducks under.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sidechain: Option<Id>,
    /// The side-chain is taken after that track's devices but before its
    /// fader, pan and mute, rather than after them.
    #[serde(default, skip_serializing_if = "is_false")]
    pub sidechain_pre: bool,
    /// Where the device's further output pairs play, by pair number (2 for
    /// its second) and track. Pairs not named here are not heard.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub outputs: BTreeMap<u32, Id>,
    /// The device's own id (`ParamInfo::id`) of each parameter key that the
    /// project uses, where the two differ: a new version of a plugin that
    /// puts its parameters in another order or names them otherwise still
    /// gets its values and lanes. Written when the project is saved.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub param_ids: BTreeMap<String, String>,
    /// Files the device keeps beside its state, by name, base64 encoded:
    /// what an attachment of a plugin keeps (an ARA archive). A project
    /// folder holds each as `<n>-<kind>.<name>` next to the `.state`.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub files: BTreeMap<String, String>,
}

fn is_zero_u32(value: &u32) -> bool {
    *value == 0
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Clip {
    pub id: Id,
    pub name: String,
    /// Position and length on the timeline, in beats.
    pub start: f64,
    pub length: f64,
    pub muted: bool,
    pub content: ClipContent,
    /// Beats over which an audio clip fades in from its start and out to its
    /// end. Two clips fade across each other where one's fade out overlaps
    /// the other's fade in.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub fade_in: f64,
    #[serde(default, skip_serializing_if = "is_zero")]
    pub fade_out: f64,
    /// For an audio clip, what it keeps when the tempo before it changes;
    /// `None` is [`Timebase::Time`]. MIDI clips follow beats.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timebase: Option<Timebase>,
    /// How many times as long as its file an audio clip plays it, at the
    /// file's pitch: 2 is half speed. 1 plays the file as it is.
    #[serde(default = "one", skip_serializing_if = "is_one")]
    pub stretch: f64,
    /// Semitones an audio clip plays higher than its file (lower below
    /// 0), at the same length.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub pitch: f64,
    /// How an audio clip is stretched or shifted (see `stretch.rs`).
    #[serde(default, skip_serializing_if = "is_auto")]
    pub stretch_mode: StretchMode,
    /// The tempo an audio clip's sound is at as it is stretched now, which
    /// a clip in [`Timebase::Stretch`] follows: at this tempo it plays at
    /// `stretch`. Recordings know theirs.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_tempo: Option<f64>,
    /// Warp markers of an audio clip, in the order of their moments of the
    /// file: each part of the file between two is stretched on its own
    /// (see `warp.rs`).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub warp: Vec<WarpMarker>,
    /// An audio clip shifted in pitch keeps its formants (the shape of its
    /// spectrum, which says what vowel is sung), so that a voice does not
    /// sound smaller or larger.
    #[serde(default, skip_serializing_if = "is_false")]
    pub formants: bool,
    /// The clip repeats what it plays from `loop_start` for `loop_length`
    /// beats, over its whole length.
    #[serde(default, rename = "loop", skip_serializing_if = "is_false")]
    pub looped: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub loop_length: Option<f64>,
    /// Beats from the clip's start to where the repeated stretch begins: 0,
    /// or less once the start has been trimmed (more than a repeat back is
    /// a repeat less back).
    #[serde(default, skip_serializing_if = "is_zero")]
    pub loop_start: f64,
    #[serde(default)]
    pub meta: Map<String, Value>,
    /// The MIDI clip file outside the project's folder that the notes are
    /// read from: the project refers to it and keeps no copy. The first
    /// edit of the notes makes them the project's own (`origin`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<PathBuf>,
    /// The file outside the project that the notes were copied from.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<PathBuf>,
    /// The name of the link of a linked MIDI clip: every clip of one link
    /// has the same notes and controller moves, and an edit of one changes
    /// all of them (`model/links.rs`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub link: Option<String>,
}

/// What an audio clip keeps when the tempo changes. Either way it keeps its
/// length in seconds, so that a recording plays every sample at the time
/// it was recorded at: its end beat follows from the tempo map.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Timebase {
    /// Its start stays at the same time in seconds (REAPER's default for
    /// audio items), moving in beats when the tempo before it changes.
    #[default]
    Time,
    /// Its start stays on its beat.
    Beats,
    /// Its start and its length stay on their beats: the sound is
    /// stretched to fit, from the tempo it is at (`source_tempo`).
    Stretch,
}

pub use crate::stretch::Mode as StretchMode;

/// A warp marker: the moment `source` of a clip's file plays where its
/// moment `target` would without the markers, both in seconds of the file,
/// the clip's stretch then applied to both.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct WarpMarker {
    pub source: f64,
    pub target: f64,
}

fn one() -> f64 {
    1.0
}

fn is_one(value: &f64) -> bool {
    *value == 1.0
}

fn is_auto(mode: &StretchMode) -> bool {
    *mode == StretchMode::Auto
}

impl Clip {
    /// The stamp of a MIDI clip's notes ([`Notes::stamp`]); `None` for audio.
    pub fn stamp(&self) -> Option<u64> {
        match &self.content {
            ClipContent::Midi { notes, .. } => Some(notes.stamp()),
            ClipContent::Audio { .. } | ClipContent::Custom(_) | ClipContent::Nest { .. } => None,
        }
    }

    /// The beats a looped clip repeats, if it loops.
    pub fn repeat(&self) -> Option<(f64, f64)> {
        let length = self.loop_length.filter(|l| *l > 0.0)?;
        self.looped.then_some((self.loop_start, length))
    }

    /// What the clip plays: its own MIDI or audio, or a custom clip's
    /// sound.
    pub fn playable(&self) -> Option<&ClipContent> {
        match &self.content {
            ClipContent::Custom(custom) => custom.sound.as_ref().map(Sound::content),
            built_in => Some(built_in),
        }
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum ClipContent {
    Midi {
        notes: Notes,
        /// Controller, pitch wheel and pressure moves, in the order they happen.
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        controls: Vec<Control>,
    },
    Audio {
        file: PathBuf,
        /// Seconds into the file where the clip starts playing.
        offset: f64,
        /// Clip gain in dB.
        gain: f64,
        /// Changes to the sound that its file keeps out of, made in order
        /// (`edits.rs`).
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        edits: Vec<crate::edits::AudioEdit>,
    },
    /// A clip of a kind that an extension defines. Boxed: the enum stays
    /// as small as it was, and MIDI clips, most clips, pay nothing.
    Custom(Box<CustomContent>),
    /// A nest (subproject) placed here: see `model/nest.rs`.
    Nest {
        nest: NestId,
        /// Beats into the nest where the clip starts (trim and slip change
        /// it).
        #[serde(default, skip_serializing_if = "is_zero")]
        offset: f64,
        play: NestPlay,
    },
}

impl ClipContent {
    /// `midi`, `audio`, or the name of a custom clip's kind.
    pub fn kind(&self) -> &str {
        match self {
            ClipContent::Midi { .. } => "midi",
            ClipContent::Audio { .. } => "audio",
            ClipContent::Custom(custom) => custom.kind.as_str(),
            ClipContent::Nest { .. } => "nest",
        }
    }
}

/// A controller moving to a value at a point in a MIDI clip: a control
/// change, the pitch wheel, pressure, a registered or assignable controller,
/// or a program change. With `key` it belongs to the note on that key
/// alone, as MIDI 2.0 has it: that note's own pitch bend, pressure or
/// controller.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Control {
    /// Beats from the start of the clip; below 0 it is hidden before the
    /// clip's start and not played.
    #[serde(default)]
    pub start: f64,
    #[serde(flatten)]
    pub what: ControlKind,
    /// 0 to 1, or -1 to 1 for pitch bend. Kept as a fraction, so nothing of
    /// a 32-bit value is lost.
    #[serde(default)]
    pub value: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub key: Option<u8>,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum ControlKind {
    /// A control change by number: 1 is the modulation wheel, 64 the
    /// sustain pedal. With a key, the registered per-note controller of
    /// that number.
    Cc {
        number: u8,
    },
    Bend,
    Pressure,
    /// A registered controller (RPN) by bank and index; per note, by index.
    Registered {
        #[serde(default)]
        bank: u8,
        index: u8,
    },
    /// An assignable controller (NRPN) by bank and index; per note, by index.
    Assignable {
        #[serde(default)]
        bank: u8,
        index: u8,
    },
    /// Choose a sound, with its bank (fourteen bits) if that is given.
    Program {
        program: u8,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        bank: Option<u16>,
    },
}

impl Control {
    /// Why this cannot be played, if it cannot.
    pub fn problem(&self) -> Option<&'static str> {
        let range = match self.what {
            ControlKind::Bend => -1.0..=1.0,
            _ => 0.0..=1.0,
        };
        let seven = |n: u8| n < 128;
        // A move before 0 lies before the clip's start, hidden there by a
        // trim of the clip's start, and is not played.
        if !self.start.is_finite() {
            return Some("it needs a start that is a finite number");
        }
        if !range.contains(&self.value) {
            return Some("its value is out of range: 0 to 1, or -1 to 1 for pitch bend");
        }
        if self.key.is_some_and(|key| !seven(key)) {
            return Some("keys go up to 127");
        }
        match self.what {
            ControlKind::Cc { number } if !seven(number) => Some("controller numbers go up to 127"),
            ControlKind::Registered { bank, index } | ControlKind::Assignable { bank, index }
                if self.key.is_none() && !(seven(bank) && seven(index)) =>
            {
                Some("a controller's bank and index go up to 127")
            }
            ControlKind::Program { program, bank }
                if !seven(program) || bank.is_some_and(|b| b > 0x3fff) =>
            {
                Some("programs go up to 127 and banks to 16383")
            }
            ControlKind::Program { .. } if self.key.is_some() => {
                Some("a program change belongs to a channel, not to a note")
            }
            _ => None,
        }
    }

    /// The engine's event for this, on a channel.
    pub fn event(&self, ch: u8) -> EventKind {
        let value = self.value;
        if let Some(key) = self.key {
            let ctl = match self.what {
                ControlKind::Bend => NoteCtl::Bend,
                ControlKind::Pressure => NoteCtl::Pressure,
                ControlKind::Cc { number } => NoteCtl::Registered(number),
                ControlKind::Registered { index, .. } => NoteCtl::Registered(index),
                ControlKind::Assignable { index, .. } => NoteCtl::Assignable(index),
                ControlKind::Program { program, bank } => {
                    return EventKind::Program { program, bank, ch };
                }
            };
            return EventKind::NoteControl {
                key,
                ctl,
                value,
                ch,
            };
        }
        let ctl = match self.what {
            ControlKind::Cc { number } => Ctl::Cc(number),
            ControlKind::Bend => Ctl::Bend,
            ControlKind::Pressure => Ctl::Pressure,
            ControlKind::Registered { bank, index } => Ctl::Registered(bank, index),
            ControlKind::Assignable { bank, index } => Ctl::Assignable(bank, index),
            ControlKind::Program { program, bank } => {
                return EventKind::Program { program, bank, ch };
            }
        };
        EventKind::Control { ctl, value, ch }
    }

    /// What an engine event is as a controller move at `start`: nothing for notes.
    pub fn from_event(start: f64, kind: EventKind) -> Option<Self> {
        let (what, value, key) = match kind {
            EventKind::Control { ctl, value, .. } => (
                match ctl {
                    Ctl::Cc(number) => ControlKind::Cc { number },
                    Ctl::Bend => ControlKind::Bend,
                    Ctl::Pressure => ControlKind::Pressure,
                    Ctl::Registered(bank, index) => ControlKind::Registered { bank, index },
                    Ctl::Assignable(bank, index) => ControlKind::Assignable { bank, index },
                },
                value,
                None,
            ),
            EventKind::NoteControl {
                key, ctl, value, ..
            } => (
                match ctl {
                    NoteCtl::Bend => ControlKind::Bend,
                    NoteCtl::Pressure => ControlKind::Pressure,
                    NoteCtl::Registered(index) => ControlKind::Registered { bank: 0, index },
                    NoteCtl::Assignable(index) => ControlKind::Assignable { bank: 0, index },
                },
                value,
                Some(key),
            ),
            EventKind::Program { program, bank, .. } => {
                (ControlKind::Program { program, bank }, 0.0, None)
            }
            EventKind::NoteOn { .. } | EventKind::NoteOff { .. } | EventKind::AllNotesOff => {
                return None;
            }
        };
        Some(Self {
            start,
            what,
            value,
            key,
        })
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Note {
    /// Beats from the start of the clip. A note before 0 (or from the clip's
    /// length on) is hidden by a trim of the clip's edge: kept, but not
    /// played until the edge is dragged out over it again.
    pub start: f64,
    pub length: f64,
    /// MIDI note number, 60 is middle C.
    pub pitch: u8,
    /// 1 to 127.
    #[serde(default = "default_velocity")]
    pub velocity: u8,
    /// Free-form data for extensions, such as a lyric. It travels with the
    /// note through edits, unlike data kept beside the clip's note list.
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub meta: Map<String, Value>,
    /// What names the note within its clip for as long as it lives, however
    /// it is moved or changed (`paw://clip/7/note/41`). 0 until the session
    /// gives it one, which it does to every note that has none, or shares
    /// one with a note before it, before the edit is played or kept.
    #[serde(default, skip_serializing_if = "unnamed")]
    pub id: u64,
    /// The MIDI 2.0 attribute its note-on carries, such as an articulation
    /// of the orchestral articulation profile (M2-123); `None` for none.
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "de_attr"
    )]
    pub attr: Option<NoteAttr>,
}

/// A note's MIDI 2.0 attribute: `{ "type": 17, "data": 40960 }`. Type 0
/// means none, and a note never keeps it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NoteAttr {
    #[serde(rename = "type")]
    pub kind: u8,
    #[serde(default)]
    pub data: u16,
}

impl From<NoteAttr> for paw_engine::Attr {
    fn from(a: NoteAttr) -> Self {
        paw_engine::Attr {
            kind: a.kind,
            data: a.data,
        }
    }
}

impl NoteAttr {
    /// The attribute of an engine event's note-on, `None` for none.
    pub fn of(attr: paw_engine::Attr) -> Option<Self> {
        (!attr.is_none()).then_some(NoteAttr {
            kind: attr.kind,
            data: attr.data,
        })
    }
}

/// An attribute as given: a table of `type` and `data`, or nothing (`false`,
/// `null`, an empty table, or type 0).
pub fn de_attr<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Option<NoteAttr>, D::Error> {
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum Given {
        Attr(NoteAttr),
        Flag(bool),
        Empty(Vec<Value>),
        Unit(()),
    }
    match Given::deserialize(d) {
        Ok(Given::Attr(a)) => Ok((a.kind != 0).then_some(a)),
        Ok(Given::Flag(false)) | Ok(Given::Unit(())) => Ok(None),
        Ok(Given::Empty(list)) if list.is_empty() => Ok(None),
        _ => Err(serde::de::Error::custom(
            "a note's attribute is `{ type = 0 to 255, data = 0 to 65535 }`, or false for none",
        )),
    }
}

fn default_velocity() -> u8 {
    100
}

fn unnamed(id: &u64) -> bool {
    *id == 0
}

impl Clip {
    /// About how many bytes the clip holds that `before` (the same clip in
    /// an earlier state) does not share with it: of its notes, the runs it
    /// does not share (see [`Notes`]).
    fn weight_over(&self, before: Option<&Clip>) -> usize {
        use std::mem::size_of;
        size_of::<Clip>()
            + match &self.content {
                ClipContent::Midi { notes, controls } => {
                    let was = match before.map(|c| &c.content) {
                        Some(ClipContent::Midi { notes, .. }) => Some(notes),
                        _ => None,
                    };
                    notes.weight_over(was) + controls.capacity() * size_of::<Control>()
                }
                // Its data, media and signals are shared behind `Arc`s.
                ClipContent::Audio { .. } | ClipContent::Custom(_) | ClipContent::Nest { .. } => 0,
            }
    }
}

/// Finds the items of an earlier list by a key (an id), for a later list
/// walked in order. An edit changes a few places, so the two lists mostly
/// line up: it looks at the places after the last one found first, then
/// through the whole list, and makes a map only when many are not where
/// they were. Every edit compares states (for the undo history, the engine
/// and the change events), so this stays quick for a track of thousands of
/// clips.
pub struct ByKey<'a, T, K, F = fn(&T) -> K> {
    old: &'a [T],
    key: F,
    at: usize,
    misses: usize,
    map: Option<std::collections::HashMap<K, usize>>,
}

impl<'a, T, K: Eq + std::hash::Hash + Copy, F: Fn(&T) -> K> ByKey<'a, T, K, F> {
    pub fn new(old: &'a [T], key: F) -> Self {
        Self { old, key, at: 0, misses: 0, map: None }
    }

    /// Where the item with this key is in the earlier list.
    pub fn position(&mut self, key: K) -> Option<usize> {
        let of = &self.key;
        let near = self.at..(self.at + 4).min(self.old.len());
        let found = match near.clone().find(|&k| of(&self.old[k]) == key) {
            Some(k) => Some(k),
            None if self.map.is_none() && self.misses < 8 => {
                self.misses += 1;
                self.old.iter().position(|x| of(x) == key)
            }
            None => {
                let old = self.old;
                let map = self
                    .map
                    .get_or_insert_with(|| old.iter().enumerate().map(|(i, x)| (of(x), i)).collect());
                map.get(&key).copied()
            }
        };
        let k = found?;
        self.at = k + 1;
        Some(k)
    }

    /// The item with this key in the earlier list.
    pub fn find(&mut self, key: K) -> Option<&'a T> {
        let old = self.old;
        self.position(key).map(|k| &old[k])
    }
}

/// [`ByKey`] for lists of items with ids.
pub type ById<'a, T> = ByKey<'a, Arc<T>, Id>;

/// Where a track's clips may differ from `before` (the same track in another
/// state, or `None` for a new track): `before`'s clips in that stretch, and
/// the places of `clips` in it. Every clip outside it is the very same in
/// both, found by the runs they share (see [`Clips::changed`]).
pub fn changed_clips<'a>(
    before: Option<&'a Clips>,
    clips: &Clips,
) -> (Vec<&'a Arc<Clip>>, std::ops::Range<usize>) {
    match before {
        Some(before) => {
            let (old, new) = clips.changed(before);
            (before.range(old).collect(), new)
        }
        None => (Vec::new(), 0..clips.len()),
    }
}

/// Give every note of a list that has no id, or the id of a note before it,
/// the next free one. Returns whether any changed. The same notes are always
/// given the same ids, so a state written without them (an older file, a
/// step of the undo history) comes back with the ids it had.
pub fn name_notes(notes: &mut Notes) -> bool {
    let unnamed = notes.unnamed();
    if unnamed.is_empty() {
        return false;
    }
    // Past every id there is, so no id given clashes with one further on.
    let mut next = notes.iter().map(|n| n.id).max().unwrap_or(0) + 1;
    for i in unnamed {
        notes[i].id = next;
        next += 1;
    }
    true
}

/// Automation of one of a track's settings, or of a parameter of one of its devices.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Lane {
    pub id: Id,
    pub target: Target,
    /// A lane that is off keeps its points but does not move its target.
    pub enabled: bool,
    /// `(beat, value)` in the target's own units, sorted by beat. Values are
    /// joined by straight lines; before the first point and after the last
    /// the nearest value holds.
    pub points: Vec<(f64, f64)>,
    /// How the curve goes from a point to the next where it does not go in
    /// a straight line, by the beat of the point it leaves.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub shapes: Vec<Segment>,
    /// For a state lane: the states its device takes. The value of a
    /// point is the index of one of them, and it holds up to the next
    /// point (see [`Target::State`]).
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub states: Vec<Arc<LaneState>>,
}

/// One of the states a state lane gives its device: a whole saved state,
/// a request that changes it (an LV2 property set to a file), parameter
/// values, a program change, or some of these together. A state the device
/// takes on its audio thread (parameters, a program, a request its
/// controller can prepare) lands on the point's frame; a whole saved state
/// is loaded on the main thread. See the explanation of state lanes.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LaneState {
    /// The name the lane shows for it.
    pub name: String,
    /// The plugin's whole saved state, base64 encoded.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    /// Parameter values by key.
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub params: BTreeMap<String, f64>,
    /// A request to the device, as `paw.api.device_call` makes it.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub call: Option<StateCall>,
    /// A program change, 0 to 127, with its bank when one is given.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub program: Option<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bank: Option<u16>,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct StateCall {
    pub method: String,
    pub data: String,
}

/// The shape of the stretch of a lane from one point to the next.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub struct Segment {
    /// The beat of the point the stretch leaves from.
    pub beat: f64,
    pub shape: Shape,
    /// For a smooth stretch, -1 to 1: above 0 it moves early and settles,
    /// below 0 it waits and then moves.
    #[serde(default)]
    pub tension: f64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Shape {
    Linear,
    /// The value holds and jumps at the next point.
    Hold,
    /// An S curve, bent by the tension.
    Smooth,
}

/// How many straight pieces a smooth stretch is played as.
const SMOOTH_PIECES: usize = 32;

/// Where a smooth stretch is `t` of the way along, 0 to 1.
pub fn smooth(t: f64, tension: f64) -> f64 {
    let t = t.clamp(0.0, 1.0);
    let t = t.powf(4f64.powf(-tension.clamp(-1.0, 1.0)));
    t * t * (3.0 - 2.0 * t)
}

impl Lane {
    /// The points as they are played: joined by straight lines, a held
    /// stretch as a jump at the next point and a smooth one as many short
    /// lines. The points themselves when every stretch is straight.
    pub fn played(&self) -> std::borrow::Cow<'_, [(f64, f64)]> {
        // A state lane has no curve: each state holds to the next point.
        let states = matches!(self.target, Target::State { .. });
        if self.shapes.is_empty() && !states {
            return std::borrow::Cow::Borrowed(&self.points);
        }
        let hold = Segment {
            beat: 0.0,
            shape: Shape::Hold,
            tension: 0.0,
        };
        let mut out = Vec::with_capacity(self.points.len() * 2);
        for (i, &(beat, value)) in self.points.iter().enumerate() {
            out.push((beat, value));
            let Some(&(next, to)) = self.points.get(i + 1) else { break };
            let seg = if states {
                &hold
            } else {
                let Some(seg) = self.shapes.iter().find(|s| s.beat == beat) else { continue };
                seg
            };
            match seg.shape {
                Shape::Linear => {}
                Shape::Hold => out.push((next, value)),
                Shape::Smooth => {
                    for k in 1..SMOOTH_PIECES {
                        let t = k as f64 / SMOOTH_PIECES as f64;
                        out.push((beat + (next - beat) * t, value + (to - value) * smooth(t, seg.tension)));
                    }
                }
            }
        }
        std::borrow::Cow::Owned(out)
    }

    /// The value the lane plays at a beat: on the curve between two
    /// points, the nearest point's value before the first and after the
    /// last. 0 for a lane with no points.
    pub fn value_at(&self, beat: f64) -> f64 {
        let played = self.played();
        let Some(&(first_beat, first)) = played.first() else {
            return 0.0;
        };
        if beat <= first_beat {
            return first;
        }
        for pair in played.windows(2) {
            let ((b0, v0), (b1, v1)) = (pair[0], pair[1]);
            if beat <= b1 {
                return if b1 > b0 { v0 + (v1 - v0) * (beat - b0) / (b1 - b0) } else { v1 };
            }
        }
        played.last().map_or(0.0, |p| p.1)
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Target {
    /// The track's fader, in dB.
    Volume,
    /// The track's pan, -1 to 1.
    Pan,
    /// A parameter, by key, of a device on the same track.
    Param { device: Id, param: String },
    /// The state of a device on the same track: a lane of states, whose
    /// points each name one of the lane's [`Lane::states`] and hold it up
    /// to the next point, with no curve between.
    State { device: Id },
}

impl Target {
    pub fn device(&self) -> Option<Id> {
        match self {
            Target::Param { device, .. } | Target::State { device } => Some(*device),
            _ => None,
        }
    }
}

impl Project {
    /// Give the notes that have none an id (see `Note::id`), looking only at
    /// the clips that are not the very same as in `before` (the state the
    /// last naming saw), and touching only those that need it.
    pub fn name_notes(&mut self, before: &Project) -> bool {
        self.name_notes_since(&before.tracks, &before.master)
    }

    /// [`name_notes`](Self::name_notes), with only the tracks of `before`.
    pub fn name_notes_since(&mut self, before: &[Arc<Track>], master: &Arc<Track>) -> bool {
        let mut named = false;
        let mut old_tracks = ById::new(before, |t: &Arc<Track>| t.id);
        let tracks = self.tracks.iter_mut().chain(std::iter::once(&mut self.master));
        for track in tracks {
            let old = if track.id == MASTER_ID {
                Some(master)
            } else {
                old_tracks.find(track.id)
            };
            if old.is_some_and(|o| Arc::ptr_eq(o, track)) {
                continue;
            }
            let (old_clips, places) = changed_clips(old.map(|o| &o.clips), &track.clips);
            let mut old_clips = ByKey::new(&old_clips[..], |c: &&Arc<Clip>| c.id);
            // The places of the clips that this state changed and that have
            // notes to name.
            let needs: Vec<usize> = track
                .clips
                .range(places.clone())
                .zip(places)
                .map(|(c, i)| (i, c))
                .filter(|(_, c)| match &c.content {
                    _ if old_clips.find(c.id).is_some_and(|o| Arc::ptr_eq(o, *c)) => false,
                    ClipContent::Midi { notes, .. } => !notes.unnamed().is_empty(),
                    _ => false,
                })
                .map(|(i, _)| i)
                .collect();
            if needs.is_empty() {
                continue;
            }
            let clips = &mut Arc::make_mut(track).clips;
            for i in needs {
                if let ClipContent::Midi { notes, .. } = &mut Arc::make_mut(&mut clips[i]).content {
                    named |= name_notes(notes);
                }
            }
        }
        named
    }

    /// About how many bytes this project holds that `before` does not
    /// share with it: what keeping it as a step of the undo history costs.
    pub fn weight_over(before: &Project, project: &Project) -> usize {
        use std::mem::size_of;
        let mut old = ById::new(&before.tracks, |t: &Arc<Track>| t.id);
        let mut bytes = 0;
        for track in project.all_tracks() {
            let was = if track.id == MASTER_ID {
                Some(&before.master)
            } else {
                old.find(track.id)
            };
            if was.is_some_and(|w| Arc::ptr_eq(w, track)) {
                continue;
            }
            bytes += size_of::<Track>();
            bytes += track.clips.weight_over(was.map(|w| &w.clips));
            let (old_clips, places) = changed_clips(was.map(|w| &w.clips), &track.clips);
            let mut clips = ByKey::new(&old_clips[..], |c: &&Arc<Clip>| c.id);
            for clip in track.clips.range(places) {
                let was = clips.find(clip.id);
                if !was.is_some_and(|c| Arc::ptr_eq(c, clip)) {
                    bytes += clip.weight_over(was.map(|c| &***c));
                }
            }
            let mut devices = ById::new(was.map_or(&[][..], |w| &w.devices[..]), |d: &Arc<DeviceInst>| d.id);
            for device in &track.devices {
                if !devices.find(device.id).is_some_and(|d| Arc::ptr_eq(d, device)) {
                    bytes += size_of::<DeviceInst>()
                        + device.state.as_ref().map_or(0, String::len)
                        + device.params.len() * 48;
                }
            }
            bytes += track.lanes.iter().map(|l| l.points.len() * 16).sum::<usize>();
        }
        bytes
    }

    /// Every track including the master track, which comes last.
    pub fn all_tracks(&self) -> impl Iterator<Item = &Arc<Track>> {
        self.tracks.iter().chain(std::iter::once(&self.master))
    }

    pub fn track(&self, id: Id) -> Option<&Arc<Track>> {
        self.all_tracks().find(|t| t.id == id)
    }

    pub fn track_mut(&mut self, id: Id) -> Option<&mut Track> {
        let track = if id == MASTER_ID {
            &mut self.master
        } else {
            self.tracks.iter_mut().find(|t| t.id == id)?
        };
        Some(Arc::make_mut(track))
    }

    /// The track that holds a device, and the device's position in its chain.
    pub fn find_device(&self, id: Id) -> Option<(Id, usize)> {
        self.all_tracks()
            .find_map(|t| t.devices.iter().position(|d| d.id == id).map(|i| (t.id, i)))
    }

    /// The track that holds an automation lane, and the lane's index on it.
    pub fn find_lane(&self, id: Id) -> Option<(Id, usize)> {
        self.all_tracks()
            .find_map(|t| t.lanes.iter().position(|l| l.id == id).map(|i| (t.id, i)))
    }

    pub fn lane(&self, id: Id) -> Option<&Arc<Lane>> {
        let (track, index) = self.find_lane(id)?;
        Some(&self.track(track)?.lanes[index])
    }

    pub fn lane_mut(&mut self, id: Id) -> Option<&mut Lane> {
        let (track, index) = self.find_lane(id)?;
        Some(Arc::make_mut(&mut self.track_mut(track)?.lanes[index]))
    }

    /// The track that holds a clip, and the clip's index on it.
    ///
    /// Where the clip was last found is looked at first, and the places
    /// beside it (a clip taken out or put in before it moves it by one).
    /// Only when it is not there are all the clips looked through, and the
    /// place of each is remembered.
    pub fn find_clip(&self, id: Id) -> Option<(Id, usize)> {
        let mut places = self.places.0.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(&(track, index)) = places.get(&id)
            && let Some(t) = self.track(track)
        {
            let near = [index, index.wrapping_sub(1), index + 1];
            if let Some(&at) = near.iter().find(|&&i| t.clips.get(i).is_some_and(|c| c.id == id)) {
                places.insert(id, (track, at));
                return Some((track, at));
            }
        }
        places.clear();
        let mut found = None;
        for t in self.all_tracks() {
            for (i, c) in t.clips.iter().enumerate() {
                places.insert(c.id, (t.id, i));
                if c.id == id && found.is_none() {
                    found = Some((t.id, i));
                }
            }
        }
        found
    }

    /// Remember where a clip is, having just put it there.
    pub fn found_clip(&self, id: Id, track: Id, index: usize) {
        let mut places = self.places.0.lock().unwrap_or_else(|e| e.into_inner());
        places.insert(id, (track, index));
    }

    pub fn device(&self, id: Id) -> Option<&Arc<DeviceInst>> {
        let (track, index) = self.find_device(id)?;
        Some(&self.track(track)?.devices[index])
    }

    /// A clip on the timeline or off it, for cues.
    pub fn clip(&self, id: Id) -> Option<&Arc<Clip>> {
        if let Some((track, index)) = self.find_clip(id) {
            return Some(&self.track(track)?.clips[index]);
        }
        let (track, index) = self.find_cue_clip(id)?;
        Some(&self.track(track)?.cues[index])
    }

    /// The track that holds a clip off the timeline, and the clip's index
    /// among its cue clips.
    pub fn find_cue_clip(&self, id: Id) -> Option<(Id, usize)> {
        self.all_tracks()
            .find_map(|t| t.cues.iter().position(|c| c.id == id).map(|i| (t.id, i)))
    }


    pub fn device_mut(&mut self, id: Id) -> Option<&mut DeviceInst> {
        let (track, index) = self.find_device(id)?;
        Some(Arc::make_mut(&mut self.track_mut(track)?.devices[index]))
    }

    /// A clip on the timeline or off it, to change.
    pub fn clip_mut(&mut self, id: Id) -> Option<&mut Clip> {
        if let Some((track, index)) = self.find_clip(id) {
            return Some(Arc::make_mut(&mut self.track_mut(track)?.clips[index]));
        }
        let (track, index) = self.find_cue_clip(id)?;
        Some(Arc::make_mut(&mut self.track_mut(track)?.cues[index]))
    }

    /// Whether routing `from` into `to` would make audio flow in a circle.
    /// Audio flows on from a track through its output and its sends alike.
    pub fn would_cycle(&self, from: Id, to: Id) -> bool {
        let tracks: std::collections::HashMap<Id, &Track> =
            self.tracks.iter().map(|t| (t.id, &**t)).collect();
        let mut seen = std::collections::HashSet::new();
        let mut stack = vec![to];
        while let Some(id) = stack.pop() {
            if id == from {
                return true;
            }
            if id == MASTER_ID || !seen.insert(id) {
                continue;
            }
            if let Some(t) = tracks.get(&id) {
                stack.extend(t.output);
                stack.extend(t.sends.iter().map(|s| s.target));
                stack.extend(t.devices.iter().flat_map(|d| d.outputs.values()));
            }
            // A track feeds the tracks of the devices that listen to it.
            stack.extend(
                self.all_tracks()
                    .filter(|t| t.devices.iter().any(|d| d.sidechain == Some(id)))
                    .map(|t| t.id),
            );
        }
        false
    }

    /// The largest id in use.
    pub fn max_id(&self) -> Id {
        self.all_tracks()
            .flat_map(|t| {
                std::iter::once(t.id)
                    .chain(t.devices.iter().map(|d| d.id))
                    .chain(t.clips.iter().map(|c| c.id))
                    .chain(t.cues.iter().map(|c| c.id))
                    .chain(t.lanes.iter().map(|l| l.id))
            })
            .chain(self.nests.keys().map(|n| n.0))
            .max()
            .unwrap_or(0)
    }

    /// The tempo map, for converting between beats, seconds and bars.
    pub fn tempo_map(&self) -> &Arc<TempoMap> {
        &self.map
    }

    /// A hash of the tempo and signature points: the same points give the
    /// same stamp, so an undo gives the old stamp back. 53 bits, so that
    /// Lua holds it exactly.
    pub fn tempo_stamp(&self) -> u64 {
        use std::hash::{Hash, Hasher};
        let mut hash = std::collections::hash_map::DefaultHasher::new();
        (self.tempo.to_bits(), self.tempo_ramp, self.sig_num, self.sig_den).hash(&mut hash);
        for c in &self.tempo_changes {
            (c.beat.to_bits(), c.bpm.to_bits(), c.ramp).hash(&mut hash);
        }
        // Between the two lists, so that a tempo point never reads as a signature.
        u8::MAX.hash(&mut hash);
        for c in &self.sig_changes {
            (c.beat.to_bits(), c.num, c.den).hash(&mut hash);
        }
        hash.finish() >> 11
    }

    /// Every tempo point, the start's first.
    pub fn tempo_points(&self) -> Vec<TempoPoint> {
        let first = TempoPoint {
            beat: 0.0,
            bpm: self.tempo,
            ramp: self.tempo_ramp,
        };
        std::iter::once(first)
            .chain(self.tempo_changes.iter().map(|c| TempoPoint {
                beat: c.beat,
                bpm: c.bpm,
                ramp: c.ramp,
            }))
            .collect()
    }

    /// Every signature point, the start's first.
    pub fn sig_points(&self) -> Vec<SigPoint> {
        let first = SigPoint {
            beat: 0.0,
            num: self.sig_num,
            den: self.sig_den,
        };
        std::iter::once(first)
            .chain(self.sig_changes.iter().map(|c| SigPoint {
                beat: c.beat,
                num: c.num,
                den: c.den,
            }))
            .collect()
    }

    /// Build the map again from the tempo and signature fields, after they
    /// were set or read from a file, and tidy the fields as the map has them.
    pub fn refresh_tempo(&mut self) {
        let map = TempoMap::new(&self.tempo_points(), &self.sig_points());
        self.set_tempo_map(map);
    }

    /// Take the tempo and signature points of `map`.
    pub fn set_tempo_map(&mut self, map: TempoMap) {
        let mut tempos = map.tempos();
        let first = tempos.next().expect("a map has a first tempo");
        self.tempo = first.bpm;
        self.tempo_ramp = first.ramp;
        self.tempo_changes = tempos
            .map(|p| TempoChange {
                beat: p.beat,
                bpm: p.bpm,
                ramp: p.ramp,
            })
            .collect();
        let mut sigs = map.signatures();
        let first = sigs.next().expect("a map has a first signature");
        (self.sig_num, self.sig_den) = (first.num, first.den);
        self.sig_changes = sigs
            .map(|p| SigChange {
                beat: p.beat,
                num: p.num,
                den: p.den,
            })
            .collect();
        self.map = Arc::new(map);
    }

    /// Change to a new tempo map, moving audio clips as their timebase
    /// says: each keeps its length (and fades) in seconds, and its start in
    /// seconds or in beats. MIDI clips and automation stay on their beats.
    /// A block of a subproject with a tempo of its own keeps its start on
    /// its beat and its length in seconds.
    pub fn retime(&mut self, map: TempoMap) {
        let old = self.map.clone();
        self.fit_own_tempo_blocks(&old, &map);
        let tracks = std::iter::once(&mut self.master).chain(self.tracks.iter_mut());
        for track in tracks {
            let audio = |c: &Arc<Clip>| matches!(c.content, ClipContent::Audio { .. });
            if !track.clips.iter().any(audio) {
                continue;
            }
            for clip in Arc::make_mut(track).clips.iter_mut().filter(|c| audio(c)) {
                let s0 = old.seconds(clip.start);
                let s1 = old.seconds(clip.start + clip.length);
                if clip.timebase == Some(Timebase::Stretch) {
                    // Everything stays on its beats; the sound is stretched
                    // as much more as the clip now lasts longer.
                    let now = map.seconds_between(clip.start, clip.start + clip.length);
                    let (lo, hi) = crate::stretch::RATIO_RANGE;
                    let stretch = (clip.stretch * now / (s1 - s0)).clamp(lo, hi);
                    if (stretch - clip.stretch).abs() > 1e-12 {
                        Arc::make_mut(clip).stretch = stretch;
                    }
                    continue;
                }
                let fade_in = old.seconds(clip.start + clip.fade_in) - s0;
                let fade_out = s1 - old.seconds(clip.start + clip.length - clip.fade_out);
                let start = match clip.timebase.unwrap_or_default() {
                    Timebase::Time => map.beat(s0).max(0.0),
                    Timebase::Beats | Timebase::Stretch => clip.start,
                };
                let n0 = map.seconds(start);
                let end = map.beat(n0 + (s1 - s0));
                let moved = (
                    start,
                    end - start,
                    if clip.fade_in > 0.0 {
                        map.beat(n0 + fade_in) - start
                    } else {
                        0.0
                    },
                    if clip.fade_out > 0.0 {
                        end - map.beat(n0 + (s1 - s0) - fade_out)
                    } else {
                        0.0
                    },
                );
                let same = |a: f64, b: f64| (a - b).abs() < 1e-12;
                if !(same(moved.0, clip.start)
                    && same(moved.1, clip.length)
                    && same(moved.2, clip.fade_in)
                    && same(moved.3, clip.fade_out))
                {
                    // What repeats keeps its length in seconds as the sound does.
                    let repeat = clip.loop_length.map(|beats| {
                        let seconds = old.seconds_between(clip.start, clip.start + beats);
                        (map.beat(n0 + seconds) - start, beats)
                    });
                    let c = Arc::make_mut(clip);
                    (c.start, c.length, c.fade_in, c.fade_out) = moved;
                    if let Some((length, beats)) = repeat {
                        c.loop_start *= length / beats;
                        c.loop_length = Some(length);
                    }
                }
            }
        }
        self.set_tempo_map(map);
    }

    /// Whether the map was built from the fields as they are now.
    pub fn tempo_is_current(&self) -> bool {
        let m = &self.map;
        m.tempos().eq(self.tempo_points()) && m.signatures().eq(self.sig_points())
    }

    /// Where the song's last clip ends, in beats.
    pub fn end(&self) -> f64 {
        self.all_tracks()
            .filter(|t| t.nest.is_none())
            .flat_map(|t| t.clips.iter().map(|c| c.start + c.length))
            .fold(0.0, f64::max)
    }

    /// Check what a project file holds against what the editing calls allow,
    /// so that a damaged or hand-made file cannot load into a state the rest
    /// of the program does not expect: a tempo of 0 (renders that never
    /// end), two things with one id, routing loops, numbers out of range.
    pub fn validate(&self) -> anyhow::Result<()> {
        self.check_tempo_and_signature()?;
        self.check_master_and_ids()?;
        let tracks: std::collections::HashMap<Id, &Track> =
            self.all_tracks().map(|t| (t.id, &**t)).collect();
        for t in self.all_tracks() {
            check_track(t, &tracks)?;
        }
        self.check_routing_loops(&tracks)?;
        self.check_links()?;
        nest::check(self)
    }

    /// The tempo, the tempo changes and the time signatures are in range.
    fn check_tempo_and_signature(&self) -> anyhow::Result<()> {
        check_range("the tempo", self.tempo, 1.0, 999.0)?;
        for c in &self.tempo_changes {
            check_range("a tempo change's tempo", c.bpm, 1.0, 999.0)?;
            check_range("a tempo change's beat", c.beat, 0.0, 1e9)?;
        }
        for c in &self.sig_changes {
            check_range("a signature change's beat", c.beat, 0.0, 1e9)?;
            check_range("a signature's numerator", c.num as f64, 1.0, 64.0)?;
            check_range("a signature's denominator", c.den as f64, 1.0, 64.0)?;
        }
        check_range(
            "the time signature's numerator",
            self.sig_num as f64,
            1.0,
            64.0,
        )?;
        check_range(
            "the time signature's denominator",
            self.sig_den as f64,
            1.0,
            64.0,
        )?;
        Ok(())
    }

    /// The master is the master, and no two things have one id.
    fn check_master_and_ids(&self) -> anyhow::Result<()> {
        use anyhow::bail;
        if self.master.id != MASTER_ID
            || self.master.output.is_some()
            || !self.master.sends.is_empty()
        {
            bail!("the master track must have id {MASTER_ID} and no output or sends");
        }
        let mut ids = std::collections::HashSet::new();
        let mut unique = |id: Id| -> anyhow::Result<()> {
            if !ids.insert(id) {
                bail!("id {id} is used twice");
            }
            Ok(())
        };
        for t in self.all_tracks() {
            unique(t.id)?;
            for d in &t.devices {
                unique(d.id)?;
            }
            for c in t.clips.iter().chain(&t.cues) {
                unique(c.id)?;
            }
            for l in &t.lanes {
                unique(l.id)?;
            }
        }
        Ok(())
    }

    /// Routing must not go round in a circle: a depth-first walk along
    /// outputs and sends that never comes back to a track on its own path.
    fn check_routing_loops(
        &self,
        tracks: &std::collections::HashMap<Id, &Track>,
    ) -> anyhow::Result<()> {
        use anyhow::bail;
        let mut state: std::collections::HashMap<Id, u8> = std::collections::HashMap::new();
        for start in &self.tracks {
            if state.contains_key(&start.id) {
                continue;
            }
            let mut stack: Vec<(Id, usize)> = vec![(start.id, 0)];
            state.insert(start.id, 1);
            while let Some(&mut (id, ref mut next)) = stack.last_mut() {
                let t = tracks[&id];
                let targets: Vec<Id> = t
                    .output
                    .iter()
                    .copied()
                    .chain(t.sends.iter().map(|s| s.target))
                    .collect();
                match targets.get(*next) {
                    Some(&to) => {
                        *next += 1;
                        match state.get(&to) {
                            Some(1) => bail!("track {} ({}) is routed in a loop", t.id, t.name),
                            Some(_) => {}
                            None => {
                                state.insert(to, 1);
                                stack.push((to, 0));
                            }
                        }
                    }
                    None => {
                        state.insert(id, 2);
                        stack.pop();
                    }
                }
            }
        }
        Ok(())
    }
}

fn check_range(what: &str, v: f64, lo: f64, hi: f64) -> anyhow::Result<()> {
    if !(lo..=hi).contains(&v) {
        anyhow::bail!("{what} is {v}, which is outside {lo} to {hi}");
    }
    Ok(())
}

/// One track: its levels, routing, devices, clips and lanes.
fn check_track(t: &Track, tracks: &std::collections::HashMap<Id, &Track>) -> anyhow::Result<()> {
    use anyhow::bail;
    let name = format!("track {} ({})", t.id, t.name);
    check_range(&format!("the volume of {name}"), t.volume, -120.0, 24.0)?;
    check_range(&format!("the pan of {name}"), t.pan, -1.0, 1.0)?;
    for target in t.output.iter().chain(t.sends.iter().map(|s| &s.target)) {
        if *target == t.id || *target == MASTER_ID || !tracks.contains_key(target) {
            bail!("{name} is routed to track {target}, which it cannot be");
        }
    }
    for s in &t.sends {
        check_range(&format!("a send level of {name}"), s.level, -120.0, 24.0)?;
    }
    for d in &t.devices {
        if let Some((key, v)) = d.params.iter().find(|(_, v)| !v.is_finite()) {
            bail!("parameter {key} of device {} is {v}", d.id);
        }
    }
    if t.cues.iter().any(|c| c.start != 0.0) {
        bail!("{name} has a clip off the timeline that does not start at 0");
    }
    for c in t.clips.iter().chain(&t.cues) {
        check_clip(c)?;
    }
    for l in &t.lanes {
        check_lane(t, l)?;
    }
    Ok(())
}

/// One clip: its place, its content and its loop.
fn check_clip(c: &Clip) -> anyhow::Result<()> {
    use anyhow::bail;
    if !c.start.is_finite() || c.start < 0.0 || !c.length.is_finite() || c.length <= 0.0 {
        bail!(
            "clip {} starts at {} and is {} long: it needs a start of at least 0 and a length above 0",
            c.id,
            c.start,
            c.length
        );
    }
    match &c.content {
        ClipContent::Midi { notes, controls } => {
            if let Some((control, problem)) = controls
                .iter()
                .find_map(|c| c.problem().map(|problem| (c, problem)))
            {
                bail!(
                    "clip {} holds a controller move {control:?}: {problem}",
                    c.id
                );
            }
            if let Some(n) = notes.iter().find(|n| {
                !n.start.is_finite()
                    || !n.length.is_finite()
                    || n.length <= 0.0
                    || n.pitch > 127
                    || n.velocity > 127
            }) {
                bail!("clip {} holds a note that cannot be played: {n:?}", c.id);
            }
        }
        ClipContent::Audio { offset, gain, .. } => {
            if !offset.is_finite() || *offset < 0.0 {
                bail!("audio clip {} has offset {offset}", c.id);
            }
            check_range(&format!("the gain of clip {}", c.id), *gain, -120.0, 24.0)?;
            let (lo, hi) = crate::stretch::RATIO_RANGE;
            check_range(&format!("the stretch of clip {}", c.id), c.stretch, lo, hi)?;
            let most = crate::stretch::PITCH_RANGE;
            check_range(&format!("the pitch of clip {}", c.id), c.pitch, -most, most)?;
            if let Some(bpm) = c.source_tempo {
                check_range(&format!("the tempo of clip {}", c.id), bpm, 1.0, 999.0)?;
            }
            let finite = c
                .warp
                .iter()
                .all(|m| m.source.is_finite() && m.target.is_finite());
            let ordered = c
                .warp
                .windows(2)
                .all(|w| w[1].source > w[0].source && w[1].target > w[0].target);
            if !finite || !ordered {
                bail!("the warp markers of clip {} are out of order", c.id);
            }
        }
        ClipContent::Custom(custom) => {
            if !custom.offset.is_finite() {
                bail!("{} clip {} has offset {}", custom.kind, c.id, custom.offset);
            }
        }
        ClipContent::Nest { offset, .. } => {
            if !offset.is_finite() || *offset < 0.0 {
                bail!("subproject clip {} has offset {offset}", c.id);
            }
        }
    }
    if let Some(length) = c.loop_length {
        let what = format!("the loop length of clip {}", c.id);
        check_range(&what, length, 1e-6, 1e9)?;
    }
    let what = format!("the loop start of clip {}", c.id);
    check_range(&what, c.loop_start, -1e9, 1e9)
}

/// One automation lane of track `t`: its points, shapes and target.
fn check_lane(t: &Track, l: &Lane) -> anyhow::Result<()> {
    use anyhow::bail;
    if l.points
        .iter()
        .any(|(b, v)| !b.is_finite() || !v.is_finite() || *b < 0.0)
    {
        bail!(
            "automation lane {} has a point that is not a finite beat and value",
            l.id
        );
    }
    if l.shapes.iter().any(|s| !s.beat.is_finite() || !s.tension.is_finite()) {
        bail!("automation lane {} has a shape that is not at a finite beat", l.id);
    }
    let limits = match &l.target {
        Target::Volume => Some((-120.0, 24.0)),
        Target::Pan => Some((-1.0, 1.0)),
        Target::Param { .. } => None,
        Target::State { .. } => Some((0.0, l.states.len().saturating_sub(1) as f64)),
    };
    if let Some((lo, hi)) = limits {
        for (_, v) in &l.points {
            check_range(&format!("a point of automation lane {}", l.id), *v, lo, hi)?;
        }
    }
    if matches!(l.target, Target::State { .. }) && !l.points.is_empty() && l.states.is_empty() {
        bail!("state lane {} has points but no states", l.id);
    }
    if let Some(device) = l.target.device()
        && !t.devices.iter().any(|d| d.id == device)
    {
        bail!(
            "automation lane {} is for device {device}, which is not on its track",
            l.id
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_channels_round_trip_as_plain_strings() {
        for (text, first, count) in [("1", 0, 1), ("3", 2, 1), ("1/2", 0, 2), (" 3 / 4 ", 2, 2)] {
            let input: InputChannels = text.parse().unwrap();
            assert_eq!(input, InputChannels { first, count }, "{text}");
            let plain = input.to_string();
            assert_eq!(serde_json::to_string(&input).unwrap(), format!("\"{plain}\""));
            assert_eq!(serde_json::from_str::<InputChannels>(&format!("\"{plain}\"")).unwrap(), input);
        }
        for bad in ["", "0", "x", "1/3", "2/1", "1/2/3", "300"] {
            assert!(bad.parse::<InputChannels>().unwrap_err().contains("bad input"), "{bad}");
        }
    }

    /// A project as files were written before tracks had a height of their
    /// own and before anything could lie hidden before a clip's start.
    const OLD: &str = r#"{
        "name": "old", "tempo": 120.0, "sig_num": 4, "sig_den": 4,
        "master": { "id": 0, "name": "Master", "volume": 0.0, "pan": 0.0, "mute": false,
            "solo": false, "armed": false, "output": null, "sends": [], "devices": [],
            "clips": [], "color": null },
        "tracks": [{ "id": 1, "name": "Keys", "volume": -3.0, "pan": 0.0, "mute": false,
            "solo": false, "armed": false, "output": null, "sends": [], "devices": [],
            "color": null,
            "clips": [{ "id": 2, "name": "riff", "start": 4.0, "length": 4.0, "muted": false,
                "content": { "kind": "midi",
                    "notes": [{ "start": 0.0, "length": 1.0, "pitch": 60, "velocity": 90 }],
                    "controls": [{ "start": 0.5, "type": "cc", "number": 1, "value": 0.5 }] } }] }]
    }"#;

    #[test]
    fn an_old_project_loads_unchanged() {
        let project: Project = serde_json::from_str(OLD).expect("an old project loads");
        project.validate().expect("and is valid");
        let track = &project.tracks[0];
        assert_eq!(
            track.height, None,
            "a track is as tall as the zoom makes it"
        );
        let ClipContent::Midi { notes, controls } = &track.clips[0].content else {
            panic!("a MIDI clip");
        };
        assert_eq!((notes.len(), controls.len()), (1, 1));
        let saved = serde_json::to_string(&project).unwrap();
        assert!(!saved.contains("height"), "and is saved as it was: {saved}");
    }

    #[test]
    fn a_height_and_hidden_moves_are_kept() {
        let mut project: Project = serde_json::from_str(OLD).unwrap();
        let track = Arc::make_mut(&mut project.tracks[0]);
        track.height = Some(2.5);
        let clip = Arc::make_mut(&mut track.clips[0]);
        if let ClipContent::Midi { notes, controls } = &mut clip.content {
            notes[0].start = -1.0;
            controls[0].start = -0.5;
        }
        project
            .validate()
            .expect("notes and moves before the start are allowed");
        let again: Project =
            serde_json::from_str(&serde_json::to_string(&project).unwrap()).unwrap();
        assert_eq!(again.tracks[0].height, Some(2.5));
    }
}

#[cfg(test)]
mod tempo_tests {
    use super::*;

    #[test]
    fn one_tempo_saves_as_before() {
        let p = Project::default();
        let text = serde_json::to_value(&p).unwrap();
        let o = text.as_object().unwrap();
        assert!(!o.contains_key("tempo_changes") && !o.contains_key("sig_changes"));
        assert!(!o.contains_key("tempo_ramp") && !o.contains_key("map"));
        assert_eq!(o["tempo"], 120.0);
    }

    #[test]
    fn changes_load_into_the_map() {
        let mut v = serde_json::to_value(Project::default()).unwrap();
        v["tempo"] = 100.0.into();
        v["tempo_ramp"] = true.into();
        v["tempo_changes"] = serde_json::json!([{"beat": 8, "bpm": 50}, {"beat": 4, "bpm": 200}]);
        v["sig_changes"] = serde_json::json!([{"beat": 16, "num": 6, "den": 8}]);
        let mut p: Project = serde_json::from_value(v).unwrap();
        p.validate().unwrap();
        p.refresh_tempo();
        assert!(p.tempo_is_current());
        assert_eq!(p.tempo_changes[0].beat, 4.0, "kept in order");
        let m = p.tempo_map();
        // 100 to 200 over four beats, linear in time: 4 * 60 / 150 s.
        assert!((m.seconds(4.0) - 1.6).abs() < 1e-12);
        assert_eq!(m.signature(17.0), (6, 8));
        let back = serde_json::to_value(&p).unwrap();
        assert_eq!(back["tempo_changes"].as_array().unwrap().len(), 2);
    }
}

#[cfg(test)]
mod note_ids {
    use super::*;

    fn note(pitch: u8, id: u64) -> Note {
        Note { start: 0.0, length: 1.0, pitch, velocity: 100, meta: Map::new(), id, attr: None }
    }

    #[test]
    fn notes_without_an_id_get_the_next_free_ones_and_the_same_ones_again() {
        let mut notes = Notes::from(vec![note(60, 0), note(62, 0), note(64, 0)]);
        assert!(name_notes(&mut notes));
        assert_eq!(notes.iter().map(|n| n.id).collect::<Vec<_>>(), [1, 2, 3]);
        assert!(!name_notes(&mut notes), "named notes are left alone");
        let mut again = Notes::from(vec![note(60, 0), note(62, 0), note(64, 0)]);
        name_notes(&mut again);
        assert_eq!(again, notes, "the same notes, the same ids");
    }

    #[test]
    fn a_copy_next_to_its_original_gets_an_id_of_its_own() {
        let mut notes = Notes::from(vec![note(60, 7), note(60, 7), note(62, 3), note(65, 0)]);
        assert!(name_notes(&mut notes));
        assert_eq!(notes.iter().map(|n| n.id).collect::<Vec<_>>(), [7, 8, 3, 9]);
    }

    #[test]
    fn a_note_without_an_id_is_written_without_one() {
        let text = serde_json::to_string(&note(60, 0)).unwrap();
        assert!(!text.contains("\"id\""), "{text}");
        let back: Note = serde_json::from_str(&serde_json::to_string(&note(60, 4)).unwrap()).unwrap();
        assert_eq!(back.id, 4);
    }
}

#[cfg(test)]
mod by_key {
    use super::*;

    #[test]
    fn items_are_found_in_place_moved_added_and_removed() {
        let old: Vec<u64> = (1..=100).collect();
        // One removed (10), one added (500), one moved to the end (20).
        let mut new: Vec<u64> = old.iter().copied().filter(|&x| x != 10 && x != 20).collect();
        new.insert(50, 500);
        new.push(20);
        let mut by = ByKey::new(&old[..], |x: &u64| *x);
        let found: Vec<Option<usize>> = new.iter().map(|&x| by.position(x)).collect();
        for (x, at) in new.iter().zip(&found) {
            assert_eq!(*at, old.iter().position(|o| o == x), "{x}");
        }
        // Many out of place: a map is made, and still every one is found.
        let reversed: Vec<u64> = old.iter().rev().copied().collect();
        let mut by = ByKey::new(&old[..], |x: &u64| *x);
        assert!(reversed.iter().all(|&x| by.position(x) == Some(x as usize - 1)));
        assert!(by.map.is_some());
        assert_eq!(by.position(1000), None);
    }
}

#[cfg(test)]
mod lane_shapes {
    use super::*;
    use paw_engine::automation::value_at;

    fn lane(shapes: Vec<Segment>) -> Lane {
        Lane { id: 1, target: Target::Volume, enabled: true, points: vec![(0.0, -12.0), (4.0, 0.0), (8.0, -6.0)], shapes, states: Vec::new() }
    }

    #[test]
    fn a_state_lane_holds_each_state_to_the_next_point() {
        let mut states = lane(Vec::new());
        states.target = Target::State { device: 7 };
        states.points = vec![(0.0, 0.0), (4.0, 1.0), (8.0, 0.0)];
        assert_eq!(value_at(&states.played(), 3.99), Some(0.0));
        assert_eq!(value_at(&states.played(), 4.0), Some(1.0));
        assert_eq!(value_at(&states.played(), 7.0), Some(1.0), "no curve between");
        assert_eq!(value_at(&states.played(), 9.0), Some(0.0));
    }

    #[test]
    fn a_held_stretch_jumps_at_the_next_point_and_a_smooth_one_eases() {
        let straight = lane(Vec::new());
        assert_eq!(value_at(&straight.played(), 2.0), Some(-6.0));
        let held = lane(vec![Segment { beat: 0.0, shape: Shape::Hold, tension: 0.0 }]);
        assert_eq!(value_at(&held.played(), 3.99), Some(-12.0));
        assert_eq!(value_at(&held.played(), 4.0), Some(0.0));
        assert_eq!(value_at(&held.played(), 6.0), Some(-3.0), "the next stretch is straight");
        let eased = lane(vec![Segment { beat: 0.0, shape: Shape::Smooth, tension: 0.0 }]);
        assert!((value_at(&eased.played(), 2.0).unwrap() + 6.0).abs() < 1e-9, "half way at the middle");
        assert!(value_at(&eased.played(), 0.5).unwrap() < -11.0, "slow to leave");
        let early = lane(vec![Segment { beat: 0.0, shape: Shape::Smooth, tension: 1.0 }]);
        assert!(value_at(&early.played(), 1.0).unwrap() > value_at(&eased.played(), 1.0).unwrap());
        let text = serde_json::to_string(&straight).unwrap();
        assert!(!text.contains("shapes"), "{text}");
        let back: Lane = serde_json::from_str(&serde_json::to_string(&held).unwrap()).unwrap();
        assert_eq!(back.shapes, held.shapes);
    }
}
