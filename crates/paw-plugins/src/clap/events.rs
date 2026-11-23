//! paw's events to CLAP's events, and the plugin's output events back. The
//! conversion runs on the audio thread: no lock, no allocation and no wait.

use std::ptr;

use clack_host::events::event_types::{TransportEvent, TransportFlags};
use clack_host::events::io::{InputEventBuffer, OutputEventBuffer, TryPushError};
use clack_host::events::spaces::CoreEventSpace;
use clack_host::events::EventFlags;
use clack_host::prelude::{ClapId, EventHeader, UnknownEvent};
use clack_host::utils::{Cookie, FixedPoint};
use clap_sys::events::*;
use clap_sys::id::clap_id;
use paw_engine::{Event, EventKind, NOTE_BEND_RANGE, NoteCtl, ProcessCtx, ump};

use crate::HeldNotes;

/// One CLAP event of any type that paw sends.
#[repr(C)]
#[derive(Clone, Copy)]
pub(super) union ClapEvent {
    header: clap_event_header,
    note: clap_event_note,
    param: clap_event_param_value,
    midi: clap_event_midi,
    midi2: clap_event_midi2,
    expression: clap_event_note_expression,
}

/// The CLAP note expression a per-note controller is, and its value there.
/// The registered per-note controllers mean what the control changes of the
/// same number do.
fn expression(ctl: NoteCtl, value: f64) -> Option<(clap_note_expression, f64)> {
    Some(match ctl {
        NoteCtl::Bend => (CLAP_NOTE_EXPRESSION_TUNING, value * NOTE_BEND_RANGE),
        NoteCtl::Pressure => (CLAP_NOTE_EXPRESSION_PRESSURE, value),
        // CLAP's volume is a gain with 1 as unity; full scale here is unity.
        NoteCtl::Registered(7) => (CLAP_NOTE_EXPRESSION_VOLUME, value.max(1e-4)),
        NoteCtl::Registered(10) => (CLAP_NOTE_EXPRESSION_PAN, value),
        NoteCtl::Registered(1) => (CLAP_NOTE_EXPRESSION_VIBRATO, value),
        NoteCtl::Registered(11) => (CLAP_NOTE_EXPRESSION_EXPRESSION, value),
        NoteCtl::Registered(74) => (CLAP_NOTE_EXPRESSION_BRIGHTNESS, value),
        _ => return None,
    })
}

fn header<T>(time: u32, type_: clap_event_type) -> clap_event_header {
    clap_event_header {
        size: size_of::<T>() as u32,
        time,
        space_id: CLAP_CORE_EVENT_SPACE_ID,
        type_,
        flags: 0,
    }
}

/// How a plugin takes paw's events, from its note dialects.
#[derive(Clone, Copy)]
pub(super) struct NoteRoute {
    /// Whether the plugin takes CLAP note events rather than MIDI.
    pub(super) clap_notes: bool,
    /// Whether it takes MIDI 1.0 messages, and MIDI 2.0 ones, for what is
    /// not a note.
    pub(super) midi: bool,
    pub(super) midi2: bool,
}

/// The events of one block, as the plugin reads them.
pub(super) struct ClapEvents(Vec<ClapEvent>);

impl ClapEvents {
    /// Room for `capacity` events in a block: `fill` drops the events past
    /// it, and so never allocates.
    pub(super) fn with_capacity(capacity: usize) -> Self {
        Self(Vec::with_capacity(capacity))
    }

    /// The events of the next block: the parameter changes in `pending`
    /// (which it empties) first, at its start, then the block's events in
    /// `input`, as `route` says the plugin takes them. Audio thread.
    pub(super) fn fill(
        &mut self,
        pending: &mut Vec<(u32, f32)>,
        param_ids: &[(ClapId, Cookie)],
        held: &mut HeldNotes,
        input: &[Event],
        route: NoteRoute,
    ) {
        let events = &mut self.0;
        events.clear();
        for (index, value) in pending.drain(..) {
            let Some(&(param_id, cookie)) = param_ids.get(index as usize) else {
                continue;
            };
            events.push(ClapEvent {
                param: clap_event_param_value {
                    header: header::<clap_event_param_value>(0, CLAP_EVENT_PARAM_VALUE),
                    param_id: param_id.get(),
                    cookie: cookie.as_raw(),
                    note_id: -1,
                    port_index: -1,
                    channel: -1,
                    key: -1,
                    value: value as f64,
                },
            });
        }
        let NoteRoute {
            clap_notes,
            midi,
            midi2,
        } = route;
        held.expand(input, |frame, kind| {
            let mut push = |event: ClapEvent| {
                if events.len() < events.capacity() {
                    events.push(event);
                }
            };
            match kind {
                EventKind::NoteOn { key, ch, .. } | EventKind::NoteOff { key, ch }
                    if clap_notes =>
                {
                    let (type_, velocity) = match kind {
                        EventKind::NoteOn { vel, .. } => (CLAP_EVENT_NOTE_ON, vel as f64),
                        _ => (CLAP_EVENT_NOTE_OFF, 0.0),
                    };
                    push(ClapEvent {
                        note: clap_event_note {
                            header: header::<clap_event_note>(frame, type_),
                            note_id: -1,
                            port_index: 0,
                            channel: ch as i16,
                            key: key as i16,
                            velocity,
                        },
                    });
                }
                // A note's own controllers are what CLAP calls note expressions.
                EventKind::NoteControl {
                    key,
                    ctl,
                    value,
                    ch,
                } if clap_notes && expression(ctl, value).is_some() => {
                    let (expression_id, value) = expression(ctl, value).unwrap();
                    push(ClapEvent {
                        expression: clap_event_note_expression {
                            header: header::<clap_event_note_expression>(
                                frame,
                                CLAP_EVENT_NOTE_EXPRESSION,
                            ),
                            expression_id,
                            note_id: -1,
                            port_index: 0,
                            channel: ch as i16,
                            key: key as i16,
                            value,
                        },
                    });
                }
                // Everything else is MIDI: as 2.0, whole, to a plugin
                // that takes it, and as 1.0 otherwise.
                _ if midi2 => {
                    if let Some(data) = ump::encode(0, kind) {
                        push(ClapEvent {
                            midi2: clap_event_midi2 {
                                header: header::<clap_event_midi2>(frame, CLAP_EVENT_MIDI2),
                                port_index: 0,
                                data: [data[0], data[1], 0, 0],
                            },
                        });
                    }
                }
                _ if midi => ump::midi1(kind, |data, _| {
                    push(ClapEvent {
                        midi: clap_event_midi {
                            header: header::<clap_event_midi>(frame, CLAP_EVENT_MIDI),
                            port_index: 0,
                            data,
                        },
                    })
                }),
                _ => {}
            }
        });
    }
}

impl InputEventBuffer for ClapEvents {
    fn len(&self) -> u32 {
        self.0.len() as u32
    }

    fn get(&self, index: u32) -> Option<&UnknownEvent> {
        let event = self.0.get(index as usize)?;
        // SAFETY: Each event was built whole by `fill`, with a header that names its own type
        // and size, and the union holds at least that size; the event lives as long as `self`.
        Some(unsafe { UnknownEvent::from_raw(ptr::from_ref(event).cast()) })
    }
}

/// What a plugin tells in its output events.
pub(super) struct Out {
    /// Parameter values it reports changing, on their way to the
    /// controller: CLAP id, value, whether it came inside a gesture, and
    /// whether it came in the first block after a state.
    pub(super) changed: rtrb::Producer<(clap_id, f64, bool, bool)>,
    /// The block the plugin processes now is the first after a state.
    pub(super) taking: bool,
    /// The parameters between `GESTURE_BEGIN` and `GESTURE_END` now: a
    /// person moves them in the plugin's window.
    pub(super) gestures: Vec<clap_id>,
}

/// The plugin's output events. Only parameter changes and gestures are
/// kept: they are how a plugin tells the host what was done in its editor.
impl OutputEventBuffer for Out {
    fn try_push(&mut self, event: &UnknownEvent) -> Result<(), TryPushError> {
        match event.as_core_event() {
            Some(CoreEventSpace::ParamValue(event)) => {
                if let Some(id) = event.param_id().map(ClapId::get) {
                    let gesture = self.gestures.contains(&id);
                    let _ = self.changed.push((id, event.value(), gesture, self.taking));
                }
            }
            Some(CoreEventSpace::ParamGestureBegin(event)) => {
                // Room is kept for many at once: no allocation here.
                if let Some(id) = event.param_id().map(ClapId::get)
                    && self.gestures.len() < self.gestures.capacity()
                {
                    self.gestures.push(id);
                }
            }
            Some(CoreEventSpace::ParamGestureEnd(event)) => {
                if let Some(id) = event.param_id().map(ClapId::get) {
                    self.gestures.retain(|known| *known != id);
                }
            }
            _ => {}
        }
        Ok(())
    }
}

/// The transport as of the block's first frame.
pub(super) fn transport(ctx: &ProcessCtx) -> TransportEvent {
    // Cut toward zero into CLAP's fixed point, not rounded.
    let fixed = |value: f64| FixedPoint::from_bits((value * FixedPoint::FACTOR as f64) as i64);
    let mut flags = TransportFlags::HAS_TEMPO
        | TransportFlags::HAS_BEATS_TIMELINE
        | TransportFlags::HAS_SECONDS_TIMELINE
        | TransportFlags::HAS_TIME_SIGNATURE;
    flags.set(TransportFlags::IS_PLAYING, ctx.playing);
    TransportEvent {
        header: EventHeader::new_core(0, EventFlags::empty()),
        flags,
        song_pos_beats: fixed(ctx.position),
        song_pos_seconds: fixed(ctx.seconds),
        tempo: ctx.tempo,
        tempo_inc: 0.0,
        loop_start_beats: FixedPoint::default(),
        loop_end_beats: FixedPoint::default(),
        loop_start_seconds: FixedPoint::default(),
        loop_end_seconds: FixedPoint::default(),
        bar_start: fixed(ctx.bar_start),
        bar_number: ctx.bar as i32,
        time_signature_numerator: ctx.sig_num as u16,
        time_signature_denominator: ctx.sig_den as u16,
    }
}
