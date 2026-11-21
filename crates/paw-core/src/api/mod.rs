//! `paw.api`: the flat, plain-data interface between the kernel and Lua.
//!
//! Every function here takes and returns numbers, strings and tables, never
//! live objects. The friendly objects in `require("paw")` are Lua wrappers over these, and the
//! RPC socket exposes the same functions to other processes.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use paw_engine::EventKind;
use mlua::serde::SerializeOptions;
use mlua::{Lua, LuaSerdeExt, Table, Value as LuaValue};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::Value;

use crate::grid::{Caps, Grid, Highlights};
use crate::io::Io;
use crate::model::NoteAttr;
use crate::session::Session;
use crate::watchdog::{self, Watchdog};

pub struct Env {
    pub config_dir: PathBuf,
    /// Load the Lua runtime from this directory instead of the built-in copy.
    pub runtime_dir: Option<PathBuf>,
    /// Skip the user's configuration and extensions.
    pub clean: bool,
    pub scripted: bool,
    pub argv: Vec<String>,
}

pub struct Timer {
    pub id: u64,
    pub due: Instant,
    pub repeat: Option<Duration>,
    /// In the registry, not held as a `Function`: each Lua value that Rust
    /// holds takes a slot of a stack that has room for about 8000, and a
    /// script that never lets the timers fire can start more than that.
    pub func: Rc<mlua::RegistryKey>,
}

/// Everything the kernel and the Lua API functions both reach into.
pub struct Shared {
    pub session: RefCell<Session>,
    /// The screen of the seat whose turn it is (see runtime/lua/paw/seats.tl),
    /// as big as that seat's terminal: `sizes`, by connection, 0 for the
    /// program's own.
    pub grid: RefCell<Grid>,
    pub sizes: RefCell<HashMap<u64, (u16, u16)>>,
    /// What each terminal can show besides cells, by connection.
    pub caps: RefCell<HashMap<u64, Caps>>,
    /// The connection whose turn it is (whose seat), 0 for the program's own.
    pub seat: Cell<u64>,
    pub highlights: RefCell<Highlights>,
    /// The screen needs drawing again.
    pub dirty: Cell<bool>,
    /// Only the live parts of the screen need drawing again (the playhead,
    /// the meters, the status line): `paw.api.ui_redraw_live`.
    pub live_dirty: Cell<bool>,
    /// Frames drawn: whole, live parts only, and live parts that changed
    /// nothing and were not sent (`paw.api.ui_frames`).
    pub frames: Cell<[u64; 3]>,
    /// The frame `ui_frame_snapshot` drew last, for tests.
    pub snapshot: RefCell<Option<Grid>>,
    /// How many times a redraw has been asked for: a window showing one
    /// view draws it again only when this has moved.
    pub redraws: Cell<u64>,
    /// A frontend is showing the grid.
    pub attached: Cell<bool>,
    pub cursor: Cell<Option<(u16, u16)>>,
    pub timers: RefCell<Vec<Timer>>,
    pub next_timer: Cell<u64>,
    /// Values that outlive a reload of the Lua state.
    pub state: RefCell<HashMap<String, Value>>,
    pub quit: Cell<Option<i32>>,
    pub reload: Cell<bool>,
    pub log: RefCell<VecDeque<String>>,
    /// Helper processes and sockets that extensions opened.
    pub io: RefCell<Io>,
    pub started: Instant,
    /// The connections on the control socket, for pushing events to them.
    pub clients: crate::rpc::Clients,
    /// The connection whose terminal the input being handled came from, or
    /// whose call is being answered, or 0 for the program's own; and the
    /// connections whose terminals asked to leave, for the kernel to let go
    /// after this turn.
    pub input_from: Cell<u64>,
    /// MIDI that came in from ports and has not been made into `midi.in`
    /// events yet.
    pub midi_in: Arc<Mutex<VecDeque<(u32, EventKind)>>>,
    pub detach: RefCell<Vec<u64>>,
    /// Interrupts Lua that has run past its time limit.
    pub watchdog: Watchdog,
    /// The scenes graphical frontends are sent (`crate::scene`).
    pub scenes: RefCell<crate::scene::Scenes>,
    pub env: Env,
}

impl Shared {
    /// Make `midi.in` events of what came in from ports since last time.
    pub fn hear_midi(&self) {
        loop {
            // Not held while the session works: the port's thread adds to it.
            let Some((port, kind)) = self.midi_in.lock().unwrap().pop_front() else {
                return;
            };
            self.session.borrow_mut().midi_event(port, kind);
        }
    }

    /// Make `proc.output` events of what helper processes have written.
    pub fn hear_output(&self) {
        let arrived = self.io.borrow_mut().arrived();
        let mut session = self.session.borrow_mut();
        for id in arrived {
            session.emit(crate::events::KernelEvent::ProcOutput(crate::events::ProcOutput { id }));
        }
    }

    pub fn log(&self, line: String) {
        let mut log = self.log.borrow_mut();
        if log.len() >= 1000 {
            log.pop_front();
        }
        log.push_back(line);
    }
}

pub trait LuaResult<T> {
    /// Turn an error into a Lua error with the full chain of causes.
    fn lua(self) -> mlua::Result<T>;
}

impl<T> LuaResult<T> for anyhow::Result<T> {
    fn lua(self) -> mlua::Result<T> {
        self.map_err(|err| mlua::Error::runtime(format!("{err:#}")))
    }
}

pub fn to_lua<T: serde::Serialize>(lua: &Lua, value: &T) -> mlua::Result<LuaValue> {
    // JSON null becomes nil, so that `if track.output then` reads naturally.
    let options = SerializeOptions::new()
        .serialize_none_to_null(false)
        .serialize_unit_to_null(false);
    lua.to_value_with(value, options)
}

pub fn from_lua<T: DeserializeOwned>(lua: &Lua, value: LuaValue) -> mlua::Result<T> {
    lua.from_value(value)
}

/// An attribute from Lua: a table of `type` and `data`; nil, false or type
/// 0 for none.
fn attr_from_lua(lua: &Lua, value: LuaValue) -> mlua::Result<Option<NoteAttr>> {
    #[derive(Deserialize)]
    struct Given(#[serde(deserialize_with = "crate::model::de_attr")] Option<NoteAttr>);
    if value.is_nil() {
        return Ok(None);
    }
    Ok(from_lua::<Given>(lua, value)?.0)
}

/// What a setter (`track_set`, `clip_set` ...) is given: one `key` and its
/// `value`, or a table of changes by key (a patch), in the order of their
/// names. A patch cannot clear a field: a table has no entry for nil.
fn changes(lua: &Lua, key: LuaValue, value: LuaValue) -> mlua::Result<Vec<(String, LuaValue)>> {
    match key {
        LuaValue::Table(patch) => {
            let mut out = patch.pairs::<String, LuaValue>().collect::<mlua::Result<Vec<_>>>()?;
            out.sort_by(|a, b| a.0.cmp(&b.0));
            Ok(out)
        }
        key => Ok(vec![(from_lua::<String>(lua, key)?, value)]),
    }
}

/// Read an options table, where leaving the table out means all defaults.
fn options<T: DeserializeOwned + Default>(lua: &Lua, value: LuaValue) -> mlua::Result<T> {
    if value.is_nil() {
        Ok(T::default())
    } else {
        from_lua(lua, value)
    }
}

fn cell(v: f64) -> i32 {
    v.floor() as i32
}

/// Defines `api.<name>` for each entry. Inside a body, `$sh` is the shared state.
macro_rules! define {
    ($lua:ident, $api:ident, $shared:ident; $(fn $name:ident($l:pat_param, $sh:ident, $args:pat_param => $ty:ty) $body:block)*) => {
        $({
            let $sh = $shared.clone();
            $api.set(stringify!($name), $lua.create_function(move |$l, $args: $ty| $body)?)?;
        })*
    };
}

/// The version of the scripting interface, `paw.api.version`: the minor
/// number goes up with additions, the major with anything taken away or
/// changed, so that an extension can say which it needs (`requires`).
pub const API_VERSION: &str = "1.0.0";

// One file for each area of the API, each with an `install` that defines
// its functions with `define!`. tools/apidoc.lua and paw-mcp's reference
// read the comments over each `fn` of these files: keep the one-line form.
mod project;
mod tracks;
mod devices;
mod clips;
mod automation;
mod transport;
mod midi;
mod engine;
mod undo;
mod screen;
mod timers;
mod processes;
mod formats;
mod system;

pub use screen::{render, render_live};
pub(crate) use screen::draw_view;
pub use timers::due_timers;

/// Build the `paw.api` table and make it available as `require("paw.api")`.
pub fn install(lua: &Lua, shared: &Rc<Shared>) -> mlua::Result<()> {
    let api = lua.create_table()?;
    api.set("limit_async", watchdog::ASYNC)?;
    api.set("version", API_VERSION)?;

    project::install(lua, &api, shared)?;
    tracks::install(lua, &api, shared)?;
    devices::install(lua, &api, shared)?;
    clips::install(lua, &api, shared)?;
    automation::install(lua, &api, shared)?;
    transport::install(lua, &api, shared)?;
    midi::install(lua, &api, shared)?;
    engine::install(lua, &api, shared)?;
    undo::install(lua, &api, shared)?;
    screen::install(lua, &api, shared)?;
    timers::install(lua, &api, shared)?;
    processes::install(lua, &api, shared)?;
    formats::install(lua, &api, shared)?;
    system::install(lua, &api, shared)?;

    crate::measure::install(lua, &api, shared)?;
    crate::tempo_api::install(lua, &api, shared)?;
    crate::luadev_api::install(lua, &api, shared)?;
    crate::fs_api::install(lua, &api)?;
    crate::scene::install(lua, &api, shared)?;

    let loaded: Table = lua.globals().get::<Table>("package")?.get("loaded")?;
    loaded.set("paw.api", api)
}
