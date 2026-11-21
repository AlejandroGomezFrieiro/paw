//! CLAP hosting, written against the C interface. The file's entry and its
//! plugin factory go through Clack's host crate (`clack-host`); the rest is
//! still `clap-sys`.
//!
//! Threading follows the CLAP rules: a plugin is created, activated,
//! deactivated and destroyed on the main thread, and `start_processing` and
//! `process` run on the audio thread. [`ClapDevice`] is the audio-thread half
//! and [`ClapController`] the main-thread half; both hold the same [`Shared`],
//! which destroys the plugin when the last of them is dropped.

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
use clack_host::entry::{EntryDescriptor, PluginEntry, PluginEntryError};
use clap_sys::events::*;
use clap_sys::ext::audio_ports::{
    CLAP_EXT_AUDIO_PORTS, clap_audio_port_info, clap_plugin_audio_ports,
};
use clap_sys::ext::gui::{
    CLAP_EXT_GUI, CLAP_WINDOW_API_WAYLAND, CLAP_WINDOW_API_X11, clap_host_gui, clap_plugin_gui,
    clap_window, clap_window_handle,
};
use clap_sys::ext::log::{CLAP_EXT_LOG, clap_host_log, clap_log_severity};
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
    clap_host_params, clap_param_info, clap_plugin_params,
};
use clap_sys::ext::posix_fd_support::{
    CLAP_EXT_POSIX_FD_SUPPORT, CLAP_POSIX_FD_READ, clap_host_posix_fd_support,
    clap_plugin_posix_fd_support,
};
use clap_sys::ext::preset_load::{
    CLAP_EXT_PRESET_LOAD, CLAP_EXT_PRESET_LOAD_COMPAT, clap_plugin_preset_load,
};
use clap_sys::ext::render::{
    CLAP_EXT_RENDER, CLAP_RENDER_OFFLINE, CLAP_RENDER_REALTIME, clap_plugin_render,
};
use clap_sys::ext::state::{CLAP_EXT_STATE, clap_host_state, clap_plugin_state};
use clap_sys::ext::thread_check::{CLAP_EXT_THREAD_CHECK, clap_host_thread_check};
use clap_sys::ext::timer_support::{
    CLAP_EXT_TIMER_SUPPORT, clap_host_timer_support, clap_plugin_timer_support,
};
use clap_sys::factory::plugin_factory::clap_plugin_factory;
use clap_sys::factory::preset_discovery::{
    CLAP_PRESET_DISCOVERY_FACTORY_ID, CLAP_PRESET_DISCOVERY_FACTORY_ID_COMPAT,
    clap_preset_discovery_factory,
};
use clap_sys::fixedpoint::{CLAP_BEATTIME_FACTOR, CLAP_SECTIME_FACTOR};
use clap_sys::host::clap_host;
use clap_sys::id::clap_id;
use clap_sys::plugin::clap_plugin;
use clap_sys::ext::tail::{CLAP_EXT_TAIL, clap_plugin_tail};
use clap_sys::process::{
    CLAP_PROCESS_CONTINUE_IF_NOT_QUIET, CLAP_PROCESS_ERROR, CLAP_PROCESS_SLEEP, CLAP_PROCESS_TAIL,
    clap_process,
};
use clap_sys::stream::{clap_istream, clap_ostream};
use clap_sys::version::CLAP_VERSION;
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
    factory: *const clap_plugin_factory,
    /// The file's preset-discovery factory, or null.
    presets: *const clap_preset_discovery_factory,
}

// The factory is only used from the main thread.
// SAFETY: `factory` and `presets` point into the plugin file's static entry data, and the file is never
// unloaded (ManuallyDrop), so moving a Library to another thread keeps them valid.
unsafe impl Send for Library {}
// SAFETY: The CLAP threading rules keep every call through `factory` and `presets` on the main
// thread, and the fields are never written after `load`, so sharing a Library is sound.
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
    let factory = entry
        .get_plugin_factory()
        .context("the file has no plugin factory")?
        .raw()
        .as_ptr()
        .cast_const();
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
        factory,
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
    plugin: *const clap_plugin,
    params: *const clap_plugin_params,
    state: *const clap_plugin_state,
    gui: *const clap_plugin_gui,
    timers: *const clap_plugin_timer_support,
    fds: *const clap_plugin_posix_fd_support,
    /// How long the plugin rings after its input stops, when it says.
    tail: *const clap_plugin_tail,
    /// The CLAP id and cookie of each parameter, in the order we list them.
    param_ids: Vec<(clap_id, *mut c_void)>,
    param_infos: Vec<ParamInfo>,
    flags: Arc<HostFlags>,
    /// Held by the audio thread while the plugin processes a block, and by
    /// the main thread while it is deactivated for an attachment
    /// ([`ClapController::stopped`]): the audio thread only tries it, and
    /// leaves the block to the plugin's stand-in when it cannot have it.
    run: Mutex<()>,
    /// The audio thread has started the plugin processing.
    processing: AtomicBool,
    /// The plugin was deactivated and activated again: the audio thread
    /// starts it processing anew.
    restarted: AtomicBool,
    /// The plugin is active: between its `activate` and its `deactivate`.
    active: AtomicBool,
    sample_rate: f64,
    max_block: u32,
    // Kept alive for the plugin, which holds pointers into both.
    _host: Box<clap_host>,
    _library: Arc<Library>,
}

// The pointers are only followed under the CLAP threading rules: `plugin`'s
// processing functions from the audio thread, everything else from the main
// thread, with both halves dropped on the main thread.
// SAFETY: The raw pointers in `Shared` are used under the CLAP threading rules (see the comment
// above): the processing functions only on the audio thread, the rest only on the main thread.
// Both halves are dropped on the main thread.
unsafe impl Send for Shared {}
// SAFETY: What the two threads share is atomics, mutexes and the read-only `param_ids`, `param_infos`;
// the plugin pointers follow the threading rules named above.
unsafe impl Sync for Shared {}

impl Drop for Shared {
    fn drop(&mut self) {
        // SAFETY: `plugin` was returned by `create_plugin` and is destroyed once, here, when the last
        // half is dropped; the device has stopped and deactivated it already (`ClapDevice::drop`).
        unsafe {
            if let Some(destroy) = (*self.plugin).destroy {
                destroy(self.plugin);
            }
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
        // SAFETY: The library is loaded and `factory` is a live plugin factory; the host given to the plugin
        // is boxed, so its address stays put, and is kept alive in `Shared::_host`. Every plugin
        // function called here (`init`, `activate`, the extensions) is called in the order the ABI
        // requires, on the main thread, before the plugin is shared with the audio thread.
        unsafe {
            let flags = Arc::new(HostFlags::new());
            let host = Box::new(clap_host {
                clap_version: CLAP_VERSION,
                host_data: Arc::as_ptr(&flags) as *mut c_void,
                name: c"paw".as_ptr(),
                vendor: c"paw".as_ptr(),
                url: c"".as_ptr(),
                version: c"0.1.0".as_ptr(),
                get_extension: Some(host_get_extension),
                request_restart: Some(host_request_restart),
                request_process: Some(host_request_process),
                request_callback: Some(host_request_callback),
            });
            let factory = &*library.factory;
            let plugin = factory.create_plugin.context("no create_plugin")?(
                library.factory,
                &*host,
                self.id.as_ptr(),
            );
            if plugin.is_null() {
                bail!("{} could not create the plugin", self.path.display());
            }
            let mut shared = Shared {
                plugin,
                params: ptr::null(),
                state: ptr::null(),
                gui: ptr::null(),
                timers: ptr::null(),
                fds: ptr::null(),
                tail: ptr::null(),
                param_ids: Vec::new(),
                param_infos: Vec::new(),
                flags,
                run: Mutex::new(()),
                processing: AtomicBool::new(false),
                restarted: AtomicBool::new(false),
                active: AtomicBool::new(false),
                sample_rate: sample_rate as f64,
                max_block: max_block as u32,
                _host: host,
                _library: library,
            };
            if !(*plugin).init.context("no init")?(plugin) {
                bail!("the plugin failed to initialize");
            }
            shared.params = extension(plugin, CLAP_EXT_PARAMS);
            shared.state = extension(plugin, CLAP_EXT_STATE);
            shared.gui = extension(plugin, CLAP_EXT_GUI);
            shared.timers = extension(plugin, CLAP_EXT_TIMER_SUPPORT);
            shared.fds = extension(plugin, CLAP_EXT_POSIX_FD_SUPPORT);
            shared.tail = extension(plugin, CLAP_EXT_TAIL);
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
            let activate = (*plugin).activate.context("no activate")?;
            if !activate(plugin, sample_rate as f64, 1, max_block as u32) {
                bail!("the plugin failed to activate");
            }
            shared.active.store(true, Relaxed);
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
                events: Vec::with_capacity(2048),
                pending: Vec::with_capacity(512),
                held: HeldNotes::new(),
                clap_notes,
                midi,
                midi2,
                started: false,
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
    events: Vec<ClapEvent>,
    /// Parameter changes waiting for the next block: index and value.
    pending: Vec<(u32, f32)>,
    held: HeldNotes,
    /// Whether the plugin takes CLAP note events rather than MIDI.
    clap_notes: bool,
    /// Whether it takes MIDI 1.0 messages, and MIDI 2.0 ones, for what is
    /// not a note.
    midi: bool,
    midi2: bool,
    started: bool,
    failed: bool,
    steady_time: i64,
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
        let plugin = self.shared.plugin;
        // Woken: its tail starts again from here.
        self.rest.begin(io, self.shared.flags.wake.swap(false, Relaxed));
        // The main thread has the plugin deactivated for an attachment:
        // this block is the stand-in's, silence for an instrument and the
        // input passed through for an effect.
        // SAFETY: `shared` lives as long as `self`, which holds it.
        let shared: &Shared = unsafe { &*Arc::as_ptr(&self.shared) };
        let running = shared.run.try_lock();
        if running.is_err() || !shared.active.load(Relaxed) {
            if self.inputs.ports.is_empty() {
                io.left.fill(0.0);
                io.right.fill(0.0);
            }
            return;
        }
        if shared.restarted.swap(false, Relaxed) {
            self.started = false;
        }
        // SAFETY: `plugin` is the live plugin and `shared.run` is held (the `try_lock` above), so the main
        // thread cannot deactivate it; the buffers' pointers lead to `max_block` frames per channel
        // and `n <= max_block`; `in_events`, `out_events`, `transport` and `process` live on this
        // frame until `process` returns; `self.out` and `self.events` are not touched while the plugin
        // holds them. Called on the audio thread, as `start_processing` and `process` require.
        unsafe {
            if !self.started && !self.failed {
                self.started = (*plugin).start_processing.is_none_or(|start| start(plugin));
                self.failed = !self.started;
                shared.processing.store(self.started, Relaxed);
            }
            if !self.started {
                return;
            }

            if let Some(port) = self.inputs.channels.first_mut() {
                match port.as_mut_slice() {
                    [] => {}
                    [mono] => {
                        for (m, (l, r)) in mono.iter_mut().zip(io.left.iter().zip(io.right.iter()))
                        {
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

            self.events.clear();
            for (index, value) in self.pending.drain(..) {
                let Some(&(param_id, cookie)) = self.shared.param_ids.get(index as usize) else {
                    continue;
                };
                self.events.push(ClapEvent {
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
            let (events, clap_notes) = (&mut self.events, self.clap_notes);
            let (midi, midi2) = (self.midi, self.midi2);
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

            let beats = |b: f64| (b * CLAP_BEATTIME_FACTOR as f64) as i64;
            let mut transport: clap_event_transport = std::mem::zeroed();
            transport.header = header::<clap_event_transport>(0, CLAP_EVENT_TRANSPORT);
            transport.flags = CLAP_TRANSPORT_HAS_TEMPO
                | CLAP_TRANSPORT_HAS_BEATS_TIMELINE
                | CLAP_TRANSPORT_HAS_SECONDS_TIMELINE
                | CLAP_TRANSPORT_HAS_TIME_SIGNATURE
                | if ctx.playing {
                    CLAP_TRANSPORT_IS_PLAYING
                } else {
                    0
                };
            transport.song_pos_beats = beats(ctx.position);
            transport.song_pos_seconds = (ctx.seconds * CLAP_SECTIME_FACTOR as f64) as i64;
            transport.tempo = ctx.tempo;
            transport.bar_start = beats(ctx.bar_start);
            transport.bar_number = ctx.bar as i32;
            transport.tsig_num = ctx.sig_num as u16;
            transport.tsig_denom = ctx.sig_den as u16;

            let in_events = clap_input_events {
                ctx: &mut self.events as *mut Vec<ClapEvent> as *mut c_void,
                size: Some(events_size),
                get: Some(events_get),
            };
            // Set before `out_events` takes its pointer to `self.out`, which
            // nothing else touches until `process` returns.
            let loads = self.shared.flags.loads.load(Ordering::Acquire);
            self.out.taking = loads != self.loads;
            self.loads = loads;
            let out_events = clap_output_events {
                ctx: &mut self.out as *mut Out as *mut c_void,
                try_push: Some(events_push),
            };
            let process = clap_process {
                steady_time: self.steady_time,
                frames_count: n as u32,
                transport: &transport,
                audio_inputs: self.inputs.ports.as_ptr(),
                audio_outputs: self.outputs.ports.as_mut_ptr(),
                audio_inputs_count: self.inputs.ports.len() as u32,
                audio_outputs_count: self.outputs.ports.len() as u32,
                in_events: &in_events,
                out_events: &out_events,
            };
            self.steady_time += n as i64;
            let Some(run) = (*plugin).process else { return };
            let status = run(plugin, &process);
            // Counted once the block is done: a state taken on in it, and
            // the plugin's words of it, are there before the count is.
            self.shared.flags.blocks.fetch_add(1, Ordering::Release);
            if status == CLAP_PROCESS_ERROR {
                return;
            }
            // Whether the plugin may sleep through silence from here on:
            // it says so, or says it may once its output is quiet, or once
            // its tail has gone by.
            let out_quiet = || self.outputs.channels.iter().flatten().all(|c| silent(&c[..n]));
            match status {
                CLAP_PROCESS_SLEEP => self.rest.end(true),
                CLAP_PROCESS_CONTINUE_IF_NOT_QUIET => self.rest.end(out_quiet()),
                CLAP_PROCESS_TAIL => {
                    let tail = self.shared.tail;
                    let frames = tail
                        .as_ref()
                        .and_then(|t| t.get)
                        .map(|get| get(plugin))
                        .filter(|frames| *frames != u32::MAX);
                    self.rest.end_after_tail(frames.map(u64::from), out_quiet());
                }
                _ => self.rest.end(false),
            }
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
        let plugin = self.shared.plugin;
        // SAFETY: `plugin` is live, and this runs on the main thread after the audio thread let the device
        // go, so `stop_processing` and `deactivate` do not race with `process`.
        unsafe {
            if self.started
                && self.shared.processing.load(Relaxed)
                && let Some(stop) = (*plugin).stop_processing
            {
                stop(plugin);
            }
            if self.shared.active.swap(false, Relaxed)
                && let Some(deactivate) = (*plugin).deactivate
            {
                deactivate(plugin);
            }
        }
    }
}

unsafe extern "C" fn events_size(list: *const clap_input_events) -> u32 {
    // SAFETY: `list.ctx` is the `Vec<ClapEvent>` that `process` put there, alive until `process`
    // returns; the plugin calls this inside `process` only.
    unsafe { (*((*list).ctx as *const Vec<ClapEvent>)).len() as u32 }
}

unsafe extern "C" fn events_get(
    list: *const clap_input_events,
    index: u32,
) -> *const clap_event_header {
    // SAFETY: `list.ctx` is the `Vec<ClapEvent>` that `process` put there; the pointer returned points
    // into it and stays valid for the block.
    unsafe {
        let events = &*((*list).ctx as *const Vec<ClapEvent>);
        events
            .get(index as usize)
            .map_or(ptr::null(), |event| &event.header)
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
unsafe extern "C" fn events_push(
    list: *const clap_output_events,
    event: *const clap_event_header,
) -> bool {
    // SAFETY: `event` is a valid CLAP event (the plugin owns it for the call) of the size its header
    // says, and the cast matches `type_`; `list.ctx` is the `Out` that `process` put there, used
    // only inside `process`, on the audio thread.
    unsafe {
        if (*event).space_id != CLAP_CORE_EVENT_SPACE_ID {
            return true;
        }
        let out = &mut *((*list).ctx as *mut Out);
        match (*event).type_ {
            CLAP_EVENT_PARAM_VALUE => {
                let event = &*(event as *const clap_event_param_value);
                let gesture = out.gestures.contains(&event.param_id);
                let _ = out.changed.push((event.param_id, event.value, gesture, out.taking));
            }
            CLAP_EVENT_PARAM_GESTURE_BEGIN => {
                let event = &*(event as *const clap_event_param_gesture);
                // Room is kept for many at once: no allocation here.
                if out.gestures.len() < out.gestures.capacity() {
                    out.gestures.push(event.param_id);
                }
            }
            CLAP_EVENT_PARAM_GESTURE_END => {
                let event = &*(event as *const clap_event_param_gesture);
                out.gestures.retain(|id| *id != event.param_id);
            }
            _ => {}
        }
    }
    true
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
            // SAFETY: `plugin` is live and `on_main_thread` runs on the main thread, as the plugin asked.
            unsafe {
                if let Some(on_main_thread) = (*self.shared.plugin).on_main_thread {
                    on_main_thread(self.shared.plugin);
                }
            }
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
        let plugin = shared.plugin;
        let _held = shared.run.lock().unwrap_or_else(|e| e.into_inner());
        // SAFETY: `plugin` is live, `shared.run` is held so the audio thread is off it, and the calls
        // (`stop_processing`, `deactivate`, `activate`) are made from the main thread as the ABI wants.
        unsafe {
            if shared.processing.swap(false, Relaxed)
                && let Some(stop) = (*plugin).stop_processing
            {
                stop(plugin);
            }
            if shared.active.swap(false, Relaxed)
                && let Some(deactivate) = (*plugin).deactivate
            {
                deactivate(plugin);
            }
            let result = f();
            let activate = (*plugin).activate.context("no activate")?;
            if !activate(plugin, shared.sample_rate, 1, shared.max_block) {
                bail!("the plugin failed to activate again");
            }
            shared.active.store(true, Relaxed);
            shared.restarted.store(true, Relaxed);
            shared.flags.wake.store(true, Relaxed);
            Ok(result)
        }
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
            let shared = &self.shared;
            let plugin = shared.plugin;
            let _held = shared.run.lock().unwrap_or_else(|e| e.into_inner());
            // SAFETY: `plugin` is live and the audio thread is held off by `run`, as in `stopped`.
            unsafe {
                if shared.processing.swap(false, Relaxed)
                    && let Some(stop) = (*plugin).stop_processing
                {
                    stop(plugin);
                }
                if shared.active.swap(false, Relaxed)
                    && let Some(deactivate) = (*plugin).deactivate
                {
                    deactivate(plugin);
                }
            }
            self.attached.clear();
        }
    }
}

// --- what the host offers the plugin -----------------------------------------

unsafe fn flags<'a>(host: *const clap_host) -> &'a HostFlags {
    // SAFETY: `host.host_data` is the `Arc<HostFlags>` pointer that `create` set, kept alive by
    // `Shared::flags` as long as the plugin; the plugin gives back the host it was created with.
    unsafe { &*((*host).host_data as *const HostFlags) }
}

unsafe extern "C" fn host_request_restart(host: *const clap_host) {
    // SAFETY: The plugin gives back the host it was created with (see `flags`).
    unsafe { flags(host) }.restart.store(true, Relaxed);
}

unsafe extern "C" fn host_request_process(host: *const clap_host) {
    // SAFETY: The plugin gives back the host it was created with (see `flags`).
    unsafe { flags(host) }.wake.store(true, Relaxed);
}

unsafe extern "C" fn host_request_callback(host: *const clap_host) {
    // SAFETY: The plugin gives back the host it was created with (see `flags`).
    unsafe { flags(host) }.callback.store(true, Relaxed);
}

unsafe extern "C" fn host_is_main_thread(_: *const clap_host) -> bool {
    is_main_thread()
}

unsafe extern "C" fn host_is_audio_thread(_: *const clap_host) -> bool {
    !is_main_thread()
}

unsafe extern "C" fn host_log(_: *const clap_host, _: clap_log_severity, _: *const c_char) {}

unsafe extern "C" fn host_params_rescan(host: *const clap_host, _: u32) {
    // SAFETY: The plugin gives back the host it was created with (see `flags`).
    unsafe { flags(host) }.rescan.store(true, Relaxed);
}

unsafe extern "C" fn host_gui_request_resize(
    host: *const clap_host,
    width: u32,
    height: u32,
) -> bool {
    // SAFETY: The plugin gives back the host it was created with (see `flags`).
    *unsafe { flags(host) }.resize.lock().unwrap() = Some((width, height));
    true
}

unsafe extern "C" fn host_gui_request_show(_: *const clap_host) -> bool {
    true
}

unsafe extern "C" fn host_gui_closed(host: *const clap_host, _was_destroyed: bool) {
    // SAFETY: The plugin gives back the host it was created with (see `flags`).
    unsafe { flags(host) }.closed.store(true, Relaxed);
}

unsafe extern "C" fn host_register_timer(
    host: *const clap_host,
    period_ms: u32,
    id: *mut clap_id,
) -> bool {
    // SAFETY: The plugin gives back the host it was created with (see `flags`).
    let flags = unsafe { flags(host) };
    let timer = flags.next_timer.fetch_add(1, Relaxed);
    flags
        .watches
        .lock()
        .unwrap()
        .add_timer(period_ms as u64, timer);
    // SAFETY: The plugin gives a non-null `id` to write the timer id to, as the ABI requires.
    unsafe { *id = timer };
    true
}

unsafe extern "C" fn host_unregister_timer(host: *const clap_host, id: clap_id) -> bool {
    // SAFETY: The plugin gives back the host it was created with (see `flags`).
    unsafe { flags(host) }
        .watches
        .lock()
        .unwrap()
        .remove_timer(&id);
    true
}

unsafe extern "C" fn host_register_fd(host: *const clap_host, fd: i32, _flags: u32) -> bool {
    // SAFETY: The plugin gives back the host it was created with (see `flags`).
    unsafe { flags(host) }
        .watches
        .lock()
        .unwrap()
        .fds
        .push((fd, ()));
    true
}

unsafe extern "C" fn host_modify_fd(_: *const clap_host, _fd: i32, _flags: u32) -> bool {
    true
}

unsafe extern "C" fn host_unregister_fd(host: *const clap_host, fd: i32) -> bool {
    // SAFETY: The plugin gives back the host it was created with (see `flags`).
    unsafe { flags(host) }
        .watches
        .lock()
        .unwrap()
        .fds
        .retain(|(known, ())| *known != fd);
    true
}

unsafe extern "C" fn host_params_clear(_: *const clap_host, _: clap_id, _: u32) {}

unsafe extern "C" fn host_noop(_: *const clap_host) {}

static THREAD_CHECK: clap_host_thread_check = clap_host_thread_check {
    is_main_thread: Some(host_is_main_thread),
    is_audio_thread: Some(host_is_audio_thread),
};
static LOG: clap_host_log = clap_host_log {
    log: Some(host_log),
};
static PARAMS: clap_host_params = clap_host_params {
    rescan: Some(host_params_rescan),
    clear: Some(host_params_clear),
    request_flush: Some(host_noop),
};
static STATE: clap_host_state = clap_host_state {
    mark_dirty: Some(host_noop),
};

static GUI: clap_host_gui = clap_host_gui {
    resize_hints_changed: Some(host_noop),
    request_resize: Some(host_gui_request_resize),
    request_show: Some(host_gui_request_show),
    request_hide: Some(host_gui_request_show),
    closed: Some(host_gui_closed),
};
static TIMERS: clap_host_timer_support = clap_host_timer_support {
    register_timer: Some(host_register_timer),
    unregister_timer: Some(host_unregister_timer),
};
static FDS: clap_host_posix_fd_support = clap_host_posix_fd_support {
    register_fd: Some(host_register_fd),
    modify_fd: Some(host_modify_fd),
    unregister_fd: Some(host_unregister_fd),
};

unsafe extern "C" fn host_get_extension(_: *const clap_host, id: *const c_char) -> *const c_void {
    // SAFETY: The plugin gives a non-null NUL-terminated extension id that lives through the call.
    let id = unsafe { CStr::from_ptr(id) };
    if id == CLAP_EXT_THREAD_CHECK {
        &THREAD_CHECK as *const _ as *const c_void
    } else if id == CLAP_EXT_LOG {
        &LOG as *const _ as *const c_void
    } else if id == CLAP_EXT_PARAMS {
        &PARAMS as *const _ as *const c_void
    } else if id == CLAP_EXT_STATE {
        &STATE as *const _ as *const c_void
    } else if id == CLAP_EXT_GUI {
        &GUI as *const _ as *const c_void
    } else if id == CLAP_EXT_TIMER_SUPPORT {
        &TIMERS as *const _ as *const c_void
    } else if id == CLAP_EXT_POSIX_FD_SUPPORT {
        &FDS as *const _ as *const c_void
    } else {
        ptr::null()
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
