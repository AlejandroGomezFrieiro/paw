//! Plugins made apart from the session's main loop.
//!
//! Making a plugin in its helper can take seconds, or hang (a Windows
//! plugin under Wine waiting on a dead network mount). With loading apart
//! on, a device whose factory can do so ([`DeviceFactory::starts_apart`])
//! is given a stand-in in the engine at once (an instrument silent, an
//! effect passing the sound through) and is made while the program carries
//! on: a few at a time, each with its saved state loaded, and put in place
//! of its stand-in when it is ready (`device.ready`). One that fails or
//! takes too long stays a stand-in, stopped, with the reason
//! (`device.stopped`), and keeps its saved state for the next try.
//!
//! [`DeviceFactory::starts_apart`]: paw_engine::DeviceFactory::starts_apart

use crate::events::{DeviceReady, DeviceTrouble, Item, KernelEvent as E};
use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use anyhow::{Result, bail};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use paw_engine::MAX_BLOCK;
use paw_engine::device::{StartTest, Starting, test_deadline};

use super::Session;
use crate::model::Id;
use crate::sync::{SyncCtx, install};

/// How many plugins are made at the same time.
const AT_ONCE: usize = 4;

/// Longer than any plugin is let take to be made and load its state: the
/// helper's own limits end it before this.
const LONGEST: Duration = Duration::from_secs(120);

pub(super) enum Load {
    /// Waiting for its turn.
    Queued,
    Starting(Box<dyn Starting>),
    /// It could not be made, for this reason.
    Failed(String),
}

/// What a test asked of one device while it loads (`sandbox.hold`,
/// `sandbox.hang`, `sandbox.deadline`).
#[derive(Clone, Copy, Debug, Default)]
pub(super) struct LoadTest {
    /// Kept back when it is made, until `sandbox.release`: it stays a
    /// stand-in, and is no work in flight for [`Session::work`].
    held: bool,
    /// Given to the factory when the device starts.
    start: StartTest,
}

#[derive(Default)]
pub(super) struct Loads {
    /// Whether devices are made apart (see [`Session::set_load_apart`]).
    pub on: bool,
    /// By id, which is also the order they were added in.
    pub devices: BTreeMap<Id, Load>,
    /// What tests asked of devices that load, by id. An entry goes with
    /// the load: a device made again starts with none.
    tests: BTreeMap<Id, LoadTest>,
}

impl Loads {
    /// Whether the device is waiting or being made.
    pub fn loading(&self, id: Id) -> bool {
        matches!(
            self.devices.get(&id),
            Some(Load::Queued | Load::Starting(_))
        )
    }

    /// Whether a test holds the device back (`sandbox.hold`).
    fn held(&self, id: Id) -> bool {
        self.tests.get(&id).is_some_and(|test| test.held)
    }

    /// Why the device could not be made, if that is what happened to it.
    pub fn failed(&self, id: Id) -> Option<&str> {
        match self.devices.get(&id) {
            Some(Load::Failed(why)) => Some(why),
            _ => None,
        }
    }

    pub fn busy(&self) -> bool {
        self.count() > 0
    }

    /// How many devices wait or are being made.
    pub fn count(&self) -> usize {
        self.devices
            .values()
            .filter(|load| !matches!(load, Load::Failed(_)))
            .count()
    }

    /// How many devices wait or are being made, and are not held by a
    /// test: the work that the session still does by itself.
    pub fn in_flight(&self) -> usize {
        self.devices
            .iter()
            .filter(|(id, load)| !matches!(load, Load::Failed(_)) && !self.held(**id))
            .count()
    }
}

impl Session {
    /// Make plugins apart from the main loop from now on (see the module's
    /// description), or wait for each as it is added, as scripts do unless
    /// they ask otherwise. Returns what it was.
    pub fn set_load_apart(&mut self, on: bool) -> bool {
        self.flush();
        self.engine.map.defer = on;
        std::mem::replace(&mut self.loads.on, on)
    }

    /// Take note of the devices the last sync gave stand-ins, and forget
    /// those that are no longer in the engine. Called after every sync.
    pub(super) fn note_deferred(&mut self) {
        for id in std::mem::take(&mut self.engine.map.deferred) {
            // A device made again (restarted, or undone and done again)
            // starts over: dropping what was under way ends its helper.
            self.loads.devices.insert(id, Load::Queued);
            self.loads.tests.remove(&id);
        }
        let map = &self.engine.map;
        self.loads
            .devices
            .retain(|id, _| map.devices.contains_key(id));
        let loads = &self.loads.devices;
        self.loads.tests.retain(|id, _| loads.contains_key(id));
    }

    /// A test command for a device that is loading, which the session
    /// answers itself: none for another device or command. `sandbox.hold`
    /// keeps the device back when it is made, until `sandbox.release`.
    /// `sandbox.hang` and `sandbox.deadline <ms>` are for a device that has
    /// not started yet (it starts in the next turn): it is not made, and
    /// it is given up on after the deadline.
    pub(super) fn load_test(&mut self, id: Id, method: &str, data: &[u8]) -> Option<Result<Vec<u8>>> {
        const COMMANDS: [&str; 4] = ["sandbox.hold", "sandbox.release", "sandbox.hang", "sandbox.deadline"];
        if !self.loads.loading(id) || !COMMANDS.contains(&method) {
            return None;
        }
        let queued = matches!(self.loads.devices.get(&id), Some(Load::Queued));
        let test = self.loads.tests.entry(id).or_default();
        let answer = match method {
            "sandbox.hold" => {
                test.held = true;
                Ok(())
            }
            "sandbox.release" => {
                test.held = false;
                Ok(())
            }
            "sandbox.hang" | "sandbox.deadline" if !queued => {
                Err(anyhow::anyhow!("{method}: the device is being made already"))
            }
            "sandbox.hang" => {
                test.start.hang = data != b"0";
                Ok(())
            }
            _ => test_deadline(data).map(|deadline| test.start.deadline = deadline),
        };
        Some(answer.map(|()| Vec::new()))
    }

    /// Start what is waiting, while there is room, and put in place what
    /// has been made. Called regularly, from [`idle`](Self::idle).
    pub(super) fn poll_loads(&mut self) {
        if !self.loads.busy() {
            return;
        }
        let mut ready = Vec::new();
        let mut failed = Vec::new();
        for (id, load) in self.loads.devices.iter_mut() {
            // One that a test holds stays a stand-in, made or not.
            if self.loads.tests.get(id).is_some_and(|test| test.held) {
                continue;
            }
            if let Load::Starting(starting) = load
                && let Some(outcome) = starting.poll()
            {
                match outcome {
                    Ok(instance) => ready.push((*id, instance)),
                    Err(err) => {
                        let why = format!("{err:#}");
                        failed.push((*id, why.clone()));
                        *load = Load::Failed(why);
                    }
                }
            }
        }
        for (id, _) in &ready {
            self.loads.devices.remove(id);
            self.loads.tests.remove(id);
        }
        let running = self
            .loads
            .devices
            .values()
            .filter(|load| matches!(load, Load::Starting(_)))
            .count();
        let waiting: Vec<Id> = self
            .loads
            .devices
            .iter()
            .filter(|(_, load)| matches!(load, Load::Queued))
            .map(|(id, _)| *id)
            .take(AT_ONCE.saturating_sub(running))
            .collect();
        for id in waiting {
            if let Some(why) = self.start_load(id) {
                failed.push((id, why));
            }
        }
        for (id, instance) in ready {
            let Some(device) = self.doc.project.device(id).cloned() else {
                continue;
            };
            {
                let mut ctx = SyncCtx {
                    registry: &self.registry,
                    sources: &self.sources,
                    audio: &mut self.audio,
                    live: &mut self.live,
                    sample_rate: self.engine.handle.sample_rate as f32,
                    warnings: &mut self.doc.warnings,
                    offline: false,
                    waker: self.engine.handle.waker(),
                };
                let handle = &mut self.engine.handle;
                let mut send = |msg| handle.send(msg);
                install(&device, instance, &self.engine.map, &mut ctx, &mut send);
            }
            let track = self.doc.project.find_device(id).map(|(track, _)| track);
            let name = self.device_name(&device.kind);
            self.doc.emit(E::DeviceReady(DeviceReady { id, track, name }));
            self.doc.emit(E::DeviceChanged(Item::on(id, track)));
            self.doc.emit(E::changed());
            // Its latency lines the tracks up again.
            self.doc.dirty = true;
        }
        for (id, why) in failed {
            self.loads.tests.remove(&id);
            let Some((track, _)) = self.doc.project.find_device(id) else {
                continue;
            };
            let kind = self.doc.project.device(id).map_or("", |d| d.kind.as_str());
            let name = self.device_name(kind);
            self.doc.emit(E::DeviceStopped(DeviceTrouble { device: id, track, name, reason: Some(why), loading: true }));
            self.doc.emit(E::DeviceChanged(Item::on(id, Some(track))));
            self.doc.emit(E::changed());
        }
        self.flush();
    }

    /// Begin making a device that was waiting. Returns why it could not
    /// even begin, having marked it failed.
    fn start_load(&mut self, id: Id) -> Option<String> {
        let device = self.doc.project.device(id)?;
        let state = device.state.as_deref().map(|text| BASE64.decode(text));
        let why = match (self.registry.get(&device.kind), state) {
            (_, Some(Err(err))) => format!("its saved state is not base64: {err}"),
            (Some(factory), state) => {
                let state = state.and_then(Result::ok);
                let test = self.loads.tests.get(&id).map(|test| test.start).unwrap_or_default();
                match factory.start(self.engine.handle.sample_rate as f32, MAX_BLOCK, state, test) {
                    Some(starting) => {
                        self.loads.devices.insert(id, Load::Starting(starting));
                        return None;
                    }
                    None => "it cannot be made apart".into(),
                }
            }
            (None, _) => format!("`{}` is not installed", device.kind),
        };
        self.loads.devices.insert(id, Load::Failed(why.clone()));
        Some(why)
    }

    /// The name a device kind is shown with.
    pub(super) fn device_name(&self, kind: &str) -> String {
        self.registry
            .get(kind)
            .map_or_else(|| kind.to_string(), |f| f.info().name.clone())
    }

    /// Wait for one device to be made, if it is being made: for what needs
    /// the plugin itself (its parameters, its state, its window).
    pub(super) fn await_device(&mut self, id: Id) {
        let deadline = Instant::now() + LONGEST;
        while self.loads.loading(id) && Instant::now() < deadline {
            if matches!(self.loads.devices.get(&id), Some(Load::Queued))
                && let Some(why) = self.start_load(id)
            {
                self.doc.warnings.push(why);
            }
            self.poll_loads();
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    /// Wait up to `limit` for every device being made; then say which is
    /// not ready, if one is not. For rendering, which needs them all.
    pub fn await_loads(&mut self, limit: Duration) -> Result<()> {
        self.flush();
        let deadline = Instant::now() + limit;
        while self.loads.busy() && Instant::now() < deadline {
            self.poll_loads();
            std::thread::sleep(Duration::from_millis(5));
        }
        let describe = |session: &Session, id: Id| {
            let device = session.doc.project.device(id);
            let name = session.device_name(device.map_or("", |d| d.kind.as_str()));
            let track = session
                .doc.project
                .find_device(id)
                .and_then(|(track, _)| session.doc.project.track(track))
                .map_or(String::new(), |t| t.name.clone());
            format!("{name} on {track}")
        };
        match self.loads.devices.iter().next() {
            Some((id, Load::Failed(why))) => bail!(
                "{} did not load ({why}): restart it or set it offline first",
                describe(self, *id)
            ),
            Some((id, _)) => bail!("{} is still loading", describe(self, *id)),
            None => Ok(()),
        }
    }
}

/// How the next project opened is to be opened: with every plugin (CLAP,
/// LV2, VST3, and devices written in Lua) offline, or some devices (by id).
/// Taken by the next open.
#[derive(Default, Debug, Clone, serde::Deserialize)]
#[serde(default)]
pub struct OpenOpts {
    pub plugins_offline: bool,
    pub offline: Vec<Id>,
}

impl Session {
    /// Set offline what `opts` says to, in a project about to be opened.
    pub(super) fn apply_open_opts(&mut self, project: &mut crate::model::Project) {
        let opts = std::mem::take(&mut self.open_opts);
        if !opts.plugins_offline && opts.offline.is_empty() {
            return;
        }
        let registry = &self.registry;
        let plugin = |kind: &str| {
            use paw_engine::DeviceFormat::{Clap, Lua, Lv2, Vst3};
            registry
                .get(kind)
                .is_some_and(|f| matches!(f.info().format, Clap | Lv2 | Vst3 | Lua))
        };
        for track in project
            .tracks
            .iter_mut()
            .chain(std::iter::once(&mut project.master))
        {
            if !track.devices.iter().any(|d| {
                !d.offline
                    && ((opts.plugins_offline && plugin(&d.kind)) || opts.offline.contains(&d.id))
            }) {
                continue;
            }
            let track = std::sync::Arc::make_mut(track);
            for device in track.devices.iter_mut() {
                if !device.offline
                    && ((opts.plugins_offline && plugin(&device.kind))
                        || opts.offline.contains(&device.id))
                {
                    std::sync::Arc::make_mut(device).offline = true;
                }
            }
        }
    }

    /// Say how the next project is to be opened (see [`OpenOpts`]).
    pub fn set_open_opts(&mut self, opts: OpenOpts) {
        self.open_opts = opts;
    }
}
