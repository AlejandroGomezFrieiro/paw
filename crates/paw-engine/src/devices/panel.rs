//! The main-thread side of the built-in effects that report something
//! (a curve, gain reduction, loudness, pitch) or whose latency depends on a
//! setting. The device and its [`Face`] are made together and share
//! whatever they need through atomics ([`super::dsp::Readings`],
//! [`super::dsp::Tap`]); the face keeps a copy of the parameter values,
//! which the host gives it alongside every change it sends the device.
//!
//! Scripts reach a face through `paw.api.device_call(id, method, data)`;
//! answers are text: numbers separated by spaces, or `name value` lines.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]

use anyhow::{Result, bail};

use crate::device::{Controller, Device, DeviceFactory, DeviceInfo, Instance, ParamInfo, Ports};

pub trait Face {
    /// Answer a request. `values` are the device's parameters as set now.
    fn call(&mut self, values: &[f32], method: &str, data: &[u8]) -> Result<Vec<u8>> {
        let _ = (values, data);
        bail!("this device has no method `{method}`")
    }
    /// Frames by which the output is behind the input with these settings.
    fn latency(&self, values: &[f32]) -> u32 {
        let _ = values;
        0
    }
    /// Whether the device listens to a side-chain.
    fn sidechain(&self) -> bool {
        false
    }
}

/// The two halves of a new built-in effect.
pub type Pair = (Box<dyn Device>, Box<dyn Face>);

pub struct Factory {
    pub info: DeviceInfo,
    pub make: fn(f32) -> Pair,
}

impl DeviceFactory for Factory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, _max_block: usize) -> Result<Instance> {
        let (device, face) = (self.make)(sample_rate);
        Ok(Instance {
            device,
            controller: Some(Box::new(Panel {
                values: self.info.params.iter().map(|p| p.default).collect(),
                params: self.info.params.clone(),
                face,
            })),
        })
    }

    fn latency(&self, sample_rate: f32) -> u32 {
        let (_, face) = (self.make)(sample_rate);
        face.latency(
            &self
                .info
                .params
                .iter()
                .map(|p| p.default)
                .collect::<Vec<_>>(),
        )
    }
}

struct Panel {
    params: Vec<ParamInfo>,
    values: Vec<f32>,
    face: Box<dyn Face>,
}

impl Controller for Panel {
    fn params(&self) -> Vec<ParamInfo> {
        self.params.clone()
    }

    fn value(&self, _index: usize) -> Option<f64> {
        // The project holds every value; there is nothing of our own.
        None
    }

    fn set_value(&mut self, index: usize, value: f64) {
        if let Some(v) = self.values.get_mut(index) {
            *v = value as f32;
        }
    }

    fn save_state(&mut self) -> Result<Option<Vec<u8>>> {
        Ok(None)
    }

    fn load_state(&mut self, _state: &[u8]) -> Result<()> {
        Ok(())
    }

    fn latency(&self) -> u32 {
        self.face.latency(&self.values)
    }

    fn call(&mut self, method: &str, data: &[u8]) -> Result<Vec<u8>> {
        self.face.call(&self.values, method, data)
    }

    fn ports(&self) -> Ports {
        Ports {
            sidechain: self.face.sidechain(),
            ..Ports::default()
        }
    }
}

/// Numbers as text, separated by spaces, with `digits` decimals.
pub fn numbers(values: impl IntoIterator<Item = f64>, digits: usize) -> Vec<u8> {
    let mut out = String::new();
    for (i, v) in values.into_iter().enumerate() {
        if i > 0 {
            out.push(' ');
        }
        let v = if v.is_finite() { v } else { -200.0 };
        out.push_str(&format!("{v:.digits$}"));
    }
    out.into_bytes()
}

/// `name value` lines.
pub fn fields(pairs: &[(&str, f64)]) -> Vec<u8> {
    let mut out = String::new();
    for (name, v) in pairs {
        let v = if v.is_finite() { *v } else { -200.0 };
        out.push_str(&format!("{name} {v:.4}\n"));
    }
    out.into_bytes()
}

/// A count from a request's data, such as the number of points of a curve.
pub fn count(data: &[u8], default: usize, max: usize) -> usize {
    std::str::from_utf8(data)
        .ok()
        .and_then(|s| s.trim().parse::<usize>().ok())
        .unwrap_or(default)
        .clamp(2, max)
}
