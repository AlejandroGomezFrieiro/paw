//! The plugin instance that the device and the controller both hold.

use std::cell::RefCell;
use std::sync::{Arc, Mutex};

use clack_extensions::gui::PluginGui;
use clack_extensions::params::PluginParams;
use clack_extensions::posix_fd::PluginPosixFd;
use clack_extensions::state::PluginState;
use clack_extensions::tail::PluginTail;
use clack_extensions::timer::PluginTimer;
use clack_host::prelude::{
    ClapId, PluginAudioConfiguration, PluginAudioProcessor, PluginInstance, PluginInstanceError,
    PluginMainThreadHandle,
};
use clack_host::utils::Cookie;
use paw_engine::ParamInfo;

use super::host::{HostFlags, PawHost};
use super::library::Library;

/// The plugin instance and what both halves need to reach it.
pub(super) struct Shared {
    /// The plugin, through Clack. Main thread only (see the `Send` and
    /// `Sync` notes below): created, activated, deactivated and destroyed
    /// there.
    pub(super) instance: RefCell<PluginInstance<PawHost>>,
    /// The plugin's extensions that are called often, asked for once.
    pub(super) ext: PluginExtensions,
    /// The CLAP id and cookie of each parameter, in the order we list them.
    pub(super) param_ids: Vec<(ClapId, Cookie)>,
    pub(super) param_infos: Vec<ParamInfo>,
    pub(super) flags: Arc<HostFlags>,
    /// The plugin's audio processor while the plugin is active. The audio
    /// thread holds it while the plugin processes a block, and only tries
    /// it: it leaves the block to the plugin's stand-in when it cannot have
    /// it or finds none. The main thread takes the processor out to
    /// deactivate the plugin ([`Shared::deactivate`]) and puts a new one
    /// back when it activates it again ([`ClapController::stopped`](super::controller::ClapController::stopped)).
    pub(super) run: Mutex<Option<PluginAudioProcessor<PawHost>>>,
    pub(super) sample_rate: f64,
    pub(super) max_block: u32,
    // Kept alive for the plugin's preset-discovery factory.
    pub(super) _library: Arc<Library>,
}

// SAFETY: `PluginInstance` is not `Send` so that its main-thread functions are called from one
// thread. `instance`, and so every main-thread handle to the plugin, is only used on the main
// thread: `ClapFactory::create` makes the `Shared` there, the controller lives there, and both
// halves are dropped there (the engine drops a device on the main thread once the audio thread
// has let it go). The audio thread reaches the plugin only through the processor in `run` (which
// is `Send`), `ext.tail` with the processor's handle while it holds `run`, and the atomics and
// mutexes in `flags`.
unsafe impl Send for Shared {}
// SAFETY: What the two threads share is `run` (a mutex), `flags` (atomics and mutexes) and the
// read-only `ext`, `param_ids`, `param_infos`, `sample_rate` and `max_block`. `instance` is a
// `RefCell` that only the main thread touches (see above), so no two threads borrow it at once.
unsafe impl Sync for Shared {}

/// The plugin's extensions that paw calls again and again, each `None` when
/// the plugin has none. The others are asked for when they are used.
#[derive(Clone, Copy)]
pub(super) struct PluginExtensions {
    pub(super) params: Option<PluginParams>,
    pub(super) state: Option<PluginState>,
    pub(super) gui: Option<PluginGui>,
    pub(super) timers: Option<PluginTimer>,
    pub(super) fds: Option<PluginPosixFd>,
    /// How long the plugin rings after its input stops, when it says.
    pub(super) tail: Option<PluginTail>,
}

impl PluginExtensions {
    pub(super) fn new(plugin: &PluginMainThreadHandle) -> Self {
        Self {
            params: plugin.get_extension(),
            state: plugin.get_extension(),
            gui: plugin.get_extension(),
            timers: plugin.get_extension(),
            fds: plugin.get_extension(),
            tail: plugin.get_extension(),
        }
    }
}

impl Shared {
    /// Run `f` with the plugin's main-thread handle. Main thread only, and
    /// not from inside another `on_main`.
    pub(super) fn on_main<R>(&self, f: impl FnOnce(&PluginMainThreadHandle) -> R) -> R {
        let mut instance = self.instance.borrow_mut();
        f(&instance.plugin_handle())
    }

    /// Activate the plugin: its audio processor, not processing yet.
    /// Main thread, with the plugin inactive.
    pub(super) fn activate(&self) -> Result<PluginAudioProcessor<PawHost>, PluginInstanceError> {
        let configuration = PluginAudioConfiguration {
            sample_rate: self.sample_rate,
            min_frames_count: 1,
            max_frames_count: self.max_block,
        };
        let processor = self.instance.borrow_mut().activate(|_, _| (), configuration)?;
        Ok(processor.into())
    }

    /// Stop the plugin processing and deactivate it, taking its processor
    /// out of `run`, which the caller holds. Main thread: `stop_processing`
    /// is called from here while the audio thread is held off, since the
    /// plugin may not be deactivated while it processes.
    pub(super) fn deactivate(&self, run: &mut Option<PluginAudioProcessor<PawHost>>) {
        if let Some(processor) = run.take() {
            self.instance.borrow_mut().deactivate(processor.into_stopped());
        }
    }
}

impl Drop for Shared {
    /// The last half is dropped, on the main thread: the plugin is
    /// deactivated if it is still active, then `instance` destroys it.
    fn drop(&mut self) {
        let run = self.run.get_mut().unwrap_or_else(|e| e.into_inner());
        if let Some(processor) = run.take() {
            self.instance.get_mut().deactivate(processor.into_stopped());
        }
    }
}
