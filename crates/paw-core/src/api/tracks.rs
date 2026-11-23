//! `paw.api`: tracks.

use std::path::Path;
use std::rc::Rc;

use mlua::{Lua, Table, Value as LuaValue};
use serde_json::Value;

use crate::model::{Id, NestId};

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
        // The ids of the song's tracks, in their order. `{ nest = id }`
        // gives the tracks of that subproject instead (without its master),
        // and `{ all = true }` every track: the song's and each
        // subproject's. Views list the tracks of their scope with
        // `paw.scope.tracks()`.
        // @param opts? types.TrackListOptions
        // @return {integer}
        fn track_list(lua, sh, opts => LuaValue) {
            let opts: crate::session::TrackListOpts = options(lua, opts)?;
            Ok(sh.session.borrow().track_ids(&opts))
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

        // --- nests (subprojects): tracks with a timeline of their own ---
        // The ids of the subprojects, in the order they were made.
        // @return {integer}
        fn nest_list(_, sh, () => ()) {
            Ok(sh.session.borrow().nest_list().into_iter().map(|n| n.0).collect::<Vec<u64>>())
        }
        // A subproject as a table: its fields, `tracks` (its tracks in order,
        // without its master) and `used` (whether the song plays it). With
        // `key`, only that field of its own (`name`, `length`, `master`...):
        // this is quicker.
        // @type function(id: integer): types.Nest
        fn nest_get(lua, sh, (id, key) => (u64, Option<String>)) {
            let session = sh.session.borrow();
            match key {
                Some(key) => to_lua(lua, &session.nest_field(NestId(id), &key).lua()?),
                None => to_lua(lua, &session.nest_view(NestId(id)).lua()?),
            }
        }
        // Make a subproject with its master track and no other track, as one
        // undo step, for example `{ name = "Bridge", length = 32 }`. The length
        // is in beats, and 32 when you leave it out. Add its tracks with
        // `track_add({ nest = id })`. Returns its id.
        // @param opts? types.NestOptions
        // @return integer
        fn nest_add(lua, sh, opts => LuaValue) {
            sh.session.borrow_mut().nest_add(options(lua, opts)?).map(|n| n.0).lua()
        }
        // Promote the subproject of a block (`clip`) to song data, as one
        // undo step: its tracks come back in a group named after it at the
        // place of its return row, their clips at the row's beats, cut at
        // the block. The group track gets the master's devices and then the
        // row's, the sum of their faders in dB, the row's pan and sends, and
        // their lanes (two volume lanes added in dB). The row, the master
        // and the subproject go. A subproject saved per track (`<Space>zw`)
        // gives its clips back to the rows of its blocks instead, with no
        // group. Returns `group`, `tracks`, `from`, `to`, `zero` (the song's
        // beat of the subproject's beat 0) and `combined` (the targets of
        // the lanes made one). `paw.nest.promote` does the rest: regions,
        // the meter, the view.
        // @return types.NestPromoted
        fn nest_promote(lua, sh, clip => Id) {
            let promoted = sh.session.borrow_mut().nest_promote(clip).lua()?;
            to_lua(lua, &serde_json::to_value(promoted).map_err(mlua::Error::external)?)
        }
        // Make the block `clip` a subproject of its own, as one undo step: a
        // copy of its subproject (tracks, devices, lanes and clips) named
        // `Ballad 2`, which the block and the stems of the same block then
        // play. The other blocks keep the subproject. Returns the copy's id.
        // @return integer
        fn nest_unique(_, sh, clip => Id) {
            sh.session.borrow_mut().nest_unique(clip).map(|n| n.0).lua()
        }
        // Save a view as a subproject, as one undo step: the clips of
        // `tracks` from `from` to `to` (beats of their place) move into a
        // new subproject named `name` with the meter `meter`. Per track,
        // each row keeps its devices and gets a track of the subproject
        // with its clips; add a block on the row that plays it. With
        // `own_row`, the tracks go in (whole, or as copies with copies of
        // their devices and lanes) and one return row plays the mix; add
        // its block. `paw.nest.save` does the rest: blocks, regions, the
        // window. Returns `nest`, `rows`, `row`, `tracks` and `changes`.
        // @param opts types.NestSaveOptions
        // @return types.NestSaved
        fn nest_save(lua, sh, opts => LuaValue) {
            let saved = sh.session.borrow_mut().nest_save(options(lua, opts)?).lua()?;
            to_lua(lua, &serde_json::to_value(saved).map_err(mlua::Error::external)?)
        }
        // Make the project folder `dir` a subproject, as one undo step with
        // the block that places it. The subproject refers to the folder: the
        // song keeps no copy and reads the folder again when it opens. Its
        // tracks, its master and the subprojects inside come from the folder.
        // It follows the song's tempo (its own is kept, for `nest.time own`)
        // and keeps the meter of the folder. Its first edit, or `nest_own`,
        // makes it the song's own copy. Nothing places it yet: add a block.
        // Returns its id.
        // @return integer
        fn nest_import(_, sh, dir => String) {
            sh.session.borrow_mut().nest_import(Path::new(&dir)).map(|n| n.0).lua()
        }
        // Make subproject `id`, which refers to a project folder, the song's
        // own copy now, as one undo step, with the subprojects that came with
        // it. Returns the folder it referred to, which it keeps as `origin`.
        // @return string
        fn nest_own(_, sh, id => u64) {
            let folder = sh.session.borrow_mut().nest_own(NestId(id)).lua()?;
            Ok(folder.to_string_lossy().into_owned())
        }
        // Write a subproject as a project folder of its own at `dir`, a new
        // or empty folder. Its tracks become the project's tracks and its
        // master the master. A subproject that follows the song's tempo or
        // meter gets the song's from its first block. Its media are copied
        // into `media/`. The song does not change. Returns `path` (the
        // new `project.toml`), `tracks`, `media` (the files copied),
        // `missing` and `changes`.
        // @return types.NestExported
        fn nest_export(lua, sh, (id, dir) => (u64, String)) {
            let exported = sh.session.borrow_mut().nest_export(NestId(id), Path::new(&dir)).lua()?;
            to_lua(lua, &serde_json::to_value(exported).map_err(mlua::Error::external)?)
        }
        // Write a view as a project folder of its own at `dir`, a new or
        // empty folder: copies of `tracks` with their devices, their clips
        // and lanes from `from` to `to` (beats of their place) from beat
        // 0, the markers and regions inside, and the tempo and meter of the
        // time. A route to a track outside the view is cut, and `changes`
        // tells each cut. The song does not change. Returns what
        // `nest_export` returns.
        // @param opts types.ScopeExportOptions
        // @return types.NestExported
        fn scope_export(lua, sh, (opts, dir) => (LuaValue, String)) {
            let exported = sh.session.borrow_mut().scope_export(options(lua, opts)?, Path::new(&dir)).lua()?;
            to_lua(lua, &serde_json::to_value(exported).map_err(mlua::Error::external)?)
        }
        // Change a subproject: a table of the entries to change (`name`,
        // `length`, `tempo`, `meter`, `kind`, `meta`), as `nest_get` gives
        // them, or one `key` and its value.
        // @type function(id: integer, patch: types.Nest)
        // @type function(id: integer, key: string, value: nil)
        fn nest_set(lua, sh, (id, key, value) => (u64, LuaValue, LuaValue)) {
            let mut session = sh.session.borrow_mut();
            for (key, value) in changes(lua, key, value)? {
                let value: Value = from_lua(lua, value)?;
                session.nest_set(NestId(id), &key, value).lua()?;
            }
            Ok(())
        }

    }
    Ok(())
}
