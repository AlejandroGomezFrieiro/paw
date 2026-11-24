//! The document: the project, its edits and its undo tree, with no engine.
//!
//! The session holds one document in `doc`. An edit changes
//! [`Document::project`] and marks it dirty. The session's `flush` then
//! compares the project with what the engine last saw and sends the
//! difference: only `sync` tells the engine. A test of an edit or an undo
//! makes a [`Document`] and needs no engine.
//!
//! The submodules hold the methods of each area (parts, clips, notes,
//! lanes, nests, devices, tempo, the project's fields, the undo tree). Where
//! a method needs what only the session has (a file, a plugin's parameter
//! range), it takes it as an argument: `sound_seconds`, `is_file`,
//! [`ParamRange`], `path`. It reads no clock either: a step of the undo tree
//! gets the schedule time of the turn (`now`) and the wall time that the
//! tree shows (`wall`, seconds since 1970) from the session.
#![cfg_attr(test, expect(clippy::float_cmp, reason = "debt: pay down"))]

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::Result;
use serde_json::Value;

use crate::clock::ScheduleTime;
use crate::events::{ClipCopied, KernelEvent as E, NestCopied, PartCopied};
use crate::history::{History, StateId};
use crate::model::chain::SplitRegistry as _;
use crate::model::{Clip, ClipContent, DeviceInst, Id, Links, MASTER_ID, Project, Part};
use crate::sync::ModelEvent;

// The model's part of each area: what reads or changes only the project.
// A method that also reads a file, asks a plugin or tells the engine stays
// on Session, in the file of the same name one folder up, and calls these.
mod automation;
mod clips;
mod devices;
mod chain;
mod kinds;
mod links;
mod nests;
pub(crate) mod notes;
mod project;
mod stacks;
mod tempo;
mod parts;
mod undo_tree;
pub(super) mod values;
pub(super) use automation::{check_lane_state, clean_points};
pub(crate) use automation::{LanePatch, LaneView};
pub(crate) use devices::DevicePatch;
pub(super) use clips::{check_clip_part, check_pitch, check_ratio, check_tempo, check_warp};
pub(crate) use clips::{ClipChange, ClipKind, ClipOpts, ClipPatch, CustomSet};
pub(crate) use parts::{PartListOpts, PartPatch, PartView};
pub(crate) use project::{ProjectPatch, ProjectView};
#[cfg(test)]
pub(super) use parts::PartOpts;
pub(super) use undo_tree::{Adjusting, new_history};
use undo_tree::{SWEEP_GAP, Undo};
pub(super) use values::{finite, sorted};
pub(crate) use values::{Change, Settable};
pub(crate) use chain::{Place, WrapOpts};
pub(crate) use kinds::{KindBook, KindInfo};

/// The project, its undo tree, and what its edits report.
pub(crate) struct Document {
    pub project: Project,
    /// The parts (and the master) as the last edit left them, its notes
    /// named: the next edit looks for notes to name only where it differs.
    pub(super) named: (Vec<Arc<Part>>, Arc<Part>),
    /// The project differs from what the engine last saw: the session's
    /// next `flush` sends the difference.
    pub(super) dirty: bool,
    /// The undo tree and the open step: see `undo_tree.rs`.
    pub(super) undo: Undo,
    pub(super) next_id: Id,
    /// The kinds of each family that `paw.kinds` defined, as the kernel
    /// reads them (`kinds.rs`). Not part of the project.
    pub(crate) kinds: KindBook,
    /// The kinds of split, with those that extensions defined
    /// (`paw.chain.define_kind`). Not part of the project.
    pub(super) split_kinds: crate::model::chain::SplitKinds,
    /// The kinds of modifier of a stack (`model/modifiers.rs`). Not part
    /// of the project.
    pub(super) modifier_kinds: crate::model::modifiers::ModKinds,
    /// Change notifications waiting to be delivered to Lua.
    pub events: Vec<ModelEvent>,
    pub warnings: Vec<String>,
}

#[cfg(test)]
impl Default for Document {
    /// For a test: an empty project with no undo steps, made at the wall
    /// time 0.
    fn default() -> Self {
        Self::new(0.0)
    }
}

impl Document {
    /// An empty project with no undo steps, made at the wall time `wall`
    /// (seconds since 1970).
    pub(crate) fn new(wall: f64) -> Self {
        let project = Project::default();
        Self {
            named: (project.parts.clone(), project.master.clone()),
            undo: Undo::new(&project, wall),
            project,
            dirty: false,
            next_id: MASTER_ID + 1,
            kinds: KindBook::default(),
            split_kinds: crate::model::chain::SplitKinds::builtin(),
            modifier_kinds: crate::model::modifiers::builtin_kinds(),
            events: Vec::new(),
            warnings: Vec::new(),
        }
    }
}

impl Document {
    /// Report an event to Lua at the end of the turn (`events_take`).
    pub(crate) fn emit(&mut self, event: crate::events::KernelEvent) {
        self.events.push(event.into());
    }

    /// Change the project. The engine catches up at the session's next
    /// `flush`.
    ///
    /// An edit that fails must leave the project as it found it (check
    /// first, then change). It then makes no undo step and does not mark the
    /// project modified, so that the next undo undoes the last real edit.
    pub(crate) fn edit<R>(&mut self, f: impl FnOnce(&mut Project) -> Result<R>) -> Result<R> {
        self.edit_then(f, true)
    }

    /// An edit that leaves every note with an id of its own, so that nothing
    /// need be named after it: one note added, changed or removed, which on
    /// a clip of many thousands would otherwise cost a look at all of them.
    pub(crate) fn edit_named<R>(&mut self, f: impl FnOnce(&mut Project) -> Result<R>) -> Result<R> {
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
            // A chain follows its owner's devices (`model/owner.rs`).
            self.project.fit_chains();
            if name {
                self.named = (self.project.parts.clone(), self.project.master.clone());
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
    pub(crate) fn changes(&self) -> u64 {
        self.undo.edits
    }

    pub(super) fn new_id(&mut self) -> Id {
        let id = self.next_id;
        self.next_id += 1;
        id
    }

    /// Close the current undo step at `now`, if anything changed since the
    /// last one; the step shows the wall time `wall`. True when it made a new
    /// step; false when nothing changed, or when the open step joined the
    /// step before it.
    pub(crate) fn checkpoint(&mut self, now: ScheduleTime, wall: f64) -> bool {
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
            self.undo.history.amend(self.undo.checkpoint.clone(), wall);
            self.undo.last_sweep = None;
            return false;
        }
        // The one control this step moved, if that is all it did.
        let moved = sweep
            .key
            .filter(|_| sweep.moves == sweep.edits && !sweep.mixed);
        if let (Some(key), Some((last, at, state))) = (&moved, &self.undo.last_sweep)
            && key == last
            && now - *at < SWEEP_GAP
            && *state == self.undo.history.current()
            && self.undo.history.can_amend()
        {
            // Still the same move: the step made for it holds where it got to.
            let state = *state;
            self.undo.checkpoint = self.project.clone();
            self.undo.history.amend(self.undo.checkpoint.clone(), wall);
            self.undo.last_sweep = Some((key.clone(), now, state));
            return false;
        }
        if let Some(name) = self.only_nest_changed() {
            self.undo.history.label_place(&name);
        }
        let previous = std::mem::replace(&mut self.undo.checkpoint, self.project.clone());
        self.undo.history.set_current_snapshot(previous);
        let state = self.undo.history.push(self.undo.checkpoint.clone(), wall);
        if self.undo.history.newly_pruned() {
            self.warnings.push(format!(
                "the undo history keeps {} steps and {} MB at most: its oldest steps are let go",
                self.undo.history.limit(),
                self.undo.history.byte_limit() >> 20
            ));
        }
        self.undo.last_sweep = moved.map(|key| (key, now, state));
        true
    }

    /// Undo the last step. False, and nothing changes, at the first state.
    ///
    /// The session's `undo` also ends a trial, tells the engine first, and
    /// reads a state that is only in the undo file.
    #[cfg(test)]
    pub(crate) fn undo(&mut self) -> bool {
        self.move_in_history(History::undo).is_some()
    }

    /// Redo the step undone last. False, and nothing changes, when there is
    /// none.
    #[cfg(test)]
    pub(crate) fn redo(&mut self) -> bool {
        self.move_in_history(History::redo).is_some()
    }

    /// Close the open step, then move in the tree and take up the state
    /// moved to. None, and nothing changes, when there is nowhere to go.
    #[cfg(test)]
    fn move_in_history(&mut self, go: impl FnOnce(&mut History<Project>) -> Option<StateId>) -> Option<StateId> {
        // A move in the tree ends a sweep: the open step joins no step
        // before it, so the time does not matter.
        self.undo.last_sweep = None;
        self.checkpoint(ScheduleTime::ZERO, 0.0);
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

    /// The name of the subproject whose parts are all that this step
    /// changed, for the step's label (one undo tree names where each step
    /// was made). None when it changed a part of the song, or nothing of a
    /// part.
    fn only_nest_changed(&self) -> Option<String> {
        if self.project.nests.is_empty() {
            return None;
        }
        let before: HashMap<Id, &Arc<Part>> =
            self.undo.checkpoint.parts.iter().map(|t| (t.id, t)).collect();
        let now: HashMap<Id, &Arc<Part>> = self.project.parts.iter().map(|t| (t.id, t)).collect();
        // The places of the parts that came, changed or went.
        let changed = self
            .project
            .parts
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
        self.own_edited_parts();
        self.own_edited_nests();
    }

    /// A nest that refers to a project folder outside (`:import`), with
    /// the nests that came with it, that this step changed is now the
    /// project's own, as a part is: `nest.copied`, once for the
    /// reference. A change is one of a nest of the reference, or of a
    /// part of one: its fields, its parts, their devices (not a plugin's
    /// state, read again at each save), clips and lanes.
    fn own_edited_nests(&mut self) {
        let references = self.undo.checkpoint.references();
        for (top, group) in references {
            let (old, new) = (&self.undo.checkpoint, &self.project);
            let source = old.nest(top).and_then(|n| n.source.clone());
            // `:nest.own` in this step, or the nest went: nothing to own.
            if new.nest(top).is_none_or(|n| n.source != source) {
                continue;
            }
            let nest_changed = group.iter().any(|id| match (old.nest(*id), new.nest(*id)) {
                (Some(a), Some(b)) => !Arc::ptr_eq(a, b) && a != b,
                _ => true,
            });
            let ours = |p: &Project| -> HashMap<Id, Arc<Part>> {
                p.parts
                    .iter()
                    .filter(|t| t.nest.is_some_and(|n| group.contains(&n)))
                    .map(|t| (t.id, t.clone()))
                    .collect()
            };
            let (before, now) = (ours(old), ours(new));
            let parts_changed = before.len() != now.len()
                || now.iter().any(|(id, t)| {
                    before
                        .get(id)
                        .is_none_or(|b| !Arc::ptr_eq(b, t) && without_states(b) != without_states(t))
                });
            if !(nest_changed || parts_changed) {
                continue;
            }
            self.project.own_reference(&group);
            let Some(nest) = self.project.nest(top) else {
                continue;
            };
            let copied = NestCopied { nest: top.0, name: nest.name.clone(), origin: nest.origin.clone() };
            self.emit(E::NestCopied(copied));
        }
    }

    /// A part read from a folder outside the project, or a chain read from
    /// a file outside it, that this step changed is now the project's own,
    /// as a clip is (`own_edited_clips`): `part.copied`, `chain.copied`.
    /// A part takes its clips from that folder with it.
    pub(super) fn own_edited_parts(&mut self) {
        let before: HashMap<Id, &Arc<Part>> = self
            .undo.checkpoint
            .parts
            .iter()
            .filter(|t| t.source.is_some() || t.chain_source.is_some())
            .map(|t| (t.id, t))
            .collect();
        if before.is_empty() {
            return;
        }
        let (mut parts, mut chains) = (Vec::new(), Vec::new());
        for t in &self.project.parts {
            let Some(old) = before.get(&t.id) else {
                continue;
            };
            if Arc::ptr_eq(old, t) {
                continue;
            }
            if t.source.is_some() && t.source == old.source && without_states(old) != without_states(t) {
                parts.push(t.id);
            } else if t.chain_source.is_some()
                && t.chain_source == old.chain_source
                && stateless(&old.devices) != stateless(&t.devices)
            {
                chains.push(t.id);
            }
        }
        for id in parts {
            let Some(part) = self.project.part_mut(id) else {
                continue;
            };
            part.origin = part.source.take();
            let folder = part.origin.clone().unwrap_or_default();
            for clip in part.clips.iter_mut().chain(part.cues.iter_mut()) {
                if clip.source.as_ref().is_some_and(|s| s.starts_with(&folder)) {
                    let clip = Arc::make_mut(clip);
                    clip.origin = clip.source.take();
                }
            }
            let copied = PartCopied { part: id, name: part.name.clone(), origin: part.origin.clone() };
            self.emit(E::PartCopied(copied));
        }
        for id in chains {
            let Some(part) = self.project.part_mut(id) else {
                continue;
            };
            part.chain_origin = part.chain_source.take();
            let copied = PartCopied { part: id, name: part.name.clone(), origin: part.chain_origin.clone() };
            self.emit(E::ChainCopied(copied));
        }
    }

    pub(super) fn own_edited_clips(&mut self) {
        // Only the clips of the parts the step changed, and of those only
        // the stretch it changed, can have been edited.
        let (old, new) = (&self.undo.checkpoint, &self.project);
        let mut after = crate::model::ById::new(&new.parts, |t: &Arc<Part>| t.id);
        let mut before: HashMap<Id, &Arc<Clip>> = HashMap::new();
        let mut changed: Vec<(&Arc<Part>, Option<&Arc<Part>>)> = Vec::new();
        for part in old.all_parts() {
            let now = if part.id == MASTER_ID { Some(&new.master) } else { after.find(part.id) };
            if now.is_some_and(|n| Arc::ptr_eq(n, part)) {
                continue;
            }
            let span = match now {
                Some(now) => now.clips.changed(&part.clips).0,
                None => 0..part.clips.len(),
            };
            let clips = part.clips.range(span).chain(&part.cues);
            before.extend(clips.filter(|c| c.source.is_some()).map(|c| (c.id, c)));
            if let Some(now) = now {
                changed.push((now, Some(part)));
            }
        }
        if before.is_empty() {
            return;
        }
        let mut was = crate::model::ById::new(&old.parts, |t: &Arc<Part>| t.id);
        for part in &new.parts {
            if was.find(part.id).is_none() {
                changed.push((part, None));
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
        for (part, was) in changed {
            let span = match was {
                Some(was) => part.clips.changed(&was.clips).1,
                None => 0..part.clips.len(),
            };
            for clip in part.clips.range(span).chain(&part.cues) {
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

/// A part's devices as JSON without a plugin's state: a plugin's state is
/// read again at each save, and that is not an edit.
fn stateless(devices: &[Arc<DeviceInst>]) -> Vec<Value> {
    devices
        .iter()
        .map(|d| {
            let mut v = serde_json::to_value(&**d).unwrap_or_default();
            v.as_object_mut().map(|o| o.remove("state"));
            v
        })
        .collect()
}

/// A part as JSON, its devices [`stateless`]: two parts that differ only
/// in a plugin's state give the same value.
fn without_states(t: &Part) -> Value {
    let mut v = serde_json::to_value(t).unwrap_or_default();
    if let Some(o) = v.as_object_mut() {
        o.insert("devices".into(), Value::Array(stateless(&t.devices)));
    }
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_edit_is_undone_and_redone_with_no_engine() {
        let mut doc = Document::default();
        let id = doc.new_id();
        doc.edit(|project| {
            project.parts.push(Arc::new(Part::new(id)));
            Ok(())
        })
        .unwrap();
        assert!(doc.checkpoint(ScheduleTime::ZERO, 0.0), "the edit makes an undo step");

        assert!(doc.undo(), "the step is undone");
        assert!(doc.project.parts.is_empty(), "the undo takes the part away");
        assert!(doc.redo(), "the step is redone");
        let parts: Vec<Id> = doc.project.parts.iter().map(|t| t.id).collect();
        assert_eq!(parts, [id], "the redo gives the part back");
        assert!(!doc.redo(), "nothing is left to redo");
    }

    #[test]
    fn the_first_edit_inside_a_nest_from_a_folder_makes_it_the_projects_own_in_the_same_step() {
        use crate::model::NestId;
        use std::path::Path;
        let mut doc = Document::default();
        let mut part = Project::default();
        let mut keys = Part::new(1);
        keys.name = "Keys".into();
        part.parts.push(Arc::new(keys));
        let mut song = Part::new(2);
        song.name = "Guitar".into();
        doc.edit(|p| {
            p.parts.push(Arc::new(song));
            p.adopt(part, NestId(10), "Bridge", Path::new("/lib/bridge"));
            Ok(())
        })
        .unwrap();
        doc.checkpoint(ScheduleTime::ZERO, 0.0);
        let source = |doc: &Document| doc.project.nest(NestId(10)).and_then(|n| n.source.clone());
        let copied = |doc: &Document| {
            doc.events.iter().filter(|e| matches!(e.event, E::NestCopied(_))).count()
        };
        let rename = |doc: &mut Document, id: Id, name: &str| {
            doc.edit(|p| {
                p.part_mut(id).unwrap().name = name.into();
                Ok(())
            })
            .unwrap();
            doc.checkpoint(ScheduleTime::ZERO, 0.0);
        };
        rename(&mut doc, 2, "Lead");
        assert!(source(&doc).is_some(), "an edit of the song leaves the reference");
        rename(&mut doc, 12, "Piano");
        assert_eq!(source(&doc), None, "an edit of its part makes it the project's own");
        let nest = doc.project.nest(NestId(10)).unwrap();
        assert_eq!(nest.origin.as_deref(), Some(Path::new("/lib/bridge")), "it keeps where it came from");
        assert_eq!(copied(&doc), 1, "said once");
        rename(&mut doc, 12, "Organ");
        assert_eq!(copied(&doc), 1, "and not again");
        doc.undo();
        doc.undo();
        assert_eq!(source(&doc).as_deref(), Some(Path::new("/lib/bridge")), "one undo step with the edit");
    }

    #[test]
    fn an_edit_that_fails_makes_no_undo_step() {
        let mut doc = Document::default();
        let failed = doc.edit(|project| -> Result<()> {
            anyhow::bail!("{} parts: no change", project.parts.len())
        });
        assert!(failed.is_err());
        assert!(!doc.checkpoint(ScheduleTime::ZERO, 0.0), "no step for an edit that failed");
        assert!(!doc.undo(), "nothing to undo");
    }

    /// Moves of one control are one undo step while each comes less than
    /// `SWEEP_GAP` of schedule time after the step before; a pause as long
    /// as the gap starts a new step.
    #[test]
    fn moves_of_one_control_join_one_step_until_a_pause_on_the_schedule_clock() {
        let at = |ms: u64| ScheduleTime::from_start(std::time::Duration::from_millis(ms));
        let mut doc = Document::default();
        let id = doc.new_id();
        doc.edit(|p| {
            p.parts.push(Arc::new(Part::new(id)));
            Ok(())
        })
        .unwrap();
        doc.checkpoint(at(0), 0.0);
        let drag = |doc: &mut Document, gain: f64, now: ScheduleTime| {
            doc.edit(|p| {
                p.part_mut(id).unwrap().volume = gain;
                Ok(())
            })
            .unwrap();
            doc.swept(format!("volume {id}"));
            doc.checkpoint(now, 0.0)
        };
        assert!(drag(&mut doc, -1.0, at(100)), "the first move makes a step");
        assert!(!drag(&mut doc, -2.0, at(100) + SWEEP_GAP / 2), "a move within the gap joins it");
        assert!(drag(&mut doc, -3.0, at(100) + SWEEP_GAP / 2 + SWEEP_GAP), "a move after a pause makes a new step");
        doc.undo();
        assert_eq!(doc.project.part(id).unwrap().volume, -2.0, "one undo takes back the last step");
        doc.undo();
        assert_eq!(doc.project.part(id).unwrap().volume, Part::new(id).volume, "the next takes back the joined moves");
    }
}
