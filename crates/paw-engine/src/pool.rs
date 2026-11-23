//! Worker threads for the audio thread: parts that do not feed each other
//! are processed side by side.
//!
//! The pool is built on the main thread and handed to the engine. From then
//! on the thread driving the engine calls [`Pool::run`] with a number of items
//! and a function of the item's index; the workers and the caller take items
//! until none are left, and `run` returns when all are done. Nothing here
//! allocates or locks: work is claimed with one compare-and-swap, and a
//! sleeping worker is woken by unparking it.
//!
//! A worker with nothing to do looks for more for a moment while a block is
//! under way, for the next group of parts, and sleeps as soon as the caller
//! says the block is done ([`Pool::idle`]), so that the workers cost nothing
//! between blocks.
//!
//! Workers treat denormals as zero, as every thread that drives an engine
//! does, so that a part sounds the same whichever thread runs it. When the
//! caller runs with real-time priority (an audio callback), the workers take
//! the same priority; if the system refuses, the pool does all the work on
//! the calling thread rather than make an audio callback wait for threads
//! that anything may push aside.

use std::cell::UnsafeCell;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU32, AtomicU64, Ordering};
use std::thread::JoinHandle;

/// Items of one job. More are run in pieces.
const MAX_ITEMS: usize = 0xffff;
/// How long a worker with nothing to do looks for more before it sleeps.
/// Long enough to be awake for the next group of parts of the same block.
const IDLE_SPINS: u32 = 2_000;

#[derive(Clone, Copy)]
struct Job {
    data: *const (),
    call: unsafe fn(*const (), usize),
}

struct Inner {
    /// The current job and how far it has got: a number that changes with
    /// every job in the top half, then the item count and the next item to
    /// take, 16 bits each.
    state: AtomicU64,
    /// Items finished.
    done: AtomicU32,
    /// Written by the caller only while no item can be claimed, and read by
    /// a worker only after it has claimed one of this job's items.
    job: UnsafeCell<Job>,
    stop: AtomicBool,
    /// A block is under way: more work may come at once.
    busy: AtomicBool,
    /// The caller's scheduling policy and priority, for the workers to match:
    /// -1 until known.
    policy: AtomicI32,
    priority: AtomicI32,
    /// Workers that could not take the caller's priority.
    refused: AtomicU32,
}

// SAFETY: everything but `job` is atomic. `job` is only read under the
// protocol above: the caller (`Pool::run`, which takes `&mut Pool`, so there
// is one) writes it before it publishes the job's state (Release), and a
// worker reads it only after its compare-exchange on that state (AcqRel)
// claimed an item, which the caller waits for before it writes the next job.
// What `job.data` points to is shared by the threads, and `run` requires it
// to be `Sync`.
unsafe impl Sync for Inner {}
// SAFETY: `job.data` is the only field that is not `Send`; it is a shared
// borrow of a `Sync` closure (see above), so it may be used on any thread.
unsafe impl Send for Inner {}

fn pack(job: u32, count: usize, next: usize) -> u64 {
    ((job as u64) << 32) | ((count as u64) << 16) | next as u64
}

impl Inner {
    /// Take items of the current job until there are none left to take.
    fn work(&self) {
        loop {
            let state = self.state.load(Ordering::Acquire);
            let (count, next) = ((state >> 16) & 0xffff, state & 0xffff);
            if next >= count {
                return;
            }
            if self
                .state
                .compare_exchange_weak(state, state + 1, Ordering::AcqRel, Ordering::Relaxed)
                .is_err()
            {
                continue;
            }
            // Counted as done even if the item panics, so the caller is not
            // left waiting for it.
            struct Done<'a>(&'a AtomicU32);
            impl Drop for Done<'_> {
                fn drop(&mut self) {
                    self.0.fetch_add(1, Ordering::Release);
                }
            }
            let _done = Done(&self.done);
            // SAFETY: the claim succeeded, so the job is the one this state
            // belongs to: the caller wrote it before it published the state,
            // and writes it again only after this item is counted as done.
            let job = unsafe { *self.job.get() };
            // SAFETY: `job.call` is `call::<G>` and `job.data` a `&G` of the
            // same `G`, set together by `erase`; the `G` lives until every
            // claimed item is done, and this one is not until `_done` drops.
            unsafe { (job.call)(job.data, next as usize) };
        }
    }

    fn has_work(&self) -> bool {
        let state = self.state.load(Ordering::Acquire);
        (state & 0xffff) < ((state >> 16) & 0xffff)
    }
}

pub struct Pool {
    inner: Arc<Inner>,
    workers: Vec<JoinHandle<()>>,
    job: u32,
    /// Whether the caller's priority has been looked at.
    matched: bool,
}

impl Pool {
    /// A pool that runs work on `threads` threads, counting the caller: it
    /// starts one fewer.
    pub fn new(threads: usize) -> Self {
        let inner = Arc::new(Inner {
            state: AtomicU64::new(0),
            done: AtomicU32::new(0),
            job: UnsafeCell::new(Job {
                data: std::ptr::null(),
                call: |_, _| {},
            }),
            stop: AtomicBool::new(false),
            busy: AtomicBool::new(false),
            policy: AtomicI32::new(-1),
            priority: AtomicI32::new(0),
            refused: AtomicU32::new(0),
        });
        let workers = (1..threads.max(1))
            .filter_map(|index| {
                let inner = inner.clone();
                std::thread::Builder::new()
                    .name(format!("audio-{index}"))
                    .spawn(move || worker(&inner))
                    .ok()
            })
            .collect();
        Self {
            inner,
            workers,
            job: 0,
            matched: false,
        }
    }

    /// Threads that take work, counting the caller. 1 when the workers could
    /// not be given the caller's priority and are left out.
    pub fn threads(&self) -> usize {
        if self.usable() {
            self.workers.len() + 1
        } else {
            1
        }
    }

    fn usable(&self) -> bool {
        self.inner.refused.load(Ordering::Relaxed) == 0
    }

    /// Call `f(0)`, `f(1)`, … `f(count - 1)`, each once, spread over the
    /// threads, and return when all have returned.
    pub fn run<F: Fn(usize) + Sync>(&mut self, count: usize, f: &F) {
        if !self.matched {
            self.matched = true;
            let (policy, priority) = current_priority();
            self.inner.priority.store(priority, Ordering::Relaxed);
            self.inner.policy.store(policy, Ordering::Release);
        }
        if count < 2 || self.workers.is_empty() || !self.usable() {
            (0..count).for_each(f);
            return;
        }
        self.inner.busy.store(true, Ordering::Relaxed);
        /// # Safety
        /// `data` must point to an `F` that is alive for the call.
        unsafe fn call<F: Fn(usize)>(data: *const (), index: usize) {
            // SAFETY: the caller's promise above.
            unsafe { (*(data as *const F))(index) }
        }
        let mut first = 0;
        while first < count {
            let items = (count - first).min(MAX_ITEMS);
            let piece = |index: usize| f(first + index);
            // Lifetimes are erased here: `piece` outlives the job, because
            // this function does not go on until every item is done.
            fn erase<G: Fn(usize)>(g: &G) -> Job {
                Job {
                    data: g as *const G as *const (),
                    call: call::<G>,
                }
            }
            // SAFETY: no item can be claimed now (the state of the last job
            // was closed and its claimed items are done, or there was none),
            // so no worker reads `job` while it is written. `piece` is
            // `Sync`, as it borrows only `f` (`F: Sync`) and `first`.
            unsafe { *self.inner.job.get() = erase(&piece) };
            self.inner.done.store(0, Ordering::Relaxed);
            self.job = self.job.wrapping_add(1);
            self.inner
                .state
                .store(pack(self.job, items, 0), Ordering::Release);
            for worker in self.workers.iter().take(items - 1) {
                worker.thread().unpark();
            }
            // Whatever happens on this thread, the job is not left while a
            // worker may still be in it.
            struct Finish<'a>(&'a Inner, usize);
            impl Drop for Finish<'_> {
                fn drop(&mut self) {
                    let (inner, items) = (self.0, self.1);
                    // Nothing more is handed out; what was not is not waited for.
                    let state = inner.state.load(Ordering::Acquire);
                    let taken = inner.state.swap(state | 0xffff, Ordering::AcqRel) & 0xffff;
                    let taken = (taken as usize).min(items);
                    let mut spins = 0u32;
                    while (inner.done.load(Ordering::Acquire) as usize) < taken {
                        spins += 1;
                        if spins < IDLE_SPINS {
                            std::hint::spin_loop();
                        } else {
                            std::thread::yield_now();
                        }
                    }
                }
            }
            let finish = Finish(&self.inner, items);
            self.inner.work();
            drop(finish);
            first += items;
        }
    }
}

impl Pool {
    /// Say that no more work comes until the next block: the workers go to
    /// sleep at once instead of looking for more.
    pub fn idle(&self) {
        self.inner.busy.store(false, Ordering::Relaxed);
    }
}

impl Drop for Pool {
    fn drop(&mut self) {
        self.inner.stop.store(true, Ordering::Release);
        for worker in self.workers.drain(..) {
            worker.thread().unpark();
            let _ = worker.join();
        }
    }
}

fn worker(inner: &Inner) {
    crate::backend::no_denormals();
    let mut policy = -1;
    let mut spins = 0;
    loop {
        if inner.stop.load(Ordering::Acquire) {
            return;
        }
        let wanted = inner.policy.load(Ordering::Acquire);
        if wanted != policy {
            policy = wanted;
            if !match_priority(wanted, inner.priority.load(Ordering::Relaxed)) {
                inner.refused.fetch_add(1, Ordering::Relaxed);
            }
        }
        if inner.has_work() {
            inner.work();
            spins = 0;
        } else if spins < IDLE_SPINS && inner.busy.load(Ordering::Relaxed) {
            spins += 1;
            std::hint::spin_loop();
        } else {
            spins = 0;
            // Unparking leaves a token behind, so work announced between the
            // look above and here is not slept through.
            std::thread::park();
        }
    }
}

/// The calling thread's scheduling policy and priority.
#[cfg(unix)]
fn current_priority() -> (i32, i32) {
    let mut policy = 0;
    // SAFETY: `sched_param` is a plain C struct of integers; all zeros is one.
    let mut param: libc::sched_param = unsafe { std::mem::zeroed() };
    // SAFETY: the calling thread exists, and both out-pointers are to live
    // locals of the right types.
    let result =
        unsafe { libc::pthread_getschedparam(libc::pthread_self(), &mut policy, &mut param) };
    if result == 0 {
        // A thread made real-time by the system's helper carries a flag in
        // its policy that says its children do not inherit it.
        #[cfg(target_os = "linux")]
        let policy = policy & !libc::SCHED_RESET_ON_FORK;
        (policy, param.sched_priority)
    } else {
        (libc::SCHED_OTHER, 0)
    }
}

/// Give the calling thread a policy and priority. Says whether it has what a
/// real-time caller needs it to have.
// Not `audio_thread_priority`: it asks RtKit over D-Bus (a C library for the
// Nix build) and does not copy the sound thread's own policy and priority.
#[cfg(unix)]
fn match_priority(policy: i32, priority: i32) -> bool {
    if policy != libc::SCHED_FIFO && policy != libc::SCHED_RR {
        // An ordinary caller: stay ordinary too.
        return true;
    }
    // SAFETY: `sched_param` is a plain C struct of integers; all zeros is one.
    let mut param: libc::sched_param = unsafe { std::mem::zeroed() };
    param.sched_priority = priority;
    // SAFETY: the calling thread exists, and `param` is a live local; a
    // policy or priority the system does not take is an error, not UB.
    let result = unsafe { libc::pthread_setschedparam(libc::pthread_self(), policy, &param) };
    result == 0
}

#[cfg(not(unix))]
fn current_priority() -> (i32, i32) {
    (0, 0)
}

#[cfg(not(unix))]
fn match_priority(_policy: i32, _priority: i32) -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;

    #[test]
    fn every_item_runs_once() {
        let mut pool = Pool::new(4);
        for count in [0, 1, 2, 3, 17, 1000] {
            let hits: Vec<AtomicUsize> = (0..count).map(|_| AtomicUsize::new(0)).collect();
            for _ in 0..50 {
                pool.run(count, &|i| {
                    hits[i].fetch_add(1, Ordering::Relaxed);
                });
            }
            assert!(hits.iter().all(|h| h.load(Ordering::Relaxed) == 50));
        }
    }

    #[test]
    fn work_is_shared_between_threads() {
        let mut pool = Pool::new(4);
        let seen = std::sync::Mutex::new(std::collections::HashSet::new());
        pool.run(64, &|_| {
            seen.lock().unwrap().insert(std::thread::current().id());
            std::thread::sleep(std::time::Duration::from_millis(2));
        });
        assert!(seen.lock().unwrap().len() > 1);
    }

    /// Driven by a real-time thread, the workers become real-time too.
    #[cfg(target_os = "linux")]
    #[test]
    fn workers_take_the_priority_of_the_thread_that_drives_them() {
        let outcome = std::thread::spawn(|| {
            // SAFETY: `sched_param` is a plain C struct of integers.
            let mut param: libc::sched_param = unsafe { std::mem::zeroed() };
            param.sched_priority = 5;
            // SAFETY: this thread exists, and `param` is a live local.
            let allowed = unsafe {
                libc::pthread_setschedparam(libc::pthread_self(), libc::SCHED_FIFO, &param)
            } == 0;
            if !allowed {
                return None;
            }
            let mut pool = Pool::new(3);
            let seen = std::sync::Mutex::new(Vec::new());
            for _ in 0..20 {
                pool.run(6, &|_| {
                    seen.lock().unwrap().push(current_priority());
                    std::thread::sleep(std::time::Duration::from_millis(1));
                });
            }
            Some((pool.threads(), seen.into_inner().unwrap()))
        })
        .join()
        .unwrap();
        let Some((threads, seen)) = outcome else {
            eprintln!("skipped: this user may not make a thread real-time");
            return;
        };
        assert_eq!(threads, 3, "the workers were not refused");
        assert!(
            seen.iter().all(|p| *p == (libc::SCHED_FIFO, 5)),
            "every item ran at the caller's priority: {seen:?}"
        );
    }

    #[test]
    fn a_pool_of_one_runs_on_the_caller() {
        let mut pool = Pool::new(1);
        let me = std::thread::current().id();
        pool.run(8, &|_| assert_eq!(std::thread::current().id(), me));
        assert_eq!(pool.threads(), 1);
    }
}
