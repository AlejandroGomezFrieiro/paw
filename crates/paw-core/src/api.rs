//! `paw.api`: the flat, plain-data interface between the kernel and Lua.
//!
//! Every function here takes and returns numbers, strings and tables, never
//! live objects. The friendly objects in `require("paw")` are Lua wrappers over these, and the
//! RPC socket exposes the same functions to other processes.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use paw_engine::backend::{BackendOptions, TestInput};
use paw_engine::{EventKind, ump};
use mlua::serde::SerializeOptions;
use mlua::{Function, Lua, LuaSerdeExt, LuaString, Table, Value as LuaValue};
use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::{Value, json};
use unicode_width::UnicodeWidthStr;

use crate::grid::{self, Caps, Color, Grid, Highlight, Highlights, Rect, Style};
use crate::io::Io;
use crate::model::{ClipContent, Control, Id, Note, NoteAttr};
use crate::session::notes::{NoteChange, NoteRange, NotesEdit};
use crate::session::{RenderOpts, Session};
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
            session.events.push(("proc.output".into(), json!({ "id": id })));
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

/// Bytes as a Lua string, or nil and the reason they could not be made.
fn bytes_or_why(lua: &Lua, bytes: anyhow::Result<Vec<u8>>) -> mlua::Result<(LuaValue, LuaValue)> {
    Ok(match bytes {
        Ok(bytes) => (LuaValue::String(lua.create_string(&bytes)?), LuaValue::Nil),
        Err(err) => (LuaValue::Nil, LuaValue::String(lua.create_string(format!("{err:#}"))?)),
    })
}

pub fn from_lua<T: DeserializeOwned>(lua: &Lua, value: LuaValue) -> mlua::Result<T> {
    lua.from_value(value)
}

/// Notes as Lua tables: what `to_lua` makes of them, built directly. Views
/// ask for a clip's notes every time they draw, so this is on a hot path.
fn notes_to_lua(lua: &Lua, notes: &crate::model::Notes) -> mlua::Result<LuaValue> {
    let list = lua.create_table_with_capacity(notes.len(), 0)?;
    list.set_metatable(Some(lua.array_metatable()))?;
    for (i, n) in notes.iter().enumerate() {
        list.raw_seti(i + 1, note_to_lua(lua, n)?)?;
    }
    Ok(LuaValue::Table(list))
}

fn note_to_lua(lua: &Lua, n: &Note) -> mlua::Result<Table> {
    let note = lua.create_table_with_capacity(0, 4)?;
    note.raw_set("start", n.start)?;
    note.raw_set("length", n.length)?;
    note.raw_set("pitch", n.pitch)?;
    note.raw_set("velocity", n.velocity)?;
    if n.id != 0 {
        note.raw_set("id", n.id)?;
    }
    // What extensions keep with a note, such as its lyric.
    if !n.meta.is_empty() {
        note.raw_set("meta", to_lua(lua, &n.meta)?)?;
    }
    if let Some(attr) = n.attr {
        note.raw_set("attr", attr_to_lua(lua, attr)?)?;
    }
    Ok(note)
}

/// A note's attribute as Lua has it: `{ type = 17, data = 40960 }`.
fn attr_to_lua(lua: &Lua, attr: NoteAttr) -> mlua::Result<Table> {
    let table = lua.create_table_with_capacity(0, 2)?;
    table.raw_set("type", attr.kind)?;
    table.raw_set("data", attr.data)?;
    Ok(table)
}

/// A track's attribute map from Lua as the data `track_set` takes.
fn attr_map_from_lua(lua: &Lua, value: LuaValue) -> mlua::Result<Value> {
    let empty = match &value {
        LuaValue::Nil | LuaValue::Boolean(false) => true,
        LuaValue::Table(t) => t.is_empty(),
        _ => false,
    };
    if empty {
        return Ok(Value::Null);
    }
    let map: crate::attr_map::AttrMap = from_lua(lua, value)?;
    serde_json::to_value(map).map_err(mlua::Error::external)
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

/// A note's place in its clip as Lua counts it, from 1, turned into ours.
fn note_index(index: usize) -> mlua::Result<usize> {
    index
        .checked_sub(1)
        .ok_or_else(|| mlua::Error::runtime("notes are counted from 1"))
}

/// Notes from Lua. Well-formed lists of note tables are read directly;
/// anything else goes through serde, so that what is accepted and the errors
/// for what is not stay exactly those of `from_lua`.
fn notes_from_lua(lua: &Lua, value: LuaValue) -> mlua::Result<Vec<Note>> {
    fn direct(value: &LuaValue) -> Option<Vec<Note>> {
        let LuaValue::Table(list) = value else {
            return None;
        };
        let len = list.raw_len();
        if list.pairs::<LuaValue, LuaValue>().count() != len {
            return None;
        }
        let int = |v: LuaValue| match v {
            LuaValue::Integer(i) => u8::try_from(i).ok(),
            _ => None,
        };
        let num = |v: LuaValue| match v {
            LuaValue::Integer(i) => Some(i as f64),
            LuaValue::Number(n) => Some(n),
            _ => None,
        };
        let mut notes = Vec::with_capacity(len);
        for i in 1..=len {
            let LuaValue::Table(note) = list.raw_get::<LuaValue>(i).ok()? else {
                return None;
            };
            let velocity = match note.raw_get::<LuaValue>("velocity").ok()? {
                LuaValue::Nil => 100,
                v => int(v)?,
            };
            // A note that carries data of an extension's, or an
            // attribute, goes the long way.
            if !note.raw_get::<LuaValue>("meta").ok()?.is_nil()
                || !note.raw_get::<LuaValue>("attr").ok()?.is_nil()
            {
                return None;
            }
            notes.push(Note {
                start: num(note.raw_get("start").ok()?)?,
                length: num(note.raw_get("length").ok()?)?,
                pitch: int(note.raw_get("pitch").ok()?)?,
                velocity,
                meta: Default::default(),
                id: match note.raw_get::<LuaValue>("id").ok()? {
                    LuaValue::Nil => 0,
                    LuaValue::Integer(i) => u64::try_from(i).ok()?,
                    LuaValue::Number(n) if n >= 0.0 && n.fract() == 0.0 => n as u64,
                    _ => return None,
                },
                attr: None,
            });
        }
        Some(notes)
    }
    match direct(&value) {
        Some(notes) => Ok(notes),
        None => from_lua(lua, value),
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

/// A terminal's capabilities as Lua reads them (`paw.api.ui_caps`).
fn caps_lua(caps: &Caps) -> Value {
    let mut value = caps.to_json();
    value["cell"] = json!({ "w": caps.cell.0, "h": caps.cell.1 });
    value["pixels"] = json!(caps.pixels());
    value
}

fn parse_style(table: &Table) -> mlua::Result<Style> {
    let color = |key: &str| -> mlua::Result<Option<Color>> {
        Ok(match table.get::<LuaValue>(key)? {
            LuaValue::Nil => None,
            LuaValue::String(s) => {
                let text = s.to_str()?;
                Some(
                    Color::parse(&text)
                        .ok_or_else(|| mlua::Error::runtime(format!("bad colour `{}`", &*text)))?,
                )
            }
            LuaValue::Integer(i) => Some(Color::Indexed(i as u8)),
            LuaValue::Number(n) => Some(Color::Indexed(n as u8)),
            _ => {
                return Err(mlua::Error::runtime(format!(
                    "`{key}` must be a colour name, `#rrggbb` or 0-255"
                )));
            }
        })
    };
    let mut style = Style {
        fg: color("fg")?,
        bg: color("bg")?,
        on: 0,
        off: 0,
    };
    let attrs = [
        ("bold", grid::BOLD),
        ("dim", grid::DIM),
        ("italic", grid::ITALIC),
        ("underline", grid::UNDERLINE),
        ("reverse", grid::REVERSE),
        ("strike", grid::STRIKE),
    ];
    for (key, bit) in attrs {
        match table.get::<Option<bool>>(key)? {
            Some(true) => style.on |= bit,
            Some(false) => style.off |= bit,
            None => {}
        }
    }
    Ok(style)
}

/// A style given as a highlight group name, a table of attributes, or nil.
fn style_of(shared: &Shared, value: &LuaValue) -> mlua::Result<Style> {
    match value {
        LuaValue::Nil => Ok(Style::default()),
        LuaValue::String(name) => Ok(shared.highlights.borrow().get(&name.to_str()?)),
        LuaValue::Table(table) => parse_style(table),
        _ => Err(mlua::Error::runtime(
            "a style must be a highlight name or a table",
        )),
    }
}

/// Draw the UI by calling the Lua runtime's `render(width, height)`.
///
/// Lua draws through `api.grid_text` and `api.grid_fill`. There is deliberately
/// no drawing-buffer object: `paw.api` only ever passes plain data, so nothing
/// Lua holds can keep kernel state alive or outlive a reload.
///
/// Do not hand Lua a Rust type through `mlua::UserData` without checking this
/// first: with mlua 0.12.2 and LuaJIT on x86-64, collecting such an object
/// crashes. The finalizer mlua installs for those types returns its `int` with
/// the upper half of the register undefined, and LuaJIT's interpreter reads
/// all 64 bits. `tests/suite.lua` forces a collection after drawing to catch
/// a regression.
pub fn render(lua: &Lua, shared: &Shared) -> mlua::Result<()> {
    let (width, height) = {
        let grid = shared.grid.borrow();
        (grid.width, grid.height)
    };
    let paw: Table = lua.globals().get("paw")?;
    let kernel: Table = paw.get("_kernel")?;
    kernel.get::<Function>("render")?.call((width, height))
}

/// Draw only the live parts of the frame drawn last again (see
/// [`crate::grid::Live`]). False when the runtime finds that the frame needs
/// drawing whole: something not live moves.
pub fn render_live(lua: &Lua, shared: &Shared) -> mlua::Result<bool> {
    let (width, height) = {
        let grid = shared.grid.borrow();
        (grid.width, grid.height)
    };
    let paw: Table = lua.globals().get("paw")?;
    let kernel: Table = paw.get("_kernel")?;
    kernel.get::<Function>("render_live")?.call((width, height))
}

/// One view drawn by itself, as a window shows it: its grid, where it put
/// the cursor, and the theme's text and background colours.
pub(crate) type Drawn = (Grid, Option<(u16, u16)>, (u8, u8, u8), (u8, u8, u8));

/// Draw one view by itself on a grid of its own, as a window shows it, with
/// the colours of the theme in 24 bits, whatever the terminal shows. The
/// screen, its cursor and whether it needs drawing are left as they were.
pub(crate) fn draw_view(lua: &Lua, sh: &Shared, name: &str, width: u16, height: u16) -> mlua::Result<Drawn> {
    let screen = sh.grid.replace(Grid::new(width, height));
    let (cursor, dirty, redraws) = (sh.cursor.replace(None), sh.dirty.get(), sh.redraws.get());
    sh.highlights.borrow_mut().full_colour = true;
    let drawn = (|| {
        let paw: Table = lua.globals().get("paw")?;
        let kernel: Table = paw.get("_kernel")?;
        kernel.get::<Function>("render_view")?.call::<()>((name, width, height))
    })();
    let normal = sh.highlights.borrow().get("Normal");
    sh.highlights.borrow_mut().full_colour = false;
    let grid = sh.grid.replace(screen);
    let at = sh.cursor.replace(cursor);
    sh.dirty.set(dirty);
    sh.redraws.set(redraws);
    drawn?;
    let fg = grid::rgb(normal.fg.unwrap_or(Color::Default), (0xd8, 0xd9, 0xdc));
    let bg = grid::rgb(normal.bg.unwrap_or(Color::Default), (0x18, 0x19, 0x1c));
    Ok((grid, at, fg, bg))
}

/// [`draw_view`] as rows of runs of one style (see [`Grid::runs`]).
fn view_snapshot(lua: &Lua, sh: &Shared, name: &str, width: u16, height: u16) -> mlua::Result<Value> {
    let (grid, at, fg, bg) = draw_view(lua, sh, name, width, height)?;
    Ok(serde_json::json!({
        "width": width,
        "height": height,
        "fg": grid::hex(fg),
        "bg": grid::hex(bg),
        "rows": grid.runs(fg, bg),
        "cursor": at.map(|(x, y)| serde_json::json!({ "x": x, "y": y })),
    }))
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct EngineOpts {
    backend: Option<String>,
    sample_rate: Option<u32>,
    buffer_size: Option<u32>,
    /// Open the audio device's input. On by default.
    input: Option<bool>,
    /// Devices by name, id or part of a name; the system's default without.
    output_device: Option<String>,
    input_device: Option<String>,
    test_input: Option<TestInputOpts>,
    /// MIDI ports for the null backend to list, by name.
    test_midi: Option<Vec<String>>,
    /// Open the real MIDI ports even on the null backend, which otherwise
    /// leaves them closed.
    midi: Option<bool>,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct AudioWatchOpts {
    auto: Option<bool>,
    period: Option<f64>,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct TestDeviceOpts {
    present: Option<bool>,
    fail_after: Option<u64>,
    back_after: Option<u64>,
}

/// Which devices to change to: `{ output = "UR22", input = "UR22", buffer = 128 }`.
#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct AudioUseOpts {
    output: Option<String>,
    input: Option<String>,
    buffer: Option<u32>,
    /// The sound system: `auto`, `pipewire`, `alsa`, `jack`.
    backend: Option<String>,
    /// Hz, or 0 for the device's own.
    rate: Option<u32>,
}

/// A sine for the null backend to use as input: `{ frequency = 440, level = -12, channels = 2 }`.
#[derive(Deserialize)]
#[serde(default, deny_unknown_fields)]
struct TestInputOpts {
    frequency: f64,
    /// Peak level in dB.
    level: f64,
    channels: u16,
}

impl Default for TestInputOpts {
    fn default() -> Self {
        Self {
            frequency: 440.0,
            level: -12.0,
            channels: 2,
        }
    }
}

/// A note from Lua as if from a MIDI port: `{ type = "note_on", pitch = 60, velocity = 100 }`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct MidiEventOpts {
    #[serde(rename = "type")]
    kind: String,
    pitch: Option<u8>,
    velocity: Option<f64>,
    // Read from the table before the rest; named here so that it is allowed.
    #[allow(dead_code)]
    channel: Option<u8>,
    /// A note-on's MIDI 2.0 attribute.
    #[serde(default, deserialize_with = "crate::model::de_attr")]
    attr: Option<NoteAttr>,
}

/// A MIDI message from Lua as the engine's event: a note, or a controller
/// move in the shape a clip keeps them in, with a `channel` from 1 to 16.
fn midi_kind(lua: &Lua, event: LuaValue) -> mlua::Result<EventKind> {
    let table = match &event {
        LuaValue::Table(table) => table.clone(),
        _ => {
            return Err(mlua::Error::runtime(
                "a MIDI event is a table with a `type`",
            ));
        }
    };
    let kind: String = table.get("type")?;
    let channel: Option<u8> = table.get("channel")?;
    let ch = channel.unwrap_or(1).clamp(1, 16) - 1;
    if kind != "note_on" && kind != "note_off" {
        let control: Control = from_lua(lua, event).map_err(|err| {
            mlua::Error::runtime(format!(
                "`{kind}` is not a MIDI event that can be sent (note_on, note_off, cc, bend, \
                 pressure, registered, assignable, program): {err}"
            ))
        })?;
        if let Some(problem) = control.problem() {
            return Err(mlua::Error::runtime(format!(
                "a MIDI event cannot be that: {problem}"
            )));
        }
        return Ok(control.event(ch));
    }
    let event: MidiEventOpts = from_lua(lua, event)?;
    let pitch = || {
        event
            .pitch
            .filter(|p| *p < 128)
            .ok_or_else(|| mlua::Error::runtime("a note needs a `pitch` from 0 to 127"))
    };
    Ok(match event.kind.as_str() {
        "note_on" => {
            let vel = live_velocity(event.velocity)?;
            // As on the wire in MIDI 1.0, a note-on with no velocity is a note-off.
            if vel > 0.0 {
                EventKind::NoteOn {
                    key: pitch()?,
                    vel,
                    ch,
                    attr: event.attr.map_or(paw_engine::Attr::NONE, Into::into),
                }
            } else {
                EventKind::NoteOff { key: pitch()?, ch }
            }
        }
        _ => EventKind::NoteOff { key: pitch()?, ch },
    })
}

/// A velocity from 0 to 127, or 100 when none is given, as the engine's 0 to 1.
fn live_velocity(velocity: Option<f64>) -> mlua::Result<f32> {
    let velocity = velocity.unwrap_or(100.0);
    if !velocity.is_finite() {
        return Err(mlua::Error::runtime(format!(
            "a velocity is a number from 0 to 127, not {velocity}"
        )));
    }
    Ok((velocity / 127.0).clamp(0.0, 1.0) as f32)
}

/// This program's directory under one of the XDG base directories.
fn xdg_dir(variable: &str, fallback: &str) -> String {
    let base = std::env::var_os(variable)
        .map(std::path::PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|home| std::path::PathBuf::from(home).join(fallback))
        })
        .unwrap_or_else(std::env::temp_dir);
    base.join("paw").to_string_lossy().into_owned()
}

/// The functions of the timers that are due, with one-shot timers removed
/// and repeating ones moved on.
pub fn due_timers(shared: &Shared) -> Vec<Rc<mlua::RegistryKey>> {
    let now = Instant::now();
    let mut timers = shared.timers.borrow_mut();
    let mut due = Vec::new();
    timers.retain_mut(|timer| {
        if timer.due > now {
            return true;
        }
        due.push(timer.func.clone());
        match timer.repeat {
            Some(period) => {
                // Skip missed periods rather than firing in a burst.
                timer.due = (timer.due + period).max(now);
                true
            }
            None => false,
        }
    });
    due
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

/// Build the `paw.api` table and make it available as `require("paw.api")`.
pub fn install(lua: &Lua, shared: &Rc<Shared>) -> mlua::Result<()> {
    let api = lua.create_table()?;
    api.set("limit_async", watchdog::ASYNC)?;
    api.set("version", API_VERSION)?;

    define! { lua, api, shared;
        // --- project ---
        // The project as a table. With `key`, only that entry of the table:
        // this is quicker (`edits`, which goes up with each change, is asked
        // for on each key and each edit).
        fn project_get(lua, sh, key => Option<String>) {
            let session = sh.session.borrow();
            match key {
                Some(key) => to_lua(lua, &session.project_field(&key)),
                None => to_lua(lua, &session.project_view()),
            }
        }
        fn project_set(lua, sh, (key, value) => (String, LuaValue)) {
            sh.session.borrow_mut().project_set(&key, from_lua(lua, value)?).lua()
        }
        // Put the open project aside, with its undo history, and open an empty
        // project. `project_unshelve` brings the first project back exactly as it
        // was. For checks that need their own tracks (extensions/doctor).
        // @return nil
        fn project_shelve(_, sh, () => ()) { sh.session.borrow_mut().project_shelve().lua() }
        // @return nil
        fn project_unshelve(_, sh, () => ()) { sh.session.borrow_mut().project_unshelve().lua() }
        // @return boolean
        fn project_shelved(_, sh, () => ()) { Ok(sh.session.borrow().project_shelved()) }
        // @return nil
        fn project_new(_, sh, () => ()) {
            sh.session.borrow_mut().project_new();
            Ok(())
        }
        // Count the project as it is now as saved, for a script that wrote
        // what it holds somewhere itself (a clip opened alone, written
        // back to its file).
        // @return nil
        fn project_mark_saved(_, sh, () => ()) {
            sh.session.borrow_mut().mark_saved();
            Ok(())
        }
        // `opts.plugins_offline` opens it with all plugins offline.
        // `opts.offline` is a list of devices (by id) to open offline.
        fn project_load(lua, sh, (path, opts) => (String, LuaValue)) {
            let mut session = sh.session.borrow_mut();
            session.set_open_opts(options(lua, opts)?);
            let loaded = session.project_load(path.as_ref());
            session.set_open_opts(Default::default());
            loaded.lua()
        }
        // Write the project as it is now to a different file. The path of the
        // project and its modified flag do not change. The file keeps `note`
        // under `recovery`.
        fn project_backup(lua, sh, (path, note) => (String, LuaValue)) {
            let note: Value = from_lua(lua, note)?;
            sh.session.borrow_mut().project_backup(Path::new(&path), note).lua()
        }
        // Open a file written by `project_backup` as the project it was a
        // copy of: under that project's own file name, and as changed.
        // `opts`: `as_path` opens it under that file name instead (for a
        // `.bak`, which has no note), and what `project_load` takes.
        fn project_recover(lua, sh, (path, opts) => (String, LuaValue)) {
            let as_path: Option<String> = match &opts {
                LuaValue::Table(table) => table.get("as_path")?,
                _ => None,
            };
            let mut session = sh.session.borrow_mut();
            session.set_open_opts(options(lua, opts)?);
            let recovered = session.project_recover(Path::new(&path), as_path.as_deref().map(Path::new));
            session.set_open_opts(Default::default());
            to_lua(lua, &recovered.lua()?)
        }
        // The files of a project kept in a folder, with what each holds and
        // if it differs from the disk (see `:ls`).
        fn project_files(lua, sh, () => ()) {
            to_lua(lua, &sh.session.borrow_mut().project_files().lua()?)
        }
        // Save only these files of a project kept in a folder, by their path
        // in it. Returns the paths written.
        fn project_save_files(lua, sh, paths => Vec<String>) {
            let paths: Vec<PathBuf> = paths.into_iter().map(PathBuf::from).collect();
            to_lua(lua, &sh.session.borrow_mut().project_save_files(&paths).lua()?)
        }
        // Make every clip that refers to a MIDI clip file outside the
        // project the project's own. Returns how many.
        fn clip_collect(_, sh, () => ()) {
            Ok(sh.session.borrow_mut().clip_collect())
        }
        // Make every track read from a folder outside the project, and every
        // chain of devices read from a file outside it, the project's own.
        // Returns how many tracks and how many chains.
        fn track_collect(_, sh, () => ()) {
            Ok(sh.session.borrow_mut().track_collect())
        }
        // Add the track of a track folder outside the project (a folder with
        // a `track.json`) at `index` (from 1; the end when nil). The project
        // refers to the folder until the track's first edit. Returns its id.
        fn track_import_folder(_, sh, (folder, index) => (String, Option<usize>)) {
            sh.session.borrow_mut().track_import_folder(Path::new(&folder), index).lua()
        }
        // Give a track the devices of a chain file (a `devices.json`). With
        // `refer`, the track refers to the file until the chain's first edit.
        // Returns how many devices.
        fn track_chain_file(_, sh, (track, file, refer) => (Id, String, Option<bool>)) {
            sh.session.borrow_mut().track_chain_file(track, Path::new(&file), refer.unwrap_or(true)).lua()
        }
        // Write a track's devices as a chain file: `file` (a `devices.json`)
        // and the `.state` files of the plugins beside it. Returns the files.
        fn chain_write(lua, sh, (track, file) => (Id, String)) {
            let written = sh.session.borrow_mut().chain_write(track, Path::new(&file)).lua()?;
            to_lua(lua, &written)
        }
        // The files of the open project that changed outside paw and are not
        // acted on yet: paths in its folder, or full paths outside it.
        fn project_changed_files(lua, sh, () => ()) {
            to_lua(lua, &sh.session.borrow().changed_files())
        }
        // Keep the project as paw has it: forget the changes made outside.
        // @return nil
        fn project_keep_changes(_, sh, () => ()) {
            sh.session.borrow_mut().keep_changed_files();
            Ok(())
        }
        // Read a project kept in a folder again, as one undo step.
        fn project_reload(_, sh, () => ()) {
            sh.session.borrow_mut().project_reload().lua()
        }
        fn project_save(_, sh, path => Option<String>) {
            let saved = sh.session.borrow_mut().project_save(path.as_deref().map(AsRef::as_ref)).lua()?;
            Ok(saved.to_string_lossy().into_owned())
        }
        // The tabs and windows that the project file keeps, as plain data,
        // or nil. They are not part of the song: setting them is not an
        // edit, and the next save writes them.
        fn project_screen(lua, sh, () => ()) {
            to_lua(lua, &sh.session.borrow().screen)
        }
        // @return nil
        fn project_screen_set(lua, sh, value => LuaValue) {
            let value: Option<Value> = from_lua(lua, value)?;
            sh.session.borrow_mut().screen = value;
            Ok(())
        }

        // --- tracks ---
        // @return {integer}
        fn track_list(_, sh, () => ()) {
            Ok(sh.session.borrow().project.tracks.iter().map(|t| t.id).collect::<Vec<Id>>())
        }
        // A track as a table. With `key`, only that entry of the table: this
        // is quicker, because the table lists each clip of the track.
        fn track_get(lua, sh, (id, key) => (Id, Option<String>)) {
            let session = sh.session.borrow();
            match key {
                Some(key) => to_lua(lua, &session.track_field(id, &key).lua()?),
                None => to_lua(lua, &session.track_view(id).lua()?),
            }
        }
        // @return integer
        fn track_add(lua, sh, opts => LuaValue) { sh.session.borrow_mut().track_add(options(lua, opts)?).lua() }
        // @return nil
        fn track_remove(_, sh, id => Id) { sh.session.borrow_mut().track_remove(id).lua() }
        fn track_move(_, sh, (id, index) => (Id, usize)) {
            sh.session.borrow_mut().track_move(id, index.saturating_sub(1)).lua()
        }
        fn track_set(lua, sh, (id, key, value) => (Id, String, LuaValue)) {
            let value: Value = match key.as_str() {
                // Read as a map first: its `by_type` is keyed by numbers.
                "attr_map" => attr_map_from_lua(lua, value)?,
                _ => from_lua(lua, value)?,
            };
            sh.session.borrow_mut().track_set(id, &key, value).lua()
        }
        fn track_meter(_, sh, id => Id) { Ok(sh.session.borrow().meter(id)) }
        // The milliseconds that the attribute map of the track moves a note with
        // `attr` (below 0: earlier). 0 when the track has no attribute map.
        // @param attr? types.NoteAttr
        // @return number
        fn track_attr_delay(lua, sh, (id, attr) => (Id, LuaValue)) {
            let attr = attr_from_lua(lua, attr)?.map_or(paw_engine::Attr::NONE, Into::into);
            sh.session.borrow().attr_delay(id, attr).lua()
        }

        // --- devices ---
        fn device_types(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().device_types()) }
        // The kind of device installed that answers `query`, `{ kind, format,
        // id, name, vendor }` (each optional), as an entry of `device_types`;
        // nil when none does. It looks by `kind` (an old name too), else by
        // the plugin's own `id` (a CLAP id, a VST3 class id in either case,
        // an LV2 URI), else by `name` with the `vendor` (a kind without a
        // vendor answers any), else by `name` in any case; `format` ("clap",
        // "vst3", "lv2", "builtin") keeps to one format. With `all = true`,
        // the list of all that answer the first test that finds one. The
        // list of all kinds is not made, so it is quick with many plugins.
        fn device_find(lua, sh, query => LuaValue) {
            let q: crate::session::DeviceQuery = from_lua(lua, query)?;
            let found = sh.session.borrow().device_find(&q);
            if q.all {
                to_lua(lua, &found)
            } else {
                found.into_iter().next().map_or(Ok(LuaValue::Nil), |v| to_lua(lua, &v))
            }
        }
        fn device_get(lua, sh, id => Id) {
            // A device's parameters are those of the instance the engine
            // runs, so bring the engine up to date first: right after an undo
            // the device would otherwise read as missing.
            let mut session = sh.session.borrow_mut();
            session.flush();
            to_lua(lua, &session.device_view(id).lua()?)
        }
        fn device_add(lua, sh, (track, kind, opts) => (Id, String, LuaValue)) {
            sh.session.borrow_mut().device_add(track, &kind, options(lua, opts)?).lua()
        }
        // @return nil
        fn device_remove(_, sh, id => Id) { sh.session.borrow_mut().device_remove(id).lua() }
        fn device_move(_, sh, (id, track, index) => (Id, Id, usize)) {
            sh.session.borrow_mut().device_move(id, track, index.saturating_sub(1)).lua()
        }
        fn device_set(lua, sh, (id, key, value) => (Id, String, LuaValue)) {
            sh.session.borrow_mut().device_set(id, &key, from_lua(lua, value)?).lua()
        }
        // Set a parameter of a device, named by its key, the device's own id for
        // it or its name. The value is a number, or text as the device reads it
        // ("440 Hz", "Saw").
        fn device_set_param(lua, sh, (id, name, value) => (Id, String, LuaValue)) {
            let mut session = sh.session.borrow_mut();
            let value = match value {
                LuaValue::String(text) => session.param_parse(id, &name, &text.to_str()?).lua()?,
                other => from_lua::<f64>(lua, other)?,
            };
            session.device_set_param(id, &name, value).lua()
        }
        // One parameter of a device, named by its key, the device's own id for it
        // or its name: its entry of `param_info`, with `value` (now) and `text`
        // (that value as the device writes it).
        fn device_param(lua, sh, (id, name) => (Id, String)) {
            let mut session = sh.session.borrow_mut();
            session.flush();
            to_lua(lua, &session.device_param(id, &name).lua()?)
        }
        // A value of a parameter as text, as the device writes it ("440 Hz").
        // Without a value, the value now.
        fn device_param_text(_, sh, (id, name, value) => (Id, String, Option<f64>)) {
            let mut session = sh.session.borrow_mut();
            session.flush();
            let value = match value {
                Some(value) => value,
                None => session.device_param(id, &name).lua()?["value"].as_f64().unwrap_or_default(),
            };
            session.param_text(id, &name, value).lua()
        }
        // The value that a text stands for, for a parameter, as the device reads it.
        // An error when the device cannot read the text.
        fn device_param_parse(_, sh, (id, name, text) => (Id, String, String)) {
            let mut session = sh.session.borrow_mut();
            session.flush();
            session.param_parse(id, &name, &text).lua()
        }

        // Load a preset into a device, as one undo step:
        // `{ name =, state =, params =, factory =, call = }`. `call = { method =,
        // data = }` is a `device_call` that changes the state of the plugin
        // (`property.set` of an LV2 plugin). The state after it is kept.
        fn device_load(lua, sh, (id, load) => (Id, LuaValue)) {
            sh.session.borrow_mut().device_load(id, options(lua, load)?).lua()
        }
        // The state of a plugin. Give it as `state` when you add a copy of the device.
        fn device_state(_, sh, id => Id) { sh.session.borrow_mut().device_state(id).lua() }

        // Show or hide the window of a plugin. With no second argument, toggle it.
        fn device_editor(_, sh, (id, open) => (Id, Option<bool>)) {
            sh.session.borrow_mut().device_editor(id, open).lua()
        }
        // Start again a device that stopped (a plugin that crashed).
        // @return nil
        fn device_restart(_, sh, id => Id) { sh.session.borrow_mut().device_restart(id).lua() }
        // Examine the plugin files again (all, or those that `name` matches). This
        // includes the files that failed before. Returns notes on the files that
        // paw cannot use, or nil without plugins.
        fn plugins_rescan(_, sh, name => Option<String>) {
            Ok(sh.session.borrow_mut().registry.rescan(name.as_deref()))
        }
        // Find CLAP and VST3 plugins in one more directory from now on (the
        // directory of an extension), and register the plugins in it. Returns
        // `{ kinds, notes }`: the device kinds found there and the files that paw
        // cannot use. Returns nil where paw cannot find plugins.
        fn plugins_add_dir(lua, sh, dir => String) {
            let found = sh.session.borrow_mut().registry.add_dir(std::path::Path::new(&dir));
            match found {
                Some((kinds, notes)) => to_lua(lua, &json!({ "kinds": kinds, "notes": notes })),
                None => Ok(LuaValue::Nil),
            }
        }
        // Load an attachment: a native library that an extension ships, which
        // paw offers each CLAP plugin that it makes from now on (see
        // `crates/paw-plugins/include/paw_attach.h`). Returns the name of the
        // attachment.
        fn plugins_attach(_, sh, path => String) {
            sh.session.borrow_mut().registry.attach(std::path::Path::new(&path)).lua()
        }
        // Stop to find plugins in a directory added with `plugins_add_dir`, and
        // make no more devices of `kinds`, the kinds found there. Devices that
        // exist continue to work.
        // @return nil
        fn plugins_remove_dir(_, sh, (dir, kinds) => (String, Vec<String>)) {
            sh.session.borrow_mut().registry.remove_dir(std::path::Path::new(&dir), &kinds);
            Ok(())
        }
        // What a plugin calls its keys, `{ [pitch] = name }` (CLAP `note-name`).
        fn device_note_names(lua, sh, id => Id) {
            let names = sh.session.borrow_mut().device_note_names(id);
            let table = lua.create_table_with_capacity(0, names.len())?;
            for (pitch, name) in names {
                table.raw_set(pitch, name)?;
            }
            Ok(table)
        }
        // Add devices that fail on purpose (`test.panic`, `test.nan`). Tests use
        // them to see what a bad device does to the other devices.
        // @return nil
        fn test_devices(_, sh, () => ()) {
            paw_engine::guard::register_test_devices(&mut sh.session.borrow_mut().registry);
            Ok(())
        }
        // Panic, as a bug in the program does. Tests use it to see what paw keeps.
        // @return nil
        fn test_panic(_, _sh, why => String) {
            if !why.is_empty() {
                panic!("{why}");
            }
            Ok(())
        }
        // Make plugins apart from the main loop (true), or wait for each as
        // it is added (false, what scripts start with). Returns what it was.
        // @return boolean
        fn load_apart(_, sh, on => bool) { Ok(sh.session.borrow_mut().set_load_apart(on)) }
        // A request to a device that accepts data from scripts. Bytes in, bytes out.
        fn device_call(lua, sh, (id, method, data) => (Id, String, Option<LuaString>)) {
            let data = data.as_ref().map(|d| d.as_bytes().to_vec()).unwrap_or_default();
            let answer = sh.session.borrow_mut().device_call(id, &method, &data).lua()?;
            lua.create_string(answer)
        }
        // Data for all devices of a kind, now and in the future (also the devices
        // of a render). nil removes the topic. Returns `{ { device, error } }` for
        // the devices that refused it.
        fn device_post(lua, sh, (kind, topic, data) => (String, String, Option<LuaString>)) {
            let data = data.as_ref().map(|d| d.as_bytes().to_vec());
            let refused = sh.session.borrow_mut().device_post(&kind, &topic, data.as_deref());
            let list: Vec<Value> = refused
                .into_iter()
                .map(|(device, error)| json!({ "device": device, "error": error }))
                .collect();
            to_lua(lua, &Value::Array(list))
        }
        // Devices of `old`, a kind that was renamed, are made as `new`.
        // @return nil
        fn device_alias(_, sh, (old, new) => (String, String)) {
            sh.session.borrow_mut().registry.alias(&old, &new);
            Ok(())
        }

        // --- clips ---
        fn clip_list(lua, sh, track => Id) { to_lua(lua, &sh.session.borrow().clip_list(track).lua()?) }
        fn clip_get(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().clip_view(id).lua()?) }
        // Where new recordings and bounces go: `media` beside the project
        // file, or the user's data directory before the project has one.
        fn media_dir(_, sh, () => ()) {
            Ok(sh.session.borrow().media_dir().to_string_lossy().into_owned())
        }
        // The sound files of the project (session/media.rs): the files that paw
        // cannot find, links to new paths, and copies into the folder of the project.
        fn media_list(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().media_list()) }
        // Long files are played from the disk: past how many megabytes of
        // decoded sound (0: never), and how many gigabytes of it are kept
        // between runs. With no arguments, what is set: megabytes, directory.
        fn media_store(_, sh, (megabytes, keep) => (Option<f64>, Option<f64>)) {
            let mut session = sh.session.borrow_mut();
            if let Some(megabytes) = megabytes {
                session.set_media_store(Some(crate::peaks::media_dir()), megabytes);
                if let (Some(keep), Some((dir, megabytes))) = (keep, session.media_store()) {
                    // Tidied apart: a big cache takes a while to look through.
                    let store = paw_engine::DiskStore { dir, limit: (megabytes * 1_048_576.0) as u64 };
                    std::thread::spawn(move || store.tidy((keep.max(0.0) * 1_073_741_824.0) as u64));
                }
            }
            Ok(match session.media_store() {
                Some((dir, megabytes)) => (megabytes, Some(dir.to_string_lossy().into_owned())),
                None => (0.0, None),
            })
        }
        fn media_missing(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().media_missing()) }
        fn media_relink(lua, sh, (from, to) => (String, String)) {
            to_lua(lua, &sh.session.borrow_mut().media_relink(from.as_ref(), to.as_ref()).lua()?)
        }
        fn media_search(lua, sh, dir => String) {
            to_lua(lua, &sh.session.borrow_mut().media_search(dir.as_ref()).lua()?)
        }
        fn media_collect(lua, sh, () => ()) {
            to_lua(lua, &sh.session.borrow_mut().media_collect().lua()?)
        }
        fn media_adopt(_, sh, file => String) {
            let path = sh.session.borrow_mut().media_adopt(file.as_ref()).lua()?;
            Ok(path.to_string_lossy().into_owned())
        }
        // Audio clip operations that leave the source file alone (session/clipops.rs).
        fn clip_reverse(lua, sh, id => Id) {
            to_lua(lua, &sh.session.borrow_mut().clip_reverse(id).lua()?)
        }
        // Add an edit to an audio clip's edit list (`edits.rs`): `{ kind =
        // "gain", from, to, db }` or `{ kind = "pencil", at, channel, values }`,
        // in seconds from where the clip starts in its sound. Returns how many
        // edits it has.
        fn clip_edit_add(lua, sh, (id, edit) => (Id, LuaValue)) {
            let edit: crate::edits::AudioEdit = from_lua(lua, edit)?;
            sh.session.borrow_mut().clip_edit_add(id, edit).lua()
        }
        // Take away an audio clip's edit list. Returns how many edits it had.
        fn clip_edits_clear(_, sh, id => Id) {
            sh.session.borrow_mut().clip_edits_clear(id).lua()
        }
        // An audio clip's edit list, as `clip_edit_add` takes its edits (with
        // times in seconds of its sound).
        fn clip_edits(lua, sh, id => Id) {
            let session = sh.session.borrow();
            let clip = session.project.clip(id).ok_or_else(|| mlua::Error::runtime(format!("no clip {id}")))?;
            let edits = match &clip.content {
                ClipContent::Audio { edits, .. } => edits.clone(),
                _ => Vec::new(),
            };
            to_lua(lua, &edits)
        }
        fn clip_normalize(_, sh, (id, level) => (Id, Option<f64>)) {
            sh.session.borrow_mut().clip_normalize(id, level.unwrap_or(0.0)).lua()
        }
        fn clip_glue(lua, sh, ids => Vec<Id>) {
            to_lua(lua, &sh.session.borrow_mut().clip_glue(&ids).lua()?)
        }
        // Warp markers of an audio clip (`session/stretching.rs`), counted from 1.
        fn clip_warp_add(_, sh, (id, beat) => (Id, f64)) {
            Ok(sh.session.borrow_mut().warp_add(id, beat).lua()? + 1)
        }
        fn clip_warp_move(_, sh, (id, index, beat) => (Id, usize, f64)) {
            let index = index.checked_sub(1).ok_or_else(|| mlua::Error::runtime("warp markers count from 1"))?;
            Ok(sh.session.borrow_mut().warp_move(id, index, beat).lua()? + 1)
        }
        fn clip_warp_remove(_, sh, (id, index) => (Id, usize)) {
            let index = index.checked_sub(1).ok_or_else(|| mlua::Error::runtime("warp markers count from 1"))?;
            sh.session.borrow_mut().warp_remove(id, index).lua()
        }
        // Beats of sound left in an audio clip's file from where the clip starts in it.
        // @return number
        fn clip_source_length(_, sh, id => Id) { sh.session.borrow_mut().clip_source_length(id).lua() }
        fn clip_add(lua, sh, (track, opts) => (Id, LuaValue)) {
            sh.session.borrow_mut().clip_add(track, options(lua, opts)?).lua()
        }
        // @return nil
        fn clip_remove(_, sh, id => Id) { sh.session.borrow_mut().clip_remove(id).lua() }

        // --- cues (session/cues.rs) ---
        // A clip goes off the timeline with `clip_add(track, { cue = true, ... })`:
        // it starts at 0, loops over its length, and plays only when cued.
        // You edit it as a usual clip; `clip_set(id, "track", other)` moves it.
        fn cue_list(lua, sh, track => Id) { to_lua(lua, &sh.session.borrow().cue_list(track).lua()?) }
        // Copy a clip, with its `meta`, off the timeline of a track. Returns the copy's id.
        fn clip_to_cues(_, sh, (id, track) => (Id, Id)) {
            sh.session.borrow_mut().clip_to_cues(id, track).lua()
        }
        // `{ { track =, clip = id }, { track =, stop = true },
        // { track =, timeline = true }, ... }`, each with `quantize` (`bar`
        // when not given: off 1/16 1/8 1/4 beat bar 2bars 4bars), `legato`
        // and `from`: all on their boundary, timed together by the engine.
        fn cue(lua, sh, list => LuaValue) {
            sh.session.borrow_mut().cue(from_lua(lua, list)?).lua()
        }
        // What each track plays and has in its queue, in the last report of the engine.
        fn cue_state(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().cue_state()) }
        fn clip_set(lua, sh, (id, key, value) => (Id, String, LuaValue)) {
            sh.session.borrow_mut().clip_set(id, &key, from_lua(lua, value)?).lua()
        }
        // `n` { min, max } pairs for all of the sound that an audio clip plays.
        fn clip_peaks(lua, sh, (id, n) => (Id, usize)) {
            to_lua(lua, &sh.session.borrow_mut().clip_peaks(id, n).lua()?)
        }
        // `n` { min, max, rms } for `seconds` of a sound file from `offset`
        // seconds: the sound that the other takes of a clip would play.
        fn media_peaks(lua, sh, (file, offset, seconds, n) => (String, f64, f64, usize)) {
            let peaks = sh.session.borrow_mut().media_peaks(file.as_ref(), offset, seconds, n).lua()?;
            to_lua(lua, &peaks)
        }
        // The notes of a MIDI clip, in the order of their start. With a range
        // `{ from, to, low, high }` (beats in the clip, pitches), only the notes
        // that sound in it. The second value is then the place of each note in
        // the whole list.
        fn clip_notes(lua, sh, (id, range) => (Id, LuaValue)) {
            let session = sh.session.borrow();
            if range.is_nil() {
                let notes = notes_to_lua(lua, session.clip_notes(id).lua()?)?;
                return Ok(mlua::Variadic::from_iter([notes]));
            }
            let range: NoteRange = from_lua(lua, range)?;
            let found = session.clip_notes_in(id, &range).lua()?;
            let notes = lua.create_table_with_capacity(found.len(), 0)?;
            notes.set_metatable(Some(lua.array_metatable()))?;
            let places = lua.create_table_with_capacity(found.len(), 0)?;
            for (i, (index, note)) in found.into_iter().enumerate() {
                notes.raw_seti(i + 1, note_to_lua(lua, note)?)?;
                places.raw_seti(i + 1, index + 1)?;
            }
            Ok(mlua::Variadic::from_iter([LuaValue::Table(notes), LuaValue::Table(places)]))
        }
        // The note on `pitch` that sounds at `beat`, and its place in the notes of
        // the clip. Nothing when there is no such note.
        fn clip_note_at(lua, sh, (id, pitch, beat) => (Id, u8, f64)) {
            Ok(match sh.session.borrow().clip_note_at(id, pitch, beat).lua()? {
                Some((index, note)) => (Some(note_to_lua(lua, note)?), Some(index + 1)),
                None => (None, None),
            })
        }
        // One note at a time, by its place in the notes of the clip (from 1).
        // The functions that add and change a note return its new place,
        // because the notes stay in the order of their start.
        fn clip_note_add(lua, sh, (id, note) => (Id, LuaValue)) {
            let note: Note = from_lua(lua, note)?;
            Ok(sh.session.borrow_mut().clip_note_add(id, note).lua()? + 1)
        }
        fn clip_note_set(lua, sh, (id, index, fields) => (Id, usize, LuaValue)) {
            let change: NoteChange = from_lua(lua, fields)?;
            let index = note_index(index)?;
            Ok(sh.session.borrow_mut().clip_note_set(id, index, &change).lua()? + 1)
        }
        fn clip_note_remove(_, sh, (id, index) => (Id, usize)) {
            sh.session.borrow_mut().clip_note_remove(id, note_index(index)?).lua()
        }
        // Several at once, as one edit: `{ set = { { index = 3, start = 1 } },
        // remove = { 5, 6 }, add = { note, ... } }`. Every index is a note's
        // place before the call.
        fn clip_notes_edit(lua, sh, (id, edit) => (Id, LuaValue)) {
            let mut edit: NotesEdit = from_lua(lua, edit)?;
            for change in edit.set.iter_mut() {
                change.index = change.index.map(note_index).transpose()?;
            }
            for index in edit.remove.iter_mut() {
                *index = note_index(*index)?;
            }
            sh.session.borrow_mut().clip_notes_edit(id, edit).lua()
        }
        fn clip_set_notes(lua, sh, (id, notes) => (Id, LuaValue)) {
            let notes = notes_from_lua(lua, notes)?;
            sh.session.borrow_mut().clip_set_notes(id, notes, false).lua()
        }
        fn clip_add_notes(lua, sh, (id, notes) => (Id, LuaValue)) {
            let notes = notes_from_lua(lua, notes)?;
            sh.session.borrow_mut().clip_set_notes(id, notes, true).lua()
        }
        // Controller, pitch wheel and pressure moves of a MIDI clip:
        // { start, type = "cc" | "bend" | "pressure", number, value }.
        fn clip_controls(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().clip_controls(id).lua()?) }
        fn clip_set_controls(lua, sh, (id, controls) => (Id, LuaValue)) {
            let controls: Vec<Control> = from_lua(lua, controls)?;
            sh.session.borrow_mut().clip_set_controls(id, controls).lua()
        }

        // --- automation ---
        fn lane_list(lua, sh, track => Id) { to_lua(lua, &sh.session.borrow().lane_list(track).lua()?) }
        fn lane_get(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().lane_view(id).lua()?) }
        fn lane_add(lua, sh, (track, opts) => (Id, LuaValue)) {
            sh.session.borrow_mut().lane_add(track, from_lua(lua, opts)?).lua()
        }
        // @return nil
        fn lane_remove(_, sh, id => Id) { sh.session.borrow_mut().lane_remove(id).lua() }
        fn lane_set(lua, sh, (id, key, value) => (Id, String, LuaValue)) {
            sh.session.borrow_mut().lane_set(id, &key, from_lua(lua, value)?).lua()
        }
        fn lane_points(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().lane_points(id).lua()?) }
        fn lane_set_points(lua, sh, (id, points) => (Id, LuaValue)) {
            let points: Vec<(f64, f64)> = from_lua(lua, points)?;
            sh.session.borrow_mut().lane_set_points(id, points, false).lua()
        }
        fn lane_add_point(_, sh, (id, beat, value) => (Id, f64, f64)) {
            sh.session.borrow_mut().lane_set_points(id, vec![(beat, value)], true).lua()
        }
        fn lane_value_at(_, sh, (id, beat) => (Id, f64)) { sh.session.borrow().lane_value_at(id, beat).lua() }
        // The shapes of the stretches that are not straight, `{ beat, shape, tension }`
        // each by the beat of the point they leave: "hold" or "smooth".
        fn lane_shapes(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().lane_shapes(id).lua()?) }
        fn lane_set_shapes(lua, sh, (id, shapes) => (Id, LuaValue)) {
            let shapes: Vec<crate::model::Segment> = from_lua(lua, shapes)?;
            sh.session.borrow_mut().lane_set_shapes(id, shapes).lua()
        }
        // The states of a state lane, whole: `{ name, state, params, call =
        // { method, data }, program, bank }` each. A point's value is the
        // index of one, from 0.
        fn lane_states(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().lane_states(id).lua()?) }
        // Replace the states of a state lane, as one undo step. A point
        // that names a state no longer there names the last.
        fn lane_set_states(lua, sh, (id, states) => (Id, LuaValue)) {
            let states: Vec<crate::model::LaneState> = from_lua(lua, states)?;
            sh.session.borrow_mut().lane_set_states(id, states).lua()
        }
        // Add a state to a state lane, or replace the one of its name, as
        // one undo step. Returns its index, from 0.
        fn lane_add_state(lua, sh, (id, state) => (Id, LuaValue)) {
            let state: crate::model::LaneState = from_lua(lua, state)?;
            sh.session.borrow_mut().lane_add_state(id, state).lua()
        }
        // A control is held (a fader under the pointer) or let go: in touch
        // mode it writes automation for as long as it is held. The control
        // is named as a lane's target is.
        fn automation_hold(_, sh, (track, target, device, param, on) => (Id, String, Option<Id>, Option<String>, bool)) {
            sh.session.borrow_mut().automation_hold_named(track, &target, device, param, on).lua()
        }

        // --- transport ---
        fn transport_get(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().transport_view()) }
        fn transport_set(lua, sh, (key, value) => (String, LuaValue)) {
            sh.session.borrow_mut().transport_set(&key, from_lua(lua, value)?).lua()
        }
        // @return nil
        fn transport_play(_, sh, () => ()) {
            sh.session.borrow_mut().play();
            Ok(())
        }
        // @return nil
        fn transport_stop(_, sh, () => ()) {
            sh.session.borrow_mut().stop();
            Ok(())
        }
        // @return nil
        fn transport_seek(_, sh, beats => f64) {
            sh.session.borrow_mut().seek(beats);
            Ok(())
        }
        // Play a note on a track, with a MIDI 2.0 attribute if one is given.
        fn note_on(lua, sh, (track, pitch, velocity, attr) => (Id, u8, Option<f64>, LuaValue)) {
            let vel = live_velocity(velocity)?;
            if pitch > 127 {
                return Err(mlua::Error::runtime(format!("a pitch goes up to 127, not {pitch}")));
            }
            let attr = attr_from_lua(lua, attr)?.map_or(paw_engine::Attr::NONE, Into::into);
            sh.session.borrow_mut().live_note(track, pitch, vel, attr).lua()
        }
        fn note_off(_, sh, (track, pitch) => (Id, Option<u8>)) {
            match pitch {
                Some(key) => sh.session.borrow_mut().live_note_off(track, key).lua(),
                None => sh.session.borrow_mut().live(track, EventKind::AllNotesOff).lua(),
            }
        }
        // @return nil
        fn transport_record(_, sh, () => ()) { sh.session.borrow_mut().record().lua() }

        // --- audition (session/audition.rs) ---
        // `trial_end(false)` discards the edits made after `trial_begin`. The
        // project is then as it was and the undo history does not change.
        // `trial_end(true)` keeps the edits as one step.
        // @return nil
        fn trial_begin(_, sh, () => ()) { sh.session.borrow_mut().trial_begin().lua() }
        // @return boolean
        fn trial_end(_, sh, keep => Option<bool>) { Ok(sh.session.borrow_mut().trial_end(keep.unwrap_or(false))) }
        // @return boolean
        fn trial_active(_, sh, () => ()) { Ok(sh.session.borrow().trial_active()) }
        // A sound file heard on its own over everything, outside the project.
        // @return nil
        fn preview_play(_, sh, file => String) { sh.session.borrow_mut().preview_play(std::path::Path::new(&file)).lua() }
        // @return nil
        fn preview_stop(_, sh, () => ()) {
            sh.session.borrow_mut().preview_stop();
            Ok(())
        }
        // @return nil
        fn preview_level(_, sh, db => f64) {
            sh.session.borrow_mut().preview_set_level(db);
            Ok(())
        }
        fn preview_get(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().preview_view()) }

        // --- MIDI input ---
        fn midi_inputs(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().midi_inputs()) }
        // A port of paw that other programs can send MIDI to. `midi_close_port`
        // returns true if there was such a port to remove.
        // @return nil
        fn midi_open_port(_, sh, name => String) { sh.session.borrow_mut().midi_open_port(&name).lua() }
        // @return boolean
        fn midi_close_port(_, sh, name => String) { Ok(sh.session.borrow_mut().midi_close_port(&name)) }
        // --- MIDI output ---
        fn midi_outputs(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().midi_outputs()) }
        // A port of paw that other programs can read MIDI from. `midi_close_output`
        // returns true if there was such a port to remove.
        // @return nil
        fn midi_open_output(_, sh, name => String) { sh.session.borrow_mut().midi_open_output(&name).lua() }
        // @return boolean
        fn midi_close_output(_, sh, name => String) { Ok(sh.session.borrow_mut().midi_close_output(&name)) }
        // Open only the ports that match these ids or names, or all of them with nil.
        // @return nil
        fn midi_select(_, sh, which => Option<Vec<String>>) {
            sh.session.borrow_mut().midi_select(which);
            Ok(())
        }
        // With `port`, as if from the port of that name.
        // @return nil
        fn midi_inject(lua, sh, event => LuaValue) {
            let (port, event): (Option<String>, LuaValue) = match &event {
                LuaValue::Table(table) => {
                    // The port is where it came from, not part of the message.
                    let copy = lua.create_table()?;
                    for pair in table.pairs::<LuaValue, LuaValue>() {
                        let (key, value) = pair?;
                        copy.set(key, value)?;
                    }
                    copy.set("port", LuaValue::Nil)?;
                    (table.get("port")?, LuaValue::Table(copy))
                }
                _ => (None, event),
            };
            let kind = midi_kind(lua, event)?;
            sh.session.borrow_mut().midi_inject(kind, port.as_deref());
            Ok(())
        }
        // A Universal MIDI Packet (one or two 32-bit words), as if from a MIDI
        // 2.0 port. Returns true if the engine plays that message.
        fn midi_inject_ump(_, sh, words => Vec<u32>) {
            match ump::decode(&words) {
                Some((_, kind)) => {
                    sh.session.borrow_mut().midi_inject(kind, None);
                    Ok(true)
                }
                None => Ok(false),
            }
        }
        // What an event is as a MIDI 2.0 packet: two 32-bit words.
        fn midi_ump(lua, _sh, event => LuaValue) {
            let kind = midi_kind(lua, event)?;
            Ok(ump::encode(0, kind).map(|words| words.to_vec()))
        }
        // Send a MIDI message to one track's devices right now, outside the timeline.
        fn midi_send(lua, sh, (track, event) => (Id, LuaValue)) {
            let kind = midi_kind(lua, event)?;
            sh.session.borrow_mut().live(track, kind).lua()
        }

        // --- engine ---
        fn engine_get(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().engine_info()) }
        // The number of audio blocks that the engine finished since it
        // started. With a device id, the number of blocks that this device
        // ran: the blocks that it slept through do not count. A change sent
        // to the engine is in effect in the block after the next one that
        // finishes, so wait until the count is two more (the test helper
        // `T.next_block` does this). Nil for a device that the engine does
        // not have.
        fn blocks(_, sh, device => Option<Id>) {
            Ok(sh.session.borrow().blocks(device))
        }
        // Forget the process times that `engine_get().blocks` recorded until now.
        // @return nil
        fn engine_reset_stats(_, sh, () => ()) {
            sh.session.borrow().engine_reset_stats();
            Ok(())
        }
        // Play a track from a sound file for now, as if it is frozen, or live
        // again with nil. The project does not change (see `freeze.rs`).
        fn engine_hold(_, sh, (track, file) => (Id, Option<String>)) {
            sh.session.borrow_mut().hold(track, file.map(PathBuf::from)).lua()
        }
        // @return {integer}
        fn engine_held(_, sh, () => ()) { Ok(sh.session.borrow().held()) }
        // Only these tracks heard for now, as a solo would, or all with nil.
        // @return nil
        fn engine_audible(_, sh, tracks => Option<Vec<Id>>) {
            sh.session.borrow_mut().set_audible(tracks);
            Ok(())
        }
        // The track that plays MIDI input while no track is armed, as if
        // monitored, or none with nil (`paw.opt.midi_follows_selection`).
        // @return nil
        fn engine_follow(_, sh, track => Option<Id>) {
            sh.session.borrow_mut().set_follow(track);
            Ok(())
        }
        // The number of threads that process tracks, with the audio thread. 0
        // lets paw select the number. `engine_get().threads` gives the number in use.
        fn engine_set_threads(_, sh, threads => usize) {
            sh.session.borrow_mut().set_threads(threads).lua()
        }
        // With true, devices at rest sleep through silence: a reverb after
        // its tail, a synth with no note that sounds. The sound is the same
        // with false. `engine_get().device_sleeps` counts the blocks that
        // devices slept through.
        // @return nil
        fn engine_set_sleep(_, sh, sleep => bool) {
            sh.session.borrow_mut().set_sleep(sleep);
            Ok(())
        }
        fn engine_restart(lua, sh, opts => LuaValue) {
            let opts: EngineOpts = options(lua, opts)?;
            let backend = BackendOptions {
                backend: opts.backend.unwrap_or_else(|| "auto".into()),
                sample_rate: opts.sample_rate,
                buffer_size: opts.buffer_size,
                input: opts.input.unwrap_or(true),
                output_device: opts.output_device,
                input_device: opts.input_device,
                test_input: opts.test_input.map(|t| TestInput {
                    frequency: t.frequency,
                    level: t.level,
                    channels: t.channels,
                }),
            };
            let mut session = sh.session.borrow_mut();
            session.set_test_ports(opts.test_midi.unwrap_or_default());
            session.set_midi_without_audio(opts.midi.unwrap_or(false));
            session.engine_restart(&backend).lua()
        }
        // The audio devices the system offers, and which are open.
        fn audio_devices(lua, sh, () => ()) {
            to_lua(lua, &sh.session.borrow().audio_devices().lua()?)
        }
        // Try to open again the device that went away. Returns true when it is open.
        // @return boolean
        fn audio_reconnect(_, sh, () => ()) { sh.session.borrow_mut().audio_reconnect().lua() }
        // With `{ auto = false }`, paw does not open again a device that returns
        // by itself. `period` is the interval between checks, in milliseconds.
        // @return nil
        fn audio_watch(lua, sh, opts => LuaValue) {
            let opts: AudioWatchOpts = options(lua, opts)?;
            let period = opts.period.map(|ms| Duration::from_secs_f64(ms.max(0.0) / 1000.0));
            sh.session.borrow_mut().set_audio_watch(opts.auto, period);
            Ok(())
        }
        // The simulated device of the `test` backend. `{ present = false }`
        // disconnects it. `fail_after = n` disconnects it after n blocks of the
        // next stream. `back_after = ms` connects it again `ms` after it goes.
        // @return nil
        fn audio_test_device(lua, _sh, opts => LuaValue) {
            let opts: TestDeviceOpts = options(lua, opts)?;
            paw_engine::backend::test_device::set(opts.present, opts.fail_after, opts.back_after);
            Ok(())
        }
        // The MIDI ports the null backend lists, as if plugged in.
        // @return nil
        fn midi_test_ports(_, sh, ports => Vec<String>) {
            sh.session.borrow_mut().set_test_ports(ports);
            Ok(())
        }
        // Open other devices, and remember them for the next run.
        fn audio_use(lua, sh, opts => LuaValue) {
            let opts: AudioUseOpts = options(lua, opts)?;
            let choice = crate::session::AudioChoice { backend: opts.backend, rate: opts.rate };
            sh.session.borrow_mut().audio_use(opts.output, opts.input, opts.buffer, choice).lua()
        }
        // The level of each input channel of the device, as linear gain,
        // whatever takes it.
        fn input_levels(_, sh, () => ()) { Ok(sh.session.borrow().input_levels()) }
        // What a render can write: `{ { name = "WAV", extensions = { "wav" } } }`.
        fn render_formats(lua, _sh, ffmpeg => Option<String>) {
            to_lua(lua, &crate::session::render::formats_json(ffmpeg.as_deref()))
        }
        // Nothing when a render can write `path`, or why not.
        fn render_check(_, _sh, (path, ffmpeg) => (String, Option<String>)) {
            Ok(crate::session::render::format_of(path.as_ref(), ffmpeg.as_deref()).err().map(|e| e.to_string()))
        }
        fn render(lua, sh, (path, opts) => (String, LuaValue)) {
            let opts: RenderOpts = options(lua, opts)?;
            to_lua(lua, &sh.session.borrow_mut().render(path.as_ref(), &opts).lua()?)
        }
        // Start a render on a separate thread. Then the events `render.progress`
        // and `render.done`, `render.failed` or `render.cancelled` come.
        fn render_start(lua, sh, (path, opts) => (String, LuaValue)) {
            let opts: RenderOpts = options(lua, opts)?;
            sh.session.borrow_mut().render_start(path.as_ref(), &opts).lua()
        }
        // @return boolean
        fn render_cancel(_, sh, () => ()) { Ok(sh.session.borrow_mut().render_cancel()) }
        // The render that runs now, `{ path, fraction, seconds, cancelling }`, or nil.
        fn render_status(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().render_status()) }

        // --- undo ---
        fn undo(_, sh, () => ()) { Ok(sh.session.borrow_mut().undo()) }
        fn redo(_, sh, () => ()) { Ok(sh.session.borrow_mut().redo()) }
        // @return nil
        fn undo_checkpoint(_, sh, () => ()) {
            sh.session.borrow_mut().checkpoint();
            Ok(())
        }
        // `undo_pending` is true if the edits of this turn will close as a step.
        // `undo_discard` puts back what they changed, and no step closes
        // (`edit.before`, paw/hooks.tl).
        // @return boolean
        fn undo_pending(_, sh, () => ()) { Ok(sh.session.borrow().undo_pending()) }
        // @return boolean
        fn undo_discard(_, sh, () => ()) { Ok(sh.session.borrow_mut().undo_discard()) }
        // Make the project as it is now the start of its undo history, and
        // unchanged: a MIDI file opened as a project (paw/midifile.lua).
        // @return nil
        fn undo_reset(_, sh, () => ()) {
            sh.session.borrow_mut().undo_reset();
            Ok(())
        }
        // The undo tree and checkpoints: crate::history, session/undo.rs.
        fn undo_tree(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().undo_tree()) }
        // How many steps the history keeps, and about how many bytes of what
        // they changed: `paw.opt.undo_steps` and `undo_memory` set these.
        fn undo_limits(_, sh, (steps, bytes) => (Option<usize>, Option<usize>)) {
            sh.session.borrow_mut().undo_limits(steps, bytes).lua()
        }
        fn undo_current(_, sh, () => ()) { Ok(sh.session.borrow().undo_current()) }
        // @return boolean
        fn undo_goto(_, sh, id => u64) { Ok(sh.session.borrow_mut().undo_goto(id)) }
        fn undo_step(_, sh, n => i64) { Ok(sh.session.borrow_mut().undo_step(n)) }
        fn undo_travel(_, sh, seconds => f64) { Ok(sh.session.borrow_mut().undo_travel(seconds)) }
        fn undo_name(_, sh, (name, id) => (Option<String>, Option<u64>)) {
            sh.session.borrow_mut().undo_name(id, name).lua()
        }
        fn undo_keep(_, sh, (id, keep) => (u64, Option<bool>)) {
            sh.session.borrow_mut().undo_keep(id, keep.unwrap_or(true)).lua()
        }
        fn undo_diff(lua, sh, (a, b) => (Option<u64>, Option<u64>)) {
            to_lua(lua, &sh.session.borrow_mut().undo_diff(a, b).lua()?)
        }
        // A state's project as a project file holds it (the current state's
        // by default), and the text of a project file for a project given as
        // data: see extensions/projdiff.
        fn undo_project(lua, sh, id => Option<u64>) {
            to_lua(lua, &sh.session.borrow_mut().undo_project(id).lua()?)
        }
        fn project_file_text(lua, _sh, value => LuaValue) {
            crate::session::project_file_text(from_lua(lua, value)?).lua()
        }
        // A MIDI 2.0 clip file (`.midi2`): `{ notes, controls, length,
        // skipped }`, with times in beats; `skipped` says what the file held
        // that a clip has no place for.
        fn midi2_read(lua, _sh, path => String) {
            let bytes = std::fs::read(&path).map_err(|e| mlua::Error::runtime(format!("{path}: {e}")))?;
            let clip = crate::clipfile::decode(&bytes).lua()?;
            to_lua(lua, &json!({
                "notes": clip.notes, "controls": clip.controls, "length": clip.length, "skipped": clip.skipped,
            }))
        }
        // Write notes and controller moves (`{ notes, controls, length }`) as
        // a MIDI 2.0 clip file, all or nothing.
        fn midi2_write(lua, _sh, (path, clip) => (String, LuaValue)) {
            #[derive(Deserialize)]
            struct Given {
                #[serde(default)]
                notes: Vec<Note>,
                #[serde(default)]
                controls: Vec<Control>,
                #[serde(default)]
                length: f64,
            }
            let given: Given = from_lua(lua, clip)?;
            let bytes = crate::clipfile::encode(&given.notes, &given.controls, given.length);
            crate::safe::write_file(Path::new(&path), &bytes, false).lua()
        }
        // A MIDI 2.0 clip file as text, one note or controller move to a line,
        // as `paw clip cat` prints it.
        fn midi2_text(_, _sh, path => String) {
            let bytes = std::fs::read(&path).map_err(|e| mlua::Error::runtime(format!("{path}: {e}")))?;
            Ok(crate::clipfile::text(&crate::clipfile::decode(&bytes).lua()?))
        }
        // Give a name to the open step. The first name wins. nil removes a name
        // given while the step changed nothing.
        // @return nil
        fn undo_label(_, sh, text => Option<String>) {
            sh.session.borrow_mut().undo_label(text);
            Ok(())
        }
        // The edits of this turn join undo state `id`, the current one, and do
        // not make a step of their own. For example, a snippet changed its choice.
        // @return boolean
        fn undo_join(_, sh, id => u64) { Ok(sh.session.borrow_mut().undo_join(id)) }
        // @return nil
        fn undo_keys(_, sh, text => String) {
            sh.session.borrow_mut().undo_keys(text);
            Ok(())
        }
        fn checkpoint_dir(_, sh, () => ()) {
            Ok(sh.session.borrow().checkpoint_dir().map(|p| p.to_string_lossy().into_owned()))
        }
        fn checkpoint_write(lua, sh, (name, id) => (String, Option<u64>)) {
            to_lua(lua, &sh.session.borrow_mut().checkpoint_write(&name, id).lua()?)
        }
        fn checkpoint_list(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().checkpoint_list()) }
        fn checkpoint_restore(_, sh, file => String) {
            sh.session.borrow_mut().checkpoint_restore(&file).lua()
        }
        fn checkpoint_delete(_, sh, file => String) {
            sh.session.borrow_mut().checkpoint_delete(&file).lua()
        }

        // --- screen ---
        // @return nil
        fn ui_redraw(_, sh, () => ()) {
            sh.dirty.set(true);
            sh.redraws.set(sh.redraws.get() + 1);
            Ok(())
        }
        fn ui_redraws(_, sh, () => ()) { Ok(sh.redraws.get()) }
        // Draw only the live parts of the screen again (the playhead, the
        // meters, the status line), on the frame drawn last; a whole frame
        // when one is asked for too, or the runtime says it is needed.
        // @return nil
        fn ui_redraw_live(_, sh, () => ()) {
            sh.live_dirty.set(true);
            Ok(())
        }
        // The frames drawn so far: `{ full, live, unchanged }`: whole frames,
        // frames of the live parts only, and of those the ones that changed
        // no cell, which were not sent.
        fn ui_frames(lua, sh, () => ()) {
            let [full, live, unchanged] = sh.frames.get();
            let t = lua.create_table()?;
            t.set("full", full)?;
            t.set("live", live)?;
            t.set("unchanged", unchanged)?;
            Ok(t)
        }
        fn ui_size(_, sh, () => ()) {
            let grid = sh.grid.borrow();
            Ok((grid.width, grid.height))
        }
        fn ui_attached(_, sh, () => ()) { Ok(sh.attached.get()) }
        // @return nil
        fn ui_cursor(_, sh, (x, y) => (Option<f64>, Option<f64>)) {
            sh.cursor.set(x.zip(y).map(|(x, y)| (x.max(0.0) as u16, y.max(0.0) as u16)));
            Ok(())
        }
        // True if the terminal reports the pointer (`paw.opt.mouse`), for the
        // screen that paw draws now.
        // @return nil
        fn ui_mouse(_, sh, on => bool) {
            sh.grid.borrow_mut().mouse_off = !on;
            Ok(())
        }
        // What the terminal of the seat whose turn it is can show besides
        // cells: `{ graphics, pixels, cell = { w, h }, pixel_mouse, fg, bg }`,
        // `pixels` when a view can be shown in pixels there.
        fn ui_caps(lua, sh, () => ()) {
            let caps = sh.caps.borrow().get(&sh.seat.get()).copied().unwrap_or_default();
            to_lua(lua, &caps_lua(&caps))
        }
        // Say what that terminal can show, in the same form: its frontend
        // does when it starts, and tests do.
        fn ui_caps_set(lua, sh, caps => LuaValue) {
            let mut value: Value = lua.from_value(caps)?;
            // An empty table comes as an empty list.
            if value.as_array().is_some_and(Vec::is_empty) {
                value = json!({});
            }
            let Some(fields) = value.as_object_mut() else {
                return Err(mlua::Error::runtime("ui_caps_set takes a table: { graphics, pixels, cell = { w, h }, … }"));
            };
            let cell = fields.get("cell").map_or((Value::Null, Value::Null), |c| (c["w"].clone(), c["h"].clone()));
            fields.insert("cell".into(), json!([cell.0, cell.1]));
            sh.caps.borrow_mut().insert(sh.seat.get(), Caps::from_json(&value));
            sh.dirty.set(true);
            Ok(())
        }
        // Keep the cells `(x, y, w, h)`, clipped to `(cx, cy, cw, ch)`, for pixels
        // under the name `key` (`buf:strip`), over the text or `under` it.
        // Returns the number of the surface for `grid_surface_ops`, or nil when
        // no part of it is on the screen.
        fn grid_surface(_, sh, (key, x, y, w, h, cx, cy, cw, ch, under) => (String, f64, f64, f64, f64, f64, f64, f64, f64, Option<bool>)) {
            let cell_px = sh.caps.borrow().get(&sh.seat.get()).map_or((0, 0), |c| c.cell);
            let clip = Rect { x: cell(cx), y: cell(cy), w: cell(cw), h: cell(ch) };
            let whole = Rect { x: cell(x), y: cell(y), w: cell(w), h: cell(h) };
            Ok(sh.grid.borrow_mut().surface_part(&key, whole, clip, cell_px, under.unwrap_or(false)).map(|i| i + 1))
        }
        // The view being drawn is done with the surfaces it kept: what is
        // drawn over them from now on covers them.
        // @return nil
        fn grid_surfaces_seal(_, sh, () => ()) {
            sh.grid.borrow_mut().seal_surfaces();
            Ok(())
        }
        // The drawing a surface shows: the operations of `paw.canvas.paint`.
        // @return nil
        fn grid_surface_ops(lua, sh, (index, ops) => (usize, LuaValue)) {
            let ops: Value = lua.from_value(ops)?;
            if let Some(surface) = sh.grid.borrow_mut().surfaces.get_mut(index.wrapping_sub(1)) {
                surface.ops = Arc::new(ops);
            }
            Ok(())
        }
        // A live part of the screen is drawn over the cells `(x, y, w, h)`,
        // clipped to `(cx, cy, cw, ch)`: what is under them is kept, to draw
        // it again by itself (`paw.ui.render_live`). Returns its number for
        // `grid_live_end`, or nil when no part of it is on the screen.
        fn grid_live_begin(_, sh, (x, y, w, h, cx, cy, cw, ch) => (f64, f64, f64, f64, f64, f64, f64, f64)) {
            let clip = Rect { x: cell(cx), y: cell(cy), w: cell(cw), h: cell(ch) };
            let area = Rect { x: cell(x), y: cell(y), w: cell(w), h: cell(h) };
            Ok(sh.grid.borrow_mut().live_begin(area.intersect(&clip)).map(|i| i + 1))
        }
        // @return nil
        fn grid_live_end(_, sh, index => usize) {
            sh.grid.borrow_mut().live_end(index.wrapping_sub(1));
            Ok(())
        }
        // The frame is drawn: what is over the live parts now stays over them.
        // @return nil
        fn grid_live_seal(_, sh, () => ()) {
            sh.grid.borrow_mut().live_seal();
            Ok(())
        }
        // Take the live parts off the frame drawn last, to draw them again.
        // Returns how many there were.
        fn grid_live_restore(_, sh, () => ()) {
            Ok(sh.grid.borrow_mut().live_restore())
        }
        // A music font's SMuFL metadata (`Leland`, the default, `Bravura` or
        // `Petaluma`): `engravingDefaults`, `glyphBBoxes`, `glyphsWithAnchors`
        // and `glyphs` (every glyph name with its code point). Nil for a
        // font there is none of.
        fn smufl(lua, _sh, font => Option<String>) {
            match paw_raster::smufl(font.as_deref()) {
                Some(meta) => to_lua(lua, &meta),
                None => Ok(LuaValue::Nil),
            }
        }
        // A music font's glyph as path commands in staff spaces from its
        // origin, y down (`{ "M", x, y, "C", ... }`), for a frontend that
        // cannot draw the font. Nil for a glyph or font there is none of.
        fn smufl_outline(lua, _sh, (font, codepoint) => (Option<String>, u32)) {
            match paw_raster::glyph_outline(font.as_deref(), codepoint) {
                Some(path) => to_lua(lua, &serde_json::Value::from(path)),
                None => Ok(LuaValue::Nil),
            }
        }
        // Write drawings (the operations of `paw.canvas.paint`) to a file:
        // `format` "pdf" (one page for each drawing), "svg" or "png" (the first).
        // Each page is `{ ops, width, height }` in pixels. `scale` is the points
        // for one pixel in a PDF (0.75: 96 pixels to the inch).
        fn canvas_export(lua, _sh, (path, format, pages, scale) => (String, String, LuaValue, Option<f32>)) {
            let pages: Vec<Value> = lua.from_value(pages)?;
            let drawn: Vec<(paw_raster::Drawing, f32, f32)> = pages
                .iter()
                .map(|p| {
                    let size = |k: &str| p[k].as_f64().unwrap_or(1.0).max(1.0) as f32;
                    (paw_raster::Drawing::parse(&p["ops"]), size("width"), size("height"))
                })
                .collect();
            let Some((first, width, height)) = drawn.first() else {
                return Err(mlua::Error::runtime("nothing to write"));
            };
            let bytes = match format.as_str() {
                "pdf" => paw_raster::vector::pdf(&drawn, scale.unwrap_or(0.75)),
                "svg" => paw_raster::vector::svg(first, *width, *height).into_bytes(),
                "png" => first
                    .paint_all(*width as u32, *height as u32)
                    .and_then(|p| p.encode_png().ok())
                    .ok_or_else(|| mlua::Error::runtime("could not paint the drawing"))?,
                other => return Err(mlua::Error::runtime(format!("no format `{other}`: pdf, svg or png"))),
            };
            std::fs::write(&path, bytes).map_err(|e| mlua::Error::runtime(format!("{path}: {e}")))
        }
        fn hl_set(_, sh, (name, def, full) => (String, LuaValue, LuaValue)) {
            // `full` is the group in 24-bit colour, given when `def` is a
            // nearer form of it for a terminal that shows fewer colours.
            let parse = |def: &LuaValue| Ok(match def {
                LuaValue::String(link) => Highlight::Link(link.to_str()?.to_string()),
                LuaValue::Table(table) => Highlight::Style(parse_style(table)?),
                _ => return Err(mlua::Error::runtime("a highlight is a table of attributes or the name of another group")),
            });
            let highlight = parse(&def)?;
            let mut highlights = sh.highlights.borrow_mut();
            highlights.set(&name, highlight);
            if !full.is_nil() {
                highlights.set_full(&name, parse(&full)?);
            }
            sh.dirty.set(true);
            sh.redraws.set(sh.redraws.get() + 1);
            Ok(())
        }
        // @return integer
        fn str_width(_, _sh, text => LuaString) { Ok(text.to_str()?.width()) }
        fn ui_snapshot(lua, sh, (width, height) => (u16, u16)) {
            // Draw the UI off screen at the given size and return it as lines
            // of text, for tests and for looking at the UI over the socket.
            let screen = sh.grid.replace(Grid::new(width, height));
            let cursor = sh.cursor.get();
            let drawn = render(lua, &sh);
            let grid = sh.grid.replace(screen);
            sh.cursor.set(cursor);
            // The runtime's list of live parts is of this drawing now: the
            // screen is drawn whole next.
            sh.dirty.set(true);
            drawn?;
            let lines: Vec<String> = grid
                .cells
                .chunks(width.max(1) as usize)
                .map(|row| row.iter().filter(|c| c.ch != '\0').map(|c| c.ch).collect::<String>())
                .map(|line| line.trim_end().to_string())
                .collect();
            Ok(lines)
        }
        // A frame drawn off screen as a terminal is drawn, for tests: whole,
        // or with `live` only its live parts again on the frame this drew
        // last (nil when the runtime says it must be drawn whole). Each
        // row as its text and as its cells with their styles.
        fn ui_frame_snapshot(lua, sh, (width, height, live) => (u16, u16, Option<bool>)) {
            let mut frame = sh.snapshot.take().filter(|g| (g.width, g.height) == (width, height));
            let live = live.unwrap_or(false);
            if live && frame.is_none() {
                return Ok(LuaValue::Nil);
            }
            let screen = sh.grid.replace(frame.take().unwrap_or_else(|| Grid::new(width, height)));
            let (cursor, dirty) = (sh.cursor.get(), sh.dirty.get());
            let drawn = if live {
                render_live(lua, &sh)
            } else {
                sh.grid.borrow_mut().clear();
                render(lua, &sh).map(|()| true)
            };
            let grid = sh.grid.replace(screen);
            sh.cursor.set(cursor);
            // The runtime's list of live parts is of this drawing now: the
            // screen is drawn whole next.
            sh.dirty.set(dirty || !live);
            let drawn = drawn?;
            if !drawn {
                return Ok(LuaValue::Nil);
            }
            let rows = grid.cells.chunks(width.max(1) as usize);
            let text: Vec<String> = rows.clone().map(|row| row.iter().filter(|c| c.ch != '\0').map(|c| c.ch).collect()).collect();
            let cells: Vec<String> = rows.map(|row| row.iter().map(|c| format!("{:?}", c)).collect()).collect();
            let out = lua.create_table()?;
            out.set("text", text)?;
            out.set("cells", cells)?;
            out.set("live", grid.live.len())?;
            sh.snapshot.replace(Some(grid));
            Ok(LuaValue::Table(out))
        }
        fn ui_view_snapshot(lua, sh, (name, width, height) => (String, u16, u16)) {
            // One view drawn by itself at the given size, as rows of runs of
            // one style: what a window shows of a view that draws cells.
            let snapshot = view_snapshot(lua, &sh, &name, width.max(1), height.max(1))?;
            to_lua(lua, &snapshot)
        }
        // Draw text at `(x, y)`, clipped to the rectangle `(cx, cy, cw, ch)`.
        // Returns the number of columns the text takes.
        fn grid_text(_, sh, (x, y, text, style, cx, cy, cw, ch) => (f64, f64, LuaString, LuaValue, f64, f64, f64, f64)) {
            let style = style_of(&sh, &style)?;
            let clip = Rect { x: cell(cx), y: cell(cy), w: cell(cw), h: cell(ch) };
            let text = text.to_str()?;
            // Kept as a node too while a view is drawn for a scene.
            sh.scenes.borrow_mut().text(clip, cell(x), cell(y), &text, style);
            Ok(sh.grid.borrow_mut().text(clip, cell(x), cell(y), &text, style))
        }
        // Restyle the area `(x, y, w, h)`, clipped to `(cx, cy, cw, ch)`, and
        // overwrite its characters when `fill` is given.
        // @return nil
        fn grid_fill(_, sh, (x, y, w, h, fill, style, cx, cy, cw, ch) => (f64, f64, f64, f64, Option<LuaString>, LuaValue, f64, f64, f64, f64)) {
            let style = style_of(&sh, &style)?;
            let fill = match fill {
                Some(s) => s.to_str()?.chars().next(),
                None => None,
            };
            let clip = Rect { x: cell(cx), y: cell(cy), w: cell(cw), h: cell(ch) };
            let area = Rect { x: cell(x), y: cell(y), w: cell(w), h: cell(h) };
            sh.scenes.borrow_mut().fill(clip, area, fill, style);
            sh.grid.borrow_mut().fill(clip, area, fill, style);
            Ok(())
        }

        // --- timers ---
        // @return integer
        fn timer_start(lua, sh, (ms, repeat, func) => (f64, bool, Function)) {
            let func = Rc::new(lua.create_registry_value(func)?);
            let id = sh.next_timer.get() + 1;
            sh.next_timer.set(id);
            let period = Duration::from_secs_f64(ms.max(0.0) / 1000.0);
            // A repeating timer with no period would starve everything else.
            let repeat = repeat.then(|| period.max(Duration::from_millis(1)));
            sh.timers.borrow_mut().push(Timer { id, due: Instant::now() + period, repeat, func });
            Ok(id)
        }
        // @return nil
        fn timer_stop(_, sh, id => u64) {
            sh.timers.borrow_mut().retain(|t| t.id != id);
            Ok(())
        }
        // @return number
        fn now(_, sh, () => ()) { Ok(sh.started.elapsed().as_secs_f64() * 1000.0) }
        // The time limit on Lua (`paw.limit`). The arguments are the function to
        // call when a callback runs too long, and the time when the current
        // callback must return (on the clock of `now`, nil when it returned).
        // `limit_async` tells if paw finds an overrun inside compiled code too.
        fn limit_hook(lua, _sh, func => Function) { Watchdog::set_hook(lua, func) }
        // @return nil
        fn limit_watch(_, sh, deadline => Option<f64>) {
            sh.watchdog.watch(deadline);
            Ok(())
        }
        // @return nil
        fn sleep(_, _sh, ms => f64) {
            std::thread::sleep(Duration::from_secs_f64(ms.max(0.0) / 1000.0));
            Ok(())
        }
        // Let `ms` milliseconds pass. Timers fire and events come, as between the
        // key presses of a person. `sleep` stops all of that. A script that waits
        // for the result of a timer uses `wait`.
        fn wait(lua, sh, ms => f64) {
            let deadline = Instant::now() + Duration::from_secs_f64(ms.max(0.0) / 1000.0);
            let kernel: Table = lua.globals().get::<Table>("paw")?.get("_kernel")?;
            let (timer, settle): (Function, Function) = (kernel.get("timer")?, kernel.get("settle")?);
            let mut idled = Instant::now() - Duration::from_secs(1);
            loop {
                for func in due_timers(&sh) {
                    timer.call::<()>(lua.registry_value::<Function>(&func)?)?;
                }
                // Plugins are looked after as they are while the program runs.
                if idled.elapsed() >= Duration::from_millis(15) {
                    sh.session.borrow_mut().idle();
                    idled = Instant::now();
                }
                // What was played into a port, or written by a helper,
                // meanwhile is heard of.
                sh.hear_midi();
                sh.hear_output();
                settle.call::<()>(())?;
                sh.session.borrow_mut().checkpoint();
                if Instant::now() >= deadline {
                    return Ok(());
                }
                std::thread::sleep(Duration::from_millis(1));
            }
        }

        // --- kernel ---
        // @return nil
        fn quit(_, sh, code => Option<i32>) {
            sh.quit.set(Some(code.unwrap_or(0)));
            Ok(())
        }
        // @return nil
        fn reload(_, sh, () => ()) {
            sh.reload.set(true);
            Ok(())
        }
        // @return nil
        fn log(_, sh, line => String) {
            sh.log(line);
            Ok(())
        }
        // --- helper processes and sockets ---
        fn proc_spawn(lua, sh, (argv, opts) => (Vec<String>, LuaValue)) {
            sh.io.borrow_mut().spawn(&argv, options(lua, opts)?).lua()
        }
        fn proc_status(lua, sh, id => u64) { to_lua(lua, &sh.io.borrow_mut().status(id).lua()?) }
        // Ask it to finish and let it: `proc_status` says when it has.
        // @return nil
        fn proc_stop(_, sh, id => u64) { sh.io.borrow_mut().stop(id).lua() }
        // @return nil
        fn proc_kill(_, sh, id => u64) {
            sh.io.borrow_mut().kill(id);
            Ok(())
        }
        // A process started with `pipe = true`: what it wrote ("" when
        // nothing, nil once it closed its output). `proc_write` writes to it.
        // A `proc.output` event says when there is something to read.
        fn proc_read(lua, sh, (id, max) => (u64, Option<usize>)) {
            match sh.io.borrow_mut().read_output(id, max.unwrap_or(1 << 20)).lua()? {
                Some(bytes) => Ok(LuaValue::String(lua.create_string(bytes)?)),
                None => Ok(LuaValue::Nil),
            }
        }
        // @return nil
        fn proc_write(_, sh, (id, data) => (u64, LuaString)) { sh.io.borrow_mut().write_input(id, &data.as_bytes()).lua() }
        // @return nil
        fn proc_close_input(_, sh, id => u64) { sh.io.borrow_mut().close_input(id).lua() }
        // @return integer
        fn sock_listen(_, sh, path => String) { sh.io.borrow_mut().listen(path.into()).lua() }
        // @return integer
        fn sock_connect(_, sh, path => String) { sh.io.borrow_mut().connect(path.into()).lua() }
        fn sock_accept(_, sh, id => u64) { sh.io.borrow_mut().accept(id).lua() }
        // The bytes that came, "" when none came, nil after the peer closed.
        fn sock_read(lua, sh, (id, max) => (u64, Option<usize>)) {
            match sh.io.borrow_mut().read(id, max.unwrap_or(1 << 20)).lua()? {
                Some(bytes) => Ok(LuaValue::String(lua.create_string(bytes)?)),
                None => Ok(LuaValue::Nil),
            }
        }
        fn sock_write(_, sh, (id, data) => (u64, LuaString)) { sh.io.borrow_mut().write(id, &data.as_bytes()).lua() }
        // @return nil
        fn sock_close(_, sh, id => u64) {
            sh.io.borrow_mut().close(id);
            Ok(())
        }

        // Connections on the control socket (crates/paw-core/src/rpc.rs). Push an
        // event to one (false when it closed), list them, and tell the terminal
        // of the input that paw handles now (0 for the terminal of paw). Also
        // release the terminal of a connection.
        fn rpc_push(lua, sh, (client, event, payload) => (u64, String, LuaValue)) {
            let payload: Value = from_lua(lua, payload)?;
            Ok(sh.clients.push(client, &event, &payload))
        }
        fn rpc_clients(_, sh, () => ()) { Ok(sh.clients.ids()) }
        // @return integer
        fn rpc_version(_, _sh, () => ()) { Ok(crate::rpc::VERSION) }
        fn ui_client(_, sh, () => ()) { Ok(sh.input_from.get()) }
        // @return nil
        fn ui_seat(_, sh, seat => u64) {
            // The screen is the size of the terminal of the seat entered;
            // a seat without one (a window's) has the size there was at first.
            let (width, height) = sh.sizes.borrow().get(&seat).copied().unwrap_or((80, 24));
            let mut grid = sh.grid.borrow_mut();
            if (grid.width, grid.height) != (width, height) {
                grid.resize(width, height);
            }
            Ok(())
        }
        // @return nil
        fn ui_detach(_, sh, client => u64) {
            sh.detach.borrow_mut().push(client);
            Ok(())
        }

        fn log_get(_, sh, () => ()) { Ok(sh.log.borrow().iter().cloned().collect::<Vec<_>>()) }
        fn events_take(lua, sh, () => ()) {
            // Push pending edits to the engine and hand back the change events.
            let events = {
                let mut session = sh.session.borrow_mut();
                session.write_automation();
                session.flush();
                session.read_ahead();
                std::mem::take(&mut session.events)
            };
            let list = lua.create_table()?;
            for (name, payload) in events {
                let event = lua.create_table()?;
                event.set("name", name)?;
                event.set("payload", to_lua(lua, &payload)?)?;
                list.push(event)?;
            }
            Ok(list)
        }
        // --- JSON, for what extensions keep in files ---

        // JSON text of a value; `pretty` lays it out on lines, indented.
        fn json_encode(lua, _sh, (value, pretty) => (LuaValue, Option<bool>)) {
            let value: Value = from_lua(lua, value)?;
            let text = if pretty.unwrap_or(false) {
                serde_json::to_string_pretty(&value)
            } else {
                serde_json::to_string(&value)
            };
            text.map_err(|err| mlua::Error::runtime(format!("{err}")))
        }
        // Nil and the reason, when the text is not JSON.
        fn json_decode(lua, _sh, text => LuaString) {
            match serde_json::from_slice::<Value>(&text.as_bytes()) {
                Ok(value) => Ok((to_lua(lua, &value)?, LuaValue::Nil)),
                Err(err) => Ok((LuaValue::Nil, LuaValue::String(lua.create_string(format!("{err}"))?))),
            }
        }
        // --- XML and TOML, for the files of other programs ---

        // The root element of an XML text, or nil and what is wrong (with the
        // byte). An element is `{ name, attr, order, children, text }`:
        // `attr` maps each attribute to its text, `order` lists them as
        // written, `children` holds the child elements, `text` the text and
        // CDATA directly in it (nil when there is none). References are
        // read; an entity a DTD defines is kept as it is written. UTF-16
        // with a byte order mark is read too. `opts.spans` gives each element
        // `span = { from, open, close, to, lead, tail }`, the bytes it takes
        // in the text, so that `xml_encode` can write what is not changed
        // byte for byte. `opts.meta` is set as the metatable of each element.
        fn xml_decode(lua, _sh, (text, opts) => (LuaString, Option<Table>)) {
            let spans = opts.as_ref().and_then(|o| o.get::<Option<bool>>("spans").ok().flatten()).unwrap_or(false);
            let meta = opts.as_ref().and_then(|o| o.get::<Option<Table>>("meta").ok().flatten());
            Ok(match crate::xml::decode(lua, &text.as_bytes(), spans, meta)? {
                Ok(root) => (LuaValue::Table(root), LuaValue::Nil),
                Err(why) => (LuaValue::Nil, LuaValue::String(lua.create_string(why)?)),
            })
        }
        // The XML text of an element (as `xml_decode` gives them, or made
        // with the same fields). Attributes are written in `order`, then the
        // others by name; numbers as the shortest text that reads back the
        // same, or with at most `opts.digits` digits after the point.
        // `opts.indent` puts each element on a line, indented by it.
        // `opts.declaration` is written first (true: the usual one).
        // `opts.source` is the text the tree was read from with `spans`:
        // what did not change is written as it was, byte for byte, and the
        // text around the root element too.
        fn xml_encode(_, _sh, (root, opts) => (Table, Option<Table>)) {
            let get = |k: &str| opts.as_ref().map_or(Ok(LuaValue::Nil), |o| o.get::<LuaValue>(k));
            let source = match get("source")? { LuaValue::String(s) => Some(s.as_bytes().to_vec()), _ => None };
            let enc = crate::xml::EncodeOpts {
                indent: match get("indent")? { LuaValue::String(s) => Some(s.to_string_lossy()), _ => None },
                digits: match get("digits")? { LuaValue::Integer(n) => Some(n as usize), LuaValue::Number(n) => Some(n as usize), _ => None },
                source,
            };
            let body = crate::xml::encode(&root, &enc)?;
            let mut out = String::new();
            match get("declaration")? {
                LuaValue::Boolean(true) => out.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"),
                LuaValue::String(s) => out.push_str(&s.to_string_lossy()),
                _ => {}
            }
            let span: Option<Table> = root.get("span")?;
            match (&enc.source, span) {
                (Some(src), Some(span)) if out.is_empty() => {
                    let (from, to): (usize, usize) = (span.get("from")?, span.get("to")?);
                    if from >= 1 && to <= src.len() {
                        out.push_str(&String::from_utf8_lossy(&src[..from - 1]));
                        out.push_str(&body);
                        out.push_str(&String::from_utf8_lossy(&src[to..]));
                        return Ok(out);
                    }
                    out.push_str(&body);
                }
                _ => {
                    out.push_str(&body);
                    if enc.indent.is_some() {
                        out.push('\n');
                    }
                }
            }
            Ok(out)
        }
        // The table of a TOML text, or nil and what is wrong (`line 4: ...`).
        // Each table keeps the order of its keys in its metatable,
        // `getmetatable(t).__keys`. A date or a time is its text.
        fn toml_decode(lua, _sh, text => String) {
            Ok(match crate::toml_api::decode(lua, &text)? {
                Ok(v) => (v, LuaValue::Nil),
                Err(why) => (LuaValue::Nil, LuaValue::String(lua.create_string(why)?)),
            })
        }
        // The TOML text of a table; with `inline`, of any value on one line
        // (`{ a = 1, b = "x" }`). The keys of a table come in the order of
        // its metatable's `__keys`, then the others by name. A list of
        // tables is an array of tables.
        fn toml_encode(_, _sh, (value, inline) => (LuaValue, Option<bool>)) {
            crate::toml_api::encode(&value, inline.unwrap_or(false))
        }
        // Mark a table (a new one without `t`) as a JSON array, so that
        // `json_encode` writes it as `[]` when it is empty. Returns it.
        fn json_array(lua, _sh, t => Option<Table>) {
            let t = match t { Some(t) => t, None => lua.create_table()? };
            t.set_metatable(Some(lua.array_metatable()))?;
            Ok(t)
        }
        // --- bytes, for the file formats extensions read and write ---

        // Base64 of bytes. `opts.url` uses the URL alphabet (`-_`), and
        // `opts.pad = false` leaves out the `=` at the end.
        // @param opts? types.Base64Options
        // @return string
        fn base64_encode(_, _sh, (data, opts) => (LuaString, Option<Table>)) {
            let url = opts.as_ref().and_then(|o| o.get::<Option<bool>>("url").ok().flatten()).unwrap_or(false);
            let pad = opts.as_ref().and_then(|o| o.get::<Option<bool>>("pad").ok().flatten()).unwrap_or(true);
            Ok(crate::codec::base64_encode(&data.as_bytes(), url, pad))
        }
        // The bytes of base64 text, either alphabet, with or without its
        // padding; spaces and line ends are left out. Nil and the reason
        // when it is not base64.
        // @return string, string
        fn base64_decode(lua, _sh, text => LuaString) {
            bytes_or_why(lua, crate::codec::base64_decode(&text.as_bytes()))
        }
        // Compress `data` with deflate, as `format` says: "raw", "zlib" or "gzip".
        fn deflate(lua, _sh, (data, format) => (LuaString, String)) {
            bytes_or_why(lua, crate::codec::deflate(&data.as_bytes(), &format))
        }
        // The bytes `data` holds compressed as `format` says ("raw", "zlib"
        // or "gzip"), and the number of bytes of `data` the compressed
        // stream took (what follows is not part of it). Nil and the reason
        // when they are not compressed so.
        fn inflate(lua, _sh, (data, format) => (LuaString, String)) {
            Ok(match crate::codec::inflate(&data.as_bytes(), &format) {
                Ok((bytes, used)) => (LuaValue::String(lua.create_string(&bytes)?), LuaValue::Integer(used as i64)),
                Err(err) => (LuaValue::Nil, LuaValue::String(lua.create_string(format!("{err:#}"))?)),
            })
        }
        // The CRC-32 of bytes, as zip and gzip use it.
        // @return integer
        fn crc32(_, _sh, data => LuaString) {
            Ok(crate::codec::crc32(&data.as_bytes()))
        }
        // --- tempo maps of other programs ---

        // A tempo map from points placed in seconds, as other programs keep
        // them: `tempos` is `{ { seconds, bpm, ramp } }`, `signatures` is
        // `{ { seconds, num, den } }`. Each point's beat follows from the
        // stretch before it, held, or ramped linearly in time. Returns
        // `{ tempos, signatures, beat, seconds }`: the points in beats, as
        // `tempo_set_points` takes them, and two functions that convert
        // with this map, `beat(seconds)` and `seconds(beat)`.
        fn tempo_from_seconds(lua, _sh, (tempos, signatures) => (Table, Option<Table>)) {
            crate::tempo_api::from_seconds(lua, &tempos, signatures.as_ref())
        }
        // --- sound files, programs ---

        // The levels of a sound file, any format the engine plays: `{ rate,
        // channels, frames, seconds, peaks, peak, onset, blocks }`, levels
        // as linear gain. `peaks` holds the loudest sample of each channel,
        // `peak` the loudest of all. `onset(level, from)` gives the time in
        // seconds of the first frame, at `from` seconds or later, where a
        // channel is louder than `level` (nil when none is). `blocks(from,
        // to, ms)` gives the loudest sample of each block of `ms`
        // milliseconds (default 1) between two times in seconds.
        fn sound_envelope(lua, _sh, path => String) { crate::ext_api::sound_envelope(lua, &path) }
        // Write a WAV file: `opts` is `{ rate, channels (2), bits (16, 24,
        // or 32 for float) }`. `samples` is the interleaved samples as bytes
        // of 32-bit floats in the order of the machine (`ffi.string` of a
        // `float[?]`), or a function `(frame, count)` that gives them one
        // piece at a time and nil at the end. Returns the number of frames.
        fn sound_write(_, _sh, (path, opts, samples) => (String, Table, LuaValue)) {
            crate::ext_api::sound_write(&path, &opts, samples)
        }
        // Where a program is on `PATH`, as `command -v` says; nil when it
        // is not there. A name with a `/` is checked as it is.
        fn which(_, _sh, program => String) { Ok(crate::ext_api::which(&program)) }
        // Remove a file, or a directory with all it holds: only for what paw
        // or an extension made for itself, a cache or a temporary folder.
        // The files of the user go to the trash (`fs_trash`) instead.
        // Nothing there is no error.
        fn fs_remove(_, _sh, path => String) {
            let p = Path::new(&path);
            let Ok(meta) = p.symlink_metadata() else { return Ok(()) };
            let done = if meta.is_dir() { std::fs::remove_dir_all(p) } else { std::fs::remove_file(p) };
            done.map_err(|e| mlua::Error::runtime(format!("{path}: {e}")))
        }
        // The space of the disk that holds a path: `{ free, total }` in
        // bytes (free: what a program that is not root can use).
        fn fs_space(lua, _sh, path => String) {
            let c = std::ffi::CString::new(path.clone()).map_err(|e| mlua::Error::runtime(format!("{e}")))?;
            let mut st: libc::statvfs = unsafe { std::mem::zeroed() };
            if unsafe { libc::statvfs(c.as_ptr(), &mut st) } != 0 {
                return Err(mlua::Error::runtime(format!("{path}: {}", std::io::Error::last_os_error())));
            }
            let t = lua.create_table()?;
            t.set("free", st.f_bavail as f64 * st.f_frsize as f64)?;
            t.set("total", st.f_blocks as f64 * st.f_frsize as f64)?;
            Ok(t)
        }
        // True when a file or directory is there (a link that leads nowhere is not).
        // @return boolean
        fn fs_exists(_, _sh, path => String) { Ok(Path::new(&path).exists()) }
        fn warnings(_, sh, () => ()) { Ok(std::mem::take(&mut sh.session.borrow_mut().warnings)) }
        fn env(lua, sh, () => ()) {
            let env = lua.create_table()?;
            env.set("config_dir", sh.env.config_dir.to_string_lossy().into_owned())?;
            env.set("runtime_dir", sh.env.runtime_dir.as_ref().map(|p| p.to_string_lossy().into_owned()))?;
            env.set("clean", sh.env.clean)?;
            env.set("scripted", sh.env.scripted)?;
            // Where the program keeps what is the user's but not configuration:
            // recordings and the like, and what it needs between runs.
            env.set("data_dir", xdg_dir("XDG_DATA_HOME", ".local/share"))?;
            env.set("state_dir", xdg_dir("XDG_STATE_HOME", ".local/state"))?;
            env.set("pid", std::process::id())?;
            env.set("argv", sh.env.argv.clone())?;
            Ok(env)
        }
        fn state_get(lua, sh, key => String) {
            match sh.state.borrow().get(&key) {
                Some(value) => to_lua(lua, value),
                None => Ok(LuaValue::Nil),
            }
        }
        // @return nil
        fn state_set(lua, sh, (key, value) => (String, LuaValue)) {
            if value.is_nil() {
                sh.state.borrow_mut().remove(&key);
            } else {
                let value: Value = from_lua(lua, value)?;
                sh.state.borrow_mut().insert(key, value);
            }
            Ok(())
        }
        fn read_dir(lua, _sh, path => String) {
            let list = lua.create_table()?;
            let Ok(entries) = std::fs::read_dir(&path) else { return Ok(list) };
            let mut names: Vec<(String, bool, Option<f64>)> = entries
                .flatten()
                .map(|e| {
                    // When it was last written, in seconds since 1970.
                    let mtime = e.metadata().ok().and_then(|m| m.modified().ok())
                        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                        .map(|d| d.as_secs_f64());
                    (e.file_name().to_string_lossy().into_owned(), e.path().is_dir(), mtime)
                })
                .collect();
            names.sort_by(|a, b| a.0.cmp(&b.0));
            for (name, is_dir, mtime) in names {
                let entry = lua.create_table()?;
                entry.set("name", name)?;
                entry.set("is_dir", is_dir)?;
                entry.set("mtime", mtime)?;
                list.push(entry)?;
            }
            Ok(list)
        }
    }

    crate::measure::install(lua, &api, shared)?;
    crate::tempo_api::install(lua, &api, shared)?;
    crate::luadev_api::install(lua, &api, shared)?;
    crate::fs_api::install(lua, &api)?;
    crate::scene::install(lua, &api, shared)?;

    let loaded: Table = lua.globals().get::<Table>("package")?.get("loaded")?;
    loaded.set("paw.api", api)
}
