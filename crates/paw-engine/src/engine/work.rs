//! Making one track's block, on whichever thread takes it.

use std::sync::atomic::{AtomicU64, Ordering::Relaxed};

use crate::automation::{self, AutoTarget};
use crate::device::{Io, ProcessCtx};
use crate::event::{Ctl, Event, EventKind};
use crate::guard;
use crate::launch;
use crate::slot::{DeviceSlot, TrackSlot};
use crate::tempo::TempoMap;

use super::clock::Clock;
use super::device_rt::DeviceRt;
use super::guarded::{Claim, Guarded};
use super::regions::mix_audio;
use super::schedule::SchedEntry;
use super::shared::Shared;
use super::track::TrackRt;

/// What every track of a block shares.
pub(super) struct Block<'a> {
    pub(super) ctx: ProcessCtx,
    pub(super) n: usize,
    pub(super) start: f64,
    pub(super) end: f64,
    pub(super) map: &'a TempoMap,
    /// The frames of the block's beats: the frame each event and each
    /// frame of an audio region plays on.
    pub(super) clock: Clock<'a>,
    pub(super) flush: bool,
    pub(super) chase: bool,
    pub(super) reapply: bool,
    /// The song has just started to play: every state lane's state is
    /// given to its device again, whatever it was given before.
    pub(super) restate: bool,
    /// Devices at rest sleep through silent blocks.
    pub(super) sleep: bool,
    pub(super) meter_fall: f32,
    /// A take captures in this block: an armed track with an audio input
    /// plays its input only, not its clips, as a tape machine does.
    pub(super) capturing: bool,
}

/// One group of tracks to process, and what they read while it is done.
pub(super) struct Work<'a> {
    pub(super) block: &'a Block<'a>,
    pub(super) entries: &'a [SchedEntry],
    pub(super) tracks: &'a [Guarded<Option<Box<TrackRt>>>],
    pub(super) devices: &'a [Guarded<Option<DeviceRt>>],
    pub(super) inputs: &'a [Vec<f32>],
    pub(super) shared: &'a Shared,
    /// Nanoseconds the tracks of the group took, added up.
    pub(super) spent: &'a AtomicU64,
}

/// The program changes a block's state lanes give, each for one device: a
/// few, on the stack.
struct Programs {
    list: [(DeviceSlot, u8, Option<u16>); 4],
    count: usize,
}

impl Default for Programs {
    fn default() -> Self {
        Self {
            list: [(DeviceSlot::NONE, 0, None); 4],
            count: 0,
        }
    }
}

impl Programs {
    /// Keep a program change for a device, unless there is no room left.
    fn push(&mut self, change: (DeviceSlot, u8, Option<u16>)) {
        if self.count < self.list.len() {
            self.list[self.count] = change;
            self.count += 1;
        }
    }

    fn as_slice(&self) -> &[(DeviceSlot, u8, Option<u16>)] {
        &self.list[..self.count]
    }
}

impl Work<'_> {
    /// Make one track's block, and count the time it took.
    pub(super) fn track(&self, index: usize) {
        let began = std::time::Instant::now();
        self.make(index);
        self.spent
            .fetch_add(began.elapsed().as_nanos() as u64, Relaxed);
    }

    /// Make one track's block: its clips and input, through its devices and
    /// its fader. What has been sent into it by the tracks that feed it is
    /// already in its buffer. Touches nothing but the track and its devices.
    pub(super) fn make(&self, index: usize) {
        let entry = &self.entries[index];
        let Block { n, start, end, .. } = *self.block;
        let Some(mut claim) = self.tracks.get(entry.slot.index()).and_then(Guarded::claim) else {
            return;
        };
        let Some(t) = claim.as_deref_mut() else {
            return;
        };
        // Half a frame, in beats: how near a launch or a state lane's point
        // counts as on this block's first or last frame.
        let slack = if n > 0 {
            0.5 * (end - start) / n as f64
        } else {
            0.0
        };
        self.gather(t, slack);
        let mut programs = Programs::default();
        if self.block.ctx.playing {
            self.automate(t);
            self.give_states(t, slack, &mut programs);
        }
        self.run_chain(t, &programs);
        if let Some(state) = self.shared.launch.get(entry.slot.index()) {
            t.launcher.publish(state);
        }
        // A track with sends or side-chains from before its fader keeps
        // the fader for when they have been taken.
        if !entry.taps_pre() {
            fader(t, entry.slot, self.block, self.shared);
        }
    }

    /// What goes into the track's devices: the block's events (notes to
    /// stop and to chase, what was played live, the clips' or the playing
    /// slot's), the sound of its audio clips, and its input.
    fn gather(&self, t: &mut TrackRt, slack: f64) {
        let Block { ref ctx, n, start, .. } = *self.block;
        let playing = ctx.playing;
        let (flush, chase) = self.flush_and_chase(t, slack);
        t.events.clear();
        if flush {
            stop_notes(t);
        }
        if chase {
            // Start the notes that began before this position and are
            // still held at it: on the timeline, or in the slot that plays.
            if t.launcher.follows_arrangement() {
                launch::chase(&mut t.events, &t.clips, start);
            } else if let Some((slot, phase)) = t.launcher.slot() {
                launch::chase(&mut t.events, &slot.clips, phase);
            }
        }
        for kind in t.live.drain(..) {
            t.events.push(Event { frame: 0, kind });
        }
        // A track that records its audio input hears that input, not what
        // its clips already hold under the take.
        let replaced = self.block.capturing && t.armed && t.input_channels > 0;
        if playing && !t.launcher.follows_arrangement() {
            self.play_slot(t);
        } else if playing && !replaced {
            self.play_clips(t);
        }
        if t.monitor {
            add_input(self.inputs, t, n);
        }
        // What it plays goes to its MIDI output port as well, as it is
        // before its devices change it.
        if t.midi_out != 0 {
            t.sent.clear();
            let room = t.sent.capacity();
            t.sent
                .extend(t.events.as_slice().iter().take(room).copied());
        }
    }

    /// Whether the track stops its notes, and whether it chases those held
    /// at the block's start: for the whole engine, or for the track alone.
    fn flush_and_chase(&self, t: &mut TrackRt, slack: f64) -> (bool, bool) {
        // A launch due now: what played stops, and what plays from here
        // starts with its held notes.
        if let Some(change) = t.launcher.commit(self.block.start, slack) {
            t.flush = true;
            t.chase |= change.chase;
        }
        // The track's own flags are used up here even when the whole
        // engine is flushing or chasing anyway; left set, they would
        // stop and restart the track's notes again one block later.
        let track_flush = std::mem::take(&mut t.flush);
        let flush = self.block.flush || track_flush;
        // Chasing waits for playback, as it does for the whole engine.
        let track_chase = self.block.ctx.playing && std::mem::take(&mut t.chase);
        let chase = self.block.chase || track_chase;
        (flush, chase)
    }

    /// A slot plays instead of the timeline, or nothing does.
    fn play_slot(&self, t: &mut TrackRt) {
        let Block {
            ref ctx,
            n,
            start,
            end,
            ..
        } = *self.block;
        if let Some((slot, phase)) = t.launcher.slot() {
            let [left, right] = &mut t.buf;
            launch::play(
                slot,
                phase,
                end - start,
                n,
                &mut t.events,
                &mut left[..n],
                &mut right[..n],
                ctx,
            );
        }
        t.launcher.advance(end - start);
    }

    /// The timeline plays: the events of the track's clips in the block,
    /// each on its frame, and the sound of its audio clips.
    fn play_clips(&self, t: &mut TrackRt) {
        let Block {
            ref ctx,
            n,
            start,
            end,
            map,
            ref clock,
            ..
        } = *self.block;
        t.clips.find_sounding(start, end);
        let events = &mut t.events;
        t.clips.events(start, end, |ev| {
            // The block's beats and frames come from one clock, so an event
            // in its beats is on one of its frames; at the loop's end, the
            // last frame holds what is after it.
            events.push(Event {
                frame: clock.frame_in_block(ev.beat).min(n - 1) as u32,
                kind: ev.kind,
            });
        });
        let [left, right] = &mut t.buf;
        mix_audio(
            &t.clips,
            &mut left[..n],
            &mut right[..n],
            (start, end),
            map,
            clock,
            ctx,
        );
    }

    /// While playing, the automation lanes set the track's fader and pan
    /// and its devices' parameters, as they are at the block's start.
    fn automate(&self, t: &mut TrackRt) {
        let start = self.block.start;
        for lane in t.automation.lanes.iter_mut() {
            let Some(value) = automation::value_at(&lane.points, start) else {
                continue;
            };
            match lane.target {
                AutoTarget::Volume => t.gain = crate::db_to_gain(value),
                AutoTarget::Pan => t.pan = value as f32,
                AutoTarget::Param { device, index } => {
                    if self.block.reapply || value != lane.last {
                        if let Some(mut dev) = self.device(device)
                            && let Some(dev) = dev.as_mut()
                        {
                            dev.set_param(index, value as f32);
                        }
                        lane.last = value;
                    }
                }
            }
        }
    }

    /// While playing, the state lanes give their devices the state at the
    /// block's start; the program changes among them are kept in
    /// `programs`, for [`run_chain`](Self::run_chain) to hand each to its
    /// device only.
    ///
    /// Blocks end on the lanes' points, so a new state is given on the
    /// first frame of the block that starts at its point. A message for a
    /// point at this block's end is handed on its last frame: a plugin that
    /// finishes it after the block (an LV2 worker, at once in a render)
    /// then plays it from the point's frame.
    fn give_states(&self, t: &mut TrackRt, slack: f64, programs: &mut Programs) {
        let Block { n, start, end, .. } = *self.block;
        for lane in t.automation.states.iter_mut() {
            let Some(index) = automation::state_at(&lane.points, start + slack) else {
                continue;
            };
            if self.block.restate {
                lane.last = None;
                lane.sent_early = None;
            }
            if lane.last != Some(index) {
                let early = lane.sent_early.take() == Some(index);
                if let Some(change) = lane.changes.get(index as usize)
                    && let Some(mut dev) = self.device(lane.device)
                    && let Some(dev) = dev.as_mut()
                {
                    for &(param, value) in change.params.iter() {
                        dev.set_param(param, value);
                    }
                    if let Some(message) = change.message.as_deref()
                        && !early
                    {
                        dev.device.message(0, message);
                    }
                    if let Some((program, bank)) = change.program {
                        programs.push((lane.device, program, bank));
                    }
                }
                lane.last = Some(index);
            }
            if n > 0
                && let Some(next) = automation::next_point(&lane.points, start + slack)
                && (next - end).abs() <= slack
                && let Some(after) = automation::state_at(&lane.points, next + slack)
                && after != index
                && let Some(message) = lane
                    .changes
                    .get(after as usize)
                    .and_then(|c| c.message.as_deref())
                && let Some(mut dev) = self.device(lane.device)
                && let Some(dev) = dev.as_mut()
                && dev.device.message(n as u32 - 1, message)
            {
                lane.sent_early = Some(after);
            }
        }
    }

    /// Run the block through the track's devices in order, letting those
    /// at rest sleep through silence, and passing over or silencing those
    /// that fail.
    fn run_chain(&self, t: &mut TrackRt, programs: &Programs) {
        let Block { ref ctx, n, map, .. } = *self.block;
        // A track with a time of its own (a subproject's) gives its devices
        // its bars: a copy of the block's context, on the stack.
        let local = t.local.as_deref().map(|l| l.context(ctx, map));
        let ctx = local.as_ref().unwrap_or(ctx);
        let [left, right] = &mut t.buf;
        // Whether the block is silent with no events, as far as it is known:
        // looked at when a device at rest asks, and true still after a
        // device that slept through it.
        let mut quiet = None;
        let (mut runs, mut sleeps) = (0, 0);
        for &slot in t.chain.iter() {
            if let Some(mut dev) = self.device(slot)
                && let Some(dev) = dev.as_mut()
                && !dev.failed
            {
                // A state lane's program change, for this device only:
                // the devices before it in the chain do not hear it.
                for &(to, program, bank) in programs.as_slice() {
                    if to == slot {
                        let kind = EventKind::Program {
                            program,
                            bank,
                            ch: 0,
                        };
                        t.events.push_front(Event { frame: 0, kind });
                        quiet = None;
                    }
                }
                if self.block.sleep && dev.rests() {
                    let keyed = dev.key.as_deref().is_some_and(|[l, r]| {
                        !crate::device::silent(&l[..n]) || !crate::device::silent(&r[..n])
                    });
                    let silent = !keyed
                        && *quiet.get_or_insert_with(|| {
                            t.events.is_empty()
                                && crate::device::silent(&left[..n])
                                && crate::device::silent(&right[..n])
                        });
                    if silent {
                        dev.skip(n);
                        sleeps += 1;
                        continue;
                    }
                }
                quiet = None;
                runs += 1;
                if let Some(ran) = self.shared.device_ran.get(slot.index()) {
                    // One writer per slot: a load and a store, no locked add.
                    ran.store(ran.load(Relaxed) + 1, Relaxed);
                }
                // Taken out of the slot while the device runs on it.
                let key = dev.key.take();
                let mut outs = dev.outs.take();
                let mut io = Io {
                    left: &mut left[..n],
                    right: &mut right[..n],
                    events: &mut t.events,
                    sidechain: key.as_deref().map(|[l, r]| [&l[..n], &r[..n]]),
                    outputs: match outs.as_deref_mut() {
                        Some(outs) => outs.as_mut_slice(),
                        None => &mut [],
                    },
                };
                // A device that panics is passed over from then on (an
                // instrument falls silent, an effect lets its input through),
                // and one that puts out NaN or infinity is silenced for the
                // block: neither reaches the fader, the meters or the master.
                // The host's wet/dry mix and bypass fade go around it.
                let ok = dev.process(ctx, &mut io);
                dev.key = key;
                dev.outs = outs;
                if !ok {
                    dev.failed = true;
                    left[..n].fill(0.0);
                    right[..n].fill(0.0);
                    self.shared.set_fault(slot, guard::Fault::PANICKED);
                } else if !guard::finite(&left[..n]) || !guard::finite(&right[..n]) {
                    left[..n].fill(0.0);
                    right[..n].fill(0.0);
                    if !dev.flagged {
                        dev.flagged = true;
                        self.shared.set_fault(slot, guard::Fault::NOT_FINITE);
                    }
                }
            }
        }
        if runs > 0 {
            self.shared.device_runs.fetch_add(runs, Relaxed);
        }
        if sleeps > 0 {
            self.shared.device_sleeps.fetch_add(sleeps, Relaxed);
        }
    }

    pub(super) fn device(&self, slot: DeviceSlot) -> Option<Claim<'_, Option<DeviceRt>>> {
        self.devices.get(slot.index())?.claim()
    }
}

/// Apply a track's fader, pan and mute to its block, moving smoothly from
/// where the last block left them, and measure what comes out.
pub(super) fn fader(t: &mut TrackRt, slot: TrackSlot, block: &Block, shared: &Shared) {
    let n = block.n;
    let target = t.target_gains();
    if !t.started {
        // Nothing has sounded yet, so there is nothing to ramp from.
        t.applied = target;
    }
    let [left, right] = &mut t.buf;
    for (ch, buf) in [&mut left[..n], &mut right[..n]].into_iter().enumerate() {
        let from = t.applied[ch];
        let step = (target[ch] - from) / n as f32;
        if step.abs() < 1e-9 {
            for s in buf.iter_mut() {
                *s *= from;
            }
        } else {
            for (i, s) in buf.iter_mut().enumerate() {
                *s *= from + step * (i + 1) as f32;
            }
        }
        let peak = peak_of(buf);
        t.applied[ch] = target[ch];
        // A track silenced by a solo shows nothing, as it is heard.
        let peak = if t.quiet { 0.0 } else { peak };
        t.peak[ch] = peak.max(t.peak[ch] * block.meter_fall);
        if let Some(meter) = shared.meters.get(slot.index()) {
            meter[ch].store(t.peak[ch], Relaxed);
        }
    }
    t.started = true;
}

/// The largest magnitude in a block, NaN left out. Eight lanes, compared
/// rather than `f32::max`ed, so that it vectorises.
#[inline]
pub(super) fn peak_of(buf: &[f32]) -> f32 {
    let mut lanes = [0f32; 8];
    let mut chunks = buf.chunks_exact(8);
    for chunk in &mut chunks {
        for i in 0..8 {
            let v = chunk[i].abs();
            if v > lanes[i] {
                lanes[i] = v;
            }
        }
    }
    let rest = chunks.remainder().iter().map(|x| x.abs());
    lanes
        .into_iter()
        .chain(rest)
        .fold(0.0, |peak, v| if v > peak { v } else { peak })
}

/// Add a track's input into its buffer, ahead of its devices. A mono input
/// goes to both sides.
pub(super) fn add_input(inputs: &[Vec<f32>], t: &mut TrackRt, n: usize) {
    let Some(first) = inputs.get(t.input_first).filter(|_| t.input_channels > 0) else {
        return;
    };
    let second = match t.input_channels {
        2 => inputs.get(t.input_first + 1).unwrap_or(first),
        _ => first,
    };
    let [left, right] = &mut t.buf;
    for (d, s) in left[..n].iter_mut().zip(&first[..n]) {
        *d += s;
    }
    for (d, s) in right[..n].iter_mut().zip(&second[..n]) {
        *d += s;
    }
}

/// Stop what the track plays: its notes, and a pedal held down or a wheel
/// left bent when playback stopped, which would stay that way for whatever
/// is played next.
fn stop_notes(t: &mut TrackRt) {
    t.events.push(Event {
        frame: 0,
        kind: EventKind::AllNotesOff,
    });
    for ctl in [Ctl::Cc(64), Ctl::Bend] {
        let kind = EventKind::Control {
            ctl,
            value: 0.0,
            ch: 0,
        };
        t.events.push(Event { frame: 0, kind });
    }
}
