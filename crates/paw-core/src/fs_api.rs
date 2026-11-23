//! `paw.api.fs_*`: what the file manager (`paw/files.lua`) does to files.
//! Nothing here removes a file: a file leaves its place by being moved, to
//! another place or to the trash, and what would overwrite is refused
//! (`paw.api.fs_remove`, in api/system.rs, is for what paw made itself).

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use mlua::{Lua, Table};
use paw_proto::dirs::Dirs;
use percent_encoding::{utf8_percent_encode, AsciiSet, NON_ALPHANUMERIC};

use crate::api::guarded;

fn fail(what: String) -> mlua::Error {
    mlua::Error::runtime(what)
}

fn seconds(t: io::Result<std::time::SystemTime>) -> Option<f64> {
    t.ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs_f64())
}

/// Move `from` to `to`, across file systems too (a file is copied and then
/// the original goes; a directory across file systems is refused).
fn relocate(from: &Path, to: &Path) -> Result<(), String> {
    if to.symlink_metadata().is_ok() {
        return Err(format!("{} is there already", to.display()));
    }
    match fs::rename(from, to) {
        Ok(()) => Ok(()),
        Err(e) if e.raw_os_error() == Some(libc::EXDEV) => {
            if from.is_dir() {
                return Err(format!(
                    "{} cannot be moved to another disk as a folder: copy it with another program",
                    from.display()
                ));
            }
            fs::copy(from, to).map_err(|e| format!("copying {}: {e}", from.display()))?;
            fs::remove_file(from)
                .map_err(|e| format!("{} was copied but not removed: {e}", from.display()))
        }
        Err(e) => Err(format!("{}: {e}", from.display())),
    }
}

/// Copy a file, or a directory and all it holds; links are copied as links.
fn copy_tree(from: &Path, to: &Path) -> io::Result<()> {
    let meta = from.symlink_metadata()?;
    if meta.file_type().is_symlink() {
        std::os::unix::fs::symlink(fs::read_link(from)?, to)
    } else if meta.is_dir() {
        fs::create_dir(to)?;
        for entry in fs::read_dir(from)? {
            let entry = entry?;
            copy_tree(&entry.path(), &to.join(entry.file_name()))?;
        }
        Ok(())
    } else {
        fs::copy(from, to).map(|_| ())
    }
}

/// The user's trash directory (freedesktop.org Trash specification).
fn trash_dir(dirs: &Dirs) -> Option<PathBuf> {
    Some(dirs.data.as_ref()?.join("Trash"))
}

/// A name in `dir` that is free, from `name`: `a.wav`, `a.2.wav`, `a.3.wav`.
fn free_name(dir: &Path, name: &str) -> String {
    let free = |n: &str| dir.join(n).symlink_metadata().is_err();
    if free(name) {
        return name.to_string();
    }
    let (stem, ext) = match name.rfind('.') {
        Some(i) if i > 0 => (&name[..i], &name[i..]),
        _ => (name, ""),
    };
    (2..)
        .map(|n| format!("{stem}.{n}{ext}"))
        .find(|n| free(n))
        .unwrap()
}

/// Everything but ASCII letters, digits and `/-_.~` is escaped.
const ESCAPED: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'/')
    .remove(b'-')
    .remove(b'_')
    .remove(b'.')
    .remove(b'~');

fn percent_encode(path: &str) -> String {
    utf8_percent_encode(path, ESCAPED).to_string()
}

/// Now, local time, as the trash records it: `2026-11-17T09:30:00`.
// libc, not jiff or chrono: the spec wants local time with no zone, and `localtime_r` gives it with no new dependency.
fn deletion_date() -> String {
    // SAFETY: `time` accepts a null pointer; `tm` is plain integers (and a pointer that
    // `localtime_r` sets), valid as all zeros; `localtime_r` writes only into `tm` and is
    // thread-safe.
    unsafe {
        let now = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        libc::localtime_r(&now, &mut tm);
        format!(
            "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}",
            tm.tm_year + 1900,
            tm.tm_mon + 1,
            tm.tm_mday,
            tm.tm_hour,
            tm.tm_min,
            tm.tm_sec
        )
    }
}

/// Put a file in the trash, with the record of where it came from that
/// lets a file manager put it back, in the trash directory `root`. Returns
/// where it is now.
fn trash(path: &Path, root: Option<&Path>) -> Result<PathBuf, String> {
    path.symlink_metadata()
        .map_err(|e| format!("{}: {e}", path.display()))?;
    let name = path.file_name().ok_or("there is no name to trash")?;
    let abs = fs::canonicalize(path.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new(".")))
        .map_err(|e| format!("{}: {e}", path.display()))?
        .join(name);
    let Some(root) = root else {
        return Err("there is no trash: no home directory".into());
    };
    let (files, info) = (root.join("files"), root.join("info"));
    for dir in [&files, &info] {
        fs::create_dir_all(dir).map_err(|e| format!("making the trash {}: {e}", dir.display()))?;
    }
    let kept = free_name(&files, &name.to_string_lossy());
    let record = format!(
        "[Trash Info]\nPath={}\nDeletionDate={}\n",
        percent_encode(&abs.to_string_lossy()),
        deletion_date()
    );
    let note = info.join(format!("{kept}.trashinfo"));
    fs::write(&note, record).map_err(|e| format!("writing {}: {e}", note.display()))?;
    let at = files.join(&kept);
    match fs::rename(&abs, &at) {
        Ok(()) => Ok(at),
        Err(e) => {
            let _ = fs::remove_file(&note);
            if e.raw_os_error() == Some(libc::EXDEV) {
                Err(format!(
                    "{} is on another disk than the trash, so it is left where it is",
                    abs.display()
                ))
            } else {
                Err(format!("{}: {e}", abs.display()))
            }
        }
    }
}

pub(crate) fn install(lua: &Lua, api: &Table, dirs: &Dirs) -> mlua::Result<()> {
    let trash_root = trash_dir(dirs);
    // `{ kind = "file" | "dir" | "link", dir, size, mtime }`, or nil when
    // nothing is there. A link is looked at, not followed, for its kind,
    // and `dir` is true if it leads to a directory.
    // @return types.FileStat
    api.set(
        "fs_stat",
        lua.create_function(guarded!("fs_stat", |lua, path: String| {
            let Ok(meta) = fs::symlink_metadata(&path) else {
                return Ok(None);
            };
            let t = lua.create_table()?;
            let link = meta.file_type().is_symlink();
            let target = if link { fs::metadata(&path).ok() } else { None };
            let dir = target.as_ref().map_or(meta.is_dir(), |m| m.is_dir());
            t.set("kind", if link { "link" } else if dir { "dir" } else { "file" })?;
            t.set("dir", dir)?;
            t.set("size", target.as_ref().map_or(meta.len(), |m| m.len()) as f64)?;
            t.set("mtime", seconds(meta.modified()))?;
            Ok(Some(t))
        }))?,
    )?;
    // The format a sound file's header says: `{ rate, channels, seconds }`
    // (`seconds` nil when the header does not say); an error for a file
    // that is not one.
    // @return types.SoundFormat
    api.set(
        "fs_sound",
        lua.create_function(guarded!("fs_sound", |lua, path: String| {
            let probe =
                paw_engine::probe::probe(Path::new(&path)).map_err(|e| fail(e.to_string()))?;
            let t = lua.create_table()?;
            t.set("rate", probe.sample_rate)?;
            t.set("channels", probe.channels)?;
            t.set("seconds", probe.seconds)?;
            Ok(t)
        }))?,
    )?;
    // Make a directory and the ones above it that are missing.
    // @return nil
    api.set(
        "fs_mkdir",
        lua.create_function(guarded!("fs_mkdir", |_, path: String| {
            fs::create_dir_all(&path).map_err(|e| fail(format!("{path}: {e}")))
        }))?,
    )?;
    // Make an empty file where there is none.
    // @return nil
    api.set(
        "fs_create",
        lua.create_function(guarded!("fs_create", |_, path: String| {
            fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&path)
                .map(|_| ())
                .map_err(|e| fail(format!("{path}: {e}")))
        }))?,
    )?;
    // Move a file or directory; it is refused where `to` is there already.
    // @return nil
    api.set(
        "fs_move",
        lua.create_function(guarded!("fs_move", |_, (from, to): (String, String)| {
            relocate(Path::new(&from), Path::new(&to)).map_err(fail)
        }))?,
    )?;
    // Copy a file, or a directory with all it holds, to where there is nothing.
    // @return nil
    api.set(
        "fs_copy",
        lua.create_function(guarded!("fs_copy", |_, (from, to): (String, String)| {
            if Path::new(&to).symlink_metadata().is_ok() {
                return Err(fail(format!("{to} is there already")));
            }
            copy_tree(Path::new(&from), Path::new(&to)).map_err(|e| fail(format!("{from}: {e}")))
        }))?,
    )?;
    // Put a file or directory in the freedesktop trash; returns where it is.
    // @return string
    api.set(
        "fs_trash",
        lua.create_function(guarded!("fs_trash", move |_, path: String| {
            trash(Path::new(&path), trash_root.as_deref())
                .map(|p| p.to_string_lossy().into_owned())
                .map_err(fail)
        }))?,
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::percent_encode;

    #[test]
    fn percent_encode_escapes_all_but_the_safe_bytes() {
        assert_eq!(percent_encode("/a b/100%/ü#?.wav~-_"), "/a%20b/100%25/%C3%BC%23%3F.wav~-_");
    }
}
