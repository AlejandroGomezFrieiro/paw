//! A synthesized drum kit on the General MIDI drum notes:
//!
//! | Notes | Piece |
//! | --- | --- |
//! | 35, 36 | kick |
//! | 37 | rim (side stick) |
//! | 38, 40 | snare |
//! | 39 | clap |
//! | 42 | closed hat |
//! | 44 | pedal hat |
//! | 46 | open hat: the closed and the pedal hat cut it off |
//! | 41, 43, 45, 47, 48, 50 | toms, low to high |
//! | 49, 57 | crash; 52 china, 55 splash |
//! | 51, 59 | ride |
//! | 53 | ride bell |
//! | 54 | tambourine |
//! | 56 | cowbell |
//!
//! The kick, snares, clap, closed and open hat are made exactly as they
//! always were, so older projects sound the same.

use std::f32::consts::TAU;

use crate::db_to_gain;
use crate::device::{Device, Io, ParamInfo, ProcessCtx};
use crate::event::EventKind;

const GAIN: usize = 0;
const KICK_TUNE: usize = 1;
const DECAY: usize = 2;

pub(super) fn params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::new("gain", -60.0, 12.0, -6.0, "dB"),
        ParamInfo::new("kick_tune", 30.0, 90.0, 48.0, "Hz"),
        ParamInfo::new("decay", 0.25, 4.0, 1.0, "x"),
    ]
}

/// The kit's output pairs: the whole kit, then a pair for each family of
/// pieces. A family whose pair is routed somewhere plays there, and leaves
/// the first pair.
pub(super) const OUTPUTS: [&str; 7] = ["Kit", "Kick", "Snare", "Hats", "Toms", "Cymbals", "Percussion"];

#[derive(Clone, Copy, PartialEq)]
enum Kind {
    Kick,
    Snare,
    Clap,
    Hat,
    OpenHat,
    PedalHat,
    Rim,
    Tom,
    Crash,
    Ride,
    Bell,
    Cowbell,
    Tambourine,
}

impl Kind {
    /// The output pair of its family: 1 for the kick, and so on.
    fn family(self) -> usize {
        match self {
            Kind::Kick => 1,
            Kind::Snare | Kind::Clap | Kind::Rim => 2,
            Kind::Hat | Kind::OpenHat | Kind::PedalHat => 3,
            Kind::Tom => 4,
            Kind::Crash | Kind::Ride | Kind::Bell => 5,
            Kind::Cowbell | Kind::Tambourine => 6,
        }
    }
}

/// The metallic pieces are made of six square waves at these frequencies,
/// as the TR-808 makes its cymbals and hats.
const METAL: [f32; 6] = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0];

#[derive(Clone, Copy)]
struct Hit {
    kind: Kind,
    vel: f32,
    /// Seconds since the hit started.
    time: f32,
    phase: f32,
    /// Previous noise sample, for the high-pass on hats.
    last: f32,
    active: bool,
    /// What tells hits of one kind apart: a tom's pitch, a cymbal's size.
    tone: f32,
    /// More oscillators, for the pieces made of several.
    phases: [f32; 6],
    /// Filter state of the pieces that are filtered.
    low: f32,
}

const VOICES: usize = 24;

pub(super) struct Drums {
    sample_rate: f32,
    p: [f32; 3],
    hits: [Hit; VOICES],
    noise: u32,
}

/// A square wave of a phase in 0..1.
#[inline(always)]
fn square(phase: f32) -> f32 {
    if phase < 0.5 { 1.0 } else { -1.0 }
}

impl Drums {
    pub(super) fn new(sample_rate: f32) -> Self {
        let hit = Hit {
            kind: Kind::Kick,
            vel: 0.0,
            time: 0.0,
            phase: 0.0,
            last: 0.0,
            active: false,
            tone: 0.0,
            phases: [0.0; 6],
            low: 0.0,
        };
        Self {
            sample_rate,
            p: super::defaults(&params()),
            hits: [hit; VOICES],
            noise: 0x1234_5678,
        }
    }

    fn trigger(&mut self, key: u8, vel: f32) {
        let (kind, tone) = match key {
            35 | 36 => (Kind::Kick, 0.0),
            37 => (Kind::Rim, 0.0),
            38 | 40 => (Kind::Snare, 0.0),
            39 => (Kind::Clap, 0.0),
            42 => (Kind::Hat, 0.0),
            44 => (Kind::PedalHat, 0.0),
            46 => (Kind::OpenHat, 0.0),
            // Toms, by the pitch they start from.
            41 => (Kind::Tom, 82.0),
            43 => (Kind::Tom, 98.0),
            45 => (Kind::Tom, 112.0),
            47 => (Kind::Tom, 132.0),
            48 => (Kind::Tom, 156.0),
            50 => (Kind::Tom, 185.0),
            // Cymbals, by how high and short they are.
            49 => (Kind::Crash, 1.0),
            57 => (Kind::Crash, 1.12),
            52 => (Kind::Crash, 0.8),
            55 => (Kind::Crash, 1.45),
            51 => (Kind::Ride, 1.0),
            59 => (Kind::Ride, 1.1),
            53 => (Kind::Bell, 0.0),
            54 => (Kind::Tambourine, 0.0),
            56 => (Kind::Cowbell, 0.0),
            _ => return,
        };
        // A closed or pedal hat chokes a ringing open hat.
        if kind == Kind::Hat || kind == Kind::PedalHat {
            for h in &mut self.hits {
                h.active &= h.kind != Kind::OpenHat;
            }
        }
        let slot = self
            .hits
            .iter()
            .position(|h| !h.active || (h.kind == kind && h.tone == tone))
            .unwrap_or(0);
        self.hits[slot] = Hit {
            kind,
            vel,
            time: 0.0,
            phase: 0.0,
            last: 0.0,
            active: true,
            tone,
            phases: [0.0; 6],
            low: 0.0,
        };
    }

    /// Render frames `from..to` of the block: each family on its own pair
    /// where that is routed (`outputs`, from the second pair), else on the
    /// first.
    fn render(
        &mut self,
        left: &mut [f32],
        right: &mut [f32],
        outputs: &mut [Option<[Vec<f32>; 2]>],
        (from, to): (usize, usize),
    ) {
        let dt = 1.0 / self.sample_rate;
        let gain = db_to_gain(self.p[GAIN] as f64);
        let tune = self.p[KICK_TUNE];
        let stretch = self.p[DECAY].max(0.05);
        let routed = |family: usize| outputs.get(family - 1).is_some_and(Option::is_some);
        let mut apart = [false; OUTPUTS.len()];
        for (family, apart) in apart.iter_mut().enumerate().skip(1) {
            *apart = routed(family);
        }
        for i in from..to {
            let mut out = 0.0;
            let mut families = [0.0f32; OUTPUTS.len()];
            for h in self.hits.iter_mut().filter(|h| h.active) {
                // xorshift noise in -1..1
                self.noise ^= self.noise << 13;
                self.noise ^= self.noise >> 17;
                self.noise ^= self.noise << 5;
                let noise = self.noise as f32 / u32::MAX as f32 * 2.0 - 1.0;
                let t = h.time;
                let (sample, length) = match h.kind {
                    Kind::Kick => {
                        let freq = tune + 180.0 * (-t * 40.0).exp();
                        h.phase = super::fract(h.phase + freq * dt);
                        (
                            (h.phase * TAU).sin() * (-t * 9.0 / stretch).exp(),
                            0.6 * stretch,
                        )
                    }
                    Kind::Snare => {
                        h.phase = super::fract(h.phase + 190.0 * dt);
                        let tone = (h.phase * TAU).sin() * (-t * 28.0).exp() * 0.5;
                        (
                            tone + noise * (-t * 22.0 / stretch).exp() * 0.6,
                            0.35 * stretch,
                        )
                    }
                    Kind::Clap => {
                        // Three quick bursts, then a tail.
                        let burst = (super::fract(t * 90.0) < 0.5 && t < 0.035) as u8 as f32;
                        let env = burst.max((-(t - 0.035).max(0.0) * 30.0 / stretch).exp() * 0.8);
                        (noise * env * 0.6, 0.3 * stretch)
                    }
                    Kind::Hat | Kind::OpenHat => {
                        let high = noise - h.last;
                        h.last = noise;
                        let rate = if h.kind == Kind::Hat { 70.0 } else { 9.0 };
                        let length = if h.kind == Kind::Hat { 0.1 } else { 0.6 };
                        (high * (-t * rate / stretch).exp() * 0.35, length * stretch)
                    }
                    Kind::PedalHat => {
                        // Shorter than a closed hat, with the chick of the
                        // cymbals closing under it.
                        let high = noise - h.last;
                        h.last = noise;
                        h.low += (noise - h.low) * 0.12;
                        let body = (h.low * 2.5) * (-t * 60.0).exp();
                        (
                            (high * 0.3 + body * 0.25) * (-t * 110.0 / stretch).exp(),
                            0.07 * stretch,
                        )
                    }
                    Kind::Rim => {
                        // A click high up, and the wood of the rim under it.
                        h.phase = super::fract(h.phase + 1750.0 * dt);
                        h.phases[0] = super::fract(h.phases[0] + 470.0 * dt);
                        let high = noise - h.last;
                        h.last = noise;
                        let body = (h.phase * TAU).sin() * 0.5 + (h.phases[0] * TAU).sin() * 0.5;
                        (
                            (body + high * 0.25) * (-t * 90.0 / stretch).exp() * 0.8,
                            0.08 * stretch,
                        )
                    }
                    Kind::Tom => {
                        // A drum skin: the pitch falls a little as it rings.
                        let freq = h.tone * (1.0 + 0.45 * (-t * 16.0).exp());
                        h.phase = super::fract(h.phase + freq * dt);
                        let skin = (h.phase * TAU).sin() * (-t * 6.5 / stretch).exp();
                        let stick = noise * (-t * 45.0).exp() * 0.2;
                        ((skin + stick) * 0.8, 0.9 * stretch)
                    }
                    Kind::Crash | Kind::Ride => {
                        let mut metal = 0.0;
                        for (phase, f) in h.phases.iter_mut().zip(METAL) {
                            *phase = super::fract(*phase + f * h.tone * dt);
                            metal += square(*phase);
                        }
                        metal /= 6.0;
                        let (wash, rate, level, length) = if h.kind == Kind::Crash {
                            (0.55, 1.4 * h.tone * h.tone, 0.4, 3.0)
                        } else {
                            (0.15, 2.2 * h.tone, 0.28, 2.5)
                        };
                        let mixed = metal * (1.0 - wash) + noise * wash;
                        // Only the top of it: what a cymbal sounds like.
                        let high = mixed - h.last;
                        h.last = mixed;
                        // The stick on a ride, a ping at the start.
                        let ping = if h.kind == Kind::Ride {
                            h.phase = super::fract(h.phase + 2870.0 * dt);
                            (h.phase * TAU).sin() * (-t * 18.0).exp() * 0.25
                        } else {
                            0.0
                        };
                        let env = (-t * rate / stretch).exp() * (1.0 - (-t * 400.0).exp());
                        ((high * env + ping) * level, length * stretch / h.tone)
                    }
                    Kind::Bell => {
                        // The bell of a ride: few partials, a long ring.
                        h.phase = super::fract(h.phase + 740.0 * dt);
                        h.phases[0] = super::fract(h.phases[0] + 1105.0 * dt);
                        h.phases[1] = super::fract(h.phases[1] + 1789.0 * dt);
                        h.phases[2] = super::fract(h.phases[2] + 2600.0 * dt);
                        let ring = (h.phase * TAU).sin()
                            + (h.phases[0] * TAU).sin() * 0.7
                            + (h.phases[1] * TAU).sin() * 0.5
                            + (h.phases[2] * TAU).sin() * 0.3;
                        (ring * (-t * 3.2 / stretch).exp() * 0.16, 1.6 * stretch)
                    }
                    Kind::Cowbell => {
                        // Two square waves a fifth or so apart, as the 808 has it.
                        h.phase = super::fract(h.phase + 540.0 * dt);
                        h.phases[0] = super::fract(h.phases[0] + 800.0 * dt);
                        let raw = square(h.phase) + square(h.phases[0]);
                        h.low += (raw - h.low) * 0.35;
                        let env =
                            0.65 * (-t * 22.0 / stretch).exp() + 0.35 * (-t * 6.0 / stretch).exp();
                        (h.low * env * 0.22, 0.6 * stretch)
                    }
                    Kind::Tambourine => {
                        // Jingles: high noise and bright partials, shaken.
                        let high = noise - h.last;
                        h.last = noise;
                        let mut jingle = 0.0;
                        for (phase, f) in h.phases.iter_mut().take(3).zip([4120.0, 5870.0, 7330.0])
                        {
                            *phase = super::fract(*phase + f * dt);
                            jingle += square(*phase);
                        }
                        let shake = 0.55 + 0.45 * (-super::fract(t * 32.0) * 5.0).exp();
                        let env = (-t * 11.0 / stretch).exp() * shake;
                        ((high * 0.7 + jingle * 0.06) * env * 0.4, 0.45 * stretch)
                    }
                };
                let family = h.kind.family();
                if apart[family] {
                    families[family] += sample * h.vel;
                } else {
                    out += sample * h.vel;
                }
                h.time += dt;
                h.active = h.time < length;
            }
            left[i] += out * gain;
            right[i] += out * gain;
            for (family, pair) in outputs.iter_mut().enumerate() {
                if let Some([l, r]) = pair {
                    let s = families.get(family + 1).copied().unwrap_or(0.0) * gain;
                    l[i] += s;
                    r[i] += s;
                }
            }
        }
    }
}

impl Device for Drums {
    /// No drum rings: a block with no events adds nothing.
    fn resting(&self) -> bool {
        self.hits.iter().all(|h| !h.active)
    }

    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        if io.events.is_empty() && self.resting() {
            return;
        }
        let n = io.left.len();
        let mut pos = 0;
        for ev in io.events.as_slice() {
            let frame = (ev.frame as usize).min(n);
            if frame > pos {
                self.render(io.left, io.right, io.outputs, (pos, frame));
                pos = frame;
            }
            if let EventKind::NoteOn { key, vel, .. } = ev.kind {
                self.trigger(key, vel);
            }
        }
        self.render(io.left, io.right, io.outputs, (pos, n));
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if let Some(p) = self.p.get_mut(index as usize) {
            *p = value;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::{Event, EventBuf};

    /// Render notes `(frame, key, velocity)` for `frames` frames at 48 kHz,
    /// in blocks of 256, and return the left channel.
    fn render(notes: &[(u32, u8, f32)], frames: usize) -> Vec<f32> {
        let mut drums = Drums::new(48000.0);
        let mut out = Vec::with_capacity(frames);
        let mut events = EventBuf::with_capacity(64);
        let ctx = ProcessCtx::at(48000.0, 120.0, 4, 4, true);
        let mut at = 0;
        while at < frames {
            let n = 256.min(frames - at);
            let (mut left, mut right) = (vec![0.0; n], vec![0.0; n]);
            events.clear();
            for &(frame, key, vel) in notes {
                if (frame as usize) >= at && (frame as usize) < at + n {
                    events.push(Event {
                        frame: frame - at as u32,
                        kind: EventKind::NoteOn {
                            key,
                            vel,
                            ch: 9,
                            attr: crate::event::Attr::NONE,
                        },
                    });
                }
            }
            drums.process(
                &ctx,
                &mut Io {
                    left: &mut left,
                    right: &mut right,
                    events: &mut events,
                    sidechain: None,
                    outputs: &mut [],
                },
            );
            out.extend_from_slice(&left);
            at += n;
        }
        out
    }

    /// The notes the kit had at first that keep their sound (all but the
    /// pedal hat, which is a piece of its own now), with open hats ringing
    /// into closed ones, so that choking and voice slots are part of it.
    fn old_notes() -> Vec<(u32, u8, f32)> {
        let mut notes = Vec::new();
        for (i, key) in [36u8, 38, 39, 40, 42, 46, 46, 42, 36, 35, 39, 38]
            .iter()
            .enumerate()
        {
            notes.push((i as u32 * 6000, *key, 0.4 + (i % 4) as f32 * 0.2));
            if i % 3 == 0 {
                notes.push((i as u32 * 6000 + 17, 46, 0.7));
            }
        }
        notes
    }

    fn fingerprint(samples: &[f32]) -> u64 {
        // FNV-1a over the bits of every sample.
        let mut hash = 0xcbf2_9ce4_8422_2325u64;
        for s in samples {
            for b in s.to_bits().to_le_bytes() {
                hash ^= b as u64;
                hash = hash.wrapping_mul(0x100_0000_01b3);
            }
        }
        hash
    }

    #[test]
    fn the_first_seven_notes_sound_as_they_always_did() {
        let samples = render(&old_notes(), 48000 * 2);
        // What the kit made of these before the other pieces were added.
        assert_eq!(fingerprint(&samples), 0xeb21_7e3a_dd2d_aa83);
    }

    /// Loudness (RMS over the first tenth of a second), brightness (zero
    /// crossings a second, from 50 to 150 ms), how long it rings (seconds until it falls 40 dB
    /// below its peak) and how much of it is low (the share of the first
    /// tenth of a second under about 300 Hz).
    fn measure(samples: &[f32]) -> (f32, f32, f32, f32) {
        let head = &samples[..samples.len().min(4800)];
        let rms = (head.iter().map(|s| s * s).sum::<f32>() / head.len() as f32).sqrt();
        // Past the stick's noise at the start.
        let body = &samples[2400.min(samples.len())..samples.len().min(7200)];
        let crossings = body
            .windows(2)
            .filter(|w| (w[0] < 0.0) != (w[1] < 0.0))
            .count();
        let peak = samples.iter().fold(0.0f32, |m, s| m.max(s.abs()));
        let last = samples
            .iter()
            .rposition(|s| s.abs() > peak * 0.01)
            .unwrap_or(0);
        let (mut lp, mut low) = (0.0f32, 0.0f32);
        for s in head {
            lp += (s - lp) * 0.0385;
            low += lp * lp;
        }
        let all = head.iter().map(|s| s * s).sum::<f32>().max(1e-12);
        (
            rms,
            crossings as f32 / (body.len().max(1) as f32 / 48000.0),
            last as f32 / 48000.0,
            low / all,
        )
    }

    const PIECES: [(u8, &str); 15] = [
        (36, "kick"),
        (38, "snare"),
        (37, "rim"),
        (39, "clap"),
        (42, "closed hat"),
        (44, "pedal hat"),
        (46, "open hat"),
        (45, "low tom"),
        (47, "mid tom"),
        (50, "high tom"),
        (49, "crash"),
        (51, "ride"),
        (53, "ride bell"),
        (56, "cowbell"),
        (54, "tambourine"),
    ];

    #[test]
    fn every_piece_a_beat_needs_sounds_and_is_its_own() {
        let measured: Vec<(f32, f32, f32, f32)> = PIECES
            .iter()
            .map(|(key, _)| measure(&render(&[(0, *key, 1.0)], 48000 * 4)))
            .collect();
        for ((_, name), (rms, _, _, _)) in PIECES.iter().zip(&measured) {
            assert!(*rms > 0.005, "{name} makes a sound: rms {rms}");
        }
        // No two alike: each pair differs by an eighth in how bright it is
        // (two semitones, for the toms), or by a quarter in how long it
        // rings, how loud it is, or how much of it is low.
        for i in 0..PIECES.len() {
            for j in i + 1..PIECES.len() {
                let (a, b) = (measured[i], measured[j]);
                let apart = |x: f32, y: f32| (x - y).abs() > 0.25 * x.max(y);
                let brighter = (a.1 - b.1).abs() > 0.12 * a.1.max(b.1);
                assert!(
                    brighter || apart(a.2, b.2) || apart(a.0, b.0) || apart(a.3, b.3),
                    "{} and {} sound alike: {a:?} {b:?}",
                    PIECES[i].1,
                    PIECES[j].1
                );
            }
        }
        // Toms go from low to high.
        let pitch = |key| measure(&render(&[(0, key, 1.0)], 48000)).1;
        assert!(
            pitch(45) < pitch(47) && pitch(47) < pitch(50),
            "toms in order"
        );
    }

    #[test]
    fn closed_and_pedal_hats_cut_the_open_hat_off() {
        let tail = |notes: &[(u32, u8, f32)]| {
            let samples = render(notes, 48000);
            // Between 0.3 and 0.5 s: long after a closed or pedal hat is over.
            measure(&samples[14400..24000]).0
        };
        let open = tail(&[(0, 46, 1.0)]);
        assert!(open > 0.001, "an open hat rings on: {open}");
        assert_eq!(
            tail(&[(0, 46, 1.0), (4800, 42, 1.0)]),
            0.0,
            "a closed hat stops it"
        );
        assert_eq!(
            tail(&[(0, 46, 1.0), (4800, 44, 1.0)]),
            0.0,
            "so does the pedal"
        );
        assert!(
            tail(&[(0, 46, 1.0), (4800, 38, 1.0)]) > 0.001,
            "a snare does not"
        );
    }

    #[test]
    fn notes_outside_the_kit_are_silent() {
        let samples = render(&[(0, 60, 1.0), (100, 34, 1.0), (200, 82, 1.0)], 4800);
        assert!(samples.iter().all(|s| *s == 0.0));
    }
}
