//! The session on the schedule clock: the clock that its settle delays
//! wait on, and the work that it has in flight or waiting for that clock
//! (`paw.api.pending`).

use std::sync::Arc;
use std::time::Duration;

use super::Session;
use crate::clock::Clock;
use crate::stretched::SETTLE;

/// The work of the session that is not done yet. A test waits until no
/// work is in flight (`T.settle`), and moves the clock to `next_due`.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(crate) struct Work {
    /// Bakes being made on other threads or in helper processes.
    pub bakes_running: usize,
    /// Bakes that wait for their settle on the schedule clock.
    pub bakes_waiting: usize,
    /// Plugins being made apart from the main loop.
    pub plugin_loads: usize,
    /// Renders running on a thread of their own (0 or 1).
    pub renders: usize,
    /// Files changed outside paw that wait for their settle.
    pub files: usize,
    /// The first time on the schedule clock when waiting work is due.
    pub next_due: Option<Duration>,
}

impl Session {
    /// Wait the settle delays on `clock` from now on: the bakes and the
    /// file watch. The kernel gives its clock once, before any work.
    pub(crate) fn set_clock(&mut self, clock: &Arc<dyn Clock>) {
        self.audio.renders.set_clock(clock.clone());
        self.files_watch.clock = clock.clone();
    }

    /// The work in flight or waiting for the schedule clock.
    pub(crate) fn work(&self) -> Work {
        let bakes = self.audio.renders.summary();
        let next_due = [self.audio.renders.next_due(SETTLE), self.files_watch.next_due()]
            .into_iter()
            .flatten()
            .min();
        Work {
            bakes_running: bakes.running,
            bakes_waiting: bakes.waiting,
            plugin_loads: self.loads.count(),
            renders: usize::from(self.rendering()),
            files: self.files_watch.waiting(),
            next_due,
        }
    }
}
