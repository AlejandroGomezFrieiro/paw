//! A take survives what ends it badly: a disk that will take no more, and the
//! program being killed in the middle of it.

mod sealed;

use std::io::{BufRead, BufReader};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

fn scratch(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR"))
        .join(format!("safety-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// `paw --no-plugins <args> -l <script> <dir>`, sealed in `dir`.
fn paw(dir: &Path, script: &str, args: &[&Path]) -> Command {
    paw_plugins(dir, script, args, false)
}

/// The same, with plugins found as the program finds them, if `plugins`.
fn paw_plugins(dir: &Path, script: &str, args: &[&Path], plugins: bool) -> Command {
    let file = dir.join(format!("script-{}.lua", script.len()));
    std::fs::write(&file, script).unwrap();
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut command = Command::new(env!("CARGO_BIN_EXE_paw"));
    command.current_dir(&root);
    if !plugins {
        command.arg("--no-plugins");
    }
    command.args(args).arg("-l").arg(&file).arg(dir);
    sealed::seal(&mut command, dir);
    command
}

const RECORD: &str = r#"
local api = paw.api
local dir = ...
api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })
local mic = paw.add_track({ name = "mic" })
mic.input, mic.armed = "1", true
paw.project.save(dir .. "/song.json")
"#;

#[test]
fn a_disk_that_fills_up_stops_the_take_and_keeps_it() {
    let dir = scratch("full");
    let script = format!(
        r#"{RECORD}
paw.transport.record()
local waited = 0
while paw.transport.playing and waited < 15000 do paw.wait(100) waited = waited + 100 end
paw.flush()
local clips = mic:clips()
print("playing", tostring(paw.transport.playing))
print("clips", #clips)
print("beats", clips[1] and clips[1].length or 0)
for _, m in ipairs(paw.ui.messages) do print("message", m.text) end
"#
    );
    let mut command = paw(&dir, &script, &[Path::new("--clean")]);
    // Files may grow to 600 kB: about three seconds of a mono take.
    // SAFETY: only async-signal-safe calls between fork and exec.
    unsafe {
        command.pre_exec(|| {
            libc::signal(libc::SIGXFSZ, libc::SIG_IGN);
            let limit = libc::rlimit {
                rlim_cur: 600_000,
                rlim_max: 600_000,
            };
            libc::setrlimit(libc::RLIMIT_FSIZE, &limit);
            Ok(())
        });
    }
    let out = command.output().unwrap();
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        out.status.success(),
        "{stdout}\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(
        stdout.contains("playing\tfalse"),
        "the transport stopped:\n{stdout}"
    );
    assert!(stdout.contains("clips\t1"), "the take is a clip:\n{stdout}");
    let beats: f64 = stdout
        .lines()
        .find_map(|l| l.strip_prefix("beats\t"))
        .and_then(|b| b.parse().ok())
        .unwrap();
    // 600 kB of 4-byte mono samples at 48 kHz is 3.1 s, 6.2 beats at 120 bpm.
    assert!(
        (beats - 6.25).abs() < 0.1,
        "with what fitted on the disk: {beats} beats"
    );
    assert!(
        stdout.contains("recording stopped") && stdout.contains("too large"),
        "the user is told why:\n{stdout}"
    );
}

#[test]
fn a_take_survives_the_program_being_killed() {
    let dir = scratch("killed");
    let script = format!(
        r#"{RECORD}
paw.opt.autosave = 60
paw.transport.record()
paw.flush()
print("recording")
io.stdout:flush()
paw.wait(20000)
"#
    );
    let mut command = paw(&dir, &script, &[]);
    command.stdout(Stdio::piped());
    let mut child = command.spawn().unwrap();
    let mut lines = BufReader::new(child.stdout.take().unwrap()).lines();
    let started = Instant::now();
    loop {
        let line = lines.next().expect("the script started").unwrap();
        if line == "recording" {
            break;
        }
        assert!(started.elapsed() < Duration::from_secs(30));
    }
    std::thread::sleep(Duration::from_millis(3500));
    // SIGKILL: nothing of the program runs after this.
    child.kill().unwrap();
    child.wait().unwrap();

    let check = r#"
local dir = ...
paw.flush()
for _, m in ipairs(paw.ui.messages) do print("message", m.text) end
local takes = paw.autosave.orphan_takes()
print("orphans", #takes)
local choices = paw.autosave.choices()
for i, c in ipairs(choices) do print("choice", i, c.name, c.take and "take" or "copy") end
-- The safety copy puts the take back where it was, on its track.
for i, c in ipairs(choices) do
  if not c.take and c.path == dir .. "/song.json" then
    paw.commands.exec("recover " .. i)
    break
  end
end
local clips = paw.tracks()[1]:clips()
print("track", paw.tracks()[1].name)
print("clips", #clips)
print("beats", clips[1] and clips[1].length or 0)
"#;
    let song = dir.join("song.json");
    let mut command = paw(&dir, check, &[&song]);
    let out = command.output().unwrap();
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        out.status.success(),
        "{stdout}\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(
        stdout.contains("orphans\t1"),
        "the take file is offered:\n{stdout}"
    );
    assert!(
        stdout.contains("recorded take in media/"),
        "and named on opening:\n{stdout}"
    );
    assert!(
        stdout.contains("track\tmic") && stdout.contains("clips\t1"),
        "recovered onto its track:\n{stdout}"
    );
    let beats: f64 = stdout
        .lines()
        .find_map(|l| l.strip_prefix("beats\t"))
        .and_then(|b| b.parse().ok())
        .unwrap();
    // Killed after 3.5 s; the header is at most two seconds behind.
    assert!(
        beats >= 2.0 && beats <= 7.5,
        "with what was recorded: {beats} beats"
    );
}

/// A `.clap` whose loading runs `body` (C) first: a library that kills or
/// stalls whatever loads it.
fn bad_plugin(dir: &Path, name: &str, body: &str) -> PathBuf {
    let source = dir.join(format!("{name}.c"));
    std::fs::write(
        &source,
        format!(
            "#include <signal.h>\n#include <unistd.h>\n__attribute__((constructor)) static void load(void) {{ {body} }}\n"
        ),
    )
    .unwrap();
    let out = dir.join("clap").join(format!("{name}.clap"));
    std::fs::create_dir_all(out.parent().unwrap()).unwrap();
    let status = Command::new("cc")
        .args(["-shared", "-fPIC", "-o"])
        .arg(&out)
        .arg(&source)
        .status()
        .expect("a C compiler");
    assert!(status.success());
    out
}

const MESSAGES: &str = r#"
paw.flush()
for _, m in ipairs(paw.ui.messages) do print("message", m.text) end
"#;

#[test]
fn plugin_files_that_failed_are_skipped_until_rescanned() {
    let dir = scratch("scan");
    std::fs::create_dir_all(dir.join("clap")).unwrap();
    std::fs::write(
        dir.join("clap/notalibrary.clap"),
        b"this is not a shared library",
    )
    .unwrap();
    bad_plugin(&dir, "killed", "kill(getpid(), SIGKILL);");
    let run = |script: &str| {
        let mut command = paw_plugins(&dir, script, &[Path::new("--clean")], true);
        command.env_remove("PAW_TEST_PLUGINS");
        command
            .env("CLAP_PATH", dir.join("clap"))
            .env("VST3_PATH", dir.join("none"))
            .env("LV2_PATH", dir.join("none"));
        let out = command.output().unwrap();
        let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
        assert!(
            out.status.success(),
            "{stdout}\n{}",
            String::from_utf8_lossy(&out.stderr)
        );
        stdout
    };
    let first = run(MESSAGES);
    assert!(
        !first.contains("skipped"),
        "the first start looks into both:\n{first}"
    );
    let second = run(MESSAGES);
    assert!(
        second.contains("skipped 2 plugin files")
            && second.contains("killed.clap")
            && second.contains("notalibrary.clap"),
        "the second start says what it skipped, in one line:\n{second}"
    );
    // Asked, it looks again: and finds them failing again.
    let rescan = format!(
        "{MESSAGES}\nlocal notes = paw.api.plugins_rescan('killed')\nprint('notes', #notes)\nfor _, n in ipairs(notes) do print('note', n) end"
    );
    let third = run(&rescan);
    assert!(
        third.contains(
            "note\tskipped 1 plugin file that failed when looked into before (notalibrary.clap)"
        ),
        "only the named one is looked into again:\n{third}"
    );
    assert!(
        third.contains("crashed while it was looked into"),
        "and it crashes again:\n{third}"
    );
}

#[test]
fn a_plugin_file_being_scanned_when_the_program_is_killed_is_skipped_next_time() {
    let dir = scratch("scan-killed");
    bad_plugin(&dir, "stalls", "sleep(6);");
    let mut command = paw_plugins(&dir, MESSAGES, &[Path::new("--clean")], true);
    command.env_remove("PAW_TEST_PLUGINS");
    command
        .env("CLAP_PATH", dir.join("clap"))
        .env("VST3_PATH", dir.join("none"))
        .env("LV2_PATH", dir.join("none"));
    let mut child = command.stdout(Stdio::null()).spawn().unwrap();
    std::thread::sleep(Duration::from_millis(1500));
    child.kill().unwrap();
    child.wait().unwrap();

    let mut command = paw_plugins(&dir, MESSAGES, &[Path::new("--clean")], true);
    command.env_remove("PAW_TEST_PLUGINS");
    command
        .env("CLAP_PATH", dir.join("clap"))
        .env("VST3_PATH", dir.join("none"))
        .env("LV2_PATH", dir.join("none"));
    let out = command.output().unwrap();
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        stdout.contains("skipped 1 plugin file") && stdout.contains("stalls.clap"),
        "the second start skips it and says so:\n{stdout}"
    );
}

#[test]
fn a_panic_in_the_program_keeps_a_safety_copy() {
    let dir = scratch("panic");
    let script = r#"
paw.add_track({ name = "Unsaved idea" })
paw.flush()
paw.api.test_panic("a bug in the program")
"#;
    let out = paw(&dir, script, &[Path::new("--clean")]).output().unwrap();
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(!out.status.success(), "the program ends");
    assert!(
        stderr.contains("a bug in the program"),
        "with the panic's message:\n{stderr}"
    );
    assert!(
        stderr.contains("`:recover` opens it"),
        "and where the copy is:\n{stderr}"
    );
    let recovery = dir.join("xdg/state/paw/recovery");
    let copies: Vec<_> = std::fs::read_dir(&recovery).unwrap().flatten().collect();
    assert_eq!(copies.len(), 1, "one copy in {}", recovery.display());
    let text = std::fs::read_to_string(copies[0].path()).unwrap();
    assert!(
        text.contains("Unsaved idea"),
        "the copy has the unsaved work"
    );

    // The next start offers it, and it opens.
    let check = r#"
local list = paw.autosave.left_behind()
print("left", #list)
paw.commands.exec("recover 1")
print("track", paw.tracks()[1].name)
"#;
    let out = paw(&dir, check, &[Path::new("--clean")]).output().unwrap();
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        stdout.contains("left\t1") && stdout.contains("track\tUnsaved idea"),
        "{stdout}"
    );
}

#[test]
fn a_take_cut_off_by_a_kill_is_offered_after_the_folder_moved() {
    let dir = scratch("killed-moved");
    std::fs::create_dir_all(dir.join("proj")).unwrap();
    let script = r#"
local dir = ...
paw.api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })
local mic = paw.add_track({ name = "mic" })
mic.input, mic.armed = "1", true
paw.project.save(dir .. "/proj/song.json")
paw.transport.record()
paw.flush()
print("recording")
io.stdout:flush()
paw.wait(20000)
"#;
    let mut command = paw(&dir, script, &[]);
    command.stdout(Stdio::piped());
    let mut child = command.spawn().unwrap();
    let mut lines = BufReader::new(child.stdout.take().unwrap()).lines();
    while lines.next().expect("the script started").unwrap() != "recording" {}
    std::thread::sleep(Duration::from_millis(3500));
    child.kill().unwrap();
    child.wait().unwrap();
    std::fs::rename(dir.join("proj"), dir.join("moved")).unwrap();

    let check = r#"
paw.flush()
for _, m in ipairs(paw.ui.messages) do print("message", m.text) end
local takes = paw.autosave.orphan_takes()
print("orphans", #takes)
if takes[1] then paw.autosave.import_take(takes[1].file) end
local mic = paw.tracks()[1]
print("track", mic.name, #mic:clips())
print("beats", mic:clips()[1] and mic:clips()[1].length or 0)
"#;
    let song = dir.join("moved/song.json");
    let out = paw(&dir, check, &[&song]).output().unwrap();
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        out.status.success(),
        "{stdout}\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(
        stdout.contains("orphans\t1"),
        "the take is offered:\n{stdout}"
    );
    assert!(
        stdout.contains("track\tmic\t1"),
        "and lands on its track:\n{stdout}"
    );
    let beats: f64 = stdout
        .lines()
        .find_map(|l| l.strip_prefix("beats\t"))
        .and_then(|b| b.parse().ok())
        .unwrap();
    assert!(
        (2.0..=7.5).contains(&beats),
        "with what was recorded: {beats} beats"
    );
}
