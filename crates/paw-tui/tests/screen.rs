//! The terminal shows paw's frame and nothing else: what plugins, libraries
//! and child processes print goes to a log, `<C-l>` draws the whole screen
//! again over text that came another way, and a panic gives the terminal
//! back before its message.

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
fn what_a_plugin_host_prints_goes_to_the_log_with_the_name_of_the_plugin() {
    let mut screen = Screen::start("host");
    let mut c = screen.connect();
    let devices = screen.dir.join("devices");
    std::fs::create_dir_all(&devices).unwrap();
    std::fs::write(devices.join("printer.lua"), PRINTER).unwrap();
    let add = "paw.luadev.add_dir(...) paw.add_part({ name = 'P' }):add_device('lua:printer')";
    c.call("eval", json!([add, devices.to_string_lossy()])).unwrap();
    // The reader of the host's pipe writes to the log on a thread of its
    // own: each round trip lets it go on.
    while !(screen.log().contains("plugin Printer: host-out") && screen.log().contains("plugin Printer: host-err")) {
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
