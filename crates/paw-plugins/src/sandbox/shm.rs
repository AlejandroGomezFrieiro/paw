//! The block of shared memory the audio crosses in, and its futex handshake.

#![expect(clippy::allow_attributes_without_reason, reason = "debt: pay down")]
#![expect(clippy::allow_attributes, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_possible_wrap, reason = "debt: pay down")]

use std::cell::UnsafeCell;
use std::os::fd::OwnedFd;
use std::ptr::NonNull;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::time::Duration;

use anyhow::{Context, Result, anyhow};
use paw_engine::{Event, MAX_PAIRS};
use rustix::mm;
use rustix::thread::futex;
use super::*;

// --- the shared block -----------------------------------------------------------

/// The head of the memory both processes map. What the DAW's audio thread
/// writes before it asks for a block is read by the helper's only after it
/// has seen the request, and the other way round for the answer.
///
/// Only atomics, fields written once before the other process maps the
/// memory, and [`UnsafeCell`]s are in it, so a shared `&Header` is sound
/// while the other process writes.
#[repr(C)]
pub(super) struct Header {
    pub(super) magic: u32,
    max_block: u32,
    /// The number of the block asked for, and of the last one finished.
    pub(super) request: AtomicU32,
    pub(super) done: AtomicU32,
    pub(super) quit: AtomicU32,
    pub(super) offline: AtomicU32,
    /// The scheduling of the DAW's audio thread, for the helper's to take.
    pub(super) policy: AtomicU32,
    pub(super) priority: AtomicU32,
    /// One block's context: reached only through a [`Block`].
    context: UnsafeCell<BlockContext>,
    // What the helper's main thread tells the DAW's.
    pub(super) latency: AtomicU32,
    pub(super) editor_open: AtomicU32,
    /// Changes the plugin made by itself: written at `change_head` by the
    /// helper, read up to it by the DAW.
    pub(super) change_head: AtomicU32,
    pub(super) change_tail: AtomicU32,
    /// Why the helper stopped the device and ended, when it knows: written
    /// before it ends, read once it has.
    pub(super) reason_len: AtomicU32,
    reason: UnsafeCell<[u8; REASON]>,
    /// The plugin asked for a block between blocks (`request_process`):
    /// set by the helper's main thread, taken by the DAW's, which wakes the
    /// device and the engine.
    pub(super) wake: AtomicU32,
}

/// One block's context and counts, in the header. The audio thread whose
/// turn it is (see [`Turn`]) is the only one that touches it.
#[repr(C)]
pub(super) struct BlockContext {
    pub(super) frames: u32,
    pub(super) sample_rate: f32,
    pub(super) tempo: f64,
    pub(super) position: f64,
    pub(super) seconds: f64,
    pub(super) bar_start: f64,
    pub(super) bar: i64,
    pub(super) sig_num: u32,
    pub(super) sig_den: u32,
    pub(super) playing: u32,
    pub(super) events_in: u32,
    pub(super) params_in: u32,
    /// Bytes of messages in the block: each its frame, its length and it.
    pub(super) messages_in: u32,
    pub(super) events_out: u32,
    /// Whether the plugin was at rest after the block (see
    /// [`Device::resting`]).
    pub(super) resting: u32,
    /// Whether the block comes with a side-chain.
    pub(super) keyed: u32,
    /// Which further output pairs are asked for, a bit each from the second.
    pub(super) outs: u32,
}

// The layout is a protocol between the DAW and its helpers: these are the
// offsets the header had when the context's fields were in it one by one.
const _: () = {
    assert!(std::mem::offset_of!(Header, context) == 32);
    assert!(std::mem::size_of::<BlockContext>() == 88);
    assert!(std::mem::offset_of!(Header, latency) == 120);
    assert!(std::mem::offset_of!(Header, reason_len) == 136);
    assert!(std::mem::offset_of!(Header, reason) == 140);
    assert!(std::mem::offset_of!(Header, wake) == 1164);
    assert!(std::mem::size_of::<Header>() == 1168);
};

impl Header {
    /// The reason the helper gave for ending, if it gave one.
    pub(super) fn reason(&self) -> Option<String> {
        let len = (self.reason_len.load(Ordering::Acquire) as usize).min(REASON);
        if len == 0 {
            return None;
        }
        // SAFETY: the helper writes the reason only before it publishes its
        // length (Release, read above with Acquire), and never again.
        let reason = unsafe { &*self.reason.get() };
        Some(String::from_utf8_lossy(&reason[..len]).into_owned())
    }

    /// Give the reason the helper ends for. Called once, by the helper's
    /// main thread, as it ends.
    pub(super) fn set_reason(&self, why: &str) {
        let bytes = why.as_bytes();
        let len = bytes.len().min(REASON);
        // SAFETY: only the helper's main thread writes the reason, once, and
        // the DAW reads it only after the length below is published.
        unsafe {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), self.reason.get().cast::<u8>(), len);
        }
        self.reason_len.store(len as u32, Ordering::Release);
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub(super) struct ParamMove {
    pub(super) index: u32,
    pub(super) value: f32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub(super) struct ChangeSlot {
    pub(super) index: u32,
    /// 1 for an edit, 0 for the echo of a state ([`Change::edit`]).
    pub(super) edit: u32,
    pub(super) value: f64,
}

/// The mapping, and where each part of it is.
pub(super) struct Shm {
    base: NonNull<u8>,
    len: usize,
    pub(super) max_block: usize,
    layout: Layout,
    pub(super) fd: OwnedFd,
    /// The [`Turn`] has been handed out.
    turn_taken: AtomicBool,
}

// SAFETY: the mapping is plain memory. Its header is atomics and cells that
// one thread at a time touches (see `Header`); the block's parts are reached
// only through the one `Turn` of each process, and the changes ring has one
// writer (the helper's main thread) and one reader (the DAW's).
unsafe impl Send for Shm {}
// SAFETY: as for `Send`: `&Shm` gives no unsynchronized access by itself.
unsafe impl Sync for Shm {}

/// The right to the block's parts in this process: one per mapping, held by
/// the thread that runs blocks (the DAW's audio thread in the stand-in, the
/// helper's audio thread). Across the processes, the two take turns by the
/// header's `request` and `done`.
pub(super) struct Turn {
    /// The mapping it belongs to, as an address.
    base: usize,
}

/// The parts of the shared memory that carry one block, borrowed from the
/// one [`Turn`]: disjoint, by [`Layout`].
pub(super) struct Block<'a> {
    pub(super) context: &'a mut BlockContext,
    pub(super) left: &'a mut [f32],
    pub(super) right: &'a mut [f32],
    /// The side-chain's two channels.
    pub(super) key: [&'a mut [f32]; 2],
    /// The further output pairs, left and right one after the other.
    outs: &'a mut [f32],
    pub(super) events: &'a mut [Event],
    pub(super) params: &'a mut [ParamMove],
    pub(super) messages: &'a mut [u8],
    max_block: usize,
}

impl Block<'_> {
    /// One channel of a further output pair: `pair` 0 is the second.
    pub(super) fn out(&mut self, pair: usize, channel: usize) -> &mut [f32] {
        let at = (pair * 2 + channel) * self.max_block;
        &mut self.outs[at..at + self.max_block]
    }
}

impl Shm {
    fn layout(max_block: usize) -> Layout {
        let align = |n: usize| n.div_ceil(64) * 64;
        let left = align(std::mem::size_of::<Header>());
        let right = align(left + max_block * 4);
        let key = align(right + max_block * 4);
        let outs = align(key + 2 * max_block * 4);
        let events = align(outs + 2 * (MAX_PAIRS - 1) * max_block * 4);
        let params = align(events + EVENTS * std::mem::size_of::<Event>());
        let changes = align(params + PARAMS * std::mem::size_of::<ParamMove>());
        let messages = align(changes + CHANGES * std::mem::size_of::<ChangeSlot>());
        let len = align(messages + MESSAGES);
        Layout {
            left,
            right,
            key,
            outs,
            events,
            params,
            changes,
            messages,
            len,
        }
    }

    /// A new block of memory, zeroed, for blocks of up to `max_block` frames.
    pub(super) fn create(max_block: usize) -> Result<Self> {
        let len = Self::layout(max_block).len;
        let no_memory = |err| anyhow!("no shared memory: {}", std::io::Error::from(err));
        let fd = rustix::fs::memfd_create(c"paw-plugin", rustix::fs::MemfdFlags::CLOEXEC)
            .map_err(no_memory)?;
        rustix::fs::ftruncate(&fd, len as u64).map_err(no_memory)?;
        let shm = Self::map(fd, max_block)?;
        let header = shm.base.as_ptr().cast::<Header>();
        // SAFETY: the memory is ours alone until the helper is started with
        // its descriptor, and the header is in it, aligned (the mapping is
        // page-aligned).
        unsafe {
            (&raw mut (*header).magic).write(MAGIC);
            (&raw mut (*header).max_block).write(max_block as u32);
        }
        Ok(shm)
    }

    pub(super) fn map(fd: OwnedFd, max_block: usize) -> Result<Self> {
        let layout = Self::layout(max_block);
        let len = layout.len;
        // SAFETY: a new shared mapping of a descriptor we own; the result is
        // checked, and it is unmapped only in `drop`.
        let base = unsafe {
            mm::mmap(
                std::ptr::null_mut(),
                len,
                mm::ProtFlags::READ | mm::ProtFlags::WRITE,
                mm::MapFlags::SHARED,
                &fd,
                0,
            )
        }
        .map_err(|err| anyhow!("mapping shared memory: {}", std::io::Error::from(err)))?;
        Ok(Self {
            base: NonNull::new(base.cast()).context("mapping shared memory: null")?,
            len,
            max_block,
            layout,
            fd,
            turn_taken: AtomicBool::new(false),
        })
    }

    pub(super) fn header(&self) -> &Header {
        // SAFETY: the mapping starts with a `Header` (zeroed, then given its
        // magic), lives as long as `self`, and the header can be shared (see
        // `Header`).
        unsafe { self.base.cast::<Header>().as_ref() }
    }

    /// The right to the block's parts. There is one: a second call panics.
    pub(super) fn turn(&self) -> Turn {
        assert!(
            !self.turn_taken.swap(true, Ordering::Relaxed),
            "one turn per mapping"
        );
        Turn {
            base: self.base.as_ptr() as usize,
        }
    }

    /// `count` items of `T` at `offset`, borrowed for as long as `self`.
    ///
    /// # Safety
    ///
    /// The range is inside the mapping, aligned for `T`, does not overlap
    /// another part borrowed at the same time, and is not touched by the
    /// other process while it is borrowed.
    #[allow(clippy::mut_from_ref)]
    unsafe fn part<T>(&self, offset: usize, count: usize) -> &mut [T] {
        debug_assert!(offset + count * std::mem::size_of::<T>() <= self.len);
        // SAFETY: as the caller promises.
        unsafe { std::slice::from_raw_parts_mut(self.base.as_ptr().add(offset).cast(), count) }
    }

    /// The parts that carry a block. The process that holds `turn` has the
    /// block between asking for it and having its answer (the DAW), or
    /// between seeing the request and answering it (the helper).
    pub(super) fn block<'a>(&'a self, turn: &'a mut Turn) -> Block<'a> {
        assert_eq!(
            turn.base,
            self.base.as_ptr() as usize,
            "a turn of this mapping"
        );
        let (n, at) = (self.max_block, &self.layout);
        // SAFETY: the one turn is borrowed mutably for as long as the block,
        // so no other `Block` of this mapping exists in this process. The
        // parts are disjoint by `Layout`, in the mapping and aligned (each
        // starts on 64 bytes); the context is in the header, apart from the
        // atomics. The other process touches them only in its own turn.
        unsafe {
            let (key_l, key_r) = self.part(at.key, 2 * n).split_at_mut(n);
            Block {
                context: &mut *self.header().context.get(),
                left: self.part(at.left, n),
                right: self.part(at.right, n),
                key: [key_l, key_r],
                outs: self.part(at.outs, 2 * (MAX_PAIRS - 1) * n),
                events: self.part(at.events, EVENTS),
                params: self.part(at.params, PARAMS),
                messages: self.part(at.messages, MESSAGES),
                max_block: n,
            }
        }
    }

    /// Where `slot` of the changes ring is.
    fn change_at(&self, slot: u32) -> *mut ChangeSlot {
        let at = self.layout.changes + (slot as usize % CHANGES) * size_of::<ChangeSlot>();
        // SAFETY: the ring has CHANGES slots from `layout.changes`, in the
        // mapping.
        unsafe { self.base.as_ptr().add(at).cast() }
    }

    /// The change at `slot` of the ring, as the helper put it.
    pub(super) fn change(&self, slot: u32) -> ChangeSlot {
        // SAFETY: in the mapping and aligned; read by value, with no
        // reference made. The DAW reads only slots below `change_head`
        // (Acquire), which the helper wrote before it published them.
        unsafe { self.change_at(slot).read() }
    }

    /// Put a change at `slot` of the ring. Only the helper's main thread
    /// does, before it publishes the slot with `change_head`.
    pub(super) fn put_change(&self, slot: u32, change: ChangeSlot) {
        // SAFETY: in the mapping and aligned; written by value, with no
        // reference made, by the ring's one writer.
        unsafe { self.change_at(slot).write(change) }
    }
}

/// Where each part of the shared memory starts, and its whole length.
struct Layout {
    left: usize,
    right: usize,
    key: usize,
    outs: usize,
    events: usize,
    params: usize,
    changes: usize,
    messages: usize,
    len: usize,
}

impl Drop for Shm {
    fn drop(&mut self) {
        // SAFETY: mapped in `map` with this length, and no borrow of it
        // outlives `self`.
        let _ = unsafe { mm::munmap(self.base.as_ptr().cast(), self.len) };
    }
}

// The futex word is in memory that two processes share, so the calls are
// not FUTEX_PRIVATE. Each is one syscall, with no allocation or lock: the
// audio thread wakes the helper with it.

/// Wake every thread that waits on `word`.
pub(super) fn futex_wake(word: &AtomicU32) {
    // The kernel reads the count as an int: i32::MAX is "all".
    let _ = futex::wake(word, futex::Flags::empty(), i32::MAX as u32);
}

/// Sleep until `word` is no longer `seen`, or `limit` has passed.
pub(super) fn futex_wait(word: &AtomicU32, seen: u32, limit: Duration) {
    let time = futex::Timespec {
        tv_sec: limit.as_secs() as i64,
        tv_nsec: limit.subsec_nanos().into(),
    };
    // Woken, timed out, or the word had already changed: the caller looks
    // at the word again in each case.
    let _ = futex::wait(word, futex::Flags::empty(), seen, Some(&time));
}

