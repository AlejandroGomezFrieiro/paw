//! A safety copy written when the program panics.
//!
//! The session keeps the latest state of the project here (cheap: tracks
//! are shared, not copied) whenever it changes. A panic hook calls
//! [`write_copy`], which writes it where `:recover` looks, so a bug in the
//! program loses no more than a crash of a plugin does.

use std::path::PathBuf;
use std::sync::Mutex;

use serde_json::json;

use super::{FILE_VERSION, Session, Transport};
use crate::model::Project;

struct Latest {
    project: Project,
    transport: Transport,
    path: Option<PathBuf>,
    modified: bool,
    /// The directory `:recover` looks in (`runtime/lua/paw/autosave.lua`).
    recovery: PathBuf,
}

static LATEST: Mutex<Option<Latest>> = Mutex::new(None);

impl Session {
    /// Keep the project as it is now for [`write_copy`].
    pub(super) fn remember_for_panic(&self) {
        // Never wait: a panic hook may hold the lock on this very thread.
        if let Ok(mut latest) = LATEST.try_lock() {
            *latest = Some(Latest {
                project: self.project.clone(),
                transport: self.transport.clone(),
                path: self.path.clone(),
                modified: self.undo.touched || !self.undo.history.at_saved(),
                recovery: self.dirs.paw_state().join("recovery"),
            });
        }
    }
}

/// Write the last known state of the project as a safety copy, if it has
/// changes that are not saved. Returns the file written. `why` is kept in it.
pub fn write_copy(why: &str) -> Option<PathBuf> {
    let latest = LATEST.try_lock().ok()?;
    let latest = latest.as_ref().filter(|l| l.modified)?;
    let pid = std::process::id();
    let time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    let file = json!({
        "version": FILE_VERSION,
        "project": latest.project,
        "transport": latest.transport,
        "recovery": {
            "path": latest.path, "name": latest.project.name, "time": time, "pid": pid,
            "panic": why,
        },
    });
    let dir = &latest.recovery;
    std::fs::create_dir_all(dir).ok()?;
    let path = dir.join(format!("panic-{pid}-{time}.json"));
    crate::safe::write_file(&path, serde_json::to_string(&file).ok()?.as_bytes(), false).ok()?;
    Some(path)
}
