//! Hearing an instance on another machine: the `audio.frame` events it
//! sends a connection that listens (see `paw_proto::monitor`), played here
//! through this machine's sound device, or written to a file in its place.
//!
//! Frames arrive when the network brings them, which is not evenly. They
//! wait in a jitter buffer that starts playing once it holds a fifth of a
//! second, plays silence and fills up again when it runs dry, and drops the
//! oldest sound when it holds more than a second, so that the delay never
//! grows without end. The delay is large; this is for monitoring.
#![expect(clippy::allow_attributes, reason = "debt: pay down")]
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use std::collections::VecDeque;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use serde_json::Value;

/// How much sound waits before playing starts, and the most that may wait.
pub const PREFILL: f64 = 0.2;
pub const MOST: f64 = 1.0;

/// Frames that came in, played out at another rate.
pub struct Jitter {
    /// Left and right interleaved, at `rate`.
    queue: VecDeque<f32>,
    rate: u32,
    out_rate: u32,
    /// Where between the first two frames of the queue playing is.
    pos: f64,
    playing: bool,
    /// Times it ran dry.
    pub underruns: u64,
}

impl Jitter {
    pub fn new(out_rate: u32) -> Self {
        Self { queue: VecDeque::new(), rate: 0, out_rate, pos: 0.0, playing: false, underruns: 0 }
    }

    /// Seconds of sound waiting.
    pub fn waiting(&self) -> f64 {
        if self.rate == 0 { 0.0 } else { self.queue.len() as f64 / 2.0 / self.rate as f64 }
    }

    /// Take an `audio.frame` payload.
    pub fn push(&mut self, payload: &Value) -> Result<()> {
        let frame = paw_proto::monitor::decode(payload)?;
        if frame.rate != self.rate {
            self.queue.clear();
            self.rate = frame.rate;
            self.playing = false;
        }
        self.queue.extend(frame.samples);
        let most = (MOST * self.rate as f64) as usize * 2;
        if self.queue.len() > most {
            // Fallen behind: back to the delay it started with.
            let keep = (PREFILL * self.rate as f64) as usize * 2;
            let drop = self.queue.len() - keep;
            self.queue.drain(..drop);
        }
        Ok(())
    }

    /// Fill `out` (frames of `channels`) with what is to be heard now.
    pub fn pull(&mut self, out: &mut [f32], channels: usize) {
        if !self.playing && self.waiting() >= PREFILL {
            self.playing = true;
        }
        let step = self.rate as f64 / self.out_rate as f64;
        for frame in out.chunks_exact_mut(channels.max(1)) {
            // Two frames to go between, at least.
            if !self.playing || self.queue.len() < 4 {
                if self.playing {
                    self.playing = false;
                    self.underruns += 1;
                }
                frame.fill(0.0);
                continue;
            }
            let t = self.pos as f32;
            let left = self.queue[0] + (self.queue[2] - self.queue[0]) * t;
            let right = self.queue[1] + (self.queue[3] - self.queue[1]) * t;
            match frame {
                [mono] => *mono = (left + right) * 0.5,
                [l, r, rest @ ..] => {
                    *l = left;
                    *r = right;
                    rest.fill(0.0);
                }
                [] => {}
            }
            self.pos += step;
            while self.pos >= 1.0 && self.queue.len() >= 2 {
                self.queue.drain(..2);
                self.pos -= 1.0;
            }
        }
    }
}

/// Where the sound goes.
enum Output {
    #[cfg(feature = "device")]
    Device(#[allow(dead_code, reason = "held only to keep the stream open")] cpal::Stream),
    /// A thread that takes the sound at the pace a device would and writes
    /// it to a file.
    File { stop: Arc<AtomicBool>, thread: Option<std::thread::JoinHandle<()>> },
}

/// Plays what an instance sends.
pub struct Player {
    jitter: Arc<Mutex<Jitter>>,
    output: Output,
}

impl Drop for Player {
    // Without the `device` feature a file is the only output.
    #[cfg_attr(not(feature = "device"), allow(irrefutable_let_patterns))]
    fn drop(&mut self) {
        if let Output::File { stop, thread } = &mut self.output {
            stop.store(true, Ordering::Relaxed);
            if let Some(thread) = thread.take() {
                let _ = thread.join();
            }
        }
    }
}

impl Player {
    /// Play through this machine's default sound device.
    #[cfg(feature = "device")]
    pub fn device() -> Result<Self> {
        use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
        let host = cpal::default_host();
        let device = host.default_output_device().context("no sound device to play on here")?;
        let config: cpal::StreamConfig = device.default_output_config()?.into();
        let channels = config.channels as usize;
        let jitter = Arc::new(Mutex::new(Jitter::new(config.sample_rate)));
        let playing = jitter.clone();
        let stream = device.build_output_stream(
            config,
            move |data: &mut [f32], _: &cpal::OutputCallbackInfo| match playing.try_lock() {
                Ok(mut jitter) => jitter.pull(data, channels),
                Err(_) => data.fill(0.0),
            },
            |_err: cpal::Error| {},
            None,
        )?;
        stream.play()?;
        Ok(Self { jitter, output: Output::Device(stream) })
    }

    /// A build without the `device` feature has no sound device to play on.
    #[cfg(not(feature = "device"))]
    pub fn device() -> Result<Self> {
        anyhow::bail!("this build of paw has no sound device")
    }

    /// Write what would be played, at `rate`, to a WAV file: the null
    /// device, which tests listen through.
    pub fn file(path: &Path, rate: u32) -> Result<Self> {
        let mut wav = Wav::create(path, rate).with_context(|| format!("writing {}", path.display()))?;
        let jitter = Arc::new(Mutex::new(Jitter::new(rate)));
        let stop = Arc::new(AtomicBool::new(false));
        let (playing, stopping) = (jitter.clone(), stop.clone());
        let thread = std::thread::spawn(move || {
            let started = Instant::now();
            let mut played = 0u64;
            let mut block = Vec::new();
            while !stopping.load(Ordering::Relaxed) {
                std::thread::sleep(Duration::from_millis(10));
                let due = (started.elapsed().as_secs_f64() * rate as f64) as u64;
                block.resize((due - played) as usize * 2, 0.0);
                playing.lock().expect("a thread panicked while it held the lock").pull(&mut block, 2);
                played = due;
                if wav.append(&block).is_err() {
                    return;
                }
            }
        });
        Ok(Self { jitter, output: Output::File { stop, thread: Some(thread) } })
    }

    /// Take an `audio.frame` event's payload.
    pub fn push(&self, payload: &Value) -> Result<()> {
        self.jitter.lock().expect("a thread panicked while it held the lock").push(payload)
    }

    /// How often the sound has run dry so far.
    pub fn underruns(&self) -> u64 {
        self.jitter.lock().expect("a thread panicked while it held the lock").underruns
    }
}

/// A 16-bit stereo WAV file written as it goes, its header kept right
/// after every piece (`hound`'s `flush`) so that it can be read at any time.
struct Wav(hound::WavWriter<std::io::BufWriter<std::fs::File>>);

impl Wav {
    fn create(path: &Path, rate: u32) -> hound::Result<Self> {
        let spec = hound::WavSpec {
            channels: 2,
            sample_rate: rate,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        hound::WavWriter::create(path, spec).map(Self)
    }

    fn append(&mut self, samples: &[f32]) -> hound::Result<()> {
        let mut writer = self.0.get_i16_writer(samples.len() as u32);
        for sample in samples {
            writer.write_sample((sample.clamp(-1.0, 1.0) * 32767.0).round() as i16);
        }
        writer.flush()?;
        self.0.flush()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use paw_proto::monitor::Encoder;

    /// `seconds` of a sine at `hz`, as frames from an engine at 48 kHz.
    fn frames(seconds: f64, hz: f32) -> Vec<Value> {
        let mut encoder = Encoder::new(48000.0);
        let input: Vec<f32> = (0..(48000.0 * seconds) as usize)
            .flat_map(|i| {
                let v = (i as f32 * hz * std::f32::consts::TAU / 48000.0).sin() * 0.5;
                [v, v]
            })
            .collect();
        encoder.push(&input)
    }

    #[test]
    fn nothing_is_heard_until_a_fifth_of_a_second_waits() {
        let mut jitter = Jitter::new(48000);
        let frames = frames(1.0, 440.0);
        let mut out = vec![1.0; 480 * 2];
        for frame in &frames[..9] {
            jitter.push(frame).unwrap();
        }
        jitter.pull(&mut out, 2);
        assert!(out.iter().all(|s| *s == 0.0), "180 ms is not enough");
        jitter.push(&frames[9]).unwrap();
        jitter.pull(&mut out, 2);
        assert!(out.iter().any(|s| s.abs() > 0.1), "200 ms is");
    }

    #[test]
    fn played_at_the_device_rate_it_keeps_its_pitch_and_level() {
        let mut jitter = Jitter::new(44100);
        for frame in frames(0.5, 441.0) {
            jitter.push(&frame).unwrap();
        }
        let mut out = vec![0.0; 4410 * 2];
        jitter.pull(&mut out, 2);
        // Rising zero crossings on the left: 441 Hz is one each 100 frames.
        let left: Vec<f32> = out.iter().step_by(2).copied().collect();
        let rising = left.windows(2).filter(|w| w[0] < 0.0 && w[1] >= 0.0).count();
        assert!((43..=45).contains(&rising), "{rising} crossings in a tenth of a second");
        let peak = left.iter().fold(0f32, |m, v| m.max(v.abs()));
        assert!((peak - 0.5).abs() < 0.02, "{peak}");
        assert_eq!(jitter.underruns, 0);
    }

    #[test]
    fn running_dry_plays_silence_and_too_much_waiting_is_cut_back() {
        let mut jitter = Jitter::new(24000);
        let all = frames(2.0, 440.0);
        for frame in &all[..10] {
            jitter.push(frame).unwrap();
        }
        let mut out = vec![0.0; 24000 * 2 / 2];
        jitter.pull(&mut out, 2);
        assert_eq!(jitter.underruns, 1, "a fifth of a second does not last half a second");
        assert!(out[out.len() - 100..].iter().all(|s| *s == 0.0));
        for frame in &all[10..] {
            jitter.push(frame).unwrap();
        }
        assert!(jitter.waiting() <= MOST, "{} s waiting", jitter.waiting());
    }

    #[test]
    fn the_file_holds_what_would_have_been_played() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("heard.wav");
        let player = Player::file(&path, 48000).unwrap();
        for frame in frames(0.5, 440.0) {
            player.push(&frame).unwrap();
        }
        std::thread::sleep(Duration::from_millis(600));
        drop(player);
        let data = std::fs::read(&path).unwrap();
        assert_eq!(&data[..4], b"RIFF");
        let bytes = u32::from_le_bytes(data[40..44].try_into().unwrap()) as usize;
        assert_eq!(bytes, data.len() - 44);
        assert!(bytes >= 48000 * 4 / 2, "at least half a second written");
        let loud = data[44..].chunks_exact(2).filter(|b| i16::from_le_bytes([b[0], b[1]]).abs() > 10000).count();
        assert!(loud > 1000, "the tone is in it");
    }
}
