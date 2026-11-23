//! Devices in the engine: made, put in place of a stand-in, updated, and
//! given their parameters, files and clips.

use std::collections::BTreeMap;
use std::sync::Arc;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use paw_engine::{Category, Controller, DeviceSlot, MAX_BLOCK, Msg, ParamInfo};
use serde_json::{Value, json};

use super::mapper::Mapper;
use super::{LiveDevice, SyncCtx};
use crate::model::{ClipContent, DeviceInst, Project, Track};

/// Whether a device takes its track's clips ([`paw_engine::device::CLIPS`]).
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) enum TakesClips {
    /// Not asked yet.
    #[default]
    Unasked,
    /// It does not know the call: not asked again.
    No,
    /// It took them; this is what it was given last.
    Given(String),
}

/// Give each device that keeps files (a plugin an attachment took) the
/// audio clips of its track and the tempo, when they changed since it was
/// given them last; the first time, to find out whether it takes them.
pub(crate) fn deliver_clips(project: &Project, ctx: &mut SyncCtx) {
    for (id, live) in ctx.live.iter_mut() {
        if !live.attached || live.clips == TakesClips::No || live.stopped.is_some() {
            continue;
        }
        let Some(controller) = live.controller.as_mut() else {
            continue;
        };
        let Some(track) = project
            .find_device(*id)
            .and_then(|(track, _)| project.all_tracks().find(|t| t.id == track))
        else {
            continue;
        };
        let text = clips_json(project, track).to_string();
        if live.clips == TakesClips::Given(text.clone()) {
            continue;
        }
        match controller.call(paw_engine::device::CLIPS, text.as_bytes()) {
            Ok(_) => live.clips = TakesClips::Given(text),
            Err(err) => {
                if matches!(live.clips, TakesClips::Given(_)) {
                    ctx.warnings.push(format!("a device did not take the clips: {err:#}"));
                }
                live.clips = TakesClips::No;
            }
        }
    }
}

/// A track's audio clips and the song's tempo, as a device that reads
/// whole clips (an ARA plugin) is given them: times in seconds from the
/// start of the song, and the tempo as points of seconds and beats.
pub(crate) fn clips_json(project: &Project, track: &Track) -> Value {
    let map = project.tempo_map();
    let clips: Vec<Value> = track
        .clips
        .iter()
        .filter_map(|clip| {
            let Some(ClipContent::Audio { file, offset, gain, .. }) = clip.playable() else {
                return None;
            };
            let start = map.seconds(clip.start);
            let end = map.seconds(clip.start + clip.length);
            Some(json!({
                "id": clip.id,
                "name": clip.name,
                "file": file,
                "offset": offset,
                "start": start,
                "length": end - start,
                "stretch": clip.stretch,
                "gain": gain,
                "muted": clip.muted,
            }))
        })
        .collect();
    // A point at each tempo change and at its end, enough for a plugin to
    // place every beat: the tempo between two points is constant, or a ramp
    // given by more points.
    let mut tempo = Vec::new();
    let end = track
        .clips
        .iter()
        .map(|c| c.start + c.length)
        .fold(0.0f64, f64::max);
    let points = project.tempo_points();
    let mut beats = Vec::new();
    for (i, p) in points.iter().enumerate() {
        beats.push(p.beat);
        // A ramp is given as a point on each beat up to the next change.
        if p.ramp {
            let next = points.get(i + 1).map_or(end, |n| n.beat);
            let mut beat = p.beat + 1.0;
            while beat < next && beats.len() < 4096 {
                beats.push(beat);
                beat += 1.0;
            }
        }
    }
    beats.push(end.max(beats.last().copied().unwrap_or(0.0)) + 1.0);
    beats.sort_by(f64::total_cmp);
    beats.dedup();
    for beat in beats {
        tempo.push(json!({ "seconds": map.seconds(beat), "beat": beat }));
    }
    let signatures: Vec<Value> = project
        .sig_points()
        .iter()
        .map(|s| json!({ "beat": s.beat, "num": s.num, "den": s.den }))
        .collect();
    json!({
        "track": { "id": track.id, "name": track.name },
        "clips": clips,
        "tempo": tempo,
        "signatures": signatures,
    })
}

/// Make a device and put it in the engine, or a stand-in for it when it is
/// made apart (see [`Mapper::defer`]).
pub(super) fn add_device(device: &DeviceInst, map: &mut Mapper, ctx: &mut SyncCtx, send: &mut dyn FnMut(Msg)) {
    // Set offline: not made, and passed over in the chain.
    if device.offline {
        return;
    }
    let Some(factory) = ctx.registry.get(&device.kind) else {
        ctx.warnings.push(format!(
            "`{}` is not installed: it is passed over, and kept with its saved state",
            device.name.as_deref().unwrap_or(&device.kind)
        ));
        return;
    };
    let too_many = |ctx: &mut SyncCtx| {
        ctx.warnings
            .push(format!("too many devices: `{}` will be skipped", device.kind));
    };
    if map.defer && !ctx.offline && factory.starts_apart() {
        let Some(slot) = map.alloc_device() else {
            return too_many(ctx);
        };
        // Until it is made: an instrument is silent, an effect passes
        // the sound through.
        let instrument = factory.info().category == Category::Instrument;
        map.devices.insert(device.id, slot);
        map.deferred.push(device.id);
        send(Msg::InsertDevice {
            slot,
            device: Box::new(Standin { instrument }),
        });
        return;
    }
    let instance = match factory.create(ctx.sample_rate, MAX_BLOCK) {
        Ok(instance) => instance,
        Err(err) => {
            ctx.warnings
                .push(format!("could not load `{}`: {err:#}", device.kind));
            return;
        }
    };
    let Some(slot) = map.alloc_device() else {
        return too_many(ctx);
    };
    let mut controller = instance.controller;
    if let (Some(controller), true) = (controller.as_mut(), ctx.offline) {
        controller.set_offline(true);
    }
    if let (Some(controller), Some(state)) = (controller.as_mut(), &device.state) {
        let loaded = BASE64
            .decode(state)
            .map_err(anyhow::Error::from)
            .and_then(|bytes| controller.load_state(&bytes));
        if let Err(err) = loaded {
            ctx.warnings.push(format!(
                "could not restore the state of `{}`: {err:#}",
                device.kind
            ));
        }
    }
    let rate = ctx.sample_rate;
    let fallback = || Fallback {
        params: factory.info().params.clone(),
        latency: factory.latency(rate),
    };
    map.devices.insert(device.id, slot);
    put_in(device, slot, instance.device, controller, fallback, ctx, send);
}

/// Put a device that was made apart (see [`Mapper::defer`]) in place of its
/// stand-in, its state already loaded, with the project's parameters and
/// bypass applied.
pub(crate) fn install(
    device: &DeviceInst,
    instance: paw_engine::Instance,
    map: &Mapper,
    ctx: &mut SyncCtx,
    send: &mut dyn FnMut(Msg),
) {
    let Some(&slot) = map.devices.get(&device.id) else {
        return;
    };
    let registry = ctx.registry;
    let fallback = || Fallback {
        params: registry
            .get(&device.kind)
            .map(|f| f.info().params.clone())
            .unwrap_or_default(),
        latency: 0,
    };
    put_in(device, slot, instance.device, instance.controller, fallback, ctx, send);
}

/// What a device without a controller is taken to have, asked of its
/// factory only then.
struct Fallback {
    params: Vec<ParamInfo>,
    latency: u32,
}

/// The part of making a device that [`add_device`] and [`install`] share:
/// it is given what scripts posted and its files, put in its slot with the
/// host's path, its parameters and bypass, and kept as live.
fn put_in(
    device: &DeviceInst,
    slot: DeviceSlot,
    engine_side: Box<dyn paw_engine::Device>,
    mut controller: Option<Box<dyn Controller>>,
    fallback: impl FnOnce() -> Fallback,
    ctx: &mut SyncCtx,
    send: &mut dyn FnMut(Msg),
) {
    if let Some(controller) = controller.as_mut() {
        controller.set_waker(ctx.waker.clone());
        deliver_posts(&device.kind, controller.as_mut(), ctx);
    }
    let attached = controller
        .as_mut()
        .is_some_and(|c| give_files(device, c.as_mut(), ctx));
    let (mut params, latency) = match &controller {
        Some(controller) => (controller.params(), controller.latency()),
        None => {
            let Fallback { params, latency } = fallback();
            (params, latency)
        }
    };
    rekey(&mut params, &device.param_ids);
    // The host's wet/dry mix and gain come after the device's own.
    let own = params.len();
    params.extend(paw_engine::host::params());
    let params = Arc::new(params);
    send(Msg::InsertDevice {
        slot,
        device: engine_side,
    });
    send(Msg::SetHost {
        device: slot,
        path: Box::new(paw_engine::host::HostPath::new(
            own as u32, latency, MAX_BLOCK,
        )),
    });
    for (index, param) in params.iter().enumerate() {
        if let Some(&value) = device.params.get(&param.key) {
            let value = param_value(param, value);
            send(Msg::SetParam {
                device: slot,
                param: index as u32,
                value: value as f32,
            });
            if let Some(controller) = controller.as_mut().filter(|_| index < own) {
                controller.set_value(index, value);
            }
        }
    }
    if device.bypass {
        send(Msg::SetBypass {
            device: slot,
            bypass: true,
        });
    }
    // A parameter can change how late the device is (a look-ahead): ask
    // again now that they are set, and hold the dry signal back to match.
    let latency = match &controller {
        Some(controller) => controller.latency(),
        None => latency,
    };
    send(Msg::SetDeviceLatency {
        device: slot,
        frames: latency,
    });
    ctx.live.insert(
        device.id,
        LiveDevice {
            params,
            controller,
            latency,
            stopped: None,
            attached,
            clips: TakesClips::Unasked,
        },
    );
}

/// Give a device that was just made the files it keeps beside its state
/// ([`paw_engine::device::FILE_LOAD`]), none the first time. Whether it
/// keeps such files: a device that does not know the call keeps none.
fn give_files(device: &DeviceInst, controller: &mut dyn Controller, ctx: &mut SyncCtx) -> bool {
    let mut files = Vec::new();
    for (name, text) in &device.files {
        match BASE64.decode(text) {
            Ok(bytes) => files.push((name.clone(), bytes)),
            Err(err) => ctx.warnings.push(format!("the {name} file of `{}`: {err}", device.kind)),
        }
    }
    match controller.call(paw_engine::device::FILE_LOAD, &paw_engine::device::pack_files(&files)) {
        Ok(_) => true,
        Err(err) => {
            if !files.is_empty() {
                ctx.warnings
                    .push(format!("`{}` did not take its files: {err:#}", device.kind));
            }
            false
        }
    }
}

/// Give a device that was just made what scripts posted to its kind
/// ([`Registry::post`](paw_engine::Registry::post)), before its first block.
fn deliver_posts(kind: &str, controller: &mut dyn Controller, ctx: &mut SyncCtx) {
    for (topic, data) in ctx.registry.posts(kind) {
        if let Err(err) = controller.call(topic, data) {
            ctx.warnings
                .push(format!("`{kind}` did not take `{topic}`: {err:#}"));
        }
    }
}

/// Give each parameter the key the project knows it by, found by the
/// device's own id for it (`ids`, key to id): a plugin whose new version
/// orders or names its parameters otherwise keeps the project's values and
/// lanes. A parameter that had the key before takes the other's.
pub(crate) fn rekey(params: &mut [ParamInfo], ids: &BTreeMap<String, String>) {
    for (key, id) in ids {
        let Some(at) = params.iter().position(|p| !p.id.is_empty() && &p.id == id) else {
            continue;
        };
        if &params[at].key == key {
            continue;
        }
        let old = std::mem::replace(&mut params[at].key, key.clone());
        if let Some(other) = params
            .iter()
            .enumerate()
            .position(|(i, p)| i != at && &p.key == key)
        {
            params[other].key = old;
        }
    }
}

/// Whether a device's parameter is one of the host's (see `paw_engine::host`):
/// the last two, by those keys.
pub(crate) fn is_host(params: &[ParamInfo], index: usize) -> bool {
    index + 2 >= params.len()
        && params
            .get(index)
            .is_some_and(|p| p.key == paw_engine::host::WET || p.key == paw_engine::host::GAIN)
}

/// What stands in the engine for a device that is still being made.
struct Standin {
    instrument: bool,
}

impl paw_engine::Device for Standin {
    fn process(&mut self, _ctx: &paw_engine::ProcessCtx, io: &mut paw_engine::Io) {
        if self.instrument {
            io.left.fill(0.0);
            io.right.fill(0.0);
        }
    }

    fn set_param(&mut self, _index: u32, _value: f32) {}
}

/// Send a device the changes from `before` to `device`: a preset or state
/// loaded, parameters and bypass.
pub(super) fn update_device(
    before: &DeviceInst,
    device: &DeviceInst,
    map: &Mapper,
    ctx: &mut SyncCtx,
    send: &mut dyn FnMut(Msg),
) {
    let (Some(&slot), Some(live)) = (map.devices.get(&device.id), ctx.live.get_mut(&device.id))
    else {
        return;
    };
    // A preset was loaded, or that was undone: the state goes in first, and
    // the preset's parameters on top of it. What the preset leaves out is
    // what the state says, not the default.
    let preset = device.loaded != before.loaded;
    let with_state = preset && device.state.is_some() && live.controller.is_some();
    if with_state && let Some(controller) = live.controller.as_mut() {
        let loaded = BASE64
            .decode(device.state.as_deref().unwrap_or(""))
            .map_err(anyhow::Error::from)
            .and_then(|bytes| controller.load_state(&bytes));
        match loaded {
            // Some plugins take a state on only in their next block, which
            // an engine at rest would not run.
            Ok(()) => ctx.waker.wake(),
            Err(err) => ctx.warnings.push(format!(
                "could not load the preset into `{}`: {err:#}",
                device.kind
            )),
        }
    }
    for (index, param) in live.params.iter().enumerate() {
        let value = device.params.get(&param.key).copied();
        if with_state && value.is_none() {
            continue;
        }
        if value != before.params.get(&param.key).copied() || (with_state && value.is_some()) {
            let value = param_value(param, value.unwrap_or(param.default as f64));
            send(Msg::SetParam {
                device: slot,
                param: index as u32,
                value: value as f32,
            });
            if let Some(controller) = live
                .controller
                .as_mut()
                .filter(|_| !is_host(&live.params, index))
            {
                controller.set_value(index, value);
            }
        }
    }
    if device.state != before.state
        && !with_state
        && let Some(controller) = live.controller.as_mut().filter(|c| c.follows_state())
    {
        let loaded = BASE64
            .decode(device.state.as_deref().unwrap_or(""))
            .map_err(anyhow::Error::from)
            .and_then(|bytes| controller.load_state(&bytes));
        match loaded {
            // Some plugins take a state on only in their next block, which
            // an engine at rest would not run.
            Ok(()) => ctx.waker.wake(),
            Err(err) => ctx.warnings.push(format!(
                "could not load the state of `{}`: {err:#}",
                device.kind
            )),
        }
    }
    if device.bypass != before.bypass {
        send(Msg::SetBypass {
            device: slot,
            bypass: device.bypass,
        });
    }
}

/// A parameter value as the device may be given it: within the parameter's
/// range, whatever a project file says. Devices are not asked to cope with
/// values they never declared (a gain of 1e300 dB is an infinite gain).
pub(super) fn param_value(param: &ParamInfo, value: f64) -> f64 {
    let (min, max) = (param.min as f64, param.max as f64);
    if value.is_nan() {
        param.default as f64
    } else if min <= max {
        value.clamp(min, max)
    } else {
        value
    }
}
