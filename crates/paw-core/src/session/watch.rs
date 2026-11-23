//! Losing the audio device, and getting it back.
//!
//! When the device goes away (a USB interface unplugged, its server gone),
//! the transport stops, a take being recorded is closed and kept, the
//! engine goes on without sound on the null backend (so editing, saving and
//! rendering carry on), and `audio.lost` says which device it was. Every few
//! seconds the device is looked for; once it is back it is opened again
//! with the same settings (`audio.restored`). MIDI ports that go away and
//! come back are told of too (`midi.lost`, `midi.returned`); the tracks that
//! chose one take it again by its name.

use crate::events::{AudioLost, AudioRestored, KernelEvent as E, MidiPort};
use std::collections::BTreeSet;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use paw_engine::backend::{self, BackendChoice, BackendOptions, find_device};
use serde::Serialize;
use serde_json::Value;

use super::Session;
use crate::clock::{Clock, WallClock};

/// How often the device and the MIDI ports are looked at.
const LOOK: Duration = Duration::from_millis(200);

pub(super) struct Watch {
    /// Reopen the device by itself once it is back.
    pub auto: bool,
    /// How often to look for it while it is gone.
    pub period: Duration,
    /// The schedule clock that the looks wait on (`Session::set_clock`).
    pub clock: Arc<dyn Clock>,
    /// When the device and the ports were last looked at, on `clock`.
    last_look: Duration,
    gone: Option<Gone>,
    /// The MIDI ports there were at the last look, and those that went.
    ports: Option<BTreeSet<String>>,
    ports_gone: BTreeSet<String>,
}

impl Default for Watch {
    fn default() -> Self {
        Self {
            auto: true,
            period: Duration::from_secs(3),
            clock: Arc::new(WallClock::new()),
            last_look: Duration::ZERO,
            gone: None,
            ports: None,
            ports_gone: BTreeSet::new(),
        }
    }
}

/// A device that went away.
struct Gone {
    /// What it was opened with, to open it again the same way.
    wanted: BackendOptions,
    /// Its name, as told.
    name: String,
    /// When to look for it next, on the schedule clock.
    next_try: Duration,
}

impl Watch {
    /// The next time on the schedule clock when the watch looks: the next
    /// look, or the next try of a device that went.
    pub(super) fn next_due(&self) -> Duration {
        let look = self.last_look + LOOK;
        self.gone.as_ref().map_or(look, |gone| look.min(gone.next_try))
    }
}

/// The audio device that went away and is waited for (`engine_get().lost`).
#[derive(Clone, Copy, Debug, Serialize)]
pub(crate) struct Lost<'a> {
    pub device: &'a str,
    /// Whether paw goes back to it by itself when it comes back.
    pub auto: bool,
}

impl Session {
    /// Look after the device and the MIDI ports: called from `idle`.
    pub(super) fn watch_devices(&mut self) {
        let now = self.watch.clock.now();
        if now < self.watch.last_look + LOOK {
            return;
        }
        self.watch.last_look = now;
        // Another device was opened meanwhile: nothing to wait for.
        if self.watch.gone.is_some() && self.engine.stream.info.backend != BackendChoice::Null {
            self.watch.gone = None;
        }
        if self.watch.gone.is_none()
            && let Some(why) = self.engine.stream.lost.why()
        {
            self.device_lost(why);
        }
        if self
            .watch
            .gone
            .as_ref()
            .is_some_and(|g| self.watch.auto && now >= g.next_try)
        {
            let _ = self.audio_reconnect();
        }
        self.watch_ports();
    }

    /// Whether [`watch_devices`](Self::watch_devices) has anything to watch.
    pub(super) fn watching(&self) -> bool {
        self.engine.stream.info.backend != BackendChoice::Null
            || self.watch.gone.is_some()
            || self.midi.inputs.is_some()
            || !self.midi.test_ports.is_empty()
    }

    fn device_lost(&mut self, why: String) {
        let info = self.engine.stream.info.clone();
        let name = if info.input_device != "none" && info.input_device != info.device {
            format!("{} / {}", info.device, info.input_device)
        } else {
            info.device.clone()
        };
        let recording = self.rec.take.is_some();
        self.stop();
        // Open it again as it ran: the same rate and block, the same devices.
        let mut wanted = self.engine.backend.clone();
        wanted.sample_rate = Some(info.sample_rate);
        if wanted.buffer_size.is_none() && info.buffer_size > 0 {
            wanted.buffer_size = Some(info.buffer_size);
        }
        if wanted.output_device.is_none() && !info.device_id.is_empty() {
            wanted.output_device = Some(info.device_id.clone());
        }
        if wanted.input_device.is_none() && !info.input_device_id.is_empty() {
            wanted.input_device = Some(info.input_device_id.clone());
        }
        let null = BackendOptions {
            backend: BackendChoice::Null,
            sample_rate: Some(info.sample_rate),
            buffer_size: wanted.buffer_size,
            input: false,
            ..BackendOptions::default()
        };
        if let Err(err) = self.engine_restart(&null) {
            self.doc.warnings
                .push(format!("could not go on without the device: {err:#}"));
        }
        // The engine it runs on now is not the one the program was told to use.
        self.engine.backend = wanted.clone();
        self.watch.gone = Some(Gone {
            wanted,
            name: name.clone(),
            next_try: self.watch.clock.now() + self.watch.period,
        });
        let auto = self.watch.auto;
        self.doc.emit(E::AudioLost(AudioLost { device: name, reason: why, recording, auto }));
    }

    /// Whether the device that went is there again.
    fn device_back(wanted: &BackendOptions) -> bool {
        let Ok(list) = backend::list_devices(wanted) else {
            return false;
        };
        if list.backend == BackendChoice::Null && !wanted.backend.is_null() {
            return false;
        }
        match wanted.output_device.as_deref() {
            Some(name) => find_device(&list.outputs, name).is_some(),
            None => !list.outputs.is_empty(),
        }
    }

    /// Try to open the device that went away again: returns whether it is
    /// open. Does nothing (and returns true) when no device has gone.
    pub(crate) fn audio_reconnect(&mut self) -> Result<bool> {
        let Some(gone) = self.watch.gone.as_mut() else {
            return Ok(true);
        };
        gone.next_try = self.watch.clock.now() + self.watch.period;
        if !Self::device_back(&gone.wanted) {
            return Ok(false);
        }
        let (wanted, name) = (gone.wanted.clone(), gone.name.clone());
        match self.engine_restart(&wanted) {
            Ok(())
                if self.engine.stream.info.backend != BackendChoice::Null
                    || wanted.backend.is_null() =>
            {
                self.watch.gone = None;
                let engine = self.engine_info();
                self.doc.emit(E::AudioRestored(AudioRestored { device: name, engine }));
                Ok(true)
            }
            outcome => {
                // Not as it was: go on without sound, and keep looking.
                let rate = self.engine.stream.info.sample_rate;
                let null = BackendOptions {
                    backend: BackendChoice::Null,
                    sample_rate: Some(rate),
                    buffer_size: wanted.buffer_size,
                    input: false,
                    ..BackendOptions::default()
                };
                if self.engine.stream.info.backend != BackendChoice::Null || outcome.is_err() {
                    let _ = self.engine_restart(&null);
                }
                self.engine.backend = wanted;
                outcome.map(|_| false)
            }
        }
    }

    /// Reopen the device by itself when it comes back (on by default), and
    /// how often to look for it.
    pub(crate) fn set_audio_watch(&mut self, auto: Option<bool>, period: Option<Duration>) {
        if let Some(auto) = auto {
            self.watch.auto = auto;
        }
        if let Some(period) = period {
            self.watch.period = period.max(Duration::from_millis(10));
            if let Some(gone) = self.watch.gone.as_mut() {
                gone.next_try = gone.next_try.min(self.watch.clock.now() + self.watch.period);
            }
        }
    }

    /// The device that went away and is being waited for, if one has.
    pub(crate) fn audio_lost(&self) -> Option<Lost<'_>> {
        self.watch.gone.as_ref().map(|gone| Lost { device: &gone.name, auto: self.watch.auto })
    }

    /// Tell of MIDI ports that went away, and of those that came back.
    fn watch_ports(&mut self) {
        // Without the audio device the ports are closed, not gone: start
        // afresh once it is back.
        if self.watch.gone.is_some() {
            self.watch.ports = None;
            return;
        }
        let now: BTreeSet<String> = match self.midi_inputs() {
            Value::Array(ports) => ports
                .iter()
                .filter(|p| p["own"] != true)
                .filter_map(|p| p["name"].as_str().map(str::to_string))
                .collect(),
            _ => BTreeSet::new(),
        };
        let Some(before) = self.watch.ports.replace(now.clone()) else {
            return;
        };
        let tracks = |session: &Session, port: &str| -> Vec<String> {
            let key = paw_engine::midi::port_key(port);
            session
                .doc.project
                .tracks
                .iter()
                .filter(|t| {
                    t.midi_input
                        .as_ref()
                        .and_then(|m| m.port.as_deref())
                        .is_some_and(|p| paw_engine::midi::port_key(p) == key)
                })
                .map(|t| t.name.clone())
                .collect()
        };
        for port in before.difference(&now) {
            self.watch.ports_gone.insert(port.clone());
            let tracks = tracks(self, port);
            self.doc.emit(E::MidiLost(MidiPort { port: port.clone(), tracks }));
        }
        let back: Vec<String> = now
            .iter()
            .filter(|p| self.watch.ports_gone.contains(*p))
            .cloned()
            .collect();
        for port in back {
            self.watch.ports_gone.remove(&port);
            let tracks = tracks(self, &port);
            self.doc.emit(E::MidiReturned(MidiPort { port, tracks }));
        }
    }
}
