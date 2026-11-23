//! The sources of the open project: its media table, kept true against the
//! files on the disk with the local index and the background worker.

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use super::index::{LocalIndex, Stamp};
use super::table::{MediaRecord, MediaTable, Probe, SourceHash};
use super::worker::{Job, Learned, Worker};

/// The media table of the open project, and how it learns hashes.
#[derive(Default)]
pub struct Sources {
    /// By absolute path. Records stay when a clip stops using a file (an
    /// undo brings it back); a save writes only those the project uses.
    table: MediaTable,
    /// Opened on first use.
    index: Option<LocalIndex>,
    /// Where the index is kept between runs. The kernel sets it
    /// ([`keep_index_in`](Self::keep_index_in)); `None` keeps the index in
    /// memory only, as in the unit tests.
    index_file: Option<PathBuf>,
    worker: Option<Worker>,
    /// Files the worker has and has not answered for yet.
    pending: HashSet<PathBuf>,
    /// Files told as changed, with their new hash: each is told once.
    told: HashSet<(PathBuf, SourceHash)>,
    /// Files given to the worker by [`notice`](Self::notice), once each.
    noticed: HashSet<PathBuf>,
    /// When [`due`](Self::due) last said yes.
    looked: Option<Instant>,
}

/// How often the project is looked through for files that are new.
const LOOK_EVERY: Duration = Duration::from_millis(500);

/// A source whose bytes are not those the project recorded: the clips play
/// the new file, and the user is told once.
#[derive(Debug, PartialEq)]
pub struct Changed(pub PathBuf);

impl Sources {
    pub fn table(&self) -> &MediaTable {
        &self.table
    }

    pub fn record(&self, path: &Path) -> Option<&MediaRecord> {
        self.table.get(path).map(|r| &**r)
    }

    /// Whether the worker has `path` and has not answered for it yet.
    pub fn is_hashing(&self, path: &Path) -> bool {
        self.pending.contains(path)
    }

    /// Whether it is time to look for new files again (twice a second).
    pub fn due(&mut self) -> bool {
        let now = Instant::now();
        let due = self.looked.is_none_or(|at| now.duration_since(at) >= LOOK_EVERY);
        if due {
            self.looked = Some(now);
        }
        due
    }

    /// Keep the local index in `file` between runs. It takes effect before
    /// the index is first used.
    pub fn keep_index_in(&mut self, file: PathBuf) {
        self.index_file = Some(file);
    }

    fn index(&mut self) -> &mut LocalIndex {
        let file = &self.index_file;
        self.index.get_or_insert_with(|| LocalIndex::open(file.clone()))
    }

    /// Start again from what a project recorded (its `media.json`).
    pub fn open(&mut self, recorded: MediaTable) {
        self.table = recorded;
        self.pending.clear();
    }

    /// Check each file against the index, by one `stat`: a file this machine
    /// hashed as it is now is known at once; any other goes to the worker.
    /// A missing file keeps its record, for relinking by hash.
    pub fn check<'a>(&mut self, files: impl IntoIterator<Item = &'a Path>) -> Vec<Changed> {
        let mut changed = Vec::new();
        self.noticed.clear();
        for path in files {
            if self.pending.contains(path) {
                continue;
            }
            let Some(stamp) = Stamp::read(path) else {
                continue;
            };
            let known = self.index().get(path, &stamp);
            let record = self.table.get(path);
            match (known, record) {
                (Some(hash), Some(r)) if r.hash == hash && r.size == stamp.size => {}
                (Some(hash), Some(_)) => {
                    // Another file than recorded: told now, its header read again.
                    changed.extend(self.learned(path.to_path_buf(), stamp, hash, None));
                    self.queue(path, Some((stamp, hash)));
                }
                (known, _) => self.queue(path, known.map(|h| (stamp, h))),
            }
        }
        changed
    }

    /// Give the worker the files that have no record yet (an import, a
    /// recording), once each. Files it could not read are not tried again
    /// until the next [`check`](Self::check).
    pub fn notice<'a>(&mut self, files: impl IntoIterator<Item = &'a Path>) {
        for path in files {
            if self.table.get(path).is_none()
                && !self.pending.contains(path)
                && self.noticed.insert(path.to_path_buf())
            {
                self.queue(path, None);
            }
        }
    }

    fn queue(&mut self, path: &Path, known: Option<(Stamp, SourceHash)>) {
        if self.worker.is_none() {
            self.worker = Worker::start().ok();
        }
        let Some(worker) = &self.worker else { return };
        if worker.send(Job { path: path.to_path_buf(), known }) {
            self.pending.insert(path.to_path_buf());
        }
    }

    /// Take what the worker learned. The index is written when the worker
    /// has nothing left to do.
    pub fn poll(&mut self) -> Vec<Changed> {
        let Some(worker) = self.worker.take() else {
            return Vec::new();
        };
        let learned: Vec<Learned> = worker.take().collect();
        self.worker = Some(worker);
        let changed = learned.into_iter().filter_map(|l| self.apply(l)).collect();
        self.settle();
        changed
    }

    /// Wait for the worker to finish what it has (for tests and the end of
    /// a run).
    pub fn finish(&mut self) -> Vec<Changed> {
        let mut changed = Vec::new();
        while !self.pending.is_empty() {
            let Some(learned) = self.worker.as_ref().and_then(Worker::wait) else {
                self.pending.clear();
                break;
            };
            changed.extend(self.apply(learned));
        }
        self.settle();
        changed
    }

    fn settle(&mut self) {
        // The index is only a shortcut: one that cannot be written is
        // made again by hashing.
        if self.pending.is_empty()
            && let Some(index) = &mut self.index
        {
            let _ = index.save();
        }
    }

    fn apply(&mut self, learned: Learned) -> Option<Changed> {
        self.pending.remove(&learned.path);
        let (stamp, hash, probe) = learned.result.ok()?;
        self.learned(learned.path, stamp, hash, Some(probe))
    }

    /// Note what a file is: in the index, and in the table. A recorded hash
    /// that differs is a file changed under the project.
    fn learned(
        &mut self,
        path: PathBuf,
        stamp: Stamp,
        hash: SourceHash,
        probe: Option<Probe>,
    ) -> Option<Changed> {
        self.index().put(path.clone(), stamp, hash);
        let old = self.table.get(&path).cloned();
        let probe = match (probe, &old) {
            (Some(p), _) => p,
            (None, Some(r)) if r.hash == hash => r.probe.clone(),
            (None, _) => Probe::default(),
        };
        let record = MediaRecord { hash, size: stamp.size, probe };
        if old.as_deref() == Some(&record) {
            return None;
        }
        self.table.insert(path.clone(), record);
        let other = old.is_some_and(|r| r.hash != hash);
        (other && self.told.insert((path.clone(), hash))).then_some(Changed(path))
    }

    /// The hash of the file at `path` as it is now: from the index, or
    /// hashed here and now (relink, collect and save, which need it).
    pub fn hash_now(&mut self, path: &Path) -> std::io::Result<SourceHash> {
        let stamp = Stamp::read(path).ok_or_else(|| std::io::Error::from(std::io::ErrorKind::NotFound))?;
        if let Some(hash) = self.index().get(path, &stamp) {
            return Ok(hash);
        }
        let hash = SourceHash::of_file(path)?;
        self.index().put(path.to_path_buf(), stamp, hash);
        Ok(hash)
    }

    /// A record for each file that is there and has none, hashed here and
    /// now: a save names every file it can by its hash. The worker's files
    /// keep the record they have until it answers.
    pub fn complete<'a>(&mut self, files: impl IntoIterator<Item = &'a Path>) -> Vec<Changed> {
        let mut changed = self.poll();
        for path in files {
            if self.table.get(path).is_some() {
                continue;
            }
            let Some(stamp) = Stamp::read(path) else { continue };
            let Ok(hash) = self.hash_now(path) else { continue };
            changed.extend(self.learned(path.to_path_buf(), stamp, hash, Some(Probe::of_file(path))));
        }
        self.settle();
        changed
    }

    /// Note a file that paw just wrote with the hash of its bytes (a copy).
    pub fn wrote(&mut self, path: &Path, hash: SourceHash) {
        if let Some(stamp) = Stamp::read(path) {
            let probe = self
                .table
                .iter()
                .find(|(_, r)| r.hash == hash)
                .map(|(_, r)| r.probe.clone());
            let probe = probe.unwrap_or_else(|| Probe::of_file(path));
            self.learned(path.to_path_buf(), stamp, hash, Some(probe));
        }
    }

    /// Whether the file at `path` is the source `record` names: the same
    /// size, then the same hash.
    pub fn is(&mut self, path: &Path, record: &MediaRecord) -> bool {
        Stamp::read(path).is_some_and(|s| s.size == record.size)
            && self.hash_now(path).is_ok_and(|h| h == record.hash)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_file_changed_under_the_project_is_followed_and_told_once() {
        let dir = tempfile::tempdir().unwrap();
        let wav = dir.path().join("a.wav");
        std::fs::write(&wav, b"before").unwrap();
        let mut sources = Sources::default();
        sources.complete([wav.as_path()]);
        let before = sources.record(&wav).unwrap().hash;
        let recorded = sources.table().clone();
        std::fs::write(&wav, b"after, longer").unwrap();
        sources.open(recorded.clone());
        let mut changed = sources.check([wav.as_path()]);
        changed.extend(sources.finish());
        assert_eq!(changed, [Changed(wav.clone())]);
        let now = sources.record(&wav).unwrap();
        assert_ne!(now.hash, before);
        assert_eq!(now.size, 13);
        // Opened again from the old record: the same change is not told twice.
        sources.open(recorded);
        let mut again = sources.check([wav.as_path()]);
        again.extend(sources.finish());
        assert_eq!(again, []);
        assert_ne!(sources.record(&wav).unwrap().hash, before);
    }
}
