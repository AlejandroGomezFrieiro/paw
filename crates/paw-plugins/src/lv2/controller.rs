//! The main thread's half of an LV2 plugin: parameters, state, editor.

use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char, c_void};
use std::ptr;
use std::sync::atomic::Ordering::Relaxed;
use std::sync::Arc;

use anyhow::{Context, Result, anyhow, bail};
use paw_engine::device::Change;
use paw_engine::{Controller, ParamInfo, Ports};
use lilv_sys::*;

use crate::echo::Echo;
use crate::lv2_patch::{self, Kind, Property};
use crate::window::{GtkWindow, HostWindow, WindowEvent, ui_scale};
use super::*;
use super::urid::*;
use super::world::*;
use super::worker::*;
use super::shared::*;
use super::device::*;
use super::ui::*;

pub(super) struct Lv2Controller {
    pub(super) shared: Arc<Shared>,
    pub(super) link: Box<UiLink>,
    pub(super) from_plugin: rtrb::Consumer<u8>,
    pub(super) message: Vec<u8>,
    pub(super) ui: Option<Ui>,
    pub(super) ports: Ports,
    /// The value of each property the plugin told (by URID), or that was
    /// set from here.
    pub(super) values: HashMap<u32, serde_json::Value>,
    /// Tells the echo of a state from an edit. The editor writes a control
    /// with no gesture (paw offers no `ui:touch`): a value that a state
    /// gave is its echo, another value an edit.
    pub(super) echo: Echo,
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

    pub(super) fn ask_properties(&mut self) {
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
pub(super) unsafe fn find_properties(plugin: *const LilvPlugin, w: &World) -> Vec<Property> {
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

