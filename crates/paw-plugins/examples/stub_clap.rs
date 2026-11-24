//! A CLAP instrument for tests, built as `libstub_clap.so` by `cargo test
//! -p paw-plugins` (or `cargo build --example stub_clap`). It takes notes as
//! MIDI 2.0 (its preferred dialect), names two of its keys (`note-name`),
//! keeps the last note-on it was given for the test to read
//! (`stub_clap_last`), and while a note sounds puts out the note-on's
//! attribute: its type / 256 on the left, its subclass / 16 on the right.
//! Its state is one number, which it takes on in its next block, as some
//! plugins do (Surge XT): `stub_clap_state` reads the number it plays with.
//! The number is its one parameter too: it tells of the state it took on
//! with no gesture (its echo, as Surge XT does). In its next block, the
//! call `stub.move` makes it tell of a value inside a gesture (a person
//! moves the parameter in its window), and `stub.tell` with no gesture.
//! `stub.quiet 1` makes it tell nothing of a state it takes on: the host
//! reads its value back. `stub.hold 1` makes its next block wait, after it
//! looked for a state to take on, until `stub_clap_release`
//! (`stub_clap_held` says that it waits): a state given then comes while
//! a block is under way. `stub.restart` makes it ask the host for a
//! restart (`request_restart`), and `stub.activations` answers how many
//! times this instance was activated. `stub.move` and `stub.tell` ask the
//! host for a block (`request_process`), as a plugin that changes by
//! itself does. It takes the render mode (`clap.render`), and
//! `stub.render` answers the mode of its first block and the mode it has
//! now, each `none` (never set), `realtime` or `offline`, or `no-block`.

#![expect(clippy::unwrap_used, reason = "the stub plugin of the tests: a failed unwrap is a failed test")]

use std::ffi::{CStr, c_char, c_void};
use std::sync::atomic::{AtomicU32, Ordering::Relaxed, Ordering::SeqCst};

use clap_sys::events::{
    CLAP_CORE_EVENT_SPACE_ID, CLAP_EVENT_PARAM_GESTURE_BEGIN, CLAP_EVENT_PARAM_GESTURE_END,
    CLAP_EVENT_PARAM_VALUE, clap_event_param_gesture, clap_event_param_value, clap_output_events,
};
use clap_sys::ext::params::{
    CLAP_EXT_PARAMS, CLAP_PARAM_IS_AUTOMATABLE, clap_param_info, clap_plugin_params,
};

use clap_sys::ext::render::{
    CLAP_EXT_RENDER, CLAP_RENDER_OFFLINE, CLAP_RENDER_REALTIME, clap_plugin_render,
    clap_plugin_render_mode,
};
use clap_sys::ext::state::{CLAP_EXT_STATE, clap_plugin_state};
use clap_sys::stream::{clap_istream, clap_ostream};

use clap_sys::entry::clap_plugin_entry;
use clap_sys::events::{CLAP_EVENT_MIDI2, clap_event_header, clap_event_midi2};
use clap_sys::ext::audio_ports::{
    CLAP_AUDIO_PORT_IS_MAIN, CLAP_EXT_AUDIO_PORTS, CLAP_PORT_STEREO, clap_audio_port_info,
    clap_plugin_audio_ports,
};
use clap_sys::ext::note_name::{CLAP_EXT_NOTE_NAME, clap_note_name, clap_plugin_note_name};
use clap_sys::ext::note_ports::{
    CLAP_EXT_NOTE_PORTS, CLAP_NOTE_DIALECT_CLAP, CLAP_NOTE_DIALECT_MIDI2, clap_note_port_info,
    clap_plugin_note_ports,
};
use clap_sys::factory::plugin_factory::{CLAP_PLUGIN_FACTORY_ID, clap_plugin_factory};
use clap_sys::host::clap_host;
use clap_sys::plugin::{clap_plugin, clap_plugin_descriptor};
use clap_sys::process::{
    CLAP_PROCESS_CONTINUE, CLAP_PROCESS_SLEEP, clap_process, clap_process_status,
};
use clap_sys::version::CLAP_VERSION;

/// The two words of the last MIDI 2.0 note-on, and how many came.
static LAST: [AtomicU32; 2] = [AtomicU32::new(0), AtomicU32::new(0)];
static COUNT: AtomicU32 = AtomicU32::new(0);
/// The attribute of the note sounding (type above data), 0 for none.
static SOUNDING: AtomicU32 = AtomicU32::new(0);
/// The state it plays with, and one loaded that waits for the next block.
static STATE: AtomicU32 = AtomicU32::new(0);
static LOADED: AtomicU32 = AtomicU32::new(u32::MAX);
/// A move in its window that waits for the next block, and a value it
/// tells with no gesture then.
static MOVE: AtomicU32 = AtomicU32::new(u32::MAX);
static TELL: AtomicU32 = AtomicU32::new(u32::MAX);
/// Tell nothing of a state taken on (1), or tell it (0).
static QUIET: AtomicU32 = AtomicU32::new(0);
/// The next block waits (1), a block waits now (2), or none waits (0).
static HOLD: AtomicU32 = AtomicU32::new(0);
/// A render mode that the host never set.
const MODE_NONE: u32 = 2;
/// The mode of the first block before the first block.
const MODE_NO_BLOCK: u32 = 3;

/// What each instance keeps of its own, in its `plugin_data`: the host
/// that made it, to ask it for a block or a restart, how many times it
/// was activated, the render mode that the host set last, and the mode
/// that its first block had. A mode is a `clap_plugin_render_mode`,
/// [`MODE_NONE`] or [`MODE_NO_BLOCK`].
struct Instance {
    host: *const clap_host,
    activations: AtomicU32,
    mode: AtomicU32,
    first_block_mode: AtomicU32,
}

/// The word that `stub.render` gives for a mode.
fn mode_word(mode: u32) -> &'static str {
    match mode {
        MODE_NONE => "none",
        MODE_NO_BLOCK => "no-block",
        m if m == CLAP_RENDER_OFFLINE as u32 => "offline",
        _ => "realtime",
    }
}

/// The instance's own data.
unsafe fn instance<'a>(plugin: *const clap_plugin) -> &'a Instance {
    // SAFETY: `plugin` is the one `create_plugin` made: its `plugin_data` is a boxed `Instance`
    // that lives until `destroy`.
    unsafe { &*((*plugin).plugin_data as *const Instance) }
}

/// Ask the host for a block.
unsafe fn wake(plugin: *const clap_plugin) {
    // SAFETY: the host that `create_plugin` was given lives as long as the plugin (CLAP), and
    // `instance` holds for the plugin the host calls with.
    unsafe {
        let host = instance(plugin).host;
        (*host).request_process.unwrap()(host);
    }
}

/// Ask the host to deactivate the plugin and activate it again.
unsafe fn restart(plugin: *const clap_plugin) {
    // SAFETY: the host that `create_plugin` was given lives as long as the plugin (CLAP), and
    // `instance` holds for the plugin the host calls with.
    unsafe {
        let host = instance(plugin).host;
        (*host).request_restart.unwrap()(host);
    }
}

/// Tell the host of the parameter's value, inside a gesture or not.
unsafe fn tell(out: *const clap_output_events, value: u32, gesture: bool) {
    let header = |size: usize, type_| clap_event_header {
        size: size as u32,
        time: 0,
        space_id: CLAP_CORE_EVENT_SPACE_ID,
        type_,
        flags: 0,
    };
    let edge = |type_| clap_event_param_gesture {
        header: header(size_of::<clap_event_param_gesture>(), type_),
        param_id: 0,
    };
    let event = clap_event_param_value {
        header: header(size_of::<clap_event_param_value>(), CLAP_EVENT_PARAM_VALUE),
        param_id: 0,
        cookie: std::ptr::null_mut(),
        note_id: -1,
        port_index: -1,
        channel: -1,
        key: -1,
        value: value as f64,
    };
    // SAFETY: `out` is the host's queue of events for this block (CLAP), and each header points
    // into an event that lives until the call returns.
    unsafe {
        let push = (*out).try_push.unwrap();
        if gesture {
            push(out, &edge(CLAP_EVENT_PARAM_GESTURE_BEGIN).header);
        }
        push(out, &raw const event.header);
        if gesture {
            push(out, &edge(CLAP_EVENT_PARAM_GESTURE_END).header);
        }
    }
}

unsafe extern "C" fn params_count(_: *const clap_plugin) -> u32 {
    1
}
unsafe extern "C" fn params_info(
    _: *const clap_plugin,
    index: u32,
    info: *mut clap_param_info,
) -> bool {
    if index > 0 {
        return false;
    }
    // SAFETY: the host gives a `clap_param_info` to write into (CLAP).
    unsafe {
        let info = &mut *info;
        info.id = 0;
        info.flags = CLAP_PARAM_IS_AUTOMATABLE;
        info.cookie = std::ptr::null_mut();
        for (to, from) in info.name.iter_mut().zip(c"State".to_bytes_with_nul()) {
            *to = *from as c_char;
        }
        info.module[0] = 0;
        info.min_value = 0.0;
        info.max_value = 127.0;
        info.default_value = 0.0;
    }
    true
}
unsafe extern "C" fn params_value(_: *const clap_plugin, id: u32, out: *mut f64) -> bool {
    if id != 0 {
        return false;
    }
    // SAFETY: the host gives a `f64` to write into (CLAP).
    unsafe { *out = STATE.load(Relaxed) as f64 };
    true
}
static PARAMS: clap_plugin_params = clap_plugin_params {
    count: Some(params_count),
    get_info: Some(params_info),
    get_value: Some(params_value),
    value_to_text: None,
    text_to_value: None,
    flush: None,
};

type Write = Option<unsafe extern "C" fn(*mut c_void, *const u8, usize)>;

/// paw's call extension (`dev.paw.call/1`), for `stub.move` (a move in the
/// window, made by a script) and `stub.tell`.
#[repr(C)]
struct PawCall {
    call: unsafe extern "C" fn(
        *const clap_plugin,
        *const c_char,
        *const u8,
        usize,
        *mut c_void,
        Write,
    ) -> bool,
}
unsafe extern "C" fn paw_call(
    plugin: *const clap_plugin,
    method: *const c_char,
    data: *const u8,
    size: usize,
    out: *mut c_void,
    write: Write,
) -> bool {
    // SAFETY: the host gives a C string and `size` bytes at `data` (paw's call extension).
    let (method, data) = unsafe {
        (
            CStr::from_ptr(method),
            std::slice::from_raw_parts(data, size),
        )
    };
    if method == c"stub.activations" {
        // SAFETY: the host calls with the plugin that `create_plugin` made, whose `plugin_data`
        // is an `Instance`.
        let count = unsafe { instance(plugin) }.activations.load(Relaxed).to_string();
        // SAFETY: the host gives a `write` that takes `out` and the bytes of a live string.
        unsafe { write.unwrap()(out, count.as_ptr(), count.len()) };
        return true;
    }
    if method == c"stub.render" {
        // SAFETY: the host calls with the plugin that `create_plugin` made, whose `plugin_data`
        // is an `Instance`.
        let instance = unsafe { instance(plugin) };
        let modes = format!(
            "{} {}",
            mode_word(instance.first_block_mode.load(SeqCst)),
            mode_word(instance.mode.load(SeqCst))
        );
        // SAFETY: the host gives a `write` that takes `out` and the bytes of a live string.
        unsafe { write.unwrap()(out, modes.as_ptr(), modes.len()) };
        return true;
    }
    let value = std::str::from_utf8(data)
        .ok()
        .and_then(|t| t.trim().parse().ok());
    let Some(value) = value else { return false };
    if method == c"stub.move" {
        MOVE.store(value, Relaxed);
        // SAFETY: the host calls with the plugin that `create_plugin` made, whose `plugin_data`
        // is an `Instance`.
        unsafe { wake(plugin) };
    } else if method == c"stub.tell" {
        TELL.store(value, Relaxed);
        // SAFETY: the host calls with the plugin that `create_plugin` made, whose `plugin_data`
        // is an `Instance`.
        unsafe { wake(plugin) };
    } else if method == c"stub.restart" {
        // SAFETY: the host calls with the plugin that `create_plugin` made, whose `plugin_data`
        // is an `Instance`.
        unsafe { restart(plugin) };
    } else if method == c"stub.quiet" {
        QUIET.store(value, Relaxed);
    } else if method == c"stub.hold" {
        HOLD.store(value, SeqCst);
    } else {
        return false;
    }
    true
}
static PAW_CALL: PawCall = PawCall { call: paw_call };

/// For tests: whether a block waits for `stub_clap_release`.
#[unsafe(no_mangle)]
pub extern "C" fn stub_clap_held() -> bool {
    HOLD.load(SeqCst) == 2
}

/// For tests: let the block that waits go on.
#[unsafe(no_mangle)]
pub extern "C" fn stub_clap_release() {
    HOLD.store(0, SeqCst);
}

/// For tests: the state the plugin plays with.
#[unsafe(no_mangle)]
pub extern "C" fn stub_clap_state() -> u32 {
    STATE.load(Relaxed)
}

unsafe extern "C" fn state_save(_: *const clap_plugin, stream: *const clap_ostream) -> bool {
    let bytes = STATE.load(Relaxed).to_le_bytes();
    // SAFETY: the host gives a stream with a `write` that takes 4 bytes (CLAP).
    unsafe { (*stream).write.unwrap()(stream, bytes.as_ptr().cast(), 4) == 4 }
}
unsafe extern "C" fn state_load(_: *const clap_plugin, stream: *const clap_istream) -> bool {
    let mut bytes = [0u8; 4];
    // SAFETY: the host gives a stream with a `read` that writes at most 4 bytes (CLAP).
    if unsafe { (*stream).read.unwrap()(stream, bytes.as_mut_ptr().cast(), 4) } != 4 {
        return false;
    }
    // Taken on in the next block, on the audio thread.
    LOADED.store(u32::from_le_bytes(bytes), Relaxed);
    true
}
static STATE_EXT: clap_plugin_state = clap_plugin_state {
    save: Some(state_save),
    load: Some(state_load),
};

unsafe extern "C" fn render_hard_realtime(_: *const clap_plugin) -> bool {
    false
}
unsafe extern "C" fn render_set(plugin: *const clap_plugin, mode: clap_plugin_render_mode) -> bool {
    if mode != CLAP_RENDER_REALTIME && mode != CLAP_RENDER_OFFLINE {
        return false;
    }
    // SAFETY: the host calls with the plugin that `create_plugin` made, whose `plugin_data` is
    // an `Instance`.
    unsafe { instance(plugin) }.mode.store(mode as u32, SeqCst);
    true
}
static RENDER: clap_plugin_render = clap_plugin_render {
    has_hard_realtime_requirement: Some(render_hard_realtime),
    set: Some(render_set),
};

/// For tests: the words of the last note-on into `out`; how many came.
///
/// # Safety
/// `out` points to two words.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn stub_clap_last(out: *mut u32) -> u32 {
    // SAFETY: the caller gives two words at `out`, as the function's contract says.
    unsafe {
        *out = LAST[0].load(Relaxed);
        *out.add(1) = LAST[1].load(Relaxed);
    }
    COUNT.load(Relaxed)
}

struct Desc(clap_plugin_descriptor);
// SAFETY: the descriptor holds only pointers to static C strings, which nothing writes.
unsafe impl Sync for Desc {}
struct Features([*const c_char; 2]);
// SAFETY: the list holds only pointers to static C strings, which nothing writes.
unsafe impl Sync for Features {}

static FEATURES: Features = Features([c"instrument".as_ptr(), std::ptr::null()]);
static DESC: Desc = Desc(clap_plugin_descriptor {
    clap_version: CLAP_VERSION,
    id: c"dev.paw.stub".as_ptr(),
    name: c"Stub".as_ptr(),
    vendor: c"paw tests".as_ptr(),
    url: c"".as_ptr(),
    manual_url: c"".as_ptr(),
    support_url: c"".as_ptr(),
    version: c"1.0".as_ptr(),
    description: c"".as_ptr(),
    features: FEATURES.0.as_ptr(),
});

unsafe extern "C" fn init(_: *const clap_plugin) -> bool {
    true
}
unsafe extern "C" fn destroy(plugin: *const clap_plugin) {
    // SAFETY: both boxes are the ones `create_plugin` made, and the host destroys a plugin once
    // (CLAP).
    unsafe {
        drop(Box::from_raw((*plugin).plugin_data as *mut Instance));
        drop(Box::from_raw(plugin as *mut clap_plugin));
    }
}
unsafe extern "C" fn activate(plugin: *const clap_plugin, _: f64, _: u32, _: u32) -> bool {
    // SAFETY: the host calls with the plugin that `create_plugin` made, whose `plugin_data` is
    // an `Instance`.
    unsafe { instance(plugin) }.activations.fetch_add(1, Relaxed);
    true
}
unsafe extern "C" fn nothing(_: *const clap_plugin) {}
unsafe extern "C" fn start(_: *const clap_plugin) -> bool {
    true
}

unsafe extern "C" fn process(
    plugin: *const clap_plugin,
    p: *const clap_process,
) -> clap_process_status {
    // The first block keeps the render mode that it had.
    // SAFETY: the host calls with the plugin that `create_plugin` made, whose `plugin_data` is
    // an `Instance`.
    let instance = unsafe { instance(plugin) };
    let _ = instance.first_block_mode.compare_exchange(
        MODE_NO_BLOCK,
        instance.mode.load(SeqCst),
        SeqCst,
        SeqCst,
    );
    // SAFETY: the host gives a `clap_process` whose event queues and buffers of `frames_count`
    // frames live until the call returns (CLAP).
    unsafe {
        let p = &*p;
        let loaded = LOADED.swap(u32::MAX, Relaxed);
        if loaded != u32::MAX {
            STATE.store(loaded, Relaxed);
            if QUIET.load(Relaxed) == 0 {
                tell(p.out_events, loaded, false);
            }
        }
        // Held after it looked for a state: one given now waits for the
        // next block.
        if HOLD.compare_exchange(1, 2, SeqCst, SeqCst).is_ok() {
            while HOLD.load(SeqCst) == 2 {
                std::hint::spin_loop();
            }
        }
        let moved = MOVE.swap(u32::MAX, Relaxed);
        if moved != u32::MAX {
            STATE.store(moved, Relaxed);
            tell(p.out_events, moved, true);
        }
        let told = TELL.swap(u32::MAX, Relaxed);
        if told != u32::MAX {
            STATE.store(told, Relaxed);
            tell(p.out_events, told, false);
        }
        let events = &*p.in_events;
        let n = events.size.unwrap()(p.in_events);
        for i in 0..n {
            let header: *const clap_event_header = events.get.unwrap()(p.in_events, i);
            if (*header).type_ != CLAP_EVENT_MIDI2 {
                continue;
            }
            let data = (*(header as *const clap_event_midi2)).data;
            match (data[0] >> 20) & 15 {
                0x9 => {
                    LAST[0].store(data[0], Relaxed);
                    LAST[1].store(data[1], Relaxed);
                    COUNT.fetch_add(1, Relaxed);
                    SOUNDING.store((data[0] & 0xff) << 16 | (data[1] & 0xffff), Relaxed);
                }
                0x8 => SOUNDING.store(0, Relaxed),
                _ => {}
            }
        }
        let attr = SOUNDING.load(Relaxed);
        let (left, right) = (
            (attr >> 16) as f32 / 256.0,
            ((attr >> 12) & 15) as f32 / 16.0,
        );
        if p.audio_outputs_count > 0 {
            let out = &*p.audio_outputs;
            for (ch, level) in [left, right]
                .into_iter()
                .enumerate()
                .take(out.channel_count as usize)
            {
                let buf =
                    std::slice::from_raw_parts_mut(*out.data32.add(ch), p.frames_count as usize);
                buf.fill(level);
            }
        }
        // With no note sounding it has nothing to do until the next.
        if attr == 0 {
            return CLAP_PROCESS_SLEEP;
        }
    }
    CLAP_PROCESS_CONTINUE
}

unsafe extern "C" fn audio_count(_: *const clap_plugin, is_input: bool) -> u32 {
    if is_input { 0 } else { 1 }
}
unsafe extern "C" fn audio_get(
    _: *const clap_plugin,
    index: u32,
    is_input: bool,
    info: *mut clap_audio_port_info,
) -> bool {
    if is_input || index > 0 {
        return false;
    }
    // SAFETY: the host gives a `clap_audio_port_info` to write into (CLAP).
    unsafe {
        (*info).id = 0;
        (*info).flags = CLAP_AUDIO_PORT_IS_MAIN;
        (*info).channel_count = 2;
        (*info).port_type = CLAP_PORT_STEREO.as_ptr();
        (*info).in_place_pair = u32::MAX;
    }
    true
}
static AUDIO_PORTS: clap_plugin_audio_ports = clap_plugin_audio_ports {
    count: Some(audio_count),
    get: Some(audio_get),
};

unsafe extern "C" fn note_count(_: *const clap_plugin, is_input: bool) -> u32 {
    is_input as u32
}
unsafe extern "C" fn note_get(
    _: *const clap_plugin,
    index: u32,
    is_input: bool,
    info: *mut clap_note_port_info,
) -> bool {
    if !is_input || index > 0 {
        return false;
    }
    // SAFETY: the host gives a `clap_note_port_info` to write into (CLAP).
    unsafe {
        (*info).id = 0;
        (*info).supported_dialects = CLAP_NOTE_DIALECT_CLAP | CLAP_NOTE_DIALECT_MIDI2;
        (*info).preferred_dialect = CLAP_NOTE_DIALECT_MIDI2;
    }
    true
}
static NOTE_PORTS: clap_plugin_note_ports = clap_plugin_note_ports {
    count: Some(note_count),
    get: Some(note_get),
};

const NAMES: [(i16, &CStr); 2] = [(24, c"Sustain"), (26, c"Staccato")];
unsafe extern "C" fn names_count(_: *const clap_plugin) -> u32 {
    NAMES.len() as u32
}
unsafe extern "C" fn names_get(
    _: *const clap_plugin,
    index: u32,
    name: *mut clap_note_name,
) -> bool {
    let Some((key, text)) = NAMES.get(index as usize) else {
        return false;
    };
    // SAFETY: the host gives a `clap_note_name` to write into (CLAP).
    unsafe {
        let name = &mut *name;
        for (to, from) in name.name.iter_mut().zip(text.to_bytes_with_nul()) {
            *to = *from as c_char;
        }
        name.port = -1;
        name.channel = -1;
        name.key = *key;
    }
    true
}
static NOTE_NAMES: clap_plugin_note_name = clap_plugin_note_name {
    count: Some(names_count),
    get: Some(names_get),
};

unsafe extern "C" fn get_extension(_: *const clap_plugin, id: *const c_char) -> *const c_void {
    // SAFETY: the host gives a C string (CLAP).
    let id = unsafe { CStr::from_ptr(id) };
    if id == CLAP_EXT_AUDIO_PORTS {
        &raw const AUDIO_PORTS as *const c_void
    } else if id == CLAP_EXT_NOTE_PORTS {
        &raw const NOTE_PORTS as *const c_void
    } else if id == CLAP_EXT_NOTE_NAME {
        &raw const NOTE_NAMES as *const c_void
    } else if id == CLAP_EXT_STATE {
        &raw const STATE_EXT as *const c_void
    } else if id == CLAP_EXT_PARAMS {
        &raw const PARAMS as *const c_void
    } else if id == CLAP_EXT_RENDER {
        &raw const RENDER as *const c_void
    } else if id == c"dev.paw.call/1" {
        &raw const PAW_CALL as *const c_void
    } else {
        std::ptr::null()
    }
}

unsafe extern "C" fn plugin_count(_: *const clap_plugin_factory) -> u32 {
    1
}
unsafe extern "C" fn plugin_descriptor(
    _: *const clap_plugin_factory,
    index: u32,
) -> *const clap_plugin_descriptor {
    if index == 0 {
        &raw const DESC.0
    } else {
        std::ptr::null()
    }
}
unsafe extern "C" fn create_plugin(
    _: *const clap_plugin_factory,
    host: *const clap_host,
    id: *const c_char,
) -> *const clap_plugin {
    // SAFETY: the host gives a C string (CLAP).
    if unsafe { CStr::from_ptr(id) } != c"dev.paw.stub" {
        return std::ptr::null();
    }
    let instance = Instance {
        host,
        activations: AtomicU32::new(0),
        mode: AtomicU32::new(MODE_NONE),
        first_block_mode: AtomicU32::new(MODE_NO_BLOCK),
    };
    Box::into_raw(Box::new(clap_plugin {
        desc: &raw const DESC.0,
        plugin_data: Box::into_raw(Box::new(instance)).cast(),
        init: Some(init),
        destroy: Some(destroy),
        activate: Some(activate),
        deactivate: Some(nothing),
        start_processing: Some(start),
        stop_processing: Some(nothing),
        reset: Some(nothing),
        process: Some(process),
        get_extension: Some(get_extension),
        on_main_thread: Some(nothing),
    }))
}
static FACTORY: clap_plugin_factory = clap_plugin_factory {
    get_plugin_count: Some(plugin_count),
    get_plugin_descriptor: Some(plugin_descriptor),
    create_plugin: Some(create_plugin),
};

unsafe extern "C" fn entry_init(_: *const c_char) -> bool {
    true
}
unsafe extern "C" fn entry_deinit() {}
unsafe extern "C" fn get_factory(id: *const c_char) -> *const c_void {
    // SAFETY: the host gives a C string (CLAP).
    if unsafe { CStr::from_ptr(id) } == CLAP_PLUGIN_FACTORY_ID {
        &raw const FACTORY as *const c_void
    } else {
        std::ptr::null()
    }
}

#[unsafe(no_mangle)]
pub static clap_entry: clap_plugin_entry = clap_plugin_entry {
    clap_version: CLAP_VERSION,
    init: Some(entry_init),
    deinit: Some(entry_deinit),
    get_factory: Some(get_factory),
};
