//! VST3 hosting over the COM bindings.
//!
//! A VST3 plugin is a component that processes audio and an edit controller
//! that owns the parameters; some plugins implement both in one object. The
//! component's `process` runs on the audio thread and everything else on the
//! main thread. Parameter values are normalized to 0..1.
//!
//! The files, by role:
//!
//! - `library.rs`: the load of a `.vst3` bundle and the list of its plugins.
//! - `host.rs`: what the host gives the plugin: the host application, the
//!   component handler, the editor's frame and the run loop.
//! - `shared.rs`: the plugin's COM objects, which both halves hold.
//! - `factory.rs`: the creation of an instance, and its parameters.
//! - `device.rs`: the audio thread only: `process` and its buses.
//! - `events.rs`: paw's events to VST3's events, parameter changes and
//!   process context.
//! - `controller.rs`: the main-thread half: parameters and changes.
//! - `editor.rs`: the plugin's editor window.
//! - `state.rs`: the state streams and the `.vstpreset` presets.

mod controller;
mod device;
mod editor;
mod events;
mod factory;
mod host;
mod library;
mod shared;
mod state;

use std::ffi::c_char;
use std::path::{Path, PathBuf};
use std::rc::Rc;

use anyhow::Result;
use paw_engine::{DeviceFactory, DeviceFormat, DeviceInfo, Registry};
use vst3::Steinberg::Vst::TChar;
use vst3::Steinberg::{TUID, tresult};

use crate::{Found, PluginFormat};

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
    hex::encode_upper(id.map(|b| b as u8))
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
    library::list(bundle)
}

/// VST3, for [`scan_in`](crate::scan_in): a `.vst3` bundle holds a shared
/// library, and its plugins are `vst3:<name>`.
pub(crate) struct Vst3;

impl PluginFormat for Vst3 {
    const NAME: &'static str = "vst3";
    const FORMAT: DeviceFormat = DeviceFormat::Vst3;
    const ENV: &'static str = "VST3_PATH";
    // The same plugin installed in two places is one plugin.
    const ONE_PER_ID: bool = true;

    fn library(bundle: &Path) -> Option<PathBuf> {
        Some(library::library_path(bundle)).filter(|library| library.is_file())
    }

    fn list(bundle: &Path) -> Result<Vec<Found>> {
        library::list(bundle)
    }

    /// The name is the handle, so two plugins cannot share one.
    fn kind(found: &Found, registry: &Registry) -> String {
        let mut kind = format!("vst3:{}", found.name);
        let mut copy = 2;
        while registry.get(&kind).is_some() {
            kind = format!("vst3:{} ({copy})", found.name);
            copy += 1;
        }
        kind
    }

    fn factory(info: DeviceInfo, bundle: &Path) -> Option<Rc<dyn DeviceFactory>> {
        let class = unhex(&info.id)?;
        Some(Rc::new(factory::Vst3Factory {
            info,
            bundle: bundle.to_path_buf(),
            class,
        }))
    }
}
