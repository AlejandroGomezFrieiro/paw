//! An algorithmic reverb: early reflections and a feedback delay network.
//!
//! The input is delayed (pre-delay), smeared by a chain of all-pass
//! diffusers per channel, and fed into eight delay lines whose outputs are
//! mixed back into their inputs through a Hadamard matrix, which keeps the
//! energy and mixes every line into every other. Each line's gain is set
//! from its length so that the tail falls by 60 dB in the decay time; a
//! low-pass and a high-pass in each line make the highs and the lows die
//! sooner (damping). The lines' lengths drift slowly by a fraction of a
//! millisecond, each at its own rate, which breaks up the resonances a
//! static network rings at (the metallic sound of a cheap reverb on a
//! snare). Early reflections are taps on the pre-delayed input, spread
//! across the stereo field. The wet signal is DC-blocked, widened or
//! narrowed (mid/side) and mixed with the dry.

use super::dsp::{self, DelayLine, Lfo, OnePole, Rest, Smooth};
use super::panel::{Face, Pair};
use crate::device::{Device, Io, ParamInfo, ProcessCtx};

const LINES: usize = 8;
/// Line lengths in ms at size 100 %: spread out and with no common factors.
const LENGTHS_MS: [f32; LINES] = [29.7, 37.1, 41.1, 43.7, 53.3, 59.9, 67.7, 73.9];
/// The size control scales the lengths from this to the largest below.
const SCALE_MIN: f32 = 0.25;
const SCALE_MAX: f32 = 1.75;
/// How far, in ms, and how fast, in Hz, the lines' lengths drift.
const DRIFT_MS: f32 = 0.35;
const DRIFT_HZ: [f64; LINES] = [0.31, 0.43, 0.53, 0.61, 0.37, 0.47, 0.59, 0.71];
/// The diffusers of each channel, in ms at size 100 %.
const DIFFUSERS_MS: [[f32; 4]; 2] = [[4.77, 3.59, 12.73, 9.31], [4.37, 3.91, 11.97, 8.83]];
/// Early reflections at size 100 %: time (ms), level, pan (-1 left .. 1 right).
const REFLECTIONS: [(f32, f32, f32); 12] = [
    (7.1, 0.84, -0.7),
    (11.3, 0.77, 0.6),
    (15.7, 0.7, -0.2),
    (19.9, 0.66, 0.9),
    (24.3, 0.6, -0.9),
    (29.3, 0.55, 0.3),
    (34.1, 0.5, -0.5),
    (41.9, 0.44, 0.8),
    (48.7, 0.4, -0.3),
    (56.3, 0.35, 0.5),
    (63.1, 0.3, -0.8),
    (71.7, 0.26, 0.1),
];
const MAX_PREDELAY_MS: f32 = 250.0;
/// Samples between recomputing the lines' gains while settings glide.
const UPDATE: u32 = 32;

const SIZE: usize = 0;
const DECAY: usize = 1;
const PREDELAY: usize = 2;
const DAMP_HIGH: usize = 3;
const DAMP_LOW: usize = 4;
const DIFFUSION: usize = 5;
const EARLY: usize = 6;
const WIDTH: usize = 7;
const MIX: usize = 8;

pub fn params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::new("size").name("Size").range(0.0, 100.0).default_value(50.0).unit("%"),
        ParamInfo::new("decay").name("Decay").range(0.1, 20.0).default_value(1.8).unit("s"),
        ParamInfo::new("predelay")
            .name("Pre-delay")
            .range(0.0, MAX_PREDELAY_MS)
            .default_value(10.0)
            .unit("ms"),
        ParamInfo::new("damp_high")
            .name("High damping")
            .range(1000.0, 20000.0)
            .default_value(7000.0)
            .unit("Hz"),
        ParamInfo::new("damp_low")
            .name("Low damping")
            .range(20.0, 1000.0)
            .default_value(80.0)
            .unit("Hz"),
        ParamInfo::new("diffusion")
            .name("Diffusion")
            .range(0.0, 100.0)
            .default_value(75.0)
            .unit("%"),
        ParamInfo::new("early").name("Early/late").range(0.0, 100.0).default_value(25.0).unit("%"),
        ParamInfo::new("width").name("Width").range(0.0, 150.0).default_value(100.0).unit("%"),
        ParamInfo::new("mix").name("Mix").range(0.0, 100.0).default_value(25.0).unit("%"),
    ]
}

struct NoFace;
impl Face for NoFace {}

pub fn make(sr: f32) -> Pair {
    (Box::new(Reverb::new(sr)), Box::new(NoFace))
}

/// A Schroeder all-pass: a delay with feedback and feedforward of `g`.
struct AllPass {
    line: DelayLine,
    max: f32,
}

impl AllPass {
    #[inline]
    fn tick(&mut self, x: f32, delay: f32, g: f32) -> f32 {
        // A whole number of frames: the diffusers' lengths only move with
        // the size, and a step there is lost in the smear.
        let d = self.line.get((delay.min(self.max) as usize).max(1) - 1);
        let v = dsp::flush(x + g * d);
        self.line.push(v);
        d - g * v
    }
}

pub struct Reverb {
    sr: f32,
    p: [f32; 9],
    predelay: [DelayLine; 2],
    diffusers: [[AllPass; 4]; 2],
    lines: [DelayLine; LINES],
    lfos: [Lfo; LINES],
    /// Each line's drift, in frames, at the last update, and how far it
    /// moves each frame until the next: the drift is worked out on a grid
    /// of [`UPDATE`] frames and drawn straight between.
    wobble: [f32; LINES],
    wobble_step: [f32; LINES],
    gains: [f32; LINES],
    lows: [OnePole; LINES],
    highs: [OnePole; LINES],
    dc: [OnePole; 2],
    /// Glide: size scale, decay seconds, pre-delay frames, mix, width,
    /// early share.
    scale: Smooth,
    decay: Smooth,
    pre: Smooth,
    mix: Smooth,
    width: Smooth,
    early: Smooth,
    clock: u32,
    started: bool,
    rest: Rest,
}

impl Reverb {
    pub fn new(sr: f32) -> Self {
        let ms = |v: f32| v * 0.001 * sr;
        let longest = ms(LENGTHS_MS[LINES - 1] * SCALE_MAX + DRIFT_MS * 2.0) as usize + 8;
        let pre_len = ms(MAX_PREDELAY_MS + REFLECTIONS[11].0 * SCALE_MAX) as usize + 8;
        let diffuser = |d: f32| {
            let max = ms(d * SCALE_MAX) + 2.0;
            AllPass {
                line: DelayLine::new(max as usize + 4),
                max,
            }
        };
        let p = super::defaults(&params());
        let mut r = Self {
            sr,
            p,
            predelay: [DelayLine::new(pre_len), DelayLine::new(pre_len)],
            diffusers: DIFFUSERS_MS.map(|ch| ch.map(diffuser)),
            lines: std::array::from_fn(|_| DelayLine::new(longest)),
            lfos: std::array::from_fn(|i| Lfo {
                phase: i as f64 / LINES as f64,
            }),
            wobble: [0.0; LINES],
            wobble_step: [0.0; LINES],
            gains: [0.0; LINES],
            lows: [OnePole::default(); LINES],
            highs: [OnePole::default(); LINES],
            dc: [OnePole::new(5.0, sr); 2],
            scale: Smooth::new(1.0, 0.15, sr),
            decay: Smooth::new(1.0, 0.05, sr),
            pre: Smooth::new(0.0, 0.05, sr),
            mix: Smooth::new(0.0, 0.02, sr),
            width: Smooth::new(1.0, 0.02, sr),
            early: Smooth::new(0.0, 0.02, sr),
            clock: 0,
            started: false,
            rest: Rest::default(),
        };
        for i in 0..r.p.len() {
            r.apply(i);
        }
        r.update_gains();
        r
    }

    fn apply(&mut self, index: usize) {
        let v = self.p[index];
        let sr = self.sr;
        match index {
            SIZE => {
                self.scale.target = SCALE_MIN + (SCALE_MAX - SCALE_MIN) * (v * 0.01).clamp(0.0, 1.0)
            }
            DECAY => self.decay.target = v.clamp(0.05, 60.0),
            PREDELAY => self.pre.target = v.clamp(0.0, MAX_PREDELAY_MS) * 0.001 * sr,
            // At the ends of their ranges the damping filters are off.
            DAMP_HIGH => {
                for f in &mut self.lows {
                    if v >= 19999.0 {
                        f.open();
                    } else {
                        f.set(v.clamp(200.0, 22000.0), sr);
                    }
                }
            }
            DAMP_LOW => {
                for f in &mut self.highs {
                    f.set(if v <= 20.5 { 0.0 } else { v.min(2000.0) }, sr);
                }
            }
            MIX => self.mix.target = (v * 0.01).clamp(0.0, 1.0),
            WIDTH => self.width.target = (v * 0.01).clamp(0.0, 1.5),
            EARLY => self.early.target = (v * 0.01).clamp(0.0, 1.0),
            _ => {}
        }
        if !self.started {
            for s in [
                &mut self.scale,
                &mut self.decay,
                &mut self.pre,
                &mut self.mix,
                &mut self.width,
                &mut self.early,
            ] {
                s.snap();
            }
        }
    }

    /// Whether every setting has got where it glides to.
    fn settled(&self) -> bool {
        ![
            &self.scale,
            &self.decay,
            &self.pre,
            &self.mix,
            &self.width,
            &self.early,
        ]
        .iter()
        .any(|s| s.moving())
    }

    /// Frames of silence the reverb remembers: its longest buffer.
    fn memory(&self) -> u32 {
        let diffusers = self.diffusers.iter().flatten();
        diffusers
            .map(|ap| ap.line.capacity())
            .chain([self.predelay[0].capacity(), self.lines[0].capacity()])
            .max()
            .unwrap_or(0) as u32
    }

    /// Let go of a tail that has died away below hearing.
    fn clear(&mut self) {
        for line in self.predelay.iter_mut().chain(&mut self.lines) {
            line.clear();
        }
        for ap in self.diffusers.iter_mut().flatten() {
            ap.line.clear();
        }
        for f in self
            .lows
            .iter_mut()
            .chain(&mut self.highs)
            .chain(&mut self.dc)
        {
            f.reset();
        }
    }

    /// Each line's gain per pass, so that the tail falls 60 dB in the decay.
    fn update_gains(&mut self) {
        let frames_per_second = self.sr;
        for (g, len) in self.gains.iter_mut().zip(LENGTHS_MS) {
            let frames = len * 0.001 * self.scale.value * frames_per_second;
            *g = 10f32.powf(-3.0 * frames / (self.decay.value * frames_per_second));
        }
    }
}

/// The fast Walsh-Hadamard transform of eight values, scaled to keep energy.
#[inline]
fn hadamard(x: &mut [f32; LINES]) {
    let mut h = 1;
    while h < LINES {
        for i in (0..LINES).step_by(h * 2) {
            for j in i..i + h {
                let (a, b) = (x[j], x[j + h]);
                x[j] = a + b;
                x[j + h] = a - b;
            }
        }
        h *= 2;
    }
    let norm = 1.0 / (LINES as f32).sqrt();
    for v in x {
        *v *= norm;
    }
}

impl Device for Reverb {
    fn resting(&self) -> bool {
        self.rest.resting
    }

    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        if self.rest.sleeps(io) {
            return;
        }
        self.started = true;
        let memory = self.memory();
        let ms = 0.001 * self.sr;
        let diffuse = (self.p[DIFFUSION] * 0.01).clamp(0.0, 1.0) * 0.7;
        let drift = DRIFT_MS * ms;
        let steps = DRIFT_HZ.map(|hz| hz / self.sr as f64 * UPDATE as f64);
        for (l, r) in io.left.iter_mut().zip(io.right.iter_mut()) {
            if self.rest.holds(*l, *r) {
                continue;
            }
            if self.clock.is_multiple_of(UPDATE) {
                if self.scale.moving() || self.decay.moving() {
                    self.update_gains();
                }
                // The drift where it is now and where it will be at the
                // next update: a sine a few times a second is a straight
                // line over that much.
                for (i, lfo) in self.lfos.iter_mut().enumerate() {
                    let from = dsp::sin_cycles(lfo.tick(steps[i])) * drift;
                    let to = dsp::sin_cycles(lfo.phase) * drift;
                    self.wobble[i] = from;
                    self.wobble_step[i] = (to - from) / UPDATE as f32;
                }
            }
            self.clock = self.clock.wrapping_add(1);
            let scale = self.scale.step();
            self.decay.step();
            let pre = self.pre.step();
            let (dry_l, dry_r) = (*l, *r);

            // Pre-delay, then early reflections from it.
            self.predelay[0].push(dry_l);
            self.predelay[1].push(dry_r);
            let at = pre.max(1.0);
            let (pl, pr) = (self.predelay[0].get_frac(at), self.predelay[1].get_frac(at));
            let (mut el, mut er) = (0.0, 0.0);
            for &(t, level, pan) in &REFLECTIONS {
                let tap = at + t * scale * ms;
                let tap = tap as usize;
                let x = self.predelay[0].get(tap) + self.predelay[1].get(tap);
                el += x * level * (1.0 - pan);
                er += x * level * (1.0 + pan);
            }
            let (el, er) = (el * 0.12, er * 0.12);

            let mut input = [pl, pr];
            for (ch, x) in input.iter_mut().enumerate() {
                for (ap, d) in self.diffusers[ch].iter_mut().zip(DIFFUSERS_MS[ch]) {
                    *x = ap.tick(*x, d * scale * ms, diffuse);
                }
            }

            // The network: read, damp, mix, feed back with the input.
            let mut taps = [0.0f32; LINES];
            for (i, tap) in taps.iter_mut().enumerate() {
                let wobble = self.wobble[i];
                self.wobble[i] += self.wobble_step[i];
                let len = LENGTHS_MS[i] * scale * ms + wobble;
                let x = self.lines[i].get_frac(len);
                let x = self.highs[i].high(self.lows[i].low(x));
                *tap = x * self.gains[i];
            }
            // Output: alternating signs give the two sides different mixes.
            let (mut wl, mut wr) = (0.0, 0.0);
            for (i, t) in taps.iter().enumerate() {
                if i % 2 == 0 {
                    wl += t;
                    wr += if i % 4 == 0 { *t } else { -t };
                } else {
                    wr += t;
                    wl += if i % 4 == 1 { -t } else { *t };
                }
            }
            hadamard(&mut taps);
            let mut level = 0.0f32;
            for (i, line) in self.lines.iter_mut().enumerate() {
                let x = taps[i] + input[i % 2] * 0.5;
                level = level.max(x.abs());
                line.push(dsp::flush(x));
            }
            let (wl, wr) = (wl * 0.35, wr * 0.35);

            // Early against late, DC blocked, width, mix.
            let early = self.early.step();
            let (late, er_level) = ((1.0 - early) * 2.0, early * 2.0);
            let wl = self.dc[0].high(wl * late.min(1.0) + el * er_level.min(1.0));
            let wr = self.dc[1].high(wr * late.min(1.0) + er * er_level.min(1.0));
            let width = self.width.step();
            let (mid, side) = ((wl + wr) * 0.5, (wl - wr) * 0.5 * width);
            let mix = self.mix.step();
            let (dry, wet) = ((2.0 * (1.0 - mix)).min(1.0), (2.0 * mix).min(1.0));
            *l = dry_l * dry + (mid + side) * wet;
            *r = dry_r * dry + (mid - side) * wet;
            // Silent for as long as it remembers, and every setting where
            // it glides to: the tail has died away.
            if self.rest.frame(dry_l, dry_r, level) >= memory
                && !self.rest.resting
                && self.settled()
            {
                self.clear();
                self.rest.resting = true;
            }
        }
        for f in self
            .lows
            .iter_mut()
            .chain(&mut self.highs)
            .chain(&mut self.dc)
        {
            f.flush();
        }
    }

    fn set_param(&mut self, index: u32, value: f32) {
        let index = index as usize;
        if index < self.p.len() && value.is_finite() {
            self.p[index] = value;
            self.apply(index);
            self.rest.wake();
            if !self.started {
                self.update_gains();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::devices::testkit::*;

    /// The time the impulse response takes to fall 60 dB, from the slope
    /// of its Schroeder curve between -5 and -35 dB (T30).
    fn rt60(ir: &[f32], sr: f32) -> f32 {
        let mut energy: Vec<f64> = ir.iter().map(|v| (*v as f64).powi(2)).collect();
        for i in (0..energy.len() - 1).rev() {
            energy[i] += energy[i + 1];
        }
        let total = energy[0];
        let db = |i: usize| 10.0 * (energy[i] / total).log10();
        let at = |level: f64| (0..energy.len()).find(|&i| db(i) < level).unwrap();
        let (a, b) = (at(-5.0), at(-35.0));
        (b - a) as f32 / sr * 2.0
    }

    fn impulse_response(fx: &mut Fx, seconds: f32) -> Vec<f32> {
        let n = (fx.sr * seconds) as usize;
        let mut x = vec![0.0; n];
        x[0] = 1.0;
        let (l, r) = fx.run_stereo(&x, &x, 512);
        l.iter().zip(&r).map(|(a, b)| a + b).collect()
    }

    fn undamped(sr: f32) -> Fx {
        let mut fx = Fx::new("reverb", sr);
        fx.set("mix", 100.0);
        fx.set("early", 0.0);
        fx.set("damp_high", 20000.0);
        fx.set("damp_low", 20.0);
        fx.set("predelay", 0.0);
        fx
    }

    #[test]
    fn the_tail_takes_the_decay_time_to_fall_60_db() {
        for sr in [44100.0, 48000.0, 96000.0] {
            for (decay, size) in [(0.8, 30.0), (2.0, 50.0), (5.0, 100.0)] {
                let mut fx = undamped(sr);
                fx.set("decay", decay);
                fx.set("size", size);
                let ir = impulse_response(&mut fx, decay * 1.5);
                let got = rt60(&ir, sr);
                assert!(
                    (got / decay - 1.0).abs() < 0.12,
                    "at {sr} Hz, size {size}: set to {decay} s, decays in {got} s"
                );
            }
        }
    }

    #[test]
    fn damping_shortens_the_highs() {
        let sr = 48000.0;
        let mut fx = undamped(sr);
        fx.set("decay", 3.0);
        let bright = impulse_response(&mut fx, 3.0);
        fx.set("damp_high", 2000.0);
        fx.reset();
        let dark = impulse_response(&mut fx, 3.0);
        // Energy above 5 kHz in the second half second, by a first difference.
        let high = |x: &[f32]| {
            rms_db(
                &x[24000..48000]
                    .windows(2)
                    .map(|w| w[1] - w[0])
                    .collect::<Vec<_>>(),
            )
        };
        assert!(
            high(&dark) < high(&bright) - 10.0,
            "{} vs {}",
            high(&dark),
            high(&bright)
        );
    }

    #[test]
    fn energy_stays_bounded_at_the_longest_decay() {
        let sr = 44100.0;
        let mut fx = undamped(sr);
        fx.set("decay", 20.0);
        fx.set("size", 100.0);
        let x = noise(sr as usize * 20, 3);
        let (l, _) = fx.run_stereo(&x, &x, 1024);
        let second = |i: usize| rms_db(&l[i * sr as usize..(i + 1) * sr as usize]);
        assert!(l.iter().all(|v| v.is_finite()));
        // Steady noise into a long tail: the level settles and stays.
        assert!(
            (second(19) - second(15)).abs() < 1.5,
            "{} then {}",
            second(15),
            second(19)
        );
        assert!(second(19) < 20.0);
    }

    #[test]
    fn no_dc_comes_out() {
        let sr = 48000.0;
        let mut fx = undamped(sr);
        fx.set("damp_low", 20.0);
        let x: Vec<f32> = noise(sr as usize * 3, 4)
            .iter()
            .map(|v| v * 0.2 + 0.5)
            .collect();
        let out = fx.run(&x, 256);
        let tail = &out[out.len() - sr as usize..];
        let mean = tail.iter().sum::<f32>() / tail.len() as f32;
        assert!(mean.abs() < 0.01, "a DC offset in, {mean} out");
    }

    #[test]
    fn mix_at_zero_is_transparent() {
        let mut fx = Fx::new("reverb", 48000.0);
        fx.set("mix", 0.0);
        let x = noise(20000, 1);
        let (l, r) = fx.run_stereo(&x, &x, 77);
        assert_eq!(l, x);
        assert_eq!(r, x);
    }

    /// How far the strongest band of a spectrum stands above the bands
    /// around it, in dB: bands of 8 bins (23 Hz at 48 kHz) from 200 Hz to
    /// 8 kHz, each against the four on either side.
    fn peakiness(x: &[f32], sr: f32) -> f64 {
        let n = x.len();
        let re: Vec<f64> = x
            .iter()
            .enumerate()
            .map(|(i, v)| {
                *v as f64 * (0.5 - 0.5 * (std::f64::consts::TAU * i as f64 / n as f64).cos())
            })
            .collect();
        let spec = dsp::rfft(&re);
        let bin = |f: f64| (f * n as f64 / sr as f64) as usize;
        let bands: Vec<f64> = (bin(200.0)..bin(8000.0))
            .step_by(8)
            .map(|b| {
                (b..b + 8)
                    .map(|k| spec[k].norm_sqr())
                    .sum::<f64>()
            })
            .collect();
        let mut most = f64::MIN;
        for k in 4..bands.len() - 4 {
            let around = (bands[k - 4..k].iter().sum::<f64>()
                + bands[k + 1..k + 5].iter().sum::<f64>())
                / 8.0;
            most = most.max(10.0 * (bands[k] / around).log10());
        }
        most
    }

    #[test]
    fn a_snare_hit_does_not_ring() {
        // A modal network rings: a few frequencies stand far above the rest
        // in the tail's spectrum, between 100 and 440 ms after the hit.
        let sr = 48000.0;
        let mut fx = Fx::new("reverb", sr);
        fx.set("mix", 100.0);
        fx.set("decay", 1.2);
        fx.set("size", 30.0);
        let mut hit = noise((sr * 0.15) as usize, 8);
        for (i, v) in hit.iter_mut().enumerate() {
            *v *= (-(i as f32) / (sr * 0.03)).exp();
        }
        hit.extend(vec![0.0; sr as usize]);
        let out = fx.run(&hit, 256);
        let at = (sr * 0.1) as usize;
        let tail = &out[at..at + 16384];
        // The same measure of noise dying away as fast: what no ringing reads.
        let rate = 6.91 / (1.2 * sr);
        let plain: Vec<f32> = noise(16384, 21)
            .iter()
            .enumerate()
            .map(|(i, v)| v * (-(i as f32) * rate).exp())
            .collect();
        let (ratio, baseline) = (peakiness(tail, sr), peakiness(&plain, sr));
        assert!(
            ratio < baseline + 3.0,
            "a band of the tail stands {ratio:.1} dB above those around it; in noise, {baseline:.1} dB"
        );
    }
}
