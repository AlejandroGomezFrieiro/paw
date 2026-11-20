//! One device written in Lua: its script in a LuaJIT state of its own, run
//! over buffers this side owns and the script sees as `ffi` arrays.
//!
//! LuaJIT allocates as it runs, so this device must never be on the
//! engine's audio thread: it runs in a helper process (see the crate's
//! documentation), where an allocation, a slow block or a crash costs only
//! that device.

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Result, anyhow};
use paw_engine::device::{Category, Controller, Device, Instance, Io, ParamInfo, Ports};
use paw_engine::{Attr, Ctl, Event, EventKind, ProcessCtx};
use mlua::{Function, HookTriggers, LightUserData, Lua, Table, VmState};
use serde::{Deserialize, Serialize};

/// Events a block may carry each way.
pub const MAX_EVENTS: usize = 1024;

/// How long a script may take to load and get ready. A loop that never
/// ends there is reported instead of holding everything up.
const LOAD_LIMIT: Duration = Duration::from_secs(5);

/// The library scripts are written with (`require("paw.dsp")`).
const DSP: &str = include_str!("../../../runtime/lua/paw/dsp.lua");
/// What loads a script and runs its blocks, in its own state.
const HOST: &str = include_str!("host.lua");

// Event types as `paw.dsp` names them.
const NOTE_ON: i32 = 1;
const NOTE_OFF: i32 = 2;
const CC: i32 = 3;
const BEND: i32 = 4;
const PRESSURE: i32 = 5;
const PROGRAM: i32 = 6;
const ALL_NOTES_OFF: i32 = 7;
const OTHER: i32 = 8;

/// An event as a script sees it (`paw_event` in `paw.dsp`).
#[repr(C)]
#[derive(Clone, Copy, Default)]
struct LuaEvent {
    frame: i32,
    kind: i32,
    /// From 1, as everywhere in Lua.
    channel: i32,
    key: i32,
    value: f64,
    /// The incoming event this one is, counting from 1, or 0.
    from: i32,
    /// A note-on's MIDI 2.0 attribute as one number, its type above its
    /// sixteen bits of data; 0 for none.
    attr: i32,
}

/// The transport for one block (`paw_transport` in `paw.dsp`).
#[repr(C)]
#[derive(Default)]
struct Transport {
    sample_rate: f64,
    tempo: f64,
    beat: f64,
    seconds: f64,
    bar_start: f64,
    bar: f64,
    sig_num: f64,
    sig_den: f64,
    playing: f64,
}

/// One parameter as a script declares it.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Param {
    pub key: String,
    pub name: String,
    pub min: f32,
    pub max: f32,
    pub default: f32,
    pub unit: String,
    pub choices: Vec<String>,
}

impl Param {
    pub fn info(&self) -> ParamInfo {
        ParamInfo {
            key: self.key.clone(),
            name: self.name.clone(),
            min: self.min,
            max: self.max,
            default: self.default,
            unit: self.unit.clone(),
            steps: self.choices.len().saturating_sub(1) as u32,
            choices: self.choices.clone(),
            automatable: true,
            ..ParamInfo::default()
        }
    }
}

/// What a script says it is.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Descriptor {
    pub name: Option<String>,
    pub category: Category,
    pub vendor: Option<String>,
    /// Its events replace those that came in, instead of being added.
    pub midi_effect: bool,
    pub sidechain: bool,
    pub params: Vec<Param>,
}

/// What a script error says, without Lua's traceback and mlua's prefix.
pub fn message(err: &mlua::Error) -> String {
    let text = match err {
        mlua::Error::RuntimeError(text) => text.clone(),
        mlua::Error::SyntaxError { message, .. } => message.clone(),
        mlua::Error::CallbackError { cause, .. } => return message(cause),
        mlua::Error::MemoryError(text) => format!("out of memory: {text}"),
        other => other.to_string(),
    };
    let text = text.split("\nstack traceback").next().unwrap_or_default();
    text.trim().to_string()
}

/// A script error as an error of this crate's.
fn lua_error(err: mlua::Error) -> anyhow::Error {
    anyhow!("{}", message(&err))
}

/// A script loaded in a state of its own: the state and the host's table.
fn load(path: &Path) -> mlua::Result<(Lua, Table)> {
    // All libraries, `ffi` and `jit` among them: the script is trusted with
    // its own process.
    let lua = unsafe { Lua::unsafe_new() };
    let started = Instant::now();
    lua.set_hook(
        HookTriggers::new().every_nth_instruction(100_000),
        move |_, _| {
            if started.elapsed() > LOAD_LIMIT {
                return Err(mlua::Error::runtime(format!(
                    "it did not get ready within {} seconds (a loop that never ends?)",
                    LOAD_LIMIT.as_secs()
                )));
            }
            Ok(VmState::Continue)
        },
    )?;
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let host: Table = lua
        .load(HOST)
        .set_name("@paw/luadev-host.lua")
        .call((path.to_string_lossy().into_owned(), name, DSP))?;
    Ok((lua, host))
}

fn descriptor(host: &Table) -> mlua::Result<Descriptor> {
    let describe: Function = host.get("describe")?;
    let t: Table = describe.call(())?;
    let mut params = Vec::new();
    for p in t.get::<Table>("params")?.sequence_values::<Table>() {
        let p = p?;
        let number =
            |key: &str| -> mlua::Result<f32> { Ok(p.get::<Option<f64>>(key)?.unwrap_or(0.0) as f32) };
        params.push(Param {
            key: p.get("key")?,
            name: p.get("name")?,
            min: number("min")?,
            max: number("max")?,
            default: number("default")?,
            unit: p.get::<Option<String>>("unit")?.unwrap_or_default(),
            choices: p
                .get::<Table>("choices")?
                .sequence_values::<String>()
                .collect::<mlua::Result<_>>()?,
        });
    }
    Ok(Descriptor {
        name: t.get("name")?,
        category: t
            .get::<String>("category")?
            .parse()
            .map_err(mlua::Error::external)?,
        vendor: t.get("vendor")?,
        midi_effect: t.get("midi_effect")?,
        sidechain: t.get("sidechain")?,
        params,
    })
}

/// Load a script to learn what it is, then let it go.
pub fn describe(path: &Path) -> Result<Descriptor> {
    let (_lua, host) = load(path).map_err(lua_error)?;
    descriptor(&host).map_err(lua_error)
}

/// The buffers the script works in, at addresses that do not move.
struct Buffers {
    left: Vec<f32>,
    right: Vec<f32>,
    key_left: Vec<f32>,
    key_right: Vec<f32>,
    events_in: Vec<LuaEvent>,
    events_out: Vec<LuaEvent>,
    /// The events that came in, as they were, to pass on.
    originals: Vec<Event>,
    params: Vec<f64>,
    transport: Transport,
}

/// The state, the function that runs a block and the one that answers calls.
struct Running {
    run: Function,
    call: Function,
    lua: Lua,
}

// A Lua state may move between threads as long as one thread at a time uses
// it: blocks run on the audio thread and calls on the main thread, each
// holding the lock, and nothing else holds any of its values.
unsafe impl Send for Running {}

/// The state, shared by the device and its controller. A call takes it
/// between two blocks; a block that comes meanwhile waits for the call.
type Shared = Arc<Mutex<Running>>;

/// Why the script stopped, shared by the device and its controller.
type Failure = Arc<Mutex<Option<String>>>;

pub struct LuaDevice {
    running: Shared,
    bufs: Box<Buffers>,
    max_block: usize,
    instrument: bool,
    midi_effect: bool,
    failed: Failure,
    stopped: bool,
}

/// Make the device a script describes, ready for blocks of up to
/// `max_block` frames.
pub fn make(path: &Path, sample_rate: f32, max_block: usize) -> Result<Instance> {
    let (lua, host) = load(path).map_err(lua_error)?;
    let desc = descriptor(&host).map_err(lua_error)?;
    let mut bufs = Box::new(Buffers {
        left: vec![0.0; max_block],
        right: vec![0.0; max_block],
        key_left: vec![0.0; max_block],
        key_right: vec![0.0; max_block],
        events_in: vec![LuaEvent::default(); MAX_EVENTS],
        events_out: vec![LuaEvent::default(); MAX_EVENTS],
        originals: vec![
            Event {
                frame: 0,
                kind: EventKind::AllNotesOff
            };
            MAX_EVENTS
        ],
        params: desc.params.iter().map(|p| p.default as f64).collect(),
        transport: Transport {
            sample_rate: sample_rate as f64,
            ..Transport::default()
        },
    });
    let bind = |bufs: &mut Buffers| -> mlua::Result<Function> {
        let ptr = lua.create_table()?;
        let put = |name: &str, at: *mut std::ffi::c_void| ptr.set(name, LightUserData(at));
        put("left", bufs.left.as_mut_ptr().cast())?;
        put("right", bufs.right.as_mut_ptr().cast())?;
        put("key_left", bufs.key_left.as_mut_ptr().cast())?;
        put("key_right", bufs.key_right.as_mut_ptr().cast())?;
        put("events_in", bufs.events_in.as_mut_ptr().cast())?;
        put("events_out", bufs.events_out.as_mut_ptr().cast())?;
        // A device without parameters still gets an address to read none from.
        put("params", bufs.params.as_mut_ptr().cast())?;
        put("transport", (&mut bufs.transport as *mut Transport).cast())?;
        host.get::<Function>("bind")?
            .call::<()>((ptr, max_block, MAX_EVENTS, sample_rate))?;
        host.get("run")
    };
    let run = bind(&mut bufs).map_err(lua_error)?;
    let call = host.get("call").map_err(lua_error)?;
    // Ready: from here on a block is timed by whoever waits for it.
    lua.remove_hook();
    let running = Arc::new(Mutex::new(Running { run, call, lua }));
    let failed: Failure = Arc::new(Mutex::new(None));
    let params: Vec<ParamInfo> = desc.params.iter().map(Param::info).collect();
    let values = desc.params.iter().map(|p| p.default as f64).collect();
    Ok(Instance {
        device: Box::new(LuaDevice {
            running: running.clone(),
            bufs,
            max_block,
            instrument: desc.category == Category::Instrument,
            midi_effect: desc.midi_effect,
            failed: failed.clone(),
            stopped: false,
        }),
        controller: Some(Box::new(LuaController {
            running,
            path: path.to_path_buf(),
            params,
            values,
            failed,
            sidechain: desc.sidechain,
        })),
    })
}

impl LuaDevice {
    /// What is heard from a device that has stopped: nothing from an
    /// instrument, the input untouched from an effect.
    fn without(&self, io: &mut Io) {
        if self.instrument {
            io.left.fill(0.0);
            io.right.fill(0.0);
        }
    }
}

fn to_lua(event: &Event, index: usize) -> LuaEvent {
    let channel = event.kind.channel().map_or(0, |c| c as i32 + 1);
    let (kind, key, value) = match event.kind {
        EventKind::NoteOn { key, vel, .. } => (NOTE_ON, key as i32, vel as f64),
        EventKind::NoteOff { key, .. } => (NOTE_OFF, key as i32, 0.0),
        EventKind::Control { ctl, value, .. } => match ctl {
            Ctl::Cc(number) => (CC, number as i32, value),
            Ctl::Bend => (BEND, 0, value),
            Ctl::Pressure => (PRESSURE, 0, value),
            _ => (OTHER, 0, value),
        },
        EventKind::NoteControl { key, value, .. } => (OTHER, key as i32, value),
        EventKind::Program { program, bank, .. } => {
            (PROGRAM, program as i32, bank.map_or(-1.0, f64::from))
        }
        EventKind::AllNotesOff => (ALL_NOTES_OFF, 0, 0.0),
    };
    LuaEvent {
        frame: event.frame as i32,
        kind,
        channel,
        key,
        value,
        from: index as i32 + 1,
        attr: match event.kind {
            EventKind::NoteOn { attr, .. } => attr.packed() as i32,
            _ => 0,
        },
    }
}

fn from_lua(event: &LuaEvent, originals: &[Event]) -> Option<EventKind> {
    let ch = (event.channel - 1).clamp(0, 15) as u8;
    let key = event.key.clamp(0, 127) as u8;
    let value = if event.value.is_finite() { event.value } else { 0.0 };
    Some(match event.kind {
        NOTE_ON => EventKind::NoteOn {
            key,
            vel: value.clamp(0.0, 1.0) as f32,
            ch,
            attr: Attr::from_packed(event.attr as u32),
        },
        NOTE_OFF => EventKind::NoteOff { key, ch },
        CC => EventKind::Control {
            ctl: Ctl::Cc(key),
            value: value.clamp(0.0, 1.0),
            ch,
        },
        BEND => EventKind::Control {
            ctl: Ctl::Bend,
            value: value.clamp(-1.0, 1.0),
            ch,
        },
        PRESSURE => EventKind::Control {
            ctl: Ctl::Pressure,
            value: value.clamp(0.0, 1.0),
            ch,
        },
        PROGRAM => EventKind::Program {
            program: key,
            bank: (value >= 0.0).then(|| value.min(16383.0) as u16),
            ch,
        },
        ALL_NOTES_OFF => EventKind::AllNotesOff,
        // Only as it came in: what it was is not in the fields.
        OTHER => {
            originals
                .get(usize::try_from(event.from).ok()?.checked_sub(1)?)?
                .kind
        }
        _ => return None,
    })
}

impl Device for LuaDevice {
    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        if self.stopped {
            return self.without(io);
        }
        let frames = io.left.len().min(self.max_block);
        let b = &mut *self.bufs;
        b.left[..frames].copy_from_slice(&io.left[..frames]);
        b.right[..frames].copy_from_slice(&io.right[..frames]);
        let keyed = match io.sidechain {
            Some([l, r]) => {
                b.key_left[..frames].copy_from_slice(&l[..frames]);
                b.key_right[..frames].copy_from_slice(&r[..frames]);
                true
            }
            None => false,
        };
        let incoming = io.events.as_slice();
        let count = incoming.len().min(MAX_EVENTS);
        for (index, event) in incoming[..count].iter().enumerate() {
            b.originals[index] = *event;
            b.events_in[index] = to_lua(event, index);
        }
        b.transport = Transport {
            sample_rate: ctx.sample_rate as f64,
            tempo: ctx.tempo,
            beat: ctx.position,
            seconds: ctx.seconds,
            bar_start: ctx.bar_start,
            bar: ctx.bar as f64,
            sig_num: ctx.sig_num as f64,
            sig_den: ctx.sig_den as f64,
            playing: ctx.playing as u8 as f64,
        };
        // A lock poisoned by a call that panicked is as good as any: the
        // state is Lua's, which does not stop halfway through a change.
        let running = self.running.lock().unwrap_or_else(|e| e.into_inner());
        let sent = match running.run.call::<i64>((frames as i64, count as i64, keyed)) {
            Ok(sent) => (sent.max(0) as usize).min(MAX_EVENTS),
            Err(err) => {
                // Stopped for good: told through the controller, which the
                // helper asks, and shown in the session as a stopped device.
                self.stopped = true;
                if let Ok(mut failed) = self.failed.lock() {
                    *failed = Some(message(&err));
                }
                return self.without(io);
            }
        };
        drop(running);
        io.left[..frames].copy_from_slice(&b.left[..frames]);
        io.right[..frames].copy_from_slice(&b.right[..frames]);

        // What it sent, in order of frame (as sent, where equal), into the
        // block's time; then merged with what came in unless it replaces that.
        let out = &mut b.events_out[..sent];
        let last = frames.saturating_sub(1) as i32;
        for e in out.iter_mut() {
            e.frame = e.frame.clamp(0, last);
        }
        for i in 1..out.len() {
            let mut j = i;
            while j > 0 && out[j - 1].frame > out[j].frame {
                out.swap(j - 1, j);
                j -= 1;
            }
        }
        let kept = if self.midi_effect { 0 } else { count };
        io.events.clear();
        let (mut i, mut j) = (0, 0);
        while i < kept || j < sent {
            let take_in = j == sent || (i < kept && b.originals[i].frame as i32 <= out[j].frame);
            if take_in {
                io.events.push(b.originals[i]);
                i += 1;
            } else {
                if let Some(kind) = from_lua(&out[j], &b.originals[..count]) {
                    io.events.push(Event {
                        frame: out[j].frame as u32,
                        kind,
                    });
                }
                j += 1;
            }
        }
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if let Some(slot) = self.bufs.params.get_mut(index as usize) {
            *slot = value as f64;
        }
    }
}

/// The main-thread side: the parameters, calls from scripts, and why the
/// script stopped.
pub struct LuaController {
    running: Shared,
    path: PathBuf,
    params: Vec<ParamInfo>,
    values: Vec<f64>,
    failed: Failure,
    sidechain: bool,
}

impl Controller for LuaController {
    fn params(&self) -> Vec<ParamInfo> {
        self.params.clone()
    }

    fn value(&self, index: usize) -> Option<f64> {
        self.values.get(index).copied()
    }

    fn set_value(&mut self, index: usize, value: f64) {
        if let Some(slot) = self.values.get_mut(index) {
            *slot = value;
        }
    }

    // The parameters are the whole state, and the project keeps them.
    fn save_state(&mut self) -> Result<Option<Vec<u8>>> {
        Ok(None)
    }

    fn load_state(&mut self, _state: &[u8]) -> Result<()> {
        Ok(())
    }

    fn health(&mut self) -> Option<String> {
        self.failed.lock().ok().and_then(|failed| failed.clone())
    }

    /// `lua.path` is the script's file; every other method is the script's
    /// own `dev.call(method, data)`, run in its state between two blocks.
    /// What that returns (a string, a number or nothing) is the answer.
    fn call(&mut self, method: &str, data: &[u8]) -> Result<Vec<u8>> {
        if method == "lua.path" {
            return Ok(self.path.to_string_lossy().into_owned().into_bytes());
        }
        if let Some(why) = self.health() {
            anyhow::bail!("the device has stopped: {why}");
        }
        let running = self.running.lock().unwrap_or_else(|e| e.into_inner());
        let data = running.lua.create_string(data).map_err(lua_error)?;
        let answer: Option<mlua::LuaString> = running.call.call((method, data)).map_err(lua_error)?;
        Ok(answer.map(|s| s.as_bytes().to_vec()).unwrap_or_default())
    }

    fn ports(&self) -> Ports {
        Ports {
            sidechain: self.sidechain,
            ..Ports::default()
        }
    }
}
