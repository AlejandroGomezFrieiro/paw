//! Hashing in the background: files whose hash this machine does not know
//! are hashed (and their header read) on a thread of their own, so that
//! nothing that plays waits for a hash. Only what needs the hash waits:
//! a save that names a file for the first time, and (later) a bake.

use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, Sender};

use super::index::Stamp;
use super::table::{Probe, SourceHash};

/// A file to learn about.
pub(super) struct Job {
    pub path: PathBuf,
    /// Its hash, when the index knows it already: only the header is read.
    pub known: Option<(Stamp, SourceHash)>,
}

/// What was learned of a file.
pub(super) struct Learned {
    pub path: PathBuf,
    /// The file as it was hashed, or why it could not be.
    pub result: std::io::Result<(Stamp, SourceHash, Probe)>,
}

/// One thread that hashes the files it is given, one at a time, in order.
/// It stops when the worker is dropped.
pub(super) struct Worker {
    jobs: Sender<Job>,
    done: Receiver<Learned>,
}

impl Worker {
    pub(super) fn start() -> std::io::Result<Self> {
        let (jobs, todo) = mpsc::channel::<Job>();
        let (tell, done) = mpsc::channel();
        std::thread::Builder::new()
            .name("paw-hash".into())
            .spawn(move || {
                for job in todo {
                    let result = learn(&job);
                    if tell.send(Learned { path: job.path, result }).is_err() {
                        break;
                    }
                }
            })?;
        Ok(Self { jobs, done })
    }

    pub(super) fn send(&self, job: Job) -> bool {
        self.jobs.send(job).is_ok()
    }

    /// What was learned since the last call, without waiting.
    pub(super) fn take(&self) -> impl Iterator<Item = Learned> + '_ {
        self.done.try_iter()
    }

    /// The next thing learned, waiting for it.
    #[cfg(test)]
    pub(crate) fn wait(&self) -> Option<Learned> {
        self.done.recv().ok()
    }
}

fn learn(job: &Job) -> std::io::Result<(Stamp, SourceHash, Probe)> {
    let changed = || std::io::Error::other("the file changed while it was read");
    let stamp = Stamp::read(&job.path).ok_or_else(|| std::io::Error::from(std::io::ErrorKind::NotFound))?;
    let hash = match job.known {
        Some((known, hash)) if known == stamp => hash,
        _ => SourceHash::of_file(&job.path)?,
    };
    let probe = Probe::of_file(&job.path);
    if Stamp::read(&job.path) != Some(stamp) {
        return Err(changed());
    }
    Ok((stamp, hash, probe))
}
