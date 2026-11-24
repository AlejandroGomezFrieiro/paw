//! The bake cache: one folder for all projects of the user,
//! `$XDG_CACHE_HOME/paw/bakes`, of entries named by their [`EntryKey`].
//!
//! ```text
//! bakes/3f/3f9a…c1/meta.json   what was asked, who made it, when, how big
//!                  peaks.bin   the entry's own files
//! bakes/tmp/<entry>.<pid>/     an entry being written, renamed into place whole
//! bakes/tmp/<entry>.lock       held while one process writes the entry
//! ```
//!
//! An entry is used and evicted as a whole. Eviction goes by the time of
//! last use (the mtime of `meta.json`, set on each [`Store::open`]) and
//! never takes a pinned entry. Nothing here is the user's: the whole folder
//! can go at any time.
#![expect(clippy::allow_attributes, reason = "debt: pay down")]

use std::collections::HashSet;
use std::fs::{self, File};
use std::io;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::key::{BakeJob, EntryKey};

/// The size of the cache when the user sets none: 16 GB.
pub(crate) const DEFAULT_LIMIT: u64 = 16 << 30;

/// An unfinished entry this old was left by a run that ended badly.
const STALE: Duration = Duration::from_secs(3600);

/// The cache.
#[derive(Clone, Debug)]
pub(crate) struct Store {
    root: PathBuf,
    /// The bytes kept by [`tidy`](Self::tidy), pins aside.
    pub limit: u64,
}

/// What an entry says of itself, in its `meta.json`.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct EntryMeta {
    /// The whole input key, compared on each open (the name has 128 bits).
    pub input_key: String,
    pub tool: String,
    /// The job, for a person who looks.
    pub job: Value,
    /// When it was made, in seconds since 1970.
    pub made: u64,
    /// The bytes of its files.
    pub bytes: u64,
}

/// An entry that is there, whole.
#[derive(Debug)]
pub(crate) struct Entry {
    dir: PathBuf,
    #[allow(dead_code, reason = "read by the tests only, until the helper lane has a bake")]
    pub meta: EntryMeta,
}

impl Entry {
    /// The entry's file `name`.
    pub(crate) fn file(&self, name: &str) -> PathBuf {
        self.dir.join(name)
    }
}

/// What [`Store::writer`] found.
pub(crate) enum Write {
    /// Make the entry: write its files, then [`EntryWriter::commit`].
    Make(EntryWriter),
    /// It is there already (another process made it meanwhile).
    Done(Entry),
    /// Another process on this machine makes it now.
    Busy,
}

/// An entry being made, in a folder of its own under `tmp/`. Dropped
/// without [`commit`](Self::commit), it leaves nothing behind.
pub(crate) struct EntryWriter {
    tmp: PathBuf,
    dest: PathBuf,
    key: EntryKey,
    job: Value,
    lock: Option<(File, PathBuf)>,
}

impl EntryWriter {
    /// Where to write the entry's file `name`.
    pub(crate) fn file(&self, name: &str) -> PathBuf {
        self.tmp.join(name)
    }

    /// Put the entry in place, whole. When another process put the same
    /// entry first, its copy stays: the content is the same.
    pub(crate) fn commit(mut self) -> io::Result<Entry> {
        let bytes = dir_bytes(&self.tmp);
        let made = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| d.as_secs());
        let meta = EntryMeta {
            input_key: self.key.input.to_string(),
            tool: self.key.tool.clone(),
            job: std::mem::take(&mut self.job),
            made,
            bytes,
        };
        fs::write(self.tmp.join(META), serde_json::to_vec_pretty(&meta)?)?;
        if let Some(parent) = self.dest.parent() {
            fs::create_dir_all(parent)?;
        }
        if fs::rename(&self.tmp, &self.dest).is_err() && !self.dest.join(META).is_file() {
            return Err(io::Error::other(format!(
                "cannot put the bake {} in place",
                self.dest.display()
            )));
        }
        Ok(Entry {
            dir: self.dest.clone(),
            meta,
        })
    }
}

impl Drop for EntryWriter {
    fn drop(&mut self) {
        // Gone after a commit; a failed or cancelled bake's files go here.
        let _ = fs::remove_dir_all(&self.tmp);
        if let Some((lock, path)) = self.lock.take() {
            let _ = fs::remove_file(path);
            drop(lock);
        }
    }
}

const META: &str = "meta.json";

/// What [`Store::tidy`] did.
#[derive(Debug, Default, PartialEq, Eq)]
pub(crate) struct Tidied {
    pub removed: usize,
    /// The bytes kept, pinned ones too.
    pub kept: u64,
    /// The bytes of pinned entries.
    pub pinned: u64,
}

impl Tidied {
    /// The pinned entries alone are more than the limit: the caller says
    /// so, once.
    pub(crate) fn over(&self, limit: u64) -> bool {
        self.pinned > limit
    }
}

impl Store {
    pub(crate) fn new(root: PathBuf, limit: u64) -> Self {
        Self { root, limit }
    }

    /// The user's cache, `$XDG_CACHE_HOME/paw/bakes`, of 16 GB.
    pub(crate) fn user(dirs: &paw_proto::dirs::Dirs) -> Self {
        Self::new(dirs.paw_cache().join("bakes"), DEFAULT_LIMIT)
    }

    pub(crate) fn root(&self) -> &Path {
        &self.root
    }

    fn dir(&self, id: &str) -> PathBuf {
        self.root.join(&id[..2]).join(id)
    }

    /// The entry of `key` when it is there whole, marked as used now.
    pub(crate) fn open(&self, key: &EntryKey) -> Option<Entry> {
        let dir = self.dir(&key.id());
        let meta_path = dir.join(META);
        let meta: EntryMeta = serde_json::from_slice(&fs::read(&meta_path).ok()?).ok()?;
        if meta.input_key != key.input.to_string() || meta.tool != key.tool {
            return None;
        }
        // Used now: the last to be evicted.
        if let Ok(file) = File::options().append(true).open(&meta_path) {
            let _ = file.set_modified(SystemTime::now());
        }
        Some(Entry { dir, meta })
    }

    /// Start to make the entry of `key` for `job`, unless it is there or
    /// another process on this machine makes it now.
    pub(crate) fn writer(&self, job: &BakeJob, key: &EntryKey) -> io::Result<Write> {
        let id = key.id();
        let tmp_root = self.root.join("tmp");
        fs::create_dir_all(&tmp_root)?;
        let lock_path = tmp_root.join(format!("{id}.lock"));
        let lock = File::create(&lock_path)?;
        match lock.try_lock() {
            Ok(()) => {}
            Err(fs::TryLockError::WouldBlock) => return Ok(Write::Busy),
            Err(fs::TryLockError::Error(err)) => return Err(err),
        }
        // Made by another while this one waited for the lock.
        if let Some(entry) = self.open(key) {
            let _ = fs::remove_file(&lock_path);
            return Ok(Write::Done(entry));
        }
        let tmp = tmp_root.join(format!("{id}.{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp)?;
        Ok(Write::Make(EntryWriter {
            tmp,
            dest: self.dir(&id),
            key: key.clone(),
            job: serde_json::to_value(job)?,
            lock: Some((lock, lock_path)),
        }))
    }

    /// Evict the entries used longest ago until the rest fit in
    /// [`limit`](Self::limit) bytes. Pinned entries (by [`EntryKey::id`])
    /// stay whatever their size. Unfinished entries left by a run that ended
    /// badly go too. An entry in use stays readable by whoever has it open.
    pub(crate) fn tidy(&self, pinned: &HashSet<String>) -> Tidied {
        self.sweep_tmp();
        let mut entries: Vec<(SystemTime, PathBuf, u64, bool)> = Vec::new();
        let shards = fs::read_dir(&self.root).into_iter().flatten().flatten();
        for shard in shards.filter(|s| s.file_name().len() == 2) {
            for entry in fs::read_dir(shard.path()).into_iter().flatten().flatten() {
                let dir = entry.path();
                let used = fs::metadata(dir.join(META))
                    .and_then(|m| m.modified())
                    .unwrap_or(UNIX_EPOCH);
                let pin = pinned.contains(entry.file_name().to_string_lossy().as_ref());
                entries.push((used, dir.clone(), dir_bytes(&dir), pin));
            }
        }
        let mut tidied = Tidied::default();
        tidied.pinned = entries.iter().filter(|e| e.3).map(|e| e.2).sum();
        tidied.kept = tidied.pinned;
        entries.sort_by_key(|e| std::cmp::Reverse(e.0));
        for (_, dir, bytes, pin) in entries {
            if pin {
                continue;
            }
            if tidied.kept + bytes <= self.limit {
                tidied.kept += bytes;
            } else if fs::remove_dir_all(&dir).is_ok() {
                tidied.removed += 1;
            }
        }
        tidied
    }

    /// Remove what runs that ended badly left in `tmp/`.
    fn sweep_tmp(&self) {
        let tmp = fs::read_dir(self.root.join("tmp")).into_iter().flatten().flatten();
        for item in tmp {
            let old = item
                .metadata()
                .and_then(|m| m.modified())
                .ok()
                .and_then(|t| t.elapsed().ok())
                .is_some_and(|age| age > STALE);
            if old {
                let path = item.path();
                let _ = fs::remove_dir_all(&path).or_else(|_| fs::remove_file(&path));
            }
        }
    }
}

/// The bytes of the files in `dir`.
fn dir_bytes(dir: &Path) -> u64 {
    fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|f| f.metadata().ok())
        .filter(|m| m.is_file())
        .map(|m| m.len())
        .sum()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bake::key::{Output, Stream};

    fn job(n: u32) -> (BakeJob, EntryKey) {
        let job = BakeJob {
            op: "test".into(),
            version: n,
            params: Value::Null,
            inputs: vec![],
            output: Output {
                stream: Stream::Data,
                rate: None,
                format: None,
            },
        };
        let key = EntryKey::new(&job, "paw.test/1");
        (job, key)
    }

    fn make(store: &Store, n: u32, bytes: usize) -> EntryKey {
        let (job, key) = job(n);
        let Write::Make(writer) = store.writer(&job, &key).unwrap() else {
            panic!("a new entry is made");
        };
        fs::write(writer.file("out.bin"), vec![0u8; bytes]).unwrap();
        writer.commit().unwrap();
        key
    }

    #[test]
    fn eviction_takes_the_oldest_and_keeps_pinned_entries() {
        let dir = tempfile::tempdir().unwrap();
        let mut store = Store::new(dir.path().join("bakes"), u64::MAX);
        let keys: Vec<_> = (0..4).map(|n| make(&store, n, 1000)).collect();
        // Used in the order 0, 1, 2, 3: 0 is the oldest.
        for (i, key) in keys.iter().enumerate() {
            let meta = store.dir(&key.id()).join(META);
            File::options()
                .append(true)
                .open(meta)
                .unwrap()
                .set_modified(UNIX_EPOCH + Duration::from_secs(1000 + i as u64))
                .unwrap();
        }
        // Room for two and a half entries; 0 is pinned.
        let each = dir_bytes(&store.dir(&keys[0].id()));
        store.limit = each * 5 / 2;
        let pinned = HashSet::from([keys[0].id()]);
        let tidied = store.tidy(&pinned);
        assert_eq!(tidied.removed, 2, "{tidied:?}");
        let there: Vec<bool> = keys.iter().map(|k| store.open(k).is_some()).collect();
        assert_eq!(there, [true, false, false, true], "the pinned and the newest stay");

        // Pins alone over the limit: nothing pinned goes, and it is told.
        store.limit = 10;
        let tidied = store.tidy(&pinned);
        assert!(tidied.over(store.limit));
        assert!(store.open(&keys[0]).is_some());
    }

    #[test]
    fn a_writer_puts_the_entry_in_place_whole_and_one_process_makes_it() {
        let dir = tempfile::tempdir().unwrap();
        let store = Store::new(dir.path().join("bakes"), DEFAULT_LIMIT);
        let (job, key) = job(1);
        let Write::Make(writer) = store.writer(&job, &key).unwrap() else {
            panic!("a new entry is made");
        };
        fs::write(writer.file("out.bin"), b"data").unwrap();
        assert!(store.open(&key).is_none(), "not there before the commit");
        // The lock is per open file description: another open of the same
        // file is another process as far as `flock` goes.
        assert!(matches!(store.writer(&job, &key).unwrap(), Write::Busy));
        let entry = writer.commit().unwrap();
        assert_eq!(fs::read(entry.file("out.bin")).unwrap(), b"data");
        assert_eq!(store.open(&key).unwrap().meta.bytes, 4);
        assert!(matches!(store.writer(&job, &key).unwrap(), Write::Done(_)));
        assert_eq!(
            fs::read_dir(store.root().join("tmp")).unwrap().count(),
            0,
            "nothing left in tmp"
        );
    }
}
