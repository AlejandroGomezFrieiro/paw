//! A kit of samples: one audio file per note, each with its level, pan,
//! tuning and choke group. A note starts its sample from the beginning and
//! lets it play to the end (note-offs are ignored, as drums do); a note of a
//! group cuts off whatever else of that group is sounding, as a closed hat
//! cuts off an open one.
//!
//! The kit is the device's state, so it is saved with the project and set
//! from scripts by setting the device's state: text, a header line and then
//! one line per pad,
//!
//! ```text
//! sampler 1
//! 36 0 0 0 0 /samples/kick.wav
//! 42 -3 0.2 0 1 /samples/hat closed.wav
//! ```
//!
//! that is `note level(dB) pan(-1..1) tune(semitones) group path`, the path
//! running to the end of the line. Files are read and decoded on the main
//! thread when the state is loaded, and the finished kit is handed to the
//! audio thread over a queue; the kit it replaces comes back to be freed.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::float_cmp, reason = "debt: pay down"))]

use std::cell::RefCell;
use std::collections::HashMap;
use std::fmt::Write as _;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::SystemTime;

use anyhow::{Context, Result, bail};
use rtrb::{Consumer, Producer, RingBuffer};

use crate::clip::AudioData;
use crate::db_to_gain;
use crate::device::{
    Controller, Device, DeviceFactory, DeviceInfo, Instance, Io, ParamInfo, ProcessCtx,
};
use paw_types::EventKind;

/// Samples that can sound at once.
pub const VOICES: usize = 32;
/// Kits on their way to the audio thread, and back.
const QUEUE: usize = 8;
/// How long a sample takes to fade out when its group cuts it off.
const CHOKE_SECONDS: f32 = 0.004;
const NONE: u16 = u16::MAX;

pub fn params() -> Vec<ParamInfo> {
    vec![
        ParamInfo::new("gain")
            .range(-60.0, 12.0)
            .default_value(0.0)
            .unit("dB"),
    ]
}

/// One pad of a kit as the state describes it.
#[derive(Clone, Debug, PartialEq)]
pub struct PadDesc {
    pub note: u8,
    /// dB.
    pub level: f32,
    /// -1 left to 1 right.
    pub pan: f32,
    /// Semitones.
    pub tune: f32,
    /// Pads of the same group above 0 cut each other off.
    pub group: u8,
    pub path: PathBuf,
}

const HEADER: &str = "sampler 1";

/// Read a kit's description.
pub fn parse(text: &str) -> Result<Vec<PadDesc>> {
    let mut lines = text.lines().filter(|l| !l.trim().is_empty());
    match lines.next() {
        None => return Ok(Vec::new()),
        Some(first) if first.trim() == HEADER => {}
        Some(first) => bail!("a sampler kit starts with `{HEADER}`, not `{first}`"),
    }
    let mut pads = Vec::new();
    for line in lines {
        let mut fields = line.trim_start().splitn(6, ' ');
        let mut next = |what: &str| {
            fields
                .next()
                .filter(|f| !f.is_empty())
                .with_context(|| format!("a pad line has no {what}: `{line}`"))
        };
        let note: u8 = next("note")?.parse().context("bad note")?;
        let level: f32 = next("level")?.parse().context("bad level")?;
        let pan: f32 = next("pan")?.parse().context("bad pan")?;
        let tune: f32 = next("tune")?.parse().context("bad tune")?;
        let group: u8 = next("group")?.parse().context("bad group")?;
        let path = PathBuf::from(next("file")?);
        if note > 127 {
            bail!("note {note} is not a MIDI note");
        }
        pads.push(PadDesc {
            note,
            level,
            pan: pan.clamp(-1.0, 1.0),
            tune,
            group,
            path,
        });
    }
    Ok(pads)
}

/// Write a kit's description, which [`parse`] reads back.
pub fn write(pads: &[PadDesc]) -> String {
    let mut out = format!("{HEADER}\n");
    for p in pads {
        let _ = writeln!(
            out,
            "{} {} {} {} {} {}",
            p.note,
            p.level,
            p.pan,
            p.tune,
            p.group,
            p.path.display()
        );
    }
    out
}

/// Decoded files by path, with when the file was last changed.
type Files = HashMap<PathBuf, (Option<SystemTime>, Arc<AudioData>)>;

thread_local! {
    // Decoded files, shared by every instance and by offline renders, and
    // read again when the file changes. Main thread only.
    static FILES: RefCell<Files> = RefCell::new(HashMap::new());
}

fn load_file(path: &Path) -> Result<Arc<AudioData>> {
    let modified = std::fs::metadata(path)
        .with_context(|| format!("reading {}", path.display()))?
        .modified()
        .ok();
    if let Some(data) = FILES.with(|f| {
        f.borrow()
            .get(path)
            .filter(|(when, _)| *when == modified)
            .map(|(_, data)| data.clone())
    }) {
        return Ok(data);
    }
    let data = AudioData::load(path)?;
    FILES.with(|f| {
        f.borrow_mut()
            .insert(path.to_path_buf(), (modified, data.clone()))
    });
    Ok(data)
}

/// A pad ready to play.
struct Pad {
    data: Arc<AudioData>,
    gain_l: f32,
    gain_r: f32,
    /// Frames of the file per frame of output.
    step: f64,
    group: u8,
}

/// What the audio thread plays from.
#[derive(Default)]
struct Kit {
    pads: Vec<Pad>,
    /// The pad of each note, or [`NONE`].
    by_note: Vec<u16>,
}

impl Kit {
    fn build(pads: &[PadDesc], sample_rate: f32) -> (Kit, Vec<String>) {
        let mut kit = Kit {
            pads: Vec::new(),
            by_note: vec![NONE; 128],
        };
        let mut problems = Vec::new();
        for p in pads {
            let data = match load_file(&p.path) {
                Ok(data) => data,
                Err(err) => {
                    problems.push(format!("{err:#}"));
                    continue;
                }
            };
            // Equal power, with the centre at full level on both sides.
            let angle = (p.pan.clamp(-1.0, 1.0) + 1.0) * std::f32::consts::FRAC_PI_4;
            let gain = db_to_gain(p.level as f64) * std::f32::consts::SQRT_2;
            let step =
                data.sample_rate as f64 / sample_rate as f64 * 2f64.powf(p.tune as f64 / 12.0);
            kit.by_note[p.note as usize] = kit.pads.len() as u16;
            kit.pads.push(Pad {
                data,
                gain_l: gain * angle.cos(),
                gain_r: gain * angle.sin(),
                step,
                group: p.group,
            });
        }
        (kit, problems)
    }
}

#[derive(Clone, Copy)]
struct Voice {
    pad: u16,
    /// Frame of the file, fractional.
    pos: f64,
    vel: f32,
    /// 1 while playing; falls to 0 once cut off.
    fade: f32,
    fading: bool,
    active: bool,
}

const SILENT: Voice = Voice {
    pad: NONE,
    pos: 0.0,
    vel: 0.0,
    fade: 1.0,
    fading: false,
    active: false,
};

/// The audio-thread side.
pub struct Sampler {
    gain: f32,
    kit: Arc<Kit>,
    kits: Consumer<Arc<Kit>>,
    garbage: Producer<Arc<Kit>>,
    voices: [Voice; VOICES],
    fade_step: f32,
}

impl Sampler {
    fn take_kits(&mut self) {
        while let Ok(kit) = self.kits.pop() {
            let old = std::mem::replace(&mut self.kit, kit);
            // What was playing belongs to the old kit.
            self.voices = [SILENT; VOICES];
            if let Err(rtrb::PushError::Full(old)) = self.garbage.push(old) {
                // Freeing here could block, so leak instead.
                std::mem::forget(old);
            }
        }
    }

    fn trigger(&mut self, key: u8, vel: f32) {
        let Some(&pad) = self.kit.by_note.get(key as usize) else {
            return;
        };
        if pad == NONE {
            return;
        }
        let group = self.kit.pads[pad as usize].group;
        if group > 0 {
            for v in self.voices.iter_mut().filter(|v| v.active) {
                if self.kit.pads[v.pad as usize].group == group {
                    v.fading = true;
                }
            }
        }
        // A free voice, or else the one that has played longest.
        let slot = match self.voices.iter().position(|v| !v.active) {
            Some(slot) => slot,
            None => {
                let mut oldest = 0;
                for (i, v) in self.voices.iter().enumerate() {
                    if v.pos > self.voices[oldest].pos {
                        oldest = i;
                    }
                }
                oldest
            }
        };
        self.voices[slot] = Voice {
            pad,
            pos: 0.0,
            vel,
            fade: 1.0,
            fading: false,
            active: true,
        };
    }

    fn render(&mut self, left: &mut [f32], right: &mut [f32]) {
        let kit = &*self.kit;
        for v in self.voices.iter_mut().filter(|v| v.active) {
            let pad = &kit.pads[v.pad as usize];
            let [l_data, r_data] = &pad.data.channels;
            let frames = l_data.len();
            let gl = pad.gain_l * v.vel * self.gain;
            let gr = pad.gain_r * v.vel * self.gain;
            for (l, r) in left.iter_mut().zip(right.iter_mut()) {
                let i = v.pos as usize;
                if i + 1 >= frames || v.fade <= 0.0 {
                    v.active = false;
                    break;
                }
                let t = (v.pos - i as f64) as f32;
                let sl = l_data[i] + (l_data[i + 1] - l_data[i]) * t;
                let sr = r_data[i] + (r_data[i + 1] - r_data[i]) * t;
                *l += sl * gl * v.fade;
                *r += sr * gr * v.fade;
                v.pos += pad.step;
                if v.fading {
                    v.fade -= self.fade_step;
                }
            }
        }
    }
}

impl Device for Sampler {
    /// No pad sounds: a block with no events adds nothing.
    fn resting(&self) -> bool {
        self.voices.iter().all(|v| !v.active)
    }

    fn process(&mut self, _ctx: &ProcessCtx, io: &mut Io) {
        self.take_kits();
        let n = io.left.len();
        let mut pos = 0;
        for ev in io.events.as_slice() {
            let frame = (ev.frame as usize).min(n);
            if frame > pos {
                self.render(&mut io.left[pos..frame], &mut io.right[pos..frame]);
                pos = frame;
            }
            if let EventKind::NoteOn { key, vel, .. } = ev.kind {
                self.trigger(key, vel);
            }
        }
        self.render(&mut io.left[pos..], &mut io.right[pos..]);
    }

    fn set_param(&mut self, index: u32, value: f32) {
        if index == 0 {
            self.gain = db_to_gain(value as f64);
        }
    }
}

/// The main-thread side: the kit's description, and the queue to the device.
struct Control {
    sample_rate: f32,
    pads: Vec<PadDesc>,
    problems: Vec<String>,
    kits: Producer<Arc<Kit>>,
    garbage: Consumer<Arc<Kit>>,
    /// A kit that did not fit in the queue yet.
    waiting: Option<Arc<Kit>>,
}

impl Control {
    fn send(&mut self) {
        while self.garbage.pop().is_ok() {}
        if let Some(kit) = self.waiting.take()
            && let Err(rtrb::PushError::Full(kit)) = self.kits.push(kit)
        {
            self.waiting = Some(kit);
        }
    }
}

impl Controller for Control {
    fn params(&self) -> Vec<ParamInfo> {
        params()
    }

    fn value(&self, _index: usize) -> Option<f64> {
        None
    }

    fn save_state(&mut self) -> Result<Option<Vec<u8>>> {
        Ok(Some(write(&self.pads).into_bytes()))
    }

    fn load_state(&mut self, state: &[u8]) -> Result<()> {
        let pads = parse(std::str::from_utf8(state).context("a sampler kit is text")?)?;
        let (kit, problems) = Kit::build(&pads, self.sample_rate);
        self.pads = pads;
        self.problems = problems;
        // Only the latest kit matters: one still waiting is replaced.
        self.waiting = Some(Arc::new(kit));
        self.send();
        if !self.problems.is_empty() {
            bail!("{}", self.problems.join("; "));
        }
        Ok(())
    }

    fn follows_state(&self) -> bool {
        true
    }

    fn idle(&mut self) {
        self.send();
    }

    /// `status`: a line per pad, `note frames rate path` for a file that
    /// was read and `note missing path` for one that was not.
    fn call(&mut self, method: &str, _data: &[u8]) -> Result<Vec<u8>> {
        match method {
            "status" => {
                let mut out = String::new();
                for p in &self.pads {
                    match FILES.with(|f| f.borrow().get(&p.path).map(|(_, d)| d.clone())) {
                        Some(data) => {
                            let _ = writeln!(
                                out,
                                "{} {} {} {}",
                                p.note,
                                data.frames(),
                                data.sample_rate,
                                p.path.display()
                            );
                        }
                        None => {
                            let _ = writeln!(out, "{} missing {}", p.note, p.path.display());
                        }
                    }
                }
                Ok(out.into_bytes())
            }
            _ => bail!("the sampler has no method `{method}`"),
        }
    }
}

pub struct Factory {
    pub info: DeviceInfo,
}

impl DeviceFactory for Factory {
    fn info(&self) -> &DeviceInfo {
        &self.info
    }

    fn create(&self, sample_rate: f32, _max_block: usize) -> Result<Instance> {
        let (kits_tx, kits_rx) = RingBuffer::new(QUEUE);
        let (garbage_tx, garbage_rx) = RingBuffer::new(QUEUE * 2);
        Ok(Instance {
            device: Box::new(Sampler {
                gain: 1.0,
                kit: Arc::new(Kit {
                    pads: Vec::new(),
                    by_note: vec![NONE; 128],
                }),
                kits: kits_rx,
                garbage: garbage_tx,
                voices: [SILENT; VOICES],
                fade_step: 1.0 / (CHOKE_SECONDS * sample_rate).max(1.0),
            }),
            controller: Some(Box::new(Control {
                sample_rate,
                pads: Vec::new(),
                problems: Vec::new(),
                kits: kits_tx,
                garbage: garbage_rx,
                waiting: None,
            })),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::{Event, EventBuf};

    fn wav(path: &Path, rate: u32, samples: &[f32]) {
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: rate,
            bits_per_sample: 32,
            sample_format: hound::SampleFormat::Float,
        };
        let mut w = hound::WavWriter::create(path, spec).unwrap();
        for s in samples {
            w.write_sample(*s).unwrap();
        }
        w.finalize().unwrap();
    }

    fn run(device: &mut dyn Device, notes: &[(u32, u8)], frames: usize) -> (Vec<f32>, Vec<f32>) {
        let mut events = EventBuf::with_capacity(16);
        for &(frame, key) in notes {
            events.push(Event {
                frame,
                kind: EventKind::NoteOn {
                    key,
                    vel: 1.0,
                    ch: 0,
                    attr: paw_types::Attr::NONE,
                },
            });
        }
        let (mut left, mut right) = (vec![0.0; frames], vec![0.0; frames]);
        let ctx = ProcessCtx::at(1000.0, 120.0, 4, 4, true);
        device.process(
            &ctx,
            &mut Io {
                left: &mut left,
                right: &mut right,
                events: &mut events,
                sidechain: None,
                outputs: &mut [],
            },
        );
        (left, right)
    }

    #[test]
    fn a_kit_reads_back_as_it_was_written() {
        let pads = vec![
            PadDesc {
                note: 36,
                level: -3.5,
                pan: 0.25,
                tune: -2.0,
                group: 0,
                path: "/a b/kick one.wav".into(),
            },
            PadDesc {
                note: 46,
                level: 0.0,
                pan: 0.0,
                tune: 0.0,
                group: 1,
                path: "hat.wav".into(),
            },
        ];
        assert_eq!(parse(&write(&pads)).unwrap(), pads);
        assert!(parse("sampler 1\n36 0 0 0\n").is_err(), "a short line");
        assert!(parse("something else\n").is_err(), "another format");
        assert!(parse("").unwrap().is_empty(), "nothing is an empty kit");
    }

    #[test]
    fn plays_each_note_s_file_with_level_pan_tune_and_choke() {
        let dir = std::env::temp_dir().join(format!("paw-sampler-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let (one, ramp) = (dir.join("one.wav"), dir.join("ramp.wav"));
        wav(&one, 1000, &[0.5; 100]);
        wav(
            &ramp,
            500,
            &(0..100).map(|i| i as f32 / 100.0).collect::<Vec<_>>(),
        );
        let factory = Factory {
            info: DeviceInfo::default(),
        };
        let Instance { device, controller } = factory.create(1000.0, 64).unwrap();
        let (mut device, mut control) = (device, controller.unwrap());
        let kit = format!(
            "sampler 1\n36 0 0 0 0 {}\n38 -6.0206 -1 0 1 {}\n40 0 1 12 1 {}\n",
            one.display(),
            one.display(),
            ramp.display()
        );
        control.load_state(kit.as_bytes()).unwrap();
        assert_eq!(
            String::from_utf8(control.save_state().unwrap().unwrap()).unwrap(),
            kit
        );

        // 36: the file as it is, in the middle.
        let (l, r) = run(&mut *device, &[(10, 36)], 200);
        assert_eq!(l[9], 0.0);
        assert!(
            (l[10] - 0.5).abs() < 1e-5 && (r[50] - 0.5).abs() < 1e-5,
            "{}",
            l[10]
        );
        assert_eq!(l[150], 0.0, "and silent once the file has played");

        // 38: half as loud, all to the left. 40, of the same group, cuts it off.
        let (l, r) = run(&mut *device, &[(0, 38), (50, 40)], 200);
        // Hard left is 3 dB up on the left, as equal-power panning has it.
        let left = 0.5 * 0.5 * std::f32::consts::SQRT_2;
        assert!(
            (l[20] - left).abs() < 1e-4 && r[20].abs() < 1e-6,
            "{} {}",
            l[20],
            r[20]
        );
        assert!(l[60].abs() < 1e-5, "cut off within a few milliseconds");
        // 40: a file at half the rate, an octave up, so it plays at the
        // rate it was made at: 100 frames from frame 50.
        assert!(r[60] > 0.0 && r[60] < r[80], "the ramp plays on the right");
        assert!(
            r[140] > 0.0 && r[160] == 0.0,
            "and is over after 100 frames"
        );

        // A note with no pad is silent; so is a kit with a file missing.
        let (l, _) = run(&mut *device, &[(0, 50)], 50);
        assert!(l.iter().all(|s| *s == 0.0));
        let missing = format!("sampler 1\n36 0 0 0 0 {}\n", dir.join("nope.wav").display());
        assert!(
            control.load_state(missing.as_bytes()).is_err(),
            "says what is missing"
        );
        let (l, _) = run(&mut *device, &[(0, 36)], 50);
        assert!(l.iter().all(|s| *s == 0.0), "and that pad is silent");
        let status = String::from_utf8(control.call("status", &[]).unwrap()).unwrap();
        assert!(status.starts_with("36 missing "), "{status}");
    }
}
