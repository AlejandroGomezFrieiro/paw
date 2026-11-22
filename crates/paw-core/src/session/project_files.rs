//! Where the reader of a project folder ([`super::folder::read_from`]) gets
//! the bytes of the project's own files: the disk, or a map of files in
//! memory, the form that [`super::folder::layout`] gives.
//!
//! The map holds only the files that paw writes into a project folder
//! (`project.toml`, `meta.json`, `screen.json`, `media.json`, `master/` and
//! `tracks/`). A file outside those (a sound file, a track folder or a chain
//! file outside the project) is read from the disk in both cases.

use std::borrow::Cow;
use std::collections::BTreeMap;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use super::folder;

/// The files a project folder is read from.
pub trait ProjectFiles: Sync {
    /// The bytes of the file at `path`, an absolute path.
    ///
    /// # Errors
    ///
    /// The I/O error of the read, `NotFound` for a file that is not there.
    fn read(&self, path: &Path) -> io::Result<Cow<'_, [u8]>>;

    /// Whether there is a file at `path`.
    fn exists(&self, path: &Path) -> bool;
}

/// The files on the disk.
#[derive(Clone, Copy, Debug, Default)]
pub struct DiskFiles;

impl ProjectFiles for DiskFiles {
    fn read(&self, path: &Path) -> io::Result<Cow<'_, [u8]>> {
        std::fs::read(path).map(Cow::Owned)
    }

    fn exists(&self, path: &Path) -> bool {
        path.exists()
    }
}

/// The files of the project folder `dir` in memory, by their path in it.
#[derive(Clone, Debug)]
pub struct MemoryFiles {
    dir: PathBuf,
    files: BTreeMap<PathBuf, Arc<[u8]>>,
}

/// Where a file that the reader asks for is.
enum Place<'a> {
    Memory(&'a [u8]),
    /// One of the project's own files that the map does not have.
    Missing,
    Disk,
}

impl MemoryFiles {
    /// The files `files` (by their path in the folder) of the folder `dir`.
    pub fn new(dir: &Path, files: BTreeMap<PathBuf, Arc<[u8]>>) -> Self {
        Self { dir: folder::tidy(dir), files }
    }

    fn place(&self, path: &Path) -> Place<'_> {
        let path = folder::tidy(path);
        let Ok(rel) = path.strip_prefix(&self.dir) else {
            return Place::Disk;
        };
        match self.files.get(rel) {
            Some(bytes) => Place::Memory(bytes),
            None if folder::is_managed(rel) => Place::Missing,
            None => Place::Disk,
        }
    }
}

impl ProjectFiles for MemoryFiles {
    fn read(&self, path: &Path) -> io::Result<Cow<'_, [u8]>> {
        match self.place(path) {
            Place::Memory(bytes) => Ok(Cow::Borrowed(bytes)),
            Place::Missing => Err(io::Error::new(
                io::ErrorKind::NotFound,
                format!("{}: not in the files in memory", path.display()),
            )),
            Place::Disk => DiskFiles.read(path),
        }
    }

    fn exists(&self, path: &Path) -> bool {
        match self.place(path) {
            Place::Memory(_) => true,
            Place::Missing => false,
            Place::Disk => path.exists(),
        }
    }
}
