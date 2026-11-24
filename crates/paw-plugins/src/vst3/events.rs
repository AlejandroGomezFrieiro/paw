//! paw's events to what VST3's `process` reads: the note events, the
//! parameter changes (a controller is a parameter in VST3) and the process
//! context. These COM objects are used on the audio thread only: no lock,
//! no allocation and no wait.

use std::cell::{Cell, UnsafeCell};
use std::ptr;

use paw_engine::ProcessCtx;
use paw_types::{Ctl, EventKind, NOTE_BEND_RANGE, NoteCtl};
use vst3::Steinberg::Vst::*;
use vst3::Steinberg::*;
use vst3::{Class, ComWrapper};

use super::{FALSE, OK};
use crate::HeldNotes;

const NOTE_ON: u16 = 0;
const NOTE_OFF: u16 = 1;
const POLY_PRESSURE: u16 = 3;
const NOTE_EXPRESSION: u16 = 4;

bitflags::bitflags! {
    /// `ProcessContext::state`.
    #[derive(Clone, Copy)]
    struct ProcessState: u32 {
        const PLAYING = 1 << 1;
        const MUSIC_TIME_VALID = 1 << 9;
        const TEMPO_VALID = 1 << 10;
        const BAR_VALID = 1 << 11;
        const TIME_SIG_VALID = 1 << 13;
    }
}

/// No parameter: a MIDI controller that the plugin maps to none.
pub(super) const NO_PARAM: ParamID = ParamID::MAX;

/// The transport as of the block's first frame, which is `samples` frames
/// after the plugin's first block.
pub(super) fn context(ctx: &ProcessCtx, sample_rate: f64, samples: i64) -> ProcessContext {
    // SAFETY: `ProcessContext` is plain data, for which all zeros is a valid value.
    let mut context: ProcessContext = unsafe { std::mem::zeroed() };
    context.state = (ProcessState::TEMPO_VALID
        | ProcessState::TIME_SIG_VALID
        | ProcessState::MUSIC_TIME_VALID
        | ProcessState::BAR_VALID
        | if ctx.playing { ProcessState::PLAYING } else { ProcessState::empty() })
    .bits();
    context.sampleRate = sample_rate;
    context.projectTimeSamples = samples;
    context.continousTimeSamples = samples;
    context.projectTimeMusic = ctx.position;
    context.barPositionMusic = ctx.bar_start;
    context.tempo = ctx.tempo;
    context.timeSigNumerator = ctx.sig_num as i32;
    context.timeSigDenominator = ctx.sig_den as i32;
    context
}

/// The id a note is known by to the plugin, which its own controllers name
/// it with: one per key and channel.
fn note_id(key: u8, ch: u8) -> i32 {
    ch as i32 * 128 + key as i32
}

/// The note events for one block. Filled and read on the audio thread.
pub(super) struct EventList {
    events: UnsafeCell<Vec<Event>>,
}

// SAFETY: The list is filled and read on the audio thread only, through `UnsafeCell`, one user at a time.
unsafe impl Send for EventList {}
// SAFETY: See `Send`: only the audio thread touches the list, so there is no sharing in fact.
unsafe impl Sync for EventList {}

impl EventList {
    /// Room for `capacity` events in a block: `fill` drops the events past
    /// it, and so never allocates.
    pub(super) fn with_capacity(capacity: usize) -> Self {
        Self {
            events: UnsafeCell::new(Vec::with_capacity(capacity)),
        }
    }

    /// The note events of the next block, from the block's events in
    /// `input`. A controller move goes to `controls` as the parameter that
    /// `midi_map` names for it, and its value, since VST3 has no controller
    /// messages.
    ///
    /// # Safety
    ///
    /// The caller is the audio thread, outside the plugin's `process`: the
    /// only user of the list.
    pub(super) unsafe fn fill(
        &self,
        held: &mut HeldNotes,
        input: &[paw_engine::Event],
        midi_map: &[ParamID; 130],
        controls: &mut Vec<(ParamID, f64)>,
    ) {
        // SAFETY: The caller is the only user of the list (see `# Safety`); the zeroed `Event` is
        // plain data, filled before use.
        unsafe {
            let events = &mut *self.events.get();
            events.clear();
            controls.clear();
            held.expand(input, |frame, kind| {
                if let EventKind::Control { ctl, value, .. } = kind {
                    let (number, value) = match ctl {
                        Ctl::Cc(number) => ((number & 127) as usize, value),
                        Ctl::Pressure => (128, value),
                        Ctl::Bend => (129, (value + 1.0) * 0.5),
                        // VST3 has nowhere to put these.
                        Ctl::Registered(..) | Ctl::Assignable(..) => return,
                    };
                    if midi_map[number] != NO_PARAM && controls.len() < controls.capacity() {
                        controls.push((midi_map[number], value.clamp(0.0, 1.0)));
                    }
                    return;
                }
                if events.len() == events.capacity() {
                    return;
                }
                let mut event: Event = std::mem::zeroed();
                event.sampleOffset = frame as i32;
                match kind {
                    EventKind::NoteOn { key, vel, ch, .. } => {
                        event.r#type = NOTE_ON;
                        event.__field0.noteOn = NoteOnEvent {
                            channel: ch as i16,
                            pitch: key as i16,
                            tuning: 0.0,
                            velocity: vel,
                            length: 0,
                            noteId: note_id(key, ch),
                        };
                    }
                    EventKind::NoteOff { key, ch } => {
                        event.r#type = NOTE_OFF;
                        event.__field0.noteOff = NoteOffEvent {
                            channel: ch as i16,
                            pitch: key as i16,
                            velocity: 0.0,
                            noteId: note_id(key, ch),
                            tuning: 0.0,
                        };
                    }
                    EventKind::NoteControl {
                        key,
                        ctl: NoteCtl::Pressure,
                        value,
                        ch,
                    } => {
                        event.r#type = POLY_PRESSURE;
                        event.__field0.polyPressure = PolyPressureEvent {
                            channel: ch as i16,
                            pitch: key as i16,
                            pressure: value as f32,
                            noteId: note_id(key, ch),
                        };
                    }
                    // A note's own controllers are VST3's note expressions.
                    EventKind::NoteControl {
                        key,
                        ctl,
                        value,
                        ch,
                    } => {
                        let (type_id, value) = match ctl {
                            // Tuning is 0.5 at rest and spans 120 semitones each way.
                            NoteCtl::Bend => (2, 0.5 + value * NOTE_BEND_RANGE / 240.0),
                            NoteCtl::Registered(7) => (0, value * 0.25),
                            NoteCtl::Registered(10) => (1, value),
                            NoteCtl::Registered(1) => (3, value),
                            NoteCtl::Registered(11) => (4, value),
                            NoteCtl::Registered(74) => (5, value),
                            _ => return,
                        };
                        event.r#type = NOTE_EXPRESSION;
                        event.__field0.noteExpressionValue = NoteExpressionValueEvent {
                            typeId: type_id,
                            noteId: note_id(key, ch),
                            value,
                        };
                    }
                    EventKind::AllNotesOff
                    | EventKind::Control { .. }
                    | EventKind::Program { .. } => return,
                }
                events.push(event);
            });
        }
    }
}

impl Class for EventList {
    type Interfaces = (IEventList,);
}

impl IEventListTrait for EventList {
    unsafe fn getEventCount(&self) -> i32 {
        // SAFETY: The list is used on the audio thread only; the plugin calls this inside `process`, when
        // `process` has finished filling it and does not touch it.
        unsafe { (&*self.events.get()).len() as i32 }
    }

    unsafe fn getEvent(&self, index: i32, event: *mut Event) -> tresult {
        // SAFETY: The plugin calls this inside `process`, on the audio thread, when `process` is not
        // changing the list; `event` is a plugin-owned `Event` to write into, distinct from the list's own.
        unsafe {
            let events = &*self.events.get();
            match events.get(index as usize) {
                Some(found) => {
                    ptr::copy_nonoverlapping(found, event, 1);
                    OK
                }
                None => FALSE,
            }
        }
    }

    unsafe fn addEvent(&self, _event: *mut Event) -> tresult {
        FALSE
    }
}

/// One parameter change at the start of the block.
struct ParamQueue {
    id: Cell<ParamID>,
    value: Cell<f64>,
}

// SAFETY: A ParamQueue is written by the audio thread before `process` and read by the plugin
// inside it, on that thread; the Cells are never touched from two threads at once.
unsafe impl Send for ParamQueue {}
// SAFETY: See `Send`: only the audio thread uses a queue.
unsafe impl Sync for ParamQueue {}

impl Class for ParamQueue {
    type Interfaces = (IParamValueQueue,);
}

impl IParamValueQueueTrait for ParamQueue {
    unsafe fn getParameterId(&self) -> ParamID {
        self.id.get()
    }

    unsafe fn getPointCount(&self) -> i32 {
        1
    }

    unsafe fn getPoint(&self, index: i32, offset: *mut i32, value: *mut ParamValue) -> tresult {
        if index != 0 {
            return FALSE;
        }
        // SAFETY: The plugin passes non-null `offset` and `value` to write to, as the ABI requires.
        unsafe {
            *offset = 0;
            *value = self.value.get();
        }
        OK
    }

    unsafe fn addPoint(&self, _offset: i32, _value: ParamValue, _index: *mut i32) -> tresult {
        FALSE
    }
}

/// The parameter changes for one block: a fixed pool of queues, of which the
/// first `used` are live.
pub(super) struct ParamChanges {
    queues: Vec<ComWrapper<ParamQueue>>,
    used: Cell<usize>,
}

// SAFETY: The queues are changed by the audio thread before `process` and read inside it, on that thread.
unsafe impl Send for ParamChanges {}
// SAFETY: See `Send`: only the audio thread uses the changes.
unsafe impl Sync for ParamChanges {}

impl ParamChanges {
    /// A pool of `count` queues: the most parameters one block changes.
    pub(super) fn new(count: usize) -> Self {
        Self {
            queues: (0..count)
                .map(|_| {
                    ComWrapper::new(ParamQueue {
                        id: Cell::new(0),
                        value: Cell::new(0.0),
                    })
                })
                .collect(),
            used: Cell::new(0),
        }
    }

    /// The changes of the next block: the parameter changes in `pending`
    /// (index and value), then the controller moves in `controls`. Both are
    /// emptied, and what finds no free queue is dropped. Audio thread.
    pub(super) fn fill(
        &self,
        pending: &mut Vec<(u32, f32)>,
        controls: &mut Vec<(ParamID, f64)>,
        param_ids: &[ParamID],
    ) {
        let mut used = 0;
        for (index, value) in pending.drain(..) {
            let Some(&id) = param_ids.get(index as usize) else {
                continue;
            };
            // One queue for each parameter: the last value set wins (a
            // value a state gave comes after one set before it).
            if let Some(queue) = self.queues[..used].iter().find(|q| q.id.get() == id) {
                queue.value.set(value as f64);
                continue;
            }
            let Some(queue) = self.queues.get(used) else {
                continue;
            };
            queue.id.set(id);
            queue.value.set(value as f64);
            used += 1;
        }
        for (id, value) in controls.drain(..) {
            let Some(queue) = self.queues.get(used) else {
                break;
            };
            queue.id.set(id);
            queue.value.set(value);
            used += 1;
        }
        self.used.set(used);
    }
}

impl Class for ParamChanges {
    type Interfaces = (IParameterChanges,);
}

impl IParameterChangesTrait for ParamChanges {
    unsafe fn getParameterCount(&self) -> i32 {
        self.used.get() as i32
    }

    unsafe fn getParameterData(&self, index: i32) -> *mut IParamValueQueue {
        match self.queues.get(index as usize) {
            Some(queue) if (index as usize) < self.used.get() => {
                queue.as_com_ref::<IParamValueQueue>().unwrap().as_ptr()
            }
            _ => ptr::null_mut(),
        }
    }

    unsafe fn addParameterData(
        &self,
        _id: *const ParamID,
        _index: *mut i32,
    ) -> *mut IParamValueQueue {
        ptr::null_mut()
    }
}

/// Where the plugin reports parameter changes of its own. Some plugins
/// insist on having somewhere to write them; nothing reads them yet.
pub(super) struct Discard {
    queue: ComWrapper<DiscardQueue>,
}

impl Discard {
    pub(super) fn new() -> Self {
        Self {
            queue: ComWrapper::new(DiscardQueue),
        }
    }
}

struct DiscardQueue;

// SAFETY: Discard holds a queue that is stateless and used only inside `process`, on the audio thread.
unsafe impl Send for Discard {}
// SAFETY: See `Send`: it has no state to share.
unsafe impl Sync for Discard {}

impl Class for Discard {
    type Interfaces = (IParameterChanges,);
}

impl Class for DiscardQueue {
    type Interfaces = (IParamValueQueue,);
}

impl IParameterChangesTrait for Discard {
    unsafe fn getParameterCount(&self) -> i32 {
        0
    }

    unsafe fn getParameterData(&self, _index: i32) -> *mut IParamValueQueue {
        ptr::null_mut()
    }

    unsafe fn addParameterData(
        &self,
        _id: *const ParamID,
        index: *mut i32,
    ) -> *mut IParamValueQueue {
        if !index.is_null() {
            // SAFETY: `index` is null-checked above; the plugin owns it for the call.
            unsafe { *index = 0 };
        }
        self.queue
            .as_com_ref::<IParamValueQueue>()
            .unwrap()
            .as_ptr()
    }
}

impl IParamValueQueueTrait for DiscardQueue {
    unsafe fn getParameterId(&self) -> ParamID {
        0
    }

    unsafe fn getPointCount(&self) -> i32 {
        0
    }

    unsafe fn getPoint(&self, _index: i32, _offset: *mut i32, _value: *mut ParamValue) -> tresult {
        FALSE
    }

    unsafe fn addPoint(&self, _offset: i32, _value: ParamValue, index: *mut i32) -> tresult {
        if !index.is_null() {
            // SAFETY: `index` is null-checked above; the plugin owns it for the call.
            unsafe { *index = 0 };
        }
        OK
    }
}

