//! Subprojects (nests) as the engine plays them: the chain mode of
//! `nest.md` 4.4.
//!
//! A nest's tracks keep their clips in the nest's own beats. The engine
//! plays each nest track as one engine track whose clips are placed in the
//! song: for each instance of the nest (a nest clip, and through it every
//! nest clip inside), a copy of each clip at `instance start + clip start -
//! instance offset`, cut at the instance's window. The copies share their
//! notes with the clip, so an edit inside the nest compiles once however
//! many instances play it (the cache of `clips.rs`). A muted instance places
//! nothing; what the nest's devices already play rings on.
//!
//! The nest's tracks play into its master (or where they route inside the
//! nest), and its master plays into the track that holds its clips: the
//! return row (`routing.rs`). A nest placed on two rows plays into the
//! first; its devices run once.
//!
//! A nest clip that plays one track (`NestPlay::Track`, a stem) places
//! only that track, and the track plays into the clip's row instead of
//! into the master (`:nest.outputs stems`).
//!
//! The pass mode of `nest.md` 4.4: a nest track that has no sound of its
//! own (no devices, its fader and pan at the middle, no lanes, not muted)
//! is no engine track for the clips that play it alone. Its clips, placed
//! and cut as above, become clips of the row that the nest clip is on, and
//! play through the devices, fader, sends and lanes of that row, as clips
//! put there would (`<Space>zw` saves a view so, and the song sounds the
//! same). Through the master, such a track still plays as an engine track.

use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use rustc_hash::FxHasher;

use crate::model::{Clip, ClipContent, Clips, Id, NestId, NestPlay, Project, Track};

/// Where a nest plays in the song: one nest clip (or a chain of them, for a
/// nest inside a nest), as song beats.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Instance {
    /// Tells the instance apart: the clip, and the instances it is in.
    pub key: u64,
    /// The song's beat where the window starts and ends.
    pub from: f64,
    pub to: f64,
    /// The song's beat of the nest's beat 0.
    pub zero: f64,
    /// The one track of the nest that this instance plays (a stem), or
    /// None for all of them.
    pub only: Option<Id>,
    /// The track that holds the nest clip (the song's or a nest's).
    pub row: Id,
}

impl Instance {
    /// The song's beat of a beat of the nest.
    pub fn song_beat(&self, beat: f64) -> f64 {
        self.zero + beat
    }

    /// Whether this instance plays track `track` of its nest.
    pub fn plays(&self, track: Id) -> bool {
        self.only.is_none_or(|only| only == track)
    }
}

/// The instances of every nest the song plays, by nest, in the order of
/// their places; the track each nest's master plays into: the track of its
/// first clip that plays its mix; and the row each stem plays into: the
/// track of the first clip that plays that one track.
#[derive(Default)]
pub(crate) struct Placed {
    pub instances: HashMap<NestId, Vec<Instance>>,
    pub hosts: HashMap<NestId, Id>,
    pub stems: HashMap<Id, Id>,
}

impl Placed {
    pub fn of(project: &Project) -> Self {
        let mut placed = Self::default();
        if project.nests.is_empty() {
            return placed;
        }
        // The clips of each place: the song's (None) or a nest's.
        let mut clips: HashMap<Option<NestId>, Vec<(&Track, &Arc<Clip>)>> = HashMap::new();
        for t in project.all_tracks() {
            for c in t.clips.iter() {
                if let ClipContent::Nest { nest, play, .. } = &c.content {
                    clips.entry(t.nest).or_default().push((t, c));
                    match play {
                        NestPlay::Master => {
                            placed.hosts.entry(*nest).or_insert(t.id);
                        }
                        NestPlay::Track(stem) => {
                            placed.stems.entry(*stem).or_insert(t.id);
                        }
                    }
                }
            }
        }
        // From the song down, at most as deep as the model allows.
        let song = Instance {
            key: 0,
            from: f64::NEG_INFINITY,
            to: f64::INFINITY,
            zero: 0.0,
            only: None,
            row: crate::model::MASTER_ID,
        };
        let mut stack: Vec<(Option<NestId>, Instance, usize)> = vec![(None, song, 0)];
        while let Some((place, outer, depth)) = stack.pop() {
            if depth > crate::model::MAX_DEPTH {
                continue;
            }
            for (t, c) in clips.get(&place).into_iter().flatten() {
                let ClipContent::Nest { nest, offset, play } = &c.content else {
                    continue;
                };
                // A stem of the outer nest plays the nests of that track only.
                if c.muted || !outer.plays(t.id) {
                    continue;
                }
                let only = match play {
                    NestPlay::Track(stem) => Some(*stem),
                    NestPlay::Master => None,
                };
                let start = outer.song_beat(c.start);
                let from = start.max(outer.from);
                let to = (start + c.length).min(outer.to);
                if to <= from {
                    continue;
                }
                let mut hash = FxHasher::default();
                (outer.key, c.id).hash(&mut hash);
                let inner = Instance { key: hash.finish(), from, to, zero: start - offset, only, row: t.id };
                placed.instances.entry(*nest).or_default().push(inner);
                stack.push((Some(*nest), inner, depth + 1));
            }
        }
        for list in placed.instances.values_mut() {
            list.sort_by(|a, b| a.from.total_cmp(&b.from).then(a.key.cmp(&b.key)));
        }
        placed
    }
}

/// The time the devices of a nest's track see: where each block of the
/// nest that plays the track is, and the nest's own meter (empty: the
/// song's).
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Local {
    places: Vec<paw_engine::Place>,
    meter: Vec<paw_engine::SigPoint>,
}

impl Local {
    /// The time of track `track` of nest `nest`, or None when the nest is
    /// not there.
    pub fn of(project: &Project, nest: NestId, track: Id, placed: &Placed) -> Option<Self> {
        let held = project.nest(nest)?;
        let places = placed
            .instances
            .get(&nest)
            .into_iter()
            .flatten()
            .filter(|i| i.plays(track))
            .map(|i| paw_engine::Place { from: i.from, to: i.to, zero: i.zero })
            .collect();
        let meter = match &held.meter {
            crate::model::NestMeter::Own { changes } => changes
                .iter()
                .map(|c| paw_engine::SigPoint { beat: c.beat, num: c.num, den: c.den })
                .collect(),
            crate::model::NestMeter::Follow => Vec::new(),
        };
        Some(Self { places, meter })
    }

    /// As the engine takes it.
    pub fn time(&self) -> paw_engine::LocalTime {
        paw_engine::LocalTime::new(self.places.clone(), &self.meter)
    }
}

/// Whether a nest track has no sound of its own, so that a clip that plays
/// it alone places its clips on the row of that clip (the pass mode).
pub(crate) fn passes(t: &Track) -> bool {
    t.devices.is_empty() && t.volume == 0.0 && t.pan == 0.0 && t.lanes.is_empty() && !t.mute
}

/// Clips that a track plays: those of `track` at each of `places`, or, with
/// no places, as they are (the own clips of a song track).
struct Source {
    track: Arc<Track>,
    places: Option<Vec<Instance>>,
}

impl Source {
    fn same(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.track, &other.track) && self.places == other.places
    }
}

/// A track as the engine plays it, and what it was made from: a nest track
/// placed at each place of its nest, and a row with the clips of the
/// tracks in pass mode that it holds blocks of.
pub(crate) struct Expanded {
    sources: Vec<Source>,
    pub track: Arc<Track>,
    /// Each copy by its id: the clip and the instance it was made from.
    copies: HashMap<Id, (Arc<Clip>, Instance, Arc<Clip>)>,
}

/// The tracks that the engine plays otherwise than the project has them,
/// by track id. What is the same as at the last sync is the very same
/// `Arc`, so that the sync sends only what changed.
pub(crate) type ExpandedTracks = HashMap<Id, Expanded>;

/// Every nest track of `project`, and every row that holds a block of a
/// track in pass mode, expanded, reusing what `old` has.
pub(crate) fn expand(project: &Project, placed: &Placed, mut old: ExpandedTracks) -> ExpandedTracks {
    let mut out = HashMap::new();
    if project.nests.is_empty() {
        return out;
    }
    let none = Vec::new();
    let mut tracks: Vec<(&Arc<Track>, Vec<Source>)> = Vec::new();
    // The clips of tracks in pass mode, by the row they play on.
    let mut hosted: HashMap<Id, Vec<Source>> = HashMap::new();
    for t in project.tracks.iter().filter(|t| t.nest.is_some()) {
        let nest = t.nest.expect("a nest track");
        let pass = passes(t);
        let mut own = Vec::new();
        for i in placed.instances.get(&nest).unwrap_or(&none).iter().filter(|i| i.plays(t.id)) {
            if !(pass && i.only == Some(t.id)) {
                own.push(*i);
                continue;
            }
            let list = hosted.entry(i.row).or_default();
            match list.iter_mut().find(|s| Arc::ptr_eq(&s.track, t)) {
                Some(s) => s.places.get_or_insert_with(Vec::new).push(*i),
                None => list.push(Source { track: t.clone(), places: Some(vec![*i]) }),
            }
        }
        tracks.push((t, vec![Source { track: t.clone(), places: Some(own) }]));
    }
    for (t, list) in &mut tracks {
        list.extend(hosted.remove(&t.id).unwrap_or_default());
    }
    for t in project.tracks.iter().filter(|t| t.nest.is_none()) {
        if let Some(more) = hosted.remove(&t.id) {
            let mut list = vec![Source { track: t.clone(), places: None }];
            list.extend(more);
            tracks.push((t, list));
        }
    }
    for (t, sources) in tracks {
        let was = match old.remove(&t.id) {
            Some(w) if w.sources.len() == sources.len() && w.sources.iter().zip(&sources).all(|(a, b)| a.same(b)) => {
                out.insert(t.id, w);
                continue;
            }
            was => was,
        };
        out.insert(t.id, build(t, sources, was.as_ref()));
    }
    out
}

/// One track as the engine plays it, from its sources (see [`Expanded`]).
fn build(t: &Arc<Track>, sources: Vec<Source>, was: Option<&Expanded>) -> Expanded {
    let mut copies = HashMap::new();
    let mut list: Vec<Arc<Clip>> = Vec::new();
    for source in &sources {
        let Some(places) = &source.places else {
            list.extend(source.track.clips.iter().cloned());
            continue;
        };
        for instance in places {
            for clip in source.track.clips.iter() {
                let id = copy_id(instance, clip.id);
                let reused = was
                    .and_then(|w| w.copies.get(&id))
                    .filter(|(from, at, _)| Arc::ptr_eq(from, clip) && at == instance)
                    .map(|(_, _, copy)| copy.clone());
                let Some(copy) = reused.or_else(|| place(clip, instance, id).map(Arc::new)) else {
                    continue;
                };
                list.push(copy.clone());
                copies.insert(id, (clip.clone(), *instance, copy));
            }
        }
    }
    list.sort_by(|a, b| a.start.total_cmp(&b.start).then(a.id.cmp(&b.id)));
    let mut clips = Clips::new();
    clips.extend(list);
    // A nest track's lanes play where its clips do, at each place of its
    // nest; a song track's are its own.
    let lanes = match (&sources[0].places, t.nest) {
        (Some(own), Some(_)) => {
            let places: Vec<(f64, f64, f64)> = own.iter().map(|i| (i.zero, i.from, i.to)).collect();
            t.lanes
                .iter()
                .map(|l| Arc::new(crate::model::nest::placed_lane(l, &places)))
                .collect()
        }
        _ => t.lanes.clone(),
    };
    let track = Arc::new(Track {
        clips,
        cues: Clips::new(),
        lanes,
        ..(**t).clone()
    });
    Expanded { sources, track, copies }
}

/// The id of the copy of clip `clip` that an instance plays: apart from
/// every clip of the project (the top bit is set, which ids never have).
fn copy_id(instance: &Instance, clip: Id) -> Id {
    let mut hash = FxHasher::default();
    (instance.key, clip).hash(&mut hash);
    hash.finish() | (1 << 63)
}

/// A clip of a nest track placed in the song for one instance, cut at its
/// window (see [`crate::model::nest::placed_clip`]).
fn place(clip: &Clip, instance: &Instance, id: Id) -> Option<Clip> {
    if matches!(clip.content, ClipContent::Nest { .. }) {
        return None;
    }
    crate::model::nest::placed_clip(clip, instance.zero, instance.from, instance.to, id)
}
