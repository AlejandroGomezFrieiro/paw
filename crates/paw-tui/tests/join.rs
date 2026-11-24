//! A second `paw` started on a project that a running paw has open joins it
//! as a new seat, in a terminal of its own (a pty here), and coming back to
//! that terminal (mode 1004) acts on changes made meanwhile to the
//! project's files.

#![expect(clippy::unwrap_used, reason = "test code: a failed unwrap is a failed test")]

mod sealed;

use std::io::{Read, Write};
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use paw_core::rpc::Connection;
use serde_json::{Value, json};

/// The processes of a test, ended when it is.
struct Running(Vec<Child>, PathBuf);

impl Drop for Running {
    fn drop(&mut self) {
        for child in &mut self.0 {
            let _ = child.kill();
            let _ = child.wait();
        }
        let _ = std::fs::remove_dir_all(&self.1);
    }
}

fn scratch(name: &str) -> PathBuf {
    // A short path: a Unix socket's must fit in 108 bytes.
    let dir = std::env::temp_dir().join(format!("paw-jn-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// `paw` with everything it keeps in `dir`: never the owner's folders.
fn paw(dir: &Path) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_paw"));
    sealed::seal(&mut command, dir);
    command.env("TERM", "xterm-256color");
    command.env_remove("PAW_TOKEN");
    command
}

/// A new pseudo-terminal of 100 by 30 cells: (its master side, the path
/// of its other side).
fn pty() -> (std::fs::File, PathBuf) {
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

/// Ask the running paw until `check` holds of the answer to `code`.
fn wait_for(c: &mut Connection, what: &str, code: &str, check: impl Fn(&Value) -> bool) -> Value {
    let until = Instant::now() + Duration::from_secs(20);
    loop {
        let got = c.call("eval", json!([code])).unwrap_or(Value::Null);
        if check(&got) {
            return got;
        }
        assert!(Instant::now() < until, "{what}: still {got}");
        std::thread::sleep(Duration::from_millis(50));
    }
}

#[test]
fn a_second_paw_on_an_open_project_joins_it_as_a_seat_and_acts_on_changes_when_its_terminal_gets_the_focus() {
    let dir = scratch("seat");
    let socket = dir.join("paw.sock");
    let headless = paw(&dir)
        .args(["--headless", "--clean", "--no-plugins", "--audio", "null", "--listen"])
        .arg(&socket)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("starting paw");
    let mut running = Running(vec![headless], dir.clone());
    let until = Instant::now() + Duration::from_secs(20);
    let mut c = loop {
        if let Ok(c) = Connection::unix(&socket) {
            break c;
        }
        assert!(Instant::now() < until, "the running paw never listened");
        std::thread::sleep(Duration::from_millis(50));
    };
    let song = dir.join("song");
    c.call(
        "eval",
        json!(["paw.add_part({ name = 'Bass' }); paw.project.save(...)", song.to_string_lossy()]),
    )
    .unwrap();
    let seats = |c: &mut Connection| c.call("eval", json!(["return #paw.seats.list()"])).unwrap();
    let before = seats(&mut c).as_u64().unwrap();

    // `paw song` in a terminal of its own.
    let (mut master, slave) = pty();
    let tty = || std::fs::OpenOptions::new().read(true).write(true).open(&slave).unwrap();
    let mut joiner = paw(&dir);
    joiner
        .args(["--clean", "--no-plugins"])
        .arg(&song)
        .stdin(Stdio::from(tty()))
        .stdout(Stdio::from(tty()))
        .stderr(Stdio::from(tty()));
    // SAFETY: only async-signal-safe calls between fork and exec.
    unsafe {
        joiner.pre_exec(|| {
            libc::setsid();
            libc::ioctl(0, libc::TIOCSCTTY, 0);
            Ok(())
        });
    }
    running.0.push(joiner.spawn().expect("starting the second paw"));
    // What it writes is read, so that it never waits on a full pty.
    let shown = Arc::new(Mutex::new(Vec::new()));
    let mut reader = master.try_clone().unwrap();
    let into = shown.clone();
    std::thread::spawn(move || {
        let mut buf = [0u8; 8192];
        while let Ok(n) = reader.read(&mut buf) {
            if n == 0 {
                break;
            }
            into.lock().unwrap().extend_from_slice(&buf[..n]);
        }
    });
    // SAFETY: `master` is open, so `dup` gives a new descriptor that nothing else owns.
    let _keep = unsafe { OwnedFd::from_raw_fd(libc::dup(master.as_raw_fd())) };

    wait_for(&mut c, "a seat for the second terminal", "return #paw.seats.list()", |v| {
        v.as_u64().is_some_and(|n| n > before)
    });
    let text = String::from_utf8_lossy(&shown.lock().unwrap()).into_owned();
    assert!(text.contains("joining it as a new seat"), "it says that it joins: {text}");
    assert_eq!(
        c.call("eval", json!(["return paw.api.project_get('path')"])).unwrap(),
        json!(song.join("project.toml").to_string_lossy()),
        "one project, not a second copy"
    );

    // Keys typed in the second terminal edit the one project.
    master.write_all(b":part.add\r").unwrap();
    wait_for(&mut c, "the part typed in the second terminal", "return #paw.parts()", |v| *v == json!(2));

    // A change to a file of the project, made outside paw.
    let file = song.join("parts/Bass/part.json");
    let text = std::fs::read_to_string(&file).unwrap();
    let at = text.find("\"volume\": ").unwrap() + "\"volume\": ".len();
    let end = at + text[at..].find([',', '\n']).unwrap();
    std::fs::write(dir.join("part.swp"), format!("{}-12.0{}", &text[..at], &text[end..])).unwrap();
    std::fs::rename(dir.join("part.swp"), &file).unwrap();
    wait_for(&mut c, "the change seen", "return #paw.api.project_changed_files()", |v| *v == json!(1));
    let read = "return paw.part('Bass').volume == -12";
    assert_eq!(c.call("eval", json!([read])).unwrap(), json!(false), "nothing read before coming back");

    // Coming back to the terminal asks at once: `y` answers, it does not
    // only bring the question up.
    master.write_all(b"\x1b[I").unwrap();
    wait_for(&mut c, "the question", "return paw.external.asking()", |v| *v == json!(true));
    master.write_all(b"y").unwrap();
    wait_for(&mut c, "the file read again", read, |v| *v == json!(true));
    assert_eq!(
        c.call("eval", json!(["return #paw.api.project_changed_files()"])).unwrap(),
        json!(0),
        "acted on"
    );
}

/// paw started in a terminal draws its first frame at once, not when the
/// first message or timer comes (the first timer is a second away).
#[test]
fn the_first_frame_is_drawn_before_anything_else_arrives() {
    let dir = scratch("first");
    let socket = dir.join("paw.sock");
    let (master, slave) = pty();
    let tty = || std::fs::OpenOptions::new().read(true).write(true).open(&slave).unwrap();
    let mut command = paw(&dir);
    command
        .args(["--clean", "--no-plugins", "--audio", "null", "--listen"])
        .arg(&socket)
        .stdin(Stdio::from(tty()))
        .stdout(Stdio::from(tty()))
        .stderr(Stdio::from(tty()));
    // SAFETY: only async-signal-safe calls between fork and exec.
    unsafe {
        command.pre_exec(|| {
            libc::setsid();
            libc::ioctl(0, libc::TIOCSCTTY, 0);
            Ok(())
        });
    }
    let _running = Running(vec![command.spawn().expect("starting paw")], dir);
    // What it writes is read, so that it never waits on a full pty.
    let mut reader = master.try_clone().unwrap();
    std::thread::spawn(move || {
        let mut buf = [0u8; 8192];
        while matches!(reader.read(&mut buf), Ok(n) if n > 0) {}
    });
    let until = Instant::now() + Duration::from_secs(30);
    let mut c = loop {
        if let Ok(c) = Connection::unix(&socket) {
            break c;
        }
        assert!(Instant::now() < until, "paw never listened");
        std::thread::sleep(Duration::from_millis(5));
    };
    // This call is the first message: a frame drawn because of it comes
    // after its answer.
    let full = c.call("eval", json!(["return paw.api.ui_frames().full"])).unwrap();
    assert!(full.as_u64().is_some_and(|n| n >= 1), "the first frame is drawn before the first message: {full}");
}
