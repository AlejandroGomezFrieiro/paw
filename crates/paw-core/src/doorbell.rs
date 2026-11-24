//! The doorbell of the kernel's loop: how the threads and the processes
//! that work for the main thread wake it when they have news.
//!
//! The loop sleeps in one wait (`mio::Poll`) until a bell rings, a
//! descriptor that it watches is ready (the `inotify` descriptor of the
//! watched files), or the time of its next due work comes. A worker sets
//! the bit of its kind in an atomic set of bits and rings the waker once
//! ([`paw_engine::Bell`]); the audio thread only sets the bit. Each turn
//! takes the bits, and the parts of the session look for their news.
//!
//! A message on the kernel's channel (a key, a request, MIDI, the output
//! of a helper) rings too: [`KernelSender`](crate::kernel::KernelSender)
//! sends and then rings [`Woken::MESSAGES`].
//!
//! In a BrowserPod pod there is no waker (WASI): the loop looks at the bits
//! every few milliseconds while it waits.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]

use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::Duration;

use paw_engine::Bell;

bitflags::bitflags! {
    /// The kinds of news that wake the loop: one bit for each.
    #[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
    pub(crate) struct Woken: u32 {
        /// A message came on the kernel's channel.
        const MESSAGES = 1;
        /// A bake ended, or a tidy of the bakes' cache.
        const BAKES = 1 << 1;
        /// The hash worker learned a file.
        const HASHES = 1 << 2;
        /// A plugin made apart from the loop is made, or could not be.
        const LOADS = 1 << 3;
        /// A render asks for a state, or ended.
        const RENDER = 1 << 4;
        /// The watched folders changed (the `inotify` descriptor).
        const FILES = 1 << 5;
        /// The audio device or the MIDI ports (looked at on a period).
        const DEVICES = 1 << 6;
        /// The engine let go of a take, or a writer of a take ended.
        const TAKES = 1 << 7;
        /// A plugin asked for a call on the main thread (a mark).
        const PLUGINS = 1 << 8;
        /// A sound file to hear on its own is read.
        const PREVIEW = 1 << 9;
        /// A measurement of the mix ended.
        const MEASURES = 1 << 10;
    }
}

impl Woken {
    /// The kinds whose workers ring when their work ends. A result of one
    /// of them that a turn finds with no ring is a missed wake. The others
    /// are marks (the audio thread, a plugin) or due times: the loop looks
    /// for them on a tick.
    pub(crate) const RINGING: Self = Self::BAKES
        .union(Self::HASHES)
        .union(Self::LOADS)
        .union(Self::RENDER)
        .union(Self::FILES)
        .union(Self::PREVIEW);
}

/// What a bell does to wake the loop.
type Ringer = paw_engine::bell::Ringer;

/// The bits and the waker of the loop, to give bells to the workers. Cheap
/// to clone. The default rings nothing: a session with no loop (a test of
/// the session, an offline render) has its bits, and nothing wakes.
#[derive(Clone, Default)]
pub(crate) struct Doorbell {
    bits: Arc<AtomicU32>,
    ringer: Option<Ringer>,
    /// Where a descriptor is watched: the poll of the loop.
    #[cfg(not(target_vendor = "browserpod"))]
    registry: Option<Arc<mio::Registry>>,
}

impl Doorbell {
    /// The bell of one kind of news, for a worker.
    pub(crate) fn bell(&self, kind: Woken) -> Bell {
        match &self.ringer {
            Some(ringer) => Bell::new(self.bits.clone(), kind.bits(), ringer.clone()),
            None => Bell::new(self.bits.clone(), kind.bits(), Arc::new(|| {})),
        }
    }

    /// The bits set since the last take, now cleared: the start of a turn.
    pub(crate) fn take(&self) -> Woken {
        Woken::from_bits_retain(paw_engine::bell::bits_of(self.bits.swap(0, Ordering::AcqRel)))
    }

    /// The bits set since the last take, left as they are.
    pub(crate) fn peek(&self) -> Woken {
        Woken::from_bits_retain(paw_engine::bell::bits_of(self.bits.load(Ordering::Acquire)))
    }

    /// Wake the loop when `fd` can be read, with the bit of `kind`. The
    /// watch ends when the descriptor is closed. Nothing for a doorbell
    /// with no loop, or in a pod: there the loop looks at the next turn.
    pub(crate) fn watch(&self, fd: std::os::fd::RawFd, kind: Woken) -> std::io::Result<()> {
        #[cfg(not(target_vendor = "browserpod"))]
        if let Some(registry) = &self.registry {
            let token = mio::Token(kind.bits() as usize);
            return registry.register(&mut mio::unix::SourceFd(&fd), token, mio::Interest::READABLE);
        }
        let _ = (fd, kind);
        Ok(())
    }
}

/// The token of the waker in the poll. A watched descriptor has the bit
/// of its kind as its token, which is never 0.
#[cfg(not(target_vendor = "browserpod"))]
const WAKER: mio::Token = mio::Token(0);

/// The one wait of the loop, and the doorbell that ends it.
pub(crate) struct Waiter {
    doorbell: Doorbell,
    #[cfg(not(target_vendor = "browserpod"))]
    poll: std::cell::RefCell<(mio::Poll, mio::Events)>,
}

#[cfg(not(target_vendor = "browserpod"))]
impl Waiter {
    pub(crate) fn new() -> std::io::Result<Self> {
        let poll = mio::Poll::new()?;
        let waker = Arc::new(mio::Waker::new(poll.registry(), WAKER)?);
        let registry = Arc::new(poll.registry().try_clone()?);
        let ringer: Ringer = Arc::new(move || {
            // A waker that cannot be written has a full counter: the loop
            // wakes anyway.
            let _ = waker.wake();
        });
        let doorbell = Doorbell { bits: Arc::default(), ringer: Some(ringer), registry: Some(registry) };
        Ok(Self { doorbell, poll: std::cell::RefCell::new((poll, mio::Events::with_capacity(16))) })
    }

    /// Sleep until a bell rings or a watched descriptor is ready, at most
    /// `timeout` (None: no limit). A bit that is set already ends it at
    /// once: a mark of the audio thread rings nothing. Gives whether
    /// something woke it; on its own time it gives false.
    pub(crate) fn wait(&self, timeout: Option<Duration>) -> std::io::Result<bool> {
        if !self.doorbell.peek().is_empty() {
            return Ok(true);
        }
        let mut guard = self.poll.borrow_mut();
        let (poll, events) = &mut *guard;
        match poll.poll(events, timeout) {
            Ok(()) => {}
            // A signal: the loop looks again, as after a ring.
            Err(err) if err.kind() == std::io::ErrorKind::Interrupted => return Ok(true),
            Err(err) => return Err(err),
        }
        for event in events.iter() {
            if event.token() != WAKER {
                // A descriptor: its token is the bit of its kind.
                let kind = Woken::from_bits_retain(event.token().0 as u32);
                self.doorbell.bits.fetch_or(kind.bits(), Ordering::AcqRel);
            }
        }
        Ok(!self.doorbell.peek().is_empty())
    }
}

#[cfg(target_vendor = "browserpod")]
impl Waiter {
    pub(crate) fn new() -> std::io::Result<Self> {
        Ok(Self { doorbell: Doorbell::default() })
    }

    /// Sleep until a bit is set, at most `timeout`. In a pod a wait with a
    /// timeout does not end at its time, only when a message comes; a short
    /// sleep does end, so the loop looks at the bits after each one.
    #[expect(clippy::disallowed_methods, reason = "a wait on the wall clock in a pod, where a timeout does not end")]
    pub(crate) fn wait(&self, timeout: Option<Duration>) -> std::io::Result<bool> {
        const STEP: Duration = Duration::from_millis(5);
        let end = timeout.map(|timeout| std::time::Instant::now() + timeout);
        loop {
            if !self.doorbell.peek().is_empty() {
                return Ok(true);
            }
            let left = end.map(|end| end.saturating_duration_since(std::time::Instant::now()));
            if left.is_some_and(|left| left.is_zero()) {
                return Ok(false);
            }
            std::thread::sleep(left.map_or(STEP, |left| left.min(STEP)));
        }
    }
}

impl Waiter {
    /// The doorbell, for the workers and the senders of messages.
    pub(crate) fn doorbell(&self) -> &Doorbell {
        &self.doorbell
    }
}

#[cfg(all(test, not(target_vendor = "browserpod")))]
mod tests {
    use super::*;

    #[test]
    fn a_ring_from_a_thread_ends_the_wait_with_its_bit_and_a_mark_ends_the_next_wait() {
        let waiter = Waiter::new().unwrap();
        let bell = waiter.doorbell().bell(Woken::BAKES);
        std::thread::spawn(move || bell.ring()).join().unwrap();
        assert!(waiter.wait(None).unwrap(), "the ring woke the wait");
        assert_eq!(waiter.doorbell().take(), Woken::BAKES);
        waiter.doorbell().bell(Woken::PLUGINS).mark();
        assert!(waiter.wait(None).unwrap(), "a mark that is set ends the wait at once");
        assert_eq!(waiter.doorbell().take(), Woken::PLUGINS);
    }

    #[test]
    fn a_watched_descriptor_that_can_be_read_wakes_the_wait_with_its_kind() {
        let waiter = Waiter::new().unwrap();
        let (ours, theirs) = std::os::unix::net::UnixStream::pair().unwrap();
        use std::os::fd::AsRawFd;
        waiter.doorbell().watch(ours.as_raw_fd(), Woken::FILES).unwrap();
        std::io::Write::write_all(&mut &theirs, b"x").unwrap();
        assert!(waiter.wait(None).unwrap());
        assert_eq!(waiter.doorbell().take(), Woken::FILES);
    }
}
