//! CLAP hosting. The file's entry, its plugin factory, the plugin instance,
//! the host's callbacks and processing (events, buffers, transport, tail) go
//! through Clack (`clack-host` and `clack-extensions`); the plugin's other
//! extensions are still `clap-sys`.
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
use clack_extensions::gui::{GuiSize, HostGui, HostGuiImpl};
use clack_extensions::log::{HostLog, HostLogImpl, LogSeverity};
use clack_extensions::params::{
    HostParams, HostParamsImplMainThread, HostParamsImplShared, ParamClearFlags, ParamRescanFlags,
};
use clack_extensions::posix_fd::{FdFlags, HostPosixFd, HostPosixFdImpl};
use clack_extensions::state::{HostState, HostStateImpl};
use clack_extensions::tail::{PluginTail, TailLength};
use clack_extensions::thread_check::{HostThreadCheck, HostThreadCheckImpl};
use clack_extensions::timer::{HostTimer, HostTimerImpl, TimerId};
use clack_host::entry::{EntryDescriptor, PluginEntry, PluginEntryError};
use clack_host::events::event_types::{TransportEvent, TransportFlags};
use clack_host::events::io::{InputEventBuffer, OutputEventBuffer, TryPushError};
use clack_host::events::spaces::CoreEventSpace;
use clack_host::events::EventFlags;
use clack_host::prelude::{
    ClapId, EventHeader, HostError, HostExtensions, HostHandlers, HostInfo, InputAudioBuffers,
    InputEvents, MainThreadHandler, OutputAudioBuffers, OutputEvents, PluginAudioConfiguration,
    PluginAudioProcessor, PluginInstance, PluginInstanceError, ProcessStatus, SharedHandler,
    UnknownEvent,
};
use clack_host::utils::FixedPoint;
use clap_sys::events::*;
use clap_sys::ext::audio_ports::{
    CLAP_EXT_AUDIO_PORTS, clap_audio_port_info, clap_plugin_audio_ports,
};
use clap_sys::ext::gui::{
    CLAP_EXT_GUI, CLAP_WINDOW_API_WAYLAND, CLAP_WINDOW_API_X11, clap_plugin_gui, clap_window,
    clap_window_handle,
};
use clap_sys::ext::note_name::{CLAP_EXT_NOTE_NAME, clap_note_name, clap_plugin_note_name};
use clap_sys::ext::note_ports::{
    CLAP_EXT_NOTE_PORTS, CLAP_NOTE_DIALECT_CLAP, CLAP_NOTE_DIALECT_MIDI, CLAP_NOTE_DIALECT_MIDI2,
    clap_note_port_info, clap_plugin_note_ports,
};
use clap_sys::ext::params::{
    CLAP_EXT_PARAMS, CLAP_PARAM_IS_AUTOMATABLE, CLAP_PARAM_IS_AUTOMATABLE_PER_CHANNEL,
    CLAP_PARAM_IS_AUTOMATABLE_PER_KEY, CLAP_PARAM_IS_AUTOMATABLE_PER_NOTE_ID, CLAP_PARAM_IS_ENUM,
    CLAP_PARAM_IS_HIDDEN, CLAP_PARAM_IS_MODULATABLE_PER_CHANNEL, CLAP_PARAM_IS_MODULATABLE_PER_KEY,
    CLAP_PARAM_IS_MODULATABLE_PER_NOTE_ID, CLAP_PARAM_IS_READONLY, CLAP_PARAM_IS_STEPPED,
    clap_param_info, clap_plugin_params,
};
use clap_sys::ext::posix_fd_support::{
    CLAP_EXT_POSIX_FD_SUPPORT, CLAP_POSIX_FD_READ, clap_plugin_posix_fd_support,
};
use clap_sys::ext::preset_load::{
    CLAP_EXT_PRESET_LOAD, CLAP_EXT_PRESET_LOAD_COMPAT, clap_plugin_preset_load,
};
use clap_sys::ext::render::{
    CLAP_EXT_RENDER, CLAP_RENDER_OFFLINE, CLAP_RENDER_REALTIME, clap_plugin_render,
};
use clap_sys::ext::state::{CLAP_EXT_STATE, clap_plugin_state};
use clap_sys::ext::timer_support::{CLAP_EXT_TIMER_SUPPORT, clap_plugin_timer_support};
use clap_sys::factory::preset_discovery::{
    CLAP_PRESET_DISCOVERY_FACTORY_ID, CLAP_PRESET_DISCOVERY_FACTORY_ID_COMPAT,
    clap_preset_discovery_factory,
};
use clap_sys::id::clap_id;
use clap_sys::plugin::clap_plugin;
use clap_sys::stream::{clap_istream, clap_ostream};
use paw_engine::device::{Change, Rest, assign_keys, silent};
use paw_engine::{
    Controller, Device, DeviceFactory, DeviceFormat, DeviceInfo, EventKind, Instance, Io,
    NOTE_BEND_RANGE, NoteCtl, ParamInfo, Ports, ProcessCtx, Registry, ump,
};

use crate::echo::Echo;
use crate::window::{HostWindow, Watches, WindowEvent, ui_scale};
use crate::{Found, HeldNotes, PluginFormat, is_main_thread, write_output};

/// A loaded `.clap` file. Never unloaded: plugins commonly leave threads and
/// static state behind that do not survive it.
struct Library {
    _lib: ManuallyDrop<libloading::Library>,
    /// The file's entry, initialized. Kept for good in `load`'s list, so
    /// Clack never calls the entry's `deinit`.
    entry: PluginEntry,
    /// The file's preset-discovery factory, or null.
    presets: *const clap_preset_discovery_factory,
}

// The preset-discovery factory is only used from the main thread.
// SAFETY: `presets` points into the plugin file's static entry data, and the file is never
// unloaded (ManuallyDrop), so moving a Library to another thread keeps it valid.
unsafe impl Send for Library {}
// SAFETY: The CLAP threading rules keep every call through `presets` on the main thread, and the
// fields are never written after `load`, so sharing a Library is sound.
unsafe impl Sync for Library {}

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
    let get_factory = entry.get_factory.context("no factory")?;
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
    // SAFETY: `get_factory` is the initialized entry's own function and gets static ids; a null
    // result means the file has no preset discovery.
    let presets = unsafe {
        let presets = get_factory(CLAP_PRESET_DISCOVERY_FACTORY_ID.as_ptr());
        if presets.is_null() {
            get_factory(CLAP_PRESET_DISCOVERY_FACTORY_ID_COMPAT.as_ptr())
        } else {
            presets
        }
    };
    let library = Arc::new(Library {
        _lib: ManuallyDrop::new(lib),
        entry,
        presets: presets.cast(),
    });
    loaded.push((path.to_path_buf(), library.clone()));
    Ok(library)
}

unsafe fn text(ptr: *const c_char) -> String {
    if ptr.is_null() {
        String::new()
    } else {
        // SAFETY: `ptr` is non-null (checked above) and the CLAP ABI requires the strings in a descriptor
        // or port to be NUL-terminated; the bytes are copied out before returning.
        unsafe { CStr::from_ptr(ptr) }
            .to_string_lossy()
            .into_owned()
    }
}

/// The text in a fixed-size buffer that a plugin filled: up to its first
/// NUL, or the whole buffer when the plugin wrote none.
fn buffer_text(buffer: &[c_char]) -> String {
    // SAFETY: `c_char` and `u8` have the same size and alignment, and the
    // slice is read only while `buffer` is borrowed.
    let bytes: &[u8] = unsafe { std::slice::from_raw_parts(buffer.as_ptr().cast(), buffer.len()) };
    match CStr::from_bytes_until_nul(bytes) {
        Ok(text) => text.to_string_lossy().into_owned(),
        Err(_) => String::from_utf8_lossy(bytes).into_owned(),
    }
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
    /// The raw plugin, from `instance`, for the calls that are still
    /// `clap-sys` (the plugin's extensions).
    plugin: *const clap_plugin,
    params: *const clap_plugin_params,
    state: *const clap_plugin_state,
    gui: *const clap_plugin_gui,
    timers: *const clap_plugin_timer_support,
    fds: *const clap_plugin_posix_fd_support,
    /// How long the plugin rings after its input stops, when it says.
    tail: Option<PluginTail>,
    /// The CLAP id and cookie of each parameter, in the order we list them.
    param_ids: Vec<(clap_id, *mut c_void)>,
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
// thread. `instance`, and the raw `plugin` and extension pointers outside of the processing
// functions, are only used on the main thread: `ClapFactory::create` makes the `Shared` there, the
// controller lives there, and both halves are dropped there (the engine drops a device on the main
// thread once the audio thread has let it go). The audio thread reaches the plugin only through
// the processor in `run` (which is `Send`), `tail` with the processor's handle while it holds
// `run`, and the atomics and mutexes in `flags`.
unsafe impl Send for Shared {}
// SAFETY: What the two threads share is `run` (a mutex), `flags` (atomics and mutexes) and the
// read-only `param_ids`, `param_infos`, `sample_rate` and `max_block`. `instance` is a `RefCell`
// that only the main thread touches (see above), so no two threads borrow it at once.
unsafe impl Sync for Shared {}

impl Shared {
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

unsafe fn extension<T>(plugin: *const clap_plugin, id: &CStr) -> *const T {
    // SAFETY: `plugin` is live and `get_extension` is the plugin's own function; the id is a live CStr.
    // The result is null or a table that lives as long as the plugin, and `T` is the table the id names.
    unsafe {
        match (*plugin).get_extension {
            Some(get) => get(plugin, id.as_ptr()).cast(),
            None => ptr::null(),
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
        let plugin: *const clap_plugin = instance.raw_instance();
        let tail = instance.plugin_handle().get_extension::<PluginTail>();
        // SAFETY: `plugin` is the live, initialized instance, which `shared` owns from here. Every
        // plugin function called here (the extensions, `activate`) is called in the order the ABI
        // requires, on the main thread, before the plugin is shared with the audio thread.
        unsafe {
            let mut shared = Shared {
                instance: RefCell::new(instance),
                plugin,
                params: extension(plugin, CLAP_EXT_PARAMS),
                state: extension(plugin, CLAP_EXT_STATE),
                gui: extension(plugin, CLAP_EXT_GUI),
                timers: extension(plugin, CLAP_EXT_TIMER_SUPPORT),
                fds: extension(plugin, CLAP_EXT_POSIX_FD_SUPPORT),
                tail,
                param_ids: Vec::new(),
                param_infos: Vec::new(),
                flags,
                run: Mutex::new(None),
                sample_rate: sample_rate as f64,
                // Clack refuses a longest block of 0 frames.
                max_block: (max_block as u32).max(1),
                _library: library,
            };
            read_params(&mut shared);

            let ports: *const clap_plugin_audio_ports = extension(plugin, CLAP_EXT_AUDIO_PORTS);
            let input_ports = port_infos(plugin, ports, true);
            let output_ports = port_infos(plugin, ports, false);
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
            let (dialects, preferred) = note_dialects(plugin);
            // Notes go as CLAP's own events unless the plugin prefers MIDI
            // 2.0, which alone carries a note's attribute (an articulation).
            let clap_notes =
                dialects & CLAP_NOTE_DIALECT_CLAP != 0 && preferred != CLAP_NOTE_DIALECT_MIDI2;
            // A channel's controllers, the pitch wheel, pressure and program
            // changes only exist as MIDI: 2.0 when the plugin takes it.
            let midi2 = dialects & CLAP_NOTE_DIALECT_MIDI2 != 0;
            let midi = !clap_notes || dialects & CLAP_NOTE_DIALECT_MIDI != 0;

            // Attachments take the plugin before it is active: ARA binds
            // a plugin to its document then.
            let attached = crate::attach::offer(c"clap", plugin.cast());
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
}

unsafe fn read_params(shared: &mut Shared) {
    // SAFETY: `shared.plugin` is live and `params` came from the plugin's own `get_extension`; `info` is
    // a zeroed `clap_param_info` (plain data, so zero is valid) that the plugin fills; `shared` is
    // borrowed mutably, so nothing else uses the plugin. Main thread, after `init`.
    unsafe {
        let Some(params) = shared.params.as_ref() else {
            return;
        };
        let (Some(count), Some(get_info)) = (params.count, params.get_info) else {
            return;
        };
        for index in 0..count(shared.plugin) {
            let mut info: clap_param_info = std::mem::zeroed();
            if !get_info(shared.plugin, index, &mut info) || info.flags & CLAP_PARAM_IS_HIDDEN != 0
            {
                continue;
            }
            shared.param_ids.push((info.id, info.cookie));
            let mut param = ParamInfo::new(
                &buffer_text(&info.name),
                info.min_value as f32,
                info.max_value as f32,
                info.default_value as f32,
                "",
            );
            param.id = info.id.to_string();
            param.group = buffer_text(&info.module).trim_matches('/').to_string();
            let flags = info.flags;
            param.automatable = flags & CLAP_PARAM_IS_AUTOMATABLE != 0;
            param.read_only = flags & CLAP_PARAM_IS_READONLY != 0;
            param.per_note = flags
                & (CLAP_PARAM_IS_AUTOMATABLE_PER_NOTE_ID
                    | CLAP_PARAM_IS_AUTOMATABLE_PER_KEY
                    | CLAP_PARAM_IS_AUTOMATABLE_PER_CHANNEL
                    | CLAP_PARAM_IS_MODULATABLE_PER_NOTE_ID
                    | CLAP_PARAM_IS_MODULATABLE_PER_KEY
                    | CLAP_PARAM_IS_MODULATABLE_PER_CHANNEL)
                != 0;
            if flags & CLAP_PARAM_IS_STEPPED != 0 {
                let span = (info.max_value - info.min_value).round();
                param.steps = if span > 0.0 && span < u32::MAX as f64 { span as u32 } else { 0 };
                // An enumeration names its steps: the plugin's own names.
                param.enumeration = flags & CLAP_PARAM_IS_ENUM != 0;
                if param.enumeration && (1..=256).contains(&param.steps) {
                    param.choices = (0..=param.steps)
                        .map(|step| {
                            value_text(shared.plugin, params, info.id, info.min_value + step as f64)
                                .unwrap_or_else(|| step.to_string())
                        })
                        .collect();
                } else {
                    param.boolean = param.steps == 1;
                }
            }
            shared.param_infos.push(param);
        }
        assign_keys(&mut shared.param_infos);
    }
}

/// A parameter's value as the plugin writes it.
unsafe fn value_text(
    plugin: *const clap_plugin,
    params: &clap_plugin_params,
    id: clap_id,
    value: f64,
) -> Option<String> {
    let to_text = params.value_to_text?;
    let mut buffer = [0 as c_char; 256];
    // SAFETY: `to_text` is the plugin's function; `buffer` is a live zeroed array, and the length passed
    // is its size, so the plugin writes within it.
    let written = unsafe { to_text(plugin, id, value, buffer.as_mut_ptr(), buffer.len() as u32) };
    written
        .then(|| buffer_text(&buffer))
        .filter(|t| !t.is_empty())
}

/// The channel count and name of each of the plugin's audio ports in one
/// direction.
unsafe fn port_infos(
    plugin: *const clap_plugin,
    ports: *const clap_plugin_audio_ports,
    is_input: bool,
) -> Vec<(usize, String)> {
    // SAFETY: `plugin` and `ports` came from the plugin; each `info` is a zeroed plain-data struct
    // that `get` fills for an index below `count`.
    unsafe {
        let Some(ports) = ports.as_ref() else {
            return Vec::new();
        };
        let (Some(count), Some(get)) = (ports.count, ports.get) else {
            return Vec::new();
        };
        (0..count(plugin, is_input))
            .map(|index| {
                let mut info: clap_audio_port_info = std::mem::zeroed();
                if get(plugin, index, is_input, &mut info) {
                    (info.channel_count as usize, buffer_text(&info.name))
                } else {
                    (0, String::new())
                }
            })
            .collect()
    }
}

/// The note dialects the plugin's first note input takes, and the one it
/// prefers.
unsafe fn note_dialects(plugin: *const clap_plugin) -> (u32, u32) {
    // SAFETY: `plugin` is live and `ports` is null or the plugin's note-ports table; `info` is a zeroed
    // plain-data struct that `get` fills.
    unsafe {
        let ports: *const clap_plugin_note_ports = extension(plugin, CLAP_EXT_NOTE_PORTS);
        let Some(ports) = ports.as_ref() else {
            return (0, 0);
        };
        let (Some(count), Some(get)) = (ports.count, ports.get) else {
            return (0, 0);
        };
        let mut info: clap_note_port_info = std::mem::zeroed();
        if count(plugin, true) > 0 && get(plugin, 0, true, &mut info) {
            (info.supported_dialects, info.preferred_dialect)
        } else {
            (0, 0)
        }
    }
}

/// What the plugin calls its keys (`clap.note-name`), as JSON: `{ "36":
/// "Kick", "24": "Sustain" }`, for keys of its first port on every channel
/// or the first. Empty when it names none.
unsafe fn note_names(plugin: *const clap_plugin) -> Vec<u8> {
    // SAFETY: `plugin` is live; the note-name table is null or the plugin's; each `name` is a zeroed
    // plain-data struct that `get` fills for an index below `count`.
    unsafe {
        let mut names = serde_json::Map::new();
        let ext: *const clap_plugin_note_name = extension(plugin, CLAP_EXT_NOTE_NAME);
        if let Some(ext) = ext.as_ref()
            && let (Some(count), Some(get)) = (ext.count, ext.get)
        {
            for index in 0..count(plugin) {
                let mut name: clap_note_name = std::mem::zeroed();
                let ours = |n: &clap_note_name| {
                    (n.port == -1 || n.port == 0) && matches!(n.channel, -1 | 0)
                };
                if !get(plugin, index, &mut name) || !ours(&name) {
                    continue;
                }
                let text = text(name.name.as_ptr());
                // A name for every key (-1) is no name for any one key.
                if (0..128).contains(&name.key) && !text.is_empty() {
                    names.insert(name.key.to_string(), text.into());
                }
            }
        }
        serde_json::to_vec(&names).unwrap_or_default()
    }
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
                    param_id,
                    cookie,
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
                let tail = self.shared.tail.map(|tail| tail.get(&processor.plugin_handle()));
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
    fn editor_api(&self) -> Option<(&'static CStr, bool)> {
        let plugin = self.shared.plugin;
        // SAFETY: `gui` is null or the plugin's gui table, which lives as long as the plugin.
        let supported = unsafe { self.shared.gui.as_ref()?.is_api_supported? };
        let wayland = std::env::var_os("WAYLAND_DISPLAY").is_some();
        [
            (CLAP_WINDOW_API_X11, false),
            (CLAP_WINDOW_API_WAYLAND, true),
            (CLAP_WINDOW_API_X11, true),
        ]
        .into_iter()
        .filter(|(api, _)| wayland || *api != CLAP_WINDOW_API_WAYLAND)
        // SAFETY: `supported` is the plugin's own function, called with the live plugin and a NUL-terminated
        // API name that is a static CStr.
        .find(|(api, floating)| unsafe { supported(plugin, api.as_ptr(), *floating) })
    }

    /// React to what happened to the editor window and what the plugin asked for.
    fn run_editor(&mut self) {
        let shared = &self.shared;
        let plugin = shared.plugin;
        let Some(editor) = self.editor.as_mut() else {
            return;
        };
        let mut close = shared.flags.closed.swap(false, Relaxed);
        // SAFETY: `plugin` and `shared.gui` are live; all calls are on the main thread, which the gui
        // extension requires; `width` and `height` are live locals.
        unsafe {
            let Some(gui) = shared.gui.as_ref() else {
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
                    WindowEvent::Resized(mut width, mut height) => {
                        // Let the plugin round the size to one it can draw, then
                        // make the window agree with what it settled on.
                        if gui.can_resize.is_some_and(|can| can(plugin)) {
                            if let Some(adjust) = gui.adjust_size {
                                adjust(plugin, &mut width, &mut height);
                            }
                            if let Some(set) = gui.set_size {
                                set(plugin, width, height);
                            }
                        } else if let Some(get) = gui.get_size {
                            get(plugin, &mut width, &mut height);
                        }
                        resized = Some((width, height));
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
            if let Some(on_timer) = shared.timers.as_ref().and_then(|t| t.on_timer) {
                for id in due {
                    on_timer(plugin, id);
                }
            }
            if let Some(on_fd) = shared.fds.as_ref().and_then(|f| f.on_fd) {
                for (fd, ()) in ready {
                    on_fd(plugin, fd, CLAP_POSIX_FD_READ);
                }
            }
        }
        if close {
            self.close_editor();
        }
    }
}

impl Controller for ClapController {
    fn set_offline(&mut self, offline: bool) {
        // SAFETY: `plugin` is live and the render extension (null or the plugin's table) is read on the main thread.
        unsafe {
            let render: *const clap_plugin_render = extension(self.shared.plugin, CLAP_EXT_RENDER);
            if let Some(set) = render.as_ref().and_then(|render| render.set) {
                let mode = if offline {
                    CLAP_RENDER_OFFLINE
                } else {
                    CLAP_RENDER_REALTIME
                };
                set(self.shared.plugin, mode);
            }
        }
    }

    fn params(&self) -> Vec<ParamInfo> {
        self.shared.param_infos.clone()
    }

    fn ports(&self) -> Ports {
        self.ports.clone()
    }

    fn value_text(&mut self, index: usize, value: f64) -> Option<String> {
        let (id, _) = *self.shared.param_ids.get(index)?;
        // SAFETY: `plugin` and `params` are live, and `to_text` runs on the main thread.
        unsafe { value_text(self.shared.plugin, self.shared.params.as_ref()?, id, value) }
    }

    fn text_value(&mut self, index: usize, text: &str) -> Option<f64> {
        let (id, _) = *self.shared.param_ids.get(index)?;
        let text = CString::new(text).ok()?;
        let mut value = 0.0;
        // SAFETY: `params` is null-checked by `as_ref`; `text` is a CString that lives through the call and
        // `value` is a live local.
        unsafe {
            let to_value = self.shared.params.as_ref()?.text_to_value?;
            to_value(self.shared.plugin, id, text.as_ptr(), &mut value)
                .then_some(value)
                .filter(|v| v.is_finite())
        }
    }

    fn value(&self, index: usize) -> Option<f64> {
        // SAFETY: `params` is null-checked by `as_ref`; `value` is a live local the plugin writes.
        unsafe {
            let get = self.shared.params.as_ref()?.get_value?;
            let (id, _) = *self.shared.param_ids.get(index)?;
            let mut value = 0.0;
            get(self.shared.plugin, id, &mut value).then_some(value)
        }
    }

    fn save_state(&mut self) -> Result<Option<Vec<u8>>> {
        unsafe extern "C" fn write(
            stream: *const clap_ostream,
            buffer: *const c_void,
            size: u64,
        ) -> i64 {
            // SAFETY: `stream.ctx` is the `Vec<u8>` that `save_state` put there, alive during `save`; the plugin
            // owns `buffer` for `size` readable bytes during the call.
            unsafe {
                let out = &mut *((*stream).ctx as *mut Vec<u8>);
                out.extend_from_slice(std::slice::from_raw_parts(
                    buffer as *const u8,
                    size as usize,
                ));
                size as i64
            }
        }
        // SAFETY: `state` is null-checked by `as_ref`; `stream` and `out` live on this frame until `save` returns.
        unsafe {
            let Some(save) = self.shared.state.as_ref().and_then(|s| s.save) else {
                return Ok(None);
            };
            let mut out = Vec::new();
            let stream = clap_ostream {
                ctx: &mut out as *mut Vec<u8> as *mut c_void,
                write: Some(write),
            };
            if !save(self.shared.plugin, &stream) {
                bail!("the plugin could not save its state");
            }
            Ok(Some(out))
        }
    }

    fn load_state(&mut self, state: &[u8]) -> Result<()> {
        unsafe extern "C" fn read(
            stream: *const clap_istream,
            buffer: *mut c_void,
            size: u64,
        ) -> i64 {
            // SAFETY: `stream.ctx` is the `&[u8]` that `load_state` put there, alive during `load`; the plugin
            // gives a `buffer` with room for `size` bytes, and `n <= size`.
            unsafe {
                let rest = &mut *((*stream).ctx as *mut &[u8]);
                let n = rest.len().min(size as usize);
                ptr::copy_nonoverlapping(rest.as_ptr(), buffer as *mut u8, n);
                *rest = &rest[n..];
                n as i64
            }
        }
        // SAFETY: `state` is null-checked by `as_ref`; `stream` and `rest` live on this frame until `load` returns.
        unsafe {
            let Some(load) = self.shared.state.as_ref().and_then(|s| s.load) else {
                return Ok(());
            };
            let mut rest = state;
            let stream = clap_istream {
                ctx: &mut rest as *mut &[u8] as *mut c_void,
                read: Some(read),
            };
            if !load(self.shared.plugin, &stream) {
                bail!("the plugin rejected the saved state");
            }
            // Some plugins take a state on only in their next block.
            self.shared.flags.wake.store(true, Relaxed);
            self.given_state();
            Ok(())
        }
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
                .position(|(known, _)| *known == id)
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
        let (api, floating) = self
            .editor_api()
            .context("this plugin has no editor this host can show")?;
        let plugin = self.shared.plugin;
        // SAFETY: `shared.gui` is non-null (`editor_api` found a supported API through it), the plugin is
        // live, and the gui calls are in the order the ABI requires (create, set_scale, set_parent,
        // show), on the main thread; `parent` lives through `set_parent`.
        unsafe {
            let gui = &*self.shared.gui;
            let destroy = || {
                if let Some(destroy) = gui.destroy {
                    destroy(plugin);
                }
            };
            if !gui.create.context("no gui.create")?(plugin, api.as_ptr(), floating) {
                bail!("the plugin could not create its editor");
            }
            // Before asking for the size, which depends on it. Wayland windows
            // are scaled by the compositor instead.
            if api == CLAP_WINDOW_API_X11
                && let Some(set_scale) = gui.set_scale
            {
                set_scale(plugin, ui_scale());
            }
            let window = if floating {
                // The plugin makes and manages the window; all it gets is a name.
                if let (Some(suggest), Ok(title)) = (gui.suggest_title, CString::new(title)) {
                    suggest(plugin, title.as_ptr());
                }
                None
            } else {
                let (mut width, mut height) = (640, 480);
                if let Some(get_size) = gui.get_size {
                    get_size(plugin, &mut width, &mut height);
                }
                let window = match HostWindow::new(title, width, height) {
                    Ok(window) => window,
                    Err(err) => {
                        destroy();
                        return Err(err);
                    }
                };
                let parent = clap_window {
                    api: CLAP_WINDOW_API_X11.as_ptr(),
                    specific: clap_window_handle {
                        x11: window.id() as _,
                    },
                };
                if !gui
                    .set_parent
                    .is_some_and(|set_parent| set_parent(plugin, &parent))
                {
                    destroy();
                    bail!("the plugin refused the editor window");
                }
                let mut window = window;
                window.set_fixed(!gui.can_resize.is_some_and(|can| can(plugin)));
                Some(window)
            };
            if let Some(show) = gui.show {
                show(plugin);
            }
            // Remember where every parameter stands, to notice what the editor changes.
            self.shared.flags.rescan.store(true, Relaxed);
            self.editor = Some(window);
        }
        self.take_changes();
        Ok(())
    }

    fn close_editor(&mut self) {
        if self.editor.is_none() {
            return;
        }
        // SAFETY: `plugin` is live and `gui` is null-checked by `as_ref`; `hide` and `destroy` are
        // called once, on the main thread, before the host window is dropped.
        unsafe {
            if let Some(gui) = self.shared.gui.as_ref() {
                if let Some(hide) = gui.hide {
                    hide(self.shared.plugin);
                }
                if let Some(destroy) = gui.destroy {
                    destroy(self.shared.plugin);
                }
            }
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
                // SAFETY: `presets` is null or the plugin file's preset-discovery factory, which lives as
                // long as the (never unloaded) file; this runs on the main thread.
                let presets = self.presets.get_or_insert_with(|| unsafe {
                    crate::presets::clap_presets(self.shared._library.presets, &self.plugin_id)
                });
                Ok(crate::presets::to_json(presets))
            }
            // SAFETY: `plugin` is live; the extension is null-checked; the CStrings live through the call.
            paw_engine::device::method::PRESET_LOAD => unsafe {
                let plugin = self.shared.plugin;
                let mut ext: *const clap_plugin_preset_load =
                    extension(plugin, CLAP_EXT_PRESET_LOAD);
                if ext.is_null() {
                    ext = extension(plugin, CLAP_EXT_PRESET_LOAD_COMPAT);
                }
                let load = ext
                    .as_ref()
                    .and_then(|e| e.from_location)
                    .context("the plugin cannot load presets")?;
                let id = String::from_utf8_lossy(data);
                let (kind, location, key) = crate::presets::clap_preset_parts(&id)?;
                let ptr_of = |c: &Option<CString>| c.as_ref().map_or(ptr::null(), |c| c.as_ptr());
                if !load(plugin, kind, ptr_of(&location), ptr_of(&key)) {
                    bail!("the plugin could not load the preset");
                }
                // What the preset changed is read back, as the echo of a
                // state.
                self.shared.flags.rescan.store(true, Relaxed);
                self.given_state();
                Ok(Vec::new())
            },
            // SAFETY: `plugin` is live and this runs on the main thread.
            paw_engine::device::method::NOTE_NAMES => Ok(unsafe { note_names(self.shared.plugin) }),
            // SAFETY: `plugin` is live and the extension is null-checked; `name`, `data` and `answer` live through
            // the call, and `call_write` is the callback type the extension expects.
            _ => unsafe {
                let ext: *const PawPluginCall = extension(self.shared.plugin, PAW_EXT_CALL);
                let call = ext
                    .as_ref()
                    .and_then(|e| e.call)
                    .with_context(|| format!("this device has no method `{method}`"))?;
                let name = CString::new(method)?;
                let mut answer: Vec<u8> = Vec::new();
                let ok = call(
                    self.shared.plugin,
                    name.as_ptr(),
                    data.as_ptr(),
                    data.len(),
                    &mut answer as *mut Vec<u8> as *mut c_void,
                    Some(call_write),
                );
                // What the plugin read or loaded may have changed its parameters.
                self.shared.flags.rescan.store(true, Relaxed);
                if !ok {
                    bail!("{}", String::from_utf8_lossy(&answer));
                }
                Ok(answer)
            },
        }
    }
}

/// paw's own extension, for plugins that answer `device_call` methods the
/// host does not know (paw's sampler answers `describe`): the plugin
/// writes its answer through `write`, and returns false when the method
/// failed, having written why.
const PAW_EXT_CALL: &CStr = c"dev.paw.call/1";

#[repr(C)]
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_buffer_text_stops_at_the_nul_and_reads_no_further_without_one() {
        let mut buffer = [b'x' as c_char; 4];
        assert_eq!(buffer_text(&buffer), "xxxx");
        buffer[2] = 0;
        assert_eq!(buffer_text(&buffer), "xx");
    }
}
