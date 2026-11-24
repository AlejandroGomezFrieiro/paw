//! Real-time audio engine.
//!
//! The engine owns everything the audio thread touches. The rest of the program
//! talks to it only through [`EngineHandle`]: a lock-free queue of [`Msg`] going
//! in, and atomics plus a garbage queue coming out. Nothing here knows about the
//! project model, Lua or any UI. The values it plays (events, the tempo map)
//! are those of `paw-types`.

#[cfg(feature = "midi")]
mod alsa;
pub mod automation;
pub mod backend;
pub mod bell;
pub mod clip;
pub mod device;
pub mod devices;
pub mod engine;
pub mod envelope;
pub mod event;
pub mod guard;
pub mod host;
pub mod launch;
pub mod local_time;
pub mod midi;
pub mod midi_filter;
pub mod midi_out;
pub mod pool;
pub mod priority;
pub mod preview;
pub mod plan;
pub mod probe;
pub mod record;
pub mod samples;
pub mod slot;
pub mod wav;

pub use automation::{AutoLane, AutoTarget, Automation, StateChange, StateLane};
pub use backend::no_denormals;
pub use bell::Bell;
pub use clip::{AudioData, AudioRegion, ClipSet, Direction, MidiEv, Piece, PieceEdit, Switch};
pub use device::{
    Category, Controller, Device, DeviceFactory, DeviceFormat, DeviceInfo, Instance, Io, MAX_PAIRS,
    ParamInfo, Ports, ProcessCtx, Quality, Registry, Rest,
};
pub use engine::{
    BlockStats, BlockSummary, Delay, Engine, EngineHandle, KeyBuf, KeyRt, MAX_BLOCK,
    MAX_DELAY, MAX_DEVICES, MAX_INPUTS, MAX_PARTS, Msg, OutBufs, OutRt, SchedEntry,
    Schedule, SendRt, Shared, PartRt, Waker, key_buf, out_bufs,
};
pub use event::{Event, EventBuf, PART_EVENTS};
pub use local_time::{LocalTime, Place};
pub use pool::Pool;
pub use preview::Preview;
pub use samples::{DiskStore, Samples, Sink, store_name};
pub use plan::GraphPlan;
pub use slot::{DeviceSlot, ProcessorSlot, PartSlot};

pub use paw_types::gain::{db_to_gain, gain_to_db};
