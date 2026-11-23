//! The main thread's end of the engine.

use std::sync::Arc;

use paw_types::EventKind;
use rtrb::{Consumer, Producer, PushError, RingBuffer};

use crate::midi_out::MidiOut;

use super::{Engine, Waker};
use super::msg::{Garbage, Msg};
use super::shared::Shared;

/// The main thread's end of the engine.
pub struct EngineHandle {
    pub(super) tx: Producer<Msg>,
    pub(super) garbage: Consumer<Garbage>,
    pub shared: Arc<Shared>,
    pub sample_rate: f64,
    pub(super) midi_tx: Option<Producer<(u32, EventKind)>>,
    pub(super) waker: Waker,
}

impl EngineHandle {
    /// What wakes the engine from rest without a message, for a device to
    /// keep ([`Controller::set_waker`]).
    ///
    /// [`Controller::set_waker`]: crate::device::Controller::set_waker
    pub fn waker(&self) -> Waker {
        self.waker.clone()
    }

    /// The sending end of the engine's MIDI input queue, for the one thread
    /// that reads MIDI ports. Notes pushed into it reach every armed track at
    /// the start of the next callback.
    /// Each message comes with the key of the port it came from.
    pub fn take_midi_input(&mut self) -> Option<Producer<(u32, EventKind)>> {
        self.midi_tx.take()
    }

    /// The receiving end of a new queue of the MIDI the tracks send to their
    /// output ports, for the one thread that sends it on
    /// ([`MidiOutputs::set_queue`]). Until one is asked for, nothing is
    /// sent: an offline render never is.
    ///
    /// [`MidiOutputs::set_queue`]: crate::midi_out::MidiOutputs::set_queue
    pub fn midi_output(&mut self) -> Consumer<MidiOut> {
        let (tx, rx) = RingBuffer::new(crate::midi_out::MIDI_OUT_CAPACITY);
        self.send(Msg::SetMidiOut(Some(Box::new(tx))));
        rx
    }

    /// The receiving end of a new queue of everything the engine plays, left
    /// and right interleaved, with room for `seconds` of it, for one thread
    /// to read. Until it is asked for (and after [`stop_monitor`]) nothing
    /// is copied.
    ///
    /// [`stop_monitor`]: Self::stop_monitor
    pub fn monitor(&mut self, seconds: f64) -> Consumer<f32> {
        let (tx, rx) = RingBuffer::new(((self.sample_rate * seconds) as usize).max(64) * 2);
        self.send(Msg::SetMonitor(Some(Box::new(tx))));
        rx
    }

    /// Stop copying what the engine plays.
    pub fn stop_monitor(&mut self) {
        self.send(Msg::SetMonitor(None));
    }

    /// Queue a message, or hand it back if the queue is full.
    pub fn try_send(&mut self, msg: Msg) -> Result<(), Msg> {
        self.tx.push(msg).map_err(|PushError::Full(msg)| msg)
    }

    /// Queue a message, waiting for the audio thread to make room if needed.
    /// Only call this while something is driving [`Engine::process`].
    pub fn send(&mut self, msg: Msg) {
        let mut msg = msg;
        while let Err(back) = self.try_send(msg) {
            msg = back;
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
    }

    /// Queue a message for an engine this thread drives itself, pumping the
    /// engine to make room if the queue is full.
    pub fn send_while(&mut self, msg: Msg, engine: &mut Engine) {
        let mut msg = msg;
        while let Err(back) = self.try_send(msg) {
            msg = back;
            engine.pump();
        }
    }

    /// Free whatever the audio thread has finished with.
    pub fn collect_garbage(&mut self) {
        while self.garbage.pop().is_ok() {}
    }
}
