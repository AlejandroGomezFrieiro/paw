//! Note and controller events passed to devices, with sample-accurate
//! offsets inside a block. The events themselves are
//! [`paw_types::EventKind`].

use paw_types::EventKind;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Event {
    /// Offset in frames from the start of the block being processed.
    pub frame: u32,
    pub kind: EventKind,
}

/// Events dropped since the program started: pushed into a full list, or
/// arriving from a MIDI port faster than the engine took them.
static DROPPED: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// How many events have been dropped so far (see [`EventBuf::push`]).
pub fn dropped() -> u64 {
    DROPPED.load(std::sync::atomic::Ordering::Relaxed)
}

/// Count an event dropped elsewhere: one a device could not pass on.
pub fn count_dropped() {
    DROPPED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
}

/// A fixed-capacity event list. Pushing past capacity drops the event, so the
/// audio thread never allocates.
pub struct EventBuf {
    events: Vec<Event>,
}

impl EventBuf {
    pub fn with_capacity(cap: usize) -> Self {
        Self {
            events: Vec::with_capacity(cap),
        }
    }

    pub fn push(&mut self, event: Event) {
        if self.events.len() < self.events.capacity() {
            self.events.push(event);
        } else {
            DROPPED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        }
    }

    /// Put an event first, before those already there: for one on the
    /// block's first frame. Dropped, as `push` drops one, when full.
    pub fn push_front(&mut self, event: Event) {
        if self.events.len() < self.events.capacity() {
            self.events.insert(0, event);
        } else {
            DROPPED.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        }
    }

    pub fn clear(&mut self) {
        self.events.clear();
    }

    pub fn as_slice(&self) -> &[Event] {
        &self.events
    }

    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }
}
