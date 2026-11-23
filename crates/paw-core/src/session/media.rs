//! Where a project's sound files are, and finding them when they have moved.
//!
//! In memory every audio clip names its file by an absolute path. A saved
//! project names files inside its own directory tree by a path relative to
//! the project file, and files elsewhere by their absolute path, so that a
//! project folder can be moved or copied whole. On opening, a file that is
//! not where the project says is looked for: relative to the project, then
//! by name in the project's directory tree and in directories where other
//! missing files turned up. What is still missing stays in the project,
//! offline and silent, under the path it was saved with.
//!
//! What a file is, is the hash of its bytes (`crate::media`). A project
//! folder keeps the hash, size and header of each file in `media.json`.
//! Opening checks each file against this machine's index with one `stat`
//! and hashes the others in the background: nothing that plays waits for
//! a hash. A missing file is found again by its name or its size, and only
//! a file with the same hash is taken for it. A file that changed on the
//! disk is followed, and the user is told once.

use crate::events::{KernelEvent as E, MediaMissing};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::ffi::{OsStr, OsString};
use std::path::{Component, Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use serde_json::{Value, json};

use super::Session;
use super::folder::PROJECT_FILE;
use crate::freeze;
use crate::media::hash::Hashing;
use crate::media::{Changed, MediaRecord, MediaTable, SourceHash, Sources};
use crate::model::{Clip, ClipContent, Project, Sound};

/// How deep, and how far, the search for a missing file by name looks.
const SEARCH_DEPTH: usize = 8;
const SEARCH_ENTRIES: usize = 50_000;

/// The files of a clip's other takes: `meta.takes.list[].file`, which
/// `paw.takes` keeps (the take that plays is the clip's own file).
fn take_files(clip: &Clip) -> impl Iterator<Item = PathBuf> + '_ {
    clip.meta
        .get("takes")
        .and_then(|takes| takes.get("list"))
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(|take| take.get("file").and_then(Value::as_str))
        .map(PathBuf::from)
}

/// Change the files of a clip's other takes for which `f` gives a new one.
fn map_take_files(clip: &mut Clip, f: &mut impl FnMut(&Path) -> Option<PathBuf>) {
    let Some(list) = clip
        .meta
        .get_mut("takes")
        .and_then(|takes| takes.get_mut("list"))
        .and_then(Value::as_array_mut)
    else {
        return;
    };
    for take in list {
        let new = take
            .get("file")
            .and_then(Value::as_str)
            .and_then(|file| f(Path::new(file)));
        if let Some(new) = new {
            take["file"] = Value::String(new.to_string_lossy().into_owned());
        }
    }
}

/// The files of a custom clip: each of its media, and the file of its sound
/// when that is audio. Derived media are the second of each pair.
fn custom_files(clip: &Clip) -> Vec<(PathBuf, bool)> {
    let ClipContent::Custom(custom) = &clip.content else {
        return Vec::new();
    };
    let mut out: Vec<(PathBuf, bool)> = custom
        .media
        .iter()
        .map(|m| (m.path.clone(), m.derived))
        .collect();
    if let Some(ClipContent::Audio { file, .. }) = custom.sound.as_ref().map(Sound::content) {
        out.push((file.clone(), false));
    }
    out
}

/// Change the files of a custom clip (see [`custom_files`]) for which `f`
/// gives a new one.
fn map_custom_files(clip: &mut Clip, f: &mut impl FnMut(&Path) -> Option<PathBuf>) {
    let ClipContent::Custom(custom) = &mut clip.content else {
        return;
    };
    let custom = &mut **custom;
    for media in &mut custom.media {
        if let Some(new) = f(&media.path) {
            media.path = new;
        }
    }
    let new_sound = match custom.sound.as_ref().map(Sound::content) {
        Some(ClipContent::Audio { file, offset, gain, edits }) => f(file).map(|file| {
            ClipContent::Audio { file, offset: *offset, gain: *gain, edits: edits.clone() }
        }),
        _ => None,
    };
    if let Some(sound) = new_sound.and_then(|c| Sound::try_from(c).ok()) {
        custom.sound = Some(sound);
    }
}

/// Change the file of every audio clip, of every other take of one, and of
/// every frozen track (see `crate::freeze`), for which `f` gives a new one.
/// Returns how many clips and tracks changed.
pub(super) fn map_files(
    project: &mut Project,
    mut f: impl FnMut(&Path) -> Option<PathBuf>,
) -> usize {
    let mut changed = 0;
    for track in project
        .tracks
        .iter_mut()
        .chain(std::iter::once(&mut project.master))
    {
        if freeze::frozen_file(track).is_some_and(|file| f(&file).is_some()) {
            freeze::map_frozen_file(Arc::make_mut(track), &mut f);
            changed += 1;
        }
        let new: Vec<(Option<PathBuf>, bool)> = track
            .clips
            .iter()
            .map(|c| {
                let own = match &c.content {
                    ClipContent::Audio { file, .. } => f(file),
                    _ => None,
                };
                let others = take_files(c).any(|file| f(&file).is_some())
                    || custom_files(c).iter().any(|(file, _)| f(file).is_some());
                (own, others)
            })
            .collect();
        if new.iter().all(|(own, others)| own.is_none() && !others) {
            continue;
        }
        let track = Arc::make_mut(track);
        for (clip, (path, others)) in track.clips.iter_mut().zip(new) {
            if path.is_none() && !others {
                continue;
            }
            let clip = Arc::make_mut(clip);
            if others {
                map_take_files(clip, &mut f);
                map_custom_files(clip, &mut f);
            }
            if let Some(path) = path
                && let ClipContent::Audio { file, .. } = &mut clip.content
            {
                *file = path;
            }
            changed += 1;
        }
    }
    changed
}

/// Every file the project's clips use, once each: the takes that are not
/// playing included, the media and the audio sound of custom clips, and the
/// files frozen tracks play.
pub fn files(project: &Project) -> BTreeSet<PathBuf> {
    project
        .all_tracks()
        .flat_map(|t| &t.clips)
        .flat_map(|c| {
            let own = match &c.content {
                ClipContent::Audio { file, .. } => Some(file.clone()),
                _ => None,
            };
            own.into_iter()
                .chain(take_files(c))
                .chain(custom_files(c).into_iter().map(|(file, _)| file))
        })
        .chain(project.all_tracks().filter_map(|t| freeze::frozen_file(t)))
        .collect()
}

/// The files of custom clips that a kind makes from other files: it makes
/// them again when they are not there, so they are never missing and never
/// collected.
pub fn derived_files(project: &Project) -> BTreeSet<PathBuf> {
    project
        .all_tracks()
        .flat_map(|t| &t.clips)
        .flat_map(|c| custom_files(c))
        .filter_map(|(file, derived)| derived.then_some(file))
        .collect()
}

/// The directory a project file is in, as an absolute path.
fn project_dir(path: &Path) -> PathBuf {
    let path = std::path::absolute(path).unwrap_or_else(|_| path.to_path_buf());
    path.parent().map(Path::to_path_buf).unwrap_or_default()
}

/// `path` without `.` and `..` steps, so that prefixes compare as they should.
fn tidy(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                if !out.pop() {
                    out.push("..");
                }
            }
            other => out.push(other),
        }
    }
    out
}

/// The project as it is written to `path`: files inside the project's
/// directory tree by a path relative to it, others as they are.
pub fn for_file(project: &Project, path: &Path) -> Project {
    let dir = tidy(&project_dir(path));
    let mut out = project.clone();
    map_files(&mut out, |file| {
        let file = tidy(file);
        file.strip_prefix(&dir)
            .ok()
            .filter(|rel| !rel.as_os_str().is_empty())
            .map(Path::to_path_buf)
    });
    out
}

/// What happened to a project's files on opening it.
#[derive(Default)]
pub struct Found {
    /// Files found somewhere other than where the project said: (was, now).
    pub moved: Vec<(PathBuf, PathBuf)>,
    /// Files that are nowhere to be found, by the path the project gave.
    pub missing: Vec<PathBuf>,
    /// Missing files for which only files with other bytes turned up:
    /// (missing, the first of those).
    pub refused: Vec<(PathBuf, PathBuf)>,
}

/// The result of a search for one missing file.
enum Search {
    Found(PathBuf),
    /// Only files with other bytes: the first of them.
    Refused(PathBuf),
    Nothing,
}

/// A directory tree read once: its files by name and by size.
#[derive(Default)]
struct Tree {
    names: HashMap<OsString, Vec<PathBuf>>,
    sizes: HashMap<u64, Vec<PathBuf>>,
}

/// Looks for missing files by name and size, in directory trees it reads once.
#[derive(Default)]
pub struct Finder {
    /// Directories where missing files have been found, searched first.
    pub dirs: Vec<PathBuf>,
    /// Trees already read, by root.
    trees: HashMap<PathBuf, Tree>,
}

impl Finder {
    /// Read a directory tree into the index, once.
    fn tree(&mut self, root: &Path) -> &Tree {
        self.trees.entry(root.to_path_buf()).or_insert_with(|| {
            let mut tree = Tree::default();
            let mut stack = vec![(root.to_path_buf(), 0usize)];
            let mut seen = 0usize;
            'walk: while let Some((dir, depth)) = stack.pop() {
                let Ok(entries) = std::fs::read_dir(&dir) else {
                    continue;
                };
                for entry in entries.flatten() {
                    seen += 1;
                    if seen > SEARCH_ENTRIES {
                        break 'walk;
                    }
                    let name = entry.file_name();
                    let Ok(kind) = entry.file_type() else {
                        continue;
                    };
                    if kind.is_dir() {
                        if depth < SEARCH_DEPTH && !name.to_string_lossy().starts_with('.') {
                            stack.push((entry.path(), depth + 1));
                        }
                    } else {
                        if let Ok(meta) = entry.metadata() {
                            tree.sizes.entry(meta.len()).or_default().push(entry.path());
                        }
                        tree.names.entry(name).or_default().push(entry.path());
                    }
                }
            }
            // The shallowest first, then by name, so that the choice repeats.
            for paths in tree.names.values_mut().chain(tree.sizes.values_mut()) {
                paths.sort_by_key(|p| (p.components().count(), p.clone()));
            }
            tree
        })
    }

    /// Where a file that is not at `file` is now, looking under `roots`:
    /// relative to each root, beside other files found, by name, then (when
    /// its record is known) by size. With a record, only a file of the same
    /// size and hash is taken.
    fn find(
        &mut self,
        file: &Path,
        roots: &[PathBuf],
        expect: Option<&MediaRecord>,
        sources: &mut Sources,
    ) -> Search {
        let Some(name) = file.file_name().map(OsStr::to_os_string) else {
            return Search::Nothing;
        };
        let mut near: Vec<PathBuf> = Vec::new();
        // Relative to each root: the last few steps of the old path, longest first.
        let parts: Vec<_> = file.components().collect();
        for root in roots {
            for k in (1..=parts.len().min(4)).rev() {
                let mut candidate = root.clone();
                for part in &parts[parts.len() - k..] {
                    candidate.push(part);
                }
                near.push(candidate);
            }
        }
        near.extend(self.dirs.iter().map(|dir| dir.join(&name)));
        let mut refused = None;
        let mut tried = HashSet::new();
        let mut take = |candidate: &Path, sources: &mut Sources| -> bool {
            if !tried.insert(candidate.to_path_buf()) || !candidate.is_file() {
                return false;
            }
            match expect {
                Some(record) if !sources.is(candidate, record) => {
                    refused.get_or_insert_with(|| candidate.to_path_buf());
                    false
                }
                _ => true,
            }
        };
        if let Some(found) = near.into_iter().find(|c| take(c, sources)) {
            return Search::Found(found);
        }
        for root in roots {
            let tree = self.tree(root);
            let by_name = tree.names.get(&name).into_iter().flatten();
            let by_size = expect
                .and_then(|r| tree.sizes.get(&r.size))
                .into_iter()
                .flatten();
            let far: Vec<PathBuf> = by_name.chain(by_size).cloned().collect();
            if let Some(found) = far.into_iter().find(|c| take(c, sources)) {
                return Search::Found(found);
            }
        }
        match refused {
            Some(other) => Search::Refused(other),
            None => Search::Nothing,
        }
    }

    /// Remember where a file turned up, to look there for the others.
    fn found_in(&mut self, path: &Path) {
        if let Some(dir) = path.parent()
            && !self.dirs.iter().any(|d| d == dir)
        {
            self.dirs.push(dir.to_path_buf());
        }
    }

    /// Point every clip whose file is missing at where it is found under
    /// `roots`. Files that are still missing are left as they were.
    pub fn relink(&mut self, project: &mut Project, roots: &[PathBuf], sources: &mut Sources) -> Found {
        let mut found = Found::default();
        let mut moved: HashMap<PathBuf, PathBuf> = HashMap::new();
        let derived = derived_files(project);
        for file in files(project) {
            if file.is_file() {
                continue;
            }
            let expect = sources.record(&file).cloned();
            match self.find(&file, roots, expect.as_ref(), sources) {
                Search::Found(now) => {
                    self.found_in(&now);
                    moved.insert(file.clone(), now.clone());
                    found.moved.push((file, now));
                }
                _ if derived.contains(&file) => {}
                Search::Refused(other) => {
                    found.refused.push((file.clone(), other));
                    found.missing.push(file);
                }
                Search::Nothing => found.missing.push(file),
            }
        }
        map_files(project, |file| moved.get(file).cloned());
        found
    }
}

/// "a.wav, b.wav and 3 more": names for a message.
fn some_names(files: &[PathBuf]) -> String {
    let names: Vec<String> = files
        .iter()
        .take(3)
        .map(|f| {
            f.file_name().map_or_else(
                || f.display().to_string(),
                |n| n.to_string_lossy().into_owned(),
            )
        })
        .collect();
    let more = files.len().saturating_sub(3);
    if more > 0 {
        format!("{} and {more} more", names.join(", "))
    } else {
        names.join(", ")
    }
}

impl Session {
    /// Keep bakes (waveform overviews, `peaks.rs`) in `store` between
    /// runs, or nowhere.
    pub fn set_bakes(&mut self, store: Option<crate::bake::Store>) {
        self.audio.bakes = store;
    }

    /// The bake cache, when there is one.
    pub fn bakes_mut(&mut self) -> Option<&mut crate::bake::Store> {
        self.audio.bakes.as_mut()
    }

    /// Play long files from the disk instead of memory: the decoded sound
    /// of a file larger than `megabytes` is kept in `dir` and read as it is
    /// played (`paw_engine::samples`). With `megabytes` at 0, or no `dir`,
    /// every file is held in memory. Files loaded already stay where they are.
    pub fn set_media_store(&mut self, dir: Option<PathBuf>, megabytes: f64) {
        let store = dir
            .filter(|_| megabytes.is_finite() && megabytes > 0.0)
            .map(|dir| paw_engine::DiskStore {
                dir,
                limit: (megabytes * 1_048_576.0) as u64,
            });
        let same = match (&store, &self.audio.store) {
            (Some(a), Some(b)) => a.dir == b.dir && a.limit == b.limit,
            (None, None) => true,
            _ => false,
        };
        if !same {
            self.audio.store = store;
            // What is loaded next is held as the new setting says; what
            // plays now plays on from where it is.
            self.audio.forget_loaded();
        }
    }

    /// Where long files' decoded sound is kept, and past what size in megabytes.
    pub fn media_store(&self) -> Option<(PathBuf, f64)> {
        let store = self.audio.store.as_ref()?;
        Some((store.dir.clone(), store.limit as f64 / 1_048_576.0))
    }

    /// Bring in from the disk what the song is about to play of the files
    /// that are played from there, so that the audio thread does not have
    /// to wait for it: the next seconds from `beat`, and from the loop's
    /// start when the loop is on.
    pub(super) fn read_ahead_from(&mut self, beat: f64) {
        self.read_ahead_at = std::time::Instant::now();
        if self.audio.store.is_none() {
            return;
        }
        const AHEAD: f64 = 8.0;
        let rate = self.engine.handle.sample_rate as u32;
        let map = self.doc.project.tempo_map();
        let now = map.seconds(beat);
        let mut windows = vec![(now, now + AHEAD)];
        let t = &self.transport;
        if t.loop_enabled && t.loop_end > t.loop_start {
            let start = map.seconds(t.loop_start);
            windows.push((start, start + AHEAD));
        }
        for clip in self.doc.project.all_tracks().flat_map(|t| &t.clips) {
            let ClipContent::Audio { file, offset, .. } = &clip.content else {
                continue;
            };
            let Some(data) = self.audio.playing(file, rate).filter(|d| d.on_disk()) else {
                continue;
            };
            let (begins, ends) = (
                map.seconds(clip.start),
                map.seconds(clip.start + clip.length),
            );
            for (from, to) in &windows {
                let (from, to) = (from.max(begins), to.min(ends));
                if to > from {
                    data.advise(offset + from - begins, offset + to - begins);
                }
            }
        }
    }

    /// [`read_ahead_from`](Self::read_ahead_from) the playhead, a few times
    /// a second while the song plays. Called every turn.
    pub fn read_ahead(&mut self) {
        if self.play.playing && self.read_ahead_at.elapsed() >= std::time::Duration::from_millis(250) {
            self.read_ahead_from(self.position());
        }
    }

    /// Make the paths of a project just read from `path` absolute, and look
    /// for files that are not where it says. Reports what is missing once.
    /// Returns whether a file was found somewhere else or holds other bytes
    /// than the project recorded: the project then differs from its file.
    pub(super) fn find_media(&mut self, project: &mut Project, path: &Path) -> bool {
        let dir = project_dir(path);
        map_files(project, |file| {
            file.is_relative().then(|| tidy(&dir.join(file)))
        });
        let recorded = self.recorded_media(path);
        self.sources.open(recorded);
        let mut finder = Finder::default();
        let found = finder.relink(project, std::slice::from_ref(&dir), &mut self.sources);
        self.report_media(&found);
        let used = sources_of(project);
        let changed = self.sources.check(used.iter().map(PathBuf::as_path));
        let told = !changed.is_empty();
        self.tell_changed(changed);
        !found.moved.is_empty() || told
    }

    /// The media table that the project at `path` recorded: its folder's
    /// `media.json`, by absolute paths. Empty for a project in one file.
    fn recorded_media(&mut self, path: &Path) -> MediaTable {
        if path.file_name().is_none_or(|n| n != PROJECT_FILE) {
            return MediaTable::default();
        }
        let dir = project_dir(path);
        let file = dir.join(MEDIA_FILE);
        let Ok(bytes) = std::fs::read(&file) else {
            return MediaTable::default();
        };
        match MediaTable::from_json(&bytes) {
            Ok(table) => table.renamed(|p| Some(self.home.resolve(p, &dir))),
            Err(e) => {
                self.doc.warnings.push(format!(
                    "{}: {e}; paw learns what each file is again",
                    file.display()
                ));
                MediaTable::default()
            }
        }
    }

    /// Tell once of each file that holds other bytes than the project
    /// recorded: its clips play the new file.
    pub(super) fn tell_changed(&mut self, changed: Vec<Changed>) {
        for Changed(path) in changed {
            self.doc.warnings.push(format!(
                "{} changed since the project was saved: its clips play the new file",
                some_names(std::slice::from_ref(&path))
            ));
        }
    }

    /// Take what the background hashing learned, and give it the files
    /// that the project uses and nothing knows yet (an import, a
    /// recording). Called every turn.
    pub fn poll_media(&mut self) {
        let changed = self.sources.poll();
        if self.sources.due() {
            let used = sources_of(&self.doc.project);
            self.sources.notice(used.iter().map(PathBuf::as_path));
        }
        if !changed.is_empty() {
            self.doc.undo.touched = true;
            self.tell_changed(changed);
        }
    }

    /// The `media.json` of the project for its folder `dir`: a record of
    /// each file the project uses, under the path the clips name it by in
    /// the folder. A file with no record yet is hashed now: a save names
    /// every file that is there by its hash.
    pub(super) fn media_for_folder(&mut self, dir: &Path) -> MediaTable {
        let used = sources_of(&self.doc.project);
        let changed = self.sources.complete(used.iter().map(PathBuf::as_path));
        if !changed.is_empty() {
            self.doc.undo.touched = true;
            self.tell_changed(changed);
        }
        let dir = tidy(dir);
        self.sources.table().renamed(|path| {
            used.contains(path).then(|| {
                tidy(path)
                    .strip_prefix(&dir)
                    .ok()
                    .filter(|rel| !rel.as_os_str().is_empty())
                    .map_or_else(|| path.to_path_buf(), Path::to_path_buf)
            })
        })
    }

    /// Say what was found and what is missing, in one message each.
    fn report_media(&mut self, found: &Found) {
        if !found.moved.is_empty() {
            let files: Vec<PathBuf> = found.moved.iter().map(|m| m.0.clone()).collect();
            self.doc.warnings.push(format!(
                "found {} moved media file{} ({}); save to keep the new place",
                files.len(),
                if files.len() == 1 { "" } else { "s" },
                some_names(&files)
            ));
        }
        self.report_refused(found);
        if !found.missing.is_empty() {
            self.doc.warnings.push(format!(
                "{} media file{} missing ({}): {} clips are offline; :media.relink finds them",
                found.missing.len(),
                if found.missing.len() == 1 {
                    " is"
                } else {
                    "s are"
                },
                some_names(&found.missing),
                if found.missing.len() == 1 {
                    "its"
                } else {
                    "their"
                },
            ));
        }
        if !found.missing.is_empty() || !found.moved.is_empty() {
            let missing = MediaMissing { files: found.missing.clone(), found: found.moved.len() };
            self.doc.emit(E::MediaMissing(missing));
        }
    }

    /// One message for each file that a search did not take because it
    /// holds other bytes than the missing file did.
    fn report_refused(&mut self, found: &Found) {
        for (missing, other) in &found.refused {
            self.doc.warnings.push(other_sound(missing, other));
        }
    }

    /// Files the project's clips play that are not there, once each.
    pub fn media_missing(&self) -> Vec<PathBuf> {
        let derived = derived_files(&self.doc.project);
        files(&self.doc.project)
            .into_iter()
            .filter(|f| !f.is_file() && !derived.contains(f))
            .collect()
    }

    /// Every file the project's clips play: `{ path, missing, inside,
    /// on_disk, hash, size }`, `inside` when it is in the project's
    /// directory tree, `hash` and `size` once they are known.
    pub fn media_list(&self) -> Value {
        let dir = self.path.as_deref().map(|p| tidy(&project_dir(p)));
        Value::Array(
            files(&self.doc.project)
                .into_iter()
                .map(|f| {
                    let inside = dir.as_ref().is_some_and(|d| tidy(&f).starts_with(d));
                    // Played from the disk, not held in memory (long files).
                    let on_disk = self.audio.on_disk(&f).unwrap_or(false);
                    let record = self.sources.record(&f);
                    json!({
                        "path": f, "missing": !f.is_file(), "inside": inside,
                        "on_disk": on_disk,
                        "hash": record.map(|r| r.hash.to_string()),
                        "size": record.map(|r| r.size),
                    })
                })
                .collect(),
        )
    }

    /// Point the clips that play `from` at `to`, and look beside `to` for
    /// the other missing files. One undo step. Returns `{ clips, found, missing }`.
    /// A file with other bytes than `from` had is refused unless `anyway`:
    /// it becomes a new source.
    pub fn media_relink(&mut self, from: &Path, to: &Path, anyway: bool) -> Result<Value> {
        let to = std::path::absolute(to).unwrap_or_else(|_| to.to_path_buf());
        if !to.is_file() {
            bail!("{} is not a file", to.display());
        }
        paw_engine::AudioData::load(&to)?;
        if !files(&self.doc.project).contains(from) {
            bail!("no clip plays {}", from.display());
        }
        if !anyway
            && let Some(record) = self.sources.record(from).cloned()
            && !self.sources.is(&to, &record)
        {
            bail!("{}", other_sound(from, &to));
        }
        let clips = self.edit(|p| Ok(map_files(p, |f| (f == from).then(|| to.clone()))))?;
        let dir = to.parent().map(Path::to_path_buf).unwrap_or_default();
        let mut result = self.media_search(&dir)?;
        result["clips"] = json!(clips);
        Ok(result)
    }

    /// Look for every missing file in a directory tree, and point the clips
    /// at what is found. One undo step. Returns `{ found, missing }`.
    pub fn media_search(&mut self, dir: &Path) -> Result<Value> {
        if !dir.is_dir() {
            bail!("{} is not a directory", dir.display());
        }
        let dir = std::path::absolute(dir).unwrap_or_else(|_| dir.to_path_buf());
        let mut finder = Finder {
            dirs: vec![dir.clone()],
            ..Default::default()
        };
        let mut project = self.doc.project.clone();
        let found = finder.relink(&mut project, &[dir], &mut self.sources);
        self.report_refused(&found);
        if !found.moved.is_empty() {
            let moved: HashMap<PathBuf, PathBuf> = found.moved.iter().cloned().collect();
            self.edit(|p| Ok(map_files(p, |f| moved.get(f).cloned())))?;
        }
        Ok(json!({
            "found": found.moved.len(),
            "missing": found.missing,
        }))
    }

    /// Copy every file the project plays from outside its directory tree
    /// into `media` beside the project file, and point the clips at the
    /// copies. The originals stay. A file with the same bytes as one the
    /// project has in its folder already, or as one copied before it, is
    /// not copied again: its clips play that one. One undo step. Returns
    /// `{ copied, same, missing, dir }`.
    pub fn media_collect(&mut self) -> Result<Value> {
        let path = self.path.clone().context(
            "the project has no file yet: save it first, so that its files have somewhere to go",
        )?;
        let dir = tidy(&project_dir(&path));
        let media = dir.join("media");
        let mut copies: HashMap<PathBuf, PathBuf> = HashMap::new();
        let mut missing = Vec::new();
        let used = sources_of(&self.doc.project);
        let (inside, outside): (Vec<&PathBuf>, Vec<&PathBuf>) =
            used.iter().partition(|f| tidy(f).starts_with(&dir));
        // The project's own files, by their bytes.
        let mut have: HashMap<SourceHash, PathBuf> = HashMap::new();
        for file in inside {
            if let Ok(hash) = self.sources.hash_now(file) {
                have.entry(hash).or_insert_with(|| file.clone());
            }
        }
        let mut same = 0;
        for file in outside {
            if !file.is_file() {
                missing.push(file.clone());
                continue;
            }
            let hash = self
                .sources
                .hash_now(file)
                .with_context(|| format!("reading {}", file.display()))?;
            if let Some(copy) = have.get(&hash) {
                copies.insert(file.clone(), copy.clone());
                same += 1;
                continue;
            }
            let copy = copy_into(file, &media, &mut self.sources)?;
            have.insert(hash, copy.clone());
            copies.insert(file.clone(), copy);
        }
        if !copies.is_empty() {
            self.edit(|p| Ok(map_files(p, |f| copies.get(f).cloned())))?;
        }
        Ok(json!({ "copied": copies.len() - same, "same": same, "missing": missing, "dir": media }))
    }

    /// Copy a file into `media` beside the project, for importing with
    /// `paw.opt.copy_imports` on. Gives the copy, or the file itself when it
    /// is in the project's tree already or the project has no file.
    pub fn media_adopt(&mut self, file: &Path) -> Result<PathBuf> {
        let Some(path) = self.path.clone() else {
            return Ok(file.to_path_buf());
        };
        let file = std::path::absolute(file).unwrap_or_else(|_| file.to_path_buf());
        let dir = tidy(&project_dir(&path));
        if tidy(&file).starts_with(&dir) {
            return Ok(file);
        }
        copy_into(&file, &dir.join("media"), &mut self.sources)
    }
}

/// The file a project folder keeps its media table in.
pub const MEDIA_FILE: &str = "media.json";

/// The files of a project that are sources: every file it plays, without
/// those that a kind of clip makes again when they are not there.
fn sources_of(project: &Project) -> BTreeSet<PathBuf> {
    let derived = derived_files(project);
    files(project)
        .into_iter()
        .filter(|f| !derived.contains(f))
        .collect()
}

/// The message for a file that holds other bytes than `missing` did.
fn other_sound(missing: &Path, other: &Path) -> String {
    if missing.file_name() == other.file_name() {
        format!("{} has the same name but other sound", other.display())
    } else {
        format!(
            "{} has other sound than {} had",
            other.display(),
            some_names(&[missing.to_path_buf()])
        )
    }
}

/// Copy `file` into `dir` under its own name, or with a number added when a
/// different file has that name there already. A file with the same bytes
/// there already is used. The copy is hashed as it is written.
fn copy_into(file: &Path, dir: &Path, sources: &mut Sources) -> Result<PathBuf> {
    std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
    let stem = file.file_stem().unwrap_or_default().to_string_lossy();
    let ext = file
        .extension()
        .map(|e| format!(".{}", e.to_string_lossy()))
        .unwrap_or_default();
    let size = std::fs::metadata(file)?.len();
    let mut n = 1;
    loop {
        let name = if n == 1 {
            format!("{stem}{ext}")
        } else {
            format!("{stem}-{n}{ext}")
        };
        let target = dir.join(name);
        match std::fs::metadata(&target) {
            Ok(meta) if meta.len() == size && same_bytes(file, &target, sources) => {
                return Ok(target);
            }
            Ok(_) => n += 1,
            Err(_) => {
                // Copy beside it and rename, so that a full disk leaves no half file.
                let tmp = dir.join(format!(".{stem}{ext}.part"));
                let hash = copy_hashing(file, &tmp)
                    .with_context(|| format!("copying {} to {}", file.display(), dir.display()))?;
                std::fs::rename(&tmp, &target)
                    .with_context(|| format!("writing {}", target.display()))?;
                sources.wrote(&target, hash);
                return Ok(target);
            }
        }
    }
}

/// Copy `from` to `to`, hashing the bytes as they pass.
fn copy_hashing(from: &Path, to: &Path) -> std::io::Result<SourceHash> {
    let mut source = std::fs::File::open(from)?;
    let mut out = Hashing::new(std::fs::File::create(to)?);
    std::io::copy(&mut source, &mut out)?;
    let (file, hash) = out.finish();
    file.sync_all()?;
    Ok(hash.into())
}

fn same_bytes(a: &Path, b: &Path, sources: &mut Sources) -> bool {
    match (sources.hash_now(a), sources.hash_now(b)) {
        (Ok(a), Ok(b)) => a == b,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_inside_the_project_are_written_relative() {
        let mut p = Project::default();
        Arc::make_mut(&mut p.master).clips = vec![
            Arc::new(clip(1, "/songs/a/media/x.wav")),
            Arc::new(clip(2, "/elsewhere/y.wav")),
            Arc::new(clip(3, "/songs/a/../a/z.wav")),
        ]
        .into();
        let out = for_file(&p, Path::new("/songs/a/song.json"));
        let got: Vec<PathBuf> = out
            .master
            .clips
            .iter()
            .map(|c| match &c.content {
                ClipContent::Audio { file, .. } => file.clone(),
                _ => unreachable!(),
            })
            .collect();
        assert_eq!(
            got,
            [
                PathBuf::from("media/x.wav"),
                PathBuf::from("/elsewhere/y.wav"),
                PathBuf::from("z.wav")
            ]
        );
    }

    #[test]
    fn a_custom_clips_media_are_handled_like_sound_files() {
        let content = serde_json::json!({
            "kind": "custom", "type": "video", "data": { "json": "{}" },
            "media": [
                { "role": "source", "path": "/songs/a/media/film.mp4" },
                { "role": "proxy", "path": "/cache/video-3f9a.flac", "derived": true },
            ],
            "sound": { "kind": "audio", "file": "/elsewhere/mix.wav", "offset": 0.0, "gain": 0.0 },
        });
        let mut c = clip(1, "");
        c.content = serde_json::from_value(content).unwrap();
        let mut p = Project::default();
        Arc::make_mut(&mut p.master).clips = vec![Arc::new(c)].into();
        assert_eq!(files(&p).len(), 3);
        assert_eq!(derived_files(&p), BTreeSet::from([PathBuf::from("/cache/video-3f9a.flac")]));
        let out = for_file(&p, Path::new("/songs/a/project.toml"));
        let got: Vec<PathBuf> = files(&out).into_iter().collect();
        assert!(got.contains(&PathBuf::from("media/film.mp4")), "{got:?}");
        assert!(got.contains(&PathBuf::from("/elsewhere/mix.wav")), "{got:?}");
    }

    /// A project in `dir` whose one clip plays `media/take.wav`, which held
    /// `bytes` when the project recorded it, and which is gone now.
    fn lost_take(dir: &Path, bytes: &[u8]) -> (Project, Sources) {
        let file = dir.join("media/take.wav");
        std::fs::create_dir_all(file.parent().unwrap()).unwrap();
        std::fs::write(&file, bytes).unwrap();
        let mut sources = Sources::default();
        sources.complete([file.as_path()]);
        std::fs::remove_file(&file).unwrap();
        let mut p = Project::default();
        Arc::make_mut(&mut p.master).clips = vec![Arc::new(clip(1, file.to_str().unwrap()))].into();
        (p, sources)
    }

    fn put(path: &Path, bytes: &[u8]) {
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, bytes).unwrap();
    }

    #[test]
    fn a_moved_and_renamed_file_is_found_by_its_hash() {
        let dir = tempfile::tempdir().unwrap();
        let (mut p, mut sources) = lost_take(dir.path(), b"the take's bytes");
        // The same size, other bytes: not it.
        put(&dir.path().join("a/decoy.wav"), b"other bytes 1234");
        put(&dir.path().join("b/renamed.wav"), b"the take's bytes");
        let found = Finder::default().relink(&mut p, &[dir.path().to_path_buf()], &mut sources);
        assert_eq!(found.missing, Vec::<PathBuf>::new());
        assert_eq!(files(&p), BTreeSet::from([dir.path().join("b/renamed.wav")]));
    }

    #[test]
    fn a_file_of_the_same_name_with_other_bytes_is_refused() {
        let dir = tempfile::tempdir().unwrap();
        let (mut p, mut sources) = lost_take(dir.path(), b"the take's bytes");
        let other = dir.path().join("old/take.wav");
        put(&other, b"another take");
        let found = Finder::default().relink(&mut p, &[dir.path().to_path_buf()], &mut sources);
        let lost = dir.path().join("media/take.wav");
        assert_eq!(found.missing, [lost.clone()]);
        assert_eq!(found.refused, [(lost.clone(), other.clone())]);
        assert_eq!(files(&p), BTreeSet::from([lost.clone()]), "the clip keeps its path");
        assert!(other_sound(&lost, &other).ends_with("take.wav has the same name but other sound"));
    }

    fn clip(id: u64, file: &str) -> crate::model::Clip {
        crate::model::Clip {
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
            id,
            name: String::new(),
            start: 0.0,
            length: 1.0,
            muted: false,
            content: ClipContent::Audio {
                file: file.into(),
                offset: 0.0,
                gain: 0.0,
                edits: Vec::new(),
            },
            fade_in: 0.0,
            fade_out: 0.0,
            meta: Default::default(),
            source: None,
            origin: None,
            link: None,
            overrides: Default::default(),
        }
    }
}
