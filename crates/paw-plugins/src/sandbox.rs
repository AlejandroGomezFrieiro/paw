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

use std::io::{Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow, bail};
use paw_engine::device::{
    Controller, Device, DeviceFactory, DeviceInfo, Instance, Io, ParamInfo, Ports, Rest,
    Starting,
};
use paw_engine::{Event, MAX_PAIRS, ProcessCtx, Registry};
use serde_json::{Value, json};

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
        .filter(|info| matches!(info.format.as_str(), "clap" | "lv2" | "vst3"))
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
    // One block's context.
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
    reason: [u8; REASON],
}

impl Header {
    /// The reason the helper gave for ending, if it gave one.
    fn reason(&self) -> Option<String> {
        let len = (self.reason_len.load(Ordering::Acquire) as usize).min(REASON);
        (len > 0).then(|| String::from_utf8_lossy(&self.reason[..len]).into_owned())
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
struct Change {
    index: u32,
    value: f64,
}

/// The mapping, and where each part of it is.
struct Shm {
    base: *mut u8,
    len: usize,
    max_block: usize,
    fd: OwnedFd,
}

// Each part is used by one thread on each side, in turn, as the header says.
unsafe impl Send for Shm {}
unsafe impl Sync for Shm {}

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
        let messages = align(changes + CHANGES * std::mem::size_of::<Change>());
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
        let fd = unsafe { libc::memfd_create(c"paw-plugin".as_ptr(), libc::MFD_CLOEXEC) };
        if fd < 0 {
            bail!("no shared memory: {}", std::io::Error::last_os_error());
        }
        let fd = unsafe { OwnedFd::from_raw_fd(fd) };
        if unsafe { libc::ftruncate(fd.as_raw_fd(), len as libc::off_t) } != 0 {
            bail!("no shared memory: {}", std::io::Error::last_os_error());
        }
        let shm = Self::map(fd, max_block)?;
        let header = shm.header_mut();
        header.magic = MAGIC;
        header.max_block = max_block as u32;
        Ok(shm)
    }

    fn map(fd: OwnedFd, max_block: usize) -> Result<Self> {
        let len = Self::layout(max_block).len;
        let base = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                len,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                fd.as_raw_fd(),
                0,
            )
        };
        if base == libc::MAP_FAILED {
            bail!("mapping shared memory: {}", std::io::Error::last_os_error());
        }
        Ok(Self {
            base: base.cast(),
            len,
            max_block,
            fd,
        })
    }

    fn header(&self) -> &Header {
        unsafe { &*self.base.cast::<Header>() }
    }

    #[allow(clippy::mut_from_ref)]
    fn header_mut(&self) -> &mut Header {
        unsafe { &mut *self.base.cast::<Header>() }
    }

    #[allow(clippy::mut_from_ref)]
    fn part<T>(&self, offset: usize, count: usize) -> &mut [T] {
        unsafe { std::slice::from_raw_parts_mut(self.base.add(offset).cast::<T>(), count) }
    }

    fn left(&self) -> &mut [f32] {
        self.part(Self::layout(self.max_block).left, self.max_block)
    }

    fn right(&self) -> &mut [f32] {
        self.part(Self::layout(self.max_block).right, self.max_block)
    }

    /// The side-chain's two channels.
    fn key(&self) -> (&mut [f32], &mut [f32]) {
        let at = Self::layout(self.max_block).key;
        (
            self.part(at, self.max_block),
            self.part(at + self.max_block * 4, self.max_block),
        )
    }

    /// One channel of a further output pair: `pair` 0 is the second.
    fn out(&self, pair: usize, channel: usize) -> &mut [f32] {
        let at = Self::layout(self.max_block).outs + (pair * 2 + channel) * self.max_block * 4;
        self.part(at, self.max_block)
    }

    fn events(&self) -> &mut [Event] {
        self.part(Self::layout(self.max_block).events, EVENTS)
    }

    fn params(&self) -> &mut [ParamMove] {
        self.part(Self::layout(self.max_block).params, PARAMS)
    }

    fn changes(&self) -> &mut [Change] {
        self.part(Self::layout(self.max_block).changes, CHANGES)
    }

    fn messages(&self) -> &mut [u8] {
        self.part(Self::layout(self.max_block).messages, MESSAGES)
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
        unsafe {
            libc::munmap(self.base.cast(), self.len);
        }
    }
}

fn futex_wake(word: &AtomicU32) {
    unsafe {
        libc::syscall(
            libc::SYS_futex,
            word.as_ptr(),
            libc::FUTEX_WAKE,
            i32::MAX,
            std::ptr::null::<libc::timespec>(),
        );
    }
}

/// Sleep until `word` is no longer `seen`, or `limit` has passed.
fn futex_wait(word: &AtomicU32, seen: u32, limit: Duration) {
    let time = libc::timespec {
        tv_sec: limit.as_secs() as libc::time_t,
        tv_nsec: limit.subsec_nanos() as libc::c_long,
    };
    unsafe {
        libc::syscall(
            libc::SYS_futex,
            word.as_ptr(),
            libc::FUTEX_WAIT,
            seen,
            &time,
        );
    }
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
            let head = shm.header_mut();
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
        }
        shm.left()[..frames].copy_from_slice(&io.left[..frames]);
        shm.right()[..frames].copy_from_slice(&io.right[..frames]);
        if let Some([l, r]) = io.sidechain {
            let (key_l, key_r) = shm.key();
            key_l[..frames].copy_from_slice(&l[..frames]);
            key_r[..frames].copy_from_slice(&r[..frames]);
        }
        shm.events()[..count].copy_from_slice(&events[..count]);
        shm.params()[..self.moves.len()].copy_from_slice(&self.moves);
        self.moves.clear();
        shm.messages()[..self.messages.len()].copy_from_slice(&self.messages);
        self.messages.clear();

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
        io.left[..frames].copy_from_slice(&shm.left()[..frames]);
        io.right[..frames].copy_from_slice(&shm.right()[..frames]);
        for (pair, out) in io.outputs.iter_mut().take(MAX_PAIRS - 1).enumerate() {
            if let Some([l, r]) = out {
                l[..frames].copy_from_slice(&shm.out(pair, 0)[..frames]);
                r[..frames].copy_from_slice(&shm.out(pair, 1)[..frames]);
            }
        }
        self.rest.end(header.resting != 0);
        let out = (header.events_out as usize).min(EVENTS);
        io.events.clear();
        for event in &shm.events()[..out] {
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

// --- the DAW's side: the main thread ---------------------------------------------

// Requests. Those that are answered get `[length][0 or 1][payload]` back,
// 1 with the reason when the plugin refused.
const SET_VALUE: u8 = 1;
const SAVE_STATE: u8 = 2;
const LOAD_STATE: u8 = 3;
const OPEN_EDITOR: u8 = 4;
const CLOSE_EDITOR: u8 = 5;
const SET_OFFLINE: u8 = 6;
const CALL: u8 = 7;
const QUIT: u8 = 8;
const VALUES: u8 = 9;

fn send(stream: &mut UnixStream, op: u8, payload: &[u8]) -> std::io::Result<()> {
    let mut frame = Vec::with_capacity(payload.len() + 5);
    frame.extend_from_slice(&(payload.len() as u32 + 1).to_le_bytes());
    frame.push(op);
    frame.extend_from_slice(payload);
    stream.write_all(&frame)
}

/// Read one frame: its first byte and the rest.
fn receive(stream: &mut UnixStream) -> std::io::Result<(u8, Vec<u8>)> {
    let mut length = [0u8; 4];
    stream.read_exact(&mut length)?;
    let length = u32::from_le_bytes(length) as usize;
    if length == 0 || length > 1 << 30 {
        return Err(std::io::Error::other("a frame of an impossible size"));
    }
    let mut frame = vec![0u8; length];
    stream.read_exact(&mut frame)?;
    let rest = frame.split_off(1);
    Ok((frame[0], rest))
}

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
    pending: Vec<(usize, f64)>,
    /// Why the helper is gone, once it is.
    ended: Option<String>,
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
    fn end(&mut self, why: String) {
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
        unsafe {
            libc::kill(-(self.child.id() as libc::pid_t), libc::SIGKILL);
        }
        let _ = self.child.kill();
        let _ = self.child.wait();
    }

    /// How the helper ended, if it has: the reason it gave, or how its
    /// process ended.
    fn exited(&mut self) -> Option<String> {
        match self.child.try_wait() {
            Ok(Some(status)) => Some(
                self.link
                    .shm
                    .header()
                    .reason()
                    .unwrap_or_else(|| describe(status)),
            ),
            _ => None,
        }
    }

    /// Ask the helper for something and wait for its answer, but not
    /// longer than `limit`.
    fn ask(&mut self, op: u8, payload: &[u8], limit: Duration) -> Result<Vec<u8>> {
        if let Some(why) = &self.ended {
            bail!("{} is not running: {why}", self.name);
        }
        let outcome = (|| -> std::io::Result<(u8, Vec<u8>)> {
            send(&mut self.stream, op, payload)?;
            self.stream.set_read_timeout(Some(limit))?;
            receive(&mut self.stream)
        })();
        match outcome {
            Ok((0, answer)) => Ok(answer),
            Ok((_, reason)) => bail!("{}", String::from_utf8_lossy(&reason)),
            Err(err) => {
                let why = match self.exited() {
                    Some(how) => how,
                    None if matches!(
                        err.kind(),
                        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                    ) =>
                    {
                        format!(
                            "it did not answer for {} seconds and was ended",
                            limit.as_secs()
                        )
                    }
                    None => format!("the connection to it broke ({err})"),
                };
                self.end(why.clone());
                bail!("{} stopped: {why}", self.name)
            }
        }
    }

    /// Tell the helper something that needs no answer.
    fn tell(&mut self, op: u8, payload: &[u8]) {
        if self.ended.is_none() && send(&mut self.stream, op, payload).is_err() {
            let why = self
                .exited()
                .unwrap_or_else(|| "the connection to it broke".into());
            self.end(why);
        }
    }

    fn refresh_values(&mut self) {
        if let Ok(answer) = self.ask(VALUES, &[], QUICK_LIMIT)
            && let Ok(Value::Array(values)) = serde_json::from_slice::<Value>(&answer)
        {
            for (slot, value) in self.values.iter_mut().zip(values) {
                *slot = value.as_f64().unwrap_or(*slot);
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
    let per_second = unsafe { libc::sysconf(libc::_SC_CLK_TCK) }.max(1) as u64;
    Some(Duration::from_nanos(ticks * 1_000_000_000 / per_second))
}

fn describe(status: std::process::ExitStatus) -> String {
    use std::os::unix::process::ExitStatusExt;
    match (status.signal(), status.code()) {
        (Some(libc::SIGSEGV), _) => "it crashed (a memory fault)".into(),
        (Some(libc::SIGABRT), _) => "it crashed (it aborted)".into(),
        (Some(libc::SIGKILL), _) => "it was killed".into(),
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
        let mut payload = Vec::with_capacity(12);
        payload.extend_from_slice(&(index as u32).to_le_bytes());
        payload.extend_from_slice(&value.to_le_bytes());
        self.tell(SET_VALUE, &payload);
    }

    fn save_state(&mut self) -> Result<Option<Vec<u8>>> {
        let mut answer = self.ask(SAVE_STATE, &[], STATE_LIMIT)?;
        if answer.is_empty() || answer[0] == 0 {
            return Ok(None);
        }
        Ok(Some(answer.split_off(1)))
    }

    fn load_state(&mut self, state: &[u8]) -> Result<()> {
        self.ask(LOAD_STATE, state, STATE_LIMIT)?;
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
            let change = shm.changes()[tail as usize % CHANGES];
            if let Some(slot) = self.values.get_mut(change.index as usize) {
                *slot = change.value;
                self.pending.push((change.index as usize, change.value));
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
            for (index, (old, new)) in before.iter().zip(&self.values).enumerate() {
                if old != new {
                    self.pending.push((index, *new));
                }
            }
        }
    }

    fn take_changes(&mut self) -> Vec<(usize, f64)> {
        std::mem::take(&mut self.pending)
    }

    fn value_text(&mut self, index: usize, value: f64) -> Option<String> {
        let mut payload = PARAM_TEXT.as_bytes().to_vec();
        payload.push(0);
        payload.extend_from_slice(&(index as u32).to_le_bytes());
        payload.extend_from_slice(&value.to_le_bytes());
        let answer = self.ask(CALL, &payload, QUICK_LIMIT).ok()?;
        (!answer.is_empty()).then(|| String::from_utf8_lossy(&answer).into_owned())
    }

    fn text_value(&mut self, index: usize, text: &str) -> Option<f64> {
        let mut payload = PARAM_VALUE.as_bytes().to_vec();
        payload.push(0);
        payload.extend_from_slice(&(index as u32).to_le_bytes());
        payload.extend_from_slice(text.as_bytes());
        let answer = self.ask(CALL, &payload, QUICK_LIMIT).ok()?;
        let bytes: [u8; 8] = answer.get(..8)?.try_into().ok()?;
        Some(f64::from_le_bytes(bytes))
    }

    fn has_editor(&self) -> bool {
        self.has_editor
    }

    fn editor_open(&self) -> bool {
        self.ended.is_none() && self.link.shm.header().editor_open.load(Ordering::Relaxed) != 0
    }

    fn open_editor(&mut self, title: &str) -> Result<()> {
        self.ask(OPEN_EDITOR, title.as_bytes(), STATE_LIMIT)
            .map(|_| ())
    }

    fn close_editor(&mut self) {
        self.tell(CLOSE_EDITOR, &[]);
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
        self.tell(SET_OFFLINE, &[offline as u8]);
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
        let mut payload = method.as_bytes().to_vec();
        payload.push(0);
        payload.extend_from_slice(data);
        let answer = self.ask(CALL, &payload, STATE_LIMIT)?;
        self.link.wake.store(true, Ordering::Relaxed);
        self.reread = Some(self.link.answered.load(Ordering::Relaxed));
        // A preset sets the plugin's parameters anew.
        if method == "preset.load" {
            self.refresh_values();
        }
        Ok(answer)
    }

    fn late_blocks(&self) -> u64 {
        self.link.late.load(Ordering::Relaxed) as u64
    }

    fn prepare(&mut self, method: &str, data: &[u8]) -> Result<Option<Vec<u8>>> {
        let mut payload = PREPARE.as_bytes().to_vec();
        payload.push(0);
        payload.extend_from_slice(method.as_bytes());
        payload.push(0);
        payload.extend_from_slice(data);
        let mut answer = self.ask(CALL, &payload, STATE_LIMIT)?;
        if answer.first() != Some(&1) {
            return Ok(None);
        }
        Ok(Some(answer.split_off(1)))
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
            self.end(why.unwrap_or_else(|| "it did not answer a block of the render in time and was ended".into()));
        } else if answered != answered_before {
            self.stalled_since = None;
        } else if late != late_before || self.stalled_since.is_some() {
            let since = *self.stalled_since.get_or_insert_with(Instant::now);
            if since.elapsed() >= STALL_LIMIT {
                self.end(format!(
                    "it stopped answering (no block for {} seconds) and was ended",
                    STALL_LIMIT.as_secs()
                ));
            }
        }
        self.ended.clone()
    }
}

impl Drop for RemoteController {
    fn drop(&mut self) {
        if self.ended.is_none() {
            self.link.shm.header().quit.store(1, Ordering::Release);
            futex_wake(&self.link.shm.header().request);
            let _ = send(&mut self.stream, QUIT, &[]);
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

fn param_from(value: &Value) -> ParamInfo {
    let text = |key: &str| value[key].as_str().unwrap_or_default().to_string();
    let number = |key: &str| value[key].as_f64().unwrap_or(0.0) as f32;
    let flag = |key: &str, or: bool| value[key].as_bool().unwrap_or(or);
    ParamInfo {
        key: text("key"),
        id: text("id"),
        name: text("name"),
        group: text("group"),
        min: number("min"),
        max: number("max"),
        default: number("default"),
        unit: text("unit"),
        choices: value["choices"]
            .as_array()
            .map(|list| {
                list.iter()
                    .map(|c| c.as_str().unwrap_or_default().to_string())
                    .collect()
            })
            .unwrap_or_default(),
        steps: value["steps"].as_u64().unwrap_or(0) as u32,
        boolean: flag("boolean", false),
        enumeration: flag("enumeration", false),
        automatable: flag("automatable", true),
        read_only: flag("read_only", false),
        per_note: flag("per_note", false),
    }
}

fn param_to(param: &ParamInfo) -> Value {
    json!({
        "key": param.key, "id": param.id, "name": param.name, "group": param.group,
        "min": param.min, "max": param.max, "default": param.default, "unit": param.unit,
        "choices": param.choices, "steps": param.steps, "boolean": param.boolean,
        "enumeration": param.enumeration, "automatable": param.automatable,
        "read_only": param.read_only, "per_note": param.per_note,
    })
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
        if TEST_HANG.load(Ordering::Relaxed) {
            command.env("PAW_PLUGIN_TEST_HANG", "1");
        }
        if let Some(cache) = CACHE.lock().unwrap().as_ref() {
            command.arg(cache);
        }
        unsafe {
            command.pre_exec(move || {
                // The helper is handed the socket and the memory, and is
                // told to finish if this program ends first.
                libc::fcntl(sock_fd, libc::F_SETFD, 0);
                libc::fcntl(shm_fd, libc::F_SETFD, 0);
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                // A group of its own, so that what the plugin starts in
                // turn (a bridge to Wine) can be ended along with it.
                libc::setpgid(0, 0);
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
    fn made(&self, mut controller: RemoteController, made: &Value) -> Instance {
        controller.params = made["params"]
            .as_array()
            .map(|list| list.iter().map(param_from).collect())
            .unwrap_or_default();
        controller.values = made["values"]
            .as_array()
            .map(|list| list.iter().map(|v| v.as_f64().unwrap_or(0.0)).collect())
            .unwrap_or_default();
        controller.values.resize(controller.params.len(), 0.0);
        controller.has_editor = made["has_editor"].as_bool().unwrap_or(false);
        controller.follows_state = made["follows_state"].as_bool().unwrap_or(false);
        controller.ports = Ports {
            sidechain: made["sidechain"].as_bool().unwrap_or(false),
            outputs: made["outputs"]
                .as_array()
                .map(|list| {
                    list.iter()
                        .map(|n| n.as_str().unwrap_or_default().to_string())
                        .collect()
                })
                .unwrap_or_default(),
        };
        Instance {
            device: Box::new(RemoteDevice {
                link: controller.link.clone(),
                instrument: self.info.category == "instrument",
                seq: 0,
                outstanding: false,
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

/// What the thread that waits for a helper found.
enum Heard {
    /// The plugin is made (its first word), and its state loaded.
    Made(Value),
    /// The plugin refused, saying why.
    Refused(String),
    /// No answer in time while it was being made (true) or loading its state.
    Silent(bool),
    /// The connection broke.
    Broken(String),
}

/// A plugin being made in its helper while a thread of ours waits for it.
struct RemoteStarting {
    factory: RemoteFactory,
    controller: Option<RemoteController>,
    answer: std::sync::mpsc::Receiver<Heard>,
    limit: Duration,
}

impl Starting for RemoteStarting {
    fn poll(&mut self) -> Option<Result<Instance>> {
        let heard = match self.answer.try_recv() {
            Ok(heard) => heard,
            Err(std::sync::mpsc::TryRecvError::Empty) => return None,
            Err(std::sync::mpsc::TryRecvError::Disconnected) => {
                Heard::Broken("the thread waiting for it ended".into())
            }
        };
        let mut controller = self.controller.take()?;
        let name = &self.factory.info.name;
        let why = match heard {
            Heard::Made(mut made) => {
                // The values its state brought, where it was given one.
                if let Some(values) = made.get_mut("values_now").map(Value::take) {
                    made["values"] = values;
                }
                return Some(Ok(self.factory.made(controller, &made)));
            }
            Heard::Refused(reason) => {
                controller.end(reason.clone());
                return Some(Err(anyhow!("{reason}")));
            }
            Heard::Silent(making) => controller.exited().unwrap_or_else(|| {
                if making {
                    format!(
                        "it did not answer for {} seconds while it was being made, and was ended",
                        self.limit.as_secs()
                    )
                } else {
                    format!(
                        "it did not load its state within {} seconds, and was ended",
                        STATE_LIMIT.as_secs()
                    )
                }
            }),
            Heard::Broken(err) => controller
                .exited()
                .unwrap_or_else(|| format!("the connection to it broke ({err})")),
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
    tell: std::sync::mpsc::Sender<Heard>,
) {
    let heard = (|| {
        let fail = |err: std::io::Error, making| {
            if silence(&err) {
                Heard::Silent(making)
            } else {
                Heard::Broken(err.to_string())
            }
        };
        if let Err(err) = stream.set_read_timeout(Some(limit)) {
            return Heard::Broken(err.to_string());
        }
        let mut made = match receive(&mut stream) {
            Ok((0, answer)) => match serde_json::from_slice::<Value>(&answer) {
                Ok(made) => made,
                Err(err) => return Heard::Broken(format!("its first word made no sense: {err}")),
            },
            Ok((_, reason)) => return Heard::Refused(String::from_utf8_lossy(&reason).into()),
            Err(err) => return fail(err, true),
        };
        let Some(state) = state else {
            return Heard::Made(made);
        };
        let _ = stream.set_read_timeout(Some(STATE_LIMIT));
        let loaded = send(&mut stream, LOAD_STATE, &state).and_then(|_| receive(&mut stream));
        match loaded {
            Ok((0, _)) => {}
            Ok((_, reason)) => {
                return Heard::Refused(format!(
                    "could not restore its state: {}",
                    String::from_utf8_lossy(&reason)
                ));
            }
            Err(err) => return fail(err, false),
        }
        // The values the state brought with it.
        let _ = stream.set_read_timeout(Some(QUICK_LIMIT));
        if let Ok((0, answer)) = send(&mut stream, VALUES, &[]).and_then(|_| receive(&mut stream))
            && let Ok(values @ Value::Array(_)) = serde_json::from_slice::<Value>(&answer)
        {
            made["values_now"] = values;
        }
        Heard::Made(made)
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
        let made = match receive(&mut ours) {
            Ok((0, answer)) => serde_json::from_slice::<Value>(&answer)
                .map_err(|err| anyhow!("the helper's first word made no sense: {err}"))?,
            Ok((_, reason)) => bail!("{}", String::from_utf8_lossy(&reason)),
            Err(err) => {
                let why = controller.exited().unwrap_or_else(|| {
                    if silence(&err) {
                        format!(
                            "it did not answer for {} seconds while it was being made, and was ended",
                            limit.as_secs()
                        )
                    } else {
                        format!("the connection to it broke ({err})")
                    }
                });
                controller.end(why.clone());
                bail!("{} could not be started: {why}", self.info.name)
            }
        };
        Ok(self.made(controller, &made))
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
            limit,
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
            let mut param: libc::sched_param = unsafe { std::mem::zeroed() };
            param.sched_priority = wanted.1 as i32;
            unsafe {
                libc::pthread_setschedparam(libc::pthread_self(), wanted.0 as i32, &param);
            }
        }
        let frames = (header.frames as usize).min(shm.max_block);
        for mv in &shm.params()[..(header.params_in as usize).min(PARAMS)] {
            device.set_param(mv.index, mv.value);
        }
        events.clear();
        for event in &shm.events()[..(header.events_in as usize).min(EVENTS)] {
            events.push(*event);
        }
        let messages = &shm.messages()[..(header.messages_in as usize).min(MESSAGES)];
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
            sample_rate: header.sample_rate,
            tempo: header.tempo,
            sig_num: header.sig_num,
            sig_den: header.sig_den,
            playing: header.playing != 0,
            position: header.position,
            seconds: header.seconds,
            bar: header.bar,
            bar_start: header.bar_start,
        };
        {
            let (left, right) = (shm.left(), shm.right());
            let (key_l, key_r) = shm.key();
            let wanted = header.outs;
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
                sidechain: (header.keyed != 0).then_some([&key_l[..frames], &key_r[..frames]]),
                outputs: &mut outs[..pairs.min(MAX_PAIRS - 1)],
            };
            device.process(&ctx, &mut io);
            for (pair, out) in outs.iter().enumerate() {
                if let Some([l, r]) = out {
                    shm.out(pair, 0)[..frames].copy_from_slice(&l[..frames]);
                    shm.out(pair, 1)[..frames].copy_from_slice(&r[..frames]);
                }
            }
        }
        let out = events.as_slice();
        let count = out.len().min(EVENTS);
        shm.events()[..count].copy_from_slice(&out[..count]);
        shm.header_mut().events_out = count as u32;
        shm.header_mut().resting = device.resting() as u32;
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
                send(&mut stream, 1, format!("{err:#}").as_bytes())?;
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
        let hello = json!({
            "params": params.iter().map(param_to).collect::<Vec<_>>(),
            "values": values,
            "has_editor": controller.has_editor(),
            "follows_state": controller.follows_state(),
            "sidechain": ports.sidechain,
            "outputs": ports.outputs,
        });
        shm.header()
            .latency
            .store(controller.latency(), Ordering::Relaxed);
        send(&mut stream, 0, &serde_json::to_vec(&hello)?)?;

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
                let (op, payload) = (frame[0], &frame[1..]);
                let answer: Option<Result<Vec<u8>>> = match op {
                    SET_VALUE if payload.len() >= 12 => {
                        let index = u32::from_le_bytes(payload[..4].try_into().unwrap()) as usize;
                        let value = f64::from_le_bytes(payload[4..12].try_into().unwrap());
                        controller.set_value(index, value);
                        None
                    }
                    SAVE_STATE => Some(controller.save_state().map(|state| match state {
                        Some(mut bytes) => {
                            bytes.insert(0, 1);
                            bytes
                        }
                        None => vec![0],
                    })),
                    LOAD_STATE => Some(controller.load_state(payload).map(|_| Vec::new())),
                    OPEN_EDITOR => Some(
                        controller
                            .open_editor(&String::from_utf8_lossy(payload))
                            .map(|_| Vec::new()),
                    ),
                    CLOSE_EDITOR => {
                        controller.close_editor();
                        None
                    }
                    SET_OFFLINE => {
                        controller.set_offline(payload.first() == Some(&1));
                        None
                    }
                    CALL => {
                        let split = payload
                            .iter()
                            .position(|b| *b == 0)
                            .unwrap_or(payload.len());
                        let method = String::from_utf8_lossy(&payload[..split]).into_owned();
                        let data = payload.get(split + 1..).unwrap_or(&[]);
                        let index = data
                            .get(..4)
                            .map(|b| u32::from_le_bytes(b.try_into().unwrap()) as usize);
                        if method == "sandbox.hang" {
                            TEST_HANG.store(data != b"0", Ordering::Relaxed);
                            Some(Ok(Vec::new()))
                        } else if method == PREPARE {
                            let split = data.iter().position(|b| *b == 0).unwrap_or(data.len());
                            let inner = String::from_utf8_lossy(&data[..split]).into_owned();
                            let rest = data.get(split + 1..).unwrap_or(&[]);
                            Some(controller.prepare(&inner, rest).map(|message| match message {
                                Some(mut bytes) => {
                                    bytes.insert(0, 1);
                                    bytes
                                }
                                None => vec![0],
                            }))
                        } else if method == PARAM_TEXT
                            && let (Some(index), Some(value)) = (index, data.get(4..12))
                        {
                            let value = f64::from_le_bytes(value.try_into().unwrap());
                            let text = controller.value_text(index, value).unwrap_or_default();
                            Some(Ok(text.into_bytes()))
                        } else if method == PARAM_VALUE
                            && let Some(index) = index
                        {
                            let text = String::from_utf8_lossy(&data[4..]);
                            Some(Ok(controller
                                .text_value(index, &text)
                                .map(|v| v.to_le_bytes().to_vec())
                                .unwrap_or_default()))
                        } else {
                            Some(controller.call(&method, data))
                        }
                    }
                    VALUES => {
                        let values: Vec<f64> = (0..params.len())
                            .map(|i| controller.value(i).unwrap_or(0.0))
                            .collect();
                        Some(Ok(serde_json::to_vec(&values)?))
                    }
                    QUIT => break 'serve,
                    _ => None,
                };
                if let Some(answer) = answer {
                    // A blocking write: answers can be large.
                    stream.set_write_timeout(Some(STATE_LIMIT))?;
                    match answer {
                        Ok(bytes) => send(&mut stream, 0, &bytes)?,
                        Err(err) => send(&mut stream, 1, format!("{err:#}").as_bytes())?,
                    }
                }
            }
            controller.idle();
            // A device that has stopped working by itself (a script that
            // failed) says why, and its helper ends: the DAW shows it as
            // stopped, with that reason.
            if let Some(why) = controller.health() {
                let bytes = why.as_bytes();
                let len = bytes.len().min(REASON);
                shm.header_mut().reason[..len].copy_from_slice(&bytes[..len]);
                header.reason_len.store(len as u32, Ordering::Release);
                break 'serve;
            }
            for (index, value) in controller.take_changes() {
                let head = header.change_head.load(Ordering::Relaxed);
                // A reader that has fallen a whole ring behind loses the oldest.
                shm.changes()[head as usize % CHANGES] = Change {
                    index: index as u32,
                    value,
                };
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
