//! The main-thread half of a VST3 plugin: its parameters, the processing
//! mode, and the changes its controller reports.

use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::Ordering;

use anyhow::Result;
use paw_engine::device::Change;
use paw_engine::{Controller, ParamInfo, Ports};
use vst3::ComPtr;
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
        crate::debug_assert_main_thread();
        let shared = &self.shared;
        // The audio thread waits at most one block for the lock, and then
        // leaves the blocks alone until it is let go.
        let _held = shared.run.lock().unwrap_or_else(|e| e.into_inner());
        let (block, rate) = (shared.max_block, shared.sample_rate);
        let mode = if offline { Processing::Offline } else { Processing::Realtime };
        // SAFETY: The call is on the main thread with the plugin's live objects, and `shared.run` is
        // held, so the audio thread is not in `process` while the processor is set up again.
        if unsafe { set_up_again(&shared.component, &shared.processor, block, rate, mode) } {
            shared.offline.store(offline, Ordering::Relaxed);
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

/// The processing mode of a VST3 setup.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Processing {
    /// `kRealtime`: blocks come at the speed of the sound.
    Realtime,
    /// `kOffline`: a render, where blocks come as fast as they are made.
    Offline,
}

/// Set the processor up again for blocks of at most `max_block` frames at
/// `sample_rate`, in `mode`, and give whether the plugin took the setup.
/// VST3 changes a processing setup only while the processor is stopped and
/// the component is inactive, so this stops both first and starts them
/// again after, also when the plugin refuses the setup.
///
/// # Safety
/// Call it on the main thread, with live objects of one plugin, while the
/// audio thread is not in `process` (hold `Shared::run`).
unsafe fn set_up_again(
    component: &ComPtr<IComponent>,
    processor: &ComPtr<IAudioProcessor>,
    max_block: i32,
    sample_rate: f64,
    mode: Processing,
) -> bool {
    let mut setup = ProcessSetup {
        processMode: match mode {
            Processing::Offline => OFFLINE,
            Processing::Realtime => REALTIME,
        },
        symbolicSampleSize: SAMPLE_32,
        maxSamplesPerBlock: max_block,
        sampleRate: sample_rate,
    };
    // SAFETY: The caller keeps the contract above; `setup` lives through the call.
    unsafe {
        processor.setProcessing(0);
        component.setActive(0);
        let took = processor.setupProcessing(&mut setup) == OK;
        component.setActive(1);
        processor.setProcessing(1);
        took
    }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;

    use vst3::Steinberg::Vst::ProcessModes_::{kOffline, kRealtime};
    use vst3::Steinberg::*;
    use vst3::{Class, ComWrapper};

    use super::*;

    /// A call of the host to the fake plugin.
    #[derive(Clone, Copy, Debug, PartialEq)]
    enum Call {
        Processing(bool),
        Active(bool),
        Setup(i32),
    }

    /// A plugin that records the calls that set up its processing (a spy),
    /// and does not implement the other calls.
    #[derive(Default)]
    struct Spy {
        calls: RefCell<Vec<Call>>,
    }

    impl Spy {
        fn push(&self, call: Call) -> tresult {
            self.calls.borrow_mut().push(call);
            OK
        }
    }

    impl Class for Spy {
        type Interfaces = (IComponent, IAudioProcessor);
    }

    impl IPluginBaseTrait for Spy {
        unsafe fn initialize(&self, _context: *mut FUnknown) -> tresult {
            OK
        }
        unsafe fn terminate(&self) -> tresult {
            OK
        }
    }

    impl IComponentTrait for Spy {
        unsafe fn getControllerClassId(&self, _class_id: *mut TUID) -> tresult {
            kNotImplemented
        }
        unsafe fn setIoMode(&self, _mode: IoMode) -> tresult {
            kNotImplemented
        }
        unsafe fn getBusCount(&self, _kind: MediaType, _dir: BusDirection) -> int32 {
            0
        }
        unsafe fn getBusInfo(
            &self,
            _kind: MediaType,
            _dir: BusDirection,
            _index: int32,
            _bus: *mut BusInfo,
        ) -> tresult {
            kNotImplemented
        }
        unsafe fn getRoutingInfo(&self, _in: *mut RoutingInfo, _out: *mut RoutingInfo) -> tresult {
            kNotImplemented
        }
        unsafe fn activateBus(
            &self,
            _kind: MediaType,
            _dir: BusDirection,
            _index: int32,
            _state: TBool,
        ) -> tresult {
            kNotImplemented
        }
        unsafe fn setActive(&self, state: TBool) -> tresult {
            self.push(Call::Active(state != 0))
        }
        unsafe fn setState(&self, _state: *mut IBStream) -> tresult {
            kNotImplemented
        }
        unsafe fn getState(&self, _state: *mut IBStream) -> tresult {
            kNotImplemented
        }
    }

    impl IAudioProcessorTrait for Spy {
        unsafe fn setBusArrangements(
            &self,
            _inputs: *mut SpeakerArrangement,
            _ins: int32,
            _outputs: *mut SpeakerArrangement,
            _outs: int32,
        ) -> tresult {
            kNotImplemented
        }
        unsafe fn getBusArrangement(
            &self,
            _dir: BusDirection,
            _index: int32,
            _arrangement: *mut SpeakerArrangement,
        ) -> tresult {
            kNotImplemented
        }
        unsafe fn canProcessSampleSize(&self, _size: int32) -> tresult {
            OK
        }
        unsafe fn getLatencySamples(&self) -> uint32 {
            0
        }
        unsafe fn setupProcessing(&self, setup: *mut ProcessSetup) -> tresult {
            // SAFETY: The host gives a live setup for the length of the call.
            self.push(Call::Setup(unsafe { (*setup).processMode }))
        }
        unsafe fn setProcessing(&self, state: TBool) -> tresult {
            self.push(Call::Processing(state != 0))
        }
        unsafe fn process(&self, _data: *mut ProcessData) -> tresult {
            kNotImplemented
        }
        unsafe fn getTailSamples(&self) -> uint32 {
            0
        }
    }

    /// The calls that a plugin gets when `Vst3Controller::set_offline`
    /// sets it up in `mode`.
    fn calls_to_set_up(mode: Processing) -> Vec<Call> {
        let spy = ComWrapper::new(Spy::default());
        let component = spy.to_com_ptr::<IComponent>().unwrap();
        let processor = spy.to_com_ptr::<IAudioProcessor>().unwrap();
        // SAFETY: The test thread is the only thread, and the objects are live.
        assert!(unsafe { set_up_again(&component, &processor, 512, 48000.0, mode) });
        spy.calls.take()
    }

    #[test]
    fn a_render_sets_the_processor_up_offline_and_then_realtime_again() {
        let stop = [Call::Processing(false), Call::Active(false)];
        let start = [Call::Active(true), Call::Processing(true)];
        for (mode, vst3_mode) in [(Processing::Offline, kOffline), (Processing::Realtime, kRealtime)] {
            let want = [&stop[..], &[Call::Setup(vst3_mode as i32)], &start[..]].concat();
            assert_eq!(calls_to_set_up(mode), want, "set up in {mode:?}");
        }
    }
}
