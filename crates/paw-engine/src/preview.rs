//! A sound file heard on its own, outside the project: what a picker plays
//! while a file is under its selection. It plays whether or not the
//! transport runs, is added to the output after the master at a level of
//! its own, and is never recorded, rendered or saved.
#![expect(clippy::cast_lossless, reason = "debt: pay down")]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use std::sync::Arc;

use crate::clip::AudioData;

/// Frames over which a voice fades in when it starts and out when it is
/// replaced or stopped, so that neither clicks.
pub const FADE: usize = 256;

/// One file being played, from its start.
pub struct Preview {
    data: Arc<AudioData>,
    /// Frames of the file per frame of output: the two rates' ratio.
    step: f64,
    /// Where in the file, in its own frames.
    pos: f64,
    gain: f32,
    /// How far the voice has faded in, from 0 to [`FADE`].
    env: usize,
    /// Whoever started it names it, to tell it from the one before.
    pub id: u32,
}

impl Preview {
    /// Play `data` on an engine running at `sample_rate`, at `gain`.
    pub fn new(data: Arc<AudioData>, sample_rate: f64, gain: f32, id: u32) -> Self {
        Self {
            step: data.sample_rate as f64 / sample_rate.max(1.0),
            data,
            pos: 0.0,
            gain,
            env: 0,
            id,
        }
    }

    pub fn set_gain(&mut self, gain: f32) {
        self.gain = gain;
    }

    /// Where it has got to, in seconds of the file.
    pub fn seconds(&self) -> f64 {
        self.pos / self.data.sample_rate.max(1) as f64
    }

    /// Whether the whole file has been played.
    pub fn ended(&self) -> bool {
        let frames = self.data.channels[0].len();
        self.data.complete() && self.pos + 1.0 >= frames as f64
    }

    /// Add the next `left.len()` frames into the output. A voice `leaving`
    /// fades out over [`FADE`] frames instead of in. False once there is
    /// nothing more to hear from it.
    pub fn mix(&mut self, left: &mut [f32], right: &mut [f32], leaving: bool) -> bool {
        let (l, r) = (&*self.data.channels[0], &*self.data.channels[1]);
        let len = l.len().min(r.len());
        for (out_l, out_r) in left.iter_mut().zip(right.iter_mut()) {
            if leaving {
                if self.env == 0 {
                    return false;
                }
                self.env -= 1;
            } else if self.env < FADE {
                self.env += 1;
            }
            let at = self.pos as usize;
            if at + 1 >= len {
                // What is not decoded yet is waited for; the end is the end.
                return !self.data.complete() && !leaving;
            }
            let frac = (self.pos - at as f64) as f32;
            let g = self.gain * self.env as f32 / FADE as f32;
            *out_l += (l[at] + (l[at + 1] - l[at]) * frac) * g;
            *out_r += (r[at] + (r[at + 1] - r[at]) * frac) * g;
            self.pos += self.step;
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn voice(frames: usize, rate: u32, engine_rate: f64) -> Preview {
        let ones = vec![1.0f32; frames];
        let data = AudioData {
            sample_rate: rate,
            channels: [ones.clone().into(), ones.into()],
        };
        Preview::new(Arc::new(data), engine_rate, 0.5, 7)
    }

    #[test]
    fn a_voice_fades_in_plays_at_its_level_and_ends() {
        let mut v = voice(4000, 48000, 48000.0);
        let (mut l, mut r) = (vec![0.0; 1024], vec![0.0; 1024]);
        assert!(v.mix(&mut l, &mut r, false));
        assert!(l[0] > 0.0 && l[0] < 0.01, "it starts quietly: {}", l[0]);
        assert!((l[1000] - 0.5).abs() < 1e-6, "then at its level: {}", l[1000]);
        let (mut l, mut r) = (vec![0.0; 4096], vec![0.0; 4096]);
        assert!(!v.mix(&mut l, &mut r, false), "the file is over");
        assert!(v.ended());
    }

    #[test]
    fn a_voice_at_another_rate_moves_through_the_file_at_its_rate() {
        let mut v = voice(48000, 24000, 48000.0);
        let (mut l, mut r) = (vec![0.0; 4800], vec![0.0; 4800]);
        v.mix(&mut l, &mut r, false);
        assert!((v.seconds() - 0.1).abs() < 1e-9, "{}", v.seconds());
    }

    #[test]
    fn a_voice_leaving_fades_out_and_is_done() {
        let mut v = voice(48000, 48000, 48000.0);
        let (mut l, mut r) = (vec![0.0; 1024], vec![0.0; 1024]);
        v.mix(&mut l, &mut r, false);
        let (mut l, mut r) = (vec![0.0; 1024], vec![0.0; 1024]);
        assert!(!v.mix(&mut l, &mut r, true));
        assert!(l[0] > 0.49 && l[FADE - 1] < 0.01 && l[FADE + 10] == 0.0);
    }
}
