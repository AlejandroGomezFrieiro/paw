//! State the audio thread publishes for everyone else to read.

use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU32, AtomicU64, Ordering::Relaxed};

use atomic_float::{AtomicF32, AtomicF64};

use crate::guard::Fault;
use crate::launch::{self, LaunchState};
use crate::slot::{DeviceSlot, PartSlot};

use super::stats::BlockStats;
use super::{MAX_DEVICES, MAX_INPUTS, MAX_PARTS};

/// State the audio thread publishes for everyone else to read.
pub struct Shared {
    pub(super) position: AtomicF64,
    pub(super) playing: AtomicBool,
    pub(super) meters: Vec<[AtomicF32; 2]>,
    pub(super) cpu: AtomicF32,
    pub(super) xruns: AtomicU32,
    pub(super) leaked: AtomicU32,
    pub(super) seeks: AtomicU32,
    pub(super) input_latency: AtomicF32,
    pub(super) output_latency: AtomicF32,
    /// Frames the backend asked for in its last callback.
    pub(super) period: AtomicU32,
    /// Peak level of each input channel, falling as part meters do.
    pub(super) input_meters: [AtomicF32; MAX_INPUTS],
    pub(super) latency: AtomicU32,
    pub(super) threads: AtomicU32,
    /// Clicks of a count-in still to come before the song starts; 0 when
    /// there is no count under way.
    pub(super) counting: AtomicU32,
    /// Processing time of every callback.
    pub blocks: BlockStats,
    /// What has gone wrong with each device slot: [`Fault::PANICKED`](crate::guard::Fault::PANICKED),
    /// [`Fault::NOT_FINITE`](crate::guard::Fault::NOT_FINITE). Cleared when a device is put in the slot.
    pub(super) faults: Vec<AtomicU8>,
    /// Each part's clip launcher.
    pub(super) launch: Vec<LaunchState>,
    /// The sound file being heard on its own: its id (0 for none) and
    /// where it has got to, in seconds of the file.
    pub(super) preview_id: AtomicU32,
    pub(super) preview_seconds: AtomicF64,
    /// Blocks of devices that were run, and that slept (see
    /// [`Device::resting`]), since the engine was made.
    pub(super) device_runs: AtomicU64,
    pub(super) device_sleeps: AtomicU64,
    /// Blocks in which the whole engine rested, since it was made.
    pub(super) engine_rests: AtomicU64,
    /// Groups of parts shared out between threads, since the engine was made.
    pub(super) shared_groups: AtomicU64,
    /// Callbacks the engine has finished since it was made. Unlike
    /// [`BlockStats`], never reset: tests and tools wait on it for a state
    /// to reach the audio thread.
    pub(super) processed: AtomicU64,
    /// Blocks each device slot has run (not slept through) since the engine
    /// was made. Only the thread that runs the slot's part writes it.
    pub(super) device_ran: Vec<AtomicU64>,
    /// The peak of each device slot's output, falling as a part's meter
    /// does. Only the thread that runs the slot's part writes it.
    pub(super) device_peaks: Vec<AtomicF32>,
    /// Nanoseconds each device slot has run since the engine was made.
    /// Only the thread that runs the slot's part writes it.
    pub(super) device_ns: Vec<AtomicU64>,
}

impl Shared {
    /// Everything at rest: stopped at the start, no meters, no faults.
    pub(super) fn new() -> Self {
        Self {
            position: AtomicF64::new(0.0),
            playing: AtomicBool::new(false),
            meters: (0..MAX_PARTS)
                .map(|_| [AtomicF32::new(0.0), AtomicF32::new(0.0)])
                .collect(),
            cpu: AtomicF32::new(0.0),
            xruns: AtomicU32::new(0),
            leaked: AtomicU32::new(0),
            seeks: AtomicU32::new(0),
            input_latency: AtomicF32::new(0.0),
            output_latency: AtomicF32::new(0.0),
            period: AtomicU32::new(0),
            input_meters: std::array::from_fn(|_| AtomicF32::new(0.0)),
            latency: AtomicU32::new(0),
            threads: AtomicU32::new(1),
            counting: AtomicU32::new(0),
            blocks: BlockStats::new(),
            faults: (0..MAX_DEVICES).map(|_| AtomicU8::new(0)).collect(),
            launch: (0..MAX_PARTS).map(|_| LaunchState::default()).collect(),
            preview_id: AtomicU32::new(0),
            preview_seconds: AtomicF64::new(0.0),
            device_runs: AtomicU64::new(0),
            device_sleeps: AtomicU64::new(0),
            engine_rests: AtomicU64::new(0),
            shared_groups: AtomicU64::new(0),
            processed: AtomicU64::new(0),
            device_ran: (0..MAX_DEVICES).map(|_| AtomicU64::new(0)).collect(),
            device_peaks: (0..MAX_DEVICES).map(|_| AtomicF32::new(0.0)).collect(),
            device_ns: (0..MAX_DEVICES).map(|_| AtomicU64::new(0)).collect(),
        }
    }

    /// Blocks of devices run, and blocks of devices left asleep, since the
    /// engine was made: what sleeping saves, whatever else the machine does.
    pub fn device_blocks(&self) -> (u64, u64) {
        (
            self.device_runs.load(Relaxed),
            self.device_sleeps.load(Relaxed),
        )
    }

    /// Blocks in which the whole engine rested since it was made: stopped,
    /// with nothing that sounds, it wrote silence and did no other work.
    pub fn engine_rests(&self) -> u64 {
        self.engine_rests.load(Relaxed)
    }

    /// Groups of parts shared out between threads since the engine was
    /// made: a group with little work is done on the audio thread alone.
    pub fn shared_groups(&self) -> u64 {
        self.shared_groups.load(Relaxed)
    }

    /// Callbacks the engine has finished since it was made. A message sent
    /// before one callback starts has taken effect when it is counted.
    pub fn processed(&self) -> u64 {
        self.processed.load(Relaxed)
    }

    /// Blocks the device in `slot` has run since the engine was made, the
    /// blocks it slept through not counted.
    pub fn device_processed(&self, slot: DeviceSlot) -> u64 {
        self.device_ran
            .get(slot.index())
            .map_or(0, |c| c.load(Relaxed))
    }

    /// The peak of the output of the device in `slot`, linear, the larger
    /// of its two channels: falling as a part's meter falls.
    pub fn device_peak(&self, slot: DeviceSlot) -> f32 {
        self.device_peaks.get(slot.index()).map_or(0.0, |p| p.load(Relaxed))
    }

    /// Nanoseconds the device in `slot` has run since the engine was made:
    /// the share of a stretch of time it took is the difference of two
    /// readings over the length of the stretch.
    pub fn device_time(&self, slot: DeviceSlot) -> u64 {
        self.device_ns.get(slot.index()).map_or(0, |t| t.load(Relaxed))
    }

    /// Things the audio thread could not hand back to be freed and leaked
    /// instead, because the garbage queue was full.
    pub fn leaked(&self) -> u32 {
        self.leaked.load(Relaxed)
    }

    /// How many [`Msg::Seek`] the engine has carried out. [`position`](Self::position)
    /// reflects a seek once this has counted it.
    pub fn seeks(&self) -> u32 {
        self.seeks.load(Relaxed)
    }

    /// Transport position in beats.
    pub fn position(&self) -> f64 {
        self.position.load(Relaxed)
    }

    pub fn playing(&self) -> bool {
        self.playing.load(Relaxed)
    }

    /// Beats of a count-in still to be counted before the song starts, or 0.
    pub fn counting(&self) -> u32 {
        self.counting.load(Relaxed)
    }

    /// The sound file being heard on its own ([`Msg::SetPreview`]): its id,
    /// and where it has got to in seconds; `None` once it has ended or
    /// been stopped.
    pub fn preview(&self) -> Option<(u32, f64)> {
        match self.preview_id.load(Relaxed) {
            0 => None,
            id => Some((id, self.preview_seconds.load(Relaxed))),
        }
    }

    /// What a part's clip launcher plays and has queued.
    pub fn launch(&self, slot: PartSlot) -> Option<launch::LaunchView> {
        self.launch.get(slot.index()).map(LaunchState::view)
    }

    /// Post-fader peak level of a part as linear `(left, right)`.
    pub fn meter(&self, slot: PartSlot) -> (f32, f32) {
        match self.meters.get(slot.index()) {
            Some(m) => (m[0].load(Relaxed), m[1].load(Relaxed)),
            None => (0.0, 0.0),
        }
    }

    /// Fraction of the available time the last callbacks spent processing.
    pub fn cpu(&self) -> f32 {
        self.cpu.load(Relaxed)
    }

    pub fn set_cpu(&self, load: f32) {
        self.cpu.store(load, Relaxed);
    }

    pub fn xruns(&self) -> u32 {
        self.xruns.load(Relaxed)
    }

    /// What has gone wrong with the device in `slot` since it was put there
    /// ([`Fault::PANICKED`](crate::guard::Fault::PANICKED), [`NOT_FINITE`](crate::guard::NOT_FINITE)); the bits in `clear` are
    /// taken, so that each is reported once.
    pub fn fault(&self, slot: DeviceSlot, clear: Fault) -> Fault {
        self.faults.get(slot.index()).map_or(Fault::empty(), |f| {
            Fault::from_bits_retain(f.fetch_and(!clear.bits(), Relaxed))
        })
    }

    pub(super) fn set_fault(&self, slot: DeviceSlot, fault: Fault) {
        if let Some(f) = self.faults.get(slot.index()) {
            f.fetch_or(fault.bits(), Relaxed);
        }
    }

    pub fn add_xrun(&self) {
        self.xruns.fetch_add(1, Relaxed);
    }

    /// Frames by which the output is behind the transport: the latency of
    /// the slowest path through the devices, which every other path waits for.
    pub fn latency(&self) -> u32 {
        self.latency.load(Relaxed)
    }

    /// Threads the engine processes parts on, counting the audio thread.
    pub fn threads(&self) -> u32 {
        self.threads.load(Relaxed)
    }

    /// Seconds the backend holds input back before the engine sees it.
    pub fn input_latency(&self) -> f32 {
        self.input_latency.load(Relaxed)
    }

    pub fn set_input_latency(&self, seconds: f32) {
        self.input_latency.store(seconds, Relaxed);
    }

    /// Seconds from the engine producing a block to it being heard, as the
    /// backend reports it.
    pub fn output_latency(&self) -> f32 {
        self.output_latency.load(Relaxed)
    }

    pub fn set_output_latency(&self, seconds: f32) {
        self.output_latency.store(seconds, Relaxed);
    }

    /// Frames per callback as the backend last asked for them, 0 before the first.
    pub fn period(&self) -> u32 {
        self.period.load(Relaxed)
    }

    pub fn set_period(&self, frames: u32) {
        self.period.store(frames, Relaxed);
    }

    /// Peak level of input channel `channel` (from 0) as linear gain,
    /// whether or not any part takes it.
    pub fn input_meter(&self, channel: usize) -> f32 {
        self.input_meters
            .get(channel)
            .map_or(0.0, |m| m.load(Relaxed))
    }
}
