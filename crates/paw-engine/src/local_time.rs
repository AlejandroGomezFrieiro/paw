//! A track's own time: where a subproject's track plays in the song, and
//! the transport that the devices on it see.

use paw_types::{SigPoint, TempoMap, TempoPoint, tempo::EPS};

use crate::device::ProcessCtx;

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
/// song's tempo there or its own. Made on the main thread; reading it on
/// the audio thread allocates nothing.
#[derive(Clone, Debug)]
pub struct LocalTime {
    /// By `from`.
    places: Box<[Place]>,
    /// Its own meter, in its own beats; `None` for the song's meter where
    /// it plays.
    meter: Option<TempoMap>,
    /// With a tempo of its own, its meter holds that tempo too: its
    /// position is the beat of `meter` at its seconds from the place's
    /// beat 0, not a shift of the song's beat.
    own_tempo: bool,
}

impl LocalTime {
    /// A track's time from its places (in any order) and its own meter
    /// (`sigs` in its own beats, the first at 0), or the song's when
    /// `sigs` is empty.
    pub fn new(mut places: Vec<Place>, sigs: &[SigPoint]) -> Self {
        places.sort_by(|a, b| a.from.total_cmp(&b.from));
        let tempo = [TempoPoint { beat: 0.0, bpm: 120.0, ramp: false }];
        let meter = (!sigs.is_empty()).then(|| TempoMap::new(&tempo, sigs));
        Self { places: places.into(), meter, own_tempo: false }
    }

    /// The same time with a tempo of its own (`tempos` in its own beats,
    /// the first at 0); empty `tempos` change nothing. Its meter is the
    /// first signature of the song when it has none of its own.
    pub fn with_tempo(mut self, tempos: &[TempoPoint]) -> Self {
        if tempos.is_empty() {
            return self;
        }
        let sigs: Vec<SigPoint> = match &self.meter {
            Some(m) => m.signatures().collect(),
            None => vec![SigPoint { beat: 0.0, num: 4, den: 4 }],
        };
        self.meter = Some(TempoMap::new(tempos, &sigs));
        self.own_tempo = true;
        self
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
    pub fn context(&self, song: &ProcessCtx, map: &TempoMap) -> ProcessCtx {
        let Some(place) = self.place_at(song.position) else {
            return *song;
        };
        let seconds = song.seconds - map.seconds(place.zero);
        let (position, tempo) = match &self.meter {
            Some(own) if self.own_tempo => {
                let position = own.beat(seconds);
                (position, own.tempo(position))
            }
            _ => (song.position - place.zero, song.tempo),
        };
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
        ProcessCtx {
            tempo,
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
