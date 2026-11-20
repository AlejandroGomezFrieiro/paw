//! Changes made outside paw to the files of the open project.
//!
//! paw watches the folders of a project kept in a folder, and the folders of
//! the files outside it that the project reads (clip files it refers to,
//! sound files), with inotify. Editors and `git checkout` save by writing a
//! file beside another and renaming it, so it is the folders that are
//! watched, not the files. A change paw made itself (a save) is known by the
//! bytes it wrote and is not reported. Changes that come together, as a
//! checkout's do, are reported once, when no more have come for a moment:
//! the `files.changed` event, which the Lua runtime acts on
//! (`paw.opt.on_external_change`).

use crate::events::{FilesChanged, KernelEvent as E};
use std::collections::{BTreeSet, HashMap};
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};

use super::folder::{self, PROJECT_FILE};
use crate::model::{ClipContent, Project, Track};

/// Changes that come closer together than this are one burst.
const SETTLE: Duration = Duration::from_millis(300);

/// A hash of a file's bytes, or of its absence.
pub(super) fn hash_of(bytes: Option<&[u8]>) -> u64 {
    let mut h = std::collections::hash_map::DefaultHasher::new();
    match bytes {
        Some(b) => b.hash(&mut h),
        None => 0xdead_u32.hash(&mut h),
    }
    h.finish()
}

fn hash_file(path: &Path) -> u64 {
    hash_of(std::fs::read(path).ok().as_deref())
}

pub(super) struct FileWatch {
    fd: i32,
    dirs: HashMap<i32, PathBuf>,
    by_dir: HashMap<PathBuf, i32>,
    /// The project's folder: every file in it but those of `unused/` counts.
    root: Option<PathBuf>,
    /// Files outside the folder that the project reads.
    outside: BTreeSet<PathBuf>,
    /// What paw itself last wrote to or moved away from a path.
    written: HashMap<PathBuf, u64>,
    pending: BTreeSet<PathBuf>,
    last: Instant,
    /// Files changed outside paw that are not acted on yet.
    pub changed: BTreeSet<PathBuf>,
}

impl Default for FileWatch {
    fn default() -> Self {
        Self {
            fd: -1,
            dirs: HashMap::new(),
            by_dir: HashMap::new(),
            root: None,
            outside: BTreeSet::new(),
            written: HashMap::new(),
            pending: BTreeSet::new(),
            last: Instant::now(),
            changed: BTreeSet::new(),
        }
    }
}

impl Drop for FileWatch {
    fn drop(&mut self) {
        if self.fd >= 0 {
            // SAFETY: the descriptor is ours and closed once.
            unsafe { libc::close(self.fd) };
        }
    }
}

impl FileWatch {
    /// Watch these folders and no others.
    fn set_dirs(&mut self, dirs: BTreeSet<PathBuf>) {
        if self.fd < 0 && !dirs.is_empty() {
            // SAFETY: plain system call.
            self.fd = unsafe { libc::inotify_init1(libc::IN_NONBLOCK | libc::IN_CLOEXEC) };
            if self.fd < 0 {
                return;
            }
        }
        let gone: Vec<PathBuf> = self
            .by_dir
            .keys()
            .filter(|d| !dirs.contains(*d))
            .cloned()
            .collect();
        for dir in gone {
            if let Some(wd) = self.by_dir.remove(&dir) {
                self.dirs.remove(&wd);
                // SAFETY: a watch of our descriptor.
                unsafe { libc::inotify_rm_watch(self.fd, wd) };
            }
        }
        for dir in dirs {
            if self.by_dir.contains_key(&dir) {
                continue;
            }
            use std::os::unix::ffi::OsStrExt;
            let Ok(c) = std::ffi::CString::new(dir.as_os_str().as_bytes()) else {
                continue;
            };
            let mask = libc::IN_CLOSE_WRITE
                | libc::IN_MOVED_TO
                | libc::IN_MOVED_FROM
                | libc::IN_CREATE
                | libc::IN_DELETE
                | libc::IN_ONLYDIR;
            // SAFETY: a C string and our descriptor.
            let wd = unsafe { libc::inotify_add_watch(self.fd, c.as_ptr(), mask) };
            if wd >= 0 {
                self.dirs.insert(wd, dir.clone());
                self.by_dir.insert(dir, wd);
            }
        }
    }

    /// Whether a change of `path` concerns the project.
    fn counts(&self, path: &Path) -> bool {
        if self.outside.contains(path) {
            return true;
        }
        let Some(root) = &self.root else {
            return false;
        };
        let Ok(rel) = path.strip_prefix(root) else {
            return false;
        };
        // The files paw writes and the sound files: not an editor's swap
        // file or backup beside them.
        let name = rel
            .file_name()
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        let ext = rel
            .extension()
            .map(|e| e.to_string_lossy().to_lowercase())
            .unwrap_or_default();
        !rel.starts_with("unused")
            && !name.starts_with('.')
            && (matches!(ext.as_str(), "json" | "toml" | "midi2" | "state")
                || rel.starts_with("media"))
    }

    /// Note what paw wrote to (or moved away from) a path.
    pub fn wrote(&mut self, path: PathBuf, bytes: Option<&[u8]>) {
        self.written.insert(path, hash_of(bytes));
    }

    /// Read what happened. Returns the files changed outside paw, once a
    /// burst of changes has settled.
    pub fn poll(&mut self) -> Option<Vec<PathBuf>> {
        if self.fd < 0 {
            return None;
        }
        let mut buf = [0u8; 8192];
        loop {
            // SAFETY: reading into a buffer we own, of its length.
            let n = unsafe { libc::read(self.fd, buf.as_mut_ptr().cast(), buf.len()) };
            if n <= 0 {
                break;
            }
            let mut at = 0usize;
            while at + std::mem::size_of::<libc::inotify_event>() <= n as usize {
                // SAFETY: the kernel wrote whole events into the buffer.
                let event: libc::inotify_event =
                    unsafe { std::ptr::read_unaligned(buf.as_ptr().add(at).cast()) };
                let head = std::mem::size_of::<libc::inotify_event>();
                let name = &buf[at + head..at + head + event.len as usize];
                let name = name.split(|b| *b == 0).next().unwrap_or(&[]);
                at += head + event.len as usize;
                let Some(dir) = self.dirs.get(&event.wd) else {
                    continue;
                };
                use std::os::unix::ffi::OsStrExt;
                let path = dir.join(std::ffi::OsStr::from_bytes(name));
                if event.mask & libc::IN_ISDIR != 0 {
                    continue;
                }
                if self.counts(&path) {
                    self.pending.insert(path);
                    self.last = Instant::now();
                }
            }
        }
        if self.pending.is_empty() || self.last.elapsed() < SETTLE {
            return None;
        }
        let mut changed = Vec::new();
        for path in std::mem::take(&mut self.pending) {
            let now = hash_file(&path);
            if self.written.get(&path) == Some(&now) {
                continue;
            }
            self.written.remove(&path);
            if self.changed.insert(path.clone()) {
                changed.push(path);
            }
        }
        (!changed.is_empty()).then_some(changed)
    }
}

/// Every folder under `root`, but `unused` and hidden ones.
fn folders(root: &Path, out: &mut BTreeSet<PathBuf>) {
    out.insert(root.to_path_buf());
    let Ok(entries) = std::fs::read_dir(root) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if name.starts_with('.') || (name == "unused" && root.join(PROJECT_FILE).exists()) {
            continue;
        }
        if entry.file_type().is_ok_and(|t| t.is_dir()) {
            folders(&entry.path(), out);
        }
    }
}

/// The same parts of `old` where `new` has them unchanged, so that the
/// engine keeps what it runs for them (a plugin keeps its state).
fn keep_same(old: &Project, new: &mut Project) {
    let same = |a: &dyn erased::Json, b: &dyn erased::Json| a.json() == b.json();
    let old_tracks: HashMap<u64, &Arc<Track>> = old.all_tracks().map(|t| (t.id, t)).collect();
    for track in new
        .tracks
        .iter_mut()
        .chain(std::iter::once(&mut new.master))
    {
        let Some(was) = old_tracks.get(&track.id) else {
            continue;
        };
        if same(&***was, &**track) {
            *track = Arc::clone(was);
            continue;
        }
        let t = Arc::make_mut(track);
        for d in &mut t.devices {
            if let Some(o) = was.devices.iter().find(|o| o.id == d.id)
                && same(&**o, &**d)
            {
                *d = Arc::clone(o);
            }
        }
        for c in &mut t.clips {
            if let Some(o) = was.clips.iter().find(|o| o.id == c.id)
                && same(&**o, &**c)
            {
                *c = Arc::clone(o);
            }
        }
        for l in &mut t.lanes {
            if let Some(o) = was.lanes.iter().find(|o| o.id == l.id)
                && same(&**o, &**l)
            {
                *l = Arc::clone(o);
            }
        }
    }
}

mod erased {
    pub trait Json {
        fn json(&self) -> serde_json::Value;
    }
    impl<T: serde::Serialize> Json for T {
        fn json(&self) -> serde_json::Value {
            serde_json::to_value(self).unwrap_or_default()
        }
    }
}

impl super::Session {
    /// Watch the open project's files: called when it is opened or saved.
    pub(super) fn watch_project_files(&mut self) {
        let mut dirs = BTreeSet::new();
        let root = self
            .path
            .as_ref()
            .filter(|p| p.file_name().is_some_and(|n| n == PROJECT_FILE))
            .and_then(|p| p.parent())
            .map(Path::to_path_buf);
        if let Some(root) = &root {
            folders(root, &mut dirs);
        }
        // Clip files and sound files outside the folder.
        let mut outside = BTreeSet::new();
        // Track folders and chain files outside the folder.
        for track in self.project.all_tracks() {
            if let Some(folder) = &track.source {
                dirs.insert(folder.clone());
                outside.insert(folder.join("track.json"));
                outside.insert(folder.join("devices.json"));
            }
            if let Some(chain) = &track.chain_source {
                dirs.extend(chain.parent().map(Path::to_path_buf));
                outside.insert(chain.clone());
            }
        }
        for track in self.project.all_tracks() {
            for clip in track.clips.iter().chain(&track.cues) {
                let file = match (&clip.source, &clip.content) {
                    (Some(source), _) => Some(source.clone()),
                    (None, ClipContent::Audio { file, .. }) => Some(file.clone()),
                    _ => None,
                };
                if let Some(file) = file
                    && root.as_ref().is_none_or(|r| !file.starts_with(r))
                {
                    if let Some(dir) = file.parent() {
                        dirs.insert(dir.to_path_buf());
                    }
                    outside.insert(file);
                }
            }
        }
        if root.is_none() {
            // A project in one file: watch nothing.
            dirs.clear();
            outside.clear();
        }
        self.files_watch.root = root;
        self.files_watch.outside = outside;
        self.files_watch.changed.clear();
        self.files_watch.set_dirs(dirs);
    }

    /// Look for changes made outside paw: called from `idle`.
    pub(super) fn poll_file_changes(&mut self) {
        if let Some(paths) = self.files_watch.poll() {
            let root = self.files_watch.root.clone();
            let names: Vec<PathBuf> = paths
                .iter()
                .map(|p| root.as_ref().and_then(|r| p.strip_prefix(r).ok()).unwrap_or(p).to_path_buf())
                .collect();
            self.emit(E::FilesChanged(FilesChanged { paths: names }));
        }
    }

    /// The files changed outside paw that are not acted on yet: paths in
    /// the folder, or full paths outside it.
    pub fn changed_files(&self) -> Vec<PathBuf> {
        let root = self.files_watch.root.as_ref();
        self.files_watch
            .changed
            .iter()
            .map(|p| {
                root.and_then(|r| p.strip_prefix(r).ok())
                    .map(Path::to_path_buf)
                    .unwrap_or_else(|| p.clone())
            })
            .collect()
    }

    /// Keep the project as paw has it, whatever changed on the disk: the
    /// next save writes it over those files.
    pub fn keep_changed_files(&mut self) {
        self.files_watch.changed.clear();
    }

    /// Read the project's folder again, as one undo step: what changed on
    /// the disk replaces what paw has. The parts that did not change stay
    /// as they are, so their plugins keep running.
    pub fn project_reload(&mut self) -> Result<()> {
        let Some(file) = self
            .path
            .clone()
            .filter(|p| p.file_name().is_some_and(|n| n == PROJECT_FILE))
        else {
            bail!("only a project kept in a folder is read again");
        };
        let dir = file.parent().map(Path::to_path_buf).unwrap_or_default();
        let read = folder::read(&dir)?;
        let mut project = read.project;
        project
            .validate()
            .with_context(|| format!("{} cannot be loaded", dir.display()))?;
        self.find_media(&mut project, &file);
        project.refresh_tempo();
        keep_same(&self.project, &mut project);
        self.next_id = self.next_id.max(project.max_id() + 1);
        if let Ok(transport) = serde_json::from_value::<super::Transport>(read.transport) {
            let keep = self.transport.clone();
            self.transport = super::Transport {
                recording: keep.recording,
                count_in: keep.count_in,
                pre_roll: keep.pre_roll,
                pre_roll_seconds: keep.pre_roll_seconds,
                click_level: keep.click_level,
                click_accent: keep.click_accent,
                click_output: keep.click_output,
                ..transport
            };
            self.send_transport();
        }
        self.edit(|p| {
            *p = project;
            Ok(())
        })?;
        self.files_watch.changed.clear();
        self.checkpoint();
        // What is on the disk now is what paw has: saved.
        self.history.mark_saved(false);
        Ok(())
    }
}
