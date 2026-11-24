//! A bell for a worker: how a thread or a process tells the main loop of
//! the program that its work ended, so that the loop wakes and takes the
//! result in its next turn and does not look for it on a timer.
//!
//! A bell sets one bit in a set of bits that the main loop owns, and rings
//! the loop once. A worker thread [`ring`](Bell::ring)s. The audio thread
//! makes no system call, so it only [`mark`](Bell::mark)s: the loop sees the
//! bit at its next turn. The engine knows nothing of the loop: the program
//! gives each worker its bell.

use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};

/// What a bell does to wake the loop: a system call, as a write to an
/// `eventfd`.
pub type Ringer = Arc<dyn Fn() + Send + Sync>;

/// How far up a mark sets its bit: the low 16 bits are rings, the high 16
/// bits are marks. A ring looks only at the rings, so a mark that came
/// first does not keep a ring from waking the loop. The loop takes both
/// ([`bits_of`]).
pub const MARKS: u32 = 16;

/// The kinds of news in the bits of the loop: rings and marks as one.
pub fn bits_of(raw: u32) -> u32 {
    (raw | raw >> MARKS) & ((1 << MARKS) - 1)
}

/// One kind of news for the main loop. Cheap to clone; `Send + Sync`.
#[derive(Clone, Default)]
pub struct Bell {
    /// The bits of the loop, or none for a bell that rings nothing.
    bits: Option<Arc<AtomicU32>>,
    /// The bit of this kind of news.
    bit: u32,
    ringer: Option<Ringer>,
}

impl std::fmt::Debug for Bell {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Bell").field("bit", &self.bit).finish_non_exhaustive()
    }
}

impl Bell {
    /// A bell that sets `bit` in `bits` and wakes the loop with `ringer`.
    pub fn new(bits: Arc<AtomicU32>, bit: u32, ringer: Ringer) -> Self {
        Self { bits: Some(bits), bit, ringer: Some(ringer) }
    }

    /// A bell that rings nothing: for a worker with no loop to tell (an
    /// offline render, a test of the worker alone).
    pub fn none() -> Self {
        Self::default()
    }

    /// Set the bit, and wake the loop if the bit was not set yet: a bit
    /// that is set already has woken the loop, and the loop has not taken
    /// it. From a worker thread, never from the audio thread.
    pub fn ring(&self) {
        let Some(bits) = &self.bits else { return };
        let before = bits.fetch_or(self.bit, Ordering::AcqRel);
        if before & self.bit == 0
            && let Some(ringer) = &self.ringer
        {
            ringer();
        }
    }

    /// Set the bit and wake nothing: one atomic operation, for the audio
    /// thread. The loop sees the bit at its next turn. A ring after it
    /// still wakes the loop.
    pub fn mark(&self) {
        if let Some(bits) = &self.bits {
            bits.fetch_or(self.bit << MARKS, Ordering::Release);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;

    #[test]
    fn a_bell_rings_once_until_the_loop_takes_its_bit_and_a_mark_rings_never() {
        let bits = Arc::new(AtomicU32::new(0));
        let rings = Arc::new(AtomicUsize::new(0));
        let counted = rings.clone();
        let ringer: Ringer = Arc::new(move || {
            counted.fetch_add(1, Ordering::Relaxed);
        });
        let bell = Bell::new(bits.clone(), 0b10, ringer.clone());
        bell.ring();
        bell.ring();
        assert_eq!((bits.load(Ordering::Relaxed), rings.load(Ordering::Relaxed)), (0b10, 1), "the second ring adds nothing");
        bits.store(0, Ordering::Relaxed);
        bell.ring();
        assert_eq!(rings.load(Ordering::Relaxed), 2, "a ring after the loop took the bit");
        bits.store(0, Ordering::Relaxed);
        let marks = Bell::new(bits.clone(), 0b100, ringer);
        marks.mark();
        assert_eq!(bits_of(bits.load(Ordering::Relaxed)), 0b100, "a mark sets its bit");
        assert_eq!(rings.load(Ordering::Relaxed), 2, "and wakes nothing");
        marks.ring();
        assert_eq!(rings.load(Ordering::Relaxed), 3, "a ring after a mark wakes the loop");
        Bell::none().ring();
    }
}
