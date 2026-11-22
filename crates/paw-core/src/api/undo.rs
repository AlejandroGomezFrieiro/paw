//! `paw.api`: undo, the history and checkpoints.

use std::path::Path;
use std::rc::Rc;

use mlua::{Lua, Table, Value as LuaValue};
use serde::Deserialize;
use serde_json::json;

use crate::model::{Control, Note};

use super::{LuaResult, Shared, from_lua, to_lua};

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- undo ---
        // @return boolean
        fn undo(_, sh, () => ()) { Ok(sh.session.borrow_mut().undo()) }
        // @return boolean
        fn redo(_, sh, () => ()) { Ok(sh.session.borrow_mut().redo()) }
        // @return nil
        fn undo_checkpoint(_, sh, () => ()) {
            sh.session.borrow_mut().checkpoint();
            Ok(())
        }
        // `undo_pending` is true if the edits of this turn will close as a step.
        // `undo_discard` puts back what they changed, and no step closes
        // (`edit.before`, paw/hooks.tl).
        // @return boolean
        fn undo_pending(_, sh, () => ()) { Ok(sh.session.borrow().undo_pending()) }
        // @return boolean
        fn undo_discard(_, sh, () => ()) { Ok(sh.session.borrow_mut().undo_discard()) }
        // Make the project as it is now the start of its undo history, and
        // unchanged: a MIDI file opened as a project (paw/midifile.tl).
        // @return nil
        fn undo_reset(_, sh, () => ()) {
            sh.session.borrow_mut().undo_reset();
            Ok(())
        }
        // The undo tree and checkpoints: crate::history, session/undo.rs.
        // @return types.UndoTree
        fn undo_tree(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().undo_tree()) }
        // How many steps the history keeps, and about how many bytes of what
        // they changed: `paw.opt.undo_steps` and `undo_memory` set these.
        // @return nil
        fn undo_limits(_, sh, (steps, bytes) => (Option<usize>, Option<usize>)) {
            sh.session.borrow_mut().undo_limits(steps, bytes).lua()
        }
        // @return integer
        fn undo_current(_, sh, () => ()) { Ok(sh.session.borrow().undo_current()) }
        // @return boolean
        fn undo_goto(_, sh, id => u64) { Ok(sh.session.borrow_mut().undo_goto(id)) }
        // @return integer
        fn undo_step(_, sh, n => i64) { Ok(sh.session.borrow_mut().undo_step(n)) }
        // @return integer
        fn undo_travel(_, sh, seconds => f64) { Ok(sh.session.borrow_mut().undo_travel(seconds)) }
        // @return integer
        fn undo_name(_, sh, (name, id) => (Option<String>, Option<u64>)) {
            sh.session.borrow_mut().undo_name(id, name).lua()
        }
        // @return nil
        fn undo_keep(_, sh, (id, keep) => (u64, Option<bool>)) {
            sh.session.borrow_mut().undo_keep(id, keep.unwrap_or(true)).lua()
        }
        // @return types.UndoDiff
        fn undo_diff(lua, sh, (a, b) => (Option<u64>, Option<u64>)) {
            to_lua(lua, &sh.session.borrow_mut().undo_diff(a, b).lua()?)
        }
        // A state's project as a project file holds it (the current state's
        // by default), and the text of a project file for a project given as
        // data: see extensions/projdiff.
        // @return types.ProjectData
        fn undo_project(lua, sh, id => Option<u64>) {
            to_lua(lua, &sh.session.borrow_mut().undo_project(id).lua()?)
        }
        // @param value types.ProjectData
        // @return string
        fn project_file_text(lua, _sh, value => LuaValue) {
            crate::session::project_file_text(from_lua(lua, value)?).lua()
        }
        // A MIDI 2.0 clip file (`.midi2`): `{ notes, controls, length,
        // skipped }`, with times in beats; `skipped` says what the file held
        // that a clip has no place for.
        // @return types.Midi2Clip
        fn midi2_read(lua, _sh, path => String) {
            let bytes = std::fs::read(&path).map_err(|e| mlua::Error::runtime(format!("{path}: {e}")))?;
            let clip = crate::clipfile::decode(&bytes).lua()?;
            to_lua(lua, &json!({
                "notes": clip.notes, "controls": clip.controls, "length": clip.length, "skipped": clip.skipped,
            }))
        }
        // Write notes and controller moves (`{ notes, controls, length }`) as
        // a MIDI 2.0 clip file, all or nothing.
        // @param clip types.Midi2Clip
        // @return nil
        fn midi2_write(lua, _sh, (path, clip) => (String, LuaValue)) {
            #[derive(Deserialize)]
            struct Given {
                #[serde(default)]
                notes: Vec<Note>,
                #[serde(default)]
                controls: Vec<Control>,
                #[serde(default)]
                length: f64,
            }
            let given: Given = from_lua(lua, clip)?;
            let bytes = crate::clipfile::encode(&given.notes, &given.controls, given.length);
            crate::safe::write_file(Path::new(&path), &bytes, false).lua()
        }
        // A MIDI 2.0 clip file as text, one note or controller move to a line,
        // as `paw clip cat` prints it.
        // @return string
        fn midi2_text(_, _sh, path => String) {
            let bytes = std::fs::read(&path).map_err(|e| mlua::Error::runtime(format!("{path}: {e}")))?;
            Ok(crate::clipfile::text(&crate::clipfile::decode(&bytes).lua()?))
        }
        // Give a name to the open step. The first name wins. nil removes a name
        // given while the step changed nothing.
        // @return nil
        fn undo_label(_, sh, text => Option<String>) {
            sh.session.borrow_mut().undo_label(text);
            Ok(())
        }
        // Put the project back as it was before the last step, so that a
        // command runs again and its edits take the step's place:
        // `paw.commands.adjust`. `before` is the state the command started
        // from, and `label` the step's new name.
        // @return types.UndoAdjust
        fn undo_adjust(lua, sh, (before, label) => (Option<u64>, Option<String>)) {
            to_lua(lua, &sh.session.borrow_mut().undo_adjust(before, label))
        }
        // Put the step back as it was, when the command run again failed.
        // @return nil
        fn undo_adjust_cancel(_, sh, () => ()) {
            sh.session.borrow_mut().undo_adjust_cancel();
            Ok(())
        }
        // The edits of this turn join undo state `id`, the current one, and do
        // not make a step of their own. For example, a snippet changed its choice.
        // @return boolean
        fn undo_join(_, sh, id => u64) { Ok(sh.session.borrow_mut().undo_join(id)) }
        // @return nil
        fn undo_keys(_, sh, text => String) {
            sh.session.borrow_mut().undo_keys(text);
            Ok(())
        }
        // @return string
        fn checkpoint_dir(_, sh, () => ()) {
            Ok(sh.session.borrow().checkpoint_dir().map(|p| p.to_string_lossy().into_owned()))
        }
        // @return types.Checkpoint
        fn checkpoint_write(lua, sh, (name, id) => (String, Option<u64>)) {
            to_lua(lua, &sh.session.borrow_mut().checkpoint_write(&name, id).lua()?)
        }
        // @return {types.Checkpoint}
        fn checkpoint_list(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().checkpoint_list()) }
        // @return integer
        fn checkpoint_restore(_, sh, file => String) {
            sh.session.borrow_mut().checkpoint_restore(&file).lua()
        }
        // @return nil
        fn checkpoint_delete(_, sh, file => String) {
            sh.session.borrow_mut().checkpoint_delete(&file).lua()
        }

    }
    Ok(())
}
