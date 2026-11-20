//! The CLAP plugin: `dev.paw.sampler`.
//!
//! Notes come in as MIDI 2.0 (preferred, so that each note's attribute
//! arrives with it) or MIDI 1.0; sound goes out on one stereo port. An
//! instrument is loaded from its file on the main thread (preset-load,
//! state) and handed to the audio thread through an atomic slot; the
//! program it replaces comes back the same way to be dropped on the main
//! thread, so the audio thread never frees memory.

use crate::audio::Store;
use crate::engine::{Attr, Engine, Program};
use crate::error::FormatError;
use crate::{describe, formats, params};
use clap_sys::events::*;
use clap_sys::ext::audio_ports::*;
use clap_sys::ext::note_name::*;
use clap_sys::ext::note_ports::*;
use clap_sys::ext::params::*;
use clap_sys::ext::preset_load::*;
use clap_sys::ext::state::*;
use clap_sys::factory::plugin_factory::*;
use clap_sys::factory::preset_discovery::CLAP_PRESET_DISCOVERY_LOCATION_FILE;
use clap_sys::host::clap_host;
use clap_sys::id::{CLAP_INVALID_ID, clap_id};
use clap_sys::plugin::*;
use clap_sys::plugin_features::*;
use clap_sys::process::*;
use clap_sys::stream::*;
use clap_sys::version::CLAP_VERSION;
use std::cell::UnsafeCell;
use std::ffi::{CStr, c_char, c_void};
use std::path::Path;
use std::ptr::{self, null, null_mut};
use std::sync::Arc;
use std::sync::atomic::{AtomicPtr, AtomicU64, Ordering::*};

pub const PLUGIN_ID: &CStr = c"dev.paw.sampler";

/// paw's extension for asking a plugin things by name: `device_call(id,
/// method, data)` reaches it for any method the host does not know. The
/// answer is written through `write`, in as many pieces as wanted;
/// false means the method failed, and what was written says why.
pub const PAW_EXT_CALL: &CStr = c"dev.paw.call/1";

#[repr(C)]
pub struct paw_plugin_call {
    pub call: Option<
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

struct Features([*const c_char; 4]);
// SAFETY: the pointers are to `'static` C string literals and are never written.
unsafe impl Sync for Features {}

static FEATURES: Features = Features([
    CLAP_PLUGIN_FEATURE_INSTRUMENT.as_ptr(),
    CLAP_PLUGIN_FEATURE_SAMPLER.as_ptr(),
    CLAP_PLUGIN_FEATURE_STEREO.as_ptr(),
    null(),
]);

static DESCRIPTOR: clap_plugin_descriptor = clap_plugin_descriptor {
    clap_version: CLAP_VERSION,
    id: PLUGIN_ID.as_ptr(),
    name: c"paw sampler".as_ptr(),
    vendor: c"paw".as_ptr(),
    url: c"".as_ptr(),
    manual_url: c"".as_ptr(),
    support_url: c"".as_ptr(),
    version: c"0.1.0".as_ptr(),
    description: c"Plays SFZ and Decent Sampler instruments, articulations by MIDI 2.0 note attribute or keyswitch".as_ptr(),
    features: FEATURES.0.as_ptr(),
};

/// What only the main thread touches.
struct Main {
    store: Store,
    program: Option<Arc<Program>>,
    path: String,
    error: Option<String>,
    /// Key names for `note-name`: keyswitches and labelled keys.
    names: Vec<(u8, String)>,
    active: bool,
}

type Slot = AtomicPtr<Option<Arc<Program>>>;

struct Plugin {
    clap: clap_plugin,
    host: *const clap_host,
    main: UnsafeCell<Main>,
    engine: UnsafeCell<Option<Engine>>,
    values: Vec<AtomicU64>,
    /// A program waiting for the audio thread.
    incoming: Slot,
    /// Programs the audio thread let go of, for the main thread to drop.
    retired: [Slot; 8],
}

// SAFETY: the host calls into one plugin from the main thread and the audio thread only. Each of
// the `UnsafeCell`s has one of them as its user, `values` and the slots are atomic, and `host` is
// only read.
unsafe impl Sync for Plugin {}

/// The plugin behind the host's `clap_plugin`.
///
/// # Safety
///
/// `plugin` must be the pointer that `factory_create` returned, and the
/// plugin must not be destroyed while the result is in use.
unsafe fn this<'a>(plugin: *const clap_plugin) -> &'a Plugin {
    // SAFETY: the host passes the `clap_plugin` that `factory_create` returned, and its
    // `plugin_data` points at the boxed `Plugin` until `destroy`.
    unsafe { &*((*plugin).plugin_data as *const Plugin) }
}

impl Plugin {
    #[allow(clippy::mut_from_ref)]
    fn main(&self) -> &mut Main {
        // SAFETY: `Main` is used by the main thread only, one call at a time, as CLAP requires of
        // every function that is not `process`.
        unsafe { &mut *self.main.get() }
    }

    #[allow(clippy::mut_from_ref)]
    fn engine(&self) -> &mut Option<Engine> {
        // SAFETY: the engine is made and dropped by `activate` and `deactivate` on the main thread
        // while the plugin does not process, and used by `process` and `reset` on the audio thread
        // otherwise: CLAP never runs them together.
        unsafe { &mut *self.engine.get() }
    }

    fn value(&self, index: usize) -> f64 {
        f64::from_bits(self.values[index].load(Relaxed))
    }

    fn set_value(&self, index: usize, value: f64) {
        let p = &params::PARAMS[index];
        self.values[index].store(value.clamp(p.min, p.max).to_bits(), Relaxed);
    }

    fn values(&self) -> Vec<f64> {
        (0..self.values.len()).map(|i| self.value(i)).collect()
    }

    /// # Safety
    ///
    /// `T` must be the table that the host gives for `id`.
    unsafe fn host_extension<T>(&self, id: &CStr) -> Option<&T> {
        // SAFETY: the host's `get_extension` returns null or a pointer to a table that stays valid
        // as long as the host does.
        unsafe {
            let get = (*self.host).get_extension?;
            (get(self.host, id.as_ptr()) as *const T).as_ref()
        }
    }

    /// Reads an instrument and makes it the one played.
    fn load(&self, path: &str) -> Result<(), FormatError> {
        let main = self.main();
        main.path = path.to_string();
        let instrument = match formats::read(Path::new(path)) {
            Ok(i) => i,
            Err(e) => {
                main.error = Some(e.to_string());
                return Err(e);
            }
        };
        let program = Arc::new(Program::new(instrument, &mut main.store));
        main.error = None;
        let inst = &program.instrument;
        let mut names: Vec<(u8, String)> =
            inst.articulations.iter().filter_map(|a| a.keyswitch.map(|k| (k, a.name.clone()))).collect();
        for (k, name) in &inst.key_labels {
            if !names.iter().any(|n| n.0 == *k) {
                names.push((*k, name.clone()));
            }
        }
        names.sort_by_key(|n| n.0);
        main.names = names;
        main.program = Some(program.clone());
        self.hand_over(Some(program));
        // SAFETY: called on the main thread, where the host's `changed` callback is allowed.
        unsafe {
            if let Some(h) = self.host_extension::<clap_host_note_name>(CLAP_EXT_NOTE_NAME)
                && let Some(changed) = h.changed
            {
                changed(self.host);
            }
        }
        Ok(())
    }

    fn hand_over(&self, program: Option<Arc<Program>>) {
        self.collect();
        if !self.main().active {
            return;
        }
        let new = Box::into_raw(Box::new(program));
        let old = self.incoming.swap(new, AcqRel);
        if !old.is_null() {
            // Never taken: the audio thread has not seen it.
            // SAFETY: `old` came from `Box::into_raw` and the swap took it out of its slot, so
            // nothing else owns it. The audio thread has never seen it.
            drop(unsafe { Box::from_raw(old) });
        }
    }

    /// Drops what the audio thread gave back.
    fn collect(&self) {
        for slot in &self.retired {
            let p = slot.swap(null_mut(), AcqRel);
            if !p.is_null() {
                // SAFETY: the audio thread put the pointer there from `Box::into_raw`, and the swap
                // took it out of the slot, so nothing else owns it.
                drop(unsafe { Box::from_raw(p) });
            }
        }
    }
}

// --- the plugin's functions --------------------------------------------------

unsafe extern "C" fn init(_: *const clap_plugin) -> bool {
    true
}

unsafe extern "C" fn destroy(plugin: *const clap_plugin) {
    // SAFETY: `plugin_data` is the `Box::into_raw` of `factory_create`, and CLAP calls `destroy`
    // once, with no other call running.
    unsafe {
        let p = (*plugin).plugin_data as *mut Plugin;
        let p = Box::from_raw(p);
        let incoming = p.incoming.swap(null_mut(), AcqRel);
        if !incoming.is_null() {
            drop(Box::from_raw(incoming));
        }
        p.collect();
    }
}

unsafe extern "C" fn activate(plugin: *const clap_plugin, sample_rate: f64, _: u32, _: u32) -> bool {
    // SAFETY: the host passes the `clap_plugin` that `factory_create` returned, and its
    // `plugin_data` points at the boxed `Plugin` until `destroy`.
    let p = unsafe { this(plugin) };
    let mut engine = Engine::new(sample_rate);
    engine.settings = params::settings(&p.values());
    engine.swap(p.main().program.clone());
    *p.engine() = Some(engine);
    let incoming = p.incoming.swap(null_mut(), AcqRel);
    if !incoming.is_null() {
        // SAFETY: the pointer came from `Box::into_raw` and the swap took it out of its slot, so
        // nothing else owns it.
        drop(unsafe { Box::from_raw(incoming) });
    }
    p.main().active = true;
    true
}

unsafe extern "C" fn deactivate(plugin: *const clap_plugin) {
    // SAFETY: the host passes the `clap_plugin` that `factory_create` returned, and its
    // `plugin_data` points at the boxed `Plugin` until `destroy`.
    let p = unsafe { this(plugin) };
    p.main().active = false;
    *p.engine() = None;
    let incoming = p.incoming.swap(null_mut(), AcqRel);
    if !incoming.is_null() {
        // SAFETY: the pointer came from `Box::into_raw` and the swap took it out of its slot, so
        // nothing else owns it.
        drop(unsafe { Box::from_raw(incoming) });
    }
    p.collect();
}

unsafe extern "C" fn start_processing(_: *const clap_plugin) -> bool {
    true
}

unsafe extern "C" fn stop_processing(_: *const clap_plugin) {}

unsafe extern "C" fn reset(plugin: *const clap_plugin) {
    // SAFETY: the host passes the `clap_plugin` that `factory_create` returned, and its
    // `plugin_data` points at the boxed `Plugin` until `destroy`.
    if let Some(e) = unsafe { this(plugin) }.engine() {
        e.reset();
    }
}

unsafe extern "C" fn process(plugin: *const clap_plugin, process: *const clap_process) -> clap_process_status {
    // SAFETY: every pointer is the host's for this call: `process`, its events and its buffers.
    // `data32` holds `channel_count` channels of `frames_count` floats, and `incoming` is a pointer
    // that the swap made ours.
    unsafe {
        let p = this(plugin);
        let Some(engine) = p.engine() else { return CLAP_PROCESS_ERROR };
        let process = &*process;

        // A new instrument: play it, give the old one back.
        let incoming = p.incoming.swap(null_mut(), AcqRel);
        if !incoming.is_null() {
            let new = (*incoming).take();
            *incoming = engine.swap(new);
            // With every slot full the old program is kept for good rather
            // than freed here.
            let _ = p.retired.iter().any(|s| s.compare_exchange(null_mut(), incoming, AcqRel, Relaxed).is_ok());
            if let Some(callback) = (*p.host).request_callback {
                callback(p.host);
            }
        }
        engine.settings = params::settings_from(&p.values);

        let frames = process.frames_count as usize;
        if process.audio_outputs_count == 0 || process.audio_outputs.is_null() {
            return CLAP_PROCESS_CONTINUE;
        }
        let out = &*process.audio_outputs;
        if out.data32.is_null() || out.channel_count == 0 {
            return CLAP_PROCESS_CONTINUE;
        }
        let left = std::slice::from_raw_parts_mut(*out.data32, frames);
        let right = if out.channel_count > 1 {
            std::slice::from_raw_parts_mut(*out.data32.add(1), frames)
        } else {
            std::slice::from_raw_parts_mut(*out.data32, frames)
        };
        left.fill(0.0);
        right.fill(0.0);

        let mut at = 0usize;
        let events = &*process.in_events;
        let count = events.size.map_or(0, |size| size(events));
        for i in 0..count {
            let Some(header) = events.get.map(|get| get(events, i)) else { break };
            let Some(h) = header.as_ref() else { continue };
            if h.space_id != CLAP_CORE_EVENT_SPACE_ID {
                continue;
            }
            let time = (h.time as usize).min(frames);
            if time > at {
                engine.render(&mut left[at..time], &mut right[at..time]);
                at = time;
            }
            handle(p, engine, header);
        }
        if at < frames {
            engine.render(&mut left[at..], &mut right[at..]);
        }
        CLAP_PROCESS_CONTINUE
    }
}

/// One event from the host.
///
/// # Safety
///
/// `header` must point to a whole event of the core space, of the type and
/// size that its header says.
unsafe fn handle(p: &Plugin, engine: &mut Engine, header: *const clap_event_header) {
    // SAFETY: the host's event is of the size that its `type_` says, in the core space (`process`
    // checked the space).
    unsafe {
        match (*header).type_ {
            CLAP_EVENT_NOTE_ON => {
                let e = &*(header as *const clap_event_note);
                engine.note_on(e.key as u8, e.velocity as f32, e.channel.max(0) as u8, None);
            }
            CLAP_EVENT_NOTE_OFF | CLAP_EVENT_NOTE_CHOKE => {
                let e = &*(header as *const clap_event_note);
                engine.note_off(e.key as u8, e.channel.max(0) as u8);
            }
            CLAP_EVENT_MIDI => {
                let e = &*(header as *const clap_event_midi);
                midi1(engine, e.data[0], e.data[1], e.data[2]);
            }
            CLAP_EVENT_MIDI2 => {
                let e = &*(header as *const clap_event_midi2);
                midi2(engine, e.data[0], e.data[1]);
            }
            CLAP_EVENT_PARAM_VALUE => {
                let e = &*(header as *const clap_event_param_value);
                if let Some((i, _)) = params::by_id(e.param_id) {
                    p.set_value(i, e.value);
                    engine.settings = params::settings_from(&p.values);
                }
            }
            _ => {}
        }
    }
}

pub fn midi1(engine: &mut Engine, status: u8, d1: u8, d2: u8) {
    let ch = status & 0x0F;
    match status & 0xF0 {
        0x90 if d2 > 0 => engine.note_on(d1 & 127, d2 as f32 / 127.0, ch, None),
        0x80 | 0x90 => engine.note_off(d1 & 127, ch),
        0xB0 => engine.control(d1, d2 as f32 / 127.0),
        0xE0 => engine.pitch_bend((((d2 as i32) << 7 | d1 as i32) - 8192) as f32 / 8192.0),
        _ => {}
    }
}

/// A Universal MIDI Packet: MIDI 2.0 channel voice messages (with a
/// note-on's attribute), or MIDI 1.0 ones wrapped in UMP.
pub fn midi2(engine: &mut Engine, w0: u32, w1: u32) {
    let kind = w0 >> 28;
    let status = ((w0 >> 20) & 0xF) as u8;
    let ch = ((w0 >> 16) & 0xF) as u8;
    let index = ((w0 >> 8) & 0x7F) as u8;
    match kind {
        2 => midi1(engine, (w0 >> 16) as u8, (w0 >> 8) as u8 & 0x7F, w0 as u8 & 0x7F),
        4 => match status {
            0x9 => {
                let attr_type = w0 as u8;
                let attr: Attr = (attr_type != 0).then_some((attr_type, w1 as u16));
                let vel = (w1 >> 16) as f32 / 65535.0;
                engine.note_on(index, vel.max(1.0 / 65535.0), ch, attr);
            }
            0x8 => engine.note_off(index, ch),
            0xB => engine.control(index, w1 as f32 / u32::MAX as f32),
            0xE => engine.pitch_bend(((w1 as f64 - 2147483648.0) / 2147483648.0) as f32),
            _ => {}
        },
        _ => {}
    }
}

unsafe extern "C" fn on_main_thread(plugin: *const clap_plugin) {
    // SAFETY: the host passes the `clap_plugin` that `factory_create` returned, and its
    // `plugin_data` points at the boxed `Plugin` until `destroy`.
    unsafe { this(plugin) }.collect();
}

unsafe extern "C" fn get_extension(_: *const clap_plugin, id: *const c_char) -> *const c_void {
    // SAFETY: CLAP gives a NUL-terminated string that stays valid for this call.
    let id = unsafe { CStr::from_ptr(id) };
    if id == CLAP_EXT_AUDIO_PORTS {
        &AUDIO_PORTS as *const _ as *const c_void
    } else if id == CLAP_EXT_NOTE_PORTS {
        &NOTE_PORTS as *const _ as *const c_void
    } else if id == CLAP_EXT_PARAMS {
        &PARAMS as *const _ as *const c_void
    } else if id == CLAP_EXT_STATE {
        &STATE as *const _ as *const c_void
    } else if id == CLAP_EXT_PRESET_LOAD || id == CLAP_EXT_PRESET_LOAD_COMPAT {
        &PRESET_LOAD as *const _ as *const c_void
    } else if id == CLAP_EXT_NOTE_NAME {
        &NOTE_NAME as *const _ as *const c_void
    } else if id == PAW_EXT_CALL {
        &CALL as *const _ as *const c_void
    } else {
        null()
    }
}

// --- audio and note ports ----------------------------------------------------

static AUDIO_PORTS: clap_plugin_audio_ports = clap_plugin_audio_ports {
    count: Some(audio_ports_count),
    get: Some(audio_ports_get),
};

unsafe extern "C" fn audio_ports_count(_: *const clap_plugin, is_input: bool) -> u32 {
    if is_input { 0 } else { 1 }
}

unsafe extern "C" fn audio_ports_get(_: *const clap_plugin, index: u32, is_input: bool, info: *mut clap_audio_port_info) -> bool {
    if is_input || index != 0 {
        return false;
    }
    // SAFETY: the host passes a `clap_audio_port_info` to fill.
    unsafe {
        let info = &mut *info;
        info.id = 0;
        write_name(&mut info.name, "Out");
        info.flags = CLAP_AUDIO_PORT_IS_MAIN;
        info.channel_count = 2;
        info.port_type = CLAP_PORT_STEREO.as_ptr();
        info.in_place_pair = CLAP_INVALID_ID;
    }
    true
}

static NOTE_PORTS: clap_plugin_note_ports = clap_plugin_note_ports {
    count: Some(note_ports_count),
    get: Some(note_ports_get),
};

unsafe extern "C" fn note_ports_count(_: *const clap_plugin, is_input: bool) -> u32 {
    if is_input { 1 } else { 0 }
}

unsafe extern "C" fn note_ports_get(_: *const clap_plugin, index: u32, is_input: bool, info: *mut clap_note_port_info) -> bool {
    if !is_input || index != 0 {
        return false;
    }
    // SAFETY: the host passes a `clap_note_port_info` to fill.
    unsafe {
        let info = &mut *info;
        info.id = 0;
        // Not CLAP's own note events: they have no place for a note's
        // MIDI 2.0 attribute.
        info.supported_dialects = CLAP_NOTE_DIALECT_MIDI | CLAP_NOTE_DIALECT_MIDI2;
        info.preferred_dialect = CLAP_NOTE_DIALECT_MIDI2;
        write_name(&mut info.name, "Notes");
    }
    true
}

fn write_name(out: &mut [c_char], text: &str) {
    let bytes = text.as_bytes();
    let n = bytes.len().min(out.len() - 1);
    for (o, &b) in out.iter_mut().zip(&bytes[..n]) {
        *o = b as c_char;
    }
    out[n] = 0;
}

// --- parameters --------------------------------------------------------------

static PARAMS: clap_plugin_params = clap_plugin_params {
    count: Some(params_count),
    get_info: Some(params_get_info),
    get_value: Some(params_get_value),
    value_to_text: Some(params_value_to_text),
    text_to_value: Some(params_text_to_value),
    flush: Some(params_flush),
};

unsafe extern "C" fn params_count(_: *const clap_plugin) -> u32 {
    params::PARAMS.len() as u32
}

unsafe extern "C" fn params_get_info(_: *const clap_plugin, index: u32, info: *mut clap_param_info) -> bool {
    let Some(p) = params::PARAMS.get(index as usize) else { return false };
    // SAFETY: the host passes a `clap_param_info` to fill.
    unsafe {
        let info = &mut *info;
        info.id = p.id;
        info.flags = CLAP_PARAM_IS_AUTOMATABLE | if p.stepped { CLAP_PARAM_IS_STEPPED } else { 0 };
        info.cookie = null_mut();
        write_name(&mut info.name, p.name);
        write_name(&mut info.module, "");
        info.min_value = p.min;
        info.max_value = p.max;
        info.default_value = p.default;
    }
    true
}

unsafe extern "C" fn params_get_value(plugin: *const clap_plugin, id: clap_id, out: *mut f64) -> bool {
    let Some((i, _)) = params::by_id(id) else { return false };
    // SAFETY: the host passes a place for one `f64`.
    unsafe { *out = this(plugin).value(i) };
    true
}

unsafe extern "C" fn params_value_to_text(_: *const clap_plugin, id: clap_id, value: f64, out: *mut c_char, capacity: u32) -> bool {
    let Some((_, p)) = params::by_id(id) else { return false };
    if capacity == 0 {
        return false;
    }
    // SAFETY: the host passes a buffer of `capacity` characters (not zero, checked above).
    let out = unsafe { std::slice::from_raw_parts_mut(out, capacity as usize) };
    write_name(out, &params::to_text(p, value));
    true
}

unsafe extern "C" fn params_text_to_value(_: *const clap_plugin, id: clap_id, text: *const c_char, out: *mut f64) -> bool {
    let Some((_, p)) = params::by_id(id) else { return false };
    // SAFETY: CLAP gives a NUL-terminated string that stays valid for this call.
    let text = unsafe { CStr::from_ptr(text) }.to_string_lossy();
    match params::from_text(p, &text) {
        Some(v) => {
            // SAFETY: the host passes a place for one `f64`.
            unsafe { *out = v };
            true
        }
        None => false,
    }
}

unsafe extern "C" fn params_flush(plugin: *const clap_plugin, events: *const clap_input_events, _: *const clap_output_events) {
    // SAFETY: the host's input events are valid for this call, and `get` gives a header for each
    // index below `size`.
    unsafe {
        let p = this(plugin);
        let events = &*events;
        let count = events.size.map_or(0, |size| size(events));
        for i in 0..count {
            let Some(header) = events.get.map(|get| get(events, i)) else { break };
            if header.is_null() || (*header).space_id != CLAP_CORE_EVENT_SPACE_ID || (*header).type_ != CLAP_EVENT_PARAM_VALUE {
                continue;
            }
            let e = &*(header as *const clap_event_param_value);
            if let Some((i, _)) = params::by_id(e.param_id) {
                p.set_value(i, e.value);
            }
        }
    }
}

// --- state and presets -------------------------------------------------------

static STATE: clap_plugin_state = clap_plugin_state { save: Some(state_save), load: Some(state_load) };

/// The state is small JSON: the instrument's path and the parameters.
unsafe extern "C" fn state_save(plugin: *const clap_plugin, stream: *const clap_ostream) -> bool {
    // SAFETY: the host passes the `clap_plugin` that `factory_create` returned, and its
    // `plugin_data` points at the boxed `Plugin` until `destroy`.
    let p = unsafe { this(plugin) };
    let mut values = serde_json::Map::new();
    for (i, param) in params::PARAMS.iter().enumerate() {
        values.insert(param.key.to_string(), serde_json::json!(p.value(i)));
    }
    let state = serde_json::json!({ "version": 1, "instrument": p.main().path, "params": values });
    let bytes = state.to_string().into_bytes();
    let mut done = 0;
    // SAFETY: the host's stream and its `write` are valid for this call.
    unsafe {
        let Some(write) = (*stream).write else { return false };
        while done < bytes.len() {
            let n = write(stream, bytes[done..].as_ptr() as *const c_void, (bytes.len() - done) as u64);
            if n <= 0 {
                return false;
            }
            done += n as usize;
        }
    }
    true
}

unsafe extern "C" fn state_load(plugin: *const clap_plugin, stream: *const clap_istream) -> bool {
    // SAFETY: the host passes the `clap_plugin` that `factory_create` returned, and its
    // `plugin_data` points at the boxed `Plugin` until `destroy`.
    let p = unsafe { this(plugin) };
    let mut bytes = Vec::new();
    // SAFETY: the host's stream and its `read` are valid for this call, and `read` fills at most
    // the buffer's length.
    unsafe {
        let Some(read) = (*stream).read else { return false };
        let mut buffer = [0u8; 4096];
        loop {
            let n = read(stream, buffer.as_mut_ptr() as *mut c_void, buffer.len() as u64);
            if n <= 0 {
                break;
            }
            bytes.extend_from_slice(&buffer[..n as usize]);
        }
    }
    let Ok(state) = serde_json::from_slice::<serde_json::Value>(&bytes) else { return false };
    if let Some(values) = state["params"].as_object() {
        for (key, v) in values {
            if let (Some((i, _)), Some(v)) = (params::by_key(key), v.as_f64()) {
                p.set_value(i, v);
            }
        }
    }
    let path = state["instrument"].as_str().unwrap_or("");
    if path.is_empty() {
        p.main().path.clear();
        p.main().program = None;
        p.hand_over(None);
    } else {
        // A missing library keeps its path, to play where it is found.
        let _ = p.load(path);
    }
    true
}

static PRESET_LOAD: clap_plugin_preset_load = clap_plugin_preset_load { from_location: Some(preset_from_location) };

unsafe extern "C" fn preset_from_location(plugin: *const clap_plugin, kind: u32, location: *const c_char, _key: *const c_char) -> bool {
    // SAFETY: the host passes the `clap_plugin` that `factory_create` returned, and its
    // `plugin_data` points at the boxed `Plugin` until `destroy`.
    let p = unsafe { this(plugin) };
    if kind != CLAP_PRESET_DISCOVERY_LOCATION_FILE || location.is_null() {
        return false;
    }
    // SAFETY: CLAP gives a NUL-terminated string that stays valid for this call. A null `location`
    // returned above.
    let path = unsafe { CStr::from_ptr(location) }.to_string_lossy().into_owned();
    let result = p.load(&path);
    // SAFETY: the host and its extensions are valid for this call, and `location` is passed back as
    // it came.
    unsafe {
        if let Some(h) = p.host_extension::<clap_host_preset_load>(CLAP_EXT_PRESET_LOAD) {
            match &result {
                Ok(()) => {
                    if let Some(loaded) = h.loaded {
                        loaded(p.host, kind, location, null());
                    }
                }
                Err(e) => {
                    if let Some(on_error) = h.on_error {
                        let msg = std::ffi::CString::new(e.to_string().replace('\0', " ")).unwrap_or_default();
                        on_error(p.host, kind, location, null(), 0, msg.as_ptr());
                    }
                }
            }
        }
        if let Some(h) = p.host_extension::<clap_host_state>(CLAP_EXT_STATE)
            && let Some(dirty) = h.mark_dirty
        {
            dirty(p.host);
        }
    }
    result.is_ok()
}

// --- key names ---------------------------------------------------------------

static NOTE_NAME: clap_plugin_note_name = clap_plugin_note_name { count: Some(note_name_count), get: Some(note_name_get) };

unsafe extern "C" fn note_name_count(plugin: *const clap_plugin) -> u32 {
    // SAFETY: the host passes the `clap_plugin` that `factory_create` returned, and its
    // `plugin_data` points at the boxed `Plugin` until `destroy`.
    unsafe { this(plugin) }.main().names.len() as u32
}

unsafe extern "C" fn note_name_get(plugin: *const clap_plugin, index: u32, out: *mut clap_note_name) -> bool {
    // SAFETY: the host passes the `clap_plugin` that `factory_create` returned, and its
    // `plugin_data` points at the boxed `Plugin` until `destroy`.
    let p = unsafe { this(plugin) };
    let Some((key, name)) = p.main().names.get(index as usize) else { return false };
    // SAFETY: the host passes a `clap_note_name` to fill.
    unsafe {
        let out = &mut *out;
        write_name(&mut out.name, name);
        out.port = -1;
        out.key = *key as i16;
        out.channel = -1;
    }
    true
}

// --- paw's calls -------------------------------------------------------------

static CALL: paw_plugin_call = paw_plugin_call { call: Some(call) };

unsafe extern "C" fn call(
    plugin: *const clap_plugin,
    method: *const c_char,
    _data: *const u8,
    _size: usize,
    out: *mut c_void,
    write: Option<unsafe extern "C" fn(out: *mut c_void, data: *const u8, size: usize)>,
) -> bool {
    // SAFETY: the host passes the `clap_plugin` that `factory_create` returned, and its
    // `plugin_data` points at the boxed `Plugin` until `destroy`.
    let p = unsafe { this(plugin) };
    // SAFETY: CLAP gives a NUL-terminated string that stays valid for this call.
    let method = unsafe { CStr::from_ptr(method) }.to_string_lossy();
    let (ok, answer) = match method.as_ref() {
        "describe" => {
            let main = p.main();
            (true, describe::describe(main.program.as_deref(), &main.path, main.error.as_deref(), &p.values()).to_string())
        }
        _ => (false, format!("the sampler has no method `{method}`")),
    };
    if let Some(write) = write {
        // SAFETY: `write` is the host's, and `answer` lives past the call.
        unsafe { write(out, answer.as_ptr(), answer.len()) };
    }
    ok
}

// --- the factory and the entry -----------------------------------------------

static FACTORY: clap_plugin_factory = clap_plugin_factory {
    get_plugin_count: Some(factory_count),
    get_plugin_descriptor: Some(factory_descriptor),
    create_plugin: Some(factory_create),
};

unsafe extern "C" fn factory_count(_: *const clap_plugin_factory) -> u32 {
    1
}

unsafe extern "C" fn factory_descriptor(_: *const clap_plugin_factory, index: u32) -> *const clap_plugin_descriptor {
    if index == 0 { &DESCRIPTOR } else { null() }
}

unsafe extern "C" fn factory_create(_: *const clap_plugin_factory, host: *const clap_host, id: *const c_char) -> *const clap_plugin {
    // SAFETY: CLAP gives a NUL-terminated string that stays valid for this call. A null `id`
    // returned above.
    if id.is_null() || unsafe { CStr::from_ptr(id) } != PLUGIN_ID {
        return null();
    }
    let plugin = Box::new(Plugin {
        clap: clap_plugin {
            desc: &DESCRIPTOR,
            plugin_data: null_mut(),
            init: Some(init),
            destroy: Some(destroy),
            activate: Some(activate),
            deactivate: Some(deactivate),
            start_processing: Some(start_processing),
            stop_processing: Some(stop_processing),
            reset: Some(reset),
            process: Some(process),
            get_extension: Some(get_extension),
            on_main_thread: Some(on_main_thread),
        },
        host,
        main: UnsafeCell::new(Main {
            store: Store::default(),
            program: None,
            path: String::new(),
            error: None,
            names: Vec::new(),
            active: false,
        }),
        engine: UnsafeCell::new(None),
        values: params::PARAMS.iter().map(|p| AtomicU64::new(p.default.to_bits())).collect(),
        incoming: AtomicPtr::new(null_mut()),
        retired: Default::default(),
    });
    let plugin = Box::into_raw(plugin);
    // SAFETY: `plugin` is the box just made, and nothing else holds it yet.
    unsafe {
        (*plugin).clap.plugin_data = plugin as *mut c_void;
        ptr::addr_of!((*plugin).clap)
    }
}

unsafe extern "C" fn entry_init(_: *const c_char) -> bool {
    true
}

unsafe extern "C" fn entry_deinit() {}

unsafe extern "C" fn entry_get_factory(id: *const c_char) -> *const c_void {
    // SAFETY: CLAP gives a NUL-terminated string that stays valid for this call. A null `id` is
    // checked first.
    if !id.is_null() && unsafe { CStr::from_ptr(id) } == CLAP_PLUGIN_FACTORY_ID {
        &FACTORY as *const _ as *const c_void
    } else {
        null()
    }
}

// SAFETY: `clap_entry` is the symbol that CLAP hosts look up by name, and
// nothing else in the library has it.
#[unsafe(no_mangle)]
#[allow(non_upper_case_globals)]
pub static clap_entry: clap_sys::entry::clap_plugin_entry = clap_sys::entry::clap_plugin_entry {
    clap_version: CLAP_VERSION,
    init: Some(entry_init),
    deinit: Some(entry_deinit),
    get_factory: Some(entry_get_factory),
};
