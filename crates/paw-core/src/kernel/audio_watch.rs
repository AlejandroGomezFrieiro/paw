//! The counters of the audio thread in the log. The audio thread never
//! logs (no allocation, no lock, no wait): it counts, and the kernel
//! thread reads the counts at the end of each turn and writes a warning
//! when one goes up, at most one line each second for each counter.

use std::time::Duration;

use crate::clock::ScheduleTime;

/// The counters, by their name in the log.
pub(crate) const NAMES: [&str; COUNTERS] =
    ["xruns", "late plugin blocks", "dropped MIDI events", "dropped frames of the take", "leaked blocks"];

/// How many counters the watch has.
pub(crate) const COUNTERS: usize = 5;

/// The shortest time between two lines of one counter.
const GAP: Duration = Duration::from_secs(1);

/// What the log was last told of each counter.
#[derive(Default)]
pub(crate) struct AudioWatch {
    /// The value that the last line gave, or the value after a fall (a
    /// plugin that went takes its late blocks with it).
    told: [u64; COUNTERS],
    /// When the last line of each counter was written.
    at: [Option<ScheduleTime>; COUNTERS],
}

/// One counter that went up, for one line of the log.
#[derive(Debug, PartialEq, Eq)]
pub(crate) struct Rise {
    pub name: &'static str,
    pub value: u64,
    pub added: u64,
}

impl AudioWatch {
    /// The counters of `values` that went up since their last line and
    /// whose last line is [`GAP`] or more before `now`. A rise inside the
    /// gap waits, and the next line gives it with the rises after it.
    pub(crate) fn check(&mut self, now: ScheduleTime, values: [u64; COUNTERS]) -> Vec<Rise> {
        let mut rises = Vec::new();
        for (index, value) in values.into_iter().enumerate() {
            let told = self.told[index];
            if value < told {
                self.told[index] = value;
                continue;
            }
            let quiet = self.at[index].is_none_or(|at| now.since(at) >= GAP);
            if value > told && quiet {
                rises.push(Rise { name: NAMES[index], value, added: value - told });
                self.told[index] = value;
                self.at[index] = Some(now);
            }
        }
        rises
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(ms: u64) -> ScheduleTime {
        ScheduleTime::from_start(Duration::from_millis(ms))
    }

    #[test]
    fn a_rise_is_told_once_a_second_with_what_came_in_between() {
        let mut watch = AudioWatch::default();
        assert!(watch.check(at(0), [0; COUNTERS]).is_empty());
        assert_eq!(watch.check(at(10), [2, 0, 0, 0, 0]), [Rise { name: "xruns", value: 2, added: 2 }]);
        // Inside the second: kept for the next line.
        assert!(watch.check(at(500), [5, 0, 0, 0, 0]).is_empty());
        assert_eq!(watch.check(at(1010), [6, 0, 0, 0, 0]), [Rise { name: "xruns", value: 6, added: 4 }]);
        // Each counter has a second of its own.
        assert_eq!(
            watch.check(at(1020), [6, 1, 0, 0, 0]),
            [Rise { name: "late plugin blocks", value: 1, added: 1 }]
        );
    }

    #[test]
    fn a_fall_is_not_told_and_counts_from_the_new_value() {
        let mut watch = AudioWatch::default();
        watch.check(at(0), [0, 4, 0, 0, 0]);
        assert!(watch.check(at(2000), [0, 1, 0, 0, 0]).is_empty());
        assert_eq!(
            watch.check(at(4000), [0, 2, 0, 0, 0]),
            [Rise { name: "late plugin blocks", value: 2, added: 1 }]
        );
    }
}
