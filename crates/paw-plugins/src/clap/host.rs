//! What the host offers the plugin: the callbacks it may make and the
//! extensions it may ask for. The callbacks only note what the plugin asked
//! for in [`HostFlags`], for the main thread to act on.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]

use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering::Relaxed};
use std::sync::{Arc, Mutex, OnceLock};

use clack_extensions::gui::{GuiSize, HostGui, HostGuiImpl};
use clack_extensions::log::{HostLog, HostLogImpl, LogSeverity};
use clack_extensions::params::{
    HostParams, HostParamsImplMainThread, HostParamsImplShared, ParamClearFlags, ParamRescanFlags,
};
use clack_extensions::posix_fd::{FdFlags, HostPosixFd, HostPosixFdImpl};
use clack_extensions::state::{HostState, HostStateImpl};
use clack_extensions::thread_check::{HostThreadCheck, HostThreadCheckImpl};
use clack_extensions::timer::{HostTimer, HostTimerImpl, TimerId};
use clack_host::prelude::{
    ClapId, HostError, HostExtensions, HostHandlers, MainThreadHandler, SharedHandler,
};
use clap_sys::id::clap_id;
use paw_engine::{Bell, Waker};

use crate::echo::Blocks;
use crate::is_main_thread;
use crate::window::Watches;

/// What the plugin has asked the host for, to be acted on from the main thread.
pub(super) struct HostFlags {
    pub(super) callback: AtomicBool,
    /// The plugin asked to be deactivated and activated again
    /// (`request_restart`): the controller does it in its next idle.
    pub(super) restart: AtomicBool,
    /// The plugin has to be run again, though it said it may sleep: it
    /// asked to be (`request_process`), or was given a state, which some
    /// plugins only take on in their next block. Set through
    /// [`wake`](Self::wake); the device clears it in its next block.
    pub(super) wake: AtomicBool,
    /// The engine the device is in, which [`wake`](Self::wake) wakes from
    /// rest. Set once, on the main thread, as the device goes in.
    pub(super) engine: OnceLock<Waker>,
    /// Tells the main loop that the plugin asked for a call on the main
    /// thread. Set once, on the main thread, as the device goes in.
    pub(super) bell: OnceLock<Bell>,
    /// The plugin says its parameter values changed behind the host's back.
    pub(super) rescan: AtomicBool,
    /// Blocks the plugin has processed, to tell when it has taken on a
    /// state.
    pub(super) blocks: Blocks,
    /// States the plugin was given: the first block after a new one is
    /// the block in which a plugin that takes a state on in its next block
    /// takes it on.
    pub(super) loads: AtomicU64,
    /// The plugin closed its editor itself.
    pub(super) closed: AtomicBool,
    /// A size the plugin wants its editor window to be.
    pub(super) resize: Mutex<Option<(u32, u32)>>,
    /// File descriptors and timers the plugin's editor runs on.
    pub(super) watches: Mutex<Watches<(), clap_id>>,
    pub(super) next_timer: AtomicU32,
}

impl HostFlags {
    pub(super) fn new() -> Self {
        Self {
            callback: AtomicBool::new(false),
            restart: AtomicBool::new(false),
            wake: AtomicBool::new(false),
            engine: OnceLock::new(),
            bell: OnceLock::new(),
            rescan: AtomicBool::new(false),
            blocks: Blocks::default(),
            loads: AtomicU64::new(0),
            closed: AtomicBool::new(false),
            resize: Mutex::new(None),
            watches: Mutex::new(Watches::new()),
            next_timer: AtomicU32::new(0),
        }
    }

    /// Have the plugin run in the next block, though it said it may sleep
    /// and the engine may rest. From any thread: an atomic store, and a
    /// lock-free read of the engine's waker.
    pub(super) fn wake(&self) {
        self.wake.store(true, Relaxed);
        if let Some(engine) = self.engine.get() {
            engine.wake();
        }
    }

    /// Tell the main loop that the plugin asked for something on the main
    /// thread. From any thread, also the audio thread: a mark, no system
    /// call.
    fn mark(&self) {
        if let Some(bell) = self.bell.get() {
            bell.mark();
        }
    }
}

/// paw's side of a plugin instance, for Clack: the callbacks the plugin may
/// make and the extensions it may ask for.
pub(super) struct PawHost;

/// The callbacks the plugin may make from any thread: they only note what
/// it asked for in [`HostFlags`], for the main thread to act on.
pub(super) struct HostShared {
    pub(super) flags: Arc<HostFlags>,
}

/// The callbacks the plugin makes from the main thread.
pub(super) struct HostMain<'a> {
    pub(super) shared: &'a HostShared,
}

impl HostHandlers for PawHost {
    type Shared<'a> = HostShared;
    type MainThread<'a> = HostMain<'a>;
    type AudioProcessor<'a> = ();

    fn declare_extensions(builder: &mut HostExtensions<Self>, _: &HostShared) {
        builder
            .register::<HostThreadCheck>()
            .register::<HostLog>()
            .register::<HostParams>()
            .register::<HostState>()
            .register::<HostGui>()
            .register::<HostTimer>()
            .register::<HostPosixFd>();
    }
}

impl SharedHandler<'_> for HostShared {
    fn request_restart(&self) {
        self.flags.restart.store(true, Relaxed);
        self.flags.mark();
    }

    fn request_process(&self) {
        self.flags.wake();
    }

    fn request_callback(&self) {
        self.flags.callback.store(true, Relaxed);
        self.flags.mark();
    }
}

impl<'a> MainThreadHandler<'a> for HostMain<'a> {}

// The main thread is the audio thread while it runs the blocks of the
// stepped backend (the tests).
impl HostThreadCheckImpl for HostShared {
    fn is_main_thread(&self) -> bool {
        is_main_thread() && !paw_engine::backend::audio_thread::stepping()
    }

    fn is_audio_thread(&self) -> bool {
        !self.is_main_thread()
    }
}

impl HostLogImpl for HostShared {
    fn log(&self, _: LogSeverity, _: &str) {}
}

impl HostParamsImplShared for HostShared {
    fn request_flush(&self) {}
}

impl HostParamsImplMainThread for HostMain<'_> {
    fn rescan(&self, _: ParamRescanFlags) {
        self.shared.flags.rescan.store(true, Relaxed);
    }

    fn clear(&self, _: ClapId, _: ParamClearFlags) {}
}

impl HostStateImpl for HostMain<'_> {
    fn mark_dirty(&self) {}
}

impl HostGuiImpl for HostShared {
    fn resize_hints_changed(&self) {}

    fn request_resize(&self, size: GuiSize) -> Result<(), HostError> {
        *self
            .flags
            .resize
            .lock()
            .expect("a thread panicked while it held the lock") = Some((size.width, size.height));
        Ok(())
    }

    fn request_show(&self) -> Result<(), HostError> {
        Ok(())
    }

    fn request_hide(&self) -> Result<(), HostError> {
        Ok(())
    }

    fn closed(&self, _was_destroyed: bool) {
        self.flags.closed.store(true, Relaxed);
    }
}

impl HostTimerImpl for HostMain<'_> {
    fn register_timer(&self, period_ms: u32) -> Result<TimerId, HostError> {
        let flags = &self.shared.flags;
        let timer = flags.next_timer.fetch_add(1, Relaxed);
        flags
            .watches
            .lock()
            .expect("a thread panicked while it held the lock")
            .add_timer(period_ms as u64, timer);
        Ok(TimerId(timer))
    }

    fn unregister_timer(&self, TimerId(id): TimerId) -> Result<(), HostError> {
        self.shared
            .flags
            .watches
            .lock()
            .expect("a thread panicked while it held the lock")
            .remove_timer(&id);
        Ok(())
    }
}

impl HostPosixFdImpl for HostMain<'_> {
    fn register_fd(&self, fd: i32, _: FdFlags) -> Result<(), HostError> {
        self.shared
            .flags
            .watches
            .lock()
            .expect("a thread panicked while it held the lock")
            .fds
            .push((fd, ()));
        Ok(())
    }

    fn modify_fd(&self, _fd: i32, _: FdFlags) -> Result<(), HostError> {
        Ok(())
    }

    fn unregister_fd(&self, fd: i32) -> Result<(), HostError> {
        self.shared
            .flags
            .watches
            .lock()
            .expect("a thread panicked while it held the lock")
            .fds
            .retain(|(known, ())| *known != fd);
        Ok(())
    }
}
