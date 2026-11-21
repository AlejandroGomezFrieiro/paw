//! `paw.api`: tracks.

use std::rc::Rc;

use mlua::{Lua, Table, Value as LuaValue};
use serde_json::Value;

use crate::model::Id;

use super::{LuaResult, Shared, attr_from_lua, changes, from_lua, options, to_lua};

/// A track's attribute map from Lua as the data `track_set` takes.
fn attr_map_from_lua(lua: &Lua, value: LuaValue) -> mlua::Result<Value> {
    let empty = match &value {
        LuaValue::Nil | LuaValue::Boolean(false) => true,
        LuaValue::Table(t) => t.is_empty(),
        _ => false,
    };
    if empty {
        return Ok(Value::Null);
    }
    let map: crate::attr_map::AttrMap = from_lua(lua, value)?;
    serde_json::to_value(map).map_err(mlua::Error::external)
}

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- tracks ---
        // @return {integer}
        fn track_list(_, sh, () => ()) {
            Ok(sh.session.borrow().project.tracks.iter().map(|t| t.id).collect::<Vec<Id>>())
        }
        // A track as a table. With `key`, only that entry of the table: this
        // is quicker, because the table lists each clip of the track.
        // @type function(id: integer): types.Track
        fn track_get(lua, sh, (id, key) => (Id, Option<String>)) {
            let session = sh.session.borrow();
            match key {
                Some(key) => to_lua(lua, &session.track_field(id, &key).lua()?),
                None => to_lua(lua, &session.track_view(id).lua()?),
            }
        }
        // @return integer
        // @param opts? types.TrackOptions
        fn track_add(lua, sh, opts => LuaValue) { sh.session.borrow_mut().track_add(options(lua, opts)?).lua() }
        // @return nil
        fn track_remove(_, sh, id => Id) { sh.session.borrow_mut().track_remove(id).lua() }
        // @return nil
        fn track_move(_, sh, (id, index) => (Id, usize)) {
            sh.session.borrow_mut().track_move(id, index.saturating_sub(1)).lua()
        }
        // Change a track: a table of the entries to change, as `track_get`
        // gives them (`{ name = "Bass", volume = -6 }`), or one `key` and its
        // value. Only the key form clears an entry (`track_set(id, "output",
        // nil)`). An entry that is as it was is no change.
        // @type function(id: integer, patch: types.Track)
        // @type function(id: integer, key: string, value: nil)
        fn track_set(lua, sh, (id, key, value) => (Id, LuaValue, LuaValue)) {
            let mut session = sh.session.borrow_mut();
            for (key, value) in changes(lua, key, value)? {
                let value: Value = match key.as_str() {
                    // Read as a map first: its `by_type` is keyed by numbers.
                    "attr_map" => attr_map_from_lua(lua, value)?,
                    _ => from_lua(lua, value)?,
                };
                session.track_set(id, &key, value).lua()?;
            }
            Ok(())
        }
        // @return number, number
        fn track_meter(_, sh, id => Id) { Ok(sh.session.borrow().meter(id)) }
        // The milliseconds that the attribute map of the track moves a note with
        // `attr` (below 0: earlier). 0 when the track has no attribute map.
        // @param attr? types.NoteAttr
        // @return number
        fn track_attr_delay(lua, sh, (id, attr) => (Id, LuaValue)) {
            let attr = attr_from_lua(lua, attr)?.map_or(paw_engine::Attr::NONE, Into::into);
            sh.session.borrow().attr_delay(id, attr).lua()
        }

    }
    Ok(())
}
