//! CLAP hosting. The file's entry, its plugin factory, the plugin instance,
//! the host's callbacks, processing (events, buffers, transport, tail) and the
//! plugin's extensions go through Clack (`clack-host` and `clack-extensions`).
//! paw's own types are the extensions Clack has none for: the preset-load
//! extension's compatible id and paw's `dev.paw.call/1`.
//!
//! Threading follows the CLAP rules: a plugin is created, activated,
//! deactivated and destroyed on the main thread, and `start_processing` and
//! `process` run on the audio thread. [`ClapDevice`] is the audio-thread half
//! and [`ClapController`] the main-thread half; both hold the same [`Shared`],
//! which destroys the plugin when the last of them is dropped.

use std::cell::RefCell;
use std::ffi::{CStr, CString, c_char, c_void};
use std::mem::ManuallyDrop;
use std::path::{Path, PathBuf};
use std::ptr;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering, Ordering::Relaxed};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result, bail};
use clap_sys::audio_buffer::clap_audio_buffer;
use clap_sys::entry::clap_plugin_entry;
use clack_extensions::audio_ports::{AudioPortInfoBuffer, PluginAudioPorts};
use clack_extensions::gui::{
    GuiApiType, GuiConfiguration, GuiSize, HostGui, HostGuiImpl, PluginGui, Window,
};
use clack_extensions::log::{HostLog, HostLogImpl, LogSeverity};
use clack_extensions::note_name::{NoteNameBuffer, PluginNoteName};
use clack_extensions::note_ports::{
    NoteDialect, NoteDialects, NotePortInfoBuffer, PluginNotePorts,
};
use clack_extensions::params::{
    HostParams, HostParamsImplMainThread, HostParamsImplShared, ParamClearFlags, ParamInfoBuffer,
    ParamInfoFlags, ParamRescanFlags, PluginParams,
};
use clack_extensions::posix_fd::{FdFlags, HostPosixFd, HostPosixFdImpl, PluginPosixFd};
use clack_extensions::preset_discovery::PluginPresetLoad;
use clack_extensions::preset_discovery::preset_data::Location;
use clack_extensions::render::{PluginRender, RenderMode};
use clack_extensions::state::{HostState, HostStateImpl, PluginState};
use clack_extensions::tail::{PluginTail, TailLength};
use clack_extensions::thread_check::{HostThreadCheck, HostThreadCheckImpl};
use clack_extensions::timer::{HostTimer, HostTimerImpl, PluginTimer, TimerId};
use clack_host::entry::{EntryDescriptor, PluginEntry, PluginEntryError};
use clack_host::events::event_types::{TransportEvent, TransportFlags};
use clack_host::events::io::{InputEventBuffer, OutputEventBuffer, TryPushError};
use clack_host::events::spaces::CoreEventSpace;
use clack_host::events::{EventFlags, Match};
use clack_host::extensions::{Extension, PluginExtensionSide, RawExtension};
use clack_host::prelude::{
    ClapId, EventHeader, HostError, HostExtensions, HostHandlers, HostInfo, InputAudioBuffers,
    InputEvents, MainThreadHandler, OutputAudioBuffers, OutputEvents, PluginAudioConfiguration,
    PluginAudioProcessor, PluginInstance, PluginInstanceError, PluginMainThreadHandle,
    ProcessStatus, SharedHandler, UnknownEvent,
};
use clack_host::utils::{Cookie, FixedPoint};
use clap_sys::events::*;
use clap_sys::ext::preset_load::{CLAP_EXT_PRESET_LOAD_COMPAT, clap_plugin_preset_load};
use clap_sys::id::clap_id;
use clap_sys::plugin::clap_plugin;
use paw_engine::device::{Change, Rest, assign_keys, silent};
use paw_engine::{
    Controller, Device, DeviceFactory, DeviceFormat, DeviceInfo, EventKind, Instance, Io,
    NOTE_BEND_RANGE, NoteCtl, ParamInfo, Ports, ProcessCtx, Registry, ump,
};

use crate::echo::Echo;
use crate::presets::PresetLocation;
use crate::window::{HostWindow, Watches, WindowEvent, ui_scale};
use crate::{Found, HeldNotes, PluginFormat, is_main_thread, write_output};

/// A loaded `.clap` file. Never unloaded: plugins commonly leave threads and
/// static state behind that do not survive it.
struct Library {
    _lib: ManuallyDrop<libloading::Library>,
    /// The file's entry, initialized. Kept for good in `load`'s list, so
    /// Clack never calls the entry's `deinit`.
    entry: PluginEntry,
}

/// Load a `.clap` file, or return it if it is loaded already.
fn load(path: &Path) -> Result<Arc<Library>> {
    static LOADED: Mutex<Vec<(PathBuf, Arc<Library>)>> = Mutex::new(Vec::new());
    let mut loaded = LOADED.lock().unwrap();
    if let Some((_, library)) = loaded.iter().find(|(p, _)| p == path) {
        return Ok(library.clone());
    }
    let lib = libloading::Library::from(crate::libs::open_library(path)?);
    // SAFETY: `clap_entry` is the symbol the CLAP ABI names and has the type `clap_plugin_entry`.
    // The file is never unloaded (`ManuallyDrop` below), so the entry it points to is `'static`.
    let entry: &'static EntryDescriptor = unsafe {
        let entry = *lib.get::<*const clap_plugin_entry>(b"clap_entry\0")?;
        entry.as_ref().context("no entry point")?
    };
    entry.init.context("no init")?;
    entry.get_factory.context("no factory")?;
    let c_path = CString::new(path.to_string_lossy().as_bytes())?;
    // SAFETY: `entry` is the file's own entry, valid for good (see above). Clack checks its CLAP
    // version and calls its `init` once with the path, on the main thread (under the LOADED lock).
    let entry = unsafe { PluginEntry::load_from_raw(entry, &c_path) }.map_err(|err| match err {
        PluginEntryError::EntryInitFailed => anyhow::anyhow!("the plugin refused to initialize"),
        err => anyhow::anyhow!("{err}"),
    })?;
    entry
        .get_plugin_factory()
        .context("the file has no plugin factory")?;
    let library = Arc::new(Library {
        _lib: ManuallyDrop::new(lib),
        entry,
    });
    loaded.push((path.to_path_buf(), library.clone()));
    Ok(library)
}

/// The text in a fixed-size buffer that a plugin filled, as Clack gives it:
/// up to its first NUL, or the whole buffer when the plugin wrote none.
fn buffer_text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

/// Load a file and list the plugins in it.
/// What is in a plugin file, for the helper that looks into them.
pub(crate) fn list_file(path: &Path) -> Result<Vec<Found>> {
    list(path)
}

fn list(path: &Path) -> Result<Vec<Found>> {
    let library = load(path)?;
    let factory = library
        .entry
        .get_plugin_factory()
        .context("the file has no plugin factory")?;
    let raw = factory.raw().get();
    raw.get_plugin_count.context("no plugin count")?;
    raw.get_plugin_descriptor.context("no descriptors")?;
    let text = |text: Option<&CStr>| text.map_or_else(String::new, |t| t.to_string_lossy().into_owned());
    Ok(factory
        .plugin_descriptors()
        .map(|desc| Found {
            id: text(desc.id()),
            name: text(desc.name()),
            vendor: text(desc.vendor()),
            instrument: desc.features().any(|f| f.to_bytes() == b"instrument"),
            version: text(desc.version()),
            features: desc.features().map(|f| text(Some(f))).collect(),
        })
        .collect())
}

/// CLAP, for [`scan_in`](crate::scan_in): a `.clap` is a single shared
/// library on Linux, and its plugins are `clap:<id>`.
pub(crate) struct Clap;

impl PluginFormat for Clap {
    const NAME: &'static str = "clap";
    const FORMAT: DeviceFormat = DeviceFormat::Clap;
    const ENV: &'static str = "CLAP_PATH";
    const ONE_PER_ID: bool = false;

    fn library(bundle: &Path) -> Option<PathBuf> {
        (!bundle.is_dir()).then(|| bundle.to_path_buf())
    }

    fn list(bundle: &Path) -> Result<Vec<Found>> {
        list(bundle)
    }

    fn kind(found: &Found, _registry: &Registry) -> String {
        format!("clap:{}", found.id)
    }

    fn factory(info: DeviceInfo, bundle: &Path) -> Option<Rc<dyn DeviceFactory>> {
        let id = CString::new(info.id.as_str()).ok()?;
        Some(Rc::new(ClapFactory {
            info,
            id,
            path: bundle.to_path_buf(),
        }))
    }
}

struct ClapFactory {
    info: DeviceInfo,
    id: CString,
    path: PathBuf,
}

/// What the plugin has asked the host for, to be acted on from the main thread.
struct HostFlags {
    callback: AtomicBool,
    restart: AtomicBool,
    /// The plugin has to be run again, though it said it may sleep: it
    /// asked to be (`request_process`), or was given a state, which some
    /// plugins only take on in their next block.
    wake: AtomicBool,
    /// The plugin says its parameter values changed behind the host's back.
    rescan: AtomicBool,
    /// Blocks the plugin has processed, to tell when it has taken on a
    /// state.
    blocks: AtomicU64,
    /// States the plugin was given: the first block after a new one is
    /// the block in which a plugin that takes a state on in its next block
    /// takes it on.
    loads: AtomicU64,
    /// The plugin closed its editor itself.
    closed: AtomicBool,
    /// A size the plugin wants its editor window to be.
    resize: Mutex<Option<(u32, u32)>>,
    /// File descriptors and timers the plugin's editor runs on.
    watches: Mutex<Watches<(), clap_id>>,
    next_timer: AtomicU32,
}

impl HostFlags {
    fn new() -> Self {
        Self {
            callback: AtomicBool::new(false),
            restart: AtomicBool::new(false),
            wake: AtomicBool::new(false),
            rescan: AtomicBool::new(false),
            blocks: AtomicU64::new(0),
            loads: AtomicU64::new(0),
            closed: AtomicBool::new(false),
            resize: Mutex::new(None),
            watches: Mutex::new(Watches::new()),
            next_timer: AtomicU32::new(0),
        }
    }
}

/// The plugin instance and what both halves need to reach it.
struct Shared {
    /// The plugin, through Clack. Main thread only (see the `Send` and
    /// `Sync` notes below): created, activated, deactivated and destroyed
    /// there.
    instance: RefCell<PluginInstance<PawHost>>,
    /// The plugin's extensions that are called often, asked for once.
    ext: PluginExtensions,
    /// The CLAP id and cookie of each parameter, in the order we list them.
    param_ids: Vec<(ClapId, Cookie)>,
    param_infos: Vec<ParamInfo>,
    flags: Arc<HostFlags>,
    /// The plugin's audio processor while the plugin is active. The audio
    /// thread holds it while the plugin processes a block, and only tries
    /// it: it leaves the block to the plugin's stand-in when it cannot have
    /// it or finds none. The main thread takes the processor out to
    /// deactivate the plugin ([`Shared::deactivate`]) and puts a new one
    /// back when it activates it again ([`ClapController::stopped`]).
    run: Mutex<Option<PluginAudioProcessor<PawHost>>>,
    sample_rate: f64,
    max_block: u32,
    // Kept alive for the plugin's preset-discovery factory.
    _library: Arc<Library>,
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
struct PluginExtensions {
    params: Option<PluginParams>,
    state: Option<PluginState>,
    gui: Option<PluginGui>,
    timers: Option<PluginTimer>,
    fds: Option<PluginPosixFd>,
    /// How long the plugin rings after its input stops, when it says.
    tail: Option<PluginTail>,
}

impl PluginExtensions {
    fn new(plugin: &PluginMainThreadHandle) -> Self {
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
    fn on_main<R>(&self, f: impl FnOnce(&PluginMainThreadHandle) -> R) -> R {
        let mut instance = self.instance.borrow_mut();
        f(&instance.plugin_handle())
    }

    /// Activate the plugin: its audio processor, not processing yet.
    /// Main thread, with the plugin inactive.
    fn activate(&self) -> Result<PluginAudioProcessor<PawHost>, PluginInstanceError> {
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
    fn deactivate(&self, run: &mut Option<PluginAudioProcessor<PawHost>>) {
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

impl DeviceFactory for ClapFactory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, max_block: usize) -> Result<Instance> {
        let library = load(&self.path)?;
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
        let (ext, (param_ids, param_infos), input_ports, output_ports, dialects) = {
            let plugin = instance.plugin_handle();
            let ext = PluginExtensions::new(&plugin);
            let ports = plugin.get_extension::<PluginAudioPorts>();
            (
                ext,
                read_params(&plugin, ext.params),
                port_infos(&plugin, ports, true),
                port_infos(&plugin, ports, false),
                note_dialects(&plugin),
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
        let (supported, preferred) = dialects;
        // Notes go as CLAP's own events unless the plugin prefers MIDI
        // 2.0, which alone carries a note's attribute (an articulation).
        let clap_notes =
            supported.contains(NoteDialects::CLAP) && preferred != Some(NoteDialect::Midi2);
        // A channel's controllers, the pitch wheel, pressure and program
        // changes only exist as MIDI: 2.0 when the plugin takes it.
        let midi2 = supported.contains(NoteDialects::MIDI2);
        let midi = !clap_notes || supported.contains(NoteDialects::MIDI);

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
            events: ClapEvents(Vec::with_capacity(2048)),
            pending: Vec::with_capacity(512),
            held: HeldNotes::new(),
            clap_notes,
            midi,
            midi2,
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
        let mut param = ParamInfo::new(
            &buffer_text(info.name),
            info.min_value as f32,
            info.max_value as f32,
            info.default_value as f32,
            "",
        );
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
fn value_text(
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
fn note_names(plugin: &PluginMainThreadHandle) -> Vec<u8> {
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

/// Audio buffers for every port in one direction, laid out as CLAP wants them.
struct Buffers {
    channels: Vec<Vec<Vec<f32>>>,
    _pointers: Vec<Vec<*mut f32>>,
    ports: Vec<clap_audio_buffer>,
}

impl Buffers {
    fn new(channel_counts: &[u32], max_block: usize) -> Self {
        let mut channels: Vec<Vec<Vec<f32>>> = channel_counts
            .iter()
            .map(|&count| (0..count).map(|_| vec![0.0; max_block]).collect())
            .collect();
        let mut pointers: Vec<Vec<*mut f32>> = channels
            .iter_mut()
            .map(|port| port.iter_mut().map(|ch| ch.as_mut_ptr()).collect())
            .collect();
        let ports = pointers
            .iter_mut()
            .map(|port| clap_audio_buffer {
                data32: port.as_mut_ptr(),
                data64: ptr::null_mut(),
                channel_count: port.len() as u32,
                latency: 0,
                constant_mask: 0,
            })
            .collect();
        Self {
            channels,
            _pointers: pointers,
            ports,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
union ClapEvent {
    header: clap_event_header,
    note: clap_event_note,
    param: clap_event_param_value,
    midi: clap_event_midi,
    midi2: clap_event_midi2,
    expression: clap_event_note_expression,
}

/// The CLAP note expression a per-note controller is, and its value there.
/// The registered per-note controllers mean what the control changes of the
/// same number do.
fn expression(ctl: NoteCtl, value: f64) -> Option<(clap_note_expression, f64)> {
    Some(match ctl {
        NoteCtl::Bend => (CLAP_NOTE_EXPRESSION_TUNING, value * NOTE_BEND_RANGE),
        NoteCtl::Pressure => (CLAP_NOTE_EXPRESSION_PRESSURE, value),
        // CLAP's volume is a gain with 1 as unity; full scale here is unity.
        NoteCtl::Registered(7) => (CLAP_NOTE_EXPRESSION_VOLUME, value.max(1e-4)),
        NoteCtl::Registered(10) => (CLAP_NOTE_EXPRESSION_PAN, value),
        NoteCtl::Registered(1) => (CLAP_NOTE_EXPRESSION_VIBRATO, value),
        NoteCtl::Registered(11) => (CLAP_NOTE_EXPRESSION_EXPRESSION, value),
        NoteCtl::Registered(74) => (CLAP_NOTE_EXPRESSION_BRIGHTNESS, value),
        _ => return None,
    })
}

fn header<T>(time: u32, type_: clap_event_type) -> clap_event_header {
    clap_event_header {
        size: size_of::<T>() as u32,
        time,
        space_id: CLAP_CORE_EVENT_SPACE_ID,
        type_,
        flags: 0,
    }
}

struct ClapDevice {
    shared: Arc<Shared>,
    /// What the plugin tells in its output events, kept across blocks.
    out: Out,
    inputs: Buffers,
    outputs: Buffers,
    /// The input port that takes the side-chain, and whether it holds one.
    key_port: Option<usize>,
    keyed: bool,
    /// The output ports as stereo pairs, the main one first.
    out_pairs: Vec<crate::OutPair>,
    events: ClapEvents,
    /// Parameter changes waiting for the next block: index and value.
    pending: Vec<(u32, f32)>,
    held: HeldNotes,
    /// Whether the plugin takes CLAP note events rather than MIDI.
    clap_notes: bool,
    /// Whether it takes MIDI 1.0 messages, and MIDI 2.0 ones, for what is
    /// not a note.
    midi: bool,
    midi2: bool,
    /// The plugin failed to start processing: it is not asked again.
    failed: bool,
    steady_time: u64,
    /// What the plugin said of itself after its last block (see
    /// [`Device::resting`]).
    rest: Rest,
    /// States the plugin had been given at its last block ([`HostFlags::loads`]).
    loads: u64,
}

// The buffers hold raw pointers into vectors the device owns.
// SAFETY: The buffers hold raw pointers into vectors that the device owns and moves with itself.
// The device is used from the audio thread only, after the main thread built it.
unsafe impl Send for ClapDevice {}

impl Device for ClapDevice {
    /// As the plugin's status after its last block says: asleep, or quiet,
    /// or done with its tail; unless a parameter has moved since.
    fn resting(&self) -> bool {
        self.rest.resting() && self.pending.is_empty() && !self.shared.flags.wake.load(Relaxed)
    }

    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        let n = io.left.len();
        // Woken: its tail starts again from here.
        self.rest.begin(io, self.shared.flags.wake.swap(false, Relaxed));
        // The main thread has the plugin deactivated for an attachment:
        // this block is the stand-in's, silence for an instrument and the
        // input passed through for an effect.
        let mut running = self.shared.run.try_lock().ok();
        let Some(processor) = running.as_deref_mut().and_then(Option::as_mut) else {
            if self.inputs.ports.is_empty() {
                io.left.fill(0.0);
                io.right.fill(0.0);
            }
            return;
        };
        // Started anew after the main thread deactivated it; never again
        // once it failed to start.
        if !processor.is_started() && (self.failed || processor.start_processing().is_err()) {
            self.failed = true;
            return;
        }
        let Ok(processor) = processor.as_started_mut() else {
            return;
        };

        if let Some(port) = self.inputs.channels.first_mut() {
            match port.as_mut_slice() {
                [] => {}
                [mono] => {
                    for (m, (l, r)) in mono.iter_mut().zip(io.left.iter().zip(io.right.iter())) {
                        *m = (l + r) * 0.5;
                    }
                }
                [left, right, ..] => {
                    left[..n].copy_from_slice(io.left);
                    right[..n].copy_from_slice(io.right);
                }
            }
        }
        if let Some(port) = self.key_port.and_then(|p| self.inputs.channels.get_mut(p)) {
            self.keyed = crate::put_key(port.as_mut_slice(), io.sidechain, self.keyed, n);
        }

        let events = &mut self.events.0;
        events.clear();
        for (index, value) in self.pending.drain(..) {
            let Some(&(param_id, cookie)) = self.shared.param_ids.get(index as usize) else {
                continue;
            };
            events.push(ClapEvent {
                param: clap_event_param_value {
                    header: header::<clap_event_param_value>(0, CLAP_EVENT_PARAM_VALUE),
                    param_id: param_id.get(),
                    cookie: cookie.as_raw(),
                    note_id: -1,
                    port_index: -1,
                    channel: -1,
                    key: -1,
                    value: value as f64,
                },
            });
        }
        let (clap_notes, midi, midi2) = (self.clap_notes, self.midi, self.midi2);
        self.held.expand(io.events.as_slice(), |frame, kind| {
            let mut push = |event: ClapEvent| {
                if events.len() < events.capacity() {
                    events.push(event);
                }
            };
            match kind {
                EventKind::NoteOn { key, ch, .. } | EventKind::NoteOff { key, ch }
                    if clap_notes =>
                {
                    let (type_, velocity) = match kind {
                        EventKind::NoteOn { vel, .. } => (CLAP_EVENT_NOTE_ON, vel as f64),
                        _ => (CLAP_EVENT_NOTE_OFF, 0.0),
                    };
                    push(ClapEvent {
                        note: clap_event_note {
                            header: header::<clap_event_note>(frame, type_),
                            note_id: -1,
                            port_index: 0,
                            channel: ch as i16,
                            key: key as i16,
                            velocity,
                        },
                    });
                }
                // A note's own controllers are what CLAP calls note expressions.
                EventKind::NoteControl {
                    key,
                    ctl,
                    value,
                    ch,
                } if clap_notes && expression(ctl, value).is_some() => {
                    let (expression_id, value) = expression(ctl, value).unwrap();
                    push(ClapEvent {
                        expression: clap_event_note_expression {
                            header: header::<clap_event_note_expression>(
                                frame,
                                CLAP_EVENT_NOTE_EXPRESSION,
                            ),
                            expression_id,
                            note_id: -1,
                            port_index: 0,
                            channel: ch as i16,
                            key: key as i16,
                            value,
                        },
                    });
                }
                // Everything else is MIDI: as 2.0, whole, to a plugin
                // that takes it, and as 1.0 otherwise.
                _ if midi2 => {
                    if let Some(data) = ump::encode(0, kind) {
                        push(ClapEvent {
                            midi2: clap_event_midi2 {
                                header: header::<clap_event_midi2>(frame, CLAP_EVENT_MIDI2),
                                port_index: 0,
                                data: [data[0], data[1], 0, 0],
                            },
                        });
                    }
                }
                _ if midi => ump::midi1(kind, |data, _| {
                    push(ClapEvent {
                        midi: clap_event_midi {
                            header: header::<clap_event_midi>(frame, CLAP_EVENT_MIDI),
                            port_index: 0,
                            data,
                        },
                    })
                }),
                _ => {}
            }
        });

        let loads = self.shared.flags.loads.load(Ordering::Acquire);
        self.out.taking = loads != self.loads;
        self.loads = loads;
        // Built with the block's length, not with Clack's safe builders: they
        // give a plugin with no audio ports a block of 0 frames.
        // SAFETY: Each port's channel pointers lead to `max_block` frames of the device's own
        // vectors, which live and stay in place as long as the device, and `n <= max_block`.
        let (inputs, mut outputs) = unsafe {
            (
                InputAudioBuffers::from_raw_buffers(&self.inputs.ports, n as u32),
                OutputAudioBuffers::from_raw_buffers(&mut self.outputs.ports, n as u32),
            )
        };
        let steady_time = self.steady_time;
        self.steady_time += n as u64;
        let status = processor.process(
            &inputs,
            &mut outputs,
            &InputEvents::from_buffer(&self.events),
            &mut OutputEvents::from_buffer(&mut self.out),
            Some(steady_time),
            Some(&transport(ctx)),
        );
        if let Err(PluginInstanceError::NullProcessFunction) = status {
            return;
        }
        // Counted once the block is done: a state taken on in it, and
        // the plugin's words of it, are there before the count is.
        self.shared.flags.blocks.fetch_add(1, Ordering::Release);
        // The plugin failed the block (`CLAP_PROCESS_ERROR`).
        let Ok(status) = status else {
            return;
        };
        // Whether the plugin may sleep through silence from here on:
        // it says so, or says it may once its output is quiet, or once
        // its tail has gone by.
        let out_quiet = || self.outputs.channels.iter().flatten().all(|c| silent(&c[..n]));
        match status {
            ProcessStatus::Sleep => self.rest.end(true),
            ProcessStatus::ContinueIfNotQuiet => self.rest.end(out_quiet()),
            ProcessStatus::Tail => {
                let tail = self.shared.ext.tail.map(|tail| tail.get(&processor.plugin_handle()));
                let frames = match tail {
                    Some(TailLength::Finite(frames)) => Some(u64::from(frames)),
                    _ => None,
                };
                self.rest.end_after_tail(frames, out_quiet());
            }
            ProcessStatus::Continue => self.rest.end(false),
        }

        if let Some(port) = self.outputs.channels.first() {
            let channels = [port.first().map(|c| &c[..n]), port.get(1).map(|c| &c[..n])];
            match channels {
                [Some(l), Some(r)] => {
                    write_output(io.left, io.right, &[l, r], self.inputs.ports.is_empty())
                }
                [Some(m), None] => {
                    write_output(io.left, io.right, &[m], self.inputs.ports.is_empty())
                }
                _ => {}
            }
        }
        crate::write_pairs(&self.out_pairs, &self.outputs.channels, io.outputs, n);
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if self.pending.len() < self.pending.capacity() {
            self.pending.push((index, value));
        }
    }
}

impl Drop for ClapDevice {
    /// Runs on the main thread, after the audio thread has let go of the device.
    fn drop(&mut self) {
        let mut run = self.shared.run.lock().unwrap_or_else(|e| e.into_inner());
        self.shared.deactivate(&mut run);
    }
}

/// The events of one block, as the plugin reads them.
struct ClapEvents(Vec<ClapEvent>);

impl InputEventBuffer for ClapEvents {
    fn len(&self) -> u32 {
        self.0.len() as u32
    }

    fn get(&self, index: u32) -> Option<&UnknownEvent> {
        let event = self.0.get(index as usize)?;
        // SAFETY: Each event was built whole by `process`, with a header that names its own type
        // and size, and the union holds at least that size; the event lives as long as `self`.
        Some(unsafe { UnknownEvent::from_raw(ptr::from_ref(event).cast()) })
    }
}

/// What a plugin tells in its output events.
struct Out {
    /// Parameter values it reports changing, on their way to the
    /// controller: CLAP id, value, whether it came inside a gesture, and
    /// whether it came in the first block after a state.
    changed: rtrb::Producer<(clap_id, f64, bool, bool)>,
    /// The block the plugin processes now is the first after a state.
    taking: bool,
    /// The parameters between `GESTURE_BEGIN` and `GESTURE_END` now: a
    /// person moves them in the plugin's window.
    gestures: Vec<clap_id>,
}

/// The plugin's output events. Only parameter changes and gestures are
/// kept: they are how a plugin tells the host what was done in its editor.
impl OutputEventBuffer for Out {
    fn try_push(&mut self, event: &UnknownEvent) -> Result<(), TryPushError> {
        match event.as_core_event() {
            Some(CoreEventSpace::ParamValue(event)) => {
                if let Some(id) = event.param_id().map(ClapId::get) {
                    let gesture = self.gestures.contains(&id);
                    let _ = self.changed.push((id, event.value(), gesture, self.taking));
                }
            }
            Some(CoreEventSpace::ParamGestureBegin(event)) => {
                // Room is kept for many at once: no allocation here.
                if let Some(id) = event.param_id().map(ClapId::get)
                    && self.gestures.len() < self.gestures.capacity()
                {
                    self.gestures.push(id);
                }
            }
            Some(CoreEventSpace::ParamGestureEnd(event)) => {
                if let Some(id) = event.param_id().map(ClapId::get) {
                    self.gestures.retain(|known| *known != id);
                }
            }
            _ => {}
        }
        Ok(())
    }
}

/// The transport as of the block's first frame.
fn transport(ctx: &ProcessCtx) -> TransportEvent {
    // Cut toward zero into CLAP's fixed point, not rounded.
    let fixed = |value: f64| FixedPoint::from_bits((value * FixedPoint::FACTOR as f64) as i64);
    let mut flags = TransportFlags::HAS_TEMPO
        | TransportFlags::HAS_BEATS_TIMELINE
        | TransportFlags::HAS_SECONDS_TIMELINE
        | TransportFlags::HAS_TIME_SIGNATURE;
    flags.set(TransportFlags::IS_PLAYING, ctx.playing);
    TransportEvent {
        header: EventHeader::new_core(0, EventFlags::empty()),
        flags,
        song_pos_beats: fixed(ctx.position),
        song_pos_seconds: fixed(ctx.seconds),
        tempo: ctx.tempo,
        tempo_inc: 0.0,
        loop_start_beats: FixedPoint::default(),
        loop_end_beats: FixedPoint::default(),
        loop_start_seconds: FixedPoint::default(),
        loop_end_seconds: FixedPoint::default(),
        bar_start: fixed(ctx.bar_start),
        bar_number: ctx.bar as i32,
        time_signature_numerator: ctx.sig_num as u16,
        time_signature_denominator: ctx.sig_den as u16,
    }
}

struct ClapController {
    shared: Arc<Shared>,
    plugin_id: String,
    /// The plugin's own presets, found once asked for.
    presets: Option<Vec<crate::presets::Preset>>,
    changes: rtrb::Consumer<(clap_id, f64, bool, bool)>,
    /// Tells the echo of a state from an edit.
    echo: Echo,
    /// When it was last given a state, how many blocks it had processed:
    /// its values are read again once it has processed another.
    reread: Option<u64>,
    /// The last value seen for each parameter, to tell what a rescan changed.
    known: Vec<f64>,
    /// The open editor: in one of our windows, or (`None` inside) floating in
    /// a window the plugin made itself.
    editor: Option<Option<HostWindow>>,
    ports: Ports,
    /// The attachments that took the plugin (`attach.rs`).
    attached: Vec<crate::attach::Attached>,
}

impl ClapController {
    /// The plugin was given a state (or a preset, or a request that may
    /// set its parameters): what it holds now, and again after its next
    /// block, is what it tells of its values for the echo.
    fn given_state(&mut self) {
        let values: Vec<Option<f64>> = (0..self.known.len()).map(|i| self.value(i)).collect();
        self.echo.given(values);
        self.reread = Some(self.shared.flags.blocks.load(Ordering::Acquire));
        self.shared.flags.loads.fetch_add(1, Ordering::Release);
    }

    /// The window system to open the editor with, and whether the plugin
    /// floats it in a window of its own. Embedding in an X11 window comes
    /// first, since that is what nearly every plugin offers and it lets the
    /// host own the window. A plugin that can only float is still shown, as a
    /// native Wayland window if it can make one.
    fn editor_api(&self) -> Option<GuiConfiguration<'static>> {
        let gui = self.shared.ext.gui?;
        let wayland = std::env::var_os("WAYLAND_DISPLAY").is_some();
        let configuration = |api_type, is_floating| GuiConfiguration {
            api_type,
            is_floating,
        };
        self.shared.on_main(|plugin| {
            [
                configuration(GuiApiType::X11, false),
                configuration(GuiApiType::WAYLAND, true),
                configuration(GuiApiType::X11, true),
            ]
            .into_iter()
            .filter(|c| wayland || c.api_type != GuiApiType::WAYLAND)
            .find(|c| gui.is_api_supported(plugin, *c))
        })
    }

    /// React to what happened to the editor window and what the plugin asked for.
    fn run_editor(&mut self) {
        let shared = &self.shared;
        let Some(editor) = self.editor.as_mut() else {
            return;
        };
        let mut close = shared.flags.closed.swap(false, Relaxed);
        let Some(gui) = shared.ext.gui else {
            return;
        };
        let resize = shared.flags.resize.lock().unwrap().take();
        if let (Some(window), Some((width, height))) = (editor.as_mut(), resize) {
            window.resize(width, height);
        }
        let events = editor.as_mut().map(HostWindow::events).unwrap_or_default();
        let mut resized = None;
        for event in events {
            match event {
                WindowEvent::Closed => close = true,
                WindowEvent::Resized(width, height) => {
                    // Let the plugin round the size to one it can draw, then
                    // make the window agree with what it settled on.
                    let asked = GuiSize { width, height };
                    let size = shared.on_main(|plugin| {
                        if gui.can_resize(plugin) {
                            let size = gui.adjust_size(plugin, asked).unwrap_or(asked);
                            let _ = gui.set_size(plugin, size);
                            size
                        } else {
                            gui.get_size(plugin).unwrap_or(asked)
                        }
                    });
                    resized = Some((size.width, size.height));
                }
            }
        }
        if let (Some(window), Some((width, height))) = (editor.as_mut(), resized) {
            window.resize(width, height);
        }
        // Timers and file descriptors drive the plugin's own event handling.
        let (due, ready) = {
            let mut watches = shared.flags.watches.lock().unwrap();
            (watches.due_timers(), watches.ready_fds())
        };
        shared.on_main(|plugin| {
            if let Some(timers) = shared.ext.timers {
                for id in due {
                    timers.on_timer(plugin, TimerId(id));
                }
            }
            if let Some(fds) = shared.ext.fds {
                for (fd, ()) in ready {
                    fds.on_fd(plugin, fd, FdFlags::READ);
                }
            }
        });
        if close {
            self.close_editor();
        }
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
        let Some(state) = self.shared.ext.state else {
            return Ok(None);
        };
        let mut out = Vec::new();
        self.shared
            .on_main(|plugin| state.save(plugin, &mut out))
            .map_err(|_| anyhow::anyhow!("the plugin could not save its state"))?;
        Ok(Some(out))
    }

    fn load_state(&mut self, state: &[u8]) -> Result<()> {
        let Some(ext) = self.shared.ext.state else {
            return Ok(());
        };
        let mut rest = state;
        self.shared
            .on_main(|plugin| ext.load(plugin, &mut rest))
            .map_err(|_| anyhow::anyhow!("the plugin rejected the saved state"))?;
        // Some plugins take a state on only in their next block.
        self.shared.flags.wake.store(true, Relaxed);
        self.given_state();
        Ok(())
    }

    fn idle(&mut self) {
        if self.shared.flags.callback.swap(false, Relaxed) {
            self.shared.instance.borrow_mut().call_on_main_thread_callback();
        }
        self.run_editor();
    }

    fn take_changes(&mut self) -> Vec<Change> {
        let mut out = Vec::new();
        // A plugin that takes a state on only in its next block has its
        // new values only then: read them back, as the echo they are.
        if let Some(blocks) = self.reread
            && self.shared.flags.blocks.load(Ordering::Acquire) != blocks
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
        if self.editor.is_some() {
            return Ok(());
        }
        let configuration = self
            .editor_api()
            .context("this plugin has no editor this host can show")?;
        let gui = self.shared.ext.gui.context("no gui")?;
        // The calls go in the order the ABI requires: create, set_scale,
        // set_parent, show.
        let window = self.shared.on_main(|plugin| -> Result<Option<HostWindow>> {
            if gui.create(plugin, configuration).is_err() {
                bail!("the plugin could not create its editor");
            }
            // Before asking for the size, which depends on it. Wayland windows
            // are scaled by the compositor instead.
            if configuration.api_type == GuiApiType::X11 {
                let _ = gui.set_scale(plugin, ui_scale());
            }
            let window = if configuration.is_floating {
                // The plugin makes and manages the window; all it gets is a name.
                if let Ok(title) = CString::new(title) {
                    gui.suggest_title(plugin, &title);
                }
                None
            } else {
                let (width, height) = gui
                    .get_size(plugin)
                    .map_or((640, 480), |size| (size.width, size.height));
                let mut window = match HostWindow::new(title, width, height) {
                    Ok(window) => window,
                    Err(err) => {
                        gui.destroy(plugin);
                        return Err(err);
                    }
                };
                // SAFETY: The X11 window lives in `self.editor` until `close_editor`, which
                // destroys the plugin's editor before it drops the window.
                let parent = unsafe {
                    gui.set_parent(plugin, Window::from_x11_handle(window.id() as _))
                };
                if parent.is_err() {
                    gui.destroy(plugin);
                    bail!("the plugin refused the editor window");
                }
                window.set_fixed(!gui.can_resize(plugin));
                Some(window)
            };
            let _ = gui.show(plugin);
            Ok(window)
        })?;
        // Remember where every parameter stands, to notice what the editor changes.
        self.shared.flags.rescan.store(true, Relaxed);
        self.editor = Some(window);
        self.take_changes();
        Ok(())
    }

    fn close_editor(&mut self) {
        if self.editor.is_none() {
            return;
        }
        if let Some(gui) = self.shared.ext.gui {
            self.shared.on_main(|plugin| {
                let _ = gui.hide(plugin);
                gui.destroy(plugin);
            });
        }
        // The plugin's window is gone; now ours can go.
        self.editor = None;
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

/// Load one of the plugin's presets, by the id paw gave it: through the
/// preset-load extension, or its draft (compatible) id.
fn load_preset(plugin: &PluginMainThreadHandle, id: &[u8]) -> Result<()> {
    let standard = plugin.get_extension::<PluginPresetLoad>();
    let compat = match standard {
        Some(_) => None,
        None => Some(
            plugin
                .get_extension::<PresetLoadCompat>()
                .context("the plugin cannot load presets")?,
        ),
    };
    let id = String::from_utf8_lossy(id);
    let (location, key) = crate::presets::clap_preset_parts(&id)?;
    let location = location.as_ref().map(PresetLocation::as_location);
    let key = key.as_deref();
    let loaded = location.is_some_and(|location| match (standard, compat) {
        (Some(ext), _) => ext.load_from_location(plugin, location, key).is_ok(),
        (None, Some(ext)) => ext.load_from_location(plugin, location, key),
        (None, None) => false,
    });
    if !loaded {
        bail!("the plugin could not load the preset");
    }
    Ok(())
}

/// The preset-load extension under its draft id, which Clack does not ask
/// for: [`PluginPresetLoad`] asks only for the final one.
#[derive(Clone, Copy)]
struct PresetLoadCompat(RawExtension<PluginExtensionSide, clap_plugin_preset_load>);

// SAFETY: The draft id names the same table as the final one, `clap_plugin_preset_load`.
unsafe impl Extension for PresetLoadCompat {
    const IDENTIFIERS: &'static [&'static CStr] = &[CLAP_EXT_PRESET_LOAD_COMPAT];
    type ExtensionSide = PluginExtensionSide;

    unsafe fn from_raw(raw: RawExtension<PluginExtensionSide>) -> Self {
        // SAFETY: The caller gives the table that the id names.
        Self(unsafe { raw.cast() })
    }
}

impl PresetLoadCompat {
    /// As [`PluginPresetLoad::load_from_location`]: whether the plugin loaded it.
    fn load_from_location(
        &self,
        plugin: &PluginMainThreadHandle,
        location: Location,
        key: Option<&CStr>,
    ) -> bool {
        let Some(from_location) = plugin.use_extension(&self.0).from_location else {
            return false;
        };
        let (kind, path) = location.to_raw();
        let key = key.map_or(ptr::null(), CStr::as_ptr);
        // SAFETY: The function is the plugin's own, called on the main thread with its own
        // plugin; `path` and `key` are null or strings that live through the call.
        unsafe { from_location(plugin.as_raw_ptr(), kind, path, key) }
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
    fn stopped<R>(&self, f: impl FnOnce() -> R) -> Result<R> {
        let shared = &self.shared;
        let mut run = shared.run.lock().unwrap_or_else(|e| e.into_inner());
        shared.deactivate(&mut run);
        let result = f();
        *run = Some(shared.activate().map_err(|err| match err {
            PluginInstanceError::NullActivateFunction => anyhow::anyhow!("no activate"),
            _ => anyhow::anyhow!("the plugin failed to activate again"),
        })?);
        shared.flags.wake.store(true, Relaxed);
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

// --- what the host offers the plugin -----------------------------------------

/// paw's side of a plugin instance, for Clack: the callbacks the plugin may
/// make and the extensions it may ask for.
struct PawHost;

/// The callbacks the plugin may make from any thread: they only note what
/// it asked for in [`HostFlags`], for the main thread to act on.
struct HostShared {
    flags: Arc<HostFlags>,
}

/// The callbacks the plugin makes from the main thread.
struct HostMain<'a> {
    shared: &'a HostShared,
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
    }

    fn request_process(&self) {
        self.flags.wake.store(true, Relaxed);
    }

    fn request_callback(&self) {
        self.flags.callback.store(true, Relaxed);
    }
}

impl<'a> MainThreadHandler<'a> for HostMain<'a> {}

impl HostThreadCheckImpl for HostShared {
    fn is_main_thread(&self) -> bool {
        is_main_thread()
    }

    fn is_audio_thread(&self) -> bool {
        !is_main_thread()
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
        *self.flags.resize.lock().unwrap() = Some((size.width, size.height));
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
            .unwrap()
            .add_timer(period_ms as u64, timer);
        Ok(TimerId(timer))
    }

    fn unregister_timer(&self, TimerId(id): TimerId) -> Result<(), HostError> {
        self.shared.flags.watches.lock().unwrap().remove_timer(&id);
        Ok(())
    }
}

impl HostPosixFdImpl for HostMain<'_> {
    fn register_fd(&self, fd: i32, _: FdFlags) -> Result<(), HostError> {
        self.shared.flags.watches.lock().unwrap().fds.push((fd, ()));
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
            .unwrap()
            .fds
            .retain(|(known, ())| *known != fd);
        Ok(())
    }
}

