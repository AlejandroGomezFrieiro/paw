//! `paw.api`: clips, their media, notes and controllers, and cues.

use std::rc::Rc;

use mlua::{Lua, LuaSerdeExt, Table, Value as LuaValue};

use crate::model::{ClipContent, Control, Id, Note, NoteAttr, Velocity};
use crate::session::notes::{NoteChange, NoteColumns, NoteRange, NotesEdit};

use super::{LuaResult, Shared, from_lua, kind_data, options, patch, to_lua};

/// Notes as Lua tables: what `to_lua` makes of them, built directly. Views
/// ask for a clip's notes every time they draw, so this is on a hot path.
fn notes_to_lua(lua: &Lua, notes: &crate::model::Notes) -> mlua::Result<LuaValue> {
    let list = lua.create_table_with_capacity(notes.len(), 0)?;
    list.set_metatable(Some(lua.array_metatable()))?;
    for (i, n) in notes.iter().enumerate() {
        list.raw_seti(i + 1, note_to_lua(lua, n)?)?;
    }
    Ok(LuaValue::Table(list))
}

fn note_to_lua(lua: &Lua, n: &Note) -> mlua::Result<Table> {
    let note = lua.create_table_with_capacity(0, 4)?;
    note.raw_set("start", n.start)?;
    note.raw_set("length", n.length)?;
    note.raw_set("pitch", n.pitch)?;
    note.raw_set("velocity", n.velocity.0)?;
    if n.id != 0 {
        note.raw_set("id", n.id)?;
    }
    // What extensions keep with a note, such as its lyric.
    if !n.meta.is_empty() {
        note.raw_set("meta", to_lua(lua, &n.meta)?)?;
    }
    if let Some(attr) = n.attr {
        note.raw_set("attr", attr_to_lua(lua, attr)?)?;
    }
    Ok(note)
}

/// A note's attribute as Lua has it: `{ type = 17, data = 40960 }`.
fn attr_to_lua(lua: &Lua, attr: NoteAttr) -> mlua::Result<Table> {
    let table = lua.create_table_with_capacity(0, 2)?;
    table.raw_set("type", attr.kind)?;
    table.raw_set("data", attr.data)?;
    Ok(table)
}

/// A note's place in its clip as Lua counts it, from 1, turned into ours.
fn note_index(index: usize) -> mlua::Result<usize> {
    index
        .checked_sub(1)
        .ok_or_else(|| mlua::Error::runtime("notes are counted from 1"))
}

/// The columns of `paw.api.notes_set`, read straight from their lists: no
/// table for each note. A key that is not a column is an error, as
/// `deny_unknown_fields` gives for the other note calls.
fn note_columns(table: &Table) -> mlua::Result<NoteColumns> {
    const KEYS: [&str; 6] = ["clip", "place", "start", "length", "pitch", "velocity"];
    for pair in table.pairs::<LuaValue, LuaValue>() {
        let (key, _) = pair?;
        let known = matches!(&key, LuaValue::String(name) if name.to_str().is_ok_and(|name| KEYS.contains(&&*name)));
        if !known {
            return Err(mlua::Error::runtime(format!(
                "the columns are {}, not `{}`",
                KEYS.join(", "),
                key.to_string()?
            )));
        }
    }
    let needed = |name: &str| mlua::Error::runtime(format!("the columns need `{name}`"));
    let place: Vec<usize> = table.raw_get::<Option<_>>("place")?.ok_or_else(|| needed("place"))?;
    Ok(NoteColumns {
        clip: table.raw_get::<Option<_>>("clip")?.ok_or_else(|| needed("clip"))?,
        place: place.into_iter().map(note_index).collect::<mlua::Result<_>>()?,
        start: table.raw_get("start")?,
        length: table.raw_get("length")?,
        pitch: table.raw_get("pitch")?,
        velocity: table.raw_get("velocity")?,
    })
}

/// Notes from Lua. Well-formed lists of note tables are read directly;
/// anything else goes through serde, so that what is accepted and the errors
/// for what is not stay exactly those of `from_lua`.
fn notes_from_lua(lua: &Lua, value: LuaValue) -> mlua::Result<Vec<Note>> {
    fn direct(value: &LuaValue) -> Option<Vec<Note>> {
        let LuaValue::Table(list) = value else {
            return None;
        };
        let len = list.raw_len();
        if list.pairs::<LuaValue, LuaValue>().count() != len {
            return None;
        }
        let int = |v: LuaValue| match v {
            LuaValue::Integer(i) => u8::try_from(i).ok(),
            _ => None,
        };
        let num = |v: LuaValue| match v {
            LuaValue::Integer(i) => Some(i as f64),
            LuaValue::Number(n) => Some(n),
            _ => None,
        };
        let mut notes = Vec::with_capacity(len);
        for i in 1..=len {
            let LuaValue::Table(note) = list.raw_get::<LuaValue>(i).ok()? else {
                return None;
            };
            let velocity = match note.raw_get::<LuaValue>("velocity").ok()? {
                LuaValue::Nil => 100,
                v => int(v)?,
            };
            // A note that carries data of an extension's, or an
            // attribute, goes the long way.
            if !note.raw_get::<LuaValue>("meta").ok()?.is_nil()
                || !note.raw_get::<LuaValue>("attr").ok()?.is_nil()
            {
                return None;
            }
            notes.push(Note {
                start: num(note.raw_get("start").ok()?)?,
                length: num(note.raw_get("length").ok()?)?,
                pitch: int(note.raw_get("pitch").ok()?)?,
                velocity: Velocity(velocity),
                meta: Default::default(),
                id: match note.raw_get::<LuaValue>("id").ok()? {
                    LuaValue::Nil => 0,
                    LuaValue::Integer(i) => u64::try_from(i).ok()?,
                    LuaValue::Number(n) if n >= 0.0 && n.fract() == 0.0 => n as u64,
                    _ => return None,
                },
                attr: None,
            });
        }
        Some(notes)
    }
    match direct(&value) {
        Some(notes) => Ok(notes),
        None => from_lua(lua, value),
    }
}

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- clips ---
        // The clips of a part, in timeline order. With `from` and `to`
        // (beats), only those that overlap that stretch: a view that shows
        // part of the song asks for what it shows.
        // @return {types.Clip}
        fn clip_list(lua, sh, (part, from, to) => (Id, Option<f64>, Option<f64>)) {
            let span = from.zip(to);
            to_lua(lua, &sh.session.borrow().clip_list_in(part, span).lua()?)
        }
        // @return types.Clip
        fn clip_get(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().clip_view(id).lua()?) }
        // Where new recordings and bounces go: `media` beside the project
        // file, or the user's data directory before the project has one.
        // @return string
        fn media_dir(_, sh, () => ()) {
            Ok(sh.session.borrow().media_dir().to_string_lossy().into_owned())
        }
        // The sound files of the project (session/media.rs): the files that paw
        // cannot find, links to new paths, and copies into the folder of the project.
        // @return {types.MediaFile}
        fn media_list(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().media_list()) }
        // Long files are played from the disk: past how many megabytes of
        // decoded sound (0: never), and how many gigabytes of it are kept
        // between runs. With no arguments, what is set: megabytes, directory.
        // @return number, string
        fn media_store(_, sh, (megabytes, keep) => (Option<f64>, Option<f64>)) {
            let mut session = sh.session.borrow_mut();
            if let Some(megabytes) = megabytes {
                let dir = crate::peaks::media_dir(&session.dirs);
                session.set_media_store(Some(dir), megabytes);
                if let (Some(keep), Some((dir, megabytes))) = (keep, session.media_store()) {
                    // Tidied apart: a big cache takes a while to look through.
                    let store = paw_engine::DiskStore { dir, limit: (megabytes * 1_048_576.0) as u64 };
                    std::thread::spawn(move || store.tidy((keep.max(0.0) * 1_073_741_824.0) as u64));
                }
                let pins = session.bake_pins();
                if let (Some(keep), Some(bakes)) = (keep, session.bakes_mut()) {
                    bakes.limit = (keep.max(0.0) * 1_073_741_824.0) as u64;
                    let bakes = bakes.clone();
                    std::thread::spawn(move || {
                        bakes.tidy(&pins);
                        // Where overviews were kept before the bake cache.
                        let _ = std::fs::remove_dir_all(bakes.root().with_file_name("peaks"));
                    });
                }
            }
            Ok(match session.media_store() {
                Some((dir, megabytes)) => (megabytes, Some(dir.to_string_lossy().into_owned())),
                None => (0.0, None),
            })
        }
        // @return {string}
        fn media_missing(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().media_missing()) }
        // A file with other bytes than `from` had is refused, unless `anyway`.
        // @return types.MediaFound
        fn media_relink(lua, sh, (from, to, anyway) => (String, String, Option<bool>)) {
            let mut session = sh.session.borrow_mut();
            let result = session.media_relink(from.as_ref(), to.as_ref(), anyway.unwrap_or(false));
            to_lua(lua, &result.lua()?)
        }
        // @return types.MediaFound
        fn media_search(lua, sh, dir => String) {
            to_lua(lua, &sh.session.borrow_mut().media_search(dir.as_ref()).lua()?)
        }
        // @return types.MediaCollected
        fn media_collect(lua, sh, () => ()) {
            to_lua(lua, &sh.session.borrow_mut().media_collect().lua()?)
        }
        // @return string
        fn media_adopt(_, sh, file => String) {
            let path = sh.session.borrow_mut().media_adopt(file.as_ref()).lua()?;
            Ok(path.to_string_lossy().into_owned())
        }
        // Audio clip operations that leave the source file alone (session/clipops.rs).
        // @return types.ClipEdits
        fn clip_reverse(lua, sh, id => Id) {
            to_lua(lua, &sh.session.borrow_mut().clip_reverse(id).lua()?)
        }
        // Add an edit to an audio clip's edit list (`edits.rs`): `{ kind =
        // "gain", from, to, db }` or `{ kind = "pencil", at, channel, values }`,
        // in seconds from where the clip starts in its sound. Returns how many
        // edits it has.
        // @param edit types.AudioEdit
        // @return integer
        fn clip_edit_add(lua, sh, (id, edit) => (Id, LuaValue)) {
            let edit: crate::edits::AudioEdit = from_lua(lua, edit)?;
            sh.session.borrow_mut().clip_edit_add(id, edit).lua()
        }
        // Take away an audio clip's edit list. Returns how many edits it had.
        // @return integer
        fn clip_edits_clear(_, sh, id => Id) {
            sh.session.borrow_mut().clip_edits_clear(id).lua()
        }
        // An audio clip's edit list, as `clip_edit_add` takes its edits (with
        // times in seconds of its sound).
        // @return {types.AudioEdit}
        fn clip_edits(lua, sh, id => Id) {
            let session = sh.session.borrow();
            let clip = session.doc.project.clip(id).ok_or_else(|| mlua::Error::runtime(format!("no clip {id}")))?;
            let edits = match &clip.content {
                ClipContent::Audio { edits, .. } => edits.clone(),
                _ => Vec::new(),
            };
            to_lua(lua, &edits)
        }
        // @return number
        fn clip_normalize(_, sh, (id, level) => (Id, Option<f64>)) {
            sh.session.borrow_mut().clip_normalize(id, level.unwrap_or(0.0)).lua()
        }
        // @return types.ClipGlued
        fn clip_glue(lua, sh, ids => Vec<Id>) {
            to_lua(lua, &sh.session.borrow_mut().clip_glue(&ids).lua()?)
        }
        // Warp markers of an audio clip (`session/stretching.rs`), counted from 1.
        // @return integer
        fn clip_warp_add(_, sh, (id, beat) => (Id, f64)) {
            Ok(sh.session.borrow_mut().warp_add(id, beat).lua()? + 1)
        }
        // @return integer
        fn clip_warp_move(_, sh, (id, index, beat) => (Id, usize, f64)) {
            let index = index.checked_sub(1).ok_or_else(|| mlua::Error::runtime("warp markers count from 1"))?;
            Ok(sh.session.borrow_mut().warp_move(id, index, beat).lua()? + 1)
        }
        // @return nil
        fn clip_warp_remove(_, sh, (id, index) => (Id, usize)) {
            let index = index.checked_sub(1).ok_or_else(|| mlua::Error::runtime("warp markers count from 1"))?;
            sh.session.borrow_mut().warp_remove(id, index).lua()
        }
        // Beats of sound left in an audio clip's file from where the clip starts in it.
        // @return number
        fn clip_source_length(_, sh, id => Id) { sh.session.borrow_mut().clip_source_length(id).lua() }
        // A clip of a defined kind: `kind` is its name, with `data` and `length`, and
        // `version`, `timeline`, `offset`, `media`, `sound` and `signals` as `clip_custom` gives them.
        // @param opts? types.ClipOptions
        // @return integer
        fn clip_add(lua, sh, (part, opts) => (Id, LuaValue)) {
            let (opts, data) = kind_data::split(lua, opts)?;
            let mut opts: crate::session::ClipOpts = options(lua, opts)?;
            opts.data = data.or(opts.data);
            sh.session.borrow_mut().clip_add(part, opts).lua()
        }
        // The kinds of clip that extensions defined, by name (sorted).
        // @return {string}
        fn clip_kinds(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().doc.clip_kinds()) }
        // Let `clip_add` make clips of the kind `name`: a lowercase word that
        // is not `midi`, `audio` or another built-in. `paw.clip_kinds.define` calls it.
        // @return nil
        fn clip_kind_define(_, sh, name => String) { sh.session.borrow_mut().doc.clip_kind_define(&name).lua() }
        // Stop making clips of the kind `name`. Clips of it that the project has stay.
        // @return nil
        fn clip_kind_remove(_, sh, name => String) { sh.session.borrow_mut().doc.clip_kind_remove(&name).lua() }
        // The content of a clip of a defined kind, as the project saves it:
        // `{ type, version?, timeline?, offset?, data, media?, sound?, signals? }`.
        // `data` is `{ json = value }`, a plain value (tables, strings, numbers,
        // booleans; a JSON null reads as nil), or `{ text = { ext, text } }`,
        // UTF-8 text in the kind's own format.
        // @return types.CustomContent
        fn clip_custom(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().doc.clip_custom(id).lua()?) }
        // Replace what a custom clip's kind compiled, as one undo step: `data`
        // (required), `media`, `sound` (a MIDI or audio content) and `signals`
        // are all replaced (absent: none); `version`, `timeline` and `offset`
        // stay as they are when absent. The data and the signals' bodies are
        // plain values: a function, `userdata`, `cdata`, a table that holds itself,
        // NaN, an infinite number or a string that is not UTF-8 is refused with
        // where it is (`.frames[3]: a function is not data`), and so is data
        // over 1 MB. Binary or big data goes in a media file.
        // @param set types.CustomSet
        // @return nil
        fn clip_set_custom(lua, sh, (id, set) => (Id, LuaValue)) {
            let (set, data) = kind_data::split(lua, set)?;
            let mut set: crate::session::CustomSet = from_lua(lua, set)?;
            set.data = data.or(set.data);
            sh.session.borrow_mut().doc.clip_set_custom(id, set).lua()
        }
        // @return nil
        fn clip_remove(_, sh, id => Id) { sh.session.borrow_mut().doc.clip_remove(id).lua() }
        // Put a linked copy of a MIDI clip right after it, and return the
        // id of the copy. The clips of a link share their notes and
        // controller moves: an edit of one changes all of them. A clip that
        // has no link yet starts one, named after the clip. `clip_get`
        // gives a linked clip's `link` and `link_count`.
        // @return integer
        fn clip_link(_, sh, id => Id) { sh.session.borrow_mut().doc.clip_link(id).lua() }
        // Take a clip out of its link. It keeps its notes, and edits of it no
        // longer change the other clips.
        // @return nil
        fn clip_unlink(_, sh, id => Id) { sh.session.borrow_mut().doc.clip_unlink(id).lua() }
        // Render the first `count` modifiers of a MIDI clip, or all of them
        // when `count` is nil, as one undo step. Their result becomes the
        // notes and controller moves of the clip, and they leave its
        // `modifiers`. It fails on a linked clip, and on a modifier in those
        // entries that can't run. Gives the number of modifiers that it
        // rendered, the number of notes of the clip after it, and the number
        // of notes that a modifier left out.
        // @return types.Rendered
        fn clip_render(lua, sh, (id, count) => (Id, Option<usize>)) {
            to_lua(lua, &sh.session.borrow_mut().doc.clip_render(id, count).lua()?)
        }

        // --- cues (session/cues.rs) ---
        // A clip goes off the timeline with `clip_add(part, { cue = true, ... })`:
        // it starts at 0, loops over its length, and plays only when cued.
        // You edit it as a usual clip; `clip_set(id, "part", other)` moves it.
        // @return {types.Clip}
        fn cue_list(lua, sh, part => Id) { to_lua(lua, &sh.session.borrow().cue_list(part).lua()?) }
        // Copy a clip, with its `meta`, off the timeline of a part. Returns the copy's id.
        // @return integer
        fn clip_to_cues(_, sh, (id, part) => (Id, Id)) {
            sh.session.borrow_mut().doc.clip_to_cues(id, part).lua()
        }
        // `{ { part =, clip = id }, { part =, stop = true },
        // { part =, timeline = true }, ... }`, each with `quantize` (`bar`
        // when not given: off 1/16 1/8 1/4 beat bar 2bars 4bars), `legato`
        // and `from`: all on their boundary, timed together by the engine.
        // @param list {types.Cue}
        // @return nil
        fn cue(lua, sh, list => LuaValue) {
            sh.session.borrow_mut().cue(from_lua(lua, list)?).lua()
        }
        // What each part plays and has in its queue, in the last report of the engine.
        // @return {types.CueState}
        fn cue_state(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().cue_state()) }
        // Change a clip: a table of the entries to change, as `clip_get`
        // gives them, or one `key` and its value. Only the key form clears
        // an entry (`nil`).
        // @type function(id: integer, patch: types.ClipChanges)
        // @type function(id: integer, key: string, value: nil)
        fn clip_set(lua, sh, (id, key, value) => (Id, LuaValue, LuaValue)) {
            let patch: crate::session::ClipPatch = patch(lua, key, value)?;
            sh.session.borrow_mut().clip_patch(id, patch).lua()
        }
        // `n` { min, max } pairs for all of the sound that an audio clip plays.
        // @return {types.Peak}
        fn clip_peaks(lua, sh, (id, n) => (Id, usize)) {
            to_lua(lua, &sh.session.borrow_mut().clip_peaks(id, n).lua()?)
        }
        // `n` { min, max, rms } for `seconds` of a sound file from `offset`
        // seconds: the sound that the other takes of a clip would play.
        // @return {types.Peak}
        fn media_peaks(lua, sh, (file, offset, seconds, n) => (String, f64, f64, usize)) {
            let peaks = sh.session.borrow_mut().media_peaks(file.as_ref(), offset, seconds, n).lua()?;
            to_lua(lua, &peaks)
        }
        // The notes of a MIDI clip, in the order of their start. With a range
        // `{ from, to, low, high }` (beats in the clip, pitches), only the notes
        // that sound in it. The second value is then the place of each note in
        // the whole list.
        // @param range? types.NoteRange
        // @return {types.Note}, {integer}
        fn clip_notes(lua, sh, (id, range) => (Id, LuaValue)) {
            let session = sh.session.borrow();
            if range.is_nil() {
                let notes = notes_to_lua(lua, session.doc.clip_notes(id).lua()?)?;
                return Ok(mlua::Variadic::from_iter([notes]));
            }
            let range: NoteRange = from_lua(lua, range)?;
            let found = session.doc.clip_notes_in(id, &range).lua()?;
            let notes = lua.create_table_with_capacity(found.len(), 0)?;
            notes.set_metatable(Some(lua.array_metatable()))?;
            let places = lua.create_table_with_capacity(found.len(), 0)?;
            for (i, (index, note)) in found.into_iter().enumerate() {
                notes.raw_seti(i + 1, note_to_lua(lua, note)?)?;
                places.raw_seti(i + 1, index + 1)?;
            }
            Ok(mlua::Variadic::from_iter([LuaValue::Table(notes), LuaValue::Table(places)]))
        }
        // The note on `pitch` that sounds at `beat`, and its place in the notes of
        // the clip. Nothing when there is no such note.
        // @return types.Note, integer
        fn clip_note_at(lua, sh, (id, pitch, beat) => (Id, u8, f64)) {
            Ok(match sh.session.borrow().doc.clip_note_at(id, pitch, beat).lua()? {
                Some((index, note)) => (Some(note_to_lua(lua, note)?), Some(index + 1)),
                None => (None, None),
            })
        }
        // One note at a time, by its place in the notes of the clip (from 1).
        // The functions that add and change a note return its new place,
        // because the notes stay in the order of their start.
        // @param note types.Note
        // @return integer
        fn clip_note_add(lua, sh, (id, note) => (Id, LuaValue)) {
            let note: Note = from_lua(lua, note)?;
            Ok(sh.session.borrow_mut().doc.clip_note_add(id, note).lua()? + 1)
        }
        // @param fields types.NoteChange
        // @return integer
        fn clip_note_set(lua, sh, (id, index, fields) => (Id, usize, LuaValue)) {
            let change: NoteChange = from_lua(lua, fields)?;
            let index = note_index(index)?;
            Ok(sh.session.borrow_mut().doc.clip_note_set(id, index, &change).lua()? + 1)
        }
        // @return nil
        fn clip_note_remove(_, sh, (id, index) => (Id, usize)) {
            sh.session.borrow_mut().doc.clip_note_remove(id, note_index(index)?).lua()
        }
        // Several at once, as one edit: `{ set = { { index = 3, start = 1 } },
        // remove = { 5, 6 }, add = { note, ... } }`. Every index is a note's
        // place before the call.
        // @param edit types.NotesEdit
        // @return nil
        fn clip_notes_edit(lua, sh, (id, edit) => (Id, LuaValue)) {
            let mut edit: NotesEdit = from_lua(lua, edit)?;
            for change in edit.set.iter_mut() {
                change.index = change.index.map(note_index).transpose()?;
            }
            for index in edit.remove.iter_mut() {
                *index = note_index(*index)?;
            }
            sh.session.borrow_mut().doc.clip_notes_edit(id, edit).lua()
        }
        // Many notes of many clips at once, as one edit, given as lists of the
        // same length: `{ clip = { 4, 4, 7 }, place = { 1, 2, 1 }, start = { 0, 0.5, 2 } }`.
        // Entry i is about the note at place `place[i]` of clip `clip[i]`,
        // its place before the call. A list left out of `start`, `length`,
        // `pitch` and `velocity` keeps that value of each note.
        // @param columns types.NoteColumns
        // @return nil
        fn notes_set(_, sh, columns => Table) {
            let columns = note_columns(&columns)?;
            sh.session.borrow_mut().doc.notes_set(&columns).lua()
        }
        // @param notes {types.Note}
        // @return nil
        fn clip_set_notes(lua, sh, (id, notes) => (Id, LuaValue)) {
            let notes = notes_from_lua(lua, notes)?;
            sh.session.borrow_mut().doc.clip_set_notes(id, notes, false).lua()
        }
        // @param notes {types.Note}
        // @return nil
        fn clip_add_notes(lua, sh, (id, notes) => (Id, LuaValue)) {
            let notes = notes_from_lua(lua, notes)?;
            sh.session.borrow_mut().doc.clip_set_notes(id, notes, true).lua()
        }
        // Controller, pitch wheel and pressure moves of a MIDI clip:
        // { start, type = "cc" | "bend" | "pressure", number, value }.
        // @return {types.Control}
        fn clip_controls(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().doc.clip_controls(id).lua()?) }
        // @param controls {types.Control}
        // @return nil
        fn clip_set_controls(lua, sh, (id, controls) => (Id, LuaValue)) {
            let controls: Vec<Control> = from_lua(lua, controls)?;
            sh.session.borrow_mut().doc.clip_set_controls(id, controls).lua()
        }

    }
    Ok(())
}
