//! Small tools for the stereo image and level (utility), and saturation.

use super::dsp::{self, DelayLine, Downsampler, OnePole, Shape, Smooth, Svf, SvfCoefs, Upsampler};
use super::panel::{Face, Pair};
use crate::device::{Device, Io, ParamInfo, ProcessCtx, Quality};

struct NoFace;
impl Face for NoFace {}

// ---------------------------------------------------------------------------
// Utility

const GAIN: usize = 0;
const PAN: usize = 1;
const WIDTH: usize = 2;
const MONO_BELOW: usize = 3;
const INVERT_L: usize = 4;
const INVERT_R: usize = 5;
const SWAP: usize = 6;
const DC: usize = 7;

pub fn utility_params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::new("gain")
            .name("Gain")
            .range(-48.0, 24.0)
            .default_value(0.0)
            .unit("dB"),
        ParamInfo::new("pan")
            .name("Pan")
            .range(-100.0, 100.0)
            .default_value(0.0)
            .unit("%"),
        ParamInfo::new("width")
            .name("Width")
            .range(0.0, 200.0)
            .default_value(100.0)
            .unit("%"),
        ParamInfo::new("mono_below")
            .name("Mono below")
            .range(20.0, 500.0)
            .default_value(20.0)
            .unit("Hz"),
        ParamInfo::choice("invert_l", &["Off", "On"], 0).name("Invert left"),
        ParamInfo::choice("invert_r", &["Off", "On"], 0).name("Invert right"),
        ParamInfo::choice("swap", &["Off", "On"], 0).name("Swap sides"),
        ParamInfo::choice("dc", &["Off", "On"], 0).name("DC filter"),
    ]
}

pub fn utility(sr: f32) -> Pair {
    (Box::new(Utility::new(sr)), Box::new(NoFace))
}

/// Gains of the two sides for a balance of -1 (left) to 1 (right): both
/// at unity in the middle, the far side fading out along a quarter cosine.
pub fn balance(pan: f32) -> (f32, f32) {
    let pan = pan.clamp(-1.0, 1.0);
    let fade = |p: f32| (p * std::f32::consts::FRAC_PI_2).cos();
    if pan > 0.0 {
        (fade(pan), 1.0)
    } else if pan < 0.0 {
        (1.0, fade(-pan))
    } else {
        (1.0, 1.0)
    }
}

pub struct Utility {
    sr: f32,
    p: [f32; 8],
    gain_l: Smooth,
    gain_r: Smooth,
    width: Smooth,
    mono: Option<SvfCoefs>,
    side_hp: Svf,
    dc: [OnePole; 2],
    started: bool,
    rest: super::dsp::Rest,
}

impl Utility {
    fn new(sr: f32) -> Self {
        let mut u = Self {
            sr,
            p: super::defaults(&utility_params()),
            gain_l: Smooth::new(1.0, 0.02, sr),
            gain_r: Smooth::new(1.0, 0.02, sr),
            width: Smooth::new(1.0, 0.02, sr),
            mono: None,
            side_hp: Svf::default(),
            dc: [OnePole::new(5.0, sr); 2],
            started: false,
            rest: super::dsp::Rest::default(),
        };
        u.apply();
        u
    }

    fn apply(&mut self) {
        let p = &self.p;
        let gain = dsp::db_to_lin(p[GAIN].clamp(-120.0, 48.0));
        let (bl, br) = balance(p[PAN] * 0.01);
        let sign = |on: f32| if on >= 0.5 { -1.0 } else { 1.0 };
        self.gain_l.target = gain * bl * sign(p[INVERT_L]);
        self.gain_r.target = gain * br * sign(p[INVERT_R]);
        self.width.target = (p[WIDTH] * 0.01).clamp(0.0, 4.0);
        self.mono = (p[MONO_BELOW] > 20.5)
            .then(|| SvfCoefs::new(Shape::High, p[MONO_BELOW], 0.71, 0.0, self.sr));
        if !self.started {
            self.gain_l.snap();
            self.gain_r.snap();
            self.width.snap();
        }
    }
}

/// Frames the utility waits, calm, before it lets go of what its filters
/// still hold and rests.
const UTILITY_MEMORY: u32 = 4096;

impl Device for Utility {
    fn resting(&self) -> bool {
        self.rest.resting
    }

    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        if self.rest.sleeps(io) {
            return;
        }
        self.started = true;
        let swap = self.p[SWAP] >= 0.5;
        let dc = self.p[DC] >= 0.5;
        for (l, r) in io.left.iter_mut().zip(io.right.iter_mut()) {
            let (mut x, mut y) = if swap { (*r, *l) } else { (*l, *r) };
            if dc {
                x = self.dc[0].high(x);
                y = self.dc[1].high(y);
            }
            let width = self.width.step();
            if width != 1.0 || self.mono.is_some() {
                let mid = (x + y) * 0.5;
                let mut side = (x - y) * 0.5;
                if let Some(c) = &self.mono {
                    side = self.side_hp.tick(c, side);
                }
                side *= width;
                x = mid + side;
                y = mid - side;
            }
            let calm = self.rest.frame(*l, *r, x.abs().max(y.abs()));
            *l = x * self.gain_l.step();
            *r = y * self.gain_r.step();
            if calm >= UTILITY_MEMORY
                && !self.rest.resting
                && !(self.width.moving() || self.gain_l.moving() || self.gain_r.moving())
            {
                self.side_hp = Svf::default();
                self.dc.iter_mut().for_each(OnePole::reset);
                self.rest.resting = true;
            }
        }
        self.side_hp.flush();
        self.dc[0].flush();
        self.dc[1].flush();
    }

    fn set_param(&mut self, index: u32, value: f32) {
        let index = index as usize;
        if index < self.p.len() && value.is_finite() {
            self.p[index] = value;
            self.apply();
            self.rest.wake();
        }
    }
}

// ---------------------------------------------------------------------------
// Saturation

/// Input samples per phase of the oversampling filters. The round trip is
/// `TAPS - 1` samples late, the same at two and four times.
const TAPS: usize = 32;
pub const SATURATION_LATENCY: u32 = (TAPS - 1) as u32;

const DRIVE: usize = 0;
const CURVE: usize = 1;
const OVERSAMPLE: usize = 2;
const TONE: usize = 3;
const MIX: usize = 4;
const OUTPUT: usize = 5;

pub const CURVES: &[&str] = &["Tape", "Tube", "Hard clip"];

pub fn saturation_params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::new("drive")
            .name("Drive")
            .range(0.0, 36.0)
            .default_value(6.0)
            .unit("dB"),
        ParamInfo::choice("curve", CURVES, 0).name("Curve"),
        ParamInfo::choice("oversample", &["2x", "4x"], 0).name("Oversample"),
        ParamInfo::new("tone")
            .name("Tone")
            .range(-12.0, 12.0)
            .default_value(0.0)
            .unit("dB"),
        ParamInfo::new("mix")
            .name("Mix")
            .range(0.0, 100.0)
            .default_value(100.0)
            .unit("%"),
        ParamInfo::new("output")
            .name("Output")
            .range(-24.0, 12.0)
            .default_value(0.0)
            .unit("dB"),
    ]
}

struct LatencyFace(u32);
impl Face for LatencyFace {
    fn latency(&self, _values: &[f32]) -> u32 {
        self.0
    }
}

pub fn saturation(sr: f32) -> Pair {
    (
        Box::new(Saturation::new(sr)),
        Box::new(LatencyFace(SATURATION_LATENCY)),
    )
}

/// The curves, each with a slope of one through zero, so that quiet audio
/// passes at its own level and only the peaks are rounded off.
#[inline]
pub fn shape(curve: usize, x: f32) -> f32 {
    match curve {
        // Tape: symmetric and soft, odd harmonics.
        0 => x.tanh(),
        // Tube: biased to one side, so it adds even harmonics too.
        1 => {
            const BIAS: f32 = 0.3;
            // 1 / (1 - tanh²(BIAS)), so that the slope through zero is one.
            const NORM: f32 = 1.092_733;
            ((x + BIAS).tanh() - BIAS.tanh()) * NORM
        }
        _ => x.clamp(-1.0, 1.0),
    }
}

struct Channel {
    up: [Upsampler; 2],
    down: [Downsampler; 2],
    dry: DelayLine,
    tone: Svf,
    dc: OnePole,
}

pub struct Saturation {
    sr: f32,
    p: [f32; 6],
    channels: [Channel; 2],
    drive: Smooth,
    mix: Smooth,
    output: Smooth,
    tone: SvfCoefs,
    started: bool,
}

impl Saturation {
    fn new(sr: f32) -> Self {
        let channel = || Channel {
            up: [
                Upsampler::design(2, TAPS, 0.88, 6.0),
                Upsampler::design(4, TAPS, 0.88, 6.0),
            ],
            down: [
                Downsampler::design(2, TAPS, 0.88, 6.0),
                Downsampler::design(4, TAPS, 0.88, 6.0),
            ],
            dry: DelayLine::new(TAPS),
            tone: Svf::default(),
            dc: OnePole::new(10.0, sr),
        };
        let mut s = Self {
            sr,
            p: super::defaults(&saturation_params()),
            channels: [channel(), channel()],
            drive: Smooth::new(1.0, 0.02, sr),
            mix: Smooth::new(1.0, 0.02, sr),
            output: Smooth::new(1.0, 0.02, sr),
            tone: SvfCoefs::new(Shape::HighShelf, 2500.0, 0.6, 0.0, sr),
            started: false,
        };
        for i in 0..6 {
            s.apply(i);
        }
        s
    }

    fn apply(&mut self, index: usize) {
        let v = self.p[index];
        match index {
            DRIVE => self.drive.target = dsp::db_to_lin(v.clamp(0.0, 48.0)),
            TONE => {
                self.tone =
                    SvfCoefs::new(Shape::HighShelf, 2500.0, 0.6, v.clamp(-24.0, 24.0), self.sr)
            }
            MIX => self.mix.target = (v * 0.01).clamp(0.0, 1.0),
            OUTPUT => self.output.target = dsp::db_to_lin(v.clamp(-48.0, 24.0)),
            _ => {}
        }
        if !self.started {
            self.drive.snap();
            self.mix.snap();
            self.output.snap();
        }
    }
}

impl Device for Saturation {
    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        self.started = true;
        let curve = (self.p[CURVE].round().max(0.0) as usize).min(CURVES.len() - 1);
        // In edit quality there is no oversampling: the curve shapes the
        // dry line's sample, which is as late as the round trip through the
        // filters, so the latency stays the same.
        let oversample = ctx.quality == Quality::Full;
        let four = self.p[OVERSAMPLE] >= 0.5;
        let factor = if four { 4 } else { 2 };
        let stage = four as usize;
        let mut buf = [0.0f32; 4];
        for (l, r) in io.left.iter_mut().zip(io.right.iter_mut()) {
            let drive = self.drive.step();
            let mix = self.mix.step();
            let out = self.output.step();
            for (ch, x) in self.channels.iter_mut().zip([&mut *l, &mut *r]) {
                ch.dry.push(*x);
                let dry = ch.dry.get(TAPS - 1);
                let mut wet = if oversample {
                    ch.up[stage].process(*x, &mut buf[..factor]);
                    for v in &mut buf[..factor] {
                        *v = shape(curve, *v * drive) / drive;
                    }
                    ch.down[stage].process(&buf[..factor])
                } else {
                    shape(curve, dry * drive) / drive
                };
                wet = ch.tone.tick(&self.tone, wet);
                if curve == 1 {
                    wet = ch.dc.high(wet);
                }
                *x = (dry + (wet - dry) * mix) * out;
            }
        }
        for ch in &mut self.channels {
            ch.tone.flush();
            ch.dc.flush();
        }
    }

    fn set_param(&mut self, index: u32, value: f32) {
        let index = index as usize;
        if index < self.p.len() && value.is_finite() {
            self.p[index] = value;
            self.apply(index);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::devices::testkit::*;

    #[test]
    fn utility_at_rest_changes_nothing() {
        let mut fx = Fx::new("utility", 48000.0);
        let (a, b) = (noise(5000, 1), noise(5000, 2));
        assert_eq!(fx.run_stereo(&a, &b, 64), (a, b));
    }

    #[test]
    fn utility_gain_pan_width_swap_and_invert() {
        let sr = 48000.0;
        let (a, b) = (noise(5000, 1), noise(5000, 2));
        let check = |settings: &[(&str, f32)], f: &dyn Fn(f32, f32) -> (f32, f32)| {
            let mut fx = Fx::new("utility", sr);
            for (k, v) in settings {
                fx.set(k, *v);
            }
            let (l, r) = fx.run_stereo(&a, &b, 100);
            for i in 0..a.len() {
                let (el, er) = f(a[i], b[i]);
                assert!(
                    (l[i] - el).abs() < 1e-5 && (r[i] - er).abs() < 1e-5,
                    "{settings:?}"
                );
            }
        };
        check(&[("gain", -6.0)], &|x, y| (x * 0.501_187, y * 0.501_187));
        check(&[("swap", 1.0)], &|x, y| (y, x));
        check(&[("invert_l", 1.0)], &|x, y| (-x, y));
        check(&[("width", 0.0)], &|x, y| ((x + y) / 2.0, (x + y) / 2.0));
        check(&[("width", 200.0)], &|x, y| {
            ((x + y) / 2.0 + (x - y), (x + y) / 2.0 - (x - y))
        });
        check(&[("pan", 100.0)], &|_, y| (0.0, y));
        check(&[("pan", -50.0)], &|x, y| (x, y * balance(-0.5).1));
        assert!((balance(-0.5).1 - std::f32::consts::FRAC_1_SQRT_2).abs() < 1e-6);
    }

    #[test]
    fn mono_below_takes_the_sides_out_of_the_lows() {
        let sr = 48000.0;
        let mut fx = Fx::new("utility", sr);
        fx.set("mono_below", 150.0);
        let lo = sine(50.0, sr, 48000, 0.5);
        let hi = sine(2000.0, sr, 48000, 0.5);
        let neg = |v: &[f32]| v.iter().map(|x| -x).collect::<Vec<_>>();
        // A sound in the sides only: gone in the lows, kept in the highs.
        let (l, r) = fx.run_stereo(&lo, &neg(&lo), 256);
        let side: Vec<f32> = l.iter().zip(&r).map(|(a, b)| (a - b) / 2.0).collect();
        assert!(rms_db(&side[24000..]) < rms_db(&lo) - 15.0);
        fx.reset();
        let (l, r) = fx.run_stereo(&hi, &neg(&hi), 256);
        let side: Vec<f32> = l.iter().zip(&r).map(|(a, b)| (a - b) / 2.0).collect();
        assert!((rms_db(&side[24000..]) - rms_db(&hi)).abs() < 0.1);
    }

    #[test]
    fn the_dc_filter_removes_an_offset() {
        let mut fx = Fx::new("utility", 48000.0);
        fx.set("dc", 1.0);
        let x: Vec<f32> = noise(96000, 3).iter().map(|v| v * 0.1 + 0.3).collect();
        let out = fx.run(&x, 512);
        let mean = out[48000..].iter().sum::<f32>() / 48000.0;
        assert!(mean.abs() < 0.002, "{mean}");
    }

    #[test]
    fn saturation_is_quiet_audio_unchanged_and_late_by_its_latency() {
        for sr in [44100.0, 48000.0, 96000.0] {
            for over in [0.0, 1.0] {
                let mut fx = Fx::new("saturation", sr);
                fx.set("oversample", over);
                fx.set("drive", 0.0);
                let x = sine(1000.0, sr, 8000, 0.01);
                let out = fx.run(&x, 128);
                let late = fx.latency() as usize;
                let err = (2000..8000)
                    .map(|i| (out[i] - x[i - late]).abs())
                    .fold(0.0, f32::max);
                assert!(err < 1e-4, "{sr} Hz, oversampling {over}: {err}");
            }
        }
    }

    #[test]
    fn saturation_adds_harmonics_and_little_aliasing() {
        let sr = 48000.0;
        let n = 16384;
        // 9 kHz driven hard: harmonics at 27 and 45 kHz fold back to 21
        // and 3 kHz without oversampling.
        let x = sine(9000.0, sr, n * 2, 0.8);
        let level = |out: &[f32], f: f64| {
            let tail = &out[n..];
            let re: Vec<f64> = tail
                .iter()
                .enumerate()
                .map(|(i, v)| {
                    *v as f64 * (0.5 - 0.5 * (std::f64::consts::TAU * i as f64 / n as f64).cos())
                })
                .collect();
            let spec = dsp::rfft(&re);
            let k = (f * n as f64 / sr as f64).round() as usize;
            let e: f64 = (k - 2..=k + 2).map(|k| spec[k].norm_sqr()).sum();
            10.0 * e.max(1e-30).log10()
        };
        // Against the same curve without oversampling: 17.5 dB down.
        let naive: Vec<f32> = x.iter().map(|v| (v * 15.85).tanh() / 15.85).collect();
        let naive = level(&naive, 9000.0) - level(&naive, 3000.0);
        for (over, better) in [(0.0, 8.0), (1.0, 17.0)] {
            let mut fx = Fx::new("saturation", sr);
            fx.set("drive", 24.0);
            fx.set("oversample", over);
            let out = fx.run(&x, 256);
            let down = level(&out, 9000.0) - level(&out, 3000.0);
            assert!(
                down > naive + better,
                "oversampling {over}: aliasing {down:.1} dB down, {naive:.1} without"
            );
        }
        // And the tube curve adds the second harmonic, which tape does not.
        let x = sine(1000.0, sr, n * 2, 0.5);
        let second = |curve: f32| {
            let mut fx = Fx::new("saturation", sr);
            fx.set("drive", 18.0);
            fx.set("curve", curve);
            let out = fx.run(&x, 256);
            level(&out, 2000.0) - level(&out, 1000.0)
        };
        assert!(
            second(1.0) > -40.0 && second(0.0) < -80.0,
            "{} {}",
            second(1.0),
            second(0.0)
        );
    }

    #[test]
    fn saturation_in_edit_quality_shapes_at_the_input_rate_as_late_as_at_full() {
        let mut fx = Fx::new("saturation", 48000.0);
        fx.set("drive", 24.0);
        fx.set("oversample", 1.0);
        fx.ctx.quality = Quality::Edit;
        let x = sine(9000.0, 48000.0, 4000, 0.8);
        let out = fx.run(&x, 256);
        // The tape curve on each input sample, 31 samples late, with no
        // filters of an oversampler around it.
        let drive = 10f32.powf(24.0 / 20.0);
        for (i, got) in out.iter().enumerate().skip(31) {
            let want = (x[i - 31] * drive).tanh() / drive;
            assert!((got - want).abs() < 1e-5, "sample {i}: {got}, not {want}");
        }
    }

    #[test]
    fn saturation_mix_at_zero_is_the_dry_signal_late() {
        let mut fx = Fx::new("saturation", 48000.0);
        fx.set("mix", 0.0);
        fx.set("drive", 30.0);
        let x = noise(4000, 6);
        let out = fx.run(&x, 50);
        let late = fx.latency() as usize;
        assert_eq!(&out[late..], &x[..x.len() - late]);
    }
}
