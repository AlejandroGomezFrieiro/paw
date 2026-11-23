//! The load of a `.clap` file, and the list of the plugins in it.

use std::ffi::{CStr, CString};
use std::mem::ManuallyDrop;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
use clap_sys::entry::clap_plugin_entry;
use clack_host::entry::{EntryDescriptor, PluginEntry, PluginEntryError};

use crate::Found;

/// A loaded `.clap` file. Never unloaded: plugins commonly leave threads and
/// static state behind that do not survive it.
pub(super) struct Library {
    _lib: ManuallyDrop<libloading::Library>,
    /// The file's entry, initialized. Kept for good in `load`'s list, so
    /// Clack never calls the entry's `deinit`.
    pub(super) entry: PluginEntry,
}

/// Load a `.clap` file, or return it if it is loaded already. The
/// libraries that it needs are looked for in `libraries`.
pub(super) fn load(path: &Path, libraries: &[PathBuf]) -> Result<Arc<Library>> {
    static LOADED: Mutex<Vec<(PathBuf, Arc<Library>)>> = Mutex::new(Vec::new());
    let mut loaded = LOADED.lock().unwrap();
    if let Some((_, library)) = loaded.iter().find(|(p, _)| p == path) {
        return Ok(library.clone());
    }
    let lib = libloading::Library::from(crate::libs::open_library(path, libraries)?);
    // SAFETY: `clap_entry` is the symbol the CLAP ABI names and has the type `clap_plugin_entry`.
    // The file is never unloaded (`ManuallyDrop` below), so the entry it points to is `'static`.
    let entry: &'static EntryDescriptor = unsafe {
        let entry = *lib.get::<*const clap_plugin_entry>(b"clap_entry\0")?;
        entry.as_ref().context("no entry point")?
    };
    entry.init.context("no init")?;
    entry.get_factory.context("no factory")?;
    let c_path = CString::new(path.to_string_lossy().as_bytes())?;
    // SAFETY: `entry` is the file's own entry, valid for good (see above). Clack checks its CLAP
    // version and calls its `init` once with the path, on the main thread (under the LOADED lock).
    let entry = unsafe { PluginEntry::load_from_raw(entry, &c_path) }.map_err(|err| match err {
        PluginEntryError::EntryInitFailed => anyhow::anyhow!("the plugin refused to initialize"),
        err => anyhow::anyhow!("{err}"),
    })?;
    entry
        .get_plugin_factory()
        .context("the file has no plugin factory")?;
    let library = Arc::new(Library {
        _lib: ManuallyDrop::new(lib),
        entry,
    });
    loaded.push((path.to_path_buf(), library.clone()));
    Ok(library)
}

pub(super) fn list(path: &Path, libraries: &[PathBuf]) -> Result<Vec<Found>> {
    let library = load(path, libraries)?;
    let factory = library
        .entry
        .get_plugin_factory()
        .context("the file has no plugin factory")?;
    let raw = factory.raw().get();
    raw.get_plugin_count.context("no plugin count")?;
    raw.get_plugin_descriptor.context("no descriptors")?;
    let text = |text: Option<&CStr>| text.map_or_else(String::new, |t| t.to_string_lossy().into_owned());
    Ok(factory
        .plugin_descriptors()
        .map(|desc| Found {
            id: text(desc.id()),
            name: text(desc.name()),
            vendor: text(desc.vendor()),
            instrument: desc.features().any(|f| f.to_bytes() == b"instrument"),
            version: text(desc.version()),
            features: desc.features().map(|f| text(Some(f))).collect(),
        })
        .collect())
}
