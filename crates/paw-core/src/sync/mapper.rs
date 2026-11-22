//! Which engine slot each track and device lives in, and what the engine
//! was last sent of each, so that a sync sends only what changed.

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;

use paw_engine::midi_form::Form;
use paw_engine::{DeviceSlot, MAX_DEVICES, MAX_TRACKS, MidiEv, TrackSlot};

use super::clips::{Compiled, Parts};
use super::routing::Routing;
use crate::freeze::Played;
use crate::model::{Clip, Id, MASTER_ID};

/// A track's fader as last sent ([`paw_engine::Msg::SetMix`]).
#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct MixSent {
    pub gain: f32,
    pub pan: f32,
    pub mute: bool,
    /// Silenced by a solo elsewhere, or by the session.
    pub quiet: bool,
}

/// A track's audio input as last sent ([`paw_engine::Msg::SetInput`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct InputSent {
    pub first: usize,
    pub channels: usize,
    pub monitor: bool,
    pub armed: bool,
}

/// The MIDI port's key and channel a track takes, as last sent; port 0 for
/// none.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct MidiInSent {
    pub port: u32,
    pub channel: u8,
}

/// The MIDI port a track sends to, as last sent; port 0 for none.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct MidiOutSent {
    pub port: u32,
    pub channel: u8,
    pub form: Form,
}

/// A clip off the timeline as compiled for the engine.
pub(super) struct CueEvents {
    pub clip: Arc<Clip>,
    pub events: Arc<[MidiEv]>,
}

/// Which engine slot each track and device lives in.
pub struct Mapper {
    pub tracks: HashMap<Id, TrackSlot>,
    pub devices: HashMap<Id, DeviceSlot>,
    pub(super) free_tracks: Vec<TrackSlot>,
    pub(super) free_devices: Vec<DeviceSlot>,
    next_track: u32,
    next_device: u32,
    pub(super) mix: HashMap<Id, MixSent>,
    /// The fader lane each track has because of the VCAs it is in, as last
    /// sent: see [`vca_volume_lane`](super::automation::vca_volume_lane).
    pub(super) vca_lanes: HashMap<Id, Vec<(f64, f64)>>,
    pub(super) inputs: HashMap<Id, InputSent>,
    pub(super) midi_inputs: HashMap<Id, MidiInSent>,
    pub(super) midi_outputs: HashMap<Id, MidiOutSent>,
    pub(super) routing: Routing,
    /// Devices given a buffer for a side-chain.
    pub(super) keyed: HashSet<Id>,
    /// Devices given buffers for further output pairs, and which.
    pub(super) outs: HashMap<Id, Vec<usize>>,
    /// Frames by which the output is behind the transport, as last scheduled.
    pub latency: u32,
    /// What the engine was sent of each track's clips, one part for each
    /// (see [`Parts`]), so that an edit compiles and sends only the clips
    /// it changed. Tracks whose clips are sent as one list have none.
    pub(super) parts: HashMap<Id, Parts>,
    /// The events of every MIDI clip sent, by what they are compiled from:
    /// copies of a clip anywhere share them (see [`Compiled`]).
    pub(super) compiled: Compiled,
    /// Each device's latency as last told to the host's dry signal.
    pub(super) host_latency: HashMap<Id, u32>,
    /// Make devices whose factories can ([`DeviceFactory::starts_apart`])
    /// without waiting for them: each gets a stand-in, and its id is put
    /// in [`deferred`](Self::deferred) for the session to make it.
    ///
    /// [`DeviceFactory::starts_apart`]: paw_engine::DeviceFactory::starts_apart
    pub defer: bool,
    /// Devices given a stand-in since the session last looked.
    pub deferred: Vec<Id>,
    /// Tracks the session plays from a file for now, as if they were
    /// frozen, without the project saying so (see [`crate::freeze`]).
    pub held_files: HashMap<Id, PathBuf>,
    /// When set, only these tracks are heard, with what they pass through,
    /// as if they were soloed; the project is not changed.
    pub audible: Option<HashSet<Id>>,
    /// The track that plays MIDI input as if it were monitored, without
    /// the project saying so.
    pub follow: Follow,
    /// What the engine was last told to play of each track that is not live.
    pub(super) played: HashMap<Id, Played>,
    /// The clip in each of a track's cue rows in the engine, so that a
    /// clip keeps its row (and goes on playing) while others come and go.
    pub cue_rows: HashMap<Id, Vec<Option<Id>>>,
    /// Each track's MIDI clips off the timeline as engine events, so that
    /// a change of one compiles only that one.
    pub(super) cue_events: HashMap<Id, HashMap<Id, CueEvents>>,
    /// For each state lane the engine has, by the lane's id: which of its
    /// states need the main thread (a whole saved state, or a request the
    /// device could not prepare for its audio side). The session loads
    /// those as the song plays, and a render stops on their points.
    pub state_main: HashMap<Id, Vec<bool>>,
    /// The nest tracks as last sent: their clips placed in the song for
    /// each place of their nest (see `nests.rs`).
    pub(super) expanded: super::nests::ExpandedTracks,
    /// The time each nest track's devices were last told (see `nests.rs`).
    pub(super) local: HashMap<Id, super::nests::Local>,
}

/// The track that plays MIDI input as if it were monitored, without the
/// project saying so.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Follow {
    /// The selected track, while no track is armed
    /// (`paw.opt.midi_follows_selection`).
    pub selected: Option<Id>,
    /// A track that plays it also while another track is armed, in place
    /// of `selected`: the track of the clip that step input enters into.
    pub always: Option<Id>,
}

impl Follow {
    /// The track that plays MIDI input now, if any.
    pub fn track(&self, any_armed: bool) -> Option<Id> {
        self.always.or(self.selected.filter(|_| !any_armed))
    }
}

impl Default for Mapper {
    fn default() -> Self {
        Self::new()
    }
}

impl Mapper {
    pub fn new() -> Self {
        Self {
            tracks: HashMap::from([(MASTER_ID, TrackSlot::MASTER)]),
            devices: HashMap::new(),
            free_tracks: Vec::new(),
            free_devices: Vec::new(),
            next_track: TrackSlot::MASTER.0 + 1,
            next_device: 0,
            mix: HashMap::new(),
            vca_lanes: HashMap::new(),
            inputs: HashMap::new(),
            midi_inputs: HashMap::new(),
            midi_outputs: HashMap::new(),
            routing: Vec::new(),
            keyed: HashSet::new(),
            outs: HashMap::new(),
            latency: 0,
            parts: HashMap::new(),
            compiled: Compiled::default(),
            host_latency: HashMap::new(),
            defer: false,
            deferred: Vec::new(),
            held_files: HashMap::new(),
            audible: None,
            follow: Follow::default(),
            played: HashMap::new(),
            cue_rows: HashMap::new(),
            cue_events: HashMap::new(),
            state_main: HashMap::new(),
            expanded: HashMap::new(),
            local: HashMap::new(),
        }
    }

    /// The engine's row of a clip off the timeline, if the engine has it.
    pub fn cue_row(&self, track: Id, clip: Id) -> Option<u32> {
        let rows = self.cue_rows.get(&track)?;
        rows.iter().position(|c| *c == Some(clip)).map(|r| r as u32)
    }

    /// The clip in a track's cue row in the engine.
    pub fn cue_clip(&self, track: Id, row: u32) -> Option<Id> {
        *self.cue_rows.get(&track)?.get(row as usize)?
    }

    pub(super) fn alloc_track(&mut self) -> Option<TrackSlot> {
        self.free_tracks.pop().or_else(|| {
            let slot = TrackSlot(self.next_track);
            (slot.index() < MAX_TRACKS).then(|| {
                self.next_track += 1;
                slot
            })
        })
    }

    pub(super) fn alloc_device(&mut self) -> Option<DeviceSlot> {
        self.free_devices.pop().or_else(|| {
            let slot = DeviceSlot(self.next_device);
            (slot.index() < MAX_DEVICES).then(|| {
                self.next_device += 1;
                slot
            })
        })
    }

    /// Forget a device the engine no longer runs, giving its slot back
    /// after `removals` are sent.
    pub(super) fn free_device(&mut self, id: Id, removals: &mut Vec<paw_engine::Msg>) {
        if let Some(slot) = self.devices.remove(&id) {
            removals.push(paw_engine::Msg::RemoveDevice { slot });
            self.free_devices.push(slot);
        }
    }
}
