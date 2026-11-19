//! VST3 hosting over the COM bindings.
//!
//! A VST3 plugin is a component that processes audio and an edit controller
//! that owns the parameters; some plugins implement both in one object. The
//! component's `process` runs on the audio thread and everything else on the
//! main thread. Parameter values are normalized to 0..1.

use std::cell::{Cell, RefCell, UnsafeCell};
use std::ffi::{c_char, c_void};
use std::path::{Path, PathBuf};
use std::ptr;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result, bail};
use paw_engine::device::assign_keys;
use paw_engine::{
    Controller, Ctl, Device, DeviceFactory, DeviceInfo, EventKind, Instance, Io, NOTE_BEND_RANGE,
    NoteCtl, ParamInfo, Ports, ProcessCtx, Registry,
};
use vst3::Steinberg::Linux::*;
use vst3::Steinberg::Vst::*;
use vst3::Steinberg::*;
use vst3::{Class, ComPtr, ComRef, ComWrapper, Interface};

use crate::window::{HostWindow, Watches, WindowEvent, ui_scale};
use crate::{Cache, Found, HeldNotes, find_bundles, search_dirs, write_output};

const OK: tresult = 0;
const NO_INTERFACE: tresult = -1;
const FALSE: tresult = 1;
const AUDIO: i32 = 0;
const EVENT: i32 = 1;
const INPUT: i32 = 0;
const OUTPUT: i32 = 1;
/// The type of a bus that is not the main one, such as a side-chain.
const AUX: i32 = 1;
const SAMPLE_32: i32 = 0;
const REALTIME: i32 = 0;
const OFFLINE: i32 = 2;
const NOTE_ON: u16 = 0;
const NOTE_OFF: u16 = 1;
const POLY_PRESSURE: u16 = 3;
const NOTE_EXPRESSION: u16 = 4;

/// The id a note is known by to the plugin, which its own controllers name
/// it with: one per key and channel.
fn note_id(key: u8, ch: u8) -> i32 {
    ch as i32 * 128 + key as i32
}
const PARAM_CAN_AUTOMATE: i32 = 1 << 0;
const PARAM_READ_ONLY: i32 = 1 << 1;
const PARAM_IS_LIST: i32 = 1 << 3;
const PARAM_HIDDEN: i32 = 1 << 4;
const PLAYING: u32 = 1 << 1;
const MUSIC_TIME_VALID: u32 = 1 << 9;
const TEMPO_VALID: u32 = 1 << 10;
const BAR_VALID: u32 = 1 << 11;
const TIME_SIG_VALID: u32 = 1 << 13;
const PARAM_VALUES_CHANGED: i32 = 1 << 2;
const X11_EMBED: &std::ffi::CStr = c"X11EmbedWindowID";

/// A loaded VST3 module. Never unloaded.
struct Module {
    factory: ComPtr<IPluginFactory>,
    /// The host as the factory knows it, for as long as the module lives.
    _host: ComWrapper<Host>,
}

// Used from the main thread only.
unsafe impl Send for Module {}
unsafe impl Sync for Module {}

/// The shared library inside a `.vst3` bundle.
fn library_path(bundle: &Path) -> PathBuf {
    let arch = format!("{}-linux", std::env::consts::ARCH);
    let name = bundle.file_stem().unwrap_or_default();
    bundle
        .join("Contents")
        .join(arch)
        .join(name)
        .with_extension("so")
}

fn load(bundle: &Path) -> Result<Arc<Module>> {
    static LOADED: Mutex<Vec<(PathBuf, Arc<Module>)>> = Mutex::new(Vec::new());
    let mut loaded = LOADED.lock().unwrap();
    if let Some((_, module)) = loaded.iter().find(|(p, _)| p == bundle) {
        return Ok(module.clone());
    }
    let path = library_path(bundle);
    let module = unsafe {
        let handle = crate::libs::open_library(&path)
            .with_context(|| format!("loading {}", path.display()))?
            .into_raw();
        // Borrow the handle to look symbols up, without ever closing it.
        let lib = std::mem::ManuallyDrop::new(libloading::os::unix::Library::from_raw(handle));
        if let Ok(entry) = lib.get::<unsafe extern "C" fn(*mut c_void) -> bool>(b"ModuleEntry\0")
            && !entry(handle)
        {
            bail!("the module refused to initialize");
        }
        let get_factory = lib
            .get::<unsafe extern "C" fn() -> *mut IPluginFactory>(b"GetPluginFactory\0")
            .context("not a VST3 module")?;
        let factory =
            ComPtr::from_raw(get_factory()).context("the module has no plugin factory")?;
        // A factory that takes a host context is given one before anything
        // is made with it, as the format's own hosting code does: some
        // plugins look the host up there while an instance is being created.
        let host = ComWrapper::new(Host::default());
        if let Some(factory3) = factory.cast::<IPluginFactory3>() {
            let context = host.as_com_ref::<IHostApplication>().unwrap().as_ptr() as *mut FUnknown;
            factory3.setHostContext(context);
        }
        Arc::new(Module {
            factory,
            _host: host,
        })
    };
    loaded.push((bundle.to_path_buf(), module.clone()));
    Ok(module)
}

fn chars(text: &[c_char]) -> String {
    let bytes: Vec<u8> = text
        .iter()
        .take_while(|c| **c != 0)
        .map(|c| *c as u8)
        .collect();
    String::from_utf8_lossy(&bytes).into_owned()
}

fn wide(text: &[TChar]) -> String {
    let units: Vec<u16> = text.iter().take_while(|c| **c != 0).copied().collect();
    String::from_utf16_lossy(&units)
}

fn hex(id: &TUID) -> String {
    id.iter().map(|b| format!("{:02X}", *b as u8)).collect()
}

/// The name of each of the controller's units (its groups of
/// parameters), with those it is in before it: "Osc 1/Pitch". The root
/// unit has no name.
unsafe fn unit_paths(controller: &ComPtr<IEditController>) -> std::collections::HashMap<i32, String> {
    let mut parents = std::collections::HashMap::new();
    if let Some(units) = controller.cast::<IUnitInfo>() {
        unsafe {
            for index in 0..units.getUnitCount() {
                let mut info: UnitInfo = std::mem::zeroed();
                if units.getUnitInfo(index, &mut info) == OK && info.id != 0 {
                    parents.insert(info.id, (info.parentUnitId, wide(&info.name)));
                }
            }
        }
    }
    let mut paths = std::collections::HashMap::new();
    for &id in parents.keys() {
        let mut names = Vec::new();
        let mut at = id;
        // A unit list that loops is cut at its length.
        while let Some((parent, name)) = parents.get(&at) {
            names.push(name.clone());
            if names.len() > parents.len() {
                break;
            }
            at = *parent;
        }
        names.reverse();
        paths.insert(id, names.join("/"));
    }
    paths
}

fn unhex(text: &str) -> Option<TUID> {
    let mut id = [0 as c_char; 16];
    for (i, byte) in id.iter_mut().enumerate() {
        *byte = u8::from_str_radix(text.get(i * 2..i * 2 + 2)?, 16).ok()? as c_char;
    }
    Some(id)
}

/// Load a bundle and list the audio plugins in it.
/// What is in a bundle, for the helper that looks into plugin files.
pub(crate) fn list_file(bundle: &Path) -> Result<Vec<Found>> {
    list(bundle)
}

fn list(bundle: &Path) -> Result<Vec<Found>> {
    let module = load(bundle)?;
    let mut found = Vec::new();
    unsafe {
        let factory2 = module.factory.cast::<IPluginFactory2>();
        for index in 0..module.factory.countClasses() {
            let mut info: PClassInfo = std::mem::zeroed();
            if module.factory.getClassInfo(index, &mut info) != OK
                || chars(&info.category) != "Audio Module Class"
            {
                continue;
            }
            let (mut vendor, mut instrument, mut version) = (String::new(), false, String::new());
            let mut features = Vec::new();
            if let Some(factory2) = &factory2 {
                let mut info2: PClassInfo2 = std::mem::zeroed();
                if factory2.getClassInfo2(index, &mut info2) == OK {
                    vendor = chars(&info2.vendor);
                    version = chars(&info2.version);
                    let categories = chars(&info2.subCategories);
                    instrument = categories.contains("Instrument");
                    features = categories.split('|').map(str::to_string).collect();
                }
            }
            found.push(Found {
                id: hex(&info.cid),
                name: chars(&info.name),
                vendor,
                instrument,
                version,
                features,
            });
        }
    }
    Ok(found)
}

pub(crate) fn scan(registry: &mut Registry, cache: &mut Cache, notes: &mut Vec<String>) {
    scan_in(registry, cache, notes, &search_dirs("VST3_PATH", "vst3"));
}

/// Register the plugins in the `.vst3` bundles under `dirs`.
pub(crate) fn scan_in(
    registry: &mut Registry,
    cache: &mut Cache,
    notes: &mut Vec<String>,
    dirs: &[std::path::PathBuf],
) {
    let mut seen = std::collections::HashSet::new();
    for bundle in find_bundles(dirs, "vst3") {
        let library = library_path(&bundle);
        if !library.is_file() {
            continue;
        }
        match cache.plugins(&library, || {
            crate::list_apart("vst3", &bundle, || list(&bundle))
        }) {
            Ok(found) => {
                for plugin in found {
                    let Some(class) = unhex(&plugin.id) else {
                        continue;
                    };
                    // The same plugin installed in two places is one plugin.
                    if !seen.insert(plugin.id.clone()) {
                        continue;
                    }
                    // The name is the handle, so two plugins cannot share one.
                    let mut kind = format!("vst3:{}", plugin.name);
                    let mut copy = 2;
                    while registry.get(&kind).is_some() {
                        kind = format!("vst3:{} ({copy})", plugin.name);
                        copy += 1;
                    }
                    let info = DeviceInfo {
                        kind,
                        name: plugin.name,
                        category: if plugin.instrument {
                            "instrument"
                        } else {
                            "effect"
                        }
                        .into(),
                        format: "vst3".into(),
                        vendor: plugin.vendor,
                        id: plugin.id.clone(),
                        version: plugin.version,
                        params: Vec::new(),
                        features: plugin.features,
                    };
                    registry.register(std::rc::Rc::new(Vst3Factory {
                        info,
                        bundle: bundle.clone(),
                        class,
                    }));
                }
            }
            Err(err) => notes.push(format!("{}: {err}", bundle.display())),
        }
    }
}

struct Vst3Factory {
    info: DeviceInfo,
    bundle: PathBuf,
    class: TUID,
}

// --- what the host gives the plugin ------------------------------------------

/// The host application and component handler handed to every plugin.
#[derive(Default)]
struct Host {
    /// Parameter edits made in the plugin's editor, waiting to be passed on.
    /// Each with whether it came inside `beginEdit` and `endEdit`: a
    /// person's move, not the plugin telling of a value it took on itself.
    edits: RefCell<Vec<(ParamID, f64, bool)>>,
    /// The parameters between `beginEdit` and `endEdit` now.
    gestures: RefCell<Vec<ParamID>>,
    /// The plugin says its parameter values changed wholesale.
    rescan: Cell<bool>,
    /// The processor has to be run again, though its tail has gone by: it
    /// was given a state, which some plugins (JUCE ones, Surge XT) only
    /// take on in their next block.
    wake: AtomicBool,
    /// Blocks the processor has run, to tell when it has taken on a state.
    blocks: AtomicU64,
    watches: RunLoop,
}

impl Class for Host {
    type Interfaces = (IHostApplication, IComponentHandler, IRunLoop);
}

impl IHostApplicationTrait for Host {
    unsafe fn getName(&self, name: *mut String128) -> tresult {
        unsafe {
            for (slot, unit) in (*name).iter_mut().zip("paw\0".encode_utf16()) {
                *slot = unit as TChar;
            }
        }
        OK
    }

    unsafe fn createInstance(
        &self,
        _cid: *mut TUID,
        _iid: *mut TUID,
        obj: *mut *mut c_void,
    ) -> tresult {
        unsafe { *obj = ptr::null_mut() };
        NO_INTERFACE
    }
}

impl IComponentHandlerTrait for Host {
    unsafe fn beginEdit(&self, id: ParamID) -> tresult {
        self.gestures.borrow_mut().push(id);
        OK
    }

    unsafe fn performEdit(&self, id: ParamID, value: ParamValue) -> tresult {
        let gesture = self.gestures.borrow().contains(&id);
        self.edits.borrow_mut().push((id, value, gesture));
        OK
    }

    unsafe fn endEdit(&self, id: ParamID) -> tresult {
        let mut gestures = self.gestures.borrow_mut();
        if let Some(at) = gestures.iter().position(|g| *g == id) {
            gestures.swap_remove(at);
        }
        OK
    }

    unsafe fn restartComponent(&self, flags: i32) -> tresult {
        if flags & PARAM_VALUES_CHANGED != 0 {
            self.rescan.set(true);
        }
        OK
    }
}

/// A callback object the plugin registered, compared by identity.
struct Handler<I: Interface>(ComPtr<I>);

impl<I: Interface> Clone for Handler<I> {
    fn clone(&self) -> Self {
        Handler(self.0.clone())
    }
}

impl<I: Interface> PartialEq for Handler<I> {
    fn eq(&self, other: &Self) -> bool {
        self.0.as_ptr() == other.0.as_ptr()
    }
}

/// The timers and file descriptors a plugin wants called back for. Plugins
/// look for the run loop on the editor's frame or on the host itself, so both
/// offer it and both lead here.
#[derive(Clone, Default)]
struct RunLoop(Rc<RefCell<Watches<Handler<IEventHandler>, Handler<ITimerHandler>>>>);

impl RunLoop {
    fn add_fd(&self, handler: *mut IEventHandler, fd: i32) -> tresult {
        match unsafe { ComRef::from_raw(handler) } {
            Some(handler) => {
                self.0
                    .borrow_mut()
                    .fds
                    .push((fd, Handler(handler.to_com_ptr())));
                OK
            }
            None => FALSE,
        }
    }

    fn remove_fd(&self, handler: *mut IEventHandler) -> tresult {
        self.0
            .borrow_mut()
            .fds
            .retain(|(_, known)| known.0.as_ptr() != handler);
        OK
    }

    fn add_timer(&self, handler: *mut ITimerHandler, milliseconds: u64) -> tresult {
        match unsafe { ComRef::from_raw(handler) } {
            Some(handler) => {
                self.0
                    .borrow_mut()
                    .add_timer(milliseconds, Handler(handler.to_com_ptr()));
                OK
            }
            None => FALSE,
        }
    }

    fn remove_timer(&self, handler: *mut ITimerHandler) -> tresult {
        self.0
            .borrow_mut()
            .timers_retain(|known| known.0.as_ptr() != handler);
        OK
    }

    /// Call back whatever has come due.
    fn run(&self) {
        // Collect first: a handler may register or remove others while it runs.
        let (due, ready) = {
            let mut watches = self.0.borrow_mut();
            (watches.due_timers(), watches.ready_fds())
        };
        unsafe {
            for handler in due {
                handler.0.onTimer();
            }
            for (fd, handler) in ready {
                handler.0.onFDIsSet(fd);
            }
        }
    }
}

macro_rules! run_loop_interface {
    ($class:ty) => {
        impl IRunLoopTrait for $class {
            unsafe fn registerEventHandler(&self, handler: *mut IEventHandler, fd: i32) -> tresult {
                self.watches.add_fd(handler, fd)
            }

            unsafe fn unregisterEventHandler(&self, handler: *mut IEventHandler) -> tresult {
                self.watches.remove_fd(handler)
            }

            unsafe fn registerTimer(
                &self,
                handler: *mut ITimerHandler,
                milliseconds: u64,
            ) -> tresult {
                self.watches.add_timer(handler, milliseconds)
            }

            unsafe fn unregisterTimer(&self, handler: *mut ITimerHandler) -> tresult {
                self.watches.remove_timer(handler)
            }
        }
    };
}

run_loop_interface!(Host);
run_loop_interface!(Frame);

/// What a plugin's editor is given as its frame: somewhere to ask for a new
/// size, and the run loop.
struct Frame {
    resize: Cell<Option<(u32, u32)>>,
    watches: RunLoop,
}

impl Class for Frame {
    type Interfaces = (IPlugFrame, IRunLoop);
}

impl IPlugFrameTrait for Frame {
    unsafe fn resizeView(&self, _view: *mut IPlugView, size: *mut ViewRect) -> tresult {
        let size = unsafe { &*size };
        self.resize.set(Some((
            (size.right - size.left).max(1) as u32,
            (size.bottom - size.top).max(1) as u32,
        )));
        OK
    }
}

/// An open editor: the plugin's view inside one of our windows.
struct Editor {
    view: ComPtr<IPlugView>,
    frame: ComWrapper<Frame>,
    window: HostWindow,
}

/// A growable byte stream for plugin state.
struct Stream {
    data: RefCell<Vec<u8>>,
    pos: Cell<usize>,
}

impl Stream {
    fn new(data: Vec<u8>) -> ComWrapper<Stream> {
        ComWrapper::new(Stream {
            data: RefCell::new(data),
            pos: Cell::new(0),
        })
    }
}

impl Class for Stream {
    type Interfaces = (IBStream,);
}

impl IBStreamTrait for Stream {
    unsafe fn read(&self, buffer: *mut c_void, bytes: i32, read: *mut i32) -> tresult {
        let data = self.data.borrow();
        let pos = self.pos.get().min(data.len());
        let n = (bytes.max(0) as usize).min(data.len() - pos);
        unsafe {
            ptr::copy_nonoverlapping(data.as_ptr().add(pos), buffer as *mut u8, n);
            if !read.is_null() {
                *read = n as i32;
            }
        }
        self.pos.set(pos + n);
        OK
    }

    unsafe fn write(&self, buffer: *mut c_void, bytes: i32, written: *mut i32) -> tresult {
        let mut data = self.data.borrow_mut();
        let (pos, n) = (self.pos.get(), bytes.max(0) as usize);
        if data.len() < pos + n {
            data.resize(pos + n, 0);
        }
        unsafe {
            ptr::copy_nonoverlapping(buffer as *const u8, data.as_mut_ptr().add(pos), n);
            if !written.is_null() {
                *written = n as i32;
            }
        }
        self.pos.set(pos + n);
        OK
    }

    unsafe fn seek(&self, pos: i64, mode: i32, result: *mut i64) -> tresult {
        let base = match mode {
            0 => 0,
            1 => self.pos.get() as i64,
            _ => self.data.borrow().len() as i64,
        };
        self.pos.set((base + pos).max(0) as usize);
        if !result.is_null() {
            unsafe { *result = self.pos.get() as i64 };
        }
        OK
    }

    unsafe fn tell(&self, pos: *mut i64) -> tresult {
        unsafe { *pos = self.pos.get() as i64 };
        OK
    }
}

fn stream_ptr(stream: &ComWrapper<Stream>) -> *mut IBStream {
    stream.as_com_ref::<IBStream>().unwrap().as_ptr()
}

/// The note events for one block. Filled and read on the audio thread.
struct EventList {
    events: UnsafeCell<Vec<Event>>,
}

unsafe impl Send for EventList {}
unsafe impl Sync for EventList {}

impl Class for EventList {
    type Interfaces = (IEventList,);
}

impl IEventListTrait for EventList {
    unsafe fn getEventCount(&self) -> i32 {
        unsafe { (&*self.events.get()).len() as i32 }
    }

    unsafe fn getEvent(&self, index: i32, event: *mut Event) -> tresult {
        unsafe {
            let events = &*self.events.get();
            match events.get(index as usize) {
                Some(found) => {
                    ptr::copy_nonoverlapping(found, event, 1);
                    OK
                }
                None => FALSE,
            }
        }
    }

    unsafe fn addEvent(&self, _event: *mut Event) -> tresult {
        FALSE
    }
}

/// One parameter change at the start of the block.
struct ParamQueue {
    id: Cell<ParamID>,
    value: Cell<f64>,
}

unsafe impl Send for ParamQueue {}
unsafe impl Sync for ParamQueue {}

impl Class for ParamQueue {
    type Interfaces = (IParamValueQueue,);
}

impl IParamValueQueueTrait for ParamQueue {
    unsafe fn getParameterId(&self) -> ParamID {
        self.id.get()
    }

    unsafe fn getPointCount(&self) -> i32 {
        1
    }

    unsafe fn getPoint(&self, index: i32, offset: *mut i32, value: *mut ParamValue) -> tresult {
        if index != 0 {
            return FALSE;
        }
        unsafe {
            *offset = 0;
            *value = self.value.get();
        }
        OK
    }

    unsafe fn addPoint(&self, _offset: i32, _value: ParamValue, _index: *mut i32) -> tresult {
        FALSE
    }
}

/// The parameter changes for one block: a fixed pool of queues, of which the
/// first `used` are live.
struct ParamChanges {
    queues: Vec<ComWrapper<ParamQueue>>,
    used: Cell<usize>,
}

unsafe impl Send for ParamChanges {}
unsafe impl Sync for ParamChanges {}

impl Class for ParamChanges {
    type Interfaces = (IParameterChanges,);
}

impl IParameterChangesTrait for ParamChanges {
    unsafe fn getParameterCount(&self) -> i32 {
        self.used.get() as i32
    }

    unsafe fn getParameterData(&self, index: i32) -> *mut IParamValueQueue {
        match self.queues.get(index as usize) {
            Some(queue) if (index as usize) < self.used.get() => {
                queue.as_com_ref::<IParamValueQueue>().unwrap().as_ptr()
            }
            _ => ptr::null_mut(),
        }
    }

    unsafe fn addParameterData(
        &self,
        _id: *const ParamID,
        _index: *mut i32,
    ) -> *mut IParamValueQueue {
        ptr::null_mut()
    }
}

/// Where the plugin reports parameter changes of its own. Some plugins
/// insist on having somewhere to write them; nothing reads them yet.
struct Discard {
    queue: ComWrapper<DiscardQueue>,
}

struct DiscardQueue;

unsafe impl Send for Discard {}
unsafe impl Sync for Discard {}

impl Class for Discard {
    type Interfaces = (IParameterChanges,);
}

impl Class for DiscardQueue {
    type Interfaces = (IParamValueQueue,);
}

impl IParameterChangesTrait for Discard {
    unsafe fn getParameterCount(&self) -> i32 {
        0
    }

    unsafe fn getParameterData(&self, _index: i32) -> *mut IParamValueQueue {
        ptr::null_mut()
    }

    unsafe fn addParameterData(
        &self,
        _id: *const ParamID,
        index: *mut i32,
    ) -> *mut IParamValueQueue {
        if !index.is_null() {
            unsafe { *index = 0 };
        }
        self.queue
            .as_com_ref::<IParamValueQueue>()
            .unwrap()
            .as_ptr()
    }
}

impl IParamValueQueueTrait for DiscardQueue {
    unsafe fn getParameterId(&self) -> ParamID {
        0
    }

    unsafe fn getPointCount(&self) -> i32 {
        0
    }

    unsafe fn getPoint(&self, _index: i32, _offset: *mut i32, _value: *mut ParamValue) -> tresult {
        FALSE
    }

    unsafe fn addPoint(&self, _offset: i32, _value: ParamValue, index: *mut i32) -> tresult {
        if !index.is_null() {
            unsafe { *index = 0 };
        }
        OK
    }
}

// --- an instance -------------------------------------------------------------

struct Shared {
    // Declared in the order they must be released: plugins object to the
    // component going away while its other interfaces are still held.
    processor: ComPtr<IAudioProcessor>,
    controller: Option<ComPtr<IEditController>>,
    component: ComPtr<IComponent>,
    /// The controller is its own object, to be torn down separately.
    separate: bool,
    param_ids: Vec<ParamID>,
    params: Vec<ParamInfo>,
    host: ComWrapper<Host>,
    /// Rendering to a file, faster than real time.
    offline: AtomicBool,
    /// What the processor was set up with, to set it up again.
    max_block: i32,
    sample_rate: f64,
    _module: Arc<Module>,
}

// `processor.process` is called from the audio thread; everything else, and
// the drop, happens on the main thread.
unsafe impl Send for Shared {}
unsafe impl Sync for Shared {}

impl Drop for Shared {
    fn drop(&mut self) {
        unsafe {
            if self.separate
                && let Some(controller) = &self.controller
            {
                if let (Some(a), Some(b)) = (
                    self.component.cast::<IConnectionPoint>(),
                    controller.cast::<IConnectionPoint>(),
                ) {
                    a.disconnect(b.as_ptr());
                    b.disconnect(a.as_ptr());
                }
                controller.terminate();
            }
            self.component.terminate();
        }
    }
}

/// Buffers for every bus in one direction, laid out as VST3 wants them.
struct Buses {
    channels: Vec<Vec<Vec<f32>>>,
    _pointers: Vec<Vec<*mut f32>>,
    buses: Vec<AudioBusBuffers>,
    /// The input bus that takes the side-chain: the first auxiliary one.
    key: Option<usize>,
    /// Each bus's channel count and name.
    infos: Vec<(usize, String)>,
}

impl Buses {
    unsafe fn new(component: &ComPtr<IComponent>, direction: i32, max_block: usize) -> Self {
        unsafe {
            let mut key = None;
            let mut infos = Vec::new();
            let mut channels: Vec<Vec<Vec<f32>>> = (0..component.getBusCount(AUDIO, direction))
                .map(|index| {
                    let mut info: BusInfo = std::mem::zeroed();
                    component.getBusInfo(AUDIO, direction, index, &mut info);
                    infos.push((info.channelCount.max(0) as usize, wide(&info.name)));
                    // The first bus carries the track's audio, the first
                    // auxiliary input a side-chain, and every output is
                    // heard where it is routed.
                    let keys = direction == INPUT
                        && key.is_none()
                        && index > 0
                        && info.busType == AUX
                        && info.channelCount > 0;
                    if keys {
                        key = Some(index as usize);
                    }
                    let active = index == 0 || keys || direction == OUTPUT;
                    component.activateBus(AUDIO, direction, index, active as TBool);
                    (0..info.channelCount.max(0))
                        .map(|_| vec![0.0; max_block])
                        .collect()
                })
                .collect();
            let mut pointers: Vec<Vec<*mut f32>> = channels
                .iter_mut()
                .map(|bus| bus.iter_mut().map(|ch| ch.as_mut_ptr()).collect())
                .collect();
            let buses = pointers
                .iter_mut()
                .map(|bus| {
                    let mut buffers: AudioBusBuffers = std::mem::zeroed();
                    buffers.numChannels = bus.len() as i32;
                    buffers.__field0.channelBuffers32 = bus.as_mut_ptr();
                    buffers
                })
                .collect();
            Self {
                channels,
                _pointers: pointers,
                buses,
                key,
                infos,
            }
        }
    }
}

impl DeviceFactory for Vst3Factory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, max_block: usize) -> Result<Instance> {
        let module = load(&self.bundle)?;
        unsafe {
            let host = ComWrapper::new(Host::default());
            let context = host.as_com_ref::<IHostApplication>().unwrap().as_ptr() as *mut FUnknown;

            let mut raw = ptr::null_mut();
            module.factory.createInstance(
                self.class.as_ptr(),
                IComponent::IID.as_ptr().cast(),
                &mut raw,
            );
            let component: ComPtr<IComponent> =
                ComPtr::from_raw(raw.cast()).context("the plugin could not be created")?;
            if component.initialize(context) != OK {
                bail!("the plugin failed to initialize");
            }
            let processor = component
                .cast::<IAudioProcessor>()
                .context("the plugin does not process audio")?;

            // The controller is either the same object or a class of its own.
            let mut controller = component.cast::<IEditController>();
            let separate = controller.is_none();
            if separate {
                let mut class: TUID = [0; 16];
                let mut raw = ptr::null_mut();
                if component.getControllerClassId(&mut class) == OK {
                    module.factory.createInstance(
                        class.as_ptr(),
                        IEditController::IID.as_ptr().cast(),
                        &mut raw,
                    );
                }
                controller = ComPtr::from_raw(raw.cast());
                if let Some(controller) = &controller {
                    controller.initialize(context);
                    if let (Some(a), Some(b)) = (
                        component.cast::<IConnectionPoint>(),
                        controller.cast::<IConnectionPoint>(),
                    ) {
                        a.connect(b.as_ptr());
                        b.connect(a.as_ptr());
                    }
                }
            }
            let mut shared = Shared {
                processor,
                controller,
                component,
                separate,
                param_ids: Vec::new(),
                params: Vec::new(),
                host: host.clone(),
                offline: AtomicBool::new(false),
                max_block: max_block as i32,
                sample_rate: sample_rate as f64,
                _module: module,
            };
            if let Some(controller) = &shared.controller {
                controller
                    .setComponentHandler(host.as_com_ref::<IComponentHandler>().unwrap().as_ptr());
                // Start the controller from the component's own state.
                let state = Stream::new(Vec::new());
                if shared.component.getState(stream_ptr(&state)) == OK {
                    state.pos.set(0);
                    controller.setComponentState(stream_ptr(&state));
                }
                let units = unit_paths(controller);
                for index in 0..controller.getParameterCount() {
                    let mut info: ParameterInfo = std::mem::zeroed();
                    if controller.getParameterInfo(index, &mut info) != OK
                        || info.flags & (PARAM_HIDDEN | PARAM_READ_ONLY) != 0
                    {
                        continue;
                    }
                    let title = wide(&info.title);
                    // JUCE plugins expose every MIDI controller on every channel
                    // as a parameter: two thousand entries nobody sets by hand.
                    if title.starts_with("MIDI CC ") {
                        continue;
                    }
                    shared.param_ids.push(info.id);
                    let mut param =
                        ParamInfo::new(&title, 0.0, 1.0, info.defaultNormalizedValue as f32, "");
                    param.unit = wide(&info.units);
                    param.id = info.id.to_string();
                    param.group = units.get(&info.unitId).cloned().unwrap_or_default();
                    param.automatable = info.flags & PARAM_CAN_AUTOMATE != 0;
                    param.steps = info.stepCount.max(0) as u32;
                    param.enumeration = info.flags & PARAM_IS_LIST != 0 && param.steps > 0;
                    param.boolean = param.steps == 1 && !param.enumeration;
                    shared.params.push(param);
                }
                assign_keys(&mut shared.params);
            }
            // VST3 has no controller messages: a plugin names the parameter
            // each MIDI controller moves, and the host moves that instead.
            let mut midi_map = Box::new([NO_PARAM; 130]);
            if let Some(mapping) = shared
                .controller
                .as_ref()
                .and_then(|c| c.cast::<IMidiMapping>())
            {
                for (number, slot) in midi_map.iter_mut().enumerate() {
                    let mut id: ParamID = 0;
                    if mapping.getMidiControllerAssignment(0, 0, number as i16, &mut id) == OK {
                        *slot = id;
                    }
                }
            }

            let inputs = Buses::new(&shared.component, INPUT, max_block);
            let outputs = Buses::new(&shared.component, OUTPUT, max_block);
            if shared.component.getBusCount(EVENT, INPUT) > 0 {
                shared.component.activateBus(EVENT, INPUT, 0, 1);
            }
            let mut setup = ProcessSetup {
                processMode: REALTIME,
                symbolicSampleSize: SAMPLE_32,
                maxSamplesPerBlock: max_block as i32,
                sampleRate: sample_rate as f64,
            };
            if shared.processor.setupProcessing(&mut setup) != OK {
                bail!("the plugin rejected the audio setup");
            }
            if shared.component.setActive(1) != OK {
                bail!("the plugin failed to activate");
            }
            shared.processor.setProcessing(1);
            // Frames the plugin rings for after its input stops: 0 for
            // none, all ones for for ever.
            let tail = shared.processor.getTailSamples();

            let shared = Arc::new(shared);
            let (edits, edited) = rtrb::RingBuffer::new(512);
            let out_pairs = crate::out_pairs(&outputs.infos);
            let ports = Ports {
                sidechain: inputs.key.is_some(),
                outputs: crate::pair_names(&out_pairs),
            };
            let device = Vst3Device {
                shared: shared.clone(),
                edited,
                inputs,
                outputs,
                keyed: false,
                out_pairs,
                events: ComWrapper::new(EventList {
                    events: UnsafeCell::new(Vec::with_capacity(1024)),
                }),
                changes: ComWrapper::new(ParamChanges {
                    queues: (0..128)
                        .map(|_| {
                            ComWrapper::new(ParamQueue {
                                id: Cell::new(0),
                                value: Cell::new(0.0),
                            })
                        })
                        .collect(),
                    used: Cell::new(0),
                }),
                discard: ComWrapper::new(Discard {
                    queue: ComWrapper::new(DiscardQueue),
                }),
                pending: Vec::with_capacity(128),
                midi_map,
                controls: Vec::with_capacity(64),
                held: HeldNotes::new(),
                sample_rate: sample_rate as f64,
                samples: 0,
                tail,
                quiet: 0,
                resting: false,
            };
            Ok(Instance {
                device: Box::new(device),
                controller: Some(Box::new(Vst3Controller {
                    preset_dirs: crate::presets::vst3_preset_dirs(
                        &self.info.vendor,
                        &self.info.name,
                        Some(&self.bundle),
                    ),
                    class: hex(&self.class),
                    known: vec![f64::NAN; shared.param_ids.len()],
                    loaded: None,
                    reported: Vec::new(),
                    shared,
                    edits,
                    editor: None,
                    ports,
                })),
            })
        }
    }
}

const NO_PARAM: ParamID = ParamID::MAX;

/// How long after a state what the plugin tells of its values is the echo
/// of that state.
const ECHO: Duration = Duration::from_millis(750);

struct Vst3Device {
    shared: Arc<Shared>,
    /// Edits made in the plugin's editor, which the controller knows about
    /// and the processor still has to be told: parameter index and value.
    edited: rtrb::Consumer<(u32, f32)>,
    inputs: Buses,
    outputs: Buses,
    /// Whether the side-chain bus holds a key.
    keyed: bool,
    /// The output buses as stereo pairs, the main one first.
    out_pairs: Vec<crate::OutPair>,
    events: ComWrapper<EventList>,
    changes: ComWrapper<ParamChanges>,
    discard: ComWrapper<Discard>,
    /// Parameter changes waiting for the next block: index and value.
    pending: Vec<(u32, f32)>,
    /// The parameter each MIDI controller moves, by controller number, with
    /// aftertouch at 128 and the pitch wheel at 129; [`NO_PARAM`] for none.
    midi_map: Box<[ParamID; 130]>,
    /// Controller moves of this block, as parameter and value.
    controls: Vec<(ParamID, f64)>,
    held: HeldNotes,
    sample_rate: f64,
    samples: i64,
    /// How long the plugin rings after its input stops, in frames, as it
    /// said when it was made; `u32::MAX` for for ever.
    tail: u32,
    /// Frames the input has ended with silent and without events.
    quiet: u64,
    /// Its tail has gone by and its output was silent (see
    /// [`Device::resting`]).
    resting: bool,
}

// The buffers hold raw pointers into vectors the device owns.
unsafe impl Send for Vst3Device {}

impl Device for Vst3Device {
    /// Once its tail has gone by in silence and its output was silent,
    /// unless a parameter has moved since.
    fn resting(&self) -> bool {
        self.resting
            && self.pending.is_empty()
            && self.edited.is_empty()
            && !self.shared.host.wake.load(Ordering::Relaxed)
    }

    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        let n = io.left.len();
        self.resting = false;
        // Woken: its tail starts again from here.
        if self.shared.host.wake.swap(false, Ordering::Relaxed) {
            self.quiet = 0;
        }
        self.shared.host.blocks.fetch_add(1, Ordering::Relaxed);
        if paw_engine::device::quiet(io) {
            self.quiet = self.quiet.saturating_add(n as u64);
        } else {
            self.quiet = 0;
        }
        if let Some(bus) = self.inputs.channels.first_mut() {
            match bus.as_mut_slice() {
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
        }
        if let Some(bus) = self.inputs.key.and_then(|b| self.inputs.channels.get_mut(b)) {
            self.keyed = crate::put_key(bus.as_mut_slice(), io.sidechain, self.keyed, n);
        }

        unsafe {
            let events = &mut *self.events.events.get();
            events.clear();
            let (controls, midi_map) = (&mut self.controls, &self.midi_map);
            controls.clear();
            self.held.expand(io.events.as_slice(), |frame, kind| {
                if let EventKind::Control { ctl, value, .. } = kind {
                    let (number, value) = match ctl {
                        Ctl::Cc(number) => ((number & 127) as usize, value),
                        Ctl::Pressure => (128, value),
                        Ctl::Bend => (129, (value + 1.0) * 0.5),
                        // VST3 has nowhere to put these.
                        Ctl::Registered(..) | Ctl::Assignable(..) => return,
                    };
                    if midi_map[number] != NO_PARAM && controls.len() < controls.capacity() {
                        controls.push((midi_map[number], value.clamp(0.0, 1.0)));
                    }
                    return;
                }
                if events.len() == events.capacity() {
                    return;
                }
                let mut event: Event = std::mem::zeroed();
                event.sampleOffset = frame as i32;
                match kind {
                    EventKind::NoteOn { key, vel, ch, .. } => {
                        event.r#type = NOTE_ON;
                        event.__field0.noteOn = NoteOnEvent {
                            channel: ch as i16,
                            pitch: key as i16,
                            tuning: 0.0,
                            velocity: vel,
                            length: 0,
                            noteId: note_id(key, ch),
                        };
                    }
                    EventKind::NoteOff { key, ch } => {
                        event.r#type = NOTE_OFF;
                        event.__field0.noteOff = NoteOffEvent {
                            channel: ch as i16,
                            pitch: key as i16,
                            velocity: 0.0,
                            noteId: note_id(key, ch),
                            tuning: 0.0,
                        };
                    }
                    EventKind::NoteControl {
                        key,
                        ctl: NoteCtl::Pressure,
                        value,
                        ch,
                    } => {
                        event.r#type = POLY_PRESSURE;
                        event.__field0.polyPressure = PolyPressureEvent {
                            channel: ch as i16,
                            pitch: key as i16,
                            pressure: value as f32,
                            noteId: note_id(key, ch),
                        };
                    }
                    // A note's own controllers are VST3's note expressions.
                    EventKind::NoteControl {
                        key,
                        ctl,
                        value,
                        ch,
                    } => {
                        let (type_id, value) = match ctl {
                            // Tuning is 0.5 at rest and spans 120 semitones each way.
                            NoteCtl::Bend => (2, 0.5 + value * NOTE_BEND_RANGE / 240.0),
                            NoteCtl::Registered(7) => (0, value * 0.25),
                            NoteCtl::Registered(10) => (1, value),
                            NoteCtl::Registered(1) => (3, value),
                            NoteCtl::Registered(11) => (4, value),
                            NoteCtl::Registered(74) => (5, value),
                            _ => return,
                        };
                        event.r#type = NOTE_EXPRESSION;
                        event.__field0.noteExpressionValue = NoteExpressionValueEvent {
                            typeId: type_id,
                            noteId: note_id(key, ch),
                            value,
                        };
                    }
                    EventKind::AllNotesOff
                    | EventKind::Control { .. }
                    | EventKind::Program { .. } => return,
                }
                events.push(event);
            });

            while let Ok(edit) = self.edited.pop() {
                if self.pending.len() < self.pending.capacity() {
                    self.pending.push(edit);
                }
            }
            let mut used = 0;
            for (index, value) in self.pending.drain(..) {
                let Some(&id) = self.shared.param_ids.get(index as usize) else {
                    continue;
                };
                // One queue for each parameter: the last value set wins (a
                // value a state gave comes after one set before it).
                if let Some(queue) = self.changes.queues[..used].iter().find(|q| q.id.get() == id) {
                    queue.value.set(value as f64);
                    continue;
                }
                let Some(queue) = self.changes.queues.get(used) else {
                    continue;
                };
                queue.id.set(id);
                queue.value.set(value as f64);
                used += 1;
            }
            for (id, value) in self.controls.drain(..) {
                let Some(queue) = self.changes.queues.get(used) else {
                    break;
                };
                queue.id.set(id);
                queue.value.set(value);
                used += 1;
            }
            self.changes.used.set(used);

            let mut context: ProcessContext = std::mem::zeroed();
            context.state = TEMPO_VALID
                | TIME_SIG_VALID
                | MUSIC_TIME_VALID
                | BAR_VALID
                | if ctx.playing { PLAYING } else { 0 };
            context.sampleRate = self.sample_rate;
            context.projectTimeSamples = self.samples;
            context.continousTimeSamples = self.samples;
            context.projectTimeMusic = ctx.position;
            context.barPositionMusic = ctx.bar_start;
            context.tempo = ctx.tempo;
            context.timeSigNumerator = ctx.sig_num as i32;
            context.timeSigDenominator = ctx.sig_den as i32;
            self.samples += n as i64;

            let mut data: ProcessData = std::mem::zeroed();
            data.processMode = if self.shared.offline.load(Ordering::Relaxed) {
                OFFLINE
            } else {
                REALTIME
            };
            data.symbolicSampleSize = SAMPLE_32;
            data.numSamples = n as i32;
            data.numInputs = self.inputs.buses.len() as i32;
            data.numOutputs = self.outputs.buses.len() as i32;
            data.inputs = self.inputs.buses.as_mut_ptr();
            data.outputs = self.outputs.buses.as_mut_ptr();
            data.inputParameterChanges = self
                .changes
                .as_com_ref::<IParameterChanges>()
                .unwrap()
                .as_ptr();
            data.outputParameterChanges = self
                .discard
                .as_com_ref::<IParameterChanges>()
                .unwrap()
                .as_ptr();
            data.inputEvents = self.events.as_com_ref::<IEventList>().unwrap().as_ptr();
            data.processContext = &mut context;
            if self.shared.processor.process(&mut data) != OK {
                return;
            }
        }
        self.resting = self.tail != u32::MAX
            && self.quiet >= self.tail as u64
            && self.outputs.channels.iter().flatten().all(|c| paw_engine::device::silent(&c[..n]));

        let add = self.inputs.buses.is_empty();
        if let Some(bus) = self.outputs.channels.first() {
            match bus.as_slice() {
                [] => {}
                [mono] => write_output(io.left, io.right, &[&mono[..n]], add),
                [left, right, ..] => {
                    write_output(io.left, io.right, &[&left[..n], &right[..n]], add)
                }
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

impl Drop for Vst3Device {
    /// Runs on the main thread, after the audio thread has let go of the device.
    fn drop(&mut self) {
        unsafe {
            self.shared.processor.setProcessing(0);
            self.shared.component.setActive(0);
        }
    }
}

struct Vst3Controller {
    shared: Arc<Shared>,
    /// Where this plugin's `.vstpreset` files are, and the class id they name.
    preset_dirs: Vec<PathBuf>,
    class: String,
    edits: rtrb::Producer<(u32, f32)>,
    /// The last value seen for each parameter, to tell what a rescan changed.
    known: Vec<f64>,
    /// When it was last given a state, and how many blocks the processor
    /// had run then (`u64::MAX` once the controller has read the state
    /// again).
    loaded: Option<(Instant, u64)>,
    /// Values a state gave the controller, to report.
    reported: Vec<(usize, f64)>,
    editor: Option<Editor>,
    ports: Ports,
}

impl Vst3Controller {
    /// React to what happened to the editor window and what the plugin asked for.
    fn run_editor(&mut self) {
        let Some(editor) = self.editor.as_mut() else {
            return;
        };
        let mut close = false;
        unsafe {
            let fit = |editor: &mut Editor, width: u32, height: u32| {
                let mut rect = ViewRect {
                    left: 0,
                    top: 0,
                    right: width as i32,
                    bottom: height as i32,
                };
                editor.view.onSize(&mut rect);
                editor.window.resize(width, height);
            };
            if let Some((width, height)) = editor.frame.resize.take() {
                fit(editor, width, height);
            }
            for event in editor.window.events() {
                match event {
                    WindowEvent::Closed => close = true,
                    WindowEvent::Resized(width, height) => {
                        let mut rect = ViewRect {
                            left: 0,
                            top: 0,
                            right: width as i32,
                            bottom: height as i32,
                        };
                        if editor.view.canResize() == OK {
                            // The plugin may round the size to one it can draw.
                            editor.view.checkSizeConstraint(&mut rect);
                        } else {
                            editor.view.getSize(&mut rect);
                        }
                        fit(
                            editor,
                            (rect.right - rect.left).max(1) as u32,
                            (rect.bottom - rect.top).max(1) as u32,
                        );
                    }
                }
            }
        }
        if close {
            self.close_editor();
        }
    }
}

impl Drop for Vst3Controller {
    fn drop(&mut self) {
        self.close_editor();
    }
}

impl Controller for Vst3Controller {
    fn ports(&self) -> Ports {
        self.ports.clone()
    }

    fn set_offline(&mut self, offline: bool) {
        // The mode is part of the processing setup, which can only be
        // changed while the processor is stopped.
        let shared = &self.shared;
        unsafe {
            shared.processor.setProcessing(0);
            shared.component.setActive(0);
            let mut setup = ProcessSetup {
                processMode: if offline { OFFLINE } else { REALTIME },
                symbolicSampleSize: SAMPLE_32,
                maxSamplesPerBlock: shared.max_block,
                sampleRate: shared.sample_rate,
            };
            if shared.processor.setupProcessing(&mut setup) == OK {
                shared.offline.store(offline, Ordering::Relaxed);
            }
            shared.component.setActive(1);
            shared.processor.setProcessing(1);
        }
    }

    fn params(&self) -> Vec<ParamInfo> {
        self.shared.params.clone()
    }

    fn value_text(&mut self, index: usize, value: f64) -> Option<String> {
        let id = *self.shared.param_ids.get(index)?;
        let controller = self.shared.controller.as_ref()?;
        let mut text: String128 = [0; 128];
        unsafe {
            (controller.getParamStringByValue(id, value, &mut text) == OK)
                .then(|| wide(&text))
                .filter(|t| !t.is_empty())
        }
    }

    fn text_value(&mut self, index: usize, text: &str) -> Option<f64> {
        let id = *self.shared.param_ids.get(index)?;
        let controller = self.shared.controller.as_ref()?;
        let mut units: Vec<TChar> = text.encode_utf16().map(|u| u as TChar).collect();
        units.push(0);
        let mut value = 0.0;
        unsafe {
            (controller.getParamValueByString(id, units.as_mut_ptr(), &mut value) == OK)
                .then_some(value)
                .filter(|v| v.is_finite())
        }
    }

    fn value(&self, index: usize) -> Option<f64> {
        let id = *self.shared.param_ids.get(index)?;
        Some(unsafe { self.shared.controller.as_ref()?.getParamNormalized(id) })
    }

    fn set_value(&mut self, index: usize, value: f64) {
        if let (Some(&id), Some(controller)) =
            (self.shared.param_ids.get(index), &self.shared.controller)
        {
            unsafe { controller.setParamNormalized(id, value) };
        }
    }

    fn idle(&mut self) {
        self.shared.host.watches.run();
        self.run_editor();
        // A processor that takes a state on in its next block (JUCE queues
        // it there) has its new values only then: the controller, which
        // read them from it as it was given the state, reads them again.
        if let Some((at, blocks)) = self.loaded
            && blocks != u64::MAX
            && self.shared.host.blocks.load(Ordering::Relaxed) != blocks
        {
            self.loaded = Some((at, u64::MAX));
            if let Some(controller) = &self.shared.controller {
                unsafe {
                    let state = Stream::new(Vec::new());
                    if self.shared.component.getState(stream_ptr(&state)) == OK {
                        state.pos.set(0);
                        controller.setComponentState(stream_ptr(&state));
                        self.shared.host.rescan.set(true);
                    }
                }
            }
        }
    }

    fn take_changes(&mut self) -> Vec<(usize, f64)> {
        let mut out = std::mem::take(&mut self.reported);
        // Shortly after a state, what the plugin tells of its values is the
        // echo of the state, which the processor has already: passed on, an
        // echo of a state given before an undo would play the old value.
        let echo = self.loaded.is_some_and(|(at, _)| at.elapsed() < ECHO);
        for (id, value, gesture) in self.shared.host.edits.take() {
            if let Some(index) = self.shared.param_ids.iter().position(|known| *known == id) {
                // The controller already has the value; the processor does not.
                if gesture || !echo {
                    let _ = self.edits.push((index as u32, value as f32));
                }
                self.known[index] = value;
                out.push((index, value));
            }
        }
        if self.shared.host.rescan.replace(false) {
            for index in 0..self.known.len() {
                if let Some(value) = self.value(index)
                    && value != self.known[index]
                {
                    // The first reading only records where things stand.
                    let first = self.known[index].is_nan();
                    self.known[index] = value;
                    if !first {
                        if !echo {
                            let _ = self.edits.push((index as u32, value as f32));
                        }
                        out.push((index, value));
                    }
                }
            }
        }
        out
    }

    fn has_editor(&self) -> bool {
        // Whether a view can actually be made is only known by trying.
        self.shared.controller.is_some()
    }

    fn editor_open(&self) -> bool {
        self.editor.is_some()
    }

    fn open_editor(&mut self, title: &str) -> Result<()> {
        if self.editor.is_some() {
            return Ok(());
        }
        let controller = self
            .shared
            .controller
            .as_ref()
            .context("this plugin has no editor")?;
        unsafe {
            let view: ComPtr<IPlugView> =
                ComPtr::from_raw(controller.createView(c"editor".as_ptr()))
                    .context("this plugin has no editor")?;
            if view.isPlatformTypeSupported(X11_EMBED.as_ptr()) != OK {
                bail!("the plugin's editor cannot be embedded in an X11 window");
            }
            let frame = ComWrapper::new(Frame {
                resize: Cell::new(None),
                watches: self.shared.host.watches.clone(),
            });
            view.setFrame(frame.as_com_ref::<IPlugFrame>().unwrap().as_ptr());
            // Before asking for the size, which depends on it.
            if let Some(scaling) = view.cast::<IPlugViewContentScaleSupport>() {
                scaling.setContentScaleFactor(ui_scale() as f32);
            }
            let mut rect = ViewRect {
                left: 0,
                top: 0,
                right: 640,
                bottom: 480,
            };
            view.getSize(&mut rect);
            let (width, height) = (
                (rect.right - rect.left).max(1) as u32,
                (rect.bottom - rect.top).max(1) as u32,
            );
            let mut window = HostWindow::new(title, width, height)?;
            window.set_fixed(view.canResize() != OK);
            if view.attached(window.id() as usize as *mut c_void, X11_EMBED.as_ptr()) != OK {
                view.setFrame(ptr::null_mut());
                bail!("the plugin refused the editor window");
            }
            self.shared.host.rescan.set(true);
            self.editor = Some(Editor {
                view,
                frame,
                window,
            });
        }
        self.take_changes();
        Ok(())
    }

    fn close_editor(&mut self) {
        if let Some(editor) = self.editor.take() {
            unsafe {
                editor.view.removed();
                editor.view.setFrame(ptr::null_mut());
            }
            // The view goes first, then the window it was drawn in.
            drop(editor.view);
            drop(editor.window);
        }
    }

    fn call(&mut self, method: &str, data: &[u8]) -> Result<Vec<u8>> {
        // Presets are `.vstpreset` files: the same two states this host
        // saves, in a container with the plugin's class id.
        let ours = |path: &Path| {
            let mut head = [0u8; 40];
            std::fs::File::open(path)
                .and_then(|mut f| std::io::Read::read_exact(&mut f, &mut head))
                .is_ok()
                && head[8..40].eq_ignore_ascii_case(self.class.as_bytes())
        };
        match method {
            "presets" => {
                let mut presets = crate::presets::vst3_presets(&self.preset_dirs);
                presets.retain(|p| ours(Path::new(&p.id)));
                Ok(crate::presets::to_json(&presets))
            }
            "preset.load" => {
                let path = PathBuf::from(String::from_utf8_lossy(data).into_owned());
                let bytes =
                    std::fs::read(&path).with_context(|| format!("reading {}", path.display()))?;
                let (class, comp, cont) = crate::presets::read_vstpreset(&bytes)?;
                if !class.eq_ignore_ascii_case(&self.class) {
                    bail!("{} is a preset of another plugin", path.display());
                }
                let mut state = Vec::new();
                for part in [comp, cont] {
                    state.extend_from_slice(&(part.len() as u32).to_le_bytes());
                    state.extend_from_slice(&part);
                }
                self.load_state(&state)?;
                Ok(Vec::new())
            }
            // A preset file of the plugin as it is now, for other hosts.
            "preset.export" => {
                let state = self.save_state()?.unwrap_or_default();
                let mut rest = state.as_slice();
                let mut part = || -> Vec<u8> {
                    let Some((size, tail)) = rest.split_at_checked(4) else {
                        return Vec::new();
                    };
                    let size = u32::from_le_bytes(size.try_into().unwrap()) as usize;
                    let (data, tail) = tail.split_at_checked(size).unwrap_or((tail, &[]));
                    rest = tail;
                    data.to_vec()
                };
                let (comp, cont) = (part(), part());
                Ok(crate::presets::write_vstpreset(&self.class, &comp, &cont))
            }
            _ => bail!("this device has no method `{method}`"),
        }
    }

    /// The component's state, then the controller's, each prefixed by its length.
    fn save_state(&mut self) -> Result<Option<Vec<u8>>> {
        let mut out = Vec::new();
        unsafe {
            let component = Stream::new(Vec::new());
            if self.shared.component.getState(stream_ptr(&component)) != OK {
                return Ok(None);
            }
            let controller = Stream::new(Vec::new());
            if let Some(c) = &self.shared.controller {
                c.getState(stream_ptr(&controller));
            }
            for part in [component, controller] {
                let data = part.data.borrow();
                out.extend_from_slice(&(data.len() as u32).to_le_bytes());
                out.extend_from_slice(&data);
            }
        }
        Ok(Some(out))
    }

    fn load_state(&mut self, state: &[u8]) -> Result<()> {
        let mut rest = state;
        let mut part = || -> Result<Vec<u8>> {
            let (size, tail) = rest
                .split_at_checked(4)
                .context("the saved state is cut short")?;
            let size = u32::from_le_bytes(size.try_into().unwrap()) as usize;
            let (data, tail) = tail
                .split_at_checked(size)
                .context("the saved state is cut short")?;
            rest = tail;
            Ok(data.to_vec())
        };
        let (component, controller) = (part()?, part()?);
        let before: Vec<Option<f64>> = (0..self.known.len()).map(|i| self.value(i)).collect();
        unsafe {
            let stream = Stream::new(component);
            if self.shared.component.setState(stream_ptr(&stream)) != OK {
                bail!("the plugin rejected the saved state");
            }
            if let Some(c) = &self.shared.controller {
                stream.pos.set(0);
                c.setComponentState(stream_ptr(&stream));
                if !controller.is_empty() {
                    c.setState(stream_ptr(&Stream::new(controller)));
                }
            }
        }
        // The values the controller took from the state as it was given
        // it: the processor may still have a parameter set before the
        // state waiting for its next block, so it is given these after it.
        // (A plugin that takes the state on only in its next block has the
        // old values here: nothing changed, nothing is passed on.)
        self.shared.host.edits.borrow_mut().retain(|(_, _, gesture)| *gesture);
        for (index, old) in before.into_iter().enumerate() {
            if let Some(value) = self.value(index)
                && Some(value) != old
            {
                let _ = self.edits.push((index as u32, value as f32));
                self.known[index] = value;
                self.reported.push((index, value));
            }
        }
        // Some plugins only queue the state here and take it on in their
        // next block: a processor that sleeps would never take it.
        self.shared.host.wake.store(true, Ordering::Relaxed);
        self.loaded = Some((
            Instant::now(),
            self.shared.host.blocks.load(Ordering::Relaxed),
        ));
        Ok(())
    }
}
