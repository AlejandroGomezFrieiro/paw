//! The session: the project, its undo history and the running engine.
//!
//! Every edit changes [`Session::project`] and marks it dirty. [`Session::flush`]
//! then diffs it against what the engine last saw and sends the difference.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow, bail};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use paw_engine::backend::{self, BackendOptions, Stream, StreamInfo};
use paw_engine::midi::{MidiInputs, MidiSink, MidiTarget};
use paw_engine::record::{self, AudioCapture, MidiCapture, Take, TakeShared};
use paw_engine::{Engine, EngineHandle, EventKind, Msg, ParamInfo, Pool, Registry};
use rtrb::RingBuffer;
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use serde_json::{Map, Value, json};

use crate::history::{self, History};
use crate::model::{
    Clip, ClipContent, Control, DeviceInst, Id, Lane, LaneState, MASTER_ID, MidiInput, Note, NoteAttr, Notes, Project, Segment,
    Send, Shape, StretchMode, Target, Timebase, Track, WarpMarker, parse_input,
};
use crate::sync::{AudioCache, LiveDevices, Mapper, ModelEvent, SyncCtx, sync};

mod audition;
mod clipops;
mod encode;
mod files_watch;
pub mod folder;
mod keep;
pub mod cues;
mod loading;
pub mod media;
mod midi_out;
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
mod write;

/// How many steps the undo history keeps until told otherwise
/// (`paw.opt.undo_steps`).
const UNDO_LIMIT: usize = 1000;
/// And at most about this many bytes of what its steps changed
/// (`paw.opt.undo_memory`): a step that changes one note of a big clip keeps
/// a copy of the run of notes it changed (`model::Notes`).
const UNDO_BYTES: usize = 1 << 30;

/// An undo tree for a project, from `project` on, keeping at most `limit`
/// steps and about `bytes` bytes.
fn new_history(project: Project, (limit, bytes): (usize, usize)) -> History<Project> {
    History::new(project, history::now(), limit).weigh_with(Project::weight_over, bytes)
}
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
    /// Position in the track list, counting from 1. Appended when absent.
    pub index: Option<usize>,
    pub volume: Option<f64>,
    pub pan: Option<f64>,
    pub output: Option<Id>,
    pub color: Option<String>,
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

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct ClipOpts {
    /// `midi` or `audio`. Inferred from `file` when absent.
    pub kind: Option<String>,
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
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LaneOpts {
    /// `volume`, `pan`, `param` or `state`.
    pub target: String,
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
    /// The project at the last undo step.
    checkpoint: Project,
    /// Every undo step, as a tree: see [`crate::history`] and `session/undo.rs`.
    history: History<Project>,
    dirty: bool,
    touched: bool,
    /// What the open undo step is made of, to tell a control being moved
    /// (a fader dragged, a knob turned on a controller) from other edits:
    /// its moves become one undo step, not one each.
    sweep: Sweep,
    /// The control the last undo step moved, when it did nothing else.
    last_sweep: Option<(String, Instant, history::StateId)>,
    /// The next flush reports a state put back (undo, redo, a file opened)
    /// rather than an edit: its events carry `restored = true`.
    restoring: bool,
    /// The undo state the edits of this turn join instead of making a step
    /// of their own, set by `undo_join`.
    join: Option<history::StateId>,
    /// Counts every change to the project, undo and redo included.
    edits: u64,
    next_id: Id,

    handle: EngineHandle,
    map: Mapper,
    stream: Stream,
    pub registry: Registry,
    audio: AudioCache,
    /// Checkpoints counted for [`Session::trim_audio_now_and_then`].
    trims: u32,
    /// Parameters and controllers of the devices the engine is running.
    live: LiveDevices,

    pub transport: Transport,
    playing: bool,
    /// Beats of the count-in last asked of the engine: what is still to be
    /// counted until the engine says otherwise.
    count_sent: u32,
    seeks: u32,
    seek_target: f64,
    pub path: Option<PathBuf>,
    /// The screen the project file keeps (`ProjectFile::screen`).
    pub screen: Option<Value>,
    /// Change notifications waiting to be delivered to Lua.
    pub events: Vec<ModelEvent>,
    pub warnings: Vec<String>,

    take: Option<Recording>,
    takes: u32,
    /// MIDI input ports, open while a real audio device is.
    midi: Option<MidiInputs>,
    midi_sink: MidiSink,
    /// Whether moving a fader or a parameter while playing writes automation,
    /// and what is being written.
    write: bool,
    latched: Vec<write::Latch>,
    /// Milliseconds to move recordings earlier by, on top of what the audio
    /// system reports: found by recording the metronome through a loop-back.
    record_offset: f64,
    /// The ports to open, by id or name, or `None` for all of them.
    midi_select: Option<Vec<String>>,
    /// Ports of our own for other programs to send MIDI to, by name.
    midi_own: Vec<String>,
    midi_without_audio: bool,
    /// MIDI output, open when MIDI input is, and ports of our own for other
    /// programs to read from: session/midi_out.rs.
    midi_out: Option<paw_engine::midi_out::MidiOutputs>,
    midi_out_own: Vec<String>,
    /// Threads to process tracks on, or 0 for as many as the machine has cores.
    threads: usize,
    /// Devices at rest sleep through silent blocks (`paw.opt.device_sleep`).
    sleep: bool,
    /// What the engine was last started with, to start it again with a
    /// device changed.
    backend: BackendOptions,
    /// Where the devices chosen with [`audio_use`](Self::audio_use) are
    /// remembered, or `None` not to remember them.
    pub device_file: Option<PathBuf>,
    /// MIDI ports to list on the null backend, which opens none, so that
    /// scripts and tests can choose among them.
    test_ports: Vec<String>,
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
    /// When files played from the disk were last read ahead of the playhead.
    read_ahead_at: Instant,
    /// The project put aside while a scratch one is open: see
    /// [`Session::project_shelve`].
    shelf: Option<Shelf>,
    /// Edits that may yet be thrown away, and the sound file heard on its
    /// own, with its level in dB: see `session/audition.rs`.
    trial: Option<audition::Trial>,
    preview: Option<audition::Previewing>,
    preview_ids: u32,
    preview_level: f64,
}

/// An open project, with its undo history, put aside whole.
struct Shelf {
    project: Project,
    history: History<Project>,
    touched: bool,
    transport: Transport,
    position: f64,
    path: Option<PathBuf>,
}

/// The rest of what [`Session::audio_use`] can change: the sound system
/// and the sample rate (0 for the device's own).
#[derive(Default)]
pub struct AudioChoice {
    pub backend: Option<String>,
    pub rate: Option<u32>,
}

/// The edits of the open undo step: how many, how many of them moved a
/// control, and which control if they all moved the same one.
#[derive(Default)]
struct Sweep {
    edits: u32,
    moves: u32,
    key: Option<String>,
    mixed: bool,
}

/// Moves of one control closer together than this are one undo step.
const SWEEP_GAP: Duration = Duration::from_millis(1000);

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
    pub fn new(opts: &BackendOptions, registry: Registry) -> Result<Self> {
        let (handle, stream) = start_engine(opts)?;
        let project = Project::default();
        let mut session = Self {
            synced: project.clone(),
            named: (project.tracks.clone(), project.master.clone()),
            checkpoint: project.clone(),
            history: new_history(project.clone(), (UNDO_LIMIT, UNDO_BYTES)),
            project,
            dirty: false,
            touched: false,
            sweep: Sweep::default(),
            last_sweep: None,
            restoring: false,
            join: None,
            edits: 0,
            next_id: MASTER_ID + 1,
            handle,
            map: Mapper::new(),
            stream,
            registry,
            audio: AudioCache::default(),
            trims: 0,
            live: LiveDevices::new(),
            transport: Transport::default(),
            playing: false,
            count_sent: 0,
            seeks: 0,
            seek_target: 0.0,
            path: None,
            screen: None,
            events: Vec::new(),
            warnings: Vec::new(),
            take: None,
            takes: 0,
            midi: None,
            midi_sink: Arc::new(Mutex::new(MidiTarget::default())),
            record_offset: 0.0,
            write: false,
            latched: Vec::new(),
            midi_select: None,
            midi_own: Vec::new(),
            midi_without_audio: false,
            midi_out: None,
            midi_out_own: Vec::new(),
            threads: 0,
            sleep: true,
            backend: opts.clone(),
            device_file: None,
            test_ports: Vec::new(),
            render_job: None,
            state_given: Default::default(),
            loads: Default::default(),
            open_opts: Default::default(),
            watch: Default::default(),
            files_watch: Default::default(),
            read_ahead_at: Instant::now(),
            shelf: None,
            trial: None,
            preview: None,
            preview_ids: 0,
            preview_level: -12.0,
        };
        session.warnings.extend(session.stream.info.warning.clone());
        session.send_pool();
        session.send_transport();
        session.connect_midi();
        Ok(session)
    }

    // --- editing -----------------------------------------------------------

    /// Change the project. The engine catches up at the next [`flush`](Self::flush).
    ///
    /// An edit that fails must leave the project as it found it (check
    /// first, then change). It then makes no undo step and does not mark the
    /// project modified, so that the next undo undoes the last real edit.
    pub fn edit<R>(&mut self, f: impl FnOnce(&mut Project) -> Result<R>) -> Result<R> {
        let result = self.edit_named(f);
        if result.is_ok() {
            // A note is named as it is made, so that it can be addressed at once.
            self.project.name_notes_since(&self.named.0, &self.named.1);
            self.named = (self.project.tracks.clone(), self.project.master.clone());
        }
        result
    }

    /// An edit that leaves every note with an id of its own, so that nothing
    /// need be named after it: one note added, changed or removed, which on
    /// a clip of many thousands would otherwise cost a look at all of them.
    pub fn edit_named<R>(&mut self, f: impl FnOnce(&mut Project) -> Result<R>) -> Result<R> {
        let result = f(&mut self.project);
        if result.is_ok() {
            self.history.edited();
            self.dirty = true;
            self.touched = true;
            self.edits += 1;
            self.sweep.edits += 1;
        }
        result
    }

    /// Note that the edit just made moved a control: `key` names it.
    fn swept(&mut self, key: String) {
        self.sweep.moves += 1;
        match &self.sweep.key {
            None => self.sweep.key = Some(key),
            Some(known) if *known != key => self.sweep.mixed = true,
            Some(_) => {}
        }
    }

    fn new_id(&mut self) -> Id {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    /// Send pending edits to the engine and queue their change events.
    pub fn flush(&mut self) {
        self.handle.collect_garbage();
        self.drain_take();
        if !self.dirty {
            return;
        }
        self.dirty = false;
        // Whatever was added, it has a name before anyone hears it.
        self.project.name_notes(&self.synced);
        let mut ctx = SyncCtx {
            registry: &self.registry,
            audio: &mut self.audio,
            live: &mut self.live,
            sample_rate: self.handle.sample_rate as f32,
            warnings: &mut self.warnings,
            offline: false,
        };
        let handle = &mut self.handle;
        let mut send = |msg| handle.send(msg);
        let before = self.events.len();
        sync(
            &self.synced,
            &self.project,
            &mut self.map,
            &mut ctx,
            &mut send,
            &mut self.events,
        );
        self.synced = self.project.clone();
        self.remember_for_panic();
        self.note_deferred();
        // Whoever answers edits with edits of their own (in the same undo
        // step) leaves alone a state that was put back: it holds the answer.
        if std::mem::take(&mut self.restoring) {
            for (_, payload) in &mut self.events[before..] {
                if let Value::Object(map) = payload {
                    map.insert("restored".into(), Value::Bool(true));
                }
            }
        }
    }

    /// Close the current undo step, if anything changed since the last one.
    pub fn checkpoint(&mut self) {
        // A trial's edits are one step, made when it ends.
        if self.trial.is_some() {
            return;
        }
        let sweep = std::mem::take(&mut self.sweep);
        let join = self.join.take();
        if !self.touched {
            self.history.clear_labels();
            return;
        }
        self.touched = false;
        self.own_edited_references();
        // An edit not yet played has notes not yet named: the step keeps them named.
        if self.project.name_notes(&self.checkpoint) {
            self.dirty = true;
        }
        if join.is_some_and(|state| state == self.history.current() && self.history.can_extend()) {
            // Asked for: what this turn did belongs to the step before.
            self.checkpoint = self.project.clone();
            self.history.amend(self.checkpoint.clone(), history::now());
            self.last_sweep = None;
            return;
        }
        // The one control this step moved, if that is all it did.
        let moved = sweep
            .key
            .filter(|_| sweep.moves == sweep.edits && !sweep.mixed);
        if let (Some(key), Some((last, at, state))) = (&moved, &self.last_sweep)
            && key == last
            && at.elapsed() < SWEEP_GAP
            && *state == self.history.current()
            && self.history.can_amend()
        {
            // Still the same move: the step made for it holds where it got to.
            let state = *state;
            self.checkpoint = self.project.clone();
            self.history.amend(self.checkpoint.clone(), history::now());
            self.last_sweep = Some((key.clone(), Instant::now(), state));
            return;
        }
        let previous = std::mem::replace(&mut self.checkpoint, self.project.clone());
        self.history.set_current_snapshot(previous);
        let state = self.history.push(self.checkpoint.clone(), history::now());
        if self.history.newly_pruned() {
            self.warnings.push(format!(
                "the undo history keeps {} steps and {} MB at most: its oldest steps are let go",
                self.history.limit(),
                self.history.byte_limit() >> 20
            ));
        }
        self.last_sweep = moved.map(|key| (key, Instant::now(), state));
        self.trim_audio_now_and_then();
    }

    /// A clip that refers to a file outside the project and whose notes
    /// this step changed is now the project's own, in the same step: it
    /// keeps where it came from (`origin`). Said once, as `clip.copied`.
    fn own_edited_references(&mut self) {
        self.own_edited_clips();
        self.own_edited_tracks();
    }

    /// A track read from a folder outside the project, or a chain read from
    /// a file outside it, that this step changed is now the project's own,
    /// as a clip is (`own_edited_clips`): `track.copied`, `chain.copied`.
    /// A track takes its clips from that folder with it.
    fn own_edited_tracks(&mut self) {
        let before: HashMap<Id, &Arc<Track>> = self
            .checkpoint
            .tracks
            .iter()
            .filter(|t| t.source.is_some() || t.chain_source.is_some())
            .map(|t| (t.id, t))
            .collect();
        if before.is_empty() {
            return;
        }
        // A plugin's state is read again at each save: that is not an edit.
        let stateless = |devices: &[Arc<DeviceInst>]| -> Vec<Value> {
            devices
                .iter()
                .map(|d| {
                    let mut v = serde_json::to_value(&**d).unwrap_or_default();
                    v.as_object_mut().map(|o| o.remove("state"));
                    v
                })
                .collect()
        };
        let whole = |t: &Track| -> Value {
            let mut v = serde_json::to_value(t).unwrap_or_default();
            if let Some(o) = v.as_object_mut() {
                o.insert("devices".into(), Value::Array(stateless(&t.devices)));
            }
            v
        };
        let (mut tracks, mut chains) = (Vec::new(), Vec::new());
        for t in &self.project.tracks {
            let Some(old) = before.get(&t.id) else {
                continue;
            };
            if Arc::ptr_eq(old, t) {
                continue;
            }
            if t.source.is_some() && t.source == old.source && whole(old) != whole(t) {
                tracks.push(t.id);
            } else if t.chain_source.is_some()
                && t.chain_source == old.chain_source
                && stateless(&old.devices) != stateless(&t.devices)
            {
                chains.push(t.id);
            }
        }
        for id in tracks {
            let Some(track) = self.project.track_mut(id) else {
                continue;
            };
            track.origin = track.source.take();
            let folder = track.origin.clone().unwrap_or_default();
            for clip in track.clips.iter_mut().chain(track.cues.iter_mut()) {
                if clip.source.as_ref().is_some_and(|s| s.starts_with(&folder)) {
                    let clip = Arc::make_mut(clip);
                    clip.origin = clip.source.take();
                }
            }
            self.events.push((
                "track.copied".into(),
                json!({ "track": id, "name": track.name, "origin": track.origin }),
            ));
        }
        for id in chains {
            let Some(track) = self.project.track_mut(id) else {
                continue;
            };
            track.chain_origin = track.chain_source.take();
            self.events.push((
                "chain.copied".into(),
                json!({ "track": id, "name": track.name, "origin": track.chain_origin }),
            ));
        }
    }

    fn own_edited_clips(&mut self) {
        // Only the clips of the tracks the step changed, and of those only
        // the stretch it changed, can have been edited.
        let (old, new) = (&self.checkpoint, &self.project);
        let mut after = crate::model::ById::new(&new.tracks, |t: &Arc<Track>| t.id);
        let mut before: HashMap<Id, &Arc<Clip>> = HashMap::new();
        let mut changed: Vec<(&Arc<Track>, Option<&Arc<Track>>)> = Vec::new();
        for track in old.all_tracks() {
            let now = if track.id == MASTER_ID { Some(&new.master) } else { after.find(track.id) };
            if now.is_some_and(|n| Arc::ptr_eq(n, track)) {
                continue;
            }
            let span = match now {
                Some(now) => now.clips.changed(&track.clips).0,
                None => 0..track.clips.len(),
            };
            let clips = track.clips.range(span).chain(&track.cues);
            before.extend(clips.filter(|c| c.source.is_some()).map(|c| (c.id, c)));
            if let Some(now) = now {
                changed.push((now, Some(track)));
            }
        }
        if before.is_empty() {
            return;
        }
        let mut was = crate::model::ById::new(&old.tracks, |t: &Arc<Track>| t.id);
        for track in &new.tracks {
            if was.find(track.id).is_none() {
                changed.push((track, None));
            }
        }
        let same = |a: &Clip, b: &Clip| match (&a.content, &b.content) {
            (
                ClipContent::Midi { notes, controls },
                ClipContent::Midi {
                    notes: n2,
                    controls: c2,
                },
            ) => notes == n2 && controls == c2,
            _ => true,
        };
        let mut owned = Vec::new();
        for (track, was) in changed {
            let span = match was {
                Some(was) => track.clips.changed(&was.clips).1,
                None => 0..track.clips.len(),
            };
            for clip in track.clips.range(span).chain(&track.cues) {
                if let Some(old) = before.get(&clip.id)
                    && clip.source.is_some()
                    && clip.source == old.source
                    && !Arc::ptr_eq(old, clip)
                    && !same(old, clip)
                {
                    owned.push(clip.id);
                }
            }
        }
        for id in owned {
            let Some(clip) = self.project.clip_mut(id) else {
                continue;
            };
            clip.origin = clip.source.take();
            self.events.push((
                "clip.copied".into(),
                json!({ "clip": id, "name": clip.name, "origin": clip.origin }),
            ));
        }
    }

    /// Make every clip that refers to a file outside the project the
    /// project's own (`:collect`): the next save writes their files into
    /// its folder. Returns how many.
    pub fn clip_collect(&mut self) -> usize {
        let ids: Vec<Id> = self
            .project
            .all_tracks()
            .flat_map(|t| t.clips.iter().chain(&t.cues))
            .filter(|c| c.source.as_ref().is_some_and(|s| s.is_file()))
            .map(|c| c.id)
            .collect();
        for id in &ids {
            if let Some(clip) = self.project.clip_mut(*id) {
                clip.origin = clip.source.take();
            }
        }
        if !ids.is_empty() {
            self.touched = true;
            self.dirty = true;
        }
        ids.len()
    }

    /// Make every track read from a folder outside the project, and every
    /// chain read from a file outside it, the project's own (`:collect`):
    /// the next save writes them into its folder. Returns how many tracks
    /// and how many chains. Run before `clip_collect`, which then takes
    /// such a track's clips.
    pub fn track_collect(&mut self) -> (usize, usize) {
        let (mut tracks, mut chains) = (0, 0);
        let ids: Vec<Id> = self.project.tracks.iter().map(|t| t.id).collect();
        for id in ids {
            let Some(t) = self.project.track(id) else {
                continue;
            };
            if t.source.is_none() && t.chain_source.is_none() {
                continue;
            }
            let Some(track) = self.project.track_mut(id) else {
                continue;
            };
            if track.source.is_some() {
                track.origin = track.source.take();
                tracks += 1;
            }
            if track.chain_source.is_some() {
                track.chain_origin = track.chain_source.take();
                chains += 1;
            }
        }
        if tracks + chains > 0 {
            self.touched = true;
            self.dirty = true;
        }
        (tracks, chains)
    }

    pub fn undo(&mut self) -> bool {
        self.move_in_history(History::undo).is_some()
    }

    pub fn redo(&mut self) -> bool {
        self.move_in_history(History::redo).is_some()
    }

    // --- project -----------------------------------------------------------

    pub fn project_view(&self) -> Value {
        let p = &self.project;
        json!({
            "name": p.name, "tempo": p.tempo, "sig_num": p.sig_num, "sig_den": p.sig_den,
            "tempo_ramp": p.tempo_ramp, "tempo_changes": p.tempo_changes, "sig_changes": p.sig_changes,
            "key": p.key, "path": self.path, "length": p.end(), "meta": p.meta,
            "modified": self.touched || !self.history.at_saved(),
            // Goes up with every change: compare two readings to see whether
            // something in between edited the project.
            "edits": self.edits,
        })
    }

    /// One entry of [`project_view`](Self::project_view), made alone: its
    /// `length` looks at every clip, and its `meta` can be large.
    pub fn project_field(&self, key: &str) -> Value {
        let p = &self.project;
        match key {
            "edits" => json!(self.edits),
            "name" => json!(p.name),
            "tempo" => json!(p.tempo),
            "sig_num" => json!(p.sig_num),
            "sig_den" => json!(p.sig_den),
            "key" => json!(p.key),
            "path" => json!(self.path),
            "modified" => json!(self.touched || !self.history.at_saved()),
            _ => self.project_view().get(key).cloned().unwrap_or(Value::Null),
        }
    }

    pub fn project_set(&mut self, key: &str, value: Value) -> Result<()> {
        if holds(&Ok(self.project_view()), key, &value) {
            return Ok(());
        }
        self.edit(|p| {
            match key {
                "name" => p.name = de(key, value)?,
                "tempo" => {
                    let tempo: f64 = de(key, value)?;
                    if !(1.0..=999.0).contains(&tempo) {
                        bail!("tempo must be between 1 and 999");
                    }
                    let mut map = (**p.tempo_map()).clone();
                    map.set_first_tempo(tempo);
                    p.retime(map);
                }
                "sig_num" | "sig_den" => {
                    let n = de::<u32>(key, value)?.clamp(1, 64);
                    // A beat is a whole note halved some times: 3/3 has no note to count.
                    if key == "sig_den" && !n.is_power_of_two() {
                        bail!("a time signature's lower number is 1, 2, 4, 8, 16, 32 or 64, not {n}");
                    }
                    let (num, den) = if key == "sig_num" {
                        (n, p.sig_den)
                    } else {
                        (p.sig_num, n)
                    };
                    let mut map = (**p.tempo_map()).clone();
                    map.set_first_signature(num, den);
                    p.set_tempo_map(map);
                }
                "key" => p.key = de(key, value)?,
                "meta" => p.meta = de_meta(key, value)?,
                _ => bail!("project has no settable field `{key}`"),
            }
            Ok(())
        })
    }

    /// Put the open project aside, history and all, and open an empty
    /// scratch project in its place, for something that needs tracks and
    /// clips of its own (a hardware check) without touching the user's work.
    /// [`project_unshelve`](Self::project_unshelve) puts it back exactly as
    /// it was, undo tree included.
    pub fn project_shelve(&mut self) -> Result<()> {
        if self.shelf.is_some() {
            bail!("a project is put aside already");
        }
        self.capture_states();
        self.checkpoint();
        self.history.set_current_snapshot(self.checkpoint.clone());
        let fresh = Project::default();
        let limits = (self.history.limit(), self.history.byte_limit());
        let history = std::mem::replace(&mut self.history, new_history(fresh.clone(), limits));
        self.shelf = Some(Shelf {
            project: self.project.clone(),
            history,
            touched: self.touched,
            transport: self.transport.clone(),
            position: self.position(),
            path: self.path.clone(),
        });
        self.replace_project(fresh, Transport::default(), None);
        Ok(())
    }

    /// Whether a project is put aside by [`project_shelve`](Self::project_shelve).
    pub fn project_shelved(&self) -> bool {
        self.shelf.is_some()
    }

    /// Close the scratch project and bring back the one put aside.
    pub fn project_unshelve(&mut self) -> Result<()> {
        let Some(shelf) = self.shelf.take() else {
            bail!("no project is put aside");
        };
        let limits = (self.history.limit(), self.history.byte_limit());
        self.history = shelf.history;
        self.history.set_limits(limits.0, limits.1);
        self.put_project(shelf.project, shelf.transport, shelf.path, Some(shelf.touched));
        self.seek(shelf.position);
        Ok(())
    }

    /// Replace the project, dropping the undo history.
    fn replace_project(
        &mut self,
        project: Project,
        transport: Transport,
        path: Option<PathBuf>,
    ) {
        self.put_project(project, transport, path, None);
    }

    /// Make `project` the open one. With `touched`, the undo history is
    /// already in place and kept; without, it starts again from the project.
    fn put_project(
        &mut self,
        mut project: Project,
        transport: Transport,
        path: Option<PathBuf>,
        touched: Option<bool>,
    ) {
        project.refresh_tempo();
        self.apply_open_opts(&mut project);
        // Another project: a trial of this one's is over with it.
        self.trial = None;
        self.stop();
        self.seek(0.0);
        self.next_id = self.next_id.max(project.max_id() + 1);
        self.project = project;
        self.checkpoint = self.project.clone();
        if touched.is_none() {
            self.history.reset(self.project.clone(), history::now());
        }
        self.touched = touched.unwrap_or(false);
        self.dirty = true;
        self.restoring = true;
        // The count-in is the user's, not the project's.
        let (count_in, pre_roll, pre_roll_seconds) = (
            self.transport.count_in,
            self.transport.pre_roll,
            self.transport.pre_roll_seconds,
        );
        self.transport = Transport {
            count_in,
            pre_roll,
            pre_roll_seconds,
            ..transport
        };
        self.path = path;
        // Another project opens with its own screen, if it keeps one.
        self.screen = None;
        self.send_transport();
        self.flush();
        self.cue_reset();
        // The old project's audio is not needed for undo any more.
        self.trim_audio();
        self.watch_project_files();
        self.events
            .push(("project.loaded".into(), json!({ "path": self.path })));
    }

    pub fn project_new(&mut self) {
        self.replace_project(Project::default(), Transport::default(), None);
    }

    /// Start the undo history again from the project as it is now, which
    /// counts as unchanged: for a project put together by a script from a
    /// file that is not a project, such as a MIDI file, which then opens as
    /// a project file does instead of as edits of an empty one.
    /// Count the project as it is now as saved, without writing it.
    pub fn mark_saved(&mut self) {
        self.checkpoint();
        self.history.mark_saved(false);
    }

    pub fn undo_reset(&mut self) {
        self.checkpoint = self.project.clone();
        self.history.reset(self.project.clone(), history::now());
        self.touched = false;
    }

    pub fn project_load(&mut self, path: &Path) -> Result<()> {
        if folder::is_folder_path(path) {
            return self.project_load_folder(path);
        }
        let text =
            std::fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
        let mut file: ProjectFile =
            serde_json::from_str(&text).with_context(|| format!("parsing {}", path.display()))?;
        if file.version > FILE_VERSION {
            bail!("{} was saved by a newer version", path.display());
        }
        file.project
            .validate()
            .with_context(|| format!("{} cannot be loaded", path.display()))?;
        let moved = self.find_media(&mut file.project, path);
        self.replace_project(file.project, file.transport, Some(path.to_path_buf()));
        self.screen = file.screen;
        // Files found elsewhere are a change the file does not have yet.
        self.touched |= moved;
        Ok(())
    }

    /// Write the project as it is now to `path`, without making that the
    /// project's file or counting it as saved: a safety copy. `note` goes
    /// into the file as `recovery`, for whoever finds it later.
    pub fn project_backup(&mut self, path: &Path, note: Value) -> Result<()> {
        self.capture_states();
        let file = json!({
            "version": FILE_VERSION,
            "project": self.project,
            "transport": self.transport,
            "take": self.take_in_progress(),
            "recovery": note,
        });
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
        }
        crate::safe::write_file(path, serde_json::to_string(&file)?.as_bytes(), false)?;
        Ok(())
    }

    /// Open a safety copy as the project it was a copy of: with that
    /// project's file name (none if it never had one), and as changed since
    /// it was last saved. Returns the note the copy was written with.
    /// With `as_path`, the copy opens under that file name instead (for a
    /// `.bak` or any other copy that has no note).
    pub fn project_recover(&mut self, path: &Path, as_path: Option<&Path>) -> Result<Value> {
        if path.file_name().and_then(|n| n.to_str()) == Some(&format!("{}.bak", folder::PROJECT_FILE)) {
            return self.project_recover_folder(path);
        }
        let text =
            std::fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
        let mut value: Value =
            serde_json::from_str(&text).with_context(|| format!("parsing {}", path.display()))?;
        let note = value
            .as_object_mut()
            .and_then(|o| o.remove("recovery"))
            .unwrap_or(Value::Null);
        let take = value
            .as_object_mut()
            .and_then(|o| o.remove("take"))
            .unwrap_or(Value::Null);
        let mut file: ProjectFile =
            serde_json::from_value(value).with_context(|| format!("parsing {}", path.display()))?;
        if file.version > FILE_VERSION {
            bail!("{} was saved by a newer version", path.display());
        }
        file.project
            .validate()
            .with_context(|| format!("{} cannot be recovered", path.display()))?;
        let original = as_path
            .map(Path::to_path_buf)
            .or_else(|| note["path"].as_str().map(PathBuf::from));
        // A `.bak` names files relative to the project, as the project does;
        // and either may have moved with the project's folder.
        if let Some(original) = &original {
            self.find_media(&mut file.project, original);
        }
        self.replace_project(file.project, file.transport, original);
        self.restore_take(&take);
        // It differs from what is on disk, if anything is.
        self.touched = true;
        self.edits += 1;
        Ok(note)
    }

    /// The project as a file at `path` holds it: media named as from
    /// there, and the devices' own ids of the parameters it names.
    fn file_project(&self, path: &Path) -> Project {
        let mut project = media::for_file(&self.project, path);
        let tracks = project
            .tracks
            .iter_mut()
            .chain(std::iter::once(&mut project.master));
        for track in tracks {
            self.keep_param_ids(track);
        }
        project
    }

    /// Note in each device of a track that is about to be written the
    /// device's own id of each parameter key that it or its lanes use (see
    /// `DeviceInst::param_ids`), for every place a chain is written.
    pub(crate) fn keep_param_ids(&self, track: &mut Arc<Track>) {
        let mut found = Vec::new();
        for (at, d) in track.devices.iter().enumerate() {
            let Some(live) = self.live.get(&d.id) else { continue };
            let lanes = track.lanes.iter().filter_map(|l| match &l.target {
                Target::Param { device, param } if *device == d.id => Some(param),
                _ => None,
            });
            let mut ids = d.param_ids.clone();
            for key in d.params.keys().chain(lanes) {
                let Some(p) = live.params.iter().find(|p| &p.key == key) else { continue };
                if !p.id.is_empty() && p.id != p.key {
                    ids.insert(key.clone(), p.id.clone());
                }
            }
            if ids != d.param_ids {
                found.push((at, ids));
            }
        }
        if found.is_empty() {
            return;
        }
        let track = Arc::make_mut(track);
        for (at, ids) in found {
            Arc::make_mut(&mut track.devices[at]).param_ids = ids;
        }
    }

    pub fn project_save(&mut self, path: Option<&Path>) -> Result<PathBuf> {
        let path = path
            .map(Path::to_path_buf)
            .or_else(|| self.path.clone())
            .context("the project has no file yet: give a path")?;
        if folder::is_folder_path(&path) {
            return self.project_save_folder(&path, None).map(|(path, _)| path);
        }
        self.adopt_recordings(&path)?;
        self.capture_states();
        // What is saved is everything up to here and nothing after: an edit
        // made later in the same turn is a change that is not saved.
        self.checkpoint();
        // A project that was never named takes its file's name.
        let named = (self.project.name == Project::default().name)
            .then(|| path.file_stem().map(|s| s.to_string_lossy().into_owned()))
            .flatten()
            .filter(|name| !name.is_empty());
        let mut project = self.file_project(&path);
        if let Some(name) = &named {
            project.name = name.clone();
        }
        let file = ProjectFile {
            version: FILE_VERSION,
            project,
            transport: self.transport.clone(),
            screen: self.screen.clone(),
        };
        let text = serde_json::to_string_pretty(&file)?;
        // Write beside the target, flush it and rename, so a crash cannot
        // leave half a file; what was there before is kept as `.bak`.
        crate::safe::write_file(&path, text.as_bytes(), true)?;
        self.path = Some(path.clone());
        if let Some(name) = named {
            // Not an edit to undo: the saved state is the named one.
            self.project.name = name.clone();
            self.checkpoint.name = name;
            self.history.set_current_snapshot(self.checkpoint.clone());
            self.dirty = true;
        }
        self.history.mark_saved(false);
        self.remember_for_panic();
        self.events
            .push(("project.saved".into(), json!({ "path": path })));
        Ok(path)
    }

    // --- tracks ------------------------------------------------------------

    pub fn track_view(&self, id: Id) -> Result<Value> {
        let t = self
            .project
            .track(id)
            .with_context(|| format!("no track {id}"))?;
        let index = self.project.tracks.iter().position(|x| x.id == id);
        Ok(json!({
            "id": t.id, "name": t.name, "volume": t.volume, "pan": t.pan, "mute": t.mute,
            "solo": t.solo, "armed": t.armed, "output": t.output, "sends": t.sends,
            "devices": t.devices.iter().map(|d| d.id).collect::<Vec<_>>(),
            "clips": t.clips.iter().map(|c| c.id).collect::<Vec<_>>(),
            "color": t.color, "meta": t.meta, "index": index.map(|i| i + 1),
            "master": id == MASTER_ID, "input": t.input, "monitor": t.monitor,
            "midi_input": t.midi_input, "midi_output": t.midi_output, "height": t.height,
            "automation": t.automation.name(), "attr_map": t.attr_map,
            // The tracks that devices on this one listen to as side-chains.
            "listens": t.devices.iter().filter_map(|d| d.sidechain).collect::<BTreeSet<_>>(),
            // The tracks that further output pairs of its devices play into.
            "pairs_into": t.devices.iter().flat_map(|d| d.outputs.values()).collect::<BTreeSet<_>>(),
            // A track or a chain read from outside the project's folder, or copied from there.
            "source": t.source, "origin": t.origin,
            "chain_source": t.chain_source, "chain_origin": t.chain_origin,
        }))
    }

    /// One entry of [`track_view`](Self::track_view), made alone: the
    /// handlers of each edit ask for a track's volume or meta, and the whole
    /// view lists every clip of the track.
    pub fn track_field(&self, id: Id, key: &str) -> Result<Value> {
        let t = self
            .project
            .track(id)
            .with_context(|| format!("no track {id}"))?;
        Ok(match key {
            "id" => json!(t.id),
            "name" => json!(t.name),
            "volume" => json!(t.volume),
            "pan" => json!(t.pan),
            "mute" => json!(t.mute),
            "solo" => json!(t.solo),
            "armed" => json!(t.armed),
            "output" => json!(t.output),
            "color" => json!(t.color),
            "meta" => json!(t.meta),
            "master" => json!(id == MASTER_ID),
            "input" => json!(t.input),
            "monitor" => json!(t.monitor),
            "midi_input" => json!(t.midi_input),
            "midi_output" => json!(t.midi_output),
            "height" => json!(t.height),
            _ => self.track_view(id)?.get(key).cloned().unwrap_or(Value::Null),
        })
    }

    pub fn track_add(&mut self, opts: TrackOpts) -> Result<Id> {
        let volume = finite("volume", opts.volume.unwrap_or(0.0))?.clamp(-120.0, 24.0);
        let pan = finite("pan", opts.pan.unwrap_or(0.0))?.clamp(-1.0, 1.0);
        let id = self.new_id();
        self.edit(|p| {
            if let Some(output) = opts.output
                && p.track(output).is_none()
            {
                bail!("no track {output} to output to");
            }
            let mut track = Track::new(id);
            track.name = opts
                .name
                .unwrap_or_else(|| format!("Track {}", p.tracks.len() + 1));
            track.volume = volume;
            track.pan = pan;
            track.output = opts.output.filter(|o| *o != MASTER_ID);
            track.color = opts.color;
            let index = opts
                .index
                .map_or(usize::MAX, |i| i.saturating_sub(1))
                .min(p.tracks.len());
            p.tracks.insert(index, Arc::new(track));
            Ok(id)
        })
    }

    pub fn track_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            if id == MASTER_ID {
                bail!("the master track cannot be removed");
            }
            let index = p
                .tracks
                .iter()
                .position(|t| t.id == id)
                .with_context(|| format!("no track {id}"))?;
            p.tracks.remove(index);
            // Anything that was routed into the removed track falls back to the master.
            for track in &mut p.tracks {
                if track.output == Some(id) || track.sends.iter().any(|s| s.target == id) {
                    let track = Arc::make_mut(track);
                    track.output = track.output.filter(|o| *o != id);
                    track.sends.retain(|s| s.target != id);
                }
            }
            // Devices that listened to it listen to their own input again,
            // and output pairs that played into it are no longer heard.
            let routed = |d: &DeviceInst| {
                d.sidechain == Some(id) || d.outputs.values().any(|to| *to == id)
            };
            for track in std::iter::once(&mut p.master).chain(&mut p.tracks) {
                if track.devices.iter().any(|d| routed(d)) {
                    for device in &mut Arc::make_mut(track).devices {
                        if routed(device) {
                            let device = Arc::make_mut(device);
                            if device.sidechain == Some(id) {
                                device.sidechain = None;
                                device.sidechain_pre = false;
                            }
                            device.outputs.retain(|_, to| *to != id);
                        }
                    }
                }
            }
            Ok(())
        })
    }

    pub fn track_move(&mut self, id: Id, index: usize) -> Result<()> {
        self.edit(|p| {
            let from = p
                .tracks
                .iter()
                .position(|t| t.id == id)
                .with_context(|| format!("no track {id}"))?;
            let track = p.tracks.remove(from);
            p.tracks.insert(index.min(p.tracks.len()), track);
            Ok(())
        })
    }

    pub fn track_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        if holds(&self.track_view(id), key, &value) {
            return Ok(());
        }
        if let (true, Some(track), Some(to)) = (
            matches!(key, "volume" | "pan"),
            self.project.track(id),
            value.as_f64(),
        ) {
            let (target, before) = match key {
                "volume" => (Target::Volume, track.volume),
                _ => (Target::Pan, track.pan),
            };
            self.touch(id, target, before, to);
        }
        let moved = matches!(key, "volume" | "pan").then(|| format!("track {id} {key}"));
        self.edit(|p| {
            if p.track(id).is_none() {
                bail!("no track {id}");
            }
            match key {
                "output" => {
                    let output: Option<Id> = de(key, value)?;
                    let output = output.filter(|o| *o != MASTER_ID);
                    if id == MASTER_ID {
                        bail!("the master track has no output");
                    }
                    if let Some(to) = output {
                        if p.track(to).is_none() {
                            bail!("no track {to} to output to");
                        }
                        if p.would_cycle(id, to) {
                            bail!("routing track {id} into track {to} would make a loop");
                        }
                    }
                    p.track_mut(id).unwrap().output = output;
                }
                "sends" => {
                    let mut sends: Vec<Send> = de(key, value)?;
                    for send in &mut sends {
                        send.level = send.level.clamp(-120.0, 24.0);
                    }
                    for send in &sends {
                        if id == MASTER_ID || p.track(send.target).is_none() {
                            bail!("cannot send from track {id} to track {}", send.target);
                        }
                        if p.would_cycle(id, send.target) {
                            bail!(
                                "sending track {id} to track {} would make a loop",
                                send.target
                            );
                        }
                    }
                    p.track_mut(id).unwrap().sends = sends;
                }
                "input" => {
                    if id == MASTER_ID {
                        bail!("the master track has no input");
                    }
                    let input = match value {
                        Value::Null => None,
                        Value::Number(n) => Some(n.to_string()),
                        Value::String(s) if s.is_empty() || s == "none" => None,
                        Value::String(s) => Some(s),
                        _ => bail!("an input is a channel like \"1\" or a pair like \"1/2\""),
                    };
                    let input = match input {
                        None => None,
                        Some(spec) => match parse_input(&spec) {
                            Some((first, 1)) => Some(format!("{}", first + 1)),
                            Some((first, _)) => Some(format!("{}/{}", first + 1, first + 2)),
                            None => bail!(
                                "bad input `{spec}`: give a channel like \"1\" or a pair like \"1/2\""
                            ),
                        },
                    };
                    p.track_mut(id).unwrap().input = input;
                }
                "midi_input" => {
                    if id == MASTER_ID {
                        bail!("the master track has no input");
                    }
                    let midi = match value {
                        Value::Null => None,
                        Value::String(s) if s == "all" || s.is_empty() => None,
                        Value::String(s) => Some(MidiInput {
                            port: Some(s),
                            channel: None,
                        }),
                        // An empty Lua table arrives as an empty list.
                        Value::Array(a) if a.is_empty() => None,
                        value => {
                            let mut midi: MidiInput = de(key, value)?;
                            if midi.channel.is_some_and(|ch| !(1..=16).contains(&ch)) {
                                bail!("a MIDI channel is from 1 to 16");
                            }
                            if midi.port.as_deref().is_some_and(|p| p.is_empty() || p == "all") {
                                midi.port = None;
                            }
                            (midi != MidiInput::default()).then_some(midi)
                        }
                    };
                    p.track_mut(id).unwrap().midi_input = midi;
                }
                "midi_output" => {
                    let out = midi_out::parse(value)?;
                    p.track_mut(id).unwrap().midi_output = out;
                }
                "attr_map" => p.track_mut(id).unwrap().attr_map = crate::attr_map::parse(value)?,
                _ => {
                    let t = p.track_mut(id).unwrap();
                    match key {
                        "name" => t.name = de(key, value)?,
                        "volume" => t.volume = de::<f64>(key, value)?.clamp(-120.0, 24.0),
                        "pan" => t.pan = de::<f64>(key, value)?.clamp(-1.0, 1.0),
                        "mute" => t.mute = de(key, value)?,
                        "solo" => t.solo = de(key, value)?,
                        "armed" | "monitor" if id == MASTER_ID && de::<bool>(key, value.clone())? => {
                            bail!("the master track records nothing: arm a track")
                        }
                        "armed" => t.armed = de(key, value)?,
                        "monitor" => t.monitor = de(key, value)?,
                        "color" => t.color = de(key, value)?,
                        "meta" => t.meta = de_meta(key, value)?,
                        "automation" => t.automation = de(key, value)?,
                        // A share of the zoom's height, a quarter to eight
                        // times; 1 or nothing is that height.
                        "height" => {
                            t.height = de::<Option<f64>>(key, value)?
                                .filter(|h| h.is_finite() && (h - 1.0).abs() > 1e-9)
                                .map(|h| h.clamp(0.25, 8.0))
                        }
                        _ => bail!("tracks have no settable field `{key}`"),
                    }
                }
            }
            Ok(())
        })?;
        if let Some(name) = moved {
            self.swept(name);
        }
        Ok(())
    }

    // --- devices -----------------------------------------------------------

    pub fn device_types(&self) -> Value {
        let types: Vec<Value> = self
            .registry
            .iter()
            .map(|f| {
                let info = f.info();
                let params: Vec<Value> = info.params.iter().map(param_json).collect();
                json!({
                    "kind": info.kind, "name": info.name, "category": info.category,
                    "format": info.format, "vendor": info.vendor, "params": params,
                    "id": info.id, "version": info.version, "features": info.features,
                })
            })
            .collect();
        Value::Array(types)
    }

    pub fn device_view(&self, id: Id) -> Result<Value> {
        let (track, index) = self
            .project
            .find_device(id)
            .with_context(|| format!("no device {id}"))?;
        let d = &self.project.track(track).unwrap().devices[index];
        let info = self.registry.get(&d.kind).map(|f| f.info());
        let live = self.live.get(&id);
        // Every parameter with its current value: what the project sets,
        // else what the plugin reports (from its own state), else the default.
        let mut params = serde_json::Map::new();
        let mut infos = Vec::new();
        // The parameters a lane of the track moves.
        let automated: Vec<&str> = self
            .project
            .track(track)
            .unwrap()
            .lanes
            .iter()
            .filter_map(|l| match &l.target {
                Target::Param { device, param } if *device == id && l.enabled => {
                    Some(param.as_str())
                }
                _ => None,
            })
            .collect();
        for (i, p) in live
            .map(|l| l.params.as_slice())
            .unwrap_or(&[])
            .iter()
            .enumerate()
        {
            let reported = || {
                live.and_then(|l| l.controller.as_ref())
                    .and_then(|c| c.value(i))
            };
            let value = d
                .params
                .get(&p.key)
                .copied()
                .or_else(reported)
                .unwrap_or(p.default as f64);
            params.insert(p.key.clone(), json!(value));
            let mut info = param_json(p);
            info["index"] = json!(i + 1);
            info["automated"] = json!(automated.contains(&p.key.as_str()));
            infos.push(info);
        }
        // `running`, `loading` (being made apart: see session/loading.rs),
        // `stopped`, `offline` (set so: not made at all) or `missing` (not
        // installed).
        let loading = self.loads.loading(id);
        let stopped = live
            .and_then(|l| l.stopped.clone())
            .or_else(|| self.loads.failed(id).map(str::to_string));
        let status = if d.offline {
            "offline"
        } else if info.is_none() {
            "missing"
        } else if loading {
            "loading"
        } else if stopped.is_some() || live.is_none() {
            "stopped"
        } else {
            "running"
        };
        // Whether the device has a window of its own, and whether it is showing.
        let editor = live
            .and_then(|l| l.controller.as_ref())
            .filter(|c| c.has_editor())
            .map(|c| if c.editor_open() { "open" } else { "closed" });
        // A device that is not running still has the values the project
        // keeps for it.
        if live.is_none() {
            for (key, value) in &d.params {
                params.insert(key.clone(), json!(value));
            }
        }
        let name = info.map(|i| &i.name).or(d.name.as_ref()).unwrap_or(&d.kind);
        // Who made it and which it is, as its format names it.
        let plugin = info.filter(|i| !i.id.is_empty()).map(|i| {
            json!({
                "format": i.format, "id": i.id, "name": i.name, "vendor": i.vendor,
                "version": i.version,
            })
        });
        Ok(json!({
            "plugin": plugin,
            "id": d.id, "kind": d.kind, "name": name, "offline": d.offline,
            "format": info.map_or("", |i| &i.format),
            "track": track, "index": index + 1, "bypass": d.bypass, "params": params,
            // The parameters the project sets, over what the plugin's state says.
            "overrides": d.params,
            "param_info": infos, "meta": d.meta, "editor": editor,
            // Not running: not installed, not made yet, or made and gone.
            "missing": live.is_none() && !loading && !d.offline,
            // Why the device has stopped working, for a plugin that crashed,
            // hung, or could not be made.
            "stopped": stopped,
            "status": status,
            // The track it listens to, and whether it can listen at all.
            "sidechain": d.sidechain, "sidechain_pre": d.sidechain_pre,
            // Where its further output pairs play, by pair number.
            "outputs": d.outputs,
            "ports": ports::ports_json(&self.device_ports(id)),
        }))
    }

    pub fn device_add(&mut self, track: Id, kind: &str, opts: DeviceOpts) -> Result<Id> {
        if self.registry.get(kind).is_none() {
            bail!("no device kind `{kind}`");
        }
        let id = self.new_id();
        // A plugin's name, for when it is not installed.
        let name = self
            .registry
            .get(kind)
            .map(|f| f.info())
            .filter(|info| info.format != "builtin")
            .map(|info| info.name.clone());
        self.edit(|p| {
            let t = p
                .track_mut(track)
                .with_context(|| format!("no track {track}"))?;
            let device = DeviceInst {
                id,
                kind: kind.into(),
                bypass: false,
                params: BTreeMap::new(),
                state: opts.state.clone(),
                meta: Default::default(),
                loaded: 0,
                name: name.clone(),
                offline: false,
                sidechain: None,
                sidechain_pre: false,
                outputs: BTreeMap::new(),
                param_ids: BTreeMap::new(),
                files: BTreeMap::new(),
            };
            let index = opts
                .index
                .map_or(usize::MAX, |i| i.saturating_sub(1))
                .min(t.devices.len());
            t.devices.insert(index, Arc::new(device));
            Ok(())
        })?;
        // Create it now: a plugin's parameters are only known once it exists,
        // and a plugin that fails to load should fail here, not later.
        let before = self.warnings.len();
        self.flush();
        let outcome = if self.live.contains_key(&id) || self.loads.loading(id) {
            opts.params
                .iter()
                .try_for_each(|(name, value)| self.device_set_param(id, name, *value))
        } else {
            Err(anyhow!(
                self.warnings
                    .drain(before..)
                    .next_back()
                    .unwrap_or_else(|| format!("could not load `{kind}`"))
            ))
        };
        if let Err(err) = outcome {
            self.device_remove(id)?;
            return Err(err);
        }
        Ok(id)
    }

    pub fn device_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            let (track, index) = p
                .find_device(id)
                .with_context(|| format!("no device {id}"))?;
            let t = p.track_mut(track).unwrap();
            t.devices.remove(index);
            t.lanes.retain(|l| l.target.device() != Some(id));
            Ok(())
        })
    }

    /// Move a device to `index` in the chain of `track`.
    pub fn device_move(&mut self, id: Id, track: Id, index: usize) -> Result<()> {
        self.edit(|p| {
            let (from, at) = p
                .find_device(id)
                .with_context(|| format!("no device {id}"))?;
            if p.track(track).is_none() {
                bail!("no track {track}");
            }
            if let Some(source) = p.device(id).and_then(|d| d.sidechain)
                && from != track
                && (source == track || p.would_cycle(source, track))
            {
                bail!("the device listens to track {source}: on track {track} that would make a loop");
            }
            if from != track {
                for (pair, to) in p.device(id).map(|d| d.outputs.clone()).unwrap_or_default() {
                    ports::check_output(p, track, pair, to)?;
                }
            }
            let source = p.track_mut(from).unwrap();
            let device = source.devices.remove(at);
            // A device's lanes live on the track it is on, so they go with it.
            let (lanes, keep) = std::mem::take(&mut source.lanes)
                .into_iter()
                .partition(|l| l.target.device() == Some(id) && from != track);
            source.lanes = keep;
            let t = p.track_mut(track).unwrap();
            t.devices.insert(index.min(t.devices.len()), device);
            t.lanes.extend::<Vec<_>>(lanes);
            Ok(())
        })
    }

    /// A parameter of a loaded device, by key or by its display name.
    fn param_info(&mut self, id: Id, name: &str) -> Result<ParamInfo> {
        let kind = self
            .project
            .device(id)
            .with_context(|| format!("no device {id}"))?
            .kind
            .clone();
        self.flush();
        self.await_device(id);
        let Some(live) = self.live.get(&id) else {
            bail!("device `{kind}` is not loaded");
        };
        find_param(&live.params, name)
            .map(|at| live.params[at].clone())
            .with_context(|| format!("device `{kind}` has no parameter `{name}`"))
    }

    /// A parameter of a loaded device as [`param_json`] describes it, with
    /// its value now and that value as the device writes it.
    pub fn device_param(&mut self, id: Id, name: &str) -> Result<Value> {
        let param = self.param_info(id, name)?;
        let view = self.device_view(id)?;
        let at = view["param_info"]
            .as_array()
            .and_then(|list| list.iter().position(|p| p["key"] == json!(param.key)))
            .context("the parameter is gone")?;
        let mut out = view["param_info"][at].clone();
        let value = view["params"][&param.key].as_f64().unwrap_or(param.default as f64);
        out["value"] = json!(value);
        out["text"] = json!(self.param_text(id, &param.key, value)?);
        Ok(out)
    }

    /// A value of a parameter as text: as the device writes it (a plugin's
    /// own "440 Hz"), else as [`ParamInfo::format`] does.
    pub fn param_text(&mut self, id: Id, name: &str, value: f64) -> Result<String> {
        let value = finite("a parameter value", value)?;
        let param = self.param_info(id, name)?;
        let live = self.live.get_mut(&id).context("the device is not loaded")?;
        let at = find_param(&live.params, &param.key).unwrap();
        let own = !crate::sync::is_host(&live.params, at);
        let text = live
            .controller
            .as_mut()
            .filter(|_| own)
            .and_then(|c| c.value_text(at, value));
        Ok(text.unwrap_or_else(|| param.format(value)))
    }

    /// The value a text stands for, for a parameter: as the device reads
    /// it, else as [`ParamInfo::parse`] does.
    pub fn param_parse(&mut self, id: Id, name: &str, text: &str) -> Result<f64> {
        let param = self.param_info(id, name)?;
        let live = self.live.get_mut(&id).context("the device is not loaded")?;
        let at = find_param(&live.params, &param.key).unwrap();
        let own = !crate::sync::is_host(&live.params, at);
        let value = live
            .controller
            .as_mut()
            .filter(|_| own)
            .and_then(|c| c.text_value(at, text))
            .or_else(|| param.parse(text));
        value.with_context(|| format!("`{text}` is not a value of `{}`", param.name))
    }

    /// Set a parameter by key, or by its display name.
    pub fn device_set_param(&mut self, id: Id, name: &str, value: f64) -> Result<()> {
        let value = finite("a parameter value", value)?;
        let param = self.param_info(id, name)?;
        let key = param.key.clone();
        let value = (value as f32).clamp(param.min, param.max) as f64;
        self.events.push((
            "param.touched".into(),
            json!({ "device": id, "param": key, "id": param.stable_id(), "from": "host" }),
        ));
        if self.playing
            && let Some((track, _)) = self.project.find_device(id)
            && self.auto_mode(track).writes()
        {
            let before = self.device_view(id)?["params"][&key].as_f64();
            let target = Target::Param {
                device: id,
                param: key.clone(),
            };
            self.touch(track, target, before.unwrap_or(value), value);
        }
        let name = format!("param {id} {key}");
        self.edit(|p| {
            p.device_mut(id).unwrap().params.insert(key, value);
            Ok(())
        })?;
        self.swept(name);
        Ok(())
    }

    /// Ask every plugin for its state and store it in the project, so that
    /// saving, rendering and restarting the engine reproduce what is sounding.
    ///
    /// Parameters set through the project are not read back from the plugin:
    /// the project is the authority for those, and they are applied again on
    /// top of the state whenever the plugin is recreated.
    pub fn capture_states(&mut self) {
        self.flush();
        let mut captured = Vec::new();
        let mut kept = Vec::new();
        let driven = statelanes::driven(&self.project);
        for (id, live) in &mut self.live {
            // A device that stopped working has no state to give: the
            // project keeps the one it had, and its stop was told already.
            // One a state lane drives holds the lane's state, not its own.
            if live.stopped.is_some() || driven.contains(id) {
                continue;
            }
            let Some(controller) = live.controller.as_mut() else {
                continue;
            };
            match controller.save_state() {
                Ok(Some(bytes)) => captured.push((*id, BASE64.encode(bytes))),
                Ok(None) => {}
                Err(err) => self
                    .warnings
                    .push(format!("could not save plugin state: {err:#}")),
            }
            // The files it keeps beside its state (an ARA archive).
            if live.attached {
                match controller
                    .call(paw_engine::device::FILE_SAVE, &[])
                    .and_then(|packed| paw_engine::device::unpack_files(&packed))
                {
                    Ok(files) => kept.push((
                        *id,
                        files
                            .into_iter()
                            .map(|(name, bytes)| (name, BASE64.encode(bytes)))
                            .collect::<BTreeMap<_, _>>(),
                    )),
                    Err(err) => self
                        .warnings
                        .push(format!("could not save the files of a plugin: {err:#}")),
                }
            }
        }
        for (id, state) in captured {
            if let Some(device) = self.project.device_mut(id) {
                device.state = Some(state);
            }
        }
        for (id, files) in kept {
            if let Some(device) = self.project.device_mut(id) {
                device.files = files;
            }
        }
        // This is bookkeeping, not an edit: nothing for the engine to do.
        self.synced = self.project.clone();
    }

    /// A plugin's state as it is now, base64 encoded, for making a copy of
    /// the device with [`DeviceOpts::state`]. None for devices that keep no
    /// state beyond their parameters.
    pub fn device_state(&mut self, id: Id) -> Result<Option<String>> {
        self.project
            .find_device(id)
            .with_context(|| format!("no device {id}"))?;
        self.flush();
        self.await_device(id);
        let Some(controller) = self.live.get_mut(&id).and_then(|l| l.controller.as_mut()) else {
            return Ok(None);
        };
        Ok(controller.save_state()?.map(|bytes| BASE64.encode(bytes)))
    }

    /// Load a preset into a device as one edit, which undo takes back: the
    /// plugin's state (base64, none for a device that keeps none), the
    /// parameters the preset sets, and its name, kept as `meta.preset`.
    /// With `factory`, the plugin first loads one of its own presets by that
    /// id, and the state it has then is what is kept.
    pub fn device_load(&mut self, id: Id, load: PresetLoad) -> Result<()> {
        self.project
            .find_device(id)
            .with_context(|| format!("no device {id}"))?;
        self.flush();
        let first = self.trial_loads(id);
        if let Some(live) = self.live.get_mut(&id) {
            live.given_state();
        }
        let controller = self.live.get_mut(&id).and_then(|l| l.controller.as_mut());
        // What the plugin holds now goes into the step before this one, so
        // that undo comes back to it and not to an older state (in a trial,
        // what it held before the trial's first preset).
        let mut state = load.state;
        if let Some(controller) = controller {
            if let Some(bytes) = first.then(|| controller.save_state()).and_then(|s| s.ok().flatten()) {
                let now = BASE64.encode(bytes);
                for snapshot in [&mut self.project, &mut self.checkpoint, &mut self.synced] {
                    if let Some(device) = snapshot.device_mut(id) {
                        device.state = Some(now.clone());
                    }
                }
            }
            let request = match (&load.factory, &load.call) {
                (Some(_), Some(_)) => bail!("give a preset load `factory` or `call`, not both"),
                (Some(preset), None) => Some(("preset.load", preset.as_bytes(), 10, 30)),
                // A file the plugin loads in the background (a model) can
                // take longer than one of its own presets, or much less:
                // look more often, for up to a second.
                (None, Some(call)) => Some((call.method.as_str(), call.data.as_bytes(), 200, 5)),
                (None, None) => None,
            };
            if let Some((method, data, tries, wait)) = request {
                let before = controller.save_state().ok().flatten();
                controller.call(method, data)?;
                // Some plugins finish loading on their audio thread: give
                // them a moment before reading back what they hold.
                let mut after = controller.save_state()?;
                for _ in 0..tries {
                    if after != before {
                        break;
                    }
                    std::thread::sleep(std::time::Duration::from_millis(wait));
                    controller.idle();
                    after = controller.save_state()?;
                }
                state = after.map(|bytes| BASE64.encode(bytes));
            }
        } else if load.factory.is_some() {
            bail!("this device has no presets of its own");
        } else if load.call.is_some() {
            bail!("this device takes no calls");
        }
        if let Some(text) = &state {
            BASE64
                .decode(text)
                .context("a preset's state is given in base64")?;
        }
        // The plugin already holds the new state when it loaded one of its
        // own presets or answered a call.
        let already = load.factory.is_some() || load.call.is_some();
        self.edit(|p| {
            let d = p.device_mut(id).unwrap();
            d.state = state;
            d.params = load.params;
            d.loaded = d.loaded.wrapping_add(1);
            match load.name {
                Some(name) => d.meta.insert("preset".into(), Value::String(name)),
                None => d.meta.remove("preset"),
            };
            Ok(())
        })?;
        // Loading the state it gave back into it again would only cost time.
        if already && let Some(device) = self.project.device(id).cloned() {
            let synced_device = self.synced.device_mut(id);
            if let Some(synced_device) = synced_device {
                *synced_device = (*device).clone();
            }
            self.events
                .push(("device.changed".into(), json!({ "id": id })));
            self.events.push(("changed".into(), json!({})));
        }
        Ok(())
    }

    /// Start a device again that has stopped working, or that never loaded:
    /// a new instance, with the state the project last had of it and the
    /// parameters set in the project. The project itself does not change.
    pub fn device_restart(&mut self, id: Id) -> Result<()> {
        let (track, _) = self
            .project
            .find_device(id)
            .with_context(|| format!("no device {id}"))?;
        if self.project.device(id).is_some_and(|d| d.offline) {
            bail!("the device is offline: set it online to start it");
        }
        self.flush();
        // Take it out of the engine and put it back, behind the project's back.
        let mut without = self.project.clone();
        if let Some(track) = without.track_mut(track) {
            track.devices.retain(|d| d.id != id);
        }
        let mut quiet = Vec::new();
        {
            let mut ctx = SyncCtx {
                registry: &self.registry,
                audio: &mut self.audio,
                live: &mut self.live,
                sample_rate: self.handle.sample_rate as f32,
                warnings: &mut self.warnings,
                offline: false,
            };
            let handle = &mut self.handle;
            let mut send = |msg| handle.send(msg);
            sync(
                &self.synced,
                &without,
                &mut self.map,
                &mut ctx,
                &mut send,
                &mut quiet,
            );
        }
        self.synced = without;
        self.dirty = true;
        let before = self.events.len();
        self.flush();
        // Nothing was added to the project: say only that the device changed.
        self.events.truncate(before);
        self.events
            .push(("device.changed".into(), json!({ "id": id, "track": track })));
        if !self.live.contains_key(&id) && !self.loads.loading(id) {
            let why = self
                .warnings
                .pop()
                .unwrap_or_else(|| "it could not be started".into());
            bail!("{why}");
        }
        Ok(())
    }

    /// Housekeeping for plugins: runs their editors and picks up what they
    /// changed by themselves. Call regularly from the main thread.
    pub fn idle(&mut self) {
        // A take whose file could not be written stops; what it has is kept.
        if self.take.as_ref().is_some_and(|t| t.shared.failed()) {
            self.stop();
        }
        self.render_poll();
        self.play_states();
        self.poll_preview();
        self.poll_loads();
        self.poll_stretches();
        self.watch_devices();
        self.poll_file_changes();
        let mut changed: Vec<(Id, Vec<String>)> = Vec::new();
        // What was moved in a plugin's own window, for writing automation.
        let mut moved: Vec<(Id, String, String, f64)> = Vec::new();
        let mut latency_changed = false;
        // Plugins that have stopped working since the last look.
        let mut stopped: Vec<(Id, String)> = Vec::new();
        // Devices whose output held NaN or infinity, silenced by the engine.
        let mut invalid: Vec<Id> = Vec::new();
        for (id, live) in &mut self.live {
            // Any device, built in or not, that panicked or put out NaN or
            // infinity: the engine has bypassed or silenced it.
            if let Some(&slot) = self.map.devices.get(id) {
                let fault = self
                    .handle
                    .shared
                    .fault(slot, paw_engine::guard::NOT_FINITE);
                if fault & paw_engine::guard::PANICKED != 0 && live.stopped.is_none() {
                    let why =
                        "it crashed while processing; it is bypassed until restarted".to_string();
                    live.stopped = Some(why.clone());
                    stopped.push((*id, why));
                }
                if fault & paw_engine::guard::NOT_FINITE != 0 {
                    invalid.push(*id);
                }
            }
            let echoes = live.echoes();
            let Some(controller) = live.controller.as_mut() else {
                continue;
            };
            let was_open = controller.editor_open();
            controller.idle();
            if live.stopped.is_none()
                && let Some(why) = controller.health()
            {
                live.stopped = Some(why.clone());
                stopped.push((*id, why));
            }
            let latency = controller.latency();
            if latency != live.latency {
                live.latency = latency;
                latency_changed = true;
            }
            let changes = controller.take_changes();
            // The echo of a state it was given: the values only mirror the
            // state, which the project already holds. Nothing was edited.
            if echoes {
                if !changes.is_empty() || was_open != controller.editor_open() {
                    changed.push((*id, Vec::new()));
                }
                continue;
            }
            let keys: Vec<String> = changes
                .iter()
                .filter_map(|(index, _)| Some(live.params.get(*index)?.key.clone()))
                .collect();
            for (index, value) in &changes {
                if let Some(param) = live.params.get(*index) {
                    moved.push((*id, param.key.clone(), param.stable_id().to_string(), *value));
                }
            }
            if !keys.is_empty() || was_open != controller.editor_open() {
                changed.push((*id, keys));
            }
        }
        for (device, param, stable, value) in moved {
            // The parameter last moved in a plugin's own window, for
            // `:param.last` and for the frontends to show.
            self.events.push((
                "param.touched".into(),
                json!({ "device": device, "param": param, "id": stable, "value": value, "from": "editor" }),
            ));
            if let Some((track, _)) = self.project.find_device(device) {
                self.touch(track, Target::Param { device, param }, value, value);
            }
        }
        for (device, why) in stopped {
            let Some((track, _)) = self.project.find_device(device) else {
                continue;
            };
            let kind = self.project.device(device).map_or("", |d| d.kind.as_str());
            let name = self
                .registry
                .get(kind)
                .map_or(kind.to_string(), |f| f.info().name.clone());
            self.events.push((
                "device.stopped".into(),
                json!({ "device": device, "track": track, "name": name, "reason": why }),
            ));
        }
        for device in invalid {
            let Some((track, _)) = self.project.find_device(device) else {
                continue;
            };
            let kind = self.project.device(device).map_or("", |d| d.kind.as_str());
            let name = self
                .registry
                .get(kind)
                .map_or(kind.to_string(), |f| f.info().name.clone());
            self.events.push((
                "device.invalid".into(),
                json!({ "device": device, "track": track, "name": name }),
            ));
        }
        if latency_changed {
            // The tracks have to be lined up again.
            self.dirty = true;
            self.flush();
        }
        if changed.is_empty() {
            return;
        }
        self.flush();
        for (id, keys) in changed {
            // The plugin now holds a value the project did not set. Stop
            // overriding it: the plugin's own state is what carries it from here.
            for snapshot in [&mut self.project, &mut self.checkpoint] {
                let overridden = snapshot
                    .device(id)
                    .is_some_and(|d| keys.iter().any(|key| d.params.contains_key(key)));
                if overridden && let Some(device) = snapshot.device_mut(id) {
                    device.params.retain(|key, _| !keys.contains(key));
                }
            }
            let track = self.project.find_device(id).map(|(track, _)| track);
            self.events
                .push(("device.changed".into(), json!({ "id": id, "track": track })));
        }
        // Nothing here needs sending to the engine: the plugin already has it.
        self.synced = self.project.clone();
        self.events.push(("changed".into(), json!({})));
    }

    /// Show or hide a plugin's own window. Returns whether it is open afterwards.
    pub fn device_editor(&mut self, id: Id, open: Option<bool>) -> Result<bool> {
        self.flush();
        self.await_device(id);
        let (track, _) = self
            .project
            .find_device(id)
            .with_context(|| format!("no device {id}"))?;
        let track = self
            .project
            .track(track)
            .map(|t| t.name.clone())
            .unwrap_or_default();
        let name = self
            .project
            .device(id)
            .and_then(|d| self.registry.get(&d.kind))
            .map(|f| f.info().name.clone());
        let controller = self
            .live
            .get_mut(&id)
            .and_then(|live| live.controller.as_mut())
            .filter(|controller| controller.has_editor())
            .context("this device has no editor window")?;
        if open.unwrap_or(!controller.editor_open()) {
            controller.open_editor(&format!("{} · {track}", name.unwrap_or_default()))?;
        } else {
            controller.close_editor();
        }
        let open = controller.editor_open();
        self.events
            .push(("device.changed".into(), json!({ "id": id })));
        self.events.push(("changed".into(), json!({})));
        Ok(open)
    }

    /// Pass a script's request to the main-thread side of a device.
    /// What a plugin calls its keys (CLAP's `note-name`: a drum, a
    /// keyswitch), by pitch; nothing when it names none, is no CLAP plugin,
    /// or is not made yet. Asked as views are drawn, so it waits for nothing.
    pub fn device_note_names(&mut self, id: Id) -> BTreeMap<u8, String> {
        let clap = self
            .project
            .device(id)
            .is_some_and(|d| d.kind.starts_with("clap:"));
        let Some(controller) = self
            .live
            .get_mut(&id)
            .and_then(|live| live.controller.as_mut())
            .filter(|_| clap)
        else {
            return BTreeMap::new();
        };
        let names: BTreeMap<String, String> = controller
            .call("note-names", &[])
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default();
        names
            .into_iter()
            .filter_map(|(key, name)| Some((key.parse::<u8>().ok().filter(|k| *k < 128)?, name)))
            .collect()
    }

    pub fn device_call(&mut self, id: Id, method: &str, data: &[u8]) -> Result<Vec<u8>> {
        self.flush();
        self.await_device(id);
        let kind = &self
            .project
            .device(id)
            .with_context(|| format!("no device {id}"))?
            .kind;
        self.live
            .get_mut(&id)
            .and_then(|live| live.controller.as_mut())
            .with_context(|| format!("device `{kind}` takes no calls"))?
            .call(method, data)
    }

    /// Whether any device needs [`idle`](Self::idle) to be called.
    pub fn needs_idle(&self) -> bool {
        self.live.values().any(|live| live.controller.is_some())
            || self.loads.busy()
            || self.watching()
            || self.rendering()
    }

    pub fn device_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        self.edit(|p| {
            if key == "sidechain" {
                let (track, _) = p
                    .find_device(id)
                    .with_context(|| format!("no device {id}"))?;
                // An empty Lua table arrives as an empty list.
                let source: Option<Id> = match value {
                    Value::Array(a) if a.is_empty() => None,
                    value => de(key, value)?,
                };
                if let Some(source) = source {
                    if p.track(source).is_none() {
                        bail!("no track {source} to take a side-chain from");
                    }
                    if source == MASTER_ID {
                        bail!("the master track feeds nothing, so it cannot be a side-chain");
                    }
                    if source == track {
                        bail!("a device cannot take a side-chain from its own track");
                    }
                    if p.would_cycle(source, track) {
                        bail!(
                            "a side-chain from track {source} to track {track} would make a loop"
                        );
                    }
                }
                p.device_mut(id).unwrap().sidechain = source;
                return Ok(());
            }
            if key == "outputs" {
                let (track, _) = p
                    .find_device(id)
                    .with_context(|| format!("no device {id}"))?;
                let outputs = ports::parse_outputs(value)?;
                for (pair, to) in &outputs {
                    ports::check_output(p, track, *pair, *to)?;
                }
                p.device_mut(id).unwrap().outputs = outputs;
                return Ok(());
            }
            let d = p
                .device_mut(id)
                .with_context(|| format!("no device {id}"))?;
            match key {
                "sidechain_pre" => d.sidechain_pre = de(key, value)?,
                "bypass" => d.bypass = de(key, value)?,
                "offline" => d.offline = de(key, value)?,
                "meta" => d.meta = de_meta(key, value)?,
                // Base64, as `device_state` gives it; nil for none.
                "state" => {
                    let state: Option<String> = de(key, value)?;
                    if let Some(text) = &state {
                        BASE64
                            .decode(text)
                            .context("a device's state is given in base64")?;
                    }
                    d.state = state;
                }
                _ => bail!("devices have no settable field `{key}`"),
            }
            Ok(())
        })
    }

    // --- clips -------------------------------------------------------------

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
            opts.kind = Some("midi".into());
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
        let kind =
            opts.kind
                .as_deref()
                .unwrap_or(if opts.file.is_some() { "audio" } else { "midi" });
        let tempo = self.project.tempo_map().clone();
        let (content, natural, default_name) = match kind {
            "midi" => {
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
            "audio" => {
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
            other => bail!("unknown clip kind `{other}`"),
        };
        let length = opts.length.unwrap_or(natural);
        if !length.is_finite() || length <= 0.0 || !opts.start.is_finite() || opts.start < 0.0 {
            bail!("clips need a start of at least 0 and a length above 0");
        }
        check_fade(opts.fade_in)?;
        check_fade(opts.fade_out)?;
        if kind == "midi" && (opts.fade_in > 0.0 || opts.fade_out > 0.0) {
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
                timebase: opts.timebase.filter(|_| kind == "audio"),
                stretch,
                pitch: opts.pitch,
                stretch_mode: opts.stretch_mode,
                source_tempo: opts.source_tempo.filter(|_| kind == "audio"),
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
        let plain = matches!(key, "start" | "length" | "name" | "muted");
        let held = match self.project.find_clip(id) {
            Some((track, index)) if plain => {
                let c = &self.project.track(track).unwrap().clips[index];
                let view = json!({ "start": c.start, "length": c.length, "name": c.name, "muted": c.muted });
                holds(&Ok(view), key, &value)
            }
            _ => holds(&self.clip_view(id), key, &value),
        };
        if held {
            return Ok(());
        }
        // Another file for an audio clip (another take) has to be one that
        // can be read, before the clip is changed.
        let new_file = match (key, value.as_str()) {
            ("file", Some(path)) => {
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
            if cue && key == "start" {
                bail!("a clip off the timeline starts at 0");
            }
            if cue && key == "track" {
                cues::move_cue(p, id, de(key, value)?)?;
                return Ok(());
            }
            if key == "track" {
                let (from, index) = p.find_clip(id).with_context(|| format!("no clip {id}"))?;
                let to: Id = de(key, value)?;
                if to == MASTER_ID {
                    bail!("the master track has no clips: put them on a track");
                }
                if p.track(to).is_none() {
                    bail!("no track {to}");
                }
                let clip = p.track_mut(from).unwrap().clips.remove(index);
                let clips = &mut p.track_mut(to).unwrap().clips;
                clips.push(clip);
                let at = clips.len() - 1;
                p.found_clip(id, to, at);
                return Ok(());
            }
            let c = p.clip_mut(id).with_context(|| format!("no clip {id}"))?;
            match (key, &mut c.content) {
                ("name", _) => c.name = de(key, value)?,
                ("start", _) => c.start = de::<f64>(key, value)?.max(0.0),
                ("length", _) => {
                    let length: f64 = de(key, value)?;
                    if !length.is_finite() || length <= 0.0 {
                        bail!("clip length must be above 0");
                    }
                    c.length = length;
                }
                ("muted", _) => c.muted = de(key, value)?,
                ("meta", _) => c.meta = de_meta(key, value)?,
                ("file", ClipContent::Audio { file, .. }) => {
                    *file = new_file.context("an audio clip's file is a path")?
                }
                ("offset", ClipContent::Audio { offset, .. }) => {
                    *offset = de::<f64>(key, value)?.max(0.0)
                }
                ("gain", ClipContent::Audio { gain, .. }) => {
                    *gain = de::<f64>(key, value)?.clamp(-120.0, 24.0)
                }
                ("fade_in", ClipContent::Audio { .. }) => c.fade_in = check_fade(de(key, value)?)?,
                ("fade_out", ClipContent::Audio { .. }) => {
                    c.fade_out = check_fade(de(key, value)?)?
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
            }
        })
    }

    // --- automation --------------------------------------------------------

    /// The lowest and highest value a target takes: for a state lane with
    /// `states` states, the first and the last.
    fn target_range(&self, target: &Target, states: usize) -> (f64, f64) {
        match target {
            Target::Volume => (-120.0, 24.0),
            Target::Pan => (-1.0, 1.0),
            Target::Param { device, param } => self
                .live
                .get(device)
                .and_then(|l| l.params.iter().find(|p| &p.key == param))
                .map_or((f64::MIN, f64::MAX), |p| (p.min as f64, p.max as f64)),
            Target::State { .. } => (0.0, states.saturating_sub(1) as f64),
        }
    }

    /// Points made valid for a target: finite, at beat 0 or later, within the
    /// target's range, and sorted by beat (points sharing a beat keep their
    /// order). A state lane's points name a state of its `states` by number.
    fn clean_points(
        &self,
        target: &Target,
        states: usize,
        points: Vec<(f64, f64)>,
    ) -> Result<Vec<(f64, f64)>> {
        let (min, max) = self.target_range(target, states);
        let whole = matches!(target, Target::State { .. });
        if whole && states == 0 && !points.is_empty() {
            bail!("the state lane has no states yet: add one first");
        }
        let mut points = points
            .into_iter()
            .map(|(beat, value)| {
                if !beat.is_finite() || !value.is_finite() {
                    bail!("automation points need a finite beat and value");
                }
                let value = if whole { value.round() } else { value };
                Ok((beat.max(0.0), value.clamp(min, max)))
            })
            .collect::<Result<Vec<_>>>()?;
        points.sort_by(|a, b| a.0.total_cmp(&b.0));
        Ok(points)
    }

    pub fn lane_view(&self, id: Id) -> Result<Value> {
        let (track, _) = self
            .project
            .find_lane(id)
            .with_context(|| format!("no lane {id}"))?;
        Ok(self.lane_json(self.project.lane(id).unwrap(), track))
    }

    fn lane_json(&self, l: &Lane, track: Id) -> Value {
        let (min, max) = self.target_range(&l.target, l.states.len());
        let mut v = json!({
            "id": l.id, "track": track, "enabled": l.enabled, "point_count": l.points.len(),
            "min": min, "max": max,
        });
        match &l.target {
            Target::Volume => v["target"] = json!("volume"),
            Target::Pan => v["target"] = json!("pan"),
            Target::Param { device, param } => {
                v["target"] = json!("param");
                v["device"] = json!(device);
                v["param"] = json!(param);
            }
            Target::State { device } => {
                v["target"] = json!("state");
                v["device"] = json!(device);
                v["states"] = json!(l.states.iter().map(|s| s.name.as_str()).collect::<Vec<_>>());
            }
        }
        v
    }

    /// The automation lanes of a track, without their points.
    pub fn lane_list(&self, track: Id) -> Result<Value> {
        let t = self
            .project
            .track(track)
            .with_context(|| format!("no track {track}"))?;
        Ok(Value::Array(
            t.lanes.iter().map(|l| self.lane_json(l, track)).collect(),
        ))
    }

    pub fn lane_add(&mut self, track: Id, opts: LaneOpts) -> Result<Id> {
        if self.project.track(track).is_none() {
            bail!("no track {track}");
        }
        let target = match opts.target.as_str() {
            "volume" => Target::Volume,
            "pan" => Target::Pan,
            "param" => {
                let device = opts.device.context("parameter lanes need a `device`")?;
                let name = opts
                    .param
                    .as_deref()
                    .context("parameter lanes need a `param`")?;
                if self.project.find_device(device).map(|(t, _)| t) != Some(track) {
                    bail!("device {device} is not on track {track}");
                }
                Target::Param {
                    device,
                    param: self.param_info(device, name)?.key,
                }
            }
            "state" => {
                let device = opts.device.context("state lanes need a `device`")?;
                if self.project.find_device(device).map(|(t, _)| t) != Some(track) {
                    bail!("device {device} is not on track {track}");
                }
                Target::State { device }
            }
            other => bail!("cannot automate `{other}`: use volume, pan, param or state"),
        };
        let states = opts
            .states
            .into_iter()
            .map(|s| self.check_lane_state(s).map(Arc::new))
            .collect::<Result<Vec<_>>>()?;
        if !states.is_empty() && !matches!(target, Target::State { .. }) {
            bail!("only a state lane has `states`");
        }
        if self
            .project
            .track(track)
            .unwrap()
            .lanes
            .iter()
            .any(|l| l.target == target)
        {
            bail!("track {track} already has a lane for that");
        }
        if let Target::Param { device, param } = &target
            && !self
                .project
                .device(*device)
                .unwrap()
                .params
                .contains_key(param)
        {
            // Give the parameter a value of its own in the project, so that
            // there is something to return to when the lane is turned off.
            let value = self.device_view(*device)?["params"][param].as_f64();
            let key = param.clone();
            self.edit(|p| {
                let params = &mut p.device_mut(*device).unwrap().params;
                params.insert(key, value.unwrap_or_default());
                Ok(())
            })?;
        }
        let points = self.clean_points(&target, states.len(), opts.points)?;
        let id = self.new_id();
        self.edit(|p| {
            p.track_mut(track).unwrap().lanes.push(Arc::new(Lane {
                id,
                target,
                enabled: opts.enabled.unwrap_or(true),
                points,
                shapes: Vec::new(),
                states,
            }));
            Ok(id)
        })
    }

    pub fn lane_remove(&mut self, id: Id) -> Result<()> {
        self.edit(|p| {
            let (track, index) = p.find_lane(id).with_context(|| format!("no lane {id}"))?;
            p.track_mut(track).unwrap().lanes.remove(index);
            Ok(())
        })
    }

    pub fn lane_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        if holds(&self.lane_view(id), key, &value) {
            return Ok(());
        }
        self.edit(|p| {
            let l = p.lane_mut(id).with_context(|| format!("no lane {id}"))?;
            match key {
                "enabled" => l.enabled = de(key, value)?,
                _ => bail!("lanes have no settable field `{key}`"),
            }
            Ok(())
        })
    }

    pub fn lane_points(&self, id: Id) -> Result<&[(f64, f64)]> {
        Ok(&self
            .project
            .lane(id)
            .with_context(|| format!("no lane {id}"))?
            .points)
    }

    /// Replace a lane's points, or add one, replacing any already at its beat.
    pub fn lane_set_points(&mut self, id: Id, new: Vec<(f64, f64)>, add: bool) -> Result<()> {
        let lane = self
            .project
            .lane(id)
            .with_context(|| format!("no lane {id}"))?
            .clone();
        let states = lane.states.len();
        let mut points = self.clean_points(&lane.target, states, new)?;
        if add {
            let mut all = lane.points.clone();
            all.retain(|p| !points.iter().any(|n| n.0 == p.0));
            all.append(&mut points);
            points = self.clean_points(&lane.target, states, all)?;
        }
        self.edit(|p| {
            let lane = p.lane_mut(id).unwrap();
            // A shape stays with a point that stays where it was.
            lane.shapes.retain(|s| points.iter().any(|q| q.0 == s.beat));
            lane.points = points;
            Ok(())
        })
    }

    /// The shapes of a lane's stretches that are not straight.
    pub fn lane_shapes(&self, id: Id) -> Result<&[Segment]> {
        Ok(&self
            .project
            .lane(id)
            .with_context(|| format!("no lane {id}"))?
            .shapes)
    }

    /// Replace the shapes of a lane's stretches: each by the beat of a point
    /// of the lane; a straight one need not be listed.
    pub fn lane_set_shapes(&mut self, id: Id, shapes: Vec<Segment>) -> Result<()> {
        let lane = self.project.lane(id).with_context(|| format!("no lane {id}"))?;
        let mut kept: Vec<Segment> = Vec::new();
        for mut s in shapes {
            if !s.beat.is_finite() || !s.tension.is_finite() {
                bail!("a shape needs a finite beat and tension");
            }
            if !lane.points.iter().any(|q| q.0 == s.beat) {
                bail!("lane {id} has no point at beat {} to shape", s.beat);
            }
            s.tension = s.tension.clamp(-1.0, 1.0);
            kept.retain(|k| k.beat != s.beat);
            if s.shape != Shape::Linear {
                kept.push(s);
            }
        }
        kept.sort_by(|a, b| a.beat.total_cmp(&b.beat));
        self.edit(|p| {
            p.lane_mut(id).unwrap().shapes = kept;
            Ok(())
        })
    }

    /// The lane's value at a beat, or nothing when it has no points.
    pub fn lane_value_at(&self, id: Id, beat: f64) -> Result<Option<f64>> {
        let lane = self.project.lane(id).with_context(|| format!("no lane {id}"))?;
        Ok(paw_engine::automation::value_at(&lane.played(), beat))
    }

    /// A state for a state lane, checked: a name, a state that is base64,
    /// a program within MIDI's range.
    fn check_lane_state(&self, mut state: LaneState) -> Result<LaneState> {
        state.name = state.name.trim().to_string();
        if state.name.is_empty() {
            bail!("a lane's state needs a `name`");
        }
        if let Some(text) = &state.state {
            BASE64
                .decode(text)
                .context("a lane's `state` is the plugin's state in base64")?;
        }
        if state.program.is_some_and(|p| p > 127) {
            bail!("a program is from 0 to 127");
        }
        if state.bank.is_some_and(|b| b > 16383) {
            bail!("a bank is from 0 to 16383");
        }
        if state.bank.is_some() && state.program.is_none() {
            bail!("a bank goes with a `program`");
        }
        if let Some(call) = &state.call
            && call.method.is_empty()
        {
            bail!("a lane state's `call` needs a `method`");
        }
        if state.state.is_none()
            && state.call.is_none()
            && state.params.is_empty()
            && state.program.is_none()
        {
            bail!("a lane's state needs a `state`, `call`, `params` or `program`");
        }
        Ok(state)
    }

    /// The states of a state lane, whole.
    pub fn lane_states(&self, id: Id) -> Result<Vec<Arc<LaneState>>> {
        let lane = self.project.lane(id).with_context(|| format!("no lane {id}"))?;
        if !matches!(lane.target, Target::State { .. }) {
            bail!("lane {id} is not a state lane");
        }
        Ok(lane.states.clone())
    }

    /// Replace the states of a state lane, as one edit. A point that names
    /// a state no longer there names the last; with no states, the points go.
    pub fn lane_set_states(&mut self, id: Id, states: Vec<LaneState>) -> Result<()> {
        self.lane_states(id)?;
        let states = states
            .into_iter()
            .map(|s| self.check_lane_state(s).map(Arc::new))
            .collect::<Result<Vec<_>>>()?;
        let mut names = std::collections::HashSet::new();
        if let Some(twice) = states.iter().find(|s| !names.insert(s.name.as_str())) {
            bail!("two states are named `{}`", twice.name);
        }
        let lane = self.project.lane(id).unwrap().clone();
        let points = if states.is_empty() {
            Vec::new()
        } else {
            self.clean_points(&lane.target, states.len(), lane.points.clone())?
        };
        self.edit(|p| {
            let lane = p.lane_mut(id).unwrap();
            lane.states = states;
            lane.points = points;
            Ok(())
        })
    }

    /// Add a state to a state lane, or replace the one of the same name,
    /// as one edit. Returns its index, from 0.
    pub fn lane_add_state(&mut self, id: Id, state: LaneState) -> Result<usize> {
        let mut states: Vec<LaneState> =
            self.lane_states(id)?.iter().map(|s| (**s).clone()).collect();
        let state = self.check_lane_state(state)?;
        let index = match states.iter().position(|s| s.name == state.name) {
            Some(i) => {
                states[i] = state;
                i
            }
            None => {
                states.push(state);
                states.len() - 1
            }
        };
        self.lane_set_states(id, states)?;
        Ok(index)
    }

    // --- transport ---------------------------------------------------------

    fn send_transport(&mut self) {
        let t = &self.transport;
        self.handle.send(Msg::SetLoop {
            enabled: t.loop_enabled,
            start: t.loop_start,
            end: t.loop_end,
        });
        self.handle.send(Msg::SetMetronome(t.metronome));
        self.handle.send(Msg::SetClick {
            gain: paw_engine::db_to_gain(t.click_level),
            accent: t.click_accent,
            output: t.click_output as u16,
        });
    }

    /// Where a take punched in from a stop starts playing: the pre-roll
    /// before the punch in, but never later than the playhead (a playhead
    /// further back is left alone), and not at all when the playhead is
    /// inside the range or past it.
    fn pre_roll_start(&self) -> Option<f64> {
        let t = &self.transport;
        if !t.recording || self.playing || !t.punch_enabled || t.punch_end <= t.punch_start {
            return None;
        }
        if t.pre_roll == 0 && t.pre_roll_seconds <= 0.0 {
            return None;
        }
        let at = self.position();
        if at > t.punch_start + 1e-9 {
            return None;
        }
        let map = self.project.tempo_map();
        let bar = (map.bar_of(t.punch_start) - t.pre_roll as i64).max(0);
        let from = map.bar_start(bar);
        let from = map.beat((map.seconds(from) - t.pre_roll_seconds).max(0.0));
        Some(from.min(at))
    }

    pub fn play(&mut self) {
        if let Some(from) = self.pre_roll_start() {
            self.seek(from);
        }
        self.flush();
        if self.transport.recording {
            self.start_take();
        }
        self.read_ahead_from(self.position());
        // A take begun with the song stopped is counted in first.
        let count = (self.transport.recording && !self.playing && self.transport.count_in > 0)
            .then(|| self.count_in())
            .flatten();
        let beats = match count {
            Some((msg, beats)) => {
                self.handle.send(msg);
                beats
            }
            None => {
                self.handle.send(Msg::Play);
                0
            }
        };
        self.count_sent = beats;
        self.playing = true;
        self.events.push((
            "transport.play".into(),
            json!({ "position": self.position(), "count_in": beats }),
        ));
    }

    /// The count-in before playing from where the playhead is: as many bars
    /// as `count_in` says, at the tempo and in the signature there, a click
    /// for every beat of the signature. The message for the engine, and how
    /// many beats it counts.
    fn count_in(&self) -> Option<(Msg, u32)> {
        let map = self.project.tempo_map();
        let at = self.position();
        let (num, den) = map.signature(at);
        let every = 60.0 / map.tempo(at) * 4.0 / den as f64 * self.handle.sample_rate;
        let clicks = self.transport.count_in.min(16) * num;
        let frames = (clicks as f64 * every).round() as u64;
        (frames > 0).then_some((
            Msg::CountIn {
                frames,
                every,
                clicks,
                per_bar: num,
            },
            clicks,
        ))
    }

    /// Beats of a count-in still to be counted before the song starts; 0
    /// when none is under way.
    pub fn counting(&self) -> u32 {
        let shared = &self.handle.shared;
        if !self.playing || shared.playing() {
            return 0;
        }
        // Until the engine has taken the count up, it is all still to come.
        match shared.counting() {
            0 => self.count_sent,
            left => left,
        }
    }

    pub fn stop(&mut self) {
        if self.playing {
            self.handle.send(Msg::Stop);
            self.playing = false;
            // The engine stops at its next block. Wait for that, so that the
            // position read from here on is where it stopped.
            let deadline = Instant::now() + Duration::from_millis(200);
            while self.handle.shared.playing() && Instant::now() < deadline {
                std::thread::sleep(Duration::from_micros(200));
            }
            self.events.push((
                "transport.stop".into(),
                json!({ "position": self.position() }),
            ));
            // Stopping ends the take and, with it, record mode: the next
            // play is a play, not another take over the one just made.
            if self.take.is_some() {
                self.transport.recording = false;
                self.events.push(("transport.changed".into(), json!({})));
            }
            self.finish_take();
        }
    }

    pub fn seek(&mut self, beats: f64) {
        let beats = beats.max(0.0);
        // A take is continuous, so jumping ends it and starts another.
        let recording = self.take.is_some();
        self.finish_take();
        self.handle.send(Msg::Seek(beats));
        self.seeks = self.seeks.wrapping_add(1);
        self.seek_target = beats;
        self.read_ahead_from(beats);
        self.events
            .push(("transport.seek".into(), json!({ "position": beats })));
        if recording && self.playing {
            self.start_take();
        }
    }

    /// Turn on recording and play.
    pub fn record(&mut self) -> Result<()> {
        self.transport_set("recording", Value::Bool(true))?;
        if !self.playing {
            self.play();
        }
        Ok(())
    }

    /// Where new recordings go: `media` beside the project file, or the user's
    /// data directory for a project that has never been saved.
    pub fn media_dir(&self) -> PathBuf {
        match &self.path {
            Some(path) => std::path::absolute(path)
                .unwrap_or_else(|_| path.clone())
                .with_file_name("media"),
            None => scratch_media_dir(),
        }
    }

    /// Start capturing every armed track: audio from those with an input,
    /// notes from the others.
    fn start_take(&mut self) {
        if self.take.is_some() {
            return;
        }
        // The engine has to know the tracks before it can capture them.
        self.flush();
        self.takes += 1;
        let number = self.takes;
        let shared = Arc::new(TakeShared::default());
        let sample_rate = self.handle.sample_rate as u32;
        let inputs = self.stream.info.input_channels as usize;
        let dir = self.media_dir();
        let mut audio = Vec::new();
        let mut captures = Vec::new();
        for track in self.project.tracks.iter().filter(|t| t.armed) {
            let Some((first, channels)) = track.input_channels() else {
                continue;
            };
            if first + channels > inputs {
                self.warnings.push(format!(
                    "{} records input {} but the audio device has {inputs} input channels",
                    track.name,
                    track.input.as_deref().unwrap_or("")
                ));
            }
            let started = std::fs::create_dir_all(&dir)
                .with_context(|| format!("creating {}", dir.display()))
                .and_then(|()| {
                    let path =
                        unique_path(&dir, &format!("{}-take{number}", file_safe(&track.name)));
                    // Two seconds of room for the writer to fall behind by.
                    let (tx, rx) = RingBuffer::new(sample_rate as usize * channels * 2);
                    let thread = record::spawn_writer(
                        &path,
                        sample_rate,
                        channels as u16,
                        rx,
                        shared.clone(),
                    )?;
                    Ok((path, thread, tx))
                });
            match started {
                Ok((path, thread, ring)) => {
                    audio.push((track.id, path, thread));
                    captures.push(AudioCapture {
                        first,
                        channels,
                        ring,
                    });
                }
                Err(err) => self
                    .warnings
                    .push(format!("cannot record {}: {err:#}", track.name)),
            }
        }
        let channels: usize = captures.iter().map(|c| c.channels).sum();
        let (midi_tx, midi_rx) = RingBuffer::new(16384);
        let (wraps_tx, wraps_rx) = RingBuffer::new(4096);
        let t = &self.transport;
        let looped = (t.loop_enabled && t.loop_end > t.loop_start)
            .then_some((t.loop_start, t.loop_end));
        let punch = (t.punch_enabled && t.punch_end > t.punch_start)
            .then_some((t.punch_start, t.punch_end));
        let mut take = Take::new(captures, midi_tx, shared.clone(), wraps_tx);
        if let Some((from, to)) = punch {
            // What is played at the punch out arrives as late as the
            // recording is behind the song: capture that much past it.
            let map = self.project.tempo_map();
            take.punch = Some((from, map.beat(map.seconds(to) + self.record_latency(true))));
            let at = self.position();
            let comes_round = looped.is_some_and(|(start, end)| at < end && start < to);
            if at >= to - 1e-9 && !comes_round {
                self.warnings.push(format!(
                    "the playhead is past the punch out (bar {}): nothing will be recorded",
                    map.bar_of(to) + 1
                ));
            }
        }
        self.handle.send(Msg::SetTake(Some(Box::new(take))));
        self.take = Some(Recording {
            number,
            shared,
            audio,
            midi: midi_rx,
            held: HashMap::new(),
            notes: BTreeMap::new(),
            controls: BTreeMap::new(),
            looped,
            punch,
            wraps: wraps_rx,
            wrapped: Vec::new(),
        });
        // Where the files go and how fast they grow, for a warning when
        // the disk is nearly full; and the files, for a safety copy.
        let files: Vec<&PathBuf> = self
            .take
            .iter()
            .flat_map(|t| t.audio.iter().map(|a| &a.1))
            .collect();
        let payload = json!({
            "position": self.position(), "take": number, "dir": dir,
            "bytes_per_second": channels * 4 * sample_rate as usize,
            "free": crate::safe::free_space(&dir), "files": files,
        });
        self.events.push(("transport.record".into(), payload));
    }

    /// The take being recorded, as a safety copy keeps it: its files, which
    /// track each is for and where it starts, so that the take can be put
    /// back as clips if the program never gets to finish it.
    fn take_in_progress(&self) -> Value {
        let Some(take) = &self.take else {
            return Value::Null;
        };
        let start = take.shared.start().unwrap_or_else(|| self.position());
        let files: Vec<Value> = take
            .audio
            .iter()
            .map(|(track, path, _)| json!({ "track": track, "file": path }))
            .collect();
        json!({
            "name": format!("take {}", take.number), "start": start,
            "offset": self.record_latency(true), "files": files,
        })
    }

    /// A take that was being recorded when a safety copy was made, put back
    /// as clips from whatever its files hold.
    fn restore_take(&mut self, take: &Value) {
        let Some(files) = take["files"].as_array() else {
            return;
        };
        let start = take["start"].as_f64().unwrap_or(0.0);
        for entry in files {
            let (Some(track), Some(file)) = (entry["track"].as_u64(), entry["file"].as_str())
            else {
                continue;
            };
            // The project's folder may have moved since: look in its `media`.
            let mut path = PathBuf::from(file);
            if !path.exists()
                && let Some(name) = path.file_name()
                && self.media_dir().join(name).exists()
            {
                path = self.media_dir().join(name);
            }
            let opts = ClipOpts {
                name: take["name"].as_str().map(String::from),
                start,
                file: Some(path),
                offset: take["offset"].as_f64().unwrap_or(0.0),
                source_tempo: Some(self.project.tempo_map().tempo(start)),
                ..ClipOpts::default()
            };
            if let Err(err) = self.clip_add(track as Id, opts) {
                self.warnings
                    .push(format!("the take in {file} could not be put back: {err:#}"));
            }
        }
    }

    /// Collect the notes the engine has captured for the take so far.
    fn drain_take(&mut self) {
        let Some(take) = self.take.as_mut() else {
            return;
        };
        while let Ok(frames) = take.wraps.pop() {
            take.wrapped.push(frames);
        }
        while let Ok(capture) = take.midi.pop() {
            let Some(track) = self
                .map
                .tracks
                .iter()
                .find(|(_, slot)| **slot == capture.slot)
                .map(|(id, _)| *id)
            else {
                continue;
            };
            match capture.kind {
                EventKind::NoteOn { key, vel, attr, .. } => {
                    take.end_note(track, key, capture.beat, capture.pass);
                    let velocity = (vel * 127.0).round().clamp(1.0, 127.0) as u8;
                    let note = (capture.beat, velocity, capture.pass, NoteAttr::of(attr));
                    take.held.insert((track, key), note);
                }
                EventKind::NoteOff { key, .. } => {
                    take.end_note(track, key, capture.beat, capture.pass)
                }
                EventKind::Control { .. }
                | EventKind::NoteControl { .. }
                | EventKind::Program { .. } => {
                    if let Some(control) = Control::from_event(capture.beat, capture.kind) {
                        take.controls
                            .entry((track, capture.pass))
                            .or_default()
                            .push(control);
                    }
                }
                EventKind::AllNotesOff => {
                    let keys: Vec<u8> = take
                        .held
                        .keys()
                        .filter(|(t, _)| *t == track)
                        .map(|(_, k)| *k)
                        .collect();
                    for key in keys {
                        take.end_note(track, key, capture.beat, capture.pass);
                    }
                }
            }
        }
    }

    /// Stop capturing and turn what was captured into clips where the take
    /// began, as one undo step.
    fn finish_take(&mut self) {
        let Some(shared) = self.take.as_ref().map(|t| t.shared.clone()) else {
            return;
        };
        self.handle.send(Msg::SetTake(None));
        let deadline = Instant::now() + Duration::from_secs(2);
        while !shared.closed() && Instant::now() < deadline {
            self.handle.collect_garbage();
            std::thread::sleep(Duration::from_millis(1));
        }
        // No engine is running to let go of the take, so let go of it here.
        shared.close(self.position());
        self.drain_take();
        let mut take = self.take.take().unwrap();
        let (start, end) = (shared.start(), shared.end());
        let rounds = take.wrapped.len() as u32;
        let held: Vec<(Id, u8)> = take.held.keys().copied().collect();
        for (track, key) in held {
            take.end_note(track, key, end, rounds);
        }
        // The take as the times it went round the loop, or as the one
        // stretch it is.
        let rate = self.handle.sample_rate;
        let mut looped = take.looped.filter(|_| rounds > 0);
        let mut passes: Vec<Pass> = Vec::new();
        if let (Some(start), Some(punch)) = (start, take.punch) {
            passes = self.punched_passes(&take, punch, start, end);
            // Several times round the punch range are takes of one clip
            // over it, as several times round the loop are over the loop.
            looped = (passes.len() > 1).then(|| {
                let stop = take.looped.map_or(punch.1, |(_, end)| punch.1.min(end));
                (punch.0, stop)
            });
        } else if let Some(start) = start {
            match looped {
                Some((loop_start, loop_end)) => {
                    passes.push(Pass {
                        index: 0,
                        start,
                        end: loop_end,
                        seconds: 0.0,
                    });
                    for (i, frames) in take.wrapped.iter().enumerate() {
                        let last = i + 1 == take.wrapped.len();
                        passes.push(Pass {
                            index: i as u32 + 1,
                            start: loop_start,
                            end: if last { end.min(loop_end) } else { loop_end },
                            seconds: *frames as f64 / rate,
                        });
                    }
                }
                None => passes.push(Pass {
                    index: 0,
                    start,
                    end,
                    seconds: 0.0,
                }),
            }
        }

        self.checkpoint();
        let name = format!("take {}", take.number);
        let audio = std::mem::take(&mut take.audio);
        for (track, path, thread) in audio {
            // A writer that stopped on an error has kept what it wrote, as a
            // whole WAV file: that becomes the clip like any other.
            let frames = match thread.join() {
                Ok(written) => {
                    if let Some(err) = written.error {
                        self.warnings.push(format!(
                            "recording stopped: writing {} failed ({err}); the {:.1} s before that are kept",
                            path.display(),
                            written.frames as f64 / self.handle.sample_rate
                        ));
                    }
                    written.frames
                }
                Err(_) => 0,
            };
            if frames == 0 || passes.is_empty() {
                let _ = std::fs::remove_file(&path);
                continue;
            }
            if let Err(err) =
                self.add_recorded_audio(track, &path, &name, &passes, looped, take.punch.is_some())
            {
                self.warnings.push(format!(
                    "recorded {} but could not add it: {err:#}",
                    path.display()
                ));
            }
        }
        if let Some(start) = start {
            // Notes are only late by what the player heard late.
            let map = self.project.tempo_map();
            let late = start - map.beat(map.seconds(start) - self.record_latency(false));
            let tracks: BTreeSet<Id> = take
                .notes
                .keys()
                .chain(take.controls.keys())
                .map(|(track, _)| *track)
                .collect();
            for track in tracks {
                if passes.is_empty() {
                    break;
                }
                if let Err(err) =
                    self.add_recorded_notes(track, &mut take, &name, &passes, looped, late)
                {
                    self.warnings
                        .push(format!("could not add the recorded notes: {err:#}"));
                }
            }
        }
        if shared.dropped() > 0 {
            self.warnings.push(format!(
                "the disk fell behind: {} frames of {name} were lost",
                shared.dropped()
            ));
        }
        self.checkpoint();
    }

    /// The times a punched take went through its range (`from` to `to`):
    /// one pass for each time round the loop that captured anything, each
    /// with where its sound begins in the take's files. Capturing began at
    /// `start` and the take was let go of at `end`.
    fn punched_passes(&self, take: &Recording, (from, to): (f64, f64), start: f64, end: f64) -> Vec<Pass> {
        let map = self.project.tempo_map();
        let rate = self.handle.sample_rate;
        // Capturing stops at the loop's end if that comes first, and after
        // a jump back starts again where the loop does if that is later.
        let (stop, again) = match take.looped {
            Some((loop_start, loop_end)) => (to.min(loop_end), from.max(loop_start)),
            None => (to, from),
        };
        // A block cut at the punch in may start a hair after it.
        let first = if map.seconds_between(from, start).abs() * rate < 1.5 {
            from
        } else {
            start.max(from)
        };
        let mut out = Vec::new();
        let mut before = 0u64;
        for round in 0..=take.wrapped.len() {
            let last = round == take.wrapped.len();
            let seconds = before as f64 / rate;
            let captured = if last {
                end > from + 1e-9
            } else {
                take.wrapped[round] > before
            };
            if !last {
                before = take.wrapped[round];
            }
            if !captured {
                continue;
            }
            let begin = if out.is_empty() { first } else { again };
            let finish = if last { end.min(stop) } else { stop };
            if finish - begin > 1e-9 {
                out.push(Pass {
                    index: round as u32,
                    start: begin,
                    end: finish,
                    seconds,
                });
            }
        }
        out
    }

    /// Turn a track's recorded file into clips. A take that never went
    /// round the loop is one clip where it began. One that did becomes a
    /// clip over the loop whose takes are the times round, the last of them
    /// the one that plays (`clip.meta.takes`, see `paw.takes`), and a clip
    /// before the loop for what was played on the way in.
    fn add_recorded_audio(
        &mut self,
        track: Id,
        path: &Path,
        name: &str,
        passes: &[Pass],
        looped: Option<(f64, f64)>,
        punched: bool,
    ) -> Result<()> {
        // What was played along with the song was heard late and arrived
        // late: leave that much off the front of the file.
        let latency = self.record_latency(true);
        let Some((loop_start, loop_end)) = looped else {
            let pass = &passes[0];
            let opts = ClipOpts {
                name: Some(name.to_string()),
                start: pass.start,
                // A punched take covers its punch range exactly; its file
                // holds a little more, for the latency.
                length: punched.then_some(pass.end - pass.start),
                file: Some(path.to_path_buf()),
                offset: latency + pass.seconds,
                source_tempo: Some(self.project.tempo_map().tempo(pass.start)),
                ..ClipOpts::default()
            };
            return self.clip_add(track, opts).map(|_| ());
        };
        let map = self.project.tempo_map().clone();
        let first = &passes[0];
        let last = &passes[passes.len() - 1];
        let whole = loop_end - loop_start;
        // The first time round counts from the loop's start if it began
        // there or before; the last if it got at least half way.
        let from_start = first.start <= loop_start + 1e-6;
        let lead = map.seconds_between(first.start.min(loop_start), loop_start);
        let mut kept: Vec<(&Pass, f64)> = Vec::new();
        if from_start {
            kept.push((first, latency + lead));
        }
        for pass in &passes[1..passes.len() - 1] {
            kept.push((pass, latency + pass.seconds));
        }
        let complete = !kept.is_empty();
        if last.end - loop_start >= whole / 2.0 || !complete {
            kept.push((last, latency + last.seconds));
        }
        let length = if complete {
            whole
        } else {
            last.end - loop_start
        };
        if from_start && first.start < loop_start - 1e-6 {
            // What was played on the way into the loop.
            let opts = ClipOpts {
                name: Some(format!("{name} lead-in")),
                start: first.start,
                length: Some(loop_start - first.start),
                file: Some(path.to_path_buf()),
                offset: latency,
                source_tempo: Some(map.tempo(first.start)),
                ..ClipOpts::default()
            };
            self.clip_add(track, opts)?;
        } else if !from_start {
            if first.start >= loop_start + length - 1e-6 {
                // It began after everything else ends: a clip of its own.
                let opts = ClipOpts {
                    name: Some(name.to_string()),
                    start: first.start,
                    length: Some(loop_end - first.start),
                    file: Some(path.to_path_buf()),
                    offset: latency,
                    source_tempo: Some(map.tempo(first.start)),
                    ..ClipOpts::default()
                };
                self.clip_add(track, opts)?;
            } else {
                self.warnings.push(format!(
                    "{name}: the first time round began in the middle of the loop and is left out; its sound is the first {:.1} s of {}",
                    map.seconds_between(first.start, loop_end),
                    path.display()
                ));
            }
        }
        if length <= 1e-6 {
            return Ok(());
        }
        let mut meta = Map::new();
        if kept.len() > 1 {
            let list: Vec<Value> = kept
                .iter()
                .enumerate()
                .map(|(i, (_, offset))| {
                    let label = format!("{name}.{}", i + 1);
                    if i + 1 == kept.len() {
                        json!({ "name": label })
                    } else {
                        json!({ "name": label, "file": path, "offset": offset, "gain": 0.0 })
                    }
                })
                .collect();
            // `origin`: the offset of the clip itself while the others'
            // offsets are as written here (see `paw.takes`).
            meta.insert(
                "takes".into(),
                json!({
                    "active": kept.len(), "origin": kept[kept.len() - 1].1, "list": list,
                }),
            );
        }
        let opts = ClipOpts {
            name: Some(name.to_string()),
            start: loop_start,
            length: Some(length),
            file: Some(path.to_path_buf()),
            offset: kept[kept.len() - 1].1,
            meta,
            source_tempo: Some(map.tempo(loop_start)),
            ..ClipOpts::default()
        };
        self.clip_add(track, opts).map(|_| ())
    }

    /// Turn the notes and controller moves recorded for a track into clips,
    /// as [`add_recorded_audio`](Self::add_recorded_audio) does for sound:
    /// every time round the loop that something was played in is a take.
    fn add_recorded_notes(
        &mut self,
        track: Id,
        take: &mut Recording,
        name: &str,
        passes: &[Pass],
        looped: Option<(f64, f64)>,
        late: f64,
    ) -> Result<()> {
        let mut played: Vec<(u32, Vec<Note>, Vec<Control>)> = Vec::new();
        for pass in passes {
            let notes = take.notes.remove(&(track, pass.index)).unwrap_or_default();
            let controls = take
                .controls
                .remove(&(track, pass.index))
                .unwrap_or_default();
            if !notes.is_empty() || !controls.is_empty() {
                played.push((pass.index, notes, controls));
            }
        }
        // Count from where a clip starts, moved earlier by the latency. A
        // punched take keeps what falls inside its range, and notes held
        // across the punch out end there.
        let punch = take.punch.map(|_| {
            looped.map_or(passes[0].end - passes[0].start, |(start, end)| end - start)
        });
        let place = |notes: &mut Vec<Note>, controls: &mut Vec<Control>, origin: f64| {
            for note in notes.iter_mut() {
                note.start = (note.start - origin - late).max(0.0);
            }
            for control in controls.iter_mut() {
                control.start = (control.start - origin - late).max(0.0);
            }
            if let Some(length) = punch {
                notes.retain(|n| n.start < length - 1e-9);
                for note in notes.iter_mut() {
                    note.length = note.length.min(length - note.start);
                }
                controls.retain(|c| c.start < length - 1e-9);
            }
        };
        let Some((loop_start, loop_end)) = looped else {
            let Some((_, mut notes, mut controls)) = played.pop() else {
                return Ok(());
            };
            let (start, end) = (passes[0].start, passes[0].end);
            place(&mut notes, &mut controls, start);
            let last = notes.iter().map(|n| n.start + n.length).fold(0.0, f64::max);
            let opts = ClipOpts {
                kind: Some("midi".into()),
                name: Some(name.to_string()),
                start,
                length: Some(punch.unwrap_or((end - start).max(last))),
                notes,
                controls,
                ..ClipOpts::default()
            };
            return self.clip_add(track, opts).map(|_| ());
        };
        // What was played on the way into the loop is a clip before it.
        let start = passes[0].start;
        if start < loop_start - 1e-6
            && let Some((0, notes, controls)) = played.first_mut()
        {
            let (mut before, inside): (Vec<Note>, Vec<Note>) = std::mem::take(notes)
                .into_iter()
                .partition(|n| n.start - late < loop_start);
            let (mut moves, later): (Vec<Control>, Vec<Control>) = std::mem::take(controls)
                .into_iter()
                .partition(|c| c.start - late < loop_start);
            *notes = inside;
            *controls = later;
            if !before.is_empty() || !moves.is_empty() {
                place(&mut before, &mut moves, start);
                for note in &mut before {
                    note.length = note.length.min(loop_start - start - note.start).max(1.0 / 128.0);
                }
                let opts = ClipOpts {
                    kind: Some("midi".into()),
                    name: Some(format!("{name} lead-in")),
                    start,
                    length: Some(loop_start - start),
                    notes: before,
                    controls: moves,
                    ..ClipOpts::default()
                };
                self.clip_add(track, opts)?;
            }
        }
        played.retain(|(_, notes, controls)| !notes.is_empty() || !controls.is_empty());
        let Some((_, mut notes, mut controls)) = played.pop() else {
            return Ok(());
        };
        place(&mut notes, &mut controls, loop_start);
        let mut meta = Map::new();
        if !played.is_empty() {
            let mut list: Vec<Value> = Vec::new();
            for (i, (_, mut notes, mut controls)) in played.into_iter().enumerate() {
                place(&mut notes, &mut controls, loop_start);
                list.push(json!({
                    "name": format!("{name}.{}", i + 1),
                    "notes": sorted(notes), "controls": controls,
                }));
            }
            list.push(json!({ "name": format!("{name}.{}", list.len() + 1) }));
            meta.insert(
                "takes".into(),
                json!({ "active": list.len(), "list": list }),
            );
        }
        let opts = ClipOpts {
            kind: Some("midi".into()),
            name: Some(name.to_string()),
            start: loop_start,
            length: Some(loop_end - loop_start),
            notes,
            controls,
            meta,
            ..ClipOpts::default()
        };
        self.clip_add(track, opts).map(|_| ())
    }

    /// Seconds by which what is recorded is behind the song it was played
    /// to: how late the output is heard, how late the input arrives (for
    /// audio), and the offset set by hand for what the system does not report.
    fn record_latency(&self, audio: bool) -> f64 {
        let info = &self.stream.info;
        let mut seconds = self.record_offset / 1000.0;
        if info.backend != "null" {
            seconds += info.buffer_size as f64 / info.sample_rate as f64;
            if audio {
                seconds += self.handle.shared.input_latency() as f64;
            }
        }
        seconds.max(0.0)
    }

    /// Recordings made before the project had a file live in the user's data
    /// directory. Saving links or copies them into the `media` directory
    /// beside the project and points the clips there. The originals stay,
    /// because earlier undo steps still refer to them.
    fn adopt_recordings(&mut self, path: &Path) -> Result<()> {
        let scratch = scratch_media_dir();
        let media = std::path::absolute(path)?.with_file_name("media");
        let mut moved: HashMap<PathBuf, PathBuf> = HashMap::new();
        for file in media::files(&self.project) {
            if !file.starts_with(&scratch) || moved.contains_key(&file) {
                continue;
            }
            std::fs::create_dir_all(&media)
                .with_context(|| format!("creating {}", media.display()))?;
            let stem = file.file_stem().unwrap_or_default().to_string_lossy();
            let target = unique_path(&media, &stem);
            std::fs::hard_link(&file, &target)
                .or_else(|_| std::fs::copy(&file, &target).map(|_| ()))
                .with_context(|| format!("copying {} to {}", file.display(), target.display()))?;
            moved.insert(file, target);
        }
        if moved.is_empty() {
            return Ok(());
        }
        for project in [&mut self.project, &mut self.checkpoint] {
            media::map_files(project, |file| moved.get(file).cloned());
        }
        self.dirty = true;
        Ok(())
    }

    // --- MIDI input --------------------------------------------------------

    /// Point MIDI input at the current engine, and open the ports while there
    /// is a real audio device. The null backend leaves them closed, so that
    /// scripts and tests only hear what they inject.
    fn connect_midi(&mut self) {
        if let Ok(mut sink) = self.midi_sink.lock() {
            sink.engine = self.handle.take_midi_input();
        }
        // The `test` backend's pretend device is as silent as the null one.
        if matches!(self.stream.info.backend.as_str(), "null" | "test") && !self.midi_without_audio
        {
            self.midi = None;
            self.midi_out = None;
            return;
        }
        self.connect_midi_out();
        if self.midi.is_none() {
            match MidiInputs::start(self.midi_sink.clone()) {
                Ok(midi) => {
                    if self.midi_select.is_some() {
                        midi.select(self.midi_select.clone());
                    }
                    for name in &self.midi_own {
                        midi.open_port(name);
                    }
                    self.midi = Some(midi);
                }
                Err(err) => self.warnings.push(format!("no MIDI input: {err:#}")),
            }
        }
    }

    pub fn midi_inputs(&self) -> Value {
        let mut ports = self.midi.as_ref().map(|m| m.ports()).unwrap_or_default();
        if self.midi.is_none() {
            ports = self
                .test_ports
                .iter()
                .enumerate()
                .map(|(i, name)| paw_engine::midi::PortInfo {
                    id: format!("test:{i}"),
                    name: name.clone(),
                    open: true,
                    own: false,
                })
                .collect();
            // Without a sequencer the ports of our own are still listed,
            // and `midi_inject` plays the part of whoever sends to them.
            ports.extend(self.midi_own.iter().enumerate().map(|(i, name)| {
                paw_engine::midi::PortInfo {
                    id: format!("own:{i}"),
                    name: name.clone(),
                    open: true,
                    own: true,
                }
            }));
        }
        Value::Array(
            ports
                .into_iter()
                .map(|p| json!({ "id": p.id, "name": p.name, "open": p.open, "own": p.own }))
                .collect(),
        )
    }

    /// Make a MIDI port of this program's, for other programs to send to:
    /// they see it as `paw: <name>`, and tracks choose it by `name` like
    /// any other port. It is kept through engine restarts.
    pub fn midi_open_port(&mut self, name: &str) -> Result<()> {
        if name.is_empty() || name.contains('\0') {
            bail!("a MIDI port needs a name");
        }
        if !self.midi_own.iter().any(|known| known == name) {
            self.midi_own.push(name.to_string());
            if let Some(midi) = &self.midi {
                midi.open_port(name);
            }
        }
        Ok(())
    }

    /// Take away a port made by `midi_open_port`. True if there was one.
    pub fn midi_close_port(&mut self, name: &str) -> bool {
        let Some(at) = self.midi_own.iter().position(|known| known == name) else {
            return false;
        };
        self.midi_own.remove(at);
        if let Some(midi) = &self.midi {
            midi.close_port(name);
        }
        true
    }

    /// Open only the MIDI ports matching `which` (ids or parts of names), or
    /// every port with `None`.
    pub fn midi_select(&mut self, which: Option<Vec<String>>) {
        if let Some(midi) = &self.midi {
            midi.select(which.clone());
        }
        self.midi_select = which;
    }

    /// Open the MIDI ports on the null backend too, from the next engine
    /// start: for trying real MIDI with no sound.
    pub fn set_midi_without_audio(&mut self, on: bool) {
        self.midi_without_audio = on;
    }

    /// MIDI ports for the null backend to list: see `test_ports`.
    pub fn set_test_ports(&mut self, ports: Vec<String>) {
        self.test_ports = ports;
    }

    /// Deliver a message as if it came from a MIDI input port, the one
    /// named `port` or none in particular.
    pub fn midi_inject(&mut self, kind: EventKind, port: Option<&str>) {
        self.flush();
        let port = port.map_or(0, paw_engine::midi::port_key);
        self.handle.send(Msg::MidiIn { port, kind });
        self.midi_event(port, kind);
    }

    /// Have `tap` told of everything the MIDI ports receive, on their thread.
    pub fn set_midi_tap(&mut self, tap: Box<dyn FnMut(u32, EventKind) + std::marker::Send>) {
        if let Ok(mut sink) = self.midi_sink.lock() {
            sink.tap = Some(tap);
        }
    }

    /// Tell scripts about a message from a MIDI port, as a `midi.in` event
    /// naming the port when it is one of those listed (`port` is its key).
    pub fn midi_event(&mut self, port: u32, kind: EventKind) {
        let mut payload = match kind {
            EventKind::NoteOn { key, vel, ch, attr } => {
                let mut payload = json!({
                    "type": "note_on", "pitch": key, "channel": ch + 1,
                    "velocity": (vel * 127.0).round(),
                });
                if let Some(attr) = NoteAttr::of(attr) {
                    payload["attr"] = json!(attr);
                }
                payload
            }
            EventKind::NoteOff { key, ch } => {
                json!({ "type": "note_off", "pitch": key, "channel": ch + 1 })
            }
            EventKind::Control { ch, .. }
            | EventKind::NoteControl { ch, .. }
            | EventKind::Program { ch, .. } => {
                // The same shape a clip keeps it in, with the channel it came on.
                let mut payload = json!(Control::from_event(0.0, kind));
                payload["channel"] = json!(ch + 1);
                payload.as_object_mut().map(|o| o.remove("start"));
                payload
            }
            EventKind::AllNotesOff => return,
        };
        let name = self.midi_inputs().as_array().and_then(|ports| {
            ports
                .iter()
                .filter_map(|p| p["name"].as_str())
                .find(|name| paw_engine::midi::port_key(name) == port)
                .map(str::to_string)
        });
        if let Some(name) = name {
            payload["port"] = json!(name);
        }
        self.events.push(("midi.in".into(), payload));
    }

    pub fn playing(&self) -> bool {
        self.playing
    }

    /// Transport position in beats.
    pub fn position(&self) -> f64 {
        // Until the engine has carried out the last seek, its position is stale.
        if self.handle.shared.seeks() != self.seeks {
            return self.seek_target;
        }
        self.handle.shared.position()
    }

    pub fn transport_view(&self) -> Value {
        let t = &self.transport;
        json!({
            "playing": self.playing, "position": self.position(), "tempo": self.project.tempo,
            "loop_enabled": t.loop_enabled, "loop_start": t.loop_start, "loop_end": t.loop_end,
            "metronome": t.metronome, "recording": t.recording,
            "punch_enabled": t.punch_enabled, "punch_start": t.punch_start, "punch_end": t.punch_end,
            "count_in": t.count_in, "counting": self.counting(),
            "pre_roll": t.pre_roll, "pre_roll_seconds": t.pre_roll_seconds,
            "click_level": t.click_level, "click_accent": t.click_accent, "click_output": t.click_output,
            "record_offset": self.record_offset,
            "write": self.write,
            "take": self.take.as_ref().map(|t| t.number),
        })
    }

    pub fn transport_set(&mut self, key: &str, value: Value) -> Result<()> {
        if key == "write" {
            self.write = de(key, value)?;
            self.events.push(("transport.changed".into(), json!({})));
            return Ok(());
        }
        if key == "record_offset" {
            let ms: f64 = de(key, value)?;
            if !ms.is_finite() {
                bail!("the recording offset is a number of milliseconds");
            }
            self.record_offset = ms;
            return Ok(());
        }
        let t = &mut self.transport;
        match key {
            "loop_enabled" => t.loop_enabled = de(key, value)?,
            "loop_start" => t.loop_start = de::<f64>(key, value)?.max(0.0),
            "loop_end" => t.loop_end = de::<f64>(key, value)?.max(0.0),
            "metronome" => t.metronome = de(key, value)?,
            "recording" => t.recording = de(key, value)?,
            "punch_enabled" => t.punch_enabled = de(key, value)?,
            "punch_start" => t.punch_start = finite(key, de(key, value)?)?.max(0.0),
            "punch_end" => t.punch_end = finite(key, de(key, value)?)?.max(0.0),
            "count_in" => {
                let bars: f64 = de(key, value)?;
                if !(0.0..=16.0).contains(&bars) {
                    bail!("a count-in is from 0 to 16 bars");
                }
                t.count_in = bars as u32;
            }
            "pre_roll" => {
                let bars: f64 = de(key, value)?;
                if !(0.0..=16.0).contains(&bars) {
                    bail!("a pre-roll is from 0 to 16 bars");
                }
                t.pre_roll = bars as u32;
            }
            "pre_roll_seconds" => {
                let seconds: f64 = de(key, value)?;
                if !(0.0..=30.0).contains(&seconds) {
                    bail!("a pre-roll is from 0 to 30 seconds");
                }
                t.pre_roll_seconds = seconds;
            }
            "click_level" => {
                let db: f64 = de(key, value)?;
                if !(-60.0..=12.0).contains(&db) {
                    bail!("the click's level is from -60 to +12 dB");
                }
                t.click_level = db;
            }
            "click_accent" => t.click_accent = de(key, value)?,
            "click_output" => {
                let channel: f64 = de(key, value)?;
                if !(0.0..=64.0).contains(&channel) || channel.fract() != 0.0 {
                    bail!("the click's output is a channel from 1 to 64, or 0 for with the song");
                }
                t.click_output = channel as u32;
            }
            _ => bail!("the transport has no settable field `{key}`"),
        }
        // Turning recording on or off while playing punches in or out.
        if key == "recording" {
            if !self.transport.recording {
                self.finish_take();
            } else if self.playing {
                self.start_take();
            }
        }
        self.send_transport();
        self.events.push(("transport.changed".into(), json!({})));
        Ok(())
    }

    /// Play a note on a track right now, outside the timeline.
    pub fn live(&mut self, track: Id, event: EventKind) -> Result<()> {
        self.flush();
        let slot = *self
            .map
            .tracks
            .get(&track)
            .with_context(|| format!("no track {track}"))?;
        self.handle.send(Msg::Live { track: slot, event });
        Ok(())
    }

    /// Play a note on a track now, with its attribute: what the track's
    /// attribute map sends for it goes first.
    pub fn live_note(&mut self, track: Id, key: u8, vel: f32, attr: paw_engine::Attr) -> Result<()> {
        let plan = self
            .project
            .track(track)
            .and_then(|t| t.attr_map.as_ref())
            .and_then(|m| m.plan().ok());
        let (before, ch, keep) = match &plan {
            Some(plan) => plan.live(attr),
            None => (Vec::new(), None, true),
        };
        for event in before {
            self.live(track, event)?;
        }
        let attr = if keep { attr } else { paw_engine::Attr::NONE };
        let ch = ch.unwrap_or(0);
        self.live(track, EventKind::NoteOn { key, vel, ch, attr })
    }

    /// The milliseconds a note with `attr` is moved by the track's attribute map.
    pub fn attr_delay(&self, track: Id, attr: paw_engine::Attr) -> Result<f64> {
        let track = self
            .project
            .track(track)
            .with_context(|| format!("no track {track}"))?;
        Ok(match &track.attr_map {
            Some(map) => map.plan()?.delay_of(attr),
            None => 0.0,
        })
    }

    /// Stop a note played with [`live_note`](Self::live_note), on every
    /// channel the track's attribute map may have sent it to.
    pub fn live_note_off(&mut self, track: Id, key: u8) -> Result<()> {
        let channels = self
            .project
            .track(track)
            .and_then(|t| t.attr_map.as_ref())
            .and_then(|m| m.plan().ok())
            .map(|plan| plan.channels())
            .unwrap_or_default();
        for ch in channels {
            self.live(track, EventKind::NoteOff { key, ch })?;
        }
        self.live(track, EventKind::NoteOff { key, ch: 0 })
    }

    /// Post-fader peak level of a track as linear `(left, right)`.
    pub fn meter(&self, track: Id) -> (f32, f32) {
        self.map
            .tracks
            .get(&track)
            .map(|slot| self.handle.shared.meter(*slot))
            .unwrap_or((0.0, 0.0))
    }

    // --- engine ------------------------------------------------------------

    pub fn engine_info(&self) -> Value {
        let info: &StreamInfo = &self.stream.info;
        json!({
            "backend": info.backend, "device": info.device, "sample_rate": info.sample_rate,
            "device_id": info.device_id, "input_device_id": info.input_device_id,
            "buffer_size": info.buffer_size, "cpu": self.handle.shared.cpu(),
            // Frames per callback as the device runs it, 0 until it has.
            "block": self.handle.shared.period(),
            "xruns": self.handle.shared.xruns(), "input_device": info.input_device,
            "input_channels": info.input_channels,
            "input_latency": self.handle.shared.input_latency() as f64 * 1000.0,
            "output_latency": self.handle.shared.output_latency() as f64 * 1000.0,
            // How far the output is behind the transport because of devices
            // that look ahead, in milliseconds.
            "latency": self.map.latency as f64 * 1000.0 / info.sample_rate as f64,
            "midi": self.midi.is_some(),
            "blocks": block_json(&self.handle.shared.blocks.summary(), info.sample_rate),
            "leaked": self.handle.shared.leaked(),
            // Threads tracks are processed on, counting the audio thread, and
            // what was asked for (0 leaves it to the machine).
            "threads": self.handle.shared.threads(),
            "threads_wanted": self.threads,
            // Whether devices at rest sleep through silence, and the blocks
            // of devices run and slept through since the engine started.
            "device_sleep": self.sleep,
            "device_runs": self.handle.shared.device_blocks().0,
            "device_sleeps": self.handle.shared.device_blocks().1,
            // Groups of tracks shared out between threads since the engine
            // started: one with little work runs on the audio thread alone.
            "shared_groups": self.handle.shared.shared_groups(),
            // What went wrong while playing, for the status line: blocks
            // plugins did not deliver in time, MIDI events dropped, frames
            // of the take being recorded lost to a slow disk, devices that
            // have stopped, and decoded audio files held in memory.
            "late_blocks": self.live.values().filter_map(|l| l.controller.as_ref()).map(|c| c.late_blocks()).sum::<u64>(),
            "midi_dropped": paw_engine::event::dropped(),
            "record_dropped": self.take.as_ref().map_or(0, |t| t.shared.dropped()),
            "devices_stopped": self.live.values().filter(|l| l.stopped.is_some()).count(),
            "audio_files": self.audio.len(),
            // The device that went away and is waited for, or nil.
            "lost": self.audio_lost(),
        })
    }

    /// Process tracks on this many threads, counting the audio thread, or
    /// with 0 on as many as the machine has cores. Tracks that do not feed
    /// each other are then processed side by side; the sound is the same.
    pub fn set_threads(&mut self, threads: usize) -> Result<()> {
        if threads > MAX_THREADS {
            bail!(
                "{threads} threads are too many: use up to {MAX_THREADS}, or 0 to leave it to the machine"
            );
        }
        self.threads = threads;
        self.send_pool();
        Ok(())
    }

    /// Worker threads for an engine: for the live one, or with `threads`
    /// for a render that asks for a number of its own.
    pub(crate) fn pool(&self, threads: Option<usize>) -> Option<Box<Pool>> {
        let threads = match threads.unwrap_or(self.threads) {
            0 => default_threads(),
            threads => threads.min(MAX_THREADS),
        };
        (threads > 1).then(|| Box::new(Pool::new(threads)))
    }

    fn send_pool(&mut self) {
        let pool = self.pool(None);
        self.handle.send(Msg::SetPool(pool));
        self.handle.send(Msg::SetSleep(self.sleep));
    }

    /// Whether devices at rest (a reverb whose tail has died away, a synth
    /// with no note sounding) sleep through silent blocks, which saves the
    /// processor their work. The sound is the same either way.
    pub fn set_sleep(&mut self, sleep: bool) {
        self.sleep = sleep;
        self.handle.send(Msg::SetSleep(sleep));
    }

    /// Whether devices at rest sleep, for a render that does not say.
    pub(crate) fn sleep(&self) -> bool {
        self.sleep
    }

    /// The devices the system offers, and which are open.
    pub fn audio_devices(&self) -> Result<Value> {
        let list = backend::list_devices(&self.backend)?;
        let rows = |devices: &[backend::AudioDevice]| -> Vec<Value> {
            devices
                .iter()
                .map(|d| {
                    json!({
                        "name": d.name, "id": d.id, "channels": d.channels,
                        "sample_rate": d.sample_rate, "min_block": d.min_block,
                        "max_block": d.max_block,
                    })
                })
                .collect()
        };
        let info = &self.stream.info;
        Ok(json!({
            "backend": list.backend, "outputs": rows(&list.outputs), "inputs": rows(&list.inputs),
            "output": info.device, "input": info.input_device,
            // Empty when the system's default is open.
            "output_id": info.device_id, "input_id": info.input_device_id,
            "buffer_size": info.buffer_size,
            // The sound systems there are, and the rate that runs.
            "backends": backend::backends(), "sample_rate": info.sample_rate,
            "rates": backend::RATES,
        }))
    }

    /// Open other devices: `output` and `input` by name, id or part of a
    /// name, `"default"` for the system's; `buffer` in frames, 0 to leave
    /// it to the device. What is not given stays as it is. A name that
    /// matches nothing is an error and changes nothing. The choice is
    /// remembered in [`device_file`](Self::device_file) for the next run.
    pub fn audio_use(
        &mut self,
        output: Option<String>,
        input: Option<String>,
        buffer: Option<u32>,
        choice: AudioChoice,
    ) -> Result<()> {
        let mut opts = self.backend.clone();
        if opts.backend == "auto" && self.stream.info.backend != "null" {
            // Keep to the backend that opened, rather than trying them all again.
            opts.backend = self.stream.info.backend.clone();
        }
        if let Some(backend) = choice.backend.filter(|b| !b.is_empty()) {
            if !backend::backends().contains(&backend) {
                bail!(
                    "no sound system `{backend}`; there are: {}",
                    backend::backends().join(", ")
                );
            }
            // Another system names its devices otherwise: start from its defaults.
            if backend != opts.backend {
                opts.output_device = None;
                opts.input_device = None;
            }
            opts.backend = backend;
        }
        if let Some(rate) = choice.rate {
            opts.sample_rate = (rate > 0).then_some(rate);
        }
        let list = backend::list_devices(&opts)?;
        let pick = |wanted: String,
                    devices: &[backend::AudioDevice],
                    what: &str|
         -> Result<Option<String>> {
            if wanted.is_empty() || wanted == "default" {
                return Ok(None);
            }
            match backend::find_device(devices, &wanted) {
                Some(device) => Ok(Some(device.name.clone())),
                None => {
                    let names: Vec<&str> = devices.iter().map(|d| d.name.as_str()).collect();
                    bail!(
                        "no {what} device matches `{wanted}`; there {}",
                        if names.is_empty() {
                            "are none".to_string()
                        } else {
                            format!("are: {}", names.join(", "))
                        }
                    )
                }
            }
        };
        if let Some(wanted) = output {
            opts.output_device = pick(wanted, &list.outputs, "output")?;
        }
        if let Some(wanted) = input {
            opts.input_device = pick(wanted, &list.inputs, "input")?;
            opts.input = true;
        }
        if let Some(frames) = buffer {
            opts.buffer_size = (frames > 0).then_some(frames);
        }
        self.engine_restart(&opts)?;
        if let Some(path) = &self.device_file
            && self.stream.info.backend != "null"
        {
            let remembered = crate::audio::Remembered {
                output: opts.output_device.clone(),
                input: opts.input_device.clone(),
                buffer: opts.buffer_size,
                backend: (opts.backend != "auto").then(|| opts.backend.clone()),
                rate: opts.sample_rate,
            };
            if let Err(err) = crate::audio::save(path, &remembered) {
                self.warnings
                    .push(format!("the devices could not be remembered: {err:#}"));
            }
        }
        Ok(())
    }

    /// Peak level of each input channel of the device, as linear gain.
    pub fn input_levels(&self) -> Vec<f32> {
        (0..self.stream.info.input_channels as usize)
            .map(|ch| self.handle.shared.input_meter(ch))
            .collect()
    }

    /// Audio blocks the engine has finished since it started, or, with a
    /// device, the blocks that device has run (not slept through). `None`
    /// for a device the engine does not have.
    pub fn blocks(&self, device: Option<Id>) -> Option<u64> {
        let shared = &self.handle.shared;
        match device {
            None => Some(shared.processed()),
            Some(id) => self.map.devices.get(&id).map(|&slot| shared.device_processed(slot)),
        }
    }

    /// Forget the processing times recorded so far.
    pub fn engine_reset_stats(&self) {
        self.handle.shared.blocks.reset();
    }

    /// Play a track from a sound file for now, as if it were frozen (see
    /// [`crate::freeze`]), or live again with `None`. The project is not
    /// changed: nothing is saved or undone, and renders play it live.
    pub fn hold(&mut self, track: Id, file: Option<PathBuf>) -> Result<()> {
        if track == MASTER_ID || self.project.track(track).is_none() {
            bail!("no track {track} to hold");
        }
        match file {
            Some(file) => self.map.held_files.insert(track, file),
            None => self.map.held_files.remove(&track),
        };
        self.dirty = true;
        self.flush();
        Ok(())
    }

    /// The tracks held by [`hold`](Self::hold).
    pub fn held(&self) -> Vec<Id> {
        let mut out: Vec<Id> = self.map.held_files.keys().copied().collect();
        out.sort_unstable();
        out
    }

    /// The track that plays MIDI input while no track is armed, as if it
    /// were monitored, or none. The project does not change.
    pub fn set_follow(&mut self, track: Option<Id>) {
        if self.map.follow == track {
            return;
        }
        self.map.follow = track;
        self.dirty = true;
        self.flush();
    }

    /// Let only these tracks be heard for now, with what they pass through
    /// (as a solo would, without the project's solos changing), or every
    /// track again with `None`.
    pub fn set_audible(&mut self, tracks: Option<Vec<Id>>) {
        self.map.audible = tracks.map(|ids| ids.into_iter().collect());
        self.dirty = true;
        self.flush();
    }

    /// Stop the audio backend and start another one, rebuilding the engine
    /// from the project.
    pub fn engine_restart(&mut self, opts: &BackendOptions) -> Result<()> {
        self.capture_states();
        let position = self.position();
        let was_playing = self.playing;
        self.stop();
        let (handle, stream) = start_engine(opts)?;
        self.backend = opts.clone();
        // Assigning drops the old stream, which stops the old engine.
        self.stream = stream;
        self.handle = handle;
        self.send_pool();
        self.live.clear();
        self.seeks = 0;
        let held = std::mem::take(&mut self.map.held_files);
        let audible = self.map.audible.take();
        self.map = Mapper::new();
        self.map.defer = self.loads.on;
        (self.map.held_files, self.map.audible) = (held, audible);
        self.loads.devices.clear();
        self.synced = Project::default();
        self.dirty = true;
        self.warnings.extend(self.stream.info.warning.clone());
        self.connect_midi();
        self.handle.send(Msg::SetTempo(self.project.tempo));
        self.send_transport();
        let events = std::mem::take(&mut self.events);
        self.flush();
        self.events = events;
        self.seek(position);
        if was_playing {
            self.play();
        }
        self.events
            .push(("engine.started".into(), self.engine_info()));
        Ok(())
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
    let base = std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/share")))
        .unwrap_or_else(std::env::temp_dir);
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
fn block_json(s: &paw_engine::BlockSummary, sample_rate: u32) -> Value {
    let ms = |ns: f64| ns / 1e6;
    let mean = if s.count > 0 {
        s.total_ns as f64 / s.count as f64
    } else {
        0.0
    };
    let frames = if s.count > 0 {
        s.frames as f64 / s.count as f64
    } else {
        0.0
    };
    json!({
        "count": s.count, "mean": ms(mean), "max": ms(s.max_ns as f64),
        "p50": ms(s.quantile_ns(0.5)), "p99": ms(s.quantile_ns(0.99)),
        "p999": ms(s.quantile_ns(0.999)),
        // The time one callback of the average size may take in real time.
        "budget": frames * 1000.0 / sample_rate.max(1) as f64,
    })
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

/// Notes the engine can play: a finite start, a length above 0, a pitch and
/// a velocity of at most 127.
fn check_notes(notes: &[Note]) -> Result<()> {
    for n in notes {
        if !n.start.is_finite() || !n.length.is_finite() || n.length <= 0.0 {
            bail!(
                "a note needs a finite start and a length above 0, not start {} length {}",
                n.start,
                n.length
            );
        }
        if n.pitch > 127 || n.velocity > 127 {
            bail!(
                "a note's pitch and velocity go up to 127, not pitch {} velocity {}",
                n.pitch,
                n.velocity
            );
        }
    }
    Ok(())
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

fn clip_json(c: &Clip, track: Id) -> Value {
    let mut v = json!({
        "id": c.id, "name": c.name, "start": c.start, "length": c.length, "muted": c.muted,
        "kind": c.content.kind(), "track": track, "meta": c.meta,
    });
    match &c.content {
        ClipContent::Midi { notes, controls } => {
            if let Some(source) = &c.source {
                v["source"] = json!(source);
                if !source.is_file() {
                    v["offline"] = json!(true);
                }
            }
            if let Some(origin) = &c.origin {
                v["origin"] = json!(origin);
            }
            v["note_count"] = json!(notes.len());
            v["control_count"] = json!(controls.len());
            // Changes whenever the notes do, so that whoever draws them
            // knows when to ask for them again. A number Lua holds exactly.
            use std::hash::{Hash, Hasher};
            let mut hash = std::collections::hash_map::DefaultHasher::new();
            for note in notes {
                (note.start.to_bits(), note.length.to_bits()).hash(&mut hash);
                (note.pitch, note.velocity, note.attr).hash(&mut hash);
                // What extensions keep on a note (a lyric, a spelling) too.
                if !note.meta.is_empty() {
                    Value::Object(note.meta.clone()).to_string().hash(&mut hash);
                }
            }
            v["stamp"] = json!(hash.finish() >> 11);
            // The same for the controller moves.
            let mut hash = std::collections::hash_map::DefaultHasher::new();
            for control in controls {
                control.start.to_bits().hash(&mut hash);
                control.value.to_bits().hash(&mut hash);
                control.key.hash(&mut hash);
                format!("{:?}", control.what).hash(&mut hash);
            }
            v["control_stamp"] = json!(hash.finish() >> 11);
        }
        ClipContent::Audio { file, offset, gain, edits } => {
            if !edits.is_empty() {
                v["edits"] = json!(edits.len());
            }
            // Its file is not there: the clip is silent until it is relinked.
            if !file.is_file() {
                v["offline"] = json!(true);
            }
            v["file"] = json!(file);
            v["offset"] = json!(offset);
            v["gain"] = json!(gain);
            v["fade_in"] = json!(c.fade_in);
            v["fade_out"] = json!(c.fade_out);
            v["timebase"] = json!(c.timebase.unwrap_or_default());
            v["stretch"] = json!(c.stretch);
            v["pitch"] = json!(c.pitch);
            v["stretch_mode"] = json!(c.stretch_mode);
            if let Some(bpm) = c.source_tempo {
                v["source_tempo"] = json!(bpm);
            }
        }
    }
    v["loop"] = json!(c.looped);
    v["loop_start"] = json!(c.loop_start);
    if let Some(beats) = c.loop_length {
        v["loop_length"] = json!(beats);
    }
    v
}
