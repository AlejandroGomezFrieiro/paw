//! `paw.api`: the project: open, save, its files and its entries.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::Arc;

use mlua::{BString, Lua, Table, Value as LuaValue};
use serde_json::Value;

use crate::model::Id;

use super::{LuaResult, Shared, field_to_lua, from_lua, options, patch, to_lua};

#[expect(
    clippy::too_many_lines,
    reason = "one registration for each Lua function of the table, in a list"
)]
pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- project ---
        // The project as a table. With `key`, only that entry of the table:
        // this is quicker (`edits`, which goes up with each change, is asked
        // for on each key and each edit).
        // @type function(): types.Project
        fn project_get(lua, sh, key => Option<String>) {
            let session = sh.session.borrow();
            let view = session.project_view();
            match key {
                Some(key) => field_to_lua(lua, |lua| view.field(&key, lua)),
                None => to_lua(lua, &view),
            }
        }
        // Change the project: a table of the entries to change, as
        // `project_get` gives them (`{ name = "Song", tempo = 96 }`), or one
        // `key` and its value. Only the key form clears an entry (`nil`).
        // @type function(patch: types.ProjectChanges)
        // @type function(key: string, value: nil)
        fn project_set(lua, sh, (key, value) => (LuaValue, LuaValue)) {
            let patch: crate::session::ProjectPatch = patch(lua, key, value)?;
            sh.session.borrow_mut().project_patch(patch).lua()
        }
        // Put the open project aside, with its undo history, and open an empty
        // project. `project_unshelve` brings the first project back exactly as it
        // was. For checks that need their own parts (extensions/doctor).
        // @return nil
        fn project_shelve(_, sh, () => ()) { sh.session.borrow_mut().project_shelve().lua() }
        // @return nil
        fn project_unshelve(_, sh, () => ()) { sh.session.borrow_mut().project_unshelve().lua() }
        // @return boolean
        fn project_shelved(_, sh, () => ()) { Ok(sh.session.borrow().project_shelved()) }
        // @return nil
        fn project_new(_, sh, () => ()) {
            sh.session.borrow_mut().project_new();
            Ok(())
        }
        // Count the project as it is now as saved, for a script that wrote
        // what it holds somewhere itself (a clip opened alone, written
        // back to its file).
        // @return nil
        fn project_mark_saved(_, sh, () => ()) {
            sh.session.borrow_mut().mark_saved();
            Ok(())
        }
        // Count the project as changed, so that it asks to be saved, with
        // no undo step: for data that the next save writes and undo does
        // not keep (`:workspace.save!` in the project's screen).
        // @return nil
        fn project_mark_changed(_, sh, () => ()) {
            sh.session.borrow_mut().mark_changed();
            Ok(())
        }
        // `opts.plugins_offline` opens it with all plugins offline.
        // `opts.offline` is a list of devices (by id) to open offline.
        // @param opts? types.OpenOptions
        // @return nil
        fn project_load(lua, sh, (path, opts) => (String, LuaValue)) {
            let mut session = sh.session.borrow_mut();
            session.set_open_opts(options(lua, opts)?);
            let loaded = session.project_load(path.as_ref());
            session.set_open_opts(Default::default());
            loaded.lua()
        }
        // Write the project as it is now to a different file. The path of the
        // project and its modified flag do not change. The file keeps `note`
        // under `recovery`.
        // @return nil
        fn project_backup(lua, sh, (path, note) => (String, LuaValue)) {
            let note: Value = from_lua(lua, note)?;
            sh.session.borrow_mut().project_backup(Path::new(&path), note).lua()
        }
        // Open a file written by `project_backup` as the project it was a
        // copy of: under that project's own file name, and as changed.
        // `opts`: `as_path` opens it under that file name instead (for a
        // `.bak`, which has no note), and what `project_load` takes.
        // @param opts? types.OpenOptions
        // @return any
        fn project_recover(lua, sh, (path, opts) => (String, LuaValue)) {
            let as_path: Option<String> = match &opts {
                LuaValue::Table(table) => table.get("as_path")?,
                _ => None,
            };
            let mut session = sh.session.borrow_mut();
            session.set_open_opts(options(lua, opts)?);
            let recovered = session.project_recover(Path::new(&path), as_path.as_deref().map(Path::new));
            session.set_open_opts(Default::default());
            to_lua(lua, &recovered.lua()?)
        }
        // The files of a project kept in a folder, with what each holds and
        // if it differs from the disk (see `:ls`).
        // @return {types.ProjectFile}
        fn project_files(lua, sh, () => ()) {
            to_lua(lua, &sh.session.borrow_mut().project_files().lua()?)
        }
        // Read a project folder (`song` or `song/project.toml`) without
        // opening it, in the form that `undo_project` gives. `files` holds
        // the files that paw writes in the folder, by their path in it, for
        // a version that is not on the disk, such as a revision of git. paw
        // reads the media from the disk. See extensions/projdiff.
        // @param files? {string:string}
        // @return types.ProjectData
        fn project_read(lua, sh, (path, files) => (String, Option<HashMap<String, BString>>)) {
            let files = files.map(|files| {
                files
                    .into_iter()
                    .map(|(rel, bytes)| (PathBuf::from(rel), Arc::from(Vec::from(bytes))))
                    .collect()
            });
            to_lua(lua, &sh.session.borrow().project_read(Path::new(&path), files).lua()?)
        }
        // Whether `rel`, a path in a project folder, is one of the files that
        // paw writes there (`project_read` takes these from `files`).
        // @return boolean
        fn project_file_managed(_, _sh, rel => String) {
            Ok(crate::session::folder::is_managed(Path::new(&rel)))
        }
        // Save only these files of a project kept in a folder, by their path
        // in it. Returns the paths written.
        // @return {string}
        fn project_save_files(lua, sh, paths => Vec<String>) {
            let paths: Vec<PathBuf> = paths.into_iter().map(PathBuf::from).collect();
            to_lua(lua, &sh.session.borrow_mut().project_save_files(&paths).lua()?)
        }
        // Make every clip that refers to a MIDI clip file outside the
        // project the project's own. Returns how many.
        // @return integer
        fn clip_collect(_, sh, () => ()) {
            Ok(sh.session.borrow_mut().clip_collect())
        }
        // Make every part read from a folder outside the project, and every
        // chain of devices read from a file outside it, the project's own.
        // Returns how many parts and how many chains.
        // @return integer, integer
        fn part_collect(_, sh, () => ()) {
            Ok(sh.session.borrow_mut().doc.part_collect())
        }
        // Add the part of a part folder outside the project (a folder with
        // a `part.json`) at `index` (from 1; the end when nil). The project
        // refers to the folder until the part's first edit. Returns its id.
        // @return integer
        fn part_import_folder(_, sh, (folder, index) => (String, Option<usize>)) {
            sh.session.borrow_mut().part_import_folder(Path::new(&folder), index).lua()
        }
        // Give a part the devices of a chain file (a `devices.json`). With
        // `refer`, the part refers to the file until the chain's first edit.
        // Returns how many devices.
        // @return integer
        fn part_chain_file(_, sh, (part, file, refer) => (Id, String, Option<bool>)) {
            sh.session.borrow_mut().part_chain_file(part, Path::new(&file), refer.unwrap_or(true)).lua()
        }
        // Write a part's devices as a chain file: `file` (a `devices.json`)
        // and the `.state` files of the plugins beside it. Returns the files.
        // @return {string}
        fn chain_write(lua, sh, (part, file) => (Id, String)) {
            let written = sh.session.borrow_mut().chain_write(part, Path::new(&file)).lua()?;
            to_lua(lua, &written)
        }
        // The files of the open project that changed outside paw and are not
        // acted on yet: paths in its folder, or full paths outside it.
        // @return {string}
        fn project_changed_files(lua, sh, () => ()) {
            to_lua(lua, &sh.session.borrow().changed_files())
        }
        // Keep the project as paw has it: forget the changes made outside.
        // @return nil
        fn project_keep_changes(_, sh, () => ()) {
            sh.session.borrow_mut().keep_changed_files();
            Ok(())
        }
        // Read a project kept in a folder again, as one undo step.
        // @return nil
        fn project_reload(_, sh, () => ()) {
            sh.session.borrow_mut().project_reload().lua()
        }
        // Put a whole project, in the form that `undo_project` gives, in
        // place of the open one, as one edit. Its path and its undo
        // history stay, and the parts that did not change keep running.
        // See extensions/projdiff.
        // @param project types.ProjectData
        // @return nil
        fn project_replace(lua, sh, project => LuaValue) {
            sh.session.borrow_mut().project_replace(from_lua(lua, project)?).lua()
        }
        // @return string
        fn project_save(_, sh, path => Option<String>) {
            let saved = sh.session.borrow_mut().project_save(path.as_deref().map(AsRef::as_ref)).lua()?;
            Ok(saved.to_string_lossy().into_owned())
        }
        // The tabs and windows that the project file keeps, as plain data,
        // or nil. They are not part of the song: setting them is not an
        // edit, and the next save writes them (paw/layout.tl).
        // @return types.ProjectScreen
        fn project_screen(lua, sh, () => ()) {
            to_lua(lua, &sh.session.borrow().screen)
        }
        // @param value types.ProjectScreen
        // @return nil
        fn project_screen_set(lua, sh, value => LuaValue) {
            let value: Option<Value> = from_lua(lua, value)?;
            sh.session.borrow_mut().screen = value;
            Ok(())
        }

    }
    Ok(())
}
