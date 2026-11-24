//! A small polyphonic subtractive synth: one band-limited oscillator, a
//! low-pass filter and an ADSR envelope per voice.

use std::f32::consts::{PI, TAU};

use paw_types::{Ctl, EventKind, NOTE_BEND_RANGE, NoteCtl};

use crate::db_to_gain;
use crate::device::{Device, Io, ParamInfo, ProcessCtx};

const VOICES: usize = 16;

const WAVE: usize = 0;
const ATTACK: usize = 1;
const DECAY: usize = 2;
const SUSTAIN: usize = 3;
const RELEASE: usize = 4;
const CUTOFF: usize = 5;
const RESONANCE: usize = 6;
const GAIN: usize = 7;

pub(super) fn params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::choice("wave", &["sine", "saw", "square", "triangle"], 1),
        ParamInfo::new("attack", 0.001, 2.0, 0.005, "s"),
        ParamInfo::new("decay", 0.001, 2.0, 0.15, "s"),
        ParamInfo::new("sustain", 0.0, 1.0, 0.6, ""),
        ParamInfo::new("release", 0.001, 5.0, 0.2, "s"),
        ParamInfo::new("cutoff", 20.0, 20000.0, 4000.0, "Hz"),
        ParamInfo::new("resonance", 0.0, 1.0, 0.2, ""),
        ParamInfo::new("gain", -60.0, 12.0, -12.0, "dB"),
    ]
}

#[derive(Clone, Copy, PartialEq)]
enum Stage {
    Off,
    Attack,
    Decay,
    Release,
}

#[derive(Clone, Copy)]
struct Voice {
    key: u8,
    stage: Stage,
    phase: f32,
    step: f32,
    vel: f32,
    env: f32,
    ic1: f32,
    ic2: f32,
    started: u64,
    /// The key was let go while the sustain pedal was down.
    sustained: bool,
    /// The note's own pitch bend, as a frequency ratio.
    bend: f32,
}

/// How far the pitch wheel bends, in semitones each way.
const BEND_RANGE: f32 = 2.0;

pub(super) struct Synth {
    sample_rate: f32,
    p: [f32; 8],
    voices: [Voice; VOICES],
    /// The pitch wheel as a frequency ratio, and whether the pedal is down.
    bend: f32,
    pedal: bool,
    clock: u64,
    // Filter coefficients, recomputed when cutoff or resonance change.
    a1: f32,
    a2: f32,
    a3: f32,
}

impl Synth {
    pub(super) fn new(sample_rate: f32) -> Self {
        let voice = Voice {
            key: 0,
            stage: Stage::Off,
            phase: 0.0,
            step: 0.0,
            vel: 0.0,
            env: 0.0,
            ic1: 0.0,
            ic2: 0.0,
            started: 0,
            sustained: false,
            bend: 1.0,
        };
        let mut synth = Self {
            sample_rate,
            p: super::defaults(&params()),
            voices: [voice; VOICES],
            bend: 1.0,
            pedal: false,
            clock: 0,
            a1: 0.0,
            a2: 0.0,
            a3: 0.0,
        };
        synth.update_filter();
        synth
    }

    fn update_filter(&mut self) {
        let cutoff = self.p[CUTOFF].clamp(20.0, self.sample_rate * 0.45);
        let g = (PI * cutoff / self.sample_rate).tan();
        let k = 2.0 - 1.9 * self.p[RESONANCE].clamp(0.0, 1.0);
        self.a1 = 1.0 / (1.0 + g * (g + k));
        self.a2 = g * self.a1;
        self.a3 = g * self.a2;
    }

    fn note_on(&mut self, key: u8, vel: f32) {
        self.clock += 1;
        // Reuse a voice already playing this key, then a free one, then the oldest.
        let index = self
            .voices
            .iter()
            .position(|v| v.stage != Stage::Off && v.key == key)
            .or_else(|| self.voices.iter().position(|v| v.stage == Stage::Off))
            .unwrap_or_else(|| {
                (0..VOICES)
                    .min_by_key(|&i| self.voices[i].started)
                    .unwrap_or(0)
            });
        let freq = 440.0 * 2f32.powf((key as f32 - 69.0) / 12.0);
        let v = &mut self.voices[index];
        if v.stage == Stage::Off {
            v.phase = 0.0;
            v.env = 0.0;
            v.ic1 = 0.0;
            v.ic2 = 0.0;
        }
        v.key = key;
        v.vel = vel;
        v.step = freq / self.sample_rate;
        v.stage = Stage::Attack;
        v.started = self.clock;
        v.sustained = false;
        v.bend = 1.0;
    }

    fn handle(&mut self, kind: EventKind) {
        match kind {
            EventKind::NoteOn { key, vel, .. } => self.note_on(key, vel),
            EventKind::NoteOff { key, .. } => {
                let pedal = self.pedal;
                for v in &mut self.voices {
                    if v.key == key && matches!(v.stage, Stage::Attack | Stage::Decay) {
                        if pedal {
                            v.sustained = true;
                        } else {
                            v.stage = Stage::Release;
                        }
                    }
                }
            }
            EventKind::AllNotesOff => {
                for v in &mut self.voices {
                    v.sustained = false;
                    if v.stage != Stage::Off {
                        v.stage = Stage::Release;
                    }
                }
            }
            EventKind::NoteControl {
                key,
                ctl: NoteCtl::Bend,
                value,
                ..
            } => {
                let ratio = 2f64.powf(value.clamp(-1.0, 1.0) * NOTE_BEND_RANGE / 12.0) as f32;
                for v in self.voices.iter_mut().filter(|v| v.key == key) {
                    v.bend = ratio;
                }
            }
            EventKind::NoteControl { .. } | EventKind::Program { .. } => {}
            EventKind::Control { ctl, value, .. } => match ctl {
                Ctl::Bend => {
                    self.bend = 2f32.powf(value.clamp(-1.0, 1.0) as f32 * BEND_RANGE / 12.0)
                }
                Ctl::Cc(64) => {
                    self.pedal = value >= 0.5;
                    if !self.pedal {
                        // Let go of what only the pedal was holding.
                        for v in self.voices.iter_mut().filter(|v| v.sustained) {
                            v.sustained = false;
                            if v.stage != Stage::Off {
                                v.stage = Stage::Release;
                            }
                        }
                    }
                }
                _ => {}
            },
        }
    }

    fn render(&mut self, left: &mut [f32], right: &mut [f32]) {
        let wave = self.p[WAVE].round() as u32;
        let sr = self.sample_rate;
        let attack = 1.0 / (self.p[ATTACK].max(0.001) * sr);
        // One-pole falls that get within 60 dB of their target in the given time.
        let decay = (-6.9 / (self.p[DECAY].max(0.001) * sr)).exp();
        let release = (-6.9 / (self.p[RELEASE].max(0.001) * sr)).exp();
        let sustain = self.p[SUSTAIN];
        let gain = db_to_gain(self.p[GAIN] as f64);
        let (a1, a2, a3) = (self.a1, self.a2, self.a3);
        let bend = self.bend;

        let k = Shape {
            attack,
            decay,
            release,
            sustain,
            gain,
            a1,
            a2,
            a3,
            bend,
        };
        // One loop per wave, so that the choice is made once per voice rather
        // than once per sample.
        for v in self.voices.iter_mut().filter(|v| v.stage != Stage::Off) {
            match wave {
                0 => render_voice::<0>(v, &k, left, right),
                1 => render_voice::<1>(v, &k, left, right),
                2 => render_voice::<2>(v, &k, left, right),
                _ => render_voice::<3>(v, &k, left, right),
            }
        }
    }
}

/// What every voice of a block shares: envelope steps, gain, filter.
struct Shape {
    attack: f32,
    decay: f32,
    release: f32,
    sustain: f32,
    gain: f32,
    a1: f32,
    a2: f32,
    a3: f32,
    /// The pitch wheel, as a frequency ratio.
    bend: f32,
}

#[inline(always)]
fn render_voice<const WAVE: u32>(v: &mut Voice, k: &Shape, left: &mut [f32], right: &mut [f32]) {
    for (l, r) in left.iter_mut().zip(right.iter_mut()) {
        match v.stage {
            Stage::Attack => {
                v.env += k.attack;
                if v.env >= 1.0 {
                    v.env = 1.0;
                    v.stage = Stage::Decay;
                }
            }
            Stage::Decay => v.env = k.sustain + (v.env - k.sustain) * k.decay,
            Stage::Release => {
                v.env *= k.release;
                if v.env < 1e-4 {
                    v.stage = Stage::Off;
                    break;
                }
            }
            Stage::Off => break,
        }
        let t = v.phase;
        let dt = v.step * k.bend * v.bend;
        let osc = match WAVE {
            0 => (t * TAU).sin(),
            1 => 2.0 * t - 1.0 - poly_blep(t, dt),
            2 => {
                let naive = if t < 0.5 { 1.0 } else { -1.0 };
                naive + poly_blep(t, dt) - poly_blep(super::fract(t + 0.5), dt)
            }
            _ => 1.0 - 4.0 * (t - 0.5).abs(),
        };
        v.phase = super::fract(t + dt);

        let v3 = osc - v.ic2;
        let v1 = k.a1 * v.ic1 + k.a2 * v3;
        let v2 = v.ic2 + k.a2 * v.ic1 + k.a3 * v3;
        v.ic1 = 2.0 * v1 - v.ic1;
        v.ic2 = 2.0 * v2 - v.ic2;

        let s = v2 * v.env * v.vel * k.gain;
        *l += s;
        *r += s;
    }
}

/// Correction that rounds off the step of a naive saw or square at phase `t`.
fn poly_blep(t: f32, dt: f32) -> f32 {
    if t < dt {
        let x = t / dt;
        x + x - x * x - 1.0
    } else if t > 1.0 - dt {
        let x = (t - 1.0) / dt;
        x * x + x + x + 1.0
    } else {
        0.0
    }
}

impl Device for Synth {
    /// No voice sounds: a block with no events adds nothing.
    fn resting(&self) -> bool {
        self.voices.iter().all(|v| v.stage == Stage::Off)
    }

    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        let n = io.left.len();
        let mut pos = 0;
        for ev in io.events.as_slice() {
            let frame = (ev.frame as usize).min(n);
            if frame > pos {
                self.render(&mut io.left[pos..frame], &mut io.right[pos..frame]);
                pos = frame;
            }
            self.handle(ev.kind);
        }
        self.render(&mut io.left[pos..], &mut io.right[pos..]);
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if let Some(p) = self.p.get_mut(index as usize) {
            *p = value;
            self.update_filter();
        }
    }
}
