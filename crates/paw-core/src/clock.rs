//! Schedule time: the time that timers, debounce delays and throttles wait
//! for.
//!
//! The process has one clock, chosen at the start (`paw --clock`), and the
//! kernel is its one owner. Each turn of the loop reads it once and gives
//! the time to the session as a [`ScheduleTime`]: no part of the session
//! keeps a clock of its own. A test runs on the manual clock, which moves
//! only when it is told (`paw.api.wait`), so the test steps the timers and
//! does not race them.
//!
//! The rule: a time that decides *when* a thing happens is a
//! [`ScheduleTime`]. A time that measures *how long* work took (a budget of
//! Lua, the time limit of a callback, a deadline for another process) is
//! wall time: it reads `Instant` (`paw.api.real_ms`). Clippy refuses
//! `Instant::now` in this crate (`clippy.toml`), and each budget site says
//! why it reads the wall.

use std::ops::{Add, Sub};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

/// A time on the schedule clock: how long after the start of the process.
/// Only a [`Clock`] makes one from the time of the machine, so a budget
/// time cannot go in by mistake.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ScheduleTime(Duration);

impl ScheduleTime {
    /// The start of the clock.
    pub const ZERO: Self = Self(Duration::ZERO);

    /// The time `since` after the start of the clock. For a test, and for
    /// a time that the code has as a count (a block of the stepped engine).
    pub const fn from_start(since: Duration) -> Self {
        Self(since)
    }

    /// How long after the start of the clock.
    pub const fn since_start(self) -> Duration {
        self.0
    }

    /// How long after `earlier`; zero when `earlier` is later.
    pub fn since(self, earlier: Self) -> Duration {
        self.0.saturating_sub(earlier.0)
    }

    /// The time in milliseconds after the start of the clock, as Lua reads
    /// it (`paw.api.now`).
    pub fn as_ms(self) -> f64 {
        self.0.as_secs_f64() * 1000.0
    }
}

impl Add<Duration> for ScheduleTime {
    type Output = Self;

    fn add(self, by: Duration) -> Self {
        Self(self.0.saturating_add(by))
    }
}

impl Sub for ScheduleTime {
    type Output = Duration;

    /// How long after `earlier`; zero when `earlier` is later.
    fn sub(self, earlier: Self) -> Duration {
        self.since(earlier)
    }
}

/// The schedule clock of the process.
#[derive(Debug)]
pub enum Clock {
    /// Schedule time is real time since `started`.
    Wall { started: Instant },
    /// The clock moves only when it is told (`advance_to`). It holds
    /// nanoseconds in an atomic, so that each thread reads the same time.
    Manual { nanos: AtomicU64 },
}

/// The clock moves by itself: only the manual clock is told to move.
#[derive(Debug, thiserror::Error)]
#[error("the clock on the wall moves by itself")]
pub struct NotManual;

impl Clock {
    /// A clock on the wall that starts now.
    pub fn wall() -> Self {
        #[expect(clippy::disallowed_methods, reason = "the start of the wall clock is the one read of the wall for schedule time")]
        let started = Instant::now();
        Self::Wall { started }
    }

    /// A manual clock at zero.
    pub fn manual() -> Self {
        Self::Manual { nanos: AtomicU64::new(0) }
    }

    /// Whether the clock moves only when it is told.
    pub fn is_manual(&self) -> bool {
        matches!(self, Self::Manual { .. })
    }

    /// The time now.
    pub fn now(&self) -> ScheduleTime {
        ScheduleTime(match self {
            Self::Wall { started } => started.elapsed(),
            Self::Manual { nanos } => Duration::from_nanos(nanos.load(Ordering::Relaxed)),
        })
    }

    /// Move the manual clock to `at`. A time before the clock's time does
    /// nothing: the clock never goes back.
    pub(crate) fn advance_to(&self, at: ScheduleTime) -> Result<(), NotManual> {
        let Self::Manual { nanos } = self else {
            return Err(NotManual);
        };
        let at = u64::try_from(at.0.as_nanos()).unwrap_or(u64::MAX);
        nanos.fetch_max(at, Ordering::Relaxed);
        Ok(())
    }
}

/// What the loop has left to do after a turn: the union of what each part
/// tells (the timers, the messages, the session).
#[must_use]
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Agenda {
    /// Work that the next turn can do now: a timer or a delay is due, a
    /// message waits.
    pub ready: bool,
    /// Work in flight on other threads or in other processes: bakes,
    /// hashes, plugin loads and renders.
    pub in_flight: u32,
    /// The first time after the turn when a timer or a delay is due.
    pub next_due: Option<ScheduleTime>,
    /// The longest the loop may sleep while a part has news that rings no
    /// bell: a plugin's window draws in the upkeep, the audio thread only
    /// marks. None: the part needs no tick.
    pub tick: Option<Duration>,
}

impl Agenda {
    /// Nothing is ready and nothing is in flight: only due times are left.
    pub fn quiet(&self) -> bool {
        !self.ready && self.in_flight == 0
    }
}

impl std::ops::BitOr for Agenda {
    type Output = Self;

    /// The work of both parts.
    fn bitor(self, other: Self) -> Self {
        fn first<T: Ord>(a: Option<T>, b: Option<T>) -> Option<T> {
            match (a, b) {
                (Some(a), Some(b)) => Some(a.min(b)),
                (a, b) => a.or(b),
            }
        }
        Self {
            ready: self.ready || other.ready,
            in_flight: self.in_flight.saturating_add(other.in_flight),
            next_due: first(self.next_due, other.next_due),
            tick: first(self.tick, other.tick),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(ms: u64) -> ScheduleTime {
        ScheduleTime::from_start(Duration::from_millis(ms))
    }

    #[test]
    fn a_manual_clock_moves_only_forward_and_only_when_told() {
        let clock = Clock::manual();
        assert_eq!(clock.now(), ScheduleTime::ZERO, "a new clock");
        clock.advance_to(at(150)).unwrap();
        assert_eq!(clock.now(), at(150), "after an advance");
        clock.advance_to(at(100)).unwrap();
        assert_eq!(clock.now(), at(150), "an advance to the past");
    }

    #[test]
    fn an_agenda_of_two_parts_has_the_work_of_both_and_the_first_due_time() {
        let tick = Some(Duration::from_millis(16));
        let timers = Agenda { next_due: Some(at(40)), ..Agenda::default() };
        let session = Agenda { in_flight: 2, next_due: Some(at(30)), tick, ..Agenda::default() };
        assert_eq!(timers | session, Agenda { ready: false, in_flight: 2, next_due: Some(at(30)), tick });
        assert!(!(timers | session).quiet(), "work in flight");
        assert!(timers.quiet(), "a due time is not work");
        assert_eq!(Agenda::default() | timers, timers, "an empty part adds nothing");
    }

    #[test]
    fn the_wall_clock_is_not_told_to_move() {
        assert!(Clock::wall().advance_to(at(1)).is_err());
    }
}
