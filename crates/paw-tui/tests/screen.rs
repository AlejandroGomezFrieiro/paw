//! The terminal shows paw's frame and nothing else: what plugins, libraries
//! and child processes print goes to a log, `<C-l>` draws the whole screen
//! again over text that came another way, and a panic gives the terminal
//! back before its message. paw.log keeps the lines of paw, of Lua and of
//! plugins, at the levels that `PAW_LOG` and `paw.opt.loglevel` give, and
//! `:log` shows it.

#![expect(clippy::unwrap_used, reason = "test code: a failed unwrap is a failed test")]

mod pty;
mod sealed;

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::mpsc::{Receiver, channel};

use paw_core::rpc::Connection;
use serde_json::json;

/// The end of a frame: paw ends each one with the end of a synchronized
/// update.
const FRAME_END: &str = "\x1b[?2026l";

/// paw in a pseudo-terminal, with what it wrote there so far. It ends
/// with the test.
struct Screen {
    child: Child,
    dir: PathBuf,
    keys: std::fs::File,
    written: Receiver<Vec<u8>>,
    /// The bytes that came on the terminal, as text.
    text: String,
    socket: PathBuf,
}

impl Drop for Screen {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

impl Screen {
    /// Start paw with no project and wait for its first frame.
    fn start(name: &str) -> Self {
        Self::start_with(name, |_, _| {})
    }

    /// The same, with what `change` does to the command first, in the
    /// test's folder.
    fn start_with(name: &str, change: impl FnOnce(&Path, &mut Command)) -> Self {
        // A short path: a Unix socket's must fit in 108 bytes.
        let dir = std::env::temp_dir().join(format!("paw-sc-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let socket = dir.join("paw.sock");
        let (master, slave) = pty::pty();
        let mut command = Command::new(env!("CARGO_BIN_EXE_paw"));
        change(&dir, &mut command);
        sealed::seal(&mut command, &dir);
        command
            .env("TERM", "xterm-256color")
            .args(["--clean", "--no-plugins", "--audio", "null", "--listen"])
            .arg(&socket);
        pty::run_in(&mut command, &slave);
        let child = command.spawn().expect("starting paw");
        // What paw writes is read at once, so that it never waits on a
        // full terminal.
        let (send, written) = channel();
        let mut reader = master.try_clone().unwrap();
        std::thread::spawn(move || {
            let mut buf = [0u8; 8192];
            while let Ok(n) = reader.read(&mut buf) {
                if n == 0 || send.send(buf[..n].to_vec()).is_err() {
                    break;
                }
            }
        });
        let mut screen = Self { child, dir, keys: master, written, text: String::new(), socket };
        screen.wait_for("the first frame", |text| text.contains(FRAME_END));
        screen
    }

    /// The control socket. paw listens on it before it draws the first
    /// frame.
    fn connect(&self) -> Connection {
        Connection::unix(&self.socket).expect("paw listens before its first frame")
    }

    /// Read what paw writes on the terminal until `done` holds of all of
    /// it. The stall guard of the test runner ends a wait that never ends.
    fn wait_for(&mut self, what: &str, done: impl Fn(&str) -> bool) {
        while !done(&self.text) {
            let Ok(bytes) = self.written.recv() else {
                panic!("the terminal closed before {what}:\n{:?}", self.text);
            };
            self.text.push_str(&String::from_utf8_lossy(&bytes));
        }
    }

    /// The log that takes what the process and its children print.
    fn log(&self) -> String {
        std::fs::read_to_string(self.dir.join("xdg/cache/paw/stderr.log")).unwrap_or_default()
    }

    /// paw.log of this run, in the state folder.
    fn paw_log(&self) -> String {
        std::fs::read_to_string(self.dir.join("xdg/state/paw/paw.log")).unwrap_or_default()
    }

    /// Type `keys` on the terminal and wait until a frame after them shows
    /// `shown`.
    fn type_until(&mut self, keys: &str, shown: &str) {
        let before = self.text.len();
        self.keys.write_all(keys.as_bytes()).unwrap();
        self.wait_for(shown, |text| visible(&text[before..]).contains(shown));
    }
}

/// `text` with the escape sequences of the terminal left out: what the
/// cells show, in the order that they were written.
fn visible(text: &str) -> String {
    let mut out = String::new();
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '\x1b' {
            out.push(c);
            continue;
        }
        // A control sequence ends at its first byte in @ to ~.
        if chars.next_if_eq(&'[').is_some() {
            while chars.next().is_some_and(|c| !('@'..='~').contains(&c)) {}
        } else {
            chars.next();
        }
    }
    out
}

/// Wait until the frame drawn after `mark` shows on the message line: the
/// terminal then has everything that paw wrote before it.
fn sync(screen: &mut Screen, c: &mut Connection, mark: &str) {
    c.call("eval", json!(["paw.notify(...)", mark])).unwrap();
    screen.wait_for("the mark", |text| visible(text).contains(mark));
}

#[test]
fn what_plugins_libraries_and_child_processes_print_goes_to_the_log_and_not_on_the_screen() {
    let mut screen = Screen::start("print");
    let mut c = screen.connect();
    // As a library in the process writes, and as a plugin host or a helper
    // that inherits the descriptors does.
    let print = "io.stdout:write('stray-out\\n') io.stdout:flush() io.stderr:write('stray-err\\n') \
                 os.execute('echo stray-child; echo stray-child-err >&2')";
    c.call("eval", json!([print])).unwrap();
    sync(&mut screen, &mut c, "after-the-print");
    assert!(!screen.text.contains("stray"), "nothing printed reaches the terminal:\n{:?}", screen.text);
    let log = screen.log();
    for line in ["stray-out", "stray-err", "stray-child", "stray-child-err"] {
        assert!(log.contains(line), "{line} is in the log:\n{log}");
    }
}

/// A device written in Lua runs in a plugin host, as a plugin does.
const PRINTER: &str = r#"
io.stdout:write("host-out\n")
io.stdout:flush()
io.stderr:write("host-err\n")
local dsp = require("paw.dsp")
local dev = dsp.device { name = "Printer" }
function dev.process(b) end
return dev
"#;

#[test]
fn what_a_plugin_host_prints_goes_to_paw_log_with_the_name_of_the_plugin() {
    let mut screen = Screen::start("host");
    let mut c = screen.connect();
    let devices = screen.dir.join("devices");
    std::fs::create_dir_all(&devices).unwrap();
    std::fs::write(devices.join("printer.lua"), PRINTER).unwrap();
    let add = "paw.luadev.add_dir(...) paw.add_part({ name = 'P' }):add_device('lua:printer')";
    c.call("eval", json!([add, devices.to_string_lossy()])).unwrap();
    // The reader of the host's pipe writes to the log on a thread of its
    // own: each round trip lets it go on.
    while !(screen.paw_log().contains("INFO  plugin: Printer: host-out")
        && screen.paw_log().contains("INFO  plugin: Printer: host-err"))
    {
        c.call("eval", json!(["return true"])).unwrap();
    }
    sync(&mut screen, &mut c, "after-the-host");
    assert!(!screen.text.contains("host-out") && !screen.text.contains("host-err"), "not on the screen:\n{:?}", screen.text);
}

#[test]
fn with_no_log_paw_starts_and_says_that_plugin_output_can_come_on_the_screen() {
    // A cache folder that cannot be made: its path is a file.
    let mut screen = Screen::start_with("nolog", |dir, command| {
        std::fs::write(dir.join("cache"), "").unwrap();
        command.env("XDG_CACHE_HOME", dir.join("cache"));
    });
    screen.wait_for("the message", |text| visible(text).contains("no log for the output of plugins"));
}

#[test]
fn ctrl_l_clears_the_terminal_and_draws_each_cell_again() {
    let mut screen = Screen::start("redraw");
    let mut c = screen.connect();
    // Text that comes on the terminal another way: a program that writes
    // to the terminal itself.
    c.call("eval", json!(["os.execute('printf stray-tty > /dev/tty')"])).unwrap();
    screen.wait_for("the stray text", |text| text.contains("stray-tty"));
    let before = screen.text.len();
    screen.keys.write_all(b"\x0c").unwrap();
    screen.wait_for("a frame after the key", |text| text[before..].contains(FRAME_END));
    let after = &screen.text[before..];
    let cleared = after.find("\x1b[2J").expect("the terminal is cleared");
    let shown = visible(&after[cleared..]);
    assert!(shown.contains("NOR"), "the whole screen is written again, the status line too:\n{shown}");
}

#[test]
fn a_panic_gives_the_terminal_back_and_prints_its_message_there() {
    let mut screen = Screen::start("panic");
    let mut c = screen.connect();
    // The program ends in the call, so it has no answer.
    let _ = c.call("eval", json!(["paw.api.test_panic('a bug for the screen test')"]));
    screen.wait_for("the message of the panic", |text| text.contains("a bug for the screen test"));
    let message = screen.text.find("a bug for the screen test").unwrap();
    assert!(screen.text[..message].contains("\x1b[?1049l"), "the normal screen comes back before the message");
}

#[test]
fn a_panic_leaves_its_message_its_backtrace_and_the_detail_before_it_in_paw_log() {
    let mut screen = Screen::start("panic-log");
    let mut c = screen.connect();
    c.call("eval", json!(["paw.api.log('the detail before', 'debug')"])).unwrap();
    let _ = c.call("eval", json!(["paw.api.test_panic('a bug for the log')"]));
    screen.wait_for("where the log is", |text| text.contains("the log of this run is"));
    let log = screen.paw_log();
    let detail = log.find("DEBUG lua: the detail before").expect("the flight recorder is in the log");
    let panic = log.find("ERROR panic: ").expect("the panic is in the log");
    assert!(detail < panic, "the detail comes before the panic:\n{log}");
    assert!(log[panic..].contains("a bug for the log") && log[panic..].contains("end_program"), "with its backtrace:\n{log}");
}

#[test]
fn paw_log_has_the_start_and_the_lines_of_lua_at_the_levels_of_loglevel() {
    let mut screen = Screen::start("levels");
    let mut c = screen.connect();
    let say = "paw.api.log('info-before') paw.opt.loglevel = 'warn,undo=info' \
               paw.api.log('info-after') paw.api.log('warn-after', 'warn') \
               paw.api.log('kept-detail', 'debug') paw.notify('a failure', 'error')";
    c.call("eval", json!([say])).unwrap();
    let log = screen.paw_log();
    assert!(log.contains("INFO  start: paw ") && log.contains("INFO  lua: sound: "), "the start header:\n{log}");
    // An error writes the detail that the file left out before it.
    let recorder = log.find("---- flight recorder").expect("the flight recorder is in the log");
    let (before, dump) = log.split_at(recorder);
    assert!(before.contains("info-before") && !before.contains("info-after") && before.contains("WARN  lua: warn-after"), "{log}");
    let detail = dump.find("DEBUG lua: kept-detail").expect("the detail is in the flight recorder");
    assert!(dump.contains("info-after") && detail < dump.find("ERROR lua: a failure").unwrap(), "{log}");
    sync(&mut screen, &mut c, "after-the-levels");
}

#[test]
fn paw_log_wins_over_loglevel() {
    let screen = Screen::start_with("paw-log", |_, command| {
        command.env("PAW_LOG", "error");
    });
    let mut c = screen.connect();
    c.call("eval", json!(["paw.opt.loglevel = 'debug' paw.api.log('not-written', 'warn')"])).unwrap();
    let log = screen.paw_log();
    assert!(!log.contains("not-written") && !log.contains("INFO  start"), "{log}");
}

#[test]
fn two_sessions_at_once_each_keep_their_own_log() {
    let first = Screen::start("log-a");
    let xdg = first.dir.join("xdg");
    let second = Screen::start_with("log-b", |_, command| {
        command.env("XDG_STATE_HOME", xdg.join("state")).env("XDG_CACHE_HOME", xdg.join("cache"));
    });
    first.connect().call("eval", json!(["paw.api.log('from-first')"])).unwrap();
    let mut c = second.connect();
    c.call("eval", json!(["paw.api.log('from-second')"])).unwrap();
    let files = c.call("eval", json!(["local f = paw.api.log_files() return f.current .. ' ' .. f.stderr"])).unwrap();
    let state = xdg.join("state/paw");
    let read = |name: &str| std::fs::read_to_string(state.join(name)).unwrap_or_default();
    // The second session did not rotate the log that the first writes.
    assert!(!state.join("paw.log.1").exists(), "paw.log of the first session was renamed");
    assert!(read("paw.log").contains("from-first") && !read("paw.log").contains("from-second"), "{}", read("paw.log"));
    assert!(read("paw.2.log").contains("from-second") && !read("paw.2.log").contains("from-first"), "{}", read("paw.2.log"));
    let files = files.to_string();
    assert!(files.contains("paw/paw.2.log ") && files.contains("stderr.2.log"), ":log of the second session: {files}");
}

#[test]
fn log_dump_writes_the_detail_that_the_file_left_out() {
    let mut screen = Screen::start("log-dump");
    screen.connect().call("eval", json!(["paw.api.log('kept-detail', 'debug')"])).unwrap();
    assert!(!screen.paw_log().contains("kept-detail"));
    screen.type_until(":log dump\r", "flight recorder");
    let log = screen.paw_log();
    let dump = log.find("---- flight recorder").expect("a dump in the log");
    assert!(log[dump..].contains("DEBUG lua: kept-detail"), "{log}");
}

#[test]
fn an_error_that_ends_paw_is_said_once() {
    let dir = std::env::temp_dir().join(format!("paw-sc-once-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let mut paw = Command::new(env!("CARGO_BIN_EXE_paw"));
    sealed::seal(&mut paw, &dir).args(["--clean", "--no-plugins", "--audio", "null", "-l", "no-such-script.lua"]);
    let out = paw.output().unwrap();
    let _ = std::fs::remove_dir_all(&dir);
    let said = String::from_utf8_lossy(&out.stderr);
    assert!(!out.status.success());
    assert_eq!(said.matches("no-such-script.lua").count(), 1, "{said}");
}

#[test]
fn log_shows_this_run_and_log_bang_the_run_before() {
    let mut screen = Screen::start_with("log-cmd", |dir, _| {
        let state = dir.join("xdg/state/paw");
        std::fs::create_dir_all(&state).unwrap();
        std::fs::write(state.join("paw.log"), "a line of the run before\n").unwrap();
    });
    screen.type_until(":log\r", "Log of this run");
    assert!(visible(&screen.text).contains("start:"), "the header of this run shows");
    screen.type_until(":log!\r", "a line of the run before");
}
