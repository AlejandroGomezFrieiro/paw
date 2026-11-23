//! MIDI output: a track sends what it plays to a port (see
//! `paw_engine::midi_out`), and ports of our own that other programs read.

use anyhow::{Result, bail};
use paw_engine::midi_out::MidiOutputs;
use serde_json::{Value, json};

use super::{Session, de};
use crate::model::MidiOutput;

/// A track's MIDI output from what a script gives: a port's name, a table
/// `{ port, channel, form, members }`, or nil (or "none") for none.
pub(super) fn parse(value: Value) -> Result<Option<MidiOutput>> {
    let out = match value {
        Value::Null => return Ok(None),
        Value::String(s) if s.is_empty() || s == "none" => return Ok(None),
        Value::String(port) => MidiOutput {
            port,
            channel: None,
            form: Default::default(),
            members: None,
        },
        // An empty Lua table arrives as an empty list.
        Value::Array(a) if a.is_empty() => return Ok(None),
        value => de::<MidiOutput>("midi_output", value)?,
    };
    if out.port.is_empty() {
        bail!("a MIDI output needs a port: one of paw.midi.outputs()");
    }
    if out.channel.is_some_and(|ch| !(1..=16).contains(&ch)) {
        bail!("a MIDI channel is from 1 to 16");
    }
    if out.members.is_some_and(|n| !(1..=15).contains(&n)) {
        bail!("an MPE zone has 1 to 15 member channels");
    }
    Ok(Some(out))
}

impl Session {
    /// Start sending MIDI to the ports, from the current engine.
    pub(super) fn connect_midi_out(&mut self) {
        if !MidiOutputs::SUPPORTED {
            return;
        }
        if self.midi.out.is_none() {
            match MidiOutputs::start() {
                Ok(out) => {
                    for name in &self.midi.out_own {
                        out.open_port(name);
                    }
                    self.midi.out = Some(out);
                }
                Err(err) => {
                    self.doc.warnings.push(format!("no MIDI output: {err:#}"));
                    return;
                }
            }
        }
        if let Some(out) = &self.midi.out {
            out.set_queue(self.engine.handle.midi_output());
        }
    }

    /// The ports MIDI can be sent to, and ours that others read from.
    pub(crate) fn midi_outputs(&self) -> Value {
        let ports = self.midi.out.as_ref().map(|m| m.ports()).unwrap_or_default();
        let mut list: Vec<Value> = ports
            .into_iter()
            .map(|p| json!({ "id": p.id, "name": p.name, "own": p.own }))
            .collect();
        // Without a sequencer the ports of our own are still listed.
        if self.midi.out.is_none() {
            list.extend(
                self.midi.out_own
                    .iter()
                    .enumerate()
                    .map(|(i, name)| json!({ "id": format!("own:{i}"), "name": name, "own": true })),
            );
        }
        Value::Array(list)
    }

    /// Make a MIDI port of this program's for other programs to read from:
    /// they see it as `paw out: <name>`, and tracks send to it by `name`.
    /// It is kept through engine restarts.
    pub(crate) fn midi_open_output(&mut self, name: &str) -> Result<()> {
        if name.is_empty() || name.contains('\0') {
            bail!("a MIDI port needs a name");
        }
        if !self.midi.out_own.iter().any(|known| known == name) {
            self.midi.out_own.push(name.to_string());
            if let Some(out) = &self.midi.out {
                out.open_port(name);
            }
        }
        Ok(())
    }

    /// Take away a port made by `midi_open_output`. True if there was one.
    pub(crate) fn midi_close_output(&mut self, name: &str) -> bool {
        let Some(at) = self.midi.out_own.iter().position(|known| known == name) else {
            return false;
        };
        self.midi.out_own.remove(at);
        if let Some(out) = &self.midi.out {
            out.close_port(name);
        }
        true
    }
}
