//! The load of a `.vst3` bundle, and the list of the plugins in it.

use std::ffi::c_void;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result, bail};
use vst3::Steinberg::Vst::IHostApplication;
use vst3::Steinberg::*;
use vst3::{ComPtr, ComWrapper};

use super::host::Host;
use super::{OK, chars};
use crate::Found;

/// A loaded VST3 module. Never unloaded.
pub(super) struct Module {
    pub(super) factory: ComPtr<IPluginFactory>,
    /// The host as the factory knows it, for as long as the module lives.
    _host: ComWrapper<Host>,
}

// SAFETY: The factory and the host object belong to a module that is never unloaded and sit in a
// static list, so they are never dropped. The host object holds `Rc`, `RefCell` and `Cell`, which
// are not thread safe: these impls are sound only under the convention that every call through the
// factory, and every call a plugin makes into the host's `IComponentHandler` and `IRunLoop`, is on
// the main thread (the thread that called `crate::register`). paw keeps its side of it, and `load`
// and the component handler check it in debug builds; a plugin keeps its side by the VST3 rule that
// the edit controller and its host interfaces belong to the UI thread (a JUCE plugin, given the
// host's `IRunLoop`, runs its message loop from it, on the main thread; one that calls from another
// thread breaks the convention, which a debug build reports).
unsafe impl Send for Module {}
// SAFETY: See `Send`: every call through the factory and the host is on the main thread.
unsafe impl Sync for Module {}

/// The shared library inside a `.vst3` bundle.
pub(super) fn library_path(bundle: &Path) -> PathBuf {
    let arch = format!("{}-linux", std::env::consts::ARCH);
    let name = bundle.file_stem().unwrap_or_default();
    bundle
        .join("Contents")
        .join(arch)
        .join(name)
        .with_extension("so")
}

/// Load the module of `bundle`, or return it if it is loaded already. The
/// libraries that it needs are looked for in `libraries`.
pub(super) fn load(bundle: &Path, libraries: &[PathBuf]) -> Result<Arc<Module>> {
    crate::debug_assert_main_thread();
    static LOADED: Mutex<Vec<(PathBuf, Arc<Module>)>> = Mutex::new(Vec::new());
    let mut loaded = LOADED.lock().unwrap();
    if let Some((_, module)) = loaded.iter().find(|(p, _)| p == bundle) {
        return Ok(module.clone());
    }
    let path = library_path(bundle);
    // SAFETY: The module is opened by `open_library` and its handle is never closed; `ModuleEntry` and
    // `GetPluginFactory` are the symbols the VST3 ABI names and have the types given; the
    // entry gets the module's own handle. The factory pointer is checked for null before use, and
    // `ComPtr` owns one reference to it. Main thread, once per bundle (under the LOADED lock).
    let module = unsafe {
        let handle = crate::libs::open_library(&path, libraries)
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

pub(super) fn list(bundle: &Path, libraries: &[PathBuf]) -> Result<Vec<Found>> {
    let module = load(bundle, libraries)?;
    let mut found = Vec::new();
    // SAFETY: `module.factory` is a live COM object of a module that is never unloaded; each `info` is a
    // zeroed plain-data struct that the factory fills for an index below `countClasses`.
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
                id: hex::encode_upper(info.cid.map(|b| b as u8)),
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
