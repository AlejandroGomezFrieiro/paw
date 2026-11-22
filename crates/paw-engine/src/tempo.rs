//! The tempo map: where the tempo and the time signature change along the
//! song, and exact conversions between beats, seconds and bars.
//!
//! Positions are in beats (quarter notes) from the start of the song.
//!
//! - A tempo point sets the tempo from its beat on. It either holds until
//!   the next point or ramps to the next point's tempo, the tempo changing
//!   linearly in time (as REAPER's linear tempo shape does). The time a
//!   stretch of beats takes is the integral of 60 / tempo over it, worked
//!   out in closed form, so conversions are exact however long the ramp.
//! - A signature point starts a new bar at its beat with its signature. A
//!   point that falls inside what would have been a bar cuts that bar
//!   short (a partial bar), as in REAPER.
//!
//! Lookups are binary searches over the points, so they cost the same with
//! one point or ten thousand, and never allocate: the audio thread reads a
//! map it was handed whole.

/// The tempos a map keeps to.
pub const MIN_BPM: f64 = 1.0;
pub const MAX_BPM: f64 = 999.0;

/// How close two beats must be to count as the same place: well under a
/// tick, well over the rounding of a long song in `f64`.
pub const EPS: f64 = 1e-9;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TempoPoint {
    pub beat: f64,
    pub bpm: f64,
    /// Ramp linearly (in time) to the next point's tempo instead of holding.
    pub ramp: bool,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct SigPoint {
    /// Where the bar starts, in beats.
    pub beat: f64,
    pub num: u32,
    pub den: u32,
}

/// A stretch from one tempo point to the next.
#[derive(Clone, Copy, Debug)]
struct Seg {
    beat: f64,
    seconds: f64,
    bpm: f64,
    /// Change of tempo per second while ramping; 0 while holding.
    slope: f64,
    ramp: bool,
}

/// A stretch of bars of one signature.
#[derive(Clone, Copy, Debug)]
struct Bars {
    beat: f64,
    /// Index of the bar that starts at `beat`, counting from 0.
    bar: i64,
    num: u32,
    den: u32,
    /// Beats in a whole bar.
    len: f64,
}

/// A line on a ruler: a bar line or a beat of the signature.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Line {
    pub beat: f64,
    /// Index of the bar it is in, counting from 0.
    pub bar: i64,
    /// Beat of the signature within the bar, counting from 0: 0 is the bar line.
    pub index: u32,
}

#[derive(Clone, Debug)]
pub struct TempoMap {
    segs: Vec<Seg>,
    bars: Vec<Bars>,
}

impl Default for TempoMap {
    fn default() -> Self {
        Self::constant(120.0, 4, 4)
    }
}

fn clean_sig(num: u32, den: u32) -> (u32, u32) {
    (num.clamp(1, 64), den.clamp(1, 64))
}

impl TempoMap {
    /// One tempo and one signature throughout.
    pub fn constant(bpm: f64, num: u32, den: u32) -> Self {
        Self::new(
            &[TempoPoint {
                beat: 0.0,
                bpm,
                ramp: false,
            }],
            &[SigPoint {
                beat: 0.0,
                num,
                den,
            }],
        )
    }

    /// A map from points in any order. Points before beat 0 are moved to
    /// it; of two points at one beat the later in the list wins; tempos are
    /// kept between [`MIN_BPM`] and [`MAX_BPM`]. With no point at beat 0, the
    /// first one's tempo or signature also holds before it.
    pub fn new(tempos: &[TempoPoint], sigs: &[SigPoint]) -> Self {
        let mut map = TempoMap {
            segs: Vec::with_capacity(tempos.len().max(1)),
            bars: Vec::with_capacity(sigs.len().max(1)),
        };
        map.set(tempos, sigs);
        map
    }

    /// A map from points placed in seconds, as other programs keep them
    /// (`(seconds, bpm, ramp)` and `(seconds, num, den)`): each point's beat
    /// follows from the stretch before it, held or ramped. Points are put
    /// in time order; with none at 0 s, the first tempo holds from the start.
    pub fn from_seconds(tempos: &[(f64, f64, bool)], sigs: &[(f64, u32, u32)]) -> Self {
        let mut points: Vec<(f64, f64, bool)> = tempos
            .iter()
            .filter(|p| p.0.is_finite() && p.1.is_finite())
            .map(|&(t, bpm, ramp)| (t.max(0.0), bpm.clamp(MIN_BPM, MAX_BPM), ramp))
            .collect();
        points.sort_by(|a, b| a.0.total_cmp(&b.0));
        let mut beats: Vec<TempoPoint> = Vec::with_capacity(points.len());
        let mut last = 0.0;
        for (t, bpm, ramp) in points {
            let beat = match beats.last() {
                None => 0.0,
                // The tempo changes linearly in time over a ramp, so the
                // beats are the time by the mean of its two tempos.
                Some(prev) => prev.beat + (t - last) * if prev.ramp { (prev.bpm + bpm) / 120.0 } else { prev.bpm / 60.0 },
            };
            let point = TempoPoint { beat: if t <= EPS { 0.0 } else { beat }, bpm, ramp };
            match beats.last_mut() {
                Some(prev) if point.beat - prev.beat <= EPS => *prev = point,
                _ => beats.push(point),
            }
            // The first holds from the start, wherever it is.
            last = if beats.len() == 1 && beats[0] == point { 0.0 } else { t };
        }
        let map = TempoMap::new(&beats, &[]);
        let sigs: Vec<SigPoint> = sigs.iter().map(|&(t, num, den)| SigPoint { beat: map.beat(t.max(0.0)), num, den }).collect();
        TempoMap::new(&beats, &sigs)
    }

    /// Replace the points, reusing the map's memory.
    pub fn set(&mut self, tempos: &[TempoPoint], sigs: &[SigPoint]) {
        let clean = |b: f64| if b.is_finite() { b.max(0.0) } else { 0.0 };
        self.segs.clear();
        for p in tempos {
            let bpm = if p.bpm.is_finite() { p.bpm } else { 120.0 };
            self.segs.push(Seg {
                beat: clean(p.beat),
                seconds: 0.0,
                bpm: bpm.clamp(MIN_BPM, MAX_BPM),
                slope: 0.0,
                ramp: p.ramp,
            });
        }
        if self.segs.is_empty() {
            self.segs.push(Seg {
                beat: 0.0,
                seconds: 0.0,
                bpm: 120.0,
                slope: 0.0,
                ramp: false,
            });
        }
        // Stable, so that of two points at one beat the later stays last.
        self.segs.sort_by(|a, b| a.beat.total_cmp(&b.beat));
        dedup_last(&mut self.segs, |s| s.beat);
        self.segs[0].beat = 0.0;

        self.bars.clear();
        for p in sigs {
            let (num, den) = clean_sig(p.num, p.den);
            self.bars.push(Bars {
                beat: clean(p.beat),
                bar: 0,
                num,
                den,
                len: num as f64 * 4.0 / den as f64,
            });
        }
        if self.bars.is_empty() {
            self.bars.push(Bars {
                beat: 0.0,
                bar: 0,
                num: 4,
                den: 4,
                len: 4.0,
            });
        }
        self.bars.sort_by(|a, b| a.beat.total_cmp(&b.beat));
        dedup_last(&mut self.bars, |b| b.beat);
        self.bars[0].beat = 0.0;
        self.recompute();
    }

    /// Change the first tempo, keeping the other points. Does not allocate.
    pub fn set_first_tempo(&mut self, bpm: f64) {
        if bpm.is_finite() {
            self.segs[0].bpm = bpm.clamp(MIN_BPM, MAX_BPM);
            self.recompute();
        }
    }

    /// Change the first signature, keeping the other points. Does not allocate.
    pub fn set_first_signature(&mut self, num: u32, den: u32) {
        let (num, den) = clean_sig(num, den);
        let first = &mut self.bars[0];
        (first.num, first.den, first.len) = (num, den, num as f64 * 4.0 / den as f64);
        self.recompute();
    }

    /// Work out where each point is in seconds and bars.
    fn recompute(&mut self) {
        for i in 0..self.segs.len() {
            let (beat, bpm) = (self.segs[i].beat, self.segs[i].bpm);
            if i > 0 {
                let prev = self.segs[i - 1];
                self.segs[i].seconds = prev.seconds + prev.span_seconds(beat - prev.beat);
            }
            let slope = match self.segs.get(i + 1) {
                Some(next) if self.segs[i].ramp => {
                    let seconds = 120.0 * (next.beat - beat) / (bpm + next.bpm);
                    (next.bpm - bpm) / seconds
                }
                _ => 0.0,
            };
            self.segs[i].slope = slope;
        }
        for i in 1..self.bars.len() {
            let prev = self.bars[i - 1];
            let whole = ((self.bars[i].beat - prev.beat) / prev.len - EPS)
                .ceil()
                .max(1.0);
            self.bars[i].bar = prev.bar + whole as i64;
        }
    }

    /// The tempo points, in order.
    pub fn tempos(&self) -> impl Iterator<Item = TempoPoint> + '_ {
        self.segs.iter().map(|s| TempoPoint {
            beat: s.beat,
            bpm: s.bpm,
            ramp: s.ramp,
        })
    }

    /// The signature points, in order.
    pub fn signatures(&self) -> impl Iterator<Item = SigPoint> + '_ {
        self.bars.iter().map(|b| SigPoint {
            beat: b.beat,
            num: b.num,
            den: b.den,
        })
    }

    /// One tempo and one signature throughout.
    pub fn is_constant(&self) -> bool {
        self.segs.len() == 1 && self.bars.len() == 1
    }

    fn seg_at_beat(&self, beat: f64) -> &Seg {
        let i = self.segs.partition_point(|s| s.beat <= beat);
        &self.segs[i.saturating_sub(1)]
    }

    fn seg_at_seconds(&self, seconds: f64) -> &Seg {
        let i = self.segs.partition_point(|s| s.seconds <= seconds);
        &self.segs[i.saturating_sub(1)]
    }

    /// Seconds from the start of the song to `beat`.
    pub fn seconds(&self, beat: f64) -> f64 {
        let s = self.seg_at_beat(beat);
        s.seconds + s.span_seconds(beat - s.beat)
    }

    /// The beat `seconds` from the start of the song.
    pub fn beat(&self, seconds: f64) -> f64 {
        let s = self.seg_at_seconds(seconds);
        let t = seconds - s.seconds;
        s.beat + (s.bpm * t + s.slope * t * t / 2.0) / 60.0
    }

    /// Seconds from `from` to `to` (both in beats).
    pub fn seconds_between(&self, from: f64, to: f64) -> f64 {
        self.seconds(to) - self.seconds(from)
    }

    /// The tempo at a beat.
    pub fn tempo(&self, beat: f64) -> f64 {
        let s = self.seg_at_beat(beat);
        s.bpm_after(beat - s.beat)
    }

    /// The tempo at the start of the song.
    pub fn first_tempo(&self) -> f64 {
        self.segs[0].bpm
    }

    fn bars_at_beat(&self, beat: f64) -> &Bars {
        let i = self.bars.partition_point(|b| b.beat <= beat + EPS);
        &self.bars[i.saturating_sub(1)]
    }

    fn bars_at_bar(&self, bar: i64) -> &Bars {
        let i = self.bars.partition_point(|b| b.bar <= bar);
        &self.bars[i.saturating_sub(1)]
    }

    /// The signature of the bar at a beat.
    pub fn signature(&self, beat: f64) -> (u32, u32) {
        let b = self.bars_at_beat(beat);
        (b.num, b.den)
    }

    /// The bar a beat is in, counting from 0.
    pub fn bar_of(&self, beat: f64) -> i64 {
        let b = self.bars_at_beat(beat);
        // Saturating: a beat absurdly far on is in the last bar there is.
        b.bar.saturating_add(((beat - b.beat) / b.len + EPS).floor() as i64)
    }

    /// Where bar `bar` (counting from 0) starts, in beats.
    pub fn bar_start(&self, bar: i64) -> f64 {
        let b = self.bars_at_bar(bar);
        b.beat + (bar - b.bar) as f64 * b.len
    }

    /// The signature of bar `bar` (counting from 0).
    pub fn bar_signature(&self, bar: i64) -> (u32, u32) {
        let b = self.bars_at_bar(bar);
        (b.num, b.den)
    }

    /// Beats in the bar a beat is in: shorter than its signature says for
    /// a bar cut short by the next signature point.
    pub fn bar_length(&self, beat: f64) -> f64 {
        let bar = self.bar_of(beat);
        self.bar_start(bar + 1) - self.bar_start(bar)
    }

    /// Whether a bar starts at this beat.
    pub fn is_bar_line(&self, beat: f64) -> bool {
        (self.bar_start(self.bar_of(beat)) - beat).abs() < 1e-6
    }

    /// A beat as (bar, beat in the bar, fraction of that beat), counting bars
    /// and beats from 0; beats are of the signature's unit (an eighth in 6/8).
    pub fn bbt(&self, beat: f64) -> (i64, u32, f64) {
        let bar = self.bar_of(beat);
        let start = self.bar_start(bar);
        let unit = 4.0 / self.bar_signature(bar).1 as f64;
        let units = ((beat - start) / unit).max(0.0);
        let whole = (units + EPS).floor();
        (bar, whole as u32, (units - whole).max(0.0))
    }

    /// The beat at (bar, beat in the bar, fraction), as [`bbt`](Self::bbt) gives them.
    pub fn from_bbt(&self, bar: i64, beat: u32, fraction: f64) -> f64 {
        let unit = 4.0 / self.bar_signature(bar).1 as f64;
        self.bar_start(bar) + (beat as f64 + fraction) * unit
    }

    /// Every bar and signature beat line from `from` up to and not
    /// including `to`, in order, for as long as `f` returns true.
    pub fn lines(&self, from: f64, to: f64, mut f: impl FnMut(Line) -> bool) {
        if !to.is_finite() {
            return;
        }
        let mut bar = self.bar_of(from.max(0.0));
        loop {
            let start = self.bar_start(bar);
            // A bar past the last one counted is past any `to` worth asking.
            if start >= to || bar == i64::MAX {
                return;
            }
            let end = self.bar_start(bar + 1);
            let unit = 4.0 / self.bar_signature(bar).1 as f64;
            let mut index = 0u32;
            loop {
                let beat = start + index as f64 * unit;
                if beat >= end - EPS || beat >= to {
                    break;
                }
                if beat >= from - EPS && !f(Line { beat, bar, index }) {
                    return;
                }
                index += 1;
            }
            bar += 1;
        }
    }
}

impl Seg {
    /// Seconds that `beats` past this point take.
    fn span_seconds(&self, beats: f64) -> f64 {
        if self.slope == 0.0 {
            return beats * 60.0 / self.bpm;
        }
        // Tempo a + k t gives beats (a t + k t² / 2) / 60; solved for t in
        // the form that stays exact when k is small.
        let a = self.bpm;
        let root = (a * a + 120.0 * self.slope * beats).max(0.0).sqrt();
        120.0 * beats / (a + root)
    }

    fn bpm_after(&self, beats: f64) -> f64 {
        if self.slope == 0.0 || beats <= 0.0 {
            return self.bpm;
        }
        (self.bpm * self.bpm + 120.0 * self.slope * beats)
            .max(0.0)
            .sqrt()
    }
}

/// Of each run of items with one key, keep the last.
fn dedup_last<T: Copy>(items: &mut Vec<T>, key: impl Fn(&T) -> f64) {
    let mut out = 0;
    for i in 0..items.len() {
        if out > 0 && (key(&items[out - 1]) - key(&items[i])).abs() < EPS {
            items[out - 1] = items[i];
        } else {
            items[out] = items[i];
            out += 1;
        }
    }
    items.truncate(out);
}

/// Where a track's own time is in the song: from `from` up to `to` (song
/// beats), its beat 0 is the song's beat `zero`. A subproject's track has
/// one place for each block of the subproject.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Place {
    pub from: f64,
    pub to: f64,
    pub zero: f64,
}

/// A track's own time, which the devices on it see in their transport: a
/// subproject's bars, bar 1 at the start of the block that plays, with the
/// song's tempo there. Made on the main thread; reading it on the audio
/// thread allocates nothing.
#[derive(Clone, Debug)]
pub struct LocalTime {
    /// By `from`.
    places: Box<[Place]>,
    /// Its own meter, in its own beats; `None` for the song's meter where
    /// it plays.
    meter: Option<TempoMap>,
}

impl LocalTime {
    /// A track's time from its places (in any order) and its own meter
    /// (`sigs` in its own beats, the first at 0), or the song's when
    /// `sigs` is empty.
    pub fn new(mut places: Vec<Place>, sigs: &[SigPoint]) -> Self {
        places.sort_by(|a, b| a.from.total_cmp(&b.from));
        let tempo = [TempoPoint { beat: 0.0, bpm: 120.0, ramp: false }];
        let meter = (!sigs.is_empty()).then(|| TempoMap::new(&tempo, sigs));
        Self { places: places.into(), meter }
    }

    /// The place that the song's beat is in: the last that starts at or
    /// before it, else the first.
    fn place_at(&self, beat: f64) -> Option<&Place> {
        let after = self.places.partition_point(|p| p.from <= beat + EPS);
        self.places.get(after.saturating_sub(1))
    }

    /// What a device on the track sees of a block that the song sees as
    /// `song`, with the song's map `map`: the same tempo, and its position,
    /// seconds and bars counted from the place's beat 0.
    pub fn context(&self, song: &crate::device::ProcessCtx, map: &TempoMap) -> crate::device::ProcessCtx {
        let Some(place) = self.place_at(song.position) else {
            return *song;
        };
        let position = song.position - place.zero;
        let seconds = song.seconds - map.seconds(place.zero);
        let (sig_num, sig_den, bar, bar_start) = match &self.meter {
            Some(own) => {
                let (num, den) = own.signature(position);
                let bar = own.bar_of(position);
                (num, den, bar, own.bar_start(bar))
            }
            None => {
                let first = map.bar_of(place.zero);
                (song.sig_num, song.sig_den, song.bar - first, song.bar_start - place.zero)
            }
        };
        crate::device::ProcessCtx {
            position,
            seconds,
            bar,
            bar_start,
            sig_num,
            sig_den,
            ..*song
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn points_in_seconds_land_where_the_map_plays_them() {
        // 120 held for 2 s, then a ramp from 60 to 120 over 2 s.
        let map = TempoMap::from_seconds(&[(2.0, 60.0, true), (0.0, 120.0, false), (4.0, 120.0, false)], &[(0.0, 4, 4), (2.0, 3, 4)]);
        let beats: Vec<f64> = map.tempos().map(|p| p.beat).collect();
        assert_eq!(beats, vec![0.0, 4.0, 7.0]);
        assert!((map.seconds(7.0) - 4.0).abs() < 1e-9, "the core's own math agrees");
        assert_eq!(map.signatures().last().map(|s| (s.beat, s.num)), Some((4.0, 3)));
    }

    fn t(beat: f64, bpm: f64, ramp: bool) -> TempoPoint {
        TempoPoint { beat, bpm, ramp }
    }
    fn s(beat: f64, num: u32, den: u32) -> SigPoint {
        SigPoint { beat, num, den }
    }
    fn near(a: f64, b: f64, what: &str) {
        assert!((a - b).abs() < 1e-9, "{what}: {a} is not {b}");
    }

    #[test]
    fn one_tempo_is_a_straight_line() {
        let m = TempoMap::constant(120.0, 4, 4);
        near(m.seconds(8.0), 4.0, "8 beats at 120");
        near(m.beat(4.0), 8.0, "4 s at 120");
        near(m.seconds(-2.0), -1.0, "before the start");
        assert_eq!(m.bar_of(7.999), 1);
        assert_eq!(m.bar_of(8.0), 2);
        near(m.bar_start(3), 12.0, "bar 3");
    }

    #[test]
    fn steps_add_up() {
        let m = TempoMap::new(&[t(0.0, 120.0, false), t(4.0, 60.0, false)], &[]);
        near(m.seconds(4.0), 2.0, "four beats at 120");
        near(m.seconds(6.0), 4.0, "then two at 60");
        near(m.beat(3.0), 5.0, "back");
        near(m.tempo(3.999), 120.0, "before the step");
        near(m.tempo(4.0), 60.0, "at the step");
    }

    #[test]
    fn a_ramp_takes_its_integral() {
        // 120 to 90 over 8 beats, linear in time: the average tempo is 105,
        // so it takes 8 * 60 / 105 seconds.
        let m = TempoMap::new(&[t(0.0, 120.0, true), t(8.0, 90.0, false)], &[]);
        let total = 8.0 * 60.0 / 105.0;
        near(m.seconds(8.0), total, "the whole ramp");
        near(m.tempo(8.0), 90.0, "the ramp's end");
        near(m.tempo(10.0), 90.0, "after it");
        near(m.seconds(10.0), total + 2.0 * 60.0 / 90.0, "after it");
        // Halfway in time the tempo is halfway: 105 bpm, and the beats so
        // far are (120 + 105) / 2 * t / 60.
        let half = total / 2.0;
        let beat = m.beat(half);
        near(
            beat,
            (120.0 + 105.0) / 2.0 * half / 60.0,
            "beats at half the time",
        );
        near(m.tempo(beat), 105.0, "tempo halfway");
        // Summing small steps of 60 / tempo approaches the same answer.
        let steps = 200_000;
        let db = 8.0 / steps as f64;
        let sum: f64 = (0..steps)
            .map(|i| 60.0 / m.tempo((i as f64 + 0.5) * db) * db)
            .sum();
        assert!((sum - total).abs() < 1e-7, "{sum} vs {total}");
    }

    #[test]
    fn ramps_up_and_round_trips() {
        let m = TempoMap::new(
            &[
                t(0.0, 60.0, true),
                t(4.0, 240.0, true),
                t(12.0, 30.0, false),
                t(13.0, 400.0, true),
            ],
            &[],
        );
        for i in 0..2000 {
            let b = i as f64 * 0.0137;
            near(m.beat(m.seconds(b)), b, "beat round trip");
            let sec = i as f64 * 0.0091;
            near(m.seconds(m.beat(sec)), sec, "seconds round trip");
        }
        let mut last = -1.0;
        for i in 0..2000 {
            let x = m.seconds(i as f64 * 0.01);
            assert!(x > last, "time goes forward");
            last = x;
        }
    }

    #[test]
    fn a_ramp_with_no_point_after_it_holds() {
        let m = TempoMap::new(&[t(0.0, 100.0, true)], &[]);
        near(m.seconds(10.0), 6.0, "held");
    }

    #[test]
    fn unsorted_and_duplicate_points() {
        let m = TempoMap::new(
            &[
                t(8.0, 60.0, false),
                t(2.0, 90.0, false),
                t(8.0, 30.0, false),
            ],
            &[],
        );
        let points: Vec<_> = m.tempos().collect();
        assert_eq!(points.len(), 2);
        assert_eq!(points[0].beat, 0.0, "the first point is moved to the start");
        assert_eq!(points[1].bpm, 30.0, "the later of two at one beat wins");
        near(
            m.seconds(2.0),
            2.0 * 60.0 / 90.0,
            "the first tempo holds from 0",
        );
    }

    #[test]
    fn signature_changes_count_bars() {
        // 4/4 for eight bars, then 6/8.
        let m = TempoMap::new(&[], &[s(0.0, 4, 4), s(32.0, 6, 8)]);
        assert_eq!(m.bar_of(31.9), 7);
        assert_eq!(m.bar_of(32.0), 8);
        near(m.bar_start(8), 32.0, "bar 9 starts the 6/8");
        near(m.bar_start(9), 35.0, "6/8 bars are three quarters long");
        assert_eq!(m.signature(33.0), (6, 8));
        assert_eq!(m.bbt(33.5), (8, 3, 0.0), "the fourth eighth of bar 9");
        near(m.from_bbt(8, 3, 0.0), 33.5, "and back");
        assert!(m.is_bar_line(35.0));
        assert!(!m.is_bar_line(34.0));
    }

    #[test]
    fn a_signature_inside_a_bar_cuts_it_short() {
        let m = TempoMap::new(&[], &[s(0.0, 4, 4), s(6.0, 3, 4)]);
        assert_eq!(m.bar_of(5.0), 1, "the cut bar");
        assert_eq!(m.bar_of(6.0), 2, "the new bar starts at the point");
        near(m.bar_length(5.0), 2.0, "the cut bar is two beats");
        near(m.bar_start(3), 9.0, "then bars of three");
        assert!(m.is_bar_line(6.0));
        let mut lines = Vec::new();
        m.lines(3.5, 9.5, |l| {
            lines.push((l.beat, l.bar, l.index));
            true
        });
        assert_eq!(
            lines,
            vec![
                (4.0, 1, 0),
                (5.0, 1, 1),
                (6.0, 2, 0),
                (7.0, 2, 1),
                (8.0, 2, 2),
                (9.0, 3, 0)
            ]
        );
    }

    #[test]
    fn lines_far_away_or_many_end() {
        let m = TempoMap::new(&[], &[s(0.0, 4, 4), s(8.0, 3, 4)]);
        let mut n = 0;
        m.lines(1e300, 1e300, |_| {
            n += 1;
            true
        });
        m.lines(0.0, 1e300, |_| {
            n += 1;
            n < 100
        });
        assert_eq!(n, 100, "nothing out there, and the count stops it");
        assert_eq!(m.bar_of(1e300), i64::MAX, "a beat past every bar is in the last");
    }

    #[test]
    fn lines_follow_the_unit() {
        let m = TempoMap::new(&[], &[s(0.0, 6, 8)]);
        let mut n = 0;
        let mut bars = 0;
        m.lines(0.0, 6.0, |l| {
            n += 1;
            bars += (l.index == 0) as i32;
            true
        });
        assert_eq!((n, bars), (12, 2), "two bars of six eighths");
    }

    #[test]
    fn thousands_of_points() {
        let tempos: Vec<_> = (0..10_000)
            .map(|i| t(i as f64 * 0.5, 60.0 + (i % 97) as f64, i % 3 == 0))
            .collect();
        let sigs: Vec<_> = (0..3000)
            .map(|i| s(i as f64 * 7.0, 3 + (i % 5) as u32, 4 << (i % 2)))
            .collect();
        let m = TempoMap::new(&tempos, &sigs);
        let mut seconds = 0.0;
        for p in tempos.windows(2) {
            // Each half beat on its own, summed, against the map's total.
            let a = p[0];
            let b = p[1];
            let span = if a.ramp {
                120.0 * (b.beat - a.beat) / (a.bpm + b.bpm)
            } else {
                60.0 * (b.beat - a.beat) / a.bpm
            };
            seconds += span;
            near(m.seconds(b.beat), seconds, "running total");
        }
        for i in 0..5000 {
            let b = i as f64 * 0.997;
            assert!((m.beat(m.seconds(b)) - b).abs() < 1e-7);
            let bar = m.bar_of(b);
            assert!(m.bar_start(bar) <= b + EPS && b < m.bar_start(bar + 1) + EPS);
        }
    }
}
