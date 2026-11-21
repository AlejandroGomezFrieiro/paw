//! The LV2 worker: non-real-time work for a plugin, on a thread of its own.

use std::cell::UnsafeCell;
use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering::Relaxed};
use std::sync::{Arc, OnceLock};
use std::thread::JoinHandle;
use std::time::Duration;


use super::*;

// --- the worker --------------------------------------------------------------

/// Runs a plugin's non-real-time work on its own thread. Requests travel from
/// the audio thread and responses back to it through lock-free byte queues,
/// each message framed by its length.
///
/// In a render the device waits after each `run` until the work it asked
/// for is done: its response then reaches the plugin after the very `run`
/// that asked for it, so a file loaded on a state lane's point plays from
/// that point, the same in every render. (LV2 also lets a host that does
/// not play in real time do the work inside `schedule_work`; Neural Amp
/// Modeler then played some renders differently.)
pub(super) struct Worker {
    /// Written by `schedule_work`, which the plugin calls from its `run`.
    pub(super) requests: UnsafeCell<rtrb::Producer<u8>>,
    /// Read by the device after each `run`.
    pub(super) responses: UnsafeCell<rtrb::Consumer<u8>>,
    /// Rendering: the device waits after each block for the work it asked.
    pub(super) offline: AtomicBool,
    /// Pieces of work asked for and not done yet.
    pub(super) pending: Arc<AtomicU32>,
    pub(super) stop: Arc<AtomicBool>,
    pub(super) thread: Option<JoinHandle<()>>,
}

pub(super) unsafe extern "C" fn respond(queue: *mut c_void, size: u32, data: *const c_void) -> u32 {
    unsafe {
        let queue = &mut *(queue as *mut rtrb::Producer<u8>);
        let data = std::slice::from_raw_parts(data as *const u8, size as usize);
        if write_message(queue, data) { 0 } else { 2 }
    }
}

pub(super) struct SendPtr<T>(*mut T);
unsafe impl<T> Send for SendPtr<T> {}

pub(super) fn write_message(queue: &mut rtrb::Producer<u8>, data: &[u8]) -> bool {
    if queue.slots() < data.len() + 4 {
        return false;
    }
    for byte in (data.len() as u32).to_le_bytes().iter().chain(data) {
        let _ = queue.push(*byte);
    }
    true
}

pub(super) fn read_message(queue: &mut rtrb::Consumer<u8>, into: &mut Vec<u8>) -> bool {
    if queue.slots() < 4 {
        return false;
    }
    let mut size = [0u8; 4];
    for byte in &mut size {
        *byte = queue.pop().unwrap_or(0);
    }
    into.clear();
    for _ in 0..u32::from_le_bytes(size) {
        // The writer queues a whole message at once, so the bytes are there.
        if into.len() < into.capacity() {
            into.push(queue.pop().unwrap_or(0));
        } else {
            let _ = queue.pop();
        }
    }
    true
}

impl Worker {
    pub(super) fn start(interface: *const WorkerInterface, handle: *mut c_void) -> Self {
        let (requests, mut incoming) = rtrb::RingBuffer::new(WORK_CAPACITY);
        let (outgoing, responses) = rtrb::RingBuffer::new(WORK_CAPACITY);
        let outgoing = Arc::new(std::sync::Mutex::new(outgoing));
        let stop = Arc::new(AtomicBool::new(false));
        let (raw_interface, raw_handle) = (interface as *mut WorkerInterface, handle);
        let pending = Arc::new(AtomicU32::new(0));
        let done = pending.clone();
        let (stopped, to_ui, interface, handle) = (
            stop.clone(),
            outgoing.clone(),
            SendPtr(raw_interface),
            SendPtr(raw_handle),
        );
        let thread = std::thread::spawn(move || {
            let (interface, handle) = (interface, handle);
            let mut message = Vec::with_capacity(WORK_CAPACITY);
            while !stopped.load(Relaxed) {
                while read_message(&mut incoming, &mut message) {
                    let mut outgoing = to_ui.lock().unwrap_or_else(|e| e.into_inner());
                    unsafe {
                        ((*interface.0).work)(
                            handle.0,
                            respond,
                            &mut *outgoing as *mut _ as *mut c_void,
                            message.len() as u32,
                            message.as_ptr().cast(),
                        );
                    }
                    done.fetch_sub(1, std::sync::atomic::Ordering::Release);
                }
                std::thread::sleep(Duration::from_millis(2));
            }
        });
        Self {
            requests: UnsafeCell::new(requests),
            responses: UnsafeCell::new(responses),
            offline: AtomicBool::new(false),
            pending,
            stop,
            thread: Some(thread),
        }
    }

    /// In a render, wait (at most ten seconds) until the worker has done
    /// what was asked of it, so that its responses reach the plugin after
    /// the very block that asked.
    pub(super) fn finish(&self) {
        if !self.offline.load(Relaxed) {
            return;
        }
        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        while self.pending.load(std::sync::atomic::Ordering::Acquire) > 0
            && std::time::Instant::now() < deadline
        {
            std::thread::sleep(Duration::from_micros(200));
        }
    }
}

impl Drop for Worker {
    fn drop(&mut self) {
        self.stop.store(true, Relaxed);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

pub(super) unsafe extern "C" fn schedule_work(handle: *mut c_void, size: u32, data: *const c_void) -> u32 {
    unsafe {
        // The handle is the slot the worker is put in once the plugin exists.
        let Some(worker) = (*(handle as *const OnceLock<Worker>)).get() else {
            return 1;
        };
        let data = std::slice::from_raw_parts(data as *const u8, size as usize);
        // Counted before the worker can see it, so the count never goes below 0.
        worker.pending.fetch_add(1, Relaxed);
        if write_message(&mut *worker.requests.get(), data) {
            0
        } else {
            worker.pending.fetch_sub(1, Relaxed);
            2
        }
    }
}


