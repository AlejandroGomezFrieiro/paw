//! Attachments: native libraries an extension ships, offered every CLAP
//! plugin paw makes, which can take it and reach the plugin's own
//! extensions (ARA is the one this was made for).
//!
//! The interface is C, in `include/paw_attach.h`. An attachment is loaded
//! into every process that hosts plugins: here, and in each helper, which is
//! handed the list in [`ATTACH_ENV`]. A plugin is offered to each one after
//! its `init` and before its `activate`; one that takes it gets the device's
//! calls first, and may ask for the plugin to be stopped while it answers
//! one (ARA only lets a host change what a plugin plays while it is not
//! active).
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_possible_wrap, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::cast_precision_loss, reason = "debt: pay down"))]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::float_cmp, reason = "debt: pay down"))]

use std::ffi::{CStr, CString, c_char, c_void};
use std::mem::ManuallyDrop;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

use anyhow::{Context, Result, bail};
use paw_engine::clip::AudioData;

/// How the attachments loaded here are handed to a plugin's helper.
pub(crate) const ATTACH_ENV: &str = "PAW_PLUGIN_ATTACH";

pub const ABI: u32 = 1;

pub const CALL_UNKNOWN: i32 = 0;
pub const CALL_DONE: i32 = 1;
pub const CALL_FAILED: i32 = 2;
pub const CALL_STOPPED: i32 = 3;

pub type WriteFn = unsafe extern "C" fn(out: *mut c_void, data: *const u8, size: usize);

#[repr(C)]
pub struct AudioInfo {
    pub frames: i64,
    pub sample_rate: f64,
    pub channels: u32,
}

#[repr(C)]
pub struct Host {
    pub abi: u32,
    pub audio_open: unsafe extern "C" fn(path: *const c_char, info: *mut AudioInfo) -> *mut c_void,
    pub audio_read: unsafe extern "C" fn(
        audio: *mut c_void,
        start: i64,
        frames: i64,
        channels: *const *mut f32,
        channel_count: u32,
    ) -> bool,
    pub audio_close: unsafe extern "C" fn(audio: *mut c_void),
}

#[repr(C)]
pub struct Attachment {
    pub abi: u32,
    pub name: *const c_char,
    pub attach: Option<
        unsafe extern "C" fn(
            host: *const Host,
            format: *const c_char,
            plugin: *const c_void,
        ) -> *mut c_void,
    >,
    pub call: Option<
        unsafe extern "C" fn(
            handle: *mut c_void,
            method: *const c_char,
            data: *const u8,
            size: usize,
            out: *mut c_void,
            write: WriteFn,
        ) -> i32,
    >,
    pub detach: Option<unsafe extern "C" fn(handle: *mut c_void)>,
}

/// A loaded attachment. Never unloaded: a plugin it took may outlive the
/// extension that loaded it.
struct Lib {
    path: PathBuf,
    name: String,
    entry: &'static Attachment,
    _lib: ManuallyDrop<libloading::Library>,
}

// SAFETY: A Lib holds a reference to static data in a library that is never unloaded (ManuallyDrop),
// and a path and a name that nothing mutates, so moving it to another thread is sound.
unsafe impl Send for Lib {}
// SAFETY: The same data is read-only after load, so sharing a Lib between threads is sound.
unsafe impl Sync for Lib {}

static LIBS: Mutex<Vec<Arc<Lib>>> = Mutex::new(Vec::new());
static ADOPTED: OnceLock<()> = OnceLock::new();

pub(crate) static HOST: Host = Host {
    abi: ABI,
    audio_open,
    audio_read,
    audio_close,
};

/// Load the attachment in `path` (a shared library that exports
/// `paw_attachment_entry`), for every plugin made from now on, here and in
/// helpers started from now on. Returns its name. Loading one that is
/// loaded already returns its name again.
pub fn add(path: &Path) -> Result<String> {
    adopt();
    let mut libs = LIBS
        .lock()
        .expect("a thread panicked while it held the lock");
    if let Some(lib) = libs.iter().find(|l| l.path == path) {
        return Ok(lib.name.clone());
    }
    let lib = open(path)?;
    let name = lib.name.clone();
    libs.push(Arc::new(lib));
    Ok(name)
}

fn open(path: &Path) -> Result<Lib> {
    // SAFETY: The library is loaded by its path and its entry symbol has the type of the attachment ABI,
    // which `abi` is checked against below; the entry is called once, and the library is never
    // unloaded, so the `&Attachment` and the name pointer it holds stay valid for the life of the program.
    unsafe {
        let lib = libloading::Library::new(path)
            .with_context(|| format!("could not load the attachment {}", path.display()))?;
        let entry: libloading::Symbol<unsafe extern "C" fn() -> *const Attachment> = lib
            .get(b"paw_attachment_entry\0")
            .with_context(|| format!("{} has no paw_attachment_entry", path.display()))?;
        let entry = entry()
            .as_ref()
            .with_context(|| format!("{} gave no attachment", path.display()))?;
        if entry.abi != ABI {
            bail!(
                "{} is made for version {} of paw's attachments, not {ABI}",
                path.display(),
                entry.abi
            );
        }
        let name = if entry.name.is_null() {
            String::new()
        } else {
            CStr::from_ptr(entry.name).to_string_lossy().into_owned()
        };
        Ok(Lib {
            path: path.to_path_buf(),
            name,
            entry: &*(entry as *const Attachment),
            _lib: ManuallyDrop::new(lib),
        })
    }
}

/// Take the attachments a helper was handed, once.
fn adopt() {
    ADOPTED.get_or_init(|| {
        let Some(paths) = std::env::var_os(ATTACH_ENV) else {
            return;
        };
        let mut libs = LIBS
            .lock()
            .expect("a thread panicked while it held the lock");
        for path in std::env::split_paths(&paths) {
            match open(&path) {
                Ok(lib) => libs.push(Arc::new(lib)),
                Err(err) => eprintln!("paw: {err:#}"),
            }
        }
    });
}

/// The attachments loaded, as [`ATTACH_ENV`] holds them for a helper.
pub(crate) fn env() -> Option<std::ffi::OsString> {
    adopt();
    let libs = LIBS
        .lock()
        .expect("a thread panicked while it held the lock");
    if libs.is_empty() {
        return None;
    }
    std::env::join_paths(libs.iter().map(|l| &l.path)).ok()
}

/// An attachment that took a plugin.
pub(crate) struct Attached {
    lib: Arc<Lib>,
    handle: *mut c_void,
}

// SAFETY: An Attached holds a handle only the attachment reads. It is not `Sync`, so it is used from
// one thread at a time, and the attachment interface's convention is that every call through it is
// on the main thread (the thread that called `crate::register`), which `call` checks in debug
// builds; moving it between threads in between is sound.
unsafe impl Send for Attached {}

impl Attached {
    pub(crate) fn name(&self) -> &str {
        &self.lib.name
    }

    /// Ask the attachment: its answer code and what it wrote.
    pub(crate) fn call(&self, method: &str, data: &[u8]) -> (i32, Vec<u8>) {
        crate::debug_assert_main_thread();
        let Some(call) = self.lib.entry.call else {
            return (CALL_UNKNOWN, Vec::new());
        };
        let Ok(method) = CString::new(method) else {
            return (CALL_UNKNOWN, Vec::new());
        };
        let mut answer: Vec<u8> = Vec::new();
        // SAFETY: `call` is the function the attachment gave for this handle; `method` is a NUL-terminated
        // CString that lives through the call, `data` is a live slice, and `out` points to `answer`, which
        // `write_answer` (the callback) alone appends to during the call.
        let code = unsafe {
            call(
                self.handle,
                method.as_ptr(),
                data.as_ptr(),
                data.len(),
                &raw mut answer as *mut c_void,
                write_answer,
            )
        };
        (code, answer)
    }
}

impl Drop for Attached {
    fn drop(&mut self) {
        if let Some(detach) = self.lib.entry.detach {
            // SAFETY: `detach` is the attachment's function for `handle`, which `attach` returned and nothing
            // detached before: Drop runs once.
            unsafe { detach(self.handle) };
        }
    }
}

/// Offer a plugin that was just initialized to every attachment loaded.
///
/// # Safety
/// `plugin` is a live plugin of `format`, not yet activated.
pub(crate) unsafe fn offer(format: &CStr, plugin: *const c_void) -> Vec<Attached> {
    adopt();
    let libs: Vec<Arc<Lib>> = LIBS
        .lock()
        .expect("a thread panicked while it held the lock")
        .clone();
    let mut taken = Vec::new();
    for lib in libs {
        let Some(attach) = lib.entry.attach else {
            continue;
        };
        // SAFETY: `attach` is the attachment's function; `HOST` is static, `format` is a live CStr, and the
        // caller of `offer` promises `plugin` is a live plugin of that format (this function's # Safety).
        let handle = unsafe { attach(&raw const HOST, format.as_ptr(), plugin) };
        if !handle.is_null() {
            taken.push(Attached { lib, handle });
        }
    }
    taken
}

unsafe extern "C" fn write_answer(out: *mut c_void, data: *const u8, size: usize) {
    if out.is_null() || (data.is_null() && size > 0) {
        return;
    }
    if size > 0 {
        // SAFETY: `out` is the `*mut Vec<u8>` that `Attached::call` passed as the write target and is live
        // for the whole call; `data` is non-null when `size > 0` (checked above) and the attachment
        // promises it points to `size` readable bytes.
        unsafe {
            (*(out as *mut Vec<u8>)).extend_from_slice(std::slice::from_raw_parts(data, size))
        };
    }
}

// --- sound files, for attachments ----------------------------------------------

unsafe extern "C" fn audio_open(path: *const c_char, info: *mut AudioInfo) -> *mut c_void {
    if path.is_null() {
        return std::ptr::null_mut();
    }
    // SAFETY: `path` is non-null (checked above) and the attachment promises it is NUL-terminated.
    let path = unsafe { CStr::from_ptr(path) }
        .to_string_lossy()
        .into_owned();
    let Ok(data) = AudioData::load(Path::new(&path)) else {
        return std::ptr::null_mut();
    };
    // SAFETY: The attachment promises `info` is null or points to a writable AudioInfo; null is handled by as_mut.
    if let Some(info) = unsafe { info.as_mut() } {
        info.frames = data.frames() as i64;
        info.sample_rate = data.sample_rate as f64;
        info.channels = 2;
    }
    Box::into_raw(Box::new(data)) as *mut c_void
}

unsafe extern "C" fn audio_read(
    audio: *mut c_void,
    start: i64,
    frames: i64,
    channels: *const *mut f32,
    channel_count: u32,
) -> bool {
    if audio.is_null() || channels.is_null() || frames < 0 {
        return false;
    }
    // SAFETY: `audio` is non-null (checked above) and came from `audio_open`, which leaks a live
    // `Box<Arc<AudioData>>`-shaped pointer until `audio_close`; the attachment does not use it after close.
    let data = unsafe { &*(audio as *const Arc<AudioData>) };
    // SAFETY: `channels` is non-null (checked above) and the attachment promises it holds `channel_count` pointers.
    let outs = unsafe { std::slice::from_raw_parts(channels, channel_count as usize) };
    read_into(data, start, frames as usize, outs);
    true
}

/// Copy `frames` frames from `start` into each buffer: channel 0 the left,
/// every other the right. Silence outside the sound.
fn read_into(data: &AudioData, start: i64, frames: usize, outs: &[*mut f32]) {
    for (c, &out) in outs.iter().enumerate() {
        if out.is_null() {
            continue;
        }
        // SAFETY: `out` is non-null (checked above), and the attachment promises each channel buffer holds
        // `frames` writable f32 and that the buffers do not overlap.
        let out = unsafe { std::slice::from_raw_parts_mut(out, frames) };
        let samples = &data.channels[c.min(1)];
        for (i, slot) in out.iter_mut().enumerate() {
            let at = start + i as i64;
            *slot = if at < 0 {
                0.0
            } else {
                samples.get(at as usize).copied().unwrap_or(0.0)
            };
        }
    }
}

unsafe extern "C" fn audio_close(audio: *mut c_void) {
    if !audio.is_null() {
        // SAFETY: `audio` is non-null (checked above), came from `audio_open` and the attachment closes it once.
        drop(unsafe { Box::from_raw(audio as *mut Arc<AudioData>) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_a_sound_file_with_silence_around_it() {
        let dir = std::env::temp_dir().join(format!("paw-attach-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("ramp.wav");
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: 44100,
            bits_per_sample: 32,
            sample_format: hound::SampleFormat::Float,
        };
        let mut w = hound::WavWriter::create(&path, spec).unwrap();
        for i in 0..100 {
            w.write_sample(i as f32 / 100.0).unwrap();
        }
        w.finalize().unwrap();

        let c_path = CString::new(path.to_string_lossy().as_bytes()).unwrap();
        let mut info = AudioInfo {
            frames: 0,
            sample_rate: 0.0,
            channels: 0,
        };
        // SAFETY: `c_path` is a live NUL-terminated string and `info` a live `AudioInfo`.
        let audio = unsafe { (HOST.audio_open)(c_path.as_ptr(), &raw mut info) };
        assert!(!audio.is_null());
        assert_eq!(
            (info.frames, info.sample_rate, info.channels),
            (100, 44100.0, 2)
        );
        let mut left = [9.0f32; 4];
        let mut right = [9.0f32; 4];
        let outs = [left.as_mut_ptr(), right.as_mut_ptr()];
        // SAFETY: `audio` is open; `outs` holds 2 pointers to buffers of 4 floats each.
        assert!(unsafe { (HOST.audio_read)(audio, 98, 4, outs.as_ptr(), 2) });
        assert_eq!(left, [0.98, 0.99, 0.0, 0.0]);
        assert_eq!(right, left, "a mono file reads the same on both channels");
        // SAFETY: as above; `audio` is still open.
        assert!(unsafe { (HOST.audio_read)(audio, -2, 4, outs.as_ptr(), 2) });
        assert_eq!(left, [0.0, 0.0, 0.0, 0.01]);
        // SAFETY: `audio` came from `audio_open` and is closed once, here.
        unsafe { (HOST.audio_close)(audio) };

        let missing = CString::new("/nonexistent/paw.wav").unwrap();
        // SAFETY: `missing` is a live NUL-terminated string and `info` a live `AudioInfo`.
        assert!(unsafe { (HOST.audio_open)(missing.as_ptr(), &raw mut info) }.is_null());
        std::fs::remove_dir_all(&dir).ok();
    }
}
