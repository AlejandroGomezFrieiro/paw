//! LV2 hosting on top of lilv.
//!
//! lilv finds plugins and reads their descriptions without loading any code,
//! so there is nothing to cache. A plugin gets these host features: URID
//! mapping, options (block length and sample rate), bounded block length, the
//! worker for non-real-time work, and state through lilv's state functions.

use std::cell::{Cell, RefCell, UnsafeCell};
use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char, c_void};
use std::path::PathBuf;
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering::Relaxed};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread::JoinHandle;
use std::time::Duration;

use anyhow::{Context, Result, anyhow, bail};
use paw_engine::device::Change;
use paw_engine::{
    Category, Controller, Device, DeviceFactory, DeviceFormat, DeviceInfo, EventKind, Instance, Io,
    ParamInfo, Ports, ProcessCtx, Registry, Rest, ump,
};
use lilv_sys::*;

use crate::echo::Echo;
use crate::lv2_patch::{self, Kind, PatchUrids, Property};
use crate::window::{GtkWindow, HostWindow, WindowEvent, ui_scale};
use crate::{HeldNotes, search_dirs, write_output};

const LV2_CORE: &str = "http://lv2plug.in/ns/lv2core#";
const ATOM: &str = "http://lv2plug.in/ns/ext/atom#";
const URID_MAP: &CStr = c"http://lv2plug.in/ns/ext/urid#map";
const URID_UNMAP: &CStr = c"http://lv2plug.in/ns/ext/urid#unmap";
const OPTIONS: &CStr = c"http://lv2plug.in/ns/ext/options#options";
const BOUNDED_BLOCK: &CStr = c"http://lv2plug.in/ns/ext/buf-size#boundedBlockLength";
const WORKER_SCHEDULE: &CStr = c"http://lv2plug.in/ns/ext/worker#schedule";
const WORKER_INTERFACE: &CStr = c"http://lv2plug.in/ns/ext/worker#interface";
const LOAD_DEFAULT_STATE: &CStr = c"http://lv2plug.in/ns/ext/state#loadDefaultState";
const STATE_URI: &CStr = c"urn:paw:state";

/// Bytes of event data an atom port can hold per block.
const ATOM_CAPACITY: usize = 32 * 1024;
const WORK_CAPACITY: usize = 64 * 1024;

// The few LV2 structures the host fills in itself.

#[repr(C)]
struct Feature {
    uri: *const c_char,
    data: *mut c_void,
}

#[repr(C)]
struct UridMap {
    handle: *mut c_void,
    map: unsafe extern "C" fn(*mut c_void, *const c_char) -> u32,
}

#[repr(C)]
struct UridUnmap {
    handle: *mut c_void,
    unmap: unsafe extern "C" fn(*mut c_void, u32) -> *const c_char,
}

#[repr(C)]
struct OptionsOption {
    context: u32,
    subject: u32,
    key: u32,
    size: u32,
    type_: u32,
    value: *const c_void,
}

type RespondFn = unsafe extern "C" fn(*mut c_void, u32, *const c_void) -> u32;

#[repr(C)]
struct WorkerSchedule {
    handle: *mut c_void,
    schedule_work: unsafe extern "C" fn(*mut c_void, u32, *const c_void) -> u32,
}

#[repr(C)]
struct WorkerInterface {
    work: unsafe extern "C" fn(*mut c_void, RespondFn, *mut c_void, u32, *const c_void) -> u32,
    work_response: unsafe extern "C" fn(*mut c_void, u32, *const c_void) -> u32,
    end_run: Option<unsafe extern "C" fn(*mut c_void) -> u32>,
}

#[repr(C)]
struct SequenceHeader {
    size: u32,
    type_: u32,
    unit: u32,
    pad: u32,
}

#[repr(C)]
struct EventHeader {
    frames: i64,
    size: u32,
    type_: u32,
}

// --- URIDs -------------------------------------------------------------------

/// Every URI any plugin or the host has asked a number for. Numbers start at 1.
static URIDS: Mutex<Vec<CString>> = Mutex::new(Vec::new());

fn urid(uri: &CStr) -> u32 {
    let mut uris = URIDS.lock().unwrap();
    match uris.iter().position(|known| known.as_c_str() == uri) {
        Some(index) => index as u32 + 1,
        None => {
            uris.push(uri.to_owned());
            uris.len() as u32
        }
    }
}

unsafe extern "C" fn urid_map(_: *mut c_void, uri: *const c_char) -> u32 {
    urid(unsafe { CStr::from_ptr(uri) })
}

unsafe extern "C" fn urid_unmap(_: *mut c_void, id: u32) -> *const c_char {
    let uris = URIDS.lock().unwrap();
    // The string's buffer stays where it is for the life of the program.
    uris.get(id.wrapping_sub(1) as usize)
        .map_or(ptr::null(), |uri| uri.as_ptr())
}

struct Urids {
    sequence: u32,
    chunk: u32,
    midi_event: u32,
    float: u32,
    int: u32,
    max_block: u32,
    min_block: u32,
    sample_rate: u32,
    event_transfer: u32,
    scale_factor: u32,
    window_title: u32,
    string: u32,
    object: u32,
    long: u32,
    time_position: u32,
    time_frame: u32,
    time_speed: u32,
    time_bar: u32,
    time_bar_beat: u32,
    time_beat_unit: u32,
    time_beats_per_bar: u32,
    time_beats_per_minute: u32,
    patch: PatchUrids,
}

fn urids() -> &'static Urids {
    static KNOWN: OnceLock<Urids> = OnceLock::new();
    KNOWN.get_or_init(|| Urids {
        sequence: urid(c"http://lv2plug.in/ns/ext/atom#Sequence"),
        chunk: urid(c"http://lv2plug.in/ns/ext/atom#Chunk"),
        midi_event: urid(c"http://lv2plug.in/ns/ext/midi#MidiEvent"),
        float: urid(c"http://lv2plug.in/ns/ext/atom#Float"),
        int: urid(c"http://lv2plug.in/ns/ext/atom#Int"),
        max_block: urid(c"http://lv2plug.in/ns/ext/buf-size#maxBlockLength"),
        min_block: urid(c"http://lv2plug.in/ns/ext/buf-size#minBlockLength"),
        sample_rate: urid(c"http://lv2plug.in/ns/ext/parameters#sampleRate"),
        event_transfer: urid(c"http://lv2plug.in/ns/ext/atom#eventTransfer"),
        scale_factor: urid(c"http://lv2plug.in/ns/extensions/ui#scaleFactor"),
        window_title: urid(c"http://lv2plug.in/ns/extensions/ui#windowTitle"),
        string: urid(c"http://lv2plug.in/ns/ext/atom#String"),
        object: urid(c"http://lv2plug.in/ns/ext/atom#Object"),
        long: urid(c"http://lv2plug.in/ns/ext/atom#Long"),
        time_position: urid(c"http://lv2plug.in/ns/ext/time#Position"),
        time_frame: urid(c"http://lv2plug.in/ns/ext/time#frame"),
        time_speed: urid(c"http://lv2plug.in/ns/ext/time#speed"),
        time_bar: urid(c"http://lv2plug.in/ns/ext/time#bar"),
        time_bar_beat: urid(c"http://lv2plug.in/ns/ext/time#barBeat"),
        time_beat_unit: urid(c"http://lv2plug.in/ns/ext/time#beatUnit"),
        time_beats_per_bar: urid(c"http://lv2plug.in/ns/ext/time#beatsPerBar"),
        time_beats_per_minute: urid(c"http://lv2plug.in/ns/ext/time#beatsPerMinute"),
        patch: PatchUrids {
            object: urid(c"http://lv2plug.in/ns/ext/atom#Object"),
            urid: urid(c"http://lv2plug.in/ns/ext/atom#URID"),
            path: urid(c"http://lv2plug.in/ns/ext/atom#Path"),
            string: urid(c"http://lv2plug.in/ns/ext/atom#String"),
            float: urid(c"http://lv2plug.in/ns/ext/atom#Float"),
            double: urid(c"http://lv2plug.in/ns/ext/atom#Double"),
            int: urid(c"http://lv2plug.in/ns/ext/atom#Int"),
            long: urid(c"http://lv2plug.in/ns/ext/atom#Long"),
            bool_: urid(c"http://lv2plug.in/ns/ext/atom#Bool"),
            set: urid(c"http://lv2plug.in/ns/ext/patch#Set"),
            get: urid(c"http://lv2plug.in/ns/ext/patch#Get"),
            property: urid(c"http://lv2plug.in/ns/ext/patch#property"),
            value: urid(c"http://lv2plug.in/ns/ext/patch#value"),
        },
    })
}

// --- the world ---------------------------------------------------------------

/// lilv's view of the installed plugins, and the URIs used to question it.
struct World {
    world: *mut LilvWorld,
    input: *mut LilvNode,
    audio: *mut LilvNode,
    control: *mut LilvNode,
    atom: *mut LilvNode,
    cv: *mut LilvNode,
    midi_event: *mut LilvNode,
    time_position: *mut LilvNode,
    free_wheeling: *mut LilvNode,
    toggled: *mut LilvNode,
    instrument: *mut LilvNode,
    x11_ui: *mut LilvNode,
    /// A port, or a group of ports, that takes a side-chain.
    side_chain: *mut LilvNode,
    group: *mut LilvNode,
    side_chain_of: *mut LilvNode,
    integer: *mut LilvNode,
    enumeration: *mut LilvNode,
    not_automatic: *mut LilvNode,
    unit: *mut LilvNode,
    unit_symbol: *mut LilvNode,
    label: *mut LilvNode,
    name: *mut LilvNode,
    minor_version: *mut LilvNode,
    micro_version: *mut LilvNode,
    // Properties set with patch messages (see `lv2_patch`).
    patch_writable: *mut LilvNode,
    patch_readable: *mut LilvNode,
    patch_message: *mut LilvNode,
    range: *mut LilvNode,
    file_types: *mut LilvNode,
}

// Created and used on the main thread only.
unsafe impl Send for World {}
unsafe impl Sync for World {}

fn world() -> &'static World {
    static WORLD: OnceLock<World> = OnceLock::new();
    WORLD.get_or_init(|| unsafe {
        let world = lilv_world_new();
        let dirs: Vec<String> = search_dirs("LV2_PATH", "lv2")
            .iter()
            .map(|d| d.to_string_lossy().into_owned())
            .collect();
        if let Ok(path) = CString::new(dirs.join(":")) {
            let value = lilv_new_string(world, path.as_ptr());
            lilv_world_set_option(
                world,
                c"http://drobilla.net/ns/lilv#lv2-path".as_ptr(),
                value,
            );
            lilv_node_free(value);
        }
        lilv_world_load_all(world);
        let uri = |text: String| {
            let text = CString::new(text).unwrap();
            lilv_new_uri(world, text.as_ptr())
        };
        World {
            world,
            input: uri(format!("{LV2_CORE}InputPort")),
            audio: uri(format!("{LV2_CORE}AudioPort")),
            control: uri(format!("{LV2_CORE}ControlPort")),
            cv: uri(format!("{LV2_CORE}CVPort")),
            toggled: uri(format!("{LV2_CORE}toggled")),
            instrument: uri(format!("{LV2_CORE}InstrumentPlugin")),
            atom: uri(format!("{ATOM}AtomPort")),
            midi_event: uri("http://lv2plug.in/ns/ext/midi#MidiEvent".into()),
            time_position: uri("http://lv2plug.in/ns/ext/time#Position".into()),
            free_wheeling: uri(format!("{LV2_CORE}freeWheeling")),
            x11_ui: uri("http://lv2plug.in/ns/extensions/ui#X11UI".into()),
            side_chain: uri(format!("{LV2_CORE}isSideChain")),
            group: uri("http://lv2plug.in/ns/ext/port-groups#group".into()),
            side_chain_of: uri("http://lv2plug.in/ns/ext/port-groups#sideChainOf".into()),
            integer: uri(format!("{LV2_CORE}integer")),
            enumeration: uri(format!("{LV2_CORE}enumeration")),
            not_automatic: uri("http://lv2plug.in/ns/ext/port-props#notAutomatic".into()),
            unit: uri("http://lv2plug.in/ns/extensions/units#unit".into()),
            unit_symbol: uri("http://lv2plug.in/ns/extensions/units#symbol".into()),
            label: uri("http://www.w3.org/2000/01/rdf-schema#label".into()),
            name: uri(format!("{LV2_CORE}name")),
            minor_version: uri(format!("{LV2_CORE}minorVersion")),
            micro_version: uri(format!("{LV2_CORE}microVersion")),
            patch_writable: uri("http://lv2plug.in/ns/ext/patch#writable".into()),
            patch_readable: uri("http://lv2plug.in/ns/ext/patch#readable".into()),
            patch_message: uri("http://lv2plug.in/ns/ext/patch#Message".into()),
            range: uri("http://www.w3.org/2000/01/rdf-schema#range".into()),
            file_types: uri("http://moddevices.com/ns/mod#fileTypes".into()),
        }
    })
}

/// Where the song is and how fast it goes, as a `time:Position` object for
/// a plugin's atom port. LV2 counts in beats of the signature's own unit,
/// where the engine counts in quarter notes.
fn time_position(ctx: &ProcessCtx) -> [u8; 184] {
    let u = urids();
    let per_quarter = ctx.sig_den as f64 / 4.0;
    let bar = ctx.bar;
    let frame = ctx.seconds * ctx.sample_rate as f64;
    let mut out = [0u8; 184];
    let mut at = 0;
    let mut put = |bytes: &[u8]| {
        out[at..at + bytes.len()].copy_from_slice(bytes);
        // Every value is padded out to eight bytes.
        at += bytes.len().div_ceil(4) * 4;
    };
    // The object: its size after this header, its type, then id and class.
    for word in [176, u.object, 0, u.time_position] {
        put(&word.to_ne_bytes());
    }
    let mut property = |key: u32, type_: u32, value: &[u8]| {
        for word in [key, 0, value.len() as u32, type_] {
            put(&word.to_ne_bytes());
        }
        let mut body = [0u8; 8];
        body[..value.len()].copy_from_slice(value);
        put(&body);
    };
    property(u.time_frame, u.long, &(frame.round() as i64).to_ne_bytes());
    let speed: f32 = if ctx.playing { 1.0 } else { 0.0 };
    property(u.time_speed, u.float, &speed.to_ne_bytes());
    property(u.time_bar, u.long, &bar.to_ne_bytes());
    let bar_beat = ((ctx.position - ctx.bar_start) * per_quarter) as f32;
    property(u.time_bar_beat, u.float, &bar_beat.to_ne_bytes());
    property(u.time_beat_unit, u.int, &(ctx.sig_den as i32).to_ne_bytes());
    property(
        u.time_beats_per_bar,
        u.float,
        &(ctx.sig_num as f32).to_ne_bytes(),
    );
    let tempo = (ctx.tempo * per_quarter) as f32;
    property(u.time_beats_per_minute, u.float, &tempo.to_ne_bytes());
    out
}

unsafe fn node_text(node: *const LilvNode) -> String {
    unsafe {
        let text = if node.is_null() {
            ptr::null()
        } else {
            lilv_node_as_string(node)
        };
        if text.is_null() {
            String::new()
        } else {
            CStr::from_ptr(text).to_string_lossy().into_owned()
        }
    }
}

/// The text of a node the caller owns, freeing the node.
unsafe fn take_text(node: *mut LilvNode) -> String {
    unsafe {
        let text = node_text(node);
        if !node.is_null() {
            lilv_node_free(node);
        }
        text
    }
}

/// What the plugin says of a control port besides its name and range:
/// whole steps, named options, its unit, its group, and whether the host
/// may automate it.
unsafe fn describe_port(
    plugin: *const LilvPlugin,
    port: *const LilvPort,
    w: &World,
    info: &mut ParamInfo,
) {
    unsafe {
        let span = (info.max - info.min).round();
        if !info.boolean
            && lilv_port_has_property(plugin, port, w.integer)
            && span >= 1.0
            && span < 1e6
        {
            info.steps = span as u32;
        }
        if !info.boolean && lilv_port_has_property(plugin, port, w.enumeration) {
            info.enumeration = true;
            // Named options that are the port's whole steps, in order.
            let points = lilv_port_get_scale_points(plugin, port);
            let mut named: Vec<(f32, String)> = Vec::new();
            let mut it = lilv_scale_points_begin(points);
            while !points.is_null() && !lilv_scale_points_is_end(points, it) {
                let point = lilv_scale_points_get(points, it);
                named.push((
                    lilv_node_as_float(lilv_scale_point_get_value(point)),
                    node_text(lilv_scale_point_get_label(point)),
                ));
                it = lilv_scale_points_next(points, it);
            }
            if !points.is_null() {
                lilv_scale_points_free(points);
            }
            named.sort_by(|a, b| a.0.total_cmp(&b.0));
            let whole = named
                .iter()
                .enumerate()
                .all(|(i, (value, _))| *value == info.min + i as f32);
            if whole && named.len() >= 2 && named.len() as f32 == span + 1.0 {
                info.steps = span as u32;
                info.choices = named.into_iter().map(|(_, label)| label).collect();
            }
        }
        if lilv_port_has_property(plugin, port, w.not_automatic) {
            info.automatable = false;
        }
        let unit = lilv_port_get(plugin, port, w.unit);
        if !unit.is_null() {
            let symbol = take_text(lilv_world_get(w.world, unit, w.unit_symbol, ptr::null()));
            info.unit = if symbol.is_empty() {
                unit_symbol(&node_text(unit)).to_string()
            } else {
                symbol
            };
            lilv_node_free(unit);
        }
        let group = lilv_port_get(plugin, port, w.group);
        if !group.is_null() {
            let mut name = take_text(lilv_world_get(w.world, group, w.label, ptr::null()));
            if name.is_empty() {
                name = take_text(lilv_world_get(w.world, group, w.name, ptr::null()));
            }
            info.group = name;
            lilv_node_free(group);
        }
    }
}

/// The symbol of one of LV2's own units, from its URI.
fn unit_symbol(uri: &str) -> &str {
    match uri.rsplit('#').next().unwrap_or_default() {
        "hz" => "Hz",
        "khz" => "kHz",
        "mhz" => "MHz",
        "db" => "dB",
        "ms" => "ms",
        "s" => "s",
        "min" => "min",
        "pc" => "%",
        "bpm" => "BPM",
        "beat" => "beats",
        "bar" => "bars",
        "cent" => "ct",
        "semitone12TET" => "st",
        "oct" => "oct",
        "degree" => "deg",
        "frame" => "frames",
        "midiNote" => "note",
        "m" => "m",
        "cm" => "cm",
        "mm" => "mm",
        _ => "",
    }
}

/// The first feature the plugin cannot do without that this host lacks.
unsafe fn missing_feature(plugin: *const LilvPlugin) -> Option<String> {
    let supported = [
        URID_MAP,
        URID_UNMAP,
        OPTIONS,
        BOUNDED_BLOCK,
        WORKER_SCHEDULE,
        LOAD_DEFAULT_STATE,
    ];
    unsafe {
        let required = lilv_plugin_get_required_features(plugin);
        let mut missing = None;
        let mut it = lilv_nodes_begin(required);
        while !lilv_nodes_is_end(required, it) {
            let uri = CStr::from_ptr(lilv_node_as_uri(lilv_nodes_get(required, it)));
            if !supported.contains(&uri) {
                missing = Some(uri.to_string_lossy().into_owned());
            }
            it = lilv_nodes_next(required, it);
        }
        lilv_nodes_free(required);
        missing
    }
}

/// What the installed LV2 bundles look like: each bundle with the latest
/// modification time of the bundle and the files directly in it. Adding,
/// removing or changing a bundle changes this.
fn bundle_stamps() -> Vec<(PathBuf, u64)> {
    let dirs = search_dirs("LV2_PATH", "lv2");
    crate::find_bundles(&dirs, "lv2")
        .into_iter()
        .map(|bundle| {
            let files = std::fs::read_dir(&bundle)
                .into_iter()
                .flatten()
                .flatten()
                .map(|e| crate::mtime(&e.path()));
            let latest = files.fold(crate::mtime(&bundle), u64::max);
            (bundle, latest)
        })
        .collect()
}

pub(crate) fn scan(registry: &mut Registry, cache: &mut crate::Cache, notes: &mut Vec<String>) {
    let bundles = bundle_stamps();
    let known = cache.lv2.as_ref().filter(|c| c.bundles == bundles).cloned();
    let found = match known {
        // Unchanged since last time: register from the cache and leave lilv
        // to read the bundles when an LV2 plugin is first used.
        Some(found) => found,
        None => {
            let found = scan_world(bundles);
            cache.lv2 = Some(found.clone());
            cache.mark_changed();
            found
        }
    };
    for plugin in found.plugins {
        let info = DeviceInfo {
            kind: format!("lv2:{}", plugin.id),
            name: plugin.name,
            category: if plugin.instrument { Category::Instrument } else { Category::Effect },
            format: DeviceFormat::Lv2,
            vendor: plugin.vendor,
            id: plugin.id.clone(),
            version: plugin.version,
            params: Vec::new(),
            features: plugin.features,
        };
        registry.register(std::rc::Rc::new(Lv2Factory {
            info,
            uri: plugin.id,
            plugin: OnceLock::new(),
        }));
    }
    if found.skipped > 0 {
        notes.push(format!(
            "{} LV2 plugins need host features that are not supported",
            found.skipped
        ));
    }
}

/// Load every bundle with lilv and list the plugins this host can run.
fn scan_world(bundles: Vec<(PathBuf, u64)>) -> crate::Lv2Cache {
    let w = world();
    let mut found = crate::Lv2Cache {
        bundles,
        plugins: Vec::new(),
        skipped: 0,
    };
    unsafe {
        let plugins = lilv_world_get_all_plugins(w.world);
        let mut it = lilv_plugins_begin(plugins);
        while !lilv_plugins_is_end(plugins, it) {
            let plugin = lilv_plugins_get(plugins, it);
            it = lilv_plugins_next(plugins, it);
            if missing_feature(plugin).is_some() {
                found.skipped += 1;
                continue;
            }
            let uri = node_text(lilv_plugin_get_uri(plugin));
            let class = lilv_plugin_class_get_uri(lilv_plugin_get_class(plugin));
            // Not every instrument declares the class, so also go by its ports:
            // audio out and no audio in.
            let (mut audio_in, mut audio_out) = (0, 0);
            for index in 0..lilv_plugin_get_num_ports(plugin) {
                let port = lilv_plugin_get_port_by_index(plugin, index);
                if lilv_port_is_a(plugin, port, w.audio) {
                    if lilv_port_is_a(plugin, port, w.input) {
                        audio_in += 1
                    } else {
                        audio_out += 1
                    }
                }
            }
            let instrument =
                node_text(class) == node_text(w.instrument) || (audio_in == 0 && audio_out > 0);
            let subject = lilv_plugin_get_uri(plugin);
            let minor = take_text(lilv_world_get(w.world, subject, w.minor_version, ptr::null()));
            let micro = take_text(lilv_world_get(w.world, subject, w.micro_version, ptr::null()));
            found.plugins.push(crate::Found {
                id: uri,
                name: take_text(lilv_plugin_get_name(plugin)),
                vendor: take_text(lilv_plugin_get_author_name(plugin)),
                instrument,
                version: if minor.is_empty() { String::new() } else { format!("{minor}.{}", if micro.is_empty() { "0" } else { &micro }) },
                features: Vec::new(),
            });
        }
    }
    found
}

struct Lv2Factory {
    info: DeviceInfo,
    uri: String,
    /// Looked up in the lilv world on first use.
    plugin: OnceLock<usize>,
}

impl Lv2Factory {
    fn plugin(&self) -> Result<*const LilvPlugin> {
        if let Some(&p) = self.plugin.get() {
            return Ok(p as *const LilvPlugin);
        }
        let w = world();
        let uri = CString::new(self.uri.clone())?;
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

// --- the worker --------------------------------------------------------------

/// Runs a plugin's non-real-time work on its own thread. Requests travel from
/// the audio thread and responses back to it through lock-free byte queues,
/// each message framed by its length.
///
/// In a render the device waits after each `run` until the work it asked
/// for is done: its response then reaches the plugin after the very `run`
/// that asked for it, so a file loaded on a state lane's point plays from
/// that point, the same in every render. (LV2 also lets a host that does
/// not play in real time do the work inside `schedule_work`; Neural Amp
/// Modeler then played some renders differently.)
struct Worker {
    /// Written by `schedule_work`, which the plugin calls from its `run`.
    requests: UnsafeCell<rtrb::Producer<u8>>,
    /// Read by the device after each `run`.
    responses: UnsafeCell<rtrb::Consumer<u8>>,
    /// Rendering: the device waits after each block for the work it asked.
    offline: AtomicBool,
    /// Pieces of work asked for and not done yet.
    pending: Arc<AtomicU32>,
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

unsafe extern "C" fn respond(queue: *mut c_void, size: u32, data: *const c_void) -> u32 {
    unsafe {
        let queue = &mut *(queue as *mut rtrb::Producer<u8>);
        let data = std::slice::from_raw_parts(data as *const u8, size as usize);
        if write_message(queue, data) { 0 } else { 2 }
    }
}

struct SendPtr<T>(*mut T);
unsafe impl<T> Send for SendPtr<T> {}

fn write_message(queue: &mut rtrb::Producer<u8>, data: &[u8]) -> bool {
    if queue.slots() < data.len() + 4 {
        return false;
    }
    for byte in (data.len() as u32).to_le_bytes().iter().chain(data) {
        let _ = queue.push(*byte);
    }
    true
}

fn read_message(queue: &mut rtrb::Consumer<u8>, into: &mut Vec<u8>) -> bool {
    if queue.slots() < 4 {
        return false;
    }
    let mut size = [0u8; 4];
    for byte in &mut size {
        *byte = queue.pop().unwrap_or(0);
    }
    into.clear();
    for _ in 0..u32::from_le_bytes(size) {
        // The writer queues a whole message at once, so the bytes are there.
        if into.len() < into.capacity() {
            into.push(queue.pop().unwrap_or(0));
        } else {
            let _ = queue.pop();
        }
    }
    true
}

impl Worker {
    fn start(interface: *const WorkerInterface, handle: *mut c_void) -> Self {
        let (requests, mut incoming) = rtrb::RingBuffer::new(WORK_CAPACITY);
        let (outgoing, responses) = rtrb::RingBuffer::new(WORK_CAPACITY);
        let outgoing = Arc::new(std::sync::Mutex::new(outgoing));
        let stop = Arc::new(AtomicBool::new(false));
        let (raw_interface, raw_handle) = (interface as *mut WorkerInterface, handle);
        let pending = Arc::new(AtomicU32::new(0));
        let done = pending.clone();
        let (stopped, to_ui, interface, handle) = (
            stop.clone(),
            outgoing.clone(),
            SendPtr(raw_interface),
            SendPtr(raw_handle),
        );
        let thread = std::thread::spawn(move || {
            let (interface, handle) = (interface, handle);
            let mut message = Vec::with_capacity(WORK_CAPACITY);
            while !stopped.load(Relaxed) {
                while read_message(&mut incoming, &mut message) {
                    let mut outgoing = to_ui.lock().unwrap_or_else(|e| e.into_inner());
                    unsafe {
                        ((*interface.0).work)(
                            handle.0,
                            respond,
                            &mut *outgoing as *mut _ as *mut c_void,
                            message.len() as u32,
                            message.as_ptr().cast(),
                        );
                    }
                    done.fetch_sub(1, std::sync::atomic::Ordering::Release);
                }
                std::thread::sleep(Duration::from_millis(2));
            }
        });
        Self {
            requests: UnsafeCell::new(requests),
            responses: UnsafeCell::new(responses),
            offline: AtomicBool::new(false),
            pending,
            stop,
            thread: Some(thread),
        }
    }

    /// In a render, wait (at most ten seconds) until the worker has done
    /// what was asked of it, so that its responses reach the plugin after
    /// the very block that asked.
    fn finish(&self) {
        if !self.offline.load(Relaxed) {
            return;
        }
        let deadline = std::time::Instant::now() + Duration::from_secs(10);
        while self.pending.load(std::sync::atomic::Ordering::Acquire) > 0
            && std::time::Instant::now() < deadline
        {
            std::thread::sleep(Duration::from_micros(200));
        }
    }
}

impl Drop for Worker {
    fn drop(&mut self) {
        self.stop.store(true, Relaxed);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

unsafe extern "C" fn schedule_work(handle: *mut c_void, size: u32, data: *const c_void) -> u32 {
    unsafe {
        // The handle is the slot the worker is put in once the plugin exists.
        let Some(worker) = (*(handle as *const OnceLock<Worker>)).get() else {
            return 1;
        };
        let data = std::slice::from_raw_parts(data as *const u8, size as usize);
        // Counted before the worker can see it, so the count never goes below 0.
        worker.pending.fetch_add(1, Relaxed);
        if write_message(&mut *worker.requests.get(), data) {
            0
        } else {
            worker.pending.fetch_sub(1, Relaxed);
            2
        }
    }
}

// --- an instance -------------------------------------------------------------

/// What the plugin was handed at instantiation and keeps pointers to.
struct HostData {
    map: UridMap,
    unmap: UridUnmap,
    schedule: WorkerSchedule,
    options: [OptionsOption; 4],
    features: Vec<Feature>,
    feature_list: Vec<*const Feature>,
    max_block: i32,
    min_block: i32,
    sample_rate: f32,
    worker: OnceLock<Worker>,
}

struct Shared {
    plugin: *const LilvPlugin,
    instance: *mut LilvInstance,
    host: Box<HostData>,
    /// One value per control port, read and written as `f32`. The plugin is
    /// connected straight to these.
    controls: Box<[AtomicU32]>,
    /// For each parameter, the index of its value in `controls`.
    param_slots: Vec<usize>,
    params: Vec<ParamInfo>,
    /// Port symbol to index in `controls`, for saving and restoring state.
    symbols: HashMap<CString, usize>,
    worker_interface: *const WorkerInterface,
    scratch: UnsafeCell<f32>,
    /// Every control port as (port index, index in `controls`), for the editor.
    control_ports: Vec<(u32, usize)>,
    /// The control that tells the plugin it is rendering faster than real
    /// time, if it has one.
    free_wheeling: Option<usize>,
    /// The port index of each atom buffer, in the device's order.
    atom_ports: Vec<u32>,
    /// Port symbol to port index.
    port_symbols: HashMap<CString, u32>,
    /// The plugin's X11 editor, if it has one.
    ui: Option<UiInfo>,
    /// Whether an editor is open and wants to hear from the plugin.
    ui_open: AtomicBool,
    /// The properties the plugin lists (`patch:writable`, `patch:readable`).
    properties: Vec<Property>,
    /// The port index of the atom input that takes patch messages, when
    /// the plugin has properties.
    patch_port: Option<u32>,
    /// The index in `controls` of the port where the plugin says how many
    /// frames its output is behind its input, if it has one.
    latency: Option<usize>,
    /// A control changed since the plugin last ran: it must run again,
    /// asleep or not (see [`Device::resting`]).
    wake: AtomicBool,
}

/// Where a plugin's editor lives on disk, and how it is shown.
struct UiInfo {
    uri: CString,
    binary: PathBuf,
    bundle: CString,
    kind: UiKind,
}

/// The ways an LV2 editor can get on screen, best first.
#[derive(Clone, Copy, Debug, PartialEq, PartialOrd)]
enum UiKind {
    /// An X11 window embedded in one of ours.
    X11,
    /// Any toolkit (Gtk, Qt, …) whose editor opens a window of its own.
    Shows,
    /// The older convention for the same thing.
    External,
    /// A Gtk widget with no window: this host puts it in one.
    Gtk,
}

// The plugin's `run` and worker functions are called as LV2 allows; the rest
// is used from the main thread only, which is also where this is dropped.
unsafe impl Send for Shared {}
unsafe impl Sync for Shared {}

impl Shared {
    fn control(&self, slot: usize) -> f32 {
        f32::from_bits(self.controls[slot].load(Relaxed))
    }

    fn set_control(&self, slot: usize, value: f32) {
        self.controls[slot].store(value.to_bits(), Relaxed);
        self.wake.store(true, Relaxed);
    }

    /// Whether the worker has work not done, or answers the plugin has
    /// not been given yet.
    fn working(&self) -> bool {
        self.host.worker.get().is_some_and(|worker| {
            worker.pending.load(std::sync::atomic::Ordering::Acquire) > 0
                || unsafe { (*worker.responses.get()).slots() } > 0
        })
    }
}

impl Drop for Shared {
    fn drop(&mut self) {
        // Stop the worker before the plugin it calls into goes away.
        drop(self.host.worker.take());
        unsafe { lilv_instance_free(self.instance) };
    }
}

fn host_data(sample_rate: f32, max_block: usize) -> Box<HostData> {
    let u = urids();
    let mut host = Box::new(HostData {
        map: UridMap {
            handle: ptr::null_mut(),
            map: urid_map,
        },
        unmap: UridUnmap {
            handle: ptr::null_mut(),
            unmap: urid_unmap,
        },
        schedule: WorkerSchedule {
            handle: ptr::null_mut(),
            schedule_work,
        },
        options: std::array::from_fn(|_| OptionsOption {
            context: 0,
            subject: 0,
            key: 0,
            size: 0,
            type_: 0,
            value: ptr::null(),
        }),
        features: Vec::new(),
        feature_list: Vec::new(),
        max_block: max_block as i32,
        min_block: 1,
        sample_rate,
        worker: OnceLock::new(),
    });
    // Everything below points into the box, which never moves.
    let option = |key, size, type_, value: *const c_void| OptionsOption {
        context: 0,
        subject: 0,
        key,
        size,
        type_,
        value,
    };
    host.options[0] = option(
        u.max_block,
        4,
        u.int,
        &host.max_block as *const i32 as *const c_void,
    );
    host.options[1] = option(
        u.min_block,
        4,
        u.int,
        &host.min_block as *const i32 as *const c_void,
    );
    host.options[2] = option(
        u.sample_rate,
        4,
        u.float,
        &host.sample_rate as *const f32 as *const c_void,
    );
    host.schedule.handle = &host.worker as *const OnceLock<Worker> as *mut c_void;
    let feature = |uri: &'static CStr, data: *mut c_void| Feature {
        uri: uri.as_ptr(),
        data,
    };
    host.features = vec![
        feature(URID_MAP, &mut host.map as *mut UridMap as *mut c_void),
        feature(URID_UNMAP, &mut host.unmap as *mut UridUnmap as *mut c_void),
        feature(OPTIONS, host.options.as_mut_ptr() as *mut c_void),
        feature(BOUNDED_BLOCK, ptr::null_mut()),
        feature(
            WORKER_SCHEDULE,
            &mut host.schedule as *mut WorkerSchedule as *mut c_void,
        ),
        feature(LOAD_DEFAULT_STATE, ptr::null_mut()),
    ];
    host.feature_list = host.features.iter().map(|f| f as *const Feature).collect();
    host.feature_list.push(ptr::null());
    host
}

/// An atom port's buffer: 64-bit aligned, as atoms must be.
struct AtomBuffer {
    data: Vec<u64>,
    input: bool,
}

impl AtomBuffer {
    fn new(input: bool) -> Self {
        Self {
            data: vec![0; ATOM_CAPACITY / 8],
            input,
        }
    }

    fn header(&mut self) -> &mut SequenceHeader {
        unsafe { &mut *(self.data.as_mut_ptr() as *mut SequenceHeader) }
    }

    /// Get the buffer ready for a block: an empty sequence to read from, or
    /// free space for the plugin to write into.
    fn reset(&mut self) {
        let u = urids();
        let input = self.input;
        let header = self.header();
        header.unit = 0;
        header.pad = 0;
        if input {
            header.size = 8;
            header.type_ = u.sequence;
        } else {
            header.size = (ATOM_CAPACITY - 8) as u32;
            header.type_ = u.chunk;
        }
    }

    fn push_midi(&mut self, frame: u32, bytes: [u8; 3], len: u32) {
        let used = 8 + self.header().size as usize;
        if used + 24 > ATOM_CAPACITY {
            return;
        }
        unsafe {
            let at = (self.data.as_mut_ptr() as *mut u8).add(used);
            (at as *mut EventHeader).write(EventHeader {
                frames: frame as i64,
                size: len,
                type_: urids().midi_event,
            });
            // Two or three bytes of MIDI, padded out to eight.
            let mut body = [0u8; 8];
            body[..3].copy_from_slice(&bytes);
            ptr::copy_nonoverlapping(body.as_ptr(), at.add(16), 8);
        }
        self.header().size += 24;
    }

    /// Append an event holding `atom`, a complete atom: header and body.
    fn push_atom(&mut self, frame: u32, atom: &[u8]) {
        let used = 8 + self.header().size as usize;
        let padded = atom.len().div_ceil(8) * 8;
        if atom.len() < 8 || used + 8 + padded > ATOM_CAPACITY {
            return;
        }
        unsafe {
            let at = (self.data.as_mut_ptr() as *mut u8).add(used);
            (at as *mut i64).write(frame as i64);
            ptr::write_bytes(at.add(8), 0, padded);
            ptr::copy_nonoverlapping(atom.as_ptr(), at.add(8), atom.len());
        }
        self.header().size += (8 + padded) as u32;
    }

    /// Call `f` with each event's atom (header and body) in a sequence the
    /// plugin wrote.
    fn each_event(&self, mut f: impl FnMut(&[u8])) {
        let bytes =
            unsafe { std::slice::from_raw_parts(self.data.as_ptr() as *const u8, ATOM_CAPACITY) };
        let header = unsafe { &*(self.data.as_ptr() as *const SequenceHeader) };
        if header.type_ != urids().sequence {
            return;
        }
        let end = (8 + header.size as usize).min(ATOM_CAPACITY);
        let mut at = 16;
        while at + 16 <= end {
            let size = u32::from_le_bytes(bytes[at + 8..at + 12].try_into().unwrap()) as usize;
            if at + 16 + size > end {
                break;
            }
            f(&bytes[at + 8..at + 16 + size]);
            at += 16 + size.div_ceil(8) * 8;
        }
    }
}

impl DeviceFactory for Lv2Factory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, max_block: usize) -> Result<Instance> {
        let plugin = self.plugin()?;
        let w = world();
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

            let count = lilv_plugin_get_num_ports(plugin) as usize;
            let (mut mins, mut maxs, mut defaults) =
                (vec![0f32; count], vec![0f32; count], vec![0f32; count]);
            lilv_plugin_get_port_ranges_float(
                plugin,
                mins.as_mut_ptr(),
                maxs.as_mut_ptr(),
                defaults.as_mut_ptr(),
            );

            let mut controls = Vec::new();
            let (mut param_slots, mut params, mut symbols) =
                (Vec::new(), Vec::new(), HashMap::new());
            let mut audio_in = Vec::new();
            let mut audio_out = Vec::new();
            let mut key_in = Vec::new();
            let mut out_names = Vec::new();
            let mut atoms = Vec::new();
            let mut midi_in = None;
            let mut time_in = None;
            // (port index, what it connects to)
            let mut plan: Vec<(u32, Connect)> = Vec::new();

            for index in 0..count {
                let port = lilv_plugin_get_port_by_index(plugin, index as u32);
                let is = |class| lilv_port_is_a(plugin, port, class);
                let input = is(w.input);
                if is(w.control) {
                    let slot = controls.len();
                    let or = |v: f32, fallback: f32| if v.is_nan() { fallback } else { v };
                    let (min, max) = (or(mins[index], 0.0), or(maxs[index], 1.0));
                    let default = or(defaults[index], min).clamp(min.min(max), max.max(min));
                    controls.push(AtomicU32::new(default.to_bits()));
                    let symbol =
                        CStr::from_ptr(lilv_node_as_string(lilv_port_get_symbol(plugin, port)))
                            .to_owned();
                    if input {
                        let mut info = ParamInfo::new(
                            &take_text(lilv_port_get_name(plugin, port)),
                            min,
                            max,
                            default,
                            "",
                        );
                        info.key = symbol.to_string_lossy().into_owned();
                        info.id = info.key.clone();
                        if lilv_port_has_property(plugin, port, w.toggled) {
                            info.choices = vec!["off".into(), "on".into()];
                            info.boolean = true;
                            info.steps = 1;
                        }
                        describe_port(plugin, port, w, &mut info);
                        params.push(info);
                        param_slots.push(slot);
                        symbols.insert(symbol, slot);
                    }
                    plan.push((index as u32, Connect::Control(slot)));
                } else if is(w.cv) {
                    // Control voltage is not routed anywhere yet.
                    plan.push((index as u32, Connect::Spare));
                } else if is(w.audio) && input && takes_key(plugin, port, w) {
                    key_in.push(vec![0f32; max_block]);
                    plan.push((index as u32, Connect::Key(key_in.len() - 1)));
                } else if is(w.audio) {
                    let buffers = if input { &mut audio_in } else { &mut audio_out };
                    if !input {
                        out_names.push(take_text(lilv_port_get_name(plugin, port)));
                    }
                    buffers.push(vec![0f32; max_block]);
                    plan.push((index as u32, Connect::Audio(input, buffers.len() - 1)));
                } else if is(w.atom) {
                    if input
                        && midi_in.is_none()
                        && lilv_port_supports_event(plugin, port, w.midi_event)
                    {
                        midi_in = Some(atoms.len());
                    }
                    if input
                        && time_in.is_none()
                        && lilv_port_supports_event(plugin, port, w.time_position)
                    {
                        time_in = Some(atoms.len());
                    }
                    atoms.push(AtomBuffer::new(input));
                    plan.push((index as u32, Connect::Atom(atoms.len() - 1)));
                } else {
                    lilv_instance_free(instance);
                    bail!("port {index} is of a kind this host does not know");
                }
            }

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
            let mut port_symbols = HashMap::new();
            for index in 0..count as u32 {
                let port = lilv_plugin_get_port_by_index(plugin, index);
                let symbol =
                    CStr::from_ptr(lilv_node_as_string(lilv_port_get_symbol(plugin, port)));
                port_symbols.insert(symbol.to_owned(), index);
            }
            let mut atom_ports = vec![0; atoms.len()];
            let mut control_ports = Vec::new();
            for (port, connect) in &plan {
                match *connect {
                    Connect::Control(slot) => control_ports.push((*port, slot)),
                    Connect::Atom(index) => atom_ports[index] = *port,
                    _ => {}
                }
            }
            // The port a plugin reads to know it is rendering offline.
            let wheel = lilv_plugin_get_port_by_designation(plugin, w.input, w.free_wheeling);
            let free_wheeling = (!wheel.is_null())
                .then(|| lilv_port_get_index(plugin, wheel))
                .and_then(|index| control_ports.iter().find(|(port, _)| *port == index))
                .map(|(_, slot)| *slot);
            let properties = find_properties(plugin, w);
            // Patch messages go to the atom input that says it takes them,
            // else to the first one that is not only for MIDI.
            let atom_inputs: Vec<u32> = atom_ports
                .iter()
                .zip(&atoms)
                .filter(|(_, atom)| atom.input)
                .map(|(port, _)| *port)
                .collect();
            let supports = |port: u32, what| {
                let p = lilv_plugin_get_port_by_index(plugin, port);
                lilv_port_supports_event(plugin, p, what)
            };
            let patch_port = (!properties.is_empty())
                .then(|| {
                    atom_inputs
                        .iter()
                        .find(|p| supports(**p, w.patch_message))
                        .or_else(|| atom_inputs.iter().find(|p| !supports(**p, w.midi_event)))
                        .or(atom_inputs.first())
                        .copied()
                })
                .flatten();
            let latency = lilv_plugin_has_latency(plugin)
                .then(|| lilv_plugin_get_latency_port_index(plugin))
                .and_then(|index| control_ports.iter().find(|(port, _)| *port == index))
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
                port_symbols,
                ui: find_ui(plugin),
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
            // The outputs two by two in their order, the main pair first,
            // each named after its left one.
            let out_pairs: Vec<crate::OutPair> = (0..audio_out.len())
                .step_by(2)
                .take(paw_engine::MAX_PAIRS)
                .map(|left| crate::OutPair {
                    port: 0,
                    left,
                    right: (left + 1).min(audio_out.len() - 1),
                    name: side_less(&out_names[left]),
                })
                .collect();
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

#[derive(Clone, Copy)]
enum Connect {
    Control(usize),
    /// Whether it is an input, and its index among the buffers of that kind.
    Audio(bool, usize),
    /// A side-chain input, by its index among those.
    Key(usize),
    Atom(usize),
    Spare,
}

struct Lv2Device {
    shared: Arc<Shared>,
    /// Messages from the editor for the plugin's atom inputs, and from the
    /// plugin's atom outputs for the editor. Each is a port index followed by
    /// one atom.
    from_ui: rtrb::Consumer<u8>,
    to_ui: rtrb::Producer<u8>,
    message: Vec<u8>,
    audio_in: Vec<Vec<f32>>,
    audio_out: Vec<Vec<f32>>,
    /// The side-chain inputs, and whether they hold a key.
    key_in: Vec<Vec<f32>>,
    keyed: bool,
    /// The outputs as stereo pairs, the main one first.
    out_pairs: Vec<crate::OutPair>,
    atoms: Vec<AtomBuffer>,
    /// Index in `atoms` of the port that takes MIDI.
    midi_in: Option<usize>,
    /// The port that is told where the song is and how fast it goes, and
    /// what it was last told: playing, tempo, signature, and the position
    /// the next block starts at if nothing jumps.
    time_in: Option<usize>,
    time_sent: Option<(bool, f64, u32, u32, f64)>,
    _spare: Vec<f32>,
    held: HeldNotes,
    response: Vec<u8>,
    /// Messages a state lane handed for the next block, each as its frame,
    /// the index of its atom input, its length and the atom.
    queued: Vec<u8>,
    /// Whether the plugin may sleep (see [`Device::resting`]).
    rest: Rest,
    /// How long, in frames, the plugin may ring after its input stops,
    /// besides its latency. LV2 has no way to say it.
    tail: u64,
}

/// Room for the messages of state lanes that one block takes.
const QUEUED_CAPACITY: usize = 16384;

/// The tail an LV2 plugin is given: it sleeps once its input was silent
/// for this long, plus its latency, and its output is silent too.
const TAIL_SECONDS: f64 = 5.0;

impl Lv2Device {
    /// Put the messages state lanes handed into their atom inputs: those
    /// for the first frame, or (`later`) the others.
    fn push_queued(&mut self, n: usize, later: bool) {
        let mut at = 0;
        while let Some(head) = self.queued.get(at..at + 12) {
            let word = |i: usize| u32::from_le_bytes(head[i..i + 4].try_into().unwrap()) as usize;
            let (frame, index, len) = (word(0).min(n.saturating_sub(1)), word(4), word(8));
            if let Some(atom) = self.queued.get(at + 12..at + 12 + len)
                && (frame > 0) == later
            {
                self.atoms[index].push_atom(frame as u32, atom);
            }
            at += 12 + len;
        }
    }
}

impl Device for Lv2Device {
    /// Once its tail has gone by in silence and its output was silent,
    /// unless a control, a message or the worker has something for it.
    fn resting(&self) -> bool {
        self.rest.resting()
            && self.queued.is_empty()
            && self.from_ui.slots() == 0
            && !self.shared.wake.load(Relaxed)
            && !self.shared.working()
    }

    fn message(&mut self, frame: u32, data: &[u8]) -> bool {
        let Some((port, atom)) = data.split_at_checked(4) else {
            return false;
        };
        let port = u32::from_le_bytes(port.try_into().unwrap());
        let Some(index) = self.shared.atom_ports.iter().position(|p| *p == port) else {
            return false;
        };
        if !self.atoms[index].input || self.queued.len() + 12 + atom.len() > self.queued.capacity() {
            return false;
        }
        self.queued.extend_from_slice(&frame.to_le_bytes());
        self.queued.extend_from_slice(&(index as u32).to_le_bytes());
        self.queued.extend_from_slice(&(atom.len() as u32).to_le_bytes());
        self.queued.extend_from_slice(atom);
        true
    }

    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        let n = io.left.len();
        // Woken: its tail starts again from here.
        self.rest.begin(io, self.shared.wake.swap(false, Relaxed));
        match self.audio_in.as_mut_slice() {
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
        self.keyed = crate::put_key(self.key_in.as_mut_slice(), io.sidechain, self.keyed, n);
        for atom in &mut self.atoms {
            atom.reset();
        }
        // What state lanes handed for the block's first frame.
        self.push_queued(n, false);
        if let Some(port) = self.time_in {
            // Told when something changes: starting, stopping, a jump, a new
            // tempo. In between, the plugin counts on from what it was told.
            let beats = n as f64 * ctx.tempo / (60.0 * ctx.sample_rate as f64);
            let expected = self.time_sent.map(|(.., next)| next);
            let state = (ctx.playing, ctx.tempo, ctx.sig_num, ctx.sig_den);
            let unchanged = self
                .time_sent
                .is_some_and(|(p, t, n, d, _)| (p, t, n, d) == state)
                && expected.is_some_and(|next| (next - ctx.position).abs() < 1e-6);
            if !unchanged {
                self.atoms[port].push_atom(0, &time_position(ctx));
            }
            let next = ctx.position + if ctx.playing { beats } else { 0.0 };
            self.time_sent = Some((ctx.playing, ctx.tempo, ctx.sig_num, ctx.sig_den, next));
        }
        if let Some(port) = self.midi_in {
            let atom = &mut self.atoms[port];
            self.held.expand(io.events.as_slice(), |frame, kind| {
                ump::midi1(kind, |bytes, len| atom.push_midi(frame, bytes, len));
            });
        } else {
            // Keep the held-note bookkeeping in step even with nowhere to send.
            self.held.expand(io.events.as_slice(), |_, _: EventKind| {});
        }
        // What the editor sent, such as the path of a file to load.
        while read_message(&mut self.from_ui, &mut self.message) {
            let Some((port, atom)) = self.message.split_at_checked(4) else {
                continue;
            };
            let port = u32::from_le_bytes(port.try_into().unwrap());
            if let Some(index) = self.shared.atom_ports.iter().position(|p| *p == port)
                && self.atoms[index].input
            {
                self.atoms[index].push_atom(0, atom);
            }
        }
        // What state lanes handed for a later frame: after the rest, so
        // that each sequence stays in the order of its frames.
        self.push_queued(n, true);
        self.queued.clear();

        let shared = &self.shared;
        unsafe {
            lilv_instance_run(shared.instance, n as u32);
            if let (Some(worker), Some(interface)) =
                (shared.host.worker.get(), shared.worker_interface.as_ref())
            {
                let handle = lilv_instance_get_handle(shared.instance).cast();
                worker.finish();
                while read_message(&mut *worker.responses.get(), &mut self.response) {
                    (interface.work_response)(
                        handle,
                        self.response.len() as u32,
                        self.response.as_ptr().cast(),
                    );
                }
                if let Some(end_run) = interface.end_run {
                    end_run(handle);
                }
            }
        }

        // An open editor hears everything the plugin sends; with none open,
        // the controller still hears the new values of its properties.
        let ui_open = shared.ui_open.load(Relaxed);
        if ui_open || shared.patch_port.is_some() {
            for (atom, port) in self
                .atoms
                .iter()
                .zip(&shared.atom_ports)
                .filter(|(atom, _)| !atom.input)
            {
                atom.each_event(|event| {
                    if !ui_open && !lv2_patch::is_set(&urids().patch, event) {
                        return;
                    }
                    self.message.clear();
                    self.message.extend_from_slice(&port.to_le_bytes());
                    self.message.extend_from_slice(event);
                    write_message(&mut self.to_ui, &self.message);
                });
            }
        }

        let latency = shared.latency.map_or(0, |slot| shared.control(slot).max(0.0) as u64);
        self.rest.end_after_tail(
            Some(self.tail + latency),
            self.audio_out.iter().all(|c| paw_engine::device::silent(&c[..n])),
        );

        let add = self.audio_in.is_empty();
        match self.audio_out.as_slice() {
            [] => {}
            [mono] => write_output(io.left, io.right, &[&mono[..n]], add),
            [left, right, ..] => write_output(io.left, io.right, &[&left[..n], &right[..n]], add),
        }
        crate::write_pairs(
            &self.out_pairs,
            std::slice::from_ref(&self.audio_out),
            io.outputs,
            n,
        );
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if let Some(&slot) = self.shared.param_slots.get(index as usize) {
            self.shared.set_control(slot, value);
        }
    }
}

impl Drop for Lv2Device {
    fn drop(&mut self) {
        unsafe { lilv_instance_deactivate(self.shared.instance) };
    }
}

unsafe extern "C" fn get_port_value(
    symbol: *const c_char,
    shared: *mut c_void,
    size: *mut u32,
    type_: *mut u32,
) -> *const c_void {
    unsafe {
        let shared = &*(shared as *const Shared);
        let Some(&slot) = shared.symbols.get(CStr::from_ptr(symbol)) else {
            *size = 0;
            *type_ = 0;
            return ptr::null();
        };
        // lilv copies the value before asking for the next one.
        *shared.scratch.get() = shared.control(slot);
        *size = 4;
        *type_ = urids().float;
        shared.scratch.get().cast()
    }
}

unsafe extern "C" fn set_port_value(
    symbol: *const c_char,
    shared: *mut c_void,
    value: *const c_void,
    size: u32,
    type_: u32,
) {
    unsafe {
        let shared = &*(shared as *const Shared);
        let Some(&slot) = shared.symbols.get(CStr::from_ptr(symbol)) else {
            return;
        };
        let u = urids();
        if type_ == u.float && size == 4 {
            shared.set_control(slot, *(value as *const f32));
        } else if type_ == u.int && size == 4 {
            shared.set_control(slot, *(value as *const i32) as f32);
        }
    }
}

unsafe fn restore(shared: &Shared, state: *const LilvState) {
    unsafe {
        lilv_state_restore(
            state,
            shared.instance,
            Some(set_port_value),
            shared as *const Shared as *mut c_void,
            0,
            shared.host.feature_list.as_ptr().cast(),
        );
    }
    // A plugin may take part of a state on only in its next block.
    shared.wake.store(true, Relaxed);
}

/// What the editor is given as its way back to the host. It lives in a box
/// so the pointer handed to the editor stays good.
struct UiLink {
    shared: Arc<Shared>,
    to_plugin: UnsafeCell<rtrb::Producer<u8>>,
    /// Parameters the editor changed: position in the parameter list and value.
    changes: RefCell<Vec<(usize, f64)>>,
    /// A size the editor asked its window to be.
    resize: Cell<Option<(u32, u32)>>,
    /// The editor says its window was closed.
    closed: Cell<bool>,
}

#[repr(C)]
struct UiDescriptor {
    uri: *const c_char,
    instantiate: unsafe extern "C" fn(
        *const UiDescriptor,
        *const c_char,
        *const c_char,
        WriteFn,
        *mut c_void,
        *mut *mut c_void,
        *const *const Feature,
    ) -> *mut c_void,
    cleanup: unsafe extern "C" fn(*mut c_void),
    port_event: Option<unsafe extern "C" fn(*mut c_void, u32, u32, u32, *const c_void)>,
    extension_data: Option<unsafe extern "C" fn(*const c_char) -> *const c_void>,
}

type WriteFn = unsafe extern "C" fn(*mut c_void, u32, u32, u32, *const c_void);

#[repr(C)]
struct UiResize {
    handle: *mut c_void,
    ui_resize: unsafe extern "C" fn(*mut c_void, i32, i32) -> i32,
}

#[repr(C)]
struct UiPortMap {
    handle: *mut c_void,
    port_index: unsafe extern "C" fn(*mut c_void, *const c_char) -> u32,
}

/// The editor wrote to a port: a control value, or a message for an atom port.
unsafe extern "C" fn ui_write(
    link: *mut c_void,
    port: u32,
    size: u32,
    protocol: u32,
    buffer: *const c_void,
) {
    unsafe {
        let link = &*(link as *const UiLink);
        let shared = &link.shared;
        if protocol == 0 && size == 4 {
            let value = *(buffer as *const f32);
            if let Some(&(_, slot)) = shared.control_ports.iter().find(|(p, _)| *p == port) {
                shared.set_control(slot, value);
                if let Some(index) = shared.param_slots.iter().position(|s| *s == slot) {
                    link.changes.borrow_mut().push((index, value as f64));
                }
            }
        } else if protocol == urids().event_transfer {
            let mut message = port.to_le_bytes().to_vec();
            message.extend_from_slice(std::slice::from_raw_parts(
                buffer as *const u8,
                size as usize,
            ));
            write_message(&mut *link.to_plugin.get(), &message);
        }
    }
}

unsafe extern "C" fn ui_resize(link: *mut c_void, width: i32, height: i32) -> i32 {
    let link = unsafe { &*(link as *const UiLink) };
    link.resize
        .set(Some((width.max(1) as u32, height.max(1) as u32)));
    0
}

unsafe extern "C" fn ui_port_index(link: *mut c_void, symbol: *const c_char) -> u32 {
    unsafe {
        let link = &*(link as *const UiLink);
        link.shared
            .port_symbols
            .get(CStr::from_ptr(symbol))
            .copied()
            .unwrap_or(u32::MAX)
    }
}

const UI: &str = "http://lv2plug.in/ns/extensions/ui#";
const EXTERNAL_UI: &CStr = c"http://kxstudio.sf.net/ns/lv2ext/external-ui#Widget";
const EXTERNAL_HOST: &CStr = c"http://kxstudio.sf.net/ns/lv2ext/external-ui#Host";
const SHOW_INTERFACE: &CStr = c"http://lv2plug.in/ns/extensions/ui#showInterface";
const IDLE_INTERFACE: &CStr = c"http://lv2plug.in/ns/extensions/ui#idleInterface";

/// The best editor the plugin offers that this host can show.
///
/// A plugin may ship several editors. An X11 one is embedded in a window of
/// ours. Editors in other toolkits are used when they can open a window of
/// their own, which is what `ui:showInterface` and the older "external UI"
/// are for: the toolkit then runs inside the editor's library and this host
/// links none of them. A bare Gtk widget is put in a Gtk window here.
unsafe fn find_ui(plugin: *const LilvPlugin) -> Option<UiInfo> {
    let w = world();
    // For trying a particular kind: `PAW_LV2_UI=x11|shows|external|gtk`.
    let only = std::env::var("PAW_LV2_UI").ok();
    unsafe {
        let uri = |text: String| {
            let text = CString::new(text).unwrap();
            lilv_new_uri(w.world, text.as_ptr())
        };
        let gtk = [uri(format!("{UI}GtkUI")), uri(format!("{UI}Gtk3UI"))];
        let external = lilv_new_uri(w.world, EXTERNAL_UI.as_ptr());
        let extension_data = uri(format!("{LV2_CORE}extensionData"));
        let show_interface = lilv_new_uri(w.world, SHOW_INTERFACE.as_ptr());

        let uis = lilv_plugin_get_uis(plugin);
        let mut found: Option<UiInfo> = None;
        let mut it = lilv_uis_begin(uis);
        while !lilv_uis_is_end(uis, it) {
            let ui = lilv_uis_get(uis, it);
            it = lilv_uis_next(uis, it);
            let shows =
                lilv_world_ask(w.world, lilv_ui_get_uri(ui), extension_data, show_interface);
            let is_gtk = gtk.iter().any(|class| lilv_ui_is_a(ui, *class));
            let mut kinds = Vec::new();
            if lilv_ui_is_a(ui, w.x11_ui) {
                kinds.push(UiKind::X11);
            } else if lilv_ui_is_a(ui, external) {
                kinds.push(UiKind::External);
            } else {
                if shows {
                    kinds.push(UiKind::Shows);
                }
                if is_gtk {
                    kinds.push(UiKind::Gtk);
                }
            }
            let path = |node: *const LilvNode| {
                let parsed = lilv_file_uri_parse(lilv_node_as_uri(node), ptr::null_mut());
                if parsed.is_null() {
                    return None;
                }
                let path = CStr::from_ptr(parsed).to_owned();
                lilv_free(parsed.cast());
                Some(path)
            };
            let (Some(binary), Some(bundle)) = (
                path(lilv_ui_get_binary_uri(ui)),
                path(lilv_ui_get_bundle_uri(ui)),
            ) else {
                continue;
            };
            for kind in kinds {
                let wanted = only
                    .as_deref()
                    .is_none_or(|name| format!("{kind:?}").eq_ignore_ascii_case(name));
                if wanted && found.as_ref().is_none_or(|best| kind < best.kind) {
                    found = Some(UiInfo {
                        uri: CStr::from_ptr(lilv_node_as_uri(lilv_ui_get_uri(ui))).to_owned(),
                        binary: PathBuf::from(binary.to_string_lossy().into_owned()),
                        bundle: bundle.clone(),
                        kind,
                    });
                }
            }
        }
        lilv_uis_free(uis);
        for node in gtk
            .into_iter()
            .chain([external, extension_data, show_interface])
        {
            lilv_node_free(node);
        }
        found
    }
}

/// What an "external" editor hands back: three functions to drive it with.
#[repr(C)]
struct ExternalWidget {
    run: unsafe extern "C" fn(*mut ExternalWidget),
    show: unsafe extern "C" fn(*mut ExternalWidget),
    hide: unsafe extern "C" fn(*mut ExternalWidget),
}

#[repr(C)]
struct ExternalHost {
    ui_closed: unsafe extern "C" fn(*mut c_void),
    plugin_human_id: *const c_char,
}

unsafe extern "C" fn ui_closed(link: *mut c_void) {
    unsafe { &*(link as *const UiLink) }.closed.set(true);
}

#[repr(C)]
struct ShowInterface {
    show: unsafe extern "C" fn(*mut c_void) -> i32,
    hide: unsafe extern "C" fn(*mut c_void) -> i32,
}

/// Lets an editor reach the plugin's own extension data.
#[repr(C)]
struct DataAccess {
    data_access: unsafe extern "C" fn(*const c_char) -> *const c_void,
}

/// Where an open editor is drawn.
enum Surface {
    Embedded(HostWindow),
    /// The editor's own window.
    Own(*const ShowInterface),
    External(*mut ExternalWidget),
    Gtk(GtkWindow),
}

/// An open editor.
struct Ui {
    descriptor: *const UiDescriptor,
    handle: *mut c_void,
    idle: Option<unsafe extern "C" fn(*mut c_void) -> i32>,
    surface: Surface,
    /// The last value shown for each control port, to send only what changed.
    shown: Vec<f32>,
    // What the editor was handed at instantiation and may still point to.
    _features: Vec<Feature>,
    _feature_list: Vec<*const Feature>,
    _resize: Box<UiResize>,
    _port_map: Box<UiPortMap>,
    _external: Box<ExternalHost>,
    _data_access: Option<Box<DataAccess>>,
    _options: Vec<OptionsOption>,
    _scale: Box<f32>,
    _title: CString,
}

struct Lv2Controller {
    shared: Arc<Shared>,
    link: Box<UiLink>,
    from_plugin: rtrb::Consumer<u8>,
    message: Vec<u8>,
    ui: Option<Ui>,
    ports: Ports,
    /// The value of each property the plugin told (by URID), or that was
    /// set from here.
    values: HashMap<u32, serde_json::Value>,
    /// Tells the echo of a state from an edit. The editor writes a control
    /// with no gesture (paw offers no `ui:touch`): a value that a state
    /// gave is its echo, another value an edit.
    echo: Echo,
}

/// Note the value a message from the plugin gives a property.
fn note_property(values: &mut HashMap<u32, serde_json::Value>, atom: &[u8]) {
    if let Some((property, value)) = lv2_patch::parse_set(&urids().patch, atom) {
        values.insert(property, value);
    }
}

impl Lv2Controller {
    /// The host set the controls from a state itself: what they hold now
    /// are the state's values, for the echo.
    fn expect_values(&mut self) {
        let values: Vec<Option<f64>> =
            (0..self.shared.param_slots.len()).map(|i| self.value(i)).collect();
        self.echo.given(values);
    }

    /// Send a patch message to the plugin's control port. False when the
    /// plugin takes none, or the way to it is full.
    fn send_patch(&mut self, atom: &[u8]) -> bool {
        let Some(port) = self.shared.patch_port else {
            return false;
        };
        let mut message = port.to_le_bytes().to_vec();
        message.extend_from_slice(atom);
        write_message(self.link.to_plugin.get_mut(), &message)
    }

    fn ask_properties(&mut self) {
        if !self.shared.properties.is_empty() {
            self.send_patch(&lv2_patch::get_message(&urids().patch));
        }
    }

    /// Take what the plugin sent while no editor is open: the new values of
    /// its properties.
    fn read_plugin(&mut self) {
        while read_message(&mut self.from_plugin, &mut self.message) {
            if let Some((_, atom)) = self.message.split_at_checked(4) {
                note_property(&mut self.values, atom);
            }
        }
    }

    fn properties_json(&mut self) -> Vec<u8> {
        if self.ui.is_none() {
            self.read_plugin();
        }
        let list: Vec<serde_json::Value> = self
            .shared
            .properties
            .iter()
            .map(|p| p.json(self.values.get(&p.urid)))
            .collect();
        serde_json::to_vec(&list).unwrap_or_default()
    }

    /// Set a property from `{ "property": name, "value": value }`.
    fn set_property(&mut self, data: &[u8]) -> Result<()> {
        let (urid, value, message) = self.property_message(data)?;
        if !self.send_patch(&message) {
            bail!("the plugin did not take the message: try again");
        }
        self.values.insert(urid, value);
        Ok(())
    }

    /// The `patch:Set` that sets a property from `{ "property": name,
    /// "value": value }`, with the property's URID and the value: checked,
    /// not sent.
    fn property_message(&self, data: &[u8]) -> Result<(u32, serde_json::Value, Vec<u8>)> {
        #[derive(serde::Deserialize)]
        struct Set {
            property: String,
            value: serde_json::Value,
        }
        let set: Set = serde_json::from_slice(data)
            .context("give the property as { \"property\": name, \"value\": value }")?;
        let shared = self.shared.clone();
        if shared.properties.is_empty() {
            bail!("this plugin has no properties");
        }
        let Some(property) = lv2_patch::find(&shared.properties, &set.property) else {
            let names: Vec<&str> = shared.properties.iter().map(|p| p.key()).collect();
            bail!(
                "this plugin has no property `{}` (it has: {})",
                set.property,
                names.join(", ")
            );
        };
        if !property.writable {
            bail!("the plugin does not take a value for `{}`", property.key());
        }
        if property.kind == Kind::Path
            && let Some(path) = set.value.as_str()
            && !path.is_empty()
        {
            let file = std::path::Path::new(path);
            if !file.is_absolute() {
                bail!("give `{}` an absolute path, not {path}", property.key());
            }
            if !file.exists() {
                bail!("there is no file {path}");
            }
        }
        let message = lv2_patch::set_message(&urids().patch, property, &set.value)?;
        Ok((property.urid, set.value, message))
    }
    /// Keep the open editor up to date and let it do its work.
    fn run_editor(&mut self) {
        let Some(ui) = self.ui.as_mut() else { return };
        let shared = &self.shared;
        let mut close = self.link.closed.replace(false);
        unsafe {
            match &mut ui.surface {
                Surface::Embedded(window) => {
                    if let Some((width, height)) = self.link.resize.take() {
                        window.resize(width, height);
                    }
                    for event in window.events() {
                        close |= matches!(event, WindowEvent::Closed);
                    }
                }
                Surface::External(widget) => ((**widget).run)(*widget),
                Surface::Gtk(window) => close |= window.run(),
                Surface::Own(_) => {}
            }
            if let Some(port_event) = (*ui.descriptor).port_event {
                // Control values, the plugin's outputs included: meters and such.
                for (index, (port, slot)) in shared.control_ports.iter().enumerate() {
                    let value = shared.control(*slot);
                    if ui.shown[index].to_bits() != value.to_bits() {
                        ui.shown[index] = value;
                        port_event(ui.handle, *port, 4, 0, (&value as *const f32).cast());
                    }
                }
                // What the plugin sent from its atom outputs.
                while read_message(&mut self.from_plugin, &mut self.message) {
                    let Some((port, atom)) = self.message.split_at_checked(4) else {
                        continue;
                    };
                    let port = u32::from_le_bytes(port.try_into().unwrap());
                    note_property(&mut self.values, atom);
                    port_event(
                        ui.handle,
                        port,
                        atom.len() as u32,
                        urids().event_transfer,
                        atom.as_ptr().cast(),
                    );
                }
            }
            // An editor with its own window says it was closed by returning non-zero.
            if let Some(idle) = ui.idle {
                close |= idle(ui.handle) != 0;
            }
        }
        if close {
            self.close_editor();
        }
    }
}

impl Drop for Lv2Controller {
    fn drop(&mut self) {
        self.close_editor();
    }
}

impl Controller for Lv2Controller {
    fn ports(&self) -> Ports {
        self.ports.clone()
    }

    fn set_offline(&mut self, offline: bool) {
        if let Some(slot) = self.shared.free_wheeling {
            let value: f32 = if offline { 1.0 } else { 0.0 };
            self.shared.controls[slot].store(value.to_bits(), Relaxed);
        }
        if let Some(worker) = self.shared.host.worker.get() {
            worker.offline.store(offline, Relaxed);
        }
    }

    fn prepare(&mut self, method: &str, data: &[u8]) -> Result<Option<Vec<u8>>> {
        if method != paw_engine::device::method::PROPERTY_SET {
            return Ok(None);
        }
        let Some(port) = self.shared.patch_port else {
            bail!("this plugin has no properties");
        };
        let (_, _, atom) = self.property_message(data)?;
        let mut message = port.to_le_bytes().to_vec();
        message.extend_from_slice(&atom);
        Ok(Some(message))
    }

    fn params(&self) -> Vec<ParamInfo> {
        self.shared.params.clone()
    }

    fn value(&self, index: usize) -> Option<f64> {
        Some(self.shared.control(*self.shared.param_slots.get(index)?) as f64)
    }

    fn idle(&mut self) {
        if self.ui.is_some() {
            self.run_editor();
        } else {
            self.read_plugin();
        }
    }

    fn take_changes(&mut self) -> Vec<Change> {
        let changes = self.link.changes.take();
        changes
            .into_iter()
            .map(|(index, value)| self.echo.change(index, value, false))
            .collect()
    }

    fn has_editor(&self) -> bool {
        self.shared.ui.is_some()
    }

    fn editor_open(&self) -> bool {
        self.ui.is_some()
    }

    fn open_editor(&mut self, title: &str) -> Result<()> {
        if self.ui.is_some() {
            return Ok(());
        }
        let shared = &self.shared;
        let info = shared
            .ui
            .as_ref()
            .context("this plugin has no editor this host can show")?;
        unsafe {
            // Never unloaded, like the plugins themselves.
            let lib = std::mem::ManuallyDrop::new(libloading::Library::from(
                crate::libs::open_library(&info.binary)
                    .with_context(|| format!("loading {}", info.binary.display()))?,
            ));
            let get = lib
                .get::<unsafe extern "C" fn(u32) -> *const UiDescriptor>(b"lv2ui_descriptor\0")
                .context("not an LV2 editor")?;
            let descriptor = (0..)
                .map(|index| get(index))
                .take_while(|d| !d.is_null())
                .find(|d| CStr::from_ptr((**d).uri) == info.uri.as_c_str())
                .context("the editor is not in its library")?;

            let window = match info.kind {
                UiKind::X11 => Some(HostWindow::new(title, 640, 480)?),
                _ => None,
            };
            let link = &*self.link as *const UiLink as *mut c_void;
            self.link.closed.set(false);
            let title = CString::new(title).unwrap_or_default();
            let mut resize = Box::new(UiResize {
                handle: link,
                ui_resize,
            });
            let mut port_map = Box::new(UiPortMap {
                handle: link,
                port_index: ui_port_index,
            });
            let mut external = Box::new(ExternalHost {
                ui_closed,
                plugin_human_id: title.as_ptr(),
            });
            let host = &shared.host;
            // The plugin's options, plus how much to magnify the editor.
            let scale = Box::new(ui_scale() as f32);
            let u = urids();
            let mut options: Vec<OptionsOption> = host.options[..3]
                .iter()
                .map(|o| OptionsOption {
                    context: 0,
                    subject: 0,
                    key: o.key,
                    size: o.size,
                    type_: o.type_,
                    value: o.value,
                })
                .collect();
            options.push(OptionsOption {
                context: 0,
                subject: 0,
                key: u.scale_factor,
                size: 4,
                type_: u.float,
                value: (&*scale as *const f32).cast(),
            });
            // For editors that make their own window.
            options.push(OptionsOption {
                context: 0,
                subject: 0,
                key: u.window_title,
                size: title.as_bytes_with_nul().len() as u32,
                type_: u.string,
                value: title.as_ptr().cast(),
            });
            options.push(OptionsOption {
                context: 0,
                subject: 0,
                key: 0,
                size: 0,
                type_: 0,
                value: ptr::null(),
            });

            let feature = |uri: &'static CStr, data: *mut c_void| Feature {
                uri: uri.as_ptr(),
                data,
            };
            let mut features = vec![
                feature(URID_MAP, &host.map as *const UridMap as *mut c_void),
                feature(URID_UNMAP, &host.unmap as *const UridUnmap as *mut c_void),
                feature(OPTIONS, options.as_mut_ptr() as *mut c_void),
                feature(
                    c"http://lv2plug.in/ns/extensions/ui#resize",
                    &mut *resize as *mut UiResize as *mut c_void,
                ),
                feature(
                    c"http://lv2plug.in/ns/extensions/ui#portMap",
                    &mut *port_map as *mut UiPortMap as *mut c_void,
                ),
                feature(IDLE_INTERFACE, ptr::null_mut()),
                feature(
                    c"http://lv2plug.in/ns/ext/instance-access",
                    lilv_instance_get_handle(shared.instance).cast(),
                ),
                feature(
                    EXTERNAL_HOST,
                    &mut *external as *mut ExternalHost as *mut c_void,
                ),
            ];
            if let Some(window) = &window {
                features.push(feature(
                    c"http://lv2plug.in/ns/extensions/ui#parent",
                    window.id() as usize as *mut c_void,
                ));
            }
            // Some editors read the plugin's extension data directly.
            let mut data_access = (*(*shared.instance).lv2_descriptor)
                .extension_data
                .map(|get| {
                    Box::new(DataAccess {
                        data_access: std::mem::transmute::<
                            extern "C" fn(*const c_char) -> *const c_void,
                            unsafe extern "C" fn(*const c_char) -> *const c_void,
                        >(get),
                    })
                });
            if let Some(access) = data_access.as_mut() {
                features.push(feature(
                    c"http://lv2plug.in/ns/ext/data-access",
                    &mut **access as *mut DataAccess as *mut c_void,
                ));
            }
            let mut feature_list: Vec<*const Feature> =
                features.iter().map(|f| f as *const Feature).collect();
            feature_list.push(ptr::null());

            let plugin_uri = lilv_node_as_uri(lilv_plugin_get_uri(shared.plugin));
            let mut widget = ptr::null_mut();
            let handle = ((*descriptor).instantiate)(
                descriptor,
                plugin_uri,
                info.bundle.as_ptr(),
                ui_write,
                link,
                &mut widget,
                feature_list.as_ptr(),
            );
            if handle.is_null() {
                bail!("the plugin's editor could not be created");
            }
            let extension = |uri: &CStr| -> *const c_void {
                (*descriptor)
                    .extension_data
                    .map_or(ptr::null(), |data| data(uri.as_ptr()))
            };
            let idle = Some(extension(IDLE_INTERFACE))
                .filter(|interface| !interface.is_null())
                .map(|interface| *(interface as *const unsafe extern "C" fn(*mut c_void) -> i32));

            let surface = match (info.kind, window) {
                (UiKind::X11, Some(mut window)) => {
                    // Fit the window to the editor: what it asked for, else what it made.
                    if let Some((width, height)) = self
                        .link
                        .resize
                        .take()
                        .or_else(|| window.child_size(widget as usize as u32))
                    {
                        window.resize(width, height);
                    }
                    // LV2 editors size themselves; the host has no way to ask
                    // them to follow a window.
                    window.set_fixed(true);
                    Ok(Surface::Embedded(window))
                }
                (UiKind::External, _) if !widget.is_null() => {
                    let widget = widget as *mut ExternalWidget;
                    ((*widget).show)(widget);
                    Ok(Surface::External(widget))
                }
                (UiKind::Shows, _) => {
                    match (extension(SHOW_INTERFACE) as *const ShowInterface).as_ref() {
                        Some(show) => {
                            (show.show)(handle);
                            Ok(Surface::Own(show))
                        }
                        None => Err(anyhow!("the editor does not say how to show itself")),
                    }
                }
                (UiKind::Gtk, _) => GtkWindow::wrap(widget, &title).map(Surface::Gtk),
                _ => Err(anyhow!("the editor gave back no window")),
            };
            let surface = match surface {
                Ok(surface) => surface,
                Err(err) => {
                    ((*descriptor).cleanup)(handle);
                    return Err(err);
                }
            };
            self.ui = Some(Ui {
                descriptor,
                handle,
                idle,
                surface,
                // Not-a-number never equals a value, so everything is sent once.
                shown: vec![f32::NAN; shared.control_ports.len()],
                _features: features,
                _feature_list: feature_list,
                _resize: resize,
                _port_map: port_map,
                _external: external,
                _data_access: data_access,
                _options: options,
                _scale: scale,
                _title: title,
            });
            shared.ui_open.store(true, Relaxed);
        }
        Ok(())
    }

    fn close_editor(&mut self) {
        if let Some(ui) = self.ui.take() {
            self.shared.ui_open.store(false, Relaxed);
            unsafe {
                match &ui.surface {
                    Surface::Own(show) => {
                        ((**show).hide)(ui.handle);
                    }
                    Surface::External(widget) => ((**widget).hide)(*widget),
                    // The widget leaves the window before its editor destroys it.
                    Surface::Gtk(window) => window.release(),
                    Surface::Embedded(_) => {}
                }
                ((*ui.descriptor).cleanup)(ui.handle);
            }
            // Only now the window the editor was drawn in.
            drop(ui.surface);
        }
    }

    fn save_state(&mut self) -> Result<Option<Vec<u8>>> {
        let shared = &*self.shared;
        let w = world();
        unsafe {
            let map = &shared.host.map as *const UridMap as *mut _;
            let state = lilv_state_new_from_instance(
                shared.plugin,
                shared.instance,
                map,
                ptr::null(),
                ptr::null(),
                ptr::null(),
                ptr::null(),
                Some(get_port_value),
                shared as *const Shared as *mut c_void,
                // Only state that is plain data and safe to move between machines.
                3,
                shared.host.feature_list.as_ptr().cast(),
            );
            if state.is_null() {
                return Ok(None);
            }
            let unmap = &shared.host.unmap as *const UridUnmap as *mut _;
            let text =
                lilv_state_to_string(w.world, map, unmap, state, STATE_URI.as_ptr(), ptr::null());
            lilv_state_free(state);
            if text.is_null() {
                bail!("the plugin's state could not be written out");
            }
            let bytes = CStr::from_ptr(text).to_bytes().to_vec();
            lilv_free(text.cast());
            Ok(Some(bytes))
        }
    }

    fn call(&mut self, method: &str, data: &[u8]) -> Result<Vec<u8>> {
        let shared = &*self.shared;
        let w = world().world;
        let uri = |text: &str| -> Result<*mut LilvNode> {
            let text = CString::new(text)?;
            Ok(unsafe { lilv_new_uri(w, text.as_ptr()) })
        };
        match method {
            // What the plugin holds besides its parameters (a model file, an
            // impulse response), and the values it last told.
            paw_engine::device::method::PROPERTIES => Ok(self.properties_json()),
            paw_engine::device::method::PROPERTY_SET => self.set_property(data).map(|_| Vec::new()),
            // The presets the plugin's bundles (and the user's) describe.
            paw_engine::device::method::PRESETS => unsafe {
                let class = uri("http://lv2plug.in/ns/ext/presets#Preset")?;
                let label = uri("http://www.w3.org/2000/01/rdf-schema#label")?;
                let related = lilv_plugin_get_related(shared.plugin, class);
                let mut presets = Vec::new();
                let mut it = lilv_nodes_begin(related);
                while !lilv_nodes_is_end(related, it) {
                    let preset = lilv_nodes_get(related, it);
                    lilv_world_load_resource(w, preset);
                    let id = node_text(preset);
                    let mut name = take_text(lilv_world_get(w, preset, label, ptr::null()));
                    if name.is_empty() {
                        name = id.rsplit(['/', '#', ':']).next().unwrap_or(&id).to_string();
                    }
                    presets.push(crate::presets::Preset {
                        id,
                        name,
                        category: String::new(),
                    });
                    it = lilv_nodes_next(related, it);
                }
                lilv_nodes_free(related);
                lilv_node_free(class);
                lilv_node_free(label);
                presets.sort_by(|a, b| a.name.cmp(&b.name));
                Ok(crate::presets::to_json(&presets))
            },
            paw_engine::device::method::PRESET_LOAD => unsafe {
                let node = uri(&String::from_utf8_lossy(data))?;
                lilv_world_load_resource(w, node);
                let map = &shared.host.map as *const UridMap as *mut _;
                let state = lilv_state_new_from_world(w, map, node);
                lilv_node_free(node);
                if state.is_null() {
                    bail!("the preset could not be read");
                }
                restore(shared, state);
                lilv_state_free(state);
                self.expect_values();
                Ok(Vec::new())
            },
            _ => bail!("this device has no method `{method}`"),
        }
    }

    fn load_state(&mut self, state: &[u8]) -> Result<()> {
        let shared = &*self.shared;
        let text = CString::new(state).context("the saved state is not text")?;
        unsafe {
            let map = &shared.host.map as *const UridMap as *mut _;
            let state = lilv_state_new_from_string(world().world, map, text.as_ptr());
            if state.is_null() {
                bail!("the saved state could not be read");
            }
            restore(shared, state);
            lilv_state_free(state);
        }
        self.expect_values();
        self.ask_properties();
        Ok(())
    }
}

/// The properties a plugin lists as `patch:writable` or `patch:readable`.
unsafe fn find_properties(plugin: *const LilvPlugin, w: &World) -> Vec<Property> {
    let mut properties: Vec<Property> = Vec::new();
    unsafe {
        let subject = lilv_plugin_get_uri(plugin);
        for (predicate, writable) in [(w.patch_writable, true), (w.patch_readable, false)] {
            let nodes = lilv_world_find_nodes(w.world, subject, predicate, ptr::null());
            if nodes.is_null() {
                continue;
            }
            let mut it = lilv_nodes_begin(nodes);
            while !lilv_nodes_is_end(nodes, it) {
                let node = lilv_nodes_get(nodes, it);
                it = lilv_nodes_next(nodes, it);
                let uri = node_text(node);
                if let Some(known) = properties.iter_mut().find(|p| p.uri == uri) {
                    known.writable |= writable;
                    known.readable |= !writable;
                    continue;
                }
                let range = take_text(lilv_world_get(w.world, node, w.range, ptr::null()));
                let label = take_text(lilv_world_get(w.world, node, w.label, ptr::null()));
                let types = take_text(lilv_world_get(w.world, node, w.file_types, ptr::null()));
                let Ok(c_uri) = CString::new(uri.clone()) else { continue };
                properties.push(Property {
                    urid: urid(&c_uri),
                    label: if label.is_empty() { uri.rsplit(['#', '/', ':']).next().unwrap_or(&uri).to_string() } else { label },
                    kind: Kind::from_range(&range),
                    range,
                    writable,
                    readable: !writable,
                    file_types: types
                        .split(',')
                        .map(|t| t.trim().to_string())
                        .filter(|t| !t.is_empty())
                        .collect(),
                    uri,
                });
            }
            lilv_nodes_free(nodes);
        }
    }
    properties
}
