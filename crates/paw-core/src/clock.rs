//! Schedule time: the time that timers, settle delays and throttles wait
//! for.
//!
//! The process has one clock, chosen at the start (`paw --clock`). The
//! kernel gives the same `Arc<dyn Clock>` to each reader as an argument or
//! a field. A test runs on a [`ManualClock`], which moves only when it is
//! told (`paw.api.wait`), so the test steps the timers and does not race
//! them. A time that measures work (a budget of Lua, the time limit of a
//! callback, a deadline for another process) is wall time: it reads
//! `Instant` (`paw.api.real_ms`), not this clock.

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

/// The schedule time since the start of the process.
pub trait Clock: Send + Sync {
    /// The time since the clock started.
    fn now(&self) -> Duration;

    /// The manual clock, when this is one: the kernel advances it. None
    /// for a clock that moves by itself.
    fn manual(&self) -> Option<&ManualClock> {
        None
    }
}

/// The clock on the wall: schedule time is real time.
pub struct WallClock {
    started: Instant,
}

impl WallClock {
    /// A clock that starts now.
    pub fn new() -> Self {
        Self { started: Instant::now() }
    }
}

impl Default for WallClock {
    fn default() -> Self {
        Self::new()
    }
}

impl Clock for WallClock {
    fn now(&self) -> Duration {
        self.started.elapsed()
    }
}

/// A clock that moves only when it is told. It holds nanoseconds in an
/// atomic, so that each thread reads the same time.
#[derive(Default)]
pub struct ManualClock {
    nanos: AtomicU64,
}

impl ManualClock {
    /// Move the clock to `at`. A time before the clock's time does nothing:
    /// the clock never goes back.
    pub fn advance_to(&self, at: Duration) {
        let nanos = u64::try_from(at.as_nanos()).unwrap_or(u64::MAX);
        self.nanos.fetch_max(nanos, Ordering::Relaxed);
    }
}

impl Clock for ManualClock {
    fn now(&self) -> Duration {
        Duration::from_nanos(self.nanos.load(Ordering::Relaxed))
    }

    fn manual(&self) -> Option<&ManualClock> {
        Some(self)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_manual_clock_moves_only_forward_and_only_when_told() {
        let clock = ManualClock::default();
        assert_eq!(clock.now(), Duration::ZERO, "a new clock");
        clock.advance_to(Duration::from_millis(150));
        assert_eq!(clock.now(), Duration::from_millis(150), "after an advance");
        clock.advance_to(Duration::from_millis(100));
        assert_eq!(clock.now(), Duration::from_millis(150), "an advance to the past");
    }
}
