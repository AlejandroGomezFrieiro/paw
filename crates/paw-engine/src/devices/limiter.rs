//! A look-ahead brick-wall limiter, for the master: nothing leaves it above
//! the ceiling, and with true-peak detection on, neither do the peaks
//! between samples that a converter or an encoder would make.
//!
//! For each input frame the gain that would bring it under the ceiling is
//! worked out, with an exponential release. The gain applied to the delayed
//! signal is the average, over a window, of the smallest such gain in a
//! window of the same length before it. Every term of that average covers
//! the frame being played, so the result is never above what that frame
//! needs, and the gain comes down along a smooth ramp instead of clipping.
//!
//! The true-peak detector interpolates the input four times over and takes
//! the largest value around each sample, refined by a parabola through the
//! points around each crest. It does so twice, with two windowed-sinc
//! filters, and believes the higher: one is the filter BS.1770 meters (and
//! this program's own analysis) read true peak with, the other lets through
//! everything up to the Nyquist frequency at full level, which a real
//! converter may. The filters' delay comes out of the look-ahead, so the
//! latency is always [`LOOKAHEAD`] whatever the setting.

use std::sync::Arc;

use anyhow::Result;

use super::dsp::{self, DelayLine, Readings, Smooth, Upsampler};
use super::panel::{self, Face, Pair};
use crate::device::{Device, Io, ParamInfo, ProcessCtx};

/// How late the output is, in seconds.
pub const LOOKAHEAD: f32 = 0.005;
/// Interpolation of the true-peak detector.
const OVERSAMPLE: usize = 4;
/// Input samples per phase of the meter's filter and of the wide one.
const TAPS: usize = 24;
const WIDE_TAPS: usize = 16;
/// Input frames by which the detector's verdict on a frame comes after it.
const DETECT_DELAY: usize = TAPS / 2;
/// Headroom kept below the ceiling in true-peak mode, for the peaks the
/// four-times detector cannot see and for the gain's own movement.
const TRUE_PEAK_MARGIN_DB: f32 = 0.2;

const CEILING: usize = 0;
const GAIN: usize = 1;
const RELEASE: usize = 2;
const TRUE_PEAK: usize = 3;

pub fn params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::new("ceiling")
            .name("Ceiling")
            .range(-24.0, 0.0)
            .default_value(-1.0)
            .unit("dB"),
        ParamInfo::new("gain")
            .name("Gain")
            .range(0.0, 24.0)
            .default_value(0.0)
            .unit("dB"),
        ParamInfo::new("release")
            .name("Release")
            .range(1.0, 1000.0)
            .default_value(100.0)
            .unit("ms"),
        ParamInfo::choice("true_peak", &["Off", "On"], 1).name("True peak"),
    ]
}

pub fn make(sr: f32) -> Pair {
    let readings = Readings::new();
    (
        Box::new(Limiter::new(sr, readings.clone())),
        Box::new(LimiterFace { sr, readings }),
    )
}

/// Interpolation as a true-peak meter does it, and interpolation that lets
/// everything up to the input's Nyquist frequency through at full level
/// (and a little above it, through the transition band): the detector would
/// rather read a peak too high than too low.
fn detectors() -> [Upsampler; 2] {
    [
        Upsampler::design(OVERSAMPLE, TAPS, 1.0, 7.0),
        Upsampler::design(OVERSAMPLE, WIDE_TAPS, 1.35, 5.0),
    ]
}

/// The largest of `points`, and of the crests between them found from the
/// parabola through each three that rise and fall again: that makes what
/// four points a sample can miss of a peak ten times smaller.
#[inline]
fn crest(points: &[f32], last: &mut [f32; 2]) -> f32 {
    let mut most = 0.0f32;
    for &v in points {
        let [y0, y1] = *last;
        let curve = y0 - 2.0 * y1 + v;
        if (y1 >= y0 && y1 >= v || y1 <= y0 && y1 <= v) && curve != 0.0 {
            let offset = (0.5 * (y0 - v) / curve).clamp(-1.0, 1.0);
            most = most.max((y1 - 0.25 * (y0 - v) * offset).abs());
        }
        most = most.max(v.abs());
        *last = [y1, v];
    }
    most
}

fn latency_frames(sr: f32) -> usize {
    ((LOOKAHEAD * sr).round() as usize).max(DETECT_DELAY + 1)
}

pub struct Limiter {
    sr: f32,
    p: [f32; 4],
    gain: Smooth,
    ceiling: f32,
    release: f32,
    true_peak: bool,
    lines: [DelayLine; 2],
    latency: usize,
    /// The detector: interpolators, the input it has seen, and the largest
    /// interpolated value of the last frame.
    /// [channel][meter, wide]
    up: [[Upsampler; 2]; 2],
    /// The wide filter's verdicts, held back to line up with the meter's.
    wide: DelayLine,
    raw: DelayLine,
    last_seg: f32,
    /// The last two interpolated points of each channel.
    last: [[[f32; 2]; 2]; 2],
    /// Candidates for the smallest gain in the window: positions and values,
    /// values rising from front to back.
    queue_at: Vec<u64>,
    queue_gain: Vec<f32>,
    head: usize,
    count: usize,
    /// The window's smallest gain at each of the last `window` frames, and
    /// their sum.
    minima: Vec<f32>,
    sum: f64,
    at: usize,
    frame: u64,
    held: f32,
    readings: Arc<Readings<3>>,
    started: bool,
}

impl Limiter {
    fn new(sr: f32, readings: Arc<Readings<3>>) -> Self {
        let latency = latency_frames(sr);
        let window = latency - DETECT_DELAY;
        let mut l = Self {
            sr,
            p: super::defaults(&params()),
            gain: Smooth::new(1.0, 0.02, sr),
            ceiling: 1.0,
            release: 0.0,
            true_peak: true,
            lines: [DelayLine::new(latency), DelayLine::new(latency)],
            latency,
            up: [detectors(), detectors()],
            wide: DelayLine::new(TAPS),
            raw: DelayLine::new(DETECT_DELAY + 2),
            last_seg: 0.0,
            last: [[[0.0; 2]; 2]; 2],
            queue_at: vec![0; window + 1],
            queue_gain: vec![1.0; window + 1],
            head: 0,
            count: 0,
            minima: vec![1.0; window],
            sum: window as f64,
            at: 0,
            frame: 0,
            held: 1.0,
            readings,
            started: false,
        };
        for i in 0..4 {
            l.apply(i);
        }
        l
    }

    fn apply(&mut self, index: usize) {
        let p = &self.p;
        match index {
            CEILING | TRUE_PEAK => {
                self.true_peak = p[TRUE_PEAK] >= 0.5;
                let margin = if self.true_peak {
                    TRUE_PEAK_MARGIN_DB
                } else {
                    0.0
                };
                self.ceiling = dsp::db_to_lin(p[CEILING].clamp(-60.0, 0.0) - margin);
            }
            GAIN => {
                self.gain.target = dsp::db_to_lin(p[GAIN].clamp(-24.0, 48.0));
                if !self.started {
                    self.gain.snap();
                }
            }
            RELEASE => {
                self.release = dsp::time_coef(p[RELEASE].max(0.1) * 0.001, self.sr);
            }
            _ => {}
        }
    }

    /// The peak the detector sees for the frame `DETECT_DELAY` back.
    #[inline]
    fn detect(&mut self, l: f32, r: f32) -> f32 {
        self.raw.push(l.abs().max(r.abs()));
        let sample = self.raw.get(DETECT_DELAY);
        if !self.true_peak {
            return sample;
        }
        let (mut seg, mut wide) = (0.0f32, 0.0f32);
        let mut buf = [0.0f32; OVERSAMPLE];
        for ((up, last), x) in self.up.iter_mut().zip(&mut self.last).zip([l, r]) {
            up[0].process(x, &mut buf);
            seg = seg.max(crest(&buf, &mut last[0]));
            up[1].process(x, &mut buf);
            wide = wide.max(crest(&buf, &mut last[1]));
        }
        self.wide.push(wide);
        let seg = seg.max(self.wide.get((TAPS - WIDE_TAPS) / 2));
        // The interpolated points of this frame and the one before cover
        // the stretch on either side of the frame being judged.
        let around = seg.max(self.last_seg);
        self.last_seg = seg;
        around.max(sample)
    }
}

impl Device for Limiter {
    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        self.started = true;
        let window = self.minima.len();
        let cap = self.queue_at.len();
        let ceiling = self.ceiling;
        let hard = dsp::db_to_lin(self.p[CEILING].clamp(-60.0, 0.0));
        let (mut most, mut peak_in) = (1.0f32, 0.0f32);
        for (l, r) in io.left.iter_mut().zip(io.right.iter_mut()) {
            let g = self.gain.step();
            let (in_l, in_r) = (*l * g, *r * g);
            peak_in = peak_in.max(in_l.abs()).max(in_r.abs());
            let peak = self.detect(in_l, in_r);
            let need = if peak > ceiling { ceiling / peak } else { 1.0 };
            // Down at once, back up slowly.
            self.held = need.min(1.0 - (1.0 - self.held) * self.release);

            // The smallest gain among this frame and the `window` before it.
            // The oldest goes first, so that the queue never holds more
            // than it has room for (a release rising every frame keeps
            // every entry).
            if self.count > 0 && self.queue_at[self.head] + (window as u64) < self.frame {
                self.head = (self.head + 1) % cap;
                self.count -= 1;
            }
            while self.count > 0 {
                let back = (self.head + self.count - 1) % cap;
                if self.queue_gain[back] < self.held {
                    break;
                }
                self.count -= 1;
            }
            let back = (self.head + self.count) % cap;
            self.queue_at[back] = self.frame;
            self.queue_gain[back] = self.held;
            self.count += 1;
            let smallest = self.queue_gain[self.head];

            self.sum += (smallest - self.minima[self.at]) as f64;
            self.minima[self.at] = smallest;
            let applied = ((self.sum / window as f64) as f32).min(1.0);
            self.at = (self.at + 1) % window;
            self.frame += 1;
            most = most.min(applied);

            self.lines[0].push(in_l);
            self.lines[1].push(in_r);
            let (out_l, out_r) = (
                self.lines[0].get(self.latency),
                self.lines[1].get(self.latency),
            );
            // The last word: no sample over the ceiling, ever.
            *l = (out_l * applied).clamp(-hard, hard);
            *r = (out_r * applied).clamp(-hard, hard);
        }
        self.held = dsp::flush(self.held - 1.0) + 1.0;
        self.readings.set(0, dsp::lin_to_db(most));
        self.readings.set(1, dsp::lin_to_db(peak_in));
    }

    fn set_param(&mut self, index: u32, value: f32) {
        let index = index as usize;
        if index < self.p.len() && value.is_finite() {
            self.p[index] = value;
            self.apply(index);
        }
    }
}

struct LimiterFace {
    sr: f32,
    readings: Arc<Readings<3>>,
}

impl Face for LimiterFace {
    /// `meters`: `gr`, the gain reduction of the latest block in dB (0 or
    /// below), and `input`, its peak after the input gain.
    fn call(&mut self, _values: &[f32], method: &str, _data: &[u8]) -> Result<Vec<u8>> {
        match method {
            "meters" => Ok(panel::fields(&[
                ("gr", self.readings.get(0) as f64),
                ("input", self.readings.get(1) as f64),
            ])),
            _ => anyhow::bail!("the limiter answers `meters`, not `{method}`"),
        }
    }

    fn latency(&self, _values: &[f32]) -> u32 {
        latency_frames(self.sr) as u32
    }
}

/// The highest true peak of a signal, interpolated `factor` times over with
/// a windowed sinc of `taps` input samples.
#[cfg(test)]
fn interpolated_peak<const F: usize>(x: &[f32], taps: usize, beta: f64) -> f32 {
    let mut up = Upsampler::design(F, taps, 1.0, beta);
    let mut buf = [0.0f32; F];
    let mut most = 0.0f32;
    for &v in x.iter().chain(std::iter::repeat_n(&0.0, taps)) {
        up.process(v, &mut buf);
        for b in buf {
            most = most.max(b.abs());
        }
    }
    most
}

/// True peak far more finely: 32 times over, 128 taps.
#[cfg(test)]
pub fn fine_peak(x: &[f32]) -> f32 {
    interpolated_peak::<32>(x, 128, 8.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::devices::testkit::*;

    /// Signals that make inter-sample peaks: sines near a quarter and half
    /// the rate at odd phases, a square, a clipped sine, alternating full
    /// scale, impulses, noise, and steps.
    fn nasty(sr: f32) -> Vec<(String, Vec<f32>)> {
        let n = (sr * 0.5) as usize;
        let mut out = Vec::new();
        for (f, phase) in [
            (sr / 4.0, 0.785),
            (sr / 4.0 * 0.999, 0.3),
            (sr * 0.49, 0.1),
            (11025.0, 0.5),
            (997.0, 0.0),
        ] {
            let s: Vec<f32> = (0..n)
                .map(|i| (std::f32::consts::TAU * f * i as f32 / sr + phase).sin() * 1.4)
                .collect();
            out.push((format!("sine {f}"), s));
        }
        out.push((
            "square".into(),
            (0..n)
                .map(|i| if (i / 7) % 2 == 0 { 1.0 } else { -1.0 })
                .collect(),
        ));
        out.push((
            "clipped".into(),
            (0..n)
                .map(|i| ((i as f32 * 0.3).sin() * 4.0).clamp(-1.0, 1.0))
                .collect(),
        ));
        out.push((
            "alternating".into(),
            (0..n)
                .map(|i| if i % 2 == 0 { 1.0 } else { -1.0 })
                .collect(),
        ));
        out.push((
            "pairs".into(),
            (0..n).map(|i| [1.0, 1.0, -1.0, -1.0][i % 4]).collect(),
        ));
        let mut imp = vec![0.0; n];
        for i in (100..n).step_by(997) {
            imp[i] = 1.0;
            imp[i + 1] = -1.0;
        }
        out.push(("impulses".into(), imp));
        out.push((
            "noise".into(),
            noise(n, 9).iter().map(|v| v * 4.0).collect(),
        ));
        let mut bursts = vec![0.0; n];
        for (i, v) in bursts.iter_mut().enumerate() {
            if (i / 2000) % 2 == 1 {
                *v = ((i as f32) * 2.1).sin() * 2.0;
            }
        }
        out.push(("bursts".into(), bursts));
        // Each ends in silence the limiter hears, rather than being cut off
        // while still inside it: a cut is a step that the measurement would
        // see ring.
        for (_, s) in &mut out {
            s.extend(std::iter::repeat_n(0.0, (sr * 0.05) as usize));
        }
        out
    }

    #[test]
    fn nothing_passes_the_ceiling_not_even_between_samples() {
        for sr in [44100.0, 48000.0, 96000.0] {
            for (name, signal) in nasty(sr) {
                for gain in [0.0, 12.0] {
                    let mut fx = Fx::new("limiter", sr);
                    fx.set("ceiling", -1.0);
                    fx.set("gain", gain);
                    let right: Vec<f32> = signal.iter().map(|v| -v * 0.7).collect();
                    let (l, r) = fx.run_stereo(&signal, &right, 256);
                    let ceiling = dsp::db_to_lin(-1.0);
                    // As `:analyze` reads the rendered file.
                    let tp = paw_measure::analyze(f64::from(sr), &l, &r).true_peak;
                    assert!(
                        tp <= -1.0,
                        "{name} at {sr} Hz, +{gain} dB: a true peak of {tp:.3} dBTP"
                    );
                    // Read far more finely, too, except for loud broadband
                    // noise: there the ideal reconstruction's peaks depend on
                    // samples further away than any look-ahead sees.
                    if name != "noise" {
                        let fine = fine_peak(&l).max(fine_peak(&r));
                        assert!(
                            fine <= ceiling,
                            "{name} at {sr} Hz, +{gain} dB: read finely, {:.3} dBTP",
                            dsp::lin_to_db(fine)
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn sample_peaks_hold_the_ceiling_exactly_with_true_peak_off() {
        let mut fx = Fx::new("limiter", 48000.0);
        fx.set("true_peak", 0.0);
        fx.set("ceiling", -6.0);
        for (name, signal) in nasty(48000.0) {
            fx.reset();
            let out = fx.run(&signal, 100);
            assert!(peak(&out) <= dsp::db_to_lin(-6.0), "{name}");
        }
    }

    #[test]
    fn quiet_audio_passes_unchanged_and_late_by_the_latency() {
        let sr = 48000.0;
        let mut fx = Fx::new("limiter", sr);
        let input = noise(10000, 4).iter().map(|v| v * 0.5).collect::<Vec<_>>();
        let out = fx.run(&input, 64);
        let late = fx.latency() as usize;
        assert_eq!(late, 240, "5 ms at 48 kHz");
        assert_eq!(&out[late..], &input[..input.len() - late]);
    }

    #[test]
    fn a_loud_passage_is_held_at_the_ceiling_and_released() {
        let sr = 48000.0;
        let mut fx = Fx::new("limiter", sr);
        fx.set("true_peak", 0.0);
        fx.set("ceiling", -3.0);
        fx.set("release", 50.0);
        let mut input = sine(1000.0, sr, 24000, 1.0);
        input.extend(sine(1000.0, sr, 48000, 0.25));
        let out = fx.run(&input, 128);
        let held = peak(&out[10000..24000]);
        assert!(
            (dsp::lin_to_db(held) + 3.0).abs() < 0.05,
            "held at the ceiling: {}",
            dsp::lin_to_db(held)
        );
        assert!(
            fx.field("meters", "gr") > -0.01,
            "the quiet part ends up untouched"
        );
        let after = peak(&out[24000 + 240 + 20000..]);
        assert!(
            (after - 0.25).abs() < 0.002,
            "and comes back to its level after the release: {after}"
        );
    }
}
