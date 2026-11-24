//! The slots of the machine: a cap on the paw processes of all the runs
//! of the suite on one machine. The test group of nextest caps the parts
//! of one run only, and several agents can run the suite at once.

use std::env;
use std::fs::{self, File, TryLockError};
use std::path::{Path, PathBuf};

/// The folder of the lock files, and the number of slots.
#[derive(Clone)]
pub(crate) struct Slots {
    dir: PathBuf,
    count: usize,
}

/// A slot that this process holds. The lock goes when it drops, and also
/// when the process ends.
pub(crate) struct Slot {
    _file: File,
}

impl Slots {
    /// `PAW_SUITE_LOCKS` (else `/tmp/paw-suite-locks`) and
    /// `PAW_SUITE_SLOTS` (else 4). A count that is not a number from 1 up
    /// is an error when a part takes a slot.
    pub(crate) fn from_env() -> Self {
        let dir = env::var_os("PAW_SUITE_LOCKS")
            .map_or_else(|| PathBuf::from("/tmp/paw-suite-locks"), PathBuf::from);
        let count = env::var("PAW_SUITE_SLOTS")
            .ok()
            .map_or(Some(4), |n| n.trim().parse().ok())
            .unwrap_or(0);
        Self { dir, count }
    }

    #[cfg(test)]
    pub(crate) fn new(dir: &Path, count: usize) -> Self {
        Self {
            dir: dir.to_path_buf(),
            count,
        }
    }

    /// Take a free slot. When all slots are taken, wait for one: the lock
    /// call blocks until its holder lets it go.
    ///
    /// # Errors
    ///
    /// "suite: cannot take a slot in <dir>: <error>" when the folder or a
    /// lock file cannot be made, or a lock fails. A part never runs with
    /// no slot.
    pub(crate) fn take(&self) -> Result<Slot, String> {
        let fail = |error: &dyn std::fmt::Display| {
            format!(
                "suite: cannot take a slot in {}: {error}",
                self.dir.display()
            )
        };
        if self.count == 0 {
            return Err(fail(&"PAW_SUITE_SLOTS is not a number from 1 up"));
        }
        fs::create_dir_all(&self.dir).map_err(|error| fail(&error))?;
        let open = |k: usize| File::create(lock_path(&self.dir, k)).map_err(|error| fail(&error));
        for k in 1..=self.count {
            let file = open(k)?;
            match file.try_lock() {
                Ok(()) => return Ok(Slot { _file: file }),
                Err(TryLockError::WouldBlock) => {}
                Err(TryLockError::Error(error)) => return Err(fail(&error)),
            }
        }
        // Every slot is taken: wait on one of them. The process id spreads
        // the waiters over the slots.
        let k = usize::try_from(std::process::id()).unwrap_or(0) % self.count + 1;
        let file = open(k)?;
        eprintln!(
            "suite: waiting for one of the {} slots in {}",
            self.count,
            self.dir.display()
        );
        file.lock().map_err(|error| fail(&error))?;
        Ok(Slot { _file: file })
    }
}

fn lock_path(dir: &Path, k: usize) -> PathBuf {
    dir.join(format!("slot{k}"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Arc, mpsc};

    #[test]
    fn with_one_slot_the_second_taker_waits_until_the_first_lets_go() {
        let dir = tempfile::tempdir().expect("a scratch folder");
        let slots = Slots::new(dir.path(), 1);
        let first = slots.take().expect("the first slot");
        let released = Arc::new(AtomicBool::new(false));
        let (taken, got) = mpsc::channel();
        let waiter = {
            let (slots, released) = (slots, Arc::clone(&released));
            std::thread::spawn(move || {
                let slot = slots.take().expect("the slot after the first lets go");
                taken.send(released.load(Ordering::SeqCst)).expect("send");
                drop(slot);
            })
        };
        released.store(true, Ordering::SeqCst);
        drop(first);
        assert!(
            got.recv().expect("the second taker got the slot"),
            "the second taker got the slot before it was free"
        );
        waiter.join().expect("the waiter");
    }

    #[test]
    fn a_folder_that_cannot_be_made_refuses_the_slot() {
        let dir = tempfile::tempdir().expect("a scratch folder");
        let file = dir.path().join("a-file");
        fs::write(&file, "").expect("write the file");
        let Err(message) = Slots::new(&file.join("locks"), 4).take() else {
            panic!("a slot in a folder under a file")
        };
        assert!(
            message.starts_with(&format!(
                "suite: cannot take a slot in {}: ",
                file.join("locks").display()
            )),
            "{message}"
        );
    }
}
