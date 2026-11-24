//! Effects that move: chorus, flanger, phaser, tremolo and auto-pan, and
//! the delay.
//!
//! Each has a rate in Hz or, with `sync` set, a note length at the tempo
//! of the moment (asked of the engine every block, so it follows tempo
//! changes). While the song plays, a synced LFO is locked to the song's
//! position, so it lands the same way on every pass.

use super::dsp::{self, DelayLine, Lfo, NOTE_BEATS, Rest, Shape, Smooth, Svf, SvfCoefs};
use super::panel::{Face, Pair};
use crate::device::{Device, Io, ParamInfo, ProcessCtx};

struct NoFace;
impl Face for NoFace {}

/// The LFO's cycles per sample for this block.
fn lfo_step(rate_hz: f32, sync: f32, ctx: &ProcessCtx, sr: f32) -> f64 {
    match dsp::sync_seconds(sync, ctx.tempo) {
        Some(seconds) => 1.0 / (seconds as f64 * sr as f64),
        None => rate_hz.clamp(0.0, 50.0) as f64 / sr as f64,
    }
}

/// While playing in sync, the phase the song's position puts the LFO at.
fn locked_phase(sync: f32, ctx: &ProcessCtx) -> Option<f64> {
    let index = sync.round() as usize;
    if !ctx.playing || index == 0 || !ctx.position.is_finite() {
        return None;
    }
    let beats = NOTE_BEATS[(index - 1).min(NOTE_BEATS.len() - 1)];
    Some((ctx.position / beats).rem_euclid(1.0))
}

fn rate(default: f32) -> ParamInfo {
    ParamInfo::new("rate").name("Rate").range(0.02, 20.0).default_value(default).unit("Hz")
}

fn sync() -> ParamInfo {
    ParamInfo::choice("sync", &dsp::sync_choices(), 0).name("Sync")
}

// ---------------------------------------------------------------------------
// Chorus and flanger: a delay whose length the LFO moves.

const M_RATE: usize = 0;
const M_SYNC: usize = 1;
const M_DEPTH: usize = 2;
const M_DELAY: usize = 3;
const M_FEEDBACK: usize = 4;
const M_SPREAD: usize = 5;
const M_MIX: usize = 6;
const M_VOICES: usize = 7;

pub fn chorus_params() -> Vec<ParamInfo> {
    vec![
        rate(0.6),
        sync(),
        ParamInfo::new("depth").name("Depth").range(0.0, 100.0).default_value(40.0).unit("%"),
        ParamInfo::new("delay").name("Delay").range(2.0, 40.0).default_value(12.0).unit("ms"),
        ParamInfo::new("feedback").name("Feedback").range(-90.0, 90.0).default_value(0.0).unit("%"),
        ParamInfo::new("spread").name("Stereo").range(0.0, 180.0).default_value(90.0).unit("°"),
        ParamInfo::new("mix").name("Mix").range(0.0, 100.0).default_value(50.0).unit("%"),
        ParamInfo::choice("voices", &["1", "2", "3"], 1).name("Voices"),
    ]
}

pub fn flanger_params() -> Vec<ParamInfo> {
    vec![
        rate(0.2),
        sync(),
        ParamInfo::new("depth").name("Depth").range(0.0, 100.0).default_value(70.0).unit("%"),
        ParamInfo::new("delay").name("Delay").range(0.1, 10.0).default_value(1.0).unit("ms"),
        ParamInfo::new("feedback")
            .name("Feedback")
            .range(-95.0, 95.0)
            .default_value(50.0)
            .unit("%"),
        ParamInfo::new("spread").name("Stereo").range(0.0, 180.0).default_value(90.0).unit("°"),
        ParamInfo::new("mix").name("Mix").range(0.0, 100.0).default_value(50.0).unit("%"),
    ]
}

pub fn chorus(sr: f32) -> Pair {
    (
        Box::new(Modulated::new(sr, chorus_params(), 0.8)),
        Box::new(NoFace),
    )
}

pub fn flanger(sr: f32) -> Pair {
    (
        Box::new(Modulated::new(sr, flanger_params(), 1.0)),
        Box::new(NoFace),
    )
}

/// A chorus or flanger.
pub struct Modulated {
    sr: f32,
    p: [f32; 8],
    lines: [DelayLine; 2],
    last: [f32; 2],
    lfo: Lfo,
    /// How much of the base delay the depth can swing it by.
    swing: f32,
    base: Smooth,
    depth: Smooth,
    mix: Smooth,
    started: bool,
    rest: Rest,
}

impl Modulated {
    fn new(sr: f32, params: Vec<ParamInfo>, swing: f32) -> Self {
        let mut p = [0.0; 8];
        for (v, info) in p.iter_mut().zip(&params) {
            *v = info.default;
        }
        if params.len() <= M_VOICES {
            p[M_VOICES] = 0.0;
        }
        let max = (0.04 * 2.0 * sr) as usize + 8;
        let mut m = Self {
            sr,
            p,
            lines: [DelayLine::new(max), DelayLine::new(max)],
            last: [0.0; 2],
            lfo: Lfo::default(),
            swing,
            base: Smooth::new(0.0, 0.05, sr),
            depth: Smooth::new(0.0, 0.05, sr),
            mix: Smooth::new(0.0, 0.02, sr),
            started: false,
            rest: Rest::default(),
        };
        m.apply();
        m
    }

    fn apply(&mut self) {
        let p = &self.p;
        self.base.target = p[M_DELAY].clamp(0.05, 40.0) * 0.001 * self.sr;
        self.depth.target = (p[M_DEPTH] * 0.01).clamp(0.0, 1.0) * self.swing;
        self.mix.target = (p[M_MIX] * 0.01).clamp(0.0, 1.0);
        if !self.started {
            self.base.snap();
            self.depth.snap();
            self.mix.snap();
        }
    }
}

impl Device for Modulated {
    fn resting(&self) -> bool {
        self.rest.resting
    }

    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        if self.rest.sleeps(io) {
            return;
        }
        self.started = true;
        let memory = self.lines[0].capacity() as u32;
        let step = lfo_step(self.p[M_RATE], self.p[M_SYNC], ctx, self.sr);
        if let Some(phase) = locked_phase(self.p[M_SYNC], ctx) {
            self.lfo.phase = phase;
        }
        let spread = (self.p[M_SPREAD].clamp(0.0, 180.0) / 360.0) as f64;
        let voices = (self.p[M_VOICES].round().clamp(0.0, 2.0) as usize) + 1;
        let feedback = (self.p[M_FEEDBACK] * 0.01).clamp(-0.95, 0.95);
        let max = (self.lines[0].capacity() - 4) as f32;
        for (l, r) in io.left.iter_mut().zip(io.right.iter_mut()) {
            if self.rest.holds(*l, *r) {
                continue;
            }
            let phase = self.lfo.tick(step);
            let base = self.base.step();
            let depth = self.depth.step();
            let mix = self.mix.step();
            let (dry_l, dry_r) = (*l, *r);
            let mut level = 0.0f32;
            for (ch, x) in [&mut *l, &mut *r].into_iter().enumerate() {
                let mut wet = 0.0;
                for v in 0..voices {
                    let ph = phase + ch as f64 * spread + v as f64 / voices as f64;
                    // From the base delay up: the LFO swings 0..1.
                    let swing = 0.5 + 0.5 * dsp::sin_cycles(ph);
                    // Read before this frame is written: one frame less.
                    let delay = (base * (1.0 + depth * swing)).clamp(2.0, max);
                    wet += self.lines[ch].get_frac(delay - 1.0);
                }
                wet /= voices as f32;
                let push = *x + wet * feedback;
                level = level.max(push.abs()).max(wet.abs());
                self.lines[ch].push(dsp::flush(push));
                self.last[ch] = wet;
                *x += (wet - *x) * mix;
            }
            if self.rest.frame(dry_l, dry_r, level) >= memory
                && !self.rest.resting
                && !(self.base.moving() || self.depth.moving() || self.mix.moving())
            {
                self.lines.iter_mut().for_each(DelayLine::clear);
                self.last = [0.0; 2];
                self.rest.resting = true;
            }
        }
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
// Phaser: all-pass stages whose corner the LFO sweeps.

const P_RATE: usize = 0;
const P_SYNC: usize = 1;
const P_DEPTH: usize = 2;
const P_CENTER: usize = 3;
const P_STAGES: usize = 4;
const P_FEEDBACK: usize = 5;
const P_SPREAD: usize = 6;
const P_MIX: usize = 7;
const MAX_STAGES: usize = 12;
const STAGES: &[&str] = &["2", "4", "6", "8", "12"];

pub fn phaser_params() -> Vec<ParamInfo> {
    vec![
        rate(0.3),
        sync(),
        ParamInfo::new("depth").name("Depth").range(0.0, 100.0).default_value(60.0).unit("%"),
        ParamInfo::new("center")
            .name("Centre")
            .range(100.0, 4000.0)
            .default_value(800.0)
            .unit("Hz"),
        ParamInfo::choice("stages", STAGES, 1).name("Stages"),
        ParamInfo::new("feedback")
            .name("Feedback")
            .range(-95.0, 95.0)
            .default_value(40.0)
            .unit("%"),
        ParamInfo::new("spread").name("Stereo").range(0.0, 180.0).default_value(90.0).unit("°"),
        ParamInfo::new("mix").name("Mix").range(0.0, 100.0).default_value(50.0).unit("%"),
    ]
}

pub fn phaser(sr: f32) -> Pair {
    (Box::new(Phaser::new(sr)), Box::new(NoFace))
}

pub struct Phaser {
    sr: f32,
    p: [f32; 8],
    /// Each stage's state, per channel.
    state: [[f32; MAX_STAGES]; 2],
    last: [f32; 2],
    lfo: Lfo,
    mix: Smooth,
    started: bool,
    rest: Rest,
}

impl Phaser {
    fn new(sr: f32) -> Self {
        Self {
            sr,
            p: super::defaults(&phaser_params()),
            state: [[0.0; MAX_STAGES]; 2],
            last: [0.0; 2],
            lfo: Lfo::default(),
            mix: Smooth::new(0.5, 0.02, sr),
            started: false,
            rest: Rest::default(),
        }
    }
}

/// Frames a phaser's all-passes ring for at most, at the level they rest at.
const PHASER_MEMORY: u32 = 64;

impl Device for Phaser {
    fn resting(&self) -> bool {
        self.rest.resting
    }

    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        if self.rest.sleeps(io) {
            return;
        }
        if !self.started {
            self.mix.snap();
        }
        self.started = true;
        let p = self.p;
        let step = lfo_step(p[P_RATE], p[P_SYNC], ctx, self.sr);
        if let Some(phase) = locked_phase(p[P_SYNC], ctx) {
            self.lfo.phase = phase;
        }
        let stages = [2, 4, 6, 8, 12][(p[P_STAGES].round().clamp(0.0, 4.0)) as usize];
        // The depth sweeps up to three octaves either side of the centre.
        let octaves = (p[P_DEPTH] * 0.01).clamp(0.0, 1.0) * 3.0;
        let center = p[P_CENTER].clamp(20.0, 10000.0);
        let feedback = (p[P_FEEDBACK] * 0.01).clamp(-0.95, 0.95);
        let spread = (p[P_SPREAD].clamp(0.0, 180.0) / 360.0) as f64;
        let nyquist = self.sr * 0.45;
        for (l, r) in io.left.iter_mut().zip(io.right.iter_mut()) {
            if self.rest.holds(*l, *r) {
                continue;
            }
            let phase = self.lfo.tick(step);
            let mix = self.mix.step();
            let (dry_l, dry_r) = (*l, *r);
            let mut level = 0.0f32;
            for (ch, x) in [&mut *l, &mut *r].into_iter().enumerate() {
                let sweep = dsp::sin_cycles(phase + ch as f64 * spread);
                let f = (center * (octaves * sweep).exp2()).clamp(10.0, nyquist);
                let t = (std::f32::consts::PI * f / self.sr).tan();
                let a = (t - 1.0) / (t + 1.0);
                let mut y = *x + self.last[ch] * feedback;
                for s in &mut self.state[ch][..stages] {
                    // First-order all-pass, transposed direct form II.
                    let out = a * y + *s;
                    *s = dsp::flush(y - a * out);
                    level = level.max(s.abs());
                    y = out;
                }
                let y = dsp::flush(y);
                level = level.max(y.abs());
                self.last[ch] = y;
                *x += (y - *x) * mix;
            }
            if self.rest.frame(dry_l, dry_r, level) >= PHASER_MEMORY
                && !self.rest.resting
                && !self.mix.moving()
            {
                self.state = [[0.0; MAX_STAGES]; 2];
                self.last = [0.0; 2];
                self.rest.resting = true;
            }
        }
    }

    fn set_param(&mut self, index: u32, value: f32) {
        let index = index as usize;
        if index < self.p.len() && value.is_finite() {
            self.p[index] = value;
            self.rest.wake();
            if index == P_MIX {
                self.mix.target = (value * 0.01).clamp(0.0, 1.0);
                if !self.started {
                    self.mix.snap();
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Tremolo and auto-pan.

const T_MODE: usize = 0;
const T_RATE: usize = 1;
const T_SYNC: usize = 2;
const T_DEPTH: usize = 3;
const T_SHAPE: usize = 4;

pub fn tremolo_params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::choice("mode", &["Tremolo", "Auto-pan"], 0).name("Mode"),
        rate(5.0),
        sync(),
        ParamInfo::new("depth").name("Depth").range(0.0, 100.0).default_value(50.0).unit("%"),
        ParamInfo::choice("shape", &["Sine", "Triangle", "Square"], 0).name("Shape"),
    ]
}

pub fn tremolo(sr: f32) -> Pair {
    (Box::new(Tremolo::new(sr)), Box::new(NoFace))
}

pub struct Tremolo {
    sr: f32,
    p: [f32; 5],
    lfo: Lfo,
    depth: Smooth,
    started: bool,
    rest: Rest,
}

impl Tremolo {
    fn new(sr: f32) -> Self {
        let p = super::defaults(&tremolo_params());
        Self {
            sr,
            p,
            lfo: Lfo::default(),
            depth: Smooth::new(p[T_DEPTH] * 0.01, 0.02, sr),
            started: false,
            rest: Rest::default(),
        }
    }
}

/// The LFO's shape at `phase`, from -1 to 1. The square is softened over a
/// twentieth of the cycle so that it does not click.
fn wave(shape: usize, phase: f64) -> f32 {
    let ph = phase.rem_euclid(1.0) as f32;
    match shape {
        1 => 1.0 - 4.0 * (ph - 0.5).abs() + 0.0,
        2 => ((dsp::sin_cycles(phase)) * 8.0).clamp(-1.0, 1.0),
        _ => dsp::sin_cycles(phase),
    }
}

impl Device for Tremolo {
    fn resting(&self) -> bool {
        self.rest.resting
    }

    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        if self.rest.sleeps(io) {
            return;
        }
        if !self.started {
            self.depth.snap();
        }
        self.started = true;
        let p = self.p;
        let step = lfo_step(p[T_RATE], p[T_SYNC], ctx, self.sr);
        if let Some(phase) = locked_phase(p[T_SYNC], ctx) {
            self.lfo.phase = phase;
        }
        let shape = p[T_SHAPE].round().clamp(0.0, 2.0) as usize;
        let pan = p[T_MODE] >= 0.5;
        for (l, r) in io.left.iter_mut().zip(io.right.iter_mut()) {
            if self.rest.holds(*l, *r) {
                continue;
            }
            let w = wave(shape, self.lfo.tick(step));
            let depth = self.depth.step();
            // It holds nothing: silence in is silence out.
            if self.rest.frame(*l, *r, 0.0) > 0 && !self.rest.resting && !self.depth.moving() {
                self.rest.resting = true;
            }
            if pan {
                // Equal power across the field, as far out as the depth.
                let angle = (1.0 + w * depth) * std::f32::consts::FRAC_PI_4;
                let s = std::f32::consts::SQRT_2;
                *l *= angle.cos() * s;
                *r *= angle.sin() * s;
            } else {
                // Down from full level by the depth at the LFO's trough.
                let g = 1.0 - depth * (0.5 - 0.5 * w);
                *l *= g;
                *r *= g;
            }
        }
    }

    fn set_param(&mut self, index: u32, value: f32) {
        let index = index as usize;
        if index < self.p.len() && value.is_finite() {
            self.p[index] = value;
            self.rest.wake();
            if index == T_DEPTH {
                self.depth.target = (value * 0.01).clamp(0.0, 1.0);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Delay

const MAX_DELAY_SECONDS: f32 = 4.0;
const D_TIME: usize = 0;
const D_FEEDBACK: usize = 1;
const D_MIX: usize = 2;
const D_SYNC: usize = 3;
const D_MODE: usize = 4;
const D_LOW_CUT: usize = 5;
const D_HIGH_CUT: usize = 6;
const D_WIDTH: usize = 7;

pub fn delay_params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::new("time")
            .name("Time")
            .range(1.0, MAX_DELAY_SECONDS * 1000.0)
            .default_value(375.0)
            .unit("ms"),
        ParamInfo::new("feedback").name("Feedback").range(0.0, 0.95).default_value(0.35),
        ParamInfo::new("mix").name("Mix").range(0.0, 1.0).default_value(0.25),
        sync(),
        ParamInfo::choice("mode", &["Stereo", "Ping-pong"], 0).name("Mode"),
        ParamInfo::new("low_cut")
            .name("Low cut")
            .range(20.0, 2000.0)
            .default_value(20.0)
            .unit("Hz"),
        ParamInfo::new("high_cut")
            .name("High cut")
            .range(1000.0, 20000.0)
            .default_value(20000.0)
            .unit("Hz"),
        ParamInfo::new("width").name("Width").range(0.0, 100.0).default_value(100.0).unit("%"),
    ]
}

pub fn delay(sr: f32) -> Pair {
    (Box::new(Delay::new(sr)), Box::new(NoFace))
}

/// An echo: the time in ms or as a note length at the tempo, stereo or
/// ping-pong, with the repeats filtered so they darken and thin out. The
/// echoes are added to the dry sound, which stays at full level; `mix` is
/// the level of the echoes. A new time glides there, like tape.
pub struct Delay {
    sr: f32,
    p: [f32; 8],
    lines: [DelayLine; 2],
    time: Smooth,
    low: Option<SvfCoefs>,
    high: Option<SvfCoefs>,
    filters: [[Svf; 2]; 2],
    started: bool,
    rest: Rest,
    /// How many frames of silence the lines last took in, up to their
    /// length: at their length they hold nothing but silence (as a new
    /// delay does), and silence in gives silence out without writing them.
    /// A delay that never hears a sound then never touches the memory of
    /// its lines, which is most of the memory of a project with many.
    quiet: usize,
}

impl Delay {
    fn new(sr: f32) -> Self {
        let len = (MAX_DELAY_SECONDS * sr) as usize + 4;
        let mut d = Self {
            sr,
            p: super::defaults(&delay_params()),
            lines: [DelayLine::new(len), DelayLine::new(len)],
            time: Smooth::new(0.0, 0.08, sr),
            low: None,
            high: None,
            filters: Default::default(),
            started: false,
            rest: Rest::default(),
            quiet: usize::MAX,
        };
        d.apply();
        d
    }

    /// True when the lines and the filters hold nothing and this block's
    /// input is silence: the block's output is then its input.
    fn silent(&self, io: &Io) -> bool {
        self.quiet >= self.lines[0].capacity() + 4
            && self.filters.iter().flatten().all(|f| f.is_zero())
            && io.left.iter().chain(io.right.iter()).all(|x| x.to_bits() == 0)
    }

    fn apply(&mut self) {
        let p = &self.p;
        self.low = (p[D_LOW_CUT] > 20.5)
            .then(|| SvfCoefs::new(Shape::High, p[D_LOW_CUT], 0.71, 0.0, self.sr));
        self.high = (p[D_HIGH_CUT] < 19999.0)
            .then(|| SvfCoefs::new(Shape::Low, p[D_HIGH_CUT], 0.71, 0.0, self.sr));
    }

    /// The delay in frames for this block.
    fn frames(&self, ctx: &ProcessCtx) -> f32 {
        let frames = match dsp::sync_seconds(self.p[D_SYNC], ctx.tempo) {
            // To a thousandth of a frame, so that a note length that is a
            // whole number of frames reads exactly.
            Some(_) => {
                let index = (self.p[D_SYNC].round() as usize).clamp(1, NOTE_BEATS.len());
                let seconds = NOTE_BEATS[index - 1] * 60.0 / ctx.tempo.max(1.0);
                ((seconds * self.sr as f64 * 1000.0).round() / 1000.0) as f32
            }
            // Whole frames, as the delay always had them: renders stay the same.
            None => (self.p[D_TIME] * 0.001 * self.sr).floor(),
        };
        frames.clamp(1.0, (self.lines[0].capacity() - 4) as f32)
    }
}

impl Device for Delay {
    fn resting(&self) -> bool {
        self.rest.resting
    }

    fn process(&mut self, ctx: &ProcessCtx, io: &mut Io) {
        if self.rest.sleeps(io) {
            return;
        }
        self.time.target = self.frames(ctx);
        if !self.started {
            self.time.snap();
        }
        self.started = true;
        if self.silent(io) {
            for _ in 0..io.left.len() {
                self.time.step();
            }
            // Holding nothing, and settled: at rest.
            self.rest.resting = !self.time.moving();
            return;
        }
        let feedback = self.p[D_FEEDBACK].clamp(0.0, 0.95);
        let mix = self.p[D_MIX].clamp(0.0, 1.0);
        let pingpong = self.p[D_MODE] >= 0.5;
        let width = (self.p[D_WIDTH] * 0.01).clamp(0.0, 1.0);
        for (l, r) in io.left.iter_mut().zip(io.right.iter_mut()) {
            let t = self.time.step();
            // A whole number of frames reads exactly, without interpolation.
            let read = |line: &DelayLine| {
                if t.fract() == 0.0 {
                    line.get(t as usize - 1)
                } else {
                    line.get_frac(t - 1.0)
                }
            };
            let mut wet = [read(&self.lines[0]), read(&self.lines[1])];
            // The repeats are filtered on their way back in.
            let mut back = wet;
            for (ch, x) in back.iter_mut().enumerate() {
                if let Some(c) = &self.low {
                    *x = self.filters[0][ch].tick(c, *x);
                }
                if let Some(c) = &self.high {
                    *x = self.filters[1][ch].tick(c, *x);
                }
                *x *= feedback;
            }
            let (input_l, input_r) = if pingpong {
                // Everything enters on the left and crosses over each repeat.
                ((*l + *r) * 0.5 + back[1], back[0])
            } else {
                (*l + back[0], *r + back[1])
            };
            let (input_l, input_r) = (dsp::flush(input_l), dsp::flush(input_r));
            self.lines[0].push(input_l);
            self.lines[1].push(input_r);
            self.quiet = if input_l == 0.0 && input_r == 0.0 { self.quiet.saturating_add(1) } else { 0 };
            if width < 1.0 {
                let mid = (wet[0] + wet[1]) * 0.5;
                wet[0] = mid + (wet[0] - mid) * width;
                wet[1] = mid + (wet[1] - mid) * width;
            }
            let (dry_l, dry_r) = (*l, *r);
            *l += wet[0] * mix;
            *r += wet[1] * mix;
            // Calm for as long as it reads back: every echo has died away.
            let level = input_l.abs().max(input_r.abs());
            if self.rest.frame(dry_l, dry_r, level) as f32 > t + 4.0
                && !self.rest.resting
                && !self.time.moving()
            {
                // Lines that took in only silence for their whole length hold
                // nothing, and are left alone (their memory untouched).
                if self.quiet < self.lines[0].capacity() + 4 {
                    self.lines.iter_mut().for_each(DelayLine::clear);
                }
                self.quiet = usize::MAX;
                self.filters = Default::default();
                self.rest.resting = true;
            }
        }
        for f in self.filters.iter_mut().flatten() {
            f.flush();
        }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::devices::testkit::*;

    #[test]
    fn a_delay_in_silence_writes_nothing_and_sounds_the_same() {
        // A sound, silence for longer than the lines, a sound again, with
        // the filters on. Negative zeros are silence that the delay still
        // writes, so they give what it gave before it left silence alone.
        let sr = 48000.0;
        let mut input = vec![0.0f32; (sr * 12.0) as usize];
        input[100] = 1.0;
        input[(sr * 10.0) as usize] = 0.5;
        let written: Vec<f32> = input.iter().map(|&x| if x == 0.0 { -0.0 } else { x }).collect();
        let run = |input: &[f32]| {
            let mut fx = Fx::new("delay", sr);
            fx.set("feedback", 0.6);
            fx.set("low_cut", 200.0);
            fx.set("high_cut", 5000.0);
            fx.run_stereo(input, input, 256)
        };
        let (a, b) = (run(&input), run(&written));
        assert!(a.0.iter().zip(&b.0).all(|(x, y)| x == y), "left");
        assert!(a.1.iter().zip(&b.1).all(|(x, y)| x == y), "right");
        let after = (sr * 10.0) as usize;
        assert!(a.0[after + 1..].iter().any(|x| x.abs() > 0.01), "the second sound echoes");
        // A new delay that hears only silence leaves its lines alone.
        let mut d = Delay::new(sr);
        let (mut l, mut r) = (vec![0.0f32; 512], vec![0.0f32; 512]);
        let ctx = ProcessCtx::at(sr, 120.0, 4, 4, false);
        for _ in 0..100 {
            let mut events = crate::EventBuf::with_capacity(4);
            let mut io = Io { left: &mut l, right: &mut r, events: &mut events, sidechain: None, outputs: &mut [] };
            d.process(&ctx, &mut io);
        }
        assert_eq!(d.quiet, usize::MAX);
    }

    #[test]
    fn mix_at_zero_is_transparent() {
        for kind in ["chorus", "flanger", "phaser", "delay"] {
            let mut fx = Fx::new(kind, 48000.0);
            fx.set("mix", 0.0);
            let (a, b) = (noise(9000, 1), noise(9000, 2));
            assert_eq!(fx.run_stereo(&a, &b, 64), (a, b), "{kind}");
        }
        let mut fx = Fx::new("tremolo", 48000.0);
        fx.set("depth", 0.0);
        let a = noise(9000, 1);
        assert_eq!(fx.run(&a, 64), a, "tremolo");
    }

    #[test]
    fn a_synced_delay_repeats_on_the_beat_at_the_tempo_of_the_moment() {
        let sr = 48000.0;
        for (tempo, note, beats) in [
            (120.0, "1/4", 1.0),
            (90.0, "1/8.", 0.75),
            (150.0, "1/4T", 2.0 / 3.0),
        ] {
            let mut fx = Fx::new("delay", sr);
            fx.ctx.tempo = tempo;
            let index = dsp::NOTE_NAMES.iter().position(|n| *n == note).unwrap() + 1;
            fx.set("sync", index as f32);
            fx.set("mix", 1.0);
            fx.set("feedback", 0.5);
            let mut x = vec![0.0; sr as usize * 3];
            x[0] = 1.0;
            let out = fx.run(&x, 128);
            let echo = (beats * 60.0 / tempo * sr as f64).round() as usize;
            assert!(
                (out[echo] - 1.0).abs() < 1e-6,
                "{note} at {tempo}: {}",
                out[echo]
            );
            assert!(
                (out[echo * 2] - 0.5).abs() < 1e-6,
                "the second repeat at half"
            );
            assert!(out[1..echo].iter().all(|v| v.abs() < 1e-9));
        }
    }

    #[test]
    fn ping_pong_alternates_sides() {
        let sr = 48000.0;
        let mut fx = Fx::new("delay", sr);
        fx.set("time", 100.0);
        fx.set("mode", 1.0);
        fx.set("mix", 1.0);
        fx.set("feedback", 0.5);
        let mut x = vec![0.0; 24000];
        x[0] = 1.0;
        let (l, r) = fx.run_stereo(&x, &x, 128);
        assert!(
            (l[4800] - 1.0).abs() < 1e-6 && r[4800].abs() < 1e-9,
            "first on the left"
        );
        assert!(
            (r[9600] - 0.5).abs() < 1e-6 && l[9600].abs() < 1e-9,
            "then on the right"
        );
        assert!((l[14400] - 0.25).abs() < 1e-6);
    }

    #[test]
    fn the_repeats_darken_with_the_high_cut() {
        let sr = 48000.0;
        let mut fx = Fx::new("delay", sr);
        fx.set("time", 50.0);
        fx.set("mix", 1.0);
        fx.set("feedback", 0.9);
        fx.set("high_cut", 2000.0);
        let mut x = vec![0.0; 48000];
        x[0] = 1.0;
        let out = fx.run(&x, 128);
        let echo = |k: usize| &out[2400 * k - 50..2400 * k + 200];
        let hf = |s: &[f32]| s.windows(2).map(|w| (w[1] - w[0]).powi(2)).sum::<f32>();
        assert!(
            hf(echo(6)) < hf(echo(2)) * 0.1,
            "each repeat duller than the last"
        );
    }

    #[test]
    fn tremolo_dips_by_its_depth_and_auto_pan_keeps_the_power() {
        let sr = 48000.0;
        let mut fx = Fx::new("tremolo", sr);
        fx.set("rate", 4.0);
        fx.set("depth", 50.0);
        let x = vec![0.5; 48000];
        let out = fx.run(&x, 64);
        let lo = out.iter().fold(1.0f32, |m, v| m.min(*v));
        let hi = out.iter().fold(0.0f32, |m, v| m.max(*v));
        assert!(
            (lo - 0.25).abs() < 1e-3 && (hi - 0.5).abs() < 1e-3,
            "{lo} {hi}"
        );
        fx.set("mode", 1.0);
        fx.set("depth", 100.0);
        let (l, r) = fx.run_stereo(&x, &x, 64);
        for i in (0..48000).step_by(97) {
            let power = l[i] * l[i] + r[i] * r[i];
            assert!((power - 0.5).abs() < 1e-3, "power {power}");
        }
        assert!(
            l.iter().any(|v| v.abs() < 1e-3) && r.iter().any(|v| v.abs() < 1e-3),
            "full depth reaches each side"
        );
    }

    #[test]
    fn a_synced_lfo_follows_the_tempo() {
        // A quarter-note tremolo at 150 bpm dips 2.5 times a second.
        let sr = 48000.0;
        let mut fx = Fx::new("tremolo", sr);
        fx.ctx.tempo = 150.0;
        let quarter = dsp::NOTE_NAMES.iter().position(|n| *n == "1/4").unwrap() + 1;
        fx.set("sync", quarter as f32);
        fx.set("depth", 100.0);
        let out = fx.run(&vec![1.0; 96000], 256);
        let dips = out
            .windows(3)
            .filter(|w| w[1] < w[0] && w[1] <= w[2] && w[1] < 0.01)
            .count();
        assert_eq!(dips, 5);
    }

    #[test]
    fn the_phaser_notches_move_and_the_flanger_combs() {
        let sr = 48000.0;
        // A static flanger (no depth) at 1 ms with mix 50 %: a comb with
        // notches at 500 Hz, 1500 Hz...
        let mut fx = Fx::new("flanger", sr);
        fx.set("depth", 0.0);
        fx.set("feedback", 0.0);
        fx.set("delay", 1.0);
        let notch = fx.run(&sine(500.0, sr, 24000, 0.5), 256);
        let peak_ = fx.run(&sine(1000.0, sr, 24000, 0.5), 256);
        assert!(
            rms_db(&notch[12000..]) < -40.0,
            "{}",
            rms_db(&notch[12000..])
        );
        assert!((rms_db(&peak_[12000..]) - rms_db(&sine(1000.0, sr, 12000, 0.5))).abs() < 0.2);
        // Four stages at 1 kHz shift by 180 degrees where each shifts by 45:
        // tan(pi f / rate) = tan(pi 1000 / rate) tan(pi / 8).
        let mut fx = Fx::new("phaser", sr);
        fx.set("depth", 0.0);
        fx.set("feedback", 0.0);
        fx.set("center", 1000.0);
        let t = (std::f32::consts::PI * 1000.0 / sr).tan() * (std::f32::consts::PI / 8.0).tan();
        let f = t.atan() * sr / std::f32::consts::PI;
        let out = fx.run(&sine(f, sr, 24000, 0.5), 256);
        assert!(rms_db(&out[12000..]) < -40.0, "{}", rms_db(&out[12000..]));
    }
}
