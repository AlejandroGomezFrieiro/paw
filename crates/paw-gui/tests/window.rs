//! The window, driven for real: each scenario starts an X server on a display
//! of its own, a window manager and the window with a setup script, makes
//! pointer and key gestures with xdotool, and asks the kernel over the
//! window's control socket what it holds afterwards.
//!
//! These need Xvfb, openbox and xdotool (ImageMagick and tesseract too, to photograph
//! the window and find words on it). The dev shell has them; without them the tests
//! say what is missing and pass. A failed scenario leaves `failure.png` and
//! the window's output in its directory under `target/tmp/window`.

use std::collections::HashMap;
use std::fs;
use std::io::Write as _;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Condvar, Mutex, Once};
use std::time::{Duration, Instant};

/// Where things are in the window, in pixels from the corner of its content,
/// as the window lays them out (src/app.rs: `TRANSPORT_H`). What is in a
/// pane the kernel draws (the arrange view, the piano roll) is where its
/// view put it, asked of the kernel (`arrange_point`, `roll_point`).
mod place {
    /// The transport bar along the top.
    pub const TRANSPORT_H: i32 = 40;
    /// Where the main area, the panes of the kernel's windows, starts:
    /// under the transport bar and the line under it.
    pub const AREA_TOP: i32 = TRANSPORT_H + 1;
}

type Point = (i32, i32);

/// A word read off the screen: where it is in the window, and which line of
/// text it is on.
struct Word {
    text: String,
    line: (u32, u32, u32),
    x: i32,
    y: i32,
    w: i32,
    h: i32,
}

/// How much a screenshot is enlarged before it is read.
const OCR_SCALE: i32 = 3;

/// A word as it is compared: lower case letters and digits only, so that
/// "Render…" and "render" are one.
fn plain(word: &str) -> String {
    word.chars()
        .filter(|c| c.is_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

const DEMO: &str = "dofile('examples/demo-song.lua')";

// ---------------------------------------------------------------- tools

fn on_path(name: &str) -> Option<PathBuf> {
    std::env::split_paths(&std::env::var_os("PATH")?)
        .map(|dir| dir.join(name))
        .find(|path| path.is_file())
}

struct Tools {
    xvfb: PathBuf,
    openbox: PathBuf,
    xdotool: PathBuf,
    import: PathBuf,
    convert: PathBuf,
    tesseract: PathBuf,
}

fn tools() -> Result<Tools, String> {
    let find = |name: &'static str| on_path(name).ok_or(name);
    let all = (
        find("Xvfb"),
        find("openbox"),
        find("xdotool"),
        find("import"),
        find("tesseract"),
        find("convert"),
    );
    match all {
        (Ok(xvfb), Ok(openbox), Ok(xdotool), Ok(import), Ok(tesseract), Ok(convert)) => Ok(Tools {
            xvfb,
            openbox,
            xdotool,
            import,
            tesseract,
            convert,
        }),
        (a, b, c, d, e, f) => {
            let missing: Vec<&str> = [a, b, c, d, e, f]
                .into_iter()
                .filter_map(Result::err)
                .collect();
            Err(format!(
                "{} not installed (`nix develop` has them)",
                missing.join(", ")
            ))
        }
    }
}

/// The `paw` binary beside the window's, built when it is not there.
fn kernel_binary() -> PathBuf {
    let gui = PathBuf::from(env!("CARGO_BIN_EXE_paw-gui"));
    let dir = gui.parent().unwrap().to_path_buf();
    let paw = dir.join("paw");
    static BUILD: Once = Once::new();
    BUILD.call_once(|| {
        if paw.is_file() {
            return;
        }
        let cargo = std::env::var_os("CARGO").unwrap_or_else(|| "cargo".into());
        let mut build = Command::new(cargo);
        build.args(["build", "-p", "paw-tui"]);
        if dir.file_name().is_some_and(|name| name == "release") {
            build.arg("--release");
        }
        let status = build.current_dir(repo()).status();
        assert!(status.is_ok_and(|s| s.success()), "building the paw binary");
    });
    paw
}

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap()
}

// -------------------------------------------------------- a counting gate

/// How many scenes run at once: each is an X server, a window and a kernel.
static SLOTS: (Mutex<usize>, Condvar) = (Mutex::new(0), Condvar::new());
const MAX_SCENES: usize = 3;

/// The slots a scene holds.
struct Slot(usize);

impl Slot {
    fn take() -> Slot {
        let (count, free) = &SLOTS;
        let mut count = count.lock().unwrap();
        while *count >= MAX_SCENES {
            count = free.wait(count).unwrap();
        }
        *count += 1;
        Slot(1)
    }

    /// Every slot, once the scenes running have ended: for a scene that
    /// measures the window's own load, which scenes beside it disturb.
    fn take_all() -> Slot {
        let (count, free) = &SLOTS;
        let mut count = count.lock().unwrap();
        while *count > 0 {
            count = free.wait(count).unwrap();
        }
        *count = MAX_SCENES;
        Slot(MAX_SCENES)
    }
}

impl Drop for Slot {
    fn drop(&mut self) {
        *SLOTS.0.lock().unwrap() -= self.0;
        SLOTS.1.notify_all();
    }
}

// ---------------------------------------------------------------- a scene

/// One window on a private display, with everything that serves it. Dropping
/// it ends every process, whether the scenario passed or not.
struct Scene {
    name: String,
    dir: PathBuf,
    tools: Tools,
    display: String,
    xvfb: Child,
    /// The display number, held until the server is gone.
    _display: Claim,
    openbox: Child,
    gui: Child,
    /// The kernel the window is a client of, when it did not start one.
    kernel: Option<Child>,
    /// Where that kernel listens on the network.
    tcp: Option<String>,
    socket: PathBuf,
    paw: PathBuf,
    envs: Vec<(&'static str, PathBuf)>,
    /// Where the window's content starts on the screen.
    origin: Point,
    size: Point,
    _slot: Slot,
}

fn signal_group(child: &Child) {
    // Each process leads a group of its own: the window's kernel dies with it.
    unsafe { libc::kill(-(child.id() as i32), libc::SIGKILL) };
}

/// Start `program` as the leader of a group of its own.
fn spawn_group(command: &mut Command) -> Child {
    use std::os::unix::process::CommandExt;
    command
        .process_group(0)
        .spawn()
        .expect("starting a process")
}

/// Whether a server listens on the display, or one is starting on it (its
/// lock file names a process that runs). The files an X server killed
/// without notice leaves behind do not count.
fn display_in_use(number: u32) -> bool {
    let lock = fs::read_to_string(format!("/tmp/.X{number}-lock")).unwrap_or_default();
    let running = lock
        .trim()
        .parse::<u32>()
        .is_ok_and(|pid| Path::new(&format!("/proc/{pid}")).exists());
    running || UnixStream::connect(format!("/tmp/.X11-unix/X{number}")).is_ok()
}

/// openbox's own configuration with a rule that takes the frame off every
/// window (its keys, Alt-F4 among them, stay).
fn undecorated_openbox_config(openbox: &Path) -> Option<String> {
    let binary = fs::canonicalize(openbox).ok()?;
    let rc = binary.parent()?.parent()?.join("etc/xdg/openbox/rc.xml");
    let text = fs::read_to_string(rc).ok()?;
    let rule = "<applications><application class=\"*\"><decor>no</decor></application>";
    text.contains("<applications>")
        .then(|| text.replacen("<applications>", rule, 1))
}

/// A display number that one test process holds. The X server's own lock
/// file appears only after it started, so two test processes (two checkouts
/// testing at once) that probe at the same moment would both take the same
/// number: one of them then ran its windows on the other's server, and keys
/// and windows of two tests mixed. The claim is a file made with
/// `create_new`, which only one process can make; it names the process, so
/// that the claim of a process that died is let go.
struct Claim(PathBuf);

impl Claim {
    fn take(number: u32) -> Option<Claim> {
        use std::io::ErrorKind;
        let path = PathBuf::from(format!("/tmp/.paw-test-display-{number}"));
        for _ in 0..3 {
            match fs::OpenOptions::new().write(true).create_new(true).open(&path) {
                Ok(mut file) => {
                    let _ = write!(file, "{}", std::process::id());
                    return Some(Claim(path));
                }
                Err(err) if err.kind() == ErrorKind::AlreadyExists => {
                    let owner = fs::read_to_string(&path).unwrap_or_default();
                    let alive = owner
                        .trim()
                        .parse::<u32>()
                        .is_ok_and(|pid| Path::new(&format!("/proc/{pid}")).exists());
                    // A claim just made may not hold its pid yet.
                    if alive || owner.trim().is_empty() {
                        return None;
                    }
                    if fs::read_to_string(&path).unwrap_or_default() == owner {
                        let _ = fs::remove_file(&path);
                    }
                }
                Err(_) => return None,
            }
        }
        None
    }
}

impl Drop for Claim {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

/// An X server on the first display from 120 up that is free. Tests run side
/// by side, in this process and in others, so a number is claimed first.
fn start_xvfb(tools: &Tools, dir: &Path) -> (Child, String, Claim) {
    for number in 120..400 {
        let socket = format!("/tmp/.X11-unix/X{number}");
        let Some(claim) = Claim::take(number) else {
            continue;
        };
        if display_in_use(number) {
            continue;
        }
        let log = fs::File::create(dir.join("xvfb.out")).unwrap();
        let mut command = Command::new(&tools.xvfb);
        command
            .arg(format!(":{number}"))
            .args(["-screen", "0", "1500x960x24", "-nolisten", "tcp"])
            .stdout(Stdio::null())
            .stderr(log);
        let mut child = spawn_group(&mut command);
        let deadline = Instant::now() + Duration::from_secs(10);
        loop {
            // The socket is ours when the server that listens is the one
            // started here (its lock file names it), not a neighbor's.
            let lock = fs::read_to_string(format!("/tmp/.X{number}-lock")).unwrap_or_default();
            if lock.trim() == child.id().to_string() && UnixStream::connect(&socket).is_ok() {
                return (child, format!(":{number}"), claim);
            }
            if child.try_wait().unwrap().is_some() || Instant::now() > deadline {
                signal_group(&child);
                let _ = child.wait();
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
    }
    panic!("no free display from :120 up");
}

/// The control socket's path has to fit in a socket address: a short
/// directory when the scratch one is too long.
fn runtime_dir(dir: &Path, name: &str) -> PathBuf {
    let here = dir.join("run");
    if here.as_os_str().len() < 60 {
        here
    } else {
        std::env::temp_dir().join(format!("paw-window-{}-{name}", std::process::id()))
    }
}

impl Scene {
    /// Start the window with `setup` run in its kernel; None, after saying
    /// so, when the tools for it are not installed.
    fn start(name: &str, setup: &str) -> Option<Scene> {
        Scene::launch(name, setup, false, Slot::take)
    }

    /// The same, but the window is a client of a kernel started beside it,
    /// reached over TCP with a token (`--connect`).
    fn start_remote(name: &str, setup: &str) -> Option<Scene> {
        Scene::launch(name, setup, true, Slot::take)
    }

    /// The same, with no other scene running beside it while it lasts.
    fn start_alone(name: &str, setup: &str) -> Option<Scene> {
        Scene::launch(name, setup, false, Slot::take_all)
    }

    fn launch(name: &str, setup: &str, remote: bool, take: fn() -> Slot) -> Option<Scene> {
        let tools = match tools() {
            Ok(tools) => tools,
            Err(missing) => {
                eprintln!("window test {name} skipped: {missing}");
                return None;
            }
        };
        let slot = take();
        let paw = kernel_binary();
        let dir = Path::new(env!("CARGO_TARGET_TMPDIR"))
            .join("window")
            .join(name);
        let _ = fs::remove_dir_all(&dir);
        let run = runtime_dir(&dir, name);
        let _ = fs::remove_dir_all(&run);
        let mut envs = vec![
            ("HOME", dir.join("home")),
            ("XDG_CACHE_HOME", dir.join("xdg/cache")),
            ("XDG_STATE_HOME", dir.join("xdg/state")),
            ("XDG_DATA_HOME", dir.join("xdg/data")),
            ("XDG_CONFIG_HOME", dir.join("xdg/config")),
            ("XDG_RUNTIME_DIR", run),
            // No test can reach the desktop's portals or session bus.
            (
                "DBUS_SESSION_BUS_ADDRESS",
                "unix:path=/nonexistent/bus".into(),
            ),
        ];
        for (key, path) in &envs {
            if *key != "DBUS_SESSION_BUS_ADDRESS" {
                fs::create_dir_all(path).unwrap();
            }
        }
        let (xvfb, display, display_claim) = start_xvfb(&tools, &dir);
        envs.push(("PAW_BIN", paw.clone()));
        // A scene named so asks for the processor (GLX, its parts copied).
        if name.ends_with("-sw") {
            envs.push(("PAW_GUI_RENDERER", "software".into()));
        }

        // The server listens before it answers: on a busy machine it compiles
        // its keymap for seconds, and a client that connects then (openbox
        // does, once) is refused and ends. The window manager starts when
        // the server answers, and again if it ended all the same; the window
        // opens when it is the window manager. A window that opens before has
        // no focus and no Alt-F4 (see `take_focus`).
        let xdotool_ok = |args: &[&str]| {
            Command::new(&tools.xdotool)
                .args(args)
                .env("DISPLAY", &display)
                .output()
                .is_ok_and(|o| o.status.success())
        };
        let deadline = Instant::now() + Duration::from_secs(60);
        while !xdotool_ok(&["getdisplaygeometry"]) {
            assert!(Instant::now() < deadline, "the X server never answered");
            std::thread::sleep(Duration::from_millis(50));
        }
        let rc = undecorated_openbox_config(&tools.openbox).map(|rc| {
            let file = dir.join("openbox-rc.xml");
            fs::write(&file, rc).unwrap();
            file
        });
        let mut openbox = None;
        for _ in 0..5 {
            let wm_log = fs::File::create(dir.join("openbox.out")).unwrap();
            let mut command = Command::new(&tools.openbox);
            command
                .env("DISPLAY", &display)
                .stdout(wm_log.try_clone().unwrap())
                .stderr(wm_log);
            // No frames: the window's content is where the window is (the
            // pointer's places count on it).
            if let Some(file) = &rc {
                command.arg("--config-file").arg(file);
            }
            let mut child = spawn_group(&mut command);
            let deadline = Instant::now() + Duration::from_secs(20);
            let mut ready = false;
            while child.try_wait().unwrap().is_none() && Instant::now() < deadline {
                if xdotool_ok(&["get_desktop"]) {
                    ready = true;
                    break;
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            if ready {
                openbox = Some(child);
                break;
            }
            signal_group(&child);
            let _ = child.wait();
        }
        let openbox = openbox.unwrap_or_else(|| {
            panic!(
                "openbox never took the screen: {}",
                fs::read_to_string(dir.join("openbox.out")).unwrap_or_default()
            )
        });

        let out = fs::File::create(dir.join("window.out")).unwrap();
        let run = envs
            .iter()
            .find(|(k, _)| *k == "XDG_RUNTIME_DIR")
            .unwrap()
            .1
            .clone();
        let mut kernel = None;
        let mut window_args: Vec<String> =
            ["--clean", "--no-plugins", "--audio", "null", "-e", setup]
                .map(String::from)
                .to_vec();
        let mut socket = None;
        let mut tcp = None;
        if remote {
            let port = {
                let probe = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
                probe.local_addr().unwrap().port()
            };
            let token = dir.join("token");
            fs::write(&token, "window-test-token\n").unwrap();
            let unix = run.join("kernel.sock");
            let mut command = Command::new(&paw);
            command
                .args([
                    "--headless",
                    "--clean",
                    "--no-plugins",
                    "--audio",
                    "null",
                    "--listen",
                ])
                .arg(&unix)
                .arg("--listen-tcp")
                .arg(format!("127.0.0.1:{port}"))
                .arg("--token-file")
                .arg(&token)
                .args(["-e", setup])
                .current_dir(repo())
                .stdin(Stdio::null())
                .stdout(out.try_clone().unwrap())
                .stderr(out.try_clone().unwrap());
            for (key, value) in &envs {
                command.env(key, value);
            }
            kernel = Some(spawn_group(&mut command));
            let deadline = Instant::now() + Duration::from_secs(60);
            while UnixStream::connect(&unix).is_err() {
                assert!(Instant::now() < deadline, "the kernel never listened");
                std::thread::sleep(Duration::from_millis(100));
            }
            window_args = vec![
                "--connect".into(),
                format!("127.0.0.1:{port}"),
                "--token-file".into(),
                token.to_string_lossy().into_owned(),
            ];
            socket = Some(unix);
            tcp = Some(format!("127.0.0.1:{port}"));
        }
        let mut command = Command::new(env!("CARGO_BIN_EXE_paw-gui"));
        command
            .args(&window_args)
            .current_dir(repo())
            .env("DISPLAY", &display)
            .env("RUST_BACKTRACE", "1")
            .env_remove("WAYLAND_DISPLAY")
            .env_remove("XAUTHORITY")
            .stdin(Stdio::null())
            .stdout(out.try_clone().unwrap())
            .stderr(out);
        for (key, value) in &envs {
            command.env(key, value);
        }
        let gui = spawn_group(&mut command);
        let socket = socket.unwrap_or_else(|| run.join(format!("paw-gui-{}.sock", gui.id())));

        let mut scene = Scene {
            name: name.to_string(),
            dir,
            tools,
            display,
            xvfb,
            _display: display_claim,
            openbox,
            gui,
            kernel,
            tcp,
            socket,
            paw,
            envs,
            origin: (0, 0),
            size: (0, 0),
            _slot: slot,
        };
        scene.wait_until_shown();
        Some(scene)
    }

    fn wait_until_shown(&mut self) {
        let deadline = Instant::now() + Duration::from_secs(90);
        let id = loop {
            assert!(
                self.alive(),
                "the window ended while starting\n{}",
                self.output()
            );
            assert!(
                Instant::now() < deadline,
                "the window never showed\n{}",
                self.output()
            );
            if let Some(Ok(answer)) = self.try_ctl("return 1") {
                if answer.trim() == "1" {
                    let found = self.xdotool(&["search", "--onlyvisible", "--name", "^paw"]);
                    if let Some(id) = found.lines().next().filter(|l| !l.is_empty()) {
                        break id.to_string();
                    }
                }
            }
            std::thread::sleep(Duration::from_millis(100));
        };
        // At the corner of the screen, so that nothing is partly off it.
        self.xdotool(&["windowmove", &id, "0", "0"]);
        self.take_focus(&id);
        std::thread::sleep(Duration::from_millis(500));
        let geometry = self.xdotool(&["getwindowgeometry", "--shell", &id]);
        let value = |key: &str| -> i32 {
            geometry
                .lines()
                .find_map(|line| line.strip_prefix(key)?.strip_prefix('='))
                .and_then(|v| v.trim().parse().ok())
                .unwrap_or_else(|| panic!("no {key} in {geometry}"))
        };
        self.origin = (value("X"), value("Y"));
        self.size = (value("WIDTH"), value("HEIGHT"));
        // The first state has to arrive and be drawn.
        std::thread::sleep(Duration::from_millis(700));
    }

    /// Wait until the window has the input focus of the X server, and give it
    /// when nobody does. openbox gives the focus to a window that it sees
    /// map; on a busy machine it may start after the window has mapped, and
    /// then nothing gives the focus (the server's focus stays on no window,
    /// `xdotool getwindowfocus` fails): every key sent after that goes to no
    /// window, and the first click is the first thing that gives the focus.
    fn take_focus(&self, id: &str) {
        let deadline = Instant::now() + Duration::from_secs(20);
        loop {
            if self.xdotool(&["getwindowfocus"]).trim() == id {
                return;
            }
            assert!(
                Instant::now() < deadline,
                "{}: the window never got the input focus",
                self.name
            );
            self.xdotool(&["windowfocus", id]);
            std::thread::sleep(Duration::from_millis(100));
        }
    }

    fn env_path(&self, key: &str) -> &Path {
        &self.envs.iter().find(|(k, _)| *k == key).unwrap().1
    }

    // ------------------------------------------------------ the kernel

    fn try_ctl(&self, lua: &str) -> Option<Result<String, String>> {
        let output = Command::new(&self.paw)
            .arg("ctl")
            .arg("--socket")
            .arg(&self.socket)
            .arg("eval")
            .arg(lua)
            .envs(self.envs.iter().map(|(k, v)| (*k, v)))
            .output()
            .ok()?;
        let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if output.status.success() {
            Some(Ok(text))
        } else {
            let err = String::from_utf8_lossy(&output.stderr).trim().to_string();
            Some(Err(format!("{text} {err}")))
        }
    }

    /// Run Lua in the kernel (`return ...` to get something back) and say
    /// what it printed.
    fn ctl(&self, lua: &str) -> String {
        match self.try_ctl(lua) {
            Some(Ok(text)) => text,
            Some(Err(err)) => panic!("the kernel answered `{lua}` with an error: {err}"),
            None => panic!("could not run paw ctl"),
        }
    }

    fn number(&self, lua: &str) -> f64 {
        let text = self.ctl(lua);
        text.parse()
            .unwrap_or_else(|_| panic!("`{lua}` gave {text:?}, not a number"))
    }

    /// Wait up to `seconds` for a Lua expression to hold; what the kernel
    /// last said when it did not.
    fn wait_for(&self, condition: &str, seconds: u64) -> Result<(), String> {
        let lua = format!("return ({condition}) and true or false");
        let deadline = Instant::now() + Duration::from_secs(seconds);
        let mut last = String::new();
        while Instant::now() < deadline {
            last = match self.try_ctl(&lua) {
                Some(Ok(text)) if text == "true" => return Ok(()),
                Some(Ok(text)) => text,
                Some(Err(err)) => err,
                None => "no answer".into(),
            };
            std::thread::sleep(Duration::from_millis(100));
        }
        Err(last)
    }

    /// Wait for a Lua expression to hold, as the kernel will take a moment
    /// over what a gesture meant. The limit is for a loaded machine, which
    /// is slow, not wrong: the time the slowest needs, not the usual time.
    fn expect(&self, what: &str, condition: &str) {
        let Err(last) = self.wait_for(condition, 30) else {
            return;
        };
        let now = self
            .try_ctl(&format!("return {condition}"))
            .map(|r| format!("{r:?}"))
            .unwrap_or_default();
        panic!(
            "{}: expected {what}: `{condition}` (last answer {last}, value {now})",
            self.name
        );
    }

    // ------------------------------------------------------ the window

    fn alive(&mut self) -> bool {
        self.gui.try_wait().unwrap().is_none()
    }

    fn output(&self) -> String {
        fs::read_to_string(self.dir.join("window.out")).unwrap_or_default()
    }

    fn assert_alive(&mut self, what: &str) {
        assert!(self.alive(), "the window ended {what}\n{}", self.output());
        let out = self.output();
        assert!(
            !out.contains("panicked"),
            "the window panicked {what}\n{out}"
        );
    }

    /// Wait for the window to end (a minute at most: it waits for the
    /// kernel to end, which a loaded machine makes slow).
    fn wait_gone(&mut self, what: &str) {
        let deadline = Instant::now() + Duration::from_secs(60);
        while Instant::now() < deadline {
            if !self.alive() {
                return;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        panic!("{}: the window should have ended {what}", self.name);
    }

    /// The window's share of a processor over `seconds`, in percent of one.
    fn cpu_percent(&self, seconds: f64) -> f64 {
        let ticks = || -> f64 {
            let stat = fs::read_to_string(format!("/proc/{}/stat", self.gui.id())).unwrap();
            // Fields after the name in parentheses: user time is the 12th.
            let rest: Vec<&str> = stat[stat.rfind(')').unwrap() + 2..].split(' ').collect();
            rest[11].parse::<f64>().unwrap() + rest[12].parse::<f64>().unwrap()
        };
        let before = ticks();
        std::thread::sleep(Duration::from_secs_f64(seconds));
        let per_second = unsafe { libc::sysconf(libc::_SC_CLK_TCK) } as f64;
        (ticks() - before) / per_second / seconds * 100.0
    }

    /// The share of a processor of the window and its kernel together (every
    /// process of the window's group), over `seconds`, in percent of one.
    fn group_cpu_percent(&self, seconds: f64) -> f64 {
        let group = self.gui.id().to_string();
        let ticks = || -> f64 {
            let mut sum = 0.0;
            for entry in fs::read_dir("/proc").unwrap().flatten() {
                let Ok(stat) = fs::read_to_string(entry.path().join("stat")) else { continue };
                let Some(close) = stat.rfind(')') else { continue };
                let rest: Vec<&str> = stat[close + 2..].split(' ').collect();
                // Fields after the name: the group is the 3rd, user and system time the 12th and 13th.
                if rest.len() > 12 && rest[2] == group {
                    sum += rest[11].parse::<f64>().unwrap_or(0.0) + rest[12].parse::<f64>().unwrap_or(0.0);
                }
            }
            sum
        };
        let before = ticks();
        std::thread::sleep(Duration::from_secs_f64(seconds));
        let per_second = unsafe { libc::sysconf(libc::_SC_CLK_TCK) } as f64;
        (ticks() - before) / per_second / seconds * 100.0
    }

    /// The window's share of a processor once it has settled, in percent of
    /// one: measured five seconds at a time until a measure is under
    /// `limit`, six times at most; every measure taken, the last last. On a
    /// busy machine (the other tests, other builds) a window that has just
    /// started can still be busy after a few seconds, and what it does costs
    /// more; a window that draws while nothing changes is over the limit in
    /// every measure.
    fn settled_cpu_percent(&self, limit: f64) -> Vec<f64> {
        let mut seen = Vec::new();
        while seen.len() < 6 && seen.last().is_none_or(|p| *p >= limit) {
            seen.push(self.cpu_percent(5.0));
        }
        seen
    }

    // ----------------------------------------------------- the pointer

    fn xdotool(&self, args: &[&str]) -> String {
        let output = Command::new(&self.tools.xdotool)
            .args(args)
            .env("DISPLAY", &self.display)
            .output()
            .expect("running xdotool");
        String::from_utf8_lossy(&output.stdout).to_string()
    }

    fn screen(&self, at: Point) -> (String, String) {
        (
            (self.origin.0 + at.0).to_string(),
            (self.origin.1 + at.1).to_string(),
        )
    }

    fn pause(&self, seconds: f64) {
        std::thread::sleep(Duration::from_secs_f64(seconds));
    }

    fn mouse_to(&self, at: Point) {
        let (x, y) = self.screen(at);
        self.xdotool(&["mousemove", &x, &y]);
        self.pause(0.15);
    }

    fn click(&self, at: Point) {
        self.mouse_to(at);
        self.xdotool(&["click", "1"]);
        self.pause(0.3);
    }

    fn double_click(&self, at: Point) {
        self.mouse_to(at);
        self.xdotool(&["click", "--repeat", "2", "--delay", "50", "1"]);
        self.pause(0.4);
    }

    /// Press at `from`, move to `to` in steps, let go.
    fn drag(&self, from: Point, to: Point) {
        self.mouse_to(from);
        let mut args: Vec<String> = vec![
            "mousedown".into(),
            "1".into(),
            "sleep".into(),
            "0.15".into(),
        ];
        let steps = 14;
        for step in 1..=steps {
            let at = (
                from.0 + (to.0 - from.0) * step / steps,
                from.1 + (to.1 - from.1) * step / steps,
            );
            let (x, y) = self.screen(at);
            args.extend(["mousemove".into(), x, y, "sleep".into(), "0.03".into()]);
        }
        args.extend(["sleep".into(), "0.15".into(), "mouseup".into(), "1".into()]);
        let args: Vec<&str> = args.iter().map(String::as_str).collect();
        self.xdotool(&args);
        self.pause(0.4);
    }

    fn key(&self, keys: &str) {
        self.xdotool(&["key", keys]);
        self.pause(0.3);
    }

    fn type_text(&self, text: &str) {
        self.xdotool(&["type", "--delay", "20", text]);
        self.pause(0.3);
    }

    /// The wheel `times` steps up (zooming in, with Ctrl) over `at`.
    fn wheel_with_ctrl(&self, at: Point, up: bool, times: u32) {
        self.mouse_to(at);
        let button = if up { "4" } else { "5" };
        let times = times.to_string();
        self.xdotool(&[
            "keydown", "ctrl", "click", "--repeat", &times, "--delay", "80", button, "keyup",
            "ctrl",
        ]);
        self.pause(0.4);
    }

    /// A number about the pane that shows `view` (`p.x`, `p.w`...), from
    /// where the kernel lays the main area out (`paw.panes.state`).
    fn pane(&self, view: &str, part: &str) -> i32 {
        self.number(&format!(
            "for _, p in ipairs(paw.panes.state().panes) do if p.view == '{view}' then return {part} end end"
        )) as i32
    }

    /// The middle of the pane that shows `view`, in the window.
    fn pane_middle(&self, view: &str) -> Point {
        (self.pane(view, "p.x + p.w / 2"), place::AREA_TOP + self.pane(view, "p.y + p.h / 2"))
    }

    /// The window's close button as a window manager sends it: asked of
    /// openbox by the window's id (`_NET_CLOSE_WINDOW`), which sends the
    /// window WM_DELETE_WINDOW. Not Alt-F4, which goes through openbox's
    /// grab of the key: on a loaded machine the F4 of a first key of the
    /// session went past it to the window as a plain key, and nothing
    /// closed (most likely while openbox grabbed its keys again after the
    /// server changed to xdotool's keyboard).
    fn close_window(&self) {
        let found = self.xdotool(&["search", "--onlyvisible", "--name", "^paw"]);
        let id = found.lines().next().expect("the window");
        self.xdotool(&["windowquit", id]);
        self.pause(0.3);
    }

    /// The file menu, from the project's name at the left of the transport bar.
    fn open_file_menu(&self) {
        self.click((40, place::TRANSPORT_H / 2));
    }

    /// File, Render…: the dialog, up when its Tail field shows.
    fn open_render_dialog(&self) {
        self.open_file_menu();
        self.click_text("Render");
        self.find_text("Tail", 0);
    }

    /// Type `path` in the open render dialog's file field and press Render.
    fn render_to(&self, path: &Path) {
        self.click_right_of("File", 150);
        self.key("ctrl+a");
        self.type_text(path.to_str().unwrap());
        self.click_last_text("Render");
    }

    // ----------------------------------------------- finding text on screen
    //
    // Menu entries and dialog buttons move whenever one is added, so they
    // are found by what they say: the window is photographed, enlarged,
    // inverted (light text on dark reads worse) and read by tesseract.

    /// The words on the window now, with where they are in the window, read
    /// three ways: inverted, with a global threshold and with a local one.
    /// Each misses text the others get (a dialog on a dimmed backdrop; a
    /// light button), and what is found by any counts.
    /// The first match from the top stops at the first reading that finds
    /// it; the last waits for all four, as a reading may miss a later one.
    fn screens(&self, text: &str, nth: i32) -> Vec<Vec<Word>> {
        let mut screens = Vec::new();
        for prepare in [
            &["-negate"][..],
            &["-threshold", "60%"],
            &["-lat", "60x60+3%"],
            &["-lat", "30x30-3%"],
        ] {
            screens.push(self.words(prepare));
            if nth >= 0 && Scene::locate(&screens, text, nth).is_some() {
                break;
            }
        }
        screens
    }

    fn words(&self, prepare: &[&str]) -> Vec<Word> {
        let (import, tesseract) = (&self.tools.import, &self.tools.tesseract);
        let crop = format!(
            "{}x{}+{}+{}",
            self.size.0, self.size.1, self.origin.0, self.origin.1
        );
        let mut shot = Command::new(import)
            .args(["-window", "root", "-crop", &crop, "+repage", "png:-"])
            .env("DISPLAY", &self.display)
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .expect("running import");
        let mut larger = Command::new(&self.tools.convert)
            .arg("png:-")
            .args(["-resize", &format!("{}%", OCR_SCALE * 100)])
            .args(prepare)
            .args(["-colorspace", "Gray", "png:-"])
            .stdin(Stdio::from(shot.stdout.take().unwrap()))
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .expect("running convert");
        let read = Command::new(tesseract)
            .args(["stdin", "stdout", "--psm", "11", "tsv"])
            .stdin(Stdio::from(larger.stdout.take().unwrap()))
            .stderr(Stdio::null())
            .output()
            .expect("running tesseract");
        let _ = shot.wait();
        let _ = larger.wait();
        let scale = OCR_SCALE as f64;
        String::from_utf8_lossy(&read.stdout)
            .lines()
            .filter_map(|line| {
                let f: Vec<&str> = line.split('\t').collect();
                if f.len() < 12 || f[0] != "5" {
                    return None;
                }
                let n = |i: usize| f[i].parse::<f64>().ok();
                Some(Word {
                    text: f[11].to_string(),
                    line: (n(2)? as u32, n(3)? as u32, n(4)? as u32),
                    x: (n(6)? / scale) as i32,
                    y: (n(7)? / scale) as i32,
                    w: (n(8)? / scale) as i32,
                    h: (n(9)? / scale) as i32,
                })
            })
            .collect()
    }

    /// Where `text` is among `words`, as the middle of its words in the
    /// window: the `nth` match from the top of the window (the last with
    /// `nth` negative, counting from -1).
    fn locate(screens: &[Vec<Word>], text: &str, nth: i32) -> Option<Point> {
        let wanted: Vec<String> = text
            .split_whitespace()
            .map(plain)
            .filter(|w| !w.is_empty())
            .collect();
        let mut found: Vec<Point> = Vec::new();
        for words in screens {
            Scene::locate_in(words, &wanted, &mut found);
        }
        // The same words read in more than one way are one.
        let mut unique: Vec<Point> = Vec::new();
        for at in found {
            if !unique
                .iter()
                .any(|u| (u.0 - at.0).abs() < 12 && (u.1 - at.1).abs() < 12)
            {
                unique.push(at);
            }
        }
        let mut found = unique;
        found.sort_by_key(|&(x, y)| (y / 12, x));
        let at = if nth < 0 {
            found.len() as i32 + nth
        } else {
            nth
        };
        usize::try_from(at)
            .ok()
            .and_then(|at| found.get(at).copied())
    }

    fn locate_in(words: &[Word], wanted: &[String], found: &mut Vec<Point>) {
        let words: Vec<(&Word, String)> = words
            .iter()
            .map(|w| (w, plain(&w.text)))
            .filter(|(_, p)| !p.is_empty())
            .collect();
        for start in 0..words.len().saturating_sub(wanted.len() - 1) {
            let run = &words[start..start + wanted.len()];
            let same_line = run.iter().all(|(w, _)| w.line == run[0].0.line);
            if same_line && run.iter().zip(wanted).all(|((_, p), w)| p == w) {
                let left = run.iter().map(|(w, _)| w.x).min().unwrap();
                let right = run.iter().map(|(w, _)| w.x + w.w).max().unwrap();
                let top = run.iter().map(|(w, _)| w.y).min().unwrap();
                let bottom = run.iter().map(|(w, _)| w.y + w.h).max().unwrap();
                found.push(((left + right) / 2, (top + bottom) / 2));
            }
        }
    }

    /// Wait for `text` to show and say where (30 seconds at most, the
    /// limit of `expect`: a loaded machine draws late).
    fn find_text(&self, text: &str, nth: i32) -> Point {
        let deadline = Instant::now() + Duration::from_secs(30);
        loop {
            let screens = self.screens(text, nth);
            if let Some(at) = Scene::locate(&screens, text, nth) {
                return at;
            }
            if Instant::now() > deadline {
                let seen: Vec<&str> = screens.iter().flatten().map(|w| w.text.as_str()).collect();
                panic!(
                    "{}: no `{text}` on the screen; the words seen: {}",
                    self.name,
                    seen.join(" ")
                );
            }
            self.pause(0.3);
        }
    }

    /// Whether `text` shows within `seconds`.
    fn shows(&self, text: &str, seconds: u64) -> bool {
        let deadline = Instant::now() + Duration::from_secs(seconds);
        loop {
            if Scene::locate(&self.screens(text, 0), text, 0).is_some() {
                return true;
            }
            if Instant::now() > deadline {
                return false;
            }
            self.pause(0.3);
        }
    }

    /// Whether `text` has left the screen within `seconds`.
    fn hides(&self, text: &str, seconds: u64) -> bool {
        let deadline = Instant::now() + Duration::from_secs(seconds);
        loop {
            if Scene::locate(&self.screens(text, 0), text, 0).is_none() {
                return true;
            }
            if Instant::now() > deadline {
                return false;
            }
            self.pause(0.3);
        }
    }

    /// Click the first `text` from the top of the window.
    fn click_text(&self, text: &str) {
        self.click(self.find_text(text, 0));
    }

    /// Click the last `text` (a dialog's button, under its title).
    fn click_last_text(&self, text: &str) {
        self.click(self.find_text(text, -1));
    }

    /// Click `dx` pixels right of `text`: a field beside its label.
    fn click_right_of(&self, text: &str, dx: i32) {
        let (x, y) = self.find_text(text, 0);
        self.click((x + dx, y));
    }

    fn shot(&self, file: &str) {
        let _ = Command::new(&self.tools.import)
            .args(["-window", "root"])
            .arg(self.dir.join(file))
            .env("DISPLAY", &self.display)
            .output();
    }

    /// The colours of the pixels in the box `size` points wide and high
    /// from `at`, as red, green and blue.
    fn pixels(&self, at: Point, size: (i32, i32)) -> Vec<[u8; 3]> {
        let (x, y) = self.screen(at);
        let output = Command::new(&self.tools.import)
            .args(["-window", "root", "-crop", &format!("{}x{}+{x}+{y}", size.0, size.1), "-depth", "8", "rgb:-"])
            .env("DISPLAY", &self.display)
            .output()
            .expect("running import");
        output.stdout.chunks_exact(3).map(|p| [p[0], p[1], p[2]]).collect()
    }
}

impl Drop for Scene {
    fn drop(&mut self) {
        if std::thread::panicking() {
            self.shot("failure.png");
            let out = self.output();
            let tail: Vec<&str> = out.lines().rev().take(20).collect();
            let tail: Vec<&str> = tail.into_iter().rev().collect();
            eprintln!(
                "window test {} failed; screenshot and output are in {}\n{}",
                self.name,
                self.dir.display(),
                tail.join("\n")
            );
        }
        for child in [
            Some(&mut self.gui),
            Some(&mut self.openbox),
            self.kernel.as_mut(),
        ]
        .into_iter()
        .flatten()
        {
            signal_group(child);
            let _ = child.wait();
        }
        // The X server is asked to go, so that it removes its socket.
        unsafe { libc::kill(self.xvfb.id() as i32, libc::SIGTERM) };
        let deadline = Instant::now() + Duration::from_secs(3);
        while self.xvfb.try_wait().unwrap().is_none() && Instant::now() < deadline {
            std::thread::sleep(Duration::from_millis(20));
        }
        signal_group(&self.xvfb);
        let _ = self.xvfb.wait();
        let _ = std::io::stderr().flush();
        // The socket is in a directory that may not be ours to keep.
        let run = self.env_path("XDG_RUNTIME_DIR").to_path_buf();
        if run.starts_with(std::env::temp_dir()) {
            let _ = fs::remove_dir_all(run);
        }
    }
}

/// Start a scene or end the test, saying why, when the tools are missing.
macro_rules! scene {
    ($name:expr, $setup:expr) => {
        match Scene::start($name, $setup) {
            Some(scene) => scene,
            None => return,
        }
    };
    ($name:expr, $setup:expr, remote) => {
        match Scene::start_remote($name, $setup) {
            Some(scene) => scene,
            None => return,
        }
    };
    ($name:expr, $setup:expr, alone) => {
        match Scene::start_alone($name, $setup) {
            Some(scene) => scene,
            None => return,
        }
    };
}

// ---------------------------------------------------------------- scenarios

#[test]
fn demo_song_shows_and_answers_the_pointer() {
    let mut w = scene!("demo", DEMO);

    // It starts with the demo song and shows it.
    w.pause(3.0);
    w.assert_alive("after showing the demo song");
    assert_eq!(w.number("return #paw.api.track_list()"), 5.0);
    w.shot("demo.png");
    // Xvfb has no graphics card: the window says that it draws on the
    // processor, once, and `:checkhealth window` tells why.
    w.expect(
        "the renderer told",
        "paw.frontend.window_renderer and paw.frontend.window_renderer.software",
    );
    w.expect(
        "a warning in :checkhealth",
        "paw.health.run('window').items[1].level == 'warn'",
    );

    // A click on a header selects the track.
    let keys = w.number("return paw.api.track_list()[3]") as i32;
    assert_eq!(
        w.ctl(&format!("return paw.api.track_get({keys}).name")),
        "Keys"
    );
    w.click(arrange_point(&w, "6", "row('track', 3) + 0.5"));
    w.expect(
        "the cursor on Keys",
        &format!("paw.cursor.track_id() == {keys}"),
    );
    let first = w.number("return paw.api.track_list()[1]") as i32;
    w.click(arrange_point(&w, "6", "row('track', 1) + 0.5"));
    w.expect(
        "the cursor on Drums",
        &format!("paw.cursor.track_id() == {first}"),
    );

    // The M button mutes the track, and again lets it sound.
    let bass = w.number("return paw.api.track_list()[2]") as i32;
    let mute = arrange_point(&w, "v.flags.mute + 0.5", "row('track', 2) + 0.5");
    w.click(mute);
    w.expect("Bass muted", &format!("paw.api.track_get({bass}).mute"));
    w.click(mute);
    w.expect(
        "Bass sounding",
        &format!("not paw.api.track_get({bass}).mute"),
    );

    // The file menu opens from the project's name; Render… opens the dialog,
    // and a typed path and the Render button write the file.
    let target = w.dir.join("render/song.wav");
    fs::create_dir_all(target.parent().unwrap()).unwrap();
    w.open_render_dialog();
    w.shot("render-dialog.png");
    w.render_to(&target);
    wait_for_file(&target, 1000);
    w.assert_alive("after rendering");
}

/// Four seconds of a sine wave, louder to its end, as a 16-bit mono WAV
/// file.
fn write_tone(path: &Path) {
    let rate = 48_000u32;
    let samples: Vec<i16> = (0..rate * 4)
        .map(|i| {
            let t = i as f32 / rate as f32;
            (t / 4.0 * 0.9 * (t * 220.0 * std::f32::consts::TAU).sin() * i16::MAX as f32) as i16
        })
        .collect();
    let data = (samples.len() * 2) as u32;
    let mut out = Vec::with_capacity(44 + data as usize);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes());
    out.extend_from_slice(&rate.to_le_bytes());
    out.extend_from_slice(&(rate * 2).to_le_bytes());
    out.extend_from_slice(&2u16.to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data.to_le_bytes());
    for s in samples {
        out.extend_from_slice(&s.to_le_bytes());
    }
    fs::write(path, out).unwrap();
}

/// How many pixels of the body of the clip of track `track` (beats `from`
/// to `to`, under its name) are not its plain face: its notes or its wave.
fn drawn_in_body(w: &Scene, track: usize, from: f32, to: f32) -> usize {
    let at = arrange_point(w, &format!("beat({from})"), &format!("row('track', {track}) + 1.4"));
    let end = arrange_point(w, &format!("beat({to})"), &format!("row('track', {track}) + 2.6"));
    let pixels = w.pixels(at, (end.0 - at.0, end.1 - at.1));
    let mut counts: HashMap<[u8; 3], usize> = HashMap::new();
    for p in &pixels {
        *counts.entry(*p).or_default() += 1;
    }
    let face = counts.into_iter().max_by_key(|(_, n)| *n).map(|(p, _)| p).unwrap();
    let sum = |p: &[u8; 3]| p.iter().map(|&c| c as i32).sum::<i32>();
    pixels.iter().filter(|p| (sum(p) - sum(&face)).abs() > 90).count()
}

#[test]
fn a_clip_shows_its_name_and_its_notes_or_its_waveform() {
    let media = Path::new(env!("CARGO_TARGET_TMPDIR")).join("clip-contents-media");
    fs::create_dir_all(&media).unwrap();
    let tone = media.join("Walrus.wav");
    write_tone(&tone);
    let setup = format!(
        "{DEMO} local t = paw.add_track({{ name = 'Audio' }}) paw.import_audio('{}', {{ track = t.id, start = 0 }})",
        tone.display()
    );
    let mut w = scene!("clip-contents", &setup);
    w.expect("the audio clip", "#paw.api.clip_list(paw.api.track_list()[6]) == 1");
    // The pointer over the audio lane, away from its clip: the lane is
    // painted again for it, and the clip over it too.
    w.mouse_to(arrange_point(&w, "beat(20)", "row('track', 6) + 2"));
    // The pictures inside the clips come after the frame that asks for them.
    w.pause(2.0);
    w.shot("clip-contents.png");
    // The clips are sent with an empty list of warp markers: the window
    // reads the rest of their props all the same.
    assert!(drawn_in_body(&w, 1, 0.5, 3.5) > 20, "the drums' notes in their clip");
    assert!(drawn_in_body(&w, 6, 0.5, 5.5) > 20, "the waveform in the audio clip");
    assert!(w.shows("Walrus", 5), "the audio clip's name on it");
    w.assert_alive("after showing the clips");
}

#[test]
fn a_block_of_a_subproject_shows_its_name_and_the_notes_it_plays() {
    let setup = "local row = paw.add_track({ name = 'Return' }) \
        local n = paw.api.nest_add({ name = 'Ballad', length = 16 }) \
        local p = paw.api.track_add({ name = 'Piano', nest = n }) \
        paw.api.clip_add(p, { start = 0, length = 8, notes = { { pitch = 60, start = 0, length = 2 }, { pitch = 72, start = 2, length = 2 } } }) \
        paw.api.clip_add(row.id, { nest = n, start = 0 }) \
        paw.cursor.set_track(row.id) paw.api.undo_checkpoint()";
    let mut w = scene!("nest-block", setup);
    w.expect("the block", "#paw.api.clip_list(paw.api.track_list()[1]) == 1");
    // The picture inside the block comes after the frame that asks for it.
    w.pause(2.0);
    assert!(drawn_in_body(&w, 1, 0.5, 3.5) > 20, "the notes of the subproject in its block");
    assert!(w.shows("Ballad", 5), "the block's name: the row is named Return");
    w.assert_alive("after showing the block");
}

/// The window's pixels once the song has played a while and stopped:
/// drawn again only where they changed (`paw.opt.window_cache`), or the
/// next frame drawn whole.
fn look(w: &Scene, partial: bool) -> Vec<[u8; 3]> {
    if partial {
        w.ctl("paw.opt.window_cache = true paw.api.transport_play()");
        w.pause(2.0);
        w.ctl("paw.api.transport_stop()");
        // The meters fall back to nothing, and their peaks go. A peak is
        // held for two seconds by the kernel's clock, and drops when the
        // kernel next samples it: a loaded machine does that late, and a
        // fixed wait shows the held peak in one drawing and not in the
        // other. A held peak above 1e-5 is a line at the left of a meter
        // well, even where it is under the scale. Wait for the peaks, not
        // for the time.
        w.expect(
            "every meter and held peak to have fallen",
            "(function() for _, id in ipairs(paw.api.track_list()) do \
               local l, r, hold = paw.draw.track_peak(id) \
               if math.max(l, r) > 0.001 or hold > 1e-5 then return false end \
             end return true end)()",
        );
        w.pause(1.0);
    } else {
        // A change of the option draws a frame, whole.
        w.ctl("paw.opt.window_cache = false");
        w.pause(1.0);
    }
    still(w)
}

/// The window's pixels once they stay the same for a second: a loaded
/// machine draws the last frames late (a minute at most).
fn still(w: &Scene) -> Vec<[u8; 3]> {
    let deadline = Instant::now() + Duration::from_secs(60);
    let mut before = w.pixels((0, 0), (1400, 860));
    loop {
        w.pause(1.0);
        let now = w.pixels((0, 0), (1400, 860));
        if now == before || Instant::now() > deadline {
            return now;
        }
        before = now;
    }
}

/// How many pixels differ, and how many of them by more than 2 in a
/// colour.
fn differ(a: &[[u8; 3]], b: &[[u8; 3]]) -> (usize, usize) {
    assert_eq!(a.len(), b.len());
    let (mut count, mut big) = (0, 0);
    for (p, q) in a.iter().zip(b) {
        let d = (0..3).map(|i| p[i].abs_diff(q[i])).max().unwrap();
        count += (d > 0) as usize;
        big += (d > 2) as usize;
    }
    (count, big)
}

// A window drawn again only where it changed, frame after frame while the
// song plays (the playhead, the meters, the time), shows what a window
// drawn whole shows: the arrange view with the pointer over a button, the
// mixer and the devices, the piano roll, the arrange view zoomed. Each
// square drawn again is drawn from every shape that reaches into it, so
// the pixels are the same.
#[test]
fn a_window_drawn_again_where_it_changed_looks_as_one_drawn_whole() {
    partial_look("partial-look");
}

// The same with the software renderer asked for, which on X11 shows a
// frame by copying its changed parts to the window, with no swap.
#[test]
fn a_window_on_the_processor_drawn_again_where_it_changed_looks_as_one_drawn_whole() {
    partial_look("partial-look-sw");
}

fn partial_look(name: &str) {
    let mut w = scene!(name, DEMO);
    w.pause(3.0);
    w.mouse_to(arrange_point(&w, "v.flags.mute + 0.5", "row('track', 2) + 0.5"));
    let keys = w.number("return paw.api.clip_list(paw.api.track_list()[3])[1].id") as i32;
    let views = [
        ("arrange", String::new()),
        ("mixer", "paw.commands.exec('view.toggle mixer')".to_string()),
        ("roll", format!("paw.commands.exec('view.toggle mixer') return paw.frontend.act.open_clip({keys})")),
        // A view painted as pictures, its playhead drawn anew each tick.
        ("notation", "paw.ext.load('extensions/notation') paw.commands.exec('notation')".to_string()),
        ("zoomed", "paw.ui.focus('arrange') paw.commands.exec('zoom by=1.4142')".to_string()),
    ];
    for (what, setup) in views {
        w.ctl(&setup);
        let partial = look(&w, true);
        w.shot(&format!("{what}-partial.png"));
        let whole = look(&w, false);
        let (count, big) = differ(&partial, &whole);
        eprintln!("{what}: {count} pixels differ, {big} by more than 2");
        let at: Vec<_> = (0..partial.len()).filter(|&i| partial[i] != whole[i]).take(12).map(|i| (i % 1400, i / 1400)).collect();
        eprintln!("{what}: at {at:?}");
        for &(x, y) in at.iter().take(3) {
            let row = |v: &[[u8; 3]]| (x.saturating_sub(3)..x + 3).map(|x| v[y * 1400 + x]).collect::<Vec<_>>();
            eprintln!("  row {y} partial {:?}\n  row {y} whole   {:?}", row(&partial), row(&whole));
        }
        if count > 0 {
            w.shot(&format!("{what}-whole.png"));
            panic!("{what}: {count} pixels differ, {big} by more than 2");
        }
    }
    w.assert_alive("at the end");
}

/// Wait for a file of at least `size` bytes.
fn wait_for_file(path: &Path, size: u64) {
    let deadline = Instant::now() + Duration::from_secs(60);
    while !fs::metadata(path).is_ok_and(|m| m.len() >= size) {
        assert!(Instant::now() < deadline, "no file at {}", path.display());
        std::thread::sleep(Duration::from_millis(200));
    }
}

/// A song with a project file, so that Save has somewhere to write.
fn saved_song(path: &Path) -> String {
    format!("{DEMO}\npaw.project.save('{}')", path.display())
}

#[test]
fn closing_with_unsaved_changes_asks() {
    // Autosave on: a copy of the unsaved project is made and must go when
    // it is thrown away.
    let mut w = scene!("closing", &format!("paw.opt.autosave = 1\n{DEMO}"));
    let recovery = w.env_path("XDG_STATE_HOME").join("paw/recovery");
    let copies = || -> usize {
        fs::read_dir(&recovery)
            .map(|dir| dir.filter_map(Result::ok).count())
            .unwrap_or(0)
    };
    let deadline = Instant::now() + Duration::from_secs(30);
    while copies() == 0 {
        assert!(Instant::now() < deadline, "no recovery copy was made");
        w.pause(0.2);
    }

    // Cancel keeps it running.
    w.close_window();
    w.shot("closing.png");
    w.click_text("Cancel");
    // The next close comes once this dialog has gone, not while it is up.
    assert!(w.hides("Cancel", 30), "the dialog stayed after Cancel");
    w.assert_alive("after Cancel");
    w.expect(
        "the project still unsaved",
        "paw.api.project_get().modified",
    );

    // Don't save ends it, and the copy goes with it.
    w.close_window();
    w.click_text("Don't save");
    w.wait_gone("after Don't save");
    assert_eq!(copies(), 0, "a recovery copy was left behind");
}

#[test]
fn closing_with_a_project_file_saves_it() {
    let file = {
        let mut dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join("window/closing-saves-files");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir.push("song");
        dir
    };
    let mut w = scene!("closing-saves", &saved_song(&file));
    w.ctl("paw.add_track({ name = 'Added after saving' })");
    w.expect("the added track unsaved", "paw.api.project_get().modified");
    let saved = fs::read_to_string(file.join("project.toml")).unwrap();
    assert!(
        !saved.contains("Added-after-saving"),
        "the folder already holds the change"
    );

    w.close_window();
    w.click_last_text("Save");
    w.wait_gone("after Save");
    let saved = fs::read_to_string(file.join("project.toml")).unwrap();
    assert!(
        saved.contains("Added-after-saving"),
        "Save did not write the change into {}",
        file.display()
    );
}

#[test]
fn lane_rows_take_drawn_points_and_markers_take_clicks() {
    let mut w = scene!("lanes", DEMO);
    w.ctl("return paw.markers.add(8, 'Verse').id");

    // The first track's lanes as rows, and a drag across the row draws.
    let drums = w.number("return paw.api.track_list()[1]") as i32;
    w.ctl(&format!("return paw.frontend.act.lane_rows({drums})"));
    w.expect(
        "a lane row on Drums",
        &format!("#paw.frontend.state(0).tracks[1].lane_rows == 1"),
    );
    w.pause(0.8);
    let lane = w.number(&format!("return paw.api.lane_list({drums})[1].id")) as i32;
    assert_eq!(
        w.number(&format!("return #paw.api.lane_points({lane})")),
        0.0
    );
    let low = arrange_point(&w, "beat(2)", "row('lane', 1) + 1.8");
    let high = arrange_point(&w, "beat(10)", "row('lane', 1) + 0.2");
    w.drag(low, high);
    w.shot("lane-drawn.png");
    w.expect(
        "points drawn",
        &format!("#paw.api.lane_points({lane}) >= 6"),
    );
    w.expect(
        "points between the beats dragged across",
        &format!(
            "(function() local lo, hi = 1e9, -1e9 for _, p in ipairs(paw.api.lane_points({lane})) do lo = math.min(lo, p[1]) hi = math.max(hi, p[1]) end return lo >= 1.5 and hi <= 10.5 and hi >= 8 end)()"
        ),
    );
    w.expect(
        "a curve, not one level",
        &format!(
            "(function() local pts = paw.api.lane_points({lane}) return math.abs(pts[1][2] - pts[#pts][2]) > 0.5 end)()"
        ),
    );
    w.assert_alive("after drawing in a lane");

    // A click on the marker puts the edit cursor at it.
    w.expect("the cursor elsewhere", "paw.cursor.beat ~= 8");
    w.click(arrange_point(&w, "beat(8) + 2.5", "1.5"));
    w.expect("the edit cursor at the marker", "paw.cursor.beat == 8");
    w.assert_alive("after clicking a marker");
}

/// A track with a clip and an empty one, for gestures on clips.
const CLIP_SONG: &str = "
local a = paw.add_track({ name = 'A' })
paw.add_track({ name = 'B' })
a:add_clip({ start = 4, length = 4, name = 'c', notes = { { pitch = 60, start = 0, length = 1 } } })
";

#[test]
fn clips_move_trim_and_are_made_by_the_pointer() {
    let mut w = scene!("clips", CLIP_SONG);
    let a = w.number("return paw.api.track_list()[1]") as i32;
    let b = w.number("return paw.api.track_list()[2]") as i32;
    let clip = |field: &str| format!("paw.api.clip_get(paw.api.clip_list({a})[1].id).{field}");
    let at = |w: &Scene, beat: &str, track: i32| arrange_point(w, &format!("beat({beat})"), &format!("row('track', {track}) + 1.5"));
    assert_eq!(w.number(&format!("return {}", clip("start"))), 4.0);

    // Dragged eight beats along, it lands on the beat there.
    w.drag(at(&w, "5.5", 1), at(&w, "13.5", 1));
    w.expect("the clip at beat 12", &format!("{} == 12", clip("start")));
    w.expect("its length kept", &format!("{} == 4", clip("length")));
    w.shot("clip-moved.png");

    // The end edge, dragged two beats, makes it longer.
    w.drag(at(&w, "16 - 0.4 / g.zoom", 1), at(&w, "18 - 0.4 / g.zoom", 1));
    w.expect(
        "the clip six beats long",
        &format!("{} == 6", clip("length")),
    );
    w.expect("its start kept", &format!("{} == 12", clip("start")));

    // The start edge, dragged a beat in, shortens it from the front.
    w.drag(at(&w, "12 + 0.4 / g.zoom", 1), at(&w, "13 + 0.4 / g.zoom", 1));
    w.expect(
        "the clip starting at 13",
        &format!("{} == 13", clip("start")),
    );
    w.expect(
        "the end kept",
        &format!(
            "{} == 18",
            format!("{} + {}", clip("start"), clip("length"))
        ),
    );

    // A double click on an empty stretch of the second track makes a clip.
    assert_eq!(w.number(&format!("return #paw.api.clip_list({b})")), 0.0);
    w.double_click(at(&w, "20.3", 2));
    w.expect("a clip on B at bar 20", &format!("#paw.api.clip_list({b}) == 1 and paw.api.clip_get(paw.api.clip_list({b})[1].id).start == 20"));
    w.assert_alive("after editing clips");
}

/// 4000 beats: long clips (one with a note every few beats), a long region,
/// and an automation lane with points all across it.
const LONG_SONG: &str = "
paw.project.tempo = 120
local track = paw.add_track({ name = 'Long' })
local notes = {}
for beat = 0, 2996, 4 do notes[#notes + 1] = { pitch = 48 + math.floor(beat / 4) % 24, start = beat, length = 2 } end
track:add_clip({ start = 0, length = 3000, name = 'long', notes = notes })
track:add_clip({ start = 3000, length = 1000, name = 'tail', notes = { { pitch = 60, start = 0, length = 4 } } })
paw.add_track({ name = 'Other' }):add_clip({ start = 100, length = 2000, name = 'other', notes = { { pitch = 50, start = 0, length = 8 } } })
paw.markers.add(100, 'Region', { length = 3000 })
paw.markers.add(2000, 'Middle')
local id = paw.api.track_list()[1]
local lane = paw.api.lane_add(id, { target = 'volume' })
for beat = 0, 4000, 8 do paw.api.lane_add_point(lane, beat, beat % 16 == 0 and -3 or -12) end
";

#[test]
fn a_very_long_song_does_not_hurt_the_window() {
    let mut w = scene!("long", LONG_SONG);
    w.expect(
        "the song 4000 beats long",
        "paw.api.project_get().length >= 4000",
    );
    w.ctl("return paw.frontend.act.lane_rows(paw.api.track_list()[1])");
    w.pause(3.0);
    w.assert_alive("after showing it");
    let idle = w.cpu_percent(3.0);
    assert!(
        idle < 40.0,
        "the window uses {idle:.0}% of a core when idle"
    );

    // Zooming in, and out again, with Ctrl and the wheel.
    let over = arrange_point(&w, "beat(10)", "row('track', 2) + 1.5");
    w.wheel_with_ctrl(over, true, 12);
    w.assert_alive("after zooming in");
    w.wheel_with_ctrl(over, false, 20);
    w.assert_alive("after zooming out");
    w.key("ctrl+0");
    w.assert_alive("after showing the whole song");
    w.shot("long-fit.png");
    w.wheel_with_ctrl(over, true, 14);
    w.assert_alive("after zooming in again");

    // The notes of the long clip, in the piano roll, opened by a double
    // click (again if the window was too busy to take two clicks as one).
    let notes_at = arrange_point(&w, "beat(10)", "row('track', 1) + 1.5");
    for _ in 0..3 {
        w.double_click(notes_at);
        if w.wait_for("paw.ui.visible('pianoroll')", 5).is_ok() {
            break;
        }
    }
    w.expect("the piano roll open", "paw.ui.visible('pianoroll')");
    w.pause(1.0);
    w.assert_alive("after opening the piano roll");
    w.shot("long-roll.png");
}

// The roll shows only the notes in view, so a clip of 3000 beats costs no
// more than a short one. (Before that it used about 90% of a core.)
#[test]
fn a_piano_roll_on_a_very_long_clip_is_idle() {
    let mut w = scene!("long-roll", LONG_SONG);
    let clip = w.number("return paw.api.clip_list(paw.api.track_list()[1])[1].id") as i32;
    w.ctl(&format!("return paw.frontend.act.open_clip({clip})"));
    w.expect("the piano roll open", "paw.ui.visible('pianoroll')");
    w.pause(3.0);
    let busy = w.cpu_percent(3.0);
    assert!(
        busy < 40.0,
        "the window uses {busy:.0}% of a core with the roll open"
    );
    w.assert_alive("at the end");
}

/// A directory of this test's own, outside the scene's (which is wiped at
/// the start), for files that must exist before the window starts.
fn files_dir(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR"))
        .join("window")
        .join(format!("{name}-files"));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

// The window's own processor time is measured with no other scene running,
// whose X servers and windows would take the machine from it.
#[test]
fn an_idle_window_uses_little_of_a_processor() {
    let mut w = scene!("idle", DEMO, alone);
    let idle = w.settled_cpu_percent(5.0);
    assert!(idle.last() < Some(&5.0), "the idle window uses {idle:.1?}% of a core");
    w.assert_alive("while idle");
}

// What playing costs with two piano rolls side by side, against one: the
// window and its kernel together, measured in turns so that what else the
// machine does falls on both alike. Run on its own, with the threads of the
// software renderer fixed (`LP_NUM_THREADS=4 cargo test --release -p
// paw-gui --test window -- --ignored --nocapture playing_with_two_rolls`).
#[test]
#[ignore]
fn playing_with_two_rolls_costs_about_what_one_does() {
    let mut w = scene!("cpu-two-rolls", TWO_CLIPS, alone);
    let one_roll = "paw.commands.exec('e roll://' .. first) paw.commands.exec('only')";
    w.ctl(one_roll);
    w.expect("one roll", "#paw.panes.state().panes == 1 and paw.ui.views.pianoroll.clip_id == first");
    let (mut one, mut two) = (Vec::new(), Vec::new());
    for round in 0..4 {
        for split in [round % 2 == 1, round % 2 == 0] {
            if split {
                w.ctl(one_roll);
                w.ctl("paw.commands.exec('vs roll://' .. second)");
                w.expect("two rolls", "#paw.panes.state().panes == 2");
            } else {
                w.ctl(one_roll);
                w.expect("one roll", "#paw.panes.state().panes == 1");
            }
            w.ctl("paw.api.transport_seek(0) paw.api.transport_play()");
            w.pause(1.5);
            let cpu = w.group_cpu_percent(5.0);
            w.ctl("paw.api.transport_stop()");
            w.pause(0.5);
            if split { two.push(cpu) } else { one.push(cpu) }
        }
    }
    let mean = |v: &[f64]| v.iter().sum::<f64>() / v.len() as f64;
    eprintln!("playing, window and kernel, % of a core: one roll {one:.1?} (mean {:.1}), two rolls {two:.1?} (mean {:.1})", mean(&one), mean(&two));
    w.shot("cpu-two-rolls.png");
    assert!(mean(&two) < mean(&one) * 1.6 + 5.0, "two rolls cost {:.1}% against {:.1}% for one", mean(&two), mean(&one));
    w.assert_alive("after playing");
}

#[test]
fn an_idle_window_with_kernel_panes_and_a_window_of_a_view_asks_for_nothing() {
    let mut w = scene!("idle-panes", &format!("{LANE_SONG}\npaw.qf.set({{ {{ address = paw.address.project(), text = 'zebra crossing' }} }})"), alone);
    // The curve in a pane (cells and a strip under them), the list in a
    // window of its own.
    w.key("Return");
    w.expect("the curve in a pane", "paw.ui.focused == 'curve'");
    w.type_text(":qf.window");
    w.key("Return");
    w.expect("the list in a window of its own", "#paw.canvas.windows() == 1");
    w.expect("all sent as scenes: the arrange view and the device panel too", "#paw.scene.watchers()[1].windows == 4");
    w.find_text("dB", 0);
    let idle = w.settled_cpu_percent(5.0);
    assert!(idle.last() < Some(&5.0), "the idle window uses {idle:.1?}% of a core");
    w.assert_alive("while idle with panes");
}

#[test]
fn the_file_menu_lists_recent_projects_and_opens_one() {
    let dir = files_dir("recent");
    let file = dir.join("recentsong.json");
    let setup = format!(
        "paw.recent.use('{}/recent.json')\n{DEMO}\npaw.project.save('{}')\npaw.project.new()",
        dir.display(),
        file.display()
    );
    let mut w = scene!("recent", &setup);
    w.expect("an empty project", "paw.api.project_get().path == nil");
    w.open_file_menu();
    w.click_text("Open recent");
    w.shot("recent-menu.png");
    w.click_text("recentsong");
    w.expect(
        "the saved project open",
        &format!("paw.api.project_get().path == '{}'", file.display()),
    );
    w.expect("its tracks", "#paw.api.track_list() == 5");
    w.assert_alive("after opening a recent project");
}

#[test]
fn the_render_dialog_offers_mp3() {
    if on_path("ffmpeg").is_none() {
        eprintln!("window test mp3 skipped: ffmpeg is not installed");
        return;
    }
    let mut w = scene!("mp3", DEMO);
    let target = w.dir.join("render/song.mp3");
    fs::create_dir_all(target.parent().unwrap()).unwrap();
    w.open_render_dialog();
    w.click_text("MP3");
    w.render_to(&target);
    wait_for_file(&target, 1000);
    // MP3 starts with an ID3 tag or a frame header.
    let head = fs::read(&target).unwrap();
    assert!(
        head.starts_with(b"ID3") || (head[0] == 0xff && head[1] & 0xe0 == 0xe0),
        "not an MP3 file"
    );
    w.assert_alive("after rendering");
}

#[test]
fn take_lanes_show_the_takes_and_a_click_chooses_one() {
    let setup = "
local track = paw.add_track({ name = 'T' })
local id = paw.api.track_list()[1]
track:add_clip({ start = 0, length = 8, name = 'c', notes = { { pitch = 60, start = 0, length = 1 } } })
paw.takes.new(paw.api.clip_list(id)[1].id)
paw.cursor.set_track(id)
";
    let mut w = scene!("takes", setup);
    let clip = "paw.api.clip_list(paw.api.track_list()[1])[1].id";
    w.expect(
        "two takes, the second playing",
        &format!("select(2, paw.takes.count({clip})) == 2"),
    );
    w.ctl("return paw.commands.exec('take.lanes')");
    w.expect(
        "two take rows",
        "paw.frontend.state(0).tracks[1].take_rows == 2",
    );
    w.pause(0.8);
    w.shot("take-lanes.png");
    // Row k of the lanes is under the clip: the first take's row is the
    // first.
    w.click(arrange_point(&w, "beat(2)", "row('take', 1) + 0.5"));
    w.expect(
        "the first take playing",
        &format!("select(2, paw.takes.count({clip})) == 1"),
    );
    w.assert_alive("after choosing a take");
}

#[test]
fn the_more_menu_docks_a_view_in_a_pane_that_pops_out_on_request() {
    let mut w = scene!(
        "more",
        &format!("{DEMO}\npaw.ext.load('extensions/undotree')")
    );
    w.click_text("More");
    w.shot("more-menu.png");
    w.click_text("Undo tree");
    w.expect(
        "the undo tree docked in a pane, painted, with the keyboard",
        "(function() for _, p in ipairs(paw.panes.state().panes) do if p.view == 'undotree_paint' then return p.kind == 'paint' and p.focused end end end)()",
    );
    assert_eq!(w.number("return #paw.canvas.windows()"), 0.0);
    w.shot("more-pane.png");
    // The first button on its title pops it out into a window of its own;
    // its own `q` there closes it, and keys reach the main window again.
    let right = w.pane("undotree_paint", "p.x + p.w");
    let top = place::AREA_TOP + w.pane("undotree_paint", "p.y");
    w.click((right - 37, top + 12));
    w.expect(
        "the undo tree in a window of its own",
        "#paw.canvas.windows() == 1 and paw.canvas.windows()[1].name == 'undotree_paint'",
    );
    w.pause(0.6);
    w.key("q");
    w.expect("its window closed", "#paw.canvas.windows() == 0");
    w.expect("the keyboard back in the main window", "paw.ui.focused == 'arrange'");
    let row = w.number("return paw.cursor.track().index");
    w.key("j");
    w.expect("keys reach it", &format!("paw.cursor.track().index == {}", row + 1.0));
    w.assert_alive("after a view in a pane and in a window");
}

/// The demo song with a volume lane shown as a row under its first track,
/// the cursor on it.
const LANE_SONG: &str = "
dofile('examples/demo-song.lua')
local t = paw.tracks()[1]
local lane = t:automate('volume')
lane:set_points({ { 0, -12 }, { 8, 0 } })
paw.lanes.open(t)
paw.cursor.set_track(t.id, lane.id)
";

#[test]
fn enter_on_a_lane_row_shows_its_curve_in_a_pane() {
    let mut w = scene!("curve-pane", LANE_SONG);
    w.key("Return");
    w.expect("the curve has the keyboard", "paw.ui.focused == 'curve'");
    w.expect(
        "in a pane drawn in cells, with room",
        "(function() for _, p in ipairs(paw.panes.state().panes) do if p.view == 'curve' then return p.kind == 'cells' and p.w > 200 and p.h > 100 and p.focused end end end)()",
    );
    // What the kernel draws there shows: the curve's scale along its left.
    w.find_text("dB", 0);
    w.shot("curve-pane.png");
    // Its keys work in it: a point added at the cursor.
    let lane = w.number("return paw.api.lane_list(paw.tracks()[1].id)[1].id") as i32;
    let before = w.number(&format!("return #paw.api.lane_points({lane})"));
    w.key("l");
    w.key("l");
    w.key("o");
    w.expect(
        "a point added from the pane",
        &format!("#paw.api.lane_points({lane}) == {}", before + 1.0),
    );
    // `:q` closes the pane and gives the keyboard back.
    w.type_text(":q");
    w.key("Return");
    w.expect("the pane gone", "paw.ui.focused ~= 'curve'");
    w.assert_alive("after the curve's pane");
}

/// The demo song and a quickfix list of one entry.
const QF_SONG: &str = "
dofile('examples/demo-song.lua')
paw.qf.set({ { address = paw.address.project(), text = 'zebra crossing', level = 'error' } }, { title = 'Tests' })
";

#[test]
fn copen_docks_the_list_and_focus_moves_between_panes_and_comes_back() {
    let mut w = scene!("copen", QF_SONG);
    w.type_text(":copen");
    w.key("Return");
    w.expect("the list has the keyboard", "paw.ui.focused == 'qflist'");
    w.find_text("zebra crossing", 0);
    w.shot("copen.png");
    // Ctrl-w k goes up to the arrange view, a click in the list back to it.
    w.key("ctrl+w");
    w.key("k");
    w.expect("the arrange view has the keyboard", "paw.ui.focused == 'arrange'");
    w.click(w.pane_middle("qflist"));
    w.expect("a click gives the list the keyboard", "paw.ui.focused == 'qflist'");
    // A click in the arrange view's pane takes it back.
    w.click(arrange_point(&w, "6", "row('track', 1) + 0.5"));
    w.expect("a click gives the arrange view the keyboard", "paw.ui.focused == 'arrange'");
    // Popped out, the list leaves its pane for a window of its own; `q`
    // there closes it and the keyboard is the main window's again.
    w.type_text(":qf.window");
    w.key("Return");
    w.expect(
        "the list in a window of its own, not in a pane",
        "#paw.canvas.windows() == 1 and paw.ui.focused == 'qflist' and #paw.panes.state().panes == 2",
    );
    w.pause(0.6);
    w.key("q");
    w.expect("its window closed", "#paw.canvas.windows() == 0");
    w.expect("the keyboard back in the arrange view", "paw.ui.focused == 'arrange'");
    w.key("ctrl+w");
    w.key("l");
    w.expect("keys reach the main window again", "paw.ui.focused == 'devices'");
    w.assert_alive("after moving between panes");
}

#[test]
fn tabs_show_along_the_top_and_a_click_or_gt_goes_to_one() {
    let mut w = scene!("tabs", DEMO);
    w.type_text(":tabnew mixer");
    w.key("Return");
    w.expect("two tabs, the second current", "#paw.ui.tabs == 2 and paw.ui.tab == 2");
    w.expect(
        "the mixer fills the second",
        "(function() local s = paw.panes.state() return #s.panes == 1 and s.panes[1].view == 'mixer' and s.top > 0 end)()",
    );
    w.shot("tabs.png");
    w.click_text("arrange");
    w.expect("a click on the first tab goes there", "paw.ui.tab == 1");
    w.key("g");
    w.key("t");
    w.expect("gt to the next", "paw.ui.tab == 2");
    w.type_text(":tabclose");
    w.key("Return");
    w.expect("one tab again", "#paw.ui.tabs == 1");
    w.assert_alive("after tabs");
}

/// Where the row of tabs puts tab `i` (from 0): every tab is 150 pixels
/// wide with 2 between, from 6 in (crates/paw-gui/src/panes.rs).
fn tab_at(i: i32, dx: i32) -> Point {
    (6 + i * 152 + dx, place::AREA_TOP + 15)
}

#[test]
fn a_tab_closes_by_its_button_or_a_middle_click_a_plus_opens_one_and_a_drag_moves_it() {
    let mut w = scene!("tab-buttons", DEMO);
    let views = "(function() local out = {} for _, t in ipairs(paw.ui.tabs) do out[#out + 1] = paw.layout.windows(t.layout)[1].view end return table.concat(out, ' ') end)()";
    w.type_text(":tabnew mixer");
    w.key("Return");
    w.expect("two tabs", "#paw.ui.tabs == 2");
    // The + after the last tab: a new tab on the start page.
    w.click((6 + 2 * 152 + 11, place::AREA_TOP + 15));
    w.expect("+ opens a third tab, on the start page", &format!("#paw.ui.tabs == 3 and paw.ui.tab == 3 and {views} == 'arrange mixer empty'"));
    w.shot("tab-new.png");
    // Its close button, at its right end.
    w.click(tab_at(2, 150 - 13));
    w.expect("its close button closes it", &format!("{views} == 'arrange mixer'"));
    // A middle click on a tab closes it.
    w.type_text(":tabnew devices");
    w.key("Return");
    w.expect("a tab of the device panel", &format!("{views} == 'arrange mixer devices'"));
    w.mouse_to(tab_at(1, 60));
    w.xdotool(&["click", "2"]);
    w.pause(0.3);
    w.expect("a middle click closes the mixer's tab", &format!("{views} == 'arrange devices'"));
    // A drag of the first tab past the second moves it there, as :tabmove.
    w.drag(tab_at(0, 60), tab_at(1, 100));
    w.expect("the arrange view's tab is the second now", &format!("{views} == 'devices arrange'"));
    w.assert_alive("after the tab buttons");
}

/// The demo song, the notation extension, and the first two MIDI clips of
/// the song as `first` and `second`.
const TWO_CLIPS: &str = "
dofile('examples/demo-song.lua')
paw.ext.load('extensions/notation')
local ids = {}
for _, t in ipairs(paw.api.track_list()) do
  for _, c in ipairs(paw.api.clip_list(t)) do
    if c.kind == 'midi' then ids[#ids + 1] = c.id end
  end
end
first, second = ids[1], ids[#ids]
";

#[test]
fn a_start_layout_of_the_notation_alone_fills_the_window() {
    let mut w = scene!("notation-alone", &format!("{TWO_CLIPS}\npaw.ui.start_layout = 'notation://' .. first\npaw.layout.start()"));
    w.expect(
        "one pane, the notation, the whole main area",
        "(function() local s = paw.panes.state() return #s.panes == 1 and s.panes[1].view == 'notation' and s.panes[1].x == 0 and s.panes[1].y == 0 end)()",
    );
    w.expect("on the clip that the layout names", "paw.ui.views.notation.clip_id == first");
    w.pause(1.0);
    w.shot("notation-alone.png");
    // Closing and toggling leave it: no arrange view comes.
    w.key("ctrl+w");
    w.key("c");
    w.type_text(":view.close");
    w.key("Return");
    w.expect(
        "still the notation alone, and no arrange view in the layout",
        "(function() local s = paw.panes.state() return #s.panes == 1 and s.panes[1].view == 'notation' and not paw.layout.find(paw.ui.layout, 'arrange') end)()",
    );
    w.assert_alive("with the notation alone");
}

#[test]
fn a_split_made_with_ctrl_w_v_shows_two_piano_rolls_on_two_clips() {
    let mut w = scene!("two-rolls", &format!("{TWO_CLIPS}\npaw.layout.restore(paw.layout.as_tabs('roll://' .. first))"));
    w.expect("the roll alone", "#paw.panes.state().panes == 1 and paw.ui.focused == 'pianoroll'");
    w.key("ctrl+w");
    w.key("v");
    w.expect(
        "two panes of the roll side by side",
        "(function() local s = paw.panes.state() return #s.panes == 2 and s.panes[1].view == 'pianoroll' and s.panes[2].view == 'pianoroll' and s.panes[2].x > s.panes[1].x end)()",
    );
    let second = w.ctl("return second");
    w.type_text(&format!(":e roll://{second}"));
    w.key("Return");
    w.expect(
        "each pane on its own clip",
        "(function() local c = {} for _, win in ipairs(paw.layout.windows(paw.ui.layout)) do c[#c + 1] = paw.layout.within(win, function() return paw.ui.views.pianoroll.clip_id end) end return c[1] == first and c[2] == second end)()",
    );
    w.pause(1.0);
    w.shot("two-rolls.png");
    // A click in the left pane (on its keyboard, which plays a note) gives
    // it the keyboard of the computer, with its clip.
    let left = w.ctl("local p = paw.panes.state().panes[1] return math.floor(p.x + 12)").parse::<i32>().unwrap();
    let mid = w.ctl("local p = paw.panes.state().panes[1] return math.floor(p.y + p.h / 2)").parse::<i32>().unwrap();
    w.click((left, place::AREA_TOP + mid));
    w.expect("the left roll has the keyboard, on the first clip", "paw.ui.views.pianoroll.clip_id == first");
    w.assert_alive("with two rolls");
}

#[test]
fn the_window_follows_a_change_made_from_outside() {
    let mut w = scene!("pushed", DEMO);
    assert!(!w.shows("Zebra", 0), "the track is there before it is made");
    w.ctl("return paw.add_track({ name = 'Zebra' }).id");
    assert!(
        w.shows("Zebra", 10),
        "a track added from outside does not show in the window"
    );
    w.ctl("return paw.api.track_set(paw.api.track_list()[6], 'name', 'Okapi')");
    assert!(
        w.shows("Okapi", 10),
        "a track renamed from outside does not show"
    );
    w.assert_alive("after changes from outside");
}

#[test]
fn a_window_connects_to_a_kernel_over_tcp_and_a_wrong_token_is_refused() {
    let mut w = scene!("remote", DEMO, remote);
    assert!(w.shows("Drums", 20), "the remote project does not show");
    w.ctl("return paw.add_track({ name = 'Zebra' }).id");
    assert!(
        w.shows("Zebra", 10),
        "a change at the remote kernel does not show"
    );
    w.assert_alive("while connected");

    let refused = Command::new(env!("CARGO_BIN_EXE_paw-gui"))
        .args([
            "--connect",
            w.tcp.as_deref().unwrap(),
            "--token",
            "not-the-token",
        ])
        .env("DISPLAY", &w.display)
        .env("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent/bus")
        // Where it remembers the kernel's certificate: the scene's, not ours.
        .env("XDG_STATE_HOME", w.env_path("XDG_STATE_HOME"))
        .output()
        .unwrap();
    let said = String::from_utf8_lossy(&refused.stderr).to_string()
        + &String::from_utf8_lossy(&refused.stdout);
    assert!(!refused.status.success(), "a wrong token was taken: {said}");
    assert!(said.contains("did not accept the token"), "{said}");
}

#[test]
fn a_window_told_not_to_listen_stops_at_once_and_says_why() {
    let xdg = Path::new(env!("CARGO_TARGET_TMPDIR")).join(format!("no-listen-{}", std::process::id()));
    std::fs::create_dir_all(&xdg).unwrap();
    let out = Command::new(env!("CARGO_BIN_EXE_paw-gui"))
        .args(["--no-listen", "--no-plugins", "--audio", "null"])
        .env("PAW_BIN", kernel_binary())
        .env_remove("DISPLAY")
        .env_remove("WAYLAND_DISPLAY")
        .env("XDG_RUNTIME_DIR", &xdg)
        .env("XDG_CONFIG_HOME", &xdg)
        .env("XDG_STATE_HOME", &xdg)
        .env("XDG_DATA_HOME", &xdg)
        .env("XDG_CACHE_HOME", &xdg)
        .stdin(Stdio::null())
        .output()
        .unwrap();
    let _ = std::fs::remove_dir_all(&xdg);
    let said = String::from_utf8_lossy(&out.stderr).to_string() + &String::from_utf8_lossy(&out.stdout);
    assert!(!out.status.success(), "{said}");
    assert!(said.contains("--no-listen"), "{said}");
    // It saw the kernel end, and did not wait out its limit for a socket
    // that never came: a time on the clock would also count the build of
    // the kernel and a loaded machine.
    assert!(said.contains("the kernel stopped before it was ready"), "it waited for a socket that never came: {said}");
}

/// How reliably the screen is read, for whoever changes how: every text the
/// tests click, in each place they click it, over fresh windows. Run it
/// with `cargo test -p paw-gui --test window -- --ignored --nocapture
/// reading_the_screen`; it says how many readings found each text.
#[test]
#[ignore = "a measurement, not a test: it takes minutes"]
fn reading_the_screen_is_reliable() {
    const RUNS: usize = 8;
    let (mut tried, mut found) = (0, 0);
    for run in 0..RUNS {
        let w = scene!(
            "reading",
            &format!("{DEMO}\npaw.ext.load('extensions/undotree')")
        );
        let mut check = |w: &Scene, texts: &[(&str, i32)]| {
            for &(text, nth) in texts {
                tried += 1;
                let at = Scene::locate(&w.screens(text, nth), text, nth);
                if at.is_some() {
                    found += 1;
                } else {
                    eprintln!("run {run}: `{text}` not found");
                }
            }
        };
        w.open_file_menu();
        check(
            &w,
            &[
                ("New project", 0),
                ("Open recent", 0),
                ("Save as", 0),
                ("Render", 0),
                ("Quit", 0),
            ],
        );
        w.click((700, 700));
        w.click_text("More");
        check(&w, &[("Undo tree", 0)]);
        w.click((700, 700));
        w.open_render_dialog();
        check(
            &w,
            &[
                ("File", 0),
                ("Tail", 0),
                ("MP3", 0),
                ("Cancel", 0),
                ("Render", -1),
            ],
        );
        w.click_text("Cancel");
        w.close_window();
        check(&w, &[("Don't save", 0), ("Cancel", 0), ("Save", -1)]);
    }
    eprintln!("read {found} of {tried}");
    assert_eq!(found, tried);
}

#[test]
fn keys_reach_the_window_after_an_entry_of_a_submenu() {
    let mut w = scene!("submenu", DEMO);
    let header = arrange_point(&w, "6", "row('track', 1) + 0.5");
    w.click(header);
    w.expect("the first track under the cursor", "paw.cursor.track().index == 1");
    w.mouse_to(header);
    w.xdotool(&["click", "3"]);
    w.pause(0.4);
    w.click_text("Colour");
    w.shot("submenu.png");
    w.click_text("Teal");
    w.expect("the colour taken", "paw.tracks()[1].color ~= nil");
    // The menus are shut: what is typed goes to the kernel's mappings.
    w.key("j");
    w.expect("the cursor on the second track", "paw.cursor.track().index == 2");
    w.assert_alive("after a submenu");
}

/// The clip launcher extension, two tracks, clips in slots, two named
/// scenes, and the session view shown.
const SESSION_SONG: &str = "
local api = paw.api
paw.ext.load('extensions/launcher')
local launcher = require('launcher')
local keys = paw.add_track({ name = 'Keys' })
keys:add_clip({ start = 0, length = 8, name = 'Chorus', notes = { { pitch = 60, start = 0, length = 2 } } })
local bass = paw.add_track({ name = 'Bass' })
launcher.add(keys.id, 0, { length = 4, name = 'Riff', notes = { { pitch = 67, start = 0, length = 1 } } })
launcher.add(bass.id, 0, { length = 4, name = 'Walk', notes = { { pitch = 36, start = 0, length = 1 } } })
launcher.set_scene_name(0, 'Verse')
launcher.set_scene_name(1, 'Bridge')
api.undo_checkpoint()
paw.ui.show('session')
";

#[test]
fn the_session_view_launches_scenes_and_takes_clips_from_the_timeline() {
    let mut w = scene!("session", SESSION_SONG);
    let keys = w.number("return paw.api.track_list()[1]") as i32;
    let bass = w.number("return paw.api.track_list()[2]") as i32;
    let playing = |track: i32| format!("(require('launcher').state()[{track}] or {{}}).slot");

    // A scene launches its row on both tracks together.
    w.click_text("Verse");
    w.expect(
        "the first scene playing",
        &format!("{} == 0 and {} == 0", playing(keys), playing(bass)),
    );
    w.shot("session-playing.png");
    w.click_text("all");
    w.expect(
        "every clip stopped",
        &format!("(require('launcher').state()[{keys}] or {{}}).stopped == true"),
    );
    w.type_text(":launch.back all");
    w.key("Return");
    w.expect("the timeline again", "next(require('launcher').state()) == nil");
    // The scene set the song playing, and the timeline follows the playhead:
    // on a loaded machine it has paged past the chorus before the drag.
    // Stopped, and back at its start, the chorus stays where it is drawn.
    w.ctl("paw.api.transport_stop()");
    w.expect("the song stopped", "not paw.api.transport_get().playing");
    w.ctl("paw.ui.views.arrange.scroll = 0; paw.api.ui_redraw()");

    // A clip dragged from the timeline onto an empty slot of the bass is
    // copied into it: the slot under the bass's clip, in the second row.
    let column = w.find_text("Walk", 0);
    let row = w.find_text("Bridge", 0);
    // The chorus is the clip at the start of the first row: its name is small
    // on its colour, which the reading of the screen does not always make out.
    let chorus = arrange_point(&w, "beat(1)", "row('track', 1) + 1.5");
    w.drag(chorus, (column.0, row.1));
    w.expect(
        "a copy of the chorus in the bass's second slot",
        &format!(
            "require('launcher').clip({bass}, 1) ~= nil and require('launcher').clip({bass}, 1).name == 'Chorus'"
        ),
    );
    w.expect(
        "the chorus still on the timeline",
        &format!("#paw.api.clip_list({keys}) == 1"),
    );

    // A double click on a clip in a slot opens its notes.
    let riff = w.find_text("Riff", 0);
    w.double_click(riff);
    w.expect(
        "the riff in the piano roll",
        &format!("paw.ui.views.pianoroll:clip().id == require('launcher').clip({keys}, 0).id"),
    );
    w.shot("session-roll.png");
    w.assert_alive("after the session view");
}

#[test]
fn the_windows_position_is_kept_in_the_layout() {
    let mut w = scene!("position", DEMO);
    let found = w.xdotool(&["search", "--onlyvisible", "--name", "^paw"]);
    let id = found.lines().next().expect("the window").to_string();
    w.xdotool(&["windowmove", &id, "420", "180"]);
    // It is written once a position has stood for a second.
    w.expect(
        "the position in the kernel's layout",
        "(function() local l = paw.frontend.layout_get() return l.x ~= nil and math.abs(l.x - 420) < 40 and math.abs(l.y - 180) < 40 end)()",
    );
    w.assert_alive("after being moved");
}

#[test]
fn the_status_bar_names_the_view_and_lists_its_keys() {
    let mut w = scene!("keybar", DEMO);
    // The mode names the view that has the keys, as the terminal's does,
    // and the line shows that view's keys while nothing else has it.
    // The pointer over the timeline has its own hint on the line.
    w.mouse_to((700, 20));
    assert!(w.shows("commands", 20), "the key bar of the arrange view");
    w.xdotool(&["key", "space", "m", "m"]);
    w.expect("the mixer focused", "paw.ui.focused == 'mixer'");
    w.shot("keybar-mixer.png");
    assert!(w.shows("pan", 10), "the mixer's keys");
    // A prefix lists the keys that can follow it.
    w.key("g");
    w.expect("a prefix waiting", "paw.keymap.pending() == 'g'");
    w.shot("keybar-which-key.png");
    w.key("Escape");
    w.assert_alive("after the key bar");
}

/// Where a point of the mixer is in the window, from the kernel: `x` and
/// `y` (Lua, fractions allowed) in the mixer's own cells, with `s` its first
/// strip's parts (paw/views/mixer.lua). The mixer is a scene drawn in a
/// pane: its title row is under the pane's own title.
fn mixer_point(w: &Scene, x: &str, y: &str) -> Point {
    let lua = format!(
        "local s = paw.ui.views.mixer.geometry.strips[1]
         local x, y = {x}, {y}
         for _, p in ipairs(paw.panes.state().panes) do
           if p.view == 'mixer' then
             local c = paw.canvas.cell
             return math.floor(p.x + 6 + x * c.w) .. ',' .. math.floor({top} + p.y + 24 - c.h + y * c.h)
           end
         end",
        top = place::AREA_TOP
    );
    let text = w.ctl(&lua);
    let (x, y) = text.trim_matches('"').split_once(',').unwrap_or_else(|| panic!("no mixer pane: {text}"));
    (x.parse().unwrap(), y.parse().unwrap())
}

#[test]
fn the_mixer_is_the_kernels_scene_and_its_faders_and_switches_take_the_pointer() {
    let mut w = scene!("mixer-scene", DEMO);
    w.ctl("paw.ui.show('mixer')");
    w.expect(
        "the mixer sent as a scene, its widgets as roles",
        "(function() for _, p in ipairs(paw.panes.state().panes) do if p.view == 'mixer' then return p.kind == 'cells' end end end)()",
    );
    w.expect("drawn", "paw.ui.views.mixer.geometry ~= nil");
    let id = "paw.ui.views.mixer.geometry.strips[1].id";
    let before = w.number(&format!("return paw.api.track_get({id}).volume"));
    // The fader, dragged up three rows from near its foot: louder, as in
    // the terminal (tests/tuimouse.lua drags it the same).
    let fader = mixer_point(&w, "s.x + math.floor(s.w / 2) + 1.5", "1 + s.fader + s.rows - 1.5");
    let ch = w.number("return paw.canvas.cell.h") as i32;
    w.shot("mixer-scene.png");
    w.drag(fader, (fader.0, fader.1 - 3 * ch));
    w.expect("dragged up, louder", &format!("paw.api.track_get({id}).volume > {before} and paw.api.track_get({id}).volume > -30"));
    // Two clicks on it: 0 dB.
    w.double_click(fader);
    w.expect("a double click: 0 dB", &format!("math.abs(paw.api.track_get({id}).volume) < 1e-9"));
    // M on the strip's switches.
    let mute = mixer_point(&w, "s.x + 1.5", "1 + s.chips + 0.5");
    w.click(mute);
    w.expect("M mutes", &format!("paw.api.track_get({id}).mute == true"));
    w.shot("mixer-scene-after.png");
    w.assert_alive("after working the mixer");
}

/// Where a point of the piano roll is in the window, from the kernel: a
/// pitch and a beat (Lua), in the middle of the pitch's row.
/// Where a point of the arrange view is in the window: `x` and `y` are Lua
/// expressions in its cells, which may use `beat(b)` (the column of a
/// beat), `row(kind, index)` (the line where the row of a track, a take
/// lane or a lane of the track drawn `index`th begins), `v` (the view) and
/// `g` (its geometry). The view's pane shows it from its corner, its ruler
/// the first row.
fn arrange_point(w: &Scene, x: &str, y: &str) -> Point {
    let lua = format!(
        "local v = paw.ui.views.arrange
         local g = v.geometry
         local function beat(b) return g.hw + (b - v.scroll) * g.zoom end
         local function row(kind, index)
           for _, r in ipairs(g.layout.rows) do if r.kind == kind and r.index == index then return r.y end end
         end
         for _, p in ipairs(paw.panes.state().panes) do
           if p.view == 'arrange' then
             local c = paw.canvas.cell
             return math.floor(p.x + ({x}) * c.w) .. ',' .. math.floor({top} + p.y + ({y}) * c.h)
           end
         end",
        top = place::AREA_TOP
    );
    let text = w.ctl(&lua);
    let (x, y) = text.trim_matches('"').split_once(',').unwrap_or_else(|| panic!("no arrange pane: {text}"));
    (x.parse().unwrap(), y.parse().unwrap())
}

fn roll_point(w: &Scene, pitch: &str, beat: &str) -> Point {
    let lua = format!(
        "local r = paw.ui.views.pianoroll
         local g = r.geometry
         for _, p in ipairs(paw.panes.state().panes) do
           if p.view == 'pianoroll' then
             local c = paw.canvas.cell
             local x, y = g.keys + ({beat} - r.scroll) * g.zoom, g.head + r.top - ({pitch}) + 0.5
             return math.floor(p.x + 6 + x * c.w) .. ',' .. math.floor({top} + p.y + 24 - c.h + y * c.h)
           end
         end",
        top = place::AREA_TOP
    );
    let text = w.ctl(&lua);
    let (x, y) = text.trim_matches('"').split_once(',').unwrap_or_else(|| panic!("no roll pane: {text}"));
    (x.parse().unwrap(), y.parse().unwrap())
}

#[test]
fn the_piano_roll_is_the_kernels_scene_and_its_pencil_draws_and_moves_notes() {
    let mut w = scene!(
        "roll-scene",
        "local t = paw.add_track({ name = 'Lead' })
         local c = t:add_clip({ start = 0, length = 8, name = 'Hook', notes = { { pitch = 60, start = 1, length = 1 } } })
         paw.api.undo_checkpoint()
         paw.ui.views.pianoroll:edit(c)
         paw.ui.views.pianoroll.pitch, paw.ui.views.pianoroll.top = 60, 66"
    );
    w.expect(
        "the roll sent as a scene",
        "(function() for _, p in ipairs(paw.panes.state().panes) do if p.view == 'pianoroll' then return p.kind == 'cells' end end end)()",
    );
    w.expect("drawn", "paw.ui.views.pianoroll.geometry ~= nil");
    let notes = "(function() local o = {} for _, n in ipairs(paw.ui.views.pianoroll:clip():notes()) do o[#o + 1] = n.pitch .. '@' .. n.start .. '+' .. n.length end return table.concat(o, ' ') end)()";
    // A click on empty grid: a note of the roll's length, on the step clicked.
    let empty = roll_point(&w, "64", "3.1");
    w.click(empty);
    w.expect("a click draws a note", &format!("{notes} == '60@1+1 64@3+0.25'"));
    w.shot("roll-scene.png");
    // The first note dragged a beat on and two rows up.
    let note = roll_point(&w, "60", "1.4");
    let to = roll_point(&w, "62", "2.4");
    w.drag(note, to);
    w.expect("a drag moves it", &format!("{notes} == '62@2+1 64@3+0.25'"));
    w.shot("roll-scene-after.png");
    w.assert_alive("after working the roll");
}

#[test]
fn a_mixer_strip_says_where_its_track_plays_into_and_a_click_there_offers_another() {
    let mut w = scene!("mixer-output", DEMO);
    w.ctl("paw.ui.show('mixer')");
    w.expect("the row under the name", "paw.ui.views.mixer.geometry ~= nil and paw.ui.views.mixer.geometry.strips[1].output ~= nil");
    let id = "paw.ui.views.mixer.geometry.strips[1].id";
    w.shot("mixer-output.png");
    w.click(mixer_point(&w, "s.x + 3.5", "1 + s.output + 0.5"));
    w.expect(
        "the tracks it could play into, to choose from",
        &format!("paw.pick.state() ~= nil and paw.pick.state().title == 'Output of ' .. paw.api.track_get({id}).name"),
    );
    w.key("Escape");
    w.assert_alive("after choosing where a track plays into");
}

#[test]
fn a_tall_mixer_strip_names_four_devices_and_a_click_on_the_fourth_picks_it() {
    let mut w = scene!("mixer-devices", DEMO);
    w.ctl("local t = paw.track(paw.api.track_list()[1]) for _ = 1, 5 do t:add_device('gain') end");
    // The mixer in a tab of its own, as tall as the window.
    w.type_text(":tabnew mixer");
    w.key("Return");
    w.expect("four rows for devices", "paw.ui.views.mixer.geometry ~= nil and paw.ui.views.mixer.geometry.strips[1].slots == 4");
    w.shot("mixer-devices.png");
    w.click(mixer_point(&w, "s.x + 3.5", "1 + s.devices + 3 + 0.5"));
    w.expect(
        "the fourth device picked in the device panel",
        "paw.ui.focused == 'devices' and paw.ui.views.devices:selected().id == paw.api.track_get(paw.api.track_list()[1]).devices[4]",
    );
    w.assert_alive("after picking a device");
}

#[test]
fn the_clip_light_lights_at_full_scale_and_a_click_on_the_peak_puts_it_out() {
    let mut w = scene!("mixer-clip", DEMO);
    w.ctl("paw.ui.show('mixer')");
    w.expect("drawn", "paw.ui.views.mixer.geometry ~= nil");
    let id = "paw.ui.views.mixer.geometry.strips[1].id";
    // The clip light, along the top of the first strip's meters.
    let light = mixer_point(&w, "s.x + 1", "1 + s.fader");
    let red = |w: &Scene| w.pixels(light, (14, 6)).iter().any(|p| p[0] > 220 && p[1] < 90 && p[2] < 90);
    assert!(!red(&w), "the light is out before anything clipped");
    // Playing, the meters and peaks move by the live values alone: the
    // mixer is not drawn again for them.
    w.ctl(
        "_G.drawn, _G.render = 0, paw.ui.render_scene
         paw.ui.render_scene = function(view, ...) if view == 'mixer' then drawn = drawn + 1 end return render(view, ...) end
         paw.api.transport_play()",
    );
    w.pause(1.5);
    let drawn = w.number("return drawn");
    w.ctl("paw.api.transport_stop(); paw.ui.render_scene = _G.render");
    assert!(drawn <= 3.0, "the mixer was drawn {drawn} times in a second and a half of playing");
    // Every meter at full scale for a moment, as the kernel reads them.
    w.ctl("_G.real_meter = paw.api.track_meter; paw.api.track_meter = function() return 1, 1 end");
    w.expect("lit in the live values", &format!("paw.scene.live().clips[tostring({id})] == true"));
    w.ctl("paw.api.track_meter = _G.real_meter");
    w.pause(0.5);
    w.shot("mixer-clip.png");
    assert!(red(&w), "the clip light is lit in the window");
    w.expect("it stays lit", &format!("select(4, paw.draw.track_peak({id})) == true"));
    w.click(mixer_point(&w, "s.x + s.w - 1.5", "1 + s.fader + s.rows + 0.5"));
    w.expect("a click on the peak puts it out", &format!("select(4, paw.draw.track_peak({id})) == false"));
    w.pause(0.5);
    assert!(!red(&w), "and the window shows it out");
    w.assert_alive("after the clip light");
}

/// Where a point of the device panel is in the window, from the kernel:
/// `x` and `y` (Lua, fractions allowed) in the panel's own cells, its title
/// row 0, with `W` its width and `lay` its layout (paw/views/devices.lua).
fn devices_point(w: &Scene, x: &str, y: &str) -> Point {
    let lua = format!(
        "for _, p in ipairs(paw.panes.state().panes) do
           if p.view == 'devices' then
             local c = paw.canvas.cell
             local W = math.floor((p.w - 12) / c.w)
             local lay = paw.ui.views.devices.layout(W)
             local x, y = {x}, {y}
             return math.floor(p.x + 6 + x * c.w) .. ',' .. math.floor({top} + p.y + 24 - c.h + y * c.h)
           end
         end",
        top = place::AREA_TOP
    );
    let text = w.ctl(&lua);
    let (x, y) = text.trim_matches('"').split_once(',').unwrap_or_else(|| panic!("no device pane: {text}"));
    (x.parse().unwrap(), y.parse().unwrap())
}

#[test]
fn the_device_panel_is_the_kernels_scene_and_its_sliders_and_buttons_take_the_pointer() {
    let mut w = scene!(
        "devices-scene",
        "local t = paw.add_track({ name = 'Lead' })
         t:add_device('gain')
         t:add_device('delay')
         paw.cursor.set_track(t)"
    );
    w.expect(
        "the panel sent as a scene, its widgets as roles",
        "(function() for _, p in ipairs(paw.panes.state().panes) do if p.view == 'devices' then return p.kind == 'cells' end end end)()",
    );
    w.expect("drawn", "paw.ui.views.devices.geometry ~= nil and paw.ui.views.devices.geometry.lay ~= nil");
    let id = "paw.api.track_get(paw.cursor.track_id()).devices";
    let first = w.number(&format!("return {id}[1]")) as i64;
    // The first parameter of the gain, on row 2: dragged to the end of its
    // slider, the top of its range.
    let key = "paw.api.device_get(".to_string() + &first.to_string() + ").param_info[1]";
    let start = devices_point(&w, "lay.bar_at + 1.5", "2.5");
    let end = devices_point(&w, "lay.bar_at + lay.bar + 2", "2.5");
    w.shot("devices-scene.png");
    w.drag(start, end);
    w.expect("dragged to the end: the top of its range", &format!("paw.api.device_get({first}).params[{key}.key] == {key}.max"));
    // A double click: back to its default.
    w.double_click(start);
    w.expect("a double click: its default", &format!("paw.api.device_get({first}).params[{key}.key] == {key}.default"));
    // The power button, at the right of the heading on row 1.
    w.click(devices_point(&w, "W - 3", "1.5"));
    w.expect("the power button bypasses it", &format!("paw.api.device_get({first}).bypass == true"));
    w.shot("devices-scene-after.png");
    w.assert_alive("after working the device panel");
}

#[test]
fn the_command_line_lists_what_it_could_complete() {
    let mut w = scene!("complete", DEMO);
    w.type_text(":tem");
    w.expect("the prompt open", "paw.keymap.mode == 'c'");
    w.shot("complete.png");
    assert!(w.shows("tempo", 5), "tempo among the candidates");
    w.key("Escape");
    // Up walks back through what was run.
    w.type_text(":set grid 1/8");
    w.key("Return");
    w.expect("the line run", "paw.keymap.mode == 'n'");
    w.type_text(":");
    w.key("Up");
    w.expect(
        "the last line back",
        "require('paw.views.cmdline').state().before == 'set grid 1/8'",
    );
    w.key("Escape");
    w.assert_alive("after the command line");
}

#[test]
fn a_message_goes_at_the_next_key_or_change_of_mode() {
    let mut w = scene!("message", DEMO);
    // Reading the screen takes longer than a message is shown.
    w.ctl("paw.opt.message_time = 600000");
    w.ctl("paw.notify('tuning forks everywhere')");
    assert!(w.shows("tuning forks", 5), "the message on the status bar");
    w.key("j");
    assert!(!w.shows("tuning forks", 1), "gone at the next key");
    w.ctl("paw.notify('another message here')");
    assert!(w.shows("another message", 5), "the next one shows");
    w.xdotool(&["key", "colon"]);
    w.expect("the command line open", "paw.keymap.mode == 'c'");
    w.pause(0.6);
    assert!(!w.shows("another message", 1), "gone with the mode");
    w.key("Escape");
    w.assert_alive("after messages");
}

#[test]
fn a_render_says_its_peak_with_a_sign_and_warns_when_it_clips() {
    let mut w = scene!("peaksign", DEMO);
    w.ctl("paw.opt.message_time = 600000");
    w.ctl("paw.emit('render.done', { path = '/x/loud.wav', seconds = 3, peak = 2.04 })");
    assert!(w.shows("+6.2", 5), "the peak with its sign");
    w.shot("peak-sign.png");
    assert_eq!(
        w.ctl("return paw.ui.message.level").trim(),
        "warn",
        "a clipping render is a warning"
    );
    w.assert_alive("after a render");
}

#[test]
fn the_commands_list_fills_the_window() {
    let mut w = scene!("picker", DEMO);
    w.xdotool(&["key", "space", "f", "colon"]);
    w.expect("the picker open", "paw.ui.float ~= nil");
    w.pause(0.6);
    w.shot("picker.png");
    // The page is drawn as wide as the window has room for, not 104 columns.
    let wide = w.ctl("local w = 0 for _, r in ipairs(paw.ui.rects) do w = math.max(w, r.w) end return w");
    let columns: i32 = wide.trim().parse().unwrap_or(0);
    assert!(columns > 120, "the page is wider than the old 104 columns: {columns}");
    w.assert_alive("after the picker");
}

#[test]
fn the_piano_roll_scrolls_to_the_cursor_and_opens_on_it() {
    let mut w = scene!(
        "rollscroll",
        "local t = paw.add_track({ name = 'Lead' })
         t:add_clip({ start = 0, length = 8, name = 'Hook', notes = { { pitch = 98, start = 0, length = 1 } } })
         paw.api.undo_checkpoint()"
    );
    w.ctl("paw.cursor.set_track(paw.tracks()[1].id) paw.keymap.feed('<CR>')");
    w.expect("the roll open", "paw.ui.visible('pianoroll')");
    w.shot("roll-open.png");
    // To a low note and to a high one: the row of the cursor is in view.
    w.ctl("paw.ui.views.pianoroll.pitch = 38 paw.api.ui_redraw()");
    w.pause(0.8);
    w.shot("roll-low.png");
    let in_view = "(function(r) return r.pitch <= r.top and r.pitch > r.top - r.geometry.rows end)(paw.ui.views.pianoroll)";
    w.expect("the row of the cursor in view", in_view);
    assert!(w.shows("quantize", 5), "the roll drawn from its scene, its row of tools as buttons");
    w.ctl("paw.ui.views.pianoroll.pitch = 124 paw.api.ui_redraw()");
    w.pause(0.8);
    w.shot("roll-high.png");
    w.expect("the row of the cursor in view", in_view);
    w.assert_alive("after the roll");
}

#[test]
fn a_count_typed_in_the_window_reaches_the_kernel() {
    let mut w = scene!("count", DEMO);
    w.ctl("paw.keymap.feed(':e paw://tracks<CR>')");
    w.expect("the tracks as text", "paw.ui.focused:match('^textbuf') ~= nil");
    w.pause(0.5);
    w.xdotool(&["key", "j"]);
    w.xdotool(&["key", "3"]);
    w.expect("the count waiting", "paw.keymap.pending() == '3'");
    // Pressing Control must not end it: Ctrl-a then adds three, not one.
    w.key("ctrl+a");
    w.expect(
        "three added to the number, not one",
        "require('paw.textbuf').buf().state.text:line(2):find('vol -2.0', 1, true) ~= nil",
    );
    w.shot("count.png");
    w.assert_alive("after a count");
}

#[test]
fn an_ex_line_shows_its_count_and_marks_what_it_covers() {
    let mut w = scene!("exline", DEMO);
    w.type_text(":%s/c4/d4/g");
    w.expect("the line open", "paw.keymap.mode == 'c'");
    assert!(w.shows("match", 5), "the count at the end of the line");
    w.shot("ex-preview.png");
    w.key("Escape");
    w.type_text(":%s/c4/d4/gc");
    w.key("Return");
    w.expect("the question asked", "paw.ex.shown() ~= nil and paw.ex.shown().current ~= nil");
    assert!(w.shows("replace with", 5), "the question on the status bar");
    w.key("q");
    w.assert_alive("after the Ex line");
}
