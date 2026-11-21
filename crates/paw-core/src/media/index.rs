//! The local index: which files this machine has hashed already.
//!
//! It maps a file's absolute path, size, change time and inode to the hash
//! of its bytes, so that opening a project costs one `stat` per source and
//! no hash when nothing changed. It is this machine's knowledge, not the
//! project's: it lives at `$XDG_STATE_HOME/paw/media-index` and is never
//! saved with a project (git and copies change the times it is keyed by).
//!
//! The file is text, one entry per line: hash, size, change time in
//! nanoseconds, inode, then the path to the end of the line. Two programs
//! that write it at once lose some of each other's entries at worst, and
//! those files are hashed again.

use std::collections::HashMap;
use std::io::{self, Write};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

use super::table::SourceHash;

/// The first line of the file: its format.
const HEADER: &str = "paw media-index 1";
/// Past this many entries, those of files that are gone are dropped on saving.
const TIDY_PAST: usize = 100_000;

/// What says that a file is still the one that was hashed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Stamp {
    pub size: u64,
    /// The change time, in nanoseconds since 1970.
    pub mtime: i128,
    pub inode: u64,
}

impl Stamp {
    pub fn of(meta: &std::fs::Metadata) -> Self {
        Self {
            size: meta.len(),
            mtime: i128::from(meta.mtime()) * 1_000_000_000 + i128::from(meta.mtime_nsec()),
            inode: meta.ino(),
        }
    }

    /// The stamp of the file at `path`, when it is a file.
    pub fn read(path: &Path) -> Option<Self> {
        std::fs::metadata(path)
            .ok()
            .filter(std::fs::Metadata::is_file)
            .map(|m| Self::of(&m))
    }
}

/// The hashes this machine knows, by absolute path.
#[derive(Debug, Default)]
pub struct LocalIndex {
    /// Where it is kept; `None` keeps it in memory only.
    file: Option<PathBuf>,
    entries: HashMap<PathBuf, (Stamp, SourceHash)>,
    /// Entries learned since the last save.
    changed: bool,
}

impl LocalIndex {
    /// `$XDG_STATE_HOME/paw/media-index`. The kernel's own unit tests keep
    /// the index in memory, so that they never write into the user's folders.
    pub fn default_file() -> Option<PathBuf> {
        if cfg!(test) {
            return None;
        }
        Some(paw_proto::state_dir().join("media-index"))
    }

    /// The index kept in `file`, with what it holds now. A file that cannot
    /// be read is an empty index (it is only a shortcut).
    pub fn open(file: Option<PathBuf>) -> Self {
        let entries = file
            .as_deref()
            .and_then(|f| std::fs::read_to_string(f).ok())
            .map(|text| parse(&text))
            .unwrap_or_default();
        Self { file, entries, changed: false }
    }

    /// The hash of the file at `path`, when it is still as it was hashed.
    pub fn get(&self, path: &Path, stamp: &Stamp) -> Option<SourceHash> {
        self.entries
            .get(path)
            .filter(|(s, _)| s == stamp)
            .map(|(_, h)| *h)
    }

    pub fn put(&mut self, path: PathBuf, stamp: Stamp, hash: SourceHash) {
        if self.entries.get(&path) != Some(&(stamp, hash)) {
            self.entries.insert(path, (stamp, hash));
            self.changed = true;
        }
    }

    /// Write what was learned, merged with what another program wrote in the
    /// meantime (ours wins), in full beside the file and then renamed over it.
    pub fn save(&mut self) -> io::Result<()> {
        let Some(file) = self.file.clone().filter(|_| self.changed) else {
            return Ok(());
        };
        if let Ok(text) = std::fs::read_to_string(&file) {
            for (path, entry) in parse(&text) {
                self.entries.entry(path).or_insert(entry);
            }
        }
        if self.entries.len() > TIDY_PAST {
            self.entries.retain(|path, _| path.is_file());
        }
        if let Some(dir) = file.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let mut lines: Vec<(&PathBuf, &(Stamp, SourceHash))> = self.entries.iter().collect();
        lines.sort_by_key(|(path, _)| *path);
        let mut text = String::with_capacity(lines.len() * 160);
        text.push_str(HEADER);
        text.push('\n');
        for (path, (stamp, hash)) in lines {
            let Some(path) = path.to_str().filter(|p| !p.contains('\n')) else {
                continue;
            };
            text.push_str(&format!("{hash}\t{}\t{}\t{}\t{path}\n", stamp.size, stamp.mtime, stamp.inode));
        }
        let tmp = file.with_extension(format!("tmp-{}", std::process::id()));
        let mut out = std::fs::File::create(&tmp)?;
        out.write_all(text.as_bytes())?;
        drop(out);
        std::fs::rename(&tmp, &file)?;
        self.changed = false;
        Ok(())
    }
}

/// The entries of an index file; lines that do not read are skipped.
fn parse(text: &str) -> HashMap<PathBuf, (Stamp, SourceHash)> {
    let mut lines = text.lines();
    if lines.next() != Some(HEADER) {
        return HashMap::new();
    }
    lines
        .filter_map(|line| {
            let mut parts = line.splitn(5, '\t');
            let hash = parts.next()?.parse().ok()?;
            let size = parts.next()?.parse().ok()?;
            let mtime = parts.next()?.parse().ok()?;
            let inode = parts.next()?.parse().ok()?;
            let path = PathBuf::from(parts.next()?);
            Some((path, (Stamp { size, mtime, inode }, hash)))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_index_comes_back_from_its_file_and_misses_a_changed_file() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("state/media-index");
        let wav = dir.path().join("a\tb.wav");
        std::fs::write(&wav, b"one").unwrap();
        let stamp = Stamp::read(&wav).unwrap();
        let hash = SourceHash::of_file(&wav).unwrap();
        let mut index = LocalIndex::open(Some(file.clone()));
        index.put(wav.clone(), stamp, hash);
        index.save().unwrap();
        let back = LocalIndex::open(Some(file));
        assert_eq!(back.get(&wav, &stamp), Some(hash));
        std::fs::write(&wav, b"other").unwrap();
        assert_eq!(back.get(&wav, &Stamp::read(&wav).unwrap()), None);
    }
}
