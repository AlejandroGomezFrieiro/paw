//! Measuring a stereo signal: loudness (ITU-R BS.1770-4, EBU R 128, EBU Tech
//! 3341 and 3342), true peak (BS.1770 annex 2), sample peak and clipped runs,
//! DC offset, crest factor, stereo correlation, width, mono-sum loss and a
//! coarse spectrum.
//!
//! [`Analyzer`] takes the signal in pieces of any length and keeps per-100 ms
//! sums, so that a long song needs only a little memory and the series that
//! findings are placed by fall out of the same pass.
//!
//! Why not the `ebur128` crate: its integrated, momentary and short-term
//! readings agree with these to 0.001 LU, but it takes the short-term
//! blocks for loudness range only once a second (libebur128's 2 s overlap).
//! Tech 3342 asks for at least 10 Hz since its version 3, and on music
//! that alternates quiet and loud passages the two differ by several LU. The
//! crate also hides what the analysis needs from the gate: the blocks it
//! keeps (for the mono loss) and the two ends of the loudness range.

use std::sync::Arc;

use realfft::num_complex::Complex;
use realfft::{RealFftPlanner, RealToComplex};
use serde::Serialize;

/// Time between two points of every series, and the step of the gating blocks.
pub const HOP_SECONDS: f64 = 0.1;
/// Momentary loudness window: 400 ms, 4 hops.
const MOMENTARY_HOPS: usize = 4;
/// Short-term loudness window: 3 s, 30 hops.
const SHORT_TERM_HOPS: usize = 30;
const ABSOLUTE_GATE: f64 = -70.0;
const RELATIVE_GATE: f64 = -10.0;
const LRA_RELATIVE_GATE: f64 = -20.0;
/// What series hold where there is no sound to measure.
pub const FLOOR_DB: f64 = -150.0;
/// A sample at or above this is at digital full scale (it includes a 16-bit
/// file's largest positive value, 32767/32768).
const FULL_SCALE: f32 = 0.999_95;
/// Consecutive full-scale samples that make a clipped run (Audacity's default),
/// and unclipped samples that end one.
const RUN_START: usize = 3;
const RUN_END: usize = 3;
/// Runs kept with their positions; more are only counted.
const MAX_RUNS: usize = 2000;
/// Sound starts and ends where the sample peak crosses this (-60 dBFS).
const SOUND_THRESHOLD: f32 = 0.001;
/// Half the length of the true-peak interpolator, in input samples.
const TP_HALF: usize = 12;
/// Octave bands: IEC 61260-1 base-ten mid frequencies, 31.5 Hz to 16 kHz.
const OCTAVES: [&str; 10] = [
    "31.5", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k",
];

fn db(power_ratio: f64) -> f64 {
    if power_ratio > 0.0 {
        (10.0 * power_ratio.log10()).max(FLOOR_DB)
    } else {
        FLOOR_DB
    }
}

fn amp_db(amplitude: f64) -> f64 {
    db(amplitude * amplitude)
}

/// Loudness of a mean-square sum over channels, per BS.1770 (channel weights 1).
fn lufs(power: f64) -> f64 {
    if power > 0.0 {
        (-0.691 + 10.0 * power.log10()).max(FLOOR_DB)
    } else {
        FLOOR_DB
    }
}

/// A biquad in direct form I, in f64.
#[derive(Clone, Copy, Default)]
pub(super) struct Biquad {
    pub(super) b: [f64; 3],
    pub(super) a: [f64; 2],
    x: [f64; 2],
    y: [f64; 2],
}

impl Biquad {
    #[inline]
    fn run(&mut self, x: f64) -> f64 {
        let y = self.b[0] * x + self.b[1] * self.x[0] + self.b[2] * self.x[1]
            - self.a[0] * self.y[0]
            - self.a[1] * self.y[1];
        self.x = [x, self.x[0]];
        self.y = [y, self.y[0]];
        y
    }
}

/// The two stages of BS.1770's K-weighting at any sample rate, from the
/// analogue prototypes behind the standard's 48 kHz coefficients (the same
/// derivation as libebur128's). At 48 kHz they reproduce the table in
/// BS.1770-4 to the printed precision.
pub(super) fn k_weighting(rate: f64) -> [Biquad; 2] {
    use std::f64::consts::PI;
    // Stage 1: a high shelf of about +4 dB above 1.5 kHz, for the head.
    let (f0, gain, q) = (1681.974450955533, 3.999843853973347, 0.7071752369554196);
    let k = (PI * f0 / rate).tan();
    let vh = 10f64.powf(gain / 20.0);
    let vb = vh.powf(0.4996667741545416);
    let a0 = 1.0 + k / q + k * k;
    let shelf = Biquad {
        b: [
            (vh + vb * k / q + k * k) / a0,
            2.0 * (k * k - vh) / a0,
            (vh - vb * k / q + k * k) / a0,
        ],
        a: [2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0],
        ..Default::default()
    };
    // Stage 2: the RLB high pass at about 38 Hz.
    let (f0, q) = (38.13547087602444, 0.5003270373238773);
    let k = (PI * f0 / rate).tan();
    let a0 = 1.0 + k / q + k * k;
    let high_pass = Biquad {
        b: [1.0, -2.0, 1.0],
        a: [2.0 * (k * k - 1.0) / a0, (1.0 - k / q + k * k) / a0],
        ..Default::default()
    };
    [shelf, high_pass]
}

/// Interpolates between samples to find peaks that fall between them:
/// BS.1770-4 annex 2 with a windowed-sinc filter of its own (24 taps per
/// phase, Kaiser window), 4x oversampling below 96 kHz and 2x from there.
struct TruePeak {
    /// Coefficients per phase between two samples, `2 * TP_HALF` each.
    phases: Vec<Vec<f32>>,
    /// Recent input per channel. Sample `s` is at `s + TP_HALF - 1 - base`;
    /// it starts with zeros for the time before the signal.
    hist: [Vec<f32>; 2],
    base: usize,
    /// The next sample to interpolate after.
    next: usize,
}

fn bessel_i0(x: f64) -> f64 {
    let (mut sum, mut term) = (1.0, 1.0);
    for k in 1..50 {
        term *= (x / 2.0) / k as f64;
        sum += term * term;
        if term * term < 1e-17 * sum {
            break;
        }
    }
    sum
}

impl TruePeak {
    fn new(rate: f64) -> Self {
        let factor = if rate >= 96_000.0 { 2 } else { 4 };
        let beta = 7.0;
        let half = TP_HALF as f64;
        let phases = (1..factor)
            .map(|p| {
                let frac = p as f64 / factor as f64;
                // Taps for samples m - TP_HALF + 1 ..= m + TP_HALF around m + frac.
                let mut taps: Vec<f64> = (0..2 * TP_HALF)
                    .map(|i| {
                        let d = (i as f64 - (half - 1.0)) - frac;
                        let x = std::f64::consts::PI * d;
                        let sinc = if d.abs() < 1e-12 { 1.0 } else { x.sin() / x };
                        let r = (d / half).clamp(-1.0, 1.0);
                        sinc * bessel_i0(beta * (1.0 - r * r).sqrt()) / bessel_i0(beta)
                    })
                    .collect();
                // Unity gain at DC for every phase.
                let sum: f64 = taps.iter().sum();
                taps.iter_mut().for_each(|t| *t /= sum);
                taps.into_iter().map(|t| t as f32).collect()
            })
            .collect();
        Self {
            phases,
            hist: [vec![0.0; TP_HALF - 1], vec![0.0; TP_HALF - 1]],
            base: 0,
            next: 0,
        }
    }

    /// Add samples, calling `found(sample, peak)` with the highest
    /// interpolated level after every sample that has enough samples after it.
    fn push(&mut self, left: &[f32], right: &[f32], mut found: impl FnMut(usize, f32)) {
        self.hist[0].extend_from_slice(left);
        self.hist[1].extend_from_slice(right);
        self.run(&mut found);
    }

    /// The signal has ended: interpolate the last samples against silence.
    fn finish(&mut self, mut found: impl FnMut(usize, f32)) {
        for hist in &mut self.hist {
            hist.extend(std::iter::repeat_n(0.0, TP_HALF));
        }
        self.run(&mut found);
    }

    fn run(&mut self, found: &mut impl FnMut(usize, f32)) {
        let len = self.hist[0].len();
        let span = 2 * TP_HALF;
        while self.next - self.base + span <= len {
            let from = self.next - self.base;
            let mut peak = 0f32;
            for hist in &self.hist {
                let window = &hist[from..from + span];
                for taps in &self.phases {
                    let y: f32 = window.iter().zip(taps).map(|(x, c)| x * c).sum();
                    peak = peak.max(y.abs());
                }
            }
            found(self.next, peak);
            self.next += 1;
        }
        // Keep only what the next samples still need.
        let drop = self.next - self.base;
        if drop > 4 * span {
            for hist in &mut self.hist {
                hist.drain(..drop);
            }
            self.base += drop;
        }
    }
}

/// Put an interpolated peak in its hop and keep the highest.
fn place_true_peak(
    hops: &mut [Hop],
    current: &mut Hop,
    hop_frames: usize,
    best: &mut (f32, usize),
    at: usize,
    peak: f32,
) {
    if peak > best.0 {
        *best = (peak, at);
    }
    let slot = match hops.get_mut(at / hop_frames) {
        Some(hop) => hop,
        None => current,
    };
    slot.true_peak = slot.true_peak.max(peak);
}

/// Sums over one 100 ms hop.
#[derive(Clone, Copy, Default)]
struct Hop {
    /// K-weighted energy, left and right.
    kl: f64,
    kr: f64,
    /// K-weighted energy of the mono sum played on both sides: sum((kl + kr)^2 / 2).
    kmono: f64,
    /// Plain products, for correlation.
    lr: f64,
    ll: f64,
    rr: f64,
    sample_peak: f32,
    true_peak: f32,
}

/// A stretch of clipped samples.
#[derive(Clone, Debug, Serialize)]
pub struct Run {
    /// Seconds from the start.
    pub at: f64,
    /// Frames from the first clipped sample to the last.
    pub frames: usize,
    /// Highest level in the run, in dBFS.
    pub peak: f64,
}

#[derive(Clone, Debug, Serialize)]
pub struct Band {
    pub name: String,
    /// Edges in Hz.
    pub low: f64,
    pub high: f64,
    /// Share of the total energy, in dB (0 is all of it).
    pub share: f64,
}

/// Every number the analysis gives, as plain data.
#[derive(Clone, Debug, Serialize)]
pub struct Analysis {
    pub sample_rate: f64,
    pub frames: usize,
    pub seconds: f64,

    /// LUFS. `None` when nothing passes the gates.
    pub integrated: Option<f64>,
    pub momentary_max: Option<f64>,
    pub short_term_max: Option<f64>,
    /// LU, EBU Tech 3342. `None` for programmes shorter than one 3 s window.
    pub lra: Option<f64>,
    pub lra_low: Option<f64>,
    pub lra_high: Option<f64>,

    /// dBTP and dBFS.
    pub true_peak: f64,
    pub true_peak_at: f64,
    pub sample_peak: f64,
    pub sample_peak_at: f64,
    /// Peak to loudness ratio: true peak minus integrated loudness, in dB.
    pub plr: Option<f64>,
    /// Sample peak over RMS of both channels, in dB.
    pub crest: Option<f64>,
    pub rms: f64,
    /// Samples (per channel) at or over full scale, and samples over it.
    pub clipped_samples: usize,
    pub over_samples: usize,
    pub clip_runs: usize,
    pub runs: Vec<Run>,

    /// DC offset per channel: the median of 1 s means, linear (1 = full scale).
    pub dc: [f64; 2],
    /// The plain mean over everything.
    pub dc_mean: [f64; 2],

    /// Pearson correlation of left and right over the whole programme.
    pub correlation: f64,
    /// Side energy over mid plus side: 0 is mono, 0.5 unrelated channels, 1 opposite polarity.
    pub width: f64,
    /// Side level relative to mid, in dB.
    pub side: f64,
    /// Integrated loudness of the mono sum (L+R)/2 on both sides, and how much
    /// lower than the stereo it is over the blocks the stereo reading kept
    /// (150 when it cancels completely).
    pub mono_integrated: Option<f64>,
    pub mono_loss: Option<f64>,

    /// Where the sample peak first and last passes -60 dBFS, in seconds;
    /// `None` when it never does.
    pub sound_start: Option<f64>,
    pub sound_end: Option<f64>,

    pub bands: Vec<Band>,
    pub series: Series,
}

/// Values every 100 ms. Point `i` describes the window that ends at
/// `(i + 1) * hop` seconds; silence reads `FLOOR_DB`, and correlation reads
/// 1 where both sides are silent and 0 where one is.
#[derive(Clone, Debug, Default, Serialize)]
pub struct Series {
    pub hop: f64,
    pub momentary: Vec<f64>,
    pub short_term: Vec<f64>,
    /// Over 400 ms windows, like the momentary loudness.
    pub correlation: Vec<f64>,
    /// Over each 100 ms on its own, for placing the start of a passage.
    pub correlation_hop: Vec<f64>,
    pub mono_loss: Vec<f64>,
    /// Peaks within each 100 ms, in dBFS and dBTP.
    pub sample_peak: Vec<f64>,
    pub true_peak: Vec<f64>,
    /// Mean of each whole second, left and right: DC offset over time.
    /// Point `i` is the second from `i` to `i + 1` s.
    pub dc_left: Vec<f64>,
    pub dc_right: Vec<f64>,
}

pub struct Analyzer {
    rate: f64,
    hop_frames: usize,
    k: [[Biquad; 2]; 2],
    tp: TruePeak,
    hops: Vec<Hop>,
    current: Hop,
    in_hop: usize,
    frames: usize,
    /// The highest interpolated level and the sample it follows.
    tp_best: (f32, usize),
    sample_peak: f32,
    sample_peak_at: usize,
    energy: [f64; 2],
    sum: [f64; 2],
    mid: f64,
    side: f64,
    second: [f64; 2],
    in_second: usize,
    second_means: [Vec<f64>; 2],
    sound: Option<(usize, usize)>,
    // Clipping.
    clipped: usize,
    overs: usize,
    streak: usize,
    open: Option<(usize, usize, f32)>,
    runs: Vec<Run>,
    run_count: usize,
    // Spectrum of the mid signal.
    fft_size: usize,
    fft: Arc<dyn RealToComplex<f64>>,
    fft_buf: Vec<f64>,
    fft_in: Vec<f64>,
    fft_out: Vec<Complex<f64>>,
    window: Vec<f64>,
    spectrum: Vec<f64>,
}

impl Analyzer {
    pub fn new(sample_rate: f64) -> Self {
        let rate = sample_rate.max(1.0);
        let k = k_weighting(rate);
        // Frames of about a sixth of a second, so the 31.5 Hz band holds a few bins.
        let fft_size = ((rate / 6.0) as usize).next_power_of_two().max(256);
        let window = (0..fft_size)
            .map(|i| 0.5 - 0.5 * (2.0 * std::f64::consts::PI * i as f64 / fft_size as f64).cos())
            .collect();
        let fft = RealFftPlanner::<f64>::new().plan_fft_forward(fft_size);
        let fft_in = fft.make_input_vec();
        let fft_out = fft.make_output_vec();
        Self {
            rate,
            hop_frames: ((rate * HOP_SECONDS).round() as usize).max(1),
            k: [k, k],
            tp: TruePeak::new(rate),
            hops: Vec::new(),
            current: Hop::default(),
            in_hop: 0,
            frames: 0,
            tp_best: (0.0, 0),
            sample_peak: 0.0,
            sample_peak_at: 0,
            energy: [0.0; 2],
            sum: [0.0; 2],
            mid: 0.0,
            side: 0.0,
            second: [0.0; 2],
            in_second: 0,
            second_means: [Vec::new(), Vec::new()],
            sound: None,
            clipped: 0,
            overs: 0,
            streak: 0,
            open: None,
            runs: Vec::new(),
            run_count: 0,
            fft_size,
            fft,
            fft_buf: Vec::with_capacity(fft_size),
            fft_in,
            fft_out,
            window,
            spectrum: vec![0.0; fft_size / 2 + 1],
        }
    }

    pub fn frames(&self) -> usize {
        self.frames
    }

    /// Add the next stretch of the signal. `left` and `right` are the same length.
    pub fn push(&mut self, left: &[f32], right: &[f32]) {
        let n = left.len().min(right.len());
        let (left, right) = (&left[..n], &right[..n]);
        let hop_frames = self.hop_frames;
        let per_second = self.rate.round() as usize;
        for i in 0..n {
            let (l, r) = (left[i], right[i]);
            let (lf, rf) = (l as f64, r as f64);
            let frame = self.frames + i;

            let [[l1, l2], [r1, r2]] = &mut self.k;
            let kl = l2.run(l1.run(lf));
            let kr = r2.run(r1.run(rf));
            let h = &mut self.current;
            h.kl += kl * kl;
            h.kr += kr * kr;
            h.kmono += (kl + kr) * (kl + kr) * 0.5;
            h.lr += lf * rf;
            h.ll += lf * lf;
            h.rr += rf * rf;
            let peak = l.abs().max(r.abs());
            if peak > h.sample_peak {
                h.sample_peak = peak;
            }
            if peak > self.sample_peak {
                self.sample_peak = peak;
                self.sample_peak_at = frame;
            }
            if peak > SOUND_THRESHOLD {
                self.sound = Some(match self.sound {
                    Some((first, _)) => (first, frame),
                    None => (frame, frame),
                });
            }

            self.energy[0] += lf * lf;
            self.energy[1] += rf * rf;
            self.sum[0] += lf;
            self.sum[1] += rf;
            let (m, s) = ((lf + rf) * 0.5, (lf - rf) * 0.5);
            self.mid += m * m;
            self.side += s * s;
            self.second[0] += lf;
            self.second[1] += rf;
            self.in_second += 1;
            if self.in_second == per_second {
                for ch in 0..2 {
                    self.second_means[ch].push(self.second[ch] / per_second as f64);
                }
                self.second = [0.0; 2];
                self.in_second = 0;
            }

            for x in [l.abs(), r.abs()] {
                if x >= FULL_SCALE {
                    self.clipped += 1;
                }
                if x > 1.0 {
                    self.overs += 1;
                }
            }
            if peak >= FULL_SCALE {
                self.streak += 1;
                match &mut self.open {
                    Some((_, last, top)) => {
                        *last = frame;
                        *top = top.max(peak);
                    }
                    None if self.streak >= RUN_START || peak > 1.0 => {
                        self.open = Some((frame + 1 - self.streak, frame, peak));
                    }
                    None => {}
                }
            } else {
                self.streak = 0;
                if let Some((_, last, _)) = self.open
                    && frame - last >= RUN_END
                {
                    self.close_run();
                }
            }

            self.fft_buf.push(m);
            if self.fft_buf.len() == self.fft_size {
                self.spectrum_frame();
            }

            self.in_hop += 1;
            if self.in_hop == hop_frames {
                self.hops.push(self.current);
                self.current = Hop::default();
                self.in_hop = 0;
            }
        }
        self.frames += n;

        // True peaks arrive a few samples late; put each in its hop.
        let (hops, current, best) = (&mut self.hops, &mut self.current, &mut self.tp_best);
        self.tp.push(left, right, |at, peak| {
            place_true_peak(hops, current, hop_frames, best, at, peak)
        });
    }

    fn close_run(&mut self) {
        if let Some((start, last, top)) = self.open.take() {
            self.run_count += 1;
            if self.runs.len() < MAX_RUNS {
                self.runs.push(Run {
                    at: start as f64 / self.rate,
                    frames: last - start + 1,
                    peak: amp_db(top as f64),
                });
            }
        }
    }

    fn spectrum_frame(&mut self) {
        let n = self.fft_size;
        // Without the frame's mean, so that a DC offset (reported on its own)
        // does not leak into the lowest bands through the window.
        let mean = self.fft_buf.iter().sum::<f64>() / n as f64;
        for ((x, w), out) in self.fft_buf.iter().zip(&self.window).zip(&mut self.fft_in) {
            *out = (x - mean) * w;
        }
        // The input is a whole frame of the planned length, so this cannot fail.
        self.fft
            .process(&mut self.fft_in, &mut self.fft_out)
            .expect("an FFT frame of the planned length");
        for (power, bin) in self.spectrum.iter_mut().zip(&self.fft_out) {
            *power += bin.norm_sqr();
        }
        // Half overlap: with a Hann window the frames then add up to a constant.
        self.fft_buf.drain(..n / 2);
    }

    pub fn finish(mut self) -> Analysis {
        let hop_frames = self.hop_frames;
        let (hops, current, best) = (&mut self.hops, &mut self.current, &mut self.tp_best);
        self.tp
            .finish(|at, peak| place_true_peak(hops, current, hop_frames, best, at, peak));
        if self.in_hop > 0 {
            // A last, partial hop: in the series and peaks, not in the gating.
            self.hops.push(self.current);
        }
        let complete = self.frames / self.hop_frames;
        self.close_run();
        if !self.fft_buf.is_empty() && self.fft_buf.len() > self.fft_size / 4 {
            self.fft_buf.resize(self.fft_size, 0.0);
            self.spectrum_frame();
        }

        let hop_frames = self.hop_frames as f64;
        let hops = &self.hops;
        // Mean-square sums over a window of hops ending at `end` (inclusive).
        let window = |end: usize, len: usize, f: &dyn Fn(&Hop) -> f64| -> f64 {
            let first = (end + 1).saturating_sub(len);
            let sum: f64 = hops[first..=end].iter().map(f).sum();
            sum / ((end + 1 - first) as f64 * hop_frames)
        };
        let stereo = |h: &Hop| h.kl + h.kr;
        let mono = |h: &Hop| h.kmono;

        // Gating blocks: every complete 400 ms window, 75 % overlap.
        let blocks = |f: &dyn Fn(&Hop) -> f64| -> Vec<f64> {
            if complete < MOMENTARY_HOPS {
                return Vec::new();
            }
            (MOMENTARY_HOPS - 1..complete)
                .map(|end| window(end, MOMENTARY_HOPS, f))
                .collect()
        };
        let stereo_blocks = blocks(&stereo);
        let mono_blocks = blocks(&mono);
        let kept = gate(&stereo_blocks);
        let integrated = mean_of(&stereo_blocks, &kept);
        let mono_integrated = gated(&mono_blocks);
        // The loss in mono over the same blocks as the stereo reading, so
        // that passages which cancel count instead of being gated away.
        let mono_same = mean_of(&mono_blocks, &kept);
        let momentary_max = stereo_blocks
            .iter()
            .cloned()
            .fold(None, |m: Option<f64>, p| Some(m.map_or(p, |m| m.max(p))));

        let short_blocks: Vec<f64> = if complete >= SHORT_TERM_HOPS {
            (SHORT_TERM_HOPS - 1..complete)
                .map(|end| window(end, SHORT_TERM_HOPS, &stereo))
                .collect()
        } else {
            Vec::new()
        };
        let short_term_max = short_blocks
            .iter()
            .cloned()
            .fold(None, |m: Option<f64>, p| Some(m.map_or(p, |m| m.max(p))));
        let (lra, lra_low, lra_high) = loudness_range(&short_blocks);

        let mut series = Series {
            hop: HOP_SECONDS,
            ..Default::default()
        };
        for end in 0..hops.len() {
            series
                .momentary
                .push(lufs(window(end, MOMENTARY_HOPS, &stereo)));
            series
                .short_term
                .push(lufs(window(end, SHORT_TERM_HOPS, &stereo)));
            let first = (end + 1).saturating_sub(MOMENTARY_HOPS);
            let (mut lr, mut ll, mut rr, mut st, mut mo) = (0.0, 0.0, 0.0, 0.0, 0.0);
            for h in &hops[first..=end] {
                lr += h.lr;
                ll += h.ll;
                rr += h.rr;
                st += h.kl + h.kr;
                mo += h.kmono;
            }
            series
                .correlation
                .push(correlation(lr, ll, rr, hop_frames * MOMENTARY_HOPS as f64));
            let h = &hops[end];
            series
                .correlation_hop
                .push(correlation(h.lr, h.ll, h.rr, hop_frames));
            series.mono_loss.push(if st > 1e-12 && mo > 0.0 {
                db(st / mo).min(-FLOOR_DB)
            } else if st > 1e-12 {
                -FLOOR_DB
            } else {
                0.0
            });
            series
                .sample_peak
                .push(amp_db(hops[end].sample_peak as f64));
            series
                .true_peak
                .push(amp_db(hops[end].true_peak.max(hops[end].sample_peak) as f64));
        }

        let frames = self.frames;
        let total: f64 = hops.iter().map(|h| h.lr).sum();
        let (ll, rr): (f64, f64) = (self.energy[0], self.energy[1]);
        let true_peak = self.tp_best.0.max(self.sample_peak);
        let true_peak_at = if self.tp_best.0 >= self.sample_peak {
            self.tp_best.1
        } else {
            self.sample_peak_at
        };
        let rms = if frames > 0 {
            ((ll + rr) / (2.0 * frames as f64)).sqrt()
        } else {
            0.0
        };
        let dc_mean = if frames > 0 {
            [self.sum[0] / frames as f64, self.sum[1] / frames as f64]
        } else {
            [0.0; 2]
        };
        let dc = if self.second_means[0].is_empty() {
            dc_mean
        } else {
            [median(&self.second_means[0]), median(&self.second_means[1])]
        };

        series.dc_left = self.second_means[0].clone();
        series.dc_right = self.second_means[1].clone();
        let bands = self.bands();
        let true_peak_db = amp_db(true_peak as f64);
        let sample_peak_db = amp_db(self.sample_peak as f64);
        Analysis {
            sample_rate: self.rate,
            frames,
            seconds: frames as f64 / self.rate,
            integrated: integrated.map(lufs),
            momentary_max: momentary_max.map(lufs),
            short_term_max: short_term_max.map(lufs),
            lra,
            lra_low,
            lra_high,
            true_peak: true_peak_db,
            true_peak_at: true_peak_at as f64 / self.rate,
            sample_peak: sample_peak_db,
            sample_peak_at: self.sample_peak_at as f64 / self.rate,
            plr: integrated.map(|i| true_peak_db - lufs(i)),
            crest: (rms > 0.0).then(|| sample_peak_db - amp_db(rms)),
            rms: amp_db(rms),
            clipped_samples: self.clipped,
            over_samples: self.overs,
            clip_runs: self.run_count,
            runs: self.runs,
            dc,
            dc_mean,
            correlation: correlation(total, ll, rr, frames as f64),
            width: if self.mid + self.side > 0.0 {
                self.side / (self.mid + self.side)
            } else {
                0.0
            },
            side: if self.mid > 0.0 {
                db(self.side / self.mid)
            } else if self.side > 0.0 {
                -FLOOR_DB
            } else {
                FLOOR_DB
            },
            mono_integrated: mono_integrated.map(lufs),
            mono_loss: integrated.map(|s| {
                let m = mono_same.unwrap_or(0.0);
                if m > 0.0 {
                    (10.0 * (s / m).log10()).min(-FLOOR_DB)
                } else {
                    -FLOOR_DB
                }
            }),
            sound_start: self.sound.map(|(first, _)| first as f64 / self.rate),
            sound_end: self.sound.map(|(_, last)| (last + 1) as f64 / self.rate),
            bands,
            series,
        }
    }

    /// Octave-band shares of the mid signal's energy, with what lies below
    /// the 31.5 Hz band as `sub` and above the 16 kHz band as `air`.
    fn bands(&self) -> Vec<Band> {
        let bin_hz = self.rate / self.fft_size as f64;
        let g = 10f64.powf(0.3);
        let mut edges = vec![0.0];
        for k in -5..=5 {
            edges.push(1000.0 * g.powf(k as f64 - 0.5));
        }
        edges.push(self.rate / 2.0);
        let mut names = vec!["sub".to_string()];
        names.extend(OCTAVES.iter().map(|s| s.to_string()));
        names.push("air".to_string());
        let mut energy = vec![0.0; names.len()];
        // The DC bin is left out: offset is reported on its own.
        for (k, p) in self.spectrum.iter().enumerate().skip(1) {
            let hz = k as f64 * bin_hz;
            let band = edges.windows(2).position(|e| hz >= e[0] && hz < e[1]);
            if let Some(b) = band {
                energy[b] += p;
            }
        }
        let total: f64 = energy.iter().sum();
        names
            .into_iter()
            .enumerate()
            .filter(|(i, _)| edges[*i] < edges[i + 1])
            .map(|(i, name)| Band {
                name,
                low: edges[i],
                high: edges[i + 1],
                share: if total > 0.0 {
                    db(energy[i] / total)
                } else {
                    FLOOR_DB
                },
            })
            .collect()
    }
}

fn correlation(lr: f64, ll: f64, rr: f64, frames: f64) -> f64 {
    // Below about -100 dBFS RMS a side counts as silent.
    let quiet = 1e-10 * frames.max(1.0);
    match (ll > quiet, rr > quiet) {
        (true, true) => (lr / (ll * rr).sqrt()).clamp(-1.0, 1.0),
        (false, false) => 1.0,
        _ => 0.0,
    }
}

/// BS.1770-4 gating: which blocks are above -70 LUFS and above the mean of
/// those minus 10 LU.
fn gate(blocks: &[f64]) -> Vec<bool> {
    let absolute = 10f64.powf((ABSOLUTE_GATE + 0.691) / 10.0);
    let above: Vec<f64> = blocks.iter().copied().filter(|p| *p > absolute).collect();
    if above.is_empty() {
        return vec![false; blocks.len()];
    }
    let mean = above.iter().sum::<f64>() / above.len() as f64;
    let relative = (mean * 10f64.powf(RELATIVE_GATE / 10.0)).max(absolute);
    blocks.iter().map(|p| *p > relative).collect()
}

/// The gated mean power of a list of block powers: integrated loudness
/// before taking the logarithm.
pub fn gated(blocks: &[f64]) -> Option<f64> {
    mean_of(blocks, &gate(blocks))
}

fn mean_of(blocks: &[f64], keep: &[bool]) -> Option<f64> {
    let (sum, n) = blocks
        .iter()
        .zip(keep)
        .filter(|(_, k)| **k)
        .fold((0.0, 0usize), |(s, n), (p, _)| (s + p, n + 1));
    (n > 0).then(|| sum / n as f64)
}

/// EBU Tech 3342: short-term loudness gated at -70 LUFS and 20 LU below the
/// mean, then the 95th minus the 10th percentile.
fn loudness_range(short_term: &[f64]) -> (Option<f64>, Option<f64>, Option<f64>) {
    let absolute = 10f64.powf((ABSOLUTE_GATE + 0.691) / 10.0);
    let above: Vec<f64> = short_term
        .iter()
        .copied()
        .filter(|p| *p > absolute)
        .collect();
    if above.is_empty() {
        return (None, None, None);
    }
    let mean = above.iter().sum::<f64>() / above.len() as f64;
    let relative = mean * 10f64.powf(LRA_RELATIVE_GATE / 10.0);
    let mut kept: Vec<f64> = above
        .into_iter()
        .filter(|p| *p > relative)
        .map(lufs)
        .collect();
    if kept.is_empty() {
        return (None, None, None);
    }
    kept.sort_by(f64::total_cmp);
    let at = |q: f64| kept[((kept.len() - 1) as f64 * q).round() as usize];
    let (low, high) = (at(0.10), at(0.95));
    (Some(high - low), Some(low), Some(high))
}

fn median(values: &[f64]) -> f64 {
    let mut v = values.to_vec();
    v.sort_by(f64::total_cmp);
    let n = v.len();
    if n % 2 == 1 {
        v[n / 2]
    } else {
        (v[n / 2 - 1] + v[n / 2]) / 2.0
    }
}

/// Measure a whole signal at once.
pub fn analyze(sample_rate: f64, left: &[f32], right: &[f32]) -> Analysis {
    let mut a = Analyzer::new(sample_rate);
    for (l, r) in left.chunks(4096).zip(right.chunks(4096)) {
        a.push(l, r);
    }
    a.finish()
}
