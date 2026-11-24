//! Automation lanes as the engine plays them, the faders of VCAs, and what
//! a lane that stops automating gives back.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]
#![expect(clippy::float_cmp, reason = "debt: pay down")]

use std::sync::Arc;

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use paw_engine::{AutoLane, AutoTarget, Automation, Msg, StateChange, StateLane};

use super::SyncCtx;
use super::devices::{is_host, param_value};
use super::mapper::Mapper;
use crate::model::{Id, Lane, Project, Target, Part};

/// Whether a lane moves its target: it is on and has somewhere to take it.
pub(crate) fn is_active(lane: &Lane) -> bool {
    lane.enabled && !lane.points.is_empty()
}

pub(super) fn build_automation(
    part: &Part,
    project: &Project,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
) -> Automation {
    let mut set = Automation::default();
    // A part whose automation is off keeps its lanes and plays none.
    let on = part.automation != crate::model::AutoMode::Off;
    let vca = vca_volume_lane(part, project);
    if let Some(points) = &vca {
        set.lanes.push(AutoLane::new(AutoTarget::Volume, points.clone()));
    }
    for lane in &part.lanes {
        map.state_main.remove(&lane.id);
    }
    for lane in part.lanes.iter().filter(|l| on && is_active(l)) {
        let mut range = None;
        let target = match &lane.target {
            Target::State { device } => {
                if let Some(state) = state_lane(lane, *device, map, ctx) {
                    set.states.push(state);
                }
                continue;
            }
            // The fader's lane is already there when VCAs are involved.
            Target::Volume if vca.is_some() => continue,
            Target::Volume => AutoTarget::Volume,
            Target::Pan => AutoTarget::Pan,
            Target::Param { device, param } => {
                let (Some(&slot), Some(live)) = (map.devices.get(device), ctx.live.get(device))
                else {
                    continue;
                };
                let Some(index) = live.params.iter().position(|p| &p.key == param) else {
                    continue;
                };
                range = Some(&live.params[index]);
                AutoTarget::Param {
                    device: slot,
                    index: index as u32,
                }
            }
        };
        // Shaped stretches go to the engine as the straight pieces they are played as.
        let played = lane.played();
        let points: Vec<(f64, f64)> = match range {
            Some(param) => played
                .iter()
                .map(|&(beat, v)| (beat, param_value(param, v)))
                .collect(),
            None => played.into_owned(),
        };
        set.lanes.push(AutoLane::new(target, points));
    }
    set
}

/// A state lane as the engine plays it: what each state does on the audio
/// thread (parameters, a program change, a request the device's controller
/// prepares as a message), and in `map.state_main` which states also need
/// the main thread.
pub(super) fn state_lane(lane: &Lane, device: Id, map: &mut Mapper, ctx: &mut SyncCtx) -> Option<StateLane> {
    let &slot = map.devices.get(&device)?;
    let live = ctx.live.get_mut(&device);
    let (params, mut controller) = match live {
        Some(live) => (live.params.clone(), live.controller.as_mut()),
        None => (Arc::new(Vec::new()), None),
    };
    let mut main = Vec::with_capacity(lane.states.len());
    let mut changes = Vec::with_capacity(lane.states.len());
    for state in &lane.states {
        let mut change = StateChange {
            params: state
                .params
                .iter()
                .filter_map(|(key, value)| {
                    let index = params.iter().position(|p| &p.key == key)?;
                    Some((index as u32, param_value(&params[index], *value) as f32))
                })
                .collect(),
            program: state.program.map(|p| (p, state.bank)),
            message: None,
        };
        let mut needs_main = state.state.is_some();
        if let Some(call) = &state.call {
            match controller
                .as_mut()
                .map(|c| c.prepare(&call.method, call.data.as_bytes()))
            {
                Some(Ok(Some(message))) => change.message = Some(message.into()),
                Some(Err(err)) => {
                    ctx.warnings
                        .push(format!("state `{}` of a lane: {err:#}", state.name));
                    needs_main = true;
                }
                _ => needs_main = true,
            }
        }
        main.push(needs_main);
        changes.push(change);
    }
    let points: Vec<(f64, u32)> = lane
        .points
        .iter()
        .filter(|(_, v)| (*v as usize) < lane.states.len())
        .map(|&(beat, v)| (beat, v as u32))
        .collect();
    if main.iter().any(|m| *m) {
        map.state_main.insert(lane.id, main);
    }
    Some(StateLane::new(slot, points, changes))
}

/// A lane's points: beats and values.
type Points = [(f64, f64)];

/// Whether a part is a VCA: a fader, mute and solo that belong to other
/// parts and carry no audio of their own. The runtime marks it in its meta.
pub(super) fn is_vca(part: &Part) -> bool {
    part.meta.get("vca").and_then(|v| v.as_bool()) == Some(true)
}

/// The VCAs a part is assigned to (named in its meta) that exist.
pub(super) fn vcas_of<'a>(part: &Part, project: &'a Project) -> Vec<&'a Part> {
    let Some(ids) = part.meta.get("vcas").and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    if is_vca(part) {
        return Vec::new();
    }
    project
        .parts
        .iter()
        .filter(|t| is_vca(t) && ids.iter().any(|id| id.as_u64() == Some(t.id)))
        .map(|t| &**t)
        .collect()
}

/// A fader's lane on its own: its points in dB, or `None` where the fader
/// is still (or its automation is off).
pub(super) fn fader_points(part: &Part) -> Option<&[(f64, f64)]> {
    if part.automation == crate::model::AutoMode::Off {
        return None;
    }
    part
        .lanes
        .iter()
        .find(|l| l.target == Target::Volume && is_active(l))
        .map(|l| l.points.as_slice())
}

/// The fader lane of a part that is in VCAs, when any lane is in play: the
/// sum in dB of its own fader and its VCAs' faders, each a lane or a fixed
/// value. Lanes are straight lines between points, so the sum is too, with
/// a point wherever one of them has one: the engine plays it as any lane,
/// sample by sample, and a render hears the same.
pub(super) fn vca_volume_lane(part: &Part, project: &Project) -> Option<Vec<(f64, f64)>> {
    let vcas = vcas_of(part, project);
    if vcas.is_empty() {
        return None;
    }
    let all: Vec<&Part> = std::iter::once(part).chain(vcas).collect();
    let lanes: Vec<Option<&[(f64, f64)]>> = all.iter().map(|t| fader_points(t)).collect();
    if lanes.iter().all(|l| l.is_none()) {
        return None;
    }
    let mut beats: Vec<f64> = lanes
        .iter()
        .flatten()
        .flat_map(|l| l.iter().map(|p| p.0))
        .collect();
    beats.sort_by(f64::total_cmp);
    beats.dedup();
    let sum = |at: &dyn Fn(&Points) -> f64| -> f64 {
        all.iter()
            .zip(&lanes)
            .map(|(t, l)| l.map_or(t.volume, at))
            .sum()
    };
    let mut out = Vec::new();
    for b in beats {
        // The value as a beat is reached, and as it is left (they differ at a jump).
        let before = sum(&|p| value_before(p, b));
        let after = sum(&|p| paw_types::automation::value_at(p, b).unwrap_or(0.0));
        if before != after {
            out.push((b, before));
        }
        out.push((b, after));
    }
    Some(out)
}

/// A lane's value as `beat` is approached from before it.
pub(super) fn value_before(points: &[(f64, f64)], beat: f64) -> f64 {
    let next = points.partition_point(|p| p.0 < beat);
    match (next.checked_sub(1).map(|i| points[i]), points.get(next)) {
        (None, Some(b)) => b.1,
        (Some(a), None) => a.1,
        (Some(a), Some(b)) => a.1 + (b.1 - a.1) * (beat - a.0) / (b.0 - a.0),
        (None, None) => 0.0,
    }
}

/// Put back the project's own value of anything a lane stopped automating,
/// since the engine otherwise keeps the last automated value.
pub(super) fn release_targets(
    old: &Part,
    new: &Part,
    map: &mut Mapper,
    ctx: &mut SyncCtx,
    send: &mut dyn FnMut(Msg),
) {
    let active =
        |t: &Part, target: &Target| t.lanes.iter().any(|l| &l.target == target && is_active(l));
    for lane in old
        .lanes
        .iter()
        .filter(|l| is_active(l) && !active(new, &l.target))
    {
        match &lane.target {
            // Forget what the engine was last told, so that the mix is sent again.
            Target::Volume | Target::Pan => {
                map.mix.remove(&new.id);
            }
            Target::Param { device, param } => {
                let Some(inst) = new.devices.iter().find(|d| d.id == *device) else {
                    continue;
                };
                let (Some(&slot), Some(live)) = (map.devices.get(device), ctx.live.get_mut(device))
                else {
                    continue;
                };
                let Some(index) = live.params.iter().position(|p| &p.key == param) else {
                    continue;
                };
                let value = inst
                    .params
                    .get(param)
                    .copied()
                    .unwrap_or(live.params[index].default as f64);
                let value = param_value(&live.params[index], value);
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
            // The device takes back the state the project gives it, and
            // the parameters set in the project.
            Target::State { device } => {
                let Some(inst) = new.devices.iter().find(|d| d.id == *device) else {
                    continue;
                };
                let (Some(&slot), Some(live)) = (map.devices.get(device), ctx.live.get_mut(device))
                else {
                    continue;
                };
                if live.controller.is_some()
                    && let Some(state) = &inst.state
                    && let Ok(bytes) = BASE64.decode(state)
                    && let Err(err) = live.load_state(&bytes)
                {
                    ctx.warnings
                        .push(format!("could not give a device its state back: {err:#}"));
                }
                for (index, param) in live.params.iter().enumerate() {
                    let Some(&value) = inst.params.get(&param.key) else {
                        continue;
                    };
                    let value = param_value(param, value);
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
        }
    }
}
