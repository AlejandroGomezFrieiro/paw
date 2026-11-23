//! Running a processor's plan: the operations of its chain, in order, on
//! the slot's buffer and the plan's own (see [`crate::plan`]).

use std::sync::atomic::Ordering::Relaxed;

use crate::device::{Io, ProcessCtx};
use crate::event::{Event, EventBuf};
use paw_types::EventKind;
use crate::guard;
use crate::plan::{Buf, Ev, Filter, Gain, GraphPlan, Op, Part, Ring};
use crate::slot::DeviceSlot;

use super::MAX_BLOCK;
use super::part::PartRt;
use super::work::{Block, Programs, Work, peak_of};

/// One stereo buffer of a plan, as long as the block.
type Pair<'b> = [&'b mut [f32]; 2];

/// The buffers a plan runs on: the slot's own (buffer 0), and the plan's
/// work buffers after it.
struct Bufs<'a> {
    slot: &'a mut [Vec<f32>; 2],
    work: &'a mut [f32],
    n: usize,
}

const PAIR: usize = 2 * MAX_BLOCK;

fn pair(chunk: &mut [f32], n: usize) -> Pair<'_> {
    let (left, right) = chunk[..PAIR].split_at_mut(MAX_BLOCK);
    [&mut left[..n], &mut right[..n]]
}

impl Bufs<'_> {
    fn one(&mut self, buf: Buf) -> Pair<'_> {
        let n = self.n;
        match buf.index() {
            0 => {
                let [left, right] = &mut *self.slot;
                [&mut left[..n], &mut right[..n]]
            }
            k => pair(&mut self.work[(k - 1) * PAIR..], n),
        }
    }

    /// Two buffers at once, which the compiler made different.
    fn two(&mut self, a: Buf, b: Buf) -> (Pair<'_>, Pair<'_>) {
        let n = self.n;
        match (a.index(), b.index()) {
            (0, k) => {
                let [left, right] = &mut *self.slot;
                ([&mut left[..n], &mut right[..n]], pair(&mut self.work[(k - 1) * PAIR..], n))
            }
            (k, 0) => {
                let [left, right] = &mut *self.slot;
                (pair(&mut self.work[(k - 1) * PAIR..], n), [&mut left[..n], &mut right[..n]])
            }
            (i, j) if i < j => {
                let (low, high) = self.work.split_at_mut((j - 1) * PAIR);
                (pair(&mut low[(i - 1) * PAIR..], n), pair(high, n))
            }
            (i, j) => {
                let (low, high) = self.work.split_at_mut((i - 1) * PAIR);
                (pair(high, n), pair(&mut low[(j - 1) * PAIR..], n))
            }
        }
    }
}

/// The event list `ev`: the slot's own (0), or one of the plan's.
fn list<'e>(slot: &'e mut EventBuf, lists: &'e mut [EventBuf], ev: Ev) -> &'e mut EventBuf {
    match ev.index() {
        0 => slot,
        k => &mut lists[k - 1],
    }
}

/// What the devices of one run of a plan share.
struct Run<'p> {
    /// The program changes of the block's state lanes, each for one device.
    programs: &'p Programs,
    /// Whether the buffer and the events the devices run on are silent
    /// and empty, as far as it is known: looked at when a device at rest
    /// asks, and true still after a device that slept through it.
    quiet: Option<bool>,
    /// Blocks of devices run and slept through.
    runs: u64,
    sleeps: u64,
}

impl Work<'_> {
    /// Run the block through the processor's plan: its devices in order,
    /// letting those at rest sleep through silence and passing over or
    /// silencing those that fail; and its splits, branches and merges.
    pub(super) fn run_plan(&self, t: &mut PartRt, programs: &Programs) {
        let Block { ref ctx, n, map, meter_fall, .. } = *self.block;
        // A part with a time of its own (a subproject's) gives its devices
        // its bars: a copy of the block's context, on the stack.
        let local = t.local.as_deref().map(|l| l.context(ctx, map));
        let ctx = local.as_ref().unwrap_or(ctx);
        let PartRt { buf, events, plan, .. } = t;
        let GraphPlan { ops, arena, bufs, events: lists, crossovers, allpasses, gains, rings, meters, .. } =
            &mut **plan;
        let (work, lines) = arena.split_at_mut(*bufs * PAIR);
        let mut b = Bufs { slot: buf, work, n };
        let mut run = Run { programs, quiet: None, runs: 0, sleeps: 0 };
        for op in ops.iter() {
            match *op {
                Op::Run { device, buf, events: ev } => {
                    let list = list(events, lists, ev);
                    self.run_device(ctx, device, b.one(buf), list, &mut run);
                    continue;
                }
                Op::Clear { buf } => b.one(buf).into_iter().for_each(|ch| ch.fill(0.0)),
                Op::Copy { from, to } => {
                    let (from, to) = b.two(from, to);
                    from.into_iter().zip(to).for_each(|(f, t)| t.copy_from_slice(f));
                }
                Op::Events { from, to, filter } => copy_events(events, lists, from, to, filter),
                Op::Take { from, to, part } => take(b.two(from, to), part),
                Op::Band { rest, low, xover } => {
                    let (rest, low) = b.two(rest, low);
                    crossovers[xover as usize].split(rest, low);
                }
                Op::Allpass { buf, filter } => allpasses[filter as usize].run(b.one(buf)),
                Op::Delay { buf, ring } => delay(&mut rings[ring as usize], lines, b.one(buf)),
                Op::Merge { from, to, gain, part } => merge(b.two(from, to), &mut gains[gain as usize], part),
                Op::Out { wet, to, wet_gain, dry_gain } => {
                    let (wet, to) = b.two(wet, to);
                    let (w, d) = (gains[wet_gain as usize], gains[dry_gain as usize]);
                    out(wet, to, w, d);
                    gains[wet_gain as usize].applied = w.target;
                    gains[dry_gain as usize].applied = d.target;
                }
                Op::Meter { buf, meter } => {
                    let [left, right] = b.one(buf);
                    meters.store(meter, [peak_of(left), peak_of(right)], meter_fall);
                }
            }
            // The other operations change what the devices after them hear.
            run.quiet = None;
        }
        if run.runs > 0 {
            self.shared.device_runs.fetch_add(run.runs, Relaxed);
        }
        if run.sleeps > 0 {
            self.shared.device_sleeps.fetch_add(run.sleeps, Relaxed);
        }
    }

    /// Run one device on a buffer and its events, or let it sleep, and
    /// measure its peak and its time.
    fn run_device(
        &self,
        ctx: &ProcessCtx,
        slot: DeviceSlot,
        [left, right]: Pair<'_>,
        events: &mut EventBuf,
        run: &mut Run,
    ) {
        let n = left.len();
        let Some(mut dev) = self.device(slot) else { return };
        let Some(dev) = dev.as_mut().filter(|d| !d.failed) else { return };
        // A state lane's program change, for this device only: the devices
        // before it in the chain do not hear it.
        for &(to, program, bank) in run.programs.as_slice() {
            if to == slot {
                let kind = EventKind::Program { program, bank, ch: 0 };
                events.push_front(Event { frame: 0, kind });
                run.quiet = None;
            }
        }
        let fall = self.block.meter_fall;
        if self.block.sleep && dev.rests() {
            let keyed = dev
                .key
                .as_deref()
                .is_some_and(|[l, r]| !crate::device::silent(&l[..n]) || !crate::device::silent(&r[..n]));
            let silent = !keyed
                && *run.quiet.get_or_insert_with(|| {
                    events.is_empty() && crate::device::silent(left) && crate::device::silent(right)
                });
            if silent {
                dev.skip(n);
                run.sleeps += 1;
                if let Some(peak) = self.shared.device_peaks.get(slot.index()) {
                    peak.store(peak.load(Relaxed) * fall, Relaxed);
                }
                return;
            }
        }
        run.quiet = None;
        run.runs += 1;
        if let Some(ran) = self.shared.device_ran.get(slot.index()) {
            // One writer per slot: a load and a store, no locked add.
            ran.store(ran.load(Relaxed) + 1, Relaxed);
        }
        let began = std::time::Instant::now();
        // Taken out of the slot while the device runs on it.
        let key = dev.key.take();
        let mut outs = dev.outs.take();
        let mut io = Io {
            left: &mut *left,
            right: &mut *right,
            events,
            sidechain: key.as_deref().map(|[l, r]| [&l[..n], &r[..n]]),
            outputs: match outs.as_deref_mut() {
                Some(outs) => outs.as_mut_slice(),
                None => &mut [],
            },
        };
        // A device that panics is passed over from then on (an instrument
        // falls silent, an effect lets its input through), and one that
        // puts out NaN or infinity is silenced for the block: neither
        // reaches the fader, the meters or the master. The host's wet/dry
        // mix and bypass fade go around it.
        let ok = dev.process(ctx, &mut io);
        dev.key = key;
        dev.outs = outs;
        if !ok {
            dev.failed = true;
            left.fill(0.0);
            right.fill(0.0);
            self.shared.set_fault(slot, guard::Fault::PANICKED);
        } else if !guard::finite(left) || !guard::finite(right) {
            left.fill(0.0);
            right.fill(0.0);
            if !dev.flagged {
                dev.flagged = true;
                self.shared.set_fault(slot, guard::Fault::NOT_FINITE);
            }
        }
        let spent = u64::try_from(began.elapsed().as_nanos()).unwrap_or(u64::MAX);
        if let Some(ns) = self.shared.device_ns.get(slot.index()) {
            ns.store(ns.load(Relaxed).saturating_add(spent), Relaxed);
        }
        if let Some(peak) = self.shared.device_peaks.get(slot.index()) {
            let now = peak_of(left).max(peak_of(right));
            peak.store(now.max(peak.load(Relaxed) * fall), Relaxed);
        }
    }
}

/// Copy the event list `from` into `to`, with only the notes of `filter`.
/// A note-off goes to each branch of a velocity split: it has no
/// velocity, and a branch that has not the note lets it pass.
fn copy_events(slot: &mut EventBuf, lists: &mut [EventBuf], from: Ev, to: Ev, filter: Filter) {
    let (from, to) = match (from.index(), to.index()) {
        (0, k) => (&*slot, &mut lists[k - 1]),
        (i, j) if i < j => {
            let (low, high) = lists.split_at_mut(j - 1);
            (&low[i - 1], &mut high[0])
        }
        (i, j) => {
            let (low, high) = lists.split_at_mut(i - 1);
            (&high[0], &mut low[j - 1])
        }
    };
    to.clear();
    let within = |v: u8, (low, high): (u8, u8)| (low..=high).contains(&v);
    for event in from.as_slice() {
        let keep = match (filter, event.kind) {
            (Filter::All, _) => true,
            (Filter::Keys(low, high), EventKind::NoteOn { key, .. } | EventKind::NoteOff { key, .. })
            | (Filter::Keys(low, high), EventKind::NoteControl { key, .. }) => within(key, (low, high)),
            (Filter::Velocities(low, high), EventKind::NoteOn { vel, .. }) => {
                within((vel * 127.0).round().clamp(0.0, 127.0) as u8, (low, high))
            }
            _ => true,
        };
        if keep {
            to.push(*event);
        }
    }
}

/// The part of `from` that a branch takes, in both channels of `to`.
fn take(([left, right], [to_l, to_r]): (Pair<'_>, Pair<'_>), part: Part) {
    match part {
        Part::Stereo => {
            to_l.copy_from_slice(left);
            to_r.copy_from_slice(right);
        }
        Part::Left => {
            to_l.copy_from_slice(left);
            to_r.copy_from_slice(left);
        }
        Part::Right => {
            to_l.copy_from_slice(right);
            to_r.copy_from_slice(right);
        }
        Part::Mid | Part::Side => {
            let sign = if part == Part::Mid { 1.0 } else { -1.0 };
            for i in 0..left.len() {
                let v = 0.5 * (left[i] + sign * right[i]);
                to_l[i] = v;
                to_r[i] = v;
            }
        }
    }
}

/// Where a gain starts in a block, and how much it moves each frame: from
/// where the last block left it to its target.
fn ramp(gain: &Gain, ch: usize, n: usize) -> (f32, f32) {
    let from = gain.applied[ch];
    let step = (gain.target[ch] - from) / n.max(1) as f32;
    if step.abs() < 1e-9 { (from, 0.0) } else { (from, step) }
}

#[inline]
fn at((from, step): (f32, f32), i: usize) -> f32 {
    if step == 0.0 { from } else { from + step * (i + 1) as f32 }
}

/// Add a branch into the merge with its gains, as `part`.
fn merge(([left, right], [to_l, to_r]): (Pair<'_>, Pair<'_>), gain: &mut Gain, part: Part) {
    let n = left.len();
    let (gl, gr) = (ramp(gain, 0, n), ramp(gain, 1, n));
    match part {
        Part::Stereo if gl.1 == 0.0 && gr.1 == 0.0 => {
            // Constant gains: a plain sum, which vectorises.
            for (t, s) in to_l.iter_mut().zip(left.iter()) {
                *t += s * gl.0;
            }
            for (t, s) in to_r.iter_mut().zip(right.iter()) {
                *t += s * gr.0;
            }
        }
        _ => {
            for i in 0..n {
                let (l, r) = (left[i] * at(gl, i), right[i] * at(gr, i));
                match part {
                    Part::Stereo => {
                        to_l[i] += l;
                        to_r[i] += r;
                    }
                    Part::Mid => {
                        to_l[i] += 0.5 * (l + r);
                        to_r[i] += 0.5 * (l + r);
                    }
                    Part::Side => {
                        to_l[i] += 0.5 * (l + r);
                        to_r[i] -= 0.5 * (l + r);
                    }
                    Part::Left => to_l[i] += 0.5 * (l + r),
                    Part::Right => to_r[i] += 0.5 * (l + r),
                }
            }
        }
    }
    gain.applied = gain.target;
}

/// `to` (the dry signal) with the gain `dry`, plus `wet` with the gain
/// `wet`.
fn out(wet: Pair<'_>, to: Pair<'_>, wet_gain: Gain, dry_gain: Gain) {
    for (ch, (wet, to)) in wet.into_iter().zip(to).enumerate() {
        let n = wet.len();
        let (w, d) = (ramp(&wet_gain, ch, n), ramp(&dry_gain, ch, n));
        for (i, (t, s)) in to.iter_mut().zip(wet.iter()).enumerate() {
            *t = *t * at(d, i) + s * at(w, i);
        }
    }
}

/// Hold a buffer back by a delay line: what comes out is what went in
/// `ring.len` frames before.
fn delay(ring: &mut Ring, lines: &mut [f32], buf: Pair<'_>) {
    let len = ring.len;
    let mut end = ring.at;
    for (ch, buf) in buf.into_iter().enumerate() {
        let line = &mut lines[ring.start + ch * len..ring.start + (ch + 1) * len];
        let mut at = ring.at;
        for s in buf.iter_mut() {
            std::mem::swap(s, &mut line[at]);
            at += 1;
            if at == len {
                at = 0;
            }
        }
        end = at;
    }
    ring.at = end;
}
