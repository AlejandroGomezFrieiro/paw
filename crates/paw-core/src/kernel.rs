//! The kernel: one thread that owns the session and the Lua state and takes
//! turns handling input, RPC calls and timers.
//!
//! Almost everything a user sees is Lua. The kernel only calls a handful of
//! entry points in `paw._kernel` (`key`, `mouse`, `settle`, `render`, `rpc`, …)
//! and exposes `paw.api` for Lua to call back into. One turn of its loop
//! is [`reactor::Reactor::turn`].

mod reactor;
#[cfg(test)]
mod turn_tests;

pub(crate) use reactor::{Desk, Reactor};

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::mpsc::{SendError, Sender, channel};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use anyhow::{Context, Result, anyhow};
use paw_engine::backend::BackendOptions;
use paw_engine::Registry;
use include_dir::{Dir, include_dir};
use mlua::{Function, Lua, Table, Value as LuaValue};
use serde_json::Value;

use crate::api::{self, Env, Shared};
use crate::clock::{Agenda, Clock, ScheduleTime};
use crate::doorbell::{Waiter, Woken};
use crate::grid::{Caps, Grid, Highlights};
use crate::rpc::{ClientId, Clients};
use crate::session::Session;
use crate::startuptime;
use crate::watchdog::Watchdog;

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

/// The sending end of the kernel's channel, for other threads: a message
/// sent wakes the loop. Cheap to clone.
#[derive(Clone)]
pub struct KernelSender {
    tx: Sender<KernelMsg>,
    bell: paw_engine::Bell,
}

impl KernelSender {
    /// Send a message to the kernel and wake its loop. An error gives the
    /// message back when the kernel is gone.
    pub fn send(&self, msg: KernelMsg) -> Result<(), SendError<KernelMsg>> {
        self.tx.send(msg)?;
        self.bell.ring();
        Ok(())
    }
}

/// Something that shows the grid to a person.
pub trait Frontend {
    fn present(&mut self, grid: &Grid, cursor: Option<(u16, u16)>) -> Result<()>;

    /// Forget what the screen shows: the next [`present`](Self::present)
    /// writes every cell again, over text that another program wrote on
    /// the terminal (`paw.api.ui_repaint`). A frontend that keeps no copy
    /// of the screen has nothing to forget.
    fn repaint(&mut self) {}
}

pub struct KernelOpts {
    pub backend: BackendOptions,
    /// Every kind of device that can be created: the built-in ones and plugins.
    pub registry: Registry,
    pub config_dir: PathBuf,
    pub runtime_dir: Option<PathBuf>,
    /// The user's home folder, which `~/` names in a project's files: the
    /// program reads it once at its start (`HOME`). `None` keeps every path
    /// outside a project absolute.
    pub home: Option<PathBuf>,
    /// The user's base directories (data, state, cache, runtime): the
    /// program resolves them once at its start, and the kernel keeps its
    /// files in them.
    pub dirs: paw_proto::dirs::Dirs,
    pub clean: bool,
    /// Running a script (`-l`), not a session somebody works in.
    pub scripted: bool,
    pub argv: Vec<String>,
    /// The schedule clock of the process (`paw --clock`).
    pub clock: Clock,
}

pub struct Kernel {
    shared: Rc<Shared>,
    lua: Lua,
    tx: KernelSender,
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
        let device_file = crate::audio::file(&opts.dirs);
        let mut backend = opts.backend.clone();
        crate::audio::apply(&mut backend, &crate::audio::load(&device_file));
        let mut session = Session::new(&backend, opts.registry)?;
        session.device_file = Some(device_file);
        session.home = crate::session::folder::Home::new(opts.home);
        session.set_bakes(Some(crate::bake::Store::user(&opts.dirs)));
        session.sources.keep_index_in(crate::media::index::LocalIndex::default_file(&opts.dirs));
        session.dirs = opts.dirs;
        session.set_now(opts.clock.now());
        let waiter = Waiter::new().context("the wait of the kernel's loop")?;
        session.set_doorbell(waiter.doorbell().clone());
        let (tx, rx) = channel();
        let tx = KernelSender { tx, bell: waiter.doorbell().bell(Woken::MESSAGES) };
        let clients = Clients::default();
        // MIDI input goes straight to the engine; scripts hear of it here.
        // It waits in a queue of its own, which a script that waits empties
        // too (`paw.wait`): the message only wakes the loop.
        let midi_tx = tx.clone();
        let midi_in = Arc::new(Mutex::new(VecDeque::new()));
        let heard = midi_in.clone();
        session.set_midi_tap(Box::new(move |port, kind| {
            heard.lock().expect("a thread panicked while it held the lock").push_back((port, kind));
            let _ = midi_tx.send(KernelMsg::Midi);
        }));
        #[expect(clippy::disallowed_methods, reason = "paw.api.real_ms and the time limit of Lua measure work from the start")]
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
            kept_cells: RefCell::new(HashMap::new()),
            redraws: Cell::new(0),
            line_redraws: Cell::new(0),
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
            clock: opts.clock,
            rx,
            inbox: RefCell::new(VecDeque::new()),
            turning: Cell::new(false),
            desk: RefCell::new(reactor::Desk::new(clients.clone())),
            clients,
            midi_in,
            input_from: Cell::new(0),
            detach: RefCell::new(Vec::new()),
            watchdog: Watchdog::new(started),
            measures: crate::measure::Running::with_bell(waiter.doorbell().bell(Woken::MEASURES)),
            waiter,
            missed: Cell::new(Woken::empty()),
            missed_wakes: Cell::new(0),
            looked_on_a_tick: Cell::new(false),
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
        let output_tx = tx.clone();
        shared.io.borrow_mut().on_output(Arc::new(move || {
            let _ = output_tx.send(KernelMsg::Output);
        }));
        Ok(Self { shared, lua: Lua::new(), tx })
    }

    /// A handle for other threads to send input and RPC calls to the kernel.
    pub fn sender(&self) -> KernelSender {
        self.tx.clone()
    }

    /// Show the screen on a frontend of the given size.
    pub fn attach(&mut self, frontend: Box<dyn Frontend>, width: u16, height: u16) {
        self.shared.grid.borrow_mut().resize(width, height);
        self.shared.sizes.borrow_mut().insert(0, (width, height));
        self.shared.attached.set(true);
        self.shared.desk.borrow_mut().frontends.push((0, frontend));
    }

    /// Say what the program's own terminal can show besides cells.
    pub fn set_caps(&mut self, caps: Caps) {
        self.shared.caps.borrow_mut().insert(0, caps);
    }

    /// The connections open on the control socket, to serve them with and
    /// to push events to.
    pub fn clients(&self) -> Clients {
        self.shared.clients.clone()
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
        if startuptime::is_on() {
            startuptime::event("Lua state, paw.api");
            // Each module that `require` loads gets a line of its own.
            self.lua
                .load("require('paw.startuptime').wrap()")
                .set_name("=startuptime")
                .exec()
                .map_err(lua_error)?;
        }
        self.lua
            .load("require('paw')")
            .set_name("=boot")
            .exec()
            .map_err(lua_error)?;
        self.reactor().call::<()>("startup", ()).map_err(lua_error)?;
        startuptime::event("startup: views, extensions, configuration");
        // A reload keeps the terminals attached, each in a seat of its own.
        let clients: Vec<ClientId> = self.shared.desk.borrow().frontends.iter().map(|(id, _)| *id).collect();
        for client in clients {
            if client != 0 {
                self.reactor().call::<()>("seat_open", (client, "terminal")).map_err(lua_error)?;
            }
        }
        self.close_turn();
        self.shared.dirty.set(true);
        startuptime::event("runtime ready");
        // Loading the runtime frees many megabytes that the C library keeps
        // for later: give them back to the system.
        #[cfg(target_env = "gnu")]
        // SAFETY: malloc_trim takes an integer and only returns free memory to the system.
        unsafe {
            libc::malloc_trim(0);
        }
        Ok(())
    }

    /// paw's schema of the chain language, as JSON: each kind of device
    /// that the registry has now (with the plugins and the Lua devices of
    /// the extensions), and the kinds of split and modulator.
    pub fn chain_schema(&self) -> String {
        crate::chain_schema::json(&self.shared.session.borrow())
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
        self.reactor().begin(self.shared.clock.now());
        let result = self
            .lua
            .load(code)
            .set_name(name)
            .call::<()>(mlua::Variadic::from_iter(args));
        self.close_turn();
        result.map_err(lua_error)
    }

    /// The kernel's state and Lua state, for one piece of work.
    fn reactor(&self) -> Reactor<'_> {
        Reactor::new(&self.shared, &self.lua)
    }

    /// One turn of the loop at `now` ([`Reactor::turn`]): the one turn that
    /// `run`, `paw.api.step` and `paw.api.wait` take.
    pub fn turn(&mut self, now: ScheduleTime) -> Agenda {
        self.reactor().turn(now)
    }

    /// Finish a turn that ran Lua outside the loop (the start, `-e`, a
    /// script): push the edits, deliver the events, close the undo step.
    fn close_turn(&mut self) {
        self.reactor().close_turn();
    }

    /// Take turns until something asks to quit. Returns the exit code.
    pub fn run(&mut self) -> Result<i32> {
        // What the start made (the runtime, the project opened, the
        // expressions run) is shown now, not after the first message or
        // timer, which can be a second away.
        if self.shared.dirty.get() {
            self.reactor().render();
        }
        let shown = if self.shared.desk.borrow().frontends.is_empty() { "ready, no screen" } else { "first frame" };
        self.startup_done(shown);
        let mut agenda = self.reactor().agenda(self.shared.clock.now());
        loop {
            // Sleep until a message, a due time or the tick of the upkeep.
            // A manual clock moves only in a script's wait: here a timer in
            // its future comes back to this loop with nothing due, which
            // costs one turn.
            self.reactor().wait(&agenda, self.shared.clock.now(), None)?;
            agenda = self.turn(self.shared.clock.now());
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
                if let Err(err) = self.reactor().call::<()>("exit", ()) {
                    self.reactor().report("exit", err);
                }
                return Ok(code);
            }
            if self.shared.dirty.get() || self.shared.live_dirty.get() {
                self.reactor().render();
            }
        }
    }

    /// The end of the start that `paw --startuptime` times: its last line,
    /// the file written, and `require` as it was. Nothing when the start
    /// was not timed, or after the first time.
    pub fn startup_done(&mut self, label: &str) {
        match startuptime::finish(label) {
            Ok(false) => {}
            Ok(true) => {
                let unwrap = self.lua.load("require('paw.startuptime').unwrap()").set_name("=startuptime").exec();
                if let Err(err) = unwrap {
                    self.reactor().report("startuptime", err);
                }
            }
            Err(err) => {
                let line = format!("--startuptime: cannot write the file: {err}");
                if !self.shared.attached.get() {
                    eprintln!("{line}");
                }
                self.shared.log(line);
            }
        }
    }

    /// Run Lua code with `...` set to `args`, as its own turn.
    pub fn eval(&mut self, code: &str, args: &[&str]) -> Result<()> {
        let args = mlua::Variadic::from_iter(args.iter().map(|a| a.to_string()));
        self.reactor().begin(self.shared.clock.now());
        let result = self.lua.load(code).set_name("=eval").call::<()>(args);
        self.close_turn();
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
