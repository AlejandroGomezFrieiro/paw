//! The player: an instrument made ready to play (`Program`, built off the
//! audio thread), and the voices that play it (`Engine`, on the audio
//! thread, which allocates, locks and reads files never).

use crate::audio::{PAD, Pcm, Sample, Store, Value};
use crate::interp::{self, BEFORE, Quality, TAPS};
use crate::model::*;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, Ordering::Relaxed};
use std::time::Instant;

/// Voices the pool holds: the most the polyphony parameter allows, and
/// some to let stolen voices fade out.
pub const MAX_POLYPHONY: usize = 256;
const POOL: usize = MAX_POLYPHONY + 32;
/// Modulation (envelopes on pitch and filter, controllers, crossfades) is
/// worked out every this many frames; gain moves in a line between.
const CHUNK: usize = 16;
/// Seconds a stolen or choked voice takes to fade.
const FAST_FADE: f32 = 0.006;

/// An instrument with its samples in memory and lookups by key.
pub struct Program {
    pub instrument: Instrument,
    pub samples: Vec<Arc<Sample>>,
    /// Region → index into `samples`.
    region_sample: Vec<usize>,
    /// Regions that may start on a note-on of each key.
    on_key: Vec<Vec<u32>>,
    /// Regions that may start on a note-off of each key.
    off_key: Vec<Vec<u32>>,
    /// The keyswitch on each key, as an index into `instrument.switches`.
    switch_on_key: [Option<u16>; 128],
    /// Round robin counters per region.
    counters: Box<[AtomicU32]>,
    /// Each articulation's M2-123 code, for notes' attributes.
    codes: Vec<u32>,
    pub load_ms: f64,
}

impl Program {
    /// Loads every sample the instrument names (through `store`, which
    /// keeps them for the next load). Regions whose file cannot be read
    /// are left out and reported in the instrument's warnings.
    pub fn new(mut instrument: Instrument, store: &mut Store) -> Program {
        let started = Instant::now();
        // Each file once, all read together.
        let mut paths: Vec<PathBuf> = Vec::new();
        let mut path_index: HashMap<PathBuf, usize> = HashMap::new();
        for r in &instrument.regions {
            if let Source::File(p) = &r.source {
                path_index.entry(p.clone()).or_insert_with(|| {
                    paths.push(p.clone());
                    paths.len() - 1
                });
            }
        }
        let mut samples: Vec<Arc<Sample>> = Vec::new();
        let mut sample_of_path: Vec<Option<usize>> = Vec::with_capacity(paths.len());
        for result in store.load_all(&paths) {
            match result {
                Ok(s) => {
                    samples.push(s);
                    sample_of_path.push(Some(samples.len() - 1));
                }
                Err(e) => {
                    instrument.warn(e.to_string());
                    sample_of_path.push(None);
                }
            }
        }
        let mut waves: Vec<(Source, usize)> = Vec::new();
        let mut region_sample = Vec::new();
        let mut kept = Vec::new();
        for region in std::mem::take(&mut instrument.regions) {
            let index = match &region.source {
                Source::File(path) => sample_of_path[path_index[path]],
                source => Some(match waves.iter().find(|w| &w.0 == source) {
                    Some(w) => w.1,
                    None => {
                        samples.push(Arc::new(match source {
                            Source::Wave(w) => Sample::wave(*w),
                            _ => Sample::silence(),
                        }));
                        waves.push((source.clone(), samples.len() - 1));
                        samples.len() - 1
                    }
                }),
            };
            if let Some(i) = index {
                region_sample.push(i);
                kept.push(region);
            }
        }
        instrument.regions = kept;
        let mut on_key = vec![Vec::new(); 128];
        let mut off_key = vec![Vec::new(); 128];
        for (i, r) in instrument.regions.iter().enumerate() {
            for key in r.lokey..=r.hikey.min(127) {
                match r.trigger {
                    Trigger::Release | Trigger::ReleaseKey => off_key[key as usize].push(i as u32),
                    _ => on_key[key as usize].push(i as u32),
                }
            }
        }
        let mut switch_on_key = [None; 128];
        for (i, s) in instrument.switches.iter().enumerate() {
            switch_on_key[s.key as usize & 127] = Some(i as u16);
        }
        let counters = (0..instrument.regions.len()).map(|_| AtomicU32::new(0)).collect();
        store.trim();
        let codes = crate::m2::codes(&instrument.articulations);
        Program {
            codes,
            instrument,
            samples,
            region_sample,
            on_key,
            off_key,
            switch_on_key,
            counters,
            load_ms: started.elapsed().as_secs_f64() * 1000.0,
        }
    }

    pub fn memory(&self) -> usize {
        self.samples.iter().map(|s| s.bytes()).sum()
    }

    /// Seconds from where a region starts playing (its `offset`) to the
    /// attack of its sample.
    pub fn onset(&self, region: usize) -> f64 {
        let sample = &self.samples[self.region_sample[region]];
        let offset = self.instrument.regions[region].offset;
        sample.onset.saturating_sub(offset) as f64 / sample.rate
    }
}

/// What the plugin's parameters set, as the engine uses them.
#[derive(Clone, Copy, Debug)]
pub struct Settings {
    /// Linear.
    pub gain: f32,
    pub polyphony: usize,
    /// Cents.
    pub tune: f32,
    pub transpose: f32,
    pub attack_scale: f32,
    pub release_scale: f32,
    /// 0..2, scaling how much velocity changes the level.
    pub velocity: f32,
    /// Linear gain of release triggers.
    pub release_level: f32,
    /// Cents added to every filter's cutoff.
    pub cutoff: f32,
    pub quality: Quality,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            gain: 1.0,
            polyphony: 128,
            tune: 0.0,
            transpose: 0.0,
            attack_scale: 1.0,
            release_scale: 1.0,
            velocity: 1.0,
            release_level: 1.0,
            cutoff: 0.0,
            quality: Quality::Sinc,
        }
    }
}

/// A note's attribute (MIDI 2.0): type and data.
pub type Attr = Option<(u8, u16)>;

#[derive(Clone, Copy, PartialEq, Debug)]
enum Stage {
    Delay,
    Attack,
    Hold,
    Decay,
    Sustain,
    Release,
    Done,
}

/// An envelope as it runs.
#[derive(Clone, Copy, Debug)]
struct Eg {
    stage: Stage,
    level: f32,
    left: u32,
    start: f32,
    attack: u32,
    attack_step: f32,
    hold: u32,
    decay_mul: f32,
    sustain: f32,
    release_mul: f32,
}

/// Where an exponential fall ends: -80 dB.
const FLOOR: f32 = 1e-4;

impl Eg {
    const OFF: Eg = Eg {
        stage: Stage::Done,
        level: 0.0,
        left: 0,
        start: 0.0,
        attack: 0,
        attack_step: 0.0,
        hold: 0,
        decay_mul: 0.0,
        sustain: 0.0,
        release_mul: 0.0,
    };

    fn start(e: &Envelope, vel: f32, sr: f32, attack_scale: f32, release_scale: f32) -> Eg {
        let frames = |s: f32| (s.max(0.0) * sr) as u32;
        let fall = |s: f32| if s <= 0.0 { 0.0 } else { (FLOOR.ln() / (s * sr)).exp() };
        let mut eg = Eg {
            stage: Stage::Delay,
            level: 0.0,
            left: frames(e.delay),
            start: e.start.clamp(0.0, 1.0),
            attack: frames((e.attack + e.vel2attack * vel) * attack_scale),
            attack_step: 0.0,
            hold: frames(e.hold),
            decay_mul: fall(e.decay + e.vel2decay * vel),
            sustain: (e.sustain + e.vel2sustain * vel).clamp(0.0, 1.0),
            release_mul: fall(((e.release + e.vel2release * vel) * release_scale).max(0.0005)),
        };
        if eg.left == 0 {
            eg.enter_attack();
        }
        eg
    }

    fn enter_attack(&mut self) {
        self.level = self.start;
        if self.attack == 0 {
            self.level = 1.0;
            self.enter_hold();
        } else {
            self.stage = Stage::Attack;
            self.left = self.attack;
            self.attack_step = (1.0 - self.start) / self.attack as f32;
        }
    }

    fn enter_hold(&mut self) {
        if self.hold > 0 {
            self.stage = Stage::Hold;
            self.left = self.hold;
        } else {
            self.enter_decay();
        }
    }

    fn enter_decay(&mut self) {
        if self.decay_mul > 0.0 && self.sustain < 1.0 {
            self.stage = Stage::Decay;
        } else {
            self.level = self.sustain;
            self.stage = Stage::Sustain;
        }
    }

    fn release(&mut self) {
        if self.stage != Stage::Done {
            self.stage = Stage::Release;
        }
    }

    fn release_in(&mut self, seconds: f32, sr: f32) {
        self.release_mul = (FLOOR.ln() / (seconds.max(0.0005) * sr)).exp();
        self.release();
    }

    #[inline(always)]
    fn next(&mut self) -> f32 {
        match self.stage {
            Stage::Sustain => {}
            Stage::Delay => {
                self.left = self.left.saturating_sub(1);
                if self.left == 0 {
                    self.enter_attack();
                }
                return 0.0;
            }
            Stage::Attack => {
                self.level += self.attack_step;
                self.left -= 1;
                if self.left == 0 || self.level >= 1.0 {
                    self.level = 1.0;
                    self.enter_hold();
                }
            }
            Stage::Hold => {
                self.left -= 1;
                if self.left == 0 {
                    self.enter_decay();
                }
            }
            Stage::Decay => {
                self.level *= self.decay_mul;
                if self.level <= self.sustain {
                    self.level = self.sustain;
                    self.stage = Stage::Sustain;
                }
            }
            Stage::Release => {
                self.level *= self.release_mul;
                if self.level < FLOOR {
                    self.level = 0.0;
                    self.stage = Stage::Done;
                }
            }
            Stage::Done => {}
        }
        self.level
    }

    /// Runs `n` frames on, for envelopes read once a chunk.
    fn skip(&mut self, n: usize) -> f32 {
        for _ in 0..n {
            self.next();
        }
        self.level
    }
}

/// A state-variable filter (Simper's), per channel.
#[derive(Clone, Copy, Default, Debug)]
struct Svf {
    ic1: [f32; 2],
    ic2: [f32; 2],
}

#[derive(Clone, Copy, Default, Debug)]
struct Coefs {
    a1: f32,
    a2: f32,
    a3: f32,
    k: f32,
    /// One-pole.
    g1: f32,
}

impl Coefs {
    fn new(cutoff: f32, resonance_db: f32, sr: f32) -> Coefs {
        let fc = cutoff.clamp(10.0, sr * 0.49);
        let g = (std::f32::consts::PI * fc / sr).tan();
        let q = (std::f32::consts::FRAC_1_SQRT_2 * 10f32.powf(resonance_db / 20.0)).max(0.5);
        let k = 1.0 / q;
        let a1 = 1.0 / (1.0 + g * (g + k));
        Coefs { a1, a2: g * a1, a3: g * g * a1, k, g1: g / (1.0 + g) }
    }
}

impl Svf {
    #[inline(always)]
    fn run(&mut self, c: &Coefs, kind: FilterKind, ch: usize, x: f32) -> f32 {
        match kind {
            FilterKind::Lp1 | FilterKind::Hp1 => {
                let v = (x - self.ic1[ch]) * c.g1;
                let lp = v + self.ic1[ch];
                self.ic1[ch] = lp + v;
                if kind == FilterKind::Lp1 { lp } else { x - lp }
            }
            _ => {
                let v3 = x - self.ic2[ch];
                let v1 = c.a1 * self.ic1[ch] + c.a2 * v3;
                let v2 = self.ic2[ch] + c.a2 * self.ic1[ch] + c.a3 * v3;
                self.ic1[ch] = 2.0 * v1 - self.ic1[ch];
                self.ic2[ch] = 2.0 * v2 - self.ic2[ch];
                match kind {
                    FilterKind::Lp2 | FilterKind::Lp4 => v2,
                    FilterKind::Hp2 | FilterKind::Hp4 => x - c.k * v1 - v2,
                    FilterKind::Bp2 => v1,
                    _ => x - c.k * v1,
                }
            }
        }
    }
}

#[derive(Clone, Copy, Debug)]
struct Voice {
    active: bool,
    region: u32,
    sample: u32,
    key: u8,
    /// Frames into the sample (not counting its padding).
    pos: f64,
    /// Frames per output frame before modulation.
    speed: f64,
    /// The last frame played.
    end: u64,
    looping: bool,
    loop_start: u64,
    loop_end: u64,
    /// Frames of crossfade before the loop's end.
    xfade: u64,
    /// Frames before the voice sounds.
    delay: u32,
    amp: Eg,
    pitch_eg: Eg,
    fil_eg: Eg,
    released: bool,
    /// Gain that is fixed for the voice's life.
    gain: f32,
    /// The gain at the end of the last chunk, per channel.
    last_gain: [f32; 2],
    cutoff: f32,
    filter: Svf,
    filter2: Svf,
    coefs: Coefs,
    age: u64,
    /// Fading out fast after being stolen or choked.
    stolen: bool,
}

impl Voice {
    const IDLE: Voice = Voice {
        active: false,
        region: 0,
        sample: 0,
        key: 0,
        pos: 0.0,
        speed: 1.0,
        end: 0,
        looping: false,
        loop_start: 0,
        loop_end: 0,
        xfade: 0,
        delay: 0,
        amp: Eg::OFF,
        pitch_eg: Eg::OFF,
        fil_eg: Eg::OFF,
        released: false,
        gain: 0.0,
        last_gain: [0.0; 2],
        cutoff: 0.0,
        filter: Svf { ic1: [0.0; 2], ic2: [0.0; 2] },
        filter2: Svf { ic1: [0.0; 2], ic2: [0.0; 2] },
        coefs: Coefs { a1: 0.0, a2: 0.0, a3: 0.0, k: 0.0, g1: 0.0 },
        age: 0,
        stolen: false,
    };
}

pub struct Engine {
    program: Option<Arc<Program>>,
    pub settings: Settings,
    sr: f32,
    voices: Box<[Voice]>,
    cc: [f32; 128],
    bend: f32,
    pedal: bool,
    held: [bool; 128],
    sustained: [bool; 128],
    /// What each held key's note-on was: velocity, frame, switch state.
    note_vel: [f32; 128],
    note_time: [u64; 128],
    note_switch: [u128; 128],
    switch_state: u128,
    previous: Option<u8>,
    rng: u64,
    time: u64,
    ages: u64,
}

impl Engine {
    pub fn new(sample_rate: f64) -> Engine {
        let mut e = Engine {
            program: None,
            settings: Settings::default(),
            sr: sample_rate as f32,
            voices: vec![Voice::IDLE; POOL].into_boxed_slice(),
            cc: [0.0; 128],
            bend: 0.0,
            pedal: false,
            held: [false; 128],
            sustained: [false; 128],
            note_vel: [0.0; 128],
            note_time: [0; 128],
            note_switch: [0; 128],
            switch_state: 0,
            previous: None,
            rng: 1,
            time: 0,
            ages: 0,
        };
        e.reset();
        e
    }

    pub fn program(&self) -> Option<&Arc<Program>> {
        self.program.as_ref()
    }

    /// Plays another program from now on; the voices of the old one stop.
    /// Returns the old one, which the caller drops off the audio thread.
    pub fn swap(&mut self, program: Option<Arc<Program>>) -> Option<Arc<Program>> {
        let old = std::mem::replace(&mut self.program, program);
        self.reset();
        old
    }

    /// Silence and the state of a fresh start: controllers, keyswitches,
    /// round robins and the random draws, so that renders repeat.
    pub fn reset(&mut self) {
        for v in self.voices.iter_mut() {
            v.active = false;
        }
        self.cc = [0.0; 128];
        self.cc[7] = 1.0;
        self.cc[10] = 0.5;
        self.cc[11] = 1.0;
        self.bend = 0.0;
        self.pedal = false;
        self.held = [false; 128];
        self.sustained = [false; 128];
        self.previous = None;
        self.rng = 0x2545_F491_4F6C_DD1D;
        self.switch_state = 0;
        if let Some(p) = &self.program {
            for &(cc, v) in &p.instrument.cc_init {
                self.cc[cc as usize & 127] = v;
            }
            self.switch_state = p.instrument.default_switch;
            for c in p.counters.iter() {
                c.store(0, Relaxed);
            }
        }
    }

    pub fn active_voices(&self) -> usize {
        self.voices.iter().filter(|v| v.active).count()
    }

    fn random(&mut self) -> f32 {
        self.rng ^= self.rng << 13;
        self.rng ^= self.rng >> 7;
        self.rng ^= self.rng << 17;
        (self.rng >> 40) as f32 / (1u64 << 24) as f32
    }

    // --- events ---

    pub fn control(&mut self, cc: u8, value: f32) {
        let cc = cc & 127;
        self.cc[cc as usize] = value.clamp(0.0, 1.0);
        match cc {
            64 => {
                let down = value >= 0.5;
                if self.pedal && !down {
                    self.pedal = false;
                    for key in 0..128u8 {
                        if self.sustained[key as usize] {
                            self.sustained[key as usize] = false;
                            self.release_key(key, 0, false);
                        }
                    }
                }
                self.pedal = down;
            }
            120 => {
                for v in self.voices.iter_mut() {
                    v.active = false;
                }
            }
            121 => {
                self.bend = 0.0;
                self.cc[1] = 0.0;
                self.cc[64] = 0.0;
                self.pedal = false;
            }
            123 => {
                for key in 0..128u8 {
                    if self.held[key as usize] || self.sustained[key as usize] {
                        self.held[key as usize] = false;
                        self.sustained[key as usize] = false;
                        self.release_key(key, 0, true);
                    }
                }
            }
            _ => {}
        }
    }

    /// -1..1.
    pub fn pitch_bend(&mut self, value: f32) {
        self.bend = value.clamp(-1.0, 1.0);
    }

    /// A note-on. `vel` is 0..1 (MIDI 2.0's 16 bits kept); `attr` the
    /// note's MIDI 2.0 attribute, which chooses the articulation of this
    /// note alone.
    pub fn note_on(&mut self, key: u8, vel: f32, ch: u8, attr: Attr) {
        let Some(program) = self.program.clone() else { return };
        let key = key & 127;
        let inst = &program.instrument;
        // A keyswitch changes what the notes after it play.
        if let Some(s) = program.switch_on_key[key as usize] {
            let s = &inst.switches[s as usize];
            self.switch_state = (self.switch_state & !s.mask) | s.values;
            if s.swallow {
                return;
            }
        }
        let mut switch = self.switch_state;
        if let Some((t, data)) = attr {
            if crate::m2::resets_round_robin(t, data) {
                for c in program.counters.iter() {
                    c.store(0, Relaxed);
                }
            }
            if let Some(a) = crate::m2::resolve(&program.codes, t, data) {
                let a = &inst.articulations[a];
                switch = (switch & !a.mask) | a.values;
            }
        }
        let others_held = self.held.iter().enumerate().any(|(k, &h)| h && k != key as usize);
        let vel7 = (vel * 127.0).round().clamp(1.0, 127.0) as u8;
        let draw = self.random();
        let seq_draw = self.random();
        for &ri in &program.on_key[key as usize] {
            let r = &inst.regions[ri as usize];
            match r.trigger {
                Trigger::First if others_held => continue,
                Trigger::Legato if !others_held => continue,
                _ => {}
            }
            if !self.matches(r, vel7, ch, switch, draw) {
                continue;
            }
            if r.sw_previous.is_some() && r.sw_previous != self.previous {
                continue;
            }
            if r.seq_length > 1 {
                let place = match r.seq_mode {
                    SeqMode::RoundRobin => program.counters[ri as usize].fetch_add(1, Relaxed) % r.seq_length,
                    SeqMode::Random => (seq_draw * r.seq_length as f32) as u32 % r.seq_length,
                };
                if place + 1 != r.seq_position {
                    continue;
                }
            }
            self.start(&program, ri, key, vel, 1.0);
        }
        self.held[key as usize] = true;
        self.sustained[key as usize] = false;
        self.note_vel[key as usize] = vel;
        self.note_time[key as usize] = self.time;
        self.note_switch[key as usize] = switch;
        self.previous = Some(key);
    }

    pub fn note_off(&mut self, key: u8, ch: u8) {
        let key = key & 127;
        if !self.held[key as usize] {
            return;
        }
        self.held[key as usize] = false;
        if self.pedal {
            self.sustained[key as usize] = true;
            self.release_triggers(key, ch, Trigger::ReleaseKey);
        } else {
            self.release_key(key, ch, false);
        }
    }

    /// Releases the voices of a key and starts its release triggers.
    fn release_key(&mut self, key: u8, ch: u8, quiet: bool) {
        let Some(program) = self.program.clone() else { return };
        for v in self.voices.iter_mut() {
            if v.active && v.key == key && !v.released {
                let mode = program.instrument.regions[v.region as usize].loop_mode;
                if mode == Some(LoopMode::OneShot) && !quiet {
                    continue;
                }
                // A sustain loop ends with the note; the sample plays on past it.
                if mode == Some(LoopMode::Sustain) {
                    v.looping = false;
                }
                v.released = true;
                v.amp.release();
                v.pitch_eg.release();
                v.fil_eg.release();
            }
        }
        if !quiet {
            self.release_triggers(key, ch, Trigger::Release);
            self.release_triggers(key, ch, Trigger::ReleaseKey);
        }
    }

    fn release_triggers(&mut self, key: u8, ch: u8, kind: Trigger) {
        let Some(program) = self.program.clone() else { return };
        let inst = &program.instrument;
        let vel = self.note_vel[key as usize];
        let vel7 = (vel * 127.0).round().clamp(1.0, 127.0) as u8;
        let held = (self.time - self.note_time[key as usize]) as f32 / self.sr;
        let switch = self.note_switch[key as usize];
        let draw = self.random();
        for &ri in &program.off_key[key as usize] {
            let r = &inst.regions[ri as usize];
            if r.trigger != kind || !self.matches(r, vel7, ch, switch, draw) {
                continue;
            }
            if r.seq_length > 1 {
                let place = program.counters[ri as usize].fetch_add(1, Relaxed) % r.seq_length;
                if place + 1 != r.seq_position {
                    continue;
                }
            }
            let gain = 10f32.powf(-r.rt_decay * held / 20.0) * self.settings.release_level;
            self.start(&program, ri, key, vel, gain);
        }
    }

    fn matches(&self, r: &Region, vel7: u8, ch: u8, switch: u128, draw: f32) -> bool {
        if vel7 < r.lovel || vel7 > r.hivel {
            return false;
        }
        let ch1 = ch + 1;
        if ch1 < r.lochan || ch1 > r.hichan {
            return false;
        }
        if draw < r.lorand || draw >= r.hirand {
            return false;
        }
        if r.switch_any != 0 && switch & r.switch_any == 0 {
            return false;
        }
        if switch & r.switch_all != r.switch_all {
            return false;
        }
        if r.sw_down.is_some_and(|k| !self.held[k as usize]) || r.sw_up.is_some_and(|k| self.held[k as usize]) {
            return false;
        }
        r.cc_ranges.iter().all(|c| {
            let v = self.cc[c.cc as usize];
            v >= c.lo - 1e-6 && v <= c.hi + 1e-6
        })
    }

    /// Starts a voice of region `ri`.
    fn start(&mut self, program: &Program, ri: u32, key: u8, vel: f32, extra_gain: f32) {
        let r = &program.instrument.regions[ri as usize];
        let sample = &program.samples[program.region_sample[ri as usize]];
        let sr = self.sr;

        // Choke groups and polyphony limits stop voices first.
        let first_group = r.groups.first().copied();
        let mut group_count = 0;
        let mut key_count = 0;
        for v in self.voices.iter_mut() {
            if !v.active || v.stolen {
                continue;
            }
            let other = &program.instrument.regions[v.region as usize];
            if !other.off_by.is_empty() && r.groups.iter().any(|g| other.off_by.contains(g)) {
                choke(v, other, sr);
                continue;
            }
            if first_group.is_some() && other.groups.first().copied() == first_group && !v.released {
                group_count += 1;
                if v.key == key {
                    key_count += 1;
                }
            }
        }
        if let (Some(limit), Some(g)) = (r.polyphony, first_group)
            && group_count >= limit
        {
            self.steal_where(|v, reg| reg.groups.first() == Some(&g) && !v.released, program);
        }
        if let (Some(limit), Some(g)) = (r.note_polyphony, first_group)
            && key_count >= limit
        {
            self.steal_where(|v, reg| reg.groups.first() == Some(&g) && v.key == key && !v.released, program);
        }
        let sounding = self.voices.iter().filter(|v| v.active && !v.stolen).count();
        if sounding >= self.settings.polyphony.clamp(1, MAX_POLYPHONY) {
            self.steal(program);
        }
        let slot = match self.voices.iter().position(|v| !v.active) {
            Some(i) => i,
            // Every voice busy, the fading ones too: the oldest goes at once.
            None => (0..self.voices.len()).min_by_key(|&i| self.voices[i].age).unwrap(),
        };

        // Pitch.
        let keycenter = r.keycenter.or(sample.keycenter).unwrap_or(60) as f32;
        let cents = (key as f32 - keycenter) * r.keytrack
            + r.tune
            + r.transpose as f32 * 100.0
            + r.pitch_veltrack * vel
            + sample.fine_tune
            + self.settings.tune
            + self.settings.transpose * 100.0;
        let speed = 2f64.powf(cents as f64 / 1200.0) * sample.rate / sr as f64;

        // Level fixed for the voice's life.
        let veltrack = r.amp_veltrack * self.settings.velocity;
        let curve = |v: f32| match r.amp_velcurve {
            Some(c) => program.instrument.curves.get(c).map_or(v * v, |c| c.at(v)),
            None => v * v,
        };
        // A negative part makes soft notes loud.
        let vt = veltrack.clamp(-1.0, 1.0);
        let vgain = 1.0 - vt.abs() + vt.abs() * if vt >= 0.0 { curve(vel) } else { curve(1.0 - vel) };
        let mut gain = db(r.volume) * r.amplitude * vgain * extra_gain;
        for f in &r.xf_key {
            gain *= f.gain(key as f32, r.xf_keycurve);
        }
        for f in &r.xf_vel {
            gain *= f.gain(vel * 127.0, r.xf_velcurve);
        }

        // The span played, and the loop.
        let last = sample.frames.saturating_sub(1) as u64;
        let end = r.end.unwrap_or(last).min(last);
        let mode = r.loop_mode.unwrap_or(if sample.loop_points.is_some() {
            LoopMode::Continuous
        } else {
            LoopMode::NoLoop
        });
        let (ls, le) = match (r.loop_start, r.loop_end, sample.loop_points) {
            (Some(s), Some(e), _) => (s, e),
            (s, e, Some((fs, fe))) => (s.unwrap_or(fs), e.unwrap_or(fe)),
            (s, e, None) => (s.unwrap_or(0), e.unwrap_or(end)),
        };
        let le = le.min(end);
        let looping = matches!(mode, LoopMode::Continuous | LoopMode::Sustain) && le > ls;
        let xfade = if r.loop_crossfade_frames > 0 {
            r.loop_crossfade_frames
        } else {
            (r.loop_crossfade * sample.rate as f32) as u64
        }
        .min(le.saturating_sub(ls))
        .min(ls);
        let random = if r.offset_random > 0 { self.random() } else { 0.0 };
        let offset = (r.offset + (random * r.offset_random as f32) as u64).min(end);

        let settings = self.settings;
        let filter_cutoff = r.filter.as_ref().map_or(0.0, |f| {
            f.cutoff * cents_ratio((key as f32 - f.keycenter as f32) * f.keytrack + f.veltrack * vel + settings.cutoff)
        });
        self.ages += 1;
        let v = &mut self.voices[slot];
        *v = Voice {
            active: true,
            region: ri,
            sample: program.region_sample[ri as usize] as u32,
            key,
            pos: offset as f64,
            speed,
            end,
            looping,
            loop_start: ls,
            loop_end: le,
            xfade,
            delay: (r.delay.max(0.0) * sr) as u32,
            amp: Eg::start(&r.amp_eg, vel, sr, settings.attack_scale, settings.release_scale),
            pitch_eg: Eg::start(&r.pitch_eg, vel, sr, 1.0, 1.0),
            fil_eg: r.filter.as_ref().map_or(Eg::OFF, |f| Eg::start(&f.eg, vel, sr, 1.0, 1.0)),
            released: false,
            gain,
            last_gain: [0.0; 2],
            cutoff: filter_cutoff,
            filter: Svf::default(),
            filter2: Svf::default(),
            coefs: Coefs::default(),
            age: self.ages,
            stolen: false,
        };
        // The first chunk starts at its own gain, not from silence.
        let first = self.chunk_gain(program, slot);
        self.voices[slot].last_gain = first;
    }

    /// Fades the voice that matters least: released ones first (the
    /// quietest), then the oldest.
    fn steal(&mut self, program: &Program) {
        self.steal_where(|_, _| true, program);
    }

    fn steal_where(&mut self, pick: impl Fn(&Voice, &Region) -> bool, program: &Program) {
        let mut best: Option<usize> = None;
        for (i, v) in self.voices.iter().enumerate() {
            if !v.active || v.stolen || !pick(v, &program.instrument.regions[v.region as usize]) {
                continue;
            }
            best = Some(match best {
                None => i,
                Some(b) => {
                    let o = &self.voices[b];
                    let better = match (v.released, o.released) {
                        (true, false) => true,
                        (false, true) => false,
                        (true, true) => v.amp.level < o.amp.level,
                        (false, false) => v.age < o.age,
                    };
                    if better { i } else { b }
                }
            });
        }
        if let Some(i) = best {
            let sr = self.sr;
            let v = &mut self.voices[i];
            v.stolen = true;
            v.released = true;
            v.amp.release_in(FAST_FADE, sr);
        }
    }

    // --- sound ---

    /// The gain of each channel for the chunk starting now: the voice's
    /// fixed gain, the controllers' and crossfades', pan and the plugin's.
    fn chunk_gain(&self, program: &Program, i: usize) -> [f32; 2] {
        let v = &self.voices[i];
        let r = &program.instrument.regions[v.region as usize];
        let mut gain = v.gain * self.settings.gain;
        // Channel volume and expression (CC 7, 11), squared as a fader.
        gain *= self.cc[7] * self.cc[7] * self.cc[11] * self.cc[11];
        for (cc, f) in &r.xf_cc {
            gain *= f.gain(self.cc[*cc as usize], r.xf_cccurve);
        }
        let mut pan = r.pan + (self.cc[10] * 2.0 - 1.0);
        let mut volume = 0.0;
        for m in &r.mods {
            let x = self.mod_value(program, m);
            match m.target {
                Target::Amplitude => gain *= (1.0 - m.depth / 100.0) + x * m.depth / 100.0,
                Target::Volume => volume += x * m.depth,
                Target::Pan => pan += x * m.depth / 100.0,
                _ => {}
            }
        }
        gain *= db(volume);
        let pan = pan.clamp(-1.0, 1.0);
        // Equal power, unity in the middle.
        let angle = (pan + 1.0) * std::f32::consts::FRAC_PI_4;
        let s = std::f32::consts::SQRT_2;
        [gain * angle.cos() * s, gain * angle.sin() * s]
    }

    fn mod_value(&self, program: &Program, m: &CcMod) -> f32 {
        let x = self.cc[m.cc as usize];
        match m.curve.and_then(|c| program.instrument.curves.get(c)) {
            Some(c) => c.at(x),
            None => x,
        }
    }

    /// Adds `frames` frames of every voice to `left` and `right`.
    pub fn render(&mut self, left: &mut [f32], right: &mut [f32]) {
        let frames = left.len().min(right.len());
        let Some(program) = self.program.clone() else {
            self.time += frames as u64;
            return;
        };
        let tables = interp::tables();
        for i in 0..self.voices.len() {
            if !self.voices[i].active {
                continue;
            }
            let mut done = 0;
            while done < frames && self.voices[i].active {
                let n = CHUNK.min(frames - done);
                self.render_chunk(&program, tables, i, &mut left[done..done + n], &mut right[done..done + n]);
                done += n;
            }
        }
        self.time += frames as u64;
    }

    fn render_chunk(&mut self, program: &Program, tables: &interp::Tables, i: usize, left: &mut [f32], right: &mut [f32]) {
        let n = left.len();
        let sr = self.sr;
        let r = &program.instrument.regions[self.voices[i].region as usize];
        let target = self.chunk_gain(program, i);
        let mut pitch = r.bend_up.max(0.0) * self.bend.max(0.0) - r.bend_down.min(0.0) * self.bend.min(0.0);
        let mut cutoff_cents = 0.0;
        let mut resonance = r.filter.as_ref().map_or(0.0, |f| f.resonance);
        for m in &r.mods {
            let x = self.mod_value(program, m);
            match m.target {
                Target::Pitch => pitch += x * m.depth,
                Target::Cutoff => cutoff_cents += x * m.depth,
                Target::Resonance => resonance += x * m.depth,
                _ => {}
            }
        }
        let quality = self.settings.quality;
        let v = &mut self.voices[i];
        let pitch_level = v.pitch_eg.skip(n);
        pitch += pitch_level * r.pitch_eg_depth;
        let speed = v.speed * cents_ratio(pitch) as f64;
        if let Some(f) = &r.filter {
            let level = v.fil_eg.skip(n);
            let cutoff = v.cutoff * cents_ratio(cutoff_cents + level * f.eg_depth);
            v.coefs = Coefs::new(cutoff, resonance, sr);
        }
        let sample = &program.samples[v.sample as usize];
        let start_gain = v.last_gain;
        v.last_gain = target;
        let chunk = Chunk {
            speed,
            start_gain,
            target,
            filter: r.filter.as_ref().map(|f| f.kind),
            width: r.width,
            position: r.position,
            table: tables.for_speed(speed),
        };
        // One loop per kind of sample and of interpolation, so that the
        // frame loop decides nothing it could decide once.
        match (&sample.pcm, quality) {
            (Pcm::I16(d), Quality::Linear) => run::<i16, LINEAR>(v, sample, d, &chunk, left, right),
            (Pcm::I16(d), Quality::Hermite) => run::<i16, HERMITE>(v, sample, d, &chunk, left, right),
            (Pcm::I16(d), Quality::Sinc) => run::<i16, SINC>(v, sample, d, &chunk, left, right),
            (Pcm::F32(d), Quality::Linear) => run::<f32, LINEAR>(v, sample, d, &chunk, left, right),
            (Pcm::F32(d), Quality::Hermite) => run::<f32, HERMITE>(v, sample, d, &chunk, left, right),
            (Pcm::F32(d), Quality::Sinc) => run::<f32, SINC>(v, sample, d, &chunk, left, right),
        }
    }

    /// Voices sounding now, for the host (CLAP voice-info).
    pub fn voice_count(&self) -> u32 {
        self.voices.iter().filter(|v| v.active && !v.stolen).count() as u32
    }
}

fn choke(v: &mut Voice, region: &Region, sr: f32) {
    v.released = true;
    if region.off_fast {
        v.stolen = true;
        v.amp.release_in(FAST_FADE, sr);
    } else {
        v.amp.release_in(region.off_time, sr);
    }
}

fn db(v: f32) -> f32 {
    10f32.powf(v / 20.0)
}

fn cents_ratio(cents: f32) -> f32 {
    (cents * (std::f32::consts::LN_2 / 1200.0)).exp()
}

/// What a voice's chunk keeps the same from frame to frame.
struct Chunk<'a> {
    speed: f64,
    start_gain: [f32; 2],
    target: [f32; 2],
    filter: Option<FilterKind>,
    width: f32,
    position: f32,
    table: &'a [f32],
}

const LINEAR: u8 = 0;
const HERMITE: u8 = 1;
const SINC: u8 = 2;

/// Plays a chunk of one voice into `left` and `right`.
fn run<S: Value, const Q: u8>(v: &mut Voice, sample: &Sample, data: &[S], c: &Chunk, left: &mut [f32], right: &mut [f32]) {
    let n = left.len();
    let step = 1.0 / n as f32;
    let mut coefs = [0.0f32; TAPS];
    let stereo = sample.channels == 2;
    let image = stereo && (c.width != 1.0 || c.position != 0.0);
    for f in 0..n {
        if v.delay > 0 {
            v.delay -= 1;
            continue;
        }
        let env = v.amp.next();
        if v.amp.stage == Stage::Done {
            v.active = false;
            return;
        }
        let ipos = v.pos as usize;
        let frac = (v.pos - ipos as f64) as f32;
        let (mut l, mut r) = read::<S, Q>(data, stereo, sample, v, ipos, frac, c.table, &mut coefs);
        if v.looping && v.xfade > 0 {
            let into = v.pos - (v.loop_end + 1 - v.xfade) as f64;
            if into >= 0.0 {
                // The loop's end fades into what comes before its start.
                let t = (into / v.xfade as f64) as f32;
                let back = v.pos - (v.loop_end + 1 - v.loop_start) as f64;
                let bi = back as usize;
                let (bl, br) = read::<S, Q>(data, stereo, sample, v, bi, (back - bi as f64) as f32, c.table, &mut coefs);
                let (go, gi) = ((1.0 - t).sqrt(), t.sqrt());
                l = l * go + bl * gi;
                r = r * go + br * gi;
            }
        }
        if image {
            let mid = (l + r) * 0.5;
            let side = (l - r) * 0.5 * c.width;
            let a = (c.position + 1.0) * std::f32::consts::FRAC_PI_4;
            l = (mid + side) * a.cos() * std::f32::consts::SQRT_2;
            r = (mid - side) * a.sin() * std::f32::consts::SQRT_2;
        }
        if let Some(kind) = c.filter {
            l = v.filter.run(&v.coefs, kind, 0, l);
            r = v.filter.run(&v.coefs, kind, 1, r);
            if matches!(kind, FilterKind::Lp4 | FilterKind::Hp4) {
                l = v.filter2.run(&v.coefs, kind, 0, l);
                r = v.filter2.run(&v.coefs, kind, 1, r);
            }
        }
        let t = (f + 1) as f32 * step;
        left[f] += l * (c.start_gain[0] + (c.target[0] - c.start_gain[0]) * t) * env;
        right[f] += r * (c.start_gain[1] + (c.target[1] - c.start_gain[1]) * t) * env;

        v.pos += c.speed;
        if v.looping {
            if v.pos >= (v.loop_end + 1) as f64 {
                v.pos -= (v.loop_end + 1 - v.loop_start) as f64;
            }
        } else if v.pos > v.end as f64 {
            v.active = false;
            return;
        }
    }
}

/// The frame of the sample under `index` (which may be past the loop's
/// end, read from its start), as an index into the padded data.
#[inline(always)]
fn place(sample: &Sample, v: &Voice, index: isize) -> usize {
    let mut i = index;
    if v.looping {
        let len = (v.loop_end + 1 - v.loop_start) as isize;
        while i > v.loop_end as isize {
            i -= len;
        }
    }
    (i + PAD as isize).clamp(0, (sample.frames + 2 * PAD - 1) as isize) as usize
}

/// The sample's value (both channels) at `ipos + frac`.
#[allow(clippy::too_many_arguments)]
#[inline(always)]
fn read<S: Value, const Q: u8>(
    data: &[S],
    stereo: bool,
    sample: &Sample,
    v: &Voice,
    ipos: usize,
    frac: f32,
    table: &[f32],
    coefs: &mut [f32; TAPS],
) -> (f32, f32) {
    let ch = if stereo { 2 } else { 1 };
    // A sample that does not loop, or a place whose taps are all before
    // the loop's end: frames are read straight.
    let straight = !v.looping || ipos + TAPS - BEFORE <= v.loop_end as usize;
    if Q == SINC {
        interp::coefficients(table, frac, coefs);
        let (mut l, mut r) = (0.0f32, 0.0f32);
        if straight {
            let base = (ipos + PAD - BEFORE) * ch;
            if stereo {
                let w = &data[base..base + 2 * TAPS];
                for k in 0..TAPS {
                    l += w[2 * k].f() * coefs[k];
                    r += w[2 * k + 1].f() * coefs[k];
                }
            } else {
                let w = &data[base..base + TAPS];
                for k in 0..TAPS {
                    l += w[k].f() * coefs[k];
                }
                r = l;
            }
        } else {
            for (k, c) in coefs.iter().enumerate() {
                let i = place(sample, v, ipos as isize + k as isize - BEFORE as isize) * ch;
                l += data[i].f() * c;
                r += data[i + ch - 1].f() * c;
            }
        }
        return (l, r);
    }
    let at = |k: isize| {
        if straight {
            (ipos as isize + PAD as isize + k) as usize * ch
        } else {
            place(sample, v, ipos as isize + k) * ch
        }
    };
    if Q == HERMITE {
        let (a, b, c, d) = (at(-1), at(0), at(1), at(2));
        let l = interp::hermite(data[a].f(), data[b].f(), data[c].f(), data[d].f(), frac);
        let r = if stereo {
            interp::hermite(data[a + 1].f(), data[b + 1].f(), data[c + 1].f(), data[d + 1].f(), frac)
        } else {
            l
        };
        return (l, r);
    }
    let (a, b) = (at(0), at(1));
    let l = data[a].f() + (data[b].f() - data[a].f()) * frac;
    let r = if stereo { data[a + 1].f() + (data[b + 1].f() - data[a + 1].f()) * frac } else { l };
    (l, r)
}
