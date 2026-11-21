//! LV2 hosting on top of lilv.
//!
//! lilv finds plugins and reads their descriptions without loading any code,
//! so there is nothing to cache. A plugin gets these host features: URID
//! mapping, options (block length and sample rate), bounded block length, the
//! worker for non-real-time work, and state through lilv's state functions.

mod atom;
mod controller;
mod device;
mod factory;
mod shared;
mod ui;
mod urid;
mod worker;
mod world;

pub(crate) use world::scan;

use std::ffi::{CStr, c_char, c_void};



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

