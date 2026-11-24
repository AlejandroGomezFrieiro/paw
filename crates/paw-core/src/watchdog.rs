//! Stops Lua that runs away, from outside it.
//!
//! A hook set in Lua for the length of every callback would do, but LuaJIT
//! does not call hooks from compiled code, so the code that needs watching
//! would have to be kept out of the compiler. Instead nothing is set while a
//! callback runs. A thread here knows when the callback must have returned
//! (`paw.limit` tells it), and only when that time has passed does it set a
//! hook, from outside, which LuaJIT is built to allow
//! (`LUAJIT_ENABLE_CHECKHOOK`, see `.cargo/config.toml`: compiled loops look
//! for a hook and leave to the interpreter when there is one). The hook calls
//! the Lua function `paw.limit` registered, which raises the error.

use std::ffi::c_int;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, Thread};
use std::time::{Duration, Instant};

use mlua::{Function, Lua, ffi};

/// LuaJIT was built to look for hooks in compiled code (`build.rs`).
pub(crate) const ASYNC: bool = cfg!(lua_checkhook);

/// The registry key of the Lua function the hook calls.
const HOOK_KEY: &std::ffi::CStr = c"paw.limit.hook";

/// In `deadline`: the kernel is gone and the thread should end.
const GONE: u64 = u64::MAX;

/// The longest the thread sleeps before it looks at the deadline again. A
/// deadline set later than the one it sleeps for is then seen in time, and a
/// deadline far in the future (`paw.api.limit_watch(2^53)`) does not keep
/// the thread asleep after it is taken away.
const LONGEST_NAP: Duration = Duration::from_secs(1);

struct StatePtr(*mut ffi::lua_State);
// SAFETY: only ever passed to `lua_sethook`, which LuaJIT allows from another thread, and
// only while the mutex around it is held and `detach` has not cleared it (so the state is
// alive).
unsafe impl Send for StatePtr {}

struct Inner {
    /// The Lua state to interrupt, or null between states.
    state: Mutex<StatePtr>,
    /// When the running callback must have returned, in microseconds since
    /// `started`, or 0 while nothing is being watched.
    deadline: AtomicU64,
    /// The thread is parked with nothing to watch.
    parked: AtomicBool,
    started: Instant,
}

pub(crate) struct Watchdog {
    inner: Arc<Inner>,
    thread: Thread,
}

unsafe extern "C-unwind" fn hook(state: *mut ffi::lua_State, _ar: *mut ffi::lua_Debug) {
    // SAFETY: LuaJIT calls this hook with the state that runs, on its own thread, so every
    // call below is on a live state with the stack it is allowed to use.
    unsafe {
        // Once is enough: the Lua side asks again if it wants watching on.
        ffi::lua_sethook(state, None, 0, 0);
        ffi::lua_getfield(state, ffi::LUA_REGISTRYINDEX, HOOK_KEY.as_ptr());
        if ffi::lua_type(state, -1) == ffi::LUA_TFUNCTION {
            // Raises when the callback has had its time; the error leaves
            // through here.
            ffi::lua_call(state, 0, 0);
        } else {
            ffi::lua_pop(state, 1);
        }
    }
}

impl Watchdog {
    pub(crate) fn new(started: Instant) -> Self {
        let inner = Arc::new(Inner {
            state: Mutex::new(StatePtr(std::ptr::null_mut())),
            deadline: AtomicU64::new(0),
            parked: AtomicBool::new(false),
            started,
        });
        let theirs = inner.clone();
        let handle = thread::Builder::new()
            .name("lua-watchdog".into())
            .spawn(move || watch(&theirs))
            .expect("starting the watchdog thread");
        Self {
            inner,
            thread: handle.thread().clone(),
        }
    }

    /// Watch this Lua state from now on. Call on the thread that runs it,
    /// outside any coroutine.
    pub(crate) fn attach(&self, lua: &Lua) -> mlua::Result<()> {
        let mut main = std::ptr::null_mut();
        // SAFETY: the closure only copies the pointer of the state out; it touches nothing.
        unsafe { lua.exec_raw::<()>((), |state| main = state)? };
        self.inner.deadline.store(0, Ordering::SeqCst);
        self.inner.state.lock().unwrap().0 = main;
        Ok(())
    }

    /// Stop watching, before the Lua state goes away.
    pub(crate) fn detach(&self) {
        self.inner.deadline.store(0, Ordering::SeqCst);
        self.inner.state.lock().unwrap().0 = std::ptr::null_mut();
    }

    /// The Lua function to call when a callback has overrun.
    pub(crate) fn set_hook(lua: &Lua, func: Function) -> mlua::Result<()> {
        lua.set_named_registry_value(HOOK_KEY.to_str().unwrap(), func)
    }

    /// The running callback must return by `ms` (on the clock of `started`),
    /// or `None` when it has returned.
    pub(crate) fn watch(&self, ms: Option<f64>) {
        let micros = deadline_micros(ms);
        self.inner.deadline.store(micros, Ordering::SeqCst);
        if micros != 0 && self.inner.parked.swap(false, Ordering::SeqCst) {
            self.thread.unpark();
        }
    }
}

/// A deadline in milliseconds as the thread keeps it: microseconds, 0 for
/// none, and at least 1 for a time that passed. A huge or infinite time
/// stays below [`GONE`], so that no deadline ends the thread.
fn deadline_micros(ms: Option<f64>) -> u64 {
    ms.map_or(0, |ms| ((ms.max(0.0) * 1000.0) as u64).clamp(1, GONE - 1))
}

/// How long the thread sleeps while a deadline is ahead: until it, or
/// [`LONGEST_NAP`] if that comes first.
fn nap(deadline: u64, now: u64) -> Duration {
    Duration::from_micros(deadline.saturating_sub(now)).min(LONGEST_NAP)
}

impl Drop for Watchdog {
    fn drop(&mut self) {
        self.inner.deadline.store(GONE, Ordering::SeqCst);
        self.thread.unpark();
    }
}

fn watch(inner: &Inner) {
    loop {
        let deadline = inner.deadline.load(Ordering::SeqCst);
        if deadline == GONE {
            return;
        }
        if deadline == 0 {
            inner.parked.store(true, Ordering::SeqCst);
            // A deadline set between the look and the flag would be missed.
            if inner.deadline.load(Ordering::SeqCst) == 0 {
                thread::park();
            }
            inner.parked.store(false, Ordering::SeqCst);
            continue;
        }
        let now = inner.started.elapsed().as_micros() as u64;
        if now < deadline {
            // Callbacks come and go many times before one overruns: sleep
            // through them and look at whichever is running afterwards.
            thread::sleep(nap(deadline, now));
            continue;
        }
        // Still the same callback, and its time is up.
        if inner
            .deadline
            .compare_exchange(deadline, 0, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok()
        {
            let state = inner.state.lock().unwrap();
            if !state.0.is_null() {
                // SAFETY: the state is not null and the lock is held, so `detach` cannot clear
                // it and the state cannot go away before the call returns; `hook` has the
                // signature that LuaJIT calls.
                unsafe { ffi::lua_sethook(state.0, Some(hook), ffi::LUA_MASKCOUNT, 1 as c_int) };
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_deadline_ends_the_thread() {
        for ms in [1e300, f64::INFINITY, 2f64.powi(64)] {
            assert_ne!(deadline_micros(Some(ms)), GONE, "{ms} ms");
        }
        assert_eq!(deadline_micros(None), 0, "no deadline");
        assert_eq!(deadline_micros(Some(-1.0)), 1, "a time that passed is still a deadline");
        assert_eq!(deadline_micros(Some(f64::NAN)), 1, "so is a time that is not a number");
    }

    #[test]
    fn the_thread_looks_again_within_a_second_of_a_far_deadline() {
        assert_eq!(nap(GONE - 1, 0), LONGEST_NAP, "a deadline far in the future");
        assert_eq!(nap(2_500, 1_000), Duration::from_micros(1_500), "a near deadline");
    }
}
