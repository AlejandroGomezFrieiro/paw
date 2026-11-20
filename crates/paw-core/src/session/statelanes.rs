//! State lanes on the main thread.
//!
//! The engine gives a device the parts of a state it can take on its audio
//! thread (parameters, a program change, a request its controller prepared
//! as a message) on the frame of the point. What only the main thread can
//! do is done here: a plugin's whole saved state (`setState` in CLAP and
//! VST3), and a request the device could not prepare.
//!
//! - While the song plays, the session gives it when the playhead has
//!   passed the point: within a turn of the main loop, and the plugin may
//!   then take a while more to load what the state names.
//! - A render stops on the point's frame, gives it, and waits until the
//!   plugin is ready (see [`Settle`]) before it renders on. So a render
//!   has the new state from the point's frame on, the same every time.
//!
//! The explanation of state lanes in the documentation says more.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use paw_engine::Msg;

use super::Session;
use crate::model::{AutoMode, Id, Lane, LaneState, Project, Target};
use crate::sync::{LiveDevice, LiveDevices, Mapper, is_active};

/// What each state lane last gave its device from the main thread, by the
/// lane's id: the lane as it was (its address), the device's preset count
/// ([`DeviceInst::loaded`]), and the state's index.
///
/// [`DeviceInst::loaded`]: crate::model::DeviceInst::loaded
pub(crate) type Given = HashMap<Id, (usize, u32, usize)>;

/// A state lane that has states for the main thread, with its device.
struct MainLane<'a> {
    lane: &'a Arc<Lane>,
    device: Id,
    /// Which of its states need the main thread.
    main: &'a [bool],
}

fn main_lanes<'a>(project: &'a Project, map: &'a Mapper) -> Vec<MainLane<'a>> {
    let mut out = Vec::new();
    for track in project.all_tracks() {
        if track.automation == AutoMode::Off {
            continue;
        }
        for lane in &track.lanes {
            let (Target::State { device }, Some(main)) = (&lane.target, map.state_main.get(&lane.id))
            else {
                continue;
            };
            if is_active(lane) {
                out.push(MainLane {
                    lane,
                    device: *device,
                    main,
                });
            }
        }
    }
    out
}

/// The index of the state a lane gives at `beat`.
fn index_at(lane: &Lane, beat: f64) -> Option<usize> {
    paw_engine::automation::value_at(&lane.played(), beat).map(|v| v.round().max(0.0) as usize)
}

/// The devices that an active state lane drives: the project does not
/// take their state back from them, as it does not take an automated
/// parameter's value.
pub(crate) fn driven(project: &Project) -> Vec<Id> {
    project
        .all_tracks()
        .filter(|t| t.automation != AutoMode::Off)
        .flat_map(|t| &t.lanes)
        .filter(|l| is_active(l))
        .filter_map(|l| match l.target {
            Target::State { device } => Some(device),
            _ => None,
        })
        .collect()
}

/// The state each active state lane of a project gives at `beat`, with its
/// device.
pub(crate) fn states_at(project: &Project, beat: f64) -> Vec<(Id, Arc<LaneState>)> {
    let mut out = Vec::new();
    for track in project.all_tracks() {
        if track.automation == AutoMode::Off {
            continue;
        }
        for lane in track.lanes.iter().filter(|l| is_active(l)) {
            if let Target::State { device } = lane.target
                && let Some(state) = index_at(lane, beat).and_then(|i| lane.states.get(i))
            {
                out.push((device, state.clone()));
            }
        }
    }
    out
}

/// Give a device the whole of a state from the main thread, before a
/// render starts: its saved state, its request, and the parameters to set
/// (returned, to send to the render's engine).
pub(crate) fn give_all(live: &mut LiveDevice, state: &LaneState) -> Result<Vec<(u32, f32)>> {
    if let Some(controller) = live.controller.as_mut() {
        if let Some(text) = &state.state {
            let bytes = BASE64.decode(text).context("a lane's state is base64")?;
            controller.load_state(&bytes)?;
        }
        if let Some(call) = &state.call {
            controller.call(&call.method, call.data.as_bytes())?;
        }
    }
    let mut params = Vec::new();
    for (key, value) in &state.params {
        if let Some(index) = live.params.iter().position(|p| &p.key == key) {
            params.push((index as u32, *value as f32));
            if let Some(controller) = live.controller.as_mut() {
                controller.set_value(index, *value);
            }
        }
    }
    Ok(params)
}

/// Give a device the main-thread part of a state: its saved state, and a
/// request that could not be prepared for the audio thread. Returns the
/// parameters to set again after a saved state, which sets them all.
pub(crate) fn give(live: &mut LiveDevice, state: &LaneState) -> Result<Vec<(u32, f32)>> {
    let controller = live
        .controller
        .as_mut()
        .context("the device takes no saved state")?;
    if let Some(text) = &state.state {
        let bytes = BASE64.decode(text).context("a lane's state is base64")?;
        controller.load_state(&bytes)?;
    }
    if let Some(call) = &state.call
        && controller
            .prepare(&call.method, call.data.as_bytes())
            .ok()
            .flatten()
            .is_none()
    {
        controller.call(&call.method, call.data.as_bytes())?;
    }
    let mut params = Vec::new();
    if state.state.is_some() {
        for (key, value) in &state.params {
            if let Some(index) = live.params.iter().position(|p| &p.key == key) {
                params.push((index as u32, *value as f32));
                if let Some(controller) = live.controller.as_mut() {
                    controller.set_value(index, *value);
                }
            }
        }
    }
    Ok(params)
}

impl Session {
    /// While the song plays, give each device the main-thread part of the
    /// state its lane is at, when that changes. Called from `idle`.
    pub(super) fn play_states(&mut self) {
        if self.map.state_main.is_empty() || !self.playing {
            return;
        }
        let beat = self.position();
        let mut todo = Vec::new();
        for lane in main_lanes(&self.project, &self.map) {
            let Some(index) = index_at(lane.lane, beat) else {
                continue;
            };
            let loaded = self.project.device(lane.device).map_or(0, |d| d.loaded);
            let key = (Arc::as_ptr(lane.lane) as usize, loaded, index);
            if self.state_given.get(&lane.lane.id) == Some(&key) {
                continue;
            }
            self.state_given.insert(lane.lane.id, key);
            if lane.main.get(index) == Some(&true)
                && let Some(state) = lane.lane.states.get(index)
            {
                todo.push((lane.device, state.clone()));
            }
        }
        for (device, state) in todo {
            let Some(live) = self.live.get_mut(&device) else {
                continue;
            };
            match give(live, &state) {
                Ok(params) => {
                    if let Some(&slot) = self.map.devices.get(&device) {
                        for (param, value) in params {
                            self.handle.send(Msg::SetParam {
                                device: slot,
                                param,
                                value,
                            });
                        }
                    }
                }
                Err(err) => self
                    .warnings
                    .push(format!("state `{}` of a lane: {err:#}", state.name)),
            }
        }
    }
}

/// A point of a state lane where a render stops to give a device a state
/// on the main thread.
pub(crate) struct Stop {
    /// Frames of the engine from the start of the render.
    pub frame: u64,
    pub device: Id,
    pub state: Arc<LaneState>,
}

/// The main-thread states of a render: those in force at its start, and
/// the stops after it, in order. `frames(beat)` is the engine's frame of
/// a beat, from the start.
pub(crate) fn render_stops(
    project: &Project,
    map: &Mapper,
    start: f64,
    frames: impl Fn(f64) -> u64,
) -> (Vec<(Id, Arc<LaneState>)>, Vec<Stop>) {
    let mut first = Vec::new();
    let mut stops = Vec::new();
    for lane in main_lanes(project, map) {
        let mut at = index_at(lane.lane, start);
        if let Some(index) = at
            && lane.main.get(index) == Some(&true)
        {
            first.push((lane.device, lane.lane.states[index].clone()));
        }
        for &(beat, value) in &lane.lane.points {
            let index = value.round().max(0.0) as usize;
            if beat <= start || at == Some(index) {
                continue;
            }
            at = Some(index);
            if lane.main.get(index) == Some(&true) {
                stops.push(Stop {
                    frame: frames(beat),
                    device: lane.device,
                    state: lane.lane.states[index].clone(),
                });
            }
        }
    }
    stops.sort_by_key(|s| s.frame);
    (first, stops)
}

/// Waiting for plugins to be ready after a new state: until the processes
/// of the plugins that run in one have used no processor time for a
/// moment (a plugin loads a model on a thread of its own: while it works,
/// its process does), at most `limit`. A plugin in this process gives no
/// such sign: then a fixed moment.
pub(crate) struct Settle {
    began: Instant,
    limit: Duration,
    /// Each process's time when last looked at, and since when it has not grown.
    seen: HashMap<Id, (Duration, Instant)>,
    /// A plugin gives no sign, and is waited for a fixed moment.
    fixed: bool,
    /// Whether a plugin that gives no sign is waited for at all: after it
    /// was given a state, not at the start of a render.
    blind: bool,
}

/// How long a process must use no processor time to be counted as ready.
const QUIET: Duration = Duration::from_millis(150);
/// The least wait after a plugin was given a state: a plugin's process can
/// be quiet for a moment before its loading starts, more so on a busy machine.
const LEAST: Duration = Duration::from_millis(150);
/// Processor time a process may use while it is counted as quiet: two
/// of the system's ticks, for a plugin's own timers.
const NOISE: Duration = Duration::from_millis(20);
/// The wait for a plugin that gives no sign.
const FIXED: Duration = Duration::from_millis(500);

impl Settle {
    pub fn new(limit: Duration) -> Self {
        Self {
            began: Instant::now(),
            limit,
            seen: HashMap::new(),
            fixed: false,
            blind: true,
        }
    }

    /// For the start of a render: only plugins that give a sign are waited for.
    pub fn start(limit: Duration) -> Self {
        Self {
            blind: false,
            ..Self::new(limit)
        }
    }

    /// Whether the devices `ids` (all of `live` when None) are ready.
    pub fn ready(&mut self, live: &mut LiveDevices, ids: Option<&[Id]>) -> bool {
        let now = Instant::now();
        let waited = now - self.began;
        if waited >= self.limit {
            return true;
        }
        let mut ready = true;
        for (id, device) in live.iter_mut() {
            if ids.is_some_and(|ids| !ids.contains(id)) || device.stopped.is_some() {
                continue;
            }
            let Some(controller) = device.controller.as_mut() else {
                continue;
            };
            match controller.busy_time() {
                Some(time) => match self.seen.get_mut(id) {
                    Some((last, since)) if time <= *last + NOISE => {
                        ready &= now - *since >= QUIET;
                    }
                    Some(entry) => {
                        *entry = (time, now);
                        ready = false;
                    }
                    None => {
                        self.seen.insert(*id, (time, now));
                        ready = false;
                    }
                },
                None => self.fixed |= self.blind,
            }
        }
        ready
            && (!self.blind || waited >= LEAST.min(self.limit))
            && (!self.fixed || waited >= FIXED.min(self.limit))
    }

    /// Wait here until [`ready`](Self::ready).
    pub fn wait(mut self, live: &mut LiveDevices, ids: Option<&[Id]>) {
        while !self.ready(live, ids) {
            std::thread::sleep(Duration::from_millis(10));
        }
    }
}
