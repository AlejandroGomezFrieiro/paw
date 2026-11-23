//! The main-thread half of a CLAP plugin: its parameters, the changes it
//! reports, the calls paw makes to it, and the attachments that took it.

use std::ffi::{CStr, CString, c_char, c_void};
use std::ptr;
use std::sync::Arc;
use std::sync::atomic::{Ordering, Ordering::Relaxed};

use anyhow::{Context, Result, bail};
use clack_extensions::render::{PluginRender, RenderMode};
use clack_host::extensions::{Extension, PluginExtensionSide, RawExtension};
use clack_host::prelude::{PluginInstanceError, PluginMainThreadHandle};
use clap_sys::id::clap_id;
use clap_sys::plugin::clap_plugin;
use paw_engine::device::Change;
use paw_engine::{Controller, ParamInfo, Ports};

use super::factory::{note_names, value_text};
use super::shared::Shared;
use super::state::load_preset;
use crate::echo::Echo;
use crate::window::HostWindow;

/// The main-thread half of a CLAP plugin, which the engine's controller
/// calls are made on.
pub(super) struct ClapController {
    pub(super) shared: Arc<Shared>,
    pub(super) plugin_id: String,
    /// The plugin's own presets, found once asked for.
    pub(super) presets: Option<Vec<crate::presets::Preset>>,
    pub(super) changes: rtrb::Consumer<(clap_id, f64, bool, bool)>,
    /// Tells the echo of a state from an edit.
    pub(super) echo: Echo,
    /// When it was last given a state, the mark of its blocks: its values
    /// are read again once a block after it is done.
    pub(super) reread: Option<u64>,
    /// The last value seen for each parameter, to tell what a rescan changed.
    pub(super) known: Vec<f64>,
    /// The open editor: in one of our windows, or (`None` inside) floating in
    /// a window the plugin made itself.
    pub(super) editor: Option<Option<HostWindow>>,
    pub(super) ports: Ports,
    /// The attachments that took the plugin (`attach.rs`).
    pub(super) attached: Vec<crate::attach::Attached>,
    /// Why the plugin stopped: it asked to be restarted, and did not
    /// activate again. It stays deactivated, and [`health`] says so.
    ///
    /// [`health`]: Controller::health
    pub(super) failed: Option<String>,
}

impl ClapController {
    /// The plugin was given a state (or a preset, or a request that may
    /// set its parameters): what it holds now, and again after its next
    /// block, is what it tells of its values for the echo.
    pub(super) fn given_state(&mut self) {
        let values: Vec<Option<f64>> = (0..self.known.len()).map(|i| self.value(i)).collect();
        self.echo.given(values);
        self.reread = Some(self.shared.flags.blocks.mark());
        self.shared.flags.loads.fetch_add(1, Ordering::Release);
    }
}

impl Controller for ClapController {
    fn set_offline(&mut self, offline: bool) {
        let mode = if offline {
            RenderMode::Offline
        } else {
            RenderMode::Realtime
        };
        self.shared.on_main(|plugin| {
            if let Some(render) = plugin.get_extension::<PluginRender>() {
                let _ = render.set(plugin, mode);
            }
        });
    }

    fn params(&self) -> Vec<ParamInfo> {
        self.shared.param_infos.clone()
    }

    fn ports(&self) -> Ports {
        self.ports.clone()
    }

    fn value_text(&mut self, index: usize, value: f64) -> Option<String> {
        let (id, _) = *self.shared.param_ids.get(index)?;
        let params = self.shared.ext.params?;
        self.shared.on_main(|plugin| value_text(plugin, params, id, value))
    }

    fn text_value(&mut self, index: usize, text: &str) -> Option<f64> {
        let (id, _) = *self.shared.param_ids.get(index)?;
        let params = self.shared.ext.params?;
        let text = CString::new(text).ok()?;
        self.shared
            .on_main(|plugin| params.text_to_value(plugin, id, &text))
            .filter(|v| v.is_finite())
    }

    fn value(&self, index: usize) -> Option<f64> {
        let params = self.shared.ext.params?;
        let (id, _) = *self.shared.param_ids.get(index)?;
        self.shared.on_main(|plugin| params.get_value(plugin, id))
    }

    fn save_state(&mut self) -> Result<Option<Vec<u8>>> {
        self.save_plugin_state()
    }

    fn load_state(&mut self, state: &[u8]) -> Result<()> {
        self.load_plugin_state(state)
    }

    fn idle(&mut self) {
        let flags = &self.shared.flags;
        if flags.callback.swap(false, Relaxed) {
            self.shared.instance.borrow_mut().call_on_main_thread_callback();
        }
        // The plugin asked to be deactivated and activated again (`request_restart`),
        // as after a change of its latency. `stopped` wakes it and the engine,
        // so that it starts to process again in the next block.
        if flags.restart.swap(false, Relaxed)
            && self.failed.is_none()
            && let Err(err) = self.stopped(|| ())
        {
            self.failed = Some(format!("it did not restart: {err}"));
        }
        self.run_editor();
    }

    fn set_waker(&mut self, waker: paw_engine::Waker) {
        // Set once: a device goes into one engine.
        let _ = self.shared.flags.engine.set(waker);
    }

    fn set_bell(&mut self, bell: paw_engine::Bell) {
        // Set once: a device goes into one session.
        let _ = self.shared.flags.bell.set(bell);
    }

    fn wants_idle(&self) -> bool {
        let flags = &self.shared.flags;
        self.editor_open() || self.state_pending() || flags.callback.load(Relaxed) || flags.restart.load(Relaxed)
    }

    fn health(&mut self) -> Option<String> {
        self.failed.clone()
    }

    fn state_pending(&self) -> bool {
        self.reread.is_some_and(|mark| !self.shared.flags.blocks.after(mark))
    }

    fn take_changes(&mut self) -> Vec<Change> {
        let mut out = Vec::new();
        // A plugin that takes a state on only in its next block has its
        // new values only then: read them back, as the echo they are.
        if let Some(mark) = self.reread
            && self.shared.flags.blocks.after(mark)
        {
            self.reread = None;
            let values: Vec<Option<f64>> = (0..self.known.len()).map(|i| self.value(i)).collect();
            for (index, value) in values.iter().enumerate() {
                if let Some(value) = *value
                    && value != self.known[index]
                {
                    let first = self.known[index].is_nan();
                    self.known[index] = value;
                    if !first {
                        out.push(Change {
                            index,
                            value,
                            edit: false,
                        });
                    }
                }
            }
            self.echo.given(values);
        }
        // Changes the plugin reported while processing.
        while let Ok((id, value, gesture, taking)) = self.changes.pop() {
            if let Some(index) = self
                .shared
                .param_ids
                .iter()
                .position(|(known, _)| known.get() == id)
            {
                self.known[index] = value;
                // Told with no gesture in the block that took a state on:
                // the state's values.
                out.push(if !gesture && taking {
                    self.echo.state(index, value)
                } else {
                    self.echo.change(index, value, gesture)
                });
            }
        }
        // And a request to read everything again, as after loading a preset.
        if self.shared.flags.rescan.swap(false, Relaxed) {
            for index in 0..self.known.len() {
                if let Some(value) = self.value(index)
                    && value != self.known[index]
                {
                    // The first reading only records where things stand.
                    let first = self.known[index].is_nan();
                    self.known[index] = value;
                    if !first {
                        out.push(self.echo.change(index, value, false));
                    }
                }
            }
        }
        out
    }

    fn has_editor(&self) -> bool {
        self.editor_api().is_some()
    }

    fn editor_open(&self) -> bool {
        self.editor.is_some()
    }

    fn open_editor(&mut self, title: &str) -> Result<()> {
        self.open_window(title)
    }

    fn close_editor(&mut self) {
        self.close_window();
    }

    fn call(&mut self, method: &str, data: &[u8]) -> Result<Vec<u8>> {
        if let Some(answer) = self.call_attached(method, data) {
            return answer;
        }
        match method {
            paw_engine::device::method::PRESETS => {
                let presets = self.presets.get_or_insert_with(|| {
                    crate::presets::clap_presets(&self.shared._library.entry, &self.plugin_id)
                });
                Ok(crate::presets::to_json(presets))
            }
            paw_engine::device::method::PRESET_LOAD => {
                self.shared.on_main(|plugin| load_preset(plugin, data))?;
                // What the preset changed is read back, as the echo of a
                // state.
                self.shared.flags.rescan.store(true, Relaxed);
                self.given_state();
                Ok(Vec::new())
            }
            paw_engine::device::method::NOTE_NAMES => Ok(self.shared.on_main(note_names)),
            _ => {
                let (ok, answer) = self.shared.on_main(|plugin| {
                    let ext = plugin
                        .get_extension::<PawCall>()
                        .filter(|ext| ext.can_call(plugin))
                        .with_context(|| format!("this device has no method `{method}`"))?;
                    let name = CString::new(method)?;
                    anyhow::Ok(ext.call(plugin, &name, data))
                })?;
                // What the plugin read or loaded may have changed its parameters.
                self.shared.flags.rescan.store(true, Relaxed);
                if !ok {
                    bail!("{}", String::from_utf8_lossy(&answer));
                }
                Ok(answer)
            }
        }
    }
}

impl ClapController {
    /// Offer a call to the attachments that took the plugin: `None` when
    /// none of them knows the method. The methods paw itself sends
    /// (`paw.clips`, `paw.file.save`, `paw.file.load`) go only to them.
    fn call_attached(&mut self, method: &str, data: &[u8]) -> Option<Result<Vec<u8>>> {
        use crate::attach::{CALL_DONE, CALL_FAILED, CALL_STOPPED};
        let ours = method.starts_with("paw.");
        let unknown = || Err(anyhow::anyhow!("this device has no method `{method}`"));
        if self.attached.is_empty() {
            return ours.then(unknown);
        }
        match method {
            // Each attachment's file, by its name.
            "paw.file.save" => {
                let mut files = Vec::new();
                for attached in &self.attached {
                    let (code, bytes) = attached.call(method, data);
                    if code == CALL_DONE && !bytes.is_empty() {
                        files.push((attached.name().to_string(), bytes));
                    }
                }
                return Some(Ok(paw_engine::device::pack_files(&files)));
            }
            "paw.file.load" => {
                let files = match paw_engine::device::unpack_files(data) {
                    Ok(files) => files,
                    Err(err) => return Some(Err(err)),
                };
                for (name, bytes) in files {
                    let Some(index) = self.attached.iter().position(|a| a.name() == name) else {
                        continue;
                    };
                    if let Err(err) = self.ask(index, method, &bytes) {
                        return Some(Err(err));
                    }
                }
                return Some(Ok(Vec::new()));
            }
            _ => {}
        }
        for index in 0..self.attached.len() {
            let (code, answer) = self.attached[index].call(method, data);
            match code {
                CALL_DONE => return Some(Ok(answer)),
                CALL_FAILED => return Some(Err(failure(answer))),
                CALL_STOPPED => return Some(self.ask_stopped(index, method, data)),
                _ => {}
            }
        }
        ours.then(unknown)
    }

    /// One attachment's answer to a call, stopping the plugin if it asks.
    fn ask(&mut self, index: usize, method: &str, data: &[u8]) -> Result<Vec<u8>> {
        use crate::attach::{CALL_DONE, CALL_FAILED, CALL_STOPPED};
        let (code, answer) = self.attached[index].call(method, data);
        match code {
            CALL_DONE => Ok(answer),
            CALL_FAILED => Err(failure(answer)),
            CALL_STOPPED => self.ask_stopped(index, method, data),
            _ => bail!("this device has no method `{method}`"),
        }
    }

    fn ask_stopped(&mut self, index: usize, method: &str, data: &[u8]) -> Result<Vec<u8>> {
        use crate::attach::{CALL_DONE, CALL_FAILED};
        let attached = &self.attached[index];
        let (code, answer) = self.stopped(|| attached.call(method, data))?;
        match code {
            CALL_DONE => Ok(answer),
            CALL_FAILED => Err(failure(answer)),
            _ => bail!("`{method}` was not done with the plugin stopped"),
        }
    }

    /// Run `f` with the plugin deactivated, the audio thread held off it,
    /// then activate it again. The audio thread starts it processing anew;
    /// its `stop_processing` is called from here, while the audio thread
    /// waits, since the plugin may not be deactivated while it processes.
    pub(super) fn stopped<R>(&self, f: impl FnOnce() -> R) -> Result<R> {
        let shared = &self.shared;
        let mut run = shared.run.lock().unwrap_or_else(|e| e.into_inner());
        shared.deactivate(&mut run);
        let result = f();
        *run = Some(shared.activate().map_err(|err| match err {
            PluginInstanceError::NullActivateFunction => anyhow::anyhow!("no activate"),
            _ => anyhow::anyhow!("the plugin failed to activate again"),
        })?);
        shared.flags.wake();
        Ok(result)
    }
}

/// An attachment's reason for a failure.
fn failure(answer: Vec<u8>) -> anyhow::Error {
    let text = String::from_utf8_lossy(&answer).into_owned();
    if text.is_empty() {
        anyhow::anyhow!("the attachment failed")
    } else {
        anyhow::anyhow!(text)
    }
}

impl Drop for ClapController {
    fn drop(&mut self) {
        self.close_editor();
        // Attachments let go of the plugin while it is still there, and not
        // active: it is not processed again.
        if !self.attached.is_empty() {
            let mut run = self.shared.run.lock().unwrap_or_else(|e| e.into_inner());
            self.shared.deactivate(&mut run);
            self.attached.clear();
        }
    }
}

/// paw's own extension, for plugins that answer `device_call` methods the
/// host does not know (paw's sampler answers `describe`): the plugin
/// writes its answer through `write`, and returns false when the method
/// failed, having written why.
#[derive(Clone, Copy)]
struct PawCall(RawExtension<PluginExtensionSide, PawPluginCall>);

// SAFETY: `dev.paw.call/1` is paw's own id, and the table it names is `PawPluginCall`.
unsafe impl Extension for PawCall {
    const IDENTIFIERS: &'static [&'static CStr] = &[c"dev.paw.call/1"];
    type ExtensionSide = PluginExtensionSide;

    unsafe fn from_raw(raw: RawExtension<PluginExtensionSide>) -> Self {
        // SAFETY: The caller gives the table that the id names.
        Self(unsafe { raw.cast() })
    }
}

impl PawCall {
    /// Whether the table has its function.
    fn can_call(&self, plugin: &PluginMainThreadHandle) -> bool {
        plugin.use_extension(&self.0).call.is_some()
    }

    /// Call `method` with `data`: whether it succeeded, and what the plugin
    /// wrote (its answer, or why it failed).
    fn call(&self, plugin: &PluginMainThreadHandle, method: &CStr, data: &[u8]) -> (bool, Vec<u8>) {
        let mut answer: Vec<u8> = Vec::new();
        let Some(call) = plugin.use_extension(&self.0).call else {
            return (false, answer);
        };
        // SAFETY: `call` is the plugin's own function, called on the main thread with its own
        // plugin; `method`, `data` and `answer` live through the call, and `call_write` is the
        // callback type the extension expects, writing into `answer`.
        let ok = unsafe {
            call(
                plugin.as_raw_ptr(),
                method.as_ptr(),
                data.as_ptr(),
                data.len(),
                ptr::from_mut(&mut answer).cast(),
                Some(call_write),
            )
        };
        (ok, answer)
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
struct PawPluginCall {
    call: Option<
        unsafe extern "C" fn(
            plugin: *const clap_plugin,
            method: *const c_char,
            data: *const u8,
            size: usize,
            out: *mut c_void,
            write: Option<unsafe extern "C" fn(out: *mut c_void, data: *const u8, size: usize)>,
        ) -> bool,
    >,
}

unsafe extern "C" fn call_write(out: *mut c_void, data: *const u8, size: usize) {
    if out.is_null() || data.is_null() {
        return;
    }
    // SAFETY: `out` is the `Vec<u8>` that `call` passed and is alive during the call; `data` is non-null
    // (checked above) and the plugin owns it for `size` bytes.
    unsafe { (*(out as *mut Vec<u8>)).extend_from_slice(std::slice::from_raw_parts(data, size)) };
}
