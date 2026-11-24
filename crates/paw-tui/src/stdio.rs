//! The standard output and error of the process while the terminal shows
//! paw.
//!
//! Code in this process writes to descriptors 1 and 2 whenever it likes:
//! the client library of the audio backend, a plugin hosted in-process,
//! `io.stdout` in Lua, and each child process that inherits them. On the
//! screen that text breaks the frame. So while paw draws, descriptors 1
//! and 2 point at a log file, and the terminal frontend writes through
//! [`Screen`], a private copy of the terminal's descriptor.
//!
//! The descriptor work is for Unix only. On another platform, [`capture`]
//! and [`release`] do nothing and [`Screen`] writes to the standard output.

use std::fs::File;
use std::io::{self, Write};

/// The terminal, for the frontend to write the frame to.
pub(crate) struct Screen;

impl Write for Screen {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        sys::write(buf)
    }

    fn flush(&mut self) -> io::Result<()> {
        sys::flush()
    }
}

/// Point descriptors 1 and 2 at `log` until [`release`]. [`Screen`] then
/// writes to the terminal through a private descriptor. A second call
/// while captured does nothing. On an error, descriptors 1 and 2 stay as
/// they are.
pub(crate) fn capture(log: &File) -> io::Result<()> {
    sys::capture(log)
}

/// Put descriptors 1 and 2 back on the terminal, so that a last message
/// (an error, a panic) reaches the user. It does nothing when they are not
/// captured.
pub(crate) fn release() {
    sys::release();
}

/// Write `bytes` to the terminal from a signal handler: one system call,
/// no allocation and no lock.
#[cfg(unix)]
pub(crate) fn write_from_signal(bytes: &[u8]) {
    sys::write_from_signal(bytes);
}

#[cfg(unix)]
mod sys {
    use std::fs::File;
    use std::io;
    use std::os::fd::{AsFd, BorrowedFd, IntoRawFd, OwnedFd, RawFd};
    use std::sync::Mutex;
    use std::sync::atomic::{AtomicI32, Ordering};

    /// The private copy of the terminal's descriptor, or -1 before
    /// [`capture`]. It stays open until the program ends. Thus a writer
    /// that read it never writes to a descriptor that is closed or used
    /// again for another file.
    static TERMINAL: AtomicI32 = AtomicI32::new(-1);

    /// Descriptors 1 and 2 as they were before [`capture`], while they
    /// point at the log.
    static SAVED: Mutex<Option<(OwnedFd, OwnedFd)>> = Mutex::new(None);

    fn terminal() -> BorrowedFd<'static> {
        match TERMINAL.load(Ordering::Acquire) {
            -1 => rustix::stdio::stdout(),
            // SAFETY: `capture` stores a descriptor that it owns and that
            // nothing closes until the program ends.
            fd => unsafe { BorrowedFd::borrow_raw(fd) },
        }
    }

    pub(super) fn write(buf: &[u8]) -> io::Result<usize> {
        Ok(rustix::io::write(terminal(), buf)?)
    }

    pub(super) fn flush() -> io::Result<()> {
        Ok(())
    }

    pub(super) fn write_from_signal(bytes: &[u8]) {
        let _ = rustix::io::write(terminal(), bytes);
    }

    pub(super) fn capture(log: &File) -> io::Result<()> {
        let mut saved = SAVED.lock().unwrap_or_else(|e| e.into_inner());
        if saved.is_some() {
            return Ok(());
        }
        // Text that the standard library keeps in its buffer goes to the
        // terminal first, not into the log.
        io::Write::flush(&mut io::stdout())?;
        let out = rustix::io::fcntl_dupfd_cloexec(rustix::stdio::stdout(), 3)?;
        let err = rustix::io::fcntl_dupfd_cloexec(rustix::stdio::stderr(), 3)?;
        if TERMINAL.load(Ordering::Acquire) == -1 {
            let private = rustix::io::fcntl_dupfd_cloexec(rustix::stdio::stdout(), 3)?;
            let raw: RawFd = private.into_raw_fd();
            TERMINAL.store(raw, Ordering::Release);
        }
        rustix::stdio::dup2_stdout(log.as_fd())?;
        if let Err(error) = rustix::stdio::dup2_stderr(log.as_fd()) {
            let _ = rustix::stdio::dup2_stdout(&out);
            return Err(error.into());
        }
        *saved = Some((out, err));
        Ok(())
    }

    pub(super) fn release() {
        // A panic hook calls this. A lock that a panic poisoned still holds
        // the descriptors. The buffer of `io::stdout` is not flushed here:
        // the thread that panics can hold its lock.
        let saved = SAVED.lock().unwrap_or_else(|e| e.into_inner()).take();
        if let Some((out, err)) = saved {
            let _ = rustix::stdio::dup2_stdout(&out);
            let _ = rustix::stdio::dup2_stderr(&err);
        }
    }
}

#[cfg(not(unix))]
mod sys {
    use std::fs::File;
    use std::io::{self, Write};

    pub(super) fn write(buf: &[u8]) -> io::Result<usize> {
        io::stdout().write(buf)
    }

    pub(super) fn flush() -> io::Result<()> {
        io::stdout().flush()
    }

    pub(super) fn capture(_log: &File) -> io::Result<()> {
        Ok(())
    }

    pub(super) fn release() {}
}
