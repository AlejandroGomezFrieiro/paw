//! Whether the files that clips read are there, without a look at the disk
//! on each clip list.
//!
//! The arrange view lists the clips of each track it shows on each frame,
//! and a clip whose file is missing says it is offline. A file event alone
//! cannot say when a file goes: inotify watches the folder of the file, and
//! a folder above it that gets a new name sends no event there. So the
//! answer for each path is kept for at most [`FRESH`], and then the file is
//! looked at again. Each change paw makes (an edit, an undo, a load) and
//! each file event forgets every answer, so that what paw does itself shows
//! at once. An edit of the document is seen by its count of changes
//! ([`FileCheck::after`]), so that an edit need not tell the check. The
//! answers age on the schedule clock, so that a test steps past [`FRESH`].

use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use crate::clock::{Clock, WallClock};

/// How long an answer is kept: the longest that a file can be gone, or
/// back, before a clip says so.
pub(super) const FRESH: Duration = Duration::from_secs(1);

/// The answers, by path. The session is used from one thread.
pub(super) struct FileCheck {
    /// The schedule clock that the answers age on (`Session::set_clock`).
    pub(super) clock: Arc<dyn Clock>,
    /// Each path's answer, and when it was taken on `clock`.
    seen: RefCell<HashMap<PathBuf, (Duration, bool)>>,
    /// The document's count of changes ([`Document::changes`]) when the
    /// answers in `seen` were taken.
    ///
    /// [`Document::changes`]: super::Document::changes
    changes: Cell<u64>,
}

impl Default for FileCheck {
    fn default() -> Self {
        Self {
            clock: Arc::new(WallClock::new()),
            seen: RefCell::default(),
            changes: Cell::default(),
        }
    }
}

impl FileCheck {
    /// The check, its answers forgotten first when the document changed
    /// since they were taken. `changes` is [`Document::changes`].
    ///
    /// [`Document::changes`]: super::Document::changes
    pub(super) fn after(&self, changes: u64) -> &Self {
        if self.changes.replace(changes) != changes {
            self.forget();
        }
        self
    }

    /// Whether `path` is a file, as it was at most [`FRESH`] ago.
    pub(super) fn is_file(&self, path: &Path) -> bool {
        self.is_file_at(path, self.clock.now())
    }

    fn is_file_at(&self, path: &Path, now: Duration) -> bool {
        if let Some(&(at, there)) = self.seen.borrow().get(path)
            && now.saturating_sub(at) < FRESH
        {
            return there;
        }
        let there = path.is_file();
        self.seen.borrow_mut().insert(path.to_path_buf(), (now, there));
        there
    }

    /// Forget every answer: the next question looks at the disk.
    pub(super) fn forget(&self) {
        self.seen.borrow_mut().clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_file_whose_parent_folder_is_renamed_is_missing_after_fresh() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("media/a.wav");
        std::fs::create_dir(dir.path().join("media")).unwrap();
        std::fs::write(&file, b"RIFF").unwrap();
        let check = FileCheck::default();
        let t0 = Duration::from_secs(5);
        assert!(check.is_file_at(&file, t0));
        std::fs::rename(dir.path().join("media"), dir.path().join("moved")).unwrap();
        assert!(
            check.is_file_at(&file, t0 + FRESH / 2),
            "asked again soon: the answer kept, the disk not looked at"
        );
        assert!(!check.is_file_at(&file, t0 + FRESH), "after FRESH the file is looked at again: missing");
        check.after(1);
        std::fs::rename(dir.path().join("moved"), dir.path().join("media")).unwrap();
        assert!(check.is_file_at(&file, t0 + FRESH), "a change paw made forgets the answers at once");
    }
}
