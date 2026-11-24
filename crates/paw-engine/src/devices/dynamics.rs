//! Dynamics: a compressor and a gate/expander that share a detector.
//!
//! Both work in decibels. The [`Detector`] turns the (high-passed) input
//! into a level per channel, peak or RMS, linked between the channels as
//! far as asked. A gain computer turns the level into the gain change the
//! settings call for, and a one-pole smoother in dB gives it its attack and
//! release: the gain covers 63 % of the way to a new target in one time
//! constant. Looking ahead delays the audio, not the detector, so the gain
//! is already down when a peak arrives; the delay is reported as latency.

use anyhow::Result;

use super::dsp::{self, DelayLine, Readings, Shape, Smooth, Svf, SvfCoefs, time_coef};
use super::panel::{self, Face, Pair};
use crate::device::{Device, Io, ParamInfo, ProcessCtx};

/// The longest look-ahead, in milliseconds.
pub const MAX_LOOKAHEAD_MS: f32 = 10.0;
/// Time constant of the RMS detector.
const RMS_SECONDS: f32 = 0.01;
/// Readings: gain reduction (dB, 0 or below), input and output peaks (dB).
const GR: usize = 0;
const IN: usize = 1;
const OUT: usize = 2;

/// The level of each channel, as the gain computers see it.
struct Detector {
    sr: f32,
    hp: Option<SvfCoefs>,
    hp_state: [Svf; 2],
    rms: bool,
    mean: [f32; 2],
    rms_coef: f32,
    /// 0 for each channel on its own, 1 for both from the louder.
    link: f32,
}

impl Detector {
    fn new(sr: f32) -> Self {
        Self {
            sr,
            hp: None,
            hp_state: Default::default(),
            rms: false,
            mean: [0.0; 2],
            rms_coef: time_coef(RMS_SECONDS, sr),
            link: 1.0,
        }
    }

    /// High-pass the detector at `freq`; 20 Hz and below is off.
    fn set_hp(&mut self, freq: f32) {
        self.hp = (freq > 20.5).then(|| SvfCoefs::new(Shape::High, freq, 0.71, 0.0, self.sr));
    }

    /// Levels in dB of one stereo frame; `heard` is left with the frame as
    /// the detector hears it, after its high-pass.
    #[inline]
    fn level(&mut self, l: f32, r: f32, heard: &mut [f32; 2]) -> [f32; 2] {
        let mut x = [l, r];
        if let Some(c) = &self.hp {
            x[0] = self.hp_state[0].tick(c, x[0]);
            x[1] = self.hp_state[1].tick(c, x[1]);
        }
        *heard = x;
        let mut level = [0.0; 2];
        for ch in 0..2 {
            level[ch] = if self.rms {
                let sq = x[ch] * x[ch];
                self.mean[ch] = sq + (self.mean[ch] - sq) * self.rms_coef;
                // Mean square to dB, scaled so a sine reads its peak level as
                // a peak detector would: +3 dB.
                10.0 * self.mean[ch].max(1e-20).log10() + 3.0103
            } else {
                20.0 * x[ch].abs().max(1e-10).log10()
            };
        }
        let loud = level[0].max(level[1]);
        [
            level[0] + (loud - level[0]) * self.link,
            level[1] + (loud - level[1]) * self.link,
        ]
    }

    fn flush(&mut self) {
        for s in &mut self.hp_state {
            s.flush();
        }
        for m in &mut self.mean {
            *m = dsp::flush(*m);
        }
    }
}

/// Audio held back by the look-ahead.
struct Lookahead {
    lines: [DelayLine; 2],
    frames: usize,
}

impl Lookahead {
    fn new(sr: f32) -> Self {
        let max = (MAX_LOOKAHEAD_MS * 0.001 * sr).ceil() as usize + 1;
        Self {
            lines: [DelayLine::new(max), DelayLine::new(max)],
            frames: 0,
        }
    }

    #[inline]
    fn tick(&mut self, l: f32, r: f32) -> (f32, f32) {
        self.lines[0].push(l);
        self.lines[1].push(r);
        (
            self.lines[0].get(self.frames),
            self.lines[1].get(self.frames),
        )
    }
}

fn lookahead_frames(ms: f32, sr: f32) -> u32 {
    (ms.clamp(0.0, MAX_LOOKAHEAD_MS) * 0.001 * sr).round() as u32
}

// ---------------------------------------------------------------------------
// Compressor

const C_THRESHOLD: usize = 0;
const C_RATIO: usize = 1;
const C_KNEE: usize = 2;
const C_ATTACK: usize = 3;
const C_RELEASE: usize = 4;
const C_AUTO_RELEASE: usize = 5;
const C_MAKEUP: usize = 6;
const C_AUTO_MAKEUP: usize = 7;
const C_LOOKAHEAD: usize = 8;
const C_HP: usize = 9;
const C_DETECT: usize = 10;
const C_MIX: usize = 11;
const C_LINK: usize = 12;
const C_LISTEN: usize = 13;

/// The detector's input for a frame: the side-chain when one is connected,
/// else the device's own input.
#[inline]
fn key_at(key: Option<[&[f32]; 2]>, i: usize, l: f32, r: f32) -> (f32, f32) {
    match key {
        Some([kl, kr]) => (kl[i], kr[i]),
        None => (l, r),
    }
}

pub fn compressor_params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::new("threshold")
            .name("Threshold")
            .range(-60.0, 0.0)
            .default_value(-18.0)
            .unit("dB"),
        ParamInfo::new("ratio")
            .name("Ratio")
            .range(1.0, 50.0)
            .default_value(2.0)
            .unit(":1"),
        ParamInfo::new("knee")
            .name("Knee")
            .range(0.0, 24.0)
            .default_value(6.0)
            .unit("dB"),
        ParamInfo::new("attack")
            .name("Attack")
            .range(0.05, 200.0)
            .default_value(10.0)
            .unit("ms"),
        ParamInfo::new("release")
            .name("Release")
            .range(5.0, 2000.0)
            .default_value(150.0)
            .unit("ms"),
        ParamInfo::choice("auto_release", &["Off", "On"], 0).name("Auto release"),
        ParamInfo::new("makeup")
            .name("Make-up")
            .range(-12.0, 24.0)
            .default_value(0.0)
            .unit("dB"),
        ParamInfo::choice("auto_makeup", &["Off", "On"], 0).name("Auto make-up"),
        ParamInfo::new("lookahead")
            .name("Look-ahead")
            .range(0.0, MAX_LOOKAHEAD_MS)
            .default_value(0.0)
            .unit("ms"),
        ParamInfo::new("detector_hp")
            .name("Detector HP")
            .range(20.0, 500.0)
            .default_value(20.0)
            .unit("Hz"),
        ParamInfo::choice("detect", &["Peak", "RMS"], 0).name("Detect"),
        ParamInfo::new("mix")
            .name("Mix")
            .range(0.0, 100.0)
            .default_value(100.0)
            .unit("%"),
        ParamInfo::new("link")
            .name("Stereo link")
            .range(0.0, 100.0)
            .default_value(100.0)
            .unit("%"),
        ParamInfo::choice("listen", &["Off", "On"], 0).name("Listen to key"),
    ]
}

/// The static curve: gain change in dB (0 or below) for an input level,
/// with a soft knee of `knee` dB centred on the threshold.
pub fn compress_gain(level: f32, threshold: f32, ratio: f32, knee: f32) -> f32 {
    let slope = 1.0 / ratio.max(1.0) - 1.0;
    let over = level - threshold;
    if knee > 0.0 && 2.0 * over.abs() <= knee {
        slope * (over + knee * 0.5).powi(2) / (2.0 * knee)
    } else if over > 0.0 {
        slope * over
    } else {
        0.0
    }
}

/// The ratio a setting stands for: the top of the range is a limit.
fn ratio_of(value: f32) -> f32 {
    if value >= 50.0 { 1e6 } else { value.max(1.0) }
}

/// Make-up that brings a 0 dBFS peak back halfway: what the auto make-up gives.
pub fn auto_makeup(threshold: f32, ratio: f32, knee: f32) -> f32 {
    -0.5 * compress_gain(0.0, threshold, ratio_of(ratio), knee)
}

pub fn compressor(sr: f32) -> Pair {
    let readings = Readings::new();
    (
        Box::new(Compressor::new(sr, readings.clone())),
        Box::new(DynamicsFace {
            sr,
            readings,
            gate: false,
        }),
    )
}

pub struct Compressor {
    sr: f32,
    p: [f32; 14],
    detector: Detector,
    ahead: Lookahead,
    attack: f32,
    release: f32,
    /// Gain change per channel, in dB: the fast follower, and the slow one
    /// for the automatic release.
    gr: [f32; 2],
    slow: [f32; 2],
    makeup: Smooth,
    mix: Smooth,
    readings: std::sync::Arc<Readings<3>>,
    started: bool,
}

/// Automatic release: a fast follower for transients over a slow one
/// that settles at the sustained gain reduction and lets go of it slowly.
const AUTO_FAST: f32 = 0.05;
const AUTO_SLOW_ATTACK: f32 = 0.5;
const AUTO_SLOW_RELEASE: f32 = 1.5;

impl Compressor {
    fn new(sr: f32, readings: std::sync::Arc<Readings<3>>) -> Self {
        let mut c = Self {
            sr,
            p: super::defaults(&compressor_params()),
            detector: Detector::new(sr),
            ahead: Lookahead::new(sr),
            attack: 0.0,
            release: 0.0,
            gr: [0.0; 2],
            slow: [0.0; 2],
            makeup: Smooth::new(1.0, 0.02, sr),
            mix: Smooth::new(1.0, 0.02, sr),
            readings,
            started: false,
        };
        for i in 0..c.p.len() {
            c.apply(i);
        }
        c
    }

    fn apply(&mut self, index: usize) {
        let p = &self.p;
        match index {
            C_ATTACK | C_RELEASE | C_AUTO_RELEASE => {
                self.attack = time_coef(p[C_ATTACK] * 0.001, self.sr);
                self.release = if p[C_AUTO_RELEASE] >= 0.5 {
                    time_coef(AUTO_FAST, self.sr)
                } else {
                    time_coef(p[C_RELEASE] * 0.001, self.sr)
                };
            }
            C_LOOKAHEAD => self.ahead.frames = lookahead_frames(p[C_LOOKAHEAD], self.sr) as usize,
            C_HP => self.detector.set_hp(p[C_HP]),
            C_DETECT => self.detector.rms = p[C_DETECT] >= 0.5,
            C_LINK => self.detector.link = (p[C_LINK] * 0.01).clamp(0.0, 1.0),
            C_MIX => self.mix.target = (p[C_MIX] * 0.01).clamp(0.0, 1.0),
            _ => {}
        }
        if matches!(
            index,
            C_MAKEUP | C_AUTO_MAKEUP | C_THRESHOLD | C_RATIO | C_KNEE
        ) {
            let auto = if p[C_AUTO_MAKEUP] >= 0.5 {
                auto_makeup(p[C_THRESHOLD], p[C_RATIO], p[C_KNEE])
            } else {
                0.0
            };
            self.makeup.target = dsp::db_to_lin(p[C_MAKEUP] + auto);
        }
        if !self.started {
            self.makeup.snap();
            self.mix.snap();
        }
    }
}

impl Device for Compressor {
    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        self.started = true;
        let (threshold, ratio, knee) = (
            self.p[C_THRESHOLD],
            ratio_of(self.p[C_RATIO]),
            self.p[C_KNEE],
        );
        let auto = self.p[C_AUTO_RELEASE] >= 0.5;
        let (slow_attack, slow_release) = (
            time_coef(AUTO_SLOW_ATTACK, self.sr),
            time_coef(AUTO_SLOW_RELEASE, self.sr),
        );
        let (mut most, mut peak_in, mut peak_out) = (0.0f32, 0.0f32, 0.0f32);
        let key = io.sidechain;
        let listen = key.is_some() && self.p[C_LISTEN] >= 0.5;
        let mut heard = [0.0; 2];
        for (i, (l, r)) in io.left.iter_mut().zip(io.right.iter_mut()).enumerate() {
            let (kl, kr) = key_at(key, i, *l, *r);
            let level = self.detector.level(kl, kr, &mut heard);
            peak_in = peak_in.max(l.abs()).max(r.abs());
            let (dl, dr) = self.ahead.tick(*l, *r);
            let makeup = self.makeup.step();
            let mix = self.mix.step();
            let mut out = [dl, dr];
            for ch in 0..2 {
                let target = compress_gain(level[ch], threshold, ratio, knee);
                let g = &mut self.gr[ch];
                let coef = if target < *g {
                    self.attack
                } else {
                    self.release
                };
                *g = target + (*g - target) * coef;
                let mut gr = *g;
                if auto {
                    let s = &mut self.slow[ch];
                    let coef = if target < *s {
                        slow_attack
                    } else {
                        slow_release
                    };
                    *s = target + (*s - target) * coef;
                    gr = gr.min(*s);
                }
                most = most.min(gr);
                let wet = out[ch] * dsp::db_to_lin(gr) * makeup;
                out[ch] += (wet - out[ch]) * mix;
            }
            // Listening plays what the detector hears instead.
            if listen {
                out = heard;
            }
            *l = out[0];
            *r = out[1];
            peak_out = peak_out.max(l.abs()).max(r.abs());
        }
        self.detector.flush();
        for g in self.gr.iter_mut().chain(self.slow.iter_mut()) {
            *g = dsp::flush(*g);
        }
        self.readings.set(GR, most);
        self.readings.set(IN, dsp::lin_to_db(peak_in));
        self.readings.set(OUT, dsp::lin_to_db(peak_out));
    }

    fn set_param(&mut self, index: u32, value: f32) {
        let index = index as usize;
        if index < self.p.len() && value.is_finite() {
            self.p[index] = value;
            self.apply(index);
        }
    }
}

// ---------------------------------------------------------------------------
// Gate / expander

const G_MODE: usize = 0;
const G_THRESHOLD: usize = 1;
const G_RANGE: usize = 2;
const G_RATIO: usize = 3;
const G_ATTACK: usize = 4;
const G_HOLD: usize = 5;
const G_RELEASE: usize = 6;
const G_HYSTERESIS: usize = 7;
const G_LOOKAHEAD: usize = 8;
const G_HP: usize = 9;
const G_DETECT: usize = 10;
const G_LINK: usize = 11;
const G_LISTEN: usize = 12;

pub fn gate_params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::choice("mode", &["Gate", "Expander"], 0).name("Mode"),
        ParamInfo::new("threshold")
            .name("Threshold")
            .range(-80.0, 0.0)
            .default_value(-50.0)
            .unit("dB"),
        ParamInfo::new("range")
            .name("Range")
            .range(-80.0, 0.0)
            .default_value(-60.0)
            .unit("dB"),
        ParamInfo::new("ratio")
            .name("Ratio")
            .range(1.0, 20.0)
            .default_value(4.0)
            .unit(":1"),
        ParamInfo::new("attack")
            .name("Attack")
            .range(0.05, 100.0)
            .default_value(0.5)
            .unit("ms"),
        ParamInfo::new("hold")
            .name("Hold")
            .range(0.0, 1000.0)
            .default_value(30.0)
            .unit("ms"),
        ParamInfo::new("release")
            .name("Release")
            .range(5.0, 2000.0)
            .default_value(120.0)
            .unit("ms"),
        ParamInfo::new("hysteresis")
            .name("Hysteresis")
            .range(0.0, 12.0)
            .default_value(3.0)
            .unit("dB"),
        ParamInfo::new("lookahead")
            .name("Look-ahead")
            .range(0.0, MAX_LOOKAHEAD_MS)
            .default_value(0.0)
            .unit("ms"),
        ParamInfo::new("detector_hp")
            .name("Detector HP")
            .range(20.0, 2000.0)
            .default_value(20.0)
            .unit("Hz"),
        ParamInfo::choice("detect", &["Peak", "RMS"], 0).name("Detect"),
        ParamInfo::new("link")
            .name("Stereo link")
            .range(0.0, 100.0)
            .default_value(100.0)
            .unit("%"),
        ParamInfo::choice("listen", &["Off", "On"], 0).name("Listen to key"),
    ]
}

pub fn gate(sr: f32) -> Pair {
    let readings = Readings::new();
    (
        Box::new(Gate::new(sr, readings.clone())),
        Box::new(DynamicsFace {
            sr,
            readings,
            gate: true,
        }),
    )
}

pub struct Gate {
    sr: f32,
    p: [f32; 13],
    detector: Detector,
    ahead: Lookahead,
    attack: f32,
    release: f32,
    hold_frames: u32,
    /// Per channel: open or not, frames left to hold, gain in dB.
    open: [bool; 2],
    held: [u32; 2],
    gain: [f32; 2],
    readings: std::sync::Arc<Readings<3>>,
}

impl Gate {
    fn new(sr: f32, readings: std::sync::Arc<Readings<3>>) -> Self {
        let p = super::defaults(&gate_params());
        let mut g = Self {
            sr,
            p,
            detector: Detector::new(sr),
            ahead: Lookahead::new(sr),
            attack: 0.0,
            release: 0.0,
            hold_frames: 0,
            open: [false; 2],
            held: [0; 2],
            gain: [p[G_RANGE]; 2],
            readings,
        };
        for i in 0..g.p.len() {
            g.apply(i);
        }
        g
    }

    fn apply(&mut self, index: usize) {
        let p = &self.p;
        match index {
            G_ATTACK => self.attack = time_coef(p[G_ATTACK] * 0.001, self.sr),
            G_RELEASE => self.release = time_coef(p[G_RELEASE] * 0.001, self.sr),
            G_HOLD => self.hold_frames = (p[G_HOLD].max(0.0) * 0.001 * self.sr) as u32,
            G_LOOKAHEAD => self.ahead.frames = lookahead_frames(p[G_LOOKAHEAD], self.sr) as usize,
            G_HP => self.detector.set_hp(p[G_HP]),
            G_DETECT => self.detector.rms = p[G_DETECT] >= 0.5,
            G_LINK => self.detector.link = (p[G_LINK] * 0.01).clamp(0.0, 1.0),
            _ => {}
        }
    }
}

/// The gate's gain in dB for a level, given whether it is open.
pub fn expand_gain(level: f32, threshold: f32, range: f32, ratio: f32) -> f32 {
    if level >= threshold {
        0.0
    } else {
        ((level - threshold) * (ratio.max(1.0) - 1.0)).max(range)
    }
}

impl Device for Gate {
    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        let p = self.p;
        let expander = p[G_MODE] >= 0.5;
        let (threshold, range) = (p[G_THRESHOLD], p[G_RANGE].min(0.0));
        let close_at = threshold - p[G_HYSTERESIS].max(0.0);
        let (mut most, mut peak_in, mut peak_out) = (0.0f32, 0.0f32, 0.0f32);
        let key = io.sidechain;
        let listen = key.is_some() && p[G_LISTEN] >= 0.5;
        let mut heard = [0.0; 2];
        for (i, (l, r)) in io.left.iter_mut().zip(io.right.iter_mut()).enumerate() {
            let (kl, kr) = key_at(key, i, *l, *r);
            let level = self.detector.level(kl, kr, &mut heard);
            peak_in = peak_in.max(l.abs()).max(r.abs());
            let (dl, dr) = self.ahead.tick(*l, *r);
            let mut out = [dl, dr];
            for ch in 0..2 {
                let target = if expander {
                    expand_gain(level[ch], threshold, range, p[G_RATIO])
                } else {
                    // Opens above the threshold; closes once below it by the
                    // hysteresis for longer than the hold.
                    if level[ch] >= threshold {
                        self.open[ch] = true;
                        self.held[ch] = self.hold_frames;
                    } else if level[ch] >= close_at && self.open[ch] {
                        self.held[ch] = self.hold_frames;
                    } else if self.held[ch] > 0 {
                        self.held[ch] -= 1;
                    } else {
                        self.open[ch] = false;
                    }
                    if self.open[ch] { 0.0 } else { range }
                };
                let g = &mut self.gain[ch];
                let coef = if target > *g {
                    self.attack
                } else {
                    self.release
                };
                *g = target + (*g - target) * coef;
                most = most.min(*g);
                out[ch] *= dsp::db_to_lin(*g);
            }
            if listen {
                out = heard;
            }
            *l = out[0];
            *r = out[1];
            peak_out = peak_out.max(l.abs()).max(r.abs());
        }
        self.detector.flush();
        for g in &mut self.gain {
            *g = dsp::flush(*g);
        }
        self.readings.set(GR, most);
        self.readings.set(IN, dsp::lin_to_db(peak_in));
        self.readings.set(OUT, dsp::lin_to_db(peak_out));
    }

    fn set_param(&mut self, index: u32, value: f32) {
        let index = index as usize;
        if index < self.p.len() && value.is_finite() {
            self.p[index] = value;
            self.apply(index);
        }
    }
}

struct DynamicsFace {
    sr: f32,
    readings: std::sync::Arc<Readings<3>>,
    gate: bool,
}

impl Face for DynamicsFace {
    /// `meters`: `gr` (gain change in dB, 0 or below), `input` and `output`
    /// (peak dB) of the latest block. `curve [n]`: the output level in dB
    /// for `n` input levels from -60 to 0 dB (the static curve).
    fn call(&mut self, values: &[f32], method: &str, data: &[u8]) -> Result<Vec<u8>> {
        match method {
            "meters" => Ok(panel::fields(&[
                ("gr", self.readings.get(GR) as f64),
                ("input", self.readings.get(IN) as f64),
                ("output", self.readings.get(OUT) as f64),
            ])),
            "curve" => {
                let n = panel::count(data, 61, 1000);
                let points = (0..n).map(|i| {
                    let level = -60.0 + 60.0 * i as f32 / (n - 1) as f32;
                    let change = if self.gate {
                        let v = values;
                        let ratio = if v[G_MODE] >= 0.5 { v[G_RATIO] } else { 1e6 };
                        expand_gain(level, v[G_THRESHOLD], v[G_RANGE].min(0.0), ratio)
                    } else {
                        let v = values;
                        let auto = if v[C_AUTO_MAKEUP] >= 0.5 {
                            auto_makeup(v[C_THRESHOLD], v[C_RATIO], v[C_KNEE])
                        } else {
                            0.0
                        };
                        compress_gain(level, v[C_THRESHOLD], ratio_of(v[C_RATIO]), v[C_KNEE])
                            + v[C_MAKEUP]
                            + auto
                    };
                    (level + change) as f64
                });
                Ok(panel::numbers(points, 2))
            }
            _ => anyhow::bail!("this device answers `meters` and `curve`, not `{method}`"),
        }
    }

    fn latency(&self, values: &[f32]) -> u32 {
        let at = if self.gate { G_LOOKAHEAD } else { C_LOOKAHEAD };
        lookahead_frames(values[at], self.sr)
    }

    fn sidechain(&self) -> bool {
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::devices::testkit::*;

    fn steady(level_db: f32, n: usize) -> Vec<f32> {
        // A square wave at a steady peak level: peak and RMS agree.
        let a = dsp::db_to_lin(level_db);
        (0..n)
            .map(|i| if (i / 50) % 2 == 0 { a } else { -a })
            .collect()
    }

    #[test]
    fn the_static_curve_is_the_textbook_one() {
        assert_eq!(compress_gain(-30.0, -20.0, 4.0, 0.0), 0.0);
        assert!((compress_gain(-10.0, -20.0, 4.0, 0.0) + 7.5).abs() < 1e-6);
        // In the knee: a quarter of the way, at the threshold.
        assert!((compress_gain(-20.0, -20.0, 4.0, 10.0) + 0.75 * 25.0 / 20.0).abs() < 1e-5);
        // Continuous at the knee's edges.
        let k = 12.0;
        assert!(compress_gain(-26.0, -20.0, 4.0, k).abs() < 1e-6);
        assert!(
            (compress_gain(-14.0, -20.0, 4.0, k) - compress_gain(-14.0, -20.0, 4.0, 0.0)).abs()
                < 1e-5
        );
    }

    #[test]
    fn a_steady_level_settles_on_the_static_curve() {
        for sr in [44100.0, 48000.0, 96000.0] {
            for (level, ratio, knee) in [(-6.0, 4.0, 0.0), (-12.0, 2.0, 6.0), (-3.0, 10.0, 12.0)] {
                let mut fx = Fx::new("compressor", sr);
                fx.set("threshold", -20.0);
                fx.set("ratio", ratio);
                fx.set("knee", knee);
                let input = steady(level, sr as usize);
                let out = fx.run(&input, 256);
                let got = dsp::lin_to_db(peak(&out[out.len() - 1000..]));
                let want = level + compress_gain(level, -20.0, ratio, knee);
                assert!(
                    (got - want).abs() < 0.05,
                    "{level} dB at {ratio}:1 knee {knee}: {got} not {want}"
                );
                assert!((fx.field("meters", "gr") as f32 - (want - level)).abs() < 0.05);
            }
        }
    }

    #[test]
    fn attack_and_release_take_their_time_constants() {
        let sr = 48000.0;
        let mut fx = Fx::new("compressor", sr);
        fx.set("threshold", -20.0);
        fx.set("ratio", 50.0);
        fx.set("knee", 0.0);
        fx.set("attack", 10.0);
        fx.set("release", 100.0);
        // A step from quiet to 0 dB: 20 dB of reduction to reach.
        let mut input = vec![dsp::db_to_lin(-40.0); 4800];
        input.extend(vec![1.0; 48000]);
        input.extend(vec![dsp::db_to_lin(-40.0); 48000]);
        let out = fx.run(&input, 64);
        let gr = |i: usize| dsp::lin_to_db(out[i].abs() / input[i].abs());
        // 63 % of the way after one time constant.
        let reached = (4800..)
            .find(|&i| gr(i) < -20.0 * (1.0 - (-1.0f32).exp()))
            .unwrap()
            - 4800;
        assert!(
            (reached as f32 / sr * 1000.0 - 10.0).abs() < 0.3,
            "attack took {reached} frames"
        );
        let start = 4800 + 48000;
        let back = (start..)
            .find(|&i| gr(i) > -20.0 * (-1.0f32).exp())
            .unwrap()
            - start;
        assert!(
            (back as f32 / sr * 1000.0 - 100.0).abs() < 2.0,
            "release took {back} frames"
        );
    }

    #[test]
    fn mix_at_zero_and_a_high_threshold_are_transparent() {
        let input = noise(20000, 5);
        let mut fx = Fx::new("compressor", 48000.0);
        fx.set("mix", 0.0);
        fx.set("threshold", -60.0);
        assert_eq!(
            fx.run(&input, 100),
            input,
            "a dry mix passes the input exactly"
        );
        let mut fx = Fx::new("compressor", 48000.0);
        fx.set("threshold", 0.0);
        fx.set("knee", 0.0);
        assert_eq!(
            fx.run(&input, 100),
            input,
            "nothing over the threshold, nothing changed"
        );
    }

    #[test]
    fn look_ahead_is_latency_and_catches_the_peak() {
        let sr = 48000.0;
        let mut fx = Fx::new("compressor", sr);
        fx.set("lookahead", 5.0);
        fx.set("threshold", -20.0);
        fx.set("ratio", 50.0);
        fx.set("attack", 1.0);
        fx.set("mix", 0.0);
        assert_eq!(fx.latency(), 240);
        let mut input = vec![0.0; 2000];
        input[100] = 0.5;
        let out = fx.run(&input, 64);
        assert_eq!(
            out[340], 0.5,
            "the dry signal is late by exactly the latency"
        );
        fx.set("mix", 100.0);
        fx.reset();
        let mut burst = vec![0.0; 4000];
        for (i, v) in burst.iter_mut().enumerate().skip(1000) {
            *v = if i % 2 == 0 { 1.0 } else { -1.0 };
        }
        let out = fx.run(&burst, 64);
        let first = dsp::lin_to_db(out[1240].abs());
        assert!(
            first < -10.0,
            "the gain is already down when the burst arrives: {first} dB"
        );
    }

    #[test]
    fn the_gate_opens_holds_and_closes() {
        let sr = 48000.0;
        let mut fx = Fx::new("gate", sr);
        fx.set("threshold", -30.0);
        fx.set("range", -80.0);
        fx.set("attack", 0.1);
        fx.set("hold", 50.0);
        fx.set("release", 10.0);
        let mut input = steady(-50.0, 4800);
        input.extend(steady(-10.0, 4800));
        input.extend(steady(-32.0, 4800)); // within the hysteresis: stays open
        input.extend(steady(-50.0, 9600));
        let out = fx.run(&input, 128);
        assert!(
            peak(&out[1000..4800]) < dsp::db_to_lin(-120.0),
            "closed below the threshold"
        );
        assert!(
            (peak(&out[6000..9600]) - dsp::db_to_lin(-10.0)).abs() < 1e-4,
            "open above it"
        );
        assert!(
            (peak(&out[9600..14400]) - dsp::db_to_lin(-32.0)).abs() < 1e-4,
            "held open by the hysteresis"
        );
        // Hold 50 ms, then closing with a 10 ms time constant.
        let held = &out[14400..14400 + 2300];
        assert!(
            (peak(held) - dsp::db_to_lin(-50.0)).abs() < 1e-5,
            "still open during the hold"
        );
        assert!(
            peak(&out[14400 + 2400 + 2400..]) < dsp::db_to_lin(-100.0),
            "then shut"
        );
        assert!(fx.field("meters", "gr") < -79.0);
    }

    #[test]
    fn the_expander_follows_its_ratio_down_to_its_range() {
        let sr = 48000.0;
        let mut fx = Fx::new("gate", sr);
        fx.set("mode", 1.0);
        fx.set("threshold", -30.0);
        fx.set("ratio", 2.0);
        fx.set("range", -20.0);
        for (level, want) in [(-20.0, -20.0), (-35.0, -40.0), (-60.0, -80.0)] {
            fx.reset();
            let out = fx.run(&steady(level, 48000), 256);
            let got = dsp::lin_to_db(peak(&out[40000..]));
            assert!(
                (got - want).abs() < 0.05,
                "{level} dB in: {got} out, not {want}"
            );
        }
    }
}
