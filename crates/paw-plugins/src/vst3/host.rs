//! What the host gives the plugin: the host application and component
//! handler, the frame of an editor, and the run loop of timers and file
//! descriptors that both offer. Main thread, except the atomics of `Host`.

use std::cell::{Cell, RefCell};
use std::ffi::c_void;
use std::ptr;
use std::rc::Rc;
use std::sync::atomic::AtomicBool;

use vst3::Steinberg::Linux::*;
use vst3::Steinberg::Vst::*;
use vst3::Steinberg::*;
use vst3::{Class, ComPtr, ComRef, Interface};

use super::{FALSE, NO_INTERFACE, OK};
use crate::echo::Blocks;
use crate::window::Watches;

bitflags::bitflags! {
    /// The flags of `IComponentHandler::restartComponent`.
    #[derive(Clone, Copy)]
    struct RestartFlags: i32 {
        const PARAM_VALUES_CHANGED = 1 << 2;
    }
}

/// The host application and component handler handed to every plugin.
#[derive(Default)]
pub(super) struct Host {
    /// Parameter edits made in the plugin's editor, waiting to be passed on.
    /// Each with whether it came inside `beginEdit` and `endEdit`: a
    /// person's move, not the plugin telling of a value it took on itself.
    pub(super) edits: RefCell<Vec<(ParamID, f64, bool)>>,
    /// The parameters between `beginEdit` and `endEdit` now.
    pub(super) gestures: RefCell<Vec<ParamID>>,
    /// The plugin says its parameter values changed wholesale.
    pub(super) rescan: Cell<bool>,
    /// The processor has to be run again, though its tail has gone by: it
    /// was given a state, which some plugins (JUCE ones, Surge XT) only
    /// take on in their next block.
    pub(super) wake: AtomicBool,
    /// Blocks the processor has run, to tell when it has taken on a state.
    pub(super) blocks: Blocks,
    pub(super) watches: RunLoop,
}

impl Class for Host {
    type Interfaces = (IHostApplication, IComponentHandler, IRunLoop);
}

impl IHostApplicationTrait for Host {
    unsafe fn getName(&self, name: *mut String128) -> tresult {
        // SAFETY: The plugin passes a non-null `String128` to write into, as the VST3 ABI requires.
        unsafe {
            for (slot, unit) in (*name).iter_mut().zip("paw\0".encode_utf16()) {
                *slot = unit as TChar;
            }
        }
        OK
    }

    unsafe fn createInstance(
        &self,
        _cid: *mut TUID,
        _iid: *mut TUID,
        obj: *mut *mut c_void,
    ) -> tresult {
        // SAFETY: The plugin passes a non-null `obj` to write the result to, as the VST3 ABI requires.
        unsafe { *obj = ptr::null_mut() };
        NO_INTERFACE
    }
}

impl IComponentHandlerTrait for Host {
    unsafe fn beginEdit(&self, id: ParamID) -> tresult {
        crate::debug_assert_main_thread();
        self.gestures.borrow_mut().push(id);
        OK
    }

    unsafe fn performEdit(&self, id: ParamID, value: ParamValue) -> tresult {
        crate::debug_assert_main_thread();
        let gesture = self.gestures.borrow().contains(&id);
        self.edits.borrow_mut().push((id, value, gesture));
        OK
    }

    unsafe fn endEdit(&self, id: ParamID) -> tresult {
        crate::debug_assert_main_thread();
        let mut gestures = self.gestures.borrow_mut();
        if let Some(at) = gestures.iter().position(|g| *g == id) {
            gestures.swap_remove(at);
        }
        OK
    }

    unsafe fn restartComponent(&self, flags: i32) -> tresult {
        crate::debug_assert_main_thread();
        if RestartFlags::from_bits_retain(flags).contains(RestartFlags::PARAM_VALUES_CHANGED) {
            self.rescan.set(true);
        }
        OK
    }
}

/// A callback object the plugin registered, compared by identity.
struct Handler<I: Interface>(ComPtr<I>);

impl<I: Interface> Clone for Handler<I> {
    fn clone(&self) -> Self {
        Handler(self.0.clone())
    }
}

impl<I: Interface> PartialEq for Handler<I> {
    fn eq(&self, other: &Self) -> bool {
        self.0.as_ptr() == other.0.as_ptr()
    }
}

/// The timers and file descriptors a plugin wants called back for. Plugins
/// look for the run loop on the editor's frame or on the host itself, so both
/// offer it and both lead here.
#[derive(Clone, Default)]
pub(super) struct RunLoop(Rc<RefCell<Watches<Handler<IEventHandler>, Handler<ITimerHandler>>>>);

impl RunLoop {
    fn add_fd(&self, handler: *mut IEventHandler, fd: i32) -> tresult {
        // SAFETY: The plugin passes a pointer to an `IEventHandler` it owns, or null (handled by `from_raw`);
        // `to_com_ptr` takes a counted reference, so the handler lives until it is unregistered.
        match unsafe { ComRef::from_raw(handler) } {
            Some(handler) => {
                self.0
                    .borrow_mut()
                    .fds
                    .push((fd, Handler(handler.to_com_ptr())));
                OK
            }
            None => FALSE,
        }
    }

    fn remove_fd(&self, handler: *mut IEventHandler) -> tresult {
        self.0
            .borrow_mut()
            .fds
            .retain(|(_, known)| known.0.as_ptr() != handler);
        OK
    }

    fn add_timer(&self, handler: *mut ITimerHandler, milliseconds: u64) -> tresult {
        // SAFETY: The plugin passes a pointer to an `ITimerHandler` it owns, or null (handled by `from_raw`);
        // `to_com_ptr` takes a counted reference, so the handler lives until it is unregistered.
        match unsafe { ComRef::from_raw(handler) } {
            Some(handler) => {
                self.0
                    .borrow_mut()
                    .add_timer(milliseconds, Handler(handler.to_com_ptr()));
                OK
            }
            None => FALSE,
        }
    }

    fn remove_timer(&self, handler: *mut ITimerHandler) -> tresult {
        self.0
            .borrow_mut()
            .timers_retain(|known| known.0.as_ptr() != handler);
        OK
    }

    /// Call back whatever has come due.
    pub(super) fn run(&self) {
        // Collect first: a handler may register or remove others while it runs.
        let (due, ready) = {
            let mut watches = self.0.borrow_mut();
            (watches.due_timers(), watches.ready_fds())
        };
        // SAFETY: The handlers were registered by the plugin and are held by counted references, so they
        // are live; they were collected first, so no borrow of `watches` is held while they run
        // (a handler may register or remove others). Main thread.
        unsafe {
            for handler in due {
                handler.0.onTimer();
            }
            for (fd, handler) in ready {
                handler.0.onFDIsSet(fd);
            }
        }
    }
}

macro_rules! run_loop_interface {
    ($class:ty) => {
        impl IRunLoopTrait for $class {
            unsafe fn registerEventHandler(&self, handler: *mut IEventHandler, fd: i32) -> tresult {
                self.watches.add_fd(handler, fd)
            }

            unsafe fn unregisterEventHandler(&self, handler: *mut IEventHandler) -> tresult {
                self.watches.remove_fd(handler)
            }

            unsafe fn registerTimer(
                &self,
                handler: *mut ITimerHandler,
                milliseconds: u64,
            ) -> tresult {
                self.watches.add_timer(handler, milliseconds)
            }

            unsafe fn unregisterTimer(&self, handler: *mut ITimerHandler) -> tresult {
                self.watches.remove_timer(handler)
            }
        }
    };
}

run_loop_interface!(Host);
run_loop_interface!(Frame);

/// What a plugin's editor is given as its frame: somewhere to ask for a new
/// size, and the run loop.
pub(super) struct Frame {
    pub(super) resize: Cell<Option<(u32, u32)>>,
    pub(super) watches: RunLoop,
}

impl Class for Frame {
    type Interfaces = (IPlugFrame, IRunLoop);
}

impl IPlugFrameTrait for Frame {
    unsafe fn resizeView(&self, _view: *mut IPlugView, size: *mut ViewRect) -> tresult {
        // SAFETY: The plugin passes a pointer to a live `ViewRect` it owns for the call.
        let size = unsafe { &*size };
        self.resize.set(Some((
            (size.right - size.left).max(1) as u32,
            (size.bottom - size.top).max(1) as u32,
        )));
        OK
    }
}
