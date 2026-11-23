//! The undo tree as the model holds it: its states, limits, names and
//! labels, and the step being made. A move in the tree, which may read the
//! undo file and tells the engine, is the session's, in `session/undo.rs`;
//! so is the undo file, which a thread writes.

use std::time::Duration;

use anyhow::{Result, bail};
use serde_json::{Value, json};

use super::Document;
use crate::clock::ScheduleTime;
use crate::history::{History, StateId};
use crate::model::Project;

/// How many steps the undo history keeps until told otherwise
/// (`paw.opt.undo_steps`).
const UNDO_LIMIT: usize = 1000;
/// And at most about this many bytes of what its steps changed
/// (`paw.opt.undo_memory`): a step that changes one note of a big clip keeps
/// a copy of the run of notes it changed (`model::Notes`).
const UNDO_BYTES: usize = 1 << 30;

/// An undo tree for a project, from `project` on at the wall time `wall`
/// (seconds since 1970), keeping at most `limit` steps and about `bytes`
/// bytes.
pub(crate) fn new_history(project: Project, wall: f64, (limit, bytes): (usize, usize)) -> History<Project> {
    History::new(project, wall, limit).weigh_with(Project::weight_over, bytes)
}

/// The edits of the open undo step: how many, how many of them moved a
/// control, and which control if they all moved the same one.
#[derive(Default)]
pub(crate) struct Sweep {
    pub edits: u32,
    pub moves: u32,
    pub key: Option<String>,
    pub mixed: bool,
}

/// Moves of one control closer together than this, in schedule time, are
/// one undo step.
pub(crate) const SWEEP_GAP: Duration = Duration::from_millis(1000);

/// The undo tree and the step being made: what the project was at the last
/// step, how the open step's edits are joined, and whether a flush reports a
/// state put back.
pub(crate) struct Undo {
    /// The project at the last undo step.
    pub checkpoint: Project,
    /// Every undo step, as a tree: see [`crate::history`].
    pub history: History<Project>,
    /// Edits were made since the last undo step: the open step has
    /// something in it.
    pub touched: bool,
    /// What the open undo step is made of, to tell a control being moved
    /// (a fader dragged, a knob turned on a controller) from other edits:
    /// its moves become one undo step, not one each.
    pub sweep: Sweep,
    /// The control the last undo step moved, when it did nothing else, and
    /// the schedule time of that step.
    pub last_sweep: Option<(String, ScheduleTime, StateId)>,
    /// The next flush reports a state put back (undo, redo, a file opened)
    /// rather than an edit: its events carry `restored = true`.
    pub restoring: bool,
    /// The undo state the edits of this turn join instead of making a step
    /// of their own, set by `undo_join`.
    pub join: Option<StateId>,
    /// Counts every change to the project, undo and redo included.
    pub edits: u64,
    /// While a command is run again in place of its step (the session's
    /// `undo_adjust`): the step as it was, to put back when the
    /// command fails.
    pub adjusting: Option<Adjusting>,
}

/// A step that a command is being run again for.
pub(crate) struct Adjusting {
    pub project: Project,
    pub label: Option<String>,
}

impl Undo {
    /// No steps yet: the tree starts at `project`, at the wall time `wall`.
    pub(crate) fn new(project: &Project, wall: f64) -> Self {
        Self {
            checkpoint: project.clone(),
            history: new_history(project.clone(), wall, (UNDO_LIMIT, UNDO_BYTES)),
            touched: false,
            sweep: Sweep::default(),
            last_sweep: None,
            restoring: false,
            join: None,
            edits: 0,
            adjusting: None,
        }
    }
}

impl Document {
    /// The whole tree, as plain data.
    pub(crate) fn undo_tree(&self) -> Value {
        let h = &self.undo.history;
        let states: Vec<Value> = h
            .states()
            .map(|s| {
                json!({
                    "id": s.id, "parent": s.parent, "children": s.children, "redo": s.redo,
                    "time": s.time, "label": s.label, "keys": s.keys, "name": s.name,
                    "keep": s.keep, "current": s.id == h.current(),
                    "saved": h.saved() == Some(s.id),
                })
            })
            .collect();
        json!({
            "current": h.current(), "root": h.root(), "saved": h.saved(),
            "limit": h.limit(), "pending": self.undo.touched, "states": states,
            "bytes": h.bytes(), "byte_limit": h.byte_limit(),
        })
    }

    /// Keep at most `steps` states and about `bytes` bytes of what they
    /// changed, letting the oldest go at once if there are more. Either
    /// left out stays as it is; out of the ranges `paw.opt.undo_steps` and
    /// `undo_memory` take, neither changes.
    pub(crate) fn undo_limits(&mut self, steps: Option<usize>, bytes: Option<usize>) -> Result<()> {
        if let Some(steps) = steps
            && !(10..=1_000_000).contains(&steps)
        {
            bail!("the undo history keeps 10 to 1000000 steps, not {steps}");
        }
        if let Some(bytes) = bytes
            && !(16 << 20..=1u64 << 40).contains(&(bytes as u64))
        {
            bail!("the undo history keeps 16 MB to 1 TB, not {bytes} bytes");
        }
        let h = &mut self.undo.history;
        h.set_limits(steps.unwrap_or(h.limit()), bytes.unwrap_or(h.byte_limit()));
        Ok(())
    }

    /// The current state's id.
    pub(crate) fn undo_current(&self) -> StateId {
        self.undo.history.current()
    }

    /// Keep a state from being pruned, or let it be again.
    pub(crate) fn undo_keep(&mut self, id: StateId, keep: bool) -> Result<()> {
        if !self.undo.history.set_keep(id, keep) {
            bail!("no state {id} in the undo tree");
        }
        Ok(())
    }

    /// The command making the open step: see [`History::label`].
    pub(crate) fn undo_label(&mut self, text: Option<String>) {
        self.undo.history.label(text);
    }

    /// Make the edits of the open step part of state `id` instead of a step
    /// of their own, if `id` is still the current state and nothing hangs on
    /// it. Returns whether they will be.
    pub(crate) fn undo_join(&mut self, id: StateId) -> bool {
        let joins = id == self.undo.history.current() && self.undo.history.can_extend();
        self.undo.join = joins.then_some(id);
        joins
    }

    /// The command that the session's `undo_adjust` ran again failed: put the
    /// step back as it was.
    pub(crate) fn undo_adjust_cancel(&mut self) {
        let Some(step) = self.undo.adjusting.take() else { return };
        let current = self.undo.history.current();
        self.undo.history.set_label(current, step.label);
        self.reopen_step(step.project);
    }

    /// Start the undo tree again from the project as it is, at the wall
    /// time `wall` (seconds since 1970).
    pub(crate) fn undo_reset(&mut self, wall: f64) {
        self.undo.checkpoint = self.project.clone();
        self.undo.history.reset(self.project.clone(), wall);
        self.undo.touched = false;
    }

    /// The keys typed for the open step.
    pub(crate) fn undo_keys(&mut self, text: String) {
        self.undo.history.keys(text);
    }

    /// Put back the project as the open step found it, leaving the history
    /// as it was. The session's `undo_discard` says when.
    pub(crate) fn undo_discard(&mut self) {
        self.reopen_step(self.undo.checkpoint.clone());
    }

    /// Take up `project` as the project of the last step, with an empty open
    /// step. The next flush reports it as a state put back.
    fn reopen_step(&mut self, project: Project) {
        self.project = project.clone();
        self.undo.checkpoint = project;
        self.undo.touched = false;
        self.undo.join = None;
        self.undo.sweep = Default::default();
        self.undo.history.clear_labels();
        self.dirty = true;
        self.undo.restoring = true;
        self.undo.edits += 1;
    }
}
