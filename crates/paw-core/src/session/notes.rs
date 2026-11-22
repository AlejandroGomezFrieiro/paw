//! One note at a time: `paw.api.clip_note_*`.
//!
//! A clip's notes are kept in the order they start, lower pitches first
//! within a chord, and a note is named by its place in that order. These
//! calls change one note, or a few, without the whole list crossing into Lua
//! and back, which is what an editor does most.
//!
//! Indices here count from 0; `paw.api` shows them counting from 1.

use std::cmp::Ordering;

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
        let notes = notes_of(&self.project, id)?;
        let (mut last, mut taken) = (0, false);
        for other in notes {
            last = last.max(other.id);
            taken |= other.id == note.id;
        }
        if note.id == 0 || taken {
            note.id = last + 1;
        }
        self.edit_named(|p| Ok(insert(notes_mut(p, id)?, note)))
    }

    /// Change one note, and say where it is afterwards: a note that starts
    /// at another time, or moves to another pitch, changes place.
    pub fn clip_note_set(&mut self, id: Id, index: usize, change: &NoteChange) -> Result<usize> {
        let notes = notes_of(&self.project, id)?;
        let before = notes
            .get(index)
            .ok_or_else(|| no_note(id, index, notes.len()))?;
        let mut note = before.clone();
        change.apply(&mut note);
        let stays = order(before, &note) == Ordering::Equal;
        check_notes(std::slice::from_ref(&note))?;
        self.edit_named(|p| {
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
        let count = notes_of(&self.project, id)?.len();
        if index >= count {
            return Err(no_note(id, index, count));
        }
        self.edit_named(|p| {
            notes_mut(p, id)?.remove(index);
            Ok(())
        })
    }

    /// Change, remove and add several notes as one edit.
    pub fn clip_notes_edit(&mut self, id: Id, edit: NotesEdit) -> Result<()> {
        let notes = notes_of(&self.project, id)?;
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
        self.edit(|p| {
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

    /// The first note on `pitch` sounding at `beat`, and its place.
    pub fn clip_note_at(&self, id: Id, pitch: u8, beat: f64) -> Result<Option<(usize, &Note)>> {
        Ok(notes_of(&self.project, id)?
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
        Ok(notes_of(&self.project, id)?
            .iter()
            .enumerate()
            .take_while(|(_, n)| n.start < to)
            .filter(|(_, n)| n.start + n.length > from && n.pitch >= low && n.pitch <= high)
            .collect())
    }
}
