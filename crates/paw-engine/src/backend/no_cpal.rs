//! Stands in for `cpal.rs` in a build without the `cpal` feature: the same
//! names, and no device.

use std::sync::{Arc, Mutex};

use anyhow::Result;

use super::{BackendChoice, BackendOptions, DeviceList, Lost, Opened};
use crate::engine::Engine;

/// No device can be chosen, so this is never made.
pub enum Devices {}

/// No stream runs, so this is never made.
pub enum Running {}

/// The text of the warning when `auto` falls back to the null backend.
pub fn fallback_warning(_err: &anyhow::Error) -> String {
    "built without audio device support".into()
}

pub fn backends() -> Vec<String> {
    Vec::new()
}

pub fn list_devices(opts: &BackendOptions) -> Result<DeviceList> {
    Ok(super::null_devices(opts))
}

pub fn open(opts: &BackendOptions) -> Result<Opened> {
    if opts.backend == BackendChoice::Auto {
        anyhow::bail!("built without audio device support")
    }
    anyhow::bail!("unknown audio backend `{}`", opts.backend)
}

pub fn start(
    devices: Devices,
    _parked: Arc<Mutex<Option<Engine>>>,
    _lost: Arc<Lost>,
) -> Result<Running> {
    match devices {}
}

// Stops the streams in the real module; here it keeps `drop(stream.cpal.take())` meaningful.
impl Drop for Running {
    fn drop(&mut self) {
        match *self {}
    }
}
