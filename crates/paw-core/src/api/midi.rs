//! `paw.api`: MIDI ports in and out.

use std::rc::Rc;

use paw_engine::{EventKind, ump};
use mlua::{Lua, Table, Value as LuaValue};
use serde::Deserialize;

use crate::model::{Control, Id, NoteAttr};

use super::{LuaResult, Shared, from_lua, to_lua};

/// A note from Lua as if from a MIDI port: `{ type = "note_on", pitch = 60, velocity = 100 }`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct MidiEventOpts {
    #[serde(rename = "type")]
    kind: String,
    pitch: Option<u8>,
    velocity: Option<f64>,
    // Read from the table before the rest; named here so that it is allowed.
    #[allow(dead_code)]
    channel: Option<u8>,
    /// A note-on's MIDI 2.0 attribute.
    #[serde(default, deserialize_with = "crate::model::de_attr")]
    attr: Option<NoteAttr>,
}

/// A MIDI message from Lua as the engine's event: a note, or a controller
/// move in the shape a clip keeps them in, with a `channel` from 1 to 16.
fn midi_kind(lua: &Lua, event: LuaValue) -> mlua::Result<EventKind> {
    let table = match &event {
        LuaValue::Table(table) => table.clone(),
        _ => {
            return Err(mlua::Error::runtime(
                "a MIDI event is a table with a `type`",
            ));
        }
    };
    let kind: String = table.get("type")?;
    let channel: Option<u8> = table.get("channel")?;
    let ch = channel.unwrap_or(1).clamp(1, 16) - 1;
    if kind != "note_on" && kind != "note_off" {
        let control: Control = from_lua(lua, event).map_err(|err| {
            mlua::Error::runtime(format!(
                "`{kind}` is not a MIDI event that can be sent (note_on, note_off, cc, bend, \
                 pressure, registered, assignable, program): {err}"
            ))
        })?;
        if let Some(problem) = control.problem() {
            return Err(mlua::Error::runtime(format!(
                "a MIDI event cannot be that: {problem}"
            )));
        }
        return Ok(control.event(ch));
    }
    let event: MidiEventOpts = from_lua(lua, event)?;
    let pitch = || {
        event
            .pitch
            .filter(|p| *p < 128)
            .ok_or_else(|| mlua::Error::runtime("a note needs a `pitch` from 0 to 127"))
    };
    Ok(match event.kind.as_str() {
        "note_on" => {
            let vel = live_velocity(event.velocity)?;
            // As on the wire in MIDI 1.0, a note-on with no velocity is a note-off.
            if vel > 0.0 {
                EventKind::NoteOn {
                    key: pitch()?,
                    vel,
                    ch,
                    attr: event.attr.map_or(paw_engine::Attr::NONE, Into::into),
                }
            } else {
                EventKind::NoteOff { key: pitch()?, ch }
            }
        }
        _ => EventKind::NoteOff { key: pitch()?, ch },
    })
}

/// A velocity from 0 to 127, or 100 when none is given, as the engine's 0 to 1.
pub(super) fn live_velocity(velocity: Option<f64>) -> mlua::Result<f32> {
    let velocity = velocity.unwrap_or(100.0);
    if !velocity.is_finite() {
        return Err(mlua::Error::runtime(format!(
            "a velocity is a number from 0 to 127, not {velocity}"
        )));
    }
    Ok((velocity / 127.0).clamp(0.0, 1.0) as f32)
}

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- MIDI input ---
        // @return {types.MidiPort}
        fn midi_inputs(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().midi_inputs()) }
        // A port of paw that other programs can send MIDI to. `midi_close_port`
        // returns true if there was such a port to remove.
        // @return nil
        fn midi_open_port(_, sh, name => String) { sh.session.borrow_mut().midi_open_port(&name).lua() }
        // @return boolean
        fn midi_close_port(_, sh, name => String) { Ok(sh.session.borrow_mut().midi_close_port(&name)) }
        // --- MIDI output ---
        // @return {types.MidiPort}
        fn midi_outputs(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().midi_outputs()) }
        // A port of paw that other programs can read MIDI from. `midi_close_output`
        // returns true if there was such a port to remove.
        // @return nil
        fn midi_open_output(_, sh, name => String) { sh.session.borrow_mut().midi_open_output(&name).lua() }
        // @return boolean
        fn midi_close_output(_, sh, name => String) { Ok(sh.session.borrow_mut().midi_close_output(&name)) }
        // Open only the ports that match these ids or names, or all of them with nil.
        // @return nil
        fn midi_select(_, sh, which => Option<Vec<String>>) {
            sh.session.borrow_mut().midi_select(which);
            Ok(())
        }
        // With `port`, as if from the port of that name.
        // @return nil
        // @param event types.MidiEvent
        fn midi_inject(lua, sh, event => LuaValue) {
            let (port, event): (Option<String>, LuaValue) = match &event {
                LuaValue::Table(table) => {
                    // The port is where it came from, not part of the message.
                    let copy = lua.create_table()?;
                    for pair in table.pairs::<LuaValue, LuaValue>() {
                        let (key, value) = pair?;
                        copy.set(key, value)?;
                    }
                    copy.set("port", LuaValue::Nil)?;
                    (table.get("port")?, LuaValue::Table(copy))
                }
                _ => (None, event),
            };
            let kind = midi_kind(lua, event)?;
            sh.session.borrow_mut().midi_inject(kind, port.as_deref());
            Ok(())
        }
        // A Universal MIDI Packet (one or two 32-bit words), as if from a MIDI
        // 2.0 port. Returns true if the engine plays that message.
        // @return boolean
        fn midi_inject_ump(_, sh, words => Vec<u32>) {
            match ump::decode(&words) {
                Some((_, kind)) => {
                    sh.session.borrow_mut().midi_inject(kind, None);
                    Ok(true)
                }
                None => Ok(false),
            }
        }
        // What an event is as a MIDI 2.0 packet: two 32-bit words.
        // @param event types.MidiEvent
        // @return {integer}
        fn midi_ump(lua, _sh, event => LuaValue) {
            let kind = midi_kind(lua, event)?;
            Ok(ump::encode(0, kind).map(|words| words.to_vec()))
        }
        // Send a MIDI message to one track's devices right now, outside the timeline.
        // @param event types.MidiEvent
        // @return nil
        fn midi_send(lua, sh, (track, event) => (Id, LuaValue)) {
            let kind = midi_kind(lua, event)?;
            sh.session.borrow_mut().live(track, kind).lua()
        }

    }
    Ok(())
}
