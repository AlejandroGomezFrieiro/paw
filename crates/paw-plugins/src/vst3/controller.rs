//! The main-thread half of a VST3 plugin: its parameters, the processing
//! mode, and the changes its controller reports.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::Ordering;

use anyhow::Result;
use paw_engine::device::Change;
use paw_engine::{Controller, ParamInfo, Ports};
use vst3::Steinberg::Vst::*;

use super::editor::Editor;
use super::shared::Shared;
use super::state::{Stream, stream_ptr};
use super::{OFFLINE, OK, REALTIME, SAMPLE_32, wide};
use crate::echo::Echo;

/// The main-thread half of a VST3 plugin, which the engine's controller
/// calls are made on.
pub(super) struct Vst3Controller {
    pub(super) shared: Arc<Shared>,
    /// Where this plugin's `.vstpreset` files are, and the class id they name.
    pub(super) preset_dirs: Vec<PathBuf>,
    pub(super) class: String,
    pub(super) edits: rtrb::Producer<(u32, f32)>,
    /// The last value seen for each parameter, to tell what a rescan changed.
    pub(super) known: Vec<f64>,
    /// Tells the echo of a state from an edit.
    pub(super) echo: Echo,
    /// When it was last given a state, the mark of its blocks: the
    /// controller reads the state again once a block after it is done.
    pub(super) reread: Option<u64>,
    /// Values a state gave the controller, to report as its echo.
    pub(super) reported: Vec<Change>,
    pub(super) editor: Option<Editor>,
    pub(super) ports: Ports,
}

impl Vst3Controller {
    /// What the controller holds now is what the plugin tells of its
    /// values for the echo of a state.
    pub(super) fn expect_values(&mut self) {
        let values: Vec<Option<f64>> = (0..self.known.len()).map(|i| self.value(i)).collect();
        self.echo.given(values);
    }
}

impl Drop for Vst3Controller {
    fn drop(&mut self) {
        self.close_editor();
    }
}

impl Controller for Vst3Controller {
    fn ports(&self) -> Ports {
        self.ports.clone()
    }

    fn set_offline(&mut self, offline: bool) {
        // The mode is part of the processing setup, which can only be
        // changed while the processor is stopped.
        crate::debug_assert_main_thread();
        let shared = &self.shared;
        // The audio thread waits at most one block for the lock, and then
        // leaves the blocks alone until it is let go.
        let _held = shared.run.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: The calls are on the main thread, and `shared.run` is held, so the audio thread is
        // not in `process` while the processor is stopped, set up and started again, as VST3 wants.
        unsafe {
            shared.processor.setProcessing(0);
            shared.component.setActive(0);
            let mut setup = ProcessSetup {
                processMode: if offline { OFFLINE } else { REALTIME },
                symbolicSampleSize: SAMPLE_32,
                maxSamplesPerBlock: shared.max_block,
                sampleRate: shared.sample_rate,
            };
            if shared.processor.setupProcessing(&mut setup) == OK {
                shared.offline.store(offline, Ordering::Relaxed);
            }
            shared.component.setActive(1);
            shared.processor.setProcessing(1);
        }
    }

    fn params(&self) -> Vec<ParamInfo> {
        self.shared.params.clone()
    }

    fn value_text(&mut self, index: usize, value: f64) -> Option<String> {
        let id = *self.shared.param_ids.get(index)?;
        let controller = self.shared.controller.as_ref()?;
        let mut text: String128 = [0; 128];
        // SAFETY: `controller` is live and `text` is a `String128` that the plugin fills; main thread.
        unsafe {
            (controller.getParamStringByValue(id, value, &mut text) == OK)
                .then(|| wide(&text))
                .filter(|t| !t.is_empty())
        }
    }

    fn text_value(&mut self, index: usize, text: &str) -> Option<f64> {
        let id = *self.shared.param_ids.get(index)?;
        let controller = self.shared.controller.as_ref()?;
        let mut units: Vec<TChar> = text.encode_utf16().map(|u| u as TChar).collect();
        units.push(0);
        let mut value = 0.0;
        // SAFETY: `controller` is live; `units` is NUL-terminated and lives through the call.
        unsafe {
            (controller.getParamValueByString(id, units.as_mut_ptr(), &mut value) == OK)
                .then_some(value)
                .filter(|v| v.is_finite())
        }
    }

    fn value(&self, index: usize) -> Option<f64> {
        let id = *self.shared.param_ids.get(index)?;
        // SAFETY: `controller` is a live COM object, called on the main thread.
        Some(unsafe { self.shared.controller.as_ref()?.getParamNormalized(id) })
    }

    fn set_value(&mut self, index: usize, value: f64) {
        if let (Some(&id), Some(controller)) =
            (self.shared.param_ids.get(index), &self.shared.controller)
        {
            // SAFETY: `controller` is a live COM object, called on the main thread.
            unsafe { controller.setParamNormalized(id, value) };
        }
    }

    fn idle(&mut self) {
        self.shared.host.watches.run();
        self.run_editor();
        // A processor that takes a state on in its next block (JUCE queues
        // it there) has its new values only then: the controller, which
        // read them from it as it was given the state, reads them again.
        // What changed is the echo of the state: the processor has it.
        if let Some(mark) = self.reread
            && self.shared.host.blocks.after(mark)
        {
            self.reread = None;
            if let Some(controller) = &self.shared.controller {
                let edits = self.shared.host.edits.borrow().len();
                // SAFETY: `component` and `controller` are live COM objects, called on the main thread; the
                // streams live through the calls.
                unsafe {
                    let state = Stream::new(Vec::new());
                    if self.shared.component.getState(stream_ptr(&state)) == OK {
                        state.pos.set(0);
                        controller.setComponentState(stream_ptr(&state));
                    }
                }
                // What the controller told of the state as it read it is
                // its echo, read below.
                let mut all = self.shared.host.edits.borrow_mut();
                let mut at = 0;
                all.retain(|(_, _, gesture)| {
                    at += 1;
                    at <= edits || *gesture
                });
            }
            for index in 0..self.known.len() {
                if let Some(value) = self.value(index)
                    && value != self.known[index]
                {
                    let first = self.known[index].is_nan();
                    self.known[index] = value;
                    if !first {
                        self.reported.push(Change {
                            index,
                            value,
                            edit: false,
                        });
                    }
                }
            }
            self.expect_values();
        }
    }

    fn take_changes(&mut self) -> Vec<Change> {
        let mut out = std::mem::take(&mut self.reported);
        // An echo of a state is not passed on to the processor, which has
        // the state already: an echo of a state given before an undo would
        // play the old value.
        for (id, value, gesture) in self.shared.host.edits.take() {
            if let Some(index) = self.shared.param_ids.iter().position(|known| *known == id) {
                let change = self.echo.change(index, value, gesture);
                // The controller already has the value; the processor does not.
                if change.edit {
                    let _ = self.edits.push((index as u32, value as f32));
                }
                self.known[index] = value;
                out.push(change);
            }
        }
        if self.shared.host.rescan.replace(false) {
            for index in 0..self.known.len() {
                if let Some(value) = self.value(index)
                    && value != self.known[index]
                {
                    // The first reading only records where things stand.
                    let first = self.known[index].is_nan();
                    self.known[index] = value;
                    if !first {
                        let change = self.echo.change(index, value, false);
                        if change.edit {
                            let _ = self.edits.push((index as u32, value as f32));
                        }
                        out.push(change);
                    }
                }
            }
        }
        out
    }

    fn has_editor(&self) -> bool {
        // Whether a view can actually be made is only known by trying.
        self.shared.controller.is_some()
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
        self.preset_call(method, data)
    }

    fn save_state(&mut self) -> Result<Option<Vec<u8>>> {
        self.save_plugin_state()
    }

    fn load_state(&mut self, state: &[u8]) -> Result<()> {
        self.load_plugin_state(state)
    }
}
