//! Building blocks shared by the built-in effects: decibels, parameter
//! smoothing, the state-variable filter, delay lines, oversampling, LFOs and
//! a real FFT (`realfft`) for the main-thread analyses.
//!
//! Everything that runs on the audio thread here works on preallocated
//! memory: buffers are sized in `new`, which runs on the main thread.

use std::f64::consts::PI as PI64;
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering::Relaxed};

use atomic_float::AtomicF32;

/// Decibels to linear gain, for any finite input (no floor).
#[inline]
pub fn db_to_lin(db: f32) -> f32 {
    (db * (std::f32::consts::LN_10 / 20.0)).exp()
}

/// Linear gain to decibels, floored at -200 dB so silence stays finite.
#[inline]
pub fn lin_to_db(x: f32) -> f32 {
    20.0 * x.max(1e-10).log10()
}

/// `exp(-1 / (seconds * rate))`: the coefficient of a one-pole smoother
/// that covers 63 % of the way to its target in `seconds`.
#[inline]
pub fn time_coef(seconds: f32, sample_rate: f32) -> f32 {
    let frames = seconds * sample_rate;
    if frames.is_finite() && frames > 1e-3 {
        (-1.0 / frames).exp()
    } else {
        0.0
    }
}

/// A value that glides to its target, so that a parameter change does not
/// click: a one-pole low-pass with a fixed time constant.
#[derive(Clone, Copy, Debug)]
pub struct Smooth {
    pub value: f32,
    pub target: f32,
    coef: f32,
}

impl Smooth {
    pub fn new(value: f32, seconds: f32, sample_rate: f32) -> Self {
        Self {
            value,
            target: value,
            coef: time_coef(seconds, sample_rate),
        }
    }

    #[inline]
    pub fn step(&mut self) -> f32 {
        self.value = self.target + (self.value - self.target) * self.coef;
        if (self.value - self.target).abs() <= 1e-6 * self.target.abs().max(1e-3) {
            self.value = self.target;
        }
        self.value
    }

    /// Jump to the target at once.
    pub fn snap(&mut self) {
        self.value = self.target;
    }

    pub fn moving(&self) -> bool {
        self.value != self.target
    }
}

/// What a [`Svf`] lets through. `Band` peaks at unity.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Shape {
    Low,
    High,
    Band,
    Notch,
    Bell,
    LowShelf,
    HighShelf,
    AllPass,
}

/// Coefficients of the state-variable filter (Andrew Simper's linear
/// trapezoidal SVF). It stays stable at any frequency below Nyquist and any
/// Q, and tolerates its coefficients changing every sample.
///
/// The output is `m0·input + m1·band + m2·low`, where for the normalised
/// analogue prototype `band = s/(s² + k·s + 1)` and `low = 1/(s² + k·s + 1)`,
/// mapped to the sample rate by the bilinear transform with the frequency
/// prewarped; [`response`](Self::response) evaluates exactly that.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct SvfCoefs {
    pub g: f32,
    pub k: f32,
    a1: f32,
    a2: f32,
    a3: f32,
    pub m0: f32,
    pub m1: f32,
    pub m2: f32,
}

impl SvfCoefs {
    /// `freq` in Hz (kept below Nyquist), `q` above 0, `gain_db` for the
    /// bell and the shelves.
    pub fn new(shape: Shape, freq: f32, q: f32, gain_db: f32, sample_rate: f32) -> Self {
        let freq = freq.clamp(1.0, sample_rate * 0.49);
        let q = q.clamp(0.025, 100.0);
        let base = (std::f64::consts::PI * freq as f64 / sample_rate as f64).tan() as f32;
        // A is the square root of the linear gain.
        let a = db_to_lin(gain_db.clamp(-60.0, 60.0) * 0.5);
        let k = 1.0 / q;
        let (g, k, m0, m1, m2) = match shape {
            Shape::Low => (base, k, 0.0, 0.0, 1.0),
            Shape::High => (base, k, 1.0, -k, -1.0),
            Shape::Band => (base, k, 0.0, k, 0.0),
            Shape::Notch => (base, k, 1.0, -k, 0.0),
            Shape::AllPass => (base, k, 1.0, -2.0 * k, 0.0),
            Shape::Bell => {
                let k = 1.0 / (q * a);
                (base, k, 1.0, k * (a * a - 1.0), 0.0)
            }
            Shape::LowShelf => (base / a.sqrt(), k, 1.0, k * (a - 1.0), a * a - 1.0),
            Shape::HighShelf => (base * a.sqrt(), k, a * a, k * (1.0 - a) * a, 1.0 - a * a),
        };
        let a1 = 1.0 / (1.0 + g * (g + k));
        let a2 = g * a1;
        let a3 = g * a2;
        Self {
            g,
            k,
            a1,
            a2,
            a3,
            m0,
            m1,
            m2,
        }
    }

    /// The filter's complex response at `freq` Hz, as (re, im).
    pub fn response(&self, freq: f64, sample_rate: f64) -> (f64, f64) {
        let w = (PI64 * (freq / sample_rate).min(0.4999)).tan() / self.g as f64;
        // s = j·w; den = s² + k·s + 1 = (1 - w²) + j·k·w
        let k = self.k as f64;
        let (dr, di) = (1.0 - w * w, k * w);
        let d2 = dr * dr + di * di;
        // band = j·w / den; low = 1 / den
        let (lr, li) = (dr / d2, -di / d2);
        let (br, bi) = (-w * li, w * lr);
        (
            self.m0 as f64 + self.m1 as f64 * br + self.m2 as f64 * lr,
            self.m1 as f64 * bi + self.m2 as f64 * li,
        )
    }

    /// The magnitude of [`response`](Self::response), squared.
    pub fn power(&self, freq: f64, sample_rate: f64) -> f64 {
        let (re, im) = self.response(freq, sample_rate);
        re * re + im * im
    }
}

/// The state of one channel of a state-variable filter.
#[derive(Clone, Copy, Debug, Default)]
pub struct Svf {
    ic1: f32,
    ic2: f32,
}

impl Svf {
    #[inline]
    pub fn tick(&mut self, c: &SvfCoefs, v0: f32) -> f32 {
        let v3 = v0 - self.ic2;
        let v1 = c.a1 * self.ic1 + c.a2 * v3;
        let v2 = self.ic2 + c.a2 * self.ic1 + c.a3 * v3;
        self.ic1 = 2.0 * v1 - self.ic1;
        self.ic2 = 2.0 * v2 - self.ic2;
        c.m0 * v0 + c.m1 * v1 + c.m2 * v2
    }

    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// Zero a state that has decayed to nothing, so that it never becomes
    /// a denormal number on a processor that does not flush those itself.
    pub fn flush(&mut self) {
        self.ic1 = flush(self.ic1);
        self.ic2 = flush(self.ic2);
    }

    /// True when it holds nothing of what it was given.
    pub fn is_zero(&self) -> bool {
        self.ic1 == 0.0 && self.ic2 == 0.0
    }
}

/// What an effect still rings at, below which it is silence (-120 dB): it
/// may then clear what it holds and go to sleep (see [`Rest`]).
pub const REST_LEVEL: f32 = 1e-6;

/// When an effect may go to sleep (see [`crate::Device::resting`]). It
/// counts the frames in a row that went in silent and left what the effect
/// holds below [`REST_LEVEL`]; once that has lasted as long as the effect
/// remembers, the effect clears what it holds and rests. Resting, it returns
/// at once from a silent block, so that it is the same whether the host calls
/// it or not, until a block that is not silent or a new setting wakes it.
#[derive(Clone, Copy, Debug, Default)]
pub struct Rest {
    calm: u32,
    pub resting: bool,
}

impl Rest {
    /// Count one frame of input and the loudest of what the effect holds
    /// after it; the frames in a row that were calm.
    #[inline(always)]
    pub fn frame(&mut self, l: f32, r: f32, level: f32) -> u32 {
        let calm = l == 0.0 && r == 0.0 && level < REST_LEVEL;
        if calm {
            self.calm = self.calm.saturating_add(1);
        } else {
            // Sound later in the block that put it to rest.
            self.calm = 0;
            self.resting = false;
        }
        self.calm
    }

    /// Whether a block goes by without the effect: it rests, and the block
    /// is silent. A block that is not wakes it.
    #[inline]
    pub fn sleeps(&mut self, io: &crate::device::Io) -> bool {
        if self.resting && crate::device::quiet(io) {
            return true;
        }
        self.resting = false;
        false
    }

    /// A new setting: the effect works again until it is calm once more.
    pub fn wake(&mut self) {
        self.resting = false;
    }
}

/// Zero for anything too small to hear (below -400 dB).
#[inline]
pub fn flush(x: f32) -> f32 {
    if x.abs() < 1e-20 { 0.0 } else { x }
}

/// A first-order filter: low-pass, high-pass or a DC blocker.
#[derive(Clone, Copy, Debug, Default)]
pub struct OnePole {
    /// Low-pass state.
    z: f32,
    a: f32,
}

impl OnePole {
    /// Cutoff `freq` Hz (matched by the impulse-invariant mapping).
    pub fn new(freq: f32, sample_rate: f32) -> Self {
        let mut f = Self::default();
        f.set(freq, sample_rate);
        f
    }

    pub fn set(&mut self, freq: f32, sample_rate: f32) {
        let x = (-std::f32::consts::TAU * freq.clamp(0.0, sample_rate * 0.49) / sample_rate).exp();
        self.a = 1.0 - x;
    }

    /// Let everything through the low-pass (and nothing through the high-pass).
    pub fn open(&mut self) {
        self.a = 1.0;
    }

    pub fn flush(&mut self) {
        self.z = flush(self.z);
    }

    #[inline]
    pub fn low(&mut self, x: f32) -> f32 {
        self.z += self.a * (x - self.z);
        self.z
    }

    #[inline]
    pub fn high(&mut self, x: f32) -> f32 {
        x - self.low(x)
    }

    pub fn reset(&mut self) {
        self.z = 0.0;
    }
}

/// A circular buffer of samples, its length a power of two.
#[derive(Clone, Debug)]
pub struct DelayLine {
    buf: Vec<f32>,
    mask: usize,
    write: usize,
}

impl DelayLine {
    /// Room for at least `frames` of delay.
    pub fn new(frames: usize) -> Self {
        let len = (frames + 4).next_power_of_two();
        Self {
            buf: vec![0.0; len],
            mask: len - 1,
            write: 0,
        }
    }

    /// The longest delay it holds.
    pub fn capacity(&self) -> usize {
        self.buf.len() - 4
    }

    #[inline]
    pub fn push(&mut self, x: f32) {
        self.write = (self.write + 1) & self.mask;
        self.buf[self.write] = x;
    }

    /// The sample pushed `delay` pushes ago (0 is the latest).
    #[inline]
    pub fn get(&self, delay: usize) -> f32 {
        self.buf[(self.write.wrapping_sub(delay)) & self.mask]
    }

    /// A fractional delay, interpolated with a cubic (Hermite) curve.
    #[inline]
    pub fn get_frac(&self, delay: f32) -> f32 {
        let delay = delay.clamp(1.0, (self.buf.len() - 3) as f32);
        let whole = delay as usize;
        let t = delay - whole as f32;
        let ym1 = self.get(whole - 1);
        let y0 = self.get(whole);
        let y1 = self.get(whole + 1);
        let y2 = self.get(whole + 2);
        let c1 = 0.5 * (y1 - ym1);
        let c2 = ym1 - 2.5 * y0 + 2.0 * y1 - 0.5 * y2;
        let c3 = 0.5 * (y2 - ym1) + 1.5 * (y0 - y1);
        ((c3 * t + c2) * t + c1) * t + y0
    }

    pub fn clear(&mut self) {
        self.buf.fill(0.0);
    }
}

/// A windowed-sinc low-pass FIR, normalised to unity gain at DC.
/// `cutoff` is a fraction of the sample rate, `len` is odd.
pub fn sinc_lowpass(len: usize, cutoff: f64, beta: f64) -> Vec<f64> {
    let mid = (len - 1) as f64 / 2.0;
    let mut taps: Vec<f64> = (0..len)
        .map(|i| {
            let x = i as f64 - mid;
            let sinc = if x == 0.0 {
                2.0 * cutoff
            } else {
                (2.0 * PI64 * cutoff * x).sin() / (PI64 * x)
            };
            sinc * kaiser(x / mid.max(1.0), beta)
        })
        .collect();
    let sum: f64 = taps.iter().sum();
    for t in &mut taps {
        *t /= sum;
    }
    taps
}

/// The Kaiser window at `x` in -1..1.
fn kaiser(x: f64, beta: f64) -> f64 {
    bessel_i0(beta * (1.0 - x * x).max(0.0).sqrt()) / bessel_i0(beta)
}

fn bessel_i0(x: f64) -> f64 {
    let mut sum = 1.0;
    let mut term = 1.0;
    let half = x / 2.0;
    for k in 1..50 {
        term *= half / k as f64;
        sum += term * term;
        if term * term < 1e-20 * sum {
            break;
        }
    }
    sum
}

/// Polyphase interpolation by an integer factor: each input sample gives
/// `factor` output samples, band-limited to the input's Nyquist frequency.
/// The output is `latency()` input samples behind.
#[derive(Clone, Debug)]
pub struct Upsampler {
    /// `phases[p][i]`: tap `i` of phase `p`, scaled by the factor.
    phases: Vec<Vec<f32>>,
    history: Vec<f32>,
    pos: usize,
    taps: usize,
}

impl Upsampler {
    /// `taps_per_phase` input samples of history per output, cut off a
    /// little below the input's Nyquist frequency.
    pub fn new(factor: usize, taps_per_phase: usize) -> Self {
        Self::design(factor, taps_per_phase, 0.94, 9.0)
    }

    /// With the cutoff as a fraction of the input's Nyquist frequency, and
    /// the Kaiser window's beta (higher: less ripple, a wider transition).
    pub fn design(factor: usize, taps_per_phase: usize, cutoff: f64, beta: f64) -> Self {
        let len = factor * taps_per_phase - 1;
        let proto = sinc_lowpass(len, 0.5 / factor as f64 * cutoff, beta);
        // Each phase on its own passes DC at unity.
        let phases = (0..factor)
            .map(|p| {
                let taps: Vec<f64> = (0..taps_per_phase)
                    .map(|i| proto.get(i * factor + p).copied().unwrap_or(0.0))
                    .collect();
                let sum: f64 = taps.iter().sum();
                taps.iter().map(|t| (t / sum) as f32).collect()
            })
            .collect();
        Self {
            phases,
            history: vec![0.0; taps_per_phase * 2],
            pos: 0,
            taps: taps_per_phase,
        }
    }

    pub fn factor(&self) -> usize {
        self.phases.len()
    }

    /// Delay in input samples of the output relative to the input, times
    /// the factor (so that it is a whole number of output samples).
    pub fn latency_out(&self) -> usize {
        (self.factor() * self.taps - 2) / 2
    }

    /// Push one input sample and write `factor` outputs.
    #[inline]
    pub fn process(&mut self, x: f32, out: &mut [f32]) {
        // The history is kept twice over so that a window never wraps.
        let n = self.taps;
        self.pos = if self.pos == 0 { n - 1 } else { self.pos - 1 };
        self.history[self.pos] = x;
        self.history[self.pos + n] = x;
        let h = &self.history[self.pos..self.pos + n];
        for (o, taps) in out.iter_mut().zip(&self.phases) {
            let mut acc = 0.0;
            for (a, b) in h.iter().zip(taps) {
                acc += a * b;
            }
            *o = acc;
        }
    }

    pub fn reset(&mut self) {
        self.history.fill(0.0);
    }
}

/// Decimation by an integer factor through a band-limiting FIR.
#[derive(Clone, Debug)]
pub struct Downsampler {
    taps: Vec<f32>,
    history: Vec<f32>,
    pos: usize,
    factor: usize,
}

impl Downsampler {
    /// Paired with an [`Upsampler`] of the same factor and taps, the round
    /// trip is exactly `taps_per_phase - 1` low-rate samples late.
    pub fn new(factor: usize, taps_per_phase: usize) -> Self {
        Self::design(factor, taps_per_phase, 0.94, 9.0)
    }

    /// As [`Upsampler::design`].
    pub fn design(factor: usize, taps_per_phase: usize, cutoff: f64, beta: f64) -> Self {
        let len = factor * taps_per_phase + 1;
        let taps = sinc_lowpass(len, 0.5 / factor as f64 * cutoff, beta)
            .into_iter()
            .map(|t| t as f32)
            .collect::<Vec<_>>();
        Self {
            history: vec![0.0; taps.len() * 2],
            taps,
            pos: 0,
            factor,
        }
    }

    /// Delay, in samples at the high rate.
    pub fn latency_in(&self) -> usize {
        (self.taps.len() - 1) / 2
    }

    /// Take `factor` samples at the high rate, give one at the low rate.
    #[inline]
    pub fn process(&mut self, input: &[f32]) -> f32 {
        let n = self.taps.len();
        for &x in &input[..self.factor] {
            self.pos = if self.pos == 0 { n - 1 } else { self.pos - 1 };
            self.history[self.pos] = x;
            self.history[self.pos + n] = x;
        }
        let h = &self.history[self.pos..self.pos + n];
        let mut acc = 0.0;
        for (a, b) in h.iter().zip(&self.taps) {
            acc += a * b;
        }
        acc
    }

    pub fn reset(&mut self) {
        self.history.fill(0.0);
    }
}

/// Note lengths a tempo-synced time can take, in beats (quarter notes):
/// the names are shown, the values used.
pub const NOTE_NAMES: &[&str] = &[
    "1/64", "1/32T", "1/32", "1/16T", "1/32.", "1/16", "1/8T", "1/16.", "1/8", "1/4T", "1/8.",
    "1/4", "1/2T", "1/4.", "1/2", "1/1T", "1/2.", "1/1", "1/1.", "2/1", "4/1",
];

pub const NOTE_BEATS: &[f64] = &[
    1.0 / 16.0,
    1.0 / 12.0,
    1.0 / 8.0,
    1.0 / 6.0,
    3.0 / 16.0,
    1.0 / 4.0,
    1.0 / 3.0,
    3.0 / 8.0,
    1.0 / 2.0,
    2.0 / 3.0,
    3.0 / 4.0,
    1.0,
    4.0 / 3.0,
    3.0 / 2.0,
    2.0,
    8.0 / 3.0,
    3.0,
    4.0,
    6.0,
    8.0,
    16.0,
];

/// The choices of a "sync" parameter: off, then the note lengths.
pub fn sync_choices() -> Vec<&'static str> {
    let mut out = vec!["Off"];
    out.extend_from_slice(NOTE_NAMES);
    out
}

/// Seconds of a sync choice (1 = the first note length) at `tempo`, or
/// None when the choice is 0, off.
pub fn sync_seconds(choice: f32, tempo: f64) -> Option<f32> {
    let index = choice.round() as usize;
    if index == 0 || !choice.is_finite() {
        return None;
    }
    let beats = NOTE_BEATS[(index - 1).min(NOTE_BEATS.len() - 1)];
    let tempo = if tempo.is_finite() && tempo > 1.0 {
        tempo
    } else {
        120.0
    };
    Some((beats * 60.0 / tempo) as f32)
}

/// A sine LFO: a phase from 0 to 1.
#[derive(Clone, Copy, Debug, Default)]
pub struct Lfo {
    pub phase: f64,
}

impl Lfo {
    /// Advance by `step` cycles and return the phase before the step.
    #[inline]
    pub fn tick(&mut self, step: f64) -> f64 {
        let p = self.phase;
        self.phase += step;
        if self.phase >= 1.0 {
            self.phase -= self.phase.floor();
        }
        p
    }
}

/// The sine of a phase in cycles, to within 1e-7: what an LFO needs, for a
/// fraction of the cost of the maths library's, which is called for every
/// sample of every LFO.
#[inline]
pub fn sin_cycles(phase: f64) -> f32 {
    // Into -0.5..0.5 by whole cycles (truncating through an integer, which
    // is one instruction), then into -0.25..0.25 by the sine's symmetry
    // about a quarter cycle.
    let mut x = phase - (phase as i64) as f64;
    if x >= 0.5 {
        x -= 1.0;
    } else if x < -0.5 {
        x += 1.0;
    }
    if x > 0.25 {
        x = 0.5 - x;
    } else if x < -0.25 {
        x = -0.5 - x;
    }
    // The Taylor series to the 13th power: within 6e-8 up to a quarter cycle.
    let t = x * std::f64::consts::TAU;
    let t2 = t * t;
    let p = 1.0 / 6227020800.0;
    let p = p * t2 - 1.0 / 39916800.0;
    let p = p * t2 + 1.0 / 362880.0;
    let p = p * t2 - 1.0 / 5040.0;
    let p = p * t2 + 1.0 / 120.0;
    let p = p * t2 - 1.0 / 6.0;
    (t + t * t2 * p) as f32
}

/// Recent audio, written by the audio thread and copied by the main thread
/// for analyses that would be too slow to run while processing (spectrum,
/// pitch). Torn reads are possible and harmless for those.
pub struct Tap {
    data: Box<[AtomicF32]>,
    write: AtomicUsize,
}

impl Tap {
    pub fn new(len: usize) -> Arc<Self> {
        let len = len.next_power_of_two();
        Arc::new(Self {
            data: (0..len).map(|_| AtomicF32::new(0.0)).collect(),
            write: AtomicUsize::new(0),
        })
    }

    pub fn capacity(&self) -> usize {
        self.data.len()
    }

    /// Append samples (audio thread).
    pub fn write(&self, samples: impl Iterator<Item = f32>) {
        let mask = self.data.len() - 1;
        let mut at = self.write.load(Relaxed);
        for x in samples {
            self.data[at & mask].store(x, Relaxed);
            at = at.wrapping_add(1);
        }
        self.write.store(at, Relaxed);
    }

    /// The latest `out.len()` samples, oldest first (main thread).
    pub fn read(&self, out: &mut [f32]) {
        let mask = self.data.len() - 1;
        let end = self.write.load(Relaxed);
        let n = out.len().min(self.data.len());
        for (i, o) in out[..n].iter_mut().enumerate() {
            let at = end.wrapping_sub(n).wrapping_add(i);
            *o = self.data[at & mask].load(Relaxed);
        }
    }

    /// How many samples have been written in all (wrapping).
    pub fn written(&self) -> usize {
        self.write.load(Relaxed)
    }
}

/// Numbers the audio thread publishes for meters, each an atomic f32.
pub struct Readings<const N: usize> {
    values: [AtomicF32; N],
}

impl<const N: usize> Readings<N> {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            values: std::array::from_fn(|_| AtomicF32::new(0.0)),
        })
    }

    #[inline]
    pub fn set(&self, index: usize, value: f32) {
        self.values[index].store(value, Relaxed);
    }

    pub fn get(&self, index: usize) -> f32 {
        self.values[index].load(Relaxed)
    }
}

/// The spectrum of the real signal `x`: `x.len() / 2 + 1` bins, unnormalized.
///
/// This plans and allocates, so it is for the main thread (analyses a
/// script asks for), never for a device's `process`.
pub fn rfft(x: &[f64]) -> Vec<realfft::num_complex::Complex<f64>> {
    let plan = realfft::RealFftPlanner::<f64>::new().plan_fft_forward(x.len());
    let mut input = x.to_vec();
    let mut out = plan.make_output_vec();
    plan.process(&mut input, &mut out).expect("lengths match the plan");
    out
}

/// `n` frequencies spaced evenly on a log scale from `lo` to `hi` Hz.
pub fn log_frequencies(n: usize, lo: f64, hi: f64) -> impl Iterator<Item = f64> {
    let n = n.max(2);
    (0..n).map(move |i| lo * (hi / lo).powf(i as f64 / (n - 1) as f64))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn svf_shapes_match_their_textbook_values() {
        let sr = 48000.0;
        let lp = SvfCoefs::new(Shape::Low, 1000.0, std::f32::consts::FRAC_1_SQRT_2, 0.0, sr);
        let db = |c: &SvfCoefs, f| 10.0 * c.power(f, sr as f64).log10();
        assert!(
            (db(&lp, 1000.0) + 3.0103).abs() < 0.01,
            "Butterworth low-pass is -3 dB at its cutoff"
        );
        assert!(db(&lp, 10.0).abs() < 0.001);
        let bell = SvfCoefs::new(Shape::Bell, 2000.0, 1.0, 6.0, sr);
        assert!(
            (db(&bell, 2000.0) - 6.0).abs() < 0.001,
            "a bell has its gain at its centre"
        );
        let shelf = SvfCoefs::new(Shape::LowShelf, 200.0, 0.707, -9.0, sr);
        assert!(
            (db(&shelf, 10.0) + 9.0).abs() < 0.05,
            "a low shelf has its gain far below"
        );
        assert!(db(&shelf, 10000.0).abs() < 0.05);
        assert!(
            (db(&shelf, 200.0) + 4.5).abs() < 0.05,
            "and half of it at its corner"
        );
        let high = SvfCoefs::new(Shape::HighShelf, 5000.0, 0.707, 4.0, sr);
        assert!((db(&high, 20000.0) - 4.0).abs() < 0.2);
        assert!((db(&high, 5000.0) - 2.0).abs() < 0.05);
    }

    #[test]
    fn the_filter_does_what_its_response_says() {
        // Measure with sines and compare with the analytic curve.
        let sr = 44100.0;
        for shape in [
            Shape::Bell,
            Shape::High,
            Shape::LowShelf,
            Shape::HighShelf,
            Shape::Notch,
        ] {
            let c = SvfCoefs::new(shape, 3000.0, 2.0, -7.0, sr);
            for f in [100.0, 1000.0, 2900.0, 8000.0, 18000.0] {
                let mut s = Svf::default();
                let (mut e_in, mut e_out) = (0.0f64, 0.0f64);
                for i in 0..20000 {
                    let x = (std::f64::consts::TAU * f * i as f64 / sr as f64).sin() as f32;
                    let y = s.tick(&c, x);
                    if i >= 10000 {
                        e_in += (x * x) as f64;
                        e_out += (y * y) as f64;
                    }
                }
                let measured = 10.0 * (e_out / e_in).log10();
                let expected = 10.0 * c.power(f, sr as f64).log10();
                let tolerance = if expected < -30.0 { 1.0 } else { 0.05 };
                assert!(
                    (measured - expected).abs() < tolerance,
                    "{shape:?} at {f} Hz: measured {measured:.3} dB, expected {expected:.3}"
                );
            }
        }
    }

    #[test]
    fn up_and_down_sampling_pass_the_audio_band_unchanged() {
        let mut up = Upsampler::new(4, 16);
        let mut down = Downsampler::new(4, 16);
        let latency = 15;
        let mut buf = [0.0f32; 4];
        let mut out = Vec::new();
        let input: Vec<f32> = (0..4000)
            .map(|i| (std::f32::consts::TAU * 1000.0 * i as f32 / 48000.0).sin() * 0.5)
            .collect();
        for &x in &input {
            up.process(x, &mut buf);
            out.push(down.process(&buf));
        }
        let mut err = 0.0f32;
        for i in 1000..3000 {
            err = err.max((out[i + latency] - input[i]).abs());
        }
        assert!(err < 0.01, "round trip error {err}");
    }

    #[test]
    fn rfft_finds_a_sine() {
        let n = 1024;
        let x: Vec<f64> = (0..n)
            .map(|i| (std::f64::consts::TAU * 37.0 * i as f64 / n as f64).cos())
            .collect();
        let spectrum = rfft(&x);
        assert!((spectrum[37].norm() - n as f64 / 2.0).abs() < 1e-6);
        assert!(spectrum[36].norm() < 1e-6);
    }

    #[test]
    fn the_lfo_sine_is_the_sine() {
        let mut worst = 0.0f64;
        for i in -200_000..200_000 {
            let phase = i as f64 * 0.000_137_3;
            let want = (phase * std::f64::consts::TAU).sin();
            worst = worst.max((sin_cycles(phase) as f64 - want).abs());
        }
        for phase in [0.0, 0.25, 0.5, 0.75, 1.0, -0.25, 1e6 + 0.25] {
            let want = (phase * std::f64::consts::TAU).sin();
            worst = worst.max((sin_cycles(phase) as f64 - want).abs());
        }
        assert!(worst < 1e-7, "off by {worst}");
    }
}
