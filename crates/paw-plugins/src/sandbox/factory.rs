//! The DAW's side: the factory that starts a helper and makes the stand-in.

#![expect(clippy::unwrap_used, reason = "debt: pay down")]

use std::os::fd::{AsRawFd, BorrowedFd, RawFd};
use std::os::unix::net::UnixStream;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use paw_engine::Bell;
use paw_engine::device::{Category, DeviceFactory, DeviceInfo, Instance, Ports, Rest, StartTest, Starting};
use rustix::process::Signal;
use super::*;
use super::shm::*;
use super::wire::*;
use super::device::*;
use super::controller::*;

/// Makes a plugin in a helper process.
#[derive(Clone)]
pub(super) struct RemoteFactory {
    pub(super) info: DeviceInfo,
    /// How to start the helper, where it is not the plugins' one.
    pub(super) argv: Option<Vec<String>>,
    pub(super) env: Vec<(String, String)>,
    /// The folders added in the DAW when this factory was made, as
    /// [`crate::dirs::ADDED_DIRS_ENV`] gives them to the helper.
    pub(super) added_dirs: Option<std::ffi::OsString>,
}

/// The methods by which the stand-in asks the helper for a parameter's
/// text and value (see [`Controller::value_text`]).
pub(super) const PARAM_TEXT: &str = "paw.param.text";
pub(super) const PARAM_VALUE: &str = "paw.param.value";

/// Why a helper gave no answer: whether it timed out, and the error.
pub(super) fn silence(err: &std::io::Error) -> bool {
    matches!(
        err.kind(),
        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
    )
}

impl RemoteFactory {
    /// Start the helper, which makes the plugin. Its first word, read with
    /// [`made`](Self::made), says whether that worked. With `hang` (for a
    /// test), the helper waits until it is ended before it makes the plugin.
    fn spawn(&self, sample_rate: f32, max_block: usize, hang: bool) -> Result<(RemoteController, UnixStream)> {
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
        if let Some(dirs) = &self.added_dirs {
            command.env(crate::dirs::ADDED_DIRS_ENV, dirs);
        }
        if let Some(libs) = crate::attach::env() {
            command.env(crate::attach::ATTACH_ENV, libs);
        }
        // What a test asked of this plugin (see `follow_test_env`).
        if kind_test(&self.info.kind).hang {
            command.env("PAW_PLUGIN_TEST_HANG", "1");
        }
        if hang {
            command.env("PAW_PLUGIN_HOST_HANG", "1");
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
            late_ns: AtomicU64::new(0),
            answered: AtomicU32::new(0),
            wake: AtomicBool::new(false),
        });
        let controller = RemoteController {
            name: self.info.name.clone(),
            kind: self.info.kind.clone(),
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
            stall: None,
            reread: None,
            engine: None,
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
                pending: Pending::new(),
                told_priority: false,
                rest: Rest::default(),
                offline_limit: kind_test(&self.info.kind).deadline.unwrap_or(if self.argv.is_some() {
                    STALL_LIMIT
                } else {
                    OFFLINE_LIMIT
                }),
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
    ready: Bell,
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
    // After the answer: the turn that the bell wakes finds it.
    ready.ring();
}

impl DeviceFactory for RemoteFactory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, max_block: usize) -> Result<Instance> {
        let (mut controller, mut ours) = self.spawn(sample_rate, max_block, false)?;
        // Its first word is that the plugin exists, or why it does not.
        let limit = CREATE_LIMIT;
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
        test: StartTest,
        ready: Bell,
    ) -> Option<Box<dyn Starting>> {
        let factory = self.clone();
        let (tell, answer) = std::sync::mpsc::channel();
        let limit = test.deadline.unwrap_or(CREATE_LIMIT);
        // A start that fails at once has its answer now: the loop looks.
        let failed = |err: anyhow::Error, ready: &Bell| -> Option<Box<dyn Starting>> {
            ready.ring();
            Some(Box::new(Failed(Some(err))))
        };
        let controller = match self.spawn(sample_rate, max_block, test.hang) {
            Ok((controller, ours)) => {
                let bell = ready.clone();
                let spawned = std::thread::Builder::new()
                    .name("plugin-start".into())
                    .spawn(move || wait_for_helper(ours, state, limit, tell, bell));
                if let Err(err) = spawned {
                    return failed(anyhow!("{} could not be started: {err}", self.info.name), &ready);
                }
                controller
            }
            Err(err) => return failed(err, &ready),
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


#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::Ordering;

    #[test]
    fn a_start_rings_its_bell_after_its_answer_is_sent() {
        let (ours, theirs) = UnixStream::pair().unwrap();
        // A helper that is gone before its first word.
        drop(theirs);
        let bits = Arc::new(AtomicU32::new(0));
        let (tell, answer) = std::sync::mpsc::channel();
        wait_for_helper(ours, None, CREATE_LIMIT, tell, Bell::new(bits.clone(), 1, Arc::new(|| {})));
        assert!(answer.try_recv().unwrap().is_err(), "a helper that is gone is an answer");
        assert_eq!(bits.load(Ordering::Acquire), 1, "and the loop is rung for it");
    }
}
