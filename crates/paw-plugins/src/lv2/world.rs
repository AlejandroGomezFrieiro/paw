//! The lilv world: finding plugins and reading their descriptions.

use std::ffi::{CStr, CString};
use std::path::PathBuf;
use std::ptr;
use std::sync::OnceLock;

use paw_engine::{DeviceFormat, ParamInfo, Registry};
use lilv_sys::*;

use crate::search_dirs;
use super::*;
use super::factory::*;

// --- the world ---------------------------------------------------------------

/// lilv's view of the installed plugins, and the URIs used to question it.
pub(super) struct World {
    pub(super) world: *mut LilvWorld,
    pub(super) input: *mut LilvNode,
    pub(super) audio: *mut LilvNode,
    pub(super) control: *mut LilvNode,
    pub(super) atom: *mut LilvNode,
    pub(super) cv: *mut LilvNode,
    pub(super) midi_event: *mut LilvNode,
    pub(super) time_position: *mut LilvNode,
    pub(super) free_wheeling: *mut LilvNode,
    pub(super) toggled: *mut LilvNode,
    instrument: *mut LilvNode,
    pub(super) x11_ui: *mut LilvNode,
    /// A port, or a group of ports, that takes a side-chain.
    pub(super) side_chain: *mut LilvNode,
    pub(super) group: *mut LilvNode,
    pub(super) side_chain_of: *mut LilvNode,
    integer: *mut LilvNode,
    enumeration: *mut LilvNode,
    not_automatic: *mut LilvNode,
    unit: *mut LilvNode,
    unit_symbol: *mut LilvNode,
    pub(super) label: *mut LilvNode,
    name: *mut LilvNode,
    minor_version: *mut LilvNode,
    micro_version: *mut LilvNode,
    // Properties set with patch messages (see `lv2_patch`).
    pub(super) patch_writable: *mut LilvNode,
    pub(super) patch_readable: *mut LilvNode,
    pub(super) patch_message: *mut LilvNode,
    pub(super) range: *mut LilvNode,
    pub(super) file_types: *mut LilvNode,
}

// Created and used on the main thread only.
// SAFETY: The World holds the lilv world and node pointers, made once and never freed. lilv is
// not thread safe, so by convention paw calls it from the main thread only; this impl
// is how the static `world()` can hold it.
unsafe impl Send for World {}
// SAFETY: See `Send`: the World is read-only after creation and used from the main thread.
unsafe impl Sync for World {}

pub(super) fn world() -> &'static World {
    static WORLD: OnceLock<World> = OnceLock::new();
    // SAFETY: `lilv_world_new` makes a world that lives for the program; the nodes and options are made
    // from it here and never freed; strings passed are NUL-terminated CStrings that live through each call.
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

pub(super) unsafe fn node_text(node: *const LilvNode) -> String {
    // SAFETY: `node` is null (handled) or a live lilv node; lilv owns the string `lilv_node_as_string`
    // returns and it is valid until the node is freed, so it is copied before returning.
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
pub(super) unsafe fn take_text(node: *mut LilvNode) -> String {
    // SAFETY: `node` is null or a live lilv node that the caller owns and nothing uses after this call.
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
pub(super) unsafe fn describe_port(
    plugin: *const LilvPlugin,
    port: *const LilvPort,
    w: &World,
    info: &mut ParamInfo,
) {
    // SAFETY: `plugin`, `port` and `w` are live lilv objects of the world; every list or node lilv
    // returns to us is freed in this block, and scale-point strings are copied out first.
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
    // SAFETY: `plugin` is live and `required` is a node list that we own and free before returning;
    // the URI strings are lilv's, valid until then and copied before.
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
        let uri = plugin.id.clone();
        let info = plugin.device_info(format!("lv2:{uri}"), DeviceFormat::Lv2);
        registry.register(std::rc::Rc::new(Lv2Factory {
            info,
            uri,
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
    // SAFETY: `w.world` is live and its plugin list is owned by the world; every node lilv gives is
    // read before the next call that could invalidate it, and owned ones are freed here.
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

