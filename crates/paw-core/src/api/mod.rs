//! `paw.api`: the flat, plain-data interface between the kernel and Lua.
//!
//! Every function here takes and returns numbers, strings and tables, never
//! live objects. The friendly objects in `require("paw")` are Lua wrappers over these, and the
//! RPC socket exposes the same functions to other processes.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::marker::PhantomData;
use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use paw_engine::EventKind;
use mlua::serde::SerializeOptions;
use mlua::{FromLuaMulti, Lua, LuaSerdeExt, MultiValue, Table, Value as LuaValue};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::Value;

use crate::clock::Clock;
use crate::grid::{Caps, Grid, Highlights, KeptCells};
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
    /// When it fires, on the schedule clock (`Shared::clock`).
    pub due: Duration,
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
    /// Areas of frames kept by name to be put back on later ones
    /// (`grid_keep`, `grid_put`). A change of a highlight forgets them.
    pub kept_cells: RefCell<HashMap<String, KeptCells>>,
    /// How many times a redraw has been asked for: a window showing one
    /// view draws it again only when this has moved.
    pub redraws: Cell<u64>,
    /// How many of those were `ui_redraw_line`: only the line and the list.
    pub line_redraws: Cell<u64>,
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
    /// When the kernel started, on the wall: `paw.api.real_ms` and the time
    /// limit of Lua (`watchdog`) measure from it.
    pub started: Instant,
    /// The schedule clock of the process (`paw --clock`): the timers,
    /// `paw.api.now` and the settle delays of the session read it.
    pub clock: Arc<dyn Clock>,
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
            session.doc.emit(crate::events::KernelEvent::ProcOutput(crate::events::ProcOutput { id }));
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

/// A text argument copied from the Lua stack into a buffer on the Rust
/// stack. `LuaString::to_str` and `as_bytes` allocate a shared counter for
/// each call: the screen API takes its text this way instead, with no
/// allocation for a text of up to `INLINE` bytes.
pub struct LuaText(smallvec::SmallVec<[u8; LuaText::INLINE]>);

impl LuaText {
    const INLINE: usize = 256;

    /// The text, an error when it is not UTF-8.
    pub fn to_str(&self) -> mlua::Result<&str> {
        std::str::from_utf8(&self.0).map_err(|e| mlua::Error::FromLuaConversionError {
            from: "string",
            to: "string".into(),
            message: Some(e.to_string()),
        })
    }
}

impl mlua::FromLua for LuaText {
    fn from_lua(value: LuaValue, lua: &Lua) -> mlua::Result<Self> {
        // A number is text too, as for `LuaString`.
        let text = mlua::LuaString::from_lua(value, lua)?;
        Ok(Self(smallvec::SmallVec::from_slice(&text.as_bytes())))
    }

    unsafe fn from_stack(idx: std::ffi::c_int, lua: &mlua::state::RawLua) -> mlua::Result<Self> {
        use mlua::ffi;
        let state = lua.state();
        // SAFETY: `idx` is a valid index of the stack of `state`, which mlua
        // gives. `lua_tolstring` turns a number there into its text, as Lua
        // does for a string argument. The bytes of a Lua string stay valid
        // while it is on the stack, and they are copied before this returns.
        unsafe {
            let kind = ffi::lua_type(state, idx);
            if kind != ffi::LUA_TSTRING && kind != ffi::LUA_TNUMBER {
                return Err(mlua::Error::FromLuaConversionError {
                    from: if kind == ffi::LUA_TNIL { "nil" } else { "a value that is not text" },
                    to: "string".into(),
                    message: None,
                });
            }
            let mut size = 0;
            let data = ffi::lua_tolstring(state, idx, &mut size);
            let bytes = std::slice::from_raw_parts(data.cast::<u8>(), size);
            Ok(Self(smallvec::SmallVec::from_slice(bytes)))
        }
    }
}

/// An integer as a Lua value: a Lua integer where it fits, else a number.
/// LuaJIT's integers have 64 bits; the PUC Lua of a BrowserPod pod has
/// 32 (`ptrdiff_t` in WebAssembly).
pub fn lua_integer(n: i64) -> LuaValue {
    mlua::Integer::try_from(n).map_or(LuaValue::Number(n as f64), LuaValue::Integer)
}

/// A Lua integer with 64 bits, on every Lua (see [`lua_integer`]).
#[allow(clippy::useless_conversion, reason = "mlua::Integer is i64 with LuaJIT, i32 in a pod")]
pub fn wide_integer(n: mlua::Integer) -> i64 {
    i64::from(n)
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

/// A cell coordinate or size from Lua. NaN is 0, and the value is at most a
/// quarter of `i32::MAX` either way, so that a sum of two never overflows.
/// A cell that far away is off every screen anyway.
fn cell(v: f64) -> i32 {
    const FAR: f64 = (i32::MAX / 4) as f64;
    v.floor().clamp(-FAR, FAR) as i32
}

/// A time in milliseconds from Lua as a `Duration`. A negative time or NaN
/// is none, and a time is at most a century, so that `Instant::now()` plus
/// it does not overflow.
///
/// It counts in whole nanoseconds, rounded: a whole number of milliseconds
/// gives exactly that many, so a wait of 300 ms on the manual clock lands on
/// a whole millisecond, and `as_ms` gives 300 back.
pub(crate) fn millis(ms: f64) -> Duration {
    const CENTURY_MS: f64 = 100.0 * 365.25 * 24.0 * 3600.0 * 1000.0;
    if ms.is_nan() || ms <= 0.0 {
        return Duration::ZERO;
    }
    // At most a century of nanoseconds is far below u64::MAX.
    Duration::from_nanos((ms.min(CENTURY_MS) * 1e6).round() as u64)
}

/// A `Duration` in milliseconds for Lua. The nanoseconds are divided once,
/// so a whole number of milliseconds is exact: a check such as
/// `now - last >= 50` holds at 50 ms, whatever the time since the start.
/// (`as_secs_f64() * 1000.0` rounds twice and gives 32500.999999999996 for
/// 32501 ms.)
pub(crate) fn as_ms(d: Duration) -> f64 {
    d.as_nanos() as f64 / 1e6
}

// --- The guard of each function -----------------------------------------------
//
// Each function of `paw.api` is made with `guarded!`. Then a wrong argument
// gives an error that names the function ("bad argument #1 to
// `paw.api.clip_get`"), and a panic in the function gives a Lua error and
// not the end of the program. tests/api_boundary.lua checks both for each
// function.

/// The name of a function of `paw.api`, as its errors give it. `guarded!`
/// makes one type for each function, so that the conversion of the
/// arguments knows the name and stays on the fast path of mlua.
pub trait Named {
    const NAME: &'static str;
}

/// The arguments of the function `N`: a conversion that fails names it.
pub struct Args<N, A>(A, PhantomData<N>);

impl<N: Named, A: FromLuaMulti> FromLuaMulti for Args<N, A> {
    fn from_lua_multi(values: MultiValue, lua: &Lua) -> mlua::Result<Self> {
        A::from_lua_args(values, 1, Some(N::NAME), lua).map(|args| Self(args, PhantomData))
    }

    fn from_lua_args(values: MultiValue, i: usize, _to: Option<&str>, lua: &Lua) -> mlua::Result<Self> {
        A::from_lua_args(values, i, Some(N::NAME), lua).map(|args| Self(args, PhantomData))
    }

    unsafe fn from_stack_args(
        nargs: std::ffi::c_int,
        i: usize,
        _to: Option<&str>,
        lua: &mlua::state::RawLua,
    ) -> mlua::Result<Self> {
        // SAFETY: the caller keeps the contract of `from_stack_args` (the
        // `nargs` values are on the stack of `lua`), and this passes it on
        // unchanged.
        unsafe { A::from_stack_args(nargs, i, Some(N::NAME), lua) }.map(|args| Self(args, PhantomData))
    }
}

thread_local! {
    /// How many functions of `paw.api` run now on this thread, one inside
    /// another. The panic hooks of the program read it (`in_call`).
    static CALLS: Cell<u32> = const { Cell::new(0) };
    /// Set by `end_program`: the guards let its panic go on.
    static ENDING: Cell<bool> = const { Cell::new(false) };
}

/// True while a function of `paw.api` runs on this thread. A panic there
/// becomes a Lua error and the program goes on, so a panic hook must not
/// restore the terminal or write a safety copy.
pub fn in_call() -> bool {
    CALLS.get() > 0
}

/// One count of `CALLS`, for as long as a function of `paw.api` runs, also
/// when it panics.
struct Call;

impl Call {
    fn enter() -> Self {
        CALLS.set(CALLS.get() + 1);
        Self
    }
}

impl Drop for Call {
    fn drop(&mut self) {
        CALLS.set(CALLS.get().saturating_sub(1));
    }
}

/// Panic as a bug outside `paw.api` does: the guards do not catch it, and
/// the program ends with a safety copy (`paw.api.test_panic`).
fn end_program(why: &str) -> ! {
    ENDING.set(true);
    CALLS.set(0);
    panic!("{why}");
}

/// The error of a function of `paw.api` that panicked.
fn bug(name: &str, panic: &(dyn std::any::Any + Send)) -> mlua::Error {
    let why = panic
        .downcast_ref::<&str>()
        .copied()
        .or_else(|| panic.downcast_ref::<String>().map(String::as_str))
        .unwrap_or("no message");
    mlua::Error::runtime(format!("{name} stopped on a bug in paw: {why}"))
}

/// The body of the function `N` of `paw.api`, with its guard. Use it through
/// `guarded!`, which makes `N`.
pub fn guard<N, A, R, F>(f: F) -> impl Fn(&Lua, Args<N, A>) -> mlua::Result<R> + 'static
where
    N: Named + 'static,
    A: FromLuaMulti + 'static,
    F: Fn(&Lua, A) -> mlua::Result<R> + 'static,
{
    move |lua, Args(args, _)| {
        let call = Call::enter();
        let result = std::panic::catch_unwind(AssertUnwindSafe(|| f(lua, args)));
        drop(call);
        result.unwrap_or_else(|panic| {
            if ENDING.get() {
                std::panic::resume_unwind(panic);
            }
            Err(bug(N::NAME, &*panic))
        })
    }
}

/// `named!(Name, "clip_get")`: the type `Name`, [`Named`] as
/// `paw.api.clip_get`.
macro_rules! named {
    ($type:ident, $name:expr) => {
        struct $type;
        impl $crate::api::Named for $type {
            const NAME: &'static str = concat!("paw.api.", $name);
        }
    };
}
pub(crate) use named;

/// `guarded!("clip_get", |lua, id: Id| ...)`: the function `paw.api.clip_get`
/// with its guard, for `lua.create_function`.
macro_rules! guarded {
    ($name:expr, $f:expr) => {{
        $crate::api::named!(Name, $name);
        $crate::api::guard::<Name, _, _, _>($f)
    }};
}
pub(crate) use guarded;

/// Defines `api.<name>` for each entry, with its guard. Inside a body, `$sh`
/// is the shared state.
macro_rules! define {
    ($lua:ident, $api:ident, $shared:ident; $(fn $name:ident($l:pat_param, $sh:ident, $args:pat_param => $ty:ty) $body:block)*) => {
        $({
            let $sh = $shared.clone();
            $api.set(
                stringify!($name),
                $lua.create_function(guarded!(stringify!($name), move |$l, $args: $ty| $body))?,
            )?;
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
mod kind_data;
mod automation;
mod transport;
mod midi;
mod engine;
mod undo;
mod screen;
mod timers;
mod processes;
mod formats;
mod graph;
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
    graph::install(lua, &api, shared)?;
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
    crate::fs_api::install(lua, &api, &shared.session.borrow().dirs)?;
    crate::scene::install(lua, &api, shared)?;

    let loaded: Table = lua.globals().get::<Table>("package")?.get("loaded")?;
    loaded.set("paw.api", api)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_huge_time_or_cell_is_kept_in_range() {
        assert_eq!(millis(1e300), Duration::from_secs(3_155_760_000), "a century");
        assert_eq!(millis(f64::NAN), Duration::ZERO);
        assert_eq!(millis(-5.0), Duration::ZERO);
        assert_eq!(millis(1500.0), Duration::from_millis(1500));
        assert_eq!(cell(1e300), i32::MAX / 4);
        assert_eq!(cell(-1e300), -(i32::MAX / 4));
        assert_eq!(cell(f64::NAN), 0);
        assert_eq!(cell(2.7), 2);
    }

    #[test]
    fn whole_milliseconds_stay_whole_both_ways() {
        // A throttle of 50 ms checks `now - last < 50` at 32451 and 32501 ms:
        // both must be exact, or the second note is not heard.
        for ms in [300u64, 1001, 32_451, 32_501] {
            assert_eq!(millis(ms as f64), Duration::from_millis(ms), "{ms} ms to a duration");
            assert_eq!(as_ms(Duration::from_millis(ms)), ms as f64, "{ms} ms from a duration");
        }
        assert_eq!(as_ms(Duration::from_millis(32_501)) - as_ms(Duration::from_millis(32_451)), 50.0);
    }
}
