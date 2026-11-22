//! The kernel: one thread that owns the session and the Lua state and takes
//! turns handling input, RPC calls and timers.
//!
//! Almost everything a user sees is Lua. The kernel only calls a handful of
//! entry points in `paw._kernel` (`key`, `mouse`, `settle`, `render`, `rpc`, …)
//! and exposes `paw.api` for Lua to call back into.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender, channel};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow, bail};
use paw_engine::backend::BackendOptions;
use paw_engine::Registry;
use include_dir::{Dir, include_dir};
use mlua::{FromLuaMulti, Function, IntoLuaMulti, Lua, LuaSerdeExt, Table, Value as LuaValue};
use serde_json::Value;

use crate::api::{self, Env, Shared};
use crate::grid::{Caps, Color, Grid, Highlights, Style};
use crate::remote::{self, RemoteFrontend};
use crate::rpc::{ClientId, Clients};
use crate::session::Session;
use crate::watchdog::Watchdog;

/// How often plugins get their turn on the main thread. Their editors are
/// drawn from here, so this is also their frame rate.
const IDLE_PERIOD: Duration = Duration::from_millis(16);

static RUNTIME: Dir = include_dir!("$CARGO_MANIFEST_DIR/../../runtime/lua");

/// The same modules as bytecode (made by build.rs).
mod bytecode {
    include!(concat!(env!("OUT_DIR"), "/bytecode.rs"));
}

/// The text of a file of the runtime built into the program, by its path
/// under `runtime`: `lua/paw/util.tl`, or a declaration of Teal,
/// `types/paw.d.tl`.
pub(crate) fn runtime_file(path: &str) -> Option<&'static str> {
    if let Some(rel) = path.strip_prefix("types/") {
        let i = bytecode::DECLARATIONS.binary_search_by_key(&rel, |(p, _)| p).ok()?;
        return Some(bytecode::DECLARATIONS[i].1);
    }
    RUNTIME.get_file(path.strip_prefix("lua/")?)?.contents_utf8()
}

/// A hash of the Teal declarations and modules built into the program.
pub(crate) fn teal_types() -> &'static str {
    bytecode::TEAL_TYPES
}

#[derive(Clone, Debug)]
pub enum InputEvent {
    /// A key in Neovim notation: `a`, `<C-s>`, `<Space>`, `<S-Tab>`.
    Key(String),
    Mouse {
        kind: String,
        button: String,
        x: u16,
        y: u16,
        mods: String,
        /// Where the pointer is in pixels, from the screen's corner, when
        /// the terminal says so (mode 1016).
        pixel: Option<(u16, u16)>,
    },
    Resize(u16, u16),
    /// A cell has another size in pixels (the terminal's font changed).
    CellSize(u16, u16),
    Paste(String),
    /// The terminal or the window got the focus of the desktop (true) or
    /// lost it (false): mode 1004, or the window's focus event.
    Focus(bool),
}

pub enum KernelMsg {
    Input(InputEvent),
    /// A message that arrived at a MIDI port.
    /// MIDI came in: it waits in `Shared::midi_in`.
    Midi,
    /// A helper process started with pipes wrote something or ended.
    Output,
    Rpc {
        /// The connection the call came over, or 0 for none.
        client: ClientId,
        method: String,
        params: Value,
        reply: crate::rpc::Reply,
    },
    /// A connection closed: whatever it had asked to be sent stops.
    Gone(ClientId),
}

/// Something that shows the grid to a person.
pub trait Frontend {
    fn present(&mut self, grid: &Grid, cursor: Option<(u16, u16)>) -> Result<()>;
}

pub struct KernelOpts {
    pub backend: BackendOptions,
    /// Every kind of device that can be created: the built-in ones and plugins.
    pub registry: Registry,
    pub config_dir: PathBuf,
    pub runtime_dir: Option<PathBuf>,
    pub clean: bool,
    /// Running a script (`-l`), not a session somebody works in.
    pub scripted: bool,
    pub argv: Vec<String>,
}

pub struct Kernel {
    shared: Rc<Shared>,
    lua: Lua,
    tx: Sender<KernelMsg>,
    rx: Receiver<KernelMsg>,
    /// Everything showing the grid: the program's own terminal (as
    /// connection 0) and the terminals attached over connections, each
    /// drawn from its own seat at its own size.
    frontends: Vec<(ClientId, Box<dyn Frontend>)>,
    /// Files being sent over connections (`file.*`).
    uploads: crate::upload::Uploads,
    /// What is played, sent to connections that listen (`monitor.*`).
    monitor: crate::monitor::Monitor,
    /// The frame each terminal was shown last, by connection (0 for the
    /// program's own), for drawing only its live parts again.
    kept: HashMap<ClientId, Kept>,
}

/// A terminal's last frame and where its cursor was.
#[derive(Default)]
struct Kept {
    grid: Grid,
    cursor: Option<(u16, u16)>,
}

impl Drop for Kernel {
    fn drop(&mut self) {
        self.shared.watchdog.detach();
    }
}

impl Kernel {
    pub fn new(opts: KernelOpts) -> Result<Self> {
        // The devices chosen on this machine before, unless the command line
        // names others.
        let device_file = crate::audio::file();
        let mut backend = opts.backend.clone();
        crate::audio::apply(&mut backend, &crate::audio::load(&device_file));
        let mut session = Session::new(&backend, opts.registry)?;
        session.device_file = Some(device_file);
        session.set_bakes(Some(crate::bake::Store::user()));
        let (tx, rx) = channel();
        // MIDI input goes straight to the engine; scripts hear of it here.
        // It waits in a queue of its own, which a script that waits empties
        // too (`paw.wait`): the message only wakes the loop.
        let midi_tx = tx.clone();
        let midi_in = Arc::new(Mutex::new(VecDeque::new()));
        let heard = midi_in.clone();
        session.set_midi_tap(Box::new(move |port, kind| {
            heard.lock().unwrap().push_back((port, kind));
            let _ = midi_tx.send(KernelMsg::Midi);
        }));
        let started = Instant::now();
        let shared = Rc::new(Shared {
            session: RefCell::new(session),
            grid: RefCell::new(Grid::new(80, 24)),
            sizes: RefCell::new(HashMap::new()),
            caps: RefCell::new(HashMap::new()),
            seat: Cell::new(0),
            highlights: RefCell::new(Highlights::default()),
            dirty: Cell::new(true),
            live_dirty: Cell::new(false),
            frames: Cell::new([0; 3]),
            snapshot: RefCell::new(None),
            redraws: Cell::new(0),
            attached: Cell::new(false),
            cursor: Cell::new(None),
            timers: RefCell::new(Vec::new()),
            next_timer: Cell::new(0),
            state: RefCell::new(HashMap::new()),
            quit: Cell::new(None),
            reload: Cell::new(false),
            log: RefCell::new(VecDeque::new()),
            io: RefCell::new(Default::default()),
            started,
            clients: Clients::default(),
            midi_in,
            input_from: Cell::new(0),
            detach: RefCell::new(Vec::new()),
            watchdog: Watchdog::new(started),
            scenes: Default::default(),
            env: Env {
                config_dir: opts.config_dir,
                runtime_dir: opts.runtime_dir,
                clean: opts.clean,
                scripted: opts.scripted,
                argv: opts.argv,
            },
        });
        // What a helper writes waits with it; the message only wakes the loop.
        let output_tx = Mutex::new(tx.clone());
        shared.io.borrow_mut().on_output(Arc::new(move || {
            let _ = output_tx.lock().unwrap().send(KernelMsg::Output);
        }));
        let monitor = crate::monitor::Monitor::new(shared.clients.clone());
        Ok(Self {
            shared,
            lua: Lua::new(),
            tx,
            rx,
            frontends: Vec::new(),
            uploads: Default::default(),
            monitor,
            kept: HashMap::new(),
        })
    }

    /// A handle for other threads to send input and RPC calls to the kernel.
    pub fn sender(&self) -> Sender<KernelMsg> {
        self.tx.clone()
    }

    /// Show the screen on a frontend of the given size.
    pub fn attach(&mut self, frontend: Box<dyn Frontend>, width: u16, height: u16) {
        self.shared.grid.borrow_mut().resize(width, height);
        self.shared.sizes.borrow_mut().insert(0, (width, height));
        self.shared.attached.set(true);
        self.frontends.push((0, frontend));
    }

    /// Say what the program's own terminal can show besides cells.
    pub fn set_caps(&mut self, caps: Caps) {
        self.shared.caps.borrow_mut().insert(0, caps);
    }

    /// Make it `client`'s turn: what happens next happens in its seat (the
    /// instance's when it has none of its own).
    fn enter(&self, client: ClientId) {
        self.shared.seat.set(client);
        if let Err(err) = self.call::<()>("seat", client) {
            self.report("seat", err);
        }
    }

    /// A terminal's keys, pointer and size, in its own seat.
    fn input(&mut self, client: ClientId, event: InputEvent) {
        self.enter(client);
        let result = match event {
            InputEvent::Key(key) => self.call::<()>("key", key),
            InputEvent::Paste(text) => self.call::<()>("paste", text),
            InputEvent::Mouse {
                kind,
                button,
                x,
                y,
                mods,
                pixel,
            } => (|| {
                let event = self.lua.create_table()?;
                event.set("kind", kind)?;
                event.set("button", button)?;
                event.set("x", x)?;
                event.set("y", y)?;
                event.set("mods", mods)?;
                if let Some((px, py)) = pixel {
                    event.set("px", px)?;
                    event.set("py", py)?;
                }
                self.call::<()>("mouse", event)
            })(),
            InputEvent::Resize(width, height) => {
                self.shared.sizes.borrow_mut().insert(client, (width, height));
                self.shared.grid.borrow_mut().resize(width, height);
                self.call::<()>("resize", (width, height))
            }
            InputEvent::CellSize(width, height) => {
                if let Some(caps) = self.shared.caps.borrow_mut().get_mut(&client) {
                    caps.cell = (width, height);
                }
                Ok(())
            }
            InputEvent::Focus(on) => self.call::<()>("focus", on),
        };
        if let Err(err) = result {
            self.report("input", err);
        }
        self.shared.dirty.set(true);
    }

    /// The connections open on the control socket, to serve them with and
    /// to push events to.
    pub fn clients(&self) -> Clients {
        self.shared.clients.clone()
    }

    /// The calls that are the kernel's own business rather than Lua's: a
    /// connection becoming a terminal, typing into it, and leaving.
    fn remote_ui(&mut self, client: ClientId, method: &str, params: &Value) -> Result<Value> {
        match method {
            "ui.attach" => {
                let size = |v: &Value, default| v.as_u64().map_or(default, |n| n.clamp(1, 1000) as u16);
                let (width, height) = (size(&params[0], 80), size(&params[1], 24));
                self.frontends.retain(|(id, _)| *id != client);
                let frontend = RemoteFrontend::new(client, self.shared.clients.clone());
                // What its terminal can show: without a word, cells only.
                self.shared.caps.borrow_mut().insert(client, Caps::from_json(&params[2]));
                self.frontends.push((client, Box::new(frontend)));
                self.shared.attached.set(true);
                // A seat of its own: its own cursor, mode and selection.
                if let Err(err) = self.call::<()>("seat_open", (client, "terminal")) {
                    self.report("seat_open", err);
                }
                self.input(client, InputEvent::Resize(width, height));
                Ok(Value::Bool(true))
            }
            "ui.input" => {
                if !self.frontends.iter().any(|(id, _)| *id == client) {
                    bail!("`ui.attach` first");
                }
                let event = remote::input_of(&params[0]).context("not an input event")?;
                // Lua may ask which terminal a key came from (`:detach`).
                self.shared.input_from.set(client);
                self.input(client, event);
                self.shared.input_from.set(0);
                Ok(Value::Null)
            }
            "ui.detach" => {
                self.detach(client);
                Ok(Value::Bool(true))
            }
            _ => bail!("no method `{method}`"),
        }
    }

    /// Stop showing the screen to a connection.
    fn detach(&mut self, client: ClientId) {
        let before = self.frontends.len();
        self.frontends.retain(|(id, _)| *id != client);
        self.kept.remove(&client);
        if self.frontends.len() != before {
            self.shared.clients.push(client, "ui.detached", &Value::Null);
            self.shared.sizes.borrow_mut().remove(&client);
            self.shared.caps.borrow_mut().remove(&client);
            self.enter(0);
            if let Err(err) = self.call::<()>("seat_close", (client, "terminal")) {
                self.report("seat_close", err);
            }
        }
        if self.frontends.is_empty() {
            self.shared.attached.set(false);
        }
    }

    /// Start a fresh Lua state and run the runtime, the user's configuration
    /// and their extensions in it. The session is untouched.
    pub fn boot(&mut self) -> Result<()> {
        self.shared.timers.borrow_mut().clear();
        // Extensions get the whole standard library, including `ffi` and `debug`.
        // SAFETY: the kernel's own Lua, as trusted as a user's extension; it is used only on
        // this thread, and the watchdog is detached from the old state before the new one
        // takes over.
        let lua = unsafe { Lua::unsafe_new() };
        // In a BrowserPod pod the Lua is PUC Lua 5.2: LuaJIT's globals first.
        #[cfg(target_vendor = "browserpod")]
        lua.load(include_str!("../../../runtime/lua/paw/portable.lua"))
            .set_name("@runtime/lua/paw/portable.lua")
            .exec()
            .map_err(lua_error)?;
        api::install(&lua, &self.shared).map_err(lua_error)?;
        install_loader(&lua, &self.shared.env).map_err(lua_error)?;
        // The Lua 5.3 library that Teal declares and its compiled code calls
        // (`math.type`, `table.unpack`, `utf8`, `bit32`...), before the
        // runtime and the extensions: runtime/lua/paw/compat.tl.
        lua.load("require('paw.compat')")
            .set_name("=compat")
            .exec()
            .map_err(lua_error)?;
        // The old state must not be interrupted once it is gone.
        self.shared.watchdog.detach();
        self.lua = lua;
        self.shared.watchdog.attach(&self.lua).map_err(lua_error)?;
        self.lua
            .load("require('paw')")
            .set_name("=boot")
            .exec()
            .map_err(lua_error)?;
        self.call::<()>("startup", ()).map_err(lua_error)?;
        // A reload keeps the terminals attached, each in a seat of its own.
        for (client, _) in &self.frontends {
            if *client != 0 {
                self.call::<()>("seat_open", (*client, "terminal")).map_err(lua_error)?;
            }
        }
        self.settle();
        self.shared.dirty.set(true);
        // Loading the runtime frees many megabytes that the C library keeps
        // for later: give them back to the system.
        #[cfg(target_env = "gnu")]
        // SAFETY: malloc_trim takes an integer and only returns free memory to the system.
        unsafe {
            libc::malloc_trim(0);
        }
        Ok(())
    }

    /// Call one of the entry points the Lua runtime registers in `paw._kernel`.
    fn call<R: FromLuaMulti>(&self, name: &str, args: impl IntoLuaMulti) -> mlua::Result<R> {
        let paw: Table = self.lua.globals().get("paw")?;
        let kernel: Table = paw.get("_kernel")?;
        kernel.get::<Function>(name)?.call(args)
    }

    fn report(&self, what: &str, err: mlua::Error) {
        let line = format!("{what}: {err}");
        if !self.shared.attached.get() {
            eprintln!("{line}");
        }
        self.shared.log(line);
    }

    /// Run a Lua file with `...` set to `args`.
    pub fn run_file(&mut self, path: &Path, args: Vec<String>) -> Result<()> {
        let code =
            std::fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
        let name = format!("@{}", path.display());
        // As Neovim's `-l` and the `lua` program do: `arg[0]` is the
        // script, `arg[1]` on its arguments, besides `...`.
        let set_arg = || -> mlua::Result<()> {
            let arg = self.lua.create_table()?;
            arg.raw_set(0, path.to_string_lossy().into_owned())?;
            for (i, a) in args.iter().enumerate() {
                arg.raw_set(i + 1, a.as_str())?;
            }
            self.lua.globals().set("arg", arg)
        };
        set_arg().map_err(lua_error)?;
        let result = self
            .lua
            .load(code)
            .set_name(name)
            .call::<()>(mlua::Variadic::from_iter(args));
        self.settle();
        result.map_err(lua_error)
    }

    /// Finish a turn: push edits to the engine, deliver the events they
    /// caused, and close the undo step.
    fn settle(&mut self) {
        if let Err(err) = self.call::<()>("settle", ()) {
            self.report("settle", err);
        }
        self.shared.session.borrow_mut().checkpoint();
    }

    fn handle(&mut self, msg: KernelMsg) {
        match msg {
            KernelMsg::Input(event) => self.input(0, event),
            KernelMsg::Midi => self.shared.hear_midi(),
            KernelMsg::Output => self.shared.hear_output(),
            KernelMsg::Rpc {
                client,
                method,
                params,
                reply,
            } => {
                let result = if method.starts_with("ui.") {
                    self.remote_ui(client, &method, &params)
                } else if method.starts_with("file.") {
                    let dir = self.shared.session.borrow().media_dir();
                    self.uploads.call(client, &method, &params, &dir)
                } else if method.starts_with("monitor.") {
                    let mut session = self.shared.session.borrow_mut();
                    self.monitor.call(client, &method, &mut session)
                } else {
                    self.enter(client);
                    // A command run over a connection may answer it (`:upload`, `:listen`).
                    self.shared.input_from.set(client);
                    let result = (|| {
                        let params = api::to_lua(&self.lua, &params)?;
                        let value: LuaValue = self.call("rpc", (method, params, client))?;
                        self.lua.from_value::<Value>(value)
                    })()
                    .map_err(|err| anyhow!(told(&err)));
                    self.shared.input_from.set(0);
                    result
                };
                // The one place an error becomes the text a client sees.
                let _ = reply.send(result.map_err(|err| format!("{err:#}")));
            }
            KernelMsg::Gone(client) => {
                self.detach(client);
                self.uploads.closed(client);
                self.monitor.closed(client, &mut self.shared.session.borrow_mut());
                if let Err(err) = self.call::<()>("rpc_closed", client) {
                    self.report("rpc_closed", err);
                }
            }
        }
        self.enter(0);
        // A terminal that asked to leave (`:detach`) is let go.
        let leaving: Vec<ClientId> = self.shared.detach.borrow_mut().drain(..).collect();
        for client in leaving {
            self.detach(client);
        }
    }

    fn fire_timers(&mut self) {
        for key in api::due_timers(&self.shared) {
            let func = self.lua.registry_value::<mlua::Function>(&key);
            if let Err(err) = func.and_then(|func| self.call::<()>("timer", func)) {
                self.report("timer", err);
            }
        }
    }

    fn render(&mut self) {
        // Only the live parts, unless something else asked for a frame.
        let live_only = !self.shared.dirty.get();
        self.shared.dirty.set(false);
        self.shared.live_dirty.set(false);
        if self.frontends.is_empty() {
            return;
        }
        let mut gone = Vec::new();
        for index in 0..self.frontends.len() {
            let client = self.frontends[index].0;
            // Each terminal keeps the frame it was shown last, and is drawn
            // from its own seat, at its own size.
            let (width, height) = self.shared.sizes.borrow().get(&client).copied().unwrap_or_else(|| {
                let grid = self.shared.grid.borrow();
                (grid.width, grid.height)
            });
            let mut kept = self.kept.remove(&client).unwrap_or_else(|| Kept { grid: Grid::new(width, height), cursor: None });
            if (kept.grid.width, kept.grid.height) != (width, height) {
                kept.grid.resize(width, height);
            }
            std::mem::swap(&mut *self.shared.grid.borrow_mut(), &mut kept.grid);
            self.enter(client);
            let mut changed = true;
            let mut drawn_live = false;
            let can_live = {
                let grid = self.shared.grid.borrow();
                live_only && !grid.live.is_empty() && grid.surfaces.is_empty()
            };
            if can_live {
                self.shared.cursor.set(kept.cursor);
                match api::render_live(&self.lua, &self.shared) {
                    Ok(done) => drawn_live = done,
                    Err(err) => self.report("render_live", err),
                }
                if drawn_live {
                    changed = self.shared.grid.borrow().live_changed();
                }
            }
            let mut frames = self.shared.frames.get();
            if drawn_live {
                frames[if changed { 1 } else { 2 }] += 1;
            } else {
                frames[0] += 1;
                self.shared.grid.borrow_mut().clear();
                self.shared.cursor.set(None);
                let result = api::render(&self.lua, &self.shared);
                if let Err(err) = result {
                    // The Lua UI is broken, so the kernel draws the reason itself.
                    let mut grid = self.shared.grid.borrow_mut();
                    grid.live.clear();
                    let style = Style {
                        fg: Some(Color::Indexed(9)),
                        ..Style::default()
                    };
                    let clip = grid.rect();
                    for (row, line) in format!("render failed: {err}").lines().enumerate() {
                        grid.text(clip, 0, row as i32, line, style);
                    }
                }
            }
            self.shared.frames.set(frames);
            if changed {
                let shared = self.shared.clone();
                let (grid, cursor) = (shared.grid.borrow(), shared.cursor.get());
                if let Err(err) = self.frontends[index].1.present(&grid, cursor) {
                    self.shared.log(format!("frontend: {err:#}"));
                    // A terminal at the end of a connection that has closed.
                    if client != 0 {
                        gone.push(client);
                    }
                }
            }
            kept.cursor = self.shared.cursor.get();
            std::mem::swap(&mut *self.shared.grid.borrow_mut(), &mut kept.grid);
            self.kept.insert(client, kept);
        }
        self.enter(0);
        for client in gone {
            self.detach(client);
        }
    }

    /// Take turns until something asks to quit. Returns the exit code.
    pub fn run(&mut self) -> Result<i32> {
        let mut last_idle = Instant::now();
        // What the start made (the runtime, the project opened, the
        // expressions run) is shown now, not after the first message or
        // timer, which can be a second away.
        if self.shared.dirty.get() {
            self.render();
        }
        loop {
            let next_timer = self.shared.timers.borrow().iter().map(|t| t.due).min();
            // Hosted plugins need regular attention on this thread.
            let next_idle = self
                .shared
                .session
                .borrow()
                .needs_idle()
                .then(|| last_idle + IDLE_PERIOD);
            let msg = match next_timer.into_iter().chain(next_idle).min() {
                Some(due) => match self
                    .rx
                    .recv_timeout(due.saturating_duration_since(Instant::now()))
                {
                    Ok(msg) => Some(msg),
                    Err(RecvTimeoutError::Timeout) => None,
                    Err(RecvTimeoutError::Disconnected) => {
                        return Err(anyhow!("kernel channel closed"));
                    }
                },
                None => Some(self.rx.recv()?),
            };
            if let Some(msg) = msg {
                self.handle(msg);
                // Take whatever else is already waiting before drawing.
                while let Ok(msg) = self.rx.try_recv() {
                    self.handle(msg);
                }
            }
            self.fire_timers();
            if last_idle.elapsed() >= IDLE_PERIOD {
                self.shared.session.borrow_mut().idle();
                last_idle = Instant::now();
            }
            self.settle();
            self.monitor.keep_fed(&mut self.shared.session.borrow_mut());

            if self.shared.reload.replace(false)
                && let Err(err) = self.boot()
            {
                self.shared.log(format!("reload failed: {err:#}"));
                if !self.shared.attached.get() {
                    eprintln!("reload failed: {err:#}");
                }
            }
            if let Some(code) = self.shared.quit.get() {
                // Scripts get to tidy up: an `exit` event.
                if let Err(err) = self.call::<()>("exit", ()) {
                    self.report("exit", err);
                }
                return Ok(code);
            }
            if self.shared.dirty.get() || self.shared.live_dirty.get() {
                self.render();
            }
        }
    }

    /// Run Lua code with `...` set to `args`, as its own turn.
    pub fn eval(&mut self, code: &str, args: &[&str]) -> Result<()> {
        let args = mlua::Variadic::from_iter(args.iter().map(|a| a.to_string()));
        let result = self.lua.load(code).set_name("=eval").call::<()>(args);
        self.settle();
        result.map_err(lua_error)
    }

    pub fn exit_code(&self) -> Option<i32> {
        self.shared.quit.get()
    }
}

fn lua_error(err: mlua::Error) -> anyhow::Error {
    anyhow!("{err}")
}

/// Let `require` find the runtime modules built into the binary, and the
/// user's own modules ahead of them.
fn install_loader(lua: &Lua, env: &Env) -> mlua::Result<()> {
    let package: Table = lua.globals().get("package")?;
    let mut paths = Vec::new();
    let mut add = |dir: &Path| {
        paths.push(format!("{}/?.lua", dir.display()));
        paths.push(format!("{}/?/init.lua", dir.display()));
    };
    if !env.clean {
        add(&env.config_dir.join("lua"));
    }
    if let Some(runtime) = &env.runtime_dir {
        add(&runtime.join("lua"));
    }
    paths.push(package.get::<String>("path")?);
    package.set("path", paths.join(";"))?;

    // Lua's own `loadstring`, taken before anything can replace it: `mlua`
    // loads no bytecode in its safe mode, and this bytecode is the program's.
    let loadstring: Function = lua.globals().get("loadstring")?;
    let embedded = lua.create_function(move |lua, name: String| {
        let path = name.replace('.', "/");
        let candidates = [
            format!("{path}.lua"),
            format!("{path}/init.lua"),
            format!("{path}.tl"),
            format!("{path}/init.tl"),
        ];
        for candidate in candidates {
            // The module compiled when the program was built (build.rs): it
            // loads many times quicker than its source is parsed.
            if let Ok(i) = bytecode::BYTECODE.binary_search_by_key(&candidate.as_str(), |(p, _)| p) {
                let code = lua.create_string(bytecode::BYTECODE[i].1)?;
                if let Ok(LuaValue::Function(chunk)) = loadstring.call::<LuaValue>(code) {
                    return Ok(LuaValue::Function(chunk));
                }
            }
            // A Teal module: the Lua the build made of it.
            if candidate.ends_with(".tl") {
                if let Ok(i) = bytecode::TEAL.binary_search_by_key(&candidate.as_str(), |(p, _)| p) {
                    let chunk = lua
                        .load(bytecode::TEAL[i].1)
                        .set_name(format!("@runtime/lua/{candidate}"));
                    return Ok(LuaValue::Function(chunk.into_function()?));
                }
                continue;
            }
            if let Some(file) = RUNTIME.get_file(&candidate) {
                let chunk = lua
                    .load(file.contents())
                    .set_name(format!("@runtime/lua/{candidate}"));
                return Ok(LuaValue::Function(chunk.into_function()?));
            }
        }
        Ok(LuaValue::String(lua.create_string(format!(
            "\n\tno built-in module '{name}'"
        ))?))
    })?;
    // After the path searcher, so files on disk can replace built-in modules.
    package.get::<Table>("loaders")?.push(embedded)
}

/// What went wrong in a call on the control socket, as its caller is told
/// it (docs/reference/protocol.md): the message alone, without the way it came
/// through Lua and Rust.
fn told(err: &mlua::Error) -> String {
    let whole = match err {
        mlua::Error::CallbackError { cause, .. } => return told(cause),
        mlua::Error::RuntimeError(message) => message.clone(),
        other => other.to_string(),
    };
    whole.split("\nstack traceback:").next().unwrap_or_default().trim_end().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every module of the runtime is in the program as bytecode too, and
    /// the bytecode loads: otherwise each start parses its source again.
    #[test]
    fn the_runtime_is_built_in_as_bytecode() {
        fn walk(dir: &Dir<'_>, out: &mut Vec<String>) {
            for file in dir.files() {
                if file.path().extension().is_some_and(|e| e == "lua" || e == "tl") {
                    out.push(file.path().to_string_lossy().into_owned());
                }
            }
            for sub in dir.dirs() {
                walk(sub, out);
            }
        }
        let mut sources = Vec::new();
        walk(&RUNTIME, &mut sources);
        sources.sort();
        let compiled: Vec<&str> = bytecode::BYTECODE.iter().map(|(p, _)| *p).collect();
        assert_eq!(compiled, sources);
        let teal: Vec<&str> = bytecode::TEAL.iter().map(|(p, _)| *p).collect();
        let tl_sources: Vec<&str> = sources.iter().map(String::as_str).filter(|p| p.ends_with(".tl")).collect();
        assert_eq!(teal, tl_sources, "every Teal module is in the program as Lua");
        let lua = Lua::new();
        let loadstring: Function = lua.globals().get("loadstring").unwrap();
        for (path, code) in bytecode::BYTECODE {
            let loaded: LuaValue = loadstring.call(lua.create_string(code).unwrap()).unwrap();
            assert!(matches!(loaded, LuaValue::Function(_)), "{path} loads");
        }
    }
}
