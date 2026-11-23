//! `paw.api`: the transport, live notes and auditions.

use std::rc::Rc;

use mlua::{Lua, Table, Value as LuaValue};
use paw_types::EventKind;

use crate::model::Id;

use super::{LuaResult, Shared, attr_from_lua, changes, from_lua, to_lua};
use super::midi::live_velocity;

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- transport ---
        // @return types.Transport
        fn transport_get(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().transport_view()) }
        // What moves of the transport by itself, as `transport_get` gives it
        // but without a table, for what is read on each frame: `playing`,
        // `position`, `counting` and `take` (nil while nothing records).
        // @return boolean, number, integer, integer
        fn transport_playhead(_, sh, () => ()) { Ok(sh.session.borrow().playhead()) }
        // Change the transport: a table of the entries to change, as
        // `transport_get` gives them (`{ loop_enabled = true }`), or one `key` and
        // its value. Only the key form clears an entry (`nil`).
        // @type function(patch: types.Transport)
        // @type function(key: string, value: nil)
        fn transport_set(lua, sh, (key, value) => (LuaValue, LuaValue)) {
            let mut session = sh.session.borrow_mut();
            for (key, value) in changes(lua, key, value)? {
                session.transport_set(&key, from_lua(lua, value)?).lua()?;
            }
            Ok(())
        }
        // @return nil
        fn transport_play(_, sh, () => ()) {
            sh.session.borrow_mut().play();
            Ok(())
        }
        // Stop the song. A take that records ends at once, and its clips
        // come a moment later, with the event `transport.recorded`.
        // @return nil
        fn transport_stop(_, sh, () => ()) {
            sh.session.borrow_mut().stop();
            Ok(())
        }
        // @return nil
        fn transport_seek(_, sh, beats => f64) {
            sh.session.borrow_mut().seek(beats);
            Ok(())
        }
        // Play a note on a track, with a MIDI 2.0 attribute if one is given.
        // @param attr? types.NoteAttr
        // @return nil
        fn note_on(lua, sh, (track, pitch, velocity, attr) => (Id, u8, Option<f64>, LuaValue)) {
            let vel = live_velocity(velocity)?;
            if pitch > 127 {
                return Err(mlua::Error::runtime(format!("a pitch goes up to 127, not {pitch}")));
            }
            let attr = attr_from_lua(lua, attr)?.map_or(paw_types::Attr::NONE, Into::into);
            sh.session.borrow_mut().live_note(track, pitch, vel, attr).lua()
        }
        // @return nil
        fn note_off(_, sh, (track, pitch) => (Id, Option<u8>)) {
            match pitch {
                Some(key) => sh.session.borrow_mut().live_note_off(track, key).lua(),
                None => sh.session.borrow_mut().live(track, EventKind::AllNotesOff).lua(),
            }
        }
        // @return nil
        fn transport_record(_, sh, () => ()) { sh.session.borrow_mut().record().lua() }

        // --- audition (session/audition.rs) ---
        // `trial_end(false)` discards the edits made after `trial_begin`. The
        // project is then as it was and the undo history does not change.
        // `trial_end(true)` keeps the edits as one step.
        // @return nil
        fn trial_begin(_, sh, () => ()) { sh.session.borrow_mut().trial_begin().lua() }
        // @return boolean
        fn trial_end(_, sh, keep => Option<bool>) { Ok(sh.session.borrow_mut().trial_end(keep.unwrap_or(false))) }
        // @return boolean
        fn trial_active(_, sh, () => ()) { Ok(sh.session.borrow().trial_active()) }
        // A sound file heard on its own over everything, outside the project.
        // @return nil
        fn preview_play(_, sh, file => String) { sh.session.borrow_mut().preview_play(std::path::Path::new(&file)).lua() }
        // @return nil
        fn preview_stop(_, sh, () => ()) {
            sh.session.borrow_mut().preview_stop();
            Ok(())
        }
        // @return nil
        fn preview_level(_, sh, db => f64) {
            sh.session.borrow_mut().preview_set_level(db);
            Ok(())
        }
        // @return types.Preview
        fn preview_get(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().preview_view()) }

    }
    Ok(())
}
