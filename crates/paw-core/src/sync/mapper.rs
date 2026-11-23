//! Which engine slot each part and device lives in, and what the engine
//! was last sent of each, so that a sync sends only what changed.

use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;

use paw_engine::{DeviceSlot, MAX_DEVICES, MAX_PARTS, MidiEv, PartSlot};
use paw_types::midi_form::Form;

use super::clips::{Compiled, Pieces};
use super::routing::Routing;
use crate::freeze::Played;
use crate::model::{Clip, Id, MASTER_ID};

/// A part's fader as last sent ([`paw_engine::Msg::SetMix`]).
#[derive(Clone, Copy, Debug, PartialEq)]
pub(super) struct MixSent {
    pub gain: f32,
    pub pan: f32,
    pub mute: bool,
    /// Silenced by a solo elsewhere, or by the session.
    pub quiet: bool,
}

/// A part's audio input as last sent ([`paw_engine::Msg::SetInput`]).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct InputSent {
    pub first: usize,
    pub channels: usize,
    pub monitor: bool,
    pub armed: bool,
}

/// The MIDI port's key and channel a part takes, as last sent; port 0 for
/// none.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct MidiInSent {
    pub port: u32,
    pub channel: u8,
}

/// The MIDI port a part sends to, as last sent; port 0 for none.
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

/// Which engine slot each part and device lives in.
pub struct Mapper {
    pub parts: HashMap<Id, PartSlot>,
    pub devices: HashMap<Id, DeviceSlot>,
    pub(super) free_parts: Vec<PartSlot>,
    pub(super) free_devices: Vec<DeviceSlot>,
    next_part: u32,
    next_device: u32,
    pub(super) mix: HashMap<Id, MixSent>,
    /// The fader lane each part has because of the VCAs it is in, as last
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
    /// What the engine was sent of each part's clips, one piece for each
    /// (see [`Pieces`]), so that an edit compiles and sends only the clips
    /// it changed. Parts whose clips are sent as one list have none.
    pub(super) pieces: HashMap<Id, Pieces>,
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
    /// Parts the session plays from a file for now, as if they were
    /// frozen, without the project saying so (see [`crate::freeze`]).
    pub held_files: HashMap<Id, PathBuf>,
    /// When set, only these parts are heard, with what they pass through,
    /// as if they were soloed; the project is not changed.
    pub audible: Option<HashSet<Id>>,
    /// The part that plays MIDI input as if it were monitored, without
    /// the project saying so.
    pub(crate) follow: Follow,
    /// What the engine was last told to play of each part that is not live.
    pub(super) played: HashMap<Id, Played>,
    /// The clip in each of a part's cue rows in the engine, so that a
    /// clip keeps its row (and goes on playing) while others come and go.
    pub cue_rows: HashMap<Id, Vec<Option<Id>>>,
    /// Each part's MIDI clips off the timeline as engine events, so that
    /// a change of one compiles only that one.
    pub(super) cue_events: HashMap<Id, HashMap<Id, CueEvents>>,
    /// For each state lane the engine has, by the lane's id: which of its
    /// states need the main thread (a whole saved state, or a request the
    /// device could not prepare for its audio side). The session loads
    /// those as the song plays, and a render stops on their points.
    pub state_main: HashMap<Id, Vec<bool>>,
    /// The nest parts as last sent: their clips placed in the song for
    /// each place of their nest (see `nests.rs`).
    pub(super) expanded: super::nests::ExpandedParts,
    /// The time each nest part's devices were last told (see `nests.rs`).
    pub(super) local: HashMap<Id, super::nests::Local>,
    /// The tree of each part's chain as last compiled and sent.
    pub(super) trees: HashMap<Id, paw_engine::plan::Tree>,
    /// The meters of the splits and branches of each part's plan.
    pub(super) meters: HashMap<Id, Arc<paw_engine::plan::PlanMeters>>,
}

/// The part that plays MIDI input as if it were monitored, without the
/// project saying so.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct Follow {
    /// The selected part, while no part is armed
    /// (`paw.opt.midi_follows_selection`).
    pub selected: Option<Id>,
    /// A part that plays it also while another part is armed, in place
    /// of `selected`: the part of the clip that step input enters into.
    pub always: Option<Id>,
}

impl Follow {
    /// The part that plays MIDI input now, if any.
    pub(crate) fn part(&self, any_armed: bool) -> Option<Id> {
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
            parts: HashMap::from([(MASTER_ID, PartSlot::MASTER)]),
            devices: HashMap::new(),
            free_parts: Vec::new(),
            free_devices: Vec::new(),
            next_part: PartSlot::MASTER.0 + 1,
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
            pieces: HashMap::new(),
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
            trees: HashMap::new(),
            meters: HashMap::new(),
        }
    }

    /// The peak `(left, right)` of the split or branch `node` of the chain
    /// of `part`, as the engine measured it last.
    pub fn chain_peak(&self, part: Id, node: u64) -> Option<(f32, f32)> {
        self.meters.get(&part)?.peak(node)
    }

    /// The latency of the chain of `part`, in frames, as last compiled.
    pub(super) fn chain_latency(&self, part: Id) -> Option<u32> {
        self.trees.get(&part).map(paw_engine::plan::Tree::latency)
    }

    /// The engine's row of a clip off the timeline, if the engine has it.
    pub(crate) fn cue_row(&self, part: Id, clip: Id) -> Option<u32> {
        let rows = self.cue_rows.get(&part)?;
        rows.iter().position(|c| *c == Some(clip)).map(|r| r as u32)
    }

    /// The clip in a part's cue row in the engine.
    pub(crate) fn cue_clip(&self, part: Id, row: u32) -> Option<Id> {
        *self.cue_rows.get(&part)?.get(row as usize)?
    }

    pub(super) fn alloc_part(&mut self) -> Option<PartSlot> {
        self.free_parts.pop().or_else(|| {
            let slot = PartSlot(self.next_part);
            (slot.index() < MAX_PARTS).then(|| {
                self.next_part += 1;
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
