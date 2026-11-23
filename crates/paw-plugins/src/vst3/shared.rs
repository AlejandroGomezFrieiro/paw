//! The plugin's COM objects, which the device and the controller both hold.

use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};

use paw_engine::ParamInfo;
use vst3::Steinberg::Vst::*;
use vst3::Steinberg::*;
use vst3::{ComPtr, ComWrapper};

use super::host::Host;
use super::library::Module;

/// A plugin instance: its component, processor and controller, and what
/// both halves need to reach them.
pub(super) struct Shared {
    // Declared in the order they must be released: plugins object to the
    // component going away while its other interfaces are still held.
    pub(super) processor: ComPtr<IAudioProcessor>,
    pub(super) controller: Option<ComPtr<IEditController>>,
    pub(super) component: ComPtr<IComponent>,
    /// The controller is its own object, to be torn down separately.
    pub(super) separate: bool,
    pub(super) param_ids: Vec<ParamID>,
    pub(super) params: Vec<ParamInfo>,
    pub(super) host: ComWrapper<Host>,
    /// Rendering to a file, faster than real time.
    pub(super) offline: AtomicBool,
    /// Held by the audio thread while the processor runs a block, and by
    /// the main thread while it stops the processor to set it up again
    /// (`Vst3Controller::set_offline`): the audio thread only tries it,
    /// and leaves the block as it is (silence added for an instrument, the
    /// input passed through for an effect) when it cannot have it.
    pub(super) run: Mutex<()>,
    /// What the processor was set up with, to set it up again.
    pub(super) max_block: i32,
    pub(super) sample_rate: f64,
    pub(super) _module: Arc<Module>,
}

// SAFETY: The COM pointers are used under the VST3 threading rules: the audio thread calls only
// `processor.process`, holding `run`, and reads only `offline`, `param_ids` and the host's atomics
// (`wake`, `blocks`); every other call, every use of the host's `RefCell`s, `Cell` and `Rc`, and
// the drop are on the main thread (the convention named at `Module`), and the main thread stops,
// sets up or starts the processor only while it holds `run`.
unsafe impl Send for Shared {}
// SAFETY: See `Send`: what the two threads share is atomics, `run` and fields that do not change
// after creation; the rest is used from the main thread only.
unsafe impl Sync for Shared {}

impl Drop for Shared {
    fn drop(&mut self) {
        // SAFETY: The device has stopped and deactivated the component (`Vst3Device::drop`) before the last
        // reference goes, and this runs on the main thread; the connection and terminate calls are
        // made once, with live COM objects.
        unsafe {
            if self.separate
                && let Some(controller) = &self.controller
            {
                if let (Some(a), Some(b)) = (
                    self.component.cast::<IConnectionPoint>(),
                    controller.cast::<IConnectionPoint>(),
                ) {
                    a.disconnect(b.as_ptr());
                    b.disconnect(a.as_ptr());
                }
                controller.terminate();
            }
            self.component.terminate();
        }
    }
}
