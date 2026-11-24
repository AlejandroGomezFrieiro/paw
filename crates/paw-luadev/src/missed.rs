//! The events of the blocks that a call held the state through. The audio
//! thread does not wait for a call (device.rs), so the script does not see
//! such a block. Its events wait here, and the next block that runs gives
//! them to the script first, at frame 0, in the order that they came.
//!
//! The storage has a fixed size, so the audio thread does not allocate.
//! When it is full, a note-off pushes out the newest event that is not a
//! note-off: a lost note-on is a missed note, but a lost note-off is a note
//! that does not stop.

use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use paw_engine::Event;
use paw_types::EventKind;

pub(crate) struct Missed {
    events: Box<[Event]>,
    len: usize,
    /// The blocks that the script did not run, for `lua.misses`.
    blocks: Arc<AtomicU64>,
}

fn stops_a_note(event: &Event) -> bool {
    matches!(
        event.kind,
        EventKind::NoteOff { .. } | EventKind::AllNotesOff
    )
}

impl Missed {
    pub(crate) fn new(capacity: usize, blocks: Arc<AtomicU64>) -> Self {
        let empty = Event {
            frame: 0,
            kind: EventKind::AllNotesOff,
        };
        Self {
            events: vec![empty; capacity].into_boxed_slice(),
            len: 0,
            blocks,
        }
    }

    /// The script did not run a block: keep its events for the next one.
    pub(crate) fn block(&mut self, events: &[Event]) {
        self.blocks.fetch_add(1, Ordering::Relaxed);
        for event in events {
            self.keep(*event);
        }
    }

    /// Keep one event, or make room for a note-off.
    pub(crate) fn keep(&mut self, event: Event) {
        if self.len < self.events.len() {
            self.events[self.len] = event;
            self.len += 1;
            return;
        }
        if !stops_a_note(&event) {
            return;
        }
        let Some(out) = self.events[..self.len]
            .iter()
            .rposition(|e| !stops_a_note(e))
        else {
            return;
        };
        self.events.copy_within(out + 1..self.len, out);
        self.events[self.len - 1] = event;
    }

    /// The kept events, in order and at frame 0. The store is then empty.
    pub(crate) fn take(&mut self) -> impl Iterator<Item = Event> + '_ {
        let len = std::mem::take(&mut self.len);
        self.events[..len].iter().map(|e| Event { frame: 0, ..*e })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn on(key: u8) -> Event {
        Event {
            frame: 5,
            kind: EventKind::NoteOn {
                key,
                vel: 1.0,
                ch: 0,
                attr: paw_types::Attr::NONE,
            },
        }
    }

    fn off(key: u8) -> Event {
        Event {
            frame: 5,
            kind: EventKind::NoteOff { key, ch: 0 },
        }
    }

    #[test]
    fn a_full_store_keeps_a_note_off_in_place_of_the_newest_other_event() {
        let mut missed = Missed::new(3, Arc::default());
        missed.block(&[on(60), off(61), on(62), off(63), on(64)]);
        let kept: Vec<Event> = missed.take().collect();
        let want: Vec<Event> = [on(60), off(61), off(63)]
            .iter()
            .map(|e| Event { frame: 0, ..*e })
            .collect();
        assert_eq!(kept, want);
        assert_eq!(missed.take().count(), 0, "taken once");
    }
}
