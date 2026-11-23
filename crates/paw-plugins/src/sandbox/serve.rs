//! The helper's side: the plugin-host process.

use std::io::Read;
use std::ops::ControlFlow;
use std::os::fd::{FromRawFd, OwnedFd, RawFd};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use paw_engine::device::{Controller, Device, Instance, Io, ParamInfo};
use paw_engine::{MAX_PAIRS, ProcessCtx, Registry};
use super::*;
use super::shm::*;
use super::wire::*;

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
fn audio_loop(shm: Arc<Shm>, device: Box<dyn Device>) {
    paw_engine::no_denormals();
    let header = shm.header();
    let mut turn = shm.turn();
    let mut audio = AudioSide::new(device, shm.max_block);
    let mut seen = 0u32;
    let mut scheduling = (0u32, 0u32);
    while let Some(asked) = wait_for_block(header, seen) {
        follow_scheduling(header, &mut scheduling);
        audio.run(&mut shm.block(&mut turn));
        seen = asked;
        header.done.store(asked, Ordering::Release);
        futex_wake(&header.done);
    }
}

/// Wait until the DAW asks for a block after `seen`, and return its number;
/// `None` when the DAW says to quit.
fn wait_for_block(header: &Header, seen: u32) -> Option<u32> {
    loop {
        let asked = header.request.load(Ordering::Acquire);
        if header.quit.load(Ordering::Acquire) != 0 {
            return None;
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
        return Some(asked);
    }
}

/// Run as the DAW's audio thread does, where the system allows it: take
/// the scheduling policy and priority that the DAW put in the header, when
/// they differ from `current`.
fn follow_scheduling(header: &Header, current: &mut (u32, u32)) {
    let wanted = (
        header.policy.load(Ordering::Relaxed),
        header.priority.load(Ordering::Relaxed),
    );
    if wanted == *current {
        return;
    }
    *current = wanted;
    // libc: rustix has no wrapper for pthread_setschedparam.
    // SAFETY: `sched_param` is a plain C struct of integers, for which all-zero bytes is a valid value.
    let mut param: libc::sched_param = unsafe { std::mem::zeroed() };
    param.sched_priority = wanted.1 as i32;
    // SAFETY: `pthread_self` is the calling thread and `param` is a live local; a refused change
    // (no right to set the priority) is reported by the return value, which is ignored on purpose.
    unsafe {
        libc::pthread_setschedparam(libc::pthread_self(), wanted.0 as i32, &param);
    }
}

/// The block's transport, as the device reads it.
fn process_ctx(head: &BlockContext) -> ProcessCtx {
    ProcessCtx {
        sample_rate: head.sample_rate,
        tempo: head.tempo,
        sig_num: head.sig_num,
        sig_den: head.sig_den,
        playing: head.playing != 0,
        position: head.position,
        seconds: head.seconds,
        bar: head.bar,
        bar_start: head.bar_start,
    }
}

/// What the helper's audio thread keeps from one block to the next, all
/// made before the first block: a block allocates nothing.
struct AudioSide {
    device: Box<dyn Device>,
    max_block: usize,
    events: paw_engine::EventBuf,
    /// The further output pairs, filled by the plugin and then copied over;
    /// those not asked for are put `aside` while it runs.
    outs: Vec<Option<[Vec<f32>; 2]>>,
    aside: Vec<Option<[Vec<f32>; 2]>>,
}

impl AudioSide {
    fn new(device: Box<dyn Device>, max_block: usize) -> Self {
        Self {
            device,
            max_block,
            events: paw_engine::EventBuf::with_capacity(EVENTS),
            outs: (0..MAX_PAIRS - 1)
                .map(|_| Some([vec![0.0; max_block], vec![0.0; max_block]]))
                .collect(),
            aside: (0..MAX_PAIRS - 1).map(|_| None).collect(),
        }
    }

    /// One block: what came with it in, the plugin's processing, and what
    /// it made out.
    fn run(&mut self, block: &mut Block) {
        let frames = (block.context.frames as usize).min(self.max_block);
        self.take_params(block);
        self.take_events(block);
        self.take_messages(block);
        let ctx = process_ctx(block.context);
        self.process(block, &ctx, frames);
        self.give_events(block);
    }

    fn take_params(&mut self, block: &Block) {
        for mv in &block.params[..(block.context.params_in as usize).min(PARAMS)] {
            self.device.set_param(mv.index, mv.value);
        }
    }

    fn take_events(&mut self, block: &Block) {
        self.events.clear();
        for event in &block.events[..(block.context.events_in as usize).min(EVENTS)] {
            self.events.push(*event);
        }
    }

    /// The block's messages, each its frame and its length in 4 bytes and
    /// then its bytes; a message cut short is passed over.
    fn take_messages(&mut self, block: &Block) {
        let messages = &block.messages[..(block.context.messages_in as usize).min(MESSAGES)];
        let mut at = 0;
        while let Some(head) = messages.get(at..at + 8) {
            let frame = u32::from_le_bytes(head[..4].try_into().unwrap());
            let len = u32::from_le_bytes(head[4..].try_into().unwrap()) as usize;
            if let Some(data) = messages.get(at + 8..at + 8 + len) {
                self.device.message(frame, data);
            }
            at += 8 + len;
        }
    }

    /// Let the plugin process the block in place, with the side-chain and
    /// the further output pairs that the DAW asked for.
    fn process(&mut self, block: &mut Block, ctx: &ProcessCtx, frames: usize) {
        let keyed = block.context.keyed != 0;
        let wanted = block.context.outs;
        let pairs = (u32::BITS - wanted.leading_zeros()) as usize;
        self.ready_outputs(wanted, frames);
        let Block {
            left, right, key: [key_l, key_r], ..
        } = &mut *block;
        let mut io = Io {
            left: &mut left[..frames],
            right: &mut right[..frames],
            events: &mut self.events,
            sidechain: keyed.then_some([&key_l[..frames], &key_r[..frames]]),
            outputs: &mut self.outs[..pairs.min(MAX_PAIRS - 1)],
        };
        self.device.process(ctx, &mut io);
        for (pair, out) in self.outs.iter().enumerate() {
            if let Some([l, r]) = out {
                block.out(pair, 0)[..frames].copy_from_slice(&l[..frames]);
                block.out(pair, 1)[..frames].copy_from_slice(&r[..frames]);
            }
        }
    }

    /// Put in `outs` the further output pairs that `wanted` asks for, a bit
    /// each, silent; the others aside.
    fn ready_outputs(&mut self, wanted: u32, frames: usize) {
        for (pair, (out, put)) in self.outs.iter_mut().zip(self.aside.iter_mut()).enumerate() {
            // Swapped, not made or freed: what is asked for is in `outs`.
            if (wanted >> pair & 1 != 0) != out.is_some() {
                std::mem::swap(out, put);
            }
            if let Some([l, r]) = out {
                l[..frames].fill(0.0);
                r[..frames].fill(0.0);
            }
        }
    }

    /// The events that the plugin made, and whether it is at rest.
    fn give_events(&mut self, block: &mut Block) {
        let out = self.events.as_slice();
        let count = out.len().min(EVENTS);
        block.events[..count].copy_from_slice(&out[..count]);
        block.context.events_out = count as u32;
        block.context.resting = self.device.resting() as u32;
    }
}

/// Run as a plugin's helper: `args` are the plugin's kind, the socket and
/// the shared memory handed over by the DAW, the sample rate, the largest
/// block, and the plugin cache to read. `dirs` says where to look for the
/// plugin: the program gives [`crate::PluginDirs::for_helper`]. Returns the
/// process's exit code.
///
/// # Safety
///
/// As for [`serve_with`]: the socket and the shared memory in `args` are
/// file descriptors that this process owns and that nothing else takes,
/// and no other thread is running yet.
pub unsafe fn serve(args: &[String], dirs: &crate::PluginDirs) -> i32 {
    let cache = args.get(5).map(PathBuf::from);
    let make = |kind: &str, rate: f32, max_block: usize| {
        let mut registry = Registry::default();
        crate::register(&mut registry, cache.as_deref(), dirs);
        registry
            .get(kind)
            .with_context(|| format!("no plugin `{kind}` here"))
            .and_then(|factory| factory.create(rate, max_block))
    };
    // SAFETY: The caller makes the same promises to this function.
    unsafe { serve_with(args, make) }
}

/// Run as the helper of a device that `make` makes from its kind, the
/// sample rate and the largest block, as [`serve`] does for plugins.
///
/// # Safety
///
/// `args[1]` (the socket) and `args[2]` (the shared memory) are the
/// numbers of open file descriptors that this process owns, inherited from
/// the DAW that started it, and that nothing else in the process uses or
/// closes: this takes ownership of them. No other thread is running yet,
/// since it repairs the display's environment ([`crate::repair_display_env`]).
pub unsafe fn serve_with(
    args: &[String],
    make: impl FnOnce(&str, f32, usize) -> Result<Instance>,
) -> i32 {
    // SAFETY: The caller makes the same promises to this function.
    match unsafe { run(args, make) } {
        Ok(()) => 0,
        Err(err) => {
            eprintln!("plugin-host: {err:#}");
            1
        }
    }
}

/// The helper from start to end: [`serve_with`] less its exit code.
///
/// # Safety
///
/// As for [`serve_with`].
unsafe fn run(args: &[String], make: impl FnOnce(&str, f32, usize) -> Result<Instance>) -> Result<()> {
    let [kind, sock, shm, rate, block, ..] = args else {
        bail!("usage: plugin-host <kind> <socket> <memory> <sample rate> <block> [cache]");
    };
    // SAFETY: The caller promised that `sock` names an open file descriptor that this process owns
    // and nothing else takes; it is taken once, here.
    let mut stream = unsafe { UnixStream::from_raw_fd(sock.parse::<RawFd>()?) };
    let max_block: usize = block.parse()?;
    let shm = Arc::new(Shm::map(
        // SAFETY: The caller promised that `shm` names an open file descriptor that this process
        // owns and nothing else takes; it is taken once, here.
        unsafe { OwnedFd::from_raw_fd(shm.parse::<RawFd>()?) },
        max_block,
    )?);
    if shm.header().magic != MAGIC {
        bail!("the shared memory is not the DAW's");
    }
    follow_test_env(kind);
    let instance = match make(kind, rate.parse()?, max_block) {
        Ok(instance) => instance,
        Err(err) => {
            answer(&mut stream, Err(&format!("{err:#}")))?;
            return Ok(());
        }
    };
    let controller = instance
        .controller
        .unwrap_or_else(|| Box::new(NoController));
    let mut helper = Helper::greet(controller, shm, stream)?;
    let audio = {
        let shm = helper.shm.clone();
        let device = instance.device;
        std::thread::Builder::new()
            .name("plugin-audio".into())
            .spawn(move || audio_loop(shm, device))?
    };
    helper.serve()?;
    let header = helper.shm.header();
    header.quit.store(1, Ordering::Release);
    futex_wake(&header.request);
    let _ = audio.join();
    helper.controller.close_editor();
    Ok(())
}

/// For tests: `PAW_PLUGIN_TEST_HANG` makes the audio thread stop answering
/// (see [`TEST_HANG`]), and `PAW_PLUGIN_HOST_HANG=<part of a kind>:<seconds>`
/// makes the helper of a matching plugin wait that long before it makes it,
/// as one that waits on a dead network mount does.
fn follow_test_env(kind: &str) {
    if std::env::var_os("PAW_PLUGIN_TEST_HANG").is_some() {
        TEST_HANG.store(true, Ordering::Relaxed);
    }
    if let Ok(hang) = std::env::var("PAW_PLUGIN_HOST_HANG")
        && let Some((part, secs)) = hang.rsplit_once(':')
        && kind.contains(part)
        && let Ok(secs) = secs.parse::<f64>()
    {
        std::thread::sleep(Duration::from_secs_f64(secs.clamp(0.0, 3600.0)));
    }
}

/// The helper's main thread: requests from the DAW, and the plugin's own
/// housekeeping (its editor's events among it) in between.
///
/// The fields drop in this order: the plugin before the shared memory and
/// the socket, so the DAW sees the socket close last.
struct Helper {
    controller: Box<dyn Controller>,
    shm: Arc<Shm>,
    stream: UnixStream,
    /// How many parameters the plugin said it has in its [`Hello`].
    count: usize,
}

impl Helper {
    /// Tell the DAW what the plugin is: its [`Hello`], and its latency in
    /// the header.
    fn greet(controller: Box<dyn Controller>, shm: Arc<Shm>, mut stream: UnixStream) -> Result<Self> {
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
        Ok(Self {
            count: hello.params.len(),
            controller,
            shm,
            stream,
        })
    }

    /// Serve until the DAW quits or goes, or the plugin stops working.
    fn serve(&mut self) -> Result<()> {
        self.stream.set_read_timeout(Some(Duration::from_millis(10)))?;
        let mut pending: Vec<u8> = Vec::new();
        loop {
            if self.read(&mut pending).is_break() {
                return Ok(());
            }
            while let Some(frame) = take_frame(&mut pending) {
                // A request this helper does not know, or one too short to
                // say what it asks, is passed over.
                let Some(request) = frame.split_first().and_then(|(&op, payload)| {
                    Request::decode(Op::try_from(op).ok()?, payload)
                }) else {
                    continue;
                };
                if self.handle(request)?.is_break() {
                    return Ok(());
                }
            }
            if self.housekeeping().is_break() {
                return Ok(());
            }
        }
    }

    /// Add what the DAW sent to `pending`, waiting up to the read time
    /// limit; break when the socket is closed or broken.
    fn read(&mut self, pending: &mut Vec<u8>) -> ControlFlow<()> {
        let mut chunk = [0u8; 65536];
        match self.stream.read(&mut chunk) {
            Ok(0) => return ControlFlow::Break(()),
            Ok(n) => pending.extend_from_slice(&chunk[..n]),
            Err(err)
                if matches!(
                    err.kind(),
                    std::io::ErrorKind::WouldBlock
                        | std::io::ErrorKind::TimedOut
                        | std::io::ErrorKind::Interrupted
                ) => {}
            Err(_) => return ControlFlow::Break(()),
        }
        ControlFlow::Continue(())
    }

    /// Do what one request asks, and answer it if it has an answer; break
    /// on [`Request::Quit`].
    fn handle(&mut self, request: Request) -> Result<ControlFlow<()>> {
        let controller = &mut self.controller;
        let reply = match request {
            Request::SetValue { index, value } => {
                controller.set_value(index as usize, value);
                return Ok(ControlFlow::Continue(()));
            }
            Request::CloseEditor => {
                controller.close_editor();
                return Ok(ControlFlow::Continue(()));
            }
            Request::SetOffline(offline) => {
                controller.set_offline(offline);
                return Ok(ControlFlow::Continue(()));
            }
            Request::Quit => return Ok(ControlFlow::Break(())),
            Request::SaveState => controller.save_state().map(optional),
            Request::LoadState(state) => controller.load_state(state).map(|()| Vec::new()),
            Request::OpenEditor(title) => controller.open_editor(&title).map(|()| Vec::new()),
            Request::ValueText { index, value } => Ok(controller
                .value_text(index as usize, value)
                .unwrap_or_default()
                .into_bytes()),
            Request::TextValue { index, text } => Ok(controller
                .text_value(index as usize, &text)
                .map(|v| v.to_le_bytes().to_vec())
                .unwrap_or_default()),
            Request::Prepare { method, data } => controller.prepare(&method, data).map(optional),
            Request::Call { method, data } if method == "sandbox.hang" => {
                TEST_HANG.store(data != b"0", Ordering::Relaxed);
                Ok(Vec::new())
            }
            Request::Call { method, data } => controller.call(&method, data),
            Request::Values => Ok(self.values()?),
        };
        self.reply(reply)?;
        Ok(ControlFlow::Continue(()))
    }

    /// The parameters' values, as a JSON array.
    fn values(&self) -> Result<Vec<u8>> {
        let values: Vec<f64> = (0..self.count)
            .map(|i| self.controller.value(i).unwrap_or(0.0))
            .collect();
        Ok(serde_json::to_vec(&values)?)
    }

    /// Answer a request, or say why it failed.
    fn reply(&mut self, reply: Result<Vec<u8>>) -> Result<()> {
        // A blocking write: answers can be large.
        self.stream.set_write_timeout(Some(STATE_LIMIT))?;
        match reply {
            Ok(bytes) => answer(&mut self.stream, Ok(&bytes))?,
            Err(err) => answer(&mut self.stream, Err(&format!("{err:#}")))?,
        }
        Ok(())
    }

    /// The plugin's own work between requests, and what the DAW reads of
    /// it in the header. Break when the plugin has stopped working.
    fn housekeeping(&mut self) -> ControlFlow<()> {
        let header = self.shm.header();
        self.controller.idle();
        // A device that has stopped working by itself (a script that
        // failed) says why, and its helper ends: the DAW shows it as
        // stopped, with that reason.
        if let Some(why) = self.controller.health() {
            header.set_reason(&why);
            return ControlFlow::Break(());
        }
        for change in self.controller.take_changes() {
            let head = header.change_head.load(Ordering::Relaxed);
            // A reader that has fallen a whole ring behind loses the oldest.
            self.shm.put_change(
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
            .store(self.controller.latency(), Ordering::Relaxed);
        header
            .editor_open
            .store(self.controller.editor_open() as u32, Ordering::Relaxed);
        ControlFlow::Continue(())
    }
}

/// Take one whole frame (its length in 4 bytes, then it) from the front of
/// `pending`, without its length; `None` until one has come in full.
fn take_frame(pending: &mut Vec<u8>) -> Option<Vec<u8>> {
    let length = u32::from_le_bytes(pending.get(..4)?.try_into().unwrap()) as usize;
    if pending.len() < 4 + length {
        return None;
    }
    Some(pending.drain(..4 + length).skip(4).collect())
}
