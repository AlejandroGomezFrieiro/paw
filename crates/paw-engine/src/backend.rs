//! Things that drive [`Engine::process`]: a real audio device through cpal, or
//! a clock thread that renders into nowhere when there is no device.

use std::fmt;
use std::str::FromStr;
use std::sync::atomic::{AtomicBool, Ordering::Relaxed};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use anyhow::Result;
use serde::Serialize;

use crate::engine::{Engine, MAX_INPUTS};

/// A sound system to play through, by the word scripts and the command
/// line use for it: `auto`, `null`, `test`, or a host such as `pipewire`.
#[derive(Clone, Debug, Default, PartialEq, Eq, Hash)]
pub enum BackendChoice {
    /// The first host that works, else the null backend.
    #[default]
    Auto,
    /// No device: a clock thread that renders into nowhere.
    Null,
    /// The null backend with the [`test_device`] to play to.
    Test,
    /// A cpal host by its name, such as `pipewire`, `alsa` or `jack`.
    Host(String),
}

impl BackendChoice {
    /// The word for it.
    pub fn as_str(&self) -> &str {
        match self {
            Self::Auto => "auto",
            Self::Null => "null",
            Self::Test => "test",
            Self::Host(name) => name,
        }
    }
}

impl From<&str> for BackendChoice {
    /// Any word other than `auto`, `null` and `test` names a host, as it is
    /// written: whether there is such a host is known only when it opens.
    fn from(word: &str) -> Self {
        match word {
            "auto" => Self::Auto,
            "null" => Self::Null,
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
    #[cfg(feature = "cpal")]
    cpal: Option<CpalDevices>,
}

#[cfg(feature = "cpal")]
struct CpalDevices {
    output: (cpal::Device, cpal::StreamConfig),
    input: Option<(cpal::Device, cpal::StreamConfig)>,
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
    #[cfg(feature = "cpal")]
    cpal: Option<cpal::Stream>,
    #[cfg(feature = "cpal")]
    cpal_input: Option<cpal::Stream>,
}

impl Drop for Stream {
    fn drop(&mut self) {
        self.stop.store(true, Relaxed);
        if let Some(thread) = self.thread.take() {
            drop(thread.join());
        }
        // Stop the callbacks before taking the engine away from them.
        #[cfg(feature = "cpal")]
        drop(self.cpal.take());
        #[cfg(feature = "cpal")]
        drop(self.cpal_input.take());
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
        #[cfg(feature = "cpal")]
        cpal: None,
    };
    if opts.backend == BackendChoice::Null {
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
    #[cfg(feature = "cpal")]
    {
        match open_cpal(opts) {
            Ok(opened) => Ok(opened),
            Err(err) if opts.backend == BackendChoice::Auto => Ok(null(Some(format!(
                "no audio device ({err:#}); running without sound"
            )))),
            Err(err) => Err(err),
        }
    }
    #[cfg(not(feature = "cpal"))]
    {
        if opts.backend == BackendChoice::Auto {
            Ok(null(Some("built without audio device support".into())))
        } else {
            anyhow::bail!("unknown audio backend `{}`", opts.backend)
        }
    }
}

/// Sample rates offered where the device is chosen.
pub const RATES: [u32; 5] = [44100, 48000, 88200, 96000, 192000];

/// The sound systems that can be chosen: `auto` (the first that works) and
/// each one this machine has, by name.
pub fn backends() -> Vec<String> {
    let mut out = vec!["auto".to_string()];
    #[cfg(feature = "cpal")]
    out.extend(
        cpal::available_hosts()
            .iter()
            .map(|id| id.name().to_lowercase()),
    );
    out
}

/// What the system offers: every output and input device of the backend
/// `opts.backend` would open (`auto`: the first that works). The null
/// backend offers its test input, when it has one.
pub fn list_devices(opts: &BackendOptions) -> Result<DeviceList> {
    if opts.backend == BackendChoice::Null {
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
    #[cfg(feature = "cpal")]
    {
        let mut last = anyhow::anyhow!("no audio hosts available");
        for id in cpal_hosts(&opts.backend)? {
            match cpal::host_from_id(id) {
                Ok(host) => match cpal_devices(&host) {
                    Ok(found) => {
                        return Ok(DeviceList {
                            backend: BackendChoice::Host(id.name().to_lowercase()),
                            outputs: found.outputs.into_iter().map(|(_, d)| d).collect(),
                            inputs: found.inputs.into_iter().map(|(_, d)| d).collect(),
                        });
                    }
                    Err(err) => last = err,
                },
                Err(err) => last = err.into(),
            }
        }
        if opts.backend == BackendChoice::Auto {
            return Ok(null_devices(opts));
        }
        Err(last)
    }
    #[cfg(not(feature = "cpal"))]
    Ok(null_devices(opts))
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

/// The hosts to try for a backend name, best first.
#[cfg(feature = "cpal")]
fn cpal_hosts(backend: &BackendChoice) -> Result<Vec<cpal::HostId>> {
    let hosts = cpal::available_hosts();
    if *backend == BackendChoice::Auto {
        // Prefer the low-latency servers over plain ALSA when they are there.
        let rank = |id: &cpal::HostId| match id.name().to_lowercase().as_str() {
            "pipewire" => 0,
            "jack" => 1,
            _ => 2,
        };
        let mut hosts = hosts.clone();
        hosts.sort_by_key(rank);
        return Ok(hosts);
    }
    match hosts
        .iter()
        .find(|id| id.name().eq_ignore_ascii_case(backend.as_str()))
    {
        Some(id) => Ok(vec![*id]),
        None => {
            let names: Vec<_> = hosts.iter().map(|id| id.name().to_lowercase()).collect();
            anyhow::bail!(
                "unknown audio backend `{backend}` (have: null, {})",
                names.join(", ")
            )
        }
    }
}

#[cfg(feature = "cpal")]
struct Found {
    outputs: Vec<(cpal::Device, AudioDevice)>,
    inputs: Vec<(cpal::Device, AudioDevice)>,
}

/// Every device of a host that sound can be played to or recorded from.
///
/// PipeWire lists more than devices: the system's defaults (which follow
/// whatever the default is), other programs' streams, and sinks again as
/// inputs (to record what plays through them). Those are left out, and so
/// are this and other programs' own streams.
#[cfg(feature = "cpal")]
fn cpal_devices(host: &cpal::Host) -> Result<Found> {
    use cpal::traits::{DeviceTrait, HostTrait};
    use cpal::{DeviceDirection, SupportedBufferSize};

    let pipewire = host.id().name().eq_ignore_ascii_case("pipewire");
    let mut found = Found {
        outputs: Vec::new(),
        inputs: Vec::new(),
    };
    for device in host.devices()? {
        let id = device
            .id()
            .map(|d| d.id().to_string())
            .unwrap_or_else(|_| device.to_string());
        if pipewire
            && (["sink_default", "input_default", "output_default"].contains(&id.as_str())
                || id.starts_with("cpal-"))
        {
            continue;
        }
        let description = device.description().ok();
        // Streams of programs have no description of their own, which cpal
        // gives as "unknown"; devices always have one.
        if pipewire && description.as_ref().is_none_or(|d| d.name() == "unknown") {
            continue;
        }
        let direction = description.as_ref().map(|d| d.direction());
        let name = squash(description.as_ref().map_or(&id, |d| d.name()));
        let info = |config: Result<cpal::SupportedStreamConfig, cpal::Error>| {
            config.ok().map(|c| {
                let (min, max) = match c.buffer_size() {
                    SupportedBufferSize::Range { min, max } => (*min, *max),
                    SupportedBufferSize::Unknown => (0, 0),
                };
                AudioDevice {
                    name: name.clone(),
                    id: id.clone(),
                    channels: c.channels(),
                    sample_rate: c.sample_rate(),
                    min_block: min,
                    max_block: max,
                }
            })
        };
        let output = !pipewire || direction == Some(DeviceDirection::Duplex);
        let input = !pipewire || direction == Some(DeviceDirection::Input);
        if output
            && device.supports_output()
            && let Some(info) = info(device.default_output_config())
        {
            found.outputs.push((device.clone(), info));
        }
        if input
            && device.supports_input()
            && let Some(info) = info(device.default_input_config())
        {
            found.inputs.push((device, info));
        }
    }
    for list in [&mut found.outputs, &mut found.inputs] {
        list.sort_by_key(|d| d.1.name.to_lowercase());
    }
    Ok(found)
}

/// The device of `list` that `wanted` names, else the default with a note
/// that it was not there.
#[cfg(feature = "cpal")]
fn choose(
    list: &[(cpal::Device, AudioDevice)],
    wanted: Option<&str>,
    what: &str,
    default: impl FnOnce() -> Option<cpal::Device>,
    notes: &mut Vec<String>,
) -> Option<(cpal::Device, Option<AudioDevice>)> {
    if let Some(wanted) = wanted.filter(|w| !w.trim().is_empty()) {
        let infos: Vec<AudioDevice> = list.iter().map(|(_, d)| d.clone()).collect();
        match find_device(&infos, wanted) {
            Some(info) => {
                let at = infos.iter().position(|d| d == info)?;
                return Some((list[at].0.clone(), Some(info.clone())));
            }
            None => notes.push(format!(
                "the {what} `{wanted}` is not connected; using the system's default {what}"
            )),
        }
    }
    default().map(|d| (d, None))
}

#[cfg(feature = "cpal")]
fn open_cpal(opts: &BackendOptions) -> Result<Opened> {
    use anyhow::{Context, anyhow};
    use cpal::traits::{DeviceTrait, HostTrait};

    let mut last = anyhow!("no audio hosts available");
    for id in cpal_hosts(&opts.backend)? {
        let attempt = (|| -> Result<Opened> {
            let host = cpal::host_from_id(id)?;
            let found = cpal_devices(&host)?;
            let mut notes = Vec::new();
            let (device, chosen) = choose(
                &found.outputs,
                opts.output_device.as_deref(),
                "output",
                || host.default_output_device(),
                &mut notes,
            )
            .context("no default output device")?;
            let default = device.default_output_config()?;
            let mut config: cpal::StreamConfig = default.into();
            if let Some(rate) = opts.sample_rate {
                config.sample_rate = rate;
            }
            if let Some(size) = opts.buffer_size {
                config.buffer_size = cpal::BufferSize::Fixed(size);
            }
            // Input runs at the output's rate and block size, so the two
            // streams only differ by clock drift.
            let input = if opts.input {
                choose(
                    &found.inputs,
                    opts.input_device.as_deref(),
                    "input",
                    || host.default_input_device(),
                    &mut notes,
                )
                .context("no default input device")
                .and_then(|(device, chosen)| {
                    let default = device.default_input_config()?;
                    let input = cpal::StreamConfig {
                        channels: default.channels(),
                        sample_rate: config.sample_rate,
                        buffer_size: config.buffer_size,
                    };
                    Ok((device, input, chosen))
                })
            } else {
                Err(anyhow!("input is turned off"))
            };
            let input = match input {
                Ok(input) => Some(input),
                Err(err) if opts.input => {
                    notes.push(format!("no audio input: {err:#}"));
                    None
                }
                Err(_) => None,
            };
            let name_of = |device: &cpal::Device, chosen: &Option<AudioDevice>| {
                chosen.as_ref().map_or_else(
                    || {
                        // The system's default: say so, and what it is now.
                        let what = device
                            .description()
                            .map(|d| squash(d.name()))
                            .unwrap_or_default();
                        if what.is_empty() || what.starts_with("default") {
                            "system default".to_string()
                        } else {
                            what
                        }
                    },
                    |d| d.name.clone(),
                )
            };
            let id_of = |chosen: &Option<AudioDevice>| {
                chosen.as_ref().map_or_else(String::new, |d| d.id.clone())
            };
            let info = StreamInfo {
                backend: BackendChoice::Host(id.name().to_lowercase()),
                device: name_of(&device, &chosen),
                device_id: id_of(&chosen),
                sample_rate: config.sample_rate,
                buffer_size: opts.buffer_size.unwrap_or(0),
                input_device: input
                    .as_ref()
                    .map_or_else(|| "none".into(), |(d, _, c)| name_of(d, c)),
                input_device_id: input
                    .as_ref()
                    .map_or_else(String::new, |(_, _, c)| id_of(c)),
                input_channels: input
                    .as_ref()
                    .map_or(0, |(_, c, _)| c.channels as usize)
                    .min(MAX_INPUTS) as u32,
                warning: (!notes.is_empty()).then(|| notes.join("; ")),
            };
            Ok(Opened {
                info,
                test_input: None,
                cpal: Some(CpalDevices {
                    output: (device, config),
                    input: input.map(|(d, c, _)| (d, c)),
                }),
            })
        })();
        match attempt {
            Ok(opened) => return Ok(opened),
            Err(err) => last = err.context(format!("{} backend", id.name())),
        }
    }
    Err(last)
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
        #[cfg(feature = "cpal")]
        if let Some(devices) = self.cpal {
            *parked.lock().unwrap() = Some(engine);
            let (output, input) = start_cpal(devices, parked.clone(), lost.clone())?;
            return Ok(Stream {
                info: self.info,
                lost,
                stop,
                thread: None,
                parked,
                cpal: Some(output),
                cpal_input: input,
            });
        }
        let device = (self.info.backend == BackendChoice::Test).then(|| lost.clone());
        let thread = spawn_null(
            engine,
            self.info.buffer_size.max(64) as usize,
            stop.clone(),
            self.test_input,
            device,
        );
        Ok(Stream {
            info: self.info,
            lost,
            stop,
            thread: Some(thread),
            parked,
            #[cfg(feature = "cpal")]
            cpal: None,
            #[cfg(feature = "cpal")]
            cpal_input: None,
        })
    }
}

/// Render in real time on a plain thread and throw the audio away.
fn spawn_null(
    mut engine: Engine,
    block: usize,
    stop: Arc<AtomicBool>,
    test_input: Option<TestInput>,
    // The test device, which can be unplugged: where to say so.
    device: Option<Arc<Lost>>,
) -> JoinHandle<Engine> {
    std::thread::spawn(move || {
        no_denormals();
        let mut left = vec![0.0; block];
        let mut right = vec![0.0; block];
        let channels = test_input
            .as_ref()
            .map_or(0, |t| (t.channels as usize).min(MAX_INPUTS));
        let mut input = vec![0.0f32; block * channels];
        let mut phases = vec![0.0f64; channels];
        let period = Duration::from_secs_f64(block as f64 / engine.sample_rate());
        let mut next = Instant::now();
        engine.shared().set_period(block as u32);
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
            if let Some(test) = &test_input {
                let gain = crate::db_to_gain(test.level);
                for (ch, phase) in phases.iter_mut().enumerate() {
                    let step = test.frequency * (ch + 1) as f64 / engine.sample_rate();
                    for frame in input.chunks_exact_mut(channels) {
                        frame[ch] = (*phase * std::f64::consts::TAU).sin() as f32 * gain;
                        *phase = (*phase + step).fract();
                    }
                }
            }
            engine.process_input(&input, channels, &mut left, &mut right);
            engine
                .shared()
                .set_cpu(began.elapsed().as_secs_f32() / period.as_secs_f32());
            next += period;
            match next.checked_duration_since(Instant::now()) {
                Some(wait) => std::thread::sleep(wait),
                // Fell behind, for instance after the machine slept: start over.
                None => next = Instant::now(),
            }
        }
        engine
    })
}

#[cfg(feature = "cpal")]
fn start_cpal(
    devices: CpalDevices,
    parked: Arc<Mutex<Option<Engine>>>,
    lost: Arc<Lost>,
) -> Result<(cpal::Stream, Option<cpal::Stream>)> {
    use std::sync::atomic::AtomicUsize;

    use cpal::traits::{DeviceTrait, StreamTrait};
    use rtrb::RingBuffer;

    let (device, config) = devices.output;
    let channels = config.channels as usize;
    let sample_rate = config.sample_rate as f32;
    let shared = parked.lock().unwrap().as_ref().unwrap().shared().clone();
    let errors = shared.clone();
    let mut left = vec![0.0f32; 8192];
    let mut right = vec![0.0f32; 8192];
    let mut load = 0.0f32;

    // cpal runs input and output as separate streams. Input reaches the
    // output callback through a ring; see `take_input` for how it is kept short.
    let in_channels = devices
        .input
        .as_ref()
        .map_or(0, |(_, c)| c.channels as usize);
    let (mut in_tx, mut in_rx) = RingBuffer::<f32>::new((16384 * in_channels).max(1));
    let in_period = Arc::new(AtomicUsize::new(0));
    // How long input waited in the system before its callback, in microseconds.
    let in_delay = Arc::new(AtomicUsize::new(0));
    let mut scratch = vec![0.0f32; left.len() * in_channels];
    let mut last = [0.0f32; MAX_INPUTS];
    let mut latency = 0.0f32;

    let input = match devices.input {
        Some((in_device, in_config)) => {
            let period = in_period.clone();
            let delay = in_delay.clone();
            let in_errors = shared.clone();
            let in_lost = lost.clone();
            let stream = in_device.build_input_stream(
                in_config,
                move |data: &[f32], info: &cpal::InputCallbackInfo| {
                    period.store(data.len() / in_channels, Relaxed);
                    let t = info.timestamp();
                    let waited = t.callback.saturating_duration_since(t.capture);
                    delay.store(waited.as_micros() as usize, Relaxed);
                    // Whole frames only, so the ring never holds half of one.
                    let fit = in_tx.slots() / in_channels * in_channels;
                    let _ = in_tx.push_partial_slice(&data[..data.len().min(fit)]);
                },
                move |err: cpal::Error| {
                    if matches!(err.kind(), cpal::ErrorKind::Xrun) {
                        in_errors.add_xrun();
                    } else if gone(&err) {
                        in_lost.report(format!("the input stopped: {err}"));
                    }
                },
                None,
            )?;
            Some(stream)
        }
        None => None,
    };

    let stream = device.build_output_stream(
        config,
        move |data: &mut [f32], info: &cpal::OutputCallbackInfo| {
            no_denormals();
            let t = info.timestamp();
            shared.set_output_latency(
                t.playback
                    .saturating_duration_since(t.callback)
                    .as_secs_f32(),
            );
            shared.set_period((data.len() / channels) as u32);
            // Nothing else holds this lock while the stream is alive, so
            // `try_lock` neither blocks nor fails in normal operation.
            let mut guard = parked.try_lock();
            let Some(engine) = guard.as_mut().ok().and_then(|g| g.as_mut()) else {
                data.fill(0.0);
                return;
            };
            let began = Instant::now();
            let frames = data.len() / channels;
            for chunk in data.chunks_mut(left.len() * channels) {
                let n = chunk.len() / channels;
                let input = &mut scratch[..n * in_channels];
                if in_channels > 0 {
                    let waiting = take_input(
                        &mut in_rx,
                        input,
                        in_channels,
                        in_period.load(Relaxed),
                        &mut last,
                    );
                    latency += (waiting as f32 / sample_rate - latency) * 0.1;
                    let system = in_delay.load(Relaxed) as f32 / 1e6;
                    shared.set_input_latency(latency + system);
                }
                engine.process_input(input, in_channels, &mut left[..n], &mut right[..n]);
                for (i, frame) in chunk.chunks_exact_mut(channels).enumerate() {
                    frame.fill(0.0);
                    frame[0] = left[i];
                    if channels > 1 {
                        frame[1] = right[i];
                    }
                }
                // The metronome on an output pair of its own (`click_output`).
                if let Some((first, l, r)) = engine.click_output(n) {
                    for (i, frame) in chunk.chunks_exact_mut(channels).enumerate() {
                        if let Some(s) = frame.get_mut(first) {
                            *s += l[i];
                        }
                        if let Some(s) = frame.get_mut(first + 1) {
                            *s += r[i];
                        }
                    }
                }
            }
            let budget = frames as f32 / sample_rate;
            load += (began.elapsed().as_secs_f32() / budget.max(1e-6) - load) * 0.2;
            shared.set_cpu(load);
        },
        move |err: cpal::Error| {
            if matches!(err.kind(), cpal::ErrorKind::Xrun) {
                errors.add_xrun();
            } else if gone(&err) {
                lost.report(err.to_string());
            }
        },
        None,
    )?;
    stream.play()?;
    if let Some(input) = &input {
        input.play()?;
    }
    Ok((stream, input))
}

/// Whether a stream error means the device is gone, rather than a glitch.
#[cfg(feature = "cpal")]
fn gone(err: &cpal::Error) -> bool {
    use cpal::ErrorKind::*;
    matches!(
        err.kind(),
        DeviceNotAvailable | StreamInvalidated | HostUnavailable
    )
}

/// Fill `out` with the oldest input waiting in the ring, and return how many
/// frames are left waiting.
///
/// The two clocks drift apart. When input runs ahead, more than one input
/// period plus one output block piles up; the excess is dropped, which keeps
/// the added latency bounded. When it falls behind, the last frame is repeated.
#[cfg(feature = "cpal")]
fn take_input(
    rx: &mut rtrb::Consumer<f32>,
    out: &mut [f32],
    channels: usize,
    period: usize,
    last: &mut [f32; MAX_INPUTS],
) -> usize {
    let n = out.len() / channels;
    let waiting = rx.slots() / channels;
    if waiting > n + period + n {
        let skip = (waiting - n - period) * channels;
        if let Ok(chunk) = rx.read_chunk(skip) {
            chunk.commit_all();
        }
    }
    let (got, rest) = rx.pop_partial_slice(out);
    if let Some(frame) = got.chunks_exact(channels).next_back() {
        for (l, s) in last.iter_mut().zip(frame) {
            *l = *s;
        }
    }
    for (i, s) in rest.iter_mut().enumerate() {
        *s = last.get(i % channels).copied().unwrap_or(0.0);
    }
    rx.slots() / channels
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
    unsafe { std::arch::asm!("stmxcsr [{}]", in(reg) &mut csr, options(nostack)) };
    csr
}

#[cfg(target_arch = "x86_64")]
fn set_csr(csr: u32) {
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
        for word in ["auto", "null", "test", "pipewire", "Null"] {
            assert_eq!(BackendChoice::from(word).to_string(), word);
        }
        assert_eq!(BackendChoice::from("jack"), BackendChoice::Host("jack".into()));
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
