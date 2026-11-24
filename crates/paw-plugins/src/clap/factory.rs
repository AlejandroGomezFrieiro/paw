//! The creation of a plugin instance, and what the plugin tells of itself
//! on the main thread: its parameters, ports, note dialects and key names.

use std::cell::RefCell;
use std::ffi::CString;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use anyhow::Result;
use clack_extensions::audio_ports::{AudioPortInfoBuffer, PluginAudioPorts};
use clack_extensions::note_name::{NoteNameBuffer, PluginNoteName};
use clack_extensions::note_ports::{
    NoteDialect, NoteDialects, NotePortInfoBuffer, PluginNotePorts,
};
use clack_extensions::params::{ParamInfoBuffer, ParamInfoFlags, PluginParams};
use clack_host::events::Match;
use clack_host::prelude::{
    ClapId, HostInfo, PluginInstance, PluginInstanceError, PluginMainThreadHandle,
};
use clack_host::utils::Cookie;
use clap_sys::plugin::clap_plugin;
use paw_engine::device::{Rest, assign_keys};
use paw_engine::{DeviceFactory, DeviceInfo, Instance, ParamInfo, Ports};

use super::buffer_text;
use super::controller::ClapController;
use super::device::{Buffers, ClapDevice};
use super::events::{ClapEvents, NoteRoute, Out};
use super::host::{HostFlags, HostMain, HostShared, PawHost};
use super::library::load;
use super::shared::{PluginExtensions, Shared};
use crate::HeldNotes;
use crate::echo::Echo;

/// A CLAP plugin of a file, which makes instances of it.
pub(super) struct ClapFactory {
    pub(super) info: DeviceInfo,
    pub(super) id: CString,
    pub(super) path: PathBuf,
    /// Where the libraries that the file needs are looked for.
    pub(super) libraries: Arc<[PathBuf]>,
}

impl DeviceFactory for ClapFactory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, max_block: usize) -> Result<Instance> {
        let library = load(&self.path, &self.libraries)?;
        let flags = Arc::new(HostFlags::new());
        let host = HostInfo::new("paw", "paw", "", "0.1.0")?;
        let host_flags = flags.clone();
        let mut instance = PluginInstance::<PawHost>::new(
            move |_| HostShared { flags: host_flags },
            |shared| HostMain { shared },
            &library.entry,
            &self.id,
            &host,
        )
        .map_err(|err| match err {
            PluginInstanceError::NullFactoryCreatePluginFunction => {
                anyhow::anyhow!("no create_plugin")
            }
            PluginInstanceError::InstantiationFailed => {
                anyhow::anyhow!("the plugin failed to initialize")
            }
            _ => anyhow::anyhow!("{} could not create the plugin", self.path.display()),
        })?;
        // The raw plugin only for the attachments, which take it as it is.
        let raw_plugin: *const clap_plugin = instance.raw_instance();
        // What the plugin is, read on the main thread before it is shared
        // with the audio thread.
        let (ext, (param_ids, param_infos), input_ports, output_ports, route) = {
            let plugin = instance.plugin_handle();
            let ext = PluginExtensions::new(&plugin);
            let ports = plugin.get_extension::<PluginAudioPorts>();
            (
                ext,
                read_params(&plugin, ext.params),
                port_infos(&plugin, ports, true),
                port_infos(&plugin, ports, false),
                note_route(&plugin),
            )
        };
        let mut shared = Shared {
            instance: RefCell::new(instance),
            ext,
            param_ids,
            param_infos,
            flags,
            run: Mutex::new(None),
            sample_rate: sample_rate as f64,
            // Clack refuses a longest block of 0 frames.
            max_block: (max_block as u32).max(1),
            _library: library,
        };

        let channels = |ports: &[(usize, String)]| -> Vec<u32> {
            ports.iter().map(|(count, _)| *count as u32).collect()
        };
        let inputs = Buffers::new(&channels(&input_ports), max_block);
        let outputs = Buffers::new(&channels(&output_ports), max_block);
        // The main port is the first; the first other input that takes
        // sound is the side-chain.
        let key_port = (1..input_ports.len()).find(|&i| input_ports[i].0 > 0);
        let out_pairs = crate::out_pairs(&output_ports);
        let ports = Ports {
            sidechain: key_port.is_some(),
            outputs: crate::pair_names(&out_pairs),
        };

        // Attachments take the plugin before it is active: ARA binds
        // a plugin to its document then.
        // SAFETY: `raw_plugin` is the live, initialized instance that `shared` owns, offered on the
        // main thread before it is active, as the attachments require.
        let attached = unsafe { crate::attach::offer(c"clap", raw_plugin.cast()) };
        let processor = shared.activate().map_err(|err| match err {
            PluginInstanceError::NullActivateFunction => anyhow::anyhow!("no activate"),
            _ => anyhow::anyhow!("the plugin failed to activate"),
        })?;
        *shared.run.get_mut().unwrap() = Some(processor);
        let shared = Arc::new(shared);
        let (changed, changes) = rtrb::RingBuffer::new(1024);
        let device = ClapDevice {
            shared: shared.clone(),
            out: Out {
                changed,
                gestures: Vec::with_capacity(64),
                taking: false,
            },
            inputs,
            outputs,
            key_port,
            keyed: false,
            out_pairs,
            events: ClapEvents::with_capacity(2048),
            pending: Vec::with_capacity(512),
            held: HeldNotes::new(),
            route,
            failed: false,
            steady_time: 0,
            rest: Rest::default(),
            loads: 0,
        };
        let mut controller = ClapController {
            plugin_id: self.id.to_string_lossy().into_owned(),
            presets: None,
            known: vec![f64::NAN; shared.param_ids.len()],
            shared,
            changes,
            echo: Echo::default(),
            reread: None,
            editor: None,
            ports,
            attached,
            failed: None,
        };
        // What it starts with is a state too: its first words of its
        // values are no edit.
        controller.given_state();
        Ok(Instance {
            device: Box::new(device),
            controller: Some(Box::new(controller)),
        })
    }
}

/// The plugin's parameters that it does not hide: their CLAP ids and
/// cookies, and what paw tells of them.
fn read_params(
    plugin: &PluginMainThreadHandle,
    params: Option<PluginParams>,
) -> (Vec<(ClapId, Cookie)>, Vec<ParamInfo>) {
    let (mut ids, mut infos) = (Vec::new(), Vec::new());
    let Some(params) = params else {
        return (ids, infos);
    };
    let mut buffer = ParamInfoBuffer::new();
    for index in 0..params.count(plugin) {
        let Some(info) = params.get_info(plugin, index, &mut buffer) else {
            continue;
        };
        let flags = info.flags;
        if flags.contains(ParamInfoFlags::IS_HIDDEN) {
            continue;
        }
        ids.push((info.id, info.cookie));
        let mut param = ParamInfo::new(&buffer_text(info.name))
            .range(info.min_value as f32, info.max_value as f32)
            .default_value(info.default_value as f32);
        param.id = info.id.get().to_string();
        param.group = buffer_text(info.module).trim_matches('/').to_string();
        param.automatable = flags.contains(ParamInfoFlags::IS_AUTOMATABLE);
        param.read_only = flags.contains(ParamInfoFlags::IS_READONLY);
        param.per_note = flags.intersects(
            ParamInfoFlags::IS_AUTOMATABLE_PER_NOTE_ID
                | ParamInfoFlags::IS_AUTOMATABLE_PER_KEY
                | ParamInfoFlags::IS_AUTOMATABLE_PER_CHANNEL
                | ParamInfoFlags::IS_MODULATABLE_PER_NOTE_ID
                | ParamInfoFlags::IS_MODULATABLE_PER_KEY
                | ParamInfoFlags::IS_MODULATABLE_PER_CHANNEL,
        );
        if flags.contains(ParamInfoFlags::IS_STEPPED) {
            let span = (info.max_value - info.min_value).round();
            param.steps = if span > 0.0 && span < u32::MAX as f64 { span as u32 } else { 0 };
            // An enumeration names its steps: the plugin's own names.
            param.enumeration = flags.contains(ParamInfoFlags::IS_ENUM);
            if param.enumeration && (1..=256).contains(&param.steps) {
                let (id, min) = (info.id, info.min_value);
                param.choices = (0..=param.steps)
                    .map(|step| {
                        value_text(plugin, params, id, min + step as f64)
                            .unwrap_or_else(|| step.to_string())
                    })
                    .collect();
            } else {
                param.boolean = param.steps == 1;
            }
        }
        infos.push(param);
    }
    assign_keys(&mut infos);
    (ids, infos)
}

/// A parameter's value as the plugin writes it.
pub(super) fn value_text(
    plugin: &PluginMainThreadHandle,
    params: PluginParams,
    id: ClapId,
    value: f64,
) -> Option<String> {
    let mut buffer = [0u8; 256];
    let text = params.value_to_text(plugin, id, value, &mut buffer).ok()?;
    Some(buffer_text(text)).filter(|t| !t.is_empty())
}

/// The channel count and name of each of the plugin's audio ports in one
/// direction.
fn port_infos(
    plugin: &PluginMainThreadHandle,
    ports: Option<PluginAudioPorts>,
    is_input: bool,
) -> Vec<(usize, String)> {
    let Some(ports) = ports else {
        return Vec::new();
    };
    let mut buffer = AudioPortInfoBuffer::new();
    (0..ports.count(plugin, is_input))
        .map(|index| match ports.get(plugin, index, is_input, &mut buffer) {
            Some(info) => (info.channel_count as usize, buffer_text(info.name)),
            None => (0, String::new()),
        })
        .collect()
}

/// How the plugin takes paw's events, from the note dialects of its first
/// note input.
fn note_route(plugin: &PluginMainThreadHandle) -> NoteRoute {
    let (supported, preferred) = note_dialects(plugin);
    // Notes go as CLAP's own events unless the plugin prefers MIDI
    // 2.0, which alone carries a note's attribute (an articulation).
    let clap_notes =
        supported.contains(NoteDialects::CLAP) && preferred != Some(NoteDialect::Midi2);
    NoteRoute {
        clap_notes,
        // A channel's controllers, the pitch wheel, pressure and program
        // changes only exist as MIDI: 2.0 when the plugin takes it.
        midi: !clap_notes || supported.contains(NoteDialects::MIDI),
        midi2: supported.contains(NoteDialects::MIDI2),
    }
}

/// The note dialects the plugin's first note input takes, and the one it
/// prefers.
fn note_dialects(plugin: &PluginMainThreadHandle) -> (NoteDialects, Option<NoteDialect>) {
    let none = (NoteDialects::empty(), None);
    let Some(ports) = plugin.get_extension::<PluginNotePorts>() else {
        return none;
    };
    let mut buffer = NotePortInfoBuffer::new();
    if ports.count(plugin, true) == 0 {
        return none;
    }
    ports
        .get(plugin, 0, true, &mut buffer)
        .map_or(none, |info| (info.supported_dialects, info.preferred_dialect))
}

/// What the plugin calls its keys (`clap.note-name`), as JSON: `{ "36":
/// "Kick", "24": "Sustain" }`, for keys of its first port on every channel
/// or the first. Empty when it names none.
pub(super) fn note_names(plugin: &PluginMainThreadHandle) -> Vec<u8> {
    let mut names = serde_json::Map::new();
    if let Some(ext) = plugin.get_extension::<PluginNoteName>() {
        let mut buffer = NoteNameBuffer::new();
        let first_or_all = |m: Match<u16>| matches!(m, Match::All | Match::Specific(0));
        for index in 0..ext.count(plugin) {
            let Some(name) = ext.get(plugin, index as u32, &mut buffer) else {
                continue;
            };
            if !first_or_all(name.port) || !first_or_all(name.channel) {
                continue;
            }
            let text = buffer_text(name.name);
            // A name for every key (-1) is no name for any one key.
            if let Match::Specific(key @ 0..128) = name.key
                && !text.is_empty()
            {
                names.insert(key.to_string(), text.into());
            }
        }
    }
    serde_json::to_vec(&names).unwrap_or_default()
}
