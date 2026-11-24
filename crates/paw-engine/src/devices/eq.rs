//! A parametric equaliser: eight bands, each a cut, shelf, bell, notch or
//! band-pass, built from state-variable filters, and an output gain.
//!
//! A band's frequency, gain and Q glide to new settings (in octaves, dB and
//! octaves of Q) and its filter is recomputed every [`UPDATE`] samples while
//! they do, which the state-variable filter takes without clicks. Switching
//! a band on or off, or changing its type, fades it out and in over 10 ms.
//! A bell or shelf at 0 dB is skipped, so a flat band costs nothing.

use anyhow::Result;

use super::dsp::{self, Shape, Smooth, Svf, SvfCoefs};
use super::panel::{self, Face, Pair};
use crate::device::{Device, Io, ParamInfo, ProcessCtx};

pub const BANDS: usize = 8;
/// Parameters per band: on, type, frequency, gain, Q.
const PER_BAND: usize = 5;
const OUTPUT: usize = BANDS * PER_BAND;
/// Samples between filter updates while a setting glides.
const UPDATE: u32 = 16;

pub const TYPES: &[&str] = &[
    "Low cut 12",
    "Low cut 24",
    "Low shelf",
    "Bell",
    "High shelf",
    "High cut 12",
    "High cut 24",
    "Notch",
    "Band pass",
];

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    LowCut12,
    LowCut24,
    LowShelf,
    Bell,
    HighShelf,
    HighCut12,
    HighCut24,
    Notch,
    BandPass,
}

impl Kind {
    pub fn from_value(v: f32) -> Self {
        use Kind::*;
        let all = [
            LowCut12, LowCut24, LowShelf, Bell, HighShelf, HighCut12, HighCut24, Notch, BandPass,
        ];
        all[(v.round().max(0.0) as usize).min(all.len() - 1)]
    }

    /// Whether the band uses its gain (and is a no-op at 0 dB).
    fn has_gain(self) -> bool {
        matches!(self, Kind::LowShelf | Kind::Bell | Kind::HighShelf)
    }

    /// The filters in series that make this band: up to two.
    pub fn stages(self, freq: f32, q: f32, gain: f32, sr: f32) -> [Option<SvfCoefs>; 2] {
        // Two second-order sections with the Q's of a fourth-order
        // Butterworth, both scaled with the band's Q (0.71 is Butterworth).
        let scale = q / std::f32::consts::FRAC_1_SQRT_2;
        let one = |shape, q| Some(SvfCoefs::new(shape, freq, q, gain, sr));
        match self {
            Kind::LowCut12 => [one(Shape::High, q), None],
            Kind::LowCut24 => [
                one(Shape::High, 0.5412 * scale),
                one(Shape::High, 1.3066 * scale),
            ],
            Kind::HighCut12 => [one(Shape::Low, q), None],
            Kind::HighCut24 => [
                one(Shape::Low, 0.5412 * scale),
                one(Shape::Low, 1.3066 * scale),
            ],
            Kind::LowShelf => [one(Shape::LowShelf, q), None],
            Kind::HighShelf => [one(Shape::HighShelf, q), None],
            Kind::Bell => [one(Shape::Bell, q), None],
            Kind::Notch => [one(Shape::Notch, q), None],
            Kind::BandPass => [one(Shape::Band, q), None],
        }
    }
}

/// Where each band starts: off at the ends, flat in between.
const DEFAULTS: [(bool, Kind, f32, f32); BANDS] = [
    (false, Kind::LowCut24, 80.0, 0.71),
    (true, Kind::LowShelf, 120.0, 0.71),
    (true, Kind::Bell, 300.0, 1.0),
    (true, Kind::Bell, 800.0, 1.0),
    (true, Kind::Bell, 2500.0, 1.0),
    (true, Kind::Bell, 6000.0, 1.0),
    (true, Kind::HighShelf, 10000.0, 0.71),
    (false, Kind::HighCut12, 18000.0, 0.71),
];

pub fn params() -> Vec<ParamInfo> {
    let mut out = Vec::new();
    for (i, &(on, kind, freq, q)) in DEFAULTS.iter().enumerate() {
        let b = i + 1;
        out.push(
            ParamInfo::choice(&format!("b{b}_on"), &["Off", "On"], on as usize)
                .name(&format!("{b} On")),
        );
        out.push(
            ParamInfo::choice(&format!("b{b}_type"), TYPES, kind as usize)
                .name(&format!("{b} Type")),
        );
        out.push(
            ParamInfo::new(&format!("b{b}_freq"))
                .name(&format!("{b} Freq"))
                .range(20.0, 20000.0)
                .default_value(freq)
                .unit("Hz"),
        );
        out.push(
            ParamInfo::new(&format!("b{b}_gain"))
                .name(&format!("{b} Gain"))
                .range(-24.0, 24.0)
                .default_value(0.0)
                .unit("dB"),
        );
        out.push(
            ParamInfo::new(&format!("b{b}_q"))
                .name(&format!("{b} Q"))
                .range(0.1, 18.0)
                .default_value(q)
                .unit("Q"),
        );
    }
    out.push(
        ParamInfo::new("output")
            .name("Output")
            .range(-24.0, 24.0)
            .default_value(0.0)
            .unit("dB"),
    );
    out
}

pub fn make(sr: f32) -> Pair {
    (Box::new(Eq::new(sr)), Box::new(EqFace { sr }))
}

#[derive(Clone, Copy)]
struct Band {
    on: bool,
    kind: Kind,
    /// The kind to change to once faded out.
    next: Kind,
    /// log2 of the frequency, dB, log2 of Q: what glides.
    freq: Smooth,
    gain: Smooth,
    q: Smooth,
    coefs: [Option<SvfCoefs>; 2],
    /// [stage][channel]
    state: [[Svf; 2]; 2],
    /// How much of the band is heard, 0 to 1, moving to `on`.
    level: f32,
}

impl Band {
    fn level_target(&self) -> f32 {
        if self.on && self.next == self.kind {
            1.0
        } else {
            0.0
        }
    }

    /// Whether processing the band would change nothing.
    fn idle(&self) -> bool {
        (self.level == 0.0 && self.level_target() == 0.0)
            || (self.kind.has_gain()
                && self.gain.value == 0.0
                && !self.gain.moving()
                && self.next == self.kind)
    }

    fn update(&mut self, sr: f32) {
        self.coefs = self.kind.stages(
            self.freq.value.exp2(),
            self.q.value.exp2(),
            self.gain.value,
            sr,
        );
    }
}

pub struct Eq {
    sr: f32,
    bands: [Band; BANDS],
    output: Smooth,
    /// Samples processed, for updating filters on a fixed grid whatever
    /// the block size.
    clock: u32,
    started: bool,
    /// Step of a band's level per sample.
    fade: f32,
    rest: dsp::Rest,
}

impl Eq {
    pub fn new(sr: f32) -> Self {
        // Settings glide with a 20 ms time constant, evaluated per update.
        let glide = 0.02 / UPDATE as f32;
        let bands = DEFAULTS.map(|(on, kind, freq, q)| {
            let mut b = Band {
                on,
                kind,
                next: kind,
                freq: Smooth::new(freq.log2(), glide, sr),
                gain: Smooth::new(0.0, glide, sr),
                q: Smooth::new(q.log2(), glide, sr),
                coefs: [None, None],
                state: Default::default(),
                level: if on { 1.0 } else { 0.0 },
            };
            b.update(sr);
            b
        });
        Self {
            sr,
            bands,
            output: Smooth::new(1.0, 0.02, sr),
            clock: 0,
            started: false,
            fade: 1.0 / (0.01 * sr),
            rest: dsp::Rest::default(),
        }
    }

    /// Glide the bands one step and refresh the filters that moved.
    fn update(&mut self) {
        for b in &mut self.bands {
            let moving = b.freq.moving() || b.gain.moving() || b.q.moving();
            if moving {
                b.freq.step();
                b.gain.step();
                b.q.step();
                b.update(self.sr);
            }
        }
    }
}

/// Frames an EQ waits, calm, before it lets go of what its filters still
/// hold and rests.
const EQ_MEMORY: u32 = 4096;

impl Eq {
    /// Whether every band and the output are where they glide to.
    fn settled(&self) -> bool {
        !self.output.moving()
            && self.bands.iter().all(|b| {
                b.next == b.kind
                    && b.level == b.level_target()
                    && !(b.freq.moving() || b.gain.moving() || b.q.moving())
            })
    }
}

impl Device for Eq {
    fn resting(&self) -> bool {
        self.rest.resting
    }

    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        if self.rest.sleeps(io) {
            return;
        }
        self.started = true;
        for (l, r) in io.left.iter_mut().zip(io.right.iter_mut()) {
            if self.rest.holds(*l, *r) {
                continue;
            }
            if self.clock.is_multiple_of(UPDATE) {
                self.update();
            }
            self.clock = self.clock.wrapping_add(1);
            let (mut x, mut y) = (*l, *r);
            for b in &mut self.bands {
                if b.idle() {
                    if b.kind == b.next {
                        b.level = b.level_target();
                    }
                    continue;
                }
                let (mut fl, mut fr) = (x, y);
                for (coefs, state) in b.coefs.iter().zip(&mut b.state) {
                    if let Some(c) = coefs {
                        fl = state[0].tick(c, fl);
                        fr = state[1].tick(c, fr);
                    }
                }
                // Fade toward on or off; once silent, take up the new type.
                let target = b.level_target();
                if b.level != target {
                    b.level = if b.level < target {
                        (b.level + self.fade).min(target)
                    } else {
                        (b.level - self.fade).max(target)
                    };
                    if b.level == 0.0 && b.next != b.kind {
                        b.kind = b.next;
                        b.state = Default::default();
                        b.update(self.sr);
                    }
                }
                if b.level == 1.0 {
                    (x, y) = (fl, fr);
                } else {
                    x += (fl - x) * b.level;
                    y += (fr - y) * b.level;
                }
            }
            let g = self.output.step();
            let calm = self.rest.frame(*l, *r, x.abs().max(y.abs()));
            *l = x * g;
            *r = y * g;
            if calm >= EQ_MEMORY && !self.rest.resting && self.settled() {
                for b in &mut self.bands {
                    b.state = Default::default();
                }
                self.rest.resting = true;
            }
        }
        for b in &mut self.bands {
            for stage in &mut b.state {
                stage[0].flush();
                stage[1].flush();
            }
        }
    }

    fn set_param(&mut self, index: u32, value: f32) {
        let index = index as usize;
        if !value.is_finite() {
            return;
        }
        self.rest.wake();
        if index == OUTPUT {
            self.output.target = dsp::db_to_lin(value.clamp(-24.0, 24.0));
            if !self.started {
                self.output.snap();
            }
            return;
        }
        let Some(b) = self.bands.get_mut(index / PER_BAND) else {
            return;
        };
        match index % PER_BAND {
            0 => b.on = value >= 0.5,
            1 => b.next = Kind::from_value(value),
            2 => b.freq.target = value.clamp(10.0, 24000.0).log2(),
            3 => b.gain.target = value.clamp(-30.0, 30.0),
            _ => b.q.target = value.clamp(0.025, 40.0).log2(),
        }
        if !self.started {
            b.freq.snap();
            b.gain.snap();
            b.q.snap();
            b.kind = b.next;
            b.level = b.level_target();
            b.update(self.sr);
        } else if b.level == 0.0 && b.next != b.kind {
            // Silent already: take the new type at once.
            b.kind = b.next;
            b.state = Default::default();
            b.update(self.sr);
        }
    }
}

/// The equaliser's response with these parameter values, at `freq` Hz, in dB.
pub fn response_db(values: &[f32], freq: f64, sr: f32) -> f64 {
    let mut power = 1.0f64;
    for b in 0..BANDS {
        let v = &values[b * PER_BAND..];
        if v[0] < 0.5 {
            continue;
        }
        let kind = Kind::from_value(v[1]);
        for c in kind.stages(v[2], v[4], v[3], sr).iter().flatten() {
            power *= c.power(freq, sr as f64);
        }
    }
    10.0 * power.max(1e-30).log10() + values[OUTPUT] as f64
}

struct EqFace {
    sr: f32,
}

impl Face for EqFace {
    /// `curve [n]`: the response in dB at `n` frequencies (default 128)
    /// spaced evenly on a log scale from 20 Hz to 20 kHz.
    /// `at <hz>`: the response at one frequency.
    fn call(&mut self, values: &[f32], method: &str, data: &[u8]) -> Result<Vec<u8>> {
        match method {
            "curve" => {
                let n = panel::count(data, 128, 4096);
                let points =
                    dsp::log_frequencies(n, 20.0, 20000.0).map(|f| response_db(values, f, self.sr));
                Ok(panel::numbers(points, 2))
            }
            "at" => {
                let f: f64 = std::str::from_utf8(data)?.trim().parse()?;
                Ok(panel::numbers([response_db(values, f, self.sr)], 3))
            }
            _ => anyhow::bail!("the equaliser answers `curve` and `at`, not `{method}`"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::devices::testkit::*;

    /// The response measured with a sine, in dB.
    fn measure(fx: &mut Fx, freq: f32) -> f64 {
        let sr = fx.sr;
        fx.reset();
        let n = (sr * 0.5) as usize;
        let input: Vec<f32> = (0..n)
            .map(|i| (std::f32::consts::TAU * freq * i as f32 / sr).sin() * 0.25)
            .collect();
        let (l, _) = fx.run_stereo(&input, &input, 256);
        let skip = n / 2;
        let e_in: f64 = input[skip..].iter().map(|x| (x * x) as f64).sum();
        let e_out: f64 = l[skip..].iter().map(|x| (x * x) as f64).sum();
        10.0 * (e_out / e_in).log10()
    }

    #[test]
    fn flat_by_default_and_bit_transparent() {
        for sr in [44100.0, 48000.0, 96000.0] {
            let mut fx = Fx::new("eq", sr);
            let noise = noise(4096, 1);
            let (l, r) = fx.run_stereo(&noise, &noise, 128);
            assert_eq!(
                l, noise,
                "a flat equaliser leaves the samples exactly as they were"
            );
            assert_eq!(r, noise);
        }
    }

    #[test]
    fn measured_response_matches_the_curve_it_reports() {
        for sr in [44100.0, 48000.0, 96000.0] {
            let mut fx = Fx::new("eq", sr);
            fx.set("b1_on", 1.0);
            fx.set("b1_type", Kind::LowCut24 as usize as f32);
            fx.set("b1_freq", 100.0);
            fx.set("b3_gain", 6.0);
            fx.set("b3_freq", 400.0);
            fx.set("b3_q", 2.0);
            fx.set("b5_gain", -9.0);
            fx.set("b5_freq", 3000.0);
            fx.set("b7_gain", 3.0);
            fx.set("b8_on", 1.0);
            fx.set("b8_type", Kind::HighCut12 as usize as f32);
            fx.set("b8_freq", 15000.0);
            fx.set("output", -2.0);
            let curve = fx.call_numbers("curve", "64");
            assert_eq!(curve.len(), 64);
            for f in [50.0, 100.0, 400.0, 1000.0, 3000.0, 8000.0, 12000.0, 16000.0] {
                let expected = response_db(&fx.values(), f as f64, sr);
                let measured = measure(&mut fx, f);
                assert!(
                    (measured - expected).abs() < 0.1,
                    "{sr} Hz rate, {f} Hz: measured {measured:.2} dB, the curve says {expected:.2}"
                );
            }
            // And the curve matches the textbook at the landmarks.
            let at = |f: f64| response_db(&fx.values(), f, sr);
            assert!(
                (at(100.0) - (-3.01 - 2.0)).abs() < 0.2,
                "a 24 dB low cut is -3 dB at its frequency"
            );
            assert!(at(25.0) < -45.0, "and falls 24 dB an octave: {}", at(25.0));
        }
    }

    #[test]
    fn a_bell_peaks_at_its_gain_and_a_notch_removes_its_frequency() {
        let mut fx = Fx::new("eq", 48000.0);
        fx.set("b4_gain", 12.0);
        fx.set("b4_freq", 1000.0);
        assert!((measure(&mut fx, 1000.0) - 12.0).abs() < 0.05);
        fx.set("b4_type", Kind::Notch as usize as f32);
        fx.settle();
        assert!(measure(&mut fx, 1000.0) < -40.0);
    }

    #[test]
    fn stable_at_the_top_of_the_range_and_at_high_q() {
        for sr in [44100.0, 48000.0, 96000.0] {
            let mut fx = Fx::new("eq", sr);
            for b in 1..=8 {
                fx.set(&format!("b{b}_on"), 1.0);
                fx.set(&format!("b{b}_freq"), 20000.0);
                fx.set(&format!("b{b}_q"), 18.0);
                fx.set(&format!("b{b}_gain"), 24.0);
                fx.set(&format!("b{b}_type"), (b % TYPES.len()) as f32);
            }
            let input = noise(sr as usize, 3);
            let (l, r) = fx.run_stereo(&input, &input, 64);
            // As loud as the response allows, and no louder: nothing runs away.
            let most = fx
                .call_numbers("curve", "2000")
                .into_iter()
                .fold(-200.0, f64::max);
            let bound = 10f64.powf(most / 20.0) as f32 * 0.5 * 8.0;
            assert!(
                l.iter().chain(&r).all(|x| x.is_finite() && x.abs() < bound),
                "bound {bound}"
            );
        }
    }

    #[test]
    fn moving_a_band_glides_without_clicks() {
        // A sine through a bell swept from 200 Hz to 5 kHz at once: the output
        // may change level but must not jump between neighbouring samples
        // more than the sine itself could.
        let sr = 48000.0;
        let mut fx = Fx::new("eq", sr);
        fx.set("b4_gain", 18.0);
        fx.set("b4_freq", 200.0);
        let input: Vec<f32> = (0..48000)
            .map(|i| (std::f32::consts::TAU * 1000.0 * i as f32 / sr).sin() * 0.1)
            .collect();
        let mut out = Vec::new();
        for (i, chunk) in input.chunks(480).enumerate() {
            if i == 20 {
                fx.set("b4_freq", 1000.0);
                fx.set("b4_type", Kind::HighShelf as usize as f32);
            }
            if i == 50 {
                fx.set("b4_on", 0.0);
            }
            let (l, _) = fx.run_stereo(chunk, chunk, 480);
            out.extend(l);
        }
        let max_step = out
            .windows(2)
            .map(|w| (w[1] - w[0]).abs())
            .fold(0.0, f32::max);
        // The sine at the bell's full 18 dB moves at most 2π·1000/48000·0.1·7.9.
        assert!(max_step < 0.11, "largest step {max_step}");
    }
}
