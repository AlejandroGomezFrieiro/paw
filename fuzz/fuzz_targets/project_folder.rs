//! A project folder, as paw opens it (`session::folder::read_from`):
//! `project.toml`, the track folders with their JSON and clip files, and
//! the nests. An error, or a project with its problems listed, never a
//! panic.
//!
//! The input is the files of one folder, each after a line that names it:
//!
//! ```text
//! === project.toml
//! tracks = ["Bass"]
//! === tracks/Bass/track.json
//! {"id": 1, "name": "Bass", "clips": []}
//! ```
//!
//! The files are in memory only. A file that the input does not give is
//! not there, also outside the folder: the target never reads the disk.

#![no_main]

use std::borrow::Cow;
use std::collections::BTreeMap;
use std::io;
use std::path::{Component, Path, PathBuf};

use libfuzzer_sys::fuzz_target;
use paw_core::session::folder;
use paw_core::session::project_files::ProjectFiles;

/// The line that starts a file; the rest of the line is its path.
const MARK: &[u8] = b"=== ";

/// The folder that the files are in.
const DIR: &str = "/fuzz/song";

/// The files of the input, by their absolute path.
struct Files(BTreeMap<PathBuf, Vec<u8>>);

impl Files {
    /// The files of the input. A line with [`MARK`] starts a file, and the
    /// lines after it, up to the next mark, are its bytes: the line feed
    /// before a mark belongs to the mark, so a binary file (a `.midi2`
    /// clip) keeps its length. The lines before the first mark are dropped.
    fn parse(bytes: &[u8]) -> Self {
        let mut lines: BTreeMap<PathBuf, Vec<&[u8]>> = BTreeMap::new();
        let mut open: Option<PathBuf> = None;
        for line in bytes.split(|&b| b == b'\n') {
            if let Some(name) = line.strip_prefix(MARK) {
                let path = lexical(&Path::new(DIR).join(String::from_utf8_lossy(name).trim()));
                lines.insert(path.clone(), Vec::new());
                open = Some(path);
            } else if let Some(body) = open.as_ref().and_then(|path| lines.get_mut(path)) {
                body.push(line);
            }
        }
        Self(
            lines
                .into_iter()
                .map(|(path, body)| (path, body.join(&b'\n')))
                .collect(),
        )
    }
}

/// The path with `.` and `..` taken out, without a look at the disk.
fn lexical(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out
}

impl ProjectFiles for Files {
    fn read(&self, path: &Path) -> io::Result<Cow<'_, [u8]>> {
        match self.0.get(&lexical(path)) {
            Some(bytes) => Ok(Cow::Borrowed(bytes)),
            None => Err(io::Error::from(io::ErrorKind::NotFound)),
        }
    }

    fn exists(&self, path: &Path) -> bool {
        self.0.contains_key(&lexical(path))
    }
}

fuzz_target!(|bytes: &[u8]| {
    let _ = folder::read_from(&Files::parse(bytes), Path::new(DIR));
});
