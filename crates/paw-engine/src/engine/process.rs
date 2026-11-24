//! One callback: cutting it into blocks, running the graph, and routing the parts.

use std::sync::atomic::{AtomicU64, Ordering::Relaxed};

use paw_types::TempoMap;

use crate::device::ProcessCtx;
use crate::midi_out::MidiOut;
use crate::record::PUNCH_EPS;
use crate::slot::PartSlot;

use super::click::{CLICK_FRAMES, Count};
use super::clock::Clock;
use super::device_rt::DeviceRt;
use super::guarded::Guarded;
use super::msg::Garbage;
use super::schedule::{SchedEntry, Schedule};
use super::part::{KeyRt, PartRt};
use super::work::{Block, Work, fader};
use super::{Engine, MAX_BLOCK, METER_FALL_SECONDS};

/// One block of a callback: where it starts, how many frames it has, and
/// where it ends, on the timeline.
struct Cut {
    start: f64,
    n: usize,
    end: f64,
    /// The block ends at the loop's end: the next starts at its start.
    wrap: bool,
}

impl Cut {
    /// End the block `frames` into it, if that is inside it: something
    /// happens on that frame, and the next block starts with it.
    fn end_on(&mut self, frames: usize) {
        if frames > 0 && frames < self.n {
            self.n = frames;
            self.wrap = false;
        }
    }
}

impl Engine {
    /// Render the next `left.len()` frames with no input. `left` and `right`
    /// must be the same length.
    pub fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.process_input(&[], 0, left, right);
    }

    /// Render the next `left.len()` frames, with `input` holding as many
    /// frames of `channels` interleaved input channels.
    ///
    /// The frames are cut into blocks, each ending where something has to
    /// happen on its frame (see [`cut_block`](Self::cut_block)), and each
    /// block is run through the graph by [`segment`](Self::segment).
    pub fn process_input(
        &mut self,
        input: &[f32],
        channels: usize,
        left: &mut [f32],
        right: &mut [f32],
    ) {
        let began = std::time::Instant::now();
        let total = left.len().min(right.len());
        let woken = self.begin_callback(total);
        if self.rests(woken) {
            self.rest_callback(input, channels, &mut left[..total], &mut right[..total]);
        } else {
            self.run_blocks(input, channels, &mut left[..total], &mut right[..total]);
        }
        self.publish_transport();
        self.play_preview(&mut left[..total], &mut right[..total]);
        self.feed_monitor(&left[..total], &right[..total]);
        let ns = u64::try_from(began.elapsed().as_nanos()).unwrap_or(u64::MAX);
        self.shared.blocks.record(ns, total);
        self.shared.processed.fetch_add(1, Relaxed);
    }

    /// Cut the frames of a callback into blocks, and run each through the
    /// graph.
    fn run_blocks(&mut self, input: &[f32], channels: usize, left: &mut [f32], right: &mut [f32]) {
        let callback_ns = crate::midi_out::clock_ns();
        let total = left.len();
        let mut done = 0;
        while done < total {
            self.start_counted_song();
            let cut = self.cut_block(total - done);
            let n = cut.n;
            self.load_input(input, channels, done, n);
            self.capture(n, cut.start);
            self.stamp_midi_out(callback_ns, done);
            self.click_at = done;
            let counts = self.counts();
            let (out_l, out_r) = (&mut left[done..done + n], &mut right[done..done + n]);
            self.segment(out_l, out_r, cut.start, cut.end);
            self.note_quiet(counts, out_l, out_r);
            done += n;
            self.end_block(&cut);
        }
    }

    /// What a callback does before its first block: take the main
    /// thread's messages, and clear the click's own output. True if a
    /// message or a MIDI input event came, or a device woke the engine.
    fn begin_callback(&mut self, total: usize) -> bool {
        // `|`, not `||`: the messages are taken and the wake is cleared
        // whatever the other gives.
        let woken = self.take_messages() | self.waker.take();
        if let Some(pool) = &self.pool {
            // Fewer than it was given, if its workers were refused the
            // priority of this thread.
            self.shared.threads.store(pool.threads() as u32, Relaxed);
        }
        if self.click_output > 0 {
            let room = total.min(CLICK_FRAMES);
            self.click_buf[0][..room].fill(0.0);
            self.click_buf[1][..room].fill(0.0);
        }
        woken
    }

    /// A count-in that has run its course starts the song on this frame.
    fn start_counted_song(&mut self) {
        if let Some(count) = self.count.as_mut()
            && !count.started
            && count.elapsed >= count.frames
        {
            count.started = true;
            self.playing = true;
            self.chase = true;
            self.reapply = true;
            self.restate = true;
        }
    }

    /// The next block, of at most `left` frames, from the play position.
    ///
    /// While playing, a block ends early on the frame where something has
    /// to happen: the loop's end, a launch, a punch in or out, a state
    /// lane's point. Each is one [`Cut::end_on`].
    fn cut_block(&mut self, left: usize) -> Cut {
        let mut n = left.min(MAX_BLOCK);
        if let Some(count) = self.count.as_ref().filter(|c| !c.started) {
            n = n.min((count.frames - count.elapsed) as usize);
        }
        let start = self.head.beat();
        let mut cut = Cut {
            start,
            n,
            end: start,
            wrap: false,
        };
        let launch_at = if self.launching && self.playing {
            self.next_launch(start)
        } else {
            None
        };
        let Some(map) = self.map.as_deref().filter(|_| self.playing) else {
            return cut;
        };
        let clock = Clock::new(map, &self.head, self.sample_rate);
        if self.loop_enabled && start < self.loop_end {
            let to_loop_end = clock.frames_to(self.loop_end);
            if to_loop_end <= cut.n {
                cut.n = to_loop_end.max(1);
                cut.wrap = true;
            }
        }
        // A launch happens on its frame.
        if let Some(beat) = launch_at {
            cut.end_on(clock.frames_on(beat));
        }
        // A punched take starts and stops capturing on the frame.
        if let Some((from, to)) = self.take.as_ref().and_then(|t| t.punch) {
            for edge in [from, to] {
                if edge - start > PUNCH_EPS {
                    cut.end_on(clock.frames_on(edge).max(1));
                }
            }
        }
        // A state changes on its point's frame.
        if self.has_states
            && let Some(beat) = self.next_state_point(start)
        {
            cut.end_on(clock.frames_on(beat));
        }
        cut.end = if cut.wrap {
            self.loop_end
        } else {
            clock.beat_after(cut.n)
        };
        cut
    }

    /// When the block that starts `done` frames into this callback is
    /// heard, for the MIDI sent with it.
    fn stamp_midi_out(&mut self, callback_ns: u64, done: usize) {
        if self.midi_out.is_some() {
            let sr = self.sample_rate;
            // The block is heard after the plugins' delay and the
            // output's, and the MIDI sent with it goes as late.
            let late = self.schedule.as_ref().map_or(0, |s| s.latency) as f64 / sr
                + self.shared.output_latency() as f64;
            self.heard_ns = callback_ns + ((done as f64 / sr + late) * 1e9) as u64;
        }
    }

    /// After a block: the count-in counts it, a take notes the loop's
    /// wrap, and the play position moves on.
    fn end_block(&mut self, cut: &Cut) {
        if let Some(count) = self.count.as_mut() {
            count.elapsed += cut.n as u64;
            if count.started && count.next >= count.clicks {
                self.count = None;
            }
        }
        let wrap = cut.wrap;
        if wrap && let Some(take) = self.take.as_deref_mut().filter(|_| self.playing) {
            // A take goes round with the loop: where it did is kept, so
            // that each time round can be told from the others.
            take.pass += 1;
            let _ = take.wraps.push(take.frames);
        }
        if self.playing {
            if wrap {
                self.head.put(self.loop_start);
            } else {
                self.head.advance(cut.n, cut.end);
            }
            self.flush_notes |= wrap;
            self.chase |= wrap;
            if wrap {
                self.requantize(self.loop_start);
            }
        }
    }

    /// Tell the main thread where the transport is, after a callback.
    fn publish_transport(&self) {
        self.shared.position.store(self.head.beat(), Relaxed);
        self.shared.playing.store(self.playing, Relaxed);
        self.shared
            .counting
            .store(self.count.as_ref().map_or(0, Count::left), Relaxed);
        self.shared.seeks.store(self.seeks, Relaxed);
    }

    /// Hand what was played to the listener, if there is one.
    fn feed_monitor(&mut self, left: &[f32], right: &[f32]) {
        if let Some(monitor) = self.monitor.as_deref_mut() {
            // What does not fit is dropped: the listener has fallen behind.
            let frames = left.len().min(monitor.slots() / 2);
            if let Ok(chunk) = monitor.write_chunk_uninit(frames * 2) {
                let samples = left[..frames]
                    .iter()
                    .zip(&right[..frames])
                    .flat_map(|(l, r)| [*l, *r]);
                chunk.fill_from_iter(samples);
            }
        }
    }

    /// Add the sound file being heard on its own, and the one fading out
    /// before it, to the output.
    pub(super) fn play_preview(&mut self, left: &mut [f32], right: &mut [f32]) {
        if let Some(leaving) = self.preview_leaving.as_deref_mut()
            && !leaving.mix(left, right, true)
            && let Some(gone) = self.preview_leaving.take()
        {
            self.discard(Garbage::Preview(gone));
        }
        let Some(preview) = self.preview.as_deref_mut() else {
            self.shared.preview_id.store(0, Relaxed);
            return;
        };
        let more = preview.mix(left, right, false);
        self.shared.preview_seconds.store(preview.seconds(), Relaxed);
        self.shared
            .preview_id
            .store(if more { preview.id } else { 0 }, Relaxed);
        if !more && let Some(gone) = self.preview.take() {
            self.discard(Garbage::Preview(gone));
        }
    }

    /// Run the whole graph for one block covering beats `start..end`.
    pub(super) fn segment(&mut self, out_l: &mut [f32], out_r: &mut [f32], start: f64, end: f64) {
        let n = out_l.len();
        let flush = std::mem::take(&mut self.flush_notes);
        let Some(map) = self.map.take() else {
            return;
        };
        let block = self.block(&map, n, start, end, flush);
        out_l.fill(0.0);
        out_r.fill(0.0);

        let Some(mut schedule) = self.schedule.take() else {
            self.map = Some(map);
            return;
        };
        self.clear_buffers(&mut schedule, n, flush);
        self.run_groups(&mut schedule, &block, out_l, out_r);
        if block.ctx.playing {
            schedule.hold_peak();
        }
        // The click belongs with what is heard, which is this far behind.
        let behind = schedule.latency as f64 / self.sample_rate;
        self.schedule = Some(schedule);
        self.sound_clicks(&block, behind, out_l, out_r);
        self.map = Some(map);
    }

    /// What every part of the block `start..end` shares. Uses up the
    /// engine's wishes to chase, reapply and restate, while playing.
    fn block<'m>(
        &mut self,
        map: &'m TempoMap,
        n: usize,
        start: f64,
        end: f64,
        flush: bool,
    ) -> Block<'m> {
        let playing = self.playing;
        let sr = self.sample_rate;
        let (sig_num, sig_den) = map.signature(start);
        let bar = map.bar_of(start);
        Block {
            ctx: ProcessCtx {
                sample_rate: sr as f32,
                tempo: map.tempo(start),
                sig_num,
                sig_den,
                playing,
                position: start,
                seconds: map.seconds(start),
                bar,
                bar_start: map.bar_start(bar),
                quality: self.quality,
            },
            n,
            start,
            end,
            map,
            clock: Clock::new(map, &self.head, sr),
            flush,
            chase: playing && std::mem::take(&mut self.chase),
            reapply: playing && std::mem::take(&mut self.reapply),
            restate: playing && std::mem::take(&mut self.restate),
            sleep: self.sleep,
            meter_fall: (-(n as f32) / (sr as f32 * METER_FALL_SECONDS)).exp(),
            capturing: playing && self.take.as_ref().is_some_and(|take| take.captures_at(start)),
        }
    }

    /// Silence the buffers the block's parts are sent into, and on a
    /// flush, what their delays still hold.
    fn clear_buffers(&mut self, schedule: &mut Schedule, n: usize, flush: bool) {
        for entry in schedule.entries.iter_mut() {
            if let Some(part) = self.part_mut(entry.slot) {
                part.buf[0][..n].fill(0.0);
                part.buf[1][..n].fill(0.0);
            }
            if flush {
                // What was on its way when playback stopped or moved is not
                // part of what comes next.
                entry.delay.clear();
                entry.sends.iter_mut().for_each(|send| send.delay.clear());
                entry.keys.iter_mut().for_each(|key| key.delay.clear());
                entry.outs.iter_mut().for_each(|out| out.delay.clear());
            }
            for key in &entry.keys {
                if let Some(buf) = self
                    .device_mut(key.device)
                    .and_then(|d| d.key.as_deref_mut())
                {
                    buf[0][..n].fill(0.0);
                    buf[1][..n].fill(0.0);
                }
            }
            // A device that does not run this block (bypassed, failed)
            // leaves its further pairs silent.
            for out in &entry.outs {
                if let Some(pair) = self
                    .device_mut(out.device)
                    .and_then(|d| d.outs.as_deref_mut())
                    .and_then(|outs| outs.get_mut(out.pair)?.as_mut())
                {
                    pair[0][..n].fill(0.0);
                    pair[1][..n].fill(0.0);
                }
            }
        }
    }

    /// Make and route the parts of the schedule, group by group.
    ///
    /// The parts of a group do not feed each other: each makes its own
    /// sound, on whichever thread takes it. What they send on is then
    /// added up here, in the order of the entries, so the sums are the same
    /// however many threads ran.
    fn run_groups(
        &mut self,
        schedule: &mut Schedule,
        block: &Block,
        out_l: &mut [f32],
        out_r: &mut [f32],
    ) {
        // Live, a block that one thread does in a quarter of the time it
        // has is done on one: the other threads are not woken at all.
        let budget = (block.n as f64 / self.sample_rate * 1e9) as u64;
        let held = if block.ctx.playing { schedule.peak } else { 0 };
        let share = self.offline || schedule.cost().max(held) >= budget / 4;
        let mut first = 0;
        let mut group = 0;
        while first < schedule.entries.len() {
            let last = schedule.group_end(first);
            let spent = AtomicU64::new(0);
            let shared_out = share
                && schedule.worth_sharing(group, first, last)
                && last - first > 1
                && self.pool.as_deref().is_some_and(|pool| pool.threads() > 1);
            let threads = if shared_out {
                let more = schedule.worth_sharing_after(group, last);
                let entries = &mut schedule.entries[first..last];
                self.run_shared(entries, block, &spent, more, out_l, out_r)
            } else {
                let entries = &mut schedule.entries[first..last];
                self.run_alone(entries, block, &spent, out_l, out_r);
                1
            };
            schedule.note_cost(group, spent.load(Relaxed), threads > 1);
            first = last;
            group += 1;
        }
        if let Some(pool) = self.pool.as_deref().filter(|_| !self.offline) {
            pool.idle();
        }
    }

    /// Make a group's parts on the pool's threads, then route them in the
    /// order of the entries. `more` tells whether a later group of the
    /// block is shared out too. Gives how many threads took part.
    fn run_shared(
        &mut self,
        entries: &mut [SchedEntry],
        block: &Block,
        spent: &AtomicU64,
        more: bool,
        out_l: &mut [f32],
        out_r: &mut [f32],
    ) -> usize {
        let Some(pool) = self.pool.as_deref_mut() else {
            self.run_alone(entries, block, spent, out_l, out_r);
            return 1;
        };
        let work = Work {
            block,
            entries,
            parts: &self.parts,
            devices: &self.devices,
            inputs: &self.inputs[..self.input_count],
            shared: &self.shared,
            spent,
        };
        pool.run(entries.len(), &|index| work.part(index));
        self.shared.shared_groups.fetch_add(1, Relaxed);
        // No more sharing in this block: the workers need not look for
        // any. A render goes on to the next block at once, where the
        // workers are wanted again.
        if !more && !self.offline {
            pool.idle();
        }
        let threads = pool.threads().min(entries.len());
        for entry in entries.iter_mut() {
            self.route(entry, block, out_l, out_r);
        }
        threads
    }

    /// Make a group's parts one by one on this thread. Alone, a part is
    /// sent on while its block is still at hand.
    fn run_alone(
        &mut self,
        entries: &mut [SchedEntry],
        block: &Block,
        spent: &AtomicU64,
        out_l: &mut [f32],
        out_r: &mut [f32],
    ) {
        for entry in entries.iter_mut() {
            Work {
                block,
                entries: std::slice::from_ref(entry),
                parts: &self.parts,
                devices: &self.devices,
                inputs: &self.inputs[..self.input_count],
                shared: &self.shared,
                spent,
            }
            .part(0);
            self.route(entry, block, out_l, out_r);
        }
    }

    /// Send a processed part's block on: to its output and its sends, or
    /// out of the engine for the master.
    pub(super) fn route(
        &mut self,
        entry: &mut SchedEntry,
        block: &Block,
        out_l: &mut [f32],
        out_r: &mut [f32],
    ) {
        let n = block.n;
        let Some(mut part) = self
            .parts
            .get_mut(entry.slot.index())
            .and_then(|t| t.get_mut().take())
        else {
            return;
        };
        let t = &mut *part;
        self.send_midi_out(t);
        if entry.taps_pre() {
            self.route_pre_fader(entry, t, block);
        }
        if entry.slot == PartSlot::MASTER {
            out_l.copy_from_slice(&t.buf[0][..n]);
            out_r.copy_from_slice(&t.buf[1][..n]);
        } else {
            self.route_post_fader(entry, t, n);
            self.route_outs(entry, n);
        }
        *self.parts[entry.slot.index()].get_mut() = Some(part);
    }

    /// What the part played goes out of its MIDI output port, as late as
    /// its block is heard.
    fn send_midi_out(&mut self, t: &mut PartRt) {
        if t.midi_out == 0 {
            return;
        }
        let Some(out) = self.midi_out.as_deref_mut() else {
            return;
        };
        let ns_per_frame = 1e9 / self.sample_rate;
        let channel = t.midi_out_channel.checked_sub(1);
        for ev in t.sent.drain(..) {
            let message = MidiOut {
                at: self.heard_ns + (ev.frame as f64 * ns_per_frame) as u64,
                port: t.midi_out,
                form: t.midi_out_form,
                kind: crate::midi_out::on_channel(ev.kind, channel),
            };
            if out.push(message).is_err() {
                crate::event::count_dropped();
            }
        }
    }

    /// Take the sends and side-chains from before the fader, then apply
    /// the fader, which was left for now so that they could be taken.
    fn route_pre_fader(&mut self, entry: &mut SchedEntry, t: &mut PartRt, block: &Block) {
        let n = block.n;
        // Sends from before the fader ignore it and the pan, but not the
        // mute.
        let pre = if t.mute || t.quiet { 0.0 } else { 1.0 };
        let pre_from = if t.started { t.applied_pre } else { pre };
        t.applied_pre = pre;
        for send in entry.sends.iter_mut().filter(|send| send.pre) {
            if let Some(dst) = self
                .parts
                .get_mut(send.target.index())
                .and_then(|t| t.get_mut().as_deref_mut())
            {
                let src = [&t.buf[0][..n], &t.buf[1][..n]];
                let [l, r] = &mut dst.buf;
                send.delay.mix(
                    src,
                    [&mut l[..n], &mut r[..n]],
                    send.gain * pre_from,
                    send.gain * pre,
                );
            }
        }
        for key in entry.keys.iter_mut().filter(|key| key.pre) {
            key_into(&mut self.devices, key, [&t.buf[0][..n], &t.buf[1][..n]]);
        }
        fader(t, entry.slot, block, &self.shared);
    }

    /// Send the part's faded block to its output, its sends from after
    /// the fader, and the side-chains that listen there.
    fn route_post_fader(&mut self, entry: &mut SchedEntry, t: &mut PartRt, n: usize) {
        // A part silenced by another's solo is not heard, moving there
        // smoothly, but its side-chains are still taken from it.
        let heard = if t.quiet { 0.0 } else { 1.0 };
        let heard_from = std::mem::replace(&mut t.applied_heard, heard);
        let src = [&t.buf[0][..n], &t.buf[1][..n]];
        if let Some(dst) = self
            .parts
            .get_mut(entry.output.index())
            .and_then(|t| t.get_mut().as_deref_mut())
        {
            let [l, r] = &mut dst.buf;
            entry
                .delay
                .mix(src, [&mut l[..n], &mut r[..n]], heard_from, heard);
        }
        for send in entry.sends.iter_mut().filter(|send| !send.pre) {
            if let Some(dst) = self
                .parts
                .get_mut(send.target.index())
                .and_then(|t| t.get_mut().as_deref_mut())
            {
                let [l, r] = &mut dst.buf;
                send.delay.mix(
                    src,
                    [&mut l[..n], &mut r[..n]],
                    send.gain * heard_from,
                    send.gain * heard,
                );
            }
        }
        for key in entry.keys.iter_mut().filter(|key| !key.pre) {
            key_into(&mut self.devices, key, src);
        }
    }

    /// Send the further output pairs of the part's devices where they go.
    fn route_outs(&mut self, entry: &mut SchedEntry, n: usize) {
        for out in entry.outs.iter_mut() {
            let (Some(pair), Some(dst)) = (
                self.devices
                    .get_mut(out.device.index())
                    .and_then(|d| d.get_mut().as_mut())
                    .and_then(|d| d.outs.as_deref())
                    .and_then(|outs| outs.get(out.pair)?.as_ref()),
                self.parts
                    .get_mut(out.target.index())
                    .and_then(|t| t.get_mut().as_deref_mut()),
            ) else {
                continue;
            };
            let [l, r] = &mut dst.buf;
            out.delay.mix(
                [&pair[0][..n], &pair[1][..n]],
                [&mut l[..n], &mut r[..n]],
                1.0,
                1.0,
            );
        }
    }
}

/// Put a block of a part into the side-chain of a device that listens to it.
pub(super) fn key_into(
    devices: &mut [Guarded<Option<DeviceRt>>],
    key: &mut KeyRt,
    src: [&[f32]; 2],
) {
    let n = src[0].len();
    if let Some([l, r]) = devices
        .get_mut(key.device.index())
        .and_then(|d| d.get_mut().as_mut())
        .and_then(|d| d.key.as_deref_mut())
    {
        key.delay.mix(src, [&mut l[..n], &mut r[..n]], 1.0, 1.0);
    }
}
