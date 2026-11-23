//! One note at a time: `paw.api.clip_note_*`.
//!
//! A clip's notes are kept in the order they start, lower pitches first
//! within a chord, and a note is named by its place in that order. These
//! calls change one note, or a few, without the whole list crossing into Lua
//! and back, which is what an editor does most. `paw.api.notes_set` changes
//! many notes of many clips, given as columns of values (a command over a
//! range, such as `:%quantize`).
//!
//! Indices here count from 0; `paw.api` shows them counting from 1.

use std::cmp::Ordering;
use std::collections::HashMap;

use anyhow::{Context, Result, bail};
use serde::Deserialize;
use serde_json::{Map, Value};

use super::{Session, check_notes};
use crate::model::{ClipContent, Id, Note, NoteAttr, Notes, Project, de_attr};

/// What to change about a note. Fields left out stay as they are.
#[derive(Clone, Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct NoteChange {
    /// Which note, in [`NotesEdit::set`].
    pub index: Option<usize>,
    pub start: Option<f64>,
    pub length: Option<f64>,
    pub pitch: Option<u8>,
    pub velocity: Option<u8>,
    pub meta: Option<Map<String, Value>>,
    /// A new attribute, or none (`false`) to take it away.
    #[serde(deserialize_with = "some_attr")]
    pub attr: Option<Option<NoteAttr>>,
}

/// An attribute given in a change, as opposed to one left out.
fn some_attr<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Option<Option<NoteAttr>>, D::Error> {
    de_attr(d).map(Some)
}

impl NoteChange {
    fn apply(&self, note: &mut Note) {
        if let Some(start) = self.start {
            note.start = start;
        }
        if let Some(length) = self.length {
            note.length = length;
        }
        if let Some(pitch) = self.pitch {
            note.pitch = pitch;
        }
        if let Some(velocity) = self.velocity {
            note.velocity = velocity;
        }
        if let Some(meta) = &self.meta {
            note.meta = meta.clone();
        }
        if let Some(attr) = self.attr {
            note.attr = attr;
        }
    }
}

/// Several changes to one clip's notes, made together. Every index is a
/// note's place before any of them is made.
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct NotesEdit {
    pub set: Vec<NoteChange>,
    pub remove: Vec<usize>,
    pub add: Vec<Note>,
}

/// New values for many notes of many clips, as columns
/// (`paw.api.notes_set`): entry `i` of each column is about the note at
/// `place[i]` of clip `clip[i]`. A column that is not there keeps that
/// field of each note. Each place is the note's place before the change.
///
/// Columns and not a list of changes, so that an edit of thousands of
/// notes (`:%quantize`) crosses from Lua as a few lists of numbers, with
/// no table for each note.
#[derive(Debug, Default)]
pub struct NoteColumns {
    pub clip: Vec<Id>,
    pub place: Vec<usize>,
    pub start: Option<Vec<f64>>,
    pub length: Option<Vec<f64>>,
    pub pitch: Option<Vec<u8>>,
    pub velocity: Option<Vec<u8>>,
}

/// The notes of one clip that a [`NoteColumns`] changes: each with its
/// place, as it is after the change.
struct ClipChanges {
    id: Id,
    changed: Vec<(usize, Note)>,
}

impl NoteColumns {
    /// Each column has an entry for each entry of `clip`.
    fn check_lengths(&self) -> Result<()> {
        let count = self.clip.len();
        let lengths = [
            ("place", Some(self.place.len())),
            ("start", self.start.as_ref().map(Vec::len)),
            ("length", self.length.as_ref().map(Vec::len)),
            ("pitch", self.pitch.as_ref().map(Vec::len)),
            ("velocity", self.velocity.as_ref().map(Vec::len)),
        ];
        for (name, length) in lengths {
            if let Some(length) = length
                && length != count
            {
                bail!("`{name}` has {length} entries, and `clip` has {count}");
            }
        }
        Ok(())
    }

    /// True when the change can move a note to another place in its clip.
    fn moves(&self) -> bool {
        self.start.is_some() || self.pitch.is_some()
    }

    /// Give `note` the values of entry `entry`.
    fn apply(&self, entry: usize, note: &mut Note) {
        if let Some(start) = &self.start {
            note.start = start[entry];
        }
        if let Some(length) = &self.length {
            note.length = length[entry];
        }
        if let Some(pitch) = &self.pitch {
            note.pitch = pitch[entry];
        }
        if let Some(velocity) = &self.velocity {
            note.velocity = velocity[entry];
        }
    }

    /// The changed notes of each clip, in the order the clips first come,
    /// each list in the order of the places. It checks everything and
    /// changes nothing: a wrong entry stops the change before it starts.
    fn changes(&self, project: &Project) -> Result<Vec<ClipChanges>> {
        self.check_lengths()?;
        // Each clip once, with its notes: a look for a clip walks the tracks.
        let mut clips: Vec<(ClipChanges, &Notes)> = Vec::new();
        let mut slot_of: HashMap<Id, usize> = HashMap::new();
        for (entry, (&id, &place)) in self.clip.iter().zip(&self.place).enumerate() {
            let slot = match slot_of.get(&id) {
                Some(&slot) => slot,
                None => {
                    let found = ClipChanges { id, changed: Vec::new() };
                    clips.push((found, notes_of(project, id)?));
                    slot_of.insert(id, clips.len() - 1);
                    clips.len() - 1
                }
            };
            let (found, notes) = &mut clips[slot];
            let mut note = notes
                .get(place)
                .ok_or_else(|| no_note(id, place, notes.len()))?
                .clone();
            self.apply(entry, &mut note);
            check_notes(std::slice::from_ref(&note))
                .with_context(|| format!("note {} of clip {id}", place + 1))?;
            found.changed.push((place, note));
        }
        clips
            .into_iter()
            .map(|(mut found, _)| {
                // Two entries for one note would leave the result to their order.
                found.changed.sort_by_key(|(place, _)| *place);
                if let Some(pair) = found.changed.windows(2).find(|pair| pair[0].0 == pair[1].0) {
                    bail!("note {} of clip {} is in the columns twice", pair[0].0 + 1, found.id);
                }
                Ok(found)
            })
            .collect()
    }
}

/// Write the changes that [`NoteColumns::changes`] found, and keep each
/// clip's notes in their order when a note can have moved.
fn write_changes(project: &mut Project, changes: Vec<ClipChanges>, moves: bool) -> Result<()> {
    for ClipChanges { id, changed } in changes {
        let notes = notes_mut(project, id)?;
        for (place, note) in changed {
            notes[place] = note;
        }
        if moves {
            // Stable, so notes that did not move keep their order.
            notes.sort_by(order);
        }
    }
    Ok(())
}

/// Which of a clip's notes to return. Bounds left out are open.
#[derive(Debug, Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct NoteRange {
    /// Beats from the start of the clip: notes sounding anywhere in `from..to`.
    pub from: Option<f64>,
    pub to: Option<f64>,
    /// Pitches, both included.
    pub low: Option<u8>,
    pub high: Option<u8>,
}

/// The order notes are kept in.
fn order(a: &Note, b: &Note) -> Ordering {
    a.start.total_cmp(&b.start).then(a.pitch.cmp(&b.pitch))
}

/// A cursor on `beat` is on a note from its start up to, not including, its end.
const EPS: f64 = 1e-9;

fn notes_of(project: &Project, id: Id) -> Result<&Notes> {
    match &project
        .clip(id)
        .with_context(|| format!("no clip {id}"))?
        .content
    {
        ClipContent::Midi { notes, .. } => Ok(notes),
        ClipContent::Audio { .. } => bail!("clip {id} is an audio clip"),
        other => bail!("clip {id} is a clip of the kind `{}`", other.kind()),
    }
}

fn notes_mut(project: &mut Project, id: Id) -> Result<&mut Notes> {
    match &mut project
        .clip_mut(id)
        .with_context(|| format!("no clip {id}"))?
        .content
    {
        ClipContent::Midi { notes, .. } => Ok(notes),
        ClipContent::Audio { .. } => bail!("clip {id} is an audio clip"),
        other => bail!("clip {id} is a clip of the kind `{}`", other.kind()),
    }
}

fn no_note(id: Id, index: usize, count: usize) -> anyhow::Error {
    anyhow::anyhow!("clip {id} has no note {}: it has {count} notes", index + 1)
}

/// Put a note where it belongs, after any that start with it on its pitch.
fn insert(notes: &mut Notes, note: Note) -> usize {
    let at = notes.partition_point(|n| order(n, &note) != Ordering::Greater);
    notes.insert(at, note);
    at
}

impl Session {
    /// Add one note, and say where in the clip's notes it went.
    pub fn clip_note_add(&mut self, id: Id, mut note: Note) -> Result<usize> {
        check_notes(std::slice::from_ref(&note))?;
        // Named here, as `name_notes` would name it (the next free id), with
        // one look at the ids and nothing made: adding notes one by one to a
        // clip of many thousands stays quick.
        let notes = notes_of(&self.doc.project, id)?;
        let (mut last, mut taken) = (0, false);
        for other in notes {
            last = last.max(other.id);
            taken |= other.id == note.id;
        }
        if note.id == 0 || taken {
            note.id = last + 1;
        }
        self.doc.edit_named(|p| Ok(insert(notes_mut(p, id)?, note)))
    }

    /// Change one note, and say where it is afterwards: a note that starts
    /// at another time, or moves to another pitch, changes place.
    pub fn clip_note_set(&mut self, id: Id, index: usize, change: &NoteChange) -> Result<usize> {
        let notes = notes_of(&self.doc.project, id)?;
        let before = notes
            .get(index)
            .ok_or_else(|| no_note(id, index, notes.len()))?;
        let mut note = before.clone();
        change.apply(&mut note);
        let stays = order(before, &note) == Ordering::Equal;
        check_notes(std::slice::from_ref(&note))?;
        self.doc.edit_named(|p| {
            let notes = notes_mut(p, id)?;
            if stays {
                notes[index] = note;
                Ok(index)
            } else {
                notes.remove(index);
                Ok(insert(notes, note))
            }
        })
    }

    pub fn clip_note_remove(&mut self, id: Id, index: usize) -> Result<()> {
        let count = notes_of(&self.doc.project, id)?.len();
        if index >= count {
            return Err(no_note(id, index, count));
        }
        self.doc.edit_named(|p| {
            notes_mut(p, id)?.remove(index);
            Ok(())
        })
    }

    /// Change, remove and add several notes as one edit.
    pub fn clip_notes_edit(&mut self, id: Id, edit: NotesEdit) -> Result<()> {
        let notes = notes_of(&self.doc.project, id)?;
        let count = notes.len();
        let mut changed = Vec::with_capacity(edit.set.len());
        for change in &edit.set {
            let index = change
                .index
                .context("every entry of `set` needs the `index` of its note")?;
            let mut note = notes
                .get(index)
                .ok_or_else(|| no_note(id, index, count))?
                .clone();
            change.apply(&mut note);
            changed.push((index, note));
        }
        if let Some(&index) = edit.remove.iter().find(|i| **i >= count) {
            return Err(no_note(id, index, count));
        }
        check_notes(&edit.add)?;
        for (_, note) in &changed {
            check_notes(std::slice::from_ref(note))?;
        }
        self.doc.edit(|p| {
            let notes = notes_mut(p, id)?;
            for (index, note) in changed {
                notes[index] = note;
            }
            if !edit.remove.is_empty() {
                let mut gone = vec![false; notes.len()];
                edit.remove.iter().for_each(|i| gone[*i] = true);
                let mut at = 0;
                notes.retain(|_| {
                    at += 1;
                    !gone[at - 1]
                });
            }
            notes.extend(edit.add);
            // Stable, so notes that did not move keep their order.
            notes.sort_by(order);
            Ok(())
        })
    }

    /// Change many notes of many clips as one edit (`paw.api.notes_set`).
    /// A wrong entry changes nothing.
    pub fn notes_set(&mut self, columns: &NoteColumns) -> Result<()> {
        let changes = columns.changes(&self.doc.project)?;
        let moves = columns.moves();
        // No note is added, and each changed note keeps its id.
        self.doc.edit_named(|p| write_changes(p, changes, moves))
    }

    /// The first note on `pitch` sounding at `beat`, and its place.
    pub fn clip_note_at(&self, id: Id, pitch: u8, beat: f64) -> Result<Option<(usize, &Note)>> {
        Ok(notes_of(&self.doc.project, id)?
            .iter()
            .enumerate()
            // Notes are in the order they start: nothing later can be under the beat.
            .take_while(|(_, n)| n.start - EPS <= beat)
            .find(|(_, n)| n.pitch == pitch && beat < n.start + n.length - EPS))
    }

    /// The notes within a range, each with its place.
    pub fn clip_notes_in(&self, id: Id, range: &NoteRange) -> Result<Vec<(usize, &Note)>> {
        let (low, high) = (range.low.unwrap_or(0), range.high.unwrap_or(u8::MAX));
        let from = range.from.unwrap_or(f64::NEG_INFINITY);
        let to = range.to.unwrap_or(f64::INFINITY);
        Ok(notes_of(&self.doc.project, id)?
            .iter()
            .enumerate()
            .take_while(|(_, n)| n.start < to)
            .filter(|(_, n)| n.start + n.length > from && n.pitch >= low && n.pitch <= high)
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use serde_json::json;

    use super::*;
    use crate::model::{Clip, Track};

    /// A project with clip 3: C4, D4 and E4 a beat apart, named 1 to 3.
    fn project() -> Project {
        let clip: Clip = serde_json::from_value(json!({
            "id": 3, "name": "verse", "start": 0.0, "length": 8.0, "muted": false,
            "content": { "kind": "midi", "notes": [
                { "start": 0.0, "length": 1.0, "pitch": 60, "velocity": 100, "id": 1 },
                { "start": 1.0, "length": 1.0, "pitch": 62, "velocity": 100, "id": 2 },
                { "start": 2.0, "length": 1.0, "pitch": 64, "velocity": 100, "id": 3 },
            ] },
        }))
        .unwrap();
        let mut track = Track::new(1);
        track.clips.push(Arc::new(clip));
        let mut project = Project::default();
        project.tracks.push(Arc::new(track));
        project
    }

    /// Each note of clip 3 as (id, start, pitch, velocity).
    fn notes(project: &Project) -> Vec<(u64, f64, u8, u8)> {
        notes_of(project, 3)
            .unwrap()
            .iter()
            .map(|n| (n.id, n.start, n.pitch, n.velocity))
            .collect()
    }

    /// What `Session::notes_set` does to the project, with no session.
    fn set(project: &mut Project, columns: &NoteColumns) -> Result<()> {
        let changes = columns.changes(project)?;
        write_changes(project, changes, columns.moves())
    }

    #[test]
    fn columns_move_notes_and_the_clip_keeps_them_in_order() {
        let mut project = project();
        let columns = NoteColumns {
            clip: vec![3, 3],
            place: vec![2, 0],
            start: Some(vec![0.5, 2.5]),
            ..NoteColumns::default()
        };
        set(&mut project, &columns).unwrap();
        assert_eq!(
            notes(&project),
            [(3, 0.5, 64, 100), (2, 1.0, 62, 100), (1, 2.5, 60, 100)],
            "the moved notes, in the order of their starts, with their ids"
        );
    }

    #[test]
    fn a_column_that_is_not_there_keeps_that_value() {
        let mut project = project();
        let columns = NoteColumns {
            clip: vec![3],
            place: vec![1],
            velocity: Some(vec![40]),
            ..NoteColumns::default()
        };
        set(&mut project, &columns).unwrap();
        assert_eq!(notes(&project), [(1, 0.0, 60, 100), (2, 1.0, 62, 40), (3, 2.0, 64, 100)]);
    }

    #[test]
    fn a_wrong_entry_gives_an_error_and_changes_nothing() {
        let columns = |clip: Vec<Id>, place: Vec<usize>, length: Vec<f64>| NoteColumns {
            clip,
            place,
            length: Some(length),
            ..NoteColumns::default()
        };
        let cases = [
            (columns(vec![3], vec![0], vec![]), "`length` has 0 entries, and `clip` has 1"),
            (columns(vec![3], vec![5], vec![2.0]), "clip 3 has no note 6: it has 3 notes"),
            (columns(vec![9], vec![0], vec![2.0]), "no clip 9"),
            (columns(vec![3, 3], vec![1, 1], vec![2.0, 3.0]), "note 2 of clip 3 is in the columns twice"),
            (
                columns(vec![3, 3], vec![0, 1], vec![2.0, 0.0]),
                "note 2 of clip 3: a note needs a finite start and a length above 0, not start 1 length 0",
            ),
        ];
        let before = notes(&project());
        for (columns, want) in cases {
            let mut project = project();
            let Err(error) = set(&mut project, &columns) else { panic!("{columns:?} was taken") };
            assert_eq!(format!("{error:#}"), want, "{columns:?}");
            assert_eq!(notes(&project), before, "{columns:?} changed the notes");
        }
    }
}
