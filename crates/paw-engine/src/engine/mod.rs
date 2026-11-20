//! The audio-thread side of the engine and the handle the main thread drives it with.
//!
//! Ownership rule: anything the audio thread uses is built on the main thread,
//! sent over as a `Box`, and sent back through the garbage queue when replaced.
//! The audio thread itself never allocates or frees.

mod apply;
mod click;
mod device_rt;
mod guarded;
mod handle;
mod msg;
mod process;
mod regions;
mod schedule;
mod shared;
mod stats;
mod track;
mod work;

use std::sync::Arc;
use std::sync::atomic::Ordering::Relaxed;

use rtrb::{Consumer, Producer, PushError, RingBuffer};

use crate::automation;
use crate::event::{Ctl, EventKind};
use crate::midi_out::MidiOut;
use crate::pool::Pool;
use crate::preview::Preview;
use crate::record::{MidiCapture, Take};
use crate::slot::{DeviceSlot, TrackSlot};
use crate::tempo::TempoMap;

pub use device_rt::{KeyBuf, OutBufs, key_buf, out_bufs};
pub use handle::EngineHandle;
pub use msg::Msg;
pub use schedule::{SchedEntry, Schedule};
pub use shared::Shared;
pub use stats::{BLOCK_BUCKETS, BLOCK_STATS_FLOOR_NS, BlockStats, BlockSummary};
pub use track::{Delay, KeyRt, MAX_DELAY, OutRt, SendRt, TrackRt};

pub(crate) use regions::mix_audio_constant;

use click::{CLICK_FRAMES, Click, Count};
use device_rt::DeviceRt;
use guarded::Guarded;
use msg::Garbage;

/// Largest block handed to devices. Longer callbacks are split.
pub const MAX_BLOCK: usize = 1024;
pub const MAX_TRACKS: usize = 1024;
pub const MAX_DEVICES: usize = 8192;
/// Input channels beyond this many are ignored.
pub const MAX_INPUTS: usize = 32;

const MSG_CAPACITY: usize = 16384;
const GARBAGE_CAPACITY: usize = 16384;
const MIDI_IN_CAPACITY: usize = 4096;
const METER_FALL_SECONDS: f32 = 0.3;

pub struct Engine {
    sample_rate: f64,
    tracks: Vec<Guarded<Option<Box<TrackRt>>>>,
    devices: Vec<Guarded<Option<DeviceRt>>>,
    pool: Option<Box<Pool>>,
    schedule: Option<Box<Schedule>>,
    rx: Consumer<Msg>,
    garbage: Producer<Garbage>,
    shared: Arc<Shared>,
    /// Taken out while a block is processed, so that the tracks can read
    /// it while the engine is borrowed; always there between blocks.
    map: Option<Box<TempoMap>>,
    playing: bool,
    position: f64,
    loop_enabled: bool,
    loop_start: f64,
    loop_end: f64,
    metronome: bool,
    /// The metronome's gain, accent and output (see [`Msg::SetClick`]).
    click_gain: f32,
    click_accent: bool,
    click_output: u16,
    /// The clicks of the frames of a call, when they go to an output of
    /// their own; and where in them the block under way starts.
    click_buf: [Vec<f32>; 2],
    click_at: usize,
    flush_notes: bool,
    /// Playback is about to start somewhere new: notes already under way at
    /// that position need to be started.
    chase: bool,
    /// Automated parameters must be sent again even if their value has not
    /// moved, because something else may have set them since.
    reapply: bool,
    /// The song starts to play: state lanes give their states again.
    restate: bool,
    /// Some track has a state lane: blocks end on its points.
    has_states: bool,
    /// The devices hold their lanes' states already (see [`Msg::StatesHeld`]).
    states_held: bool,
    seeks: u32,
    click: Click,
    /// The current block of input, one buffer per channel.
    inputs: Vec<Vec<f32>>,
    input_count: usize,
    take: Option<Box<Take>>,
    midi_rx: Consumer<(u32, EventKind)>,
    /// A count-in under way, or whose last clicks are still to be heard.
    count: Option<Count>,
    /// Where tracks' MIDI output goes, when something sends it on.
    midi_out: Option<Box<Producer<MidiOut>>>,
    /// Where a copy of the output goes, while someone listens elsewhere.
    monitor: Option<Box<Producer<f32>>>,
    /// When the block being made is heard, on [`midi_out::clock_ns`].
    ///
    /// [`midi_out::clock_ns`]: crate::midi_out::clock_ns
    heard_ns: u64,
    /// Some track has a launch queued.
    launching: bool,
    /// The sound file being heard on its own, and the one before it while
    /// it fades out.
    preview: Option<Box<Preview>>,
    preview_leaving: Option<Box<Preview>>,
    /// Devices at rest sleep through silent blocks (see [`Msg::SetSleep`]).
    sleep: bool,
    /// Rendering to a file, as fast as it goes: work is shared between
    /// threads whenever that is faster. Live, only when one thread could
    /// come near the time a block has.
    offline: bool,
}

impl Engine {
    pub fn new(sample_rate: f64) -> (Engine, EngineHandle) {
        let (tx, rx) = RingBuffer::new(MSG_CAPACITY);
        let (garbage_tx, garbage_rx) = RingBuffer::new(GARBAGE_CAPACITY);
        let (midi_tx, midi_rx) = RingBuffer::new(MIDI_IN_CAPACITY);
        let shared = Arc::new(Shared::new());
        let mut tracks: Vec<Guarded<Option<Box<TrackRt>>>> =
            (0..MAX_TRACKS).map(|_| Guarded::new(None)).collect();
        *tracks[TrackSlot::MASTER.index()].get_mut() = Some(TrackRt::new());
        let schedule = Schedule::new(vec![SchedEntry::new(TrackSlot::MASTER, TrackSlot::NONE)], 0);
        let engine = Engine {
            sample_rate,
            tracks,
            devices: (0..MAX_DEVICES).map(|_| Guarded::new(None)).collect(),
            pool: None,
            schedule: Some(Box::new(schedule)),
            rx,
            garbage: garbage_tx,
            shared: shared.clone(),
            map: Some(Box::new(TempoMap::default())),
            playing: false,
            position: 0.0,
            loop_enabled: false,
            loop_start: 0.0,
            loop_end: 4.0,
            metronome: false,
            click_gain: 1.0,
            click_accent: true,
            click_output: 0,
            click_buf: [vec![0.0; CLICK_FRAMES], vec![0.0; CLICK_FRAMES]],
            click_at: 0,
            flush_notes: false,
            chase: false,
            reapply: false,
            restate: false,
            has_states: false,
            states_held: false,
            seeks: 0,
            click: Click::default(),
            inputs: (0..MAX_INPUTS).map(|_| vec![0.0; MAX_BLOCK]).collect(),
            input_count: 0,
            take: None,
            midi_rx,
            count: None,
            midi_out: None,
            monitor: None,
            heard_ns: 0,
            launching: false,
            preview: None,
            preview_leaving: None,
            sleep: true,
            offline: false,
        };
        (
            engine,
            EngineHandle {
                tx,
                garbage: garbage_rx,
                shared,
                sample_rate,
                midi_tx: Some(midi_tx),
            },
        )
    }

    pub fn sample_rate(&self) -> f64 {
        self.sample_rate
    }

    pub fn shared(&self) -> &Arc<Shared> {
        &self.shared
    }

    /// Process tracks on the threads of a pool as well as on the calling
    /// thread, or with `None` on the calling thread alone. For an engine not
    /// yet handed to an audio thread; one that has been takes [`Msg::SetPool`].
    pub fn set_pool(&mut self, pool: Option<Box<Pool>>) -> Option<Box<Pool>> {
        let threads = pool.as_ref().map_or(1, |pool| pool.threads());
        self.shared.threads.store(threads as u32, Relaxed);
        std::mem::replace(&mut self.pool, pool)
    }

    /// Whether devices at rest sleep through silent blocks, for an engine
    /// not yet handed to an audio thread; one that has been takes
    /// [`Msg::SetSleep`].
    pub fn set_sleep(&mut self, sleep: bool) {
        self.sleep = sleep;
    }

    /// Say that the engine renders to a file, as fast as it can, rather
    /// than live: then tracks are shared between threads whenever that is
    /// faster, where live they are only when one thread would take a good
    /// part of the time a block has, and the other threads' time is saved.
    pub fn set_offline(&mut self, offline: bool) {
        self.offline = offline;
    }

    fn discard(&mut self, garbage: Garbage) {
        if let Err(PushError::Full(garbage)) = self.garbage.push(garbage) {
            // Freeing here would block the audio thread, so leak instead.
            std::mem::forget(garbage);
            self.shared.leaked.fetch_add(1, Relaxed);
        }
    }

    /// Apply every queued message. Called at the start of each [`process`](Self::process).
    pub fn pump(&mut self) {
        while let Ok(msg) = self.rx.pop() {
            self.apply(msg);
        }
        while let Ok((port, kind)) = self.midi_rx.pop() {
            self.midi_in(port, kind);
        }
    }

    /// Move every queued launch to the first boundary from `beat`, where
    /// the song has jumped to.
    fn requantize(&mut self, beat: f64) {
        if !self.launching {
            return;
        }
        let Some(map) = self.map.take() else {
            return;
        };
        for t in self.tracks.iter_mut() {
            if let Some(t) = t.get_mut().as_deref_mut() {
                t.launcher.requantize(&map, beat);
            }
        }
        self.map = Some(map);
    }

    /// The first beat after `start` on which a queued launch happens, to
    /// end the block there. Notes whether any launch is still queued.
    fn next_launch(&mut self, start: f64) -> Option<f64> {
        let schedule = self.schedule.take()?;
        let (mut next, mut any) = (None::<f64>, false);
        for entry in &schedule.entries {
            if let Some(at) = self
                .tracks
                .get_mut(entry.slot.index())
                .and_then(|t| t.get_mut().as_deref())
                .and_then(|t| t.launcher.queued_at())
            {
                any = true;
                if at > start {
                    next = Some(next.map_or(at, |n: f64| n.min(at)));
                }
            }
        }
        self.schedule = Some(schedule);
        self.launching = any;
        next
    }

    /// Deliver a note from MIDI input to every track that takes it, and
    /// capture it for the take when recording.
    fn midi_in(&mut self, port: u32, kind: EventKind) {
        let Some(schedule) = self.schedule.take() else {
            return;
        };
        let position = self.position;
        let mut capture = self
            .take
            .as_deref_mut()
            .filter(|take| self.playing && take.captures_at(position));
        for entry in &schedule.entries {
            let Some(t) = self
                .tracks
                .get_mut(entry.slot.index())
                .and_then(|t| t.get_mut().as_deref_mut())
            else {
                continue;
            };
            if !t.hears(port, &kind) {
                continue;
            }
            match kind {
                EventKind::NoteOn { key, .. } => t.held |= 1 << (key & 127),
                EventKind::NoteOff { key, .. } => t.held &= !(1 << (key & 127)),
                EventKind::AllNotesOff => t.held = 0,
                _ => {}
            }
            if t.live.len() < t.live.capacity() {
                t.live.push(kind);
            }
            // A track that is only monitored plays what comes in, but
            // records nothing.
            if let Some(take) = capture.as_deref_mut().filter(|_| t.armed) {
                take.shared.begin(self.position);
                let _ = take.midi.push(MidiCapture {
                    slot: entry.slot,
                    beat: self.position,
                    kind,
                    pass: take.pass,
                });
            }
        }
        self.schedule = Some(schedule);
    }

    /// Copy `n` frames of input, starting at frame `at`, out of an interleaved buffer.
    ///
    /// Each channel's level is metered here, whatever takes it, so that a
    /// signal can be seen arriving before a track is armed or monitored.
    fn load_input(&mut self, input: &[f32], channels: usize, at: usize, n: usize) {
        self.input_count = channels.min(MAX_INPUTS);
        let fall = (-(n as f32) / (self.sample_rate as f32 * METER_FALL_SECONDS)).exp();
        for (ch, buf) in self.inputs[..self.input_count].iter_mut().enumerate() {
            let mut peak = 0.0f32;
            for (i, s) in buf[..n].iter_mut().enumerate() {
                *s = input.get((at + i) * channels + ch).copied().unwrap_or(0.0);
                peak = peak.max(s.abs());
            }
            let meter = &self.shared.input_meters[ch];
            let held = f32::from_bits(meter.load(Relaxed)) * fall;
            meter.store(peak.max(held).to_bits(), Relaxed);
        }
        // Channels the device no longer has fall silent.
        for meter in &self.shared.input_meters[self.input_count..] {
            if meter.load(Relaxed) != 0 {
                meter.store(0, Relaxed);
            }
        }
    }

    /// Copy this block's input into the take, for every track it records.
    fn capture(&mut self, n: usize, start: f64) {
        let Self {
            take,
            inputs,
            input_count,
            playing,
            ..
        } = self;
        let Some(take) = take
            .as_deref_mut()
            .filter(|take| *playing && take.captures_at(start))
        else {
            return;
        };
        take.shared.begin(start);
        take.frames += n as u64;
        for cap in &mut take.audio {
            let Ok(mut chunk) = cap.ring.write_chunk(n * cap.channels) else {
                take.shared.add_dropped(n as u64);
                continue;
            };
            let (a, b) = chunk.as_mut_slices();
            for (i, s) in a.iter_mut().chain(b.iter_mut()).enumerate() {
                let ch = cap.first + i % cap.channels;
                *s = if ch < *input_count {
                    inputs[ch][i / cap.channels]
                } else {
                    0.0
                };
            }
            chunk.commit_all();
        }
    }

    fn track_mut(&mut self, slot: TrackSlot) -> Option<&mut TrackRt> {
        self.tracks.get_mut(slot.index())?.get_mut().as_deref_mut()
    }

    fn device_mut(&mut self, slot: DeviceSlot) -> Option<&mut DeviceRt> {
        self.devices.get_mut(slot.index())?.get_mut().as_mut()
    }

    /// Look again whether any track has a state lane (after its
    /// automation or the tracks changed): a message, not a block, does this.
    fn note_states(&mut self) {
        self.has_states = self.tracks.iter_mut().any(|t| {
            t.get_mut()
                .as_deref()
                .is_some_and(|t| t.automation.states.iter().any(|s| !s.points.is_empty()))
        });
    }

    /// The first point of a state lane after `beat`, on any track: a block
    /// ends there, so that the state changes on the point's own frame.
    fn next_state_point(&self, beat: f64) -> Option<f64> {
        let mut next: Option<f64> = None;
        for t in self.tracks.iter() {
            let Some(claim) = t.claim() else { continue };
            let Some(t) = claim.as_deref() else { continue };
            for lane in &t.automation.states {
                if let Some(at) = automation::next_point(&lane.points, beat) {
                    next = Some(next.map_or(at, |n| n.min(at)));
                }
            }
        }
        next
    }

    /// The metronome's clicks of the last call to [`process_input`], when
    /// they go to an output pair of their own: the first channel of the
    /// pair (from 0), and the left and right frames.
    ///
    /// [`process_input`]: Self::process_input
    pub fn click_output(&self, frames: usize) -> Option<(usize, &[f32], &[f32])> {
        (self.click_output > 0 && frames <= CLICK_FRAMES).then(|| {
            (
                self.click_output as usize - 1,
                &self.click_buf[0][..frames],
                &self.click_buf[1][..frames],
            )
        })
    }
}

/// Where a controller is kept while chasing: the 128 control changes, then
/// the pitch wheel and pressure. Registered and assignable controllers are
/// settings more than performance, and are not chased.
pub(crate) fn ctl_index(ctl: Ctl) -> Option<usize> {
    match ctl {
        Ctl::Cc(number) => Some((number & 127) as usize),
        Ctl::Bend => Some(128),
        Ctl::Pressure => Some(129),
        Ctl::Registered(..) | Ctl::Assignable(..) => None,
    }
}

pub(crate) fn ctl_at(index: usize) -> Ctl {
    match index {
        128 => Ctl::Bend,
        129 => Ctl::Pressure,
        number => Ctl::Cc(number as u8),
    }
}
