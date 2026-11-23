//! Time stretching and pitch shifting of recorded sound.
//!
//! A stretched clip does not stretch as it plays: the stretch of its file is
//! made once, here, on a worker thread (see `stretched.rs`), and the engine
//! plays the result sample for sample, as it plays any file.
//!
//! Two ways of stretching, both keeping the pitch:
//!
//! - [`Mode::Tonal`]: a phase vocoder with identity phase locking (Laroche
//!   and Dolson): each spectral peak's phase moves on at its own frequency,
//!   and the bins around a peak keep their phase relation to it, which
//!   keeps a held note from sounding phasey. At an onset the phases start
//!   again from the input's, so that an attack is not smeared by the phases
//!   of what came before it. Good for held and melodic sound at any ratio.
//! - [`Mode::Percussive`]: WSOLA, overlapping pieces of the input at its own
//!   speed, each placed where it continues the last one best. An onset is
//!   played once, whole and at the time it should be: the piece that holds
//!   it is placed so that it lands there, and the next one carries on from
//!   it without a jump. Good for drums and speech at modest ratios.
//!
//! [`Mode::Auto`] chooses by how many onsets the sound has a second.
//!
//! Stereo stays one image: the phases (for the vocoder) and the places
//! (for WSOLA) are worked out on the sum of the channels and applied to
//! both, so the same sound in both channels comes out the same in both.
//!
//! How long the result is, and where each moment of the input lands in it,
//! is a [`Warp`]: a sound at input frame `x` is at output frame
//! `warp(x)`, evenly `x * ratio`, or by parts stretched differently (warp
//! markers, a clip bent along the tempo). Both ways follow the warp as it
//! goes, frame by frame. A pitch shift is a stretch by the warp times the
//! shift, then a sinc resampling back by the shift. A shift can keep the
//! sound's formants ([`Params::formants`]): the vocoder then moves the
//! spectrum's envelope the other way first, so that the resampling puts it
//! back where it was (see [`Envelope`]).

use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use anyhow::{Result, bail};
use paw_engine::{AudioData, Sink};
use realfft::RealFftPlanner;
use realfft::num_complex::Complex;
use serde::{Deserialize, Serialize};

use crate::resample::Stream;
pub(crate) use crate::warp::Warp;

/// How a clip is stretched: see the module's description.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Mode {
    #[default]
    Auto,
    Tonal,
    Percussive,
}

impl Mode {
    pub fn name(self) -> &'static str {
        match self {
            Mode::Auto => "auto",
            Mode::Tonal => "tonal",
            Mode::Percussive => "percussive",
        }
    }
}

/// The shortest and longest a stretch can make a sound: a quarter to four
/// times as long. Past about 0.5 to 2 it is heard.
pub(crate) const RATIO_RANGE: (f64, f64) = (0.25, 4.0);

/// The furthest a pitch moves, in semitones, either way.
pub(crate) const PITCH_RANGE: f64 = 24.0;

/// Onsets a second from which [`Mode::Auto`] takes the sound for drums.
const PERCUSSIVE_DENSITY: f64 = 2.0;

/// What [`Mode::Auto`] chooses for a sound.
pub fn choose(data: &AudioData) -> Mode {
    let onsets = onsets(&mid(data), data.sample_rate);
    // The first onset is the sound starting, which says nothing of it.
    let seconds = data.seconds().max(1e-9);
    if (onsets.len().saturating_sub(1)) as f64 / seconds >= PERCUSSIVE_DENSITY {
        Mode::Percussive
    } else {
        Mode::Tonal
    }
}

/// What a sound is made into.
#[derive(Clone, Debug)]
pub struct Params {
    /// Where each moment goes, in seconds.
    pub(crate) warp: Warp,
    /// How much higher it plays.
    pub semitones: f64,
    pub mode: Mode,
    /// A shift keeps the formants where they were. Only the vocoder can:
    /// with this, it stretches whatever the mode.
    pub formants: bool,
}

impl Params {
    /// `ratio` times as long, `semitones` higher.
    pub fn even(ratio: f64, semitones: f64, mode: Mode) -> Self {
        Self {
            warp: Warp::even(ratio),
            semitones,
            mode,
            formants: false,
        }
    }
}

/// How many frames `frames` at `rate` make through `warp`.
pub(crate) fn length(frames: usize, rate: u32, warp: &Warp) -> usize {
    warp.in_frames(rate as f64)
        .forward(frames as f64)
        .round()
        .max(0.0) as usize
}

/// `data` made into what `params` say, kept where `sink` keeps it: a
/// growing sink ([`Sink::growing`]) of [`length`] frames can be played as
/// it fills. Gives up, with an error, once `cancel` is set.
pub fn render(
    data: &AudioData,
    params: &Params,
    sink: Sink,
    cancel: &AtomicBool,
) -> Result<AudioData> {
    params.warp.check()?;
    let semitones = params.semitones;
    if !semitones.is_finite() || semitones.abs() > PITCH_RANGE {
        bail!("a pitch shift is at most {PITCH_RANGE} semitones either way, not {semitones}");
    }
    let rate = data.sample_rate;
    let frames = data.frames();
    let wanted = length(frames, rate, &params.warp);
    let shift = (semitones / 12.0).exp2();
    let formants = (params.formants && semitones != 0.0).then_some(shift);
    let mode = match params.mode {
        _ if formants.is_some() => Mode::Tonal,
        Mode::Auto => choose(data),
        mode => mode,
    };
    let mut out = if semitones == 0.0 {
        Out::Sink(Box::new(sink))
    } else {
        // Made `shift` times longer still, then played back that much faster.
        Out::Resample(Box::new(Stream::new(1.0 / shift, rate, wanted, sink)?))
    };
    let map = params.warp.in_frames(rate as f64).scaled(shift);
    let length = map.forward(frames as f64).round().max(0.0) as usize;
    let input = [&data.channels[0][..], &data.channels[1][..]];
    match mode {
        Mode::Percussive => wsola(input, rate, &map, length, &mut out, cancel)?,
        _ => vocoder(input, rate, &map, length, formants, &mut out, cancel)?,
    }
    out.finish(rate, wanted)
}

/// Where the stretched sound goes as it is made.
enum Out {
    Sink(Box<Sink>),
    Resample(Box<Stream>),
}

impl Out {
    fn push(&mut self, left: &[f32], right: &[f32]) -> Result<()> {
        match self {
            Out::Sink(sink) => sink.push(left, Some(right)),
            Out::Resample(stream) => stream.push(left, right),
        }
    }

    fn finish(self, rate: u32, wanted: usize) -> Result<AudioData> {
        match self {
            Out::Sink(mut sink) => {
                if sink.frames() < wanted {
                    let silence = vec![0.0; wanted - sink.frames()];
                    sink.push(&silence, Some(&silence))?;
                }
                sink.finish(rate)
            }
            Out::Resample(stream) => stream.finish(),
        }
    }
}

/// Overlap-add of frames into the output, handing on each stretch of it
/// once no later frame can add to it.
struct Ola {
    acc: [Vec<f32>; 2],
    /// Output frame of `acc`'s first.
    base: usize,
    /// Frames the output has; what goes past is dropped.
    length: usize,
}

impl Ola {
    fn new(length: usize) -> Self {
        Self {
            acc: [Vec::new(), Vec::new()],
            base: 0,
            length,
        }
    }

    /// Add `frame` from output frame `at`, scaled by `scale`.
    fn add(&mut self, at: i64, frame: [&[f32]; 2], scale: f32) {
        for (i, (l, r)) in frame[0].iter().zip(frame[1]).enumerate() {
            let pos = at + i as i64;
            if pos < self.base as i64 || pos >= self.length as i64 {
                continue;
            }
            let k = pos as usize - self.base;
            if k >= self.acc[0].len() {
                self.acc[0].resize(k + 1, 0.0);
                self.acc[1].resize(k + 1, 0.0);
            }
            self.acc[0][k] += l * scale;
            self.acc[1][k] += r * scale;
        }
    }

    /// Hand on everything before output frame `to`.
    fn emit(&mut self, to: i64, out: &mut Out) -> Result<()> {
        let to = (to.max(0) as usize).min(self.length);
        if to <= self.base {
            return Ok(());
        }
        let n = to - self.base;
        if self.acc[0].len() < n {
            self.acc[0].resize(n, 0.0);
            self.acc[1].resize(n, 0.0);
        }
        out.push(&self.acc[0][..n], &self.acc[1][..n])?;
        self.acc[0].drain(..n);
        self.acc[1].drain(..n);
        self.base = to;
        Ok(())
    }
}

/// A periodic Hann window: copies of it `n / 2` apart add up to 1.
fn hann(n: usize) -> Vec<f32> {
    (0..n)
        .map(|i| (0.5 - 0.5 * (std::f64::consts::TAU * i as f64 / n as f64).cos()) as f32)
        .collect()
}

/// The power of two nearest `seconds` at `rate`.
fn frame_size(rate: u32, seconds: f64) -> usize {
    let n = (rate as f64 * seconds).max(64.0);
    1 << (n.log2().round() as u32)
}

/// Both channels added, at half level.
fn mid(data: &AudioData) -> Vec<f32> {
    data.channels[0]
        .iter()
        .zip(data.channels[1].iter())
        .map(|(l, r)| 0.5 * (l + r))
        .collect()
}

/// Copy `src[from..from + out.len()]` into `out`, with zeros outside `src`.
fn read(src: &[f32], from: i64, out: &mut [f32]) {
    for (i, o) in out.iter_mut().enumerate() {
        let pos = from + i as i64;
        *o = if pos >= 0 && (pos as usize) < src.len() {
            src[pos as usize]
        } else {
            0.0
        };
    }
}

/// Where sounds begin, as input frames, in order: where the energy of the
/// sound's changes (its high frequencies) jumps well above what it was
/// just before, at least 50 ms after the last onset.
pub(crate) fn onsets(mono: &[f32], rate: u32) -> Vec<usize> {
    let block = (rate as usize / 344).max(16);
    let energy: Vec<f64> = mono
        .chunks(block)
        .enumerate()
        .map(|(b, chunk)| {
            let mut prev = if b == 0 { 0.0 } else { mono[b * block - 1] };
            let mut e = 0.0f64;
            for x in chunk {
                e += ((x - prev) as f64).powi(2);
                prev = *x;
            }
            e
        })
        .collect();
    let loudest = energy.iter().cloned().fold(0.0, f64::max);
    if loudest <= 0.0 {
        return Vec::new();
    }
    // Quieter than this is too quiet to have onsets: 60 dB below the loudest.
    let floor = loudest * 1e-6;
    const HISTORY: usize = 16;
    let gap = (rate as f64 * 0.05 / block as f64).ceil() as usize;
    let mut out = Vec::new();
    let mut last: Option<usize> = None;
    for b in 0..energy.len() {
        let from = b.saturating_sub(HISTORY);
        let before = if b > from {
            energy[from..b].iter().sum::<f64>() / (b - from) as f64
        } else {
            0.0
        };
        if energy[b] > floor && energy[b] > 8.0 * before && last.is_none_or(|l| b >= l + gap) {
            // The block's first frame that holds the jump.
            let start = b * block;
            let end = (start + block).min(mono.len());
            let at = (start..end)
                .find(|&i| {
                    let prev = if i == 0 { 0.0 } else { mono[i - 1] };
                    ((mono[i] - prev) as f64).powi(2) * block as f64 > energy[b] * 0.25
                })
                .unwrap_or(start);
            out.push(at);
            last = Some(b);
        }
    }
    out
}

fn wrap(phase: f64) -> f64 {
    use std::f64::consts::{PI, TAU};
    phase - TAU * ((phase + PI) / TAU).floor()
}

/// The phase vocoder (see the module's description), following `map` (in
/// frames). With `formants`, the shift that will follow, it moves each
/// frame's spectral envelope by the inverse of the shift.
fn vocoder(
    input: [&[f32]; 2],
    rate: u32,
    map: &Warp,
    length: usize,
    formants: Option<f64>,
    out: &mut Out,
    cancel: &AtomicBool,
) -> Result<()> {
    // About 46 ms: 2048 frames at 44.1 and 48 kHz.
    let n = frame_size(rate, 0.046);
    let hop = n / 8;
    let bins = n / 2 + 1;
    let window = hann(n);
    // Hann windows applied twice, 1/8 of their length apart, add up to 3.
    let scale = 1.0 / (3.0 * n as f32);
    let mut planner = RealFftPlanner::<f32>::new();
    let forward = planner.plan_fft_forward(n);
    let inverse = planner.plan_fft_inverse(n);
    let mono: Vec<f32> = input[0]
        .iter()
        .zip(input[1])
        .map(|(l, r)| 0.5 * (l + r))
        .collect();
    let onsets = onsets(&mono, rate);
    let mut next_onset = 0;

    let mut frame = vec![0.0f32; n];
    let mut spectra: [Vec<Complex<f32>>; 3] = std::array::from_fn(|_| forward.make_output_vec());
    let mut outs: [Vec<f32>; 2] = [vec![0.0; n], vec![0.0; n]];
    let mut magnitude = vec![0.0f32; bins];
    let mut phase = vec![0.0f64; bins];
    let mut last_phase = vec![0.0f64; bins];
    let mut synth = vec![0.0f64; bins];
    let mut peaks = Vec::with_capacity(bins / 2);
    let mut ola = Ola::new(length);
    let mut last_start: Option<i64> = None;
    let mut last_centre = f64::NEG_INFINITY;
    let mut envelope = formants.map(|shift| Envelope::new(&mut planner, n, rate, shift));

    // Synthesis frame m starts at m * hop - n + hop, so that the first
    // output frames have every frame over them that later ones have.
    let mut m: i64 = 0;
    loop {
        let start = m * hop as i64 - (n - hop) as i64;
        if start >= length as i64 {
            break;
        }
        if m % 64 == 0 && cancel.load(Ordering::Relaxed) {
            bail!("cancelled");
        }
        let centre = map.inverse((start + n as i64 / 2) as f64);
        let a_start = centre.round() as i64 - n as i64 / 2;
        // The analysis hop actually taken, for the phases' advance.
        let a_hop = last_start.map(|s| (a_start - s) as f64);
        // A frame whose centre passed an onset starts its phases afresh.
        let mut reset = a_hop.is_none_or(|h| h <= 0.0);
        while next_onset < onsets.len() && (onsets[next_onset] as f64) <= centre {
            reset |= onsets[next_onset] as f64 > last_centre;
            next_onset += 1;
        }
        last_centre = centre;

        for (c, src) in [input[0], input[1], &mono[..]].iter().enumerate() {
            read(src, a_start, &mut frame);
            for (x, w) in frame.iter_mut().zip(&window) {
                *x *= w;
            }
            forward
                .process(&mut frame, &mut spectra[c])
                .map_err(|e| anyhow::anyhow!("stretching: {e}"))?;
        }
        // The sum of the channels sets the phases, unless it cancels out
        // (the channels in opposite phase), where the left one does.
        let mut reference = std::mem::take(&mut spectra[2]);
        let mut loudest = 0.0f32;
        for k in 0..bins {
            let (l, r) = (spectra[0][k], spectra[1][k]);
            if reference[k].norm_sqr() * 4.0 < 0.01 * (l - r).norm_sqr() {
                reference[k] = l;
            }
            magnitude[k] = reference[k].norm();
            phase[k] = reference[k].arg() as f64;
            loudest = loudest.max(magnitude[k]);
        }
        spectra[2] = reference;

        match a_hop {
            Some(a_hop) if !reset => {
                peaks.clear();
                let floor = loudest * 1e-5;
                for k in 0..bins {
                    let v = magnitude[k];
                    let around = (k.saturating_sub(2)..=(k + 2).min(bins - 1)).filter(|&j| j != k);
                    if v > floor && around.clone().all(|j| v >= magnitude[j]) {
                        peaks.push(k);
                    }
                }
                if peaks.is_empty() {
                    synth.copy_from_slice(&phase);
                } else {
                    let omega = |k: usize| std::f64::consts::TAU * k as f64 / n as f64;
                    for &p in &peaks {
                        let expected = a_hop * omega(p);
                        let deviation = wrap(phase[p] - last_phase[p] - expected);
                        let frequency = omega(p) + deviation / a_hop;
                        synth[p] = wrap(synth[p] + hop as f64 * frequency);
                    }
                    // Each bin keeps its phase relation to the peak of its
                    // region; regions part at the lowest bin between peaks.
                    let mut from = 0;
                    for (i, &p) in peaks.iter().enumerate() {
                        let to = match peaks.get(i + 1) {
                            Some(&q) => (p..q)
                                .min_by(|a, b| magnitude[*a].total_cmp(&magnitude[*b]))
                                .unwrap_or(p),
                            None => bins - 1,
                        };
                        for k in from..=to {
                            if k != p {
                                synth[k] = wrap(synth[p] + phase[k] - phase[p]);
                            }
                        }
                        from = to + 1;
                    }
                }
            }
            _ => synth.copy_from_slice(&phase),
        }
        last_phase.copy_from_slice(&phase);
        last_start = Some(a_start);
        let gains = match &mut envelope {
            Some(envelope) => Some(envelope.gains(&magnitude)?),
            None => None,
        };

        for c in 0..2 {
            let spectrum = &mut spectra[c];
            for k in 0..bins {
                let turn = synth[k] - phase[k];
                let gain = gains.map_or(1.0, |g| g[k]);
                spectrum[k] *= Complex::from_polar(gain, turn as f32);
            }
            spectrum[0].im = 0.0;
            spectrum[bins - 1].im = 0.0;
            inverse
                .process(spectrum, &mut outs[c])
                .map_err(|e| anyhow::anyhow!("stretching: {e}"))?;
            for (x, w) in outs[c].iter_mut().zip(&window) {
                *x *= w;
            }
        }
        ola.add(start, [&outs[0], &outs[1]], scale);
        ola.emit(start + hop as i64, out)?;
        m += 1;
    }
    ola.emit(length as i64, out)
}

/// WSOLA (see the module's description), following `map` (in frames).
fn wsola(
    input: [&[f32]; 2],
    rate: u32,
    map: &Warp,
    length: usize,
    out: &mut Out,
    cancel: &AtomicBool,
) -> Result<()> {
    // About 21 ms: 1024 frames at 44.1 and 48 kHz.
    let w = frame_size(rate, 0.025);
    let hop = w / 2;
    // How far a piece may move from where it belongs to fit the last one.
    let tolerance = (hop / 2) as i64;
    let window = hann(w);
    let mono: Vec<f32> = input[0]
        .iter()
        .zip(input[1])
        .map(|(l, r)| 0.5 * (l + r))
        .collect();
    let onsets = onsets(&mono, rate);
    let (w64, hop64) = (w as i64, hop as i64);
    // Where an input frame belongs in the output.
    let place = |x: f64| map.forward(x);

    let mut ola = Ola::new(length);
    let mut pieces: [Vec<f32>; 2] = [vec![0.0; w], vec![0.0; w]];
    let mut natural = vec![0.0f32; hop];
    let mut candidate = vec![0.0f32; hop + 2 * tolerance as usize];
    // The onsets played whole so far: those before this index.
    let mut done = 0;
    // The last piece's place in the input.
    let mut last: Option<i64> = None;
    // Whether the next piece must carry straight on from the last.
    let mut carry = false;
    let mut m: i64 = 0;
    loop {
        // Piece m goes to the output from (m - 1) * hop.
        let at = (m - 1) * hop64;
        if at >= length as i64 {
            break;
        }
        if m % 256 == 0 && cancel.load(Ordering::Relaxed) {
            bail!("cancelled");
        }
        let nominal = map.inverse((at + hop64) as f64).round() as i64 - hop64;
        let pos = match last {
            None => nominal,
            Some(prev) if carry => prev + hop64,
            Some(prev) => {
                let next = onsets.get(done).map(|&o| o as i64);
                match next {
                    // The next onset belongs in this piece's second half (or
                    // before it, when it could not be placed earlier): the
                    // piece is placed so that it lands where it belongs.
                    Some(o) if place(o as f64) < (at + w64) as f64 => {
                        let into = (place(o as f64).round() as i64 - at).max(hop64);
                        (o - into).max(prev + 1)
                    }
                    _ => {
                        let natural_at = prev + hop64;
                        read(&mono, natural_at, &mut natural);
                        read(&mono, nominal - tolerance, &mut candidate);
                        let best = best_fit(&natural, &candidate, tolerance);
                        let mut pos = nominal + best;
                        // A piece holds no onset that is still to be placed.
                        if let Some(o) = next {
                            pos = pos.min(o - w64);
                        }
                        // Nor one already played.
                        if done > 0 {
                            pos = pos.max(onsets[done - 1] as i64 + 1);
                        }
                        pos
                    }
                }
            }
        };
        // An onset in this piece's second half is played whole by the next
        // piece carrying straight on.
        carry = false;
        while let Some(&o) = onsets.get(done) {
            let o = o as i64;
            if o < pos + hop64 {
                // In the first half: played by the piece before, or passed.
                done += 1;
            } else if o < pos + w64 {
                carry = true;
                done += 1;
            } else {
                break;
            }
        }
        for c in 0..2 {
            read(input[c], pos, &mut pieces[c]);
            for (x, win) in pieces[c].iter_mut().zip(&window) {
                *x *= win;
            }
        }
        ola.add(at, [&pieces[0], &pieces[1]], 1.0);
        ola.emit(at + hop64, out)?;
        last = Some(pos);
        m += 1;
    }
    ola.emit(length as i64, out)
}

/// How far from `tolerance` into `candidate` the stretch that best
/// continues `natural` begins, from `-tolerance` to `tolerance`: by
/// normalised cross-correlation, coarsely and then to the frame.
fn best_fit(natural: &[f32], candidate: &[f32], tolerance: i64) -> i64 {
    let n = natural.len();
    let score = |offset: usize, step: usize| {
        let (mut dot, mut energy) = (0.0f32, 1e-9f32);
        for i in (0..n).step_by(step) {
            let c = candidate[offset + i];
            dot += natural[i] * c;
            energy += c * c;
        }
        dot / energy.sqrt()
    };
    let span = 2 * tolerance as usize;
    let mut best = (tolerance as usize, f32::NEG_INFINITY);
    for offset in (0..=span).step_by(4) {
        let s = score(offset, 2);
        if s > best.1 {
            best = (offset, s);
        }
    }
    let coarse = best.0;
    best.1 = f32::NEG_INFINITY;
    for offset in coarse.saturating_sub(4)..=(coarse + 4).min(span) {
        let s = score(offset, 1);
        if s > best.1 {
            best = (offset, s);
        }
    }
    best.0 as i64 - tolerance
}

/// The envelope of a spectrum, and the gains that move it.
///
/// The envelope is found by liftering the cepstrum: the log of the
/// magnitudes, transformed back, holds the slow shape of the spectrum (the
/// formants) in its first coefficients and the fine one (the harmonics of
/// a voice) further out; keeping the first ones and transforming forward
/// again gives the shape alone. A voice of up to about 650 Hz keeps its
/// harmonics out of what is kept.
struct Envelope {
    inverse: Arc<dyn realfft::ComplexToReal<f32>>,
    forward: Arc<dyn realfft::RealToComplex<f32>>,
    log: Vec<Complex<f32>>,
    cepstrum: Vec<f32>,
    smooth: Vec<Complex<f32>>,
    /// The envelope, in log magnitude, by bin.
    shape: Vec<f32>,
    gains: Vec<f32>,
    /// Coefficients kept.
    keep: usize,
    shift: f64,
}

impl Envelope {
    fn new(planner: &mut RealFftPlanner<f32>, n: usize, rate: u32, shift: f64) -> Self {
        let inverse = planner.plan_fft_inverse(n);
        let forward = planner.plan_fft_forward(n);
        let bins = n / 2 + 1;
        Self {
            log: inverse.make_input_vec(),
            cepstrum: inverse.make_output_vec(),
            smooth: forward.make_output_vec(),
            inverse,
            forward,
            shape: vec![0.0; bins],
            gains: vec![1.0; bins],
            // 1.5 ms of quefrency.
            keep: ((rate as f64 * 0.0015) as usize).clamp(8, n / 4),
            shift,
        }
    }

    /// The gain for each bin of a spectrum of `magnitude` that, once the
    /// spectrum is moved `shift` times higher, leaves its envelope where it
    /// was: the envelope at `shift` times the bin's frequency, over the
    /// envelope at it.
    fn gains(&mut self, magnitude: &[f32]) -> Result<&[f32]> {
        let bins = magnitude.len();
        let n = self.cepstrum.len();
        let floor = magnitude.iter().cloned().fold(0.0, f32::max) * 1e-6 + 1e-20;
        for (l, m) in self.log.iter_mut().zip(magnitude) {
            *l = Complex::new((m + floor).ln(), 0.0);
        }
        self.inverse
            .process(&mut self.log, &mut self.cepstrum)
            .map_err(|e| anyhow::anyhow!("finding formants: {e}"))?;
        for (q, c) in self.cepstrum.iter_mut().enumerate() {
            if q >= self.keep && q <= n - self.keep {
                *c = 0.0;
            }
        }
        self.forward
            .process(&mut self.cepstrum, &mut self.smooth)
            .map_err(|e| anyhow::anyhow!("finding formants: {e}"))?;
        for (s, c) in self.shape.iter_mut().zip(&self.smooth) {
            *s = c.re / n as f32;
        }
        for k in 0..bins {
            let at = k as f64 * self.shift;
            let i = (at as usize).min(bins - 1);
            let frac = (at - i as f64).min(1.0) as f32;
            let next = self.shape[(i + 1).min(bins - 1)];
            let moved = self.shape[i] + (next - self.shape[i]) * frac;
            // At most 40 dB either way: where the envelope is all but
            // silent its shape says little.
            self.gains[k] = (moved - self.shape[k]).clamp(-4.6, 4.6).exp();
        }
        Ok(&self.gains)
    }
}

/// For tests: `data` stretched whole, in memory.
#[cfg(test)]
pub(crate) fn stretched(data: &AudioData, params: &Params) -> Result<Arc<AudioData>> {
    render(data, params, Sink::memory(), &AtomicBool::new(false)).map(Arc::new)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::f64::consts::TAU;

    const RATE: u32 = 48_000;

    fn sound(left: Vec<f32>, right: Vec<f32>) -> AudioData {
        AudioData {
            sample_rate: RATE,
            channels: [left.into(), right.into()],
        }
    }

    fn sine(freq: f64, seconds: f64, amplitude: f64) -> Vec<f32> {
        (0..(RATE as f64 * seconds) as usize)
            .map(|i| (amplitude * (TAU * freq * i as f64 / RATE as f64).sin()) as f32)
            .collect()
    }

    /// The middle of a signal, away from its edges.
    fn middle(s: &[f32]) -> &[f32] {
        &s[s.len() / 5..s.len() * 4 / 5]
    }

    /// Frequency by zero crossings rising, between the first and the last.
    fn frequency(s: &[f32]) -> f64 {
        let s = middle(s);
        let mut crossings = Vec::new();
        for i in 1..s.len() {
            if s[i - 1] < 0.0 && s[i] >= 0.0 {
                let frac = s[i - 1] as f64 / (s[i - 1] - s[i]) as f64;
                crossings.push(i as f64 - 1.0 + frac);
            }
        }
        let span = crossings.last().unwrap() - crossings[0];
        (crossings.len() - 1) as f64 * RATE as f64 / span
    }

    fn rms(s: &[f32]) -> f64 {
        let s = middle(s);
        (s.iter().map(|x| (*x as f64).powi(2)).sum::<f64>() / s.len() as f64).sqrt()
    }

    /// The largest step from one sample to the next, past the first and
    /// last few milliseconds.
    fn largest_step(s: &[f32]) -> f32 {
        let edge = RATE as usize / 100;
        s[edge..s.len() - edge]
            .windows(2)
            .map(|w| (w[1] - w[0]).abs())
            .fold(0.0, f32::max)
    }

    #[test]
    fn a_sine_keeps_its_pitch_and_level_and_has_the_length_asked_for() {
        let freq = 440.0;
        let src = sine(freq, 2.0, 0.5);
        let source_step = largest_step(&src);
        for mode in [Mode::Tonal, Mode::Percussive] {
            for ratio in [0.5, 0.8, 1.25, 2.0] {
                let out = stretched(
                    &sound(src.clone(), src.clone()),
                    &Params::even(ratio, 0.0, mode),
                )
                .unwrap();
                let left = &out.channels[0];
                assert_eq!(
                    out.frames(),
                    (src.len() as f64 * ratio).round() as usize,
                    "{mode:?} {ratio}"
                );
                let f = frequency(left);
                assert!(
                    (f / freq - 1.0).abs() < 0.005,
                    "{mode:?} at {ratio}: {f:.2} Hz"
                );
                let level = 20.0 * (rms(left) / rms(&src)).log10();
                assert!(
                    level.abs() < 1.0,
                    "{mode:?} at {ratio}: level {level:.2} dB"
                );
                let step = largest_step(left);
                assert!(
                    step < source_step * 1.1,
                    "{mode:?} at {ratio}: a step of {step} against the sine's {source_step}"
                );
                eprintln!(
                    "{mode:?} x{ratio}: {f:.3} Hz, {level:+.3} dB, largest step {:.3} of the sine's",
                    step / source_step
                );
            }
        }
    }

    /// Clicks a quarter of a second apart, with a little noise between.
    fn clicks(count: usize) -> (Vec<f32>, Vec<usize>) {
        let spacing = RATE as usize / 4;
        let mut s = vec![0.0f32; spacing * (count + 1)];
        let mut seed = 1u32;
        for x in s.iter_mut() {
            seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            *x = ((seed >> 8) as f32 / (1u32 << 24) as f32 - 0.5) * 0.002;
        }
        let at: Vec<usize> = (1..=count).map(|i| i * spacing).collect();
        for &i in &at {
            s[i] = 0.9;
        }
        (s, at)
    }

    /// Where the samples above half of `peak` are, one per click.
    fn found(s: &[f32], peak: f32) -> Vec<usize> {
        let mut out: Vec<usize> = Vec::new();
        for (i, x) in s.iter().enumerate() {
            if x.abs() > peak / 2.0 && out.last().is_none_or(|l| i > l + RATE as usize / 50) {
                out.push(i);
            }
        }
        out
    }

    #[test]
    fn a_click_train_keeps_its_clicks_their_spacing_and_no_pre_echo() {
        let (src, at) = clicks(8);
        for ratio in [0.5, 0.8, 1.25, 2.0] {
            let out = stretched(
                &sound(src.clone(), src.clone()),
                &Params::even(ratio, 0.0, Mode::Percussive),
            )
            .unwrap();
            let left = &out.channels[0];
            let got = found(left, 0.9);
            assert_eq!(got.len(), at.len(), "x{ratio}: clicks at {got:?}");
            let mut worst = 0.0f64;
            for (g, a) in got.iter().zip(&at) {
                let error = (*g as f64 - *a as f64 * ratio).abs() * 1000.0 / RATE as f64;
                worst = worst.max(error);
            }
            assert!(
                worst < 2.0,
                "x{ratio}: a click {worst:.2} ms from its place: {got:?} {at:?}"
            );
            // Before each click, what is there is no louder than the noise.
            let mut echo = 0.0f32;
            for g in &got {
                let from = g.saturating_sub(RATE as usize / 20);
                for x in &left[from..g.saturating_sub(RATE as usize / 1000)] {
                    echo = echo.max(x.abs());
                }
            }
            let echo_db = 20.0 * (echo / 0.9).log10();
            assert!(echo_db < -40.0, "x{ratio}: pre-echo at {echo_db:.1} dB");
            let peak = got.iter().map(|g| left[*g].abs()).fold(1.0, f32::min);
            eprintln!(
                "clicks x{ratio}: {} of {}, worst {worst:.3} ms off, pre-echo {echo_db:.1} dB, \
                 quietest click {peak:.3}",
                got.len(),
                at.len()
            );
        }
        // The vocoder, for the record: it smears a click over its frame.
        for ratio in [0.8, 1.25] {
            let out = stretched(
                &sound(src.clone(), src.clone()),
                &Params::even(ratio, 0.0, Mode::Tonal),
            )
            .unwrap();
            let got = found(&out.channels[0], 0.9);
            eprintln!("clicks through the vocoder x{ratio}: {} found", got.len());
        }
    }

    #[test]
    fn auto_takes_clicks_for_drums_and_a_sine_for_a_tone() {
        let (c, _) = clicks(8);
        assert_eq!(choose(&sound(c.clone(), c)), Mode::Percussive);
        let s = sine(220.0, 2.0, 0.5);
        assert_eq!(choose(&sound(s.clone(), s)), Mode::Tonal);
    }

    #[test]
    fn a_pitch_shift_moves_a_sine_by_the_ratio_and_keeps_its_length() {
        let src = sine(440.0, 2.0, 0.5);
        for (semitones, ratio) in [(3.0, 1.0), (-0.5, 1.0), (7.0, 1.5), (-12.0, 0.8)] {
            for mode in [Mode::Tonal, Mode::Percussive] {
                let out = stretched(
                    &sound(src.clone(), src.clone()),
                    &Params::even(ratio, semitones, mode),
                )
                .unwrap();
                assert_eq!(out.frames(), (src.len() as f64 * ratio).round() as usize);
                let want = 440.0 * (semitones / 12.0f64).exp2();
                let f = frequency(&out.channels[0]);
                assert!(
                    (f / want - 1.0).abs() < 0.005,
                    "{mode:?} {semitones:+} st: {f:.2} Hz, not {want:.2}"
                );
                eprintln!("{mode:?} {semitones:+} st x{ratio}: {f:.3} Hz for {want:.3}");
            }
        }
    }

    #[test]
    fn the_same_sound_in_both_channels_comes_out_the_same_in_both() {
        let (c, _) = clicks(4);
        let s: Vec<f32> = sine(330.0, 1.25, 0.4)
            .iter()
            .zip(&c)
            .map(|(a, b)| a + b)
            .collect();
        for mode in [Mode::Tonal, Mode::Percussive] {
            let out =
                stretched(&sound(s.clone(), s.clone()), &Params::even(1.37, 2.0, mode)).unwrap();
            assert!(
                out.channels[0].iter().eq(out.channels[1].iter()),
                "{mode:?}"
            );
        }
        // A stereo sound keeps the difference between its channels: the
        // right channel half as loud comes out half as loud.
        let half: Vec<f32> = s.iter().map(|x| x * 0.5).collect();
        let out = stretched(
            &sound(s.clone(), half),
            &Params::even(1.5, 0.0, Mode::Tonal),
        )
        .unwrap();
        let ratio = rms(&out.channels[1]) / rms(&out.channels[0]);
        assert!((ratio - 0.5).abs() < 0.01, "right against left {ratio}");
    }

    #[test]
    fn a_render_that_is_cancelled_stops() {
        let s = sine(440.0, 1.0, 0.5);
        let cancel = AtomicBool::new(true);
        let data = sound(s.clone(), s);
        assert!(
            render(
                &data,
                &Params::even(2.0, 0.0, Mode::Tonal),
                Sink::memory(),
                &cancel
            )
            .is_err()
        );
        assert!(
            render(
                &data,
                &Params::even(9.0, 0.0, Mode::Tonal),
                Sink::memory(),
                &cancel
            )
            .is_err()
        );
    }

    #[test]
    fn a_warp_puts_each_click_where_it_says_in_both_ways() {
        // Two seconds made into three: the first second into a half, the
        // second into two and a half.
        let (src, at) = clicks(7);
        let warp = Warp::new(vec![(0.0, 0.0), (1.0, 0.5)], 0.5, 2.5);
        let data = sound(src.clone(), src.clone());
        let place = |x: usize| warp.forward(x as f64 / RATE as f64) * RATE as f64;
        for mode in [Mode::Percussive, Mode::Tonal] {
            let params = Params {
                warp: warp.clone(),
                semitones: 0.0,
                mode,
                formants: false,
            };
            let out = stretched(&data, &params).unwrap();
            assert_eq!(out.frames(), length(src.len(), RATE, &warp));
            assert_eq!(
                out.frames(),
                (warp.forward(2.0) * RATE as f64).round() as usize
            );
            // The vocoder smears a click over its frame: only its loudest
            // sample is looked for, near where it belongs.
            let peak = if mode == Mode::Tonal { 0.3 } else { 0.9 };
            let got = found(&out.channels[0], peak);
            assert_eq!(got.len(), at.len(), "{mode:?}: clicks at {got:?}");
            for (g, a) in got.iter().zip(&at) {
                let off = (*g as f64 - place(*a)).abs() * 1000.0 / RATE as f64;
                let limit = if mode == Mode::Tonal { 25.0 } else { 2.0 };
                assert!(off < limit, "{mode:?}: a click {off:.2} ms from its place");
            }
        }
    }

    #[test]
    fn a_growing_sink_is_filled_with_what_memory_would_hold() {
        let s = sine(330.0, 1.5, 0.5);
        let data = sound(s.clone(), s);
        let params = Params::even(1.7, 3.0, Mode::Tonal);
        let whole = stretched(&data, &params).unwrap();
        let frames = length(data.frames(), RATE, &params.warp);
        let sink = Sink::growing(frames, RATE, None).unwrap();
        let playing = sink.playing().unwrap();
        let made = render(&data, &params, sink, &AtomicBool::new(false)).unwrap();
        assert!(made.complete() && playing.complete());
        assert!(whole.channels[0].iter().eq(playing.channels[0].iter()));
        assert!(whole.channels[1].iter().eq(made.channels[1].iter()));
    }

    /// A voice-like sound: harmonics of `f0` shaped by one formant at
    /// `formant` Hz.
    fn vowel(f0: f64, formant: f64, seconds: f64) -> Vec<f32> {
        let shape = |f: f64| 0.02 + (-((f - formant) / 250.0).powi(2)).exp();
        let harmonics: Vec<(f64, f64)> = (1..)
            .map(|h| h as f64 * f0)
            .take_while(|f| *f < 8000.0)
            .map(|f| (f, shape(f)))
            .collect();
        (0..(RATE as f64 * seconds) as usize)
            .map(|i| {
                let t = i as f64 / RATE as f64;
                let s: f64 = harmonics.iter().map(|(f, a)| a * (TAU * f * t).sin()).sum();
                (0.1 * s) as f32
            })
            .collect()
    }

    /// The frequency of the loudest harmonic in the middle of `s`.
    fn loudest(s: &[f32]) -> f64 {
        let n = 16384;
        let from = s.len() / 2 - n / 2;
        let window = hann(n);
        let mut frame: Vec<f32> = s[from..from + n]
            .iter()
            .zip(&window)
            .map(|(x, w)| x * w)
            .collect();
        let fft = RealFftPlanner::<f32>::new().plan_fft_forward(n);
        let mut spectrum = fft.make_output_vec();
        fft.process(&mut frame, &mut spectrum).unwrap();
        let (k, _) = spectrum
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.norm().total_cmp(&b.1.norm()))
            .unwrap();
        k as f64 * RATE as f64 / n as f64
    }

    #[test]
    fn a_shift_keeping_formants_leaves_the_formant_where_it_was() {
        let (f0, formant) = (150.0, 1000.0);
        let src = vowel(f0, formant, 1.5);
        let data = sound(src.clone(), src.clone());
        let before = loudest(&src);
        assert!(
            (before - formant).abs() <= f0 / 2.0,
            "the source's at {before:.0} Hz"
        );
        for semitones in [7.0, -5.0] {
            let shift = (semitones / 12.0f64).exp2();
            let mut params = Params::even(1.0, semitones, Mode::Auto);
            let moved = loudest(&stretched(&data, &params).unwrap().channels[0]);
            params.formants = true;
            let out = stretched(&data, &params).unwrap();
            let kept = loudest(&out.channels[0]);
            eprintln!("{semitones:+} st: formant {moved:.0} Hz moved, {kept:.0} Hz kept");
            let spacing = f0 * shift;
            assert!(
                (moved - formant * shift).abs() <= spacing,
                "{semitones:+} st, moved: the loudest harmonic at {moved:.0} Hz"
            );
            assert!(
                (kept - formant).abs() <= spacing,
                "{semitones:+} st, kept: the loudest harmonic at {kept:.0} Hz"
            );
            // And it is a harmonic of the shifted pitch.
            let h = kept / spacing;
            assert!(
                (h - h.round()).abs() < 0.05,
                "harmonic {h:.2} of the new pitch"
            );
            assert_eq!(out.frames(), src.len());
        }
    }
}
