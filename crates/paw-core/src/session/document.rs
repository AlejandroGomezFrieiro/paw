//! The document: the project, its edits and its undo tree, with no engine.
//!
//! [`Session`](super::Session) holds one document in `doc`. An edit changes
//! [`Document::project`] and marks it dirty. The session's `flush` then
//! compares the project with what the engine last saw and sends the
//! difference: only `sync` tells the engine. A test of an edit or an undo
//! makes a [`Document`] and needs no engine.

use std::collections::{BTreeSet, HashMap};
use std::sync::Arc;
use std::time::Instant;

use anyhow::Result;
use serde_json::Value;

use super::undo::{self, SWEEP_GAP};
use crate::events::{ClipCopied, KernelEvent as E, TrackCopied};
use crate::history::{self, History, StateId};
use crate::model::{Clip, ClipContent, ClipKindId, DeviceInst, Id, Links, MASTER_ID, Project, Track};
use crate::sync::ModelEvent;

mod links;
pub mod notes;
mod tempo;
mod tracks;
pub use tracks::ControlMove;

/// The project, its undo tree, and what its edits report.
pub struct Document {
    pub project: Project,
    /// The tracks (and the master) as the last edit left them, its notes
    /// named: the next edit looks for notes to name only where it differs.
    pub(super) named: (Vec<Arc<Track>>, Arc<Track>),
    /// The project differs from what the engine last saw: the session's
    /// next `flush` sends the difference.
    pub(super) dirty: bool,
    /// The undo tree and the open step: see `session/undo.rs`.
    pub(super) undo: undo::Undo,
    pub(super) next_id: Id,
    /// The kinds of clip that extensions defined (`paw.clip_kinds.define`):
    /// a clip of another custom kind is not added. Not part of the project.
    pub(super) clip_kinds: BTreeSet<ClipKindId>,
    /// Change notifications waiting to be delivered to Lua.
    pub events: Vec<ModelEvent>,
    pub warnings: Vec<String>,
}

impl Default for Document {
    /// An empty project with no undo steps.
    fn default() -> Self {
        let project = Project::default();
        Self {
            named: (project.tracks.clone(), project.master.clone()),
            undo: undo::Undo::new(&project),
            project,
            dirty: false,
            next_id: MASTER_ID + 1,
            clip_kinds: BTreeSet::new(),
            events: Vec::new(),
            warnings: Vec::new(),
        }
    }
}

impl Document {
    /// Report an event to Lua at the end of the turn (`events_take`).
    pub fn emit(&mut self, event: crate::events::KernelEvent) {
        self.events.push(event.into());
    }

    /// Change the project. The engine catches up at the session's next
    /// `flush`.
    ///
    /// An edit that fails must leave the project as it found it (check
    /// first, then change). It then makes no undo step and does not mark the
    /// project modified, so that the next undo undoes the last real edit.
    pub fn edit<R>(&mut self, f: impl FnOnce(&mut Project) -> Result<R>) -> Result<R> {
        self.edit_then(f, true)
    }

    /// An edit that leaves every note with an id of its own, so that nothing
    /// need be named after it: one note added, changed or removed, which on
    /// a clip of many thousands would otherwise cost a look at all of them.
    pub fn edit_named<R>(&mut self, f: impl FnOnce(&mut Project) -> Result<R>) -> Result<R> {
        self.edit_then(f, false)
    }

    /// The edit, then what follows each edit that did not fail: its new
    /// notes named (with `name`), then the clips of each link it changed
    /// given the changed notes, so that they share the same named notes.
    fn edit_then<R>(&mut self, f: impl FnOnce(&mut Project) -> Result<R>, name: bool) -> Result<R> {
        let links = Links::before(&self.project);
        let result = f(&mut self.project);
        if result.is_ok() {
            if name {
                // A note is named as it is made, so that it can be addressed at once.
                self.project.name_notes_since(&self.named.0, &self.named.1);
            }
            links.spread(&mut self.project);
            if name {
                self.named = (self.project.tracks.clone(), self.project.master.clone());
            }
            self.undo.history.edited();
            self.dirty = true;
            self.undo.touched = true;
            self.undo.edits += 1;
            self.undo.sweep.edits += 1;
        }
        result
    }

    /// Note that the edit just made moved a control: `key` names it.
    pub(super) fn swept(&mut self, key: String) {
        self.undo.sweep.moves += 1;
        match &self.undo.sweep.key {
            None => self.undo.sweep.key = Some(key),
            Some(known) if *known != key => self.undo.sweep.mixed = true,
            Some(_) => {}
        }
    }

    /// Counts every change to the project, undo and redo included: a
    /// cache of what the project names (the files that clips read) is
    /// stale when the count moved.
    pub fn changes(&self) -> u64 {
        self.undo.edits
    }

    pub(super) fn new_id(&mut self) -> Id {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    /// Close the current undo step, if anything changed since the last one.
    /// True when it made a new step; false when nothing changed, or when the
    /// open step joined the step before it.
    pub fn checkpoint(&mut self) -> bool {
        let sweep = std::mem::take(&mut self.undo.sweep);
        let join = self.undo.join.take();
        self.undo.adjusting = None;
        if !self.undo.touched {
            self.undo.history.clear_labels();
            return false;
        }
        self.undo.touched = false;
        self.own_edited_references();
        // An edit not yet played has notes not yet named: the step keeps them named.
        if self.project.name_notes(&self.undo.checkpoint) {
            self.dirty = true;
        }
        if join.is_some_and(|state| state == self.undo.history.current() && self.undo.history.can_extend()) {
            // Asked for: what this turn did belongs to the step before.
            self.undo.checkpoint = self.project.clone();
            self.undo.history.amend(self.undo.checkpoint.clone(), history::now());
            self.undo.last_sweep = None;
            return false;
        }
        // The one control this step moved, if that is all it did.
        let moved = sweep
            .key
            .filter(|_| sweep.moves == sweep.edits && !sweep.mixed);
        if let (Some(key), Some((last, at, state))) = (&moved, &self.undo.last_sweep)
            && key == last
            && at.elapsed() < SWEEP_GAP
            && *state == self.undo.history.current()
            && self.undo.history.can_amend()
        {
            // Still the same move: the step made for it holds where it got to.
            let state = *state;
            self.undo.checkpoint = self.project.clone();
            self.undo.history.amend(self.undo.checkpoint.clone(), history::now());
            self.undo.last_sweep = Some((key.clone(), Instant::now(), state));
            return false;
        }
        if let Some(name) = self.only_nest_changed() {
            self.undo.history.label_place(&name);
        }
        let previous = std::mem::replace(&mut self.undo.checkpoint, self.project.clone());
        self.undo.history.set_current_snapshot(previous);
        let state = self.undo.history.push(self.undo.checkpoint.clone(), history::now());
        if self.undo.history.newly_pruned() {
            self.warnings.push(format!(
                "the undo history keeps {} steps and {} MB at most: its oldest steps are let go",
                self.undo.history.limit(),
                self.undo.history.byte_limit() >> 20
            ));
        }
        self.undo.last_sweep = moved.map(|key| (key, Instant::now(), state));
        true
    }

    /// Undo the last step. False, and nothing changes, at the first state.
    ///
    /// The session's `undo` also ends a trial, tells the engine first, and
    /// reads a state that is only in the undo file.
    pub fn undo(&mut self) -> bool {
        self.move_in_history(History::undo).is_some()
    }

    /// Redo the step undone last. False, and nothing changes, when there is
    /// none.
    pub fn redo(&mut self) -> bool {
        self.move_in_history(History::redo).is_some()
    }

    /// Close the open step, then move in the tree and take up the state
    /// moved to. None, and nothing changes, when there is nowhere to go.
    fn move_in_history(&mut self, go: impl FnOnce(&mut History<Project>) -> Option<StateId>) -> Option<StateId> {
        self.checkpoint();
        let (from, id) = self.history_move(go)?;
        if id != from {
            self.take_current_state();
        }
        Some(id)
    }

    /// Move in the undo tree with `go`, but do not take up the state moved
    /// to yet. Gives the state it was at and the state it is at now. None,
    /// and the tree does not move, when there is nowhere to go.
    pub(super) fn history_move(
        &mut self,
        go: impl FnOnce(&mut History<Project>) -> Option<StateId>,
    ) -> Option<(StateId, StateId)> {
        // Bookkeeping since the step closed (plugin parameters taken over by
        // their editors, recordings moved beside the project) stays with it.
        self.undo.history.set_current_snapshot(self.undo.checkpoint.clone());
        let from = self.undo.history.current();
        let id = go(&mut self.undo.history)?;
        Some((from, id))
    }

    /// Take up the state that the undo tree is at, after a move in it.
    pub(super) fn take_current_state(&mut self) {
        self.project = self.undo.history.current_snapshot().clone();
        self.undo.checkpoint = self.project.clone();
        self.dirty = true;
        self.undo.restoring = true;
        self.undo.edits += 1;
    }

    /// The name of the subproject whose tracks are all that this step
    /// changed, for the step's label (one undo tree names where each step
    /// was made). None when it changed a track of the song, or nothing of a
    /// track.
    fn only_nest_changed(&self) -> Option<String> {
        if self.project.nests.is_empty() {
            return None;
        }
        let before: HashMap<Id, &Arc<Track>> =
            self.undo.checkpoint.tracks.iter().map(|t| (t.id, t)).collect();
        let now: HashMap<Id, &Arc<Track>> = self.project.tracks.iter().map(|t| (t.id, t)).collect();
        // The places of the tracks that came, changed or went.
        let changed = self
            .project
            .tracks
            .iter()
            .filter(|t| before.get(&t.id).is_none_or(|b| !Arc::ptr_eq(b, t)))
            .chain(before.values().copied().filter(|t| !now.contains_key(&t.id)))
            .map(|t| t.nest);
        let mut place = None;
        for nest in changed {
            if place.is_some_and(|p| p != nest) {
                return None;
            }
            place = Some(nest);
        }
        let nest = place.flatten()?;
        self.project.nest(nest).map(|n| n.name.clone())
    }

    /// A clip that refers to a file outside the project and whose notes
    /// this step changed is now the project's own, in the same step: it
    /// keeps where it came from (`origin`). Said once, as `clip.copied`.
    pub(super) fn own_edited_references(&mut self) {
        self.own_edited_clips();
        self.own_edited_tracks();
    }

    /// A track read from a folder outside the project, or a chain read from
    /// a file outside it, that this step changed is now the project's own,
    /// as a clip is (`own_edited_clips`): `track.copied`, `chain.copied`.
    /// A track takes its clips from that folder with it.
    pub(super) fn own_edited_tracks(&mut self) {
        let before: HashMap<Id, &Arc<Track>> = self
            .undo.checkpoint
            .tracks
            .iter()
            .filter(|t| t.source.is_some() || t.chain_source.is_some())
            .map(|t| (t.id, t))
            .collect();
        if before.is_empty() {
            return;
        }
        // A plugin's state is read again at each save: that is not an edit.
        let stateless = |devices: &[Arc<DeviceInst>]| -> Vec<Value> {
            devices
                .iter()
                .map(|d| {
                    let mut v = serde_json::to_value(&**d).unwrap_or_default();
                    v.as_object_mut().map(|o| o.remove("state"));
                    v
                })
                .collect()
        };
        let whole = |t: &Track| -> Value {
            let mut v = serde_json::to_value(t).unwrap_or_default();
            if let Some(o) = v.as_object_mut() {
                o.insert("devices".into(), Value::Array(stateless(&t.devices)));
            }
            v
        };
        let (mut tracks, mut chains) = (Vec::new(), Vec::new());
        for t in &self.project.tracks {
            let Some(old) = before.get(&t.id) else {
                continue;
            };
            if Arc::ptr_eq(old, t) {
                continue;
            }
            if t.source.is_some() && t.source == old.source && whole(old) != whole(t) {
                tracks.push(t.id);
            } else if t.chain_source.is_some()
                && t.chain_source == old.chain_source
                && stateless(&old.devices) != stateless(&t.devices)
            {
                chains.push(t.id);
            }
        }
        for id in tracks {
            let Some(track) = self.project.track_mut(id) else {
                continue;
            };
            track.origin = track.source.take();
            let folder = track.origin.clone().unwrap_or_default();
            for clip in track.clips.iter_mut().chain(track.cues.iter_mut()) {
                if clip.source.as_ref().is_some_and(|s| s.starts_with(&folder)) {
                    let clip = Arc::make_mut(clip);
                    clip.origin = clip.source.take();
                }
            }
            let copied = TrackCopied { track: id, name: track.name.clone(), origin: track.origin.clone() };
            self.emit(E::TrackCopied(copied));
        }
        for id in chains {
            let Some(track) = self.project.track_mut(id) else {
                continue;
            };
            track.chain_origin = track.chain_source.take();
            let copied = TrackCopied { track: id, name: track.name.clone(), origin: track.chain_origin.clone() };
            self.emit(E::ChainCopied(copied));
        }
    }

    pub(super) fn own_edited_clips(&mut self) {
        // Only the clips of the tracks the step changed, and of those only
        // the stretch it changed, can have been edited.
        let (old, new) = (&self.undo.checkpoint, &self.project);
        let mut after = crate::model::ById::new(&new.tracks, |t: &Arc<Track>| t.id);
        let mut before: HashMap<Id, &Arc<Clip>> = HashMap::new();
        let mut changed: Vec<(&Arc<Track>, Option<&Arc<Track>>)> = Vec::new();
        for track in old.all_tracks() {
            let now = if track.id == MASTER_ID { Some(&new.master) } else { after.find(track.id) };
            if now.is_some_and(|n| Arc::ptr_eq(n, track)) {
                continue;
            }
            let span = match now {
                Some(now) => now.clips.changed(&track.clips).0,
                None => 0..track.clips.len(),
            };
            let clips = track.clips.range(span).chain(&track.cues);
            before.extend(clips.filter(|c| c.source.is_some()).map(|c| (c.id, c)));
            if let Some(now) = now {
                changed.push((now, Some(track)));
            }
        }
        if before.is_empty() {
            return;
        }
        let mut was = crate::model::ById::new(&old.tracks, |t: &Arc<Track>| t.id);
        for track in &new.tracks {
            if was.find(track.id).is_none() {
                changed.push((track, None));
            }
        }
        let same = |a: &Clip, b: &Clip| match (&a.content, &b.content) {
            (
                ClipContent::Midi { notes, controls },
                ClipContent::Midi {
                    notes: n2,
                    controls: c2,
                },
            ) => notes == n2 && controls == c2,
            _ => true,
        };
        let mut owned = Vec::new();
        for (track, was) in changed {
            let span = match was {
                Some(was) => track.clips.changed(&was.clips).1,
                None => 0..track.clips.len(),
            };
            for clip in track.clips.range(span).chain(&track.cues) {
                if let Some(old) = before.get(&clip.id)
                    && clip.source.is_some()
                    && clip.source == old.source
                    && !Arc::ptr_eq(old, clip)
                    && !same(old, clip)
                {
                    owned.push(clip.id);
                }
            }
        }
        for id in owned {
            let Some(clip) = self.project.clip_mut(id) else {
                continue;
            };
            clip.origin = clip.source.take();
            let copied = ClipCopied { clip: id, name: clip.name.clone(), origin: clip.origin.clone() };
            self.emit(E::ClipCopied(copied));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_edit_is_undone_and_redone_with_no_engine() {
        let mut doc = Document::default();
        let id = doc.new_id();
        doc.edit(|project| {
            project.tracks.push(Arc::new(Track::new(id)));
            Ok(())
        })
        .unwrap();
        assert!(doc.checkpoint(), "the edit makes an undo step");

        assert!(doc.undo(), "the step is undone");
        assert!(doc.project.tracks.is_empty(), "the undo takes the track away");
        assert!(doc.redo(), "the step is redone");
        let tracks: Vec<Id> = doc.project.tracks.iter().map(|t| t.id).collect();
        assert_eq!(tracks, [id], "the redo gives the track back");
        assert!(!doc.redo(), "nothing is left to redo");
    }

    #[test]
    fn an_edit_that_fails_makes_no_undo_step() {
        let mut doc = Document::default();
        let failed = doc.edit(|project| -> Result<()> {
            anyhow::bail!("{} tracks: no change", project.tracks.len())
        });
        assert!(failed.is_err());
        assert!(!doc.checkpoint(), "no step for an edit that failed");
        assert!(!doc.undo(), "nothing to undo");
    }
}
