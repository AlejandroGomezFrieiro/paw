//! The DAW's side: the audio thread's stand-in for a hosted plugin.

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use paw_engine::device::{Device, Io, Rest};
use paw_engine::{MAX_PAIRS, ProcessCtx};
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
    pub(super) told_priority: bool,
    /// The plugin said it was at rest after the last block.
    pub(super) rest: Rest,
    /// The longest a render waits for one block: a device that is never
    /// in this process (a script) is ended as soon as live, a plugin is
    /// given [`OFFLINE_LIMIT`].
    pub(super) offline_limit: Duration,
}

impl RemoteDevice {
    /// What is heard when the helper has no answer: nothing from an
    /// instrument, the input untouched from an effect.
    pub(super) fn without(&self, io: &mut Io) {
        if self.instrument {
            io.left.fill(0.0);
            io.right.fill(0.0);
        }
    }
}

impl Device for RemoteDevice {
    /// As the plugin said after its last block, unless a parameter has
    /// moved since.
    fn resting(&self) -> bool {
        self.rest.resting() && self.moves.is_empty() && !self.link.wake.load(Ordering::Relaxed)
    }

    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        let link = &*self.link;
        self.rest.begin(io, link.wake.swap(false, Ordering::Relaxed));
        let shm = &link.shm;
        let header = shm.header();
        // A helper that has said why it stopped is ending, or has ended.
        if link.dead.load(Ordering::Relaxed) || header.reason_len.load(Ordering::Acquire) > 0 {
            return self.without(io);
        }
        if self.outstanding {
            // The helper is still on an earlier block: it is not given
            // another until it has caught up.
            if header.done.load(Ordering::Acquire) != self.seq {
                link.late.fetch_add(1, Ordering::Relaxed);
                return self.without(io);
            }
            self.outstanding = false;
            link.answered.fetch_add(1, Ordering::Relaxed);
        }
        let frames = io.left.len().min(shm.max_block);
        if !self.told_priority {
            self.told_priority = true;
            let mut policy = 0;
            // libc, as rustix has no wrapper for the pthread scheduling
            // calls (they act on a pthread, not a kernel thread id).
            let mut param: libc::sched_param = unsafe { std::mem::zeroed() };
            unsafe {
                libc::pthread_getschedparam(libc::pthread_self(), &mut policy, &mut param);
            }
            header
                .priority
                .store(param.sched_priority as u32, Ordering::Relaxed);
            header.policy.store(policy as u32, Ordering::Relaxed);
        }
        let events = io.events.as_slice();
        let count = events.len().min(EVENTS);
        {
            let block = shm.block(&mut self.turn);
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
            block.params[..self.moves.len()].copy_from_slice(&self.moves);
            self.moves.clear();
            block.messages[..self.messages.len()].copy_from_slice(&self.messages);
            self.messages.clear();
        }

        self.seq = self.seq.wrapping_add(1);
        header.request.store(self.seq, Ordering::Release);
        futex_wake(&header.request);

        // A render waits for as long as the plugin takes; live, a block
        // that is not there in time is given up on.
        let offline = header.offline.load(Ordering::Relaxed) != 0;
        let block = Duration::from_secs_f64(frames as f64 / ctx.sample_rate.max(1.0) as f64);
        let limit = if offline {
            // Tests that make plugins hang do not wait the whole limit.
            if TEST_HANG.load(Ordering::Relaxed) {
                Duration::from_secs(1)
            } else {
                self.offline_limit
            }
        } else {
            block + block / 2 + Duration::from_millis(2)
        };
        let started = Instant::now();
        let mut spins = 0u32;
        loop {
            if header.done.load(Ordering::Acquire) == self.seq {
                break;
            }
            let waited = started.elapsed();
            let stopped = header.reason_len.load(Ordering::Acquire) > 0;
            if waited >= limit || link.dead.load(Ordering::Relaxed) || stopped {
                self.outstanding = true;
                link.late.fetch_add(1, Ordering::Relaxed);
                if offline {
                    // A render does not wait that long twice.
                    link.dead.store(true, Ordering::Relaxed);
                }
                return self.without(io);
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
        let mut block = shm.block(&mut self.turn);
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

