//! Where each track's signal goes: outputs, sends, side-chains and further
//! output pairs, solo, and the schedule the engine runs the tracks in.

use std::collections::{HashMap, HashSet};

use paw_engine::{Delay, KeyRt, MAX_DELAY, OutRt, SchedEntry, Schedule, SendRt, TrackSlot, db_to_gain};

use super::LiveDevices;
use super::automation::{is_vca, vcas_of};
use super::mapper::Mapper;
use crate::freeze::Played;
use crate::model::{DeviceInst, Id, MASTER_ID, NestId, Project, Track};

/// Where a track's signal goes, and how late it is when it leaves.
#[derive(Clone, Debug, PartialEq)]
pub(super) struct Route {
    track: Id,
    output: Id,
    sends: Vec<SendRoute>,
    /// Devices on other tracks that listen to this one: see [`Key`].
    pub keys: Vec<Key>,
    /// Further output pairs of this track's devices: see [`Out`].
    pub outs: Vec<Out>,
    /// Frames of latency of the track's own devices.
    latency: u32,
}

/// A send, as the track it leaves sees it.
#[derive(Clone, Copy, Debug, PartialEq)]
struct SendRoute {
    target: Id,
    gain: f32,
    /// Taken before the fader.
    pre: bool,
}

/// A side-chain, as the track it is taken from sees it.
#[derive(Clone, Debug, PartialEq)]
pub(super) struct Key {
    /// The track the listening device is on, and the device.
    track: Id,
    pub device: Id,
    /// Taken before the fader.
    pre: bool,
    /// Frames of latency of the devices before it on its track, which the
    /// key waits for so that it lines up with what the device hears.
    before: u32,
}

/// One of a device's further output pairs, played into another track.
#[derive(Clone, Debug, PartialEq)]
pub(super) struct Out {
    pub device: Id,
    /// 0 for the device's second pair.
    pub pair: usize,
    target: Id,
    /// Frames of latency of the track's devices up to this one, included:
    /// how late after the track's input the pair leaves.
    late: u32,
}

pub(super) type Routing = Vec<Route>;

/// Where the master of a nest that the song does not place plays: nowhere.
const NOWHERE: Id = Id::MAX;

/// The tracks that count as soloed: those that are, and the members of a
/// soloed VCA.
pub(super) fn soloed_tracks(project: &Project) -> HashSet<Id> {
    let mut out = HashSet::new();
    for t in project.all_tracks() {
        if (t.solo && !is_vca(t)) || vcas_of(t, project).iter().any(|v| v.solo) {
            out.insert(t.id);
        }
    }
    out
}

/// With some track soloed, a track still sounds if it is soloed itself, feeds a
/// soloed track, or carries a soloed track's signal on to the master: through
/// its output or a send (the reverb a soloed track sends to is heard with
/// it, and the stems of a song add up to its mix). The tracks that still
/// sound, found in one pass over the outputs.
pub(super) fn solo_paths(project: &Project, soloed: &HashSet<Id>) -> HashSet<Id> {
    let by_id: HashMap<Id, &Track> = project.tracks.iter().map(|t| (t.id, &**t)).collect();
    let mut sounding = HashSet::new();
    // Soloed tracks, and every track their sound passes through.
    let mut ahead: Vec<Id> = project.tracks.iter().map(|t| t.id).filter(|id| soloed.contains(id)).collect();
    while let Some(id) = ahead.pop() {
        if !sounding.insert(id) {
            continue;
        }
        if let Some(t) = by_id.get(&id) {
            ahead.extend(t.output.iter().chain(t.sends.iter().map(|s| &s.target)).filter(|id| by_id.contains_key(id)));
        }
    }
    // Tracks whose output reaches a soloed track. `feeds` remembers the
    // answer for every track walked through, so each is walked once.
    let mut feeds: HashMap<Id, bool> = HashMap::new();
    for t in &project.tracks {
        let mut path: Vec<&Track> = Vec::new();
        let mut beyond = false;
        let mut at = t.output;
        while let Some(&next) = at.and_then(|id| by_id.get(&id)) {
            if let Some(&known) = feeds.get(&next.id) {
                beyond = known || soloed.contains(&next.id);
                break;
            }
            if path.len() > by_id.len() {
                break;
            }
            path.push(next);
            at = next.output;
        }
        for n in path.iter().rev() {
            feeds.insert(n.id, beyond);
            beyond |= soloed.contains(&n.id);
        }
        feeds.insert(t.id, beyond);
        if beyond {
            sounding.insert(t.id);
        }
    }
    sounding
}

pub(super) fn routing_of(
    project: &Project,
    live: &LiveDevices,
    played: &HashMap<Id, Played>,
    hosts: &HashMap<NestId, Id>,
) -> Routing {
    let ids: HashSet<Id> = project.all_tracks().map(|t| t.id).collect();
    let exists = |id: Id| ids.contains(&id);
    // A device that is bypassed is not run, so it holds nothing back.
    let device_latency = |d: &DeviceInst| -> u32 {
        if d.bypass {
            return 0;
        }
        live.get(&d.id)
            .map_or(0, |l| l.latency.min(MAX_DELAY as u32))
    };
    // Nor are the devices of a frozen or held track.
    let latency = |t: &Track| -> u32 {
        if played.contains_key(&t.id) {
            return 0;
        }
        t.devices.iter().map(|d| device_latency(d)).sum()
    };
    // Side-chains, by the track they are taken from. The master feeds
    // nothing, so it keys nothing.
    let mut keys: HashMap<Id, Vec<Key>> = HashMap::new();
    for t in project.all_tracks() {
        let mut before = 0;
        for d in &t.devices {
            if let Some(source) = d
                .sidechain
                .filter(|s| exists(*s) && *s != t.id && *s != MASTER_ID)
            {
                keys.entry(source).or_default().push(Key {
                    track: t.id,
                    device: d.id,
                    pre: d.sidechain_pre,
                    before,
                });
            }
            before += device_latency(d);
        }
    }
    // Further output pairs, by the track whose devices they come from. The
    // master feeds nothing, so its devices' pairs go nowhere.
    let outs_of = |t: &Track| -> Vec<Out> {
        let mut late = 0;
        let mut outs = Vec::new();
        for d in &t.devices {
            late += device_latency(d);
            for (&pair, &target) in &d.outputs {
                if t.id != MASTER_ID && pair >= 2 && exists(target) && target != t.id {
                    outs.push(Out {
                        device: d.id,
                        pair: pair as usize - 2,
                        target,
                        late,
                    });
                }
            }
        }
        outs
    };
    project
        .all_tracks()
        .map(|t| Route {
            keys: keys.remove(&t.id).unwrap_or_default(),
            outs: outs_of(t),
            track: t.id,
            output: output_of(project, t, hosts, &exists),
            sends: t
                .sends
                .iter()
                .filter(|s| exists(s.target) && s.target != t.id)
                .map(|s| SendRoute { target: s.target, gain: db_to_gain(s.level), pre: s.pre })
                .collect(),
            latency: latency(t),
        })
        .collect()
}

/// Where a track's output goes. A nest's track plays into the nest's
/// master unless it routes elsewhere inside the nest, and the nest's master
/// into the track that holds the nest's clip: its return row.
fn output_of(project: &Project, t: &Track, hosts: &HashMap<NestId, Id>, exists: &dyn Fn(Id) -> bool) -> Id {
    let own = t.output.filter(|id| exists(*id) && *id != t.id);
    match t.nest.and_then(|n| Some((n, project.nest(n)?))) {
        Some((n, nest)) if nest.master == t.id => hosts.get(&n).copied().filter(|h| exists(*h)).unwrap_or(NOWHERE),
        Some((_, nest)) => own.unwrap_or(nest.master),
        None => own.unwrap_or(MASTER_ID),
    }
}

/// Order tracks so that each one runs after everything that feeds it, and
/// hold each connection back until the slowest signal reaching the same
/// place has arrived.
pub(super) fn build_schedule(routing: &Routing, map: &Mapper) -> Schedule {
    // The master is in the routing for its latency, not as a source.
    let sources: Vec<&Route> = routing.iter().filter(|r| r.track != MASTER_ID).collect();
    // What feeds each track: the source, and how many frames earlier than
    // its output the place it arrives at is (a side-chain arrives at a
    // device, after the devices before it).
    let mut feeders: HashMap<Id, Vec<(usize, u32)>> = HashMap::new();
    for (index, route) in sources.iter().enumerate() {
        feeders.entry(route.output).or_default().push((index, 0));
        for send in &route.sends {
            feeders.entry(send.target).or_default().push((index, 0));
        }
        for key in &route.keys {
            feeders
                .entry(key.track)
                .or_default()
                .push((index, key.before));
        }
        for out in &route.outs {
            feeders
                .entry(out.target)
                .or_default()
                .push((index, route.latency.saturating_sub(out.late)));
        }
    }
    fn visit(
        index: usize,
        sources: &[&Route],
        feeders: &HashMap<Id, Vec<(usize, u32)>>,
        state: &mut [u8],
        order: &mut Vec<usize>,
    ) {
        if state[index] != 0 {
            return;
        }
        state[index] = 1;
        for &(feeder, _) in feeders
            .get(&sources[index].track)
            .map(Vec::as_slice)
            .unwrap_or(&[])
        {
            visit(feeder, sources, feeders, state, order);
        }
        order.push(index);
    }
    let mut state = vec![0u8; sources.len()];
    let mut order = Vec::with_capacity(sources.len());
    for index in 0..sources.len() {
        visit(index, &sources, &feeders, &mut state, &mut order);
    }

    // How late each track's output is, and how late the latest signal fed
    // into it is. Feeders come first in the order, so one pass does it. A
    // side-chain that would arrive late at its device holds back the
    // track the device is on instead.
    let mut arrives: HashMap<Id, u32> = HashMap::new();
    let mut leaves: HashMap<Id, u32> = HashMap::new();
    let latest = |id: Id, leaves: &HashMap<Id, u32>| -> u32 {
        feeders
            .get(&id)
            .into_iter()
            .flatten()
            .filter_map(|&(f, early)| {
                leaves
                    .get(&sources[f].track)
                    .map(|l| l.saturating_sub(early))
            })
            .max()
            .unwrap_or(0)
    };
    for &index in &order {
        let route = sources[index];
        let arrive = latest(route.track, &leaves);
        arrives.insert(route.track, arrive);
        leaves.insert(route.track, arrive + route.latency);
    }
    let master_arrive = latest(MASTER_ID, &leaves);
    arrives.insert(MASTER_ID, master_arrive);
    let master_latency = routing
        .iter()
        .find(|r| r.track == MASTER_ID)
        .map_or(0, |r| r.latency);

    let slot = |id: &Id| map.tracks.get(id).copied();
    // What a connection into `target` waits: until the latest one gets there.
    let wait_for = |from: Id, target: Id, early: u32| -> Delay {
        let frames = (arrives.get(&target).copied().unwrap_or(0) + early)
            .saturating_sub(leaves[&from]);
        match frames {
            0 => Delay::default(),
            frames => Delay::new(frames as usize),
        }
    };
    let wait = |from: Id, target: Id| wait_for(from, target, 0);
    let mut entries: Vec<SchedEntry> = order
        .into_iter()
        .filter_map(|index| {
            let route = sources[index];
            let output = if slot(&route.output).is_some() || route.output == NOWHERE {
                route.output
            } else {
                MASTER_ID
            };
            Some(SchedEntry {
                slot: slot(&route.track)?,
                output: if output == NOWHERE {
                    TrackSlot::NONE
                } else {
                    slot(&output).unwrap_or(TrackSlot::MASTER)
                },
                delay: wait(route.track, output),
                sends: route
                    .sends
                    .iter()
                    .filter_map(|send| {
                        Some(SendRt {
                            target: slot(&send.target)?,
                            gain: send.gain,
                            pre: send.pre,
                            delay: wait(route.track, send.target),
                        })
                    })
                    .collect(),
                keys: route
                    .keys
                    .iter()
                    .filter_map(|key| {
                        Some(KeyRt {
                            device: *map.devices.get(&key.device)?,
                            track: slot(&key.track)?,
                            pre: key.pre,
                            delay: wait_for(route.track, key.track, key.before),
                        })
                    })
                    .collect(),
                outs: route
                    .outs
                    .iter()
                    .filter_map(|out| {
                        Some(OutRt {
                            device: *map.devices.get(&out.device)?,
                            pair: out.pair,
                            target: slot(&out.target)?,
                            delay: wait_for(
                                route.track,
                                out.target,
                                route.latency.saturating_sub(out.late),
                            ),
                        })
                    })
                    .collect(),
            })
        })
        .collect();
    entries.push(SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE));
    Schedule::new(entries, master_arrive + master_latency)
}
