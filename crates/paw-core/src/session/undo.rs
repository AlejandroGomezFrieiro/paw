//! The undo tree as the session uses it: moving between states, naming them,
//! what differs between two of them, and checkpoints written beside the
//! project file.
//!
//! The tree itself is [`crate::history`]. Every move here is an ordinary
//! replacement of the project by another snapshot; [`Session::flush`] then
//! sends the engine the difference, as it does after any edit, so moving
//! while the transport plays changes only what differs.
//!
//! ## Checkpoints on disk
//!
//! A checkpoint is a named state written to `<project>.checkpoints/` beside
//! the project file (`song.json` → `song.checkpoints/`), one file per
//! checkpoint: `<milliseconds since 1970>-<name, percent-encoded>.json`, so
//! listing them reads only the directory. The folder is made by the first
//! checkpoint written. A project with no file has no folder, and writing a
//! checkpoint for it fails.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::{FILE_VERSION, Session};
use crate::clock::ScheduleTime;
use crate::history::{self, History, StateId};
use crate::model::{Clip, ClipContent, CustomContent, DeviceInst, Id, Lane, Note, Notes, Project, Target, Track};

/// Readable lines in a diff, at most.
const DIFF_ITEMS: usize = 200;

/// How many steps the undo history keeps until told otherwise
/// (`paw.opt.undo_steps`).
const UNDO_LIMIT: usize = 1000;
/// And at most about this many bytes of what its steps changed
/// (`paw.opt.undo_memory`): a step that changes one note of a big clip keeps
/// a copy of the run of notes it changed (`model::Notes`).
const UNDO_BYTES: usize = 1 << 30;

/// An undo tree for a project, from `project` on, keeping at most `limit`
/// steps and about `bytes` bytes.
pub(super) fn new_history(project: Project, (limit, bytes): (usize, usize)) -> History<Project> {
    History::new(project, history::now(), limit).weigh_with(Project::weight_over, bytes)
}
/// The edits of the open undo step: how many, how many of them moved a
/// control, and which control if they all moved the same one.
#[derive(Default)]
pub(super) struct Sweep {
    pub edits: u32,
    pub moves: u32,
    pub key: Option<String>,
    pub mixed: bool,
}

/// Moves of one control closer together than this, in schedule time, are
/// one undo step.
pub(super) const SWEEP_GAP: Duration = Duration::from_millis(1000);

/// The undo tree and the step being made: what the project was at the last
/// step, how the open step's edits are joined, and whether a flush reports a
/// state put back.
pub(super) struct Undo {
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
    /// The undo file of the project: see `session/undo_file.rs`.
    pub file: super::undo_file::UndoFile,
    /// While a command is run again in place of its step
    /// ([`Session::undo_adjust`]): the step as it was, to put back when the
    /// command fails.
    pub adjusting: Option<Adjusting>,
}

/// A step that a command is being run again for.
pub(super) struct Adjusting {
    pub project: Project,
    pub label: Option<String>,
}

/// Whether the last step can be made again with other parameters.
#[derive(Serialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "lowercase")]
pub(crate) enum AdjustStatus {
    /// The project is now as it was before the step: run the command again.
    Ready,
    /// The current state is not the newest one (after `undo`).
    Old,
    /// The current step is not the one of the command to adjust.
    Other,
    /// The step was saved, named or kept, and cannot change.
    Kept,
}

/// What [`Session::undo_adjust`] found: `label` names the current step.
#[derive(Serialize)]
pub(crate) struct AdjustStart {
    pub status: AdjustStatus,
    pub label: Option<String>,
}

impl Undo {
    /// No steps yet: the tree starts at `project`.
    pub(super) fn new(project: &Project) -> Self {
        Self {
            checkpoint: project.clone(),
            history: new_history(project.clone(), (UNDO_LIMIT, UNDO_BYTES)),
            touched: false,
            sweep: Sweep::default(),
            last_sweep: None,
            restoring: false,
            join: None,
            edits: 0,
            adjusting: None,
            file: Default::default(),
        }
    }
}

#[derive(Serialize, Deserialize)]
struct CheckpointFile {
    version: u32,
    name: String,
    time: f64,
    project: Project,
}

impl Session {
    /// Close the open step, then move in the tree and take up the state
    /// moved to. None, and nothing changes, when there is nowhere to go.
    pub(super) fn move_in_history(
        &mut self,
        go: impl FnOnce(&mut History<Project>) -> Option<StateId>,
    ) -> Option<StateId> {
        // A trial under way is called off: what is undone is what was there.
        self.trial_end(false);
        // Edits made before the move report themselves as edits.
        self.flush();
        self.checkpoint();
        let (from, id) = self.doc.history_move(go)?;
        // A state still in the undo file is read now; one that cannot be
        // read is not gone to.
        if !self.undo_file_states(&[id]) {
            self.doc.undo.history.goto(from);
            return None;
        }
        if id != from {
            self.doc.take_current_state();
            self.files_there.forget();
        }
        Some(id)
    }




    /// Go to any state in the tree. False when there is no such state.
    pub(crate) fn undo_goto(&mut self, id: StateId) -> bool {
        self.move_in_history(|h| h.goto(id)).is_some()
    }

    /// `n` states later in the order they were made, earlier when negative.
    pub(crate) fn undo_step(&mut self, n: i64) -> Option<StateId> {
        self.move_in_history(|h| h.step(n))
    }

    /// To the state that was current `seconds` later, earlier when negative.
    pub(crate) fn undo_travel(&mut self, seconds: f64) -> Option<StateId> {
        self.move_in_history(|h| h.travel(seconds))
    }

    /// Name a state, or the current one (closing the open step first so the
    /// name covers what is on screen). An empty or absent name removes it.
    pub(crate) fn undo_name(&mut self, id: Option<StateId>, name: Option<String>) -> Result<StateId> {
        let id = match id {
            Some(id) => id,
            None => {
                self.checkpoint();
                self.doc.undo.history.current()
            }
        };
        if !self.doc.undo.history.set_name(id, name) {
            bail!("no state {id} in the undo tree");
        }
        Ok(id)
    }




    /// Whether the open step holds edits that the end of this turn will
    /// close as a step of their own: not during a trial, whose edits are
    /// one step made when it ends.
    pub(crate) fn undo_pending(&self) -> bool {
        self.doc.undo.touched && self.audition.trial.is_none()
    }

    /// Put back the project as the open step found it, leaving the history
    /// as it was: an edit refused before it became a step (`edit.before`).
    /// False when there is nothing to put back, or a trial is under way.
    pub(crate) fn undo_discard(&mut self) -> bool {
        if !self.undo_pending() {
            return false;
        }
        self.doc.undo_discard();
        true
    }

    /// Put the project back as it was before the last step, so that a
    /// command can run again and its new edits take the place of the step
    /// (`paw.commands.adjust`). `before` is the state (None: no command to adjust) the command started
    /// from: the step is the current one only if that is its parent and
    /// nothing hangs on it. `label` is the step's new name. The caller runs
    /// the command at once, and calls [`Document::undo_adjust_cancel`] if it
    /// fails.
    pub(crate) fn undo_adjust(&mut self, before: Option<StateId>, label: Option<String>) -> AdjustStart {
        self.checkpoint();
        let h = &self.doc.undo.history;
        let current = h.current();
        let state = h.get(current).expect("the current state is in the tree");
        let status = if !state.children.is_empty() {
            AdjustStatus::Old
        } else if before.is_none() || state.parent != before {
            AdjustStatus::Other
        } else if !h.can_extend() || self.audition.trial.is_some() {
            AdjustStatus::Kept
        } else {
            AdjustStatus::Ready
        };
        let old_label = state.label.clone();
        let parent = state.parent;
        let status = if status == AdjustStatus::Ready && !self.undo_file_states(&parent.into_iter().collect::<Vec<_>>()) {
            AdjustStatus::Kept
        } else {
            status
        };
        let h = &self.doc.undo.history;
        if status == AdjustStatus::Ready {
            let parent = parent.expect("a step has a parent");
            let parent = h.get(parent).expect("a parent is in the tree").snapshot.clone();
            let project = std::mem::replace(&mut self.doc.project, parent.clone());
            self.doc.undo.adjusting = Some(Adjusting { project, label: old_label.clone() });
            self.doc.undo.checkpoint = parent;
            self.doc.undo.history.set_label(current, label);
            self.doc.undo.touched = true;
            self.doc.undo.join = Some(current);
            self.doc.dirty = true;
            self.doc.undo.restoring = true;
            self.doc.undo.edits += 1;
        }
        AdjustStart { status, label: old_label }
    }



    /// What differs from state `a` to state `b`. `b` defaults to the current
    /// state and `a` to `b`'s parent, which is what `b`'s step changed.
    pub(crate) fn undo_diff(&mut self, a: Option<StateId>, b: Option<StateId>) -> Result<Value> {
        self.doc.undo.history.set_current_snapshot(self.doc.undo.checkpoint.clone());
        let b = b.unwrap_or(self.doc.undo.history.current());
        let to = self
            .doc.undo.history
            .get(b)
            .with_context(|| format!("no state {b} in the undo tree"))?;
        let a = a.or(to.parent).unwrap_or(b);
        for id in [a, b] {
            self.undo_file_state(id)?;
        }
        let to = self.doc.undo.history.get(b).expect("state b was found a moment ago");
        let from = self
            .doc.undo.history
            .get(a)
            .with_context(|| format!("no state {a} in the undo tree"))?;
        let mut value = diff(&from.snapshot, &to.snapshot);
        value["from"] = json!(a);
        value["to"] = json!(b);
        Ok(value)
    }

    /// The project as it was in state `id` (the current one by default), as
    /// a project file holds it, for comparing it with another version.
    pub(crate) fn undo_project(&mut self, id: Option<StateId>) -> Result<Project> {
        self.doc.undo.history.set_current_snapshot(self.doc.undo.checkpoint.clone());
        let id = id.unwrap_or(self.doc.undo.history.current());
        self.undo_file_state(id)?;
        let state = self
            .doc.undo.history
            .get(id)
            .with_context(|| format!("no state {id} in the undo tree"))?;
        Ok(state.snapshot.clone())
    }

    // --- checkpoints on disk -------------------------------------------------

    /// Where this project's checkpoints go, or None for a project with no file.
    pub(crate) fn checkpoint_dir(&self) -> Option<PathBuf> {
        self.path.as_ref().map(|p| p.with_extension("checkpoints"))
    }

    /// Write a state beside the project under `name`, and name it so in the
    /// tree: the current one (with the open step closed) unless `id` says
    /// which.
    pub(crate) fn checkpoint_write(&mut self, name: &str, id: Option<StateId>) -> Result<Value> {
        let name = name.trim();
        if name.is_empty() {
            bail!("a checkpoint needs a name");
        }
        let dir = self.checkpoint_dir().context(
            "the project has no file yet, so there is nowhere to keep checkpoints: save it first",
        )?;
        let id = self.undo_name(id, Some(name.to_string()))?;
        let project = if id == self.doc.undo.history.current() {
            // As saving does: what the plugins hold now goes with it.
            self.capture_states();
            self.doc.project.clone()
        } else {
            self.undo_file_state(id)?;
            self.doc.undo.history.get(id).unwrap().snapshot.clone()
        };
        let time = history::now();
        let file = CheckpointFile {
            version: FILE_VERSION,
            name: name.to_string(),
            time,
            project,
        };
        std::fs::create_dir_all(&dir).with_context(|| format!("creating {}", dir.display()))?;
        // The files are listed in the order of the number they start with,
        // so one made in the same millisecond as the last gets the next number.
        let newest = std::fs::read_dir(&dir)
            .into_iter()
            .flatten()
            .flatten()
            .filter_map(|entry| {
                let name = entry.file_name().to_string_lossy().into_owned();
                name.split_once('-')?.0.parse::<u64>().ok()
            })
            .max();
        let ms = ((time * 1000.0) as u64).max(newest.map_or(0, |ms| ms + 1));
        let path = dir.join(format!("{ms}-{}.json", encode(name)));
        crate::safe::write_file(&path, serde_json::to_string(&file)?.as_bytes(), false)?;
        Ok(json!({ "file": path, "name": name, "time": time, "state": id }))
    }

    /// The checkpoints kept beside the project, oldest first.
    pub(crate) fn checkpoint_list(&self) -> Value {
        let mut out: Vec<(f64, String, PathBuf)> = Vec::new();
        if let Some(dir) = self.checkpoint_dir()
            && let Ok(entries) = std::fs::read_dir(&dir)
        {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().is_none_or(|e| e != "json") {
                    continue;
                }
                let stem = path.file_stem().unwrap_or_default().to_string_lossy();
                let Some((ms, name)) = stem.split_once('-') else {
                    continue;
                };
                let Ok(ms) = ms.parse::<u64>() else { continue };
                out.push((ms as f64 / 1000.0, decode(name), path));
            }
        }
        out.sort_by(|a, b| a.0.total_cmp(&b.0));
        Value::Array(
            out.into_iter()
                .map(|(time, name, file)| json!({ "file": file, "name": name, "time": time }))
                .collect(),
        )
    }

    fn checkpoint_path(&self, file: &str) -> Result<PathBuf> {
        let path = Path::new(file);
        if path.is_absolute() || path.exists() {
            return Ok(path.to_path_buf());
        }
        let dir = self
            .checkpoint_dir()
            .context("the project has no file, so it has no checkpoints")?;
        Ok(dir.join(path))
    }

    /// Make a checkpoint written earlier the current state, as a new step
    /// below the current one (so undo comes back), named as the checkpoint.
    /// `file` is a path from [`checkpoint_list`](Self::checkpoint_list), or a
    /// file name in the checkpoint folder.
    pub(crate) fn checkpoint_restore(&mut self, file: &str) -> Result<StateId> {
        let path = self.checkpoint_path(file)?;
        let text = std::fs::read_to_string(&path)
            .with_context(|| format!("reading {}", path.display()))?;
        let file: CheckpointFile =
            serde_json::from_str(&text).with_context(|| format!("parsing {}", path.display()))?;
        if file.version > FILE_VERSION {
            bail!("{} was written by a newer version", path.display());
        }
        let mut project = file.project;
        share_with(&mut project, &self.doc.project);
        self.flush();
        self.checkpoint();
        self.doc.undo.history.clear_labels();
        self.doc.undo.history
            .label(Some(format!("checkpoint.restore {}", file.name)));
        self.doc.next_id = self.doc.next_id.max(project.max_id() + 1);
        self.doc.edit(|p| {
            *p = project;
            Ok(())
        })?;
        self.doc.undo.restoring = true;
        self.checkpoint();
        let id = self.doc.undo.history.current();
        self.doc.undo.history.set_name(id, Some(file.name));
        Ok(id)
    }

    /// Delete a checkpoint file.
    pub(crate) fn checkpoint_delete(&mut self, file: &str) -> Result<()> {
        let path = self.checkpoint_path(file)?;
        std::fs::remove_file(&path).with_context(|| format!("deleting {}", path.display()))
    }
}

/// A name as part of a file name: letters, digits, `_` and `.` stay, a space
/// becomes `+`, and every other byte `%XX`.
fn encode(name: &str) -> String {
    let mut out = String::new();
    for byte in name.bytes().take(120) {
        match byte {
            b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'_' | b'.' => out.push(byte as char),
            b' ' => out.push('+'),
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

fn decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < bytes.len() => {
                let hex = std::str::from_utf8(&bytes[i + 1..i + 3]).unwrap_or("");
                match u8::from_str_radix(hex, 16) {
                    Ok(b) => {
                        out.push(b);
                        i += 2;
                    }
                    Err(_) => out.push(b'%'),
                }
            }
            b => out.push(b),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn same<T: Serialize>(a: &T, b: &T) -> bool {
    match (serde_json::to_value(a), serde_json::to_value(b)) {
        (Ok(a), Ok(b)) => a == b,
        _ => false,
    }
}

/// Reuse `old`'s tracks, devices, clips and lanes wherever `new` has the same
/// ones, so that the engine is only sent what really differs.
pub(super) fn share_with(new: &mut Project, old: &Project) {
    let tracks: HashMap<Id, &Arc<Track>> = old.all_tracks().map(|t| (t.id, t)).collect();
    let share_track = |track: &mut Arc<Track>| {
        let Some(prev) = tracks.get(&track.id) else {
            return;
        };
        {
            let t = Arc::make_mut(track);
            fn share<'a, T: Serialize + Clone + 'a>(
                list: impl IntoIterator<Item = &'a mut Arc<T>>,
                prev: impl IntoIterator<Item = &'a Arc<T>> + Copy,
                id: impl Fn(&T) -> Id,
            ) {
                for item in list {
                    if let Some(p) = prev.into_iter().find(|p| id(p) == id(item))
                        && same(p.as_ref(), item.as_ref())
                    {
                        *item = p.clone();
                    }
                }
            }
            share(&mut t.devices, &prev.devices, |d| d.id);
            share(&mut t.clips, &prev.clips, |c| c.id);
            share(&mut t.lanes, &prev.lanes, |l| l.id);
        }
        if same(track.as_ref(), prev.as_ref()) {
            *track = (*prev).clone();
        }
    };
    share_track(&mut new.master);
    for track in &mut new.tracks {
        share_track(track);
    }
}

// --- diff --------------------------------------------------------------------

#[derive(Default, Serialize)]
struct Count {
    added: usize,
    removed: usize,
    changed: usize,
}

impl Count {
    fn total(&self) -> usize {
        self.added + self.removed + self.changed
    }
}

/// What differs between two projects, as [`diff`] reports it. Each step
/// compares one area (the project's own fields, tracks, devices, clips with
/// their notes, automation lanes) and adds its lines to `items` in that
/// order.
#[derive(Default, Serialize)]
struct Diff {
    tracks: Count,
    devices: Count,
    clips: Count,
    notes: Count,
    lanes: Count,
    project: Vec<&'static str>,
    items: Vec<String>,
    /// Nothing differs.
    same: bool,
    /// Lines left out after [`DIFF_ITEMS`].
    #[serde(skip)]
    more: usize,
}

/// Where every device, clip or lane of a project is: by its id, the track
/// holding it, and it.
type Index<'p, T> = HashMap<Id, (&'p Track, &'p Arc<T>)>;

fn index<'p, T: 'p, I: IntoIterator<Item = &'p Arc<T>>>(
    p: &'p Project,
    list: impl Fn(&'p Track) -> I,
    id: impl Fn(&T) -> Id,
) -> Index<'p, T> {
    p.all_tracks()
        .flat_map(|t| list(t).into_iter().map(move |x| (t.as_ref(), x)))
        .map(|(t, x)| (id(x), (t, x)))
        .collect()
}

/// A thing on a track that the diff matches by id between two projects:
/// a device, a clip or an automation lane.
trait Part {
    /// Its count in the diff.
    fn count(d: &mut Diff) -> &mut Count;
    /// What a line calls it: "device synth", "clip verse", "pan automation".
    fn label(&self) -> String;
    /// What changed from `prev`, on `was_on`, to `self`, on `track`, as
    /// words for its line, or `None` when nothing did. Counts the notes of a
    /// clip into `d`.
    fn changes(&self, prev: &Self, was_on: &Track, track: &Track, d: &mut Diff)
    -> Option<Vec<String>>;
}

impl Part for DeviceInst {
    fn count(d: &mut Diff) -> &mut Count {
        &mut d.devices
    }

    fn label(&self) -> String {
        format!("device {}", self.kind)
    }

    fn changes(&self, prev: &Self, was_on: &Track, track: &Track, _: &mut Diff) -> Option<Vec<String>> {
        if std::ptr::eq(prev, self) && was_on.id == track.id {
            return None;
        }
        let mut fields = moved(was_on, track);
        if prev.bypass != self.bypass {
            fields.push("bypass".into());
        }
        let keys: std::collections::BTreeSet<&String> =
            prev.params.keys().chain(self.params.keys()).collect();
        for key in keys {
            if prev.params.get(key) != self.params.get(key) {
                fields.push(key.clone());
            }
        }
        if prev.state != self.state {
            fields.push("plugin state".into());
        }
        if prev.meta != self.meta {
            fields.push("meta".into());
        }
        (!fields.is_empty()).then_some(fields)
    }
}

impl Part for Clip {
    fn count(d: &mut Diff) -> &mut Count {
        &mut d.clips
    }

    fn label(&self) -> String {
        if self.name.is_empty() {
            format!("clip {}", self.id)
        } else {
            format!("clip {}", self.name)
        }
    }

    fn changes(&self, prev: &Self, was_on: &Track, track: &Track, d: &mut Diff) -> Option<Vec<String>> {
        if std::ptr::eq(prev, self) && was_on.id == track.id {
            return None;
        }
        let mut fields = moved(was_on, track);
        for (field, differs) in [
            ("name", prev.name != self.name),
            ("start", prev.start != self.start),
            ("length", prev.length != self.length),
            ("muted", prev.muted != self.muted),
            ("meta", prev.meta != self.meta),
        ] {
            if differs {
                fields.push(field.into());
            }
        }
        match (&prev.content, &self.content) {
            (ClipContent::Midi { notes: was, .. }, ClipContent::Midi { notes: now, .. }) => {
                let n = diff_notes(was, now);
                if let Some(line) = notes_line(&n) {
                    fields.push(line);
                }
                d.notes.added += n.added;
                d.notes.removed += n.removed;
                d.notes.changed += n.changed;
            }
            (ClipContent::Custom(was), ClipContent::Custom(now)) if was.kind == now.kind => {
                let changed = custom_changes(was, now);
                if !changed.is_empty() {
                    fields.push(format!("kind {}: {}", now.kind.as_str(), changed.join(", ")));
                }
            }
            (was, now) if was.kind() != now.kind() => fields.push(format!("kind {} to {}", was.kind(), now.kind())),
            (was, now) if !same(was, now) => fields.push("audio".into()),
            _ => {}
        }
        (!fields.is_empty()).then_some(fields)
    }
}

impl Part for Lane {
    fn count(d: &mut Diff) -> &mut Count {
        &mut d.lanes
    }

    fn label(&self) -> String {
        let target = match &self.target {
            Target::Volume => "volume",
            Target::Pan => "pan",
            Target::Param { param, .. } => param,
            Target::State { .. } => "state",
        };
        format!("{target} automation")
    }

    /// A lane's line names no fields, and a lane that only moved to another
    /// track is not changed.
    fn changes(&self, prev: &Self, _: &Track, _: &Track, _: &mut Diff) -> Option<Vec<String>> {
        let differs = !std::ptr::eq(prev, self)
            && (prev.points != self.points
                || prev.shapes != self.shapes
                || prev.states != self.states
                || prev.enabled != self.enabled
                || prev.target != self.target);
        differs.then(Vec::new)
    }
}

/// Which parts of a custom clip differ, by name: its data, sound, signals
/// and media, never the data itself.
fn custom_changes(was: &CustomContent, now: &CustomContent) -> Vec<&'static str> {
    [
        ("data", !same(&was.data, &now.data)),
        ("sound", !same(&was.sound, &now.sound)),
        ("signals", !same(&was.signals, &now.signals)),
        ("media", !same(&was.media, &now.media)),
        ("timeline", was.timeline != now.timeline || was.offset != now.offset),
    ]
    .into_iter()
    .filter_map(|(part, differs)| differs.then_some(part))
    .collect()
}

/// "moved from track X" when a device or clip changed tracks.
fn moved(was_on: &Track, track: &Track) -> Vec<String> {
    if was_on.id != track.id {
        vec![format!("moved from {}", track_name(was_on))]
    } else {
        Vec::new()
    }
}

/// "2 notes added, 1 note removed", or `None` when no note differs.
fn notes_line(n: &Count) -> Option<String> {
    let mut parts = Vec::new();
    for (count, what) in [(n.added, "added"), (n.removed, "removed"), (n.changed, "changed")] {
        if count > 0 {
            parts.push(format!("{count} note{} {what}", if count == 1 { "" } else { "s" }));
        }
    }
    (!parts.is_empty()).then(|| parts.join(", "))
}

fn track_name(t: &Track) -> String {
    if t.id == crate::model::MASTER_ID {
        "the master track".into()
    } else {
        format!(
            "track {}",
            if t.name.is_empty() {
                t.id.to_string()
            } else {
                t.name.clone()
            }
        )
    }
}

/// The fields of `track` that differ from `prev`, by name.
fn track_changes(prev: &Track, track: &Track) -> Vec<&'static str> {
    let checks: [(&str, bool); 14] = [
        ("name", prev.name != track.name),
        ("volume", prev.volume != track.volume),
        ("pan", prev.pan != track.pan),
        ("mute", prev.mute != track.mute),
        ("solo", prev.solo != track.solo),
        ("armed", prev.armed != track.armed),
        ("output", prev.output != track.output),
        ("sends", prev.sends != track.sends),
        ("color", prev.color != track.color),
        ("meta", prev.meta != track.meta),
        ("input", prev.input != track.input),
        ("monitor", prev.monitor != track.monitor),
        ("midi_input", prev.midi_input != track.midi_input),
        ("height", prev.height != track.height),
    ];
    let mut fields: Vec<&str> = checks
        .into_iter()
        .filter_map(|(field, differs)| differs.then_some(field))
        .collect();
    // The same devices in another order.
    let order = |t: &Track| t.devices.iter().map(|d| d.id).collect::<Vec<_>>();
    if order(prev) != order(track)
        && order(prev)
            .iter()
            .all(|i| track.devices.iter().any(|d| d.id == *i))
        && order(track)
            .iter()
            .all(|i| prev.devices.iter().any(|d| d.id == *i))
    {
        fields.push("device order");
    }
    fields
}

impl Diff {
    fn item(&mut self, line: String) {
        if self.items.len() < DIFF_ITEMS {
            self.items.push(line);
        } else {
            self.more += 1;
        }
    }

    /// The project's own fields: name, tempo, time signature, key, meta and
    /// the order of the tracks both have.
    fn project(&mut self, a: &Project, b: &Project) {
        if a.name != b.name {
            self.project.push("name");
        }
        if a.tempo != b.tempo || a.tempo_ramp != b.tempo_ramp || a.tempo_changes != b.tempo_changes {
            self.project.push("tempo");
        }
        if (a.sig_num, a.sig_den) != (b.sig_num, b.sig_den) || a.sig_changes != b.sig_changes {
            self.project.push("time signature");
        }
        if a.key != b.key {
            self.project.push("key");
        }
        if a.meta != b.meta {
            self.project.push("meta");
        }
        if a.nests != b.nests {
            self.project.push("subprojects");
        }
        let order = |p: &Project| p.tracks.iter().map(|t| t.id).collect::<Vec<_>>();
        if order(a) != order(b) {
            let ids_a: std::collections::HashSet<Id> = order(a).into_iter().collect();
            let ids_b: std::collections::HashSet<Id> = order(b).into_iter().collect();
            let common_a: Vec<Id> = order(a).into_iter().filter(|i| ids_b.contains(i)).collect();
            let common_b: Vec<Id> = order(b).into_iter().filter(|i| ids_a.contains(i)).collect();
            if common_a != common_b {
                self.project.push("track order");
            }
        }
        if !self.project.is_empty() {
            let line = format!("~ project: {}", self.project.join(", "));
            self.item(line);
        }
    }

    /// Tracks added and changed, in `b`'s order, then those removed, in
    /// `a`'s.
    fn tracks(&mut self, a: &Project, b: &Project) {
        let tracks_a: HashMap<Id, &Arc<Track>> = a.all_tracks().map(|t| (t.id, t)).collect();
        let tracks_b: HashMap<Id, &Arc<Track>> = b.all_tracks().map(|t| (t.id, t)).collect();
        for track in b.all_tracks() {
            let Some(prev) = tracks_a.get(&track.id) else {
                self.tracks.added += 1;
                self.item(format!("+ {}", track_name(track)));
                continue;
            };
            if Arc::ptr_eq(prev, track) {
                continue;
            }
            let fields = track_changes(prev, track);
            if !fields.is_empty() {
                self.tracks.changed += 1;
                let name = if prev.name != track.name {
                    format!("{} (was {})", track_name(track), prev.name)
                } else {
                    track_name(track)
                };
                self.item(format!("~ {name}: {}", fields.join(", ")));
            }
        }
        for track in a.all_tracks() {
            if !tracks_b.contains_key(&track.id) {
                self.tracks.removed += 1;
                self.item(format!("- {}", track_name(track)));
            }
        }
    }

    /// The parts of one kind added and changed, by id, then those removed.
    fn parts<T: Part>(&mut self, a: &Index<T>, b: &Index<T>) {
        for (id, (track, now)) in sorted(b) {
            let line = match a.get(&id) {
                None => {
                    T::count(self).added += 1;
                    format!("+ {} on {}", now.label(), track_name(track))
                }
                Some((was_on, prev)) => match now.changes(prev, was_on, track, self) {
                    None => continue,
                    Some(fields) => {
                        T::count(self).changed += 1;
                        let line = format!("~ {} on {}", now.label(), track_name(track));
                        if fields.is_empty() {
                            line
                        } else {
                            format!("{line}: {}", fields.join(", "))
                        }
                    }
                },
            };
            self.item(line);
        }
        for (id, (track, gone)) in sorted(a) {
            if !b.contains_key(&id) {
                T::count(self).removed += 1;
                self.item(format!("- {} on {}", gone.label(), track_name(track)));
            }
        }
    }

    fn finish(mut self) -> Value {
        if self.more > 0 {
            let more = self.more;
            self.items.push(format!("… and {more} more"));
        }
        self.same = self.project.is_empty()
            && [&self.tracks, &self.devices, &self.clips, &self.notes, &self.lanes]
                .iter()
                .all(|c| c.total() == 0);
        serde_json::to_value(self).expect("a diff is plain data")
    }
}

/// What differs from `a` to `b`, counted per kind, with a line of text for
/// each thing added, removed or changed.
///
/// Notes are compared within clips present in both: a note at the same start
/// and pitch with anything else different is changed, a note that moved in
/// time or pitch is one removed and one added. Notes of clips added or
/// removed are not counted.
pub(super) fn diff(a: &Project, b: &Project) -> Value {
    let mut d = Diff::default();
    d.project(a, b);
    d.tracks(a, b);
    d.parts(&index(a, |t| &t.devices, |x| x.id), &index(b, |t| &t.devices, |x| x.id));
    d.parts(&index(a, |t| &t.clips, |x| x.id), &index(b, |t| &t.clips, |x| x.id));
    d.parts(&index(a, |t| &t.lanes, |x| x.id), &index(b, |t| &t.lanes, |x| x.id));
    d.finish()
}

fn sorted<T>(map: &HashMap<Id, T>) -> Vec<(Id, &T)>
where
    T: Copy,
{
    let mut out: Vec<(Id, &T)> = map.iter().map(|(id, x)| (*id, x)).collect();
    out.sort_by_key(|(id, _)| *id);
    out
}

/// Two notes that sound the same and carry the same data: their ids may
/// differ (one state was written before notes had them).
fn same_note(a: &Note, b: &Note) -> bool {
    a.start == b.start && a.length == b.length && a.pitch == b.pitch && a.velocity == b.velocity && a.meta == b.meta
}

fn diff_notes(was: &Notes, now: &Notes) -> Count {
    let mut count = Count::default();
    let mut left: HashMap<(u64, u8), Vec<&Note>> = HashMap::new();
    for note in was {
        left.entry((note.start.to_bits(), note.pitch))
            .or_default()
            .push(note);
    }
    let mut unmatched = Vec::new();
    // Exact matches first, so a changed note is not paired with an unchanged one.
    for note in now {
        let key = (note.start.to_bits(), note.pitch);
        match left
            .get_mut(&key)
            .and_then(|list| list.iter().position(|n| same_note(n, note)).map(|i| list.remove(i)))
        {
            Some(_) => {}
            None => unmatched.push(key),
        }
    }
    for key in unmatched {
        match left.get_mut(&key).and_then(|list| list.pop()) {
            Some(_) => count.changed += 1,
            None => count.added += 1,
        }
    }
    count.removed = left.values().map(Vec::len).sum();
    count
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_survive_a_file_name() {
        for name in [
            "before the bridge",
            "v2/final?",
            "ünïcode — ok",
            "a+b%c",
            "x_y.z",
        ] {
            assert_eq!(decode(&encode(name)), name);
        }
        assert_eq!(encode("before the bridge"), "before+the+bridge");
    }

    #[test]
    fn diff_counts_each_kind() {
        let mut a = Project::default();
        let mut track = Track::new(1);
        track.name = "Bass".into();
        track.devices.push(Arc::new(DeviceInst {
            id: 2,
            kind: "synth".into(),
            bypass: false,
            params: Default::default(),
            state: None,
            meta: Default::default(),
            loaded: 0,
            name: None,
            offline: false,
            sidechain: None,
            sidechain_pre: false,
            outputs: Default::default(),
            param_ids: Default::default(),
            files: Default::default(),
        }));
        let note = |start: f64, pitch: u8| Note {
            start,
            length: 1.0,
            pitch,
            velocity: 100,
            meta: Default::default(),
            id: 0,
            attr: None,
        };
        track.clips.push(Arc::new(Clip {
            timebase: None,
            stretch: 1.0,
            pitch: 0.0,
            stretch_mode: Default::default(),
            source_tempo: None,
            warp: Vec::new(),
            formants: false,
            looped: false,
            loop_length: None,
            loop_start: 0.0,
            id: 3,
            name: "verse".into(),
            start: 0.0,
            length: 4.0,
            muted: false,
            content: ClipContent::Midi {
                notes: vec![note(0.0, 60), note(1.0, 62), note(2.0, 64)].into(),
                controls: Vec::new(),
            },
            fade_in: 0.0,
            fade_out: 0.0,
            meta: Default::default(),
            source: None,
            origin: None,
            link: None,
            overrides: Default::default(),
        }));
        let custom: Clip = serde_json::from_value(json!({
            "id": 9, "name": "cue", "start": 8.0, "length": 2.0, "muted": false,
            "content": { "kind": "custom", "type": "comment",
                "data": { "json": "{\"text\":\"one\"}" } },
        }))
        .unwrap();
        track.clips.push(Arc::new(custom));
        let mut eq = (*track.devices[0]).clone();
        eq.id = 6;
        eq.kind = "eq".into();
        track.devices.push(Arc::new(eq));
        let lane = |id: Id, target: Target| Lane {
            id,
            target,
            enabled: true,
            points: vec![(0.0, 0.0)],
            shapes: Vec::new(),
            states: Vec::new(),
        };
        track.lanes.push(Arc::new(lane(5, Target::Volume)));
        a.tracks.push(Arc::new(track));
        let empty = diff(&a, &a);
        assert_eq!(empty["same"], json!(true));

        let mut b = a.clone();
        b.tempo = 100.0;
        let mut added = Track::new(4);
        added.lanes.push(Arc::new(lane(8, Target::Pan)));
        b.tracks.push(Arc::new(added));
        {
            let t = Arc::make_mut(&mut b.tracks[0]);
            t.name = "Low".into();
            t.volume = -6.0;
            t.devices.remove(1);
            Arc::make_mut(&mut t.lanes[0]).points.push((4.0, -6.0));
            Arc::make_mut(&mut t.devices[0])
                .params
                .insert("cutoff".into(), 500.0);
            let clip = Arc::make_mut(&mut t.clips[0]);
            let ClipContent::Midi { notes, .. } = &mut clip.content else {
                unreachable!()
            };
            notes[1].velocity = 50; // changed
            notes.remove(2); // removed
            notes.push(note(3.0, 67)); // added
            notes.push(note(3.5, 69)); // added
            let cue = Arc::make_mut(&mut t.clips[1]);
            let ClipContent::Custom(custom) = &mut cue.content else {
                unreachable!()
            };
            custom.data = serde_json::from_value(json!({ "json": "{\"text\":\"two\"}" })).unwrap();
        }
        let d = diff(&a, &b);
        assert_eq!(
            d,
            json!({
                "same": false,
                "project": ["tempo"],
                "tracks": {"added": 1, "removed": 0, "changed": 1},
                "devices": {"added": 0, "removed": 1, "changed": 1},
                "clips": {"added": 0, "removed": 0, "changed": 2},
                "notes": {"added": 2, "removed": 1, "changed": 1},
                "lanes": {"added": 1, "removed": 0, "changed": 1},
                "items": [
                    "~ project: tempo",
                    "~ track Low (was Bass): name, volume",
                    "+ track 4",
                    "~ device synth on track Low: cutoff",
                    "- device eq on track Bass",
                    "~ clip verse on track Low: 2 notes added, 1 note removed, 1 note changed",
                    "~ clip cue on track Low: kind comment: data",
                    "~ volume automation on track Low",
                    "+ pan automation on track 4",
                ],
            })
        );
        let back = diff(&b, &a);
        assert_eq!(back["tracks"]["removed"], json!(1));
        assert_eq!(
            back["items"],
            json!([
                "~ project: tempo",
                "~ track Bass (was Low): name, volume",
                "- track 4",
                "~ device synth on track Bass: cutoff",
                "+ device eq on track Bass",
                "~ clip verse on track Bass: 1 note added, 2 notes removed, 1 note changed",
                "~ clip cue on track Bass: kind comment: data",
                "~ volume automation on track Bass",
                "- pan automation on track 4",
            ])
        );
    }

    #[test]
    fn sharing_reuses_what_is_unchanged() {
        let mut a = Project::default();
        let mut t = Track::new(1);
        t.name = "A".into();
        a.tracks.push(Arc::new(t));
        let mut u = Track::new(2);
        u.name = "B".into();
        a.tracks.push(Arc::new(u));
        let text = serde_json::to_string(&a).unwrap();
        let mut b: Project = serde_json::from_str(&text).unwrap();
        Arc::make_mut(&mut b.tracks[1]).volume = -3.0;
        share_with(&mut b, &a);
        assert!(Arc::ptr_eq(&a.tracks[0], &b.tracks[0]));
        assert!(!Arc::ptr_eq(&a.tracks[1], &b.tracks[1]));
        assert!(Arc::ptr_eq(&a.master, &b.master));
    }
}
