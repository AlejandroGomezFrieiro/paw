//! The helper's side: the plugin-host process.

use std::io::Read;
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


