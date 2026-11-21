//! The connection to a kernel's control socket: calls are answered, and the
//! state to draw is pushed by the kernel when it changes (`frontend.watch`:
//! see docs/reference/protocol.md), in parts, and put together again here.

use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, mpsc};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow, bail};
use serde_json::{Value, json};

pub struct Client {
    pub connection: paw_proto::Connection,
    /// What moves on its own (the playhead, the meters, the mode), as last sent.
    tick: Value,
    /// The parts of the state that change with the project, as last sent.
    sections: serde_json::Map<String, Value>,
    /// Some part arrived that the window has not drawn yet; and the list
    /// of device kinds did, which is only sent at first.
    fresh: bool,
    fresh_kinds: bool,
    /// The kernel's sound, played here (`:listen`, the engine menu).
    pub player: Option<paw_listen::Player>,
    /// The scenes' patches pushed and not yet taken (`scene.patch`).
    pub patches: Vec<Value>,
    /// The live values last pushed and not yet taken (`scene.live`).
    pub live: Option<Value>,
    /// The time between two frames drawn for the song alone, in
    /// microseconds (`paw.opt.window_fps`).
    pub pace: Arc<AtomicU64>,
}

impl Client {
    /// Connect to a kernel on this machine: with a seat of its own (a cursor,
    /// mode and selection), or in the instance's own (`shared`), as a window
    /// that started its kernel itself is.
    pub fn connect(path: &Path, shared: bool) -> Result<Self> {
        Self::watching(paw_proto::Connection::unix(path)?, shared)
    }

    /// Connect to a kernel on another machine (or this one) over the network.
    pub fn connect_tcp(address: &str, token: &str, wire: &paw_proto::Wire) -> Result<Self> {
        let connection = paw_proto::Connection::tcp_with(address, token, wire)?;
        if let Some(print) = &connection.trusted_now {
            eprintln!(
                "paw-gui: {address} is trusted from now on: its certificate is {print} \
                 (remembered in {})",
                paw_proto::tls::known_path().display()
            );
        }
        Self::watching(connection, false)
    }

    fn watching(connection: paw_proto::Connection, shared: bool) -> Result<Self> {
        let mut client = Self {
            connection,
            tick: Value::Null,
            sections: serde_json::Map::new(),
            fresh: false,
            fresh_kinds: false,
            player: None,
            pace: Arc::new(AtomicU64::new(1_000_000 / 30)),
            patches: Vec::new(),
            live: None,
        };
        let seat = if shared { "instance" } else { "own" };
        client.call("frontend.watch", json!([{ "seat": seat }]))?;
        Ok(client)
    }

    /// Have `wake` called whenever the kernel sends something, so that the
    /// window draws again then and at no other time: what arrives goes
    /// through a thread that waits for it. What only moves with the song
    /// (the playhead, the meters) and the panes the kernel draws are drawn
    /// at the pace set (`pace`: 30 or 15 times a second); the first change
    /// after a pause, and any other, at once.
    pub fn wake_on_events(&mut self, wake: impl Fn() + Send + 'static) {
        let (sender, receiver) = mpsc::channel();
        let from = std::mem::replace(&mut self.connection.events, receiver);
        let pace = self.pace.clone();
        std::thread::spawn(move || {
            // The engine's load wavers all the time: a frame is drawn for it
            // only when it has moved by 4%, as the bar that shows it can.
            let mut drawn: (Value, f64) = (Value::Null, 0.0);
            // When a frame was last asked for, and one waiting for its time.
            let mut woken = Instant::now();
            let mut waiting: Option<Instant> = None;
            loop {
                let song_frame = Duration::from_micros(pace.load(Ordering::Relaxed));
                let event = match waiting {
                    Some(at) => match from.recv_timeout(at.saturating_duration_since(Instant::now())) {
                        Ok(event) => event,
                        Err(mpsc::RecvTimeoutError::Timeout) => {
                            waiting = None;
                            woken = Instant::now();
                            wake();
                            continue;
                        }
                        Err(mpsc::RecvTimeoutError::Disconnected) => break,
                    },
                    None => match from.recv() {
                        Ok(event) => event,
                        Err(_) => break,
                    },
                };
                // None for nothing new; else whether only the song moved.
                let news = match &event {
                    (name, payload) if name == "frontend.state" && payload.get("sections").is_none() => {
                        let cpu = payload["cpu"].as_f64().unwrap_or(0.0);
                        let mut rest = payload.clone();
                        rest["cpu"] = Value::Null;
                        let news = rest != drawn.0 || (cpu - drawn.1).abs() >= 0.04;
                        let song = rest["modal"] == drawn.0["modal"];
                        if news {
                            drawn = (rest, cpu);
                        }
                        news.then_some(song)
                    }
                    // A pane the kernel draws, and the meters in one, change
                    // as often as the song moves while it plays: drawn at
                    // the same pace.
                    (name, _) if name == "scene.patch" || name == "scene.live" => Some(true),
                    (name, _) => (name != "audio.frame").then_some(false),
                };
                if sender.send(event).is_err() {
                    break;
                }
                match news {
                    Some(true) if woken.elapsed() < song_frame => {
                        waiting.get_or_insert(woken + song_frame);
                    }
                    Some(_) => {
                        waiting = None;
                        woken = Instant::now();
                        wake();
                    }
                    None => {}
                }
            }
            // The kernel went away: the window must see that too.
            wake();
        });
    }

    pub fn call(&mut self, method: &str, params: Value) -> Result<Value> {
        self.connection.call(method, params).map_err(|err| {
            // Lua errors carry a traceback; the first line says what happened.
            let text = err.to_string();
            anyhow!("{}", text.lines().next().unwrap_or(&text))
        })
    }

    /// Run Lua in the kernel with `args` as `...`.
    pub fn eval(&mut self, code: &str, args: Value) -> Result<Value> {
        let mut params = vec![json!(code)];
        params.extend(args.as_array().cloned().unwrap_or_default());
        self.call("eval", Value::Array(params))
    }

    /// Start playing the kernel's sound here, or stop.
    pub fn toggle_listening(&mut self) -> Result<()> {
        if self.player.take().is_some() {
            return self.connection.notify("monitor.unlisten", json!([]));
        }
        let player = paw_listen::Player::device()?;
        self.call("monitor.listen", json!([]))?;
        self.player = Some(player);
        Ok(())
    }

    /// The state to draw, in the shape `paw.frontend.state` gives it: what
    /// moves on its own always, and the project's parts (`project`,
    /// `tracks`, `clips`, ...) only when one of them has changed since the
    /// last time this was asked. None when nothing has arrived since.
    pub fn state(&mut self) -> Result<Option<Value>> {
        let mut any = false;
        loop {
            match self.connection.events.try_recv() {
                Ok((name, mut payload)) if name == "frontend.state" => {
                    if let Some(Value::Object(parts)) =
                        payload.as_object_mut().and_then(|p| p.remove("sections"))
                    {
                        self.fresh = true;
                        self.fresh_kinds |= parts.contains_key("kinds");
                        self.sections.extend(parts);
                    }
                    self.tick = payload;
                    any = true;
                }
                Ok((name, payload)) if name == "scene.patch" => self.patches.push(payload),
                Ok((name, payload)) if name == "scene.live" => self.live = Some(payload),
                Ok((name, payload)) if name == "audio.frame" => {
                    if let Some(player) = &self.player {
                        let _ = player.push(&payload);
                    }
                }
                Ok((name, _)) if name == "monitor.toggle" => {
                    if let Err(err) = self.toggle_listening() {
                        let message = format!("cannot play the instance's sound here: {err:#}");
                        let _ = self.eval("paw.notify(..., 'error')", json!([message]));
                    }
                }
                Ok(_) => {}
                Err(mpsc::TryRecvError::Empty) => break,
                Err(mpsc::TryRecvError::Disconnected) => bail!("the kernel went away"),
            }
        }
        if !any {
            return Ok(None);
        }
        let mut state = self.tick.clone();
        if std::mem::take(&mut self.fresh)
            && let Some(state) = state.as_object_mut()
        {
            let part = |name: &str| self.sections.get(name).cloned().unwrap_or(Value::Null);
            // The bar and beat lines travel apart from the rest of the project.
            let mut project = part("project");
            if project.is_object() {
                project["lines"] = part("lines");
            }
            state.insert("project".into(), project);
            for name in ["tracks", "clips"] {
                state.insert(name.into(), part(name));
            }
            state.insert("selected".into(), part("view")["selected"].clone());
            state.insert("cursor".into(), part("view")["cursor"].clone());
            if std::mem::take(&mut self.fresh_kinds) {
                state.insert("kinds".into(), part("kinds"));
            }
        }
        Ok(Some(state))
    }
}

/// Start a kernel without a UI and connect to it.
pub fn start_kernel(args: &[String]) -> Result<(Client, Child)> {
    let runtime = paw_proto::dirs::runtime().unwrap_or_else(std::env::temp_dir);
    let socket = runtime.join(format!("paw-gui-{}.sock", std::process::id()));
    // The `paw` binary beside this one, else whichever is on the path.
    let beside = std::env::current_exe()
        .ok()
        .and_then(|exe| Some(exe.parent()?.join("paw")));
    let binary = std::env::var_os("PAW_BIN")
        .map(PathBuf::from)
        .or(beside.filter(|path| path.is_file()))
        .unwrap_or_else(|| PathBuf::from("paw"));
    let mut child = Command::new(&binary);
    child
        .arg("--headless")
        .arg("--listen")
        .arg(&socket)
        .args(args)
        .stdin(Stdio::null());
    // If this program dies without saying goodbye, the kernel must not be left
    // running with the audio device.
    // SAFETY: the closure runs between fork and exec and calls only `prctl`, which is
    // async-signal-safe; it takes no lock and does not allocate.
    unsafe {
        child.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
            Ok(())
        });
    }
    let mut child = child
        .spawn()
        .with_context(|| format!("starting {}", binary.display()))?;
    // The first start can take a while: it looks through every installed plugin.
    let deadline = Instant::now() + Duration::from_secs(120);
    loop {
        if let Ok(client) = Client::connect(&socket, true) {
            return Ok((client, child));
        }
        if let Some(status) = child.try_wait()? {
            bail!("the kernel stopped before it was ready ({status})");
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            bail!("the kernel did not open its socket");
        }
        std::thread::sleep(Duration::from_millis(30));
    }
}
