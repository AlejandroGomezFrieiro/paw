//! `paw.log` on disk: the slot of a session, the rotation of the runs at
//! the start, the cap of one run, and the fold of a line that comes again.

use std::fs::{self, File, OpenOptions, TryLockError};
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

/// The runs that the state folder keeps: `paw.log` and `paw.log.1` to
/// `paw.log.4`.
pub(super) const RUNS: usize = 5;

/// The most bytes of lines that one run writes. The dumps of the flight
/// recorder go past it: each one is at most the size of the ring.
pub(super) const CAP: u64 = 10 << 20;

/// The most bytes of `stderr.log` that go into the log of its run.
const STDERR_TAIL: u64 = 1 << 20;

/// The most sessions that each have a log at the same time.
pub(super) const SLOTS: usize = 9;

/// The files of one session: slot 1 has `paw.log` and `stderr.log`, slot
/// `k` has `paw.k.log` and `stderr.k.log`. A session holds the lock of its
/// slot (`paw.log.lock`, `paw.k.log.lock`) until its process ends, also
/// when it crashes: the system lets go of the lock of a process that ends.
/// Only the holder rotates the runs of the slot and empties its
/// `stderr` file, so two sessions never rename or fold the files of the
/// other.
pub(super) struct Slot {
    dir: PathBuf,
    /// 1 for `paw.log`, `k` for `paw.k.log`.
    number: usize,
    /// Open while the session runs: the lock goes with it.
    _lock: File,
}

impl Slot {
    /// Take the first free slot in `dir`. `None` when [`SLOTS`] sessions
    /// run.
    pub(super) fn take(dir: &Path) -> io::Result<Option<Self>> {
        fs::create_dir_all(dir)?;
        for number in 1..=SLOTS {
            let lock = OpenOptions::new()
                .create(true)
                .truncate(false)
                .write(true)
                .open(dir.join(format!("{}.log.lock", stem(number))))?;
            match lock.try_lock() {
                Ok(()) => return Ok(Some(Self { dir: dir.to_path_buf(), number, _lock: lock })),
                Err(TryLockError::WouldBlock) => {}
                Err(TryLockError::Error(err)) => return Err(err),
            }
        }
        Ok(None)
    }

    /// The log of run `n` back of this slot: 0 is this run, 1 the run
    /// before.
    pub(super) fn run(&self, n: usize) -> PathBuf {
        run_path(&self.dir, self.number, n)
    }

    /// The file in `cache` that takes the output of other code while this
    /// session shows the terminal (ADR 0042).
    pub(super) fn stderr(&self, cache: &Path) -> PathBuf {
        match self.number {
            1 => cache.join("stderr.log"),
            k => cache.join(format!("stderr.{k}.log")),
        }
    }

    /// Make room for a new run: each log of the slot moves one run back,
    /// and the oldest goes. Then the text of `stderr` (the output of other
    /// code in the run before of this slot) goes at the end of the log of
    /// that run, and `stderr` is emptied, so that it goes in one time only.
    pub(super) fn rotate(&self, stderr: Option<&Path>) -> io::Result<()> {
        for n in (0..RUNS - 1).rev() {
            match fs::rename(self.run(n), self.run(n + 1)) {
                Err(err) if err.kind() != io::ErrorKind::NotFound => return Err(err),
                _ => {}
            }
        }
        // The text of `stderr.log` is a help: a log goes on without it (a
        // cache folder that cannot be read, for example).
        if let Some(stderr) = stderr {
            let _ = fold_stderr(stderr, &self.run(1));
        }
        Ok(())
    }
}

/// The name of the files of slot `number`, without `.log`.
fn stem(number: usize) -> String {
    match number {
        1 => "paw".to_string(),
        k => format!("paw.{k}"),
    }
}

/// The log of run `n` back of slot `number` in `dir`.
pub(super) fn run_path(dir: &Path, number: usize, n: usize) -> PathBuf {
    match n {
        0 => dir.join(format!("{}.log", stem(number))),
        n => dir.join(format!("{}.log.{n}", stem(number))),
    }
}

/// Add the last [`STDERR_TAIL`] bytes of `stderr`, from the start of a
/// line, to `log`, under a line that names it. Nothing when it is empty or
/// absent.
fn fold_stderr(stderr: &Path, log: &Path) -> io::Result<()> {
    let mut source = match File::open(stderr) {
        Ok(file) => file,
        Err(err) if err.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(err) => return Err(err),
    };
    let size = source.metadata()?.len();
    if size == 0 {
        return Ok(());
    }
    let start = size.saturating_sub(STDERR_TAIL);
    source.seek(SeekFrom::Start(start))?;
    let mut text = Vec::new();
    source.read_to_end(&mut text)?;
    // A tail that starts inside a line starts at the next line.
    if start > 0
        && let Some(end) = text.iter().position(|&byte| byte == b'\n')
    {
        text.drain(..=end);
    }
    let mut log = OpenOptions::new().create(true).append(true).open(log)?;
    writeln!(log, "---- stderr.log of this run: what plugins, libraries and other programs printed ----")?;
    log.write_all(&text)?;
    if !text.ends_with(b"\n") {
        log.write_all(b"\n")?;
    }
    OpenOptions::new().write(true).open(stderr)?.set_len(0)
}

/// The log file of this run.
pub(super) struct LogFile {
    file: File,
    /// The bytes written so far, dumps included.
    written: u64,
    /// Set when a line did not fit in [`CAP`]: after that, only dumps.
    full: bool,
    /// The last line written, without its time, for the fold.
    last: String,
    /// How many times `last` came again and was not written.
    repeats: u32,
}

impl LogFile {
    /// Open a new, empty log at `path`.
    pub(super) fn create(path: &Path) -> io::Result<Self> {
        let file = File::create(path)?;
        Ok(Self { file, written: 0, full: false, last: String::new(), repeats: 0 })
    }

    /// Write one line: `time`, a space, then `body` (level, target and
    /// message). The same `body` again is only counted. Returns whether the
    /// file holds the line, which is false past the cap.
    pub(super) fn line(&mut self, time: &str, body: &str) -> bool {
        if self.full {
            return false;
        }
        if body == self.last {
            self.repeats += 1;
            return true;
        }
        self.end_repeats(time);
        let size = u64::try_from(time.len() + body.len() + 2).unwrap_or(u64::MAX);
        if self.written + size > CAP {
            self.raw(&format!(
                "{time} WARN  log: paw.log is full ({} MB): the next lines go only to the flight recorder",
                CAP >> 20
            ));
            self.full = true;
            return false;
        }
        self.raw(&format!("{time} {body}"));
        body.clone_into(&mut self.last);
        true
    }

    /// Write `lines` whatever the cap, after one line `header`.
    pub(super) fn dump<'a>(&mut self, time: &str, header: &str, lines: impl Iterator<Item = &'a str>) {
        self.end_repeats(time);
        self.raw(&format!("{time} ---- {header} ----"));
        for line in lines {
            self.raw(line);
        }
        self.raw(&format!("{time} ---- the end of the flight recorder ----"));
        // A line after the dump is written again, though it is the same
        // as the one before the dump.
        self.last.clear();
    }

    /// The count of a line that came again, before a different one.
    fn end_repeats(&mut self, time: &str) {
        if self.repeats > 0 {
            let repeats = std::mem::take(&mut self.repeats);
            self.raw(&format!("{time} (the line before came {repeats} more times)"));
        }
    }

    /// One line, in one write: a line is whole in the file when the
    /// process ends after it.
    fn raw(&mut self, line: &str) {
        let mut bytes = Vec::with_capacity(line.len() + 1);
        bytes.extend_from_slice(line.as_bytes());
        bytes.push(b'\n');
        // A log that cannot be written cannot say so: the line goes.
        if self.file.write_all(&bytes).is_ok() {
            self.written += u64::try_from(bytes.len()).unwrap_or(u64::MAX);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read(path: &Path) -> String {
        fs::read_to_string(path).unwrap_or_default()
    }

    fn slot(dir: &Path) -> Slot {
        Slot::take(dir).unwrap().expect("a free slot")
    }

    #[test]
    fn the_state_folder_keeps_five_runs() {
        let dir = tempfile::tempdir().unwrap();
        for run in 0..7 {
            let slot = slot(dir.path());
            slot.rotate(None).unwrap();
            let mut log = LogFile::create(&slot.run(0)).unwrap();
            log.line("t", &format!("INFO  test: run {run}"));
        }
        assert!(read(&dir.path().join("paw.log")).contains("run 6"));
        assert!(read(&dir.path().join("paw.log.4")).contains("run 2"));
        assert!(!dir.path().join("paw.log.5").exists());
    }

    #[test]
    fn a_second_session_takes_the_next_slot_and_leaves_the_first_alone() {
        let dir = tempfile::tempdir().unwrap();
        let first = slot(dir.path());
        first.rotate(None).unwrap();
        LogFile::create(&first.run(0)).unwrap().line("t", "INFO  test: first");
        let second = slot(dir.path());
        second.rotate(None).unwrap();
        LogFile::create(&second.run(0)).unwrap().line("t", "INFO  test: second");
        assert_eq!(second.run(0), dir.path().join("paw.2.log"));
        assert_eq!(second.stderr(Path::new("c")), Path::new("c/stderr.2.log"));
        assert!(read(&dir.path().join("paw.log")).contains("first"));
        assert!(!dir.path().join("paw.log.1").exists());
        // The lock goes with the session: the next one takes slot 1 again.
        drop(first);
        assert_eq!(slot(dir.path()).run(1), dir.path().join("paw.log.1"));
    }

    #[test]
    fn the_output_of_other_code_goes_into_the_log_of_its_run() {
        let dir = tempfile::tempdir().unwrap();
        let stderr = dir.path().join("stderr.log");
        let slot = slot(dir.path());
        LogFile::create(&slot.run(0)).unwrap().line("t", "INFO  test: the run before");
        fs::write(&stderr, "plugin Reverb: hello").unwrap();
        slot.rotate(Some(&stderr)).unwrap();
        let before = read(&slot.run(1));
        assert!(before.contains("the run before"), "{before}");
        assert!(before.ends_with("---\nplugin Reverb: hello\n"), "{before}");
        assert_eq!(read(&stderr), "");
        // Folded one time only.
        slot.rotate(Some(&stderr)).unwrap();
        assert!(!read(&slot.run(1)).contains("plugin Reverb"));
    }

    #[test]
    fn a_line_that_comes_again_is_counted() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("paw.log");
        let mut log = LogFile::create(&path).unwrap();
        for _ in 0..4 {
            assert!(log.line("t", "WARN  audio: xruns 3"));
        }
        log.line("t", "INFO  undo: step 2");
        assert_eq!(
            read(&path),
            "t WARN  audio: xruns 3\nt (the line before came 3 more times)\nt INFO  undo: step 2\n"
        );
    }

    #[test]
    fn a_full_log_takes_only_dumps() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("paw.log");
        let mut log = LogFile::create(&path).unwrap();
        let long = "x".repeat(1 << 20);
        let mut written = 0;
        while log.line("t", &format!("INFO  test: {written} {long}")) {
            written += 1;
        }
        assert_eq!(written, 9);
        assert!(!log.line("t", "INFO  test: later"));
        log.dump("t", "flight recorder", ["t DEBUG test: kept"].into_iter());
        let text = read(&path);
        assert!(text.contains("paw.log is full (10 MB)"));
        assert!(!text.contains("later"));
        assert!(text.contains("t DEBUG test: kept"));
    }
}
