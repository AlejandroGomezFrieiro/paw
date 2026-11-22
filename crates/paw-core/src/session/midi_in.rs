//! MIDI input: ports, the track that hears them and live notes.

use std::collections::BTreeSet;

use paw_engine::midi_filter::{Control as FilterControl, MidiFilter, Rule};

use crate::events::{KernelEvent as E, Nothing};
use super::*;

/// A control of MIDI input that tracks do not get, as a script names it:
/// a key (`note`) or a controller (`cc`), from the port of that name (every
/// port without), on a `channel` from 1 to 16 (every channel without).
#[derive(Clone, Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FilterRule {
    pub port: Option<String>,
    pub channel: Option<u8>,
    pub note: Option<u8>,
    pub cc: Option<u8>,
}

impl TryFrom<FilterRule> for Rule {
    type Error = anyhow::Error;

    fn try_from(rule: FilterRule) -> Result<Self> {
        let control = match (rule.note, rule.cc) {
            (Some(note), None) if note < 128 => FilterControl::Note(note),
            (None, Some(cc)) if cc < 128 => FilterControl::Cc(cc),
            (Some(_), Some(_)) | (None, None) => {
                bail!("a control of the MIDI input filter is a `note` or a `cc`, one of them")
            }
            _ => bail!("a `note` or a `cc` is from 0 to 127"),
        };
        let channel = match rule.channel {
            None => 0,
            Some(ch @ 1..=16) => ch,
            Some(ch) => bail!("a MIDI channel is from 1 to 16, not {ch}"),
        };
        Ok(Rule {
            port: rule.port.as_deref().map_or(0, paw_engine::midi::port_key),
            channel,
            control,
        })
    }
}

/// MIDI ports, in and out, and the track the input is heard on.
#[derive(Default)]
pub(super) struct MidiIo {
    /// MIDI input ports, open while a real audio device is.
    pub inputs: Option<MidiInputs>,
    /// Where the input goes: shared with the input thread.
    pub sink: MidiSink,
    /// The ports to open, by id or name, or `None` for all of them.
    pub select: Option<Vec<String>>,
    /// Ports of our own for other programs to send MIDI to, by name.
    pub own: Vec<String>,
    pub without_audio: bool,
    /// MIDI output, open when MIDI input is, and ports of our own for other
    /// programs to read from: session/midi_out.rs.
    pub out: Option<paw_engine::midi_out::MidiOutputs>,
    pub out_own: Vec<String>,
    /// MIDI ports to list on the null backend, which opens none, so that
    /// scripts and tests can choose among them.
    pub test_ports: Vec<String>,
    /// The controls of MIDI input that tracks do not get, by who set them
    /// (step input, learn), and all of them together as the engine has them.
    pub filters: BTreeMap<String, Vec<Rule>>,
    pub filter: MidiFilter,
}

impl Session {
    /// Point MIDI input at the current engine, and open the ports while there
    /// is a real audio device. The null backend leaves them closed, so that
    /// scripts and tests only hear what they inject.
    pub(super) fn connect_midi(&mut self) {
        if let Ok(mut sink) = self.midi.sink.lock() {
            sink.engine = self.engine.handle.take_midi_input();
        }
        // A new engine starts with no filter.
        if !self.midi.filter.is_empty() {
            self.engine.handle.send(Msg::SetMidiFilter(Box::new(self.midi.filter.clone())));
        }
        // The `test` backend's pretend device is as silent as the null one.
        if matches!(self.engine.stream.info.backend, BackendChoice::Null | BackendChoice::Test)
            && !self.midi.without_audio
        {
            self.midi.inputs = None;
            self.midi.out = None;
            return;
        }
        self.connect_midi_out();
        if self.midi.inputs.is_none() {
            match MidiInputs::start(self.midi.sink.clone()) {
                Ok(midi) => {
                    if self.midi.select.is_some() {
                        midi.select(self.midi.select.clone());
                    }
                    for name in &self.midi.own {
                        midi.open_port(name);
                    }
                    self.midi.inputs = Some(midi);
                }
                Err(err) => self.warnings.push(format!("no MIDI input: {err:#}")),
            }
        }
    }

    pub fn midi_inputs(&self) -> Value {
        let mut ports = self.midi.inputs.as_ref().map(|m| m.ports()).unwrap_or_default();
        if self.midi.inputs.is_none() {
            ports = self
                .midi
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
            ports.extend(self.midi.own.iter().enumerate().map(|(i, name)| {
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
        if !self.midi.own.iter().any(|known| known == name) {
            self.midi.own.push(name.to_string());
            if let Some(midi) = &self.midi.inputs {
                midi.open_port(name);
            }
        }
        Ok(())
    }

    /// Take away a port made by `midi_open_port`. True if there was one.
    pub fn midi_close_port(&mut self, name: &str) -> bool {
        let Some(at) = self.midi.own.iter().position(|known| known == name) else {
            return false;
        };
        self.midi.own.remove(at);
        if let Some(midi) = &self.midi.inputs {
            midi.close_port(name);
        }
        true
    }

    /// Open only the MIDI ports matching `which` (ids or parts of names), or
    /// every port with `None`.
    pub fn midi_select(&mut self, which: Option<Vec<String>>) {
        if let Some(midi) = &self.midi.inputs {
            midi.select(which.clone());
        }
        self.midi.select = which;
    }

    /// Open the MIDI ports on the null backend too, from the next engine
    /// start: for trying real MIDI with no sound.
    pub fn set_midi_without_audio(&mut self, on: bool) {
        self.midi.without_audio = on;
    }

    /// MIDI ports for the null backend to list: see `test_ports`.
    pub fn set_test_ports(&mut self, ports: Vec<String>) {
        self.midi.test_ports = ports;
    }

    /// The controls of MIDI input that tracks do not get, kept under `name`
    /// beside those that other names keep; none removes them. Scripts still
    /// hear those controls, as `midi.in` events marked `filtered`.
    pub fn set_midi_filter(&mut self, name: &str, rules: Vec<FilterRule>) -> Result<()> {
        let rules = rules.into_iter().map(Rule::try_from).collect::<Result<Vec<_>>>()?;
        let mut filters = self.midi.filters.clone();
        if rules.is_empty() {
            filters.remove(name);
        } else {
            filters.insert(name.to_string(), rules);
        }
        let all: BTreeSet<Rule> = filters.values().flatten().copied().collect();
        let filter = MidiFilter::try_from(all.into_iter().collect::<Vec<_>>())?;
        if filter != self.midi.filter {
            self.engine.handle.send(Msg::SetMidiFilter(Box::new(filter.clone())));
        }
        (self.midi.filters, self.midi.filter) = (filters, filter);
        Ok(())
    }

    /// Deliver a message as if it came from a MIDI input port, the one
    /// named `port` or none in particular.
    pub fn midi_inject(&mut self, kind: EventKind, port: Option<&str>) {
        self.flush();
        let port = port.map_or(0, paw_engine::midi::port_key);
        self.engine.handle.send(Msg::MidiIn { port, kind });
        self.midi_event(port, kind);
    }

    /// Have `tap` told of everything the MIDI ports receive, on their thread.
    pub fn set_midi_tap(&mut self, tap: Box<dyn FnMut(u32, EventKind) + std::marker::Send>) {
        if let Ok(mut sink) = self.midi.sink.lock() {
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
        if self.midi.filter.matches(port, &kind) {
            payload["filtered"] = json!(true);
        }
        self.emit(E::MidiIn(payload));
    }

    pub fn playing(&self) -> bool {
        self.play.playing
    }

    /// Transport position in beats.
    pub fn position(&self) -> f64 {
        // Until the engine has carried out the last seek, its position is stale.
        if self.engine.handle.shared.seeks() != self.play.seeks {
            return self.play.seek_target;
        }
        self.engine.handle.shared.position()
    }

    /// What moves of the transport by itself, without a table: whether it
    /// plays, the position in beats, the beats left to count in, and the
    /// number of the take being recorded.
    pub fn playhead(&self) -> (bool, f64, u32, Option<u32>) {
        (self.play.playing, self.position(), self.counting(), self.rec.take.as_ref().map(|t| t.number))
    }

    pub fn transport_view(&self) -> Value {
        let t = &self.transport;
        json!({
            "playing": self.play.playing, "position": self.position(), "tempo": self.project.tempo,
            "loop_enabled": t.loop_enabled, "loop_start": t.loop_start, "loop_end": t.loop_end,
            "metronome": t.metronome, "recording": t.recording,
            "punch_enabled": t.punch_enabled, "punch_start": t.punch_start, "punch_end": t.punch_end,
            "count_in": t.count_in, "counting": self.counting(),
            "pre_roll": t.pre_roll, "pre_roll_seconds": t.pre_roll_seconds,
            "click_level": t.click_level, "click_accent": t.click_accent, "click_output": t.click_output,
            "record_offset": self.rec.offset,
            "write": self.writing.on,
            "take": self.rec.take.as_ref().map(|t| t.number),
        })
    }

    pub fn transport_set(&mut self, key: &str, value: Value) -> Result<()> {
        let field: TransportField = key.parse()?;
        match field {
            TransportField::Write => {
                self.writing.on = de(key, value)?;
                self.emit(E::TransportChanged(Nothing {}));
                return Ok(());
            }
            TransportField::RecordOffset => {
                let ms: f64 = de(key, value)?;
                if !ms.is_finite() {
                    bail!("the recording offset is a number of milliseconds");
                }
                self.rec.offset = ms;
                return Ok(());
            }
            _ => field.set(&mut self.transport, key, value)?,
        }
        // Turning recording on or off while playing punches in or out.
        if field == TransportField::Recording {
            if !self.transport.recording {
                self.finish_take();
            } else if self.play.playing {
                self.start_take();
            }
        }
        self.send_transport();
        self.emit(E::TransportChanged(Nothing {}));
        Ok(())
    }

    /// Play a note on a track right now, outside the timeline.
    pub fn live(&mut self, track: Id, event: EventKind) -> Result<()> {
        self.flush();
        let slot = *self
            .engine.map
            .tracks
            .get(&track)
            .with_context(|| format!("no track {track}"))?;
        self.engine.handle.send(Msg::Live { track: slot, event });
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
        self.engine.map
            .tracks
            .get(&track)
            .map(|slot| self.engine.handle.shared.meter(*slot))
            .unwrap_or((0.0, 0.0))
    }
}

/// A field of the transport that [`Session::transport_set`] changes: the
/// key that Lua gives, parsed once.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum TransportField {
    Write,
    RecordOffset,
    LoopEnabled,
    LoopStart,
    LoopEnd,
    Metronome,
    Recording,
    PunchEnabled,
    PunchStart,
    PunchEnd,
    CountIn,
    PreRoll,
    PreRollSeconds,
    ClickLevel,
    ClickAccent,
    ClickOutput,
}

impl TransportField {
    /// Set this field of the transport. `Write` and `RecordOffset` belong
    /// to the session, not the transport: [`Session::transport_set`] sets
    /// them.
    fn set(self, t: &mut Transport, key: &str, value: Value) -> Result<()> {
        match self {
            Self::LoopEnabled => t.loop_enabled = de(key, value)?,
            Self::LoopStart => t.loop_start = de::<f64>(key, value)?.max(0.0),
            Self::LoopEnd => t.loop_end = de::<f64>(key, value)?.max(0.0),
            Self::Metronome => t.metronome = de(key, value)?,
            Self::Recording => t.recording = de(key, value)?,
            Self::PunchEnabled => t.punch_enabled = de(key, value)?,
            Self::PunchStart => t.punch_start = finite(key, de(key, value)?)?.max(0.0),
            Self::PunchEnd => t.punch_end = finite(key, de(key, value)?)?.max(0.0),
            Self::CountIn => {
                let bars: f64 = de(key, value)?;
                if !(0.0..=16.0).contains(&bars) {
                    bail!("a count-in is from 0 to 16 bars");
                }
                t.count_in = bars as u32;
            }
            Self::PreRoll => {
                let bars: f64 = de(key, value)?;
                if !(0.0..=16.0).contains(&bars) {
                    bail!("a pre-roll is from 0 to 16 bars");
                }
                t.pre_roll = bars as u32;
            }
            Self::PreRollSeconds => {
                let seconds: f64 = de(key, value)?;
                if !(0.0..=30.0).contains(&seconds) {
                    bail!("a pre-roll is from 0 to 30 seconds");
                }
                t.pre_roll_seconds = seconds;
            }
            Self::ClickLevel => {
                let db: f64 = de(key, value)?;
                if !(-60.0..=12.0).contains(&db) {
                    bail!("the click's level is from -60 to +12 dB");
                }
                t.click_level = db;
            }
            Self::ClickAccent => t.click_accent = de(key, value)?,
            Self::ClickOutput => {
                let channel: f64 = de(key, value)?;
                if !(0.0..=64.0).contains(&channel) || channel.fract() != 0.0 {
                    bail!("the click's output is a channel from 1 to 64, or 0 for with the song");
                }
                t.click_output = channel as u32;
            }
            Self::Write | Self::RecordOffset => unreachable!("set by the session"),
        }
        Ok(())
    }
}

impl std::str::FromStr for TransportField {
    type Err = anyhow::Error;

    fn from_str(key: &str) -> Result<Self> {
        Ok(match key {
            "write" => Self::Write,
            "record_offset" => Self::RecordOffset,
            "loop_enabled" => Self::LoopEnabled,
            "loop_start" => Self::LoopStart,
            "loop_end" => Self::LoopEnd,
            "metronome" => Self::Metronome,
            "recording" => Self::Recording,
            "punch_enabled" => Self::PunchEnabled,
            "punch_start" => Self::PunchStart,
            "punch_end" => Self::PunchEnd,
            "count_in" => Self::CountIn,
            "pre_roll" => Self::PreRoll,
            "pre_roll_seconds" => Self::PreRollSeconds,
            "click_level" => Self::ClickLevel,
            "click_accent" => Self::ClickAccent,
            "click_output" => Self::ClickOutput,
            _ => bail!("the transport has no settable field `{key}`"),
        })
    }
}
