//! The audio-thread half of a VST3 plugin: its `process` and its buses.
//! `process` and the functions it calls run on the audio thread: no lock,
//! no allocation and no wait. `Buses::new` and the drop run on the main
//! thread.

use std::sync::Arc;
use std::sync::atomic::Ordering;

use paw_engine::device::{Rest, silent};
use paw_engine::{Device, Io, ProcessCtx};
use vst3::Steinberg::Vst::*;
use vst3::Steinberg::*;
use vst3::{ComPtr, ComWrapper};

use super::events::{Discard, EventList, ParamChanges, context};
use super::shared::Shared;
use super::{AUDIO, AUX, INPUT, OFFLINE, OK, OUTPUT, REALTIME, SAMPLE_32, wide};
use crate::{HeldNotes, write_output};

/// Buffers for every bus in one direction, laid out as VST3 wants them.
pub(super) struct Buses {
    channels: Vec<Vec<Vec<f32>>>,
    _pointers: Vec<Vec<*mut f32>>,
    buses: Vec<AudioBusBuffers>,
    /// The input bus that takes the side-chain: the first auxiliary one.
    pub(super) key: Option<usize>,
    /// Each bus's channel count and name.
    pub(super) infos: Vec<(usize, String)>,
}

impl Buses {
    pub(super) unsafe fn new(component: &ComPtr<IComponent>, direction: i32, max_block: usize) -> Self {
        // SAFETY: `component` is a live, initialized COM object; each `BusInfo` and `AudioBusBuffers` is a
        // zeroed plain-data struct (zero is valid) that is then filled; bus indexes are below `getBusCount`.
        // The buffers' pointers lead to `max_block` frames per channel for as long as `Buses` lives.
        unsafe {
            let mut key = None;
            let mut infos = Vec::new();
            let mut channels: Vec<Vec<Vec<f32>>> = (0..component.getBusCount(AUDIO, direction))
                .map(|index| {
                    let mut info: BusInfo = std::mem::zeroed();
                    component.getBusInfo(AUDIO, direction, index, &mut info);
                    infos.push((info.channelCount.max(0) as usize, wide(&info.name)));
                    // The first bus carries the part's audio, the first
                    // auxiliary input a side-chain, and every output is
                    // heard where it is routed.
                    let keys = direction == INPUT
                        && key.is_none()
                        && index > 0
                        && info.busType == AUX
                        && info.channelCount > 0;
                    if keys {
                        key = Some(index as usize);
                    }
                    let active = index == 0 || keys || direction == OUTPUT;
                    component.activateBus(AUDIO, direction, index, active as TBool);
                    (0..info.channelCount.max(0))
                        .map(|_| vec![0.0; max_block])
                        .collect()
                })
                .collect();
            let mut pointers: Vec<Vec<*mut f32>> = channels
                .iter_mut()
                .map(|bus| bus.iter_mut().map(|ch| ch.as_mut_ptr()).collect())
                .collect();
            let buses = pointers
                .iter_mut()
                .map(|bus| {
                    let mut buffers: AudioBusBuffers = std::mem::zeroed();
                    buffers.numChannels = bus.len() as i32;
                    buffers.__field0.channelBuffers32 = bus.as_mut_ptr();
                    buffers
                })
                .collect();
            Self {
                channels,
                _pointers: pointers,
                buses,
                key,
                infos,
            }
        }
    }

    /// Put the block's sound on the main input bus, as mono or stereo, and
    /// the side-chain on the key bus; `keyed` tells whether that bus holds a
    /// key.
    fn read_input(&mut self, io: &Io, keyed: &mut bool, n: usize) {
        if let Some(bus) = self.channels.first_mut() {
            match bus.as_mut_slice() {
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
        if let Some(bus) = self.key.and_then(|b| self.channels.get_mut(b)) {
            *keyed = crate::put_key(bus.as_mut_slice(), io.sidechain, *keyed, n);
        }
    }

    /// Give the block's sound from the output buses: the main bus on the
    /// part's pair, added for an instrument, and the other pairs where they
    /// go.
    fn write_output(&self, io: &mut Io, pairs: &[crate::OutPair], add: bool, n: usize) {
        if let Some(bus) = self.channels.first() {
            match bus.as_slice() {
                [] => {}
                [mono] => write_output(io.left, io.right, &[&mono[..n]], add),
                [left, right, ..] => {
                    write_output(io.left, io.right, &[&left[..n], &right[..n]], add)
                }
            }
        }
        crate::write_pairs(pairs, &self.channels, io.outputs, n);
    }
}

/// The audio-thread half of a VST3 plugin, which the engine runs.
pub(super) struct Vst3Device {
    pub(super) shared: Arc<Shared>,
    /// Edits made in the plugin's editor, which the controller knows about
    /// and the processor still has to be told: parameter index and value.
    pub(super) edited: rtrb::Consumer<(u32, f32)>,
    pub(super) inputs: Buses,
    pub(super) outputs: Buses,
    /// Whether the side-chain bus holds a key.
    pub(super) keyed: bool,
    /// The output buses as stereo pairs, the main one first.
    pub(super) out_pairs: Vec<crate::OutPair>,
    pub(super) events: ComWrapper<EventList>,
    pub(super) changes: ComWrapper<ParamChanges>,
    pub(super) discard: ComWrapper<Discard>,
    /// Parameter changes waiting for the next block: index and value.
    pub(super) pending: Vec<(u32, f32)>,
    /// The parameter each MIDI controller moves, by controller number, with
    /// aftertouch at 128 and the pitch wheel at 129;
    /// [`NO_PARAM`](super::events::NO_PARAM) for none.
    pub(super) midi_map: Box<[ParamID; 130]>,
    /// Controller moves of this block, as parameter and value.
    pub(super) controls: Vec<(ParamID, f64)>,
    pub(super) held: HeldNotes,
    pub(super) sample_rate: f64,
    pub(super) samples: i64,
    /// How long the plugin rings after its input stops, in frames, as it
    /// said when it was made; `u32::MAX` for for ever.
    pub(super) tail: u32,
    /// Its tail has gone by and its output was silent (see
    /// [`Device::resting`]).
    pub(super) rest: Rest,
}

// The buffers hold raw pointers into vectors the device owns.
// SAFETY: The buffers hold raw pointers into vectors that the device owns and moves with itself.
// The device is used from the audio thread only, after the main thread built it.
unsafe impl Send for Vst3Device {}

impl Device for Vst3Device {
    /// Once its tail has gone by in silence and its output was silent,
    /// unless a parameter has moved since.
    fn resting(&self) -> bool {
        self.rest.resting()
            && self.pending.is_empty()
            && self.edited.is_empty()
            && !self.shared.host.wake.load(Ordering::Relaxed)
    }

    /// In three steps: the events and the audio in, the call of the
    /// processor, and its rest and audio out.
    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        let n = io.left.len();
        // Woken: its tail starts again from here.
        self.rest
            .begin(io, self.shared.host.wake.swap(false, Ordering::Relaxed));
        // The main thread has the processor stopped to set it up again: this
        // block is left as it came, which adds silence for an instrument and
        // passes the input through for an effect.
        let Ok(_running) = self.shared.run.try_lock() else {
            return;
        };

        // 1. The events and the audio in.
        self.inputs.read_input(io, &mut self.keyed, n);
        // SAFETY: This is the audio thread, outside the plugin's `process`: the only user of the
        // event list.
        unsafe {
            self.events
                .fill(&mut self.held, io.events.as_slice(), &self.midi_map, &mut self.controls)
        };
        while let Ok(edit) = self.edited.pop() {
            if self.pending.len() < self.pending.capacity() {
                self.pending.push(edit);
            }
        }
        self.changes
            .fill(&mut self.pending, &mut self.controls, &self.shared.param_ids);
        let mut context = context(ctx, self.sample_rate, self.samples);
        self.samples += n as i64;

        // 2. The call.
        // SAFETY: This is the audio thread, holding `self.shared.run` (the `try_lock` above), so the main
        // thread does not stop or set up the processor during the call; it is the only user of the
        // event list, the queues and the buffers;
        // the pointers in `data` lead to live buffers of `max_block` frames per channel (`n` is at most
        // that) and to COM objects that the device owns, which live until `process` returns; the
        // zeroed `ProcessData` is plain data, filled before use.
        unsafe {
            let mut data: ProcessData = std::mem::zeroed();
            data.processMode = if self.shared.offline.load(Ordering::Relaxed) {
                OFFLINE
            } else {
                REALTIME
            };
            data.symbolicSampleSize = SAMPLE_32;
            data.numSamples = n as i32;
            data.numInputs = self.inputs.buses.len() as i32;
            data.numOutputs = self.outputs.buses.len() as i32;
            data.inputs = self.inputs.buses.as_mut_ptr();
            data.outputs = self.outputs.buses.as_mut_ptr();
            data.inputParameterChanges = self
                .changes
                .as_com_ref::<IParameterChanges>()
                .unwrap()
                .as_ptr();
            data.outputParameterChanges = self
                .discard
                .as_com_ref::<IParameterChanges>()
                .unwrap()
                .as_ptr();
            data.inputEvents = self.events.as_com_ref::<IEventList>().unwrap().as_ptr();
            data.processContext = &mut context;
            let processed = self
                .shared
                .host
                .blocks
                .run(|| self.shared.processor.process(&mut data));
            if processed != OK {
                return;
            }
        }

        // 3. Its rest and the audio out.
        self.rest.end_after_tail(
            (self.tail != u32::MAX).then_some(self.tail as u64),
            self.outputs.channels.iter().flatten().all(|c| silent(&c[..n])),
        );
        let add = self.inputs.buses.is_empty();
        self.outputs.write_output(io, &self.out_pairs, add, n);
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if self.pending.len() < self.pending.capacity() {
            self.pending.push((index, value));
        }
    }
}

impl Drop for Vst3Device {
    /// Runs on the main thread, after the audio thread has let go of the device.
    fn drop(&mut self) {
        // SAFETY: The device is dropped on the main thread, after the audio thread let go of it, so
        // stopping the processor does not race with `process`.
        unsafe {
            self.shared.processor.setProcessing(0);
            self.shared.component.setActive(0);
        }
    }
}