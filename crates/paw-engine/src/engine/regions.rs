//! Playing a track's audio regions into its block.

use std::ops::Range;

use crate::clip::{AudioRegion, ClipSet};
use crate::device::ProcessCtx;
use crate::tempo::TempoMap;

pub(super) const DECLICK_SECONDS: f64 = 0.003;

/// Gain a fraction `x` of the way into a fade: a quarter sine, so that two
/// clips fading across each other keep their power.
pub(super) fn fade_curve(x: f64) -> f32 {
    (x.clamp(0.0, 1.0) * std::f64::consts::FRAC_PI_2).sin() as f32
}

/// Add every audio region overlapping beats `start..end` into the block.
/// Regions keep to time: a region plays its file at its own rate from the
/// moment its start beat falls on, whatever the tempo does meanwhile.
pub(super) fn mix_audio(
    clips: &ClipSet,
    left: &mut [f32],
    right: &mut [f32],
    (start, end): (f64, f64),
    map: &TempoMap,
    bpf: Option<f64>,
    ctx: &ProcessCtx,
) {
    if bpf.is_some() {
        return mix_audio_constant(clips, left, right, (start, end), ctx);
    }
    let n = left.len();
    let sr = ctx.sample_rate as f64;
    let t0 = ctx.seconds;
    for region in clips.regions(start, end) {
        if region.end <= start || region.start >= end {
            continue;
        }
        // The region's edges, in frames from the block's first frame.
        let (rs, re) = (map.seconds(region.start), map.seconds(region.end));
        let first = if rs > t0 {
            ((rs - t0) * sr).ceil() as usize
        } else {
            0
        };
        let last = (((re - t0) * sr).ceil() as usize).min(n);
        let src_rate = region.data.sample_rate as f64;
        // Fades, in frames. An edge cut into the middle of a recording gets
        // a few milliseconds of one even when none was asked for, or it clicks.
        let declick = DECLICK_SECONDS * sr;
        let span = Span {
            frames: first..last,
            origin: (t0 - rs + region.offset) * src_rate,
            step: src_rate / sr,
            fade_in: ((map.seconds(region.start + region.fade_in) - rs) * sr)
                .max(if region.declick_in { declick } else { 0.0 }),
            fade_out: ((re - map.seconds(region.end - region.fade_out)) * sr)
                .max(if region.declick_out { declick } else { 0.0 }),
            length: (re - rs) * sr,
            at: (t0 - rs) * sr,
        };
        span.play(region, left, right);
    }
}

/// [`mix_audio`] for one tempo throughout, in beats per frame: the
/// arithmetic of before there were tempo maps, so that such songs render
/// the very same samples.
pub(crate) fn mix_audio_constant(
    clips: &ClipSet,
    left: &mut [f32],
    right: &mut [f32],
    (start, end): (f64, f64),
    ctx: &ProcessCtx,
) {
    let n = left.len();
    let sr = ctx.sample_rate as f64;
    let beats_per_frame = ctx.tempo / (60.0 * sr);
    for region in clips.regions(start, end) {
        if region.end <= start || region.start >= end {
            continue;
        }
        let first = if region.start > start {
            ((region.start - start) / beats_per_frame).ceil() as usize
        } else {
            0
        };
        let last = (((region.end - start) / beats_per_frame).ceil() as usize).min(n);
        let src_rate = region.data.sample_rate as f64;
        let declick = DECLICK_SECONDS * sr;
        let span = Span {
            frames: first..last,
            origin: ((start - region.start) * 60.0 / ctx.tempo + region.offset) * src_rate,
            step: src_rate / sr,
            fade_in: (region.fade_in / beats_per_frame)
                .max(if region.declick_in { declick } else { 0.0 }),
            fade_out: (region.fade_out / beats_per_frame)
                .max(if region.declick_out { declick } else { 0.0 }),
            length: (region.end - region.start) / beats_per_frame,
            at: (start - region.start) / beats_per_frame,
        };
        span.play(region, left, right);
    }
}

/// Where one region sounds in a block, worked out for the tempo by the
/// caller: all that playing it frame by frame needs.
struct Span {
    /// The block's frames it sounds on.
    frames: Range<usize>,
    /// Source position, in source frames, of the block's first frame, as
    /// if it played forward, and how far the source moves each frame.
    origin: f64,
    step: f64,
    /// Fades, and the region's length, in frames.
    fade_in: f64,
    fade_out: f64,
    length: f64,
    /// Where in the region, in frames, the block's first frame is.
    at: f64,
}

impl Span {
    fn play(&self, region: &AudioRegion, left: &mut [f32], right: &mut [f32]) {
        let complete = region.data.complete();
        if !region.direction.is_backward() {
            self.play_forward(region, complete, left, right);
        } else if complete {
            // Only sound that is all there plays backwards (see
            // `AudioRegion::reversed`): one still being made would be
            // read from where it is not yet.
            self.play_backward(region, left, right);
        }
    }

    /// `gain` through the region's fades, `from_start` frames into it.
    fn fades(&self, mut gain: f32, from_start: f64) -> f32 {
        if from_start < self.fade_in {
            gain *= fade_curve(from_start / self.fade_in);
        }
        if self.length - from_start < self.fade_out {
            gain *= fade_curve((self.length - from_start) / self.fade_out);
        }
        gain
    }

    fn play_forward(&self, region: &AudioRegion, complete: bool, left: &mut [f32], right: &mut [f32]) {
        // Sound still being made is played as far as it is there.
        let frames = region.data.frames();
        let watched = region.hold.watched(complete);
        let hold_fade = DECLICK_SECONDS * region.data.sample_rate as f64;
        let [src_l, src_r] = &region.data.channels;
        for i in self.frames.clone() {
            let pos = self.origin + i as f64 * self.step;
            if pos < 0.0 {
                continue;
            }
            let index = pos as usize;
            if index + 1 >= frames {
                if !complete {
                    region.hold.starve();
                }
                break;
            }
            let frac = (pos - index as f64) as f32;
            let mut gain = region.gain;
            if watched {
                gain *= region
                    .hold
                    .gain(pos, frames, complete, hold_fade, fade_curve);
            }
            gain = self.fades(gain, self.at + i as f64);
            left[i] += (src_l[index] + (src_l[index + 1] - src_l[index]) * frac) * gain;
            right[i] += (src_r[index] + (src_r[index + 1] - src_r[index]) * frac) * gain;
        }
    }

    /// The region's source window read from its end: the frame `k` frames
    /// into the region plays what the forward region plays `k` frames
    /// before its end. Fades keep to the region's time, not the source's.
    fn play_backward(&self, region: &AudioRegion, left: &mut [f32], right: &mut [f32]) {
        let frames = region.data.frames();
        let [src_l, src_r] = &region.data.channels;
        // The source position the forward region plays on its first frame.
        let begins = self.origin - self.at * self.step;
        let last = frames as f64 - 1.0;
        for i in self.frames.clone() {
            let from_start = self.at + i as f64;
            let pos = begins + (self.length - 1.0 - from_start) * self.step;
            // Past the source's end: silent, as the forward region is there.
            if pos >= last {
                continue;
            }
            let pos = pos.max(0.0);
            let index = pos as usize;
            let frac = (pos - index as f64) as f32;
            let gain = self.fades(region.gain, from_start);
            left[i] += (src_l[index] + (src_l[index + 1] - src_l[index]) * frac) * gain;
            right[i] += (src_r[index] + (src_r[index + 1] - src_r[index]) * frac) * gain;
        }
    }
}
