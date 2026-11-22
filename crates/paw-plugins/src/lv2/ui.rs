//! The plugin's own editor: finding it, the host features it needs, its ports.

use std::cell::{Cell, RefCell, UnsafeCell};
use std::ffi::{CStr, CString, c_char, c_void};
use std::path::PathBuf;
use std::ptr;
use std::sync::Arc;

use anyhow::{Context, Result, anyhow};
use lilv_sys::*;

use crate::window::{GtkWindow, HostWindow, ui_scale};
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

type WriteFn = unsafe extern "C" fn(*mut c_void, u32, u32, u32, *const c_void);

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
    // SAFETY: lv2 calls this with the `link` handle given at instantiation (a pointer to the Box<UiLink>
    // that the controller owns and keeps alive until `cleanup`), and a `buffer` of `size` readable
    // bytes for the protocol, on the main thread, which is where `to_plugin` and `changes` are used.
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
    // SAFETY: `link` is the `*const UiLink` handed to the editor in `open_editor`, kept alive by the
    // controller until the editor's `cleanup` has run.
    let link = unsafe { &*(link as *const UiLink) };
    link.resize
        .set(Some((width.max(1) as u32, height.max(1) as u32)));
    0
}

pub(super) unsafe extern "C" fn ui_port_index(link: *mut c_void, symbol: *const c_char) -> u32 {
    // SAFETY: `link` is the `*const UiLink` handed to the editor (see above); `symbol` is a
    // NUL-terminated string the editor owns for the call.
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
    // SAFETY: lilv objects (`plugin`, `w.world`, the nodes made here, the list of UIs) are live for the
    // block, and every node made here is freed before it ends. Main thread only.
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
    // SAFETY: `link` is the `*const UiLink` that the controller gave the editor as the host handle; it is
    // alive until `cleanup`, and the editor calls on the main thread.
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
    /// What the editor was handed at instantiation and may still point to.
    pub(super) _features: UiFeatures,
}

/// The host features an editor is handed at instantiation. Each pointer in
/// them leads into a box, a vector's buffer or a string of this struct, so
/// they stay good when it moves; it lives as long as the editor.
pub(super) struct UiFeatures {
    _features: Vec<Feature>,
    /// Pointers to `features`, ended by a null pointer.
    feature_list: Vec<*const Feature>,
    _resize: Box<UiResize>,
    _port_map: Box<UiPortMap>,
    _external: Box<ExternalHost>,
    _data_access: Option<Box<DataAccess>>,
    _options: Vec<OptionsOption>,
    _scale: Box<f32>,
    /// The editor's window title.
    pub(super) title: CString,
}

impl UiFeatures {
    /// The features for an editor of `shared`'s plugin: `link` is the
    /// controller's `UiLink`, and `window` the window to embed the editor in,
    /// if any.
    ///
    /// # Safety
    ///
    /// `shared.instance` is a live instance, and `link` points to a `UiLink`
    /// that lives as long as the editor. Main thread.
    pub(super) unsafe fn new(
        shared: &Shared,
        link: *mut c_void,
        title: CString,
        window: Option<&HostWindow>,
    ) -> Self {
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
        // SAFETY: `shared.instance` is live (see `# Safety`), and so is its descriptor; the
        // transmute only marks the plugin's own `extension_data` function as unsafe to call.
        let (handle, mut data_access) = unsafe {
            (
                lilv_instance_get_handle(shared.instance),
                (*(*shared.instance).lv2_descriptor).extension_data.map(|get| {
                    Box::new(DataAccess {
                        data_access: std::mem::transmute::<
                            extern "C" fn(*const c_char) -> *const c_void,
                            unsafe extern "C" fn(*const c_char) -> *const c_void,
                        >(get),
                    })
                }),
            )
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
            feature(c"http://lv2plug.in/ns/ext/instance-access", handle.cast()),
            feature(
                EXTERNAL_HOST,
                &mut *external as *mut ExternalHost as *mut c_void,
            ),
        ];
        if let Some(window) = window {
            features.push(feature(
                c"http://lv2plug.in/ns/extensions/ui#parent",
                window.id() as usize as *mut c_void,
            ));
        }
        // Some editors read the plugin's extension data directly.
        if let Some(access) = data_access.as_mut() {
            features.push(feature(
                c"http://lv2plug.in/ns/ext/data-access",
                &mut **access as *mut DataAccess as *mut c_void,
            ));
        }
        let mut feature_list: Vec<*const Feature> =
            features.iter().map(|f| f as *const Feature).collect();
        feature_list.push(ptr::null());
        Self {
            _features: features,
            feature_list,
            _resize: resize,
            _port_map: port_map,
            _external: external,
            _data_access: data_access,
            _options: options,
            _scale: scale,
            title,
        }
    }

    /// The null-terminated list of the features, as `instantiate` takes it.
    pub(super) fn list(&self) -> *const *const Feature {
        self.feature_list.as_ptr()
    }
}

/// Load the editor's library, and find the editor in it.
///
/// # Safety
///
/// `info` names an LV2 editor library. Main thread.
pub(super) unsafe fn ui_descriptor(info: &UiInfo) -> Result<*const UiDescriptor> {
    // SAFETY: The editor library is opened by `open_library` and never unloaded, so the descriptor
    // and everything it points to stay valid; `lv2ui_descriptor` has the signature given by the
    // LV2 UI spec.
    unsafe {
        // Never unloaded, like the plugins themselves.
        let lib = std::mem::ManuallyDrop::new(libloading::Library::from(
            crate::libs::open_library(&info.binary)
                .with_context(|| format!("loading {}", info.binary.display()))?,
        ));
        let get = lib
            .get::<unsafe extern "C" fn(u32) -> *const UiDescriptor>(b"lv2ui_descriptor\0")
            .context("not an LV2 editor")?;
        (0..)
            .map(|index| get(index))
            .take_while(|d| !d.is_null())
            .find(|d| CStr::from_ptr((**d).uri) == info.uri.as_c_str())
            .context("the editor is not in its library")
    }
}

/// The editor's extension data with this URI, or null.
///
/// # Safety
///
/// `descriptor` is a live editor descriptor.
pub(super) unsafe fn ui_extension(descriptor: *const UiDescriptor, uri: &CStr) -> *const c_void {
    // SAFETY: `descriptor` is live (see `# Safety`), and its `extension_data` takes a URI.
    unsafe {
        (*descriptor)
            .extension_data
            .map_or(ptr::null(), |data| data(uri.as_ptr()))
    }
}

/// Put an editor that was just made on screen, the way its kind shows:
/// in `window`, fit to its size (`resize` holds the size it asked for), or
/// in a window of its own.
///
/// # Safety
///
/// `descriptor`, `handle` and `widget` are those of an editor just made
/// by `instantiate`, and not cleaned up. Main thread.
pub(super) unsafe fn show_editor(
    kind: UiKind,
    window: Option<HostWindow>,
    descriptor: *const UiDescriptor,
    handle: *mut c_void,
    widget: *mut c_void,
    resize: &Cell<Option<(u32, u32)>>,
    title: &CStr,
) -> Result<Surface> {
    // SAFETY: The editor's pointers are live (see `# Safety`); an external widget is the
    // `ExternalWidget` that the editor made, and a show interface is the one it gives.
    unsafe {
        match (kind, window) {
            (UiKind::X11, Some(mut window)) => {
                // Fit the window to the editor: what it asked for, else what it made.
                if let Some((width, height)) =
                    resize.take().or_else(|| window.child_size(widget as usize as u32))
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
                match (ui_extension(descriptor, SHOW_INTERFACE) as *const ShowInterface).as_ref() {
                    Some(show) => {
                        (show.show)(handle);
                        Ok(Surface::Own(show))
                    }
                    None => Err(anyhow!("the editor does not say how to show itself")),
                }
            }
            (UiKind::Gtk, _) => GtkWindow::wrap(widget, title).map(Surface::Gtk),
            _ => Err(anyhow!("the editor gave back no window")),
        }
    }
}

