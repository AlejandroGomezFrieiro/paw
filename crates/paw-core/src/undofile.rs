//! The undo file: the states of a project's undo tree on the disk, so that
//! undo goes on past the last save after the project is opened again.
//!
//! ```text
//! <state dir>/projects/<project>/undo/
//! ├── tree.json        the tree: each state, its links and its files' tree
//! └── blobs/ab/abcd…   a file, or a folder's list of files, by its BLAKE3 hash
//! ```
//!
//! A state is the files that a save of it writes (`folder::layout`). Each
//! file is a blob named by its hash, and each folder is a blob too: a JSON
//! object from each name in the folder to the hash of its file (`name`) or
//! of its folder (`name/`). A state is the hash of its top folder. States
//! share every file and folder they did not change, so a state costs about
//! what its edit changed.
//!
//! This module is the storage alone: what goes into a state and when is
//! `session/undo_file.rs`.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

use crate::history::StateId;

/// The version of `tree.json`'s format.
const VERSION: u32 = 1;
/// The file of the tree in the undo folder.
pub const TREE_FILE: &str = "tree.json";
const BLOBS: &str = "blobs";

/// The hash of a blob: its name in the store.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct BlobId(blake3::Hash);

impl BlobId {
    /// The id of `bytes`.
    pub fn of(bytes: &[u8]) -> Self {
        Self(blake3::hash(bytes))
    }
}

impl fmt::Display for BlobId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.0.to_hex().as_str())
    }
}

impl fmt::Debug for BlobId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "BlobId({self})")
    }
}

impl FromStr for BlobId {
    type Err = blake3::HexError;

    fn from_str(hex: &str) -> std::result::Result<Self, Self::Err> {
        blake3::Hash::from_hex(hex).map(Self)
    }
}

impl Serialize for BlobId {
    fn serialize<S: serde::Serializer>(&self, s: S) -> std::result::Result<S::Ok, S::Error> {
        s.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for BlobId {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> std::result::Result<Self, D::Error> {
        let hex = <std::borrow::Cow<'de, str>>::deserialize(d)?;
        hex.parse().map_err(serde::de::Error::custom)
    }
}

/// One state of the tree as `tree.json` holds it: the fields of
/// [`crate::history::State`] and the hash of its files.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct StateEntry {
    pub id: StateId,
    pub parent: Option<StateId>,
    pub children: Vec<StateId>,
    pub redo: Option<StateId>,
    pub time: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub keys: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub keep: bool,
    pub files: BlobId,
}

/// `tree.json`: the states, oldest first, the root, and the state that the
/// project's files on the disk are.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct TreeFile {
    pub version: u32,
    pub root: StateId,
    pub saved: StateId,
    pub states: Vec<StateEntry>,
}

impl TreeFile {
    /// A tree of `states`, checked: every link names a state in it.
    ///
    /// # Errors
    ///
    /// When a link names a state that is not there, or the root or the
    /// saved state is not there.
    pub fn new(root: StateId, saved: StateId, states: Vec<StateEntry>) -> Result<Self> {
        let tree = Self { version: VERSION, root, saved, states };
        tree.check()?;
        Ok(tree)
    }

    fn check(&self) -> Result<()> {
        let ids: HashSet<StateId> = self.states.iter().map(|s| s.id).collect();
        let named = |id: &StateId| ids.contains(id);
        if !named(&self.root) || !named(&self.saved) {
            bail!("the undo file has no state {} or {}", self.root, self.saved);
        }
        for s in &self.states {
            if !s.parent.iter().chain(&s.children).chain(&s.redo).all(named) {
                bail!("state {} of the undo file names a state that is not there", s.id);
            }
        }
        Ok(())
    }

    /// Drop the state `id`, which is not the root: its children hang from
    /// its parent, as `History` prunes.
    fn remove(&mut self, id: StateId) {
        let Some(at) = self.states.iter().position(|s| s.id == id) else { return };
        let state = self.states.remove(at);
        let Some(parent) = state.parent else { return };
        for s in &mut self.states {
            if state.children.contains(&s.id) {
                s.parent = Some(parent);
            }
            if s.id == parent {
                if let Some(i) = s.children.iter().position(|c| *c == id) {
                    s.children.splice(i..=i, state.children.iter().copied());
                }
                if s.redo == Some(id) {
                    s.redo = state.redo.or_else(|| state.children.last().copied());
                }
            }
        }
    }
}

/// A folder of the store: each name to its file (`name`) or folder
/// (`name/`).
type Folder = BTreeMap<String, BlobId>;

/// The blobs of an undo folder.
pub struct Store {
    dir: PathBuf,
    /// The blobs known to be in the store, with their sizes.
    known: HashMap<BlobId, u64>,
    /// The folders read, by id.
    folders: HashMap<BlobId, Arc<Folder>>,
}

impl Store {
    /// The store of the undo folder `dir`, which need not be there yet.
    pub fn new(dir: &Path) -> Self {
        Self { dir: dir.to_path_buf(), known: HashMap::new(), folders: HashMap::new() }
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    fn path(&self, id: BlobId) -> PathBuf {
        let hex = id.to_string();
        self.dir.join(BLOBS).join(&hex[..2]).join(hex)
    }

    /// Keep `bytes` as a blob; nothing is written when it is there already.
    ///
    /// # Errors
    ///
    /// When the blob cannot be written.
    pub fn put(&mut self, bytes: &[u8]) -> Result<BlobId> {
        let id = BlobId::of(bytes);
        if self.known.contains_key(&id) {
            return Ok(id);
        }
        let path = self.path(id);
        if !path.is_file() {
            let parent = path.parent().context("a blob's folder")?;
            std::fs::create_dir_all(parent).with_context(|| format!("creating {}", parent.display()))?;
            // Written beside its place and renamed: a blob is whole or not
            // there. Not flushed one by one: `tree.json` is, after them.
            let tmp = path.with_extension("tmp");
            std::fs::write(&tmp, bytes).with_context(|| format!("writing {}", tmp.display()))?;
            std::fs::rename(&tmp, &path).with_context(|| format!("writing {}", path.display()))?;
        }
        self.known.insert(id, bytes.len() as u64);
        Ok(id)
    }

    /// The bytes of a blob.
    ///
    /// # Errors
    ///
    /// When the blob is not there, or its bytes do not have its hash.
    pub fn get(&self, id: BlobId) -> Result<Vec<u8>> {
        let path = self.path(id);
        let bytes = std::fs::read(&path).with_context(|| format!("reading {}", path.display()))?;
        if BlobId::of(&bytes) != id {
            bail!("{} is damaged", path.display());
        }
        Ok(bytes)
    }

    fn folder(&mut self, id: BlobId) -> Result<Arc<Folder>> {
        if let Some(folder) = self.folders.get(&id) {
            return Ok(Arc::clone(folder));
        }
        let bytes = self.get(id)?;
        let folder: Arc<Folder> = Arc::new(serde_json::from_slice(&bytes).context("a folder of the undo file")?);
        self.known.insert(id, bytes.len() as u64);
        self.folders.insert(id, Arc::clone(&folder));
        Ok(folder)
    }

    /// Keep the files `files` (by their path in the project's folder): each
    /// file and each folder as a blob. Returns the top folder's id.
    ///
    /// # Errors
    ///
    /// When a blob cannot be written.
    pub fn put_files<B: AsRef<[u8]>>(&mut self, files: &BTreeMap<PathBuf, B>) -> Result<BlobId> {
        /// A folder being put together: its files' ids and its folders.
        #[derive(Default)]
        struct Node {
            files: Folder,
            dirs: BTreeMap<String, Node>,
        }
        fn put_node(store: &mut Store, node: Node) -> Result<BlobId> {
            let mut folder = node.files;
            for (name, dir) in node.dirs {
                folder.insert(format!("{name}/"), put_node(store, dir)?);
            }
            let bytes = serde_json::to_vec(&folder)?;
            let id = store.put(&bytes)?;
            store.folders.entry(id).or_insert_with(|| Arc::new(folder));
            Ok(id)
        }
        let mut top = Node::default();
        for (rel, bytes) in files {
            let mut node = &mut top;
            let mut parts: Vec<String> = rel.iter().map(|p| p.to_string_lossy().into_owned()).collect();
            let name = parts.pop().context("a file with no name")?;
            for part in parts {
                node = node.dirs.entry(part).or_default();
            }
            node.files.insert(name, self.put(bytes.as_ref())?);
        }
        put_node(self, top)
    }

    /// The files of a state, by their path in the project's folder, each
    /// with its blob's id.
    ///
    /// # Errors
    ///
    /// When a folder of the state is not there or damaged.
    pub fn files(&mut self, top: BlobId) -> Result<BTreeMap<PathBuf, BlobId>> {
        let mut out = BTreeMap::new();
        let mut stack = vec![(PathBuf::new(), top)];
        while let Some((at, id)) = stack.pop() {
            for (name, child) in self.folder(id)?.iter() {
                match name.strip_suffix('/') {
                    Some(dir) => stack.push((at.join(dir), *child)),
                    None => {
                        out.insert(at.join(name), *child);
                    }
                }
            }
        }
        Ok(out)
    }

    /// The files of a state with their bytes.
    ///
    /// # Errors
    ///
    /// When a blob of the state is not there or damaged.
    pub fn read_files(&mut self, top: BlobId) -> Result<BTreeMap<PathBuf, Arc<[u8]>>> {
        self.files(top)?
            .into_iter()
            .map(|(rel, id)| Ok((rel, Arc::from(self.get(id)?))))
            .collect()
    }

    /// Every blob a state uses, its folders too.
    fn used_by(&mut self, top: BlobId, out: &mut HashSet<BlobId>) -> Result<()> {
        let mut stack = vec![top];
        while let Some(id) = stack.pop() {
            if !out.insert(id) {
                continue;
            }
            for (name, child) in self.folder(id)?.iter() {
                if name.ends_with('/') {
                    stack.push(*child);
                } else {
                    out.insert(*child);
                }
            }
        }
        Ok(())
    }

    fn size(&mut self, id: BlobId) -> u64 {
        if let Some(size) = self.known.get(&id) {
            return *size;
        }
        let size = std::fs::metadata(self.path(id)).map_or(0, |m| m.len());
        self.known.insert(id, size);
        size
    }

    /// Write `tree` as the undo file, after dropping its oldest states that
    /// are not protected (the root, the saved state, named and kept states)
    /// until the blobs it uses take at most `byte_limit` bytes; then remove
    /// the blobs that no state uses. Returns the states dropped.
    ///
    /// # Errors
    ///
    /// When `tree.json` cannot be written, or a state's folder read.
    pub fn commit(&mut self, tree: &mut TreeFile, byte_limit: u64) -> Result<Vec<StateId>> {
        let dropped = self.fit(tree, byte_limit)?;
        tree.check()?;
        let text = serde_json::to_vec(&tree)?;
        crate::safe::write_file(&self.dir.join(TREE_FILE), &text, false)?;
        let mut used = HashSet::new();
        for state in &tree.states {
            self.used_by(state.files, &mut used)?;
        }
        self.sweep(&used);
        Ok(dropped)
    }

    /// Drop states until the blobs fit: see [`Store::commit`].
    fn fit(&mut self, tree: &mut TreeFile, byte_limit: u64) -> Result<Vec<StateId>> {
        let mut uses: HashMap<BlobId, u32> = HashMap::new();
        let mut by_state: HashMap<StateId, HashSet<BlobId>> = HashMap::new();
        for state in &tree.states {
            let mut used = HashSet::new();
            self.used_by(state.files, &mut used)?;
            for id in &used {
                *uses.entry(*id).or_default() += 1;
            }
            by_state.insert(state.id, used);
        }
        let mut total: u64 = uses.keys().map(|id| self.size(*id)).sum();
        let mut dropped = Vec::new();
        while total > byte_limit {
            let protected = |s: &StateEntry| s.id == tree.root || s.id == tree.saved || s.name.is_some() || s.keep;
            let Some(id) = tree.states.iter().find(|s| !protected(s)).map(|s| s.id) else {
                break;
            };
            tree.remove(id);
            dropped.push(id);
            for blob in by_state.remove(&id).unwrap_or_default() {
                let count = uses.get_mut(&blob).expect("a blob a state uses is counted");
                *count -= 1;
                if *count == 0 {
                    uses.remove(&blob);
                    total -= self.size(blob);
                }
            }
        }
        Ok(dropped)
    }

    /// Remove every blob that is not in `used`.
    fn sweep(&mut self, used: &HashSet<BlobId>) {
        let Ok(dirs) = std::fs::read_dir(self.dir.join(BLOBS)) else { return };
        for entry in dirs.flatten() {
            let Ok(files) = std::fs::read_dir(entry.path()) else { continue };
            for file in files.flatten() {
                let name = file.file_name();
                let id = name.to_str().and_then(|n| n.parse::<BlobId>().ok());
                if id.is_none_or(|id| !used.contains(&id)) {
                    let _ = std::fs::remove_file(file.path());
                }
            }
            // A folder left empty goes; one with a file stays.
            let _ = std::fs::remove_dir(entry.path());
        }
        self.known.retain(|id, _| used.contains(id));
        self.folders.retain(|id, _| used.contains(id));
    }

    /// The bytes of every blob in the store.
    pub fn bytes(&self) -> u64 {
        let Ok(dirs) = std::fs::read_dir(self.dir.join(BLOBS)) else { return 0 };
        dirs.flatten()
            .filter_map(|d| std::fs::read_dir(d.path()).ok())
            .flat_map(|files| files.flatten())
            .filter_map(|f| f.metadata().ok())
            .map(|m| m.len())
            .sum()
    }
}

/// Read `tree.json` of the undo folder `dir`, or `None` when there is none.
///
/// # Errors
///
/// When the file is damaged or from a newer version.
pub fn read_tree(dir: &Path) -> Result<Option<TreeFile>> {
    let path = dir.join(TREE_FILE);
    let bytes = match std::fs::read(&path) {
        Ok(bytes) => bytes,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(e).with_context(|| format!("reading {}", path.display())),
    };
    let tree: TreeFile = serde_json::from_slice(&bytes).with_context(|| format!("parsing {}", path.display()))?;
    if tree.version > VERSION {
        bail!("{} was written by a newer version", path.display());
    }
    tree.check()?;
    Ok(Some(tree))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("paw-undofile-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    fn entry(id: StateId, parent: Option<StateId>, children: Vec<StateId>, files: BlobId) -> StateEntry {
        StateEntry {
            id,
            parent,
            redo: children.last().copied(),
            children,
            time: id as f64,
            label: None,
            keys: None,
            name: None,
            keep: false,
            files,
        }
    }

    #[test]
    fn the_oldest_states_go_past_the_limit_and_their_blobs_with_them() {
        let dir = scratch("limit");
        let mut store = Store::new(&dir);
        let state = |store: &mut Store, n: u8| {
            let files: BTreeMap<PathBuf, Vec<u8>> =
                [(PathBuf::from("tracks/a/clips/x.midi2"), vec![n; 1000])].into_iter().collect();
            store.put_files(&files).unwrap()
        };
        let ids: Vec<BlobId> = (0..4).map(|n| state(&mut store, n)).collect();
        let states = vec![
            entry(0, None, vec![1], ids[0]),
            entry(1, Some(0), vec![2], ids[1]),
            entry(2, Some(1), vec![3], ids[2]),
            entry(3, Some(2), vec![], ids[3]),
        ];
        let mut tree = TreeFile::new(0, 3, states).unwrap();
        // Room for about three states: the oldest that is not the root goes.
        let dropped = store.commit(&mut tree, 4500).unwrap();
        assert_eq!(dropped, vec![1]);
        assert_eq!(tree.states[0].children, vec![2]);
        assert_eq!(tree.states[1].parent, Some(0));
        assert_eq!(read_tree(&dir).unwrap().as_ref(), Some(&tree));
        assert!(store.get(ids[1]).is_err(), "its blobs are removed");
        assert_eq!(store.read_files(ids[2]).unwrap()[Path::new("tracks/a/clips/x.midi2")][..], [2; 1000]);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
