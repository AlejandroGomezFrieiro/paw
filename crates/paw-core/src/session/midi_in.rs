//! MIDI input: ports, the track that hears them and live notes.

use super::*;

impl Session {
    /// Point MIDI input at the current engine, and open the ports while there
    /// is a real audio device. The null backend leaves them closed, so that
    /// scripts and tests only hear what they inject.
    pub(super) fn connect_midi(&mut self) {
        if let Ok(mut sink) = self.midi_sink.lock() {
            sink.engine = self.handle.take_midi_input();
        }
        // The `test` backend's pretend device is as silent as the null one.
        if matches!(self.stream.info.backend.as_str(), "null" | "test") && !self.midi_without_audio
        {
            self.midi = None;
            self.midi_out = None;
            return;
        }
        self.connect_midi_out();
        if self.midi.is_none() {
            match MidiInputs::start(self.midi_sink.clone()) {
                Ok(midi) => {
                    if self.midi_select.is_some() {
                        midi.select(self.midi_select.clone());
                    }
                    for name in &self.midi_own {
                        midi.open_port(name);
                    }
                    self.midi = Some(midi);
                }
                Err(err) => self.warnings.push(format!("no MIDI input: {err:#}")),
            }
        }
    }

    pub fn midi_inputs(&self) -> Value {
        let mut ports = self.midi.as_ref().map(|m| m.ports()).unwrap_or_default();
        if self.midi.is_none() {
            ports = self
                .test_ports
                .iter()
                .enumerate()
                .map(|(i, name)| paw_engine::midi::PortInfo {
                    id: format!("test:{i}"),
                    name: name.clone(),
                    open: true,
                    own: false,
                })
                .collect();
            // Without a sequencer the ports of our own are still listed,
            // and `midi_inject` plays the part of whoever sends to them.
            ports.extend(self.midi_own.iter().enumerate().map(|(i, name)| {
                paw_engine::midi::PortInfo {
                    id: format!("own:{i}"),
                    name: name.clone(),
                    open: true,
                    own: true,
                }
            }));
        }
        Value::Array(
            ports
                .into_iter()
                .map(|p| json!({ "id": p.id, "name": p.name, "open": p.open, "own": p.own }))
                .collect(),
        )
    }

    /// Make a MIDI port of this program's, for other programs to send to:
    /// they see it as `paw: <name>`, and tracks choose it by `name` like
    /// any other port. It is kept through engine restarts.
    pub fn midi_open_port(&mut self, name: &str) -> Result<()> {
        if name.is_empty() || name.contains('\0') {
            bail!("a MIDI port needs a name");
        }
        if !self.midi_own.iter().any(|known| known == name) {
            self.midi_own.push(name.to_string());
            if let Some(midi) = &self.midi {
                midi.open_port(name);
            }
        }
        Ok(())
    }

    /// Take away a port made by `midi_open_port`. True if there was one.
    pub fn midi_close_port(&mut self, name: &str) -> bool {
        let Some(at) = self.midi_own.iter().position(|known| known == name) else {
            return false;
        };
        self.midi_own.remove(at);
        if let Some(midi) = &self.midi {
            midi.close_port(name);
        }
        true
    }

    /// Open only the MIDI ports matching `which` (ids or parts of names), or
    /// every port with `None`.
    pub fn midi_select(&mut self, which: Option<Vec<String>>) {
        if let Some(midi) = &self.midi {
            midi.select(which.clone());
        }
        self.midi_select = which;
    }

    /// Open the MIDI ports on the null backend too, from the next engine
    /// start: for trying real MIDI with no sound.
    pub fn set_midi_without_audio(&mut self, on: bool) {
        self.midi_without_audio = on;
    }

    /// MIDI ports for the null backend to list: see `test_ports`.
    pub fn set_test_ports(&mut self, ports: Vec<String>) {
        self.test_ports = ports;
    }

    /// Deliver a message as if it came from a MIDI input port, the one
    /// named `port` or none in particular.
    pub fn midi_inject(&mut self, kind: EventKind, port: Option<&str>) {
        self.flush();
        let port = port.map_or(0, paw_engine::midi::port_key);
        self.handle.send(Msg::MidiIn { port, kind });
        self.midi_event(port, kind);
    }

    /// Have `tap` told of everything the MIDI ports receive, on their thread.
    pub fn set_midi_tap(&mut self, tap: Box<dyn FnMut(u32, EventKind) + std::marker::Send>) {
        if let Ok(mut sink) = self.midi_sink.lock() {
            sink.tap = Some(tap);
        }
    }

    /// Tell scripts about a message from a MIDI port, as a `midi.in` event
    /// naming the port when it is one of those listed (`port` is its key).
    pub fn midi_event(&mut self, port: u32, kind: EventKind) {
        let mut payload = match kind {
            EventKind::NoteOn { key, vel, ch, attr } => {
                let mut payload = json!({
                    "type": "note_on", "pitch": key, "channel": ch + 1,
                    "velocity": (vel * 127.0).round(),
                });
                if let Some(attr) = NoteAttr::of(attr) {
                    payload["attr"] = json!(attr);
                }
                payload
            }
            EventKind::NoteOff { key, ch } => {
                json!({ "type": "note_off", "pitch": key, "channel": ch + 1 })
            }
            EventKind::Control { ch, .. }
            | EventKind::NoteControl { ch, .. }
            | EventKind::Program { ch, .. } => {
                // The same shape a clip keeps it in, with the channel it came on.
                let mut payload = json!(Control::from_event(0.0, kind));
                payload["channel"] = json!(ch + 1);
                payload.as_object_mut().map(|o| o.remove("start"));
                payload
            }
            EventKind::AllNotesOff => return,
        };
        let name = self.midi_inputs().as_array().and_then(|ports| {
            ports
                .iter()
                .filter_map(|p| p["name"].as_str())
                .find(|name| paw_engine::midi::port_key(name) == port)
                .map(str::to_string)
        });
        if let Some(name) = name {
            payload["port"] = json!(name);
        }
        self.events.push(("midi.in".into(), payload));
    }

    pub fn playing(&self) -> bool {
        self.playing
    }

    /// Transport position in beats.
    pub fn position(&self) -> f64 {
        // Until the engine has carried out the last seek, its position is stale.
        if self.handle.shared.seeks() != self.seeks {
            return self.seek_target;
        }
        self.handle.shared.position()
    }

    pub fn transport_view(&self) -> Value {
        let t = &self.transport;
        json!({
            "playing": self.playing, "position": self.position(), "tempo": self.project.tempo,
            "loop_enabled": t.loop_enabled, "loop_start": t.loop_start, "loop_end": t.loop_end,
            "metronome": t.metronome, "recording": t.recording,
            "punch_enabled": t.punch_enabled, "punch_start": t.punch_start, "punch_end": t.punch_end,
            "count_in": t.count_in, "counting": self.counting(),
            "pre_roll": t.pre_roll, "pre_roll_seconds": t.pre_roll_seconds,
            "click_level": t.click_level, "click_accent": t.click_accent, "click_output": t.click_output,
            "record_offset": self.record_offset,
            "write": self.write,
            "take": self.take.as_ref().map(|t| t.number),
        })
    }

    pub fn transport_set(&mut self, key: &str, value: Value) -> Result<()> {
        if key == "write" {
            self.write = de(key, value)?;
            self.events.push(("transport.changed".into(), json!({})));
            return Ok(());
        }
        if key == "record_offset" {
            let ms: f64 = de(key, value)?;
            if !ms.is_finite() {
                bail!("the recording offset is a number of milliseconds");
            }
            self.record_offset = ms;
            return Ok(());
        }
        let t = &mut self.transport;
        match key {
            "loop_enabled" => t.loop_enabled = de(key, value)?,
            "loop_start" => t.loop_start = de::<f64>(key, value)?.max(0.0),
            "loop_end" => t.loop_end = de::<f64>(key, value)?.max(0.0),
            "metronome" => t.metronome = de(key, value)?,
            "recording" => t.recording = de(key, value)?,
            "punch_enabled" => t.punch_enabled = de(key, value)?,
            "punch_start" => t.punch_start = finite(key, de(key, value)?)?.max(0.0),
            "punch_end" => t.punch_end = finite(key, de(key, value)?)?.max(0.0),
            "count_in" => {
                let bars: f64 = de(key, value)?;
                if !(0.0..=16.0).contains(&bars) {
                    bail!("a count-in is from 0 to 16 bars");
                }
                t.count_in = bars as u32;
            }
            "pre_roll" => {
                let bars: f64 = de(key, value)?;
                if !(0.0..=16.0).contains(&bars) {
                    bail!("a pre-roll is from 0 to 16 bars");
                }
                t.pre_roll = bars as u32;
            }
            "pre_roll_seconds" => {
                let seconds: f64 = de(key, value)?;
                if !(0.0..=30.0).contains(&seconds) {
                    bail!("a pre-roll is from 0 to 30 seconds");
                }
                t.pre_roll_seconds = seconds;
            }
            "click_level" => {
                let db: f64 = de(key, value)?;
                if !(-60.0..=12.0).contains(&db) {
                    bail!("the click's level is from -60 to +12 dB");
                }
                t.click_level = db;
            }
            "click_accent" => t.click_accent = de(key, value)?,
            "click_output" => {
                let channel: f64 = de(key, value)?;
                if !(0.0..=64.0).contains(&channel) || channel.fract() != 0.0 {
                    bail!("the click's output is a channel from 1 to 64, or 0 for with the song");
                }
                t.click_output = channel as u32;
            }
            _ => bail!("the transport has no settable field `{key}`"),
        }
        // Turning recording on or off while playing punches in or out.
        if key == "recording" {
            if !self.transport.recording {
                self.finish_take();
            } else if self.playing {
                self.start_take();
            }
        }
        self.send_transport();
        self.events.push(("transport.changed".into(), json!({})));
        Ok(())
    }

    /// Play a note on a track right now, outside the timeline.
    pub fn live(&mut self, track: Id, event: EventKind) -> Result<()> {
        self.flush();
        let slot = *self
            .map
            .tracks
            .get(&track)
            .with_context(|| format!("no track {track}"))?;
        self.handle.send(Msg::Live { track: slot, event });
        Ok(())
    }

    /// Play a note on a track now, with its attribute: what the track's
    /// attribute map sends for it goes first.
    pub fn live_note(&mut self, track: Id, key: u8, vel: f32, attr: paw_engine::Attr) -> Result<()> {
        let plan = self
            .project
            .track(track)
            .and_then(|t| t.attr_map.as_ref())
            .and_then(|m| m.plan().ok());
        let (before, ch, keep) = match &plan {
            Some(plan) => plan.live(attr),
            None => (Vec::new(), None, true),
        };
        for event in before {
            self.live(track, event)?;
        }
        let attr = if keep { attr } else { paw_engine::Attr::NONE };
        let ch = ch.unwrap_or(0);
        self.live(track, EventKind::NoteOn { key, vel, ch, attr })
    }

    /// The milliseconds a note with `attr` is moved by the track's attribute map.
    pub fn attr_delay(&self, track: Id, attr: paw_engine::Attr) -> Result<f64> {
        let track = self
            .project
            .track(track)
            .with_context(|| format!("no track {track}"))?;
        Ok(match &track.attr_map {
            Some(map) => map.plan()?.delay_of(attr),
            None => 0.0,
        })
    }

    /// Stop a note played with [`live_note`](Self::live_note), on every
    /// channel the track's attribute map may have sent it to.
    pub fn live_note_off(&mut self, track: Id, key: u8) -> Result<()> {
        let channels = self
            .project
            .track(track)
            .and_then(|t| t.attr_map.as_ref())
            .and_then(|m| m.plan().ok())
            .map(|plan| plan.channels())
            .unwrap_or_default();
        for ch in channels {
            self.live(track, EventKind::NoteOff { key, ch })?;
        }
        self.live(track, EventKind::NoteOff { key, ch: 0 })
    }

    /// Post-fader peak level of a track as linear `(left, right)`.
    pub fn meter(&self, track: Id) -> (f32, f32) {
        self.map
            .tracks
            .get(&track)
            .map(|slot| self.handle.shared.meter(*slot))
            .unwrap_or((0.0, 0.0))
    }
}
