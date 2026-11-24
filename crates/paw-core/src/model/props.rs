//! Property tests of undo: the states that the undo tree keeps share what
//! did not change with the project that the session edits (`Arc`, the runs
//! of `Notes` and `Clips`), and an edit must never reach them.

use std::sync::Arc;

use proptest::collection::vec;
use proptest::prelude::*;
use proptest::sample::Index;
use serde_json::{Map, json};

use super::{Clip, ClipContent, Note, Notes, Project, Part};
use crate::history::History;
use crate::props::config;

fn note() -> impl Strategy<Value = Note> {
    (0.0..16.0f64, 0.01..4.0f64, 0u8..=127, 1u8..=127).prop_map(|(start, length, pitch, velocity)| Note {
        start,
        length,
        pitch,
        velocity: crate::model::Velocity(velocity),
        meta: Map::new(),
        id: 0,
        attr: None,
    })
}

/// The notes of a clip: mostly a few, sometimes more than one run holds.
fn notes() -> impl Strategy<Value = Vec<Note>> {
    let many = (250usize..700).prop_map(|count| {
        (0..count)
            .map(|i| Note { start: i as f64 / 4.0, length: 0.25, pitch: (i % 128) as u8, velocity: crate::model::Velocity(100), meta: Map::new(), id: 0, attr: None })
            .collect()
    });
    prop_oneof![7 => vec(note(), 0..8), 1 => many]
}

fn midi_clip(id: u64, start: f64, notes: Vec<Note>) -> Clip {
    serde_json::from_value(json!({
        "id": id, "name": format!("clip {id}"), "start": start, "length": 4.0, "muted": false,
        "content": { "kind": "midi", "notes": notes },
    }))
    .expect("a MIDI clip")
}

/// A project of a few parts; a part can have more clips than one run of
/// `Clips` holds.
fn project() -> impl Strategy<Value = Project> {
    let part = vec((0.0..64.0f64, notes()), 0..36);
    vec(part, 1..4).prop_map(|parts| {
        let mut project = Project::default();
        let mut id = 1;
        for clips in parts {
            let mut part = Part::new(id);
            id += 1;
            for (start, notes) in clips {
                part.clips.push(Arc::new(midi_clip(id, start, notes)));
                id += 1;
            }
            project.parts.push(Arc::new(part));
        }
        project
    })
}

/// One change, as the session makes them: through `Arc::make_mut` and the
/// methods of `Notes` and `Clips`. An index picks a part, a clip or a
/// note among those there are.
#[derive(Clone, Debug)]
enum Edit {
    AddNote { part: Index, clip: Index, at: Index, note: Note },
    RemoveNote { part: Index, clip: Index, at: Index },
    ChangeNote { part: Index, clip: Index, at: Index, pitch: u8, start: f64 },
    KeepNotesBelow { part: Index, clip: Index, pitch: u8 },
    SortNotesByPitch { part: Index, clip: Index },
    /// The notes sent back whole with one changed and one taken out, as
    /// Lua sends them: `Notes::assign` keeps the runs that did not change.
    AssignNotes { part: Index, clip: Index, at: Index, pitch: u8 },
    AddClip { part: Index, at: Index, start: f64, notes: Vec<Note> },
    RemoveClip { part: Index, at: Index },
    MoveClip { part: Index, at: Index, start: f64 },
    RenamePart { part: Index, name: String },
    SetVolume { part: Index, volume: f64 },
    AddPart,
    RemovePart { part: Index },
    SetTempo { bpm: f64 },
}

fn edit() -> impl Strategy<Value = Edit> {
    let index = any::<Index>;
    prop_oneof![
        (index(), index(), index(), note()).prop_map(|(part, clip, at, note)| Edit::AddNote { part, clip, at, note }),
        (index(), index(), index()).prop_map(|(part, clip, at)| Edit::RemoveNote { part, clip, at }),
        (index(), index(), index(), 0u8..=127, 0.0..16.0f64)
            .prop_map(|(part, clip, at, pitch, start)| Edit::ChangeNote { part, clip, at, pitch, start }),
        (index(), index(), 0u8..=127).prop_map(|(part, clip, pitch)| Edit::KeepNotesBelow { part, clip, pitch }),
        (index(), index()).prop_map(|(part, clip)| Edit::SortNotesByPitch { part, clip }),
        (index(), index(), index(), 0u8..=127).prop_map(|(part, clip, at, pitch)| Edit::AssignNotes { part, clip, at, pitch }),
        (index(), index(), 0.0..64.0f64, vec(note(), 0..4))
            .prop_map(|(part, at, start, notes)| Edit::AddClip { part, at, start, notes }),
        (index(), index()).prop_map(|(part, at)| Edit::RemoveClip { part, at }),
        (index(), index(), 0.0..64.0f64).prop_map(|(part, at, start)| Edit::MoveClip { part, at, start }),
        (index(), "[a-z ]{0,8}").prop_map(|(part, name)| Edit::RenamePart { part, name }),
        (index(), -60.0..6.0f64).prop_map(|(part, volume)| Edit::SetVolume { part, volume }),
        Just(Edit::AddPart),
        index().prop_map(|part| Edit::RemovePart { part }),
        (20.0..300.0f64).prop_map(|bpm| Edit::SetTempo { bpm }),
    ]
}

/// The part that `part` picks, made the project's own to change.
fn part_mut<'a>(project: &'a mut Project, part: &Index) -> Option<&'a mut Part> {
    let parts = project.parts.len();
    (parts > 0).then(|| Arc::make_mut(&mut project.parts[part.index(parts)]))
}

/// The notes of the clip that `part` and `clip` pick.
fn notes_mut<'a>(project: &'a mut Project, part: &Index, clip: &Index) -> Option<&'a mut Notes> {
    let part = part_mut(project, part)?;
    let clips = part.clips.len();
    if clips == 0 {
        return None;
    }
    match &mut Arc::make_mut(&mut part.clips[clip.index(clips)]).content {
        ClipContent::Midi { notes, .. } => Some(notes),
        _ => None,
    }
}

/// Make the change; one that picks a note or a clip where there is none
/// changes nothing.
fn apply(project: &mut Project, edit: &Edit) {
    match edit {
        Edit::AddNote { part, clip, at, note } => {
            if let Some(notes) = notes_mut(project, part, clip) {
                notes.insert(at.index(notes.len() + 1), note.clone());
            }
        }
        Edit::RemoveNote { part, clip, at } => {
            if let Some(notes) = notes_mut(project, part, clip).filter(|n| !n.is_empty()) {
                notes.remove(at.index(notes.len()));
            }
        }
        Edit::ChangeNote { part, clip, at, pitch, start } => {
            if let Some(notes) = notes_mut(project, part, clip).filter(|n| !n.is_empty()) {
                let note = notes.get_mut(at.index(notes.len())).expect("a note there");
                (note.pitch, note.start) = (*pitch, *start);
            }
        }
        Edit::KeepNotesBelow { part, clip, pitch } => {
            if let Some(notes) = notes_mut(project, part, clip) {
                notes.retain(|n| n.pitch < *pitch);
            }
        }
        Edit::SortNotesByPitch { part, clip } => {
            if let Some(notes) = notes_mut(project, part, clip) {
                notes.sort_by(|a, b| a.pitch.cmp(&b.pitch));
            }
        }
        Edit::AssignNotes { part, clip, at, pitch } => {
            if let Some(notes) = notes_mut(project, part, clip).filter(|n| !n.is_empty()) {
                let mut list = notes.to_vec();
                let at = at.index(list.len());
                list[at].pitch = *pitch;
                list.remove(list.len() - 1 - at);
                notes.assign(list);
            }
        }
        Edit::AddClip { part, at, start, notes } => {
            let id = project.max_id() + 1;
            if let Some(part) = part_mut(project, part) {
                let at = at.index(part.clips.len() + 1);
                part.clips.insert(at, Arc::new(midi_clip(id, *start, notes.clone())));
            }
        }
        Edit::RemoveClip { part, at } => {
            if let Some(part) = part_mut(project, part).filter(|t| !t.clips.is_empty()) {
                part.clips.remove(at.index(part.clips.len()));
            }
        }
        Edit::MoveClip { part, at, start } => {
            if let Some(part) = part_mut(project, part).filter(|t| !t.clips.is_empty()) {
                let at = at.index(part.clips.len());
                Arc::make_mut(&mut part.clips[at]).start = *start;
            }
        }
        Edit::RenamePart { part, name } => {
            if let Some(part) = part_mut(project, part) {
                part.name.clone_from(name);
            }
        }
        Edit::SetVolume { part, volume } => {
            if let Some(part) = part_mut(project, part) {
                part.volume = *volume;
            }
        }
        Edit::AddPart => {
            let id = project.max_id() + 1;
            project.parts.push(Arc::new(Part::new(id)));
        }
        Edit::RemovePart { part } => {
            if !project.parts.is_empty() {
                let at = part.index(project.parts.len());
                project.parts.remove(at);
            }
        }
        Edit::SetTempo { bpm } => {
            project.tempo = *bpm;
            project.refresh_tempo();
        }
    }
}

/// The project as its file has it.
fn text(project: &Project) -> String {
    serde_json::to_string(project).expect("a project is written")
}

proptest! {
    #![proptest_config(config())]

    /// An undo after a step of changes gives the project as it was before
    /// them, and a redo the project after them, while the session goes on
    /// changing its own project.
    #[test]
    fn an_undo_gives_the_project_before_a_change(
        project in project(),
        step in vec(edit(), 1..8),
        later in vec(edit(), 0..8),
    ) {
        let before = text(&project);
        let mut history = History::new(project.clone(), 0.0, 1000).weigh_with(Project::weight_over, usize::MAX);
        let mut working = project;
        for edit in &step {
            apply(&mut working, edit);
        }
        let after = text(&working);
        history.push(working.clone(), 1.0);
        // Changes of the next step, not yet kept.
        for edit in &later {
            apply(&mut working, edit);
        }

        history.undo();
        let undone = text(history.current_snapshot());
        history.redo();
        let redone = text(history.current_snapshot());

        prop_assert!(undone == before, "the undo gives the project before the step");
        prop_assert!(redone == after, "the redo gives the project after the step");
    }
}
