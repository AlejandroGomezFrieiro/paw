//! The undo tree as the model holds it: its states, limits, names and
//! labels. A move in the tree, which may read the undo file and tells the
//! engine, is the session's, in `session/undo.rs`.

use anyhow::{Result, bail};
use serde_json::{Value, json};

use super::Document;
use crate::history::StateId;
use crate::model::Project;

impl Document {
    /// The whole tree, as plain data.
    pub fn undo_tree(&self) -> Value {
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
    pub fn undo_limits(&mut self, steps: Option<usize>, bytes: Option<usize>) -> Result<()> {
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
    pub fn undo_current(&self) -> StateId {
        self.undo.history.current()
    }

    /// Keep a state from being pruned, or let it be again.
    pub fn undo_keep(&mut self, id: StateId, keep: bool) -> Result<()> {
        if !self.undo.history.set_keep(id, keep) {
            bail!("no state {id} in the undo tree");
        }
        Ok(())
    }

    /// The command making the open step: see [`History::label`].
    pub fn undo_label(&mut self, text: Option<String>) {
        self.undo.history.label(text);
    }

    /// Make the edits of the open step part of state `id` instead of a step
    /// of their own, if `id` is still the current state and nothing hangs on
    /// it. Returns whether they will be.
    pub fn undo_join(&mut self, id: StateId) -> bool {
        let joins = id == self.undo.history.current() && self.undo.history.can_extend();
        self.undo.join = joins.then_some(id);
        joins
    }

    /// The command that the session's `undo_adjust` ran again failed: put the
    /// step back as it was.
    pub fn undo_adjust_cancel(&mut self) {
        let Some(step) = self.undo.adjusting.take() else { return };
        let current = self.undo.history.current();
        self.undo.history.set_label(current, step.label);
        self.reopen_step(step.project);
    }

    /// The keys typed for the open step.
    pub fn undo_keys(&mut self, text: String) {
        self.undo.history.keys(text);
    }

    /// Put back the project as the open step found it, leaving the history
    /// as it was. The session's `undo_discard` says when.
    pub fn undo_discard(&mut self) {
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
