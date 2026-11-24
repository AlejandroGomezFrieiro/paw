//! The plugin's state: the stream it is written to and read from, the
//! saved state (the component's state, then the controller's), and the
//! `.vstpreset` files that hold the same two states. Main thread.

use crate::bytes::le_u32;
use std::cell::{Cell, RefCell};
use std::ffi::c_void;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::Ordering;

use anyhow::{Context, Result, bail};
use paw_engine::Controller;
use paw_engine::device::Change;
use vst3::Steinberg::Vst::*;
use vst3::Steinberg::*;
use vst3::{Class, ComWrapper};

use super::OK;
use super::controller::Vst3Controller;

/// A growable byte stream for plugin state.
pub(super) struct Stream {
    pub(super) data: RefCell<Vec<u8>>,
    pub(super) pos: Cell<usize>,
}

impl Stream {
    pub(super) fn new(data: Vec<u8>) -> ComWrapper<Stream> {
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
        // SAFETY: The plugin passes `buffer` with room for `bytes` bytes (`n <= bytes`); the source is
        // inside `data` (`pos + n <= len`), and the two do not overlap.
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
        // SAFETY: `data` was grown to `pos + n` above, so the destination holds `n` bytes after `pos`; the
        // plugin passes a `buffer` holding `bytes` readable bytes, in another allocation.
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
            // SAFETY: `result` is null-checked above; the plugin owns it for the call.
            unsafe { *result = self.pos.get() as i64 };
        }
        OK
    }

    unsafe fn tell(&self, pos: *mut i64) -> tresult {
        // SAFETY: The plugin passes a non-null `pos` to write to, as the `tell` contract of the ABI requires.
        unsafe { *pos = self.pos.get() as i64 };
        OK
    }
}

pub(super) fn stream_ptr(stream: &ComWrapper<Stream>) -> *mut IBStream {
    stream.as_com_ref::<IBStream>().unwrap().as_ptr()
}

impl Vst3Controller {
    /// The calls of the presets: their list, the load of one, and the
    /// export of the plugin as it is now.
    pub(super) fn preset_call(&mut self, method: &str, data: &[u8]) -> Result<Vec<u8>> {
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
            paw_engine::device::method::PRESETS => {
                let mut presets = crate::presets::vst3_presets(&self.preset_dirs);
                presets.retain(|p| ours(Path::new(&p.id)));
                Ok(crate::presets::to_json(&presets))
            }
            paw_engine::device::method::PRESET_LOAD => {
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
                self.load_plugin_state(&state)?;
                Ok(Vec::new())
            }
            // A preset file of the plugin as it is now, for other hosts.
            paw_engine::device::method::PRESET_EXPORT => {
                let state = self.save_plugin_state()?.unwrap_or_default();
                let mut rest = state.as_slice();
                let mut part = || -> Vec<u8> {
                    let (Some(size), Some(tail)) = (le_u32(rest, 0), rest.get(4..)) else {
                        return Vec::new();
                    };
                    let size = size as usize;
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
    pub(super) fn save_plugin_state(&mut self) -> Result<Option<Vec<u8>>> {
        let mut out = Vec::new();
        // SAFETY: `component` and `controller` are live COM objects called on the main thread; each
        // stream lives through its call.
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

    pub(super) fn load_plugin_state(&mut self, state: &[u8]) -> Result<()> {
        let mut rest = state;
        let mut part = || -> Result<Vec<u8>> {
            let (Some(size), Some(tail)) = (le_u32(rest, 0), rest.get(4..)) else {
                bail!("the saved state is cut short");
            };
            let size = size as usize;
            let (data, tail) = tail
                .split_at_checked(size)
                .context("the saved state is cut short")?;
            rest = tail;
            Ok(data.to_vec())
        };
        let (component, controller) = (part()?, part()?);
        let before: Vec<Option<f64>> = (0..self.known.len()).map(|i| self.value(i)).collect();
        // SAFETY: `component` and `controller` are live COM objects called on the main thread; the
        // streams live through their calls.
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
                self.reported.push(Change {
                    index,
                    value,
                    edit: false,
                });
            }
        }
        self.expect_values();
        // Some plugins only queue the state here and take it on in their
        // next block: a processor that sleeps would never take it.
        self.shared.host.wake.store(true, Ordering::Relaxed);
        self.reread = Some(self.shared.host.blocks.mark());
        Ok(())
    }
}
