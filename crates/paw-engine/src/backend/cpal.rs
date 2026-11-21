//! The cpal sound backend: real audio devices. Without the `cpal` feature,
//! `no_cpal.rs` stands in with the same names.

use std::sync::atomic::Ordering::Relaxed;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use anyhow::Result;

use super::{
    AudioDevice, BackendChoice, BackendOptions, DeviceList, Lost, Opened, StreamInfo, find_device,
    no_denormals, squash, MAX_INPUTS,
};
use crate::engine::Engine;

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
                cpal: Some(Devices {
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

pub fn start(
    devices: Devices,
    parked: Arc<Mutex<Option<Engine>>>,
    lost: Arc<Lost>,
) -> Result<Running> {
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
    Ok(Running {
        _output: stream,
        _input: input,
    })
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
