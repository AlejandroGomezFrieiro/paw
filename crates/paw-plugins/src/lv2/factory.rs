//! The factory that makes an LV2 plugin's device and controller.

use std::cell::{Cell, RefCell, UnsafeCell};
use std::collections::HashMap;
use std::ffi::{CStr, CString, c_void};
use std::sync::atomic::{AtomicBool, AtomicU32};
use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use anyhow::{Result, bail};
use paw_engine::{DeviceFactory, DeviceInfo, Instance, ParamInfo, Ports, Rest};
use lilv_sys::*;

use crate::echo::Echo;
use crate::HeldNotes;
use crate::lv2_patch::Property;
use super::*;
use super::world::*;
use super::atom::*;
use super::worker::*;
use super::shared::*;
use super::device::*;
use super::ui::*;
use super::controller::*;

pub(super) struct Lv2Factory {
    pub(super) info: DeviceInfo,
    pub(super) uri: String,
    /// Looked up in the lilv world on first use.
    pub(super) plugin: OnceLock<usize>,
    /// The folders that lilv's world reads, when this factory makes it.
    pub(super) folders: Arc<[PathBuf]>,
    /// Where the libraries that the editor needs are looked for.
    pub(super) libraries: Arc<[PathBuf]>,
}

impl Lv2Factory {
    pub(super) fn plugin(&self) -> Result<*const LilvPlugin> {
        if let Some(&p) = self.plugin.get() {
            return Ok(p as *const LilvPlugin);
        }
        let w = world_in(&self.folders);
        let uri = CString::new(self.uri.clone())?;
        // SAFETY: `w.world` is the live lilv world (it lives for the program); the node is made and freed
        // here, and the plugin it finds belongs to the world, not to the node.
        let found = unsafe {
            let node = lilv_new_uri(w.world, uri.as_ptr());
            let plugin = lilv_plugins_get_by_uri(lilv_world_get_all_plugins(w.world), node);
            lilv_node_free(node);
            plugin
        };
        if found.is_null() {
            bail!("the LV2 plugin {} is no longer installed", self.uri);
        }
        let _ = self.plugin.set(found as usize);
        Ok(found)
    }
}


/// The plugin's ports, as `create` sorts them: what each connects to, and
/// the buffers and parameters that come of them.
struct PortPlan {
    /// The value of each control port, by slot.
    controls: Vec<AtomicU32>,
    /// The slot of each parameter (an input control), and its description.
    param_slots: Vec<usize>,
    params: Vec<ParamInfo>,
    /// The slot of each input control, by its symbol.
    symbols: HashMap<CString, usize>,
    audio_in: Vec<Vec<f32>>,
    audio_out: Vec<Vec<f32>>,
    key_in: Vec<Vec<f32>>,
    /// The name of each audio output.
    out_names: Vec<String>,
    atoms: Vec<AtomBuffer>,
    /// Index in `atoms` of the input that takes MIDI, and of the one that
    /// takes the time position.
    midi_in: Option<usize>,
    time_in: Option<usize>,
    /// Each port's index, and what it connects to.
    plan: Vec<(u32, Connect)>,
}

/// Sort the plugin's ports: give each control a slot, each audio port a
/// buffer of `max_block` frames, and each atom port its buffer. An error
/// for a port of a kind this host does not know.
///
/// # Safety
///
/// `plugin` is a live plugin of the world `w`. Main thread.
unsafe fn plan_ports(plugin: *const LilvPlugin, w: &World, max_block: usize) -> Result<PortPlan> {
    // SAFETY: lilv calls on `plugin` and its ports, which the live world owns (see `# Safety`);
    // the three range arrays hold one value for each port, as lilv fills them; each symbol is
    // a NUL-terminated string of the port, copied before the next call.
    unsafe {
        let count = lilv_plugin_get_num_ports(plugin) as usize;
        let (mut mins, mut maxs, mut defaults) =
            (vec![0f32; count], vec![0f32; count], vec![0f32; count]);
        lilv_plugin_get_port_ranges_float(
            plugin,
            mins.as_mut_ptr(),
            maxs.as_mut_ptr(),
            defaults.as_mut_ptr(),
        );

        let mut ports = PortPlan {
            controls: Vec::new(),
            param_slots: Vec::new(),
            params: Vec::new(),
            symbols: HashMap::new(),
            audio_in: Vec::new(),
            audio_out: Vec::new(),
            key_in: Vec::new(),
            out_names: Vec::new(),
            atoms: Vec::new(),
            midi_in: None,
            time_in: None,
            plan: Vec::new(),
        };
        for index in 0..count {
            let port = lilv_plugin_get_port_by_index(plugin, index as u32);
            let is = |class| lilv_port_is_a(plugin, port, class);
            let input = is(w.input);
            if is(w.control) {
                let slot = ports.controls.len();
                let or = |v: f32, fallback: f32| if v.is_nan() { fallback } else { v };
                let (min, max) = (or(mins[index], 0.0), or(maxs[index], 1.0));
                let default = or(defaults[index], min).clamp(min.min(max), max.max(min));
                ports.controls.push(AtomicU32::new(default.to_bits()));
                let symbol =
                    CStr::from_ptr(lilv_node_as_string(lilv_port_get_symbol(plugin, port)))
                        .to_owned();
                if input {
                    let mut info = ParamInfo::new(&take_text(lilv_port_get_name(plugin, port)))
                        .range(min, max)
                        .default_value(default);
                    info.key = symbol.to_string_lossy().into_owned();
                    info.id = info.key.clone();
                    if lilv_port_has_property(plugin, port, w.toggled) {
                        info.choices = vec!["off".into(), "on".into()];
                        info.boolean = true;
                        info.steps = 1;
                    }
                    describe_port(plugin, port, w, &mut info);
                    ports.params.push(info);
                    ports.param_slots.push(slot);
                    ports.symbols.insert(symbol, slot);
                }
                ports.plan.push((index as u32, Connect::Control(slot)));
            } else if is(w.cv) {
                // Control voltage is not routed anywhere yet.
                ports.plan.push((index as u32, Connect::Spare));
            } else if is(w.audio) && input && takes_key(plugin, port, w) {
                ports.key_in.push(vec![0f32; max_block]);
                ports.plan.push((index as u32, Connect::Key(ports.key_in.len() - 1)));
            } else if is(w.audio) {
                let buffers = if input { &mut ports.audio_in } else { &mut ports.audio_out };
                if !input {
                    ports.out_names.push(take_text(lilv_port_get_name(plugin, port)));
                }
                buffers.push(vec![0f32; max_block]);
                ports.plan.push((index as u32, Connect::Audio(input, buffers.len() - 1)));
            } else if is(w.atom) {
                if input
                    && ports.midi_in.is_none()
                    && lilv_port_supports_event(plugin, port, w.midi_event)
                {
                    ports.midi_in = Some(ports.atoms.len());
                }
                if input
                    && ports.time_in.is_none()
                    && lilv_port_supports_event(plugin, port, w.time_position)
                {
                    ports.time_in = Some(ports.atoms.len());
                }
                ports.atoms.push(AtomBuffer::new(input));
                ports.plan.push((index as u32, Connect::Atom(ports.atoms.len() - 1)));
            } else {
                bail!("port {index} is of a kind this host does not know");
            }
        }
        Ok(ports)
    }
}

/// The index of each of the plugin's ports, by its symbol.
///
/// # Safety
///
/// `plugin` is a live plugin of the world. Main thread.
unsafe fn port_symbols(plugin: *const LilvPlugin) -> HashMap<CString, u32> {
    let mut port_symbols = HashMap::new();
    // SAFETY: lilv calls on the live `plugin` (see `# Safety`) with indexes below its port count;
    // each symbol is a NUL-terminated string of the port, copied at once.
    unsafe {
        for index in 0..lilv_plugin_get_num_ports(plugin) {
            let port = lilv_plugin_get_port_by_index(plugin, index);
            let symbol = CStr::from_ptr(lilv_node_as_string(lilv_port_get_symbol(plugin, port)));
            port_symbols.insert(symbol.to_owned(), index);
        }
    }
    port_symbols
}

/// The atom input that patch messages go to, when the plugin has
/// properties: the input that says it takes them, else the first one that
/// is not only for MIDI.
///
/// # Safety
///
/// `plugin` is a live plugin of the world `w`, and `atom_ports` are port
/// indexes of it. Main thread.
unsafe fn patch_port(
    plugin: *const LilvPlugin,
    w: &World,
    atom_ports: &[u32],
    atoms: &[AtomBuffer],
    properties: &[Property],
) -> Option<u32> {
    let atom_inputs: Vec<u32> = atom_ports
        .iter()
        .zip(atoms)
        .filter(|(_, atom)| atom.input)
        .map(|(port, _)| *port)
        .collect();
    let supports = |port: u32, what| {
        // SAFETY: `plugin` is live and `port` is one of its port indexes (see `# Safety`).
        unsafe {
            let p = lilv_plugin_get_port_by_index(plugin, port);
            lilv_port_supports_event(plugin, p, what)
        }
    };
    (!properties.is_empty())
        .then(|| {
            atom_inputs
                .iter()
                .find(|p| supports(**p, w.patch_message))
                .or_else(|| atom_inputs.iter().find(|p| !supports(**p, w.midi_event)))
                .or(atom_inputs.first())
                .copied()
        })
        .flatten()
}

/// The audio outputs two by two in their order, the main pair first, each
/// named after its left one.
fn out_pairs(out_names: &[String]) -> Vec<crate::OutPair> {
    (0..out_names.len())
        .step_by(2)
        .take(paw_engine::MAX_PAIRS)
        .map(|left| crate::OutPair {
            port: 0,
            left,
            right: (left + 1).min(out_names.len() - 1),
            name: side_less(&out_names[left]),
        })
        .collect()
}

impl DeviceFactory for Lv2Factory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, max_block: usize) -> Result<Instance> {
        let plugin = self.plugin()?;
        let w = world_in(&self.folders);
        // SAFETY: lilv calls on the live world and on `plugin`, which the world owns. `host` and `instance`
        // are owned by this function and then moved into `Shared`, whose Drop frees the instance
        // after the worker has stopped; `Shared` is built after all ports are connected. This block
        // is on the main thread, which is the one thread lilv may be called from.
        unsafe {
            let host = host_data(sample_rate, max_block);
            let instance = lilv_plugin_instantiate(
                plugin,
                sample_rate as f64,
                host.feature_list.as_ptr().cast(),
            );
            if instance.is_null() {
                bail!("the plugin could not be instantiated");
            }
            let PortPlan {
                controls,
                param_slots,
                params,
                symbols,
                mut audio_in,
                mut audio_out,
                mut key_in,
                out_names,
                mut atoms,
                midi_in,
                time_in,
                plan,
            } = match plan_ports(plugin, w, max_block) {
                Ok(ports) => ports,
                Err(err) => {
                    lilv_instance_free(instance);
                    return Err(err);
                }
            };

            let mut spare = vec![0f32; max_block];
            let controls: Box<[AtomicU32]> = controls.into();
            for (port, connect) in &plan {
                let location: *mut c_void = match *connect {
                    Connect::Control(slot) => controls[slot].as_ptr().cast(),
                    Connect::Audio(true, i) => audio_in[i].as_mut_ptr().cast(),
                    Connect::Audio(false, i) => audio_out[i].as_mut_ptr().cast(),
                    Connect::Key(i) => key_in[i].as_mut_ptr().cast(),
                    Connect::Atom(i) => atoms[i].data.as_mut_ptr().cast(),
                    Connect::Spare => spare.as_mut_ptr().cast(),
                };
                lilv_instance_connect_port(instance, *port, location);
            }

            let worker_interface: *const WorkerInterface =
                lilv_instance_get_extension_data(instance, WORKER_INTERFACE.as_ptr().cast()).cast();
            let mut atom_ports = vec![0; atoms.len()];
            let mut control_ports = Vec::new();
            for (port, connect) in &plan {
                match *connect {
                    Connect::Control(slot) => control_ports.push((*port, slot)),
                    Connect::Atom(index) => atom_ports[index] = *port,
                    _ => {}
                }
            }
            // The slot of the control port with this index.
            let slot_of = |index| control_ports.iter().find(|(port, _)| *port == index);
            // The port a plugin reads to know it is rendering offline.
            let wheel = lilv_plugin_get_port_by_designation(plugin, w.input, w.free_wheeling);
            let free_wheeling = (!wheel.is_null())
                .then(|| lilv_port_get_index(plugin, wheel))
                .and_then(slot_of)
                .map(|(_, slot)| *slot);
            let properties = find_properties(plugin, w);
            let patch_port = patch_port(plugin, w, &atom_ports, &atoms, &properties);
            let latency = lilv_plugin_has_latency(plugin)
                .then(|| lilv_plugin_get_latency_port_index(plugin))
                .and_then(slot_of)
                .map(|(_, slot)| *slot);
            let shared = Arc::new(Shared {
                plugin,
                instance,
                host,
                controls,
                param_slots,
                params,
                symbols,
                worker_interface,
                scratch: UnsafeCell::new(0.0),
                control_ports,
                free_wheeling,
                atom_ports,
                port_symbols: port_symbols(plugin),
                ui: find_ui(plugin, &self.libraries),
                ui_open: AtomicBool::new(false),
                properties,
                patch_port,
                latency,
                wake: AtomicBool::new(false),
            });
            if !worker_interface.is_null() {
                let handle = lilv_instance_get_handle(instance);
                let _ = shared
                    .host
                    .worker
                    .set(Worker::start(worker_interface, handle.cast()));
            }

            // Plugins may ship a default state that the host is meant to apply.
            let map = &shared.host.map as *const UridMap as *mut _;
            let default = lilv_state_new_from_world(w.world, map, lilv_plugin_get_uri(plugin));
            if !default.is_null() {
                restore(&shared, default);
                lilv_state_free(default);
            }

            lilv_instance_activate(instance);
            let (to_plugin, from_ui) = rtrb::RingBuffer::new(WORK_CAPACITY);
            let (to_ui, from_plugin) = rtrb::RingBuffer::new(WORK_CAPACITY);
            let out_pairs = out_pairs(&out_names);
            let ports = Ports {
                sidechain: !key_in.is_empty(),
                outputs: crate::pair_names(&out_pairs),
            };
            let device = Lv2Device {
                shared: shared.clone(),
                from_ui,
                to_ui,
                message: Vec::with_capacity(ATOM_CAPACITY),
                audio_in,
                audio_out,
                key_in,
                keyed: false,
                out_pairs,
                atoms,
                midi_in,
                time_in,
                time_sent: None,
                _spare: spare,
                held: HeldNotes::new(),
                response: Vec::with_capacity(WORK_CAPACITY),
                queued: Vec::with_capacity(QUEUED_CAPACITY),
                rest: Rest::default(),
                tail: (sample_rate as f64 * TAIL_SECONDS) as u64,
            };
            let mut controller = Lv2Controller {
                link: Box::new(UiLink {
                    shared: shared.clone(),
                    to_plugin: UnsafeCell::new(to_plugin),
                    changes: RefCell::new(Vec::new()),
                    resize: Cell::new(None),
                    closed: Cell::new(false),
                }),
                shared,
                from_plugin,
                message: Vec::with_capacity(ATOM_CAPACITY),
                ui: None,
                ports,
                values: HashMap::new(),
                echo: Echo::default(),
            };
            // Ask the plugin what its properties hold now.
            controller.ask_properties();
            Ok(Instance {
                device: Box::new(device),
                controller: Some(Box::new(controller)),
            })
        }
    }
}

/// A port's name without the side it carries, for the pair it begins.
fn side_less(name: &str) -> String {
    [" Left", " left", " L", " l"]
        .iter()
        .find_map(|side| name.strip_suffix(side))
        .unwrap_or(name)
        .to_string()
}

/// Whether an audio input takes a side-chain: it says so, or belongs to a
/// group that is the side-chain of another.
unsafe fn takes_key(plugin: *const LilvPlugin, port: *const LilvPort, w: &World) -> bool {
    // SAFETY: `plugin`, `port` and `w.world` are live lilv objects of the world; the node list `groups`
    // is owned by this function and freed before return.
    unsafe {
        if lilv_port_has_property(plugin, port, w.side_chain) {
            return true;
        }
        let groups = lilv_port_get_value(plugin, port, w.group);
        let mut keyed = false;
        let mut at = lilv_nodes_begin(groups);
        while !lilv_nodes_is_end(groups, at) {
            let group = lilv_nodes_get(groups, at);
            keyed |= lilv_world_ask(w.world, group, w.side_chain_of, std::ptr::null());
            at = lilv_nodes_next(groups, at);
        }
        lilv_nodes_free(groups);
        keyed
    }
}


