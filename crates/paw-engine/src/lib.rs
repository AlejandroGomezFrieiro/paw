//! Real-time audio engine.
//!
//! The engine owns everything the audio thread touches. The rest of the program
//! talks to it only through [`EngineHandle`]: a lock-free queue of [`Msg`] going
//! in, and atomics plus a garbage queue coming out. Nothing here knows about the
//! project model, Lua or any UI.

pub mod automation;
pub mod backend;
pub mod clip;
pub mod device;
pub mod devices;
pub mod engine;
pub mod envelope;
pub mod event;
pub mod guard;
pub mod host;
pub mod launch;
pub mod midi;
pub mod midi_form;
pub mod midi_out;
pub mod pool;
pub mod preview;
pub mod probe;
pub mod record;
pub mod samples;
pub mod tempo;
pub mod ump;
pub mod wav;

pub use automation::{AutoLane, AutoTarget, Automation, StateChange, StateLane};
pub use backend::no_denormals;
pub use clip::{AudioData, AudioRegion, ClipSet, MidiEv, Part, PartEdit, Switch};
pub use device::{
    Controller, Device, DeviceFactory, DeviceInfo, Instance, Io, MAX_PAIRS, ParamInfo, Ports,
    ProcessCtx, Registry, Rest,
};
pub use engine::{
    BlockStats, BlockSummary, Delay, Engine, EngineHandle, KeyBuf, KeyRt, MASTER, MAX_BLOCK,
    MAX_DELAY, MAX_DEVICES, MAX_INPUTS, MAX_TRACKS, Msg, NO_SLOT, OutBufs, OutRt, SchedEntry,
    Schedule, SendRt, Shared, Slot, TrackRt, key_buf, out_bufs,
};
pub use event::{Attr, Ctl, Event, EventBuf, EventKind, NOTE_BEND_RANGE, NoteCtl};
pub use pool::Pool;
pub use preview::Preview;
pub use samples::{DiskStore, Samples, Sink, store_name};
pub use tempo::{SigPoint, TempoMap, TempoPoint};

/// Convert decibels to linear gain. Anything at or below -120 dB is silence.
pub fn db_to_gain(db: f64) -> f32 {
    if db <= -120.0 {
        0.0
    } else {
        10f64.powf(db / 20.0) as f32
    }
}

/// Convert linear gain to decibels, floored at -120 dB.
pub fn gain_to_db(gain: f32) -> f64 {
    if gain <= 1e-6 {
        -120.0
    } else {
        20.0 * (gain as f64).log10()
    }
}
