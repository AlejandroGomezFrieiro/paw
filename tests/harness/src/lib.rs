//! The Lua suite as tests of cargo-nextest.
//!
//! `tests/suite.lua` is the runner. It runs the test files of one part in
//! one paw. A part is a file of `tests/`, or all the test files of one
//! extension. This crate gives each part to nextest as one test, so that
//! nextest gives the parallelism, the limits of `.config/nextest.toml`,
//! the timeouts and the reports. Each part runs in a paw of its own,
//! through `tests/tools/run.sh`, which gives the sealed environment of
//! `tests/tools/env.sh`.

use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::Command;

/// Set in the environment of each paw of a run. A command that runs the
/// suite refuses to start when it is set: a test that starts the suite
/// again would start processes without end.
pub const IN_SUITE: &str = "PAW_TEST_IN_SUITE";

/// The words of `tests/tools/suite.sh only`, one on each line. A test runs
/// when its name holds one of them.
const WORDS: &str = "PAW_TEST_WORDS";

/// The line of the pass on the manual clock that gives the number of live
/// tests of the part that it selected (tests/suite.lua).
const LIVE_LINE: &str = "live tests: ";

/// The lines that the message of a failed part keeps after each line that
/// starts with `FAIL`: the reason of the failure.
const FAIL_CONTEXT: usize = 8;

/// The two passes of a part (tests/suite.lua). The tests run on the manual
/// clock and the stepped audio backend. The live tests, which need real
/// time, run after them in a second paw on the wall clock.
#[derive(Clone, Copy)]
enum Pass {
    Manual,
    Live,
}

/// One run of the suite: the checkout, the folder of its files, and the
/// words that select the tests.
#[derive(Clone)]
pub struct Suite {
    root: PathBuf,
    scratch: PathBuf,
    words: Option<String>,
}

impl Suite {
    /// The suite of this checkout. `PAW_TEST_SCRATCH` gives the folder of
    /// the run, as for tests/tools/env.sh, and `PAW_TEST_WORDS` the words.
    #[must_use]
    pub fn from_env() -> Self {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let scratch = env::var_os("PAW_TEST_SCRATCH")
            .map_or_else(|| root.join("target/test-scratch"), PathBuf::from);
        let words = env::var(WORDS)
            .ok()
            .filter(|words| !words.trim().is_empty());
        Self {
            root,
            scratch,
            words,
        }
    }

    /// The parts of the suite, in the order of tests/suite.lua. With words,
    /// a paw loads the test files and gives only the parts that hold a
    /// test whose name holds a word.
    ///
    /// # Errors
    ///
    /// The message of a paw that did not list the parts, for example a
    /// binary that is older than the runtime.
    pub fn parts(&self) -> Result<Vec<String>, String> {
        match &self.words {
            None => Ok(parts_in(&self.root)),
            Some(words) => self.parts_with(words),
        }
    }

    /// The parts that hold a test of the words: a paw prints one line
    /// `part<tab><part>` for each of them.
    fn parts_with(&self, words: &str) -> Result<Vec<String>, String> {
        let scratch = self.fresh_folder("list")?;
        let out = scratch.join("list.out");
        let status = self
            .paw(&scratch, &out, Pass::Manual, None)?
            .env("PAW_TEST_LIST", "1")
            .status();
        let printed = fs::read_to_string(&out).unwrap_or_default();
        match status {
            Ok(status) if status.success() => Ok(printed
                .lines()
                .filter_map(|line| line.strip_prefix("part\t"))
                .map(str::to_owned)
                .collect()),
            Ok(_) => Err(format!(
                "paw did not list the parts of the words {words:?}:\n{printed}"
            )),
            Err(error) => Err(format!("cannot start tests/tools/run.sh: {error}")),
        }
    }

    /// Run the tests of `part`: the pass on the manual clock, then the live
    /// pass when the part has live tests. The output of both is in
    /// `<scratch>/parts/<part>/suite.out`.
    ///
    /// # Errors
    ///
    /// The tests that failed, with their reasons, and the path of the
    /// whole output.
    pub fn run(&self, part: &str) -> Result<(), String> {
        let scratch = self.fresh_folder(&format!("parts/{}", folder_name(part)))?;
        let out = scratch.join("suite.out");
        let manual = self.pass(part, &scratch, &out, Pass::Manual)?;
        let printed = fs::read_to_string(&out).unwrap_or_default();
        let live = if live_tests(&printed) > 0 {
            self.pass(part, &scratch, &out, Pass::Live)?
        } else {
            true
        };
        if manual && live {
            return Ok(());
        }
        let printed = fs::read_to_string(&out).unwrap_or_default();
        Err(format!(
            "{}\nthe whole output: {}",
            failures(&printed),
            out.display()
        ))
    }

    /// Run one pass of `part`. Gives whether it passed.
    fn pass(&self, part: &str, scratch: &Path, out: &Path, pass: Pass) -> Result<bool, String> {
        self.paw(scratch, out, pass, Some(part))?
            .status()
            .map(|status| status.success())
            .map_err(|error| format!("cannot start paw for {part}: {error}"))
    }

    /// A paw of the suite in the sealed environment, with the folders of
    /// `scratch`. Its output goes to `out`. Its errors go to the error
    /// output of this test: nextest shows them, and a process that paw
    /// leaves behind holds it open, so nextest reports the leak.
    fn paw(
        &self,
        scratch: &Path,
        out: &Path,
        pass: Pass,
        part: Option<&str>,
    ) -> Result<Command, String> {
        let mut command = Command::new("sh");
        command
            .arg(self.root.join("tests/tools/run.sh"))
            .arg("--clean")
            .arg("--no-plugins");
        match pass {
            Pass::Manual => {
                command
                    .args(["--clock", "manual", "--audio", "step"])
                    .env_remove("PAW_TEST_LIVE");
            }
            Pass::Live => {
                command.env("PAW_TEST_LIVE", "1");
            }
        }
        command.arg("-l").arg("tests/suite.lua");
        if let Some(words) = &self.words {
            command.arg(words);
        }
        match part {
            Some(part) => command.env("PAW_TEST_PART", part),
            None => command.env_remove("PAW_TEST_PART"),
        };
        let file = output_file(out, pass)
            .map_err(|error| format!("cannot write {}: {error}", out.display()))?;
        command
            .env_remove("PAW_TEST_LIST")
            .env("PAW_TEST_SCRATCH", scratch)
            .env(IN_SUITE, "1")
            .stdout(file);
        Ok(command)
    }

    /// An empty folder of the run (the files of an earlier run go).
    fn fresh_folder(&self, name: &str) -> Result<PathBuf, String> {
        let folder = self.scratch.join(name);
        match fs::remove_dir_all(&folder) {
            Err(error) if error.kind() != ErrorKind::NotFound => {
                return Err(format!("cannot empty {}: {error}", folder.display()));
            }
            _ => {}
        }
        fs::create_dir_all(&folder)
            .map_err(|error| format!("cannot make {}: {error}", folder.display()))?;
        Ok(folder)
    }
}

/// The file of the output of a pass: the live pass adds to the output of
/// the pass before it.
fn output_file(out: &Path, pass: Pass) -> std::io::Result<File> {
    match pass {
        Pass::Manual => File::create(out),
        Pass::Live => OpenOptions::new().append(true).open(out),
    }
}

/// The parts of the checkout at `root`, as tests/suite.lua makes them:
/// each `tests/*.lua` but `suite.lua`, then `extensions/<name>/` for each
/// extension that has a file `tests*.lua`. A folder that is not there
/// gives no part (a build sandbox has no test files).
fn parts_in(root: &Path) -> Vec<String> {
    let mut parts: Vec<String> = file_names(&root.join("tests"))
        .into_iter()
        .filter(|name| name.ends_with(".lua") && name != "suite.lua")
        .map(|name| format!("tests/{name}"))
        .collect();
    let mut extensions = folder_names(&root.join("extensions"));
    extensions.sort();
    for extension in extensions {
        let has_tests = file_names(&root.join("extensions").join(&extension))
            .iter()
            .any(|name| name.starts_with("tests") && name.ends_with(".lua"));
        if has_tests {
            parts.push(format!("extensions/{extension}/"));
        }
    }
    parts
}

/// The names of the files in `dir`, sorted.
fn file_names(dir: &Path) -> Vec<String> {
    names(dir, false)
}

/// The names of the folders in `dir`, not sorted.
fn folder_names(dir: &Path) -> Vec<String> {
    names(dir, true)
}

fn names(dir: &Path, folders: bool) -> Vec<String> {
    let Ok(entries) = fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut out: Vec<String> = entries
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_dir() == folders))
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect();
    out.sort();
    out
}

/// The name of the scratch folder of a part: its path with each character
/// that is not a letter or a digit as `-`.
fn folder_name(part: &str) -> String {
    part.chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect()
}

/// The number of live tests that the pass on the manual clock selected.
fn live_tests(printed: &str) -> usize {
    printed
        .lines()
        .find_map(|line| line.strip_prefix(LIVE_LINE)?.trim().parse().ok())
        .unwrap_or(0)
}

/// What a person reads first of the output of a part that failed: each
/// line that starts with `FAIL` and the lines of its reason. With no such
/// line (paw stopped), the end of the output.
fn failures(printed: &str) -> String {
    let lines: Vec<&str> = printed.lines().collect();
    let mut keep = vec![false; lines.len()];
    for (index, line) in lines.iter().enumerate() {
        if line.starts_with("FAIL") {
            let end = (index + FAIL_CONTEXT + 1).min(lines.len());
            keep[index..end].fill(true);
        }
    }
    if !keep.contains(&true) {
        let start = lines.len().saturating_sub(20);
        return lines[start..].join("\n");
    }
    lines
        .iter()
        .zip(keep)
        .filter(|(_, kept)| *kept)
        .map(|(line, _)| *line)
        .collect::<Vec<_>>()
        .join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_parts_are_the_test_files_and_the_extensions_with_tests() {
        let root = tempfile::tempdir().expect("a scratch folder");
        for file in [
            "tests/modal.lua",
            "tests/core.lua",
            "tests/suite.lua",
            "tests/notes.txt",
            "tests/tools/env.sh",
            "extensions/utau/tests.lua",
            "extensions/utau/tests_engine.lua",
            "extensions/euclid/init.lua",
            "extensions/doctor/tests.lua",
        ] {
            let path = root.path().join(file);
            fs::create_dir_all(path.parent().expect("a folder")).expect("make the folder");
            fs::write(&path, "").expect("write the file");
        }
        let parts = parts_in(root.path());
        assert_eq!(
            parts,
            [
                "tests/core.lua",
                "tests/modal.lua",
                "extensions/doctor/",
                "extensions/utau/"
            ]
        );
    }

    #[test]
    fn a_checkout_without_tests_has_no_parts() {
        assert!(parts_in(Path::new("/nonexistent/checkout")).is_empty());
    }

    #[test]
    fn the_live_pass_runs_only_for_live_tests() {
        assert_eq!(live_tests("ok    a test\nlive tests: 3\n\nall passed\n"), 3);
        assert_eq!(live_tests("ok    a test\nlive tests: 0\n"), 0);
        assert_eq!(
            live_tests("FAIL  the binary has the kernel API of the runtime\n"),
            0
        );
    }

    #[test]
    fn a_failure_keeps_each_failed_test_and_its_reason() {
        let printed = "ok    one\nFAIL  two\n      the reason\nok    three\nok    four\nok    five\nok    six\n\
                       ok    seven\nok    eight\nok    nine\nok    ten\n\n1 failed";
        assert_eq!(
            failures(printed),
            "FAIL  two\n      the reason\nok    three\nok    four\nok    five\nok    six\nok    seven\nok    eight\nok    nine"
        );
    }

    #[test]
    fn a_paw_that_stopped_shows_the_end_of_its_output() {
        assert_eq!(
            failures("ok    one\npanicked at the kernel"),
            "ok    one\npanicked at the kernel"
        );
    }
}
