//! Devices that measure and pass the audio through untouched: a loudness
//! meter and a tuner.
//!
//! The meter follows EBU R 128 / ITU-R BS.1770-4: K-weighting (a high shelf
//! and a high-pass, designed for the sample rate), momentary (400 ms) and
//! short-term (3 s) loudness, integrated loudness over gating blocks of
//! 400 ms every 100 ms with the absolute gate at -70 LUFS and the relative
//! gate 10 LU below, kept in a histogram of 0.1 LU bins so that nothing
//! grows while measuring. Also the true peak (four times over), the sample
//! peak, RMS per channel and the correlation of the two channels over the
//! last 300 ms. The spectrum and the tuner's pitch are worked out on the
//! main thread when asked, from recent audio the device copies out.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::float_cmp, reason = "debt: pay down"))]

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering::Relaxed};

use anyhow::Result;

use paw_measure::bs1770::{Biquad, k_weighting, lufs};

use super::dsp::{self, Readings, Tap, Upsampler};
use super::panel::{self, Face, Pair};
use crate::device::{Device, Io, ParamInfo, ProcessCtx};

/// 100 ms pieces kept: 3 s for the short-term loudness.
const PIECES: usize = 30;
/// Histogram of gating blocks: 0.1 LU bins from -70 to +10 LUFS.
const BINS: usize = 800;
const BIN_FLOOR: f64 = -70.0;

const MOMENTARY: usize = 0;
const SHORT: usize = 1;
const INTEGRATED: usize = 2;
const TRUE_PEAK: usize = 3;
const SAMPLE_PEAK: usize = 4;
const RMS_L: usize = 5;
const RMS_R: usize = 6;
const CORRELATION: usize = 7;
const NAMES: [&str; 8] = [
    "momentary",
    "short_term",
    "integrated",
    "true_peak",
    "sample_peak",
    "rms_l",
    "rms_r",
    "correlation",
];

/// What one 100 ms piece adds up.
#[derive(Clone, Copy, Default)]
struct Piece {
    /// K-weighted mean square, both channels summed.
    weighted: f64,
    /// Plain sums of squares and of the product of the channels.
    ll: f64,
    rr: f64,
    lr: f64,
}

pub fn meter_params() -> Vec<ParamInfo> {
    // Nothing to set: what it reads is asked for with `meters`.
    vec![ParamInfo::choice("hold", &["Always", "3 s"], 0).name("Peak hold")]
}

pub fn meter(sr: f32) -> Pair {
    let readings = Readings::new();
    let tap = Tap::new(8192);
    let reset = Arc::new(AtomicBool::new(false));
    (
        Box::new(Meter::new(sr, readings.clone(), tap.clone(), reset.clone())),
        Box::new(MeterFace {
            sr,
            readings,
            tap,
            reset,
        }),
    )
}

pub struct Meter {
    hold_3s: bool,
    k: [[Biquad; 2]; 2],
    up: [Upsampler; 2],
    piece_len: usize,
    filled: usize,
    current: Piece,
    pieces: [Piece; PIECES],
    at: usize,
    count: usize,
    hist_n: Box<[u32; BINS]>,
    hist_e: Box<[f64; BINS]>,
    true_peak: f32,
    sample_peak: f32,
    /// Pieces since the peaks were last held, for the 3 s hold.
    since_peak: usize,
    readings: Arc<Readings<8>>,
    tap: Arc<Tap>,
    reset: Arc<AtomicBool>,
}

impl Meter {
    fn new(sr: f32, readings: Arc<Readings<8>>, tap: Arc<Tap>, reset: Arc<AtomicBool>) -> Self {
        let k = k_weighting(sr as f64);
        let m = Self {
            hold_3s: false,
            k: [k, k],
            up: [
                Upsampler::design(4, 24, 1.0, 7.0),
                Upsampler::design(4, 24, 1.0, 7.0),
            ],
            piece_len: ((sr as f64 * 0.1).round() as usize).max(1),
            filled: 0,
            current: Piece::default(),
            pieces: [Piece::default(); PIECES],
            at: 0,
            count: 0,
            hist_n: Box::new([0; BINS]),
            hist_e: Box::new([0.0; BINS]),
            true_peak: 0.0,
            sample_peak: 0.0,
            since_peak: 0,
            readings,
            tap,
            reset,
        };
        m.publish_empty();
        m
    }

    fn publish_empty(&self) {
        for i in [
            MOMENTARY,
            SHORT,
            INTEGRATED,
            TRUE_PEAK,
            SAMPLE_PEAK,
            RMS_L,
            RMS_R,
        ] {
            self.readings.set(i, f32::NEG_INFINITY);
        }
        self.readings.set(CORRELATION, 0.0);
    }

    fn clear(&mut self) {
        self.pieces = [Piece::default(); PIECES];
        self.current = Piece::default();
        self.filled = 0;
        self.count = 0;
        self.hist_n.fill(0);
        self.hist_e.fill(0.0);
        self.true_peak = 0.0;
        self.sample_peak = 0.0;
        self.publish_empty();
    }

    /// Mean of the last `n` pieces' weighted power.
    fn mean(&self, n: usize) -> f64 {
        let n = n.min(self.count);
        if n == 0 {
            return 0.0;
        }
        let mut sum = 0.0;
        for i in 0..n {
            sum += self.pieces[(self.at + PIECES - 1 - i) % PIECES].weighted;
        }
        sum / n as f64
    }

    /// A 100 ms piece is complete: update everything that reads in pieces.
    fn finish_piece(&mut self) {
        let len = self.piece_len as f64;
        let mut piece = self.current;
        piece.weighted /= len;
        self.pieces[self.at] = piece;
        self.at = (self.at + 1) % PIECES;
        self.count = (self.count + 1).min(PIECES);
        self.current = Piece::default();
        self.filled = 0;

        let momentary = self.mean(4);
        if self.count >= 4 {
            // A gating block: the 400 ms that just ended.
            let loudness = lufs(momentary);
            if loudness > BIN_FLOOR {
                let bin = (((loudness - BIN_FLOOR) * 10.0) as usize).min(BINS - 1);
                self.hist_n[bin] += 1;
                self.hist_e[bin] += momentary;
            }
        }
        self.readings.set(MOMENTARY, lufs(momentary) as f32);
        self.readings.set(SHORT, lufs(self.mean(PIECES)) as f32);
        self.readings.set(INTEGRATED, self.integrated() as f32);

        let (mut ll, mut rr, mut lr) = (0.0, 0.0, 0.0);
        for i in 0..3.min(self.count) {
            let p = &self.pieces[(self.at + PIECES - 1 - i) % PIECES];
            ll += p.ll;
            rr += p.rr;
            lr += p.lr;
        }
        let n = 3.min(self.count) as f64 * len;
        let db = |e: f64| 10.0 * (e / n).max(1e-20).log10();
        self.readings.set(RMS_L, db(ll) as f32);
        self.readings.set(RMS_R, db(rr) as f32);
        let corr = if ll > 1e-12 && rr > 1e-12 {
            lr / (ll * rr).sqrt()
        } else {
            0.0
        };
        self.readings.set(CORRELATION, corr as f32);
        self.readings
            .set(TRUE_PEAK, dsp::lin_to_db(self.true_peak).max(-200.0));
        self.readings
            .set(SAMPLE_PEAK, dsp::lin_to_db(self.sample_peak).max(-200.0));
        self.since_peak += 1;
        if self.hold_3s && self.since_peak >= PIECES {
            self.true_peak = 0.0;
            self.sample_peak = 0.0;
            self.since_peak = 0;
        }
    }

    /// Integrated loudness from the histogram: the blocks above -70 LUFS,
    /// then those within 10 LU of their mean.
    fn integrated(&self) -> f64 {
        let (mut n, mut e) = (0u64, 0.0);
        for i in 0..BINS {
            n += self.hist_n[i] as u64;
            e += self.hist_e[i];
        }
        if n == 0 {
            return f64::NEG_INFINITY;
        }
        let gate = lufs(e / n as f64) - 10.0;
        let first = (((gate - BIN_FLOOR) * 10.0).max(0.0) as usize).min(BINS);
        let (mut n, mut e) = (0u64, 0.0);
        for i in first..BINS {
            n += self.hist_n[i] as u64;
            e += self.hist_e[i];
        }
        if n == 0 {
            f64::NEG_INFINITY
        } else {
            lufs(e / n as f64)
        }
    }
}

impl Device for Meter {
    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        if self.reset.swap(false, Relaxed) {
            self.clear();
        }
        let mut buf = [0.0f32; 4];
        for (&l, &r) in io.left.iter().zip(io.right.iter()) {
            let (xl, xr) = (l as f64, r as f64);
            let shelved = [self.k[0][0].run(xl), self.k[1][0].run(xr)];
            let wl = self.k[0][1].run(shelved[0]);
            let wr = self.k[1][1].run(shelved[1]);
            self.current.weighted += wl * wl + wr * wr;
            self.current.ll += xl * xl;
            self.current.rr += xr * xr;
            self.current.lr += xl * xr;
            self.sample_peak = self.sample_peak.max(l.abs()).max(r.abs());
            for (up, x) in self.up.iter_mut().zip([l, r]) {
                up.process(x, &mut buf);
                for v in buf {
                    self.true_peak = self.true_peak.max(v.abs());
                }
            }
            self.true_peak = self.true_peak.max(self.sample_peak);
            self.filled += 1;
            if self.filled == self.piece_len {
                self.finish_piece();
            }
        }
        for k in self.k.iter_mut().flatten() {
            k.flush_denormals();
        }
        self.tap.write(
            io.left
                .iter()
                .zip(io.right.iter())
                .map(|(l, r)| (l + r) * 0.5),
        );
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if index == 0 && value.is_finite() {
            self.hold_3s = value >= 0.5;
        }
    }
}

struct MeterFace {
    sr: f32,
    readings: Arc<Readings<8>>,
    tap: Arc<Tap>,
    reset: Arc<AtomicBool>,
}

/// The spectrum of the latest `n` samples of `tap` (a power of two), in dB
/// per band at `bands` frequencies spaced on a log scale from 20 Hz to
/// 20 kHz: the strongest bin of each band, with a full-scale sine at 0 dB.
fn spectrum(tap: &Tap, sr: f32, bands: usize) -> Vec<f64> {
    let n = 4096.min(tap.capacity());
    let mut x = vec![0.0f32; n];
    tap.read(&mut x);
    let re: Vec<f64> = x
        .iter()
        .enumerate()
        .map(|(i, v)| *v as f64 * (0.5 - 0.5 * (std::f64::consts::TAU * i as f64 / n as f64).cos()))
        .collect();
    let spec = dsp::rfft(&re);
    let full = (n as f64 / 4.0).powi(2);
    let bin_hz = sr as f64 / n as f64;
    let edges: Vec<f64> = dsp::log_frequencies(bands + 1, 20.0, 20000.0).collect();
    (0..bands)
        .map(|b| {
            let lo = ((edges[b] / bin_hz).floor() as usize).max(1);
            let hi = ((edges[b + 1] / bin_hz).ceil() as usize).clamp(lo + 1, n / 2);
            let most = (lo..hi)
                .map(|k| spec[k].norm_sqr())
                .fold(0.0, f64::max);
            (10.0 * (most / full).max(1e-20).log10()).max(-150.0)
        })
        .collect()
}

impl Face for MeterFace {
    /// `meters`: `momentary`, `short_term` and `integrated` (LUFS),
    /// `true_peak` (dBTP) and `sample_peak` (dBFS) held since the reset,
    /// `rms_l` and `rms_r` (dBFS, 300 ms), `correlation` (-1 to 1).
    /// Anything not measured yet reads -200. `spectrum [n]`: dB in `n`
    /// bands from 20 Hz to 20 kHz. `reset`: start measuring again.
    fn call(&mut self, _values: &[f32], method: &str, data: &[u8]) -> Result<Vec<u8>> {
        match method {
            "meters" => {
                let pairs: Vec<(&str, f64)> = NAMES
                    .iter()
                    .enumerate()
                    .map(|(i, name)| (*name, self.readings.get(i) as f64))
                    .collect();
                Ok(panel::fields(&pairs))
            }
            "spectrum" => {
                let bands = panel::count(data, 64, 1024);
                Ok(panel::numbers(spectrum(&self.tap, self.sr, bands), 1))
            }
            "reset" => {
                self.reset.store(true, Relaxed);
                Ok(Vec::new())
            }
            _ => {
                anyhow::bail!("the meter answers `meters`, `spectrum` and `reset`, not `{method}`")
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Tuner

pub fn tuner_params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::new("reference").name("A4").range(400.0, 480.0).default_value(440.0).unit("Hz"),
        ParamInfo::choice("mute", &["Off", "On"], 0).name("Mute"),
    ]
}

pub fn tuner(sr: f32) -> Pair {
    let tap = Tap::new(8192);
    (
        Box::new(Tuner {
            mute: false,
            tap: tap.clone(),
        }),
        Box::new(TunerFace { sr, tap }),
    )
}

pub struct Tuner {
    mute: bool,
    tap: Arc<Tap>,
}

impl Device for Tuner {
    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        self.tap.write(
            io.left
                .iter()
                .zip(io.right.iter())
                .map(|(l, r)| (l + r) * 0.5),
        );
        if self.mute {
            io.left.fill(0.0);
            io.right.fill(0.0);
        }
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if index == 1 && value.is_finite() {
            self.mute = value >= 0.5;
        }
    }
}

/// A detected pitch.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Pitch {
    pub freq: f64,
    /// How periodic the sound is, 0 to 1.
    pub confidence: f64,
}

/// The pitch of a monophonic sound by the YIN method (de Cheveigné and
/// Kawahara, 2002): the cumulative mean normalised difference function,
/// its first dip under a threshold, refined by a parabola. The difference
/// function comes from an autocorrelation done with FFTs. Looks between
/// `lo` and `hi` Hz. None for silence.
pub fn yin(x: &[f32], sr: f32, lo: f64, hi: f64) -> Option<Pitch> {
    let n = x.len();
    let w = n / 2;
    let rms = (x.iter().map(|v| (*v as f64).powi(2)).sum::<f64>() / n as f64).sqrt();
    if rms < 1e-3 {
        return None;
    }
    let tau_min = ((sr as f64 / hi).floor() as usize).max(2);
    let tau_max = ((sr as f64 / lo).ceil() as usize).min(w - 1);
    if tau_min + 2 >= tau_max {
        return None;
    }
    // r(τ) = Σ_{j<w} x[j]·x[j+τ], as the correlation of the first half
    // with the whole, through FFTs of twice the length.
    let size = (2 * n).next_power_of_two();
    let mut a = vec![0.0; size];
    let mut b = vec![0.0; size];
    for j in 0..w {
        a[j] = x[j] as f64;
    }
    for j in 0..n {
        b[j] = x[j] as f64;
    }
    // conj(A)·B, then the inverse (which realfft leaves `size` times too big).
    let (sa, sb) = (dsp::rfft(&a), dsp::rfft(&b));
    let mut c: Vec<_> = sa.iter().zip(&sb).map(|(a, b)| a.conj() * b).collect();
    // The spectrum of a real signal has real ends.
    c[0].im = 0.0;
    c[size / 2].im = 0.0;
    let mut cr = vec![0.0; size];
    realfft::RealFftPlanner::<f64>::new()
        .plan_fft_inverse(size)
        .process(&mut c, &mut cr)
        .expect("lengths match the plan");
    let r = |tau: usize| cr[tau] / size as f64;
    // Energies of the window and of the window moved by τ.
    let mut prefix = vec![0.0f64; n + 1];
    for j in 0..n {
        prefix[j + 1] = prefix[j] + (x[j] as f64).powi(2);
    }
    let e0 = prefix[w];
    let mut d = vec![0.0f64; tau_max + 2];
    for (tau, v) in d.iter_mut().enumerate().skip(1) {
        let et = prefix[tau + w] - prefix[tau];
        *v = (e0 + et - 2.0 * r(tau)).max(0.0);
    }
    // Cumulative mean normalised difference.
    let mut cmnd = vec![1.0f64; tau_max + 2];
    let mut running = 0.0;
    for tau in 1..=tau_max + 1 {
        running += d[tau];
        cmnd[tau] = if running > 0.0 {
            d[tau] * tau as f64 / running
        } else {
            1.0
        };
    }
    const THRESHOLD: f64 = 0.15;
    let mut best = None;
    let mut tau = tau_min;
    while tau <= tau_max {
        if cmnd[tau] < THRESHOLD {
            while tau < tau_max && cmnd[tau + 1] < cmnd[tau] {
                tau += 1;
            }
            best = Some(tau);
            break;
        }
        tau += 1;
    }
    let tau = best.unwrap_or_else(|| {
        (tau_min..=tau_max)
            .min_by(|a, b| cmnd[*a].total_cmp(&cmnd[*b]))
            .unwrap_or(tau_min)
    });
    // A parabola through the dip of the difference function itself (the
    // normalised one is skewed by its running mean) and its neighbours.
    let (a, b, c) = (d[tau - 1], d[tau], d[tau + 1]);
    let curve = a - 2.0 * b + c;
    let shift = if curve > 0.0 {
        (0.5 * (a - c) / curve).clamp(-1.0, 1.0)
    } else {
        0.0
    };
    Some(Pitch {
        freq: sr as f64 / (tau as f64 + shift),
        confidence: (1.0 - cmnd[tau]).clamp(0.0, 1.0),
    })
}

/// The note nearest a frequency: MIDI number, its name with octave, and how
/// many cents the frequency is above it.
pub fn nearest_note(freq: f64, a4: f64) -> (i32, String, f64) {
    let semis = 12.0 * (freq / a4).log2() + 69.0;
    let midi = semis.round() as i32;
    let cents = (semis - midi as f64) * 100.0;
    (midi, paw_types::pitch::name(midi), cents)
}

struct TunerFace {
    sr: f32,
    tap: Arc<Tap>,
}

impl Face for TunerFace {
    /// `pitch`: `freq` (Hz), `note` (such as `E2`), `midi`, `cents` (off
    /// the note, -50 to 50), `confidence` (0 to 1); with no pitch to be
    /// heard, `confidence 0` and `note -`.
    fn call(&mut self, values: &[f32], method: &str, _data: &[u8]) -> Result<Vec<u8>> {
        if method != "pitch" {
            anyhow::bail!("the tuner answers `pitch`, not `{method}`");
        }
        // 85 ms whatever the rate: two periods of the lowest string of a
        // seven-string guitar or a five-string bass with room to spare.
        let n = ((self.sr as f64 * 0.085) as usize)
            .next_power_of_two()
            .min(self.tap.capacity());
        let mut x = vec![0.0f32; n];
        self.tap.read(&mut x);
        let a4 = values.first().copied().unwrap_or(440.0).clamp(400.0, 480.0) as f64;
        let out = match yin(&x, self.sr, 27.0, 2000.0) {
            Some(p) => {
                let (midi, name, cents) = nearest_note(p.freq, a4);
                format!(
                    "freq {:.3}\nnote {name}\nmidi {midi}\ncents {cents:.2}\nconfidence {:.3}\n",
                    p.freq, p.confidence
                )
            }
            None => "freq 0\nnote -\nmidi 0\ncents 0\nconfidence 0\n".to_string(),
        };
        Ok(out.into_bytes())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::devices::testkit::*;

    fn stereo_sine(fx: &mut Fx, db: f32, seconds: f32) {
        let n = (fx.sr * seconds) as usize;
        let x = sine(1000.0, fx.sr, n, dsp::db_to_lin(db));
        let (l, r) = fx.run_stereo(&x, &x, 512);
        assert_eq!(l, x, "the meter passes audio untouched");
        assert_eq!(r, x);
    }

    #[test]
    fn a_1khz_tone_reads_its_level_in_lufs_at_every_rate() {
        for sr in [44100.0, 48000.0, 96000.0] {
            let mut fx = Fx::new("meter", sr);
            stereo_sine(&mut fx, -23.0, 4.0);
            for name in ["momentary", "short_term", "integrated"] {
                let v = fx.field("meters", name);
                assert!((v + 23.0).abs() < 0.05, "{name} at {sr}: {v}");
            }
        }
    }

    #[test]
    fn integrated_loudness_gates_as_ebu_tech_3341_says() {
        // Cases 3 and 4 of EBU Tech 3341: quiet stretches around a -23 LUFS
        // minute are gated out and the whole reads -23.
        let mut fx = Fx::new("meter", 48000.0);
        for (db, seconds) in [(-36.0, 10.0), (-23.0, 60.0), (-36.0, 10.0)] {
            stereo_sine(&mut fx, db, seconds);
        }
        let v = fx.field("meters", "integrated");
        assert!((v + 23.0).abs() < 0.1, "case 3: {v}");
        fx.call("reset", "");
        for (db, seconds) in [
            (-72.0, 10.0),
            (-36.0, 10.0),
            (-23.0, 60.0),
            (-36.0, 10.0),
            (-72.0, 10.0),
        ] {
            stereo_sine(&mut fx, db, seconds);
        }
        let v = fx.field("meters", "integrated");
        assert!((v + 23.0).abs() < 0.1, "case 4: {v}");
    }

    /// The meter on a part and `:analyze` on its render show one number.
    #[test]
    fn the_meter_and_the_analysis_of_a_file_agree() {
        let sr = 48000.0;
        // Ten seconds that change: a loud part with peaks between the
        // samples, and a quiet part that the relative gate leaves out.
        let x: Vec<f32> = (0..(sr as usize * 10))
            .map(|i| {
                let t = i as f32 / sr;
                let level = if t < 6.0 { 0.5 } else { 0.02 };
                let fade = (t * 20.0).min(1.0);
                let tone = (std::f32::consts::TAU * 440.0 * t).sin()
                    + 0.5 * (std::f32::consts::TAU * (sr / 4.0) * t + 0.785).sin();
                tone * level * fade
            })
            .collect();
        let mut fx = Fx::new("meter", sr);
        fx.run_stereo(&x, &x, 512);
        let analysis = paw_measure::analyze(f64::from(sr), &x, &x);

        let integrated = fx.field("meters", "integrated");
        let want = analysis.integrated.unwrap();
        assert!((integrated - want).abs() < 0.1, "integrated: meter {integrated}, analysis {want}");
        let true_peak = fx.field("meters", "true_peak");
        let want = analysis.true_peak;
        assert!((true_peak - want).abs() < 0.1, "true peak: meter {true_peak}, analysis {want}");
    }

    #[test]
    fn true_peak_sees_between_the_samples() {
        // A sine at a quarter of the rate, sampled 45 degrees off its crests:
        // the samples read 3 dB under the true peak.
        let mut fx = Fx::new("meter", 48000.0);
        let a = dsp::db_to_lin(-6.02);
        let x: Vec<f32> = (0..48000)
            .map(|i| [1.0, 1.0, -1.0, -1.0][i % 4] * std::f32::consts::FRAC_1_SQRT_2 * a)
            .collect();
        // The sine's sudden start rings past its level: measure from after it.
        fx.run_stereo(&x, &x, 256);
        fx.call("reset", "");
        fx.run_stereo(&x[..4000], &x[..4000], 256);
        fx.run_stereo(&x, &x, 256);
        let tp = fx.field("meters", "true_peak");
        let sp = fx.field("meters", "sample_peak");
        assert!((tp + 6.02).abs() < 0.1, "true peak {tp}");
        assert!((sp + 9.03).abs() < 0.02, "sample peak {sp}");
    }

    #[test]
    fn rms_and_correlation() {
        let mut fx = Fx::new("meter", 48000.0);
        let x = sine(997.0, 48000.0, 48000, 0.5);
        let neg: Vec<f32> = x.iter().map(|v| -v).collect();
        fx.run_stereo(&x, &x, 256);
        assert!((fx.field("meters", "rms_l") + 9.03).abs() < 0.05);
        assert!((fx.field("meters", "correlation") - 1.0).abs() < 1e-3);
        fx.run_stereo(&x, &neg, 256);
        assert!((fx.field("meters", "correlation") + 1.0).abs() < 1e-3);
        fx.run_stereo(&noise(48000, 1), &noise(48000, 2), 256);
        assert!(fx.field("meters", "correlation").abs() < 0.1);
    }

    #[test]
    fn the_spectrum_shows_a_tone_where_it_is() {
        let sr = 48000.0;
        let mut fx = Fx::new("meter", sr);
        let x = sine(1000.0, sr, 8192, dsp::db_to_lin(-6.0));
        fx.run_stereo(&x, &x, 256);
        let bands = fx.call_numbers("spectrum", "30");
        let edges: Vec<f64> = dsp::log_frequencies(31, 20.0, 20000.0).collect();
        let at = (0..30)
            .find(|&b| edges[b] <= 1000.0 && 1000.0 < edges[b + 1])
            .unwrap();
        // Within what the Hann window loses between bins (1.4 dB at most).
        assert!(
            bands[at] <= -6.0 + 0.01 && bands[at] > -7.5,
            "{}",
            bands[at]
        );
        assert!(bands[at + 3] < -60.0 && bands[at - 3] < -60.0);
    }

    #[test]
    fn the_tuner_finds_each_string_to_a_cent() {
        let sr = 48000.0;
        // The open strings, played in tune and 12 cents sharp, as a bright
        // decaying sawtooth like a plucked string.
        for (name, midi) in [
            ("E2", 40),
            ("A2", 45),
            ("D3", 50),
            ("G3", 55),
            ("B3", 59),
            ("E4", 64),
        ] {
            for detune in [0.0, 12.0, -7.0] {
                let freq = 440.0 * 2f64.powf((midi as f64 - 69.0 + detune / 100.0) / 12.0);
                let n = 24000;
                // Harmonics up to 10 kHz, falling as a sawtooth's do.
                let harmonics = (10000.0 / freq) as usize;
                let x: Vec<f32> = (0..n)
                    .map(|i| {
                        let t = i as f64 / sr as f64;
                        let saw: f64 = (1..=harmonics)
                            .map(|k| (std::f64::consts::TAU * k as f64 * freq * t).sin() / k as f64)
                            .sum();
                        (saw * 0.3 * (-(i as f64) / 20000.0).exp()) as f32
                    })
                    .collect();
                let mut fx = Fx::new("tuner", sr);
                fx.run(&x, 256);
                assert_eq!(
                    fx.call("pitch", "").lines().nth(1).unwrap(),
                    format!("note {name}")
                );
                let cents = fx.field("pitch", "cents");
                assert!(
                    (cents - detune).abs() < 1.0,
                    "{name} {detune:+}: read {cents:+.2}"
                );
                assert!(fx.field("pitch", "confidence") > 0.9);
            }
        }
        let mut fx = Fx::new("tuner", sr);
        fx.run(&vec![0.0; 9000], 256);
        assert_eq!(fx.field("pitch", "confidence"), 0.0, "silence has no pitch");
    }

    #[test]
    fn the_tuner_follows_its_reference_and_can_mute() {
        let sr = 44100.0;
        let mut fx = Fx::new("tuner", sr);
        fx.set("reference", 432.0);
        fx.set("mute", 1.0);
        let out = fx.run(&sine(432.0, sr, 8192, 0.3), 128);
        assert!(out.iter().all(|v| *v == 0.0));
        assert!(fx.field("pitch", "cents").abs() < 0.5);
        assert_eq!(fx.field("pitch", "midi"), 69.0);
    }
}
