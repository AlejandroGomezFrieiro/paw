//! Converting a sound file to the engine's sample rate, band-limited.
//!
//! A file at another rate than the engine's is converted once, when it is
//! loaded for playing, with a windowed-sinc resampler (`rubato`): frequencies
//! the new rate cannot hold are filtered out instead of folding back as
//! aliases, and no images of the old rate are left above the audio band. The
//! engine then plays the converted samples one for one.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![cfg_attr(test, expect(clippy::cast_possible_wrap, reason = "debt: pay down"))]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use paw_engine::{AudioData, Sink};
use rubato::audioadapter_buffers::direct::{SequentialSliceOfSlices, SequentialSliceOfVecs};
use rubato::{
    Async, FixedAsync, Indexing, Resampler, SincInterpolationParameters, SincInterpolationType,
    WindowFunction,
};

/// Frames handed to the resampler at a time.
const CHUNK: usize = 4096;

/// `data` at `rate`. The same length in seconds, give or take a frame.
#[cfg(test)]
pub(crate) fn convert(data: &AudioData, rate: u32) -> anyhow::Result<AudioData> {
    convert_into(data, rate, Sink::memory())
}

/// `data` at `rate`, kept where `sink` keeps it: on the disk when it is
/// large. The same length in seconds, give or take a frame.
pub(crate) fn convert_into(data: &AudioData, rate: u32, sink: Sink) -> anyhow::Result<AudioData> {
    if data.sample_rate == rate {
        return Ok(AudioData {
            sample_rate: rate,
            channels: data.channels.clone(),
        });
    }
    let ratio = rate as f64 / data.sample_rate as f64;
    let frames = data.frames();
    let wanted = (frames as f64 * ratio).round() as usize;
    let mut stream = Stream::new(ratio, rate, wanted, sink)?;
    let mut at = 0;
    while at < frames {
        let to = (at + CHUNK).min(frames);
        stream.push(&data.channels[0][at..to], &data.channels[1][at..to])?;
        at = to;
    }
    stream.finish()
}

/// Sound resampled as it comes: `ratio` frames out for each frame in,
/// `wanted` frames in all, kept where the sink keeps them. A pitch shift
/// plays a stretched sound back this way, faster or slower.
pub(crate) struct Stream {
    resampler: Async<f32>,
    buffer: Vec<Vec<f32>>,
    /// Frames of start-up delay still to drop from the output, so that the
    /// first frame out lines up with the first frame in.
    skip: usize,
    /// Frames taken that are not yet a whole chunk.
    pending: [Vec<f32>; 2],
    wanted: usize,
    rate: u32,
    sink: Sink,
}

impl Stream {
    /// `rate` is the rate the result is said to have.
    pub(crate) fn new(ratio: f64, rate: u32, wanted: usize, mut sink: Sink) -> anyhow::Result<Self> {
        let params = SincInterpolationParameters {
            sinc_len: 256,
            // The passband reaches 95% of the lower rate's Nyquist frequency:
            // 20.9 kHz going to 44.1 kHz.
            f_cutoff: Some(0.95),
            interpolation: SincInterpolationType::Cubic,
            oversampling_factor: 256,
            window: WindowFunction::BlackmanHarris2,
        };
        let resampler = Async::<f32>::new_sinc(ratio, 1.0, &params, CHUNK, 2, FixedAsync::Input)
            .map_err(|e| anyhow::anyhow!("converting the sample rate: {e}"))?;
        sink.reserve(wanted);
        let buffer = vec![vec![0.0; resampler.output_frames_max()]; 2];
        Ok(Self {
            skip: resampler.output_delay(),
            resampler,
            buffer,
            pending: [Vec::with_capacity(CHUNK), Vec::with_capacity(CHUNK)],
            wanted,
            rate,
            sink,
        })
    }

    /// No more than `wanted` frames go out, however many the filter makes.
    fn put(&mut self, made: usize) -> anyhow::Result<()> {
        let from = self.skip.min(made);
        self.skip -= from;
        let take = made.min(from + self.wanted - self.sink.frames());
        self.sink.push(
            &self.buffer[0][from..take],
            Some(&self.buffer[1][from..take]),
        )
    }

    /// One call of the resampler on the pending frames, of which the first
    /// `len` are real and the rest silence. Returns the frames made.
    fn run(&mut self, len: usize) -> anyhow::Result<usize> {
        let fail = |e: &dyn std::fmt::Display| anyhow::anyhow!("converting the sample rate: {e}");
        for p in &mut self.pending {
            p.resize(CHUNK, 0.0);
        }
        let slices = [&self.pending[0][..], &self.pending[1][..]];
        let input = SequentialSliceOfSlices::new(&slices, 2, CHUNK).map_err(|e| fail(&e))?;
        let frames = self.buffer[0].len();
        let mut output =
            SequentialSliceOfVecs::new_mut(&mut self.buffer, 2, frames).map_err(|e| fail(&e))?;
        let indexing = Indexing {
            input_offset: 0,
            output_offset: 0,
            partial_len: (len < CHUNK).then_some(len),
            active_channels_mask: None,
        };
        let (_, made) = self
            .resampler
            .process_into_buffer(&input, &mut output, Some(&indexing))
            .map_err(|e| fail(&e))?;
        self.pending[0].clear();
        self.pending[1].clear();
        Ok(made)
    }

    pub(crate) fn push(&mut self, mut left: &[f32], mut right: &[f32]) -> anyhow::Result<()> {
        while !left.is_empty() {
            let room = CHUNK - self.pending[0].len();
            let n = room.min(left.len());
            self.pending[0].extend_from_slice(&left[..n]);
            self.pending[1].extend_from_slice(&right[..n]);
            (left, right) = (&left[n..], &right[n..]);
            if self.pending[0].len() == CHUNK {
                let made = self.run(CHUNK)?;
                self.put(made)?;
            }
        }
        Ok(())
    }

    /// The rest, then silence until what is still in the filter has come out.
    pub(crate) fn finish(mut self) -> anyhow::Result<AudioData> {
        let rest = self.pending[0].len();
        let made = self.run(rest)?;
        self.put(made)?;
        // The delay is dropped in `put`; the resampler lines its output up with its input itself: what comes
        // out first is the first frame (the tests check a click's place).
        while self.sink.frames() < self.wanted {
            let made = self.run(0)?;
            if made == 0 {
                break;
            }
            self.put(made)?;
        }
        if self.sink.frames() < self.wanted {
            let silence = vec![0.0; self.wanted - self.sink.frames()];
            self.sink.push(&silence, Some(&silence))?;
        }
        self.sink.finish(self.rate)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::f64::consts::TAU;

    fn tone(rate: u32, seconds: f64, freq: impl Fn(f64) -> f64) -> AudioData {
        let n = (rate as f64 * seconds) as usize;
        let mut phase = 0.0f64;
        let mut s = Vec::with_capacity(n);
        for i in 0..n {
            let t = i as f64 / rate as f64;
            s.push((phase.sin() * 0.5) as f32);
            phase += TAU * freq(t) / rate as f64;
        }
        AudioData {
            sample_rate: rate,
            channels: [s.clone().into(), s.into()],
        }
    }

    /// Level in dB relative to an amplitude of 0.5, of the middle of a signal
    /// (away from the edges, where the filter starts and stops).
    fn rms_db(s: &[f32]) -> f64 {
        let mid = &s[s.len() / 10..s.len() * 9 / 10];
        let power: f64 = mid.iter().map(|x| (*x as f64).powi(2)).sum::<f64>() / mid.len() as f64;
        10.0 * (power / 0.125).log10()
    }

    /// Level of one frequency in a signal, by Goertzel, in dB relative to an
    /// amplitude of 0.5.
    fn level_at(s: &[f32], rate: u32, freq: f64) -> f64 {
        let mid = &s[s.len() / 10..s.len() * 9 / 10];
        let w = TAU * freq / rate as f64;
        let (mut a, mut b) = (0.0f64, 0.0f64);
        for (i, x) in mid.iter().enumerate() {
            // A Hann window keeps the measurement to the frequency asked for.
            let win = 0.5 - 0.5 * (TAU * i as f64 / mid.len() as f64).cos();
            let y = *x as f64 * win + 2.0 * w.cos() * a - b;
            b = a;
            a = y;
        }
        let power = a * a + b * b - 2.0 * w.cos() * a * b;
        let amplitude = 2.0 * power.sqrt() / (mid.len() as f64 * 0.5);
        20.0 * (amplitude / 0.5).max(1e-12).log10()
    }

    #[test]
    fn a_sweep_above_the_new_nyquist_frequency_leaves_no_aliases() {
        // 96 kHz to 48 kHz: a sweep from 25 to 46 kHz has nothing the new
        // rate can hold. Linear interpolation folds it back into the audio
        // band at about -10 dB; here what is left is below -70 dB.
        let sweep = tone(96_000, 2.0, |t| 25_000.0 + 21_000.0 * t / 2.0);
        let out = convert(&sweep, 48_000).unwrap();
        assert_eq!(out.frames(), 96_000);
        let level = rms_db(&out.channels[0]);
        assert!(level < -70.0, "aliases at {level:.1} dB");
    }

    #[test]
    fn a_tone_near_the_top_leaves_no_image_when_raising_the_rate() {
        // 44.1 kHz to 48 kHz: a 20 kHz tone has an image at 24.1 kHz, which
        // at 48 kHz folds to 23.9 kHz. It must be below -70 dB, and the tone
        // itself within 0.1 dB.
        let src = tone(44_100, 2.0, |_| 20_000.0);
        let out = convert(&src, 48_000).unwrap();
        assert_eq!(out.frames(), 96_000);
        let image = level_at(&out.channels[0], 48_000, 23_900.0);
        assert!(image < -70.0, "image at {image:.1} dB");
        let kept = level_at(&out.channels[0], 48_000, 20_000.0);
        assert!(kept.abs() < 0.1, "tone at {kept:.2} dB");
    }

    #[test]
    fn a_sweep_in_the_audio_band_keeps_its_level_and_place() {
        let sweep = tone(44_100, 2.0, |t| 100.0 + 9_900.0 * t / 2.0);
        let out = convert(&sweep, 48_000).unwrap();
        let level = rms_db(&out.channels[0]);
        assert!(level.abs() < 0.05, "level {level:.3} dB");
        // A click at a known place stays at that place in time.
        let mut click = AudioData {
            sample_rate: 44_100,
            channels: [vec![0.0; 44_100].into(), vec![0.0; 44_100].into()],
        };
        click.channels[0][22_050] = 1.0;
        let out = convert(&click, 48_000).unwrap();
        let peak = out.channels[0]
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.abs().total_cmp(&b.1.abs()))
            .unwrap()
            .0;
        assert!((peak as i64 - 24_000).abs() <= 1, "the click is at {peak}");
        let mut click = AudioData {
            sample_rate: 96_000,
            channels: [vec![0.0; 96_000].into(), vec![0.0; 96_000].into()],
        };
        click.channels[0][48_000] = 1.0;
        let out = convert(&click, 48_000).unwrap();
        let peak = out.channels[0]
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.abs().total_cmp(&b.1.abs()))
            .unwrap()
            .0;
        assert!(
            (peak as i64 - 24_000).abs() <= 1,
            "going down, the click is at {peak}"
        );
    }
}
