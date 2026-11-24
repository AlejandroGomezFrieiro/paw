//! Where a stretched clip plays each moment of its file: a map from time in
//! the file to time in the version made of it (`stretched.rs`).
//!
//! A clip stretched evenly plays a second of its file as `stretch` seconds.
//! Warp markers (`Clip::warp`) pin moments of the file to moments of the
//! clip, so that the stretch between two neighbouring markers is its own: a
//! marker is a moment of the file (`source`) and the moment of the file as
//! it would be heard without the markers (`target`), both in seconds, and
//! the clip's stretch applies to the result. Before the first marker and
//! after the last the file runs at the clip's stretch.
//!
//! A clip that follows the tempo (the `stretch` timebase) and has a tempo
//! that changes inside it is not stretched evenly but bent: its sound being
//! at `source_tempo`, each of its beats lands on a beat of the song, ramps
//! and all.
//!
//! Either way the map is made of straight pieces, from which the version is
//! made (`stretch.rs`), and in which the engine finds where the clip's
//! start is (the time its `offset` maps to).
#![cfg_attr(test, expect(clippy::cast_lossless, reason = "debt: pay down"))]
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]
#![expect(clippy::float_cmp, reason = "debt: pay down")]

use anyhow::{Result, bail};
use paw_types::TempoMap;

use crate::model::{Clip, ClipContent, Timebase, WarpMarker};
use crate::stretch::RATIO_RANGE;

/// An increasing map made of straight pieces, from one time to another.
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Warp {
    /// Its corners, (from, to), in order of both; at least one.
    points: Vec<(f64, f64)>,
    /// How fast it goes before its first corner and after its last.
    before: f64,
    after: f64,
}

impl Warp {
    /// `ratio` times as long throughout, from 0.
    pub(crate) fn even(ratio: f64) -> Self {
        Self {
            points: vec![(0.0, 0.0)],
            before: ratio,
            after: ratio,
        }
    }

    /// Through `points` (sorted, increasing in both), going on at `before`
    /// and `after` past them.
    pub(crate) fn new(points: Vec<(f64, f64)>, before: f64, after: f64) -> Self {
        if points.is_empty() {
            return Self::even(before);
        }
        Self {
            points,
            before,
            after,
        }
    }

    /// Where `x` goes.
    pub(crate) fn forward(&self, x: f64) -> f64 {
        let p = &self.points;
        let i = p.partition_point(|q| q.0 <= x);
        if i == 0 {
            return p[0].1 + (x - p[0].0) * self.before;
        }
        let (x0, y0) = p[i - 1];
        match p.get(i) {
            None => y0 + (x - x0) * self.after,
            Some(&(x1, y1)) => y0 + (x - x0) * (y1 - y0) / (x1 - x0),
        }
    }

    /// What goes to `y`.
    pub(crate) fn inverse(&self, y: f64) -> f64 {
        let p = &self.points;
        let i = p.partition_point(|q| q.1 <= y);
        if i == 0 {
            return p[0].0 + (y - p[0].1) / self.before;
        }
        let (x0, y0) = p[i - 1];
        match p.get(i) {
            None => x0 + (y - y0) / self.after,
            Some(&(x1, y1)) => x0 + (y - y0) * (x1 - x0) / (y1 - y0),
        }
    }

    /// How fast it goes in each of its pieces, the outer two first.
    pub(crate) fn slopes(&self) -> impl Iterator<Item = f64> + '_ {
        [self.before, self.after].into_iter().chain(
            self.points
                .windows(2)
                .map(|w| (w[1].1 - w[0].1) / (w[1].0 - w[0].0)),
        )
    }

    /// The ratio it goes at throughout, from 0 to 0, if it is even.
    pub(crate) fn ratio(&self) -> Option<f64> {
        let even =
            self.points.len() == 1 && self.points[0] == (0.0, 0.0) && self.before == self.after;
        even.then_some(self.before)
    }

    /// The same map with its times `to` made `k` times as long.
    pub(crate) fn scaled(&self, k: f64) -> Self {
        Self {
            points: self.points.iter().map(|&(x, y)| (x, y * k)).collect(),
            before: self.before * k,
            after: self.after * k,
        }
    }

    /// The same map in frames at `rate` rather than seconds.
    pub(crate) fn in_frames(&self, rate: f64) -> Self {
        Self {
            points: self
                .points
                .iter()
                .map(|&(x, y)| (x * rate, y * rate))
                .collect(),
            ..self.clone()
        }
    }

    /// Moved in time so that 0 goes to 0.
    fn anchored(mut self) -> Self {
        let zero = self.forward(0.0);
        for p in &mut self.points {
            p.1 -= zero;
        }
        self
    }

    /// The map as numbers that are the same for the same map, for knowing a
    /// version by it.
    pub(crate) fn bits(&self) -> Vec<u64> {
        let mut out = vec![self.before.to_bits(), self.after.to_bits()];
        for (x, y) in &self.points {
            out.push(x.to_bits());
            out.push(y.to_bits());
        }
        out
    }

    /// The map [`bits`](Self::bits) gave.
    pub(crate) fn from_bits(bits: &[u64]) -> Self {
        let f = |i: usize| f64::from_bits(bits[i]);
        let points = (2..bits.len())
            .step_by(2)
            .map(|i| (f(i), f(i + 1)))
            .collect();
        Self::new(points, f(0), f(1))
    }

    /// Fails unless each piece is stretched within [`RATIO_RANGE`].
    pub(crate) fn check(&self) -> Result<()> {
        let (lo, hi) = RATIO_RANGE;
        // A little slack for the rounding of corners worked out from beats.
        for slope in self.slopes() {
            if !(lo * (1.0 - 1e-9)..=hi * (1.0 + 1e-9)).contains(&slope) {
                bail!(
                    "a part of the clip would be stretched {slope:.3} times, outside {lo} to {hi}"
                );
            }
        }
        Ok(())
    }
}

/// A clip's markers as a map from its file's time to its time unstretched.
fn markers(warp: &[WarpMarker]) -> Warp {
    Warp::new(
        warp.iter().map(|m| (m.source, m.target)).collect(),
        1.0,
        1.0,
    )
}

/// Beats apart that a bent clip's map has a corner at, where the tempo
/// changes inside it: an eighth of a beat follows a ramp to well under a
/// millisecond.
const BEND_STEP: f64 = 0.125;

/// Whether the tempo changes anywhere from beat `a` to `b`.
fn changes(map: &TempoMap, a: f64, b: f64) -> bool {
    let first = map.tempo(a);
    let steps = ((b - a) / BEND_STEP).ceil() as usize;
    (0..=steps).any(|i| (map.tempo((a + i as f64 * BEND_STEP).min(b - 1e-9)) - first).abs() > 1e-9)
        || map.tempos().any(|p| p.beat > a && p.beat < b)
}

/// How `clip` is bent along the tempo, if it follows the tempo and the
/// tempo changes inside it: its file's time to its time, unanchored.
fn bent(clip: &Clip, map: &TempoMap, unstretched: &Warp, offset: f64) -> Option<Warp> {
    let bpm = clip.source_tempo?;
    let (a, b) = (clip.start, clip.start + clip.length);
    if clip.timebase != Some(Timebase::Stretch) || clip.repeat().is_some() || !changes(map, a, b) {
        return None;
    }
    let u_offset = unstretched.forward(offset);
    let (first, last) = (map.tempo(a), map.tempo(b - 1e-9));
    let length = map.seconds_between(a, b);
    // Seconds from the clip's start to a beat, the tempo held past its ends.
    let seconds = |beat: f64| {
        if beat < a {
            (beat - a) * 60.0 / first
        } else if beat > b {
            length + (beat - b) * 60.0 / last
        } else {
            map.seconds_between(a, beat)
        }
    };
    // The beat a moment of the unstretched file lands on.
    let beat = |u: f64| a + (u - u_offset) * bpm / 60.0;
    let mut corners: Vec<f64> = clip.warp.iter().map(|m| m.source).collect();
    let steps = ((b - a) / BEND_STEP).ceil() as usize;
    for i in 0..=steps {
        let at = (a + i as f64 * BEND_STEP).min(b);
        corners.push(unstretched.inverse(u_offset + (at - a) * 60.0 / bpm));
    }
    corners.sort_by(f64::total_cmp);
    corners.dedup_by(|x, y| (*x - *y).abs() < 1e-9);
    let points = corners
        .into_iter()
        .map(|x| (x, seconds(beat(unstretched.forward(x)))))
        .collect();
    let warp = Warp::new(points, bpm / first, bpm / last);
    warp.check().is_ok().then_some(warp)
}

/// Whether `clip` is bent along the tempo rather than stretched evenly.
pub(crate) fn is_bent(clip: &Clip, map: &TempoMap) -> bool {
    let Some(ClipContent::Audio { offset, .. }) = clip.playable() else {
        return false;
    };
    bent(clip, map, &markers(&clip.warp), *offset).is_some()
}

/// What `clip` plays of its file, with the song's tempo `map`: its file's
/// seconds to the seconds of the version it plays, 0 to 0. `None` for a
/// clip that plays its file as it is.
pub(crate) fn of(clip: &Clip, map: &TempoMap) -> Option<Warp> {
    let Some(ClipContent::Audio { offset, .. }) = clip.playable() else {
        return None;
    };
    let unstretched = markers(&clip.warp);
    let warp = match bent(clip, map, &unstretched, *offset) {
        Some(warp) => warp,
        None => unstretched.scaled(clip.stretch.0),
    }
    .anchored();
    let plain = warp.ratio() == Some(1.0) && clip.pitch == 0.0;
    (!plain).then_some(warp)
}

/// Where `clip` plays its file's moment `source`, as a beat of the song.
pub(crate) fn beat_of(clip: &Clip, map: &TempoMap, source: f64) -> f64 {
    let Some(ClipContent::Audio { offset, .. }) = clip.playable() else {
        return clip.start;
    };
    let warp = of(clip, map).unwrap_or_else(|| Warp::even(1.0));
    let from = map.seconds(clip.start) + warp.forward(source) - warp.forward(*offset);
    map.beat(from)
}

/// The moment of its file that `clip` plays at `beat`.
pub(crate) fn source_at(clip: &Clip, map: &TempoMap, beat: f64) -> f64 {
    let Some(ClipContent::Audio { offset, .. }) = clip.playable() else {
        return 0.0;
    };
    let warp = of(clip, map).unwrap_or_else(|| Warp::even(1.0));
    warp.inverse(warp.forward(*offset) + map.seconds(beat) - map.seconds(clip.start))
}

/// The `target` that puts a marker at `source` on `beat`, the rest of the
/// clip staying as it is: as the clip is bent, or stretched evenly.
pub(crate) fn target_for(clip: &Clip, map: &TempoMap, beat: f64) -> f64 {
    let Some(ClipContent::Audio { offset, .. }) = clip.playable() else {
        return 0.0;
    };
    let unstretched = markers(&clip.warp);
    let u_offset = unstretched.forward(*offset);
    let bpm = clip.source_tempo.unwrap_or(0.0);
    match bent(clip, map, &unstretched, *offset) {
        Some(_) => u_offset + (beat - clip.start) * 60.0 / bpm,
        None => u_offset + map.seconds_between(clip.start, beat) / clip.stretch.0,
    }
}

/// The furthest `target` of marker `index` of `warp` may go either way and
/// keep the stretch on both its sides within [`RATIO_RANGE`] at `stretch`.
pub(crate) fn target_range(warp: &[WarpMarker], index: usize, stretch: f64) -> (f64, f64) {
    let (lo, hi) = RATIO_RANGE;
    let m = warp[index];
    let mut range = (f64::NEG_INFINITY, f64::INFINITY);
    if let Some(left) = index.checked_sub(1).map(|i| warp[i]) {
        let span = m.source - left.source;
        range.0 = range.0.max(left.target + span * lo / stretch);
        range.1 = range.1.min(left.target + span * hi / stretch);
    }
    if let Some(right) = warp.get(index + 1) {
        let span = right.source - m.source;
        range.0 = range.0.max(right.target - span * hi / stretch);
        range.1 = range.1.min(right.target - span * lo / stretch);
    }
    range
}

#[cfg(test)]
mod tests {
    use paw_types::TempoPoint;

    use super::*;
    use crate::model::Id;
    use std::path::PathBuf;

    fn clip(start: f64, length: f64, offset: f64) -> Clip {
        serde_json::from_value(serde_json::json!({
            "id": 1 as Id, "name": "c", "start": start, "length": length, "muted": false,
            "content": { "kind": "audio", "file": PathBuf::from("/x.wav"), "offset": offset, "gain": 0.0 },
        }))
        .unwrap()
    }

    #[test]
    fn a_map_goes_both_ways_and_on_past_its_corners() {
        let w = Warp::new(vec![(1.0, 2.0), (3.0, 3.0)], 2.0, 0.5);
        for x in [-1.0, 0.0, 1.0, 2.0, 3.0, 7.5] {
            assert!((w.inverse(w.forward(x)) - x).abs() < 1e-12, "{x}");
        }
        assert_eq!(w.forward(0.0), 0.0);
        assert_eq!(w.forward(2.0), 2.5);
        assert_eq!(w.forward(5.0), 4.0);
        assert_eq!(w.slopes().collect::<Vec<_>>(), [2.0, 0.5, 0.5]);
        assert_eq!(Warp::even(1.5).ratio(), Some(1.5));
        assert_eq!(w.ratio(), None);
    }

    #[test]
    fn markers_stretch_each_part_on_its_own_and_land_where_they_are_put() {
        let map = TempoMap::constant(120.0, 4, 4);
        let mut c = clip(4.0, 8.0, 0.5);
        c.stretch = crate::model::Factor(2.0);
        assert_eq!(of(&c, &map).unwrap().ratio(), Some(2.0));
        // Pinned where they are: nothing changes.
        c.warp = vec![
            WarpMarker {
                source: 1.0,
                target: 1.0,
            },
            WarpMarker {
                source: 2.0,
                target: 2.0,
            },
        ];
        assert!(
            (beat_of(&c, &map, 1.0) - 6.0).abs() < 1e-9,
            "a second in at 2x"
        );
        // The second marker a beat (half a second) later: the second between
        // them plays for two and a half.
        c.warp[1].target = target_for(&c, &map, 11.0);
        assert!((beat_of(&c, &map, 2.0) - 11.0).abs() < 1e-9);
        let w = of(&c, &map).unwrap();
        let slopes: Vec<f64> = w.slopes().collect();
        assert_eq!(slopes, [2.0, 2.0, 2.5]);
        assert!((source_at(&c, &map, 11.0) - 2.0).abs() < 1e-9);
        // Where the clip starts is where it was.
        assert!((beat_of(&c, &map, 0.5) - 4.0).abs() < 1e-9);
        // How far it can go: a quarter to four times on both sides.
        let (lo, hi) = target_range(&c.warp, 1, 2.0);
        assert!((lo - (1.0 + 0.25 / 2.0)).abs() < 1e-12 && (hi - 3.0).abs() < 1e-12);
    }

    #[test]
    fn a_clip_following_the_tempo_is_bent_along_a_ramp_inside_it() {
        // 120 BPM, ramping from beat 4 to 100 BPM at beat 12.
        let points = [
            TempoPoint {
                beat: 0.0,
                bpm: 120.0,
                ramp: false,
            },
            TempoPoint {
                beat: 4.0,
                bpm: 120.0,
                ramp: true,
            },
            TempoPoint {
                beat: 12.0,
                bpm: 100.0,
                ramp: false,
            },
        ];
        let map = TempoMap::new(&points, &[]);
        let mut c = clip(4.0, 8.0, 0.0);
        c.timebase = Some(Timebase::Stretch);
        c.source_tempo = Some(120.0);
        let w = of(&c, &map).unwrap();
        // Each of its beats (half a second of its file) on a beat of the song.
        for k in 0..=8 {
            let source = k as f64 * 0.5;
            let beat = beat_of(&c, &map, source);
            assert!((beat - (4.0 + k as f64)).abs() < 1e-6, "beat {k} at {beat}");
        }
        assert!(w.slopes().all(|s| (1.0 - 1e-9..=1.2 + 1e-9).contains(&s)));
        // Evenly, its middle would be off its beat.
        c.timebase = None;
        c.stretch = crate::model::Factor(map.seconds_between(4.0, 12.0) / 4.0);
        let even = beat_of(&c, &map, 2.0);
        assert!((even - 8.0).abs() > 0.05, "{even}");
        // Without the ramp inside it, it is stretched evenly.
        c.timebase = Some(Timebase::Stretch);
        c.start = 12.0;
        c.stretch = crate::model::Factor(1.2);
        assert_eq!(of(&c, &map).unwrap().ratio(), Some(1.2));
    }
}
