//! The DAW's side: the main thread's stand-in (parameters, state, editor).

use std::os::unix::net::UnixStream;
use std::process::Child;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Result, bail};
use paw_engine::device::{Change, Controller, ParamInfo, Ports};
use rustix::process::Signal;
use super::*;
use super::shm::*;
use super::wire::*;
use super::device::*;

// --- the DAW's side: the main thread ---------------------------------------------

/// The main-thread half of the stand-in.
pub(super) struct RemoteController {
    pub(super) name: String,
    pub(super) link: Arc<Link>,
    pub(super) stream: UnixStream,
    pub(super) child: Child,
    pub(super) params: Vec<ParamInfo>,
    pub(super) values: Vec<f64>,
    pub(super) has_editor: bool,
    pub(super) follows_state: bool,
    pub(super) ports: Ports,
    pub(super) pending: Vec<Change>,
    /// Why the helper is gone, once it is.
    pub(super) ended: Option<HelperError>,
    pub(super) late_seen: u32,
    /// Blocks answered when last looked at, and since when none have been
    /// while some came late.
    pub(super) answered_seen: u32,
    pub(super) stalled_since: Option<Instant>,
    /// The plugin was given a state or a call when it had answered this
    /// many blocks: its values are read again once it has answered
    /// another, as some plugins take a state on only in their next block.
    pub(super) reread: Option<u32>,
}

impl RemoteController {
    /// Note that the helper is gone and why, once.
    pub(super) fn end(&mut self, why: HelperError) {
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
    pub(super) fn exited(&mut self) -> Option<HelperError> {
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
