//! Where a nest's beats are in the song (`nest.md` 4.2, `TempoMap::nest`).
//!
//! A nest that follows the song's tempo (the default) plays its beat `b`
//! at the song's beat `zero + b`: a shift, exact, and what every place in
//! the song saw before nests had a tempo of their own. A nest with its own
//! tempo (`:nest.time own`) plays through seconds: its beat `b` is the
//! moment `nest.seconds(b)` after its block starts, whatever the song's
//! tempo is there. A ritardando of the song over the block then changes
//! nothing inside it, and the block's length in the song follows its
//! seconds.
//!
//! [`Timing`] is the one place that converts. The sync places the clips,
//! the lanes and the transport of a nest's parts with it; the window
//! inside a nest reads [`Nest::own_map`] for its ruler.

use std::sync::Arc;

use paw_types::{SigPoint, TempoMap, TempoPoint};

use super::{Nest, NestMeter, NestTempo};
use crate::model::{Clip, ClipContent, Control, Id, Lane, Note, Notes};

impl Nest {
    /// Whether the nest keeps a tempo of its own.
    pub(crate) fn has_own_tempo(&self) -> bool {
        matches!(self.tempo, NestTempo::Own { .. })
    }

    /// The tempo points of its own map, the first at beat 0; empty when it
    /// follows the song.
    pub(crate) fn own_tempos(&self) -> Vec<TempoPoint> {
        match &self.tempo {
            NestTempo::Own { points } => points
                .iter()
                .map(|c| TempoPoint { beat: c.beat, bpm: c.bpm, ramp: c.ramp })
                .collect(),
            NestTempo::Follow { .. } => Vec::new(),
        }
    }

    /// The map of the nest's own timeline, for a block whose beat 0 is the
    /// song's beat `zero`: its own tempo or the song's from `zero` on, and
    /// its own meter or the song's there. None when it follows the song in
    /// both: the song's map, shifted, is its map then.
    pub(crate) fn own_map(&self, song: &TempoMap, zero: f64) -> Option<TempoMap> {
        let tempos = match &self.tempo {
            NestTempo::Own { .. } => self.own_tempos(),
            NestTempo::Follow { .. } if self.meter == NestMeter::Follow => return None,
            NestTempo::Follow { .. } => song_tempos_from(song, zero),
        };
        let sigs: Vec<SigPoint> = match &self.meter {
            NestMeter::Own { changes } => changes
                .iter()
                .map(|c| SigPoint { beat: c.beat, num: c.num, den: c.den })
                .collect(),
            // Its beats do not line up with the song's: the song's meter at
            // its start holds throughout.
            NestMeter::Follow => {
                let (num, den) = song.signature(zero);
                vec![SigPoint { beat: 0.0, num, den }]
            }
        };
        Some(TempoMap::new(&tempos, &sigs))
    }

    /// How a block of this nest places its beats: `start` is the song's beat
    /// where the block starts and `offset` the nest's beat that starts there.
    /// `outer` is the timing of the place that holds the block (`start` is a
    /// beat of that place), None for the song.
    pub(crate) fn timing(&self, song: &Arc<TempoMap>, outer: Option<&Timing>, start: f64, offset: f64) -> Timing {
        let at = outer.map_or(start, |o| o.song_beat(start));
        if self.has_own_tempo() {
            let nest = Arc::new(self.own_map(song, at).unwrap_or_default());
            let base = song.seconds(at) - nest.seconds(offset);
            return Timing::Warp(Arc::new(Warp { song: song.clone(), nest, base, shift: 0.0 }));
        }
        match outer {
            Some(Timing::Warp(w)) => Timing::Warp(Arc::new(Warp { shift: w.shift + start - offset, ..(**w).clone() })),
            _ => Timing::Shift(at - offset),
        }
    }
}

/// The song's tempo points from `zero` on, moved so that `zero` is beat 0.
pub(super) fn song_tempos_from(song: &TempoMap, zero: f64) -> Vec<TempoPoint> {
    let ramp = song.tempos().take_while(|p| p.beat <= zero).last().is_some_and(|p| p.ramp);
    let mut out = vec![TempoPoint { beat: 0.0, bpm: song.tempo(zero), ramp }];
    out.extend(
        song.tempos()
            .filter(|p| p.beat > zero)
            .map(|p| TempoPoint { beat: p.beat - zero, ..p }),
    );
    out
}

/// A nest's beats through seconds: its beat `b` plays at the song's second
/// `base + nest.seconds(b + shift)`. `shift` is not 0 for a nest that
/// follows the tempo inside one that has its own: its beats are beats of
/// the outer nest, from `shift` on.
#[derive(Clone, Debug)]
pub(crate) struct Warp {
    pub song: Arc<TempoMap>,
    pub nest: Arc<TempoMap>,
    pub base: f64,
    pub shift: f64,
}

impl PartialEq for Warp {
    /// The same song map (the very same: a tempo edit makes a new one), the
    /// same tempos inside and the same place. The meter places nothing.
    fn eq(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.song, &other.song)
            && self.base == other.base
            && self.shift == other.shift
            && self.nest.tempos().eq(other.nest.tempos())
    }
}

/// Where the beats of a nest are in the song, for one block.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Timing {
    /// Its beat `b` is the song's beat `zero + b`.
    Shift(f64),
    /// Through seconds (see [`Warp`]).
    Warp(Arc<Warp>),
}

impl Timing {
    /// The song's beat of a beat of the nest.
    pub(crate) fn song_beat(&self, beat: f64) -> f64 {
        match self {
            Self::Shift(zero) => zero + beat,
            Self::Warp(w) => w.song.beat(w.base + w.nest.seconds(beat + w.shift)),
        }
    }

    /// The nest's beat of a beat of the song.
    pub(crate) fn nest_beat(&self, song: f64) -> f64 {
        match self {
            Self::Shift(zero) => song - zero,
            Self::Warp(w) => w.nest.beat(w.song.seconds(song) - w.base) - w.shift,
        }
    }

    /// The song's beat of the nest's beat 0.
    pub(crate) fn zero(&self) -> f64 {
        self.song_beat(0.0)
    }

    /// A clip of the nest placed in the song, cut at the window `from..to`
    /// of song beats, with the id `id` (see [`super::placed_clip`]).
    pub(crate) fn place_clip(&self, clip: &Clip, from: f64, to: f64, id: Id) -> Option<Clip> {
        match self {
            Self::Shift(zero) => super::placed_clip(clip, *zero, from, to, id),
            Self::Warp(_) => self.warped_clip(clip, from, to, id),
        }
    }

    /// [`Timing::place_clip`] through seconds: each note and control lands
    /// where its own beat plays, so they keep their seconds apart. A looped
    /// MIDI clip plays its repeats as notes. Sound keeps its seconds as it
    /// is; one cut at its start is left out, as [`super::placed_clip`] does.
    fn warped_clip(&self, clip: &Clip, from: f64, to: f64, id: Id) -> Option<Clip> {
        let at = |beat: f64| self.song_beat(clip.start + beat);
        let start = at(0.0);
        let end = at(clip.length).min(to);
        let first = start.max(from);
        if end <= first {
            return None;
        }
        let cut = first - start > 1e-9;
        let mut copy = Clip {
            id,
            start: first,
            length: end - first,
            ..clip.clone()
        };
        match &clip.content {
            ClipContent::Midi { notes, controls } => {
                let inside = |beat: f64| {
                    let song = at(beat);
                    (song >= first - 1e-9 && song < end).then_some(song - first)
                };
                let notes: Notes = played_notes(clip, notes)
                    .filter_map(|n| {
                        let placed = inside(n.start)?;
                        let length = at(n.start + n.length) - at(n.start);
                        Some(Note { start: placed, length, ..n })
                    })
                    .collect();
                let controls = controls
                    .iter()
                    .filter_map(|c| Some(Control { start: inside(c.start)?, ..c.clone() }))
                    .collect();
                copy.content = ClipContent::Midi { notes, controls };
                (copy.looped, copy.loop_length, copy.loop_start) = (false, None, 0.0);
            }
            ClipContent::Nest { .. } => return None,
            _ if cut => return None,
            // Sound keeps its seconds: its loop and fades are beats of the
            // nest, now of the song.
            _ => {
                copy.fade_in = at(clip.fade_in) - start;
                copy.fade_out = at(clip.length) - at(clip.length - clip.fade_out);
                if let Some(period) = clip.loop_length {
                    copy.loop_length = Some(at(period) - start);
                    copy.loop_start = at(clip.loop_start) - start;
                }
            }
        }
        Some(copy)
    }
}

/// The notes a MIDI clip plays, from its start: a looped clip's repeats
/// one after another, each a copy of the notes of its repeated stretch.
fn played_notes<'a>(clip: &'a Clip, notes: &'a Notes) -> Box<dyn Iterator<Item = Note> + 'a> {
    let Some((loop_start, period)) = clip.repeat() else {
        return Box::new(notes.iter().cloned());
    };
    let length = clip.length;
    Box::new(
        crate::sync::repeats(loop_start, period, length).flat_map(move |(a, _)| {
            notes
                .iter()
                .filter(move |n| n.start >= loop_start && n.start < loop_start + period)
                .map(move |n| Note { start: a + n.start - loop_start, ..n.clone() })
                .filter(move |n| n.start >= 0.0 && n.start < length)
        }),
    )
}

/// A lane of a nest's part as the song plays it: for each place of the
/// nest, its timing and its window `from..to` in song beats, the lane's
/// points inside the window at their song beats, with the value it plays
/// at each edge. The shapes of the curve inside a place move with it. The
/// lane as it is when the nest has no place, or the lane no points.
pub(crate) fn timed_lane(lane: &Lane, places: &[(Timing, f64, f64)]) -> Lane {
    if places.is_empty() || lane.points.is_empty() {
        return lane.clone();
    }
    let mut points = Vec::new();
    let mut shapes = Vec::new();
    for (timing, from, to) in places {
        let (a, b) = (timing.nest_beat(*from), timing.nest_beat(*to));
        if from.is_finite() {
            points.push((*from, lane.value_at(a)));
        }
        for &(beat, value) in lane.points.iter().filter(|p| p.0 > a && p.0 < b) {
            points.push((timing.song_beat(beat), value));
        }
        for s in lane.shapes.iter().filter(|s| s.beat > a && s.beat < b) {
            shapes.push(crate::model::Segment { beat: timing.song_beat(s.beat), ..*s });
        }
        if to.is_finite() {
            points.push((*to, lane.value_at(b)));
        }
    }
    points.sort_by(|x, y| x.0.total_cmp(&y.0));
    Lane { points, shapes, ..lane.clone() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{MASTER_ID, TempoChange};
    use serde_json::json;

    fn nest(tempo: NestTempo) -> Nest {
        Nest {
            id: super::super::NestId(1),
            name: "Cue".into(),
            length: 16.0,
            tempo,
            meter: NestMeter::Follow,
            master: MASTER_ID + 2,
            kind: None,
            meta: Default::default(),
            source: None,
            origin: None,
        }
    }

    fn own(bpm: f64) -> NestTempo {
        NestTempo::Own { points: vec![TempoChange { beat: 0.0, bpm, ramp: false }] }
    }

    /// 120 bpm, then a ritardando from beat 8 to 60 bpm at beat 16.
    fn ritardando() -> Arc<TempoMap> {
        Arc::new(TempoMap::new(
            &[
                TempoPoint { beat: 0.0, bpm: 120.0, ramp: false },
                TempoPoint { beat: 8.0, bpm: 120.0, ramp: true },
                TempoPoint { beat: 16.0, bpm: 60.0, ramp: false },
            ],
            &[SigPoint { beat: 0.0, num: 4, den: 4 }],
        ))
    }

    #[test]
    fn an_own_tempo_keeps_the_seconds_of_its_beats_under_a_ritardando_of_the_song() {
        let song = ritardando();
        let timing = nest(own(120.0)).timing(&song, None, 8.0, 0.0);
        for beat in [0.0, 1.0, 4.5, 7.0] {
            let seconds = song.seconds(timing.song_beat(beat)) - song.seconds(8.0);
            assert!((seconds - beat * 0.5).abs() < 1e-9, "beat {beat}: {seconds} s");
            assert!((timing.nest_beat(timing.song_beat(beat)) - beat).abs() < 1e-9, "back again");
        }
        let follows = nest(NestTempo::default()).timing(&song, None, 8.0, 0.0);
        assert_eq!(follows, Timing::Shift(8.0), "a nest that follows is a shift");
    }

    #[test]
    fn a_nest_that_follows_inside_an_own_one_takes_its_seconds() {
        let song = ritardando();
        let outer = nest(own(60.0)).timing(&song, None, 8.0, 0.0);
        // Placed at beat 2 of the outer nest, from its own beat 1.
        let inner = nest(NestTempo::default()).timing(&song, Some(&outer), 2.0, 1.0);
        assert!((inner.song_beat(3.0) - outer.song_beat(4.0)).abs() < 1e-9);
    }

    #[test]
    fn a_looped_clip_through_seconds_plays_its_repeats_as_notes() {
        let clip: Clip = serde_json::from_value(json!({ "id": 5, "name": "", "start": 0.0, "length": 4.0,
            "muted": false, "loop": true, "loop_length": 2.0, "content": { "kind": "midi", "controls": [],
            "notes": [ { "start": 0.0, "length": 1.0, "pitch": 60, "velocity": 100 } ] } }))
        .expect("a clip");
        let song = Arc::new(TempoMap::constant(60.0, 4, 4));
        // 120 inside, 60 in the song: a beat of the nest is half a beat of the song.
        let timing = nest(own(120.0)).timing(&song, None, 8.0, 0.0);
        let placed = timing.place_clip(&clip, f64::NEG_INFINITY, f64::INFINITY, 9).expect("placed");
        assert_eq!((placed.start, placed.length, placed.looped), (8.0, 2.0, false));
        let ClipContent::Midi { notes, .. } = &placed.content else { panic!("a MIDI clip") };
        let at: Vec<(f64, f64)> = notes.iter().map(|n| (n.start, n.length)).collect();
        assert_eq!(at, vec![(0.0, 0.5), (1.0, 0.5)]);
    }

    #[test]
    fn the_own_map_has_its_tempo_and_meter_or_none_when_it_follows_both() {
        let song = ritardando();
        assert!(nest(NestTempo::default()).own_map(&song, 4.0).is_none());
        let mut six = nest(NestTempo::default());
        six.meter = NestMeter::Own { changes: vec![crate::model::SigChange { beat: 0.0, num: 6, den: 8 }] };
        let map = six.own_map(&song, 4.0).expect("its own meter");
        assert_eq!((map.signature(0.0), map.bar_start(1)), ((6, 8), 3.0));
        assert!((map.seconds(6.0) - song.seconds_between(4.0, 10.0)).abs() < 1e-9, "the song's tempo from beat 4");
    }
}
