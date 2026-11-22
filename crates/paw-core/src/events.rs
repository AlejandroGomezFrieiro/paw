//! The events the kernel reports to Lua (`paw.api.events_take`, then
//! `paw.on`): each event's name and the shape of its payload, in one place.
//! tools/apidoc.lua reads this file and writes runtime/lua/paw/events/kernel.tl,
//! the payloads as Teal records and a typed descriptor for each event
//! (`paw.on(kernel.project_saved, function(p: kernel.Saved) ... end)`).
//!
//! For apidoc: a payload is a `pub struct` here, its fields are its
//! record's fields (Rust types: text, numbers, `Option`, `Vec`, pairs, and
//! the structs here), and its `///` comment is the record's. A variant
//! whose payload is a table that another record of runtime/lua/paw/types.tl
//! describes holds a `Value`, and a `/// @type types.Name` line names that
//! record.

use std::path::PathBuf;

use serde::Serialize;
use serde_json::Value;

use crate::model::Id;

/// A change event as it waits for Lua: the event, and whether it comes from
/// a state that undo or redo put back (`restored` in its payload).
#[derive(Debug, Clone)]
pub struct ModelEvent {
    pub event: KernelEvent,
    pub restored: bool,
}

impl From<KernelEvent> for ModelEvent {
    fn from(event: KernelEvent) -> ModelEvent {
        ModelEvent { event, restored: false }
    }
}

/// No more than that the event happened.
#[derive(Debug, Clone, Serialize)]
pub struct Nothing {}

/// A track, by its id.
#[derive(Debug, Clone, Serialize)]
pub struct TrackId {
    pub id: Id,
}

/// The tracks in their new order, by id.
#[derive(Debug, Clone, Serialize)]
pub struct Order {
    pub order: Vec<Id>,
}

/// A clip, a lane or a device, and the track it is on (a device that is
/// gone, and some changes of a device, have no `track`). A MIDI clip also
/// has the `stamp` of its notes, as `clip_get` gives it: a listener can
/// tell that the notes did not change without asking for the clip.
#[derive(Debug, Clone, Serialize)]
pub struct Item {
    pub id: Id,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub track: Option<Id>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stamp: Option<u64>,
}

impl Item {
    /// A device or a lane (no stamp) on `track`.
    pub fn on(id: Id, track: Option<Id>) -> Item {
        Item { id, track, stamp: None }
    }
}

/// A track that changed, and the names of its fields that changed, as
/// `track_get` names them (`{ "mute" }`, `{ "clips" }`).
#[derive(Debug, Clone, Serialize)]
pub struct TrackChange {
    pub id: Id,
    /// @type {string}
    pub fields: Vec<&'static str>,
}

/// The track whose queue of clips to launch changed.
#[derive(Debug, Clone, Serialize)]
pub struct Cue {
    pub track: Id,
}

/// A device that finished loading, its track and its name.
#[derive(Debug, Clone, Serialize)]
pub struct DeviceReady {
    pub id: Id,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub track: Option<Id>,
    pub name: String,
}

/// A device that stopped (`reason`; `loading` when it never started) or
/// that gave values it should not (`device.invalid`, no reason).
#[derive(Debug, Clone, Serialize)]
pub struct DeviceTrouble {
    pub device: Id,
    pub track: Id,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(skip_serializing_if = "std::ops::Not::not")]
    pub loading: bool,
}

/// A parameter moved by the host (`from = "host"`) or in the plugin's own
/// window (`from = "editor"`, with its `value`): its key, and the
/// device's own id for it.
#[derive(Debug, Clone, Serialize)]
pub struct ParamTouched {
    pub device: Id,
    pub param: String,
    pub id: String,
    pub from: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<f64>,
}

/// Where the transport is, in beats.
#[derive(Debug, Clone, Serialize)]
pub struct Position {
    pub position: f64,
}

/// Where play starts, in beats, and the beats counted in before it.
#[derive(Debug, Clone, Serialize)]
pub struct Play {
    pub position: f64,
    pub count_in: f64,
}

/// A take that starts: where, its number, the folder its files go in,
/// how fast they grow and the free space there, in bytes, and the files.
#[derive(Debug, Clone, Serialize)]
pub struct Record {
    pub position: f64,
    pub take: u32,
    pub dir: PathBuf,
    pub bytes_per_second: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub free: Option<u64>,
    pub files: Vec<PathBuf>,
}

/// The audio device that went away, why, whether a take was being
/// recorded, and whether paw tries to open it again by itself.
#[derive(Debug, Clone, Serialize)]
pub struct AudioLost {
    pub device: String,
    pub reason: String,
    pub recording: bool,
    pub auto: bool,
}

/// The audio device that is back, and the engine that runs on it now.
#[derive(Debug, Clone, Serialize)]
pub struct AudioRestored {
    pub device: String,
    /// @type types.EngineInfo
    pub engine: Value,
}

/// A MIDI port that went away or came back, and the tracks (by name) that
/// take their MIDI from it.
#[derive(Debug, Clone, Serialize)]
pub struct MidiPort {
    pub port: String,
    pub tracks: Vec<String>,
}

/// A track or a track's chain whose files were copied into the project
/// (`origin`, where they were).
#[derive(Debug, Clone, Serialize)]
pub struct TrackCopied {
    pub track: Id,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub origin: Option<PathBuf>,
}

/// A clip whose file was copied into the project (`origin`, where it was).
#[derive(Debug, Clone, Serialize)]
pub struct ClipCopied {
    pub clip: Id,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub origin: Option<PathBuf>,
}

/// How far a render is (`fraction`, 0 to 1), what it does now, and the
/// seconds since it started.
#[derive(Debug, Clone, Serialize)]
pub struct RenderProgress {
    pub path: PathBuf,
    pub fraction: f64,
    pub stage: String,
    pub seconds: f64,
}

/// How much paw is baking (stretches, and later other bakes): the bakes
/// being made and waiting, and how far the running ones are together
/// (`fraction`, 0 to 1). Sent at most 4 times a second, and once when all
/// are done (both counts 0).
#[derive(Debug, Clone, Copy, Serialize)]
pub struct BakeProgress {
    pub running: usize,
    pub waiting: usize,
    pub fraction: f64,
}

/// A render that stopped: its file, and why when it failed.
#[derive(Debug, Clone, Serialize)]
pub struct RenderEnd {
    pub path: PathBuf,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// A project that was opened, from `path` (none for a new one).
#[derive(Debug, Clone, Serialize)]
pub struct Loaded {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<PathBuf>,
}

/// A project that was saved to `path`; saved as a folder, the files
/// written, the files put in `unused/`, and the files moved (`{ from, to }`).
#[derive(Debug, Clone, Serialize)]
pub struct Saved {
    pub path: PathBuf,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub written: Option<Vec<PathBuf>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unused: Option<Vec<PathBuf>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub moved: Option<Vec<(PathBuf, PathBuf)>>,
}

/// The sound files a project names that are not where it says, and how
/// many were found elsewhere.
#[derive(Debug, Clone, Serialize)]
pub struct MediaMissing {
    pub files: Vec<PathBuf>,
    pub found: usize,
}

/// A program started with `proc_spawn` that has output to read, by its id.
#[derive(Debug, Clone, Serialize)]
pub struct ProcOutput {
    pub id: u64,
}

/// The files of the project that changed outside paw: paths in its
/// folder, or full paths outside it.
#[derive(Debug, Clone, Serialize)]
pub struct FilesChanged {
    pub paths: Vec<PathBuf>,
}

/// Each event of the kernel, by its name, with its payload.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "name", content = "payload")]
pub enum KernelEvent {
    /// Anything that a view shows changed: draw again.
    #[serde(rename = "changed")]
    Changed(Nothing),
    #[serde(rename = "project.changed")]
    ProjectChanged(Nothing),
    #[serde(rename = "project.loaded")]
    ProjectLoaded(Loaded),
    #[serde(rename = "project.saved")]
    ProjectSaved(Saved),
    #[serde(rename = "track.added")]
    TrackAdded(TrackId),
    #[serde(rename = "track.changed")]
    TrackChanged(TrackChange),
    #[serde(rename = "track.removed")]
    TrackRemoved(TrackId),
    #[serde(rename = "track.moved")]
    TrackMoved(Order),
    #[serde(rename = "track.copied")]
    TrackCopied(TrackCopied),
    #[serde(rename = "chain.copied")]
    ChainCopied(TrackCopied),
    #[serde(rename = "clip.added")]
    ClipAdded(Item),
    #[serde(rename = "clip.changed")]
    ClipChanged(Item),
    #[serde(rename = "clip.removed")]
    ClipRemoved(Item),
    #[serde(rename = "clip.copied")]
    ClipCopied(ClipCopied),
    #[serde(rename = "lane.added")]
    LaneAdded(Item),
    #[serde(rename = "lane.changed")]
    LaneChanged(Item),
    #[serde(rename = "lane.removed")]
    LaneRemoved(Item),
    #[serde(rename = "cue.changed")]
    CueChanged(Cue),
    #[serde(rename = "device.added")]
    DeviceAdded(Item),
    #[serde(rename = "device.changed")]
    DeviceChanged(Item),
    #[serde(rename = "device.removed")]
    DeviceRemoved(Item),
    #[serde(rename = "device.ready")]
    DeviceReady(DeviceReady),
    #[serde(rename = "device.stopped")]
    DeviceStopped(DeviceTrouble),
    #[serde(rename = "device.invalid")]
    DeviceInvalid(DeviceTrouble),
    #[serde(rename = "param.touched")]
    ParamTouched(ParamTouched),
    #[serde(rename = "transport.changed")]
    TransportChanged(Nothing),
    #[serde(rename = "transport.play")]
    TransportPlay(Play),
    #[serde(rename = "transport.stop")]
    TransportStop(Position),
    #[serde(rename = "transport.seek")]
    TransportSeek(Position),
    #[serde(rename = "transport.record")]
    TransportRecord(Record),
    /// @type types.MidiEvent
    #[serde(rename = "midi.in")]
    MidiIn(Value),
    #[serde(rename = "midi.lost")]
    MidiLost(MidiPort),
    #[serde(rename = "midi.returned")]
    MidiReturned(MidiPort),
    /// @type types.EngineInfo
    #[serde(rename = "engine.started")]
    EngineStarted(Value),
    #[serde(rename = "audio.lost")]
    AudioLost(AudioLost),
    #[serde(rename = "audio.restored")]
    AudioRestored(AudioRestored),
    #[serde(rename = "render.progress")]
    RenderProgress(RenderProgress),
    /// @type types.RenderResult
    #[serde(rename = "render.done")]
    RenderDone(Value),
    #[serde(rename = "render.failed")]
    RenderFailed(RenderEnd),
    #[serde(rename = "render.cancelled")]
    RenderCancelled(RenderEnd),
    #[serde(rename = "bake.progress")]
    BakeProgress(BakeProgress),
    #[serde(rename = "media.missing")]
    MediaMissing(MediaMissing),
    #[serde(rename = "proc.output")]
    ProcOutput(ProcOutput),
    #[serde(rename = "files.changed")]
    FilesChanged(FilesChanged),
}

impl KernelEvent {
    /// The event that says a view should draw again.
    pub fn changed() -> KernelEvent {
        KernelEvent::Changed(Nothing {})
    }
}
