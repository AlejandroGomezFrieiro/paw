//! Plugins in processes of their own.
//!
//! A plugin is other people's code. Loaded into this process, one that
//! crashes takes the session with it, and one that hangs freezes it. So each
//! plugin instance runs in a helper process (this same program, started as
//! `plugin-host`), and the session holds a stand-in for it:
//!
//! ```text
//!  the DAW                                   plugin-host (one per instance)
//!   audio thread ── shared memory, futex ──▶ audio thread: the plugin's process()
//!   main thread  ── socket ────────────────▶ main thread: parameters, state, editor
//! ```
//!
//! Audio crosses in a block of shared memory. The DAW's audio thread writes
//! a block's input there, wakes the helper and waits for the answer, but
//! never longer than about a block lasts: a plugin that is late costs its
//! own track a block of sound, not everyone a dropout, and one that has died
//! costs nothing more. An instrument that is late or gone is silent; an
//! effect is passed through.
//!
//! Everything else crosses a socket, each request with a time limit, so a
//! plugin that hangs while it is created, or saving its state, is reported
//! and ended instead of freezing the program.
//!
//! The helper finds the plugin the way the DAW does (`register`, from the
//! same cache), creates it, and opens its editor in a window of its own, so
//! plugin windows work exactly as they do in-process.

use std::borrow::Cow;
use std::cell::UnsafeCell;
use std::io::{Read, Write};
use std::os::fd::{AsRawFd, BorrowedFd, FromRawFd, OwnedFd, RawFd};
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::ptr::NonNull;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow, bail};
use paw_engine::device::{
    Category, Change, Controller, Device, DeviceFactory, DeviceInfo, Instance, Io, ParamInfo, Ports,
    Rest, Starting,
};
use paw_engine::{Event, MAX_PAIRS, ProcessCtx, Registry};
use rustix::mm;
use rustix::process::Signal;
use rustix::thread::futex;
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;

/// How the helper is started: this program and its first arguments.
static HOST: OnceLock<Vec<String>> = OnceLock::new();
/// The plugin cache the helper reads, the DAW's own.
static CACHE: Mutex<Option<PathBuf>> = Mutex::new(None);

/// Events a block may carry each way.
const EVENTS: usize = 1024;
/// Parameter moves a block may carry to the plugin.
const PARAMS: usize = 256;
/// Parameter changes the plugin reports that may wait to be read.
const CHANGES: usize = 1024;
const MAGIC: u32 = 0x4441_5750;
/// The longest reason a helper can give for stopping.
const REASON: usize = 1024;
/// Bytes of state lanes' messages a block may carry to the plugin.
const MESSAGES: usize = 16384;
/// The call that asks the helper's controller to prepare a message
/// ([`Controller::prepare`]): its data is the method, a zero byte, the
/// request's own data.
const PREPARE: &str = "sandbox.prepare";

/// How long a plugin may take over each kind of request before it is
/// taken to have hung.
const CREATE_LIMIT: Duration = Duration::from_secs(45);
const STATE_LIMIT: Duration = Duration::from_secs(30);
const QUICK_LIMIT: Duration = Duration::from_secs(10);
/// A plugin that answers no block for this long while it is asked for them
/// is taken to have hung: it is ended and reported, and can be restarted.
const STALL_LIMIT: Duration = Duration::from_secs(2);
/// The longest a render waits for one block. A plugin that takes longer is
/// treated as stopped for the rest of the render, which goes on without it.
const OFFLINE_LIMIT: Duration = Duration::from_secs(20);

/// For tests: helpers stop answering blocks (they sleep instead). Set from
/// `sandbox.hang`; helpers started while it is set start that way.
static TEST_HANG: AtomicBool = AtomicBool::new(false);

/// Say how to start the helper: the program and the arguments that put it
/// in `plugin-host` mode. Until this is called plugins are hosted in-process,
/// which is what tests of the hosting code itself want.
pub fn set_host_command(argv: Vec<String>, cache: Option<&Path>) {
    let _ = HOST.set(argv);
    *CACHE.lock().unwrap() = cache.map(Path::to_path_buf);
}

/// Whether plugins get processes of their own: the helper is known, and
/// `PAW_PLUGIN_SANDBOX=0` has not turned it off.
pub fn enabled() -> bool {
    HOST.get().is_some() && std::env::var("PAW_PLUGIN_SANDBOX").as_deref() != Ok("0")
}

pub(crate) fn host_command() -> Option<&'static Vec<String>> {
    if enabled() { HOST.get() } else { None }
}

/// Replace every plugin's factory with one that makes it in a helper.
/// Built-in devices are this program's own code and stay where they are.
pub fn wrap(registry: &mut Registry) {
    if !enabled() {
        return;
    }
    let plugins: Vec<DeviceInfo> = registry
        .iter()
        .map(|factory| factory.info().clone())
        .filter(|info| info.format.is_plugin())
        .collect();
    for info in plugins {
        registry.register(Rc::new(RemoteFactory {
            info,
            argv: None,
            env: Vec::new(),
        }));
    }
}

/// A factory that makes each device in a helper started with `argv` (this
/// program and the arguments that put it in `plugin-host` mode), whether or
/// not plugins get helpers: for devices that must never run in this
/// process. `env` is added to the helper's environment.
pub fn remote(
    info: DeviceInfo,
    argv: Vec<String>,
    env: Vec<(String, String)>,
) -> Rc<dyn DeviceFactory> {
    Rc::new(RemoteFactory {
        info,
        argv: Some(argv),
        env,
    })
}

// --- the shared block -----------------------------------------------------------

/// The head of the memory both processes map. What the DAW's audio thread
/// writes before it asks for a block is read by the helper's only after it
/// has seen the request, and the other way round for the answer.
///
/// Only atomics, fields written once before the other process maps the
/// memory, and [`UnsafeCell`]s are in it, so a shared `&Header` is sound
/// while the other process writes.
#[repr(C)]
struct Header {
    magic: u32,
    max_block: u32,
    /// The number of the block asked for, and of the last one finished.
    request: AtomicU32,
    done: AtomicU32,
    quit: AtomicU32,
    offline: AtomicU32,
    /// The scheduling of the DAW's audio thread, for the helper's to take.
    policy: AtomicU32,
    priority: AtomicU32,
    /// One block's context: reached only through a [`Block`].
    context: UnsafeCell<BlockContext>,
    // What the helper's main thread tells the DAW's.
    latency: AtomicU32,
    editor_open: AtomicU32,
    /// Changes the plugin made by itself: written at `change_head` by the
    /// helper, read up to it by the DAW.
    change_head: AtomicU32,
    change_tail: AtomicU32,
    /// Why the helper stopped the device and ended, when it knows: written
    /// before it ends, read once it has.
    reason_len: AtomicU32,
    reason: UnsafeCell<[u8; REASON]>,
}

/// One block's context and counts, in the header. The audio thread whose
/// turn it is (see [`Turn`]) is the only one that touches it.
#[repr(C)]
struct BlockContext {
    frames: u32,
    sample_rate: f32,
    tempo: f64,
    position: f64,
    seconds: f64,
    bar_start: f64,
    bar: i64,
    sig_num: u32,
    sig_den: u32,
    playing: u32,
    events_in: u32,
    params_in: u32,
    /// Bytes of messages in the block: each its frame, its length and it.
    messages_in: u32,
    events_out: u32,
    /// Whether the plugin was at rest after the block (see
    /// [`Device::resting`]).
    resting: u32,
    /// Whether the block comes with a side-chain.
    keyed: u32,
    /// Which further output pairs are asked for, a bit each from the second.
    outs: u32,
}

// The layout is a protocol between the DAW and its helpers: these are the
// offsets the header had when the context's fields were in it one by one.
const _: () = {
    assert!(std::mem::offset_of!(Header, context) == 32);
    assert!(std::mem::size_of::<BlockContext>() == 88);
    assert!(std::mem::offset_of!(Header, latency) == 120);
    assert!(std::mem::offset_of!(Header, reason_len) == 136);
    assert!(std::mem::offset_of!(Header, reason) == 140);
    assert!(std::mem::size_of::<Header>() == 1168);
};

impl Header {
    /// The reason the helper gave for ending, if it gave one.
    fn reason(&self) -> Option<String> {
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
    fn set_reason(&self, why: &str) {
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
struct ParamMove {
    index: u32,
    value: f32,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct ChangeSlot {
    index: u32,
    /// 1 for an edit, 0 for the echo of a state ([`Change::edit`]).
    edit: u32,
    value: f64,
}

/// The mapping, and where each part of it is.
struct Shm {
    base: NonNull<u8>,
    len: usize,
    max_block: usize,
    layout: Layout,
    fd: OwnedFd,
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
struct Turn {
    /// The mapping it belongs to, as an address.
    base: usize,
}

/// The parts of the shared memory that carry one block, borrowed from the
/// one [`Turn`]: disjoint, by [`Layout`].
struct Block<'a> {
    context: &'a mut BlockContext,
    left: &'a mut [f32],
    right: &'a mut [f32],
    /// The side-chain's two channels.
    key: [&'a mut [f32]; 2],
    /// The further output pairs, left and right one after the other.
    outs: &'a mut [f32],
    events: &'a mut [Event],
    params: &'a mut [ParamMove],
    messages: &'a mut [u8],
    max_block: usize,
}

impl Block<'_> {
    /// One channel of a further output pair: `pair` 0 is the second.
    fn out(&mut self, pair: usize, channel: usize) -> &mut [f32] {
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
    fn create(max_block: usize) -> Result<Self> {
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

    fn map(fd: OwnedFd, max_block: usize) -> Result<Self> {
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

    fn header(&self) -> &Header {
        // SAFETY: the mapping starts with a `Header` (zeroed, then given its
        // magic), lives as long as `self`, and the header can be shared (see
        // `Header`).
        unsafe { self.base.cast::<Header>().as_ref() }
    }

    /// The right to the block's parts. There is one: a second call panics.
    fn turn(&self) -> Turn {
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
    fn block<'a>(&'a self, turn: &'a mut Turn) -> Block<'a> {
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
    fn change(&self, slot: u32) -> ChangeSlot {
        // SAFETY: in the mapping and aligned; read by value, with no
        // reference made. The DAW reads only slots below `change_head`
        // (Acquire), which the helper wrote before it published them.
        unsafe { self.change_at(slot).read() }
    }

    /// Put a change at `slot` of the ring. Only the helper's main thread
    /// does, before it publishes the slot with `change_head`.
    fn put_change(&self, slot: u32, change: ChangeSlot) {
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
fn futex_wake(word: &AtomicU32) {
    // The kernel reads the count as an int: i32::MAX is "all".
    let _ = futex::wake(word, futex::Flags::empty(), i32::MAX as u32);
}

/// Sleep until `word` is no longer `seen`, or `limit` has passed.
fn futex_wait(word: &AtomicU32, seen: u32, limit: Duration) {
    let time = futex::Timespec {
        tv_sec: limit.as_secs() as i64,
        tv_nsec: limit.subsec_nanos().into(),
    };
    // Woken, timed out, or the word had already changed: the caller looks
    // at the word again in each case.
    let _ = futex::wait(word, futex::Flags::empty(), seen, Some(&time));
}

// --- the DAW's side: the audio thread -------------------------------------------

/// What the stand-in's two halves share.
struct Link {
    shm: Shm,
    /// The helper has ended, or was ended for not answering.
    dead: AtomicBool,
    /// Blocks the helper did not answer in time.
    late: AtomicU32,
    /// Blocks it did answer.
    answered: AtomicU32,
    /// The plugin was given a state or a call: it is run in the next block
    /// even when it said it was at rest, as some plugins take a state on
    /// only in their next block.
    wake: AtomicBool,
}

/// The device the engine runs: it hands each block to the helper.
struct RemoteDevice {
    link: Arc<Link>,
    instrument: bool,
    /// The number of the last block asked for.
    seq: u32,
    /// That block has not been answered yet.
    outstanding: bool,
    /// The right to the shared block's parts, in this process.
    turn: Turn,
    /// Parameter moves for the next block.
    moves: Vec<ParamMove>,
    /// Messages for the next block, as the shared memory carries them.
    messages: Vec<u8>,
    told_priority: bool,
    /// The plugin said it was at rest after the last block.
    rest: Rest,
    /// The longest a render waits for one block: a device that is never
    /// in this process (a script) is ended as soon as live, a plugin is
    /// given [`OFFLINE_LIMIT`].
    offline_limit: Duration,
}

impl RemoteDevice {
    /// What is heard when the helper has no answer: nothing from an
    /// instrument, the input untouched from an effect.
    fn without(&self, io: &mut Io) {
        if self.instrument {
            io.left.fill(0.0);
            io.right.fill(0.0);
        }
    }
}

impl Device for RemoteDevice {
    /// As the plugin said after its last block, unless a parameter has
    /// moved since.
    fn resting(&self) -> bool {
        self.rest.resting() && self.moves.is_empty() && !self.link.wake.load(Ordering::Relaxed)
    }

    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        let link = &*self.link;
        self.rest.begin(io, link.wake.swap(false, Ordering::Relaxed));
        let shm = &link.shm;
        let header = shm.header();
        // A helper that has said why it stopped is ending, or has ended.
        if link.dead.load(Ordering::Relaxed) || header.reason_len.load(Ordering::Acquire) > 0 {
            return self.without(io);
        }
        if self.outstanding {
            // The helper is still on an earlier block: it is not given
            // another until it has caught up.
            if header.done.load(Ordering::Acquire) != self.seq {
                link.late.fetch_add(1, Ordering::Relaxed);
                return self.without(io);
            }
            self.outstanding = false;
            link.answered.fetch_add(1, Ordering::Relaxed);
        }
        let frames = io.left.len().min(shm.max_block);
        if !self.told_priority {
            self.told_priority = true;
            let mut policy = 0;
            // libc, as rustix has no wrapper for the pthread scheduling
            // calls (they act on a pthread, not a kernel thread id).
            let mut param: libc::sched_param = unsafe { std::mem::zeroed() };
            unsafe {
                libc::pthread_getschedparam(libc::pthread_self(), &mut policy, &mut param);
            }
            header
                .priority
                .store(param.sched_priority as u32, Ordering::Relaxed);
            header.policy.store(policy as u32, Ordering::Relaxed);
        }
        let events = io.events.as_slice();
        let count = events.len().min(EVENTS);
        {
            let block = shm.block(&mut self.turn);
            let head = &mut *block.context;
            head.frames = frames as u32;
            head.sample_rate = ctx.sample_rate;
            head.tempo = ctx.tempo;
            head.position = ctx.position;
            head.seconds = ctx.seconds;
            head.bar_start = ctx.bar_start;
            head.bar = ctx.bar;
            head.sig_num = ctx.sig_num;
            head.sig_den = ctx.sig_den;
            head.playing = ctx.playing as u32;
            head.events_in = count as u32;
            head.params_in = self.moves.len() as u32;
            head.messages_in = self.messages.len() as u32;
            head.keyed = io.sidechain.is_some() as u32;
            head.outs = io
                .outputs
                .iter()
                .take(MAX_PAIRS - 1)
                .enumerate()
                .filter(|(_, out)| out.is_some())
                .fold(0, |bits, (pair, _)| bits | 1 << pair);
            block.left[..frames].copy_from_slice(&io.left[..frames]);
            block.right[..frames].copy_from_slice(&io.right[..frames]);
            if let Some([l, r]) = io.sidechain {
                let [key_l, key_r] = block.key;
                key_l[..frames].copy_from_slice(&l[..frames]);
                key_r[..frames].copy_from_slice(&r[..frames]);
            }
            block.events[..count].copy_from_slice(&events[..count]);
            block.params[..self.moves.len()].copy_from_slice(&self.moves);
            self.moves.clear();
            block.messages[..self.messages.len()].copy_from_slice(&self.messages);
            self.messages.clear();
        }

        self.seq = self.seq.wrapping_add(1);
        header.request.store(self.seq, Ordering::Release);
        futex_wake(&header.request);

        // A render waits for as long as the plugin takes; live, a block
        // that is not there in time is given up on.
        let offline = header.offline.load(Ordering::Relaxed) != 0;
        let block = Duration::from_secs_f64(frames as f64 / ctx.sample_rate.max(1.0) as f64);
        let limit = if offline {
            // Tests that make plugins hang do not wait the whole limit.
            if TEST_HANG.load(Ordering::Relaxed) {
                Duration::from_secs(1)
            } else {
                self.offline_limit
            }
        } else {
            block + block / 2 + Duration::from_millis(2)
        };
        let started = Instant::now();
        let mut spins = 0u32;
        loop {
            if header.done.load(Ordering::Acquire) == self.seq {
                break;
            }
            let waited = started.elapsed();
            let stopped = header.reason_len.load(Ordering::Acquire) > 0;
            if waited >= limit || link.dead.load(Ordering::Relaxed) || stopped {
                self.outstanding = true;
                link.late.fetch_add(1, Ordering::Relaxed);
                if offline {
                    // A render does not wait that long twice.
                    link.dead.store(true, Ordering::Relaxed);
                }
                return self.without(io);
            }
            // Most blocks are back within a few dozen microseconds: look
            // again at once for a moment before going to sleep.
            if spins < 2000 {
                spins += 1;
                std::hint::spin_loop();
            } else {
                let seen = header.done.load(Ordering::Acquire);
                if seen != self.seq {
                    futex_wait(
                        &header.done,
                        seen,
                        (limit - waited).min(Duration::from_millis(50)),
                    );
                }
            }
        }
        link.answered.fetch_add(1, Ordering::Relaxed);
        let mut block = shm.block(&mut self.turn);
        io.left[..frames].copy_from_slice(&block.left[..frames]);
        io.right[..frames].copy_from_slice(&block.right[..frames]);
        for (pair, out) in io.outputs.iter_mut().take(MAX_PAIRS - 1).enumerate() {
            if let Some([l, r]) = out {
                l[..frames].copy_from_slice(&block.out(pair, 0)[..frames]);
                r[..frames].copy_from_slice(&block.out(pair, 1)[..frames]);
            }
        }
        self.rest.end(block.context.resting != 0);
        let out = (block.context.events_out as usize).min(EVENTS);
        io.events.clear();
        for event in &block.events[..out] {
            io.events.push(*event);
        }
    }

    fn message(&mut self, frame: u32, data: &[u8]) -> bool {
        if self.messages.len() + 8 + data.len() > MESSAGES.min(self.messages.capacity()) {
            return false;
        }
        self.messages.extend_from_slice(&frame.to_le_bytes());
        self.messages.extend_from_slice(&(data.len() as u32).to_le_bytes());
        self.messages.extend_from_slice(data);
        true
    }

    fn set_param(&mut self, index: u32, value: f32) {
        // The last word on a parameter within a block is the one that counts.
        if let Some(known) = self.moves.iter_mut().find(|m| m.index == index) {
            known.value = value;
        } else if self.moves.len() < PARAMS {
            self.moves.push(ParamMove { index, value });
        }
    }
}

// --- the control wire --------------------------------------------------------------
//
// The socket carries frames: `[length: u32 LE][first byte][payload]`, the
// length counting the first byte. A request's first byte is its `Op`. The
// requests that are answered get a frame back whose first byte is 0, or 1
// with the reason when the plugin refused. The wire is paw's own: a helper
// and a DAW built apart understand each other only while these bytes stay.

/// What a request asks for: its first byte on the wire.
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Op {
    SetValue = 1,
    SaveState = 2,
    LoadState = 3,
    OpenEditor = 4,
    CloseEditor = 5,
    SetOffline = 6,
    Call = 7,
    Quit = 8,
    Values = 9,
}

impl TryFrom<u8> for Op {
    type Error = u8;

    fn try_from(byte: u8) -> Result<Self, u8> {
        Ok(match byte {
            1 => Self::SetValue,
            2 => Self::SaveState,
            3 => Self::LoadState,
            4 => Self::OpenEditor,
            5 => Self::CloseEditor,
            6 => Self::SetOffline,
            7 => Self::Call,
            8 => Self::Quit,
            9 => Self::Values,
            other => return Err(other),
        })
    }
}

/// A request from the DAW to its helper, and what the helper answers.
#[derive(Clone, Debug, PartialEq)]
enum Request<'a> {
    /// Set a parameter. No answer.
    SetValue { index: u32, value: f64 },
    /// The plugin's state, answered as [`optional`] bytes.
    SaveState,
    LoadState(&'a [u8]),
    /// Open the editor, in a window with this title.
    OpenEditor(Cow<'a, str>),
    /// No answer.
    CloseEditor,
    /// No answer.
    SetOffline(bool),
    /// A parameter's value as text ([`Controller::value_text`]): a
    /// [`Op::Call`] of [`PARAM_TEXT`]. Answered with the text.
    ValueText { index: u32, value: f64 },
    /// The value that a parameter's text stands for
    /// ([`Controller::text_value`]): a [`Op::Call`] of [`PARAM_VALUE`].
    /// Answered with the value in 8 bytes, or with none.
    TextValue { index: u32, text: Cow<'a, str> },
    /// Get a call ready for the audio thread ([`Controller::prepare`]): a
    /// [`Op::Call`] of [`PREPARE`], answered as [`optional`] bytes.
    Prepare { method: Cow<'a, str>, data: &'a [u8] },
    /// Any other call ([`Controller::call`]).
    Call { method: Cow<'a, str>, data: &'a [u8] },
    /// End. No answer.
    Quit,
    /// The parameters' values, answered as a JSON array (see [`read_values`]).
    Values,
}

impl<'a> Request<'a> {
    fn op(&self) -> Op {
        match self {
            Self::SetValue { .. } => Op::SetValue,
            Self::SaveState => Op::SaveState,
            Self::LoadState(_) => Op::LoadState,
            Self::OpenEditor(_) => Op::OpenEditor,
            Self::CloseEditor => Op::CloseEditor,
            Self::SetOffline(_) => Op::SetOffline,
            Self::ValueText { .. }
            | Self::TextValue { .. }
            | Self::Prepare { .. }
            | Self::Call { .. } => Op::Call,
            Self::Quit => Op::Quit,
            Self::Values => Op::Values,
        }
    }

    /// The request as one frame. A call's method ends in a 0 byte.
    fn frame(&self) -> Vec<u8> {
        fn method(out: &mut Vec<u8>, name: &str) {
            out.extend_from_slice(name.as_bytes());
            out.push(0);
        }
        let mut out = vec![0; 4];
        out.push(self.op() as u8);
        match self {
            Self::SetValue { index, value } => {
                out.extend_from_slice(&index.to_le_bytes());
                out.extend_from_slice(&value.to_le_bytes());
            }
            Self::ValueText { index, value } => {
                method(&mut out, PARAM_TEXT);
                out.extend_from_slice(&index.to_le_bytes());
                out.extend_from_slice(&value.to_le_bytes());
            }
            Self::SaveState | Self::CloseEditor | Self::Quit | Self::Values => {}
            Self::LoadState(state) => out.extend_from_slice(state),
            Self::OpenEditor(title) => out.extend_from_slice(title.as_bytes()),
            Self::SetOffline(offline) => out.push(u8::from(*offline)),
            Self::TextValue { index, text } => {
                method(&mut out, PARAM_VALUE);
                out.extend_from_slice(&index.to_le_bytes());
                out.extend_from_slice(text.as_bytes());
            }
            Self::Prepare { method: inner, data } => {
                method(&mut out, PREPARE);
                method(&mut out, inner);
                out.extend_from_slice(data);
            }
            Self::Call { method: name, data } => {
                method(&mut out, name);
                out.extend_from_slice(data);
            }
        }
        let length = (out.len() - 4) as u32;
        out[..4].copy_from_slice(&length.to_le_bytes());
        out
    }

    /// The request in a frame's payload, or `None` for one too short to
    /// say what it asks.
    fn decode(op: Op, payload: &'a [u8]) -> Option<Self> {
        Some(match op {
            Op::SetValue => Self::SetValue {
                index: le_u32(payload)?,
                value: le_f64(payload.get(4..)?)?,
            },
            Op::SaveState => Self::SaveState,
            Op::LoadState => Self::LoadState(payload),
            Op::OpenEditor => Self::OpenEditor(String::from_utf8_lossy(payload)),
            Op::CloseEditor => Self::CloseEditor,
            Op::SetOffline => Self::SetOffline(payload.first() == Some(&1)),
            Op::Quit => Self::Quit,
            Op::Values => Self::Values,
            Op::Call => {
                let (method, data) = split_method(payload);
                let index = le_u32(data);
                if method == PREPARE {
                    let (method, data) = split_method(data);
                    Self::Prepare { method, data }
                } else if method == PARAM_TEXT
                    && let (Some(index), Some(value)) = (index, data.get(4..).and_then(le_f64))
                {
                    Self::ValueText { index, value }
                } else if method == PARAM_VALUE
                    && let Some(index) = index
                {
                    Self::TextValue {
                        index,
                        text: String::from_utf8_lossy(&data[4..]),
                    }
                } else {
                    Self::Call { method, data }
                }
            }
        })
    }
}

/// A call's method, up to its 0 byte, and the data after it.
fn split_method(payload: &[u8]) -> (Cow<'_, str>, &[u8]) {
    let end = payload
        .iter()
        .position(|b| *b == 0)
        .unwrap_or(payload.len());
    (
        String::from_utf8_lossy(&payload[..end]),
        payload.get(end + 1..).unwrap_or(&[]),
    )
}

fn le_u32(bytes: &[u8]) -> Option<u32> {
    Some(u32::from_le_bytes(bytes.get(..4)?.try_into().ok()?))
}

fn le_f64(bytes: &[u8]) -> Option<f64> {
    Some(f64::from_le_bytes(bytes.get(..8)?.try_into().ok()?))
}

/// Bytes that may be absent, as a state and a prepared call are answered:
/// `[0]` for none, `[1][bytes]` for some.
fn optional(bytes: Option<Vec<u8>>) -> Vec<u8> {
    match bytes {
        Some(mut bytes) => {
            bytes.insert(0, 1);
            bytes
        }
        None => vec![0],
    }
}

fn from_optional(mut answer: Vec<u8>) -> Option<Vec<u8>> {
    (answer.first() == Some(&1)).then(|| answer.split_off(1))
}

/// The first byte of an answer: the plugin did it.
const DONE: u8 = 0;
/// The first byte of an answer: the plugin refused, and the rest says why.
const REFUSED: u8 = 1;

fn send(stream: &mut UnixStream, request: &Request) -> std::io::Result<()> {
    stream.write_all(&request.frame())
}

/// Send an answer: what was asked for, or why the plugin refused.
fn answer(stream: &mut UnixStream, answer: Result<&[u8], &str>) -> std::io::Result<()> {
    let (first, payload) = match answer {
        Ok(bytes) => (DONE, bytes),
        Err(why) => (REFUSED, why.as_bytes()),
    };
    let mut frame = Vec::with_capacity(payload.len() + 5);
    frame.extend_from_slice(&(payload.len() as u32 + 1).to_le_bytes());
    frame.push(first);
    frame.extend_from_slice(payload);
    stream.write_all(&frame)
}

/// Read an answer: what was asked for, or why the plugin refused.
fn receive(stream: &mut UnixStream) -> std::io::Result<Result<Vec<u8>, String>> {
    let mut length = [0u8; 4];
    stream.read_exact(&mut length)?;
    let length = u32::from_le_bytes(length) as usize;
    if length == 0 || length > 1 << 30 {
        return Err(std::io::Error::other("a frame of an impossible size"));
    }
    let mut frame = vec![0u8; length];
    stream.read_exact(&mut frame)?;
    let rest = frame.split_off(1);
    Ok(match frame[0] {
        DONE => Ok(rest),
        _ => Err(String::from_utf8_lossy(&rest).into_owned()),
    })
}

/// The helper's first word: what the plugin that it made is like.
///
/// JSON has no word for a number that is not finite: serde_json writes it
/// as null, and the DAW reads that as 0.
#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(default)]
struct Hello {
    #[serde(deserialize_with = "params_null_as_zero")]
    params: Vec<ParamInfo>,
    #[serde(deserialize_with = "values_null_as_zero")]
    values: Vec<f64>,
    has_editor: bool,
    follows_state: bool,
    sidechain: bool,
    outputs: Vec<String>,
}

impl Hello {
    /// The bytes on the wire. They go through a [`Value`], whose keys are
    /// in order, as the helper has always written them.
    fn to_vec(&self) -> serde_json::Result<Vec<u8>> {
        serde_json::to_vec(&serde_json::to_value(self)?)
    }
}

fn params_null_as_zero<'de, D: Deserializer<'de>>(from: D) -> Result<Vec<ParamInfo>, D::Error> {
    let mut params = Vec::<Value>::deserialize(from)?;
    for param in &mut params {
        for key in ["min", "max", "default"] {
            if let Some(number) = param.get_mut(key)
                && number.is_null()
            {
                *number = 0.0.into();
            }
        }
    }
    params
        .into_iter()
        .map(|param| ParamInfo::deserialize(param).map_err(serde::de::Error::custom))
        .collect()
}

fn values_null_as_zero<'de, D: Deserializer<'de>>(from: D) -> Result<Vec<f64>, D::Error> {
    let values = Vec::<Option<f64>>::deserialize(from)?;
    Ok(values.into_iter().map(|v| v.unwrap_or(0.0)).collect())
}

/// The answer to [`Request::Values`]: each value, or `None` for one that
/// was not finite.
fn read_values(answer: &[u8]) -> Option<Vec<Option<f64>>> {
    serde_json::from_slice(answer).ok()
}

/// Why a helper is gone, or gave no answer.
#[derive(Clone, Debug, thiserror::Error)]
enum HelperError {
    /// It ended: the reason it gave, or how its process ended.
    #[error("{0}")]
    Exited(String),
    /// The plugin refused, saying why.
    #[error("{0}")]
    Refused(String),
    /// No answer to a request within the limit.
    #[error("it did not answer for {} seconds and was ended", .0.as_secs())]
    Silent(Duration),
    #[error(
        "it did not answer for {} seconds while it was being made, and was ended",
        .0.as_secs()
    )]
    SilentMaking(Duration),
    #[error("it did not load its state within {} seconds, and was ended", .0.as_secs())]
    SilentLoading(Duration),
    /// No block answered for this long, while some came late.
    #[error("it stopped answering (no block for {} seconds) and was ended", .0.as_secs())]
    Stalled(Duration),
    /// Given up on by the audio side in a render, with no reason given.
    #[error("it did not answer a block of the render in time and was ended")]
    LateInRender,
    #[error("the connection to it broke ({0})")]
    Broken(String),
    #[error("the connection to it broke")]
    Disconnected,
}

impl HelperError {
    /// What an error of the socket means: `silent` if no answer came in
    /// time, else a broken connection.
    fn of_io(err: &std::io::Error, silent: Self) -> Self {
        if silence(err) {
            silent
        } else {
            Self::Broken(err.to_string())
        }
    }
}

// --- the DAW's side: the main thread ---------------------------------------------

/// The main-thread half of the stand-in.
struct RemoteController {
    name: String,
    link: Arc<Link>,
    stream: UnixStream,
    child: Child,
    params: Vec<ParamInfo>,
    values: Vec<f64>,
    has_editor: bool,
    follows_state: bool,
    ports: Ports,
    pending: Vec<Change>,
    /// Why the helper is gone, once it is.
    ended: Option<HelperError>,
    late_seen: u32,
    /// Blocks answered when last looked at, and since when none have been
    /// while some came late.
    answered_seen: u32,
    stalled_since: Option<Instant>,
    /// The plugin was given a state or a call when it had answered this
    /// many blocks: its values are read again once it has answered
    /// another, as some plugins take a state on only in their next block.
    reread: Option<u32>,
}

impl RemoteController {
    /// Note that the helper is gone and why, once.
    fn end(&mut self, why: HelperError) {
        if self.ended.is_none() {
            self.link.dead.store(true, Ordering::Relaxed);
            // Whatever is waiting for it gives up now.
            futex_wake(&self.link.shm.header().done);
            self.kill();
            self.ended = Some(why);
        }
    }

    /// End the helper and whatever it started.
    fn kill(&mut self) {
        // The helper leads a process group of its own (see `spawn`).
        let _ = rustix::process::kill_process_group(
            rustix::process::Pid::from_child(&self.child),
            rustix::process::Signal::KILL,
        );
        let _ = self.child.kill();
        let _ = self.child.wait();
    }

    /// How the helper ended, if it has: the reason it gave, or how its
    /// process ended.
    fn exited(&mut self) -> Option<HelperError> {
        match self.child.try_wait() {
            Ok(Some(status)) => Some(HelperError::Exited(
                self.link
                    .shm
                    .header()
                    .reason()
                    .unwrap_or_else(|| describe(status)),
            )),
            _ => None,
        }
    }

    /// Ask the helper for something and wait for its answer, but not
    /// longer than `limit`.
    fn ask(&mut self, request: &Request, limit: Duration) -> Result<Vec<u8>> {
        if let Some(why) = &self.ended {
            bail!("{} is not running: {why}", self.name);
        }
        let outcome = (|| {
            send(&mut self.stream, request)?;
            self.stream.set_read_timeout(Some(limit))?;
            receive(&mut self.stream)
        })();
        match outcome {
            Ok(Ok(answer)) => Ok(answer),
            Ok(Err(reason)) => bail!("{reason}"),
            Err(err) => {
                let why = self
                    .exited()
                    .unwrap_or_else(|| HelperError::of_io(&err, HelperError::Silent(limit)));
                self.end(why.clone());
                bail!("{} stopped: {why}", self.name)
            }
        }
    }

    /// Tell the helper something that needs no answer.
    fn tell(&mut self, request: &Request) {
        if self.ended.is_none() && send(&mut self.stream, request).is_err() {
            let why = self.exited().unwrap_or(HelperError::Disconnected);
            self.end(why);
        }
    }

    fn refresh_values(&mut self) {
        if let Ok(answer) = self.ask(&Request::Values, QUICK_LIMIT)
            && let Some(values) = read_values(&answer)
        {
            for (slot, value) in self.values.iter_mut().zip(values) {
                *slot = value.unwrap_or(*slot);
            }
        }
    }
}

/// The processor time a process has used, all its threads together.
fn process_time(pid: u32) -> Option<Duration> {
    let stat = std::fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    // The name, in parentheses, may hold spaces: the fields after it count
    // from the state, the third field.
    let rest = &stat[stat.rfind(')')? + 2..];
    let fields: Vec<&str> = rest.split(' ').collect();
    let ticks = fields.get(11)?.parse::<u64>().ok()? + fields.get(12)?.parse::<u64>().ok()?;
    let per_second = rustix::param::clock_ticks_per_second().max(1);
    Some(Duration::from_nanos(ticks * 1_000_000_000 / per_second))
}

fn describe(status: std::process::ExitStatus) -> String {
    use std::os::unix::process::ExitStatusExt;
    match (status.signal(), status.code()) {
        (Some(signal), _) if signal == Signal::SEGV.as_raw() => "it crashed (a memory fault)".into(),
        (Some(signal), _) if signal == Signal::ABORT.as_raw() => "it crashed (it aborted)".into(),
        (Some(signal), _) if signal == Signal::KILL.as_raw() => "it was killed".into(),
        (Some(signal), _) => format!("it crashed (signal {signal})"),
        (None, Some(code)) => format!("its process ended with code {code}"),
        _ => "its process ended".into(),
    }
}

impl Controller for RemoteController {
    fn params(&self) -> Vec<ParamInfo> {
        self.params.clone()
    }

    fn value(&self, index: usize) -> Option<f64> {
        self.values.get(index).copied()
    }

    fn set_value(&mut self, index: usize, value: f64) {
        if let Some(slot) = self.values.get_mut(index) {
            *slot = value;
        }
        self.tell(&Request::SetValue {
            index: index as u32,
            value,
        });
    }

    fn save_state(&mut self) -> Result<Option<Vec<u8>>> {
        Ok(from_optional(self.ask(&Request::SaveState, STATE_LIMIT)?))
    }

    fn load_state(&mut self, state: &[u8]) -> Result<()> {
        self.ask(&Request::LoadState(state), STATE_LIMIT)?;
        self.link.wake.store(true, Ordering::Relaxed);
        self.reread = Some(self.link.answered.load(Ordering::Relaxed));
        self.refresh_values();
        Ok(())
    }

    fn follows_state(&self) -> bool {
        self.follows_state
    }

    fn ports(&self) -> Ports {
        self.ports.clone()
    }

    fn idle(&mut self) {
        if self.ended.is_none()
            && let Some(how) = self.exited()
        {
            self.end(how);
        }
        // What the plugin changed by itself.
        let shm = &self.link.shm;
        let header = shm.header();
        let head = header.change_head.load(Ordering::Acquire);
        let mut tail = header.change_tail.load(Ordering::Relaxed);
        while tail != head {
            let change = shm.change(tail);
            if let Some(slot) = self.values.get_mut(change.index as usize) {
                *slot = change.value;
                self.pending.push(Change {
                    index: change.index as usize,
                    value: change.value,
                    edit: change.edit != 0,
                });
            }
            tail = tail.wrapping_add(1);
        }
        header.change_tail.store(tail, Ordering::Release);
        // The values of a state the plugin has taken on since.
        if let Some(at) = self.reread
            && self.link.answered.load(Ordering::Relaxed) != at
        {
            self.reread = None;
            let before = self.values.clone();
            self.refresh_values();
            // Read back by the host: the echo of the state.
            for (index, (old, new)) in before.iter().zip(&self.values).enumerate() {
                if old != new {
                    self.pending.push(Change {
                        index,
                        value: *new,
                        edit: false,
                    });
                }
            }
        }
    }

    fn take_changes(&mut self) -> Vec<Change> {
        std::mem::take(&mut self.pending)
    }

    fn value_text(&mut self, index: usize, value: f64) -> Option<String> {
        let request = Request::ValueText {
            index: index as u32,
            value,
        };
        let answer = self.ask(&request, QUICK_LIMIT).ok()?;
        (!answer.is_empty()).then(|| String::from_utf8_lossy(&answer).into_owned())
    }

    fn text_value(&mut self, index: usize, text: &str) -> Option<f64> {
        let request = Request::TextValue {
            index: index as u32,
            text: text.into(),
        };
        le_f64(&self.ask(&request, QUICK_LIMIT).ok()?)
    }

    fn has_editor(&self) -> bool {
        self.has_editor
    }

    fn editor_open(&self) -> bool {
        self.ended.is_none() && self.link.shm.header().editor_open.load(Ordering::Relaxed) != 0
    }

    fn open_editor(&mut self, title: &str) -> Result<()> {
        self.ask(&Request::OpenEditor(title.into()), STATE_LIMIT)
            .map(|_| ())
    }

    fn close_editor(&mut self) {
        self.tell(&Request::CloseEditor);
    }

    fn latency(&self) -> u32 {
        self.link.shm.header().latency.load(Ordering::Relaxed)
    }

    fn set_offline(&mut self, offline: bool) {
        self.link
            .shm
            .header()
            .offline
            .store(offline as u32, Ordering::Relaxed);
        self.tell(&Request::SetOffline(offline));
    }

    fn call(&mut self, method: &str, data: &[u8]) -> Result<Vec<u8>> {
        // What the stand-in knows itself: the helper's process, and how
        // many blocks it did not answer in time.
        match method {
            "sandbox.pid" => return Ok(self.child.id().to_string().into_bytes()),
            // For tests: this helper, and those started from now on, stop
            // answering blocks ("0" puts it back for new ones).
            "sandbox.hang" => TEST_HANG.store(data != b"0", Ordering::Relaxed),
            "sandbox.late" => {
                return Ok(self
                    .link
                    .late
                    .load(Ordering::Relaxed)
                    .to_string()
                    .into_bytes());
            }
            _ => {}
        }
        let request = Request::Call {
            method: method.into(),
            data,
        };
        let answer = self.ask(&request, STATE_LIMIT)?;
        self.link.wake.store(true, Ordering::Relaxed);
        self.reread = Some(self.link.answered.load(Ordering::Relaxed));
        // A preset sets the plugin's parameters anew.
        if method == paw_engine::device::method::PRESET_LOAD {
            self.refresh_values();
        }
        Ok(answer)
    }

    fn late_blocks(&self) -> u64 {
        self.link.late.load(Ordering::Relaxed) as u64
    }

    fn prepare(&mut self, method: &str, data: &[u8]) -> Result<Option<Vec<u8>>> {
        let request = Request::Prepare {
            method: method.into(),
            data,
        };
        Ok(from_optional(self.ask(&request, STATE_LIMIT)?))
    }

    fn busy_time(&mut self) -> Option<Duration> {
        if self.ended.is_some() {
            return None;
        }
        process_time(self.child.id())
    }

    fn health(&mut self) -> Option<String> {
        let late = self.link.late.load(Ordering::Relaxed);
        let answered = self.link.answered.load(Ordering::Relaxed);
        let late_before = std::mem::replace(&mut self.late_seen, late);
        let answered_before = std::mem::replace(&mut self.answered_seen, answered);
        // Late now and then is a slow plugin; late every time for a while,
        // with no answer in between, is a plugin that has hung.
        if self.ended.is_none() && self.link.dead.load(Ordering::Relaxed) {
            // Given up on by the audio side: a render it did not answer, or
            // one it stopped in, saying why.
            let why = self.link.shm.header().reason();
            self.end(why.map_or(HelperError::LateInRender, HelperError::Exited));
        } else if answered != answered_before {
            self.stalled_since = None;
        } else if late != late_before || self.stalled_since.is_some() {
            let since = *self.stalled_since.get_or_insert_with(Instant::now);
            if since.elapsed() >= STALL_LIMIT {
                self.end(HelperError::Stalled(STALL_LIMIT));
            }
        }
        self.ended.as_ref().map(ToString::to_string)
    }
}

impl Drop for RemoteController {
    fn drop(&mut self) {
        if self.ended.is_none() {
            self.link.shm.header().quit.store(1, Ordering::Release);
            futex_wake(&self.link.shm.header().request);
            let _ = send(&mut self.stream, &Request::Quit);
            // Most plugins are gone in a moment; none is waited for long.
            let deadline = Instant::now() + Duration::from_millis(1500);
            while Instant::now() < deadline {
                if matches!(self.child.try_wait(), Ok(Some(_))) {
                    return;
                }
                std::thread::sleep(Duration::from_millis(5));
            }
        }
        self.link.dead.store(true, Ordering::Relaxed);
        self.kill();
    }
}

/// Makes a plugin in a helper process.
#[derive(Clone)]
struct RemoteFactory {
    info: DeviceInfo,
    /// How to start the helper, where it is not the plugins' one.
    argv: Option<Vec<String>>,
    env: Vec<(String, String)>,
}

/// The methods by which the stand-in asks the helper for a parameter's
/// text and value (see [`Controller::value_text`]).
const PARAM_TEXT: &str = "paw.param.text";
const PARAM_VALUE: &str = "paw.param.value";

/// How long a plugin may take to be made: [`CREATE_LIMIT`], or the seconds
/// in `PAW_PLUGIN_CREATE_LIMIT` (for tests).
fn create_limit() -> Duration {
    std::env::var("PAW_PLUGIN_CREATE_LIMIT")
        .ok()
        .and_then(|text| text.parse::<f64>().ok())
        .filter(|secs| secs.is_finite() && *secs > 0.0)
        .map_or(CREATE_LIMIT, Duration::from_secs_f64)
}

/// Why a helper gave no answer: whether it timed out, and the error.
fn silence(err: &std::io::Error) -> bool {
    matches!(
        err.kind(),
        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
    )
}

impl RemoteFactory {
    /// Start the helper, which makes the plugin. Its first word, read with
    /// [`made`](Self::made), says whether that worked.
    fn spawn(&self, sample_rate: f32, max_block: usize) -> Result<(RemoteController, UnixStream)> {
        let argv = match &self.argv {
            Some(argv) => argv,
            None => host_command().context("plugins are hosted in-process here")?,
        };
        let shm = Shm::create(max_block)?;
        let (ours, theirs) = UnixStream::pair()?;
        let (sock_fd, shm_fd): (RawFd, RawFd) = (theirs.as_raw_fd(), shm.fd.as_raw_fd());
        let mut command = Command::new(&argv[0]);
        command
            .args(&argv[1..])
            .arg(&self.info.kind)
            .arg(sock_fd.to_string())
            .arg(shm_fd.to_string())
            .arg(sample_rate.to_string())
            .arg(max_block.to_string())
            .envs(self.env.iter().map(|(k, v)| (k, v)))
            .stdin(Stdio::null());
        if let Some(dirs) = crate::added_dirs_env() {
            command.env(crate::ADDED_DIRS_ENV, dirs);
        }
        if let Some(libs) = crate::attach::env() {
            command.env(crate::attach::ATTACH_ENV, libs);
        }
        if TEST_HANG.load(Ordering::Relaxed) {
            command.env("PAW_PLUGIN_TEST_HANG", "1");
        }
        if let Some(cache) = CACHE.lock().unwrap().as_ref() {
            command.arg(cache);
        }
        // SAFETY: the closure runs in the child between fork and exec, where
        // only async-signal-safe calls may be made. Each call below is one
        // syscall that allocates nothing and takes no lock; errors are
        // ignored, as `Errno` is a plain number. The two descriptors stay
        // open in this process until the child is spawned.
        unsafe {
            command.pre_exec(move || {
                use rustix::io::{FdFlags, fcntl_setfd};
                use rustix::process::{set_parent_process_death_signal, setpgid};
                // The helper is handed the socket and the memory, and is
                // told to finish if this program ends first.
                let _ = fcntl_setfd(BorrowedFd::borrow_raw(sock_fd), FdFlags::empty());
                let _ = fcntl_setfd(BorrowedFd::borrow_raw(shm_fd), FdFlags::empty());
                let _ = set_parent_process_death_signal(Some(Signal::TERM));
                // A group of its own, so that what the plugin starts in
                // turn (a bridge to Wine) can be ended along with it.
                let _ = setpgid(None, None);
                Ok(())
            });
        }
        let child = command
            .spawn()
            .with_context(|| format!("starting the helper for {}", self.info.name))?;
        drop(theirs);

        let link = Arc::new(Link {
            shm,
            dead: AtomicBool::new(false),
            late: AtomicU32::new(0),
            answered: AtomicU32::new(0),
            wake: AtomicBool::new(false),
        });
        let controller = RemoteController {
            name: self.info.name.clone(),
            link,
            stream: ours.try_clone()?,
            child,
            params: Vec::new(),
            values: Vec::new(),
            has_editor: false,
            follows_state: false,
            ports: Ports::default(),
            pending: Vec::new(),
            ended: None,
            late_seen: 0,
            answered_seen: 0,
            stalled_since: None,
            reread: None,
        };
        Ok((controller, ours))
    }

    /// The device and its controller, from the helper's first word.
    fn made(&self, mut controller: RemoteController, hello: Hello) -> Instance {
        controller.params = hello.params;
        controller.values = hello.values;
        controller.values.resize(controller.params.len(), 0.0);
        controller.has_editor = hello.has_editor;
        controller.follows_state = hello.follows_state;
        controller.ports = Ports {
            sidechain: hello.sidechain,
            outputs: hello.outputs,
        };
        Instance {
            device: Box::new(RemoteDevice {
                link: controller.link.clone(),
                instrument: self.info.category == Category::Instrument,
                seq: 0,
                outstanding: false,
                turn: controller.link.shm.turn(),
                moves: Vec::with_capacity(PARAMS),
            messages: Vec::with_capacity(MESSAGES),
                told_priority: false,
                rest: Rest::default(),
                offline_limit: if self.argv.is_some() { STALL_LIMIT } else { OFFLINE_LIMIT },
            }),
            controller: Some(Box::new(controller)),
        }
    }
}

/// A plugin being made in its helper while a thread of ours waits for it.
struct RemoteStarting {
    factory: RemoteFactory,
    controller: Option<RemoteController>,
    /// The plugin made (the helper's first word), its state loaded, or why not.
    answer: std::sync::mpsc::Receiver<Result<Hello, HelperError>>,
}

impl Starting for RemoteStarting {
    fn poll(&mut self) -> Option<Result<Instance>> {
        let heard = match self.answer.try_recv() {
            Ok(heard) => heard,
            Err(std::sync::mpsc::TryRecvError::Empty) => return None,
            Err(std::sync::mpsc::TryRecvError::Disconnected) => Err(HelperError::Broken(
                "the thread waiting for it ended".into(),
            )),
        };
        let mut controller = self.controller.take()?;
        let name = &self.factory.info.name;
        let why = match heard {
            Ok(hello) => return Some(Ok(self.factory.made(controller, hello))),
            Err(HelperError::Refused(reason)) => {
                controller.end(HelperError::Refused(reason.clone()));
                return Some(Err(anyhow!("{reason}")));
            }
            // How it ended says more than the silence or the broken socket.
            Err(silent) => controller.exited().unwrap_or(silent),
        };
        controller.end(why.clone());
        Some(Err(anyhow!("{name} could not be started: {why}")))
    }
}

/// Wait on a thread of its own for the helper to make the plugin, and
/// load `state` into it.
fn wait_for_helper(
    mut stream: UnixStream,
    state: Option<Vec<u8>>,
    limit: Duration,
    tell: std::sync::mpsc::Sender<Result<Hello, HelperError>>,
) {
    let heard = (|| {
        let broken = |err: std::io::Error| HelperError::Broken(err.to_string());
        stream.set_read_timeout(Some(limit)).map_err(broken)?;
        let mut hello = match receive(&mut stream) {
            Ok(Ok(answer)) => serde_json::from_slice::<Hello>(&answer).map_err(|err| {
                HelperError::Broken(format!("its first word made no sense: {err}"))
            })?,
            Ok(Err(reason)) => return Err(HelperError::Refused(reason)),
            Err(err) => return Err(HelperError::of_io(&err, HelperError::SilentMaking(limit))),
        };
        let Some(state) = state else {
            return Ok(hello);
        };
        let _ = stream.set_read_timeout(Some(STATE_LIMIT));
        match send(&mut stream, &Request::LoadState(&state)).and_then(|_| receive(&mut stream)) {
            Ok(Ok(_)) => {}
            Ok(Err(reason)) => {
                return Err(HelperError::Refused(format!(
                    "could not restore its state: {reason}"
                )));
            }
            Err(err) => {
                return Err(HelperError::of_io(&err, HelperError::SilentLoading(STATE_LIMIT)));
            }
        }
        // The values the state brought with it.
        let _ = stream.set_read_timeout(Some(QUICK_LIMIT));
        if let Ok(Ok(answer)) =
            send(&mut stream, &Request::Values).and_then(|_| receive(&mut stream))
            && let Some(values) = read_values(&answer)
        {
            hello.values = values.into_iter().map(|v| v.unwrap_or(0.0)).collect();
        }
        Ok(hello)
    })();
    let _ = tell.send(heard);
}

impl DeviceFactory for RemoteFactory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, max_block: usize) -> Result<Instance> {
        let (mut controller, mut ours) = self.spawn(sample_rate, max_block)?;
        // Its first word is that the plugin exists, or why it does not.
        let limit = create_limit();
        ours.set_read_timeout(Some(limit))?;
        let hello = match receive(&mut ours) {
            Ok(Ok(answer)) => serde_json::from_slice::<Hello>(&answer)
                .map_err(|err| anyhow!("the helper's first word made no sense: {err}"))?,
            Ok(Err(reason)) => bail!("{reason}"),
            Err(err) => {
                let why = controller
                    .exited()
                    .unwrap_or_else(|| HelperError::of_io(&err, HelperError::SilentMaking(limit)));
                controller.end(why.clone());
                bail!("{} could not be started: {why}", self.info.name)
            }
        };
        Ok(self.made(controller, hello))
    }

    fn starts_apart(&self) -> bool {
        true
    }

    fn start(
        &self,
        sample_rate: f32,
        max_block: usize,
        state: Option<Vec<u8>>,
    ) -> Option<Box<dyn Starting>> {
        let factory = self.clone();
        let (tell, answer) = std::sync::mpsc::channel();
        let limit = create_limit();
        let controller = match self.spawn(sample_rate, max_block) {
            Ok((controller, ours)) => {
                let spawned = std::thread::Builder::new()
                    .name("plugin-start".into())
                    .spawn(move || wait_for_helper(ours, state, limit, tell));
                if let Err(err) = spawned {
                    return Some(Box::new(Failed(Some(anyhow!(
                        "{} could not be started: {err}",
                        self.info.name
                    )))));
                }
                controller
            }
            Err(err) => return Some(Box::new(Failed(Some(err)))),
        };
        Some(Box::new(RemoteStarting {
            factory,
            controller: Some(controller),
            answer,
        }))
    }
}

/// A start that failed before it began.
struct Failed(Option<anyhow::Error>);

impl Starting for Failed {
    fn poll(&mut self) -> Option<Result<Instance>> {
        self.0.take().map(Err)
    }
}

// --- the helper ------------------------------------------------------------------

/// A controller for a plugin that has none: nothing to set, nothing to save.
struct NoController;

impl Controller for NoController {
    fn params(&self) -> Vec<ParamInfo> {
        Vec::new()
    }
    fn value(&self, _index: usize) -> Option<f64> {
        None
    }
    fn save_state(&mut self) -> Result<Option<Vec<u8>>> {
        Ok(None)
    }
    fn load_state(&mut self, _state: &[u8]) -> Result<()> {
        Ok(())
    }
}

/// The helper's audio thread: do each block that is asked for.
fn audio_loop(shm: Arc<Shm>, mut device: Box<dyn Device>) {
    paw_engine::no_denormals();
    let header = shm.header();
    let mut turn = shm.turn();
    let mut events = paw_engine::EventBuf::with_capacity(EVENTS);
    // The further output pairs, filled by the plugin and then copied over;
    // those not asked for are put aside while it runs.
    let mut outs: Vec<Option<[Vec<f32>; 2]>> = (0..MAX_PAIRS - 1)
        .map(|_| Some([vec![0.0; shm.max_block], vec![0.0; shm.max_block]]))
        .collect();
    let mut aside: Vec<Option<[Vec<f32>; 2]>> = (0..MAX_PAIRS - 1).map(|_| None).collect();
    let mut seen = 0u32;
    let mut scheduling = (0u32, 0u32);
    loop {
        let asked = header.request.load(Ordering::Acquire);
        if header.quit.load(Ordering::Acquire) != 0 {
            return;
        }
        if asked == seen {
            futex_wait(&header.request, seen, Duration::from_millis(200));
            continue;
        }
        if TEST_HANG.load(Ordering::Relaxed) {
            // As a plugin stuck in its processing would: no answer, ever.
            std::thread::sleep(Duration::from_millis(50));
            continue;
        }
        // Run as the DAW's audio thread does, where the system allows it.
        let wanted = (
            header.policy.load(Ordering::Relaxed),
            header.priority.load(Ordering::Relaxed),
        );
        if wanted != scheduling {
            scheduling = wanted;
            // libc: rustix has no wrapper for pthread_setschedparam.
            let mut param: libc::sched_param = unsafe { std::mem::zeroed() };
            param.sched_priority = wanted.1 as i32;
            unsafe {
                libc::pthread_setschedparam(libc::pthread_self(), wanted.0 as i32, &param);
            }
        }
        let mut block = shm.block(&mut turn);
        let head = &mut *block.context;
        let frames = (head.frames as usize).min(shm.max_block);
        for mv in &block.params[..(head.params_in as usize).min(PARAMS)] {
            device.set_param(mv.index, mv.value);
        }
        events.clear();
        for event in &block.events[..(head.events_in as usize).min(EVENTS)] {
            events.push(*event);
        }
        let messages = &block.messages[..(head.messages_in as usize).min(MESSAGES)];
        let mut at = 0;
        while let Some(head) = messages.get(at..at + 8) {
            let frame = u32::from_le_bytes(head[..4].try_into().unwrap());
            let len = u32::from_le_bytes(head[4..].try_into().unwrap()) as usize;
            if let Some(data) = messages.get(at + 8..at + 8 + len) {
                device.message(frame, data);
            }
            at += 8 + len;
        }
        let ctx = ProcessCtx {
            sample_rate: head.sample_rate,
            tempo: head.tempo,
            sig_num: head.sig_num,
            sig_den: head.sig_den,
            playing: head.playing != 0,
            position: head.position,
            seconds: head.seconds,
            bar: head.bar,
            bar_start: head.bar_start,
        };
        let keyed = head.keyed != 0;
        let wanted = head.outs;
        {
            let Block {
                left, right, key: [key_l, key_r], ..
            } = &mut block;
            let pairs = (u32::BITS - wanted.leading_zeros()) as usize;
            for (pair, (out, put)) in outs.iter_mut().zip(aside.iter_mut()).enumerate() {
                // Swapped, not made or freed: what is asked for is in `outs`.
                if (wanted >> pair & 1 != 0) != out.is_some() {
                    std::mem::swap(out, put);
                }
                if let Some([l, r]) = out {
                    l[..frames].fill(0.0);
                    r[..frames].fill(0.0);
                }
            }
            let mut io = Io {
                left: &mut left[..frames],
                right: &mut right[..frames],
                events: &mut events,
                sidechain: keyed.then_some([&key_l[..frames], &key_r[..frames]]),
                outputs: &mut outs[..pairs.min(MAX_PAIRS - 1)],
            };
            device.process(&ctx, &mut io);
            for (pair, out) in outs.iter().enumerate() {
                if let Some([l, r]) = out {
                    block.out(pair, 0)[..frames].copy_from_slice(&l[..frames]);
                    block.out(pair, 1)[..frames].copy_from_slice(&r[..frames]);
                }
            }
        }
        let out = events.as_slice();
        let count = out.len().min(EVENTS);
        block.events[..count].copy_from_slice(&out[..count]);
        block.context.events_out = count as u32;
        block.context.resting = device.resting() as u32;
        seen = asked;
        header.done.store(asked, Ordering::Release);
        futex_wake(&header.done);
    }
}

/// Run as a plugin's helper: `args` are the plugin's kind, the socket and
/// the shared memory handed over by the DAW, the sample rate, the largest
/// block, and the plugin cache to read. Returns the process's exit code.
pub fn serve(args: &[String]) -> i32 {
    let cache = args.get(5).map(PathBuf::from);
    serve_with(args, |kind, rate, max_block| {
        let mut registry = Registry::default();
        crate::adopt_added_dirs();
        crate::register(&mut registry, cache.as_deref());
        registry
            .get(kind)
            .with_context(|| format!("no plugin `{kind}` here"))
            .and_then(|factory| factory.create(rate, max_block))
    })
}

/// Run as the helper of a device that `make` makes from its kind, the
/// sample rate and the largest block, as [`serve`] does for plugins.
pub fn serve_with(
    args: &[String],
    make: impl FnOnce(&str, f32, usize) -> Result<Instance>,
) -> i32 {
    let run = || -> Result<()> {
        let [kind, sock, shm, rate, block, ..] = args else {
            bail!("usage: plugin-host <kind> <socket> <memory> <sample rate> <block> [cache]");
        };
        let mut stream = unsafe { UnixStream::from_raw_fd(sock.parse::<RawFd>()?) };
        let max_block: usize = block.parse()?;
        let shm = Arc::new(Shm::map(
            unsafe { OwnedFd::from_raw_fd(shm.parse::<RawFd>()?) },
            max_block,
        )?);
        if shm.header().magic != MAGIC {
            bail!("the shared memory is not the DAW's");
        }
        if std::env::var_os("PAW_PLUGIN_TEST_HANG").is_some() {
            TEST_HANG.store(true, Ordering::Relaxed);
        }
        // For tests: `PAW_PLUGIN_HOST_HANG=<part of a kind>:<seconds>` makes
        // the helper of a matching plugin wait that long before it makes
        // it, as one that waits on a dead network mount does.
        if let Ok(hang) = std::env::var("PAW_PLUGIN_HOST_HANG")
            && let Some((part, secs)) = hang.rsplit_once(':')
            && kind.contains(part)
            && let Ok(secs) = secs.parse::<f64>()
        {
            std::thread::sleep(Duration::from_secs_f64(secs.clamp(0.0, 3600.0)));
        }
        let display_note = crate::repair_display_env();
        let _ = display_note;
        let made = make(kind, rate.parse()?, max_block);
        let instance = match made {
            Ok(instance) => instance,
            Err(err) => {
                answer(&mut stream, Err(&format!("{err:#}")))?;
                return Ok(());
            }
        };
        let mut controller = instance
            .controller
            .unwrap_or_else(|| Box::new(NoController));
        let params = controller.params();
        let values: Vec<f64> = (0..params.len())
            .map(|i| controller.value(i).unwrap_or(0.0))
            .collect();
        let ports = controller.ports();
        let hello = Hello {
            params,
            values,
            has_editor: controller.has_editor(),
            follows_state: controller.follows_state(),
            sidechain: ports.sidechain,
            outputs: ports.outputs,
        };
        shm.header()
            .latency
            .store(controller.latency(), Ordering::Relaxed);
        answer(&mut stream, Ok(&hello.to_vec()?))?;
        let count = hello.params.len();

        let audio = {
            let shm = shm.clone();
            let device = instance.device;
            std::thread::Builder::new()
                .name("plugin-audio".into())
                .spawn(move || audio_loop(shm, device))?
        };

        // The main thread: requests from the DAW, and the plugin's own
        // housekeeping (its editor's events among it) in between.
        stream.set_read_timeout(Some(Duration::from_millis(10)))?;
        let header = shm.header();
        let mut pending: Vec<u8> = Vec::new();
        'serve: loop {
            let mut chunk = [0u8; 65536];
            match stream.read(&mut chunk) {
                Ok(0) => break 'serve,
                Ok(n) => pending.extend_from_slice(&chunk[..n]),
                Err(err)
                    if matches!(
                        err.kind(),
                        std::io::ErrorKind::WouldBlock
                            | std::io::ErrorKind::TimedOut
                            | std::io::ErrorKind::Interrupted
                    ) => {}
                Err(_) => break 'serve,
            }
            while pending.len() >= 4 {
                let length = u32::from_le_bytes(pending[..4].try_into().unwrap()) as usize;
                if pending.len() < 4 + length {
                    break;
                }
                let frame: Vec<u8> = pending.drain(..4 + length).skip(4).collect();
                // A request this helper does not know, or one too short to
                // say what it asks, is passed over.
                let Some(request) = frame.split_first().and_then(|(&op, payload)| {
                    Request::decode(Op::try_from(op).ok()?, payload)
                }) else {
                    continue;
                };
                let reply: Option<Result<Vec<u8>>> = match request {
                    Request::SetValue { index, value } => {
                        controller.set_value(index as usize, value);
                        None
                    }
                    Request::SaveState => Some(controller.save_state().map(optional)),
                    Request::LoadState(state) => {
                        Some(controller.load_state(state).map(|()| Vec::new()))
                    }
                    Request::OpenEditor(title) => {
                        Some(controller.open_editor(&title).map(|()| Vec::new()))
                    }
                    Request::CloseEditor => {
                        controller.close_editor();
                        None
                    }
                    Request::SetOffline(offline) => {
                        controller.set_offline(offline);
                        None
                    }
                    Request::ValueText { index, value } => Some(Ok(controller
                        .value_text(index as usize, value)
                        .unwrap_or_default()
                        .into_bytes())),
                    Request::TextValue { index, text } => Some(Ok(controller
                        .text_value(index as usize, &text)
                        .map(|v| v.to_le_bytes().to_vec())
                        .unwrap_or_default())),
                    Request::Prepare { method, data } => {
                        Some(controller.prepare(&method, data).map(optional))
                    }
                    Request::Call { method, data } if method == "sandbox.hang" => {
                        TEST_HANG.store(data != b"0", Ordering::Relaxed);
                        Some(Ok(Vec::new()))
                    }
                    Request::Call { method, data } => Some(controller.call(&method, data)),
                    Request::Values => {
                        let values: Vec<f64> = (0..count)
                            .map(|i| controller.value(i).unwrap_or(0.0))
                            .collect();
                        Some(Ok(serde_json::to_vec(&values)?))
                    }
                    Request::Quit => break 'serve,
                };
                if let Some(reply) = reply {
                    // A blocking write: answers can be large.
                    stream.set_write_timeout(Some(STATE_LIMIT))?;
                    match reply {
                        Ok(bytes) => answer(&mut stream, Ok(&bytes))?,
                        Err(err) => answer(&mut stream, Err(&format!("{err:#}")))?,
                    }
                }
            }
            controller.idle();
            // A device that has stopped working by itself (a script that
            // failed) says why, and its helper ends: the DAW shows it as
            // stopped, with that reason.
            if let Some(why) = controller.health() {
                header.set_reason(&why);
                break 'serve;
            }
            for change in controller.take_changes() {
                let head = header.change_head.load(Ordering::Relaxed);
                // A reader that has fallen a whole ring behind loses the oldest.
                shm.put_change(
                    head,
                    ChangeSlot {
                        index: change.index as u32,
                        edit: change.edit as u32,
                        value: change.value,
                    },
                );
                header
                    .change_head
                    .store(head.wrapping_add(1), Ordering::Release);
            }
            header
                .latency
                .store(controller.latency(), Ordering::Relaxed);
            header
                .editor_open
                .store(controller.editor_open() as u32, Ordering::Relaxed);
        }
        header.quit.store(1, Ordering::Release);
        futex_wake(&header.request);
        let _ = audio.join();
        controller.close_editor();
        Ok(())
    };
    match run() {
        Ok(()) => 0,
        Err(err) => {
            eprintln!("plugin-host: {err:#}");
            1
        }
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    fn answered(reply: Result<&[u8], &str>) -> String {
        let (mut ours, mut theirs) = UnixStream::pair().unwrap();
        answer(&mut ours, reply).unwrap();
        drop(ours);
        let mut bytes = Vec::new();
        theirs.read_to_end(&mut bytes).unwrap();
        hex(&bytes)
    }

    /// The bytes of each request and answer as they were before the
    /// protocol had types: a helper and a DAW of other versions still
    /// understand each other.
    #[test]
    fn the_wire_keeps_its_bytes() {
        let cases = [
            (
                Request::SetValue {
                    index: 3,
                    value: 0.5,
                },
                "0d0000000103000000000000000000e03f",
            ),
            (Request::SaveState, "0100000002"),
            (Request::LoadState(b"st\0ate"), "0700000003737400617465"),
            (Request::OpenEditor("Title é".into()), "09000000045469746c6520c3a9"),
            (Request::CloseEditor, "0100000005"),
            (Request::SetOffline(true), "020000000601"),
            (
                Request::Call {
                    method: "m".into(),
                    data: &[1, 2],
                },
                "05000000076d000102",
            ),
            (
                Request::ValueText {
                    index: 2,
                    value: 0.25,
                },
                "1c000000077061772e706172616d2e746578740002000000000000000000d03f",
            ),
            (
                Request::TextValue {
                    index: 2,
                    text: "-3 dB".into(),
                },
                "1a000000077061772e706172616d2e76616c756500020000002d33206442",
            ),
            (
                Request::Prepare {
                    method: "x".into(),
                    data: b"d",
                },
                "140000000773616e64626f782e7072657061726500780064",
            ),
            (Request::Quit, "0100000008"),
            (Request::Values, "0100000009"),
        ];
        for (request, today) in cases {
            let frame = request.frame();
            assert_eq!(hex(&frame), today, "{request:?}");
            let op = Op::try_from(frame[4]).unwrap();
            assert_eq!(Request::decode(op, &frame[5..]), Some(request));
        }
        assert_eq!(answered(Ok(b"yes")), "0400000000796573");
        assert_eq!(answered(Err("no")), "03000000016e6f");
    }

    /// The helper's first word, with numbers that are not finite: JSON has
    /// no word for them, so they cross as null and arrive as 0.
    #[test]
    fn the_first_word_keeps_its_bytes() {
        let params = vec![
            ParamInfo {
                id: "7".into(),
                group: "Osc 1".into(),
                min: f32::NAN,
                max: f32::INFINITY,
                default: 0.1,
                ..ParamInfo::choice("Wave", &["Sine", "Saw"], 1)
            },
            ParamInfo::new("Gain", -24.0, 24.0, f32::NEG_INFINITY, "dB"),
        ];
        let hello = Hello {
            params: params.clone(),
            values: vec![0.5, f64::NAN],
            has_editor: true,
            follows_state: false,
            sidechain: true,
            outputs: vec!["Aux".into()],
        };
        let today = concat!(
            r#"{"follows_state":false,"has_editor":true,"outputs":["Aux"],"params":["#,
            r#"{"automatable":true,"boolean":false,"choices":["Sine","Saw"],"default":0.10000000149011612,"#,
            r#""enumeration":true,"group":"Osc 1","id":"7","key":"Wave","max":null,"min":null,"name":"Wave","#,
            r#""per_note":false,"read_only":false,"steps":1,"unit":""},"#,
            r#"{"automatable":true,"boolean":false,"choices":[],"default":null,"enumeration":false,"#,
            r#""group":"","id":"","key":"Gain","max":24.0,"min":-24.0,"name":"Gain","per_note":false,"#,
            r#""read_only":false,"steps":0,"unit":"dB"}],"sidechain":true,"values":[0.5,null]}"#,
        );
        assert_eq!(String::from_utf8(hello.to_vec().unwrap()).unwrap(), today);
        let read: Hello = serde_json::from_str(today).unwrap();
        let finite = |mut p: ParamInfo| {
            for n in [&mut p.min, &mut p.max, &mut p.default] {
                if !n.is_finite() {
                    *n = 0.0;
                }
            }
            p
        };
        assert_eq!(read.params, params.into_iter().map(finite).collect::<Vec<_>>());
        assert_eq!(read.values, [0.5, 0.0]);
    }
}
