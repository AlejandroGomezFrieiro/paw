//! Cues: clips kept off a track's timeline, started and stopped on the
//! beat while the song plays (`paw-core`'s `session/cues.rs`; the clip
//! launcher extension is one user). A track's cue clips are in rows here,
//! which the core keeps stable for each clip.
//!
//! A launch is asked for with [`Msg::Launch`](crate::Msg::Launch) and
//! happens on the first boundary of its [`Quantize`] at or after the
//! position the engine is at when it takes the message, to the frame: the
//! engine ends a block there. While a track plays a slot, or has been
//! stopped, its clips on the timeline are silent; it plays them again once
//! it is sent back to the arrangement, or when the transport stops.

use std::sync::atomic::{AtomicU32, Ordering::Relaxed};

use atomic_float::AtomicF64;

use crate::clip::{ClipSet, Stamp};
use crate::device::ProcessCtx;
use crate::engine::mix_audio_constant;
use crate::slot::TrackSlot;
use crate::event::{Attr, Event, EventBuf};
use crate::tempo::TempoMap;

/// A clip in a slot: events and sound laid out in beats from its start,
/// repeated every `length` beats.
pub struct SlotClip {
    pub clips: ClipSet,
    pub length: f64,
}

/// A track's slots, by row; `None` for an empty one.
#[derive(Default)]
pub struct Slots {
    pub rows: Vec<Option<SlotClip>>,
}

impl Slots {
    fn get(&self, row: u32) -> Option<&SlotClip> {
        self.rows
            .get(row as usize)?
            .as_ref()
            .filter(|s| s.length > 0.0)
    }
}

/// Where launches land.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Quantize {
    /// At once.
    Off,
    /// On a grid of this many beats (quarter notes), counted from the
    /// start of each bar.
    Grid(f64),
    /// On the beats of the signature: an eighth in 6/8.
    Beat,
    /// On the start of every so many bars, counted from the first.
    Bars(u32),
}

/// Two positions this close are the same.
const EPS: f64 = 1e-9;

impl Quantize {
    /// The first boundary at or after `beat`.
    pub fn next(self, map: &TempoMap, beat: f64) -> f64 {
        let beat = beat.max(0.0);
        match self {
            Quantize::Off => beat,
            Quantize::Bars(every) => {
                let every = every.max(1) as i64;
                let mut bar = map.bar_of(beat);
                if map.bar_start(bar) < beat - EPS {
                    bar += 1;
                }
                map.bar_start((bar + every - 1).div_euclid(every) * every)
            }
            Quantize::Grid(_) | Quantize::Beat => {
                let bar = map.bar_of(beat);
                let start = map.bar_start(bar);
                let unit = match self {
                    Quantize::Grid(unit) => unit.max(1e-3),
                    _ => 4.0 / map.bar_signature(bar).1 as f64,
                };
                let steps = ((beat - start) / unit - EPS).ceil().max(0.0);
                (start + steps * unit).min(map.bar_start(bar + 1))
            }
        }
    }
}

/// What a launch asks a track to do.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Target {
    /// Play the clip in this row; an empty row stops the track.
    Slot(u32),
    /// Play nothing.
    Stop,
    /// Play the track's clips on the timeline again.
    Arrangement,
}

/// How a target is published in a [`LaunchState`].
const NONE: u32 = u32::MAX;
const STOP: u32 = u32::MAX - 1;
const ARRANGEMENT: u32 = u32::MAX - 2;

impl Target {
    fn code(self) -> u32 {
        match self {
            Target::Slot(row) => row.min(ARRANGEMENT - 1),
            Target::Stop => STOP,
            Target::Arrangement => ARRANGEMENT,
        }
    }

    fn from_code(code: u32) -> Option<Self> {
        match code {
            NONE => None,
            STOP => Some(Target::Stop),
            ARRANGEMENT => Some(Target::Arrangement),
            row => Some(Target::Slot(row)),
        }
    }
}

/// One track's launch.
#[derive(Clone, Copy, Debug)]
pub struct Launch {
    pub track: TrackSlot,
    pub target: Target,
    pub quantize: Quantize,
    /// Take over where the clip playing before had got to in its loop,
    /// instead of starting from the beginning.
    pub legato: bool,
    /// The beat the clip's loop counts from, as if it had played since
    /// then: a clip just recorded goes on in step with where it began.
    pub from: Option<f64>,
}

/// What a track plays.
#[derive(Clone, Copy, Debug, PartialEq)]
enum Playing {
    Arrangement,
    Stopped,
    /// A slot's clip, `phase` beats into its loop.
    Slot {
        row: u32,
        phase: f64,
    },
}

#[derive(Clone, Copy, Debug)]
struct Queued {
    target: Target,
    quantize: Quantize,
    legato: bool,
    from: Option<f64>,
    /// The project beat it happens on.
    at: f64,
}

/// A track's clip launcher, on the audio thread.
pub struct Launcher {
    slots: Box<Slots>,
    playing: Playing,
    queued: Option<Queued>,
    /// The project beat on which what plays now began.
    since: f64,
}

impl Default for Launcher {
    fn default() -> Self {
        Self {
            slots: Box::default(),
            playing: Playing::Arrangement,
            queued: None,
            since: 0.0,
        }
    }
}

/// What changed when a launch was carried out: the notes that were
/// sounding stop, and those held at the new place start (`chase`).
pub(crate) struct Change {
    pub chase: bool,
}

impl Launcher {
    /// Take new slots, handing back the old. A slot that plays keeps its
    /// place in its loop; one that was emptied stops.
    pub(crate) fn set_slots(&mut self, slots: Box<Slots>) -> Box<Slots> {
        let old = std::mem::replace(&mut self.slots, slots);
        if let Playing::Slot { row, phase } = self.playing {
            self.playing = match self.slots.get(row) {
                Some(slot) => Playing::Slot {
                    row,
                    phase: phase.rem_euclid(slot.length),
                },
                None => Playing::Stopped,
            };
        }
        old
    }

    /// Queue a launch for the beat `at`, in place of any queued before.
    pub(crate) fn queue(&mut self, launch: &Launch, at: f64) {
        self.queued = Some(Queued {
            target: launch.target,
            quantize: launch.quantize,
            legato: launch.legato,
            from: launch.from,
            at,
        });
    }

    /// Where a queued launch happens, if one is.
    pub(crate) fn queued_at(&self) -> Option<f64> {
        self.queued.map(|q| q.at)
    }

    /// Move what is queued to the first boundary from `beat`: the song
    /// jumped there (a seek, or the loop going round).
    pub(crate) fn requantize(&mut self, map: &TempoMap, beat: f64) {
        if let Some(q) = self.queued.as_mut() {
            q.at = q.quantize.next(map, beat);
        }
    }

    /// Back to the arrangement, with nothing queued. Whether that changed
    /// what plays.
    pub(crate) fn reset(&mut self) -> bool {
        self.queued = None;
        let changed = self.playing != Playing::Arrangement;
        self.playing = Playing::Arrangement;
        changed
    }

    /// Carry out what is queued, if it is due at `start`, give or take
    /// `slack` beats.
    pub(crate) fn commit(&mut self, start: f64, slack: f64) -> Option<Change> {
        let q = self.queued.filter(|q| q.at <= start + slack.max(EPS))?;
        self.queued = None;
        let was = self.playing;
        self.playing = match q.target {
            Target::Slot(row) => match self.slots.get(row) {
                Some(slot) => Playing::Slot {
                    row,
                    phase: match (was, q.from) {
                        (_, Some(from)) => (q.at - from).rem_euclid(slot.length),
                        (Playing::Slot { phase, .. }, None) if q.legato => {
                            phase.rem_euclid(slot.length)
                        }
                        _ => 0.0,
                    },
                },
                None => Playing::Stopped,
            },
            Target::Stop => Playing::Stopped,
            Target::Arrangement => Playing::Arrangement,
        };
        self.since = q.at;
        let chase = match self.playing {
            Playing::Arrangement => true,
            Playing::Slot { phase, .. } => phase > 0.0,
            Playing::Stopped => false,
        };
        Some(Change { chase })
    }

    pub(crate) fn follows_arrangement(&self) -> bool {
        self.playing == Playing::Arrangement
    }

    /// The clip that plays, and how far into its loop.
    pub(crate) fn slot(&self) -> Option<(&SlotClip, f64)> {
        match self.playing {
            Playing::Slot { row, phase } => Some((self.slots.get(row)?, phase)),
            _ => None,
        }
    }

    /// Move on by `beats` of the song.
    pub(crate) fn advance(&mut self, beats: f64) {
        if let Playing::Slot { row, phase } = self.playing
            && let Some(slot) = self.slots.get(row)
        {
            self.playing = Playing::Slot {
                row,
                phase: (phase + beats).rem_euclid(slot.length),
            };
        }
    }

    pub(crate) fn publish(&self, state: &LaunchState) {
        let (playing, phase) = match self.playing {
            Playing::Arrangement => (ARRANGEMENT, 0.0),
            Playing::Stopped => (STOP, 0.0),
            Playing::Slot { row, phase } => (Target::Slot(row).code(), phase),
        };
        state.playing.store(playing, Relaxed);
        state.phase.store(phase, Relaxed);
        state.since.store(self.since, Relaxed);
        let (queued, at) = self.queued.map_or((NONE, 0.0), |q| (q.target.code(), q.at));
        state.queued.store(queued, Relaxed);
        state.at.store(at, Relaxed);
    }
}

/// A track's launcher as the audio thread last left it, for the main
/// thread to read.
pub struct LaunchState {
    playing: AtomicU32,
    phase: AtomicF64,
    since: AtomicF64,
    queued: AtomicU32,
    at: AtomicF64,
}

impl Default for LaunchState {
    fn default() -> Self {
        Self {
            playing: AtomicU32::new(ARRANGEMENT),
            phase: AtomicF64::new(0.0),
            since: AtomicF64::new(0.0),
            queued: AtomicU32::new(NONE),
            at: AtomicF64::new(0.0),
        }
    }
}

/// A copy of a [`LaunchState`].
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct LaunchView {
    /// What the track plays: never [`None`].
    pub playing: Target,
    /// Beats into the loop of the slot that plays.
    pub phase: f64,
    /// The project beat on which that began.
    pub since: f64,
    /// What is queued, and the beat it happens on.
    pub queued: Option<(Target, f64)>,
}

impl LaunchState {
    pub fn view(&self) -> LaunchView {
        let at = self.at.load(Relaxed);
        LaunchView {
            playing: Target::from_code(self.playing.load(Relaxed)).unwrap_or(Target::Arrangement),
            phase: self.phase.load(Relaxed),
            since: self.since.load(Relaxed),
            queued: Target::from_code(self.queued.load(Relaxed)).map(|t| (t, at)),
        }
    }
}

/// Start again the notes of `clips` that began before `before` and are still
/// held at it, and put every controller where it was last moved to, as if
/// playback had run through them. What the instrument was last told to
/// play (a keyswitch, see [`ClipSet::switches`]) is told again first.
pub(crate) fn chase(events: &mut EventBuf, clips: &ClipSet, before: f64) {
    use crate::event::EventKind;
    // Each key's last note-on, while it is held: velocity, channel, attribute.
    let mut held = [(0f32, 0u8, Attr::NONE); 128];
    let mut controllers = [f64::NAN; 130];
    let mut program = None;
    // The last event for each, in the order the track plays them: the
    // parts of its clips are each in order, but not with each other.
    let mut held_at = [Stamp::FIRST; 128];
    let mut controllers_at = [Stamp::FIRST; 130];
    let mut program_at = Stamp::FIRST;
    clips.each_before(before, |ev, at| match ev.kind {
        EventKind::NoteOn { key, vel, ch, attr } => {
            let k = (key & 127) as usize;
            if at.after(&held_at[k]) {
                held_at[k] = at;
                held[k] = (vel, ch, attr);
            }
        }
        EventKind::NoteOff { key, .. } => {
            let k = (key & 127) as usize;
            if at.after(&held_at[k]) {
                held_at[k] = at;
                held[k].0 = 0.0;
            }
        }
        EventKind::Control { ctl, value, .. } => {
            if let Some(index) = crate::engine::ctl_index(ctl)
                && at.after(&controllers_at[index])
            {
                controllers_at[index] = at;
                controllers[index] = value;
            }
        }
        EventKind::Program { .. } => {
            if at.after(&program_at) {
                program_at = at;
                program = Some(ev.kind);
            }
        }
        EventKind::NoteControl { .. } | EventKind::AllNotesOff => {}
    });
    for &kind in clips.switch_before(before) {
        match kind {
            // A keyswitch held down is started again with the held notes.
            EventKind::NoteOn { key, .. } if held[(key & 127) as usize].0 > 0.0 => {}
            // One struck is struck and let go.
            EventKind::NoteOn { key, ch, .. } => {
                events.push(Event { frame: 0, kind });
                let kind = EventKind::NoteOff { key, ch };
                events.push(Event { frame: 0, kind });
            }
            _ => events.push(Event { frame: 0, kind }),
        }
    }
    if let Some(kind) = program {
        events.push(Event { frame: 0, kind });
    }
    for (index, value) in controllers.into_iter().enumerate() {
        if !value.is_nan() {
            let kind = EventKind::Control {
                ctl: crate::engine::ctl_at(index),
                value,
                ch: 0,
            };
            events.push(Event { frame: 0, kind });
        }
    }
    for (key, (vel, ch, attr)) in held.into_iter().enumerate() {
        if vel > 0.0 {
            let kind = EventKind::NoteOn {
                key: key as u8,
                vel,
                ch,
                attr,
            };
            events.push(Event { frame: 0, kind });
        }
    }
}

/// Play `span` beats of a slot's clip from `phase` into a block of `n`
/// frames: its events into `events`, its sound into the buffers. The clip
/// goes round to its start at its length. The block's beats are spread
/// evenly over its frames, at the tempo it starts with.
#[allow(clippy::too_many_arguments)]
pub(crate) fn play(
    slot: &SlotClip,
    phase: f64,
    span: f64,
    n: usize,
    events: &mut EventBuf,
    left: &mut [f32],
    right: &mut [f32],
    ctx: &ProcessCtx,
) {
    if span <= 0.0 || n == 0 || slot.length <= 0.0 {
        return;
    }
    // At one tempo the block's beats per frame are the tempo's, exactly.
    let sr = ctx.sample_rate as f64;
    let steady = ctx.tempo / (60.0 * sr);
    let per_frame = span / n as f64;
    let (per_frame, tempo) = if (per_frame - steady).abs() <= 1e-9 * steady {
        (steady, ctx.tempo)
    } else {
        (per_frame, per_frame * 60.0 * sr)
    };
    let frame = |beats: f64| ((beats / per_frame).round().max(0.0) as usize).min(n);
    let local = ProcessCtx { tempo, ..*ctx };
    let (mut at, mut done) = (phase.rem_euclid(slot.length), 0.0);
    while span - done > EPS * span.max(1.0) {
        let to = (at + span - done).min(slot.length);
        // The piece that reaches the clip's end takes the note-offs on it.
        let ends = to >= slot.length;
        // Beats from the block's first frame to the clip's start, this time round.
        let base = done - at;
        let first = slot.clips.midi.partition_point(|e| e.beat < at);
        for ev in &slot.clips.midi[first..] {
            if ev.beat > to || (ev.beat == to && !ends) {
                break;
            }
            events.push(Event {
                frame: frame(base + ev.beat).min(n - 1) as u32,
                kind: ev.kind,
            });
        }
        let (a, b) = (frame(base + at), frame(base + to));
        if b > a {
            mix_audio_constant(
                &slot.clips,
                &mut left[a..b],
                &mut right[a..b],
                (at, to),
                &local,
            );
        }
        done += to - at;
        at = if ends { 0.0 } else { to };
    }
}
