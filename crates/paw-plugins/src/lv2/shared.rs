//! What a plugin instance shares between its device and its controller.

use std::cell::UnsafeCell;
use std::collections::HashMap;
use std::ffi::{CStr, CString, c_void};
use std::path::PathBuf;
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering::Relaxed};
use std::sync::{Arc, OnceLock};

use paw_engine::ParamInfo;
use lilv_sys::*;

use crate::lv2_patch::Property;
use super::*;
use super::urid::*;
use super::worker::*;

// --- an instance -------------------------------------------------------------

/// What the plugin was handed at instantiation and keeps pointers to.
pub(super) struct HostData {
    pub(super) map: UridMap,
    pub(super) unmap: UridUnmap,
    schedule: WorkerSchedule,
    pub(super) options: [OptionsOption; 4],
    features: Vec<Feature>,
    pub(super) feature_list: Vec<*const Feature>,
    max_block: i32,
    min_block: i32,
    sample_rate: f32,
    pub(super) worker: OnceLock<Worker>,
}

pub(super) struct Shared {
    pub(super) plugin: *const LilvPlugin,
    pub(super) instance: *mut LilvInstance,
    pub(super) host: Box<HostData>,
    /// One value per control port, read and written as `f32`. The plugin is
    /// connected straight to these.
    pub(super) controls: Box<[AtomicU32]>,
    /// For each parameter, the index of its value in `controls`.
    pub(super) param_slots: Vec<usize>,
    pub(super) params: Vec<ParamInfo>,
    /// Port symbol to index in `controls`, for saving and restoring state.
    pub(super) symbols: HashMap<CString, usize>,
    pub(super) worker_interface: *const WorkerInterface,
    pub(super) scratch: UnsafeCell<f32>,
    /// Every control port as (port index, index in `controls`), for the editor.
    pub(super) control_ports: Vec<(u32, usize)>,
    /// The control that tells the plugin it is rendering faster than real
    /// time, if it has one.
    pub(super) free_wheeling: Option<usize>,
    /// The port index of each atom buffer, in the device's order.
    pub(super) atom_ports: Vec<u32>,
    /// Port symbol to port index.
    pub(super) port_symbols: HashMap<CString, u32>,
    /// The plugin's X11 editor, if it has one.
    pub(super) ui: Option<UiInfo>,
    /// Whether an editor is open and wants to hear from the plugin.
    pub(super) ui_open: AtomicBool,
    /// The properties the plugin lists (`patch:writable`, `patch:readable`).
    pub(super) properties: Vec<Property>,
    /// The port index of the atom input that takes patch messages, when
    /// the plugin has properties.
    pub(super) patch_port: Option<u32>,
    /// The index in `controls` of the port where the plugin says how many
    /// frames its output is behind its input, if it has one.
    pub(super) latency: Option<usize>,
    /// A control changed since the plugin last ran: it must run again,
    /// asleep or not (see [`Device::resting`]).
    pub(super) wake: AtomicBool,
}

/// Where a plugin's editor lives on disk, and how it is shown.
pub(super) struct UiInfo {
    pub(super) uri: CString,
    pub(super) binary: PathBuf,
    pub(super) bundle: CString,
    pub(super) kind: UiKind,
    /// Where the libraries that the editor needs are looked for.
    pub(super) libraries: Arc<[PathBuf]>,
}

/// The ways an LV2 editor can get on screen, best first.
#[derive(Clone, Copy, Debug, PartialEq, PartialOrd)]
pub(super) enum UiKind {
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
// SAFETY: `Shared` owns raw pointers to the plugin instance and its interface. LV2 lets `run` and
// the worker interface run on different threads, and the rest (the instance, the UnsafeCell
// `scratch`, the queue consumers) is touched from the audio thread only or, for creation and
// Drop, when no other thread has the value.
unsafe impl Send for Shared {}
// SAFETY: The state two threads share is atomics (`controls`, `wake`, `ui_open`) and the worker's
// counters; the other fields are read-only after creation or used from one thread at a time.
unsafe impl Sync for Shared {}

impl Shared {
    pub(super) fn control(&self, slot: usize) -> f32 {
        f32::from_bits(self.controls[slot].load(Relaxed))
    }

    pub(super) fn set_control(&self, slot: usize, value: f32) {
        self.controls[slot].store(value.to_bits(), Relaxed);
        self.wake.store(true, Relaxed);
    }

    /// Whether the worker has work not done, or answers the plugin has
    /// not been given yet.
    pub(super) fn working(&self) -> bool {
        self.host.worker.get().is_some_and(|worker| {
            worker.pending.load(std::sync::atomic::Ordering::Acquire) > 0
                // SAFETY: `responses` is a consumer that only the audio thread uses, and `working` is called from
                // there (`Device::resting`), so this shared borrow does not overlap a `&mut` from another thread.
                || unsafe { (*worker.responses.get()).slots() } > 0
        })
    }
}

impl Drop for Shared {
    fn drop(&mut self) {
        // Stop the worker before the plugin it calls into goes away.
        drop(self.host.worker.take());
        // SAFETY: `instance` was made by `lilv_instantiate` and is freed once, here; the worker thread that
        // calls the plugin was joined by the line above.
        unsafe { lilv_instance_free(self.instance) };
    }
}

pub(super) fn host_data(sample_rate: f32, max_block: usize) -> Box<HostData> {
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


