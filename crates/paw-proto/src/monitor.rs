//! Hearing an instance somewhere else: what its engine plays, sent to a
//! connection that asked (`monitor.listen`) as `audio.frame` events,
//!
//!   { "seq": 41, "rate": 24000, "channels": 2, "pcm": "base64…" }
//!
//! each 20 ms of sound, left and right interleaved, as 16-bit little-endian
//! samples at half the engine's rate (a quarter at 88.2 kHz and above).
//! That is about 1 Mbit/s with the base64 the JSON lines need: fine on a
//! home network, too much for a slow link. It is for monitoring a mix, not
//! for judging it.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use anyhow::{Context, Result};
use base64::Engine;
use serde_json::{Value, json};

/// The rate frames are sent at is the engine's divided down to near this.
pub const TARGET_RATE: f64 = 24000.0;
/// How much sound one frame holds.
pub const FRAME_MS: f64 = 20.0;

/// Turns what the engine plays into frames to send.
pub struct Encoder {
    /// Engine frames averaged into each frame sent.
    step: usize,
    pub rate: u32,
    frame_len: usize,
    /// Sums of the engine frames taken towards the next sample, and how many.
    sum: [f32; 2],
    taken: usize,
    samples: Vec<i16>,
    seq: u64,
}

impl Encoder {
    pub fn new(engine_rate: f64) -> Self {
        let step = (engine_rate / TARGET_RATE).round().max(1.0) as usize;
        let rate = (engine_rate / step as f64).round() as u32;
        Self {
            step,
            rate,
            frame_len: ((rate as f64 * FRAME_MS / 1000.0) as usize).max(1),
            sum: [0.0; 2],
            taken: 0,
            samples: Vec::new(),
            seq: 0,
        }
    }

    /// Take interleaved stereo samples from the engine; returns the frames
    /// they finished, as `audio.frame` payloads.
    pub fn push(&mut self, interleaved: &[f32]) -> Vec<Value> {
        let mut out = Vec::new();
        for pair in interleaved.chunks_exact(2) {
            self.sum[0] += pair[0];
            self.sum[1] += pair[1];
            self.taken += 1;
            if self.taken < self.step {
                continue;
            }
            // The average of each run of engine frames: a plain low-pass
            // that keeps most of what would fold back down out of the way.
            for side in self.sum {
                let value = (side / self.step as f32).clamp(-1.0, 1.0);
                self.samples.push((value * 32767.0).round() as i16);
            }
            self.sum = [0.0; 2];
            self.taken = 0;
            if self.samples.len() >= self.frame_len * 2 {
                out.push(self.frame());
            }
        }
        out
    }

    fn frame(&mut self) -> Value {
        let bytes: Vec<u8> = self.samples.drain(..).flat_map(i16::to_le_bytes).collect();
        self.seq += 1;
        json!({
            "seq": self.seq,
            "rate": self.rate,
            "channels": 2,
            "pcm": base64::engine::general_purpose::STANDARD.encode(bytes),
        })
    }
}

/// One frame as it arrived: its number, rate, and samples, left and right
/// interleaved, from -1 to 1.
#[derive(Clone, Debug, PartialEq)]
pub struct Frame {
    pub seq: u64,
    pub rate: u32,
    pub samples: Vec<f32>,
}

/// Read an `audio.frame` payload.
pub fn decode(payload: &Value) -> Result<Frame> {
    let seq = payload["seq"].as_u64().context("a frame without its number")?;
    let rate = payload["rate"].as_u64().context("a frame without its rate")? as u32;
    let channels = payload["channels"].as_u64().unwrap_or(2);
    if channels != 2 {
        anyhow::bail!("frames of {channels} channels are not understood here");
    }
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(payload["pcm"].as_str().context("a frame without sound")?)?;
    let samples = bytes
        .chunks_exact(2)
        .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32 / 32767.0)
        .collect();
    Ok(Frame { seq, rate, samples })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn frames_carry_twenty_milliseconds_at_half_the_rate_and_come_back_the_same() {
        let mut encoder = Encoder::new(48000.0);
        assert_eq!(encoder.rate, 24000);
        // A second of a 440 Hz sine on the left, its inverse on the right.
        let input: Vec<f32> = (0..48000)
            .flat_map(|i| {
                let v = (i as f32 * 440.0 * std::f32::consts::TAU / 48000.0).sin() * 0.5;
                [v, -v]
            })
            .collect();
        let mut frames = Vec::new();
        // In pieces of uneven length, as the engine's blocks come.
        for piece in input.chunks(2 * 333) {
            frames.extend(encoder.push(piece));
        }
        assert_eq!(frames.len(), 50, "fifty frames of 20 ms");
        let decoded: Vec<Frame> = frames.iter().map(|f| decode(f).unwrap()).collect();
        assert!(decoded.iter().enumerate().all(|(i, f)| f.seq == i as u64 + 1 && f.rate == 24000));
        assert!(decoded.iter().all(|f| f.samples.len() == 480 * 2));
        let samples: Vec<f32> = decoded.iter().flat_map(|f| f.samples.clone()).collect();
        let peak = samples.iter().step_by(2).fold(0f32, |m, v| m.max(v.abs()));
        assert!((peak - 0.5).abs() < 0.01, "the level is kept: {peak}");
        assert!(samples.chunks_exact(2).all(|p| (p[0] + p[1]).abs() < 1e-3), "left and right in place");
        // The bytes of one frame: 960 samples of two bytes, in base64.
        assert_eq!(frames[0]["pcm"].as_str().unwrap().len(), 1920 / 3 * 4);
        assert!(decode(&json!({ "seq": 1, "rate": 24000, "channels": 1, "pcm": "" })).is_err());
    }

    #[test]
    fn higher_rates_are_divided_further() {
        assert_eq!(Encoder::new(44100.0).rate, 22050);
        assert_eq!(Encoder::new(96000.0).rate, 24000);
        assert_eq!(Encoder::new(88200.0).rate, 22050);
        assert_eq!(Encoder::new(16000.0).rate, 16000);
    }
}
