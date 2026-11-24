//! The play position, counted in frames.
//!
//! The position is a count of frames from an anchor beat, not a beat that
//! grows by the beats of each block. A beat per frame is not exact in
//! `f64`, so a sum of blocks gathers a rounding error that depends on the
//! size of the blocks, and a note on the edge of a frame then falls one
//! frame early or late. From an anchor, the beat of each frame and the
//! frame of each beat come from one function of the frame count, and do
//! not depend on where the blocks fall.
#![cfg_attr(test, expect(clippy::cast_lossless, reason = "debt: pay down"))]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use paw_types::TempoMap;

/// Where the song plays: the beat it was last put on, and the frames
/// played since.
///
/// The anchor moves on a seek, on the loop's wrap and on a new tempo map.
/// Each block moves `frames` on. `beat` is always the beat that the
/// engine's [`Clock`] gives for `frames`.
#[derive(Clone, Copy, Debug, Default)]
pub(super) struct PlayHead {
    anchor: f64,
    frames: u64,
    beat: f64,
}

impl PlayHead {
    /// The beat the song is on.
    pub(super) fn beat(&self) -> f64 {
        self.beat
    }

    /// Put the head on `beat`: the frames count from there.
    pub(super) fn put(&mut self, beat: f64) {
        *self = Self {
            anchor: beat,
            frames: 0,
            beat,
        };
    }

    /// Move the head `n` frames on, to `beat`, which the clock of the block
    /// gave for that frame ([`Clock::beat_after`]).
    pub(super) fn advance(&mut self, n: usize, beat: f64) {
        self.frames += n as u64;
        self.beat = beat;
    }
}

/// Beats and frames from the start of a block, while playing.
///
/// Each block's first and last beats are [`beat_at`](Self::beat_at) of a
/// frame count. An event is on the frame that
/// [`frame_of`](Self::frame_of) gives, the last frame whose beat is at or
/// before it. So the block whose beats hold an event also holds its frame,
/// whatever the size of the blocks.
#[derive(Clone, Copy)]
pub(super) struct Clock<'a> {
    map: &'a TempoMap,
    anchor: f64,
    /// Seconds at `anchor`.
    t0: f64,
    /// Frames from the anchor to the block's first frame.
    at: u64,
    sample_rate: f64,
    /// One tempo throughout: frames per beat, as plain arithmetic. A
    /// division by it gives each beat that is on a frame exactly when the
    /// frames of a beat are a whole number (120 BPM at 48 kHz).
    frames_per_beat: Option<f64>,
}

impl<'a> Clock<'a> {
    pub(super) fn new(map: &'a TempoMap, head: &PlayHead, sample_rate: f64) -> Self {
        Self {
            map,
            anchor: head.anchor,
            t0: map.seconds(head.anchor),
            at: head.frames,
            sample_rate,
            frames_per_beat: map
                .is_constant()
                .then(|| 60.0 * sample_rate / map.first_tempo()),
        }
    }

    /// The beat of the frame `frame` frames after the anchor.
    fn beat_at(&self, frame: u64) -> f64 {
        // The anchor itself, exactly: a beat taken to seconds and back can
        // come back one rounding off.
        if frame == 0 {
            return self.anchor;
        }
        match self.frames_per_beat {
            Some(fpb) => self.anchor + frame as f64 / fpb,
            None => self.map.beat(self.t0 + frame as f64 / self.sample_rate),
        }
    }

    /// Frames from the anchor to `beat`, not rounded.
    fn frames_since_anchor(&self, beat: f64) -> f64 {
        match self.frames_per_beat {
            Some(fpb) => (beat - self.anchor) * fpb,
            None => (self.map.seconds(beat) - self.t0) * self.sample_rate,
        }
    }

    /// The last frame from the anchor whose beat is at or before `beat`:
    /// the frame an event at `beat` plays on. The rounded estimate can be
    /// one frame off; the steps after it compare with
    /// [`beat_at`](Self::beat_at), the function that gives the blocks'
    /// beats.
    fn frame_of(&self, beat: f64) -> u64 {
        let mut frame = self.frames_since_anchor(beat).floor().max(0.0) as u64;
        while self.beat_at(frame + 1) <= beat {
            frame += 1;
        }
        while frame > 0 && self.beat_at(frame) > beat {
            frame -= 1;
        }
        frame
    }

    /// The frame of the block that an event at `beat`, in the block's
    /// beats, plays on.
    pub(super) fn frame_in_block(&self, beat: f64) -> usize {
        self.frame_of(beat).saturating_sub(self.at) as usize
    }

    /// The first frame of the block whose beat is at or after `beat`: 0
    /// for a beat before the block. With [`frame_in_block`](Self::frame_in_block),
    /// the frames of the block whose beats are in `from..to` are
    /// `first_frame_at(from)..first_frame_at(to)`.
    pub(super) fn first_frame_at(&self, beat: f64) -> usize {
        let frame = self.frame_of(beat);
        let frame = if self.beat_at(frame) < beat {
            frame + 1
        } else {
            frame
        };
        frame.saturating_sub(self.at) as usize
    }

    /// Frames from `beat` to the block's first frame, not rounded: how far
    /// into a region that starts at `beat` the block starts.
    pub(super) fn frames_into(&self, beat: f64) -> f64 {
        self.at as f64 - self.frames_since_anchor(beat)
    }

    /// Frames from the block's start to `beat`, not rounded.
    fn frames(&self, beat: f64) -> f64 {
        self.frames_since_anchor(beat) - self.at as f64
    }

    /// The first frame at or after `beat`.
    pub(super) fn frames_to(&self, beat: f64) -> usize {
        self.frames(beat).ceil() as usize
    }

    /// The frame `beat` is on: a point a rounding error off a frame is on it.
    pub(super) fn frames_on(&self, beat: f64) -> usize {
        let x = self.frames(beat);
        if (x - x.round()).abs() < 1e-6 {
            x.round() as usize
        } else {
            x.ceil() as usize
        }
    }

    /// The beat `n` frames after the block's start.
    pub(super) fn beat_after(&self, n: usize) -> f64 {
        self.beat_at(self.at + n as u64)
    }
}

#[cfg(test)]
mod tests {

    use paw_types::{SigPoint, TempoPoint};

    use super::*;

    /// An event is on the last frame whose beat is at or before it, so the
    /// block whose beats hold the event also holds its frame. The beats are
    /// every 5th tick (61440 a beat) over 8 beats from an anchor off the
    /// start: at 140 BPM a frame is not a whole number of ticks, and on the
    /// ramp the beats come from the map.
    #[test]
    fn an_event_is_on_the_last_frame_at_or_before_it() {
        let ramp = TempoMap::new(
            &[
                TempoPoint {
                    beat: 0.0,
                    bpm: 120.0,
                    ramp: true,
                },
                TempoPoint {
                    beat: 16.0,
                    bpm: 60.0,
                    ramp: false,
                },
            ],
            &[SigPoint {
                beat: 0.0,
                num: 4,
                den: 4,
            }],
        );
        for map in [TempoMap::constant(140.0, 4, 4), ramp] {
            let mut head = PlayHead::default();
            head.put(0.5);
            let clock = Clock::new(&map, &head, 48000.0);
            for tick in 0..8 * 61440 / 5 {
                let beat = 0.5 + (tick * 5) as f64 / 61440.0;
                let frame = clock.frame_of(beat);
                assert!(
                    clock.beat_at(frame) <= beat && beat < clock.beat_at(frame + 1),
                    "beat {beat} on frame {frame}"
                );
            }
        }
    }
}
