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
        let song = Instance { key: 0, from: f64::NEG_INFINITY, to: f64::INFINITY, zero: 0.0, only: None };
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
                let inner = Instance { key: hash.finish(), from, to, zero: start - offset, only };
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

/// A nest track as the engine plays it, and what it was made from.
pub(crate) struct Expanded {
    source: Arc<Track>,
    instances: Vec<Instance>,
    pub track: Arc<Track>,
    /// Each copy by its id: the clip and the instance it was made from.
    copies: HashMap<Id, (Arc<Clip>, Instance, Arc<Clip>)>,
}

/// The nest tracks as the engine plays them, by track id. What is the same
/// as at the last sync is the very same `Arc`, so that the sync sends only
/// what changed.
pub(crate) type ExpandedTracks = HashMap<Id, Expanded>;

/// Every nest track of `project`, expanded, reusing what `old` has.
pub(crate) fn expand(project: &Project, placed: &Placed, mut old: ExpandedTracks) -> ExpandedTracks {
    let mut out = HashMap::new();
    if project.nests.is_empty() {
        return out;
    }
    let none = Vec::new();
    for t in project.tracks.iter().filter(|t| t.nest.is_some()) {
        let nest = t.nest.expect("a nest track");
        let instances: Vec<Instance> = placed
            .instances
            .get(&nest)
            .unwrap_or(&none)
            .iter()
            .filter(|i| i.plays(t.id))
            .copied()
            .collect();
        let instances = &instances;
        let was = match old.remove(&t.id) {
            Some(w) if Arc::ptr_eq(&w.source, t) && w.instances == *instances => {
                out.insert(t.id, w);
                continue;
            }
            was => was,
        };
        let was = was.as_ref();
        let mut copies = HashMap::new();
        let mut list: Vec<Arc<Clip>> = Vec::new();
        for instance in instances {
            for clip in t.clips.iter() {
                let id = copy_id(instance, clip.id);
                let reused = was
                    .and_then(|w| w.copies.get(&id))
                    .filter(|(source, at, _)| Arc::ptr_eq(source, clip) && at == instance)
                    .map(|(_, _, copy)| copy.clone());
                let Some(copy) = reused.or_else(|| place(clip, instance, id).map(Arc::new)) else {
                    continue;
                };
                list.push(copy.clone());
                copies.insert(id, (clip.clone(), *instance, copy));
            }
        }
        list.sort_by(|a, b| a.start.total_cmp(&b.start).then(a.id.cmp(&b.id)));
        let mut clips = Clips::new();
        clips.extend(list);
        // Its lanes play where its clips do, at each place of the nest.
        let places: Vec<(f64, f64, f64)> = instances.iter().map(|i| (i.zero, i.from, i.to)).collect();
        let lanes = t
            .lanes
            .iter()
            .map(|l| Arc::new(crate::model::nest::placed_lane(l, &places)))
            .collect();
        let track = Arc::new(Track {
            clips,
            cues: Clips::new(),
            lanes,
            ..(**t).clone()
        });
        out.insert(
            t.id,
            Expanded { source: t.clone(), instances: instances.clone(), track, copies },
        );
    }
    out
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
