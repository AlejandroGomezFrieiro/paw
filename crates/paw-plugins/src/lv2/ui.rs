//! The plugin's own editor: finding it, the host features it needs, its ports.

use std::cell::{Cell, RefCell, UnsafeCell};
use std::ffi::{CStr, CString, c_char, c_void};
use std::path::PathBuf;
use std::ptr;
use std::sync::Arc;

use lilv_sys::*;

use crate::window::{GtkWindow, HostWindow};
use super::*;
use super::urid::*;
use super::world::*;
use super::worker::*;
use super::shared::*;

/// What the editor is given as its way back to the host. It lives in a box
/// so the pointer handed to the editor stays good.
pub(super) struct UiLink {
    pub(super) shared: Arc<Shared>,
    pub(super) to_plugin: UnsafeCell<rtrb::Producer<u8>>,
    /// Parameters the editor changed: position in the parameter list and value.
    pub(super) changes: RefCell<Vec<(usize, f64)>>,
    /// A size the editor asked its window to be.
    pub(super) resize: Cell<Option<(u32, u32)>>,
    /// The editor says its window was closed.
    pub(super) closed: Cell<bool>,
}

#[repr(C)]
pub(super) struct UiDescriptor {
    pub(super) uri: *const c_char,
    pub(super) instantiate: unsafe extern "C" fn(
        *const UiDescriptor,
        *const c_char,
        *const c_char,
        WriteFn,
        *mut c_void,
        *mut *mut c_void,
        *const *const Feature,
    ) -> *mut c_void,
    pub(super) cleanup: unsafe extern "C" fn(*mut c_void),
    pub(super) port_event: Option<unsafe extern "C" fn(*mut c_void, u32, u32, u32, *const c_void)>,
    pub(super) extension_data: Option<unsafe extern "C" fn(*const c_char) -> *const c_void>,
}

pub(super) type WriteFn = unsafe extern "C" fn(*mut c_void, u32, u32, u32, *const c_void);

#[repr(C)]
pub(super) struct UiResize {
    pub(super) handle: *mut c_void,
    pub(super) ui_resize: unsafe extern "C" fn(*mut c_void, i32, i32) -> i32,
}

#[repr(C)]
pub(super) struct UiPortMap {
    pub(super) handle: *mut c_void,
    pub(super) port_index: unsafe extern "C" fn(*mut c_void, *const c_char) -> u32,
}

/// The editor wrote to a port: a control value, or a message for an atom port.
pub(super) unsafe extern "C" fn ui_write(
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

pub(super) unsafe extern "C" fn ui_resize(link: *mut c_void, width: i32, height: i32) -> i32 {
    let link = unsafe { &*(link as *const UiLink) };
    link.resize
        .set(Some((width.max(1) as u32, height.max(1) as u32)));
    0
}

pub(super) unsafe extern "C" fn ui_port_index(link: *mut c_void, symbol: *const c_char) -> u32 {
    unsafe {
        let link = &*(link as *const UiLink);
        link.shared
            .port_symbols
            .get(CStr::from_ptr(symbol))
            .copied()
            .unwrap_or(u32::MAX)
    }
}

pub(super) const UI: &str = "http://lv2plug.in/ns/extensions/ui#";
pub(super) const EXTERNAL_UI: &CStr = c"http://kxstudio.sf.net/ns/lv2ext/external-ui#Widget";
pub(super) const EXTERNAL_HOST: &CStr = c"http://kxstudio.sf.net/ns/lv2ext/external-ui#Host";
pub(super) const SHOW_INTERFACE: &CStr = c"http://lv2plug.in/ns/extensions/ui#showInterface";
pub(super) const IDLE_INTERFACE: &CStr = c"http://lv2plug.in/ns/extensions/ui#idleInterface";

/// The best editor the plugin offers that this host can show.
///
/// A plugin may ship several editors. An X11 one is embedded in a window of
/// ours. Editors in other toolkits are used when they can open a window of
/// their own, which is what `ui:showInterface` and the older "external UI"
/// are for: the toolkit then runs inside the editor's library and this host
/// links none of them. A bare Gtk widget is put in a Gtk window here.
pub(super) unsafe fn find_ui(plugin: *const LilvPlugin) -> Option<UiInfo> {
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
pub(super) struct ExternalWidget {
    pub(super) run: unsafe extern "C" fn(*mut ExternalWidget),
    pub(super) show: unsafe extern "C" fn(*mut ExternalWidget),
    pub(super) hide: unsafe extern "C" fn(*mut ExternalWidget),
}

#[repr(C)]
pub(super) struct ExternalHost {
    pub(super) ui_closed: unsafe extern "C" fn(*mut c_void),
    pub(super) plugin_human_id: *const c_char,
}

pub(super) unsafe extern "C" fn ui_closed(link: *mut c_void) {
    unsafe { &*(link as *const UiLink) }.closed.set(true);
}

#[repr(C)]
pub(super) struct ShowInterface {
    pub(super) show: unsafe extern "C" fn(*mut c_void) -> i32,
    pub(super) hide: unsafe extern "C" fn(*mut c_void) -> i32,
}

/// Lets an editor reach the plugin's own extension data.
#[repr(C)]
pub(super) struct DataAccess {
    pub(super) data_access: unsafe extern "C" fn(*const c_char) -> *const c_void,
}

/// Where an open editor is drawn.
pub(super) enum Surface {
    Embedded(HostWindow),
    /// The editor's own window.
    Own(*const ShowInterface),
    External(*mut ExternalWidget),
    Gtk(GtkWindow),
}

/// An open editor.
pub(super) struct Ui {
    pub(super) descriptor: *const UiDescriptor,
    pub(super) handle: *mut c_void,
    pub(super) idle: Option<unsafe extern "C" fn(*mut c_void) -> i32>,
    pub(super) surface: Surface,
    /// The last value shown for each control port, to send only what changed.
    pub(super) shown: Vec<f32>,
    // What the editor was handed at instantiation and may still point to.
    pub(super) _features: Vec<Feature>,
    pub(super) _feature_list: Vec<*const Feature>,
    pub(super) _resize: Box<UiResize>,
    pub(super) _port_map: Box<UiPortMap>,
    pub(super) _external: Box<ExternalHost>,
    pub(super) _data_access: Option<Box<DataAccess>>,
    pub(super) _options: Vec<OptionsOption>,
    pub(super) _scale: Box<f32>,
    pub(super) _title: CString,
}

