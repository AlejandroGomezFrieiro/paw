//! Rendering built-in effects offline for tests, and the checks every one
//! of them must pass: the same output whatever the block size, finite output
//! for any parameter at the ends of its range, silence after the tail, and
//! no denormal numbers.

#![allow(dead_code)]

use crate::device::{Controller, Device, Io, ParamInfo, ProcessCtx, Registry};
use crate::event::EventBuf;

pub struct Fx {
    pub kind: String,
    pub sr: f32,
    pub device: Box<dyn Device>,
    pub control: Box<dyn Controller>,
    pub params: Vec<ParamInfo>,
    values: Vec<f32>,
    pub ctx: ProcessCtx,
    events: EventBuf,
}

impl Fx {
    pub fn new(kind: &str, sr: f32) -> Self {
        let registry = Registry::with_builtins();
        let factory = registry
            .get(kind)
            .unwrap_or_else(|| panic!("no device {kind}"));
        let instance = factory.create(sr, crate::MAX_BLOCK).unwrap();
        let control = instance
            .controller
            .expect("a built-in effect has a controller");
        let params = control.params();
        let mut fx = Self {
            kind: kind.into(),
            sr,
            device: instance.device,
            control,
            values: params.iter().map(|p| p.default).collect(),
            params,
            ctx: ProcessCtx::at(sr, 120.0, 4, 4, false),
            events: EventBuf::with_capacity(16),
        };
        // As the host does: every parameter is set before the first block.
        for i in 0..fx.params.len() {
            fx.device.set_param(i as u32, fx.values[i]);
        }
        fx
    }

    pub fn index(&self, key: &str) -> usize {
        self.params
            .iter()
            .position(|p| p.key == key)
            .unwrap_or_else(|| panic!("{} has no parameter {key}", self.kind))
    }

    pub fn set(&mut self, key: &str, value: f32) {
        let i = self.index(key);
        self.set_index(i, value);
    }

    pub fn set_index(&mut self, i: usize, value: f32) {
        let p = &self.params[i];
        let value = value.clamp(p.min, p.max);
        self.values[i] = value;
        self.device.set_param(i as u32, value);
        self.control.set_value(i, value as f64);
    }

    pub fn values(&self) -> Vec<f32> {
        self.values.clone()
    }

    /// A new instance with the same settings: no state left from before.
    pub fn reset(&mut self) {
        let values = self.values.clone();
        let tempo = self.ctx.tempo;
        *self = Fx::new(&self.kind, self.sr);
        self.ctx.tempo = tempo;
        for (i, v) in values.into_iter().enumerate() {
            self.set_index(i, v);
        }
    }

    /// Let settings that glide get where they are going.
    pub fn settle(&mut self) {
        let n = (self.sr * 0.3) as usize;
        let z = vec![0.0; n];
        self.run_stereo(&z, &z, 512);
    }

    pub fn run_stereo(
        &mut self,
        left: &[f32],
        right: &[f32],
        block: usize,
    ) -> (Vec<f32>, Vec<f32>) {
        let mut l = left.to_vec();
        let mut r = right.to_vec();
        for (cl, cr) in l.chunks_mut(block.max(1)).zip(r.chunks_mut(block.max(1))) {
            self.events.clear();
            let mut io = Io {
                left: cl,
                right: cr,
                events: &mut self.events,
                sidechain: None,
                outputs: &mut [],
            };
            self.device.process(&self.ctx, &mut io);
            if self.ctx.playing {
                self.ctx.position += cl.len() as f64 * self.ctx.tempo / 60.0 / self.sr as f64;
            }
        }
        (l, r)
    }

    pub fn run(&mut self, mono: &[f32], block: usize) -> Vec<f32> {
        self.run_stereo(mono, mono, block).0
    }

    pub fn call(&mut self, method: &str, data: &str) -> String {
        String::from_utf8(self.control.call(method, data.as_bytes()).unwrap()).unwrap()
    }

    pub fn call_numbers(&mut self, method: &str, data: &str) -> Vec<f64> {
        self.call(method, data)
            .split_whitespace()
            .map(|s| s.parse().unwrap())
            .collect()
    }

    /// A `name value` answer as a lookup.
    pub fn field(&mut self, method: &str, name: &str) -> f64 {
        let text = self.call(method, "");
        text.lines()
            .find_map(|l| {
                let (k, v) = l.split_once(' ')?;
                (k == name).then(|| v.trim().parse().unwrap())
            })
            .unwrap_or_else(|| panic!("no {name} in {text}"))
    }

    pub fn latency(&self) -> u32 {
        self.control.latency()
    }
}

/// White noise from a fixed seed, in -0.5..0.5.
pub fn noise(n: usize, seed: u32) -> Vec<f32> {
    let mut s = seed.wrapping_mul(2654435761).max(1);
    (0..n)
        .map(|_| {
            s ^= s << 13;
            s ^= s >> 17;
            s ^= s << 5;
            (s as f32 / u32::MAX as f32) - 0.5
        })
        .collect()
}

pub fn sine(freq: f32, sr: f32, n: usize, amp: f32) -> Vec<f32> {
    (0..n)
        .map(|i| (std::f32::consts::TAU * freq * i as f32 / sr).sin() * amp)
        .collect()
}

pub fn rms_db(x: &[f32]) -> f64 {
    let e: f64 = x.iter().map(|v| (*v as f64) * (*v as f64)).sum::<f64>() / x.len().max(1) as f64;
    10.0 * e.max(1e-30).log10()
}

pub fn peak(x: &[f32]) -> f32 {
    x.iter().fold(0.0, |m, v| m.max(v.abs()))
}

/// A device kind, settings that make it do something, and how long its
/// tail can ring at those settings, in seconds.
pub type Case = (&'static str, Vec<(&'static str, f32)>, f32);

/// Every built-in effect.
pub fn effects() -> Vec<Case> {
    let eq = vec![
        ("b1_on", 1.0),
        ("b3_gain", 9.0),
        ("b5_gain", -6.0),
        ("b5_q", 8.0),
        ("b7_gain", 4.0),
    ];
    let compressor = vec![
        ("threshold", -30.0),
        ("ratio", 4.0),
        ("lookahead", 3.0),
        ("detector_hp", 120.0),
        ("detect", 1.0),
        ("auto_release", 1.0),
        ("auto_makeup", 1.0),
        ("mix", 70.0),
        ("link", 50.0),
    ];
    let gate = vec![
        ("threshold", -20.0),
        ("lookahead", 2.0),
        ("hold", 10.0),
        ("detector_hp", 200.0),
        ("link", 0.0),
    ];
    let limiter = vec![("gain", 12.0), ("ceiling", -3.0), ("release", 20.0)];
    vec![
        ("eq", eq, 0.5),
        ("compressor", compressor, 0.5),
        ("gate", gate, 0.5),
        ("limiter", limiter, 0.5),
        (
            "reverb",
            vec![("decay", 2.0), ("mix", 60.0), ("size", 80.0)],
            12.0,
        ),
        (
            "utility",
            vec![
                ("gain", -3.0),
                ("pan", 30.0),
                ("width", 150.0),
                ("mono_below", 120.0),
                ("dc", 1.0),
            ],
            0.5,
        ),
        (
            "saturation",
            vec![
                ("drive", 18.0),
                ("curve", 1.0),
                ("tone", 3.0),
                ("mix", 80.0),
                ("oversample", 1.0),
            ],
            0.5,
        ),
        ("meter", vec![("hold", 1.0)], 0.0),
        ("tuner", vec![("reference", 442.0)], 0.0),
        ("chorus", vec![("feedback", 40.0), ("voices", 2.0)], 1.0),
        ("flanger", vec![("feedback", -80.0), ("rate", 2.0)], 1.0),
        ("phaser", vec![("stages", 4.0), ("feedback", 80.0)], 1.0),
        (
            "tremolo",
            vec![("mode", 1.0), ("shape", 2.0), ("sync", 8.0)],
            0.5,
        ),
        (
            "delay",
            vec![
                ("mode", 1.0),
                ("feedback", 0.7),
                ("low_cut", 200.0),
                ("high_cut", 4000.0),
                ("sync", 5.0),
                ("mix", 0.5),
            ],
            8.0,
        ),
    ]
}

/// Input that has everything: noise, a loud burst, a low sine, then silence.
fn busy_input(sr: f32) -> Vec<f32> {
    let n = (sr * 0.6) as usize;
    let mut x = noise(n, 7);
    for (i, v) in x.iter_mut().enumerate() {
        *v *= if i < n / 3 { 0.2 } else { 1.6 };
        *v += (std::f32::consts::TAU * 60.0 * i as f32 / sr).sin() * 0.3;
    }
    x
}

fn configured(kind: &str, settings: &[(&str, f32)], sr: f32) -> Fx {
    let mut fx = Fx::new(kind, sr);
    for (k, v) in settings {
        fx.set(k, *v);
    }
    fx
}

#[test]
fn the_same_output_whatever_the_block_size() {
    for (kind, settings, _) in effects() {
        for sr in [44100.0, 48000.0, 96000.0] {
            let input = busy_input(sr);
            let right: Vec<f32> = input.iter().rev().copied().collect();
            let reference = configured(kind, &settings, sr).run_stereo(&input, &right, 4096);
            for block in [1, 7, 64, 256, 1000] {
                let out = configured(kind, &settings, sr).run_stereo(&input, &right, block);
                assert!(
                    out == reference,
                    "{kind} at {sr} Hz in blocks of {block} differs from blocks of 4096"
                );
            }
        }
    }
}

#[test]
fn finite_output_at_the_ends_of_every_range() {
    let sr = 48000.0;
    for (kind, settings, _) in effects() {
        let params = Fx::new(kind, sr).params;
        let input = busy_input(sr);
        let mut cases: Vec<Vec<(usize, f32)>> = Vec::new();
        for (i, p) in params.iter().enumerate() {
            cases.push(vec![(i, p.min)]);
            cases.push(vec![(i, p.max)]);
        }
        cases.push(params.iter().enumerate().map(|(i, p)| (i, p.min)).collect());
        cases.push(params.iter().enumerate().map(|(i, p)| (i, p.max)).collect());
        for case in cases {
            let mut fx = configured(kind, &settings, sr);
            for &(i, v) in &case {
                fx.set_index(i, v);
            }
            let (l, r) = fx.run_stereo(&input, &input, 333);
            let bad = l
                .iter()
                .chain(&r)
                .position(|x| !x.is_finite() || x.abs() > 1e5);
            assert!(
                bad.is_none(),
                "{kind} with {case:?} gives {:?}",
                bad.map(|i| l.get(i))
            );
        }
    }
}

#[test]
fn silence_after_the_tail_and_no_denormals() {
    // Deliberately without flushing denormals on this thread: the effects
    // must not produce them by themselves.
    for (kind, settings, tail) in effects() {
        let sr = 44100.0;
        let mut fx = configured(kind, &settings, sr);
        let input = busy_input(sr);
        fx.run_stereo(&input, &input, 512);
        let quiet = vec![0.0f32; (sr * (tail + 1.0)) as usize];
        let (l, r) = fx.run_stereo(&quiet, &quiet, 512);
        let sub = l.iter().chain(&r).find(|x| x.is_subnormal());
        assert!(sub.is_none(), "{kind} let a denormal out: {sub:?}");
        let last = (sr * 0.5) as usize;
        let level = peak(&l[l.len() - last..]).max(peak(&r[r.len() - last..]));
        assert!(
            level < 1e-7,
            "{kind} still sounds at {level} {tail} s after the input stopped"
        );
    }
}

/// The effects that go to sleep once their tail has died away.
const SLEEPERS: &[&str] = &[
    "eq", "reverb", "utility", "chorus", "flanger", "phaser", "tremolo", "delay",
];

/// Run an effect on `input` in blocks of `block`, setting `change` (a
/// parameter and value) at frame `change_at`; with `host`, as the host does
/// when it lets devices sleep: not calling it for a silent block while it
/// rests. The output, and the blocks it slept through.
fn run_resting(
    kind: &str,
    settings: &[(&str, f32)],
    input: &[f32],
    block: usize,
    change: (usize, usize, f32),
    host: bool,
) -> (Vec<f32>, usize) {
    let sr = 48000.0;
    let mut fx = configured(kind, settings, sr);
    let (mut l, mut r) = (input.to_vec(), input.iter().map(|x| -x * 0.5).collect::<Vec<_>>());
    let mut slept = 0;
    let mut events = EventBuf::with_capacity(4);
    for (at, (cl, cr)) in l.chunks_mut(block).zip(r.chunks_mut(block)).enumerate() {
        let start = at * block;
        if (start..start + block).contains(&change.0) {
            fx.set_index(change.1, change.2);
        }
        let silent = crate::device::silent(cl) && crate::device::silent(cr);
        if host && silent && fx.device.resting() {
            slept += 1;
            continue;
        }
        let mut io = Io {
            left: cl,
            right: cr,
            events: &mut events,
            sidechain: None,
            outputs: &mut [],
        };
        fx.device.process(&fx.ctx, &mut io);
    }
    l.extend(r);
    (l, slept)
}

#[test]
fn an_effect_sounds_the_same_whether_it_sleeps_or_not() {
    let sr = 48000.0;
    for (kind, settings, tail) in effects() {
        // Bursts with silences between them longer than the tail, and a
        // short one; a setting changed while it sleeps.
        let burst = busy_input(sr);
        let mut input = Vec::new();
        for gap in [tail + 2.0, 0.01, tail + 2.0] {
            input.extend(&burst);
            input.extend(vec![0.0; (sr * gap) as usize]);
        }
        input.extend(&burst);
        let change_at = burst.len() + (sr * (tail + 1.5)) as usize;
        let param = Fx::new(kind, sr).params.len() - 1;
        let p = &Fx::new(kind, sr).params[param];
        let change = (change_at, param, (p.default + p.max) * 0.5);
        for block in [64, 1000] {
            let (always, _) = run_resting(kind, &settings, &input, block, change, false);
            let (host, slept) = run_resting(kind, &settings, &input, block, change, true);
            let same = always.iter().zip(&host).all(|(a, b)| a.to_bits() == b.to_bits());
            assert!(same, "{kind} in blocks of {block} sounds different asleep");
            if SLEEPERS.contains(&kind) {
                assert!(slept > 0, "{kind} never slept");
            } else {
                assert_eq!(slept, 0, "{kind} slept");
            }
        }
        // An effect that rests stays as it is (its LFO too) from the frame
        // it rests on to the frame that wakes it, wherever the blocks fall.
        if SLEEPERS.contains(&kind) {
            let unchanged = (usize::MAX, 0, 0.0);
            let (small, _) = run_resting(kind, &settings, &input, 64, unchanged, true);
            let (large, _) = run_resting(kind, &settings, &input, 1000, unchanged, true);
            let first = small.iter().zip(&large).position(|(a, b)| a != b);
            assert_eq!(first, None, "{kind}: blocks of 64 and of 1000 differ from this sample on");
        }
    }
}

#[test]
fn every_parameter_has_a_name_a_range_and_a_default_inside_it() {
    for (kind, _, _) in effects() {
        for p in Fx::new(kind, 48000.0).params {
            assert!(!p.name.is_empty() && !p.key.is_empty());
            assert!(
                p.min <= p.default && p.default <= p.max,
                "{kind}.{} default outside its range",
                p.key
            );
        }
    }
}
