//! State the audio thread publishes for everyone else to read.

use std::sync::atomic::{AtomicBool, AtomicU8, AtomicU32, AtomicU64, Ordering::Relaxed};

use crate::guard::Fault;
use crate::launch::{self, LaunchState};
use crate::slot::{DeviceSlot, TrackSlot};

use super::stats::BlockStats;
use super::{MAX_DEVICES, MAX_INPUTS, MAX_TRACKS};

/// State the audio thread publishes for everyone else to read.
pub struct Shared {
    pub(super) position: AtomicU64,
    pub(super) playing: AtomicBool,
    pub(super) meters: Vec<[AtomicU32; 2]>,
    pub(super) cpu: AtomicU32,
    pub(super) xruns: AtomicU32,
    pub(super) leaked: AtomicU32,
    pub(super) seeks: AtomicU32,
    pub(super) input_latency: AtomicU32,
    pub(super) output_latency: AtomicU32,
    /// Frames the backend asked for in its last callback.
    pub(super) period: AtomicU32,
    /// Peak level of each input channel, falling as track meters do.
    pub(super) input_meters: [AtomicU32; MAX_INPUTS],
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
    /// Each track's clip launcher.
    pub(super) launch: Vec<LaunchState>,
    /// The sound file being heard on its own: its id (0 for none) and
    /// where it has got to, in seconds of the file.
    pub(super) preview_id: AtomicU32,
    pub(super) preview_seconds: AtomicU64,
    /// Blocks of devices that were run, and that slept (see
    /// [`Device::resting`]), since the engine was made.
    pub(super) device_runs: AtomicU64,
    pub(super) device_sleeps: AtomicU64,
    /// Groups of tracks shared out between threads, since the engine was made.
    pub(super) shared_groups: AtomicU64,
    /// Callbacks the engine has finished since it was made. Unlike
    /// [`BlockStats`], never reset: tests and tools wait on it for a state
    /// to reach the audio thread.
    pub(super) processed: AtomicU64,
    /// Blocks each device slot has run (not slept through) since the engine
    /// was made. Only the thread that runs the slot's track writes it.
    pub(super) device_ran: Vec<AtomicU64>,
}

impl Shared {
    /// Everything at rest: stopped at the start, no meters, no faults.
    pub(super) fn new() -> Self {
        Self {
            position: AtomicU64::new(0f64.to_bits()),
            playing: AtomicBool::new(false),
            meters: (0..MAX_TRACKS)
                .map(|_| [AtomicU32::new(0), AtomicU32::new(0)])
                .collect(),
            cpu: AtomicU32::new(0),
            xruns: AtomicU32::new(0),
            leaked: AtomicU32::new(0),
            seeks: AtomicU32::new(0),
            input_latency: AtomicU32::new(0),
            output_latency: AtomicU32::new(0),
            period: AtomicU32::new(0),
            input_meters: std::array::from_fn(|_| AtomicU32::new(0)),
            latency: AtomicU32::new(0),
            threads: AtomicU32::new(1),
            counting: AtomicU32::new(0),
            blocks: BlockStats::new(),
            faults: (0..MAX_DEVICES).map(|_| AtomicU8::new(0)).collect(),
            launch: (0..MAX_TRACKS).map(|_| LaunchState::default()).collect(),
            preview_id: AtomicU32::new(0),
            preview_seconds: AtomicU64::new(0),
            device_runs: AtomicU64::new(0),
            device_sleeps: AtomicU64::new(0),
            shared_groups: AtomicU64::new(0),
            processed: AtomicU64::new(0),
            device_ran: (0..MAX_DEVICES).map(|_| AtomicU64::new(0)).collect(),
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

    /// Groups of tracks shared out between threads since the engine was
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
        f64::from_bits(self.position.load(Relaxed))
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
            id => Some((id, f64::from_bits(self.preview_seconds.load(Relaxed)))),
        }
    }

    /// What a track's clip launcher plays and has queued.
    pub fn launch(&self, slot: TrackSlot) -> Option<launch::LaunchView> {
        self.launch.get(slot.index()).map(LaunchState::view)
    }

    /// Post-fader peak level of a track as linear `(left, right)`.
    pub fn meter(&self, slot: TrackSlot) -> (f32, f32) {
        match self.meters.get(slot.index()) {
            Some(m) => (
                f32::from_bits(m[0].load(Relaxed)),
                f32::from_bits(m[1].load(Relaxed)),
            ),
            None => (0.0, 0.0),
        }
    }

    /// Fraction of the available time the last callbacks spent processing.
    pub fn cpu(&self) -> f32 {
        f32::from_bits(self.cpu.load(Relaxed))
    }

    pub fn set_cpu(&self, load: f32) {
        self.cpu.store(load.to_bits(), Relaxed);
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

    /// Threads the engine processes tracks on, counting the audio thread.
    pub fn threads(&self) -> u32 {
        self.threads.load(Relaxed)
    }

    /// Seconds the backend holds input back before the engine sees it.
    pub fn input_latency(&self) -> f32 {
        f32::from_bits(self.input_latency.load(Relaxed))
    }

    pub fn set_input_latency(&self, seconds: f32) {
        self.input_latency.store(seconds.to_bits(), Relaxed);
    }

    /// Seconds from the engine producing a block to it being heard, as the
    /// backend reports it.
    pub fn output_latency(&self) -> f32 {
        f32::from_bits(self.output_latency.load(Relaxed))
    }

    pub fn set_output_latency(&self, seconds: f32) {
        self.output_latency.store(seconds.to_bits(), Relaxed);
    }

    /// Frames per callback as the backend last asked for them, 0 before the first.
    pub fn period(&self) -> u32 {
        self.period.load(Relaxed)
    }

    pub fn set_period(&self, frames: u32) {
        self.period.store(frames, Relaxed);
    }

    /// Peak level of input channel `channel` (from 0) as linear gain,
    /// whether or not any track takes it.
    pub fn input_meter(&self, channel: usize) -> f32 {
        self.input_meters
            .get(channel)
            .map_or(0.0, |m| f32::from_bits(m.load(Relaxed)))
    }
}
