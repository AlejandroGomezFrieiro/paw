//! `paw.api`: parts.

use std::path::Path;
use std::rc::Rc;

use mlua::{Lua, Table, Value as LuaValue};
use serde_json::Value;

use crate::model::{Id, NestId};

use super::{LuaResult, Shared, attr_from_lua, changes, field_to_lua, from_lua, options, patch, to_lua};

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- parts ---
        // The ids of the song's parts, in their order. `{ nest = id }`
        // gives the parts of that subproject instead (without its master),
        // and `{ all = true }` every part: the song's and each
        // subproject's. Views list the parts of their scope with
        // `paw.scope.parts()`.
        // @param opts? types.PartListOptions
        // @return {integer}
        fn part_list(lua, sh, opts => LuaValue) {
            let opts: crate::session::PartListOpts = options(lua, opts)?;
            Ok(sh.session.borrow().doc.part_ids(&opts))
        }
        // A part as a table. With `key`, only that entry of the table: this
        // is quicker, because the table lists each clip of the part.
        // @type function(id: integer): types.Part
        fn part_get(lua, sh, (id, key) => (Id, Option<String>)) {
            let session = sh.session.borrow();
            let view = session.doc.part_view(id).lua()?;
            match key {
                Some(key) => field_to_lua(lua, |lua| view.field(&key, lua)),
                None => to_lua(lua, &view),
            }
        }
        // @return integer
        // @param opts? types.PartOptions
        fn part_add(lua, sh, opts => LuaValue) { sh.session.borrow_mut().doc.part_add(options(lua, opts)?).lua() }
        // @return nil
        fn part_remove(_, sh, id => Id) { sh.session.borrow_mut().doc.part_remove(id).lua() }
        // @return nil
        fn part_move(_, sh, (id, index) => (Id, usize)) {
            sh.session.borrow_mut().doc.part_move(id, index.saturating_sub(1)).lua()
        }
        // Change a part: a table of the entries to change, as `part_get`
        // gives them (`{ name = "Bass", volume = -6 }`), or one `key` and its
        // value. Only the key form clears an entry (`part_set(id, "output",
        // nil)`). An entry that is as it was is no change.
        // @type function(id: integer, patch: types.PartChanges)
        // @type function(id: integer, key: string, value: nil)
        fn part_set(lua, sh, (id, key, value) => (Id, LuaValue, LuaValue)) {
            let patch: crate::session::PartPatch = patch(lua, key, value)?;
            sh.session.borrow_mut().part_patch(id, patch).lua()
        }
        // @return number, number
        fn part_meter(_, sh, id => Id) { Ok(sh.session.borrow().meter(id)) }
        // The milliseconds that the attribute map of the part moves a note with
        // `attr` (below 0: earlier). 0 when the part has no attribute map.
        // @param attr? types.NoteAttr
        // @return number
        fn part_attr_delay(lua, sh, (id, attr) => (Id, LuaValue)) {
            let attr = attr_from_lua(lua, attr)?.map_or(paw_types::Attr::NONE, Into::into);
            sh.session.borrow().doc.attr_delay(id, attr).lua()
        }

        // --- nests (subprojects): parts with a timeline of their own ---
        // The ids of the subprojects, in the order they were made.
        // @return {integer}
        fn nest_list(_, sh, () => ()) {
            Ok(sh.session.borrow().doc.nest_list().into_iter().map(|n| n.0).collect::<Vec<u64>>())
        }
        // A subproject as a table: its fields, `parts` (its parts in order,
        // without its master) and `used` (whether the song plays it). With
        // `key`, only that field of its own (`name`, `length`, `master`...):
        // this is quicker.
        // @type function(id: integer): types.Nest
        fn nest_get(lua, sh, (id, key) => (u64, Option<String>)) {
            let session = sh.session.borrow();
            match key {
                Some(key) => to_lua(lua, &session.doc.nest_field(NestId(id), &key).lua()?),
                None => to_lua(lua, &session.doc.nest_view(NestId(id)).lua()?),
            }
        }
        // Make a subproject with its master part and no other part, as one
        // undo step, for example `{ name = "Bridge", length = 32 }`. The length
        // is in beats, and 32 when you leave it out. Add its parts with
        // `part_add({ nest = id })`. Returns its id.
        // @param opts? types.NestOptions
        // @return integer
        fn nest_add(lua, sh, opts => LuaValue) {
            sh.session.borrow_mut().doc.nest_add(options(lua, opts)?).map(|n| n.0).lua()
        }
        // Promote the subproject of a block (`clip`) to song data, as one
        // undo step: its parts come back in a group named after it at the
        // place of its return row, their clips at the row's beats, cut at
        // the block. The group part gets the master's devices and then the
        // row's, the sum of their faders in dB, the row's pan and sends, and
        // their lanes (two volume lanes added in dB). The row, the master
        // and the subproject go. A subproject saved per part (`<Space>zw`)
        // gives its clips back to the rows of its blocks instead, with no
        // group. Returns `group`, `parts`, `from`, `to`, `zero` (the song's
        // beat of the subproject's beat 0) and `combined` (the targets of
        // the lanes made one). `paw.nest.promote` does the rest: regions,
        // the meter, the view.
        // @return types.NestPromoted
        fn nest_promote(lua, sh, clip => Id) {
            let promoted = sh.session.borrow_mut().nest_promote(clip).lua()?;
            to_lua(lua, &serde_json::to_value(promoted).map_err(mlua::Error::external)?)
        }
        // Make the block `clip` a subproject of its own, as one undo step: a
        // copy of its subproject (parts, devices, lanes and clips) named
        // `Ballad 2`, which the block and the stems of the same block then
        // play. The other blocks keep the subproject. Returns the copy's id.
        // @return integer
        fn nest_unique(_, sh, clip => Id) {
            sh.session.borrow_mut().doc.nest_unique(clip).map(|n| n.0).lua()
        }
        // The blocks that place block `clip` in the song: a block of the
        // song first, and `clip` last. For a block inside a subproject, its
        // block in `through` places each subproject on the way, or else its
        // first block does. Fails when no block of the song plays it.
        // @param through? {integer}
        // @return {integer}
        fn block_path(_, sh, (clip, through) => (Id, Option<Vec<Id>>)) {
            let session = sh.session.borrow();
            crate::freeze::block_path(&session.doc.project, clip, &through.unwrap_or_default()).lua()
        }
        // The song's beat of beat `beat` of the place of the last block of
        // `path` (a `block_path`): the song, or the subproject that holds
        // the block.
        // @param path {integer}
        // @return number
        fn block_song_beat(_, sh, (path, beat) => (Vec<Id>, f64)) {
            let session = sh.session.borrow();
            let timing = crate::freeze::path_timing(&session.doc.project, &path).lua()?;
            Ok(timing.map_or(beat, |t| t.song_beat(beat)))
        }
        // The beat of the place of the last block of `path` (a `block_path`)
        // at the song's beat `beat`: the inverse of `block_song_beat`.
        // @param path {integer}
        // @return number
        fn block_beat(_, sh, (path, beat) => (Vec<Id>, f64)) {
            let session = sh.session.borrow();
            let timing = crate::freeze::path_timing(&session.doc.project, &path).lua()?;
            Ok(timing.map_or(beat, |t| t.nest_beat(beat)))
        }
        // Save a view as a subproject, as one undo step: the clips of
        // `parts` from `from` to `to` (beats of their place) move into a
        // new subproject named `name` with the meter `meter`. Per part,
        // each row keeps its devices and gets a part of the subproject
        // with its clips; add a block on the row that plays it. With
        // `own_row`, the parts go in (whole, or as copies with copies of
        // their devices and lanes) and one return row plays the mix; add
        // its block. `paw.nest.save` does the rest: blocks, regions, the
        // window. Returns `nest`, `rows`, `row`, `parts`, `changes`, and with
        // a row of its own the song's `group` it is in or the `buses` that no
        // longer get the time.
        // @param opts types.NestSaveOptions
        // @return types.NestSaved
        fn nest_save(lua, sh, opts => LuaValue) {
            let saved = sh.session.borrow_mut().nest_save(options(lua, opts)?).lua()?;
            to_lua(lua, &serde_json::to_value(saved).map_err(mlua::Error::external)?)
        }
        // Make the project folder `dir` a subproject, as one undo step with
        // the block that places it. The subproject refers to the folder: the
        // song keeps no copy and reads the folder again when it opens. Its
        // parts, its master and the subprojects inside come from the folder.
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
        // or empty folder. Its parts become the project's parts and its
        // master the master. A subproject that follows the song's tempo or
        // meter gets the song's from its first block. Its media are copied
        // into `media/`. The song does not change. Returns `path` (the
        // new `project.toml`), `parts`, `media` (the files copied),
        // `missing` and `changes`.
        // @return types.NestExported
        fn nest_export(lua, sh, (id, dir) => (u64, String)) {
            let exported = sh.session.borrow_mut().nest_export(NestId(id), Path::new(&dir)).lua()?;
            to_lua(lua, &serde_json::to_value(exported).map_err(mlua::Error::external)?)
        }
        // Write a view as a project folder of its own at `dir`, a new or
        // empty folder: copies of `parts` with their devices, their clips
        // and lanes from `from` to `to` (beats of their place) from beat
        // 0, the markers and regions inside, and the tempo and meter of the
        // time. A route to a part outside the view is cut, and `changes`
        // tells each cut. The song does not change. Returns what
        // `nest_export` returns.
        // @param opts types.ScopeExportOptions
        // @return types.NestExported
        fn scope_export(lua, sh, (opts, dir) => (LuaValue, String)) {
            let exported = sh.session.borrow_mut().scope_export(options(lua, opts)?, Path::new(&dir)).lua()?;
            to_lua(lua, &serde_json::to_value(exported).map_err(mlua::Error::external)?)
        }
        // Write the whole song as a project folder of its own at `dir`, a
        // new or empty folder, with its media copied into `media/`. The
        // song does not change, and its own folder stays the same. Returns
        // what `nest_export` returns.
        // @return types.NestExported
        fn song_export(lua, sh, dir => String) {
            let exported = sh.session.borrow_mut().song_export(Path::new(&dir)).lua()?;
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
                session.doc.nest_set(NestId(id), &key, value).lua()?;
            }
            Ok(())
        }

    }
    Ok(())
}
