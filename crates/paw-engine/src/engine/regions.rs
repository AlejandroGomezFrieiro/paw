//! Playing a track's audio regions into its block.

use crate::clip::ClipSet;
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
    for region in clips.regions() {
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
        // Source position, in source frames, of the block's first frame.
        let origin = (t0 - rs + region.offset) * src_rate;
        let step = src_rate / sr;
        // Sound still being made is played as far as it is there.
        let complete = region.data.complete();
        let frames = region.data.frames();
        let watched = region.hold.watched(complete);
        let hold_fade = DECLICK_SECONDS * src_rate;
        let [src_l, src_r] = &region.data.channels;
        // Fades, in frames. An edge cut into the middle of a recording gets
        // a few milliseconds of one even when none was asked for, or it clicks.
        let declick = DECLICK_SECONDS * sr;
        let fade_in = ((map.seconds(region.start + region.fade_in) - rs) * sr)
            .max(if region.declick_in { declick } else { 0.0 });
        let fade_out = ((re - map.seconds(region.end - region.fade_out)) * sr)
            .max(if region.declick_out { declick } else { 0.0 });
        let length = (re - rs) * sr;
        // Where in the region, in frames, the block's first frame is.
        let at = (t0 - rs) * sr;
        for i in first..last {
            let pos = origin + i as f64 * step;
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
            let from_start = at + i as f64;
            if from_start < fade_in {
                gain *= fade_curve(from_start / fade_in);
            }
            if length - from_start < fade_out {
                gain *= fade_curve((length - from_start) / fade_out);
            }
            left[i] += (src_l[index] + (src_l[index + 1] - src_l[index]) * frac) * gain;
            right[i] += (src_r[index] + (src_r[index + 1] - src_r[index]) * frac) * gain;
        }
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
    for region in clips.regions() {
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
        // Source position, in source frames, of the block's first frame.
        let origin = ((start - region.start) * 60.0 / ctx.tempo + region.offset) * src_rate;
        let step = src_rate / sr;
        // Sound still being made is played as far as it is there.
        let complete = region.data.complete();
        let frames = region.data.frames();
        let watched = region.hold.watched(complete);
        let hold_fade = DECLICK_SECONDS * src_rate;
        let [src_l, src_r] = &region.data.channels;
        let declick = DECLICK_SECONDS * sr;
        let fade_in =
            (region.fade_in / beats_per_frame).max(if region.declick_in { declick } else { 0.0 });
        let fade_out =
            (region.fade_out / beats_per_frame).max(if region.declick_out { declick } else { 0.0 });
        let length = (region.end - region.start) / beats_per_frame;
        let at = (start - region.start) / beats_per_frame;
        for i in first..last {
            let pos = origin + i as f64 * step;
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
            let from_start = at + i as f64;
            if from_start < fade_in {
                gain *= fade_curve(from_start / fade_in);
            }
            if length - from_start < fade_out {
                gain *= fade_curve((length - from_start) / fade_out);
            }
            left[i] += (src_l[index] + (src_l[index + 1] - src_l[index]) * frac) * gain;
            right[i] += (src_r[index] + (src_r[index + 1] - src_r[index]) * frac) * gain;
        }
    }
}
