//! The flight recorder: the last events of `debug` and above, in memory,
//! for the file when something goes wrong.

use std::collections::VecDeque;

/// The events that the ring keeps.
pub(super) const KEEP: usize = 2000;

/// One event in the ring.
struct Entry {
    /// The number of the event in the run, from 1.
    seq: u64,
    /// The line as the file writes it, with its time.
    line: String,
    /// Whether the file has the line: a dump leaves it out.
    in_file: bool,
}

/// The ring, and where the last dump ended.
#[derive(Default)]
pub(super) struct Recorder {
    ring: VecDeque<Entry>,
    /// The number of the last event pushed.
    last: u64,
    /// The number of the last event that a dump wrote, or that came before
    /// a dump: a dump writes only the events after it.
    dumped: u64,
}

impl Recorder {
    /// Keep `line`. `in_file` says whether the file has it.
    pub(super) fn push(&mut self, line: String, in_file: bool) {
        if self.ring.len() == KEEP {
            self.ring.pop_front();
        }
        self.last += 1;
        self.ring.push_back(Entry { seq: self.last, line, in_file });
    }

    /// The lines that the next dump writes: the events since the last dump
    /// that the file does not have. Taking them ends a dump.
    pub(super) fn take_undumped(&mut self) -> Vec<&str> {
        let since = std::mem::replace(&mut self.dumped, self.last);
        self.ring
            .iter()
            .filter(|entry| entry.seq > since && !entry.in_file)
            .map(|entry| entry.line.as_str())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_dump_takes_what_the_file_left_out_since_the_last_dump() {
        let mut recorder = Recorder::default();
        recorder.push("debug 1".into(), false);
        recorder.push("info 2".into(), true);
        assert_eq!(recorder.take_undumped(), ["debug 1"]);
        assert!(recorder.take_undumped().is_empty());
        recorder.push("debug 3".into(), false);
        assert_eq!(recorder.take_undumped(), ["debug 3"]);
    }

    #[test]
    fn the_ring_keeps_the_last_events() {
        let mut recorder = Recorder::default();
        for n in 0..KEEP + 5 {
            recorder.push(format!("debug {n}"), false);
        }
        let lines = recorder.take_undumped();
        assert_eq!(lines.len(), KEEP);
        assert_eq!(lines[0], "debug 5");
    }
}
