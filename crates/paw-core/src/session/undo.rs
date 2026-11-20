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
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use super::{FILE_VERSION, Session};
use crate::history::{self, History, StateId};
use crate::model::{ClipContent, Id, Note, Notes, Project, Track};

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

/// Moves of one control closer together than this are one undo step.
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
    /// The control the last undo step moved, when it did nothing else.
    pub last_sweep: Option<(String, Instant, StateId)>,
    /// The next flush reports a state put back (undo, redo, a file opened)
    /// rather than an edit: its events carry `restored = true`.
    pub restoring: bool,
    /// The undo state the edits of this turn join instead of making a step
    /// of their own, set by `undo_join`.
    pub join: Option<StateId>,
    /// Counts every change to the project, undo and redo included.
    pub edits: u64,
}

impl Undo {
    /// No steps yet: the tree starts at `project`.
    pub fn new(project: &Project) -> Self {
        Self {
            checkpoint: project.clone(),
            history: new_history(project.clone(), (UNDO_LIMIT, UNDO_BYTES)),
            touched: false,
            sweep: Sweep::default(),
            last_sweep: None,
            restoring: false,
            join: None,
            edits: 0,
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
        // Bookkeeping since the step closed (plugin parameters taken over by
        // their editors, recordings moved beside the project) stays with it.
        self.undo.history.set_current_snapshot(self.undo.checkpoint.clone());
        let from = self.undo.history.current();
        let id = go(&mut self.undo.history)?;
        if id != from {
            self.project = self.undo.history.current_snapshot().clone();
            self.undo.checkpoint = self.project.clone();
            self.dirty = true;
            self.undo.restoring = true;
            self.undo.edits += 1;
        }
        Some(id)
    }

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
            && !(16 << 20..=1 << 40).contains(&bytes)
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

    /// Go to any state in the tree. False when there is no such state.
    pub fn undo_goto(&mut self, id: StateId) -> bool {
        self.move_in_history(|h| h.goto(id)).is_some()
    }

    /// `n` states later in the order they were made, earlier when negative.
    pub fn undo_step(&mut self, n: i64) -> Option<StateId> {
        self.move_in_history(|h| h.step(n))
    }

    /// To the state that was current `seconds` later, earlier when negative.
    pub fn undo_travel(&mut self, seconds: f64) -> Option<StateId> {
        self.move_in_history(|h| h.travel(seconds))
    }

    /// Name a state, or the current one (closing the open step first so the
    /// name covers what is on screen). An empty or absent name removes it.
    pub fn undo_name(&mut self, id: Option<StateId>, name: Option<String>) -> Result<StateId> {
        let id = match id {
            Some(id) => id,
            None => {
                self.checkpoint();
                self.undo.history.current()
            }
        };
        if !self.undo.history.set_name(id, name) {
            bail!("no state {id} in the undo tree");
        }
        Ok(id)
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

    /// Whether the open step holds edits that the end of this turn will
    /// close as a step of their own: not during a trial, whose edits are
    /// one step made when it ends.
    pub fn undo_pending(&self) -> bool {
        self.undo.touched && self.audition.trial.is_none()
    }

    /// Put back the project as the open step found it, leaving the history
    /// as it was: an edit refused before it became a step (`edit.before`).
    /// False when there is nothing to put back, or a trial is under way.
    pub fn undo_discard(&mut self) -> bool {
        if !self.undo_pending() {
            return false;
        }
        self.project = self.undo.checkpoint.clone();
        self.undo.touched = false;
        self.dirty = true;
        self.undo.restoring = true;
        self.undo.edits += 1;
        self.undo.sweep = Default::default();
        self.undo.join = None;
        self.undo.history.clear_labels();
        true
    }

    /// The keys typed for the open step.
    pub fn undo_keys(&mut self, text: String) {
        self.undo.history.keys(text);
    }

    /// What differs from state `a` to state `b`. `b` defaults to the current
    /// state and `a` to `b`'s parent, which is what `b`'s step changed.
    pub fn undo_diff(&mut self, a: Option<StateId>, b: Option<StateId>) -> Result<Value> {
        self.undo.history.set_current_snapshot(self.undo.checkpoint.clone());
        let b = b.unwrap_or(self.undo.history.current());
        let to = self
            .undo.history
            .get(b)
            .with_context(|| format!("no state {b} in the undo tree"))?;
        let a = a.or(to.parent).unwrap_or(b);
        let from = self
            .undo.history
            .get(a)
            .with_context(|| format!("no state {a} in the undo tree"))?;
        let mut value = diff(&from.snapshot, &to.snapshot);
        value["from"] = json!(a);
        value["to"] = json!(b);
        Ok(value)
    }

    /// The project as it was in state `id` (the current one by default), as
    /// a project file holds it, for comparing it with another version.
    pub fn undo_project(&mut self, id: Option<StateId>) -> Result<Project> {
        self.undo.history.set_current_snapshot(self.undo.checkpoint.clone());
        let id = id.unwrap_or(self.undo.history.current());
        let state = self
            .undo.history
            .get(id)
            .with_context(|| format!("no state {id} in the undo tree"))?;
        Ok(state.snapshot.clone())
    }

    // --- checkpoints on disk -------------------------------------------------

    /// Where this project's checkpoints go, or None for a project with no file.
    pub fn checkpoint_dir(&self) -> Option<PathBuf> {
        self.path.as_ref().map(|p| p.with_extension("checkpoints"))
    }

    /// Write a state beside the project under `name`, and name it so in the
    /// tree: the current one (with the open step closed) unless `id` says
    /// which.
    pub fn checkpoint_write(&mut self, name: &str, id: Option<StateId>) -> Result<Value> {
        let name = name.trim();
        if name.is_empty() {
            bail!("a checkpoint needs a name");
        }
        let dir = self.checkpoint_dir().context(
            "the project has no file yet, so there is nowhere to keep checkpoints: save it first",
        )?;
        let id = self.undo_name(id, Some(name.to_string()))?;
        let project = if id == self.undo.history.current() {
            // As saving does: what the plugins hold now goes with it.
            self.capture_states();
            self.project.clone()
        } else {
            self.undo.history.get(id).unwrap().snapshot.clone()
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
    pub fn checkpoint_list(&self) -> Value {
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
    pub fn checkpoint_restore(&mut self, file: &str) -> Result<StateId> {
        let path = self.checkpoint_path(file)?;
        let text = std::fs::read_to_string(&path)
            .with_context(|| format!("reading {}", path.display()))?;
        let file: CheckpointFile =
            serde_json::from_str(&text).with_context(|| format!("parsing {}", path.display()))?;
        if file.version > FILE_VERSION {
            bail!("{} was written by a newer version", path.display());
        }
        let mut project = file.project;
        share_with(&mut project, &self.project);
        self.flush();
        self.checkpoint();
        self.undo.history.clear_labels();
        self.undo.history
            .label(Some(format!("checkpoint.restore {}", file.name)));
        self.next_id = self.next_id.max(project.max_id() + 1);
        self.edit(|p| {
            *p = project;
            Ok(())
        })?;
        self.undo.restoring = true;
        self.checkpoint();
        let id = self.undo.history.current();
        self.undo.history.set_name(id, Some(file.name));
        Ok(id)
    }

    /// Delete a checkpoint file.
    pub fn checkpoint_delete(&mut self, file: &str) -> Result<()> {
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
fn share_with(new: &mut Project, old: &Project) {
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

#[derive(Default)]
struct Diff {
    tracks: Count,
    devices: Count,
    clips: Count,
    notes: Count,
    lanes: Count,
    project: Vec<&'static str>,
    items: Vec<String>,
    more: usize,
}

impl Diff {
    fn item(&mut self, line: String) {
        if self.items.len() < DIFF_ITEMS {
            self.items.push(line);
        } else {
            self.more += 1;
        }
    }
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

/// What differs from `a` to `b`, counted per kind, with a line of text for
/// each thing added, removed or changed.
///
/// Notes are compared within clips present in both: a note at the same start
/// and pitch with anything else different is changed, a note that moved in
/// time or pitch is one removed and one added. Notes of clips added or
/// removed are not counted.
pub fn diff(a: &Project, b: &Project) -> Value {
    let mut d = Diff::default();
    if a.name != b.name {
        d.project.push("name");
    }
    if a.tempo != b.tempo || a.tempo_ramp != b.tempo_ramp || a.tempo_changes != b.tempo_changes {
        d.project.push("tempo");
    }
    if (a.sig_num, a.sig_den) != (b.sig_num, b.sig_den) || a.sig_changes != b.sig_changes {
        d.project.push("time signature");
    }
    if a.key != b.key {
        d.project.push("key");
    }
    if a.meta != b.meta {
        d.project.push("meta");
    }
    let order = |p: &Project| p.tracks.iter().map(|t| t.id).collect::<Vec<_>>();
    if order(a) != order(b) {
        let ids_a: std::collections::HashSet<Id> = order(a).into_iter().collect();
        let ids_b: std::collections::HashSet<Id> = order(b).into_iter().collect();
        let common_a: Vec<Id> = order(a).into_iter().filter(|i| ids_b.contains(i)).collect();
        let common_b: Vec<Id> = order(b).into_iter().filter(|i| ids_a.contains(i)).collect();
        if common_a != common_b {
            d.project.push("track order");
        }
    }
    if !d.project.is_empty() {
        let line = format!("~ project: {}", d.project.join(", "));
        d.item(line);
    }

    let tracks_a: HashMap<Id, &Arc<Track>> = a.all_tracks().map(|t| (t.id, t)).collect();
    let tracks_b: HashMap<Id, &Arc<Track>> = b.all_tracks().map(|t| (t.id, t)).collect();
    // Where every device, clip and lane is in `a`: the track holding it, and it.
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
    let devices_a = index(a, |t| &t.devices, |x| x.id);
    let devices_b = index(b, |t| &t.devices, |x| x.id);
    let clips_a = index(a, |t| &t.clips, |x| x.id);
    let clips_b = index(b, |t| &t.clips, |x| x.id);
    let lanes_a = index(a, |t| &t.lanes, |x| x.id);
    let lanes_b = index(b, |t| &t.lanes, |x| x.id);

    for track in b.all_tracks() {
        let Some(prev) = tracks_a.get(&track.id) else {
            d.tracks.added += 1;
            d.item(format!("+ {}", track_name(track)));
            continue;
        };
        if Arc::ptr_eq(prev, track) {
            continue;
        }
        let mut fields = Vec::new();
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
        for (field, differs) in checks {
            if differs {
                fields.push(field);
            }
        }
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
        if !fields.is_empty() {
            d.tracks.changed += 1;
            let name = if prev.name != track.name {
                format!("{} (was {})", track_name(track), prev.name)
            } else {
                track_name(track)
            };
            d.item(format!("~ {name}: {}", fields.join(", ")));
        }
    }
    for track in a.all_tracks() {
        if !tracks_b.contains_key(&track.id) {
            d.tracks.removed += 1;
            d.item(format!("- {}", track_name(track)));
        }
    }

    for (id, (track, device)) in sorted(&devices_b) {
        match devices_a.get(&id) {
            None => {
                d.devices.added += 1;
                d.item(format!("+ device {} on {}", device.kind, track_name(track)));
            }
            Some((was_on, prev)) if !Arc::ptr_eq(prev, device) || was_on.id != track.id => {
                let mut fields: Vec<String> = Vec::new();
                if was_on.id != track.id {
                    fields.push(format!("moved from {}", track_name(was_on)));
                }
                if prev.bypass != device.bypass {
                    fields.push("bypass".into());
                }
                let keys: std::collections::BTreeSet<&String> =
                    prev.params.keys().chain(device.params.keys()).collect();
                for key in keys {
                    if prev.params.get(key) != device.params.get(key) {
                        fields.push(key.clone());
                    }
                }
                if prev.state != device.state {
                    fields.push("plugin state".into());
                }
                if prev.meta != device.meta {
                    fields.push("meta".into());
                }
                if !fields.is_empty() {
                    d.devices.changed += 1;
                    d.item(format!(
                        "~ device {} on {}: {}",
                        device.kind,
                        track_name(track),
                        fields.join(", ")
                    ));
                }
            }
            Some(_) => {}
        }
    }
    for (id, (track, device)) in sorted(&devices_a) {
        if !devices_b.contains_key(&id) {
            d.devices.removed += 1;
            d.item(format!("- device {} on {}", device.kind, track_name(track)));
        }
    }

    // Clips, and the notes in them.
    let clip_name = |c: &crate::model::Clip| {
        if c.name.is_empty() {
            format!("clip {}", c.id)
        } else {
            format!("clip {}", c.name)
        }
    };
    for (id, (track, clip)) in sorted(&clips_b) {
        match clips_a.get(&id) {
            None => {
                d.clips.added += 1;
                d.item(format!("+ {} on {}", clip_name(clip), track_name(track)));
            }
            Some((was_on, prev)) if !Arc::ptr_eq(prev, clip) || was_on.id != track.id => {
                let mut fields: Vec<String> = Vec::new();
                if was_on.id != track.id {
                    fields.push(format!("moved from {}", track_name(was_on)));
                }
                for (field, differs) in [
                    ("name", prev.name != clip.name),
                    ("start", prev.start != clip.start),
                    ("length", prev.length != clip.length),
                    ("muted", prev.muted != clip.muted),
                    ("meta", prev.meta != clip.meta),
                ] {
                    if differs {
                        fields.push(field.into());
                    }
                }
                match (&prev.content, &clip.content) {
                    (
                        ClipContent::Midi { notes: was, .. },
                        ClipContent::Midi { notes: now, .. },
                    ) => {
                        let n = diff_notes(was, now);
                        let mut parts = Vec::new();
                        for (count, what) in [
                            (n.added, "added"),
                            (n.removed, "removed"),
                            (n.changed, "changed"),
                        ] {
                            if count > 0 {
                                parts.push(format!(
                                    "{count} note{} {what}",
                                    if count == 1 { "" } else { "s" }
                                ));
                            }
                        }
                        if !parts.is_empty() {
                            fields.push(parts.join(", "));
                        }
                        d.notes.added += n.added;
                        d.notes.removed += n.removed;
                        d.notes.changed += n.changed;
                    }
                    (was, now) if !same(was, now) => fields.push("audio".into()),
                    _ => {}
                }
                if !fields.is_empty() {
                    d.clips.changed += 1;
                    d.item(format!(
                        "~ {} on {}: {}",
                        clip_name(clip),
                        track_name(track),
                        fields.join(", ")
                    ));
                }
            }
            Some(_) => {}
        }
    }
    for (id, (track, clip)) in sorted(&clips_a) {
        if !clips_b.contains_key(&id) {
            d.clips.removed += 1;
            d.item(format!("- {} on {}", clip_name(clip), track_name(track)));
        }
    }

    let lane_name = |l: &crate::model::Lane| match &l.target {
        crate::model::Target::Volume => "volume".to_string(),
        crate::model::Target::Pan => "pan".to_string(),
        crate::model::Target::Param { param, .. } => param.clone(),
        crate::model::Target::State { .. } => "state".to_string(),
    };
    for (id, (track, lane)) in sorted(&lanes_b) {
        match lanes_a.get(&id) {
            None => {
                d.lanes.added += 1;
                d.item(format!(
                    "+ {} automation on {}",
                    lane_name(lane),
                    track_name(track)
                ));
            }
            Some((_, prev))
                if !Arc::ptr_eq(prev, lane)
                    && (prev.points != lane.points
                        || prev.shapes != lane.shapes
                        || prev.states != lane.states
                        || prev.enabled != lane.enabled
                        || prev.target != lane.target) =>
            {
                d.lanes.changed += 1;
                d.item(format!(
                    "~ {} automation on {}",
                    lane_name(lane),
                    track_name(track)
                ));
            }
            Some(_) => {}
        }
    }
    for (id, (track, lane)) in sorted(&lanes_a) {
        if !lanes_b.contains_key(&id) {
            d.lanes.removed += 1;
            d.item(format!(
                "- {} automation on {}",
                lane_name(lane),
                track_name(track)
            ));
        }
    }

    if d.more > 0 {
        let more = d.more;
        d.items.push(format!("… and {more} more"));
    }
    let empty = d.project.is_empty()
        && [&d.tracks, &d.devices, &d.clips, &d.notes, &d.lanes]
            .iter()
            .all(|c| c.total() == 0);
    json!({
        "tracks": d.tracks, "devices": d.devices, "clips": d.clips, "notes": d.notes,
        "lanes": d.lanes, "project": d.project, "items": d.items, "same": empty,
    })
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
    use crate::model::{Clip, DeviceInst};

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
        }));
        a.tracks.push(Arc::new(track));
        let empty = diff(&a, &a);
        assert_eq!(empty["same"], json!(true));

        let mut b = a.clone();
        b.tempo = 100.0;
        b.tracks.push(Arc::new(Track::new(4)));
        {
            let t = Arc::make_mut(&mut b.tracks[0]);
            t.volume = -6.0;
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
        }
        let d = diff(&a, &b);
        assert_eq!(d["same"], json!(false));
        assert_eq!(d["project"], json!(["tempo"]));
        assert_eq!(d["tracks"]["added"], json!(1));
        assert_eq!(d["tracks"]["changed"], json!(1));
        assert_eq!(d["devices"]["changed"], json!(1));
        assert_eq!(d["clips"]["changed"], json!(1));
        assert_eq!(d["notes"]["added"], json!(2));
        assert_eq!(d["notes"]["removed"], json!(1));
        assert_eq!(d["notes"]["changed"], json!(1));
        let items: Vec<String> = serde_json::from_value(d["items"].clone()).unwrap();
        assert!(
            items.contains(&"~ device synth on track Bass: cutoff".to_string()),
            "{items:?}"
        );
        assert!(
            items.contains(&"~ track Bass: volume".to_string()),
            "{items:?}"
        );

        let back = diff(&b, &a);
        assert_eq!(back["tracks"]["removed"], json!(1));
        assert_eq!(back["notes"]["added"], json!(1));
        assert_eq!(back["notes"]["removed"], json!(2));
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
