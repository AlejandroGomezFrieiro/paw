//! One device written in Lua: its script in a LuaJIT state of its own, run
//! over buffers this side owns and the script sees as `ffi` arrays.
//!
//! LuaJIT allocates as it runs, so this device must never be on the
//! engine's audio thread: it runs in a helper process (see the crate's
//! documentation), where an allocation, a slow block or a crash costs only
//! that device.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_possible_wrap, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::float_cmp, reason = "debt: pay down"))]

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock, TryLockError};
use std::time::{Duration, Instant};

use anyhow::{Result, anyhow};
use paw_engine::device::{Category, Controller, Device, Instance, Io, ParamInfo, Ports};
use paw_engine::{Event, ProcessCtx};
use mlua::{Function, HookTriggers, LightUserData, Lua, Table, VmState};
use paw_types::{Attr, Ctl, EventKind};
use serde::{Deserialize, Serialize};

use crate::missed::Missed;

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
    /// The number of whole steps of a parameter of whole numbers; 0 for a
    /// continuous one. A parameter of choices takes one step for each.
    #[serde(default)]
    pub steps: u32,
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
            steps: if self.choices.is_empty() { self.steps } else { self.choices.len().saturating_sub(1) as u32 },
            choices: self.choices.clone(),
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
    // SAFETY: the state is used only through `Running`, one thread at a time.
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
            steps: p.get::<Option<u32>>("steps")?.unwrap_or(0),
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
    /// The events that did not fit in a block, to pass on after the others
    /// have been merged. Filled and emptied in one block.
    spilled: Vec<Event>,
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
// SAFETY: as that comment says: a lock guards every use of `lua`, `run` and `call`.
unsafe impl Send for Running {}

/// The state, shared by the device and its controller. A call takes it
/// between two blocks. A block that comes meanwhile does not wait: it is
/// the stand-in's block (see `LuaDevice::without`).
type Shared = Arc<Mutex<Running>>;

/// Why the script stopped, shared by the device and its controller. Only
/// the block that fails sets it, so the set never waits for another set.
type Failure = Arc<OnceLock<String>>;

pub struct LuaDevice {
    running: Shared,
    bufs: Box<Buffers>,
    max_block: usize,
    instrument: bool,
    midi_effect: bool,
    failed: Failure,
    stopped: bool,
    /// The events of the blocks that a call held the state through.
    missed: Missed,
}

/// Make the device a script describes, ready for blocks of up to
/// `max_block` frames.
pub fn make(path: &Path, sample_rate: f32, max_block: usize) -> Result<Instance> {
    let (device, controller) = build(path, sample_rate, max_block)?;
    Ok(Instance {
        device: Box::new(device),
        controller: Some(Box::new(controller)),
    })
}

/// The two sides of the device a script describes, with the state that
/// they share.
fn build(path: &Path, sample_rate: f32, max_block: usize) -> Result<(LuaDevice, LuaController)> {
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
        spilled: Vec::with_capacity(MAX_EVENTS),
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
        put("transport", (&raw mut bufs.transport).cast())?;
        host.get::<Function>("bind")?
            .call::<()>((ptr, max_block, MAX_EVENTS, sample_rate))?;
        host.get("run")
    };
    let run = bind(&mut bufs).map_err(lua_error)?;
    let call = host.get("call").map_err(lua_error)?;
    // Ready: from here on a block is timed by whoever waits for it.
    lua.remove_hook();
    let running = Arc::new(Mutex::new(Running { run, call, lua }));
    let failed: Failure = Arc::new(OnceLock::new());
    let misses = Arc::new(AtomicU64::new(0));
    let params: Vec<ParamInfo> = desc.params.iter().map(Param::info).collect();
    let values = desc.params.iter().map(|p| p.default as f64).collect();
    let device = LuaDevice {
        running: running.clone(),
        bufs,
        max_block,
        instrument: desc.category == Category::Instrument,
        midi_effect: desc.midi_effect,
        failed: failed.clone(),
        stopped: false,
        missed: Missed::new(MAX_EVENTS, misses.clone()),
    };
    let controller = LuaController {
        running,
        path: path.to_path_buf(),
        params,
        values,
        failed,
        sidechain: desc.sidechain,
        misses,
    };
    Ok((device, controller))
}

impl LuaDevice {
    /// What is heard from a device that has stopped, or from a block that
    /// comes while a call holds the state: nothing from an instrument, the
    /// input and its events untouched from an effect.
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
    // `saturating_sub`: a script may write any number here.
    let ch = event.channel.saturating_sub(1).clamp(0, 15) as u8;
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

/// Put in `io.events` the input `originals[kept]`, the events that did not
/// fit (`spilled`) and the script's `out`, by frame. On a tie the input goes
/// first, then the events that did not fit, then the script's.
///
/// `io.events` is emptied first and each event is pushed once, so the
/// buffer needs room for the input and the script's events only. A send of
/// the script drops when the input already fills the buffer (counted in
/// `dropped()`); an input event never drops.
fn merge(io: &mut Io, originals: &[Event], kept: std::ops::Range<usize>, out: &[LuaEvent], spilled: &[Event]) {
    io.events.clear();
    let (mut i, end) = (kept.start, kept.end);
    let (mut j, mut k) = (0, 0);
    while i < end || j < out.len() || k < spilled.len() {
        let frame_in = if i < end { originals[i].frame as i32 } else { i32::MAX };
        let frame_spill = spilled.get(k).map_or(i32::MAX, |e| e.frame as i32);
        let frame_out = out.get(j).map_or(i32::MAX, |e| e.frame);
        if i < end && frame_in <= frame_spill && frame_in <= frame_out {
            io.events.push(originals[i]);
            i += 1;
        } else if k < spilled.len() && frame_spill <= frame_out {
            io.events.push(spilled[k]);
            k += 1;
        } else {
            if let Some(kind) = from_lua(&out[j], originals) {
                io.events.push(Event { frame: out[j].frame as u32, kind });
            }
            j += 1;
        }
    }
}

impl Device for LuaDevice {
    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        if self.stopped {
            return self.without(io);
        }
        // The audio thread never waits for a call: while a call holds the
        // state, the script does not run this block, and its events wait for
        // the next one. A lock poisoned by a call that panicked is as good as
        // any: the state is Lua's, which does not stop halfway through a
        // change.
        let running = match self.running.try_lock() {
            Ok(running) => running,
            Err(TryLockError::Poisoned(poisoned)) => poisoned.into_inner(),
            Err(TryLockError::WouldBlock) => {
                self.missed.block(io.events.as_slice());
                if self.midi_effect {
                    // The script gives these events out when it runs.
                    io.events.clear();
                }
                return self.without(io);
            }
        };
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
        // The events of the missed blocks first, then this block's. What does
        // not fit waits for the next block.
        let mut count = 0;
        for event in self.missed.take() {
            b.originals[count] = event;
            count += 1;
        }
        let replayed = count;
        // What does not fit goes on downstream at once from a device that
        // passes its input on. A MIDI effect gives out only what it sends.
        b.spilled.clear();
        for event in io.events.as_slice() {
            if count < MAX_EVENTS {
                b.originals[count] = *event;
                count += 1;
            } else {
                self.missed.keep(*event);
                if !self.midi_effect && b.spilled.len() < MAX_EVENTS {
                    b.spilled.push(*event);
                }
            }
        }
        for (index, event) in b.originals[..count].iter().enumerate() {
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
        let sent = match running.run.call::<i64>((frames as i64, count as i64, keyed)) {
            Ok(sent) => (sent.max(0) as usize).min(MAX_EVENTS),
            Err(err) => {
                // Stopped for good: told through the controller, which the
                // helper asks, and shown in the session as a stopped device.
                self.stopped = true;
                let _ = self.failed.set(message(&err));
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
        // The replayed events went out with their own block already, past a
        // device that does not replace its input.
        let (from, kept) = if self.midi_effect { (0, 0) } else { (replayed, count) };
        merge(io, &b.originals[..count], from..kept, out, &b.spilled);
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
    /// The blocks that the script did not run, because a call held the state.
    misses: Arc<AtomicU64>,
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
        self.failed.get().cloned()
    }

    /// `lua.path` is the script's file; every other method is the script's
    /// own `dev.call(method, data)`, run in its state between two blocks.
    /// What that returns (a string, a number or nothing) is the answer.
    fn call(&mut self, method: &str, data: &[u8]) -> Result<Vec<u8>> {
        if method == "lua.path" {
            return Ok(self.path.to_string_lossy().into_owned().into_bytes());
        }
        if method == "lua.misses" {
            return Ok(self.misses.load(Ordering::Relaxed).to_string().into_bytes());
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

#[cfg(test)]
mod tests {
    use super::*;
    use paw_engine::EventBuf;

    /// A block that comes while a call holds the state returns at once:
    /// the audio thread never waits for the main thread.
    #[test]
    fn a_block_during_a_call_does_not_wait_for_it() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("level.lua");
        std::fs::write(
            &path,
            r#"
            local dev = require("paw.dsp").device { category = "instrument" }
            function dev.process(b)
              for i = 0, b.frames - 1 do b.left[i] = 1 end
            end
            return dev
            "#,
        )
        .unwrap();
        let (mut device, mut controller) = build(&path, 48000.0, 64).unwrap();
        let block = |device: &mut LuaDevice| {
            let (mut left, mut right) = (vec![0.5; 16], vec![0.5; 16]);
            let mut events = EventBuf::with_capacity(8);
            let mut io = Io {
                left: &mut left,
                right: &mut right,
                events: &mut events,
                sidechain: None,
                outputs: &mut [],
            };
            device.process(&ProcessCtx::at(48000.0, 120.0, 4, 4, true), &mut io);
            left[0]
        };

        // The guard stands for a call that runs in the script now.
        let call = controller.running.lock().unwrap();
        assert_eq!(block(&mut device), 0.0, "an instrument is silent while a call runs");
        drop(call);
        assert_eq!(block(&mut device), 1.0, "the next block is the script's again");
        assert_eq!(controller.health(), None, "a missed block does not stop the device");
    }

    /// A note-off in a block that the script does not run comes to the
    /// script in the next block, so the note does not hang.
    #[test]
    fn the_events_of_a_missed_block_come_in_the_next_block() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("offs.lua");
        std::fs::write(
            &path,
            r#"
            local dsp = require("paw.dsp")
            local dev = dsp.device { category = "instrument" }
            local seen = ""
            function dev.process(b)
              for i = 0, b.nevents - 1 do
                local e = b.events[i]
                if e.type == dsp.NOTE_OFF then seen = seen .. "off " .. e.key .. "@" .. e.frame .. " " end
              end
            end
            function dev.call() return seen end
            return dev
            "#,
        )
        .unwrap();
        let (mut device, mut controller) = build(&path, 48000.0, 64).unwrap();
        let block = |device: &mut LuaDevice, event: Option<Event>| {
            let (mut left, mut right) = (vec![0.0; 16], vec![0.0; 16]);
            let mut events = EventBuf::with_capacity(8);
            if let Some(event) = event {
                events.push(event);
            }
            let mut io = Io {
                left: &mut left,
                right: &mut right,
                events: &mut events,
                sidechain: None,
                outputs: &mut [],
            };
            device.process(&ProcessCtx::at(48000.0, 120.0, 4, 4, true), &mut io);
        };
        let off = Event {
            frame: 7,
            kind: EventKind::NoteOff { key: 60, ch: 0 },
        };

        let call = controller.running.lock().unwrap();
        block(&mut device, Some(off));
        drop(call);
        block(&mut device, None);
        assert_eq!(controller.call("seen", b"").unwrap(), b"off 60@0 ", "at the start of the next block");
        assert_eq!(controller.call("lua.misses", b"").unwrap(), b"1");
    }

    /// Run one block of `events` through `device`; what it gives out.
    fn through(device: &mut LuaDevice, events: &[Event]) -> Vec<Event> {
        let (mut left, mut right) = (vec![0.0; 16], vec![0.0; 16]);
        let mut buf = EventBuf::with_capacity(paw_engine::PART_EVENTS);
        for event in events {
            buf.push(*event);
        }
        let mut io = Io {
            left: &mut left,
            right: &mut right,
            events: &mut buf,
            sidechain: None,
            outputs: &mut [],
        };
        device.process(&ProcessCtx::at(48000.0, 120.0, 4, 4, true), &mut io);
        buf.as_slice().to_vec()
    }

    fn script(dir: &tempfile::TempDir, name: &str, text: &str) -> std::path::PathBuf {
        let path = dir.path().join(name);
        std::fs::write(&path, text).unwrap();
        path
    }

    fn note_off(key: u8) -> Event {
        Event { frame: 3, kind: EventKind::NoteOff { key, ch: 0 } }
    }

    #[test]
    fn a_channel_that_a_script_writes_never_overflows() {
        let event = |channel| LuaEvent { kind: NOTE_OFF, channel, key: 60, ..LuaEvent::default() };
        for (channel, want) in [(i32::MIN, 0), (-5, 0), (0, 0), (1, 0), (16, 15), (17, 15), (i32::MAX, 15)] {
            assert_eq!(
                from_lua(&event(channel), &[]),
                Some(EventKind::NoteOff { key: 60, ch: want }),
                "channel {channel}"
            );
        }
    }

    #[test]
    fn a_script_that_sends_on_a_channel_that_does_not_exist_stops_with_a_message() {
        let dir = tempfile::tempdir().unwrap();
        let path = script(
            &dir,
            "channel.lua",
            r#"
            local dsp = require("paw.dsp")
            local dev = dsp.device { midi_effect = true }
            function dev.process(b) b:note_on(0, 60, 1, 17) end
            return dev
            "#,
        );
        let (mut device, mut controller) = build(&path, 48000.0, 64).unwrap();
        through(&mut device, &[]);
        let why = controller.health().unwrap();
        assert!(why.contains("a channel is a whole number from 1 to 16, not 17"), "{why}");
    }

    /// An effect whose script sends one controller at frame 9.
    const SENDS_A_CC: &str = r#"
        local dsp = require("paw.dsp")
        local dev = dsp.device {}
        function dev.process(b) b:cc(9, 7, 0.5, 1) end
        return dev
    "#;

    #[test]
    fn an_effect_passes_on_the_events_that_do_not_fit_in_a_block_in_frame_order() {
        let dir = tempfile::tempdir().unwrap();
        let path = script(&dir, "cc.lua", SENDS_A_CC);
        let (mut device, controller) = build(&path, 48000.0, 64).unwrap();
        // A block that the script misses gives 2 replayed events, so the next
        // block of 1023 events does not all fit in the script's 1024. The
        // buffer has the 1024 slots of a part.
        let call = controller.running.lock().unwrap();
        through(&mut device, &[note_off(60), note_off(61)]);
        drop(call);
        let events: Vec<Event> = (0..paw_engine::PART_EVENTS - 1)
            .map(|i| Event { frame: 3, kind: EventKind::NoteOn { key: (i % 100) as u8, vel: 0.5, ch: 0, attr: Attr::NONE } })
            .collect();
        let dropped = paw_engine::event::dropped();
        let out = through(&mut device, &events);
        // Each event of the block once, and the script's controller after
        // them, as its frame (9) is later than theirs (3). All fit the 1024
        // slots, so nothing drops.
        assert_eq!(out.len(), events.len() + 1);
        assert_eq!(&out[..events.len()], &events[..], "in the order that they came");
        assert!(matches!(out[events.len()].kind, EventKind::Control { .. }));
        assert_eq!(paw_engine::event::dropped(), dropped, "no event dropped");
        assert!(out.windows(2).all(|w| w[0].frame <= w[1].frame), "in frame order");
        // The ones that did not fit reach the script in the next block, which
        // does not send them on again.
        let out = through(&mut device, &[]);
        assert_eq!(out.len(), 1, "only the script's controller: {out:?}");
    }

    #[test]
    fn a_script_may_send_back_an_all_notes_off_as_it_came_in() {
        let dir = tempfile::tempdir().unwrap();
        let path = script(
            &dir,
            "again.lua",
            r#"
            local dsp = require("paw.dsp")
            local dev = dsp.device { midi_effect = true }
            function dev.process(b)
              for i = 0, b.nevents - 1 do
                local e = b.events[i]
                b:send(e.frame, e.type, e.key, e.value, e.channel)
              end
            end
            return dev
            "#,
        );
        let (mut device, mut controller) = build(&path, 48000.0, 64).unwrap();
        let events = [note_off(60), note_off(61), Event { frame: 4, kind: EventKind::AllNotesOff }];
        assert_eq!(through(&mut device, &events), events);
        assert_eq!(controller.health(), None);
    }

    #[test]
    fn a_midi_effect_does_not_send_the_events_of_a_missed_block_twice() {
        let dir = tempfile::tempdir().unwrap();
        let path = script(
            &dir,
            "echo.lua",
            r#"
            local dsp = require("paw.dsp")
            local dev = dsp.device { midi_effect = true }
            function dev.process(b)
              for i = 0, b.nevents - 1 do
                local e = b.events[i]
                if e.type == dsp.NOTE_OFF then b:note_off(e.frame, e.key, e.channel) end
              end
            end
            return dev
            "#,
        );
        let (mut device, controller) = build(&path, 48000.0, 64).unwrap();
        let call = controller.running.lock().unwrap();
        assert!(through(&mut device, &[note_off(60)]).is_empty(), "a MIDI effect gives out only what the script sends");
        drop(call);
        let out = through(&mut device, &[note_off(61)]);
        let keys: Vec<u8> = out.iter().filter_map(|e| match e.kind { EventKind::NoteOff { key, .. } => Some(key), _ => None }).collect();
        assert_eq!(keys, [60, 61], "each event once: the missed one first");
        assert!(through(&mut device, &[]).is_empty());
    }
}
