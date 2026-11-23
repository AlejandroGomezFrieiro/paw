//! The values and helpers that several areas of the tests use.

use paw_engine::{EngineHandle, Msg};

/// The sample rate of each engine in the tests.
pub(crate) const SR: f64 = 48000.0;

/// Put `msg` in the queue of the engine. The queue of a test never
/// fills, so a full queue is a failure.
pub(crate) fn send(handle: &mut EngineHandle, msg: Msg) {
    assert!(handle.try_send(msg).is_ok(), "message queue full");
}
