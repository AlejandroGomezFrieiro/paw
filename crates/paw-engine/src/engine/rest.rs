//! The engine at rest: stopped, with nothing that sounds or can start to
//! sound by itself, a callback writes silence and does no other work.
//!
//! Devices at rest already sleep through silent blocks (see
//! [`Device::resting`](crate::device::Device::resting)). What is left of a
//! block then is the walk over every track: buffers cleared, sums, meters.
//! The engine rests as a whole after [`QUIET_BLOCKS`] quiet blocks in a row,
//! and a message or a MIDI input event wakes it in the same callback, so
//! the first sound comes in the same block as it would without the rest.

use std::sync::atomic::Ordering::Relaxed;

use crate::device::silent;

use super::{Engine, MAX_BLOCK};

/// Quiet blocks in a row before the engine rests.
pub(super) const QUIET_BLOCKS: u32 = 8;

/// The meters must have fallen below this (-100 dB) before the engine rests
/// and sets them to zero: lower than any meter shows.
const METER_FLOOR: f32 = 1e-5;

/// How near the engine is to rest.
#[derive(Default)]
pub(super) struct Rest {
    /// Quiet blocks in a row, and their frames.
    blocks: u32,
    frames: u64,
    /// Devices that slept through the last quiet block: each of them
    /// sleeps through a rested block too.
    sleeps: u64,
    /// The engine rests.
    resting: bool,
}

/// What a block did, to tell whether it was quiet: the engine's counts of
/// devices run and slept before it.
#[derive(Clone, Copy)]
pub(super) struct Counts {
    runs: u64,
    sleeps: u64,
}

impl Engine {
    /// Whether something can sound, or start to, without a message: the
    /// song plays or counts in, a launch is queued, a sound file plays on
    /// its own, or a track hears an audio input. Or resting is off: sleep
    /// is off, or the engine renders.
    fn busy(&self) -> bool {
        !self.sleep
            || self.offline
            || self.playing
            || self.count.is_some()
            || self.launching
            || self.preview.is_some()
            || self.preview_leaving.is_some()
            || self.listening
    }

    /// Whether this callback rests. `woken` says that a message or a MIDI
    /// input event came: then it does not, and the count starts again.
    pub(super) fn rests(&mut self, woken: bool) -> bool {
        if self.launching && !self.playing && !woken {
            // Stopped, a launch starts in the block after it came: look
            // again whether one is still queued.
            self.next_launch(self.position);
        }
        if woken || self.busy() {
            self.rest = Rest::default();
            return false;
        }
        if self.rest.resting {
            return true;
        }
        let latency = self.schedule.as_ref().map_or(0, |s| s.latency as u64);
        // What the delays of the paths still hold comes out within their
        // latency, and a meter that still shows something falls on.
        if self.rest.blocks < QUIET_BLOCKS || self.rest.frames < latency || !self.meters_fallen() {
            return false;
        }
        self.clear_meters();
        self.rest.resting = true;
        true
    }

    /// The counts before a block, for [`note_quiet`](Self::note_quiet).
    pub(super) fn counts(&self) -> Counts {
        let (runs, sleeps) = self.shared.device_blocks();
        Counts { runs, sleeps }
    }

    /// After a block of `left` and `right`: it was quiet if nothing was
    /// busy, no device ran, and the output is silent.
    pub(super) fn note_quiet(&mut self, before: Counts, left: &[f32], right: &[f32]) {
        let after = self.counts();
        let quiet = !self.busy() && after.runs == before.runs && silent(left) && silent(right);
        if quiet {
            self.rest.blocks = self.rest.blocks.saturating_add(1);
            self.rest.frames += left.len() as u64;
            self.rest.sleeps = after.sleeps - before.sleeps;
        } else {
            self.rest = Rest::default();
        }
    }

    /// A rested callback: silence out, and the inputs metered, as they are
    /// whether or not a track takes them.
    pub(super) fn rest_callback(
        &mut self,
        input: &[f32],
        channels: usize,
        left: &mut [f32],
        right: &mut [f32],
    ) {
        left.fill(0.0);
        right.fill(0.0);
        let total = left.len();
        if channels > 0 {
            let mut done = 0;
            while done < total {
                let n = (total - done).min(MAX_BLOCK);
                self.load_input(input, channels, done, n);
                done += n;
            }
        }
        let blocks = total.div_ceil(MAX_BLOCK) as u64;
        self.shared.engine_rests.fetch_add(blocks, Relaxed);
        if self.rest.sleeps > 0 {
            self.shared
                .device_sleeps
                .fetch_add(self.rest.sleeps * blocks, Relaxed);
        }
    }

    /// Whether every track's meter has fallen below what a meter shows.
    fn meters_fallen(&mut self) -> bool {
        let Some(schedule) = self.schedule.take() else {
            return true;
        };
        let fallen = schedule.entries.iter().all(|entry| {
            self.track_mut(entry.slot)
                .is_none_or(|t| t.peak.iter().all(|p| *p < METER_FLOOR))
        });
        self.schedule = Some(schedule);
        fallen
    }

    /// Set every track's meter to zero, where it would fall to.
    fn clear_meters(&mut self) {
        let Some(schedule) = self.schedule.take() else {
            return;
        };
        for entry in &schedule.entries {
            if let Some(t) = self.track_mut(entry.slot) {
                t.peak = [0.0; 2];
            }
            if let Some(meter) = self.shared.meters.get(entry.slot.index()) {
                meter[0].store(0.0, Relaxed);
                meter[1].store(0.0, Relaxed);
            }
        }
        self.schedule = Some(schedule);
    }

    /// Look again whether a track hears an audio input (after the inputs
    /// or the tracks changed): a message, not a block, does this.
    pub(super) fn note_listening(&mut self) {
        self.listening = self.tracks.iter_mut().any(|t| {
            t.get_mut()
                .as_deref()
                .is_some_and(|t| t.input_channels > 0 && (t.monitor || t.armed))
        });
    }
}
