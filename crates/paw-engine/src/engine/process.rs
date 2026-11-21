//! One callback: cutting it into blocks, running the graph, and routing the tracks.

use std::sync::atomic::{AtomicU64, Ordering::Relaxed};

use crate::device::ProcessCtx;
use crate::midi_out::MidiOut;
use crate::record::PUNCH_EPS;
use crate::slot::TrackSlot;

use super::click::{CLICK_FRAMES, Count, MAX_CLICKS};
use super::device_rt::DeviceRt;
use super::guarded::Guarded;
use super::msg::Garbage;
use super::schedule::SchedEntry;
use super::track::KeyRt;
use super::work::{Block, Work, fader};
use super::{Engine, MAX_BLOCK, METER_FALL_SECONDS};

impl Engine {
    /// Render the next `left.len()` frames with no input. `left` and `right`
    /// must be the same length.
    pub fn process(&mut self, left: &mut [f32], right: &mut [f32]) {
        self.process_input(&[], 0, left, right);
    }

    /// Render the next `left.len()` frames, with `input` holding as many
    /// frames of `channels` interleaved input channels.
    pub fn process_input(
        &mut self,
        input: &[f32],
        channels: usize,
        left: &mut [f32],
        right: &mut [f32],
    ) {
        let began = std::time::Instant::now();
        let callback_ns = crate::midi_out::clock_ns();
        self.pump();
        if let Some(pool) = &self.pool {
            // Fewer than it was given, if its workers were refused the
            // priority of this thread.
            self.shared.threads.store(pool.threads() as u32, Relaxed);
        }
        let total = left.len().min(right.len());
        let sr = self.sample_rate;
        if self.click_output > 0 {
            let room = total.min(CLICK_FRAMES);
            self.click_buf[0][..room].fill(0.0);
            self.click_buf[1][..room].fill(0.0);
        }
        let mut done = 0;
        while done < total {
            // A count-in that has run its course starts the song on this frame.
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
            let mut n = (total - done).min(MAX_BLOCK);
            if let Some(count) = self.count.as_ref().filter(|c| !c.started) {
                n = n.min((count.frames - count.elapsed) as usize);
            }
            let start = self.position;
            let mut end = start;
            let mut wrap = false;
            let launch_at = if self.launching && self.playing {
                self.next_launch(start)
            } else {
                None
            };
            if let Some(map) = self.map.as_deref().filter(|_| self.playing) {
                let t0 = map.seconds(start);
                // One tempo throughout: beats per frame, as plain arithmetic.
                let bpf = map.is_constant().then(|| map.first_tempo() / (60.0 * sr));
                let frames_to = |beat: f64| match bpf {
                    Some(bpf) => ((beat - start) / bpf).ceil() as usize,
                    None => ((map.seconds(beat) - t0) * sr).ceil() as usize,
                };
                if self.loop_enabled && start < self.loop_end {
                    let to_loop_end = frames_to(self.loop_end);
                    if to_loop_end <= n {
                        n = to_loop_end.max(1);
                        wrap = true;
                    }
                }
                // On the frame: a point a rounding error off a frame is on it.
                let frames_on = |beat: f64| {
                    let x = match bpf {
                        Some(bpf) => (beat - start) / bpf,
                        None => (map.seconds(beat) - t0) * sr,
                    };
                    if (x - x.round()).abs() < 1e-6 {
                        x.round() as usize
                    } else {
                        x.ceil() as usize
                    }
                };
                // A launch happens on its frame: the block ends there.
                if let Some(frames) = launch_at.map(frames_on)
                    && frames > 0
                    && frames < n
                {
                    n = frames;
                    wrap = false;
                }
                // A punched take starts and stops capturing on the frame:
                // the block ends where it punches in or out.
                if let Some((from, to)) = self.take.as_ref().and_then(|t| t.punch) {
                    for edge in [from, to] {
                        if edge - start > PUNCH_EPS {
                            let frames = frames_on(edge).max(1);
                            if frames < n {
                                n = frames;
                                wrap = false;
                            }
                        }
                    }
                }
                // A state changes on its point's frame: the block ends there.
                if self.has_states
                    && let Some(frames) = self.next_state_point(start).map(frames_on)
                    && frames > 0
                    && frames < n
                {
                    n = frames;
                    wrap = false;
                }
                end = match (wrap, bpf) {
                    (true, _) => self.loop_end,
                    (false, Some(bpf)) => start + n as f64 * bpf,
                    (false, None) => map.beat(t0 + n as f64 / sr),
                };
            }
            self.load_input(input, channels, done, n);
            self.capture(n, start);
            if self.midi_out.is_some() {
                // The block is heard after the plugins' delay and the
                // output's, and the MIDI sent with it goes as late.
                let late = self.schedule.as_ref().map_or(0, |s| s.latency) as f64 / sr
                    + self.shared.output_latency() as f64;
                self.heard_ns = callback_ns + ((done as f64 / sr + late) * 1e9) as u64;
            }
            self.click_at = done;
            self.segment(
                &mut left[done..done + n],
                &mut right[done..done + n],
                start,
                end,
            );
            done += n;
            if let Some(count) = self.count.as_mut() {
                count.elapsed += n as u64;
                if count.started && count.next >= count.clicks {
                    self.count = None;
                }
            }
            if wrap && let Some(take) = self.take.as_deref_mut().filter(|_| self.playing) {
                // A take goes round with the loop: where it did is kept, so
                // that each time round can be told from the others.
                take.pass += 1;
                let _ = take.wraps.push(take.frames);
            }
            if self.playing {
                self.position = if wrap { self.loop_start } else { end };
                self.flush_notes |= wrap;
                self.chase |= wrap;
                if wrap {
                    self.requantize(self.loop_start);
                }
            }
        }
        self.shared.position.store(self.position, Relaxed);
        self.shared.playing.store(self.playing, Relaxed);
        self.shared
            .counting
            .store(self.count.as_ref().map_or(0, Count::left), Relaxed);
        self.shared.seeks.store(self.seeks, Relaxed);
        self.play_preview(&mut left[..total], &mut right[..total]);
        if let Some(monitor) = self.monitor.as_deref_mut() {
            // What does not fit is dropped: the listener has fallen behind.
            let frames = total.min(monitor.slots() / 2);
            if let Ok(chunk) = monitor.write_chunk_uninit(frames * 2) {
                let samples = left[..frames]
                    .iter()
                    .zip(&right[..frames])
                    .flat_map(|(l, r)| [*l, *r]);
                chunk.fill_from_iter(samples);
            }
        }
        let ns = u64::try_from(began.elapsed().as_nanos()).unwrap_or(u64::MAX);
        self.shared.blocks.record(ns, total);
        self.shared.processed.fetch_add(1, Relaxed);
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
        let playing = self.playing;
        let flush = std::mem::take(&mut self.flush_notes);
        let Some(map) = self.map.take() else {
            return;
        };
        let seconds = map.seconds(start);
        let (sig_num, sig_den) = map.signature(start);
        let bar = map.bar_of(start);
        let block = Block {
            ctx: ProcessCtx {
                sample_rate: self.sample_rate as f32,
                tempo: map.tempo(start),
                sig_num,
                sig_den,
                playing,
                position: start,
                seconds,
                bar,
                bar_start: map.bar_start(bar),
            },
            n,
            start,
            end,
            map: &map,
            bpf: map
                .is_constant()
                .then(|| map.first_tempo() / (60.0 * self.sample_rate)),
            flush,
            chase: playing && std::mem::take(&mut self.chase),
            reapply: playing && std::mem::take(&mut self.reapply),
            restate: playing && std::mem::take(&mut self.restate),
            sleep: self.sleep,
            meter_fall: (-(n as f32) / (self.sample_rate as f32 * METER_FALL_SECONDS)).exp(),
        };
        out_l.fill(0.0);
        out_r.fill(0.0);

        let Some(mut schedule) = self.schedule.take() else {
            self.map = Some(map);
            return;
        };
        for entry in schedule.entries.iter_mut() {
            if let Some(track) = self.track_mut(entry.slot) {
                track.buf[0][..n].fill(0.0);
                track.buf[1][..n].fill(0.0);
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

        // Live, a block that one thread does in a quarter of the time it
        // has is done on one: the other threads are not woken at all.
        let total: u64 = schedule.costs.iter().map(|c| c.0).sum();
        let budget = (n as f64 / self.sample_rate * 1e9) as u64;
        let held = if playing { schedule.peak } else { 0 };
        let share = self.offline || total.max(held) >= budget / 4;
        let mut first = 0;
        let mut group = 0;
        while first < schedule.entries.len() {
            let last = schedule.group_end(first);
            let worth = share && schedule.worth_sharing(group, first, last);
            let spent = AtomicU64::new(0);
            // The tracks of a group do not feed each other: each makes its
            // own sound, on whichever thread takes it. What they send on is
            // then added up here, in the order of the entries, so the sums
            // are the same however many threads ran.
            let threads = match self.pool.as_deref_mut() {
                Some(pool) if last - first > 1 && pool.threads() > 1 && worth => {
                    let work = Work {
                        block: &block,
                        entries: &schedule.entries[first..last],
                        tracks: &self.tracks,
                        devices: &self.devices,
                        inputs: &self.inputs[..self.input_count],
                        shared: &self.shared,
                        spent: &spent,
                    };
                    pool.run(last - first, &|index| work.track(index));
                    self.shared.shared_groups.fetch_add(1, Relaxed);
                    // No more sharing in this block: the workers need not
                    // look for any.
                    let mut rest = last;
                    let mut more = false;
                    for later in group + 1..schedule.groups.len() {
                        let end = schedule.groups[later];
                        more |= share && schedule.worth_sharing(later, rest, end);
                        rest = end;
                    }
                    // A render goes on to the next block at once, where the
                    // workers are wanted again.
                    if !more && !self.offline {
                        pool.idle();
                    }
                    let threads = pool.threads().min(last - first);
                    for entry in schedule.entries[first..last].iter_mut() {
                        self.route(entry, &block, out_l, out_r);
                    }
                    threads
                }
                // Alone, a track is sent on while its block is still at hand.
                _ => {
                    for entry in schedule.entries[first..last].iter_mut() {
                        Work {
                            block: &block,
                            entries: std::slice::from_ref(entry),
                            tracks: &self.tracks,
                            devices: &self.devices,
                            inputs: &self.inputs[..self.input_count],
                            shared: &self.shared,
                            spent: &spent,
                        }
                        .track(0);
                        self.route(entry, &block, out_l, out_r);
                    }
                    1
                }
            };
            // The work of the tracks themselves, whichever threads did it,
            // without the waiting: smoothed, so that one block the thread
            // was held up in does not change how the next is done.
            if let Some(slot) = schedule.costs.get_mut(group) {
                *slot = ((slot.0 * 3 + spent.load(Relaxed)) / 4, threads > 1);
            }
            first = last;
            group += 1;
        }
        if let Some(pool) = self.pool.as_deref().filter(|_| !self.offline) {
            pool.idle();
        }
        if playing {
            // Falls by half in about 7000 blocks: a minute at 256 frames.
            let total: u64 = schedule.costs.iter().map(|c| c.0).sum();
            schedule.peak = total.max(schedule.peak - schedule.peak / 10_000);
        }
        // The click belongs with what is heard, which is this far behind.
        let behind = schedule.latency as f64 / self.sample_rate;
        self.schedule = Some(schedule);

        // Where clicks start in this block: the metronome's while playing,
        // and a count-in's whether or not the metronome is on.
        let mut starts = [(usize::MAX, false); MAX_CLICKS];
        let mut count = 0;
        if playing && self.metronome {
            let from = seconds - behind;
            let to = map.seconds(end) - behind;
            self.metronome_clicks(n, &map, from, to, &mut starts, &mut count);
        }
        if let Some(counting) = self.count.as_mut() {
            counting.clicks(n, &mut starts, &mut count);
            starts[..count].sort_unstable_by_key(|s| s.0);
        }
        if (playing && self.metronome) || self.count.is_some() {
            self.click(out_l, out_r, &starts[..count]);
        } else {
            self.click.env = 0.0;
        }
        self.map = Some(map);
    }

    /// Send a processed track's block on: to its output and its sends, or
    /// out of the engine for the master.
    pub(super) fn route(
        &mut self,
        entry: &mut SchedEntry,
        block: &Block,
        out_l: &mut [f32],
        out_r: &mut [f32],
    ) {
        let n = block.n;
        let Some(mut track) = self
            .tracks
            .get_mut(entry.slot.index())
            .and_then(|t| t.get_mut().take())
        else {
            return;
        };
        let t = &mut *track;
        if t.midi_out != 0
            && let Some(out) = self.midi_out.as_deref_mut()
        {
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
        if entry.taps_pre() {
            // Sends from before the fader ignore it and the pan, but not the
            // mute. The fader was left for now, so that they could be taken.
            let pre = if t.mute || t.quiet { 0.0 } else { 1.0 };
            let pre_from = if t.started { t.applied_pre } else { pre };
            t.applied_pre = pre;
            for send in entry.sends.iter_mut().filter(|send| send.pre) {
                if let Some(dst) = self
                    .tracks
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

        if entry.slot == TrackSlot::MASTER {
            out_l.copy_from_slice(&t.buf[0][..n]);
            out_r.copy_from_slice(&t.buf[1][..n]);
        } else {
            // A track silenced by another's solo is not heard, moving there
            // smoothly, but its side-chains are still taken from it.
            let heard = if t.quiet { 0.0 } else { 1.0 };
            let heard_from = std::mem::replace(&mut t.applied_heard, heard);
            let src = [&t.buf[0][..n], &t.buf[1][..n]];
            if let Some(dst) = self
                .tracks
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
                    .tracks
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
            for out in entry.outs.iter_mut() {
                let (Some(pair), Some(dst)) = (
                    self.devices
                        .get_mut(out.device.index())
                        .and_then(|d| d.get_mut().as_mut())
                        .and_then(|d| d.outs.as_deref())
                        .and_then(|outs| outs.get(out.pair)?.as_ref()),
                    self.tracks
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
        *self.tracks[entry.slot.index()].get_mut() = Some(track);
    }
}

/// Put a block of a track into the side-chain of a device that listens to it.
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
