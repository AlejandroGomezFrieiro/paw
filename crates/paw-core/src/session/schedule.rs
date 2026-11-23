//! The session on the schedule clock: the clock that its settle delays
//! and the watch of the devices wait on, the blocks of the stepped audio
//! backend, which keep step with it, and the work that it has in flight or
//! waiting for that clock (`paw.api.pending`).

use std::sync::Arc;
use std::time::Duration;

use super::Session;
use crate::clock::{Clock, WallClock};
use crate::stretched::SETTLE;

/// The work of the session that is not done yet. A test waits until no
/// work is in flight (`T.settle`), and moves the clock to `next_due`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Work {
    /// Bakes being made on other threads or in helper processes.
    pub bakes_running: usize,
    /// Bakes that wait for their settle on the schedule clock.
    pub bakes_waiting: usize,
    /// Plugins being made apart from the main loop, but for those that a
    /// test holds back (`sandbox.hold`).
    pub plugin_loads: usize,
    /// Renders running on a thread of their own (0 or 1).
    pub renders: usize,
    /// Files changed outside paw that wait for their settle.
    pub files: usize,
    /// The first time on the schedule clock when waiting work is due.
    pub next_due: Option<Duration>,
}

/// The stepped audio backend on the schedule clock.
pub(super) struct Steps {
    /// The schedule clock (`Session::set_clock`).
    clock: Arc<dyn Clock>,
    /// The time on `clock` when the engine started: its blocks count from
    /// it. Set at each start of the engine.
    since: Duration,
}

impl Default for Steps {
    fn default() -> Self {
        Self { clock: Arc::new(WallClock::new()), since: Duration::ZERO }
    }
}

impl Session {
    /// Wait the settle delays on `clock` from now on: the bakes, the file
    /// watch, the check of missing files and the watch of the devices.
    /// The blocks of the stepped audio
    /// backend keep step with it. The kernel gives its clock once, before
    /// any work.
    pub fn set_clock(&mut self, clock: &Arc<dyn Clock>) {
        self.audio.renders.set_clock(clock.clone());
        self.files_watch.clock = clock.clone();
        self.watch.clock = clock.clone();
        self.files_there.clock = clock.clone();
        self.steps.since = clock.now();
        self.steps.clock = clock.clone();
    }

    /// Run the blocks of the stepped audio backend up to the time of the
    /// schedule clock: the audio and the clock are one time. Gives the
    /// blocks run. An engine on another backend runs on its own.
    pub(super) fn run_stepped_audio(&mut self) -> u64 {
        let at = self.steps.clock.now().saturating_sub(self.steps.since);
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
    pub fn stepped_end_of(&self, blocks: u64) -> Option<Duration> {
        self.engine.stream.end_of(blocks).map(|end| self.steps.since + end)
    }

    /// The engine restarted: its blocks count from now.
    pub(super) fn steps_restart(&mut self) {
        self.steps.since = self.steps.clock.now();
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
            plugin_loads: self.loads.in_flight(),
            renders: usize::from(self.rendering()),
            files: self.files_watch.waiting(),
            next_due,
        }
    }
}
