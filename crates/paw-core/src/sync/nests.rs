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

use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::Arc;

use rustc_hash::FxHasher;

use crate::model::{Clip, ClipContent, Clips, Id, NestId, NestPlay, Note, Notes, Project, Track};

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
}

impl Instance {
    /// The song's beat of a beat of the nest.
    pub fn song_beat(&self, beat: f64) -> f64 {
        self.zero + beat
    }
}

/// The instances of every nest the song plays, by nest, in the order of
/// their places; and the track each nest's master plays into: the track
/// of its first clip that plays its mix.
#[derive(Default)]
pub(crate) struct Placed {
    pub instances: HashMap<NestId, Vec<Instance>>,
    pub hosts: HashMap<NestId, Id>,
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
                    if *play == NestPlay::Master {
                        placed.hosts.entry(*nest).or_insert(t.id);
                    }
                }
            }
        }
        // From the song down, at most as deep as the model allows.
        let song = Instance { key: 0, from: f64::NEG_INFINITY, to: f64::INFINITY, zero: 0.0 };
        let mut stack: Vec<(Option<NestId>, Instance, usize)> = vec![(None, song, 0)];
        while let Some((place, outer, depth)) = stack.pop() {
            if depth > crate::model::MAX_DEPTH {
                continue;
            }
            for (_, c) in clips.get(&place).into_iter().flatten() {
                let ClipContent::Nest { nest, offset, .. } = &c.content else {
                    continue;
                };
                if c.muted {
                    continue;
                }
                let start = outer.song_beat(c.start);
                let from = start.max(outer.from);
                let to = (start + c.length).min(outer.to);
                if to <= from {
                    continue;
                }
                let mut hash = FxHasher::default();
                (outer.key, c.id).hash(&mut hash);
                let inner = Instance { key: hash.finish(), from, to, zero: start - offset };
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
        let instances = placed.instances.get(&nest).unwrap_or(&none);
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
        let track = Arc::new(Track {
            clips,
            cues: Clips::new(),
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
/// window. None when nothing of it is inside the window, or when it is cut
/// at its start and cannot be (a looped clip, a custom clip's sound).
fn place(clip: &Clip, instance: &Instance, id: Id) -> Option<Clip> {
    if matches!(clip.content, ClipContent::Nest { .. }) {
        return None;
    }
    let start = instance.song_beat(clip.start);
    let end = (start + clip.length).min(instance.to);
    let from = start.max(instance.from);
    if end <= from {
        return None;
    }
    let mut copy = Clip {
        id,
        start: from,
        length: end - from,
        ..clip.clone()
    };
    let cut = from - start;
    if cut > 1e-9 {
        if clip.looped {
            return None;
        }
        copy.content = match &clip.content {
            ClipContent::Midi { notes, controls } => {
                let notes: Notes = notes
                    .iter()
                    .filter(|n| n.start >= cut)
                    .map(|n| Note { start: n.start - cut, ..n.clone() })
                    .collect();
                let controls = controls
                    .iter()
                    .filter(|c| c.start >= cut)
                    .map(|c| crate::model::Control { start: c.start - cut, ..c.clone() })
                    .collect();
                ClipContent::Midi { notes, controls }
            }
            // The rest of the sound from the cut on: the clip's start moves,
            // and its offset follows in seconds at the tempo there.
            ClipContent::Audio { .. } => return None,
            _ => return None,
        };
    }
    Some(copy)
}
