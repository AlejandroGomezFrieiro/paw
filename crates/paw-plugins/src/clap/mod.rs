//! CLAP hosting. The file's entry, its plugin factory, the plugin instance,
//! the host's callbacks, processing (events, buffers, transport, tail) and the
//! plugin's extensions go through Clack (`clack-host` and `clack-extensions`).
//! paw's own types are the extensions Clack has none for: the preset-load
//! extension's compatible id and paw's `dev.paw.call/1`.
//!
//! Threading follows the CLAP rules: a plugin is created, activated,
//! deactivated and destroyed on the main thread, and `start_processing` and
//! `process` run on the audio thread. [`device::ClapDevice`] is the
//! audio-thread half and [`controller::ClapController`] the main-thread half;
//! both hold the same [`shared::Shared`], which destroys the plugin when the
//! last of them is dropped.
//!
//! The files, by role:
//!
//! - `library.rs`: the load of a `.clap` file and the list of its plugins.
//! - `host.rs`: what the host offers the plugin (its callbacks), and the
//!   flags in which they note what the plugin asked for.
//! - `shared.rs`: the plugin instance that both halves hold.
//! - `factory.rs`: the creation of an instance, and what the plugin tells of
//!   itself (parameters, ports, note dialects, key names).
//! - `device.rs`: the audio thread only: `process` and its buffers.
//! - `events.rs`: paw's events to CLAP's events, and the plugin's output
//!   events back.
//! - `controller.rs`: the main-thread half: parameters, changes, calls and
//!   attachments.
//! - `editor.rs`: the plugin's editor window.
//! - `state.rs`: the plugin's state and its presets.

mod controller;
mod device;
mod editor;
mod events;
mod factory;
mod host;
mod library;
mod shared;
mod state;

use std::ffi::CString;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use anyhow::Result;
use paw_engine::{DeviceFactory, DeviceFormat, DeviceInfo, Registry};

use crate::{Found, PluginDirs, PluginFormat};

/// The text in a fixed-size buffer that a plugin filled, as Clack gives it:
/// up to its first NUL, or the whole buffer when the plugin wrote none.
fn buffer_text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

/// Load a file and list the plugins in it.
/// What is in a plugin file, for the helper that looks into them.
pub(crate) fn list_file(path: &Path, libraries: &[PathBuf]) -> Result<Vec<Found>> {
    library::list(path, libraries)
}

/// CLAP, for [`scan_in`](crate::scan_in): a `.clap` is a single shared
/// library on Linux, and its plugins are `clap:<id>`.
pub(crate) struct Clap;

impl PluginFormat for Clap {
    const NAME: &'static str = "clap";
    const FORMAT: DeviceFormat = DeviceFormat::Clap;
    const ONE_PER_ID: bool = false;

    fn library(bundle: &Path) -> Option<PathBuf> {
        (!bundle.is_dir()).then(|| bundle.to_path_buf())
    }

    fn usual(dirs: &PluginDirs) -> &[PathBuf] {
        &dirs.clap
    }

    fn list(bundle: &Path, libraries: &[PathBuf]) -> Result<Vec<Found>> {
        library::list(bundle, libraries)
    }

    fn kind(found: &Found, _registry: &Registry) -> String {
        format!("clap:{}", found.id)
    }

    fn factory(
        info: DeviceInfo,
        bundle: &Path,
        dirs: &PluginDirs,
    ) -> Option<Rc<dyn DeviceFactory>> {
        let id = CString::new(info.id.as_str()).ok()?;
        Some(Rc::new(factory::ClapFactory {
            info,
            id,
            path: bundle.to_path_buf(),
            libraries: dirs.libraries.clone(),
        }))
    }
}
