//! The filters of a band split: Linkwitz-Riley crossovers of 24 dB an
//! octave, and the allpass filters that line up the low bands with the
//! crossovers above them.
//!
//! A Linkwitz-Riley low pass of the fourth order is a Butterworth low pass
//! of the second order run twice, and so is the high pass. Their sum is a
//! second-order allpass at the same frequency, with `Q = 1/√2`. The
//! bilinear transform keeps that sum, so the digital bands also sum to an
//! allpass: a flat magnitude. A band below a further crossover goes
//! through that crossover's allpass, as the bands above it do, so that all
//! the bands sum flat.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]

use std::f64::consts::{FRAC_1_SQRT_2, PI};

/// The coefficients of a biquad, divided by `a0`.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Coefs {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
}

#[derive(Clone, Copy, Debug)]
enum Kind {
    Low,
    High,
    All,
}

impl Coefs {
    /// The filters of the cookbook of Robert Bristow-Johnson, which are the
    /// bilinear transform of the analog ones, prewarped at `freq`.
    fn new(kind: Kind, freq: f32, sample_rate: f32) -> Self {
        let nyquist = f64::from(sample_rate) * 0.5;
        let freq = f64::from(freq).clamp(1.0, nyquist * 0.99);
        let w0 = 2.0 * PI * freq / f64::from(sample_rate);
        let (sin, cos) = w0.sin_cos();
        let alpha = sin / (2.0 * FRAC_1_SQRT_2);
        let (b0, b1, b2) = match kind {
            Kind::Low => ((1.0 - cos) / 2.0, 1.0 - cos, (1.0 - cos) / 2.0),
            Kind::High => ((1.0 + cos) / 2.0, -(1.0 + cos), (1.0 + cos) / 2.0),
            Kind::All => (1.0 - alpha, -2.0 * cos, 1.0 + alpha),
        };
        let a0 = 1.0 + alpha;
        Self { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: -2.0 * cos / a0, a2: (1.0 - alpha) / a0 }
    }
}

/// The state of one biquad on one channel (transposed direct form II).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct State {
    z1: f64,
    z2: f64,
}

impl State {
    #[inline]
    fn tick(&mut self, c: &Coefs, x: f64) -> f64 {
        let y = c.b0 * x + self.z1;
        self.z1 = c.b1 * x - c.a1 * y + self.z2;
        self.z2 = c.b2 * x - c.a2 * y;
        y
    }
}

/// One crossover of a band split, for both channels.
#[derive(Clone, Debug)]
pub(crate) struct Crossover {
    low: Coefs,
    high: Coefs,
    /// Two stages for each channel, low and high.
    lows: [[State; 2]; 2],
    highs: [[State; 2]; 2],
}

impl Crossover {
    pub(crate) fn new(freq: f32, sample_rate: f32) -> Self {
        Self {
            low: Coefs::new(Kind::Low, freq, sample_rate),
            high: Coefs::new(Kind::High, freq, sample_rate),
            lows: Default::default(),
            highs: Default::default(),
        }
    }

    /// Put the low band of `rest` into `low`, and leave the high band in
    /// `rest`.
    pub(crate) fn split(&mut self, rest: [&mut [f32]; 2], low: [&mut [f32]; 2]) {
        for (ch, (rest, low)) in rest.into_iter().zip(low).enumerate() {
            let [l1, l2] = &mut self.lows[ch];
            let [h1, h2] = &mut self.highs[ch];
            for (r, l) in rest.iter_mut().zip(low.iter_mut()) {
                let x = f64::from(*r);
                *l = l2.tick(&self.low, l1.tick(&self.low, x)) as f32;
                *r = h2.tick(&self.high, h1.tick(&self.high, x)) as f32;
            }
        }
    }

    /// Go on from the state of `old`, at the new frequency.
    pub(crate) fn adopt(&mut self, old: &Crossover) {
        self.lows = old.lows;
        self.highs = old.highs;
    }
}

/// The allpass of a crossover, for a band below it.
#[derive(Clone, Debug)]
pub(crate) struct Allpass {
    coefs: Coefs,
    states: [State; 2],
}

impl Allpass {
    pub(crate) fn new(freq: f32, sample_rate: f32) -> Self {
        Self { coefs: Coefs::new(Kind::All, freq, sample_rate), states: Default::default() }
    }

    pub(crate) fn run(&mut self, buf: [&mut [f32]; 2]) {
        for (ch, buf) in buf.into_iter().enumerate() {
            let state = &mut self.states[ch];
            for s in buf.iter_mut() {
                *s = state.tick(&self.coefs, f64::from(*s)) as f32;
            }
        }
    }

    pub(crate) fn adopt(&mut self, old: &Allpass) {
        self.states = old.states;
    }
}
