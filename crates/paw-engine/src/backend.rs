//! Things that drive [`Engine::process`]: a real audio device through cpal,
//! a clock thread that renders into nowhere when there is no device, or the
//! owner of the stream itself, block by block, for the tests (the stepped
//! backend).

#![allow(clippy::allow_attributes_without_reason, reason = "fixed with the running work on the plugin sandbox and the audio backends")]
#![allow(clippy::borrow_as_ptr, reason = "fixed with the running work on the plugin sandbox and the audio backends")]
#![allow(clippy::unwrap_used, reason = "fixed with the running work on the plugin sandbox and the audio backends")]

use std::fmt;
use std::str::FromStr;
use std::sync::atomic::{AtomicBool, Ordering::Relaxed};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use anyhow::Result;
use serde::Serialize;

use crate::engine::{Engine, MAX_INPUTS};

// The real devices: cpal's, else the page of a BrowserPod pod, else none.
#[cfg(not(target_vendor = "browserpod"))]
#[cfg_attr(not(feature = "cpal"), path = "backend/no_cpal.rs")]
mod cpal;
// The tests of the page's backend run on every machine.
#[cfg(any(test, target_vendor = "browserpod"))]
#[cfg_attr(not(target_vendor = "browserpod"), allow(dead_code))]
mod page;
#[cfg(target_vendor = "browserpod")]
use page as cpal;

/// A sound system to play through, by the word scripts and the command
/// line use for it: `auto`, `null`, `step`, `test`, or a host such as
/// `pipewire`.
#[derive(Clone, Debug, Default, PartialEq, Eq, Hash)]
pub enum BackendChoice {
    /// The first host that works, else the null backend.
    #[default]
    Auto,
    /// No device: a clock thread that renders into nowhere.
    Null,
    /// The null backend with no thread: the owner of the stream runs each
    /// block on its own thread ([`Stream::run_to`]), so that a test knows
    /// how many blocks ran. It opens no device ([`is_null`](Self::is_null)),
    /// [`StreamInfo::backend`] says `Step`, and the stream
    /// [`is_stepped`](Stream::is_stepped).
    Step,
    /// The null backend with the [`test_device`] to play to.
    Test,
    /// A cpal host by its name, such as `pipewire`, `alsa` or `jack`.
    Host(String),
}

impl BackendChoice {
    /// Whether it opens no device: the null backend, run by its clock
    /// thread or stepped.
    pub fn is_null(&self) -> bool {
        matches!(self, Self::Null | Self::Step)
    }

    /// The word for it.
    pub fn as_str(&self) -> &str {
        match self {
            Self::Auto => "auto",
            Self::Null => "null",
            Self::Step => "step",
            Self::Test => "test",
            Self::Host(name) => name,
        }
    }
}

impl From<&str> for BackendChoice {
    /// Any word other than `auto`, `null`, `step` and `test` names a host,
    /// as it is written: whether there is such a host is known only when it
    /// opens.
    fn from(word: &str) -> Self {
        match word {
            "auto" => Self::Auto,
            "null" => Self::Null,
            "step" => Self::Step,
            "test" => Self::Test,
            host => Self::Host(host.to_string()),
        }
    }
}

impl FromStr for BackendChoice {
    type Err = std::convert::Infallible;

    fn from_str(word: &str) -> std::result::Result<Self, Self::Err> {
        Ok(Self::from(word))
    }
}

impl fmt::Display for BackendChoice {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl Serialize for BackendChoice {
    fn serialize<S: serde::Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        s.serialize_str(self.as_str())
    }
}

#[derive(Clone, Debug)]
pub struct BackendOptions {
    pub backend: BackendChoice,
    pub sample_rate: Option<u32>,
    pub buffer_size: Option<u32>,
    /// Open a capture device alongside the output. Real devices only.
    pub input: bool,
    /// The output and input device by name, id or a part of the name (see
    /// [`find_device`]); `None` for the system's default. A device that is
    /// not there is replaced by the default, with a warning.
    pub output_device: Option<String>,
    pub input_device: Option<String>,
    /// What the null backend gives the engine as input, so that tests can
    /// check monitoring and recording without hardware.
    pub test_input: Option<TestInput>,
}

impl Default for BackendOptions {
    fn default() -> Self {
        Self {
            backend: BackendChoice::Auto,
            sample_rate: None,
            buffer_size: None,
            input: true,
            output_device: None,
            input_device: None,
            test_input: None,
        }
    }
}

/// An audio device the system offers, as [`list_devices`] reports it.
#[derive(Clone, Debug, PartialEq)]
pub struct AudioDevice {
    /// What the system calls it, with runs of spaces made one.
    pub name: String,
    /// The backend's own name for it, which stays the same between runs:
    /// a PipeWire node name, an ALSA device name.
    pub id: String,
    pub channels: u16,
    /// Its own sample rate, 0 when it does not say.
    pub sample_rate: u32,
    /// The block sizes it takes, 0 when it does not say.
    pub min_block: u32,
    pub max_block: u32,
}

#[derive(Clone, Debug, Default)]
pub struct DeviceList {
    pub backend: BackendChoice,
    pub outputs: Vec<AudioDevice>,
    pub inputs: Vec<AudioDevice>,
}

/// The name of the input the null backend offers when it has a test input.
pub const TEST_INPUT_NAME: &str = "test signal";

/// The device the `test` backend plays to: the null backend, with a device
/// that tests can unplug and plug in again (see [`test_device`]).
pub const TEST_DEVICE_NAME: &str = "test device";

/// A pretend audio device for tests of losing the device and getting it
/// back, without hardware. The `test` backend opens it; while it is
/// unplugged, opening fails and a stream on it reports it lost.
pub mod test_device {
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering::Relaxed};
    use std::time::{SystemTime, UNIX_EPOCH};

    static PRESENT: AtomicBool = AtomicBool::new(true);
    /// Blocks a stream plays before the device goes, or 0.
    static FAIL_AFTER: AtomicU64 = AtomicU64::new(0);
    /// Milliseconds after it goes that it comes back, or 0 for not by itself.
    static BACK_AFTER: AtomicU64 = AtomicU64::new(0);
    /// When it comes back, in milliseconds since 1970, or 0.
    static BACK_AT: AtomicU64 = AtomicU64::new(0);

    fn now() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| d.as_millis() as u64)
    }

    /// Plug it in or unplug it now; have the next stream on it lose it
    /// after `fail_after` blocks (0: never); have it come back `back_after`
    /// milliseconds after it went (0: only when plugged in).
    pub fn set(present: Option<bool>, fail_after: Option<u64>, back_after: Option<u64>) {
        if let Some(present) = present {
            unplug(!present);
        }
        if let Some(blocks) = fail_after {
            FAIL_AFTER.store(blocks, Relaxed);
        }
        if let Some(ms) = back_after {
            BACK_AFTER.store(ms, Relaxed);
        }
    }

    fn unplug(gone: bool) {
        PRESENT.store(!gone, Relaxed);
        let back = BACK_AFTER.load(Relaxed);
        BACK_AT.store(if gone && back > 0 { now() + back } else { 0 }, Relaxed);
    }

    /// Whether it is plugged in.
    pub fn present() -> bool {
        let back = BACK_AT.load(Relaxed);
        if !PRESENT.load(Relaxed) && back != 0 && now() >= back {
            PRESENT.store(true, Relaxed);
            BACK_AT.store(0, Relaxed);
        }
        PRESENT.load(Relaxed)
    }

    /// Called by a stream on it for each block: whether the device is
    /// still there.
    pub(super) fn block(played: u64) -> bool {
        let after = FAIL_AFTER.load(Relaxed);
        if after != 0 && played >= after {
            FAIL_AFTER.store(0, Relaxed);
            unplug(true);
        }
        present()
    }
}

/// Set from a stream's error handler when its device is gone: unplugged,
/// or its server ended. Read on the main thread.
#[derive(Default)]
pub struct Lost {
    gone: AtomicBool,
    why: Mutex<String>,
}

impl Lost {
    fn report(&self, why: String) {
        if !self.gone.load(Relaxed) {
            // Not the audio callback: an error handler, called once the
            // stream has failed.
            if let Ok(mut slot) = self.why.try_lock() {
                *slot = why;
            }
            self.gone.store(true, Relaxed);
        }
    }

    /// Why the device is gone, once it is.
    pub fn why(&self) -> Option<String> {
        self.gone
            .load(Relaxed)
            .then(|| self.why.lock().map(|w| w.clone()).unwrap_or_default())
    }
}

/// The device `wanted` names: one whose id or name is exactly that (ignoring
/// case), else one whose name starts with it, else one whose name or id
/// contains it. Among several, the one with the most channels: asking for
/// `UR22` finds the interface's whole input rather than one of its halves.
pub fn find_device<'a>(devices: &'a [AudioDevice], wanted: &str) -> Option<&'a AudioDevice> {
    let wanted = squash(wanted).to_lowercase();
    if wanted.is_empty() {
        return None;
    }
    let tiers: [&dyn Fn(&AudioDevice) -> bool; 3] = [
        &|d| d.id.to_lowercase() == wanted || d.name.to_lowercase() == wanted,
        &|d| d.name.to_lowercase().starts_with(&wanted),
        &|d| d.name.to_lowercase().contains(&wanted) || d.id.to_lowercase().contains(&wanted),
    ];
    tiers.iter().find_map(|tier| {
        devices
            .iter()
            .filter(|d| tier(d))
            .max_by_key(|d| (d.channels, std::cmp::Reverse(d.name.len())))
    })
}

/// Runs of white space as one space, and none at the ends.
fn squash(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// A generated input: input channel `n` (counting from 1) carries a sine at
/// `n` times `frequency`, so that a test can tell the channels apart.
#[derive(Clone, Debug)]
pub struct TestInput {
    pub frequency: f64,
    /// Peak level in dB.
    pub level: f64,
    pub channels: u16,
}

#[derive(Clone, Debug)]
pub struct StreamInfo {
    /// The backend that opened: never `Auto`.
    pub backend: BackendChoice,
    /// The output device's name, and the backend's id for it.
    pub device: String,
    pub device_id: String,
    pub sample_rate: u32,
    /// Frames per callback as requested, or 0 when left to the device.
    pub buffer_size: u32,
    pub input_device: String,
    pub input_device_id: String,
    pub input_channels: u32,
    /// Set when `auto` had to fall back to the null backend, when there is
    /// no input, or when a device asked for was not there.
    pub warning: Option<String>,
}

/// A backend that has been chosen and knows its sample rate, but is not running yet.
pub struct Opened {
    pub info: StreamInfo,
    test_input: Option<TestInput>,
    cpal: Option<cpal::Devices>,
}

/// A running backend. Dropping it stops audio.
///
/// The engine is always handed back and freed on the thread that drops the
/// stream. Hosted plugins must be destroyed on the main thread, so the stream
/// has to be dropped there.
pub struct Stream {
    pub info: StreamInfo,
    /// Says when the device has gone away.
    pub lost: Arc<Lost>,
    stop: Arc<AtomicBool>,
    thread: Option<JoinHandle<Engine>>,
    /// The engine while a cpal callback is driving it.
    parked: Arc<Mutex<Option<Engine>>>,
    cpal: Option<cpal::Running>,
    /// The engine of the stepped backend, which the owner of the stream
    /// runs on its own thread.
    stepped: Option<Stepped>,
}

impl Drop for Stream {
    fn drop(&mut self) {
        self.stop.store(true, Relaxed);
        if let Some(thread) = self.thread.take() {
            drop(thread.join());
        }
        // Stop the callbacks before taking the engine away from them.
        drop(self.cpal.take());
        let engine = self.parked.lock().map(|mut parked| parked.take());
        drop(engine);
    }
}

pub fn open(opts: &BackendOptions) -> Result<Opened> {
    let null = |warning: Option<String>| Opened {
        info: StreamInfo {
            backend: BackendChoice::Null,
            device: "none".into(),
            device_id: String::new(),
            sample_rate: opts.sample_rate.unwrap_or(48000),
            buffer_size: opts.buffer_size.unwrap_or(512),
            input_device: if opts.test_input.is_some() {
                TEST_INPUT_NAME
            } else {
                "none"
            }
            .into(),
            input_device_id: String::new(),
            input_channels: opts
                .test_input
                .as_ref()
                .map_or(0, |t| (t.channels as usize).min(MAX_INPUTS) as u32),
            warning,
        },
        test_input: opts.test_input.clone(),
        cpal: None,
    };
    if opts.backend == BackendChoice::Step {
        let mut opened = null(None);
        opened.info.backend = BackendChoice::Step;
        return Ok(opened);
    }
    if opts.backend.is_null() {
        return Ok(null(None));
    }
    if opts.backend == BackendChoice::Test {
        if !test_device::present() {
            anyhow::bail!("the {TEST_DEVICE_NAME} is not connected");
        }
        let mut opened = null(None);
        opened.info.backend = BackendChoice::Test;
        opened.info.device = TEST_DEVICE_NAME.into();
        opened.info.device_id = "test".into();
        return Ok(opened);
    }
    match cpal::open(opts) {
        Ok(opened) => Ok(opened),
        Err(err) if opts.backend == BackendChoice::Auto => {
            Ok(null(Some(cpal::fallback_warning(&err))))
        }
        Err(err) => Err(err),
    }
}

/// Sample rates offered where the device is chosen.
pub const RATES: [u32; 5] = [44100, 48000, 88200, 96000, 192000];

/// The sound systems that can be chosen: `auto` (the first that works) and
/// each one this machine has, by name.
pub fn backends() -> Vec<String> {
    let mut out = vec!["auto".to_string()];
    out.extend(cpal::backends());
    out
}

/// What the system offers: every output and input device of the backend
/// `opts.backend` would open (`auto`: the first that works). The null
/// backend offers its test input, when it has one.
pub fn list_devices(opts: &BackendOptions) -> Result<DeviceList> {
    if opts.backend.is_null() {
        return Ok(null_devices(opts));
    }
    if opts.backend == BackendChoice::Test {
        let mut list = null_devices(opts);
        list.backend = BackendChoice::Test;
        if test_device::present() {
            list.outputs.push(AudioDevice {
                name: TEST_DEVICE_NAME.into(),
                id: "test".into(),
                channels: 2,
                sample_rate: opts.sample_rate.unwrap_or(48000),
                min_block: 0,
                max_block: 0,
            });
        }
        return Ok(list);
    }
    cpal::list_devices(opts)
}

fn null_devices(opts: &BackendOptions) -> DeviceList {
    DeviceList {
        backend: BackendChoice::Null,
        outputs: Vec::new(),
        inputs: opts
            .test_input
            .iter()
            .map(|t| AudioDevice {
                name: TEST_INPUT_NAME.into(),
                id: "test".into(),
                channels: t.channels.min(MAX_INPUTS as u16),
                sample_rate: opts.sample_rate.unwrap_or(48000),
                min_block: 0,
                max_block: 0,
            })
            .collect(),
    }
}

impl Opened {
    pub fn sample_rate(&self) -> u32 {
        self.info.sample_rate
    }

    /// Start calling `engine.process`. The engine must have been created at
    /// [`sample_rate`](Self::sample_rate).
    pub fn start(self, engine: Engine) -> Result<Stream> {
        let stop = Arc::new(AtomicBool::new(false));
        let parked = Arc::new(Mutex::new(None));
        let lost = Arc::new(Lost::default());
        if let Some(devices) = self.cpal {
            *parked.lock().unwrap() = Some(engine);
            let running = cpal::start(devices, parked.clone(), lost.clone())?;
            return Ok(Stream {
                info: self.info,
                lost,
                stop,
                thread: None,
                parked,
                cpal: Some(running),
                stepped: None,
            });
        }
        let frames = self.info.buffer_size.max(64) as usize;
        let blocks = NullBlocks::new(engine, frames, self.test_input);
        let (thread, stepped) = if self.info.backend == BackendChoice::Step {
            (None, Some(Stepped { blocks, ran: 0 }))
        } else {
            let device = (self.info.backend == BackendChoice::Test).then(|| lost.clone());
            let sink = |_: &[f32], _: &[f32]| {};
            (Some(spawn_clock(blocks, stop.clone(), device, sink)), None)
        };
        Ok(Stream {
            info: self.info,
            lost,
            stop,
            thread,
            parked,
            cpal: None,
            stepped,
        })
    }
}

impl Stream {
    /// Whether the owner of the stream runs its blocks
    /// ([`BackendChoice::Step`]): no thread runs them.
    pub fn is_stepped(&self) -> bool {
        self.stepped.is_some()
    }

    /// Run, on this thread, each block of the stepped backend that ends at
    /// or before `at`, the time since the stream started, and give how many
    /// ran. Each block runs once: a time before the end of the next block
    /// runs none. A stream that runs on its own runs none.
    pub fn run_to(&mut self, at: Duration) -> u64 {
        let Some(stepped) = self.stepped.as_mut() else {
            return 0;
        };
        let due = stepped.blocks_by(at);
        let run = due.saturating_sub(stepped.ran);
        if run > 0 {
            // The thread is the audio thread while the blocks run: a plugin
            // that asks is told so.
            let _block = audio_thread::Mark::enter();
            let _denormals = NoDenormals::new();
            for _ in 0..run {
                stepped.blocks.run();
            }
            stepped.ran = due;
        }
        run
    }

    /// The time since the stream started at which `blocks` more blocks of
    /// the stepped backend have ended: [`run_to`](Self::run_to) that time
    /// runs exactly that many. None for a stream that runs on its own.
    pub fn end_of(&self, blocks: u64) -> Option<Duration> {
        let stepped = self.stepped.as_ref()?;
        Some(stepped.end_of(stepped.ran.saturating_add(blocks)))
    }
}

/// Whether the current thread runs the blocks of a stepped stream now. A
/// plugin host asks it: the main thread is the audio thread while it runs
/// them.
pub mod audio_thread {
    use std::cell::Cell;

    thread_local! {
        static STEPPING: Cell<bool> = const { Cell::new(false) };
    }

    /// Whether this thread runs the blocks of a stepped stream now.
    pub fn stepping() -> bool {
        STEPPING.with(Cell::get)
    }

    /// This thread runs blocks until the mark is dropped.
    pub(super) struct Mark;

    impl Mark {
        pub(super) fn enter() -> Self {
            STEPPING.with(|s| s.set(true));
            Self
        }
    }

    impl Drop for Mark {
        fn drop(&mut self) {
            STEPPING.with(|s| s.set(false));
        }
    }
}

/// The stepped backend: the blocks of the null backend, and how many ran.
struct Stepped {
    blocks: NullBlocks,
    /// The blocks run since the stream started. Block `n` ends at
    /// `n * frames / sample_rate` seconds.
    ran: u64,
}

impl Stepped {
    /// The number of whole blocks that end at or before `at`.
    fn blocks_by(&self, at: Duration) -> u64 {
        let frames = at.as_nanos() * self.blocks.rate() / NANOS;
        u64::try_from(frames / self.blocks.frames() as u128).unwrap_or(u64::MAX)
    }

    /// The end of block number `n`, rounded up to the next nanosecond, so
    /// that [`blocks_by`](Self::blocks_by) of that time is `n`.
    fn end_of(&self, n: u64) -> Duration {
        let frames = u128::from(n) * self.blocks.frames() as u128;
        let nanos = (frames * NANOS).div_ceil(self.blocks.rate());
        Duration::from_nanos(u64::try_from(nanos).unwrap_or(u64::MAX))
    }
}

const NANOS: u128 = 1_000_000_000;

/// The engine of the null backend with what a block needs: the output
/// buffers and the generated test input. All are made before the first
/// block, so that a block allocates nothing.
struct NullBlocks {
    engine: Engine,
    left: Vec<f32>,
    right: Vec<f32>,
    /// The test input of the last block, interleaved.
    input: Vec<f32>,
    /// The test input, and the phase of the sine of each of its channels.
    test: Option<(TestInput, Vec<f64>)>,
}

impl NullBlocks {
    fn new(engine: Engine, frames: usize, test_input: Option<TestInput>) -> Self {
        engine.shared().set_period(frames as u32);
        let channels = test_input
            .as_ref()
            .map_or(0, |t| (t.channels as usize).min(MAX_INPUTS));
        Self {
            engine,
            left: vec![0.0; frames],
            right: vec![0.0; frames],
            input: vec![0.0; frames * channels],
            test: test_input.map(|t| (t, vec![0.0; channels])),
        }
    }

    fn frames(&self) -> usize {
        self.left.len()
    }

    /// The sample rate as a whole number, for the times of the blocks:
    /// the engine runs only at whole rates.
    fn rate(&self) -> u128 {
        self.engine.sample_rate() as u128
    }

    /// Run one block: make the test input, and render into the buffers.
    /// No lock, no allocation, no wait.
    fn run(&mut self) {
        let mut channels = 0;
        if let Some((test, phases)) = &mut self.test {
            channels = phases.len();
            let gain = crate::db_to_gain(test.level);
            for (ch, phase) in phases.iter_mut().enumerate() {
                let step = test.frequency * (ch + 1) as f64 / self.engine.sample_rate();
                for frame in self.input.chunks_exact_mut(channels) {
                    frame[ch] = (*phase * std::f64::consts::TAU).sin() as f32 * gain;
                    *phase = (*phase + step).fract();
                }
            }
        }
        self.engine
            .process_input(&self.input, channels, &mut self.left, &mut self.right);
    }
}

/// Render in real time on a plain thread and give each block, left and
/// right, to `sink`: the null backend throws it away. `sink` runs on the
/// audio thread: no lock, no allocation, no wait.
fn spawn_clock(
    mut blocks: NullBlocks,
    stop: Arc<AtomicBool>,
    // The test device, which can be unplugged: where to say so.
    device: Option<Arc<Lost>>,
    mut sink: impl FnMut(&[f32], &[f32]) + Send + 'static,
) -> JoinHandle<Engine> {
    std::thread::spawn(move || {
        no_denormals();
        let seconds = blocks.frames() as f64 / blocks.engine.sample_rate();
        let period = Duration::from_secs_f64(seconds);
        let mut next = Instant::now();
        let mut played = 0u64;
        while !stop.load(Relaxed) {
            if let Some(lost) = &device {
                played += 1;
                if !test_device::block(played) {
                    lost.report(format!("the {TEST_DEVICE_NAME} was unplugged"));
                    // As a device that is gone: no more blocks.
                    while !stop.load(Relaxed) {
                        std::thread::sleep(Duration::from_millis(5));
                    }
                    break;
                }
            }
            let began = Instant::now();
            blocks.run();
            sink(&blocks.left, &blocks.right);
            blocks
                .engine
                .shared()
                .set_cpu(began.elapsed().as_secs_f32() / period.as_secs_f32());
            next += period;
            match next.checked_duration_since(Instant::now()) {
                Some(wait) => std::thread::sleep(wait),
                // Fell behind, for instance after the machine slept: start over.
                None => next = Instant::now(),
            }
        }
        blocks.engine
    })
}


/// Make the CPU treat denormal floats as zero on this thread. Decaying filters
/// and reverb tails otherwise get dramatically slower as they fade out.
// Not the `no_denormals` crate: it gives only a scoped closure (an `unsafe fn`
// that fails to compile off x86 and aarch64), while the audio threads set this
// for good and the render holds `NoDenormals` across early returns.
pub fn no_denormals() {
    #[cfg(target_arch = "x86_64")]
    set_csr(csr() | 0x8040);
}

#[cfg(target_arch = "x86_64")]
fn csr() -> u32 {
    let mut csr: u32 = 0;
    // SAFETY: `stmxcsr` stores the four bytes of MXCSR at the address of
    // `csr`, a live, aligned u32 that the asm borrows mutably; it touches no
    // other memory, no stack and no flags.
    unsafe { std::arch::asm!("stmxcsr [{}]", in(reg) &mut csr, options(nostack)) };
    csr
}

#[cfg(target_arch = "x86_64")]
fn set_csr(csr: u32) {
    // SAFETY: `ldmxcsr` only reads the four bytes of `csr`, a live u32. The
    // callers set or restore only the flush-to-zero (bit 15) and
    // denormals-are-zero (bit 6) bits of a value read from MXCSR, which every
    // x86_64 processor has, so the load cannot fault. Rust assumes the
    // default floating-point environment (see `_mm_setcsr`): with FTZ/DAZ on,
    // only denormal results differ, which is what this is for.
    unsafe { std::arch::asm!("ldmxcsr [{}]", in(reg) &csr, options(nostack, readonly)) };
}

/// Denormals treated as zero on this thread until this is dropped, for
/// processing on a thread that also does other work, such as an offline render
/// on the main thread.
pub struct NoDenormals {
    #[cfg(target_arch = "x86_64")]
    saved: u32,
}

impl NoDenormals {
    pub fn new() -> Self {
        #[cfg(target_arch = "x86_64")]
        {
            let saved = csr();
            set_csr(saved | 0x8040);
            Self { saved }
        }
        #[cfg(not(target_arch = "x86_64"))]
        Self {}
    }
}

impl Default for NoDenormals {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for NoDenormals {
    fn drop(&mut self) {
        #[cfg(target_arch = "x86_64")]
        set_csr(self.saved);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device(name: &str, id: &str, channels: u16) -> AudioDevice {
        AudioDevice {
            name: name.into(),
            id: id.into(),
            channels,
            sample_rate: 48000,
            min_block: 0,
            max_block: 0,
        }
    }

    fn inputs() -> Vec<AudioDevice> {
        vec![
            device("Bose NC 700 HP", "bluez_input.78:2B", 1),
            device("Steinberg UR22mkII 0", "alsa_input.hw_UR22mkII_0", 2),
            device(
                "Steinberg UR22mkII Input 1",
                "alsa_input.usb-Yamaha_Corporation_Steinberg_UR22mkII-00.HiFi__Line2__source",
                1,
            ),
            device(
                "Steinberg UR22mkII Input 2",
                "alsa_input.usb-Yamaha_Corporation_Steinberg_UR22mkII-00.HiFi__Line3__source",
                1,
            ),
        ]
    }

    #[test]
    fn a_part_of_a_name_finds_the_device_with_the_most_channels() {
        let list = inputs();
        assert_eq!(find_device(&list, "ur22").unwrap().channels, 2);
        assert_eq!(
            find_device(&list, "Steinberg").unwrap().id,
            "alsa_input.hw_UR22mkII_0"
        );
    }

    #[test]
    fn an_exact_name_or_id_wins_over_a_part() {
        let list = inputs();
        assert_eq!(
            find_device(&list, "steinberg  ur22mkii input 2")
                .unwrap()
                .channels,
            1
        );
        assert_eq!(
            find_device(
                &list,
                "alsa_input.usb-Yamaha_Corporation_Steinberg_UR22mkII-00.HiFi__Line2__source"
            )
            .unwrap()
            .name,
            "Steinberg UR22mkII Input 1"
        );
        assert_eq!(
            find_device(&list, "Line3").unwrap().name,
            "Steinberg UR22mkII Input 2"
        );
    }

    #[test]
    fn nothing_is_found_for_a_name_that_is_not_there() {
        assert!(find_device(&inputs(), "Scarlett").is_none());
        assert!(find_device(&inputs(), "  ").is_none());
    }

    #[test]
    fn a_backend_is_written_as_the_word_it_was_read_from() {
        for word in ["auto", "null", "step", "test", "pipewire", "Null"] {
            assert_eq!(BackendChoice::from(word).to_string(), word);
        }
        assert_eq!(BackendChoice::from("jack"), BackendChoice::Host("jack".into()));
    }

    #[test]
    fn a_stepped_stream_runs_each_block_once_at_its_end() {
        // 512 frames at 48 kHz: a block is not a whole number of nanoseconds.
        let opts = BackendOptions {
            backend: "step".into(),
            sample_rate: Some(48000),
            buffer_size: Some(512),
            ..Default::default()
        };
        let opened = open(&opts).unwrap();
        let (engine, handle) = Engine::new(f64::from(opened.sample_rate()));
        let mut stream = opened.start(engine).unwrap();
        assert!(stream.is_stepped(), "the stream is stepped");
        assert_eq!(stream.info.backend, BackendChoice::Step, "it says that it is the stepped backend");

        let three = stream.end_of(3).unwrap();
        assert_eq!(stream.run_to(three - Duration::from_nanos(1)), 2, "before the end of the third block");
        assert_eq!(stream.run_to(three), 1, "at its end");
        assert_eq!(stream.run_to(three), 0, "a block runs once");
        let next = stream.end_of(1).unwrap();
        assert!(next > three, "the next block ends later");
        assert_eq!(stream.run_to(stream.end_of(1000).unwrap()), 1000, "a thousand more");
        assert_eq!(handle.shared.processed(), 1003, "the engine ran each block");
    }

    #[test]
    fn a_stream_that_runs_on_its_own_is_not_stepped() {
        let opened = open(&BackendOptions { backend: "null".into(), ..Default::default() }).unwrap();
        let (engine, _handle) = Engine::new(f64::from(opened.sample_rate()));
        let mut stream = opened.start(engine).unwrap();
        assert!(!stream.is_stepped(), "the null backend has its clock thread");
        assert_eq!(stream.end_of(1), None, "no block to wait for");
        assert_eq!(stream.run_to(Duration::from_secs(1)), 0, "the caller runs none");
    }

    #[test]
    fn the_null_backend_offers_its_test_input() {
        let opts = BackendOptions {
            backend: "null".into(),
            test_input: Some(TestInput {
                frequency: 440.0,
                level: -12.0,
                channels: 2,
            }),
            ..Default::default()
        };
        let list = list_devices(&opts).unwrap();
        assert_eq!(list.inputs.len(), 1);
        assert_eq!(list.inputs[0].name, TEST_INPUT_NAME);
        assert!(list.outputs.is_empty());
    }
}
