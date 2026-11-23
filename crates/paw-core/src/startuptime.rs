//! `paw --startuptime FILE`: where the time of the start goes, in the
//! format of Neovim's `--startuptime`, so that the same tools read it.
//!
//! The recorder is one per process. `main` starts it before anything else,
//! the kernel and the Lua runtime add lines to it, and the kernel writes it
//! to the file after the first frame (or before a script runs). When it is
//! not started, each call is one check of an empty lock.
//!
//! Two kinds of line, as Neovim writes them, times in milliseconds:
//!
//! ```text
//! clock   self+sourced   self:  sourced script
//! clock   elapsed:              other lines
//! ```
//!
//! A sourced item (a module that `require` loads, an extension, the user's
//! `init.lua`) is opened with [`enter`] and closed with [`leave`]: its
//! `self` time is its whole time less that of the items opened inside it.
#![expect(clippy::disallowed_methods, reason = "the time of the start is a measure of work")]

use std::fmt::Write as _;
use std::io::Write as _;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// The first line, at the clock's start.
pub const STARTING: &str = "--- PAW STARTING ---";
/// The last line, after the first frame.
pub const STARTED: &str = "--- PAW STARTED ---";

static RECORDER: Mutex<Option<Recorder>> = Mutex::new(None);

/// An item opened with [`enter`] and not closed yet.
#[derive(Debug)]
struct Open {
    at: Instant,
    /// The whole time of the items closed inside it.
    inner: Duration,
}

#[derive(Debug)]
struct Recorder {
    path: PathBuf,
    start: Instant,
    /// The time of the line before, for the `elapsed` column.
    last: Instant,
    open: Vec<Open>,
    text: String,
}

fn ms(d: Duration) -> f64 {
    d.as_secs_f64() * 1000.0
}

impl Recorder {
    fn new(path: PathBuf, now: Instant) -> Self {
        let mut text = String::with_capacity(16 * 1024);
        text.push_str(
            "\n\ntimes in msec\n clock   self+sourced   self:  sourced script\n clock   elapsed:              other lines\n\n",
        );
        Self { path, start: now, last: now, open: Vec::new(), text }
    }

    fn event(&mut self, label: &str, now: Instant) {
        let _ = writeln!(
            self.text,
            "{:07.3}  {:07.3}: {label}",
            ms(now - self.start),
            ms(now - self.last)
        );
        self.last = now;
    }

    fn enter(&mut self, now: Instant) {
        self.open.push(Open { at: now, inner: Duration::ZERO });
    }

    fn leave(&mut self, label: &str, now: Instant) {
        // A `leave` without its `enter` (an error between them) is a line
        // of its own, not a panic.
        let Some(open) = self.open.pop() else {
            self.event(label, now);
            return;
        };
        let whole = now - open.at;
        let own = whole.saturating_sub(open.inner);
        if let Some(outer) = self.open.last_mut() {
            outer.inner += whole;
        }
        let _ = writeln!(
            self.text,
            "{:07.3}  {:07.3}  {:07.3}: {label}",
            ms(now - self.start),
            ms(whole),
            ms(own)
        );
        self.last = now;
    }
}

fn with(f: impl FnOnce(&mut Recorder)) {
    let mut guard = RECORDER.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(recorder) = guard.as_mut() {
        f(recorder);
    }
}

/// Start the clock, and write to `path` when the start is done.
pub fn start(path: impl Into<PathBuf>) {
    let now = Instant::now();
    let mut recorder = Recorder::new(path.into(), now);
    recorder.event(STARTING, now);
    *RECORDER.lock().unwrap_or_else(|e| e.into_inner()) = Some(recorder);
}

/// Whether the start is being timed.
#[must_use]
pub fn is_on() -> bool {
    RECORDER.lock().unwrap_or_else(|e| e.into_inner()).is_some()
}

/// A line for one step of the start, with the time since the line before.
pub fn event(label: &str) {
    let now = Instant::now();
    with(|r| r.event(label, now));
}

/// Open a sourced item; [`leave`] closes it.
pub fn enter() {
    let now = Instant::now();
    with(|r| r.enter(now));
}

/// Close the item [`enter`] opened last, with its line.
pub fn leave(label: &str) {
    let now = Instant::now();
    with(|r| r.leave(label, now));
}

/// The last step, then `--- PAW STARTED ---`; the lines are added to the
/// end of the file, as Neovim does, and the clock stops. Returns false
/// when the start was not timed.
///
/// # Errors
///
/// When the file cannot be written.
pub fn finish(label: &str) -> std::io::Result<bool> {
    let now = Instant::now();
    let Some(mut recorder) = RECORDER.lock().unwrap_or_else(|e| e.into_inner()).take() else {
        return Ok(false);
    };
    recorder.event(label, now);
    recorder.event(STARTED, now);
    let mut file = std::fs::OpenOptions::new().create(true).append(true).open(&recorder.path)?;
    file.write_all(recorder.text.as_bytes())?;
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_sourced_item_counts_its_own_time_without_what_it_loaded() {
        let t0 = Instant::now();
        let at = |n: u64| t0 + Duration::from_millis(n);
        let mut r = Recorder::new(PathBuf::from("unused"), t0);
        r.enter(at(1));
        r.enter(at(2));
        r.leave("require('paw.util')", at(5));
        r.leave("require('paw')", at(10));
        r.event("first frame", at(12));
        let lines: Vec<&str> = r.text.lines().filter(|l| l.contains(':') && !l.contains("clock")).collect();
        assert_eq!(lines[0], "005.000  003.000  003.000: require('paw.util')");
        assert_eq!(lines[1], "010.000  009.000  006.000: require('paw')", "9 ms in all, 3 of them in paw.util");
        assert_eq!(lines[2], "012.000  002.000: first frame");
    }
}
