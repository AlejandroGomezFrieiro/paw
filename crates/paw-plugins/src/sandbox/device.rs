//! The DAW's side: the audio thread's stand-in for a hosted plugin.

use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use paw_engine::device::{Device, Io, Rest};
use paw_engine::{Event, MAX_PAIRS, ProcessCtx};
use paw_types::EventKind;
use super::*;
use super::shm::*;

// --- the DAW's side: the audio thread -------------------------------------------

/// What the stand-in's two halves share.
pub(super) struct Link {
    pub(super) shm: Shm,
    /// The helper has ended, or was ended for not answering.
    pub(super) dead: AtomicBool,
    /// Blocks the helper did not answer in time.
    pub(super) late: AtomicU32,
    /// The sound time of those blocks, in nanoseconds: a stall is measured
    /// in it too, as the engine can play blocks faster than the wall clock
    /// (the stepped backend of the tests).
    pub(super) late_ns: AtomicU64,
    /// Blocks it did answer.
    pub(super) answered: AtomicU32,
    /// The plugin was given a state or a call: it is run in the next block
    /// even when it said it was at rest, as some plugins take a state on
    /// only in their next block.
    pub(super) wake: AtomicBool,
}

/// The device the engine runs: it hands each block to the helper.
pub(super) struct RemoteDevice {
    pub(super) link: Arc<Link>,
    pub(super) instrument: bool,
    /// The number of the last block asked for.
    pub(super) seq: u32,
    /// That block has not been answered yet.
    pub(super) outstanding: bool,
    /// The right to the shared block's parts, in this process.
    pub(super) turn: Turn,
    /// Parameter moves for the next block.
    pub(super) moves: Vec<ParamMove>,
    /// Messages for the next block, as the shared memory carries them.
    pub(super) messages: Vec<u8>,
    /// Events of blocks the helper was too late to take, for the next
    /// block it takes. Never longer than [`EVENTS`] (see [`Pending`]).
    pub(super) pending: Pending,
    pub(super) told_priority: bool,
    /// The plugin said it was at rest after the last block.
    pub(super) rest: Rest,
    /// The longest a render waits for one block: a device that is never
    /// in this process (a script) is ended as soon as live, a plugin is
    /// given [`OFFLINE_LIMIT`], and one of a kind that a test made hang
    /// the deadline of the test ([`KindTest`]).
    pub(super) offline_limit: Duration,
}

impl RemoteDevice {
    /// What is heard when the helper has no answer: nothing from an
    /// instrument, the input untouched from an effect.
    fn without(&self, io: &mut Io) {
        if self.instrument {
            io.left.fill(0.0);
            io.right.fill(0.0);
        }
    }

    /// A helper that has said why it stopped is ending, or has ended.
    fn helper_stopped(&self) -> bool {
        self.link.dead.load(Ordering::Relaxed)
            || self.link.shm.header().reason_len.load(Ordering::Acquire) > 0
    }

    /// The helper has answered the last block asked for. One that is
    /// still on an earlier block is not given another until it has caught
    /// up: this block counts as late, and its events are kept for the
    /// next block it takes.
    fn caught_up(&mut self, io: &Io) -> bool {
        if !self.outstanding {
            return true;
        }
        let link = &*self.link;
        if link.shm.header().done.load(Ordering::Acquire) != self.seq {
            link.late.fetch_add(1, Ordering::Relaxed);
            self.pending.keep_all(io.events.as_slice(), true);
            return false;
        }
        self.outstanding = false;
        link.answered.fetch_add(1, Ordering::Relaxed);
        true
    }

    /// Once, tell the helper the scheduling of the audio thread, for its
    /// own audio thread to take.
    fn tell_priority(&mut self) {
        if self.told_priority {
            return;
        }
        self.told_priority = true;
        let header = self.link.shm.header();
        let scheduling = paw_engine::priority::current();
        header
            .priority
            .store(scheduling.priority as u32, Ordering::Relaxed);
        header.policy.store(scheduling.policy as u32, Ordering::Relaxed);
    }

    /// Put the block's context, input, events, parameter moves and
    /// messages in the shared memory. Events kept from blocks the helper
    /// did not take go first, then this block's own.
    fn write_block(&mut self, ctx: &ProcessCtx, io: &Io, frames: usize) {
        if !self.pending.is_empty() {
            self.pending.keep_all(io.events.as_slice(), false);
        }
        let events = if self.pending.is_empty() {
            io.events.as_slice()
        } else {
            self.pending.events.as_slice()
        };
        let count = events.len().min(EVENTS);
        let block = self.link.shm.block(&mut self.turn);
        let head = &mut *block.context;
        head.frames = frames as u32;
        head.sample_rate = ctx.sample_rate;
        head.tempo = ctx.tempo;
        head.position = ctx.position;
        head.seconds = ctx.seconds;
        head.bar_start = ctx.bar_start;
        head.bar = ctx.bar;
        head.sig_num = ctx.sig_num;
        head.sig_den = ctx.sig_den;
        head.playing = ctx.playing as u32;
        head.events_in = count as u32;
        head.params_in = self.moves.len() as u32;
        head.messages_in = self.messages.len() as u32;
        head.keyed = io.sidechain.is_some() as u32;
        head.outs = io
            .outputs
            .iter()
            .take(MAX_PAIRS - 1)
            .enumerate()
            .filter(|(_, out)| out.is_some())
            .fold(0, |bits, (pair, _)| bits | 1 << pair);
        block.left[..frames].copy_from_slice(&io.left[..frames]);
        block.right[..frames].copy_from_slice(&io.right[..frames]);
        if let Some([l, r]) = io.sidechain {
            let [key_l, key_r] = block.key;
            key_l[..frames].copy_from_slice(&l[..frames]);
            key_r[..frames].copy_from_slice(&r[..frames]);
        }
        block.events[..count].copy_from_slice(&events[..count]);
        self.pending.events.clear();
        block.params[..self.moves.len()].copy_from_slice(&self.moves);
        self.moves.clear();
        block.messages[..self.messages.len()].copy_from_slice(&self.messages);
        self.messages.clear();
    }

    /// Ask the helper for the next block, and wake it.
    fn ask(&mut self) {
        let header = self.link.shm.header();
        self.seq = self.seq.wrapping_add(1);
        header.request.store(self.seq, Ordering::Release);
        futex_wake(&header.request);
    }

    /// The longest to wait for the block. A render waits for as long as
    /// the plugin takes; live, a block that is not there in time is given
    /// up on.
    fn limit(&self, offline: bool, ctx: &ProcessCtx, frames: usize) -> Duration {
        if offline {
            self.offline_limit
        } else {
            let block = Duration::from_secs_f64(frames as f64 / ctx.sample_rate.max(1.0) as f64);
            block + block / 2 + Duration::from_millis(2)
        }
    }

    /// Wait for the helper's answer, for at most the [limit](Self::limit);
    /// false if the block was given up on.
    fn wait_for_answer(&mut self, ctx: &ProcessCtx, frames: usize) -> bool {
        let link = &*self.link;
        let header = link.shm.header();
        let offline = header.offline.load(Ordering::Relaxed) != 0;
        let limit = self.limit(offline, ctx, frames);
        let started = Instant::now();
        let mut spins = 0u32;
        loop {
            if header.done.load(Ordering::Acquire) == self.seq {
                break;
            }
            let waited = started.elapsed();
            let stopped = header.reason_len.load(Ordering::Acquire) > 0;
            if waited >= limit || link.dead.load(Ordering::Relaxed) || stopped {
                self.give_up(offline);
                return false;
            }
            // Most blocks are back within a few dozen microseconds: look
            // again at once for a moment before going to sleep.
            if spins < 2000 {
                spins += 1;
                std::hint::spin_loop();
            } else {
                let seen = header.done.load(Ordering::Acquire);
                if seen != self.seq {
                    futex_wait(
                        &header.done,
                        seen,
                        (limit - waited).min(Duration::from_millis(50)),
                    );
                }
            }
        }
        link.answered.fetch_add(1, Ordering::Relaxed);
        true
    }

    /// Add the sound time of a block that was late to [`Link::late_ns`].
    fn count_late_time(&self, ctx: &ProcessCtx, frames: usize) {
        let ns = frames as f64 * 1e9 / f64::from(ctx.sample_rate.max(1.0));
        self.link.late_ns.fetch_add(ns as u64, Ordering::Relaxed);
    }

    /// The block was not back in time: it stays outstanding, and the
    /// helper gets no other until it has answered it.
    fn give_up(&mut self, offline: bool) {
        self.outstanding = true;
        self.link.late.fetch_add(1, Ordering::Relaxed);
        if offline {
            // A render does not wait that long twice.
            self.link.dead.store(true, Ordering::Relaxed);
        }
    }

    /// Take the plugin's sound, its rest and its events from the answered
    /// block.
    fn read_block(&mut self, io: &mut Io, frames: usize) {
        let mut block = self.link.shm.block(&mut self.turn);
        io.left[..frames].copy_from_slice(&block.left[..frames]);
        io.right[..frames].copy_from_slice(&block.right[..frames]);
        for (pair, out) in io.outputs.iter_mut().take(MAX_PAIRS - 1).enumerate() {
            if let Some([l, r]) = out {
                l[..frames].copy_from_slice(&block.out(pair, 0)[..frames]);
                r[..frames].copy_from_slice(&block.out(pair, 1)[..frames]);
            }
        }
        self.rest.end(block.context.resting != 0);
        let out = (block.context.events_out as usize).min(EVENTS);
        io.events.clear();
        for event in &block.events[..out] {
            io.events.push(*event);
        }
    }
}

/// The events of blocks that a late helper did not take, kept for the
/// first block it takes, at its first frame and in their order: a note-on
/// given up with its block would never sound, and a note-off would leave
/// its note hanging. The list holds at most [`EVENTS`], which it has room
/// for from the start, so the audio thread never allocates. When it is
/// full a note-off still goes in, in place of the last event that is not
/// one; what is left out is counted with the MIDI events dropped.
pub(super) struct Pending {
    events: Vec<Event>,
}

impl Pending {
    pub(super) fn new() -> Self {
        Self {
            events: Vec::with_capacity(EVENTS),
        }
    }

    fn is_empty(&self) -> bool {
        self.events.is_empty()
    }

    /// Keep `event` at `frame`; false if an event was left out: it, or
    /// the one it took the place of.
    fn keep(&mut self, frame: u32, event: &Event) -> bool {
        let event = Event { frame, ..*event };
        if self.events.len() < EVENTS {
            self.events.push(event);
            return true;
        }
        let ends = |kind: &EventKind| matches!(kind, EventKind::NoteOff { .. } | EventKind::AllNotesOff);
        if !ends(&event.kind) {
            return false;
        }
        match self.events.iter().rposition(|e| !ends(&e.kind)) {
            Some(at) => {
                self.events.remove(at);
                self.events.push(event);
                // The one it took the place of is left out instead.
                false
            }
            None => false,
        }
    }

    /// Keep each of a block's events, at the first frame of a later block
    /// (`at_start`) or at its own.
    fn keep_all(&mut self, events: &[Event], at_start: bool) {
        for event in events {
            if !self.keep(if at_start { 0 } else { event.frame }, event) {
                paw_engine::event::count_dropped();
            }
        }
    }
}

impl Device for RemoteDevice {
    /// As the plugin said after its last block, unless a parameter has
    /// moved since or events wait for it.
    fn resting(&self) -> bool {
        self.rest.resting()
            && self.moves.is_empty()
            && self.pending.is_empty()
            && !self.link.wake.load(Ordering::Relaxed)
    }

    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        self.rest.begin(io, self.link.wake.swap(false, Ordering::Relaxed));
        if self.helper_stopped() {
            self.pending.events.clear();
            return self.without(io);
        }
        let frames = io.left.len().min(self.link.shm.max_block);
        if !self.caught_up(io) {
            self.count_late_time(ctx, frames);
            return self.without(io);
        }
        self.tell_priority();
        self.write_block(ctx, io, frames);
        self.ask();
        if !self.wait_for_answer(ctx, frames) {
            self.count_late_time(ctx, frames);
            return self.without(io);
        }
        self.read_block(io, frames);
    }

    fn message(&mut self, frame: u32, data: &[u8]) -> bool {
        if self.messages.len() + 8 + data.len() > MESSAGES.min(self.messages.capacity()) {
            return false;
        }
        self.messages.extend_from_slice(&frame.to_le_bytes());
        self.messages.extend_from_slice(&(data.len() as u32).to_le_bytes());
        self.messages.extend_from_slice(data);
        true
    }

    fn set_param(&mut self, index: u32, value: f32) {
        // The last word on a parameter within a block is the one that counts.
        if let Some(known) = self.moves.iter_mut().find(|m| m.index == index) {
            known.value = value;
        } else if self.moves.len() < PARAMS {
            self.moves.push(ParamMove { index, value });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_full_list_of_kept_events_still_takes_note_offs() {
        let on = |key| Event { frame: 9, kind: EventKind::NoteOn { key, vel: 1.0, ch: 0, attr: Default::default() } };
        let off = |key| Event { frame: 9, kind: EventKind::NoteOff { key, ch: 0 } };
        let mut pending = Pending::new();
        let full: Vec<Event> = (0..EVENTS).map(|i| if i == 0 { off(1) } else { on(2) }).collect();
        pending.keep_all(&full, true);
        assert!(!pending.keep(0, &on(3)), "a note-on is left out");
        assert!(!pending.keep(0, &off(2)), "a note-off goes in, in place of a note-on");
        let kept = &pending.events;
        assert_eq!(kept.len(), EVENTS);
        assert_eq!(kept[0], Event { frame: 0, ..off(1) }, "at the block's first frame");
        assert_eq!(kept[EVENTS - 1], Event { frame: 0, ..off(2) });
        let ons = kept.iter().filter(|e| **e == Event { frame: 0, ..on(2) }).count();
        assert_eq!(ons, EVENTS - 2, "the last note-on made room");
    }
}

