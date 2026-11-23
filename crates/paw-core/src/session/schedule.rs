//! The session on the schedule clock: the time of the turn that runs,
//! which its debounce delays and the watch of the devices wait on, the
//! blocks of the stepped audio backend, which keep step with it, and the
//! work that it has in flight or waiting for that clock
//! (`paw.api.pending`).

use super::Session;
use crate::clock::ScheduleTime;
use crate::stretched::SETTLE;

/// The work of the session that is not done yet. A test waits until no
/// work is in flight (`T.settle`), and moves the clock to `next_due`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Work {
    /// Bakes being made on other threads or in helper processes.
    pub bakes_running: usize,
    /// Bakes that wait for their settle on the schedule clock.
    pub bakes_waiting: usize,
    /// Files of stretched clips that are being hashed, or whose hash the
    /// bakes have not taken in yet: their bakes are asked for after.
    pub hashing: usize,
    /// Plugins being made apart from the main loop, but for those that a
    /// test holds back (`sandbox.hold`).
    pub plugin_loads: usize,
    /// Renders running on a thread of their own (0 or 1).
    pub renders: usize,
    /// Files changed outside paw that wait for their settle.
    pub files: usize,
    /// The first time on the schedule clock when waiting work is due.
    pub next_due: Option<ScheduleTime>,
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
    pub fn set_now(&mut self, now: ScheduleTime) {
        self.now = now;
    }

    /// The schedule time of the turn that runs.
    pub fn now(&self) -> ScheduleTime {
        self.now
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
    pub fn is_audio_stepped(&self) -> bool {
        self.engine.stream.is_stepped()
    }

    /// The time on the schedule clock at which `blocks` more blocks of the
    /// stepped audio backend have ended, or None when the engine runs on
    /// its own.
    pub fn stepped_end_of(&self, blocks: u64) -> Option<ScheduleTime> {
        self.engine.stream.end_of(blocks).map(|end| self.steps.since + end)
    }

    /// The engine restarted: its blocks count from the time of the turn.
    pub(super) fn steps_restart(&mut self) {
        self.steps.since = self.now;
    }

    /// The work in flight or waiting for the schedule clock.
    pub fn work(&self) -> Work {
        let bakes = self.audio.renders.summary();
        let watch = self.watching().then(|| self.watch.next_due());
        let next_due = [self.audio.renders.next_due(SETTLE), self.files_watch.next_due(), watch]
            .into_iter()
            .flatten()
            .min();
        Work {
            bakes_running: bakes.running,
            bakes_waiting: bakes.waiting,
            hashing: self.stretch_hashing(),
            plugin_loads: self.loads.in_flight(),
            renders: usize::from(self.rendering()),
            files: self.files_watch.waiting(),
            next_due,
        }
    }

    /// The files of stretched clips with no hash in the bakes yet that are
    /// still on their way: the worker hashes them, or it has, and the next
    /// poll of the bakes takes the hash in. A file that the worker could
    /// not read is not on its way.
    fn stretch_hashing(&self) -> usize {
        self.audio
            .upkeep
            .unhashed
            .iter()
            .filter(|file| self.sources.is_hashing(file) || self.sources.record(file).is_some())
            .count()
    }
}
