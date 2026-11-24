//! A pseudo-terminal for the tests that run `paw` with a screen: the tests
//! of this crate include it with `mod pty;`.

use std::os::fd::FromRawFd;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// A new pseudo-terminal of 100 by 30 cells: (its master side, the path
/// of its other side).
pub(crate) fn pty() -> (std::fs::File, PathBuf) {
    // SAFETY: calls of libc on the descriptor that `posix_openpt` gives, checked before each
    // next use.
    unsafe {
        let master = libc::posix_openpt(libc::O_RDWR | libc::O_NOCTTY);
        assert!(master >= 0, "no pseudo-terminal");
        assert_eq!(libc::grantpt(master), 0);
        assert_eq!(libc::unlockpt(master), 0);
        let mut name = [0 as libc::c_char; 128];
        assert_eq!(libc::ptsname_r(master, name.as_mut_ptr(), name.len()), 0);
        let path = std::ffi::CStr::from_ptr(name.as_ptr()).to_string_lossy().into_owned();
        let size = libc::winsize { ws_row: 30, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0 };
        libc::ioctl(master, libc::TIOCSWINSZ, &size);
        (std::fs::File::from_raw_fd(master), PathBuf::from(path))
    }
}

/// Run `command` in the terminal whose other side is `slave`: its standard
/// input, output and error, and its controlling terminal (`/dev/tty`).
pub(crate) fn run_in(command: &mut Command, slave: &Path) {
    let tty = || std::fs::OpenOptions::new().read(true).write(true).open(slave).unwrap();
    command.stdin(Stdio::from(tty())).stdout(Stdio::from(tty())).stderr(Stdio::from(tty()));
    // SAFETY: only async-signal-safe calls between fork and exec.
    unsafe {
        command.pre_exec(|| {
            libc::setsid();
            libc::ioctl(0, libc::TIOCSCTTY, 0);
            Ok(())
        });
    }
}
