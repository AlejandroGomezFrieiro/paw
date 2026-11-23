//! The audio-thread half of a CLAP plugin: its `process` and its buffers.
//! `process` and the functions it calls run on the audio thread: no lock,
//! no allocation and no wait. `Buffers::new` and the drop run on the main
//! thread.

use std::ptr;
use std::sync::Arc;
use std::sync::atomic::{Ordering, Ordering::Relaxed};

use clack_extensions::tail::{PluginTail, TailLength};
use clack_host::prelude::{
    InputAudioBuffers, InputEvents, OutputAudioBuffers, OutputEvents, PluginInstanceError,
    ProcessStatus, StartedPluginAudioProcessor,
};
use clap_sys::audio_buffer::clap_audio_buffer;
use paw_engine::device::{Rest, silent};
use paw_engine::{Device, Io, ProcessCtx};

use super::events::{ClapEvents, NoteRoute, Out, transport};
use super::host::PawHost;
use super::shared::Shared;
use crate::{HeldNotes, write_output};

/// Audio buffers for every port in one direction, laid out as CLAP wants them.
pub(super) struct Buffers {
    channels: Vec<Vec<Vec<f32>>>,
    _pointers: Vec<Vec<*mut f32>>,
    ports: Vec<clap_audio_buffer>,
}

impl Buffers {
    pub(super) fn new(channel_counts: &[u32], max_block: usize) -> Self {
        let mut channels: Vec<Vec<Vec<f32>>> = channel_counts
            .iter()
            .map(|&count| (0..count).map(|_| vec![0.0; max_block]).collect())
            .collect();
        let mut pointers: Vec<Vec<*mut f32>> = channels
            .iter_mut()
            .map(|port| port.iter_mut().map(|ch| ch.as_mut_ptr()).collect())
            .collect();
        let ports = pointers
            .iter_mut()
            .map(|port| clap_audio_buffer {
                data32: port.as_mut_ptr(),
                data64: ptr::null_mut(),
                channel_count: port.len() as u32,
                latency: 0,
                constant_mask: 0,
            })
            .collect();
        Self {
            channels,
            _pointers: pointers,
            ports,
        }
    }

    /// Put the block's sound on the main input port, as mono or stereo,
    /// and the side-chain on `key_port`; `keyed` tells whether that port
    /// holds a key.
    fn read_input(&mut self, io: &Io, key_port: Option<usize>, keyed: &mut bool, n: usize) {
        if let Some(port) = self.channels.first_mut() {
            match port.as_mut_slice() {
                [] => {}
                [mono] => {
                    for (m, (l, r)) in mono.iter_mut().zip(io.left.iter().zip(io.right.iter())) {
                        *m = (l + r) * 0.5;
                    }
                }
                [left, right, ..] => {
                    left[..n].copy_from_slice(io.left);
                    right[..n].copy_from_slice(io.right);
                }
            }
        }
        if let Some(port) = key_port.and_then(|p| self.channels.get_mut(p)) {
            *keyed = crate::put_key(port.as_mut_slice(), io.sidechain, *keyed, n);
        }
    }

    /// Whether every channel was silent in the block's first `n` frames.
    fn quiet(&self, n: usize) -> bool {
        self.channels.iter().flatten().all(|c| silent(&c[..n]))
    }

    /// Give the block's sound from the output ports: the main port on the
    /// part's pair, added for an instrument, and the other pairs where
    /// they go.
    fn write_output(&self, io: &mut Io, pairs: &[crate::OutPair], instrument: bool, n: usize) {
        if let Some(port) = self.channels.first() {
            let channels = [port.first().map(|c| &c[..n]), port.get(1).map(|c| &c[..n])];
            match channels {
                [Some(l), Some(r)] => write_output(io.left, io.right, &[l, r], instrument),
                [Some(m), None] => write_output(io.left, io.right, &[m], instrument),
                _ => {}
            }
        }
        crate::write_pairs(pairs, &self.channels, io.outputs, n);
    }
}

/// The audio-thread half of a CLAP plugin, which the engine runs.
pub(super) struct ClapDevice {
    pub(super) shared: Arc<Shared>,
    /// What the plugin tells in its output events, kept across blocks.
    pub(super) out: Out,
    pub(super) inputs: Buffers,
    pub(super) outputs: Buffers,
    /// The input port that takes the side-chain, and whether it holds one.
    pub(super) key_port: Option<usize>,
    pub(super) keyed: bool,
    /// The output ports as stereo pairs, the main one first.
    pub(super) out_pairs: Vec<crate::OutPair>,
    pub(super) events: ClapEvents,
    /// Parameter changes waiting for the next block: index and value.
    pub(super) pending: Vec<(u32, f32)>,
    pub(super) held: HeldNotes,
    /// How the plugin takes notes and the other events.
    pub(super) route: NoteRoute,
    /// The plugin failed to start processing: it is not asked again.
    pub(super) failed: bool,
    pub(super) steady_time: u64,
    /// What the plugin said of itself after its last block (see
    /// [`Device::resting`]).
    pub(super) rest: Rest,
    /// States the plugin had been given at its last block
    /// ([`HostFlags::loads`](super::host::HostFlags::loads)).
    pub(super) loads: u64,
}

// The buffers hold raw pointers into vectors the device owns.
// SAFETY: The buffers hold raw pointers into vectors that the device owns and moves with itself.
// The device is used from the audio thread only, after the main thread built it.
unsafe impl Send for ClapDevice {}

impl Device for ClapDevice {
    /// As the plugin's status after its last block says: asleep, or quiet,
    /// or done with its tail; unless a parameter has moved since.
    fn resting(&self) -> bool {
        self.rest.resting() && self.pending.is_empty() && !self.shared.flags.wake.load(Relaxed)
    }

    /// In three steps: the events and the audio in, the call of the
    /// plugin, and its rest and audio out.
    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        let n = io.left.len();
        // Woken: its tail starts again from here.
        self.rest.begin(io, self.shared.flags.wake.swap(false, Relaxed));
        // The main thread has the plugin deactivated for an attachment:
        // this block is the stand-in's, silence for an instrument and the
        // input passed through for an effect.
        let mut running = self.shared.run.try_lock().ok();
        let Some(processor) = running.as_deref_mut().and_then(Option::as_mut) else {
            if self.inputs.ports.is_empty() {
                io.left.fill(0.0);
                io.right.fill(0.0);
            }
            return;
        };
        // Started anew after the main thread deactivated it; never again
        // once it failed to start.
        if !processor.is_started() && (self.failed || processor.start_processing().is_err()) {
            self.failed = true;
            return;
        }
        let Ok(processor) = processor.as_started_mut() else {
            return;
        };

        // 1. The events and the audio in.
        self.inputs.read_input(io, self.key_port, &mut self.keyed, n);
        self.events.fill(
            &mut self.pending,
            &self.shared.param_ids,
            &mut self.held,
            io.events.as_slice(),
            self.route,
        );

        // 2. The call.
        let loads = self.shared.flags.loads.load(Ordering::Acquire);
        self.out.taking = loads != self.loads;
        self.loads = loads;
        // Built with the block's length, not with Clack's safe builders: they
        // give a plugin with no audio ports a block of 0 frames.
        // SAFETY: Each port's channel pointers lead to `max_block` frames of the device's own
        // vectors, which live and stay in place as long as the device, and `n <= max_block`.
        let (inputs, mut outputs) = unsafe {
            (
                InputAudioBuffers::from_raw_buffers(&self.inputs.ports, n as u32),
                OutputAudioBuffers::from_raw_buffers(&mut self.outputs.ports, n as u32),
            )
        };
        let steady_time = self.steady_time;
        self.steady_time += n as u64;
        let status = self.shared.flags.blocks.run(|| {
            processor.process(
                &inputs,
                &mut outputs,
                &InputEvents::from_buffer(&self.events),
                &mut OutputEvents::from_buffer(&mut self.out),
                Some(steady_time),
                Some(&transport(ctx)),
            )
        });
        if let Err(PluginInstanceError::NullProcessFunction) = status {
            return;
        }
        // The plugin failed the block (`CLAP_PROCESS_ERROR`).
        let Ok(status) = status else {
            return;
        };

        // 3. Its rest and the audio out.
        let tail = self.shared.ext.tail;
        end_rest(&mut self.rest, status, tail, processor, &self.outputs, n);
        let instrument = self.inputs.ports.is_empty();
        self.outputs.write_output(io, &self.out_pairs, instrument, n);
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if self.pending.len() < self.pending.capacity() {
            self.pending.push((index, value));
        }
    }
}

/// Whether the plugin may sleep through silence from here on, as the
/// status of its block says: it says so, or says it may once its output is
/// quiet, or once its tail has gone by.
fn end_rest(
    rest: &mut Rest,
    status: ProcessStatus,
    tail: Option<PluginTail>,
    processor: &mut StartedPluginAudioProcessor<PawHost>,
    outputs: &Buffers,
    n: usize,
) {
    match status {
        ProcessStatus::Sleep => rest.end(true),
        ProcessStatus::ContinueIfNotQuiet => rest.end(outputs.quiet(n)),
        ProcessStatus::Tail => {
            let tail = tail.map(|tail| tail.get(&processor.plugin_handle()));
            let frames = match tail {
                Some(TailLength::Finite(frames)) => Some(u64::from(frames)),
                _ => None,
            };
            rest.end_after_tail(frames, outputs.quiet(n));
        }
        ProcessStatus::Continue => rest.end(false),
    }
}

impl Drop for ClapDevice {
    /// Runs on the main thread, after the audio thread has let go of the device.
    fn drop(&mut self) {
        let mut run = self.shared.run.lock().unwrap_or_else(|e| e.into_inner());
        self.shared.deactivate(&mut run);
    }
}
