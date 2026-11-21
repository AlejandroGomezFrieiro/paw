//! Writing files so that no crash, power cut or full disk loses what was
//! there before.

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

/// The file the previous version of `path` is kept in: `song.json.bak`.
pub fn backup_path(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_owned();
    name.push(".bak");
    PathBuf::from(name)
}

/// Write `bytes` to `path` so that at every moment `path` holds either all of
/// the old contents or all of the new: write a temporary file beside it,
/// flush it to the disk, rename it over `path` and flush the directory.
/// With `keep_backup`, the old contents are kept as `<path>.bak` first.
pub fn write_file(path: &Path, bytes: &[u8], keep_backup: bool) -> Result<()> {
    let dir = match path.parent() {
        Some(dir) if !dir.as_os_str().is_empty() => dir.to_path_buf(),
        _ => PathBuf::from("."),
    };
    let mut tmp_name = path.as_os_str().to_owned();
    tmp_name.push(".tmp");
    let tmp = PathBuf::from(tmp_name);
    let written = (|| -> std::io::Result<()> {
        let mut file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .open(&tmp)?;
        file.write_all(bytes)?;
        file.sync_all()
    })();
    if let Err(err) = written {
        // Leave nothing half written behind; the old file is untouched.
        let _ = std::fs::remove_file(&tmp);
        return Err(err).with_context(|| format!("writing {}", tmp.display()));
    }
    if keep_backup && path.is_file() {
        keep_previous(path).with_context(|| format!("keeping the previous {}", path.display()))?;
    }
    std::fs::rename(&tmp, path).with_context(|| format!("writing {}", path.display()))?;
    sync_dir(&dir);
    Ok(())
}

/// Make `<path>.bak` a copy of `path` as it is now. A hard link is instant
/// and costs no space; where links are not possible the file is copied.
/// Either way the `.bak` is replaced in one step, so it is never half there.
fn keep_previous(path: &Path) -> std::io::Result<()> {
    let bak = backup_path(path);
    let mut staged = bak.as_os_str().to_owned();
    staged.push(".tmp");
    let staged = PathBuf::from(staged);
    let _ = std::fs::remove_file(&staged);
    if std::fs::hard_link(path, &staged).is_err() {
        std::fs::copy(path, &staged)?;
        File::open(&staged)?.sync_all()?;
    }
    std::fs::rename(&staged, &bak)
}

/// Flush a directory's entries (a rename in it) to the disk. Best effort:
/// some file systems refuse to open a directory for this.
pub fn sync_dir(dir: &Path) {
    if let Ok(dir) = File::open(dir) {
        let _ = dir.sync_all();
    }
}

/// Bytes free for this user on the file system that holds `dir`.
pub fn free_space(dir: &Path) -> Option<u64> {
    use std::os::unix::ffi::OsStrExt;
    let path = std::ffi::CString::new(dir.as_os_str().as_bytes()).ok()?;
    // SAFETY: statvfs fills the struct it is given and reads a C string.
    let mut stat: libc::statvfs = unsafe { std::mem::zeroed() };
    // SAFETY: `path` is a NUL-terminated string that outlives the call; `stat` is valid.
    if unsafe { libc::statvfs(path.as_ptr(), &mut stat) } != 0 {
        return None;
    }
    Some(stat.f_bavail as u64 * stat.f_frsize as u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("paw-safe-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn the_previous_file_is_kept_as_bak() {
        let dir = scratch("bak");
        let path = dir.join("song.json");
        write_file(&path, b"one", true).unwrap();
        assert!(
            !backup_path(&path).exists(),
            "a first save has nothing to keep"
        );
        write_file(&path, b"two", true).unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"two");
        assert_eq!(std::fs::read(backup_path(&path)).unwrap(), b"one");
        write_file(&path, b"three", true).unwrap();
        assert_eq!(std::fs::read(backup_path(&path)).unwrap(), b"two");
        let left: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .flatten()
            .map(|e| e.file_name())
            .collect();
        assert_eq!(left.len(), 2, "no temporary files are left: {left:?}");
    }

    #[test]
    fn a_failed_write_leaves_the_old_file() {
        let dir = scratch("fail");
        let path = dir.join("song.json");
        write_file(&path, b"good", true).unwrap();
        // A directory where the temporary file would go makes the write fail.
        std::fs::create_dir_all(dir.join("song.json.tmp")).unwrap();
        assert!(write_file(&path, b"bad", true).is_err());
        assert_eq!(std::fs::read(&path).unwrap(), b"good");
    }
}
