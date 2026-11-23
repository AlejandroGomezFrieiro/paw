//! The creation of a plugin instance: its component, controller and
//! processor, set up on the main thread, and the parameters it shows.

use std::path::PathBuf;
use std::ptr;
use std::sync::atomic::AtomicBool;
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result, bail};
use paw_engine::device::{Rest, assign_keys};
use paw_engine::{DeviceFactory, DeviceInfo, Instance, ParamInfo, Ports};
use vst3::Steinberg::Vst::*;
use vst3::Steinberg::*;
use vst3::{ComPtr, ComWrapper, Interface};

use super::controller::Vst3Controller;
use super::device::{Buses, Vst3Device};
use super::events::{Discard, EventList, NO_PARAM, ParamChanges};
use super::host::Host;
use super::library::load;
use super::shared::Shared;
use super::state::{Stream, stream_ptr};
use super::{EVENT, INPUT, OK, OUTPUT, REALTIME, SAMPLE_32, wide};
use crate::HeldNotes;
use crate::echo::Echo;

bitflags::bitflags! {
    /// `ParameterInfo::flags`.
    #[derive(Clone, Copy)]
    struct ParamFlags: i32 {
        const CAN_AUTOMATE = 1 << 0;
        const READ_ONLY = 1 << 1;
        const IS_LIST = 1 << 3;
        const HIDDEN = 1 << 4;
    }
}

/// A VST3 plugin class of a bundle, which makes instances of it.
pub(super) struct Vst3Factory {
    pub(super) info: DeviceInfo,
    pub(super) bundle: PathBuf,
    pub(super) class: TUID,
    /// Where the libraries that the module needs are looked for.
    pub(super) libraries: Arc<[PathBuf]>,
    /// The roots of the `.vstpreset` files ([`crate::PluginDirs`]).
    pub(super) preset_roots: Arc<[PathBuf]>,
}

/// The parameters the controller shows: their ids, and what paw tells of
/// them.
///
/// # Safety
///
/// `controller` is a live, initialized controller. Main thread.
unsafe fn read_params(controller: &ComPtr<IEditController>) -> (Vec<ParamID>, Vec<ParamInfo>) {
    let (mut ids, mut params) = (Vec::new(), Vec::new());
    // SAFETY: `controller` is live (see `# Safety`); `getParameterInfo` is called with an index
    // below the count and a zeroed plain-data `ParameterInfo` that the plugin fills.
    unsafe {
        let units = unit_paths(controller);
        for index in 0..controller.getParameterCount() {
            let mut info: ParameterInfo = std::mem::zeroed();
            if controller.getParameterInfo(index, &mut info) != OK
                || ParamFlags::from_bits_retain(info.flags).intersects(ParamFlags::HIDDEN | ParamFlags::READ_ONLY)
            {
                continue;
            }
            let title = wide(&info.title);
            // JUCE plugins expose every MIDI controller on every channel
            // as a parameter: two thousand entries nobody sets by hand.
            if title.starts_with("MIDI CC ") {
                continue;
            }
            ids.push(info.id);
            let mut param =
                ParamInfo::new(&title, 0.0, 1.0, info.defaultNormalizedValue as f32, "");
            param.unit = wide(&info.units);
            param.id = info.id.to_string();
            param.group = units.get(&info.unitId).cloned().unwrap_or_default();
            param.automatable = ParamFlags::from_bits_retain(info.flags).contains(ParamFlags::CAN_AUTOMATE);
            param.steps = info.stepCount.max(0) as u32;
            param.enumeration = ParamFlags::from_bits_retain(info.flags).contains(ParamFlags::IS_LIST) && param.steps > 0;
            param.boolean = param.steps == 1 && !param.enumeration;
            params.push(param);
        }
    }
    assign_keys(&mut params);
    (ids, params)
}

/// The parameter each MIDI controller moves, as the device keeps it
/// (`Vst3Device::midi_map`). VST3 has no controller messages: a plugin
/// names the parameter each MIDI controller moves, and the host moves that
/// instead.
///
/// # Safety
///
/// `controller` is `None` or a live, initialized controller. Main thread.
unsafe fn midi_map(controller: Option<&ComPtr<IEditController>>) -> Box<[ParamID; 130]> {
    let mut midi_map = Box::new([NO_PARAM; 130]);
    if let Some(mapping) = controller.and_then(|c| c.cast::<IMidiMapping>()) {
        for (number, slot) in midi_map.iter_mut().enumerate() {
            let mut id: ParamID = 0;
            // SAFETY: `mapping` is the live controller's own interface (see `# Safety`), and
            // `id` is a live local that the plugin writes.
            if unsafe { mapping.getMidiControllerAssignment(0, 0, number as i16, &mut id) } == OK {
                *slot = id;
            }
        }
    }
    midi_map
}

/// The name of each of the controller's units (its groups of
/// parameters), with those it is in before it: "Osc 1/Pitch". The root
/// unit has no name.
unsafe fn unit_paths(controller: &ComPtr<IEditController>) -> std::collections::HashMap<i32, String> {
    let mut parents = std::collections::HashMap::new();
    if let Some(units) = controller.cast::<IUnitInfo>() {
        // SAFETY: `controller` is a live COM object; `getUnitCount`/`getUnitInfo` are called with an index
        // below the count and a zeroed plain-data `UnitInfo` that the plugin fills. Main thread.
        unsafe {
            for index in 0..units.getUnitCount() {
                let mut info: UnitInfo = std::mem::zeroed();
                if units.getUnitInfo(index, &mut info) == OK && info.id != 0 {
                    parents.insert(info.id, (info.parentUnitId, wide(&info.name)));
                }
            }
        }
    }
    let mut paths = std::collections::HashMap::new();
    for &id in parents.keys() {
        let mut names = Vec::new();
        let mut at = id;
        // A unit list that loops is cut at its length.
        while let Some((parent, name)) = parents.get(&at) {
            names.push(name.clone());
            if names.len() > parents.len() {
                break;
            }
            at = *parent;
        }
        names.reverse();
        paths.insert(id, names.join("/"));
    }
    paths
}

impl DeviceFactory for Vst3Factory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, max_block: usize) -> Result<Instance> {
        let module = load(&self.bundle, &self.libraries)?;
        // SAFETY: The factory is live; every COM call is made in the order the VST3 ABI requires
        // (createInstance, initialize, setComponentHandler, setupProcessing, setActive,
        // setProcessing) on the main thread, before the processor is shared with the audio thread;
        // the structs passed (`ProcessSetup`, zeroed plain data, `ParameterInfo`) live through each call.
        unsafe {
            let host = ComWrapper::new(Host::default());
            let context = host.as_com_ref::<IHostApplication>().unwrap().as_ptr() as *mut FUnknown;

            let mut raw = ptr::null_mut();
            module.factory.createInstance(
                self.class.as_ptr(),
                IComponent::IID.as_ptr().cast(),
                &mut raw,
            );
            let component: ComPtr<IComponent> =
                ComPtr::from_raw(raw.cast()).context("the plugin could not be created")?;
            if component.initialize(context) != OK {
                bail!("the plugin failed to initialize");
            }
            let processor = component
                .cast::<IAudioProcessor>()
                .context("the plugin does not process audio")?;

            // The controller is either the same object or a class of its own.
            let mut controller = component.cast::<IEditController>();
            let separate = controller.is_none();
            if separate {
                let mut class: TUID = [0; 16];
                let mut raw = ptr::null_mut();
                if component.getControllerClassId(&mut class) == OK {
                    module.factory.createInstance(
                        class.as_ptr(),
                        IEditController::IID.as_ptr().cast(),
                        &mut raw,
                    );
                }
                controller = ComPtr::from_raw(raw.cast());
                if let Some(controller) = &controller {
                    controller.initialize(context);
                    if let (Some(a), Some(b)) = (
                        component.cast::<IConnectionPoint>(),
                        controller.cast::<IConnectionPoint>(),
                    ) {
                        a.connect(b.as_ptr());
                        b.connect(a.as_ptr());
                    }
                }
            }
            let mut shared = Shared {
                processor,
                controller,
                component,
                separate,
                param_ids: Vec::new(),
                params: Vec::new(),
                host: host.clone(),
                offline: AtomicBool::new(false),
                run: Mutex::new(()),
                max_block: max_block as i32,
                sample_rate: sample_rate as f64,
                _module: module,
            };
            if let Some(controller) = &shared.controller {
                controller
                    .setComponentHandler(host.as_com_ref::<IComponentHandler>().unwrap().as_ptr());
                // Start the controller from the component's own state.
                let state = Stream::new(Vec::new());
                if shared.component.getState(stream_ptr(&state)) == OK {
                    state.pos.set(0);
                    controller.setComponentState(stream_ptr(&state));
                }
                (shared.param_ids, shared.params) = read_params(controller);
            }
            let midi_map = midi_map(shared.controller.as_ref());

            let inputs = Buses::new(&shared.component, INPUT, max_block);
            let outputs = Buses::new(&shared.component, OUTPUT, max_block);
            if shared.component.getBusCount(EVENT, INPUT) > 0 {
                shared.component.activateBus(EVENT, INPUT, 0, 1);
            }
            let mut setup = ProcessSetup {
                processMode: REALTIME,
                symbolicSampleSize: SAMPLE_32,
                maxSamplesPerBlock: max_block as i32,
                sampleRate: sample_rate as f64,
            };
            if shared.processor.setupProcessing(&mut setup) != OK {
                bail!("the plugin rejected the audio setup");
            }
            if shared.component.setActive(1) != OK {
                bail!("the plugin failed to activate");
            }
            shared.processor.setProcessing(1);
            // Frames the plugin rings for after its input stops: 0 for
            // none, all ones for for ever.
            let tail = shared.processor.getTailSamples();

            let shared = Arc::new(shared);
            let (edits, edited) = rtrb::RingBuffer::new(512);
            let out_pairs = crate::out_pairs(&outputs.infos);
            let ports = Ports {
                sidechain: inputs.key.is_some(),
                outputs: crate::pair_names(&out_pairs),
            };
            let device = Vst3Device {
                shared: shared.clone(),
                edited,
                inputs,
                outputs,
                keyed: false,
                out_pairs,
                events: ComWrapper::new(EventList::with_capacity(1024)),
                changes: ComWrapper::new(ParamChanges::new(128)),
                discard: ComWrapper::new(Discard::new()),
                pending: Vec::with_capacity(128),
                midi_map,
                controls: Vec::with_capacity(64),
                held: HeldNotes::new(),
                sample_rate: sample_rate as f64,
                samples: 0,
                tail,
                rest: Rest::default(),
            };
            let mut controller = Box::new(Vst3Controller {
                preset_dirs: crate::presets::vst3_preset_dirs(
                    &self.preset_roots,
                    &self.info.vendor,
                    &self.info.name,
                    Some(&self.bundle),
                ),
                class: hex::encode_upper(self.class.map(|b| b as u8)),
                known: vec![f64::NAN; shared.param_ids.len()],
                echo: Echo::default(),
                reread: None,
                reported: Vec::new(),
                shared,
                edits,
                editor: None,
                ports,
            });
            // What it starts with is a state too: its first words of its
            // values are no edit.
            controller.expect_values();
            Ok(Instance {
                device: Box::new(device),
                controller: Some(controller),
            })
        }
    }
}
