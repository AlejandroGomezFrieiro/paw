//! The undo file as the session uses it: written after each save of a
//! project folder, on a thread of its own, and read when the project opens
//! again. The storage is [`crate::undofile`].
//!
//! Lua says where the undo file of a project is (`paw.loading.project_dir`,
//! `undo/`) and whether there is one (`paw.opt.undofile`): see
//! `runtime/lua/paw/undofile.tl`.
//!
//! The states read from the undo file stay on the disk until the user goes
//! to one: until then the tree holds an empty project for each, and
//! [`Session::undo_file_state`] reads the real one when a move needs it.
#![cfg_attr(test, expect(clippy::cast_precision_loss, reason = "debt: pay down"))]

use std::collections::{BTreeMap, HashMap};
use std::path::{Path, PathBuf};
use std::thread::JoinHandle;

use anyhow::{Context, Result};
use serde_json::{Value, json};

use super::Session;
use super::folder::{self, PROJECT_FILE};
use super::media;
use super::project_files::MemoryFiles;
use crate::history::{State, StateId};
use crate::model::Project;
use crate::undofile::{self, BlobId, StateEntry, Store, TreeFile};

/// What the session knows of the undo file of the open project.
#[derive(Default)]
pub(super) struct UndoFile {
    /// The writer, idle or at work on the last save.
    writer: Option<Writer>,
    /// The states read from the undo file whose project is still on the disk.
    pub lazy: Lazy,
    /// The files that the last save of the whole project wrote, for the state
    /// it saved: the next write keeps them as that state.
    pub saved_files: Option<(StateId, BTreeMap<PathBuf, Vec<u8>>)>,
}

/// States read from an undo file whose project is not read yet, with the
/// undo folder they are in.
#[derive(Default)]
pub(super) struct Lazy {
    dir: PathBuf,
    states: HashMap<StateId, BlobId>,
}

/// What the writer knows between two writes.
struct Book {
    store: Store,
    /// The files of the parts of the last state laid out.
    parts: folder::PartCache,
    /// The files of each state in the undo file.
    written: HashMap<StateId, BlobId>,
    /// States the last write dropped to keep within the limit.
    dropped: Vec<StateId>,
    /// What went wrong in the last write.
    error: Option<String>,
}

impl Book {
    fn new(dir: &Path) -> Self {
        Self {
            store: Store::new(dir),
            parts: folder::PartCache::default(),
            written: HashMap::new(),
            dropped: Vec::new(),
            error: None,
        }
    }
}

enum Writer {
    Idle(Box<Book>),
    Busy(JoinHandle<Box<Book>>),
}

/// Where the files of a state to write come from.
enum Source {
    /// In the undo file already.
    Written(BlobId),
    /// The files that the save wrote.
    Files(BTreeMap<PathBuf, Vec<u8>>),
    /// A project to lay out as a save would.
    Project(Box<Project>),
}

/// A write of the undo file, done on the writer's thread.
struct Job {
    /// The project's `project.toml`.
    file: PathBuf,
    transport: Value,
    screen: Option<Value>,
    /// The home folder that `~/` names: the session's.
    home: folder::Home,
    root: StateId,
    saved: StateId,
    states: Vec<(StateEntry, Source)>,
    byte_limit: u64,
}

impl Job {
    fn run(self, book: &mut Book) -> Result<()> {
        let dir = self.file.parent().map(Path::to_path_buf).unwrap_or_default();
        let mut states = Vec::with_capacity(self.states.len());
        for (mut entry, source) in self.states {
            entry.files = match source {
                Source::Written(id) => id,
                Source::Files(files) => book.store.put_files(&files)?,
                Source::Project(project) => {
                    let project = media::for_file(&project, &self.file);
                    let layout =
                        folder::layout_cached(&project, &self.transport, self.screen.as_ref(), &dir, &self.home, &mut book.parts)?;
                    book.store.put_files(&layout.files)?
                }
            };
            states.push(entry);
        }
        let mut tree = TreeFile::new(self.root, self.saved, states)?;
        book.dropped = book.store.commit(&mut tree, self.byte_limit)?;
        book.written = tree.states.iter().map(|s| (s.id, s.files)).collect();
        Ok(())
    }
}

impl UndoFile {
    /// The writer's book for the undo folder `dir`, once the write under way
    /// is done: a new one for another folder.
    fn book(&mut self, dir: &Path) -> Box<Book> {
        let book = match self.writer.take() {
            Some(Writer::Idle(book)) => Some(book),
            Some(Writer::Busy(handle)) => handle.join().ok(),
            None => None,
        };
        book.filter(|b| b.store.dir() == dir)
            .unwrap_or_else(|| Box::new(Book::new(dir)))
    }

    /// Wait for the write under way, if there is one.
    pub(super) fn wait(&mut self) {
        if let Some(Writer::Busy(handle)) = self.writer.take() {
            self.writer = handle.join().ok().map(Writer::Idle);
        }
    }
}

impl Drop for UndoFile {
    fn drop(&mut self) {
        self.wait();
    }
}

/// Whether every file of `files` (by its path in `dir`) is on the disk with
/// those bytes, read on as many threads as there are cores.
fn on_disk(dir: &Path, files: &BTreeMap<PathBuf, BlobId>) -> bool {
    let list: Vec<(&PathBuf, &BlobId)> = files.iter().collect();
    let same = |(rel, id): &(&PathBuf, &BlobId)| std::fs::read(dir.join(rel)).is_ok_and(|b| BlobId::of(&b) == **id);
    let threads = std::thread::available_parallelism().map_or(1, |n| n.get()).min(8);
    if list.len() < 64 || threads < 2 {
        return list.iter().all(same);
    }
    let chunk = list.len().div_ceil(threads);
    std::thread::scope(|s| {
        let handles: Vec<_> = list
            .chunks(chunk)
            .map(|part| s.spawn(move || part.iter().all(same)))
            .collect();
        handles.into_iter().all(|h| h.join().unwrap_or(false))
    })
}

impl Session {
    /// The `project.toml` of the open project, when it is kept in a folder.
    fn folder_file(&self) -> Option<PathBuf> {
        self.path
            .clone()
            .filter(|p| p.file_name().is_some_and(|n| n == PROJECT_FILE))
    }

    /// Read the undo file in the folder `dir` for the project just opened:
    /// its states join the undo tree, with the opened state as the current
    /// one. `{ states = n }` when they did, `{ stale = true }` when the undo
    /// file is for other files than the project's on the disk (and is not
    /// read), `{}` when there is none or the project is not a folder.
    ///
    /// # Errors
    ///
    /// When the undo file is damaged.
    pub(crate) fn undo_file_open(&mut self, dir: &Path) -> Result<Value> {
        let Some(file) = self.folder_file() else { return Ok(json!({})) };
        // Only a project just opened: no step made yet.
        if self.doc.undo.history.len() != 1 || self.doc.undo.touched {
            return Ok(json!({}));
        }
        let mut book = self.undo_file.book(dir);
        let opened = self.open_tree(&mut book, &file);
        self.undo_file.writer = Some(Writer::Idle(book));
        opened
    }

    fn open_tree(&mut self, book: &mut Book, file: &Path) -> Result<Value> {
        let Some(tree) = undofile::read_tree(book.store.dir())? else { return Ok(json!({})) };
        let saved = tree
            .states
            .iter()
            .find(|s| s.id == tree.saved)
            .context("the undo file has no saved state")?;
        let files = book.store.files(saved.files)?;
        let project_dir = file.parent().map(Path::to_path_buf).unwrap_or_default();
        if !on_disk(&project_dir, &files) {
            return Ok(json!({ "stale": true }));
        }
        let states: Vec<State<Project>> = tree
            .states
            .iter()
            .map(|e| {
                let snapshot = if e.id == tree.saved { self.doc.project.clone() } else { Project::default() };
                let mut s = State::new(e.id, e.parent, e.time, snapshot);
                s.children = e.children.clone();
                s.redo = e.redo;
                s.label = e.label.clone();
                s.keys = e.keys.clone();
                s.name = e.name.clone();
                s.keep = e.keep;
                s
            })
            .collect();
        if !self.doc.undo.history.restore(states, tree.root, tree.saved) {
            anyhow::bail!("{}: the undo tree is damaged", book.store.dir().display());
        }
        book.written = tree.states.iter().map(|s| (s.id, s.files)).collect();
        self.undo_file.lazy = Lazy {
            dir: book.store.dir().to_path_buf(),
            states: tree.states.iter().filter(|s| s.id != tree.saved).map(|s| (s.id, s.files)).collect(),
        };
        self.undo_file.saved_files = None;
        Ok(json!({ "states": tree.states.len() }))
    }

    /// Write the undo file in the folder `dir` after a save of the whole
    /// project, on a thread of its own: the states new since the last
    /// write, and within about `byte_limit` bytes. Nothing for a project
    /// that is not kept in a folder.
    pub(crate) fn undo_file_write(&mut self, dir: &Path, byte_limit: u64) {
        let Some(file) = self.folder_file() else { return };
        let Some((saved, files)) = self.undo_file.saved_files.take() else { return };
        // Saved somewhere else: the states still in the old undo file are
        // read now, as the new one does not have their files.
        if self.undo_file.lazy.dir != dir {
            let ids: Vec<StateId> = self.undo_file.lazy.states.keys().copied().collect();
            self.undo_file_states(&ids);
            for id in std::mem::take(&mut self.undo_file.lazy.states).into_keys() {
                self.doc.undo.history.forget(id);
            }
        }
        let mut book = self.undo_file.book(dir);
        if let Some(error) = book.error.take() {
            self.doc.warnings.push(format!("the undo file was not written: {error}"));
        }
        // What the last write dropped to keep within the limit goes from the
        // tree here too.
        for id in std::mem::take(&mut book.dropped) {
            self.doc.undo.history.forget(id);
            self.undo_file.lazy.states.remove(&id);
        }
        let h = &self.doc.undo.history;
        if h.get(saved).is_none() {
            self.undo_file.writer = Some(Writer::Idle(book));
            return;
        }
        let mut files = Some(files);
        let states = h
            .states()
            .map(|s| {
                let source = if s.id == saved {
                    Source::Files(files.take().unwrap_or_default())
                } else if let Some(id) = self.undo_file.lazy.states.get(&s.id) {
                    Source::Written(*id)
                } else if let Some(id) = book.written.get(&s.id).filter(|_| s.id != h.current()) {
                    Source::Written(*id)
                } else {
                    Source::Project(Box::new(s.snapshot.clone()))
                };
                let entry = StateEntry {
                    id: s.id,
                    parent: s.parent,
                    children: s.children.clone(),
                    redo: s.redo,
                    time: s.time,
                    label: s.label.clone(),
                    keys: s.keys.clone(),
                    name: s.name.clone(),
                    keep: s.keep,
                    files: BlobId::of(&[]),
                };
                (entry, source)
            })
            .collect();
        let job = Job {
            file,
            transport: serde_json::to_value(&self.transport).unwrap_or_default(),
            screen: self.screen.clone(),
            home: self.home.clone(),
            root: h.root(),
            saved,
            states,
            byte_limit,
        };
        let handle = std::thread::Builder::new()
            .name("paw-undofile".into())
            .spawn(move || {
                if let Err(e) = job.run(&mut book) {
                    book.error = Some(format!("{e:#}"));
                }
                book
            });
        self.undo_file.writer = handle.ok().map(Writer::Busy);
    }

    /// Wait for the undo file being written: before the program ends.
    pub(crate) fn undo_file_wait(&mut self) {
        self.undo_file.wait();
    }

    /// Read the project of state `id` from the undo file, when the tree
    /// does not hold it yet.
    ///
    /// # Errors
    ///
    /// When its files are not in the undo file, or do not make a project.
    pub(super) fn undo_file_state(&mut self, id: StateId) -> Result<()> {
        let Some(top) = self.undo_file.lazy.states.get(&id).copied() else { return Ok(()) };
        let file = self.folder_file().context("the project is not a folder")?;
        let dir = file.parent().map(Path::to_path_buf).unwrap_or_default();
        let files = Store::new(&self.undo_file.lazy.dir).read_files(top)?;
        let read = folder::read_from(&MemoryFiles::new(&dir, files), &self.home, &dir)?;
        let mut project = read.project;
        project.validate()?;
        project.name_notes(&Project::default());
        project.refresh_tempo();
        self.find_media(&mut project, &file);
        super::undo::share_with(&mut project, &self.doc.project);
        self.doc.undo.history.set_snapshot(id, project);
        self.undo_file.lazy.states.remove(&id);
        Ok(())
    }

    /// [`undo_file_state`](Self::undo_file_state) for each of `ids`, with
    /// what goes wrong said as a warning. False when one could not be read.
    pub(super) fn undo_file_states(&mut self, ids: &[StateId]) -> bool {
        let mut ok = true;
        for id in ids {
            if let Err(e) = self.undo_file_state(*id) {
                self.doc.warnings.push(format!("state {id} of the undo file: {e:#}"));
                ok = false;
            }
        }
        ok
    }

    /// Take the states that are only in the undo file, to keep with a
    /// project put aside (`project_shelve`), or give them back.
    pub(super) fn undo_file_swap(&mut self, lazy: Lazy) -> Lazy {
        std::mem::replace(&mut self.undo_file.lazy, lazy)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Clip, ClipContent, Note, Notes, Part};
    use std::sync::Arc;

    fn clip(id: u64, seed: u64) -> Arc<Clip> {
        let value = json!({
            "id": id, "name": "riff", "start": 0.0, "length": 4.0, "muted": false,
            "content": { "kind": "midi", "notes": [] },
        });
        let mut clip: Clip = serde_json::from_value(value).unwrap();
        let notes: Vec<Note> = (0..12)
            .map(|i| Note {
                start: i as f64 / 3.0,
                // Each clip its own: equal clips would share one file.
                length: 0.25 + seed as f64 / 1024.0,
                pitch: 48 + ((i * 7 + seed) % 24) as u8,
                velocity: crate::model::Velocity(90),
                meta: Default::default(),
                id: i + 1,
                attr: None,
            })
            .collect();
        clip.content = ClipContent::Midi { notes: Notes::from(notes), controls: Vec::new() };
        Arc::new(clip)
    }

    #[test]
    fn states_share_what_they_did_not_change() {
        let dir = std::env::temp_dir().join(format!("paw-undo-file-share-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let mut project = Project::default();
        for t in 0..64u64 {
            let mut part = Part::new(t * 10 + 1);
            part.name = format!("T{t}");
            part.clips = (0..4).map(|c| clip(t * 10 + 2 + c, t * 4 + c)).collect::<Vec<_>>().into();
            project.parts.push(Arc::new(part));
        }
        let mut store = Store::new(&dir.join("undo"));
        let mut parts = folder::PartCache::default();
        let mut tops = Vec::new();
        for edit in 0..=100u64 {
            if edit > 0 {
                // One note of one clip: a step of its own.
                let part = Arc::make_mut(&mut project.parts[(edit % 64) as usize]);
                let clip = Arc::make_mut(&mut part.clips[0]);
                if let ClipContent::Midi { notes, .. } = &mut clip.content {
                    notes[0].pitch = (notes[0].pitch + 1) % 128;
                }
            }
            let layout = folder::layout_cached(&project, &json!({}), None, &dir, &folder::Home::default(), &mut parts).unwrap();
            tops.push(store.put_files(&layout.files).unwrap());
        }
        let (a, b) = (store.files(tops[1]).unwrap(), store.files(tops[2]).unwrap());
        let differ: Vec<_> = a.iter().filter(|(path, id)| b.get(*path) != Some(id)).collect();
        assert_eq!(differ.len(), 1, "one clip changed: {differ:?}");
        assert_eq!(a.len(), b.len());
        let states = tops
            .iter()
            .enumerate()
            .map(|(i, top)| StateEntry {
                id: i as StateId,
                parent: i.checked_sub(1).map(|p| p as StateId),
                children: if i < 100 { vec![i as StateId + 1] } else { Vec::new() },
                redo: (i < 100).then_some(i as StateId + 1),
                time: i as f64,
                label: None,
                keys: None,
                name: None,
                keep: false,
                files: *top,
            })
            .collect();
        let mut tree = TreeFile::new(0, 100, states).unwrap();
        assert!(store.commit(&mut tree, 256 << 20).unwrap().is_empty());
        let tree_bytes = std::fs::metadata(dir.join("undo").join(undofile::TREE_FILE)).unwrap().len();
        let bytes = store.bytes() + tree_bytes;
        println!("the undo file of 100 note edits in 64 parts: {bytes} bytes");
        assert!(bytes < 2 << 20, "the undo file of 100 note edits: {bytes} bytes");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
