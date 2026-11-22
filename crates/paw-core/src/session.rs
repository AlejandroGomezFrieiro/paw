//! The session: the project, its undo history and the running engine.
//!
//! Every edit changes [`Session::project`] and marks it dirty. [`Session::flush`]
//! then diffs it against what the engine last saw and sends the difference.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow, bail};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use paw_engine::backend::{self, BackendChoice, BackendOptions, Stream, StreamInfo};
use paw_engine::midi::{MidiInputs, MidiSink};
use paw_engine::record::{self, AudioCapture, MidiCapture, Take, TakeShared};
use paw_engine::{Engine, EngineHandle, EventKind, Msg, ParamInfo, Pool, Registry};
use rtrb::RingBuffer;
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::{Map, Value, json};

use crate::history::{self, History};
use crate::model::{
    check_clip_beat, check_notes, Clip, ClipContent, ClipKindId, Control, CustomContent, DeviceInst, KindData, MediaRef, Signal, Timeline, Id, Lane, LaneState, MASTER_ID, MidiInput, NestPlay, Note, NoteAttr, Notes, Project, Segment,
    Send, Shape, Sound, StretchMode, Target, Timebase, Track, WarpMarker, InputChannels,
};
use crate::sync::{AudioCache, Follow, LiveDevices, Mapper, ModelEvent, SyncCtx, sync};

mod editing;
mod project;
mod tracks;
mod devices;
pub use devices::DeviceQuery;
mod clips;
mod automation;
mod transport;
mod midi_in;
pub use midi_in::FilterRule;
mod engine;
mod audition;
mod clipops;
mod encode;
mod file_check;
mod files_watch;
pub mod folder;
pub mod project_files;
mod undo_file;
mod keep;
pub mod cues;
mod loading;
pub mod media;
mod midi_out;
mod nests;
mod promote;
mod save;
pub use save::SaveOpts;
pub use nests::NestOpts;
mod monitor;
mod statelanes;
mod stretching;
pub use loading::OpenOpts;
pub mod notes;
pub mod offline;
pub mod panic;
mod ports;
mod posts;
pub mod render;
pub mod tags;
mod tempo;
mod undo;
mod watch;
pub use watch::Lost;
mod write;
use undo::{SWEEP_GAP, new_history};

const FILE_VERSION: u32 = 1;
/// More points than any screen has columns.
const MAX_PEAKS: usize = 1 << 16;

/// Transport settings that are saved with the project but are not undoable.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Transport {
    pub loop_enabled: bool,
    pub loop_start: f64,
    pub loop_end: f64,
    pub metronome: bool,
    /// Record only from `punch_start` to `punch_end` (beats), the song
    /// playing on either side.
    pub punch_enabled: bool,
    pub punch_start: f64,
    pub punch_end: f64,
    /// Record a take whenever the transport plays. Never saved.
    #[serde(skip)]
    pub recording: bool,
    /// Bars to count before a take that starts with the song stopped; 0
    /// for none. Set from `paw.opt.count_in`, so not saved with a project.
    #[serde(skip)]
    pub count_in: u32,
    /// Bars, and then seconds, that a take punched in from a stop starts
    /// playing before the punch in. Set from `paw.opt.pre_roll` and
    /// `paw.opt.pre_roll_seconds`, so not saved with a project.
    #[serde(skip)]
    pub pre_roll: u32,
    #[serde(skip)]
    pub pre_roll_seconds: f64,
    /// The metronome's level in dB, whether the first beat of a bar is
    /// higher, and the first output channel (from 1) of the pair it plays
    /// on, or 0 for with the song. Set from `paw.opt.click_level`,
    /// `paw.opt.click_accent` and `paw.opt.click_output`, so not saved
    /// with a project.
    #[serde(skip)]
    pub click_level: f64,
    #[serde(skip)]
    pub click_accent: bool,
    #[serde(skip)]
    pub click_output: u32,
}

impl Default for Transport {
    fn default() -> Self {
        Self {
            loop_enabled: false,
            loop_start: 0.0,
            loop_end: 16.0,
            metronome: false,
            punch_enabled: false,
            punch_start: 0.0,
            punch_end: 0.0,
            recording: false,
            count_in: 0,
            pre_roll: 0,
            pre_roll_seconds: 0.0,
            click_level: 0.0,
            click_accent: true,
            click_output: 0,
        }
    }
}

/// What records takes: the take under way, how many takes were begun, and
/// how much earlier recordings are moved.
#[derive(Default)]
struct Recorder {
    take: Option<Recording>,
    /// Takes begun so far: the next take's number is one more.
    takes: u32,
    /// Milliseconds to move recordings earlier by, on top of what the audio
    /// system reports: found by recording the metronome through a loop-back.
    offset: f64,
}

/// A take being recorded: the writer threads filling its files, and the notes
/// played into armed tracks so far.
struct Recording {
    number: u32,
    shared: Arc<TakeShared>,
    audio: Vec<(Id, PathBuf, JoinHandle<record::Written>)>,
    midi: rtrb::Consumer<MidiCapture>,
    /// Notes still held, by track and key: the beat they began on, their
    /// velocity, which time round the loop they began in, and their attribute.
    held: HashMap<(Id, u8), (f64, u8, u32, Option<NoteAttr>)>,
    /// Finished notes by track and time round the loop, with `start` in
    /// project beats.
    notes: BTreeMap<(Id, u32), Vec<Note>>,
    /// Controller moves by track and time round, with `start` in project beats.
    controls: BTreeMap<(Id, u32), Vec<Control>>,
    /// The loop the take goes round, if the loop was on when it began, and
    /// the frames captured each time it jumped back.
    looped: Option<(f64, f64)>,
    /// The range it was punched into, in beats of the song, if punching was
    /// on when it began: only what was played there is captured.
    punch: Option<(f64, f64)>,
    wraps: rtrb::Consumer<u64>,
    wrapped: Vec<u64>,
}

impl Recording {
    /// End a held note at `at`, played in pass `pass`. A note still held
    /// when the loop jumps back ends at the loop's end.
    fn end_note(&mut self, track: Id, key: u8, at: f64, pass: u32) {
        if let Some((start, velocity, began, attr)) = self.held.remove(&(track, key)) {
            let at = match self.looped {
                Some((_, end)) if pass > began => end,
                _ => at,
            };
            self.notes.entry((track, began)).or_default().push(Note {
                start,
                length: (at - start).max(1.0 / 128.0),
                pitch: key,
                velocity,
                meta: Default::default(),
                id: 0,
                attr,
            });
        }
    }
}

/// One time round the loop of a take, or the whole of a take that never
/// went round: where it lies on the timeline and where its sound begins in
/// the take's files.
struct Pass {
    /// Its number among the take's passes, from 0.
    index: u32,
    start: f64,
    end: f64,
    /// Seconds into the files, before the latency is taken off.
    seconds: f64,
}

#[derive(Serialize, Deserialize)]
struct ProjectFile {
    version: u32,
    project: Project,
    #[serde(default)]
    transport: Transport,
    /// The tabs and windows the project opens with, as the frontends' Lua
    /// keeps them: not part of the song, and not an edit to undo.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    screen: Option<Value>,
}

/// The text of a project file for a project given as data, such as one
/// merged from three in a script. It goes through the model, so that it has
/// the form and the key order `project_save` writes (two writers that agree
/// make small diffs) and cannot be a file that does not load.
pub fn project_file_text(value: Value) -> Result<String> {
    let file: ProjectFile = serde_json::from_value(value).context("not a project file")?;
    if file.version > FILE_VERSION {
        bail!("the file is of a newer version");
    }
    file.project.validate()?;
    Ok(serde_json::to_string_pretty(&file)?)
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct TrackOpts {
    pub name: Option<String>,
    /// Position among the tracks of its place (the song, or its
    /// subproject), counting from 1. Appended when absent.
    pub index: Option<usize>,
    pub volume: Option<f64>,
    pub pan: Option<f64>,
    pub output: Option<Id>,
    pub color: Option<String>,
    /// The nest (subproject) the track is made in; the song when absent.
    pub nest: Option<crate::model::NestId>,
}

/// What `paw.api.track_list` takes: the tracks of the song when empty.
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct TrackListOpts {
    /// The tracks of this subproject, without its master.
    pub nest: Option<crate::model::NestId>,
    /// Every track: the song's and those of each subproject.
    pub all: bool,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct PresetLoad {
    /// The preset's name, shown with the device.
    pub name: Option<String>,
    /// The plugin's state, base64 encoded.
    pub state: Option<String>,
    pub params: BTreeMap<String, f64>,
    /// One of the plugin's own presets, by the id its list gives.
    pub factory: Option<String>,
    /// A request to the device that changes its state (see
    /// [`Session::device_call`]), such as an LV2 property set to a new file:
    /// the state the device has then is what is kept.
    pub call: Option<LoadCall>,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LoadCall {
    pub method: String,
    pub data: String,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct DeviceOpts {
    /// Position in the chain, counting from 1. Appended when absent.
    pub index: Option<usize>,
    pub params: BTreeMap<String, f64>,
    /// A plugin's state as [`Session::device_state`] gave it, to start from.
    pub state: Option<String>,
}

/// What a new clip holds: `midi`, `audio` or the name of a kind that an
/// extension defines, in Lua. A word that is no name fails with the text of
/// [`FromStr`](std::str::FromStr); whether an extension defined it is known
/// where the clip is added (`Session::clip_kinds`).
#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
#[serde(try_from = "String")]
pub enum ClipKind {
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

/// What a new lane automates: `volume`, `pan`, `param` or `state` in Lua.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase", try_from = "String")]
pub enum LaneKind {
    Volume,
    Pan,
    Param,
    State,
}

impl std::str::FromStr for LaneKind {
    type Err = anyhow::Error;

    fn from_str(word: &str) -> Result<Self> {
        Ok(match word {
            "volume" => Self::Volume,
            "pan" => Self::Pan,
            "param" => Self::Param,
            "state" => Self::State,
            other => bail!("cannot automate `{other}`: use volume, pan, param or state"),
        })
    }
}

impl TryFrom<String> for LaneKind {
    type Error = anyhow::Error;

    fn try_from(word: String) -> Result<Self> {
        word.parse()
    }
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct ClipOpts {
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
    /// Keep it off the timeline, among the track's cues (`session/cues.rs`).
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

/// What [`Session::clip_set_custom`] gives a custom clip: what its kind
/// compiled, replacing data, media, sound and signals together, so that it
/// is one edit. `version`, `timeline` and `offset` stay as they are when
/// absent.
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct CustomSet {
    pub data: Option<KindData>,
    pub version: Option<u32>,
    pub timeline: Option<Timeline>,
    pub offset: Option<f64>,
    pub media: Vec<MediaRef>,
    pub sound: Option<Sound>,
    pub signals: Vec<Signal>,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LaneOpts {
    /// Required: a missing target fails like an unknown one.
    pub target: Option<LaneKind>,
    /// For `param`: the device, on the same track, and its parameter by key or name.
    pub device: Option<Id>,
    pub param: Option<String>,
    pub enabled: Option<bool>,
    pub points: Vec<(f64, f64)>,
    /// For `state`: the states the lane gives its device.
    pub states: Vec<LaneState>,
}

#[derive(Clone, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct RenderOpts {
    pub start: f64,
    /// Beat to stop at. Defaults to the end of the last clip.
    pub end: Option<f64>,
    /// Extra seconds after `end`, for release and delay tails.
    pub tail: f64,
    pub sample_rate: Option<u32>,
    /// 16 or 24 for integer PCM, 32 for float.
    pub bits: u16,
    /// Only these tracks, as if they were soloed: a stem. All when empty.
    pub tracks: Vec<Id>,
    /// This track and what feeds it, before its fader, and nothing else:
    /// what freezing it plays (see [`crate::freeze::alone`]).
    pub freeze: Option<Id>,
    /// Add dither when writing 16 or 24 bits.
    pub dither: bool,
    /// Bring the loudest sample to this level in dB.
    pub normalize: Option<f64>,
    /// Bring the integrated loudness to this level in LUFS. With `normalize`
    /// as well, the peak level is a ceiling the loudness gives way to.
    pub loudness: Option<f64>,
    /// 1 for mono (both sides mixed at half level each), 2 for stereo.
    pub channels: u16,
    /// Through the master track's devices, fader and pan; false for the
    /// tracks as they reach it.
    pub master: bool,
    /// Threads to render on, when not as many as the session uses. The file
    /// is the same whatever the number.
    pub threads: Option<usize>,
    /// Whether devices at rest sleep through silence, when not as the
    /// session has it. The file is the same either way.
    pub sleep: Option<bool>,
    /// For MP3, Ogg Vorbis and Opus: "low", "medium", "high" (the default)
    /// or "best"; or a bitrate in kbit/s instead. They need ffmpeg, which is
    /// `ffmpeg` when it is not on the PATH.
    pub quality: Option<String>,
    pub bitrate: Option<u32>,
    pub ffmpeg: Option<String>,
    /// What the file is tagged with, over the project's own
    /// (`project.meta.tags`): see [`tags::Tags`].
    pub tags: tags::Tags,
    /// The most seconds a render waits for plugins to be ready: at its
    /// start, and after a state lane gives one a saved state. It waits
    /// until a plugin's process has used no processor time for a moment.
    pub settle: f64,
}

impl Default for RenderOpts {
    fn default() -> Self {
        Self {
            start: 0.0,
            end: None,
            tail: 1.0,
            sample_rate: None,
            bits: 24,
            tracks: Vec::new(),
            freeze: None,
            dither: false,
            normalize: None,
            loudness: None,
            channels: 2,
            master: true,
            threads: None,
            sleep: None,
            quality: None,
            bitrate: None,
            ffmpeg: None,
            tags: tags::Tags::default(),
            settle: 5.0,
        }
    }
}

pub struct Session {
    pub project: Project,
    /// The project as the engine last saw it.
    synced: Project,
    /// The tracks (and the master) as the last edit left them, its notes
    /// named: the next edit looks for notes to name only where it differs.
    named: (Vec<Arc<Track>>, Arc<Track>),
    /// The project differs from what the engine last saw: the next
    /// [`flush`](Self::flush) sends the difference.
    dirty: bool,
    /// The undo tree and the open step: see `session/undo.rs`.
    undo: undo::Undo,
    next_id: Id,

    /// The running engine and how it was started: see `session/engine.rs`.
    engine: engine::EngineLink,
    pub registry: Registry,
    /// The kinds of clip that extensions defined (`paw.clip_kinds.define`):
    /// a clip of another custom kind is not added. Not part of the project.
    clip_kinds: BTreeSet<ClipKindId>,
    audio: AudioCache,
    /// Checkpoints counted for [`Session::trim_audio_now_and_then`].
    trims: u32,
    /// Parameters and controllers of the devices the engine is running.
    live: LiveDevices,

    pub transport: Transport,
    /// Whether the song plays, and the seeks under way: see
    /// `session/transport.rs`.
    play: transport::Playback,
    pub path: Option<PathBuf>,
    /// The screen the project file keeps (`ProjectFile::screen`).
    pub screen: Option<Value>,
    /// Change notifications waiting to be delivered to Lua.
    pub events: Vec<ModelEvent>,
    pub warnings: Vec<String>,

    /// The take being recorded: see `session/transport.rs`.
    rec: Recorder,
    /// MIDI ports, in and out: see `session/midi_in.rs`.
    midi: midi_in::MidiIo,
    /// Automation written by moving controls: see `session/write.rs`.
    writing: write::Writing,
    /// Where the devices chosen with [`audio_use`](Self::audio_use) are
    /// remembered, or `None` not to remember them.
    pub device_file: Option<PathBuf>,
    /// The render running on a thread of its own: session/render.rs.
    render_job: Option<render::Job>,
    /// The state each state lane last gave its device from the main
    /// thread: see `session/statelanes.rs`.
    state_given: statelanes::Given,
    /// Plugins being made apart from the main loop: see `session/loading.rs`.
    loads: loading::Loads,
    /// How the next project opened is to be opened (plugins offline).
    open_opts: loading::OpenOpts,
    /// The audio device and MIDI ports, watched for going and coming back.
    watch: watch::Watch,
    /// Changes made outside paw to the open project's files.
    files_watch: files_watch::FileWatch,
    /// Whether the files that clips read are there, looked at no more than
    /// once a second for each: see `session/file_check.rs`.
    files_there: file_check::FileCheck,
    /// When files played from the disk were last read ahead of the playhead.
    read_ahead_at: Instant,
    /// What each of the project's files is: its hash, size and header
    /// (`media.json`), learned in the background (session/media.rs).
    pub(crate) sources: crate::media::Sources,
    /// The project put aside while a scratch one is open: see
    /// [`Session::project_shelve`].
    shelf: Option<Shelf>,
    /// Edits that may yet be thrown away, and the sound file heard on its
    /// own: see `session/audition.rs`.
    audition: audition::Audition,
}

/// An open project, with its undo history, put aside whole.
struct Shelf {
    project: Project,
    history: History<Project>,
    touched: bool,
    transport: Transport,
    position: f64,
    path: Option<PathBuf>,
    /// The states of its undo tree that are still only in its undo file.
    lazy: undo_file::Lazy,
}

/// The rest of what [`Session::audio_use`] can change: the sound system
/// and the sample rate (0 for the device's own).
#[derive(Default)]
pub struct AudioChoice {
    pub backend: Option<String>,
    pub rate: Option<u32>,
}

/// Free-form data from a script. An empty Lua table arrives as an empty
/// list, and means an empty map here.
fn de_meta(key: &str, value: Value) -> Result<Map<String, Value>> {
    match value {
        Value::Array(list) if list.is_empty() => Ok(Map::new()),
        value => de(key, value),
    }
}

/// Whether `key` of a view already holds `value`: setting it would change
/// nothing, and makes no undo step. Numbers are compared as numbers.
fn holds(view: &Result<Value>, key: &str, value: &Value) -> bool {
    fn same(a: &Value, b: &Value) -> bool {
        match (a, b) {
            (Value::Number(a), Value::Number(b)) => a.as_f64() == b.as_f64(),
            (Value::Array(a), Value::Array(b)) => {
                a.len() == b.len() && a.iter().zip(b).all(|(a, b)| same(a, b))
            }
            (Value::Object(a), Value::Object(b)) => {
                a.len() == b.len() && a.iter().all(|(k, v)| b.get(k).is_some_and(|w| same(v, w)))
            }
            _ => a == b,
        }
    }
    view.as_ref()
        .is_ok_and(|view| view.get(key).is_some_and(|old| same(old, value)))
}

fn de<T: DeserializeOwned>(key: &str, value: Value) -> Result<T> {
    serde_json::from_value(value).map_err(|err| anyhow!("bad value for `{key}`: {err}"))
}

impl Session {
    /// Report an event to Lua at the end of the turn (`events_take`).
    pub fn emit(&mut self, event: crate::events::KernelEvent) {
        self.events.push(event.into());
    }

    pub fn new(opts: &BackendOptions, registry: Registry) -> Result<Self> {
        let (handle, stream) = start_engine(opts)?;
        let project = Project::default();
        let mut session = Self {
            synced: project.clone(),
            named: (project.tracks.clone(), project.master.clone()),
            undo: undo::Undo::new(&project),
            project,
            dirty: false,
            next_id: MASTER_ID + 1,
            engine: engine::EngineLink { handle, map: Mapper::new(), stream, threads: 0, sleep: true, backend: opts.clone() },
            registry,
            clip_kinds: BTreeSet::new(),
            audio: AudioCache::default(),
            trims: 0,
            live: LiveDevices::new(),
            transport: Transport::default(),
            play: Default::default(),
            path: None,
            screen: None,
            events: Vec::new(),
            warnings: Vec::new(),
            rec: Recorder::default(),
            midi: Default::default(),
            writing: write::Writing::default(),
            device_file: None,
            render_job: None,
            state_given: Default::default(),
            loads: Default::default(),
            open_opts: Default::default(),
            watch: Default::default(),
            files_watch: Default::default(),
            files_there: Default::default(),
            read_ahead_at: Instant::now(),
            sources: Default::default(),
            shelf: None,
            audition: Default::default(),
        };
        session.warnings.extend(session.engine.stream.info.warning.clone());
        session.send_pool();
        session.send_transport();
        session.connect_midi();
        Ok(session)
    }

    // Rendering to a file: session/render.rs.
}

/// Noise of one step's size, added before a sample is cut down to 16 or 24
/// bits, so that what is cut off becomes a steady hiss far below the music
/// instead of distortion that follows it. The same noise every time, so that
/// a render repeats exactly.
struct Dither {
    step: f32,
    state: u32,
}

impl Dither {
    fn new(bits: u16) -> Self {
        Self {
            step: if bits < 32 {
                1.0 / (1i64 << (bits - 1)) as f32
            } else {
                0.0
            },
            state: 0x9e37_79b9,
        }
    }

    fn uniform(&mut self) -> f32 {
        // xorshift32
        self.state ^= self.state << 13;
        self.state ^= self.state >> 17;
        self.state ^= self.state << 5;
        self.state as f32 / u32::MAX as f32
    }

    /// Add triangular noise spanning one step each way.
    fn apply(&mut self, sample: f32) -> f32 {
        if self.step == 0.0 {
            return sample;
        }
        sample + (self.uniform() - self.uniform()) * self.step
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        // Finish the files of a take still being recorded.
        self.stop();
    }
}

/// Where recordings go while the project has no file.
fn scratch_media_dir() -> PathBuf {
    let base = paw_proto::dirs::data().unwrap_or_else(std::env::temp_dir);
    base.join("paw").join("recordings")
}

/// A name made of letters, digits, `-` and `_`, for use in a file name.
fn file_safe(name: &str) -> String {
    let safe: String = name
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect();
    if safe.is_empty() {
        "track".into()
    } else {
        safe
    }
}

/// `dir/stem.wav`, or `dir/stem-2.wav` and so on if that is taken.
fn unique_path(dir: &Path, stem: &str) -> PathBuf {
    let mut path = dir.join(format!("{stem}.wav"));
    let mut n = 2;
    while path.exists() {
        path = dir.join(format!("{stem}-{n}.wav"));
        n += 1;
    }
    path
}

/// More threads than this are not started, whatever is asked for.
const MAX_THREADS: usize = 64;

/// Threads to process on when no number is asked for: one per core, counting
/// cores and not the hardware threads on them, and no more than 16.
fn default_threads() -> usize {
    static THREADS: std::sync::OnceLock<usize> = std::sync::OnceLock::new();
    *THREADS.get_or_init(|| {
        let usable = std::thread::available_parallelism().map_or(1, |n| n.get());
        physical_cores().unwrap_or(usable).min(usable).clamp(1, 16)
    })
}

/// How many cores the machine has, where the system says.
fn physical_cores() -> Option<usize> {
    let mut cores = std::collections::HashSet::new();
    for entry in std::fs::read_dir("/sys/devices/system/cpu").ok()?.flatten() {
        let topology = entry.path().join("topology");
        let read = |name: &str| std::fs::read_to_string(topology.join(name)).ok();
        if let (Some(package), Some(core)) = (read("physical_package_id"), read("core_id")) {
            cores.insert((package, core));
        }
    }
    (!cores.is_empty()).then_some(cores.len())
}

fn start_engine(opts: &BackendOptions) -> Result<(EngineHandle, Stream)> {
    if let Some(rate) = opts.sample_rate {
        check_sample_rate(rate)?;
    }
    if let Some(size) = opts.buffer_size
        && !(16..=16384).contains(&size)
    {
        bail!("a buffer of {size} frames is not supported: use 16 to 16384");
    }
    let opened = backend::open(opts)?;
    check_sample_rate(opened.sample_rate())?;
    let (engine, handle) = Engine::new(opened.sample_rate() as f64);
    let stream = opened.start(engine)?;
    Ok((handle, stream))
}

/// Processing times per engine callback, in milliseconds.
#[derive(Clone, Copy, Debug, Serialize)]
pub struct BlockTimes {
    pub count: u64,
    pub mean: f64,
    pub max: f64,
    pub p50: f64,
    pub p99: f64,
    pub p999: f64,
    /// The time one callback of the average size may take in real time.
    pub budget: f64,
}

impl BlockTimes {
    pub fn new(s: &paw_engine::BlockSummary, sample_rate: u32) -> Self {
        let ms = |ns: f64| ns / 1e6;
        let per_call = |n: u64| if s.count > 0 { n as f64 / s.count as f64 } else { 0.0 };
        Self {
            count: s.count,
            mean: ms(per_call(s.total_ns)),
            max: ms(s.max_ns as f64),
            p50: ms(s.quantile_ns(0.5)),
            p99: ms(s.quantile_ns(0.99)),
            p999: ms(s.quantile_ns(0.999)),
            budget: per_call(s.frames) * 1000.0 / sample_rate.max(1) as f64,
        }
    }
}

/// [`BlockTimes`] as JSON.
fn block_json(s: &paw_engine::BlockSummary, sample_rate: u32) -> Value {
    serde_json::to_value(BlockTimes::new(s, sample_rate)).unwrap_or(Value::Null)
}

fn param_json(p: &ParamInfo) -> Value {
    json!({
        "key": p.key, "id": p.stable_id(), "name": p.name, "group": p.group,
        "min": p.min, "max": p.max, "default": p.default, "unit": p.unit, "choices": p.choices,
        "kind": p.kind(), "steps": p.steps, "automatable": p.automatable,
        "read_only": p.read_only, "per_note": p.per_note,
    })
}

/// Where a parameter is in a device's list: by key, else by the device's
/// own id for it, else by its shown name (any case).
fn find_param(params: &[ParamInfo], name: &str) -> Option<usize> {
    params
        .iter()
        .position(|p| p.key == name)
        .or_else(|| params.iter().position(|p| !p.id.is_empty() && p.id == name))
        .or_else(|| params.iter().position(|p| p.name.eq_ignore_ascii_case(name)))
}

/// Sample rates an engine or a render can run at.
pub fn check_sample_rate(rate: u32) -> Result<()> {
    if !(8000..=384_000).contains(&rate) {
        bail!("a sample rate of {rate} Hz is not supported: use 8000 to 384000");
    }
    Ok(())
}

/// `value`, or an error naming `what` if it is NaN or infinite.
fn finite(what: &str, value: f64) -> Result<f64> {
    if value.is_finite() {
        Ok(value)
    } else {
        bail!("{what} must be a finite number, not {value}")
    }
}

fn sorted(mut notes: Vec<Note>) -> Vec<Note> {
    notes.sort_by(|a, b| a.start.total_cmp(&b.start).then(a.pitch.cmp(&b.pitch)));
    notes
}

/// Give the plugins of an engine that is about to render offline a moment
/// to get ready. Many prepare in the background what a change of settings
/// needs (a delay line, an impulse response, samples) and stay silent until
/// it is there: fine when playing live, but an offline render would be over
/// before they had begun. So run a few silent blocks, with the transport
/// stopped, with short waits in between.
pub(crate) fn settle_plugins(engine: &mut Engine, live: &LiveDevices) {
    if !live.values().any(|device| device.controller.is_some()) {
        return;
    }
    let mut scratch = vec![0.0f32; 2 * paw_engine::MAX_BLOCK];
    let (left, right) = scratch.split_at_mut(paw_engine::MAX_BLOCK);
    for _ in 0..4 {
        engine.process(left, right);
        std::thread::sleep(Duration::from_millis(12));
    }
    engine.process(left, right);
}

fn check_controls(mut controls: Vec<Control>) -> Result<Vec<Control>> {
    if let Some((control, problem)) = controls
        .iter()
        .find_map(|c| c.problem().map(|problem| (c, problem)))
    {
        bail!("a controller move cannot be {control:?}: {problem}");
    }
    controls.sort_by(|a, b| a.start.total_cmp(&b.start));
    Ok(controls)
}

/// A fade is a number of beats from 0 up.
fn check_fade(beats: f64) -> Result<f64> {
    if !beats.is_finite() || beats < 0.0 {
        bail!("a fade is a number of beats from 0 up");
    }
    Ok(beats)
}

/// A warp marker as a clip's description gives it: with the beat of the
/// song it is at.
#[derive(Serialize)]
pub struct WarpView {
    source: f64,
    target: f64,
    beat: f64,
}

/// A clip as `paw.api.clip_get` and `clip_list` give it: its fields without
/// its notes or its sound, made straight into Lua with no JSON between.
/// What does not apply to its kind is left out.
#[derive(Serialize)]
pub struct ClipView<'a> {
    id: Id,
    name: &'a str,
    start: f64,
    length: f64,
    muted: bool,
    kind: &'a str,
    track: Id,
    meta: &'a Map<String, Value>,
    #[serde(rename = "loop")]
    looped: bool,
    loop_start: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    loop_length: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    cue: Option<bool>,
    // A MIDI clip's.
    #[serde(skip_serializing_if = "Option::is_none")]
    source: Option<&'a Path>,
    #[serde(skip_serializing_if = "Option::is_none")]
    offline: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    origin: Option<&'a Path>,
    #[serde(skip_serializing_if = "Option::is_none")]
    note_count: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    control_count: Option<usize>,
    /// Changes whenever the notes do ([`crate::model::Notes::stamp`]).
    #[serde(skip_serializing_if = "Option::is_none")]
    stamp: Option<u64>,
    /// The same for the controller moves.
    #[serde(skip_serializing_if = "Option::is_none")]
    control_stamp: Option<u64>,
    // An audio clip's.
    #[serde(skip_serializing_if = "Option::is_none")]
    edits: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    file: Option<&'a Path>,
    #[serde(skip_serializing_if = "Option::is_none")]
    offset: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    gain: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    fade_in: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    fade_out: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    timebase: Option<Timebase>,
    #[serde(skip_serializing_if = "Option::is_none")]
    stretch: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pitch: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    stretch_mode: Option<StretchMode>,
    #[serde(skip_serializing_if = "Option::is_none")]
    source_tempo: Option<f64>,
    // How its stretch stands (`Session::note_stretching`).
    #[serde(skip_serializing_if = "Option::is_none")]
    stretching: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    made: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    preview: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    bent: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    formants: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    warp: Option<Vec<WarpView>>,
    // A nest clip's: the subproject it places and what it plays of it.
    #[serde(skip_serializing_if = "Option::is_none")]
    nest: Option<crate::model::NestId>,
    #[serde(skip_serializing_if = "Option::is_none")]
    play: Option<NestPlay>,
}

/// A hash of a clip's controller moves, as a number Lua holds exactly.
fn control_stamp(controls: &[crate::model::Control]) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut hash = std::collections::hash_map::DefaultHasher::new();
    for control in controls {
        control.start.to_bits().hash(&mut hash);
        control.value.to_bits().hash(&mut hash);
        control.key.hash(&mut hash);
        format!("{:?}", control.what).hash(&mut hash);
    }
    hash.finish() >> 11
}

fn clip_json<'a>(c: &'a Clip, track: Id, files: &file_check::FileCheck) -> ClipView<'a> {
    let mut v = ClipView {
        id: c.id,
        name: &c.name,
        start: c.start,
        length: c.length,
        muted: c.muted,
        kind: c.content.kind(),
        track,
        meta: &c.meta,
        looped: c.looped,
        loop_start: c.loop_start,
        loop_length: c.loop_length,
        cue: None,
        source: None,
        offline: None,
        origin: None,
        note_count: None,
        control_count: None,
        stamp: None,
        control_stamp: None,
        edits: None,
        file: None,
        offset: None,
        gain: None,
        fade_in: None,
        fade_out: None,
        timebase: None,
        stretch: None,
        pitch: None,
        stretch_mode: None,
        source_tempo: None,
        stretching: None,
        made: None,
        preview: None,
        bent: None,
        formants: None,
        warp: None,
        nest: None,
        play: None,
    };
    match &c.content {
        ClipContent::Midi { notes, controls } => {
            if let Some(source) = &c.source {
                v.source = Some(source);
                if !files.is_file(source) {
                    v.offline = Some(true);
                }
            }
            v.origin = c.origin.as_deref();
            v.note_count = Some(notes.len());
            v.control_count = Some(controls.len());
            v.stamp = Some(notes.stamp());
            v.control_stamp = Some(control_stamp(controls));
        }
        ClipContent::Audio { file, offset, gain, edits } => {
            if !edits.is_empty() {
                v.edits = Some(edits.len());
            }
            // Its file is not there: the clip is silent until it is relinked.
            if !files.is_file(file) {
                v.offline = Some(true);
            }
            v.file = Some(file);
            v.offset = Some(*offset);
            v.gain = Some(*gain);
            v.fade_in = Some(c.fade_in);
            v.fade_out = Some(c.fade_out);
            v.timebase = Some(c.timebase.unwrap_or_default());
            v.stretch = Some(c.stretch);
            v.pitch = Some(c.pitch);
            v.stretch_mode = Some(c.stretch_mode);
            v.source_tempo = c.source_tempo;
        }
        ClipContent::Nest { nest, offset, play } => {
            v.nest = Some(*nest);
            v.offset = Some(*offset);
            v.play = Some(*play);
        }
        ClipContent::Custom(_) => {}
    }
    v
}
