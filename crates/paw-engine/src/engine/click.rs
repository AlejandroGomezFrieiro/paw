//! The metronome and the count-in.

use crate::tempo::TempoMap;

use super::Engine;

/// The most frames of one call whose clicks can go to an output of their
/// own: as many as a backend hands the engine at once.
pub(super) const CLICK_FRAMES: usize = 8192;

#[derive(Default)]
pub(super) struct Click {
    pub(super) phase: f32,
    pub(super) env: f32,
    pub(super) freq: f32,
}

/// A count-in: see [`Msg::CountIn`]. Frames count from when it began.
#[derive(Clone, Copy, Debug)]
pub(super) struct Count {
    pub(super) frames: u64,
    pub(super) every: f64,
    pub(super) clicks: u32,
    pub(super) per_bar: u32,
    /// How late its clicks are heard, as the song is: the schedule's latency.
    pub(super) delay: u64,
    pub(super) elapsed: u64,
    /// The next click to sound, and whether the song has started.
    pub(super) next: u32,
    pub(super) started: bool,
}

impl Count {
    /// Where the clicks of the next `n` frames fall in them.
    pub(super) fn clicks(&mut self, n: usize, starts: &mut [(usize, bool)], count: &mut usize) {
        while self.next < self.clicks {
            let at = (self.next as f64 * self.every).round() as u64 + self.delay;
            if at >= self.elapsed + n as u64 {
                break;
            }
            if at >= self.elapsed && *count < starts.len() {
                starts[*count] = ((at - self.elapsed) as usize, self.next % self.per_bar == 0);
                *count += 1;
            }
            self.next += 1;
        }
    }

    /// Beats still to be counted before the song starts.
    pub(super) fn left(&self) -> u32 {
        if self.started {
            return 0;
        }
        (((self.frames - self.elapsed.min(self.frames)) as f64 / self.every.max(1.0)).ceil() as u32)
            .max(1)
    }
}

/// Most metronome clicks in one block: at 999 BPM in x/64 a block of
/// [`MAX_BLOCK`] frames at 8 kHz holds about 34.
pub(super) const MAX_CLICKS: usize = 64;

impl Engine {
    /// Where the metronome clicks in a block of `n` frames, for the
    /// signature beats heard from `from` to `to` (in seconds), the first
    /// beat of each bar marked to be higher.
    pub(super) fn metronome_clicks(
        &self,
        n: usize,
        map: &TempoMap,
        from: f64,
        to: f64,
        starts: &mut [(usize, bool)],
        count: &mut usize,
    ) {
        let sr = self.sample_rate;
        map.lines(map.beat(from), map.beat(to), |line| {
            if *count < starts.len() {
                let at = ((map.seconds(line.beat) - from) * sr).max(0.0) as usize;
                starts[*count] = (at.min(n - 1), line.index == 0);
                *count += 1;
            }
            *count < starts.len()
        });
    }

    /// Sound the clicks that start in this block, in order of their frames,
    /// and the ring of the one before.
    pub(super) fn click(&mut self, out_l: &mut [f32], out_r: &mut [f32], starts: &[(usize, bool)]) {
        let n = out_l.len();
        let sr = self.sample_rate;
        let count = starts.len();
        let mut next = 0;
        let fall = (-1.0 / (sr as f32 * 0.02)).exp();
        let level = 0.3 * self.click_gain;
        let accents = self.click_accent;
        // On an output of its own, the clicks go beside the song, not in it.
        let at = self.click_at;
        let own = self.click_output > 0 && at + n <= CLICK_FRAMES;
        let [own_l, own_r] = &mut self.click_buf;
        let (out_l, out_r) = if own {
            (&mut own_l[at..at + n], &mut own_r[at..at + n])
        } else {
            (out_l, out_r)
        };
        for i in 0..n {
            while next < count && starts[next].0 == i {
                let accent = starts[next].1 && accents;
                self.click = Click {
                    phase: 0.0,
                    env: 1.0,
                    freq: if accent { 1760.0 } else { 1320.0 },
                };
                next += 1;
            }
            if self.click.env > 1e-4 {
                let s = (self.click.phase * std::f32::consts::TAU).sin() * self.click.env * level;
                out_l[i] += s;
                out_r[i] += s;
                self.click.phase = (self.click.phase + self.click.freq / sr as f32).fract();
                self.click.env *= fall;
            }
        }
    }
}
