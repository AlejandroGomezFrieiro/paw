//! The cpal sound backend: real audio devices. Without the `cpal` feature,
//! `no_cpal.rs` stands in with the same names.

use std::sync::atomic::{AtomicUsize, Ordering::Relaxed};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use anyhow::Result;

use super::{
    AudioDevice, BackendChoice, BackendOptions, DeviceList, Lost, Opened, StreamInfo, find_device,
    no_denormals, squash, MAX_INPUTS,
};
use crate::engine::{Engine, Shared};

/// The devices chosen and their configurations, kept until the stream starts.
pub struct Devices {
    output: (cpal::Device, cpal::StreamConfig),
    input: Option<(cpal::Device, cpal::StreamConfig)>,
}

/// The running streams. Dropping stops them: output first, then input.
pub struct Running {
    _output: cpal::Stream,
    _input: Option<cpal::Stream>,
}

/// The text of the warning when `auto` falls back to the null backend.
pub fn fallback_warning(err: &anyhow::Error) -> String {
    format!("no audio device ({err:#}); running without sound")
}

/// The names of the hosts this machine has.
pub fn backends() -> Vec<String> {
    cpal::available_hosts()
        .iter()
        .map(|id| id.name().to_lowercase())
        .collect()
}

/// The devices of the backend `opts.backend` would open (`auto`: the first
/// that works; none works: the null backend's list).
pub fn list_devices(opts: &BackendOptions) -> Result<DeviceList> {
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
        return Ok(super::null_devices(opts));
    }
    Err(last)
}

/// The hosts to try for a backend name, best first.
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

pub fn open(opts: &BackendOptions) -> Result<Opened> {
    let mut last = anyhow::anyhow!("no audio hosts available");
    for id in cpal_hosts(&opts.backend)? {
        match open_host(id, opts) {
            Ok(opened) => return Ok(opened),
            Err(err) => last = err.context(format!("{} backend", id.name())),
        }
    }
    Err(last)
}

/// A device chosen, its configuration, and what was asked for: `None` for
/// the system's default.
type Chosen = (cpal::Device, cpal::StreamConfig, Option<AudioDevice>);

/// Open the output, and the input if it is asked for, of one host.
fn open_host(id: cpal::HostId, opts: &BackendOptions) -> Result<Opened> {
    use anyhow::Context;
    use cpal::traits::{DeviceTrait, HostTrait};

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
    let input = choose_input(&host, &found, opts, &config, &mut notes);
    let info = StreamInfo {
        backend: BackendChoice::Host(id.name().to_lowercase()),
        device: device_name(&device, chosen.as_ref()),
        device_id: device_id(chosen.as_ref()),
        sample_rate: config.sample_rate,
        buffer_size: opts.buffer_size.unwrap_or(0),
        input_device: input
            .as_ref()
            .map_or_else(|| "none".into(), |(d, _, c)| device_name(d, c.as_ref())),
        input_device_id: input
            .as_ref()
            .map_or_else(String::new, |(_, _, c)| device_id(c.as_ref())),
        input_channels: input
            .as_ref()
            .map_or(0, |(_, c, _)| c.channels as usize)
            .min(MAX_INPUTS) as u32,
        warning: (!notes.is_empty()).then(|| notes.join("; ")),
    };
    Ok(Opened {
        info,
        test_input: None,
        stepped: false,
        cpal: Some(Devices {
            output: (device, config),
            input: input.map(|(d, c, _)| (d, c)),
        }),
    })
}

/// The input device, if it is asked for. Input runs at the output's rate
/// and block size, so the two streams only differ by clock drift. An input
/// that cannot be had is a note, not an error: the output plays without it.
fn choose_input(
    host: &cpal::Host,
    found: &Found,
    opts: &BackendOptions,
    output: &cpal::StreamConfig,
    notes: &mut Vec<String>,
) -> Option<Chosen> {
    use anyhow::Context;
    use cpal::traits::{DeviceTrait, HostTrait};

    if !opts.input {
        return None;
    }
    let input = choose(
        &found.inputs,
        opts.input_device.as_deref(),
        "input",
        || host.default_input_device(),
        notes,
    )
    .context("no default input device")
    .and_then(|(device, chosen)| {
        let default = device.default_input_config()?;
        let input = cpal::StreamConfig {
            channels: default.channels(),
            sample_rate: output.sample_rate,
            buffer_size: output.buffer_size,
        };
        Ok((device, input, chosen))
    });
    match input {
        Ok(input) => Some(input),
        Err(err) => {
            notes.push(format!("no audio input: {err:#}"));
            None
        }
    }
}

/// The name of a device as the stream gives it: what was asked for, or for
/// the system's default, say so, and what it is now.
fn device_name(device: &cpal::Device, chosen: Option<&AudioDevice>) -> String {
    use cpal::traits::DeviceTrait;

    chosen.map_or_else(
        || {
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
}

/// The id of the device asked for: empty for the system's default.
fn device_id(chosen: Option<&AudioDevice>) -> String {
    chosen.map_or_else(String::new, |d| d.id.clone())
}

/// The most frames the engine is given at once: a longer callback is cut
/// into pieces of this many.
const CHUNK_FRAMES: usize = 8192;

pub fn start(
    devices: Devices,
    parked: Arc<Mutex<Option<Engine>>>,
    lost: Arc<Lost>,
) -> Result<Running> {
    use cpal::traits::{DeviceTrait, StreamTrait};

    let (device, config) = devices.output;
    let shared = parked.lock().unwrap().as_ref().unwrap().shared().clone();
    let errors = shared.clone();

    // cpal runs input and output as separate streams. Input reaches the
    // output callback through a ring; see `take_input` for how it is kept short.
    let in_channels = devices
        .input
        .as_ref()
        .map_or(0, |(_, c)| c.channels as usize);
    let (writer, reader) = input_ring(in_channels);
    let input = match devices.input {
        Some((in_device, in_config)) => Some(start_input(
            &in_device,
            in_config,
            writer,
            shared.clone(),
            lost.clone(),
        )?),
        None => None,
    };

    let mut output = Output {
        channels: config.channels as usize,
        sample_rate: config.sample_rate as f32,
        left: vec![0.0; CHUNK_FRAMES],
        right: vec![0.0; CHUNK_FRAMES],
        input: reader,
        load: 0.0,
        shared,
    };
    let stream = device.build_output_stream(
        config,
        move |data: &mut [f32], info: &cpal::OutputCallbackInfo| {
            no_denormals();
            output.note_timing(data.len(), info);
            // Nothing else holds this lock while the stream is alive, so
            // `try_lock` neither blocks nor fails in normal operation.
            let mut guard = parked.try_lock();
            let Some(engine) = guard.as_mut().ok().and_then(|g| g.as_mut()) else {
                data.fill(0.0);
                return;
            };
            let began = Instant::now();
            output.play(engine, data);
            output.note_load(began, data.len());
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
    Ok(Running {
        _output: stream,
        _input: input,
    })
}

/// Start the input stream, which writes what it records into the ring.
fn start_input(
    device: &cpal::Device,
    config: cpal::StreamConfig,
    mut writer: InputWriter,
    shared: Arc<Shared>,
    lost: Arc<Lost>,
) -> Result<cpal::Stream> {
    use cpal::traits::DeviceTrait;

    let stream = device.build_input_stream(
        config,
        move |data: &[f32], info: &cpal::InputCallbackInfo| writer.write(data, info),
        move |err: cpal::Error| {
            if matches!(err.kind(), cpal::ErrorKind::Xrun) {
                shared.add_xrun();
            } else if gone(&err) {
                lost.report(format!("the input stopped: {err}"));
            }
        },
        None,
    )?;
    Ok(stream)
}

/// The two ends of the ring that carries input from its stream to the
/// output's, for `channels` interleaved channels.
fn input_ring(channels: usize) -> (InputWriter, InputReader) {
    let (tx, rx) = rtrb::RingBuffer::<f32>::new((16384 * channels).max(1));
    let period = Arc::new(AtomicUsize::new(0));
    let delay = Arc::new(AtomicUsize::new(0));
    (
        InputWriter {
            tx,
            channels,
            period: period.clone(),
            delay: delay.clone(),
        },
        InputReader {
            rx,
            channels,
            period,
            delay,
            scratch: vec![0.0; CHUNK_FRAMES * channels],
            last: [0.0; MAX_INPUTS],
            latency: 0.0,
        },
    )
}

/// The input stream's end of the ring.
struct InputWriter {
    tx: rtrb::Producer<f32>,
    channels: usize,
    /// Frames in the input's last callback.
    period: Arc<AtomicUsize>,
    /// How long input waited in the system before its callback, in microseconds.
    delay: Arc<AtomicUsize>,
}

impl InputWriter {
    fn write(&mut self, data: &[f32], info: &cpal::InputCallbackInfo) {
        let channels = self.channels;
        self.period.store(data.len() / channels, Relaxed);
        let t = info.timestamp();
        let waited = t.callback.saturating_duration_since(t.capture);
        self.delay.store(waited.as_micros() as usize, Relaxed);
        // Whole frames only, so the ring never holds half of one.
        let fit = self.tx.slots() / channels * channels;
        let _ = self.tx.push_partial_slice(&data[..data.len().min(fit)]);
    }
}

/// The output stream's end of the ring.
struct InputReader {
    rx: rtrb::Consumer<f32>,
    channels: usize,
    period: Arc<AtomicUsize>,
    delay: Arc<AtomicUsize>,
    /// The input of one piece of a callback, as the engine takes it.
    scratch: Vec<f32>,
    /// The last frame read, repeated while input falls behind.
    last: [f32; MAX_INPUTS],
    /// How long input waits in the ring, in seconds, smoothed.
    latency: f32,
}

impl InputReader {
    /// The next `n` frames of input, and how late it is, told to `shared`.
    fn read(&mut self, n: usize, sample_rate: f32, shared: &Shared) -> &[f32] {
        let input = &mut self.scratch[..n * self.channels];
        if self.channels > 0 {
            let waiting = take_input(
                &mut self.rx,
                input,
                self.channels,
                self.period.load(Relaxed),
                &mut self.last,
            );
            self.latency += (waiting as f32 / sample_rate - self.latency) * 0.1;
            let system = self.delay.load(Relaxed) as f32 / 1e6;
            shared.set_input_latency(self.latency + system);
        }
        input
    }
}

/// What the output callback keeps between calls.
struct Output {
    channels: usize,
    sample_rate: f32,
    left: Vec<f32>,
    right: Vec<f32>,
    input: InputReader,
    /// The share of its time a callback takes, smoothed.
    load: f32,
    shared: Arc<Shared>,
}

impl Output {
    /// How late what is played now is heard, and how long a callback is.
    fn note_timing(&self, samples: usize, info: &cpal::OutputCallbackInfo) {
        let t = info.timestamp();
        self.shared.set_output_latency(
            t.playback
                .saturating_duration_since(t.callback)
                .as_secs_f32(),
        );
        self.shared.set_period((samples / self.channels) as u32);
    }

    /// Fill `data` with the engine's sound, in pieces of at most
    /// [`CHUNK_FRAMES`] frames.
    fn play(&mut self, engine: &mut Engine, data: &mut [f32]) {
        let channels = self.channels;
        for chunk in data.chunks_mut(self.left.len() * channels) {
            let n = chunk.len() / channels;
            let in_channels = self.input.channels;
            let input = self.input.read(n, self.sample_rate, &self.shared);
            engine.process_input(input, in_channels, &mut self.left[..n], &mut self.right[..n]);
            for (i, frame) in chunk.chunks_exact_mut(channels).enumerate() {
                frame.fill(0.0);
                frame[0] = self.left[i];
                if channels > 1 {
                    frame[1] = self.right[i];
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
    }

    /// The share of its time the callback of `samples` samples took.
    fn note_load(&mut self, began: Instant, samples: usize) {
        let frames = samples / self.channels;
        let budget = frames as f32 / self.sample_rate;
        self.load += (began.elapsed().as_secs_f32() / budget.max(1e-6) - self.load) * 0.2;
        self.shared.set_cpu(self.load);
    }
}

/// Whether a stream error means the device is gone, rather than a glitch.
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
