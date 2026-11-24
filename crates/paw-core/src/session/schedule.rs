//! The session on the schedule clock: the time of the turn that runs,
//! which its debounce delays and the watch of the devices wait on, the
//! blocks of the stepped audio backend, which keep step with it, the work
//! that waits for that clock (`paw.api.pending`), and the bells of its
//! workers.

use super::Session;
use crate::clock::ScheduleTime;
use crate::doorbell::{Doorbell, Woken};

/// Work of the session that waits for the schedule clock: a test reads
/// it (`paw.api.pending`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct Waiting {
    /// Bakes that wait for their settle.
    pub bakes: usize,
    /// Files changed outside paw that wait for their settle.
    pub files: usize,
}

/// The stepped audio backend on the schedule clock.
#[derive(Default)]
pub(super) struct Steps {
    /// The schedule time when the engine started: its blocks count from
    /// it. Set at each start of the engine.
    since: ScheduleTime,
}

impl Session {
    /// The schedule time of the turn that runs. The kernel sets it at the
    /// start of each turn, before any work of the turn: each "when" of the
    /// session reads it, and the session reads no clock.
    pub(crate) fn set_now(&mut self, now: ScheduleTime) {
        self.now = now;
    }

    /// Run the blocks of the stepped audio backend up to the time of the
    /// turn: the audio and the clock are one time. Gives the blocks run.
    /// An engine on another backend runs on its own.
    pub(super) fn run_stepped_audio(&mut self) -> u64 {
        let at = self.now - self.steps.since;
        self.engine.stream.run_to(at)
    }

    /// Whether the engine plays on the stepped audio backend: its blocks
    /// keep step with the schedule clock.
    pub(crate) fn is_audio_stepped(&self) -> bool {
        self.engine.stream.is_stepped()
    }

    /// The time on the schedule clock at which `blocks` more blocks of the
    /// stepped audio backend have ended, or None when the engine runs on
    /// its own.
    pub(crate) fn stepped_end_of(&self, blocks: u64) -> Option<ScheduleTime> {
        self.engine.stream.end_of(blocks).map(|end| self.steps.since + end)
    }

    /// The engine restarted: its blocks count from the time of the turn.
    pub(super) fn steps_restart(&mut self) {
        self.steps.since = self.now;
    }

    /// Give the workers of the session their bells: what they ring wakes
    /// the kernel's loop. The kernel calls it once, at the start.
    pub(crate) fn set_doorbell(&mut self, doorbell: Doorbell) {
        self.audio.renders.set_bell(doorbell.bell(Woken::BAKES));
        self.sources.set_bell(doorbell.bell(Woken::HASHES));
        self.files_watch.doorbell = doorbell.clone();
        self.bell = doorbell;
    }

    /// The work that waits for the schedule clock.
    pub(crate) fn waiting(&self) -> Waiting {
        Waiting { bakes: self.audio.renders.summary().waiting, files: self.files_watch.waiting() }
    }
}
