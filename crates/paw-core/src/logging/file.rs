//! `paw.log` on disk: the rotation of the runs at the start, the cap of one
//! run, and the fold of a line that comes again.

use std::fs::{self, File, OpenOptions};
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

/// The log of run `n` back: 0 is this run (`paw.log`), 1 the run before.
pub(super) fn run_path(dir: &Path, n: usize) -> PathBuf {
    match n {
        0 => dir.join("paw.log"),
        n => dir.join(format!("paw.log.{n}")),
    }
}

/// Make room for a new run: each log moves one run back, and the oldest
/// goes. Then the text of `stderr` (the output of other code in the run
/// before, ADR 0042) goes at the end of the log of that run, and `stderr`
/// is emptied, so that it goes in one time only.
pub(super) fn rotate(dir: &Path, stderr: Option<&Path>) -> io::Result<()> {
    fs::create_dir_all(dir)?;
    for n in (0..RUNS - 1).rev() {
        match fs::rename(run_path(dir, n), run_path(dir, n + 1)) {
            Err(err) if err.kind() != io::ErrorKind::NotFound => return Err(err),
            _ => {}
        }
    }
    // The text of `stderr.log` is a help: a log goes on without it (a
    // cache folder that cannot be read, for example).
    if let Some(stderr) = stderr {
        let _ = fold_stderr(stderr, &run_path(dir, 1));
    }
    Ok(())
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
    /// Open a new, empty `paw.log` in `dir`.
    pub(super) fn create(dir: &Path) -> io::Result<Self> {
        let file = File::create(run_path(dir, 0))?;
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

    #[test]
    fn the_state_folder_keeps_five_runs() {
        let dir = tempfile::tempdir().unwrap();
        for run in 0..7 {
            rotate(dir.path(), None).unwrap();
            let mut log = LogFile::create(dir.path()).unwrap();
            log.line("t", &format!("INFO  test: run {run}"));
        }
        assert!(read(&run_path(dir.path(), 0)).contains("run 6"));
        assert!(read(&run_path(dir.path(), 4)).contains("run 2"));
        assert!(!run_path(dir.path(), 5).exists());
    }

    #[test]
    fn the_output_of_other_code_goes_into_the_log_of_its_run() {
        let dir = tempfile::tempdir().unwrap();
        let stderr = dir.path().join("stderr.log");
        LogFile::create(dir.path()).unwrap().line("t", "INFO  test: the run before");
        fs::write(&stderr, "plugin Reverb: hello").unwrap();
        rotate(dir.path(), Some(&stderr)).unwrap();
        let before = read(&run_path(dir.path(), 1));
        assert!(before.contains("the run before"), "{before}");
        assert!(before.ends_with("---\nplugin Reverb: hello\n"), "{before}");
        assert_eq!(read(&stderr), "");
        // Folded one time only.
        rotate(dir.path(), Some(&stderr)).unwrap();
        assert!(!read(&run_path(dir.path(), 1)).contains("plugin Reverb"));
    }

    #[test]
    fn a_line_that_comes_again_is_counted() {
        let dir = tempfile::tempdir().unwrap();
        let mut log = LogFile::create(dir.path()).unwrap();
        for _ in 0..4 {
            assert!(log.line("t", "WARN  audio: xruns 3"));
        }
        log.line("t", "INFO  undo: step 2");
        assert_eq!(
            read(&run_path(dir.path(), 0)),
            "t WARN  audio: xruns 3\nt (the line before came 3 more times)\nt INFO  undo: step 2\n"
        );
    }

    #[test]
    fn a_full_log_takes_only_dumps() {
        let dir = tempfile::tempdir().unwrap();
        let mut log = LogFile::create(dir.path()).unwrap();
        let long = "x".repeat(1 << 20);
        let mut written = 0;
        while log.line("t", &format!("INFO  test: {written} {long}")) {
            written += 1;
        }
        assert_eq!(written, 9);
        assert!(!log.line("t", "INFO  test: later"));
        log.dump("t", "flight recorder", ["t DEBUG test: kept"].into_iter());
        let text = read(&run_path(dir.path(), 0));
        assert!(text.contains("paw.log is full (10 MB)"));
        assert!(!text.contains("later"));
        assert!(text.contains("t DEBUG test: kept"));
    }
}
