//! A project of its own made a nest of the song (`:import <folder>`;
//! `nest.md` 3.6, 4.3): the other way of `standalone.rs`.
//!
//! The nest refers to the project folder (`Nest::source`): the song keeps
//! no copy of it and reads it again when it opens. Its tracks, devices,
//! clips, lanes and the nests inside it take ids from the nest's own id
//! on (`id + 1 + the id in the folder`), so the same song and folder give
//! the same ids each time; a song clip that plays one track of the nest
//! (a stem) keeps naming it. The nests inside go along with the same
//! `source`: with the nest, they are one reference ([`Project::references`]),
//! and the first edit of any of them makes all of them the song's own.

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::path::Path;
use std::sync::Arc;

use serde_json::{Value, json};

use super::{Nest, NestId, NestMeter, NestPlay, NestTempo};
use crate::model::{Clip, ClipContent, Id, MASTER_ID, Project, SigChange, TempoChange, Target, Track};

/// The length of a nest from a project that plays nothing: 8 bars of its
/// meter.
const EMPTY_BARS: i64 = 8;

/// Every id that a part of `p` has: tracks, devices, clips, lanes, nests.
fn ids_of(p: &Project) -> impl Iterator<Item = Id> + '_ {
    p.all_tracks()
        .flat_map(|t| {
            std::iter::once(t.id)
                .chain(t.devices.iter().map(|d| d.id))
                .chain(t.clips.iter().chain(&t.cues).map(|c| c.id))
                .chain(t.lanes.iter().map(|l| l.id))
        })
        .chain(p.nests.keys().map(|n| n.0))
}

/// Add `by` to every id of `p` and to every reference to one: a track's
/// output, sends, group and VCAs, a device's side-chain and output pairs,
/// a lane's device, a nest clip's nest and track, and the nests' own.
fn shift_ids(p: &mut Project, by: Id) {
    let shift = |id: Id| id + by;
    let shift_list = |v: &mut Value| {
        if let Some(list) = v.as_array_mut() {
            for id in list.iter_mut() {
                if let Some(n) = id.as_u64() {
                    *id = json!(shift(n));
                }
            }
        }
    };
    for t in p.tracks.iter_mut().chain(std::iter::once(&mut p.master)) {
        let t = Arc::make_mut(t);
        t.id = shift(t.id);
        t.output = t.output.map(shift);
        t.nest = t.nest.map(|n| NestId(shift(n.0)));
        t.sends.iter_mut().for_each(|s| s.target = shift(s.target));
        if let Some(group) = t.meta.get("group").and_then(Value::as_u64) {
            t.meta.insert("group".into(), json!(shift(group)));
        }
        if let Some(vcas) = t.meta.get_mut("vcas") {
            shift_list(vcas);
        }
        for d in t.devices.iter_mut() {
            let d = Arc::make_mut(d);
            d.id = shift(d.id);
            d.sidechain = d.sidechain.map(shift);
            d.outputs.values_mut().for_each(|o| *o = shift(*o));
        }
        if let Some(graph) = &mut t.graph {
            Arc::make_mut(graph).map_ids(&mut |id| shift(id));
        }
        for l in t.lanes.iter_mut() {
            let l = Arc::make_mut(l);
            l.id = shift(l.id);
            if let Target::Param { device, .. } | Target::State { device } = &mut l.target {
                *device = shift(*device);
            }
        }
        for c in t.clips.iter_mut().chain(t.cues.iter_mut()) {
            let c = Arc::make_mut(c);
            c.id = shift(c.id);
            if let ClipContent::Nest { nest, play, .. } = &mut c.content {
                *nest = NestId(shift(nest.0));
                if let NestPlay::Track(track) = play {
                    *track = shift(*track);
                }
            }
        }
    }
    p.nests = std::mem::take(&mut p.nests)
        .into_values()
        .map(|n| {
            let mut n = (*n).clone();
            n.id = NestId(shift(n.id.0));
            n.master = shift(n.master);
            (n.id, Arc::new(n))
        })
        .collect();
}

/// The links of `part`'s clips that a link of `song` has the name of,
/// renamed `<name>-<nest>`: two links of one name would share their notes.
fn rename_links(part: &mut Project, song: &Project, nest: NestId) {
    let taken: HashSet<&str> = song
        .all_tracks()
        .flat_map(|t| t.clips.iter().chain(&t.cues))
        .filter_map(|c| c.link.as_deref())
        .collect();
    for t in part.tracks.iter_mut() {
        if !t.clips.iter().chain(&t.cues).any(|c| c.link.as_deref().is_some_and(|l| taken.contains(l))) {
            continue;
        }
        let t = Arc::make_mut(t);
        for c in t.clips.iter_mut().chain(t.cues.iter_mut()) {
            if c.link.as_deref().is_some_and(|l| taken.contains(l)) {
                let c = Arc::make_mut(c);
                c.link = c.link.take().map(|l| format!("{l}-{nest}"));
            }
        }
    }
}

/// How long a nest of `part` is: to the end of the bar where its last clip,
/// marker or region ends (an exported subproject keeps its regions), or 8
/// bars when it has none.
fn length_of(part: &Project) -> f64 {
    let map = part.tempo_map();
    let markers = part.meta.get("markers").and_then(Value::as_array).into_iter().flatten();
    let marked = markers
        .filter_map(|m| Some(m.get("beat")?.as_f64()? + m.get("length").and_then(Value::as_f64).unwrap_or(0.0)))
        .fold(0.0, f64::max);
    let end = part.end().max(marked);
    if end <= 0.0 {
        return map.bar_start(EMPTY_BARS);
    }
    let bar = map.bar_of(end - 1e-9) + 1;
    map.bar_start(bar)
}

impl Project {
    /// Make the project `part` (read from the folder `source`) nest `id`
    /// of this project, named `name`, as the module says: its tracks are
    /// the nest's, its master the nest's master, its markers, data and
    /// key the nest's. It follows the song's tempo and keeps its own in
    /// `kept`, and it keeps its own meter. Nothing places it yet. The
    /// caller checks the project after.
    pub(crate) fn adopt(&mut self, mut part: Project, id: NestId, name: &str, source: &Path) {
        part.refresh_tempo();
        // Its ids from the nest's on; past every id of the song when one
        // of those is taken (the folder has more parts than when it came),
        // and the song's stems of the nest follow.
        let natural = id.0 + 1;
        let used: BTreeSet<Id> = ids_of(self).collect();
        let base = if ids_of(&part).any(|i| used.contains(&(i + natural))) {
            used.last().copied().unwrap_or(0).max(id.0) + 1
        } else {
            natural
        };
        if base != natural {
            self.move_stems(id, natural, base);
        }
        shift_ids(&mut part, base);
        rename_links(&mut part, self, id);
        let master = base + MASTER_ID;
        let nest = Nest {
            id,
            name: name.to_string(),
            length: length_of(&part),
            tempo: NestTempo::Follow {
                kept: part
                    .tempo_points()
                    .into_iter()
                    .map(|p| TempoChange { beat: p.beat, bpm: p.bpm, ramp: p.ramp })
                    .collect(),
            },
            meter: NestMeter::Own {
                changes: part
                    .sig_points()
                    .into_iter()
                    .map(|s| SigChange { beat: s.beat, num: s.num, den: s.den })
                    .collect(),
            },
            master,
            kind: None,
            meta: {
                let mut meta = std::mem::take(&mut part.meta);
                // A subproject keeps its key in its meta; the song in `key`.
                if let Some(key) = part.key.take().filter(|k| Some(k) != self.key.as_ref()) {
                    meta.insert("key".into(), json!(key));
                }
                meta
            },
            source: Some(source.to_path_buf()),
            origin: None,
        };
        for t in part.tracks.iter_mut() {
            let t = Arc::make_mut(t);
            if t.nest.is_none() {
                t.nest = Some(id);
                // In a nest, no output is its master.
                t.output = t.output.filter(|o| *o != master);
            }
        }
        let mut mix: Track = (*part.master).clone();
        mix.nest = Some(id);
        mix.output = None;
        mix.sends.clear();
        self.tracks.extend(part.tracks);
        self.tracks.push(Arc::new(mix));
        for (inner, n) in part.nests {
            let n = Nest { source: Some(source.to_path_buf()), origin: None, ..(*n).clone() };
            self.nests.insert(inner, Arc::new(n));
        }
        self.nests.insert(id, Arc::new(nest));
    }

    /// The song's clips that play one track of nest `id`: the tracks that
    /// were numbered from `from` are now numbered from `to`.
    fn move_stems(&mut self, id: NestId, from: Id, to: Id) {
        for t in self.tracks.iter_mut() {
            let stems = |c: &Clip| {
                matches!(c.content, ClipContent::Nest { nest, play: NestPlay::Track(_), .. } if nest == id)
            };
            if !t.clips.iter().any(|c| stems(c)) {
                continue;
            }
            for c in Arc::make_mut(t).clips.iter_mut() {
                if let ClipContent::Nest { nest, play: NestPlay::Track(track), .. } = &mut Arc::make_mut(c).content
                    && *nest == id
                    && *track >= from
                {
                    *track = *track - from + to;
                }
            }
        }
    }

    /// The nests that refer to a folder outside the project, each with
    /// the nests that came with it: by the one the others are inside
    /// (its reference's top), the nests of its reference, itself
    /// included. A nest inside is one of the same `source` that a nest of
    /// the reference places.
    pub(crate) fn references(&self) -> BTreeMap<NestId, BTreeSet<NestId>> {
        let held = self.nests_held();
        let source_of = |id: &NestId| self.nest(*id).and_then(|n| n.source.as_ref());
        // A nest of a reference that a nest of the same reference places
        // is not a top.
        let inner: BTreeSet<NestId> = held
            .iter()
            .filter_map(|(place, nests)| Some((source_of(place.as_ref()?)?, nests)))
            .flat_map(|(source, nests)| nests.iter().filter(move |n| source_of(n) == Some(source)).copied())
            .collect();
        let mut out = BTreeMap::new();
        for (id, nest) in &self.nests {
            let Some(source) = &nest.source else {
                continue;
            };
            if inner.contains(id) {
                continue;
            }
            let mut group = BTreeSet::new();
            let mut stack = vec![*id];
            while let Some(at) = stack.pop() {
                if group.insert(at) {
                    let below = held.get(&Some(at)).into_iter().flatten();
                    stack.extend(below.filter(|n| source_of(n) == Some(source)).copied());
                }
            }
            out.insert(*id, group);
        }
        out
    }

    /// Make the nests `group` (a reference, as [`Project::references`]
    /// gives it) the project's own: each keeps where it came from in
    /// `origin`.
    pub(crate) fn own_reference(&mut self, group: &BTreeSet<NestId>) {
        for id in group {
            if let Some(nest) = self.nest_mut(*id)
                && nest.source.is_some()
            {
                nest.origin = nest.source.take();
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::nest::tests::{add_nest, nest_clip, song};
    use crate::model::Send;
    use std::path::PathBuf;

    /// A project of its own: Keys and Verb (Keys sends to Verb) and a
    /// nest Fill inside, at 90 bpm in 3/4.
    fn library() -> Project {
        let mut p = Project::default();
        let mut keys = Track::new(1);
        keys.name = "Keys".into();
        keys.sends.push(Send { target: 2, level: -6.0, pre: false });
        keys.clips.push(nest_clip(3, 10, 0.0, json!("master")));
        let mut verb = Track::new(2);
        verb.name = "Verb".into();
        p.tracks.push(Arc::new(keys));
        p.tracks.push(Arc::new(verb));
        add_nest(&mut p, 10, "Fill", Vec::new());
        p.tempo = 90.0;
        (p.sig_num, p.sig_den) = (3, 4);
        p.refresh_tempo();
        p.validate().expect("a valid library project");
        p
    }

    #[test]
    fn a_project_becomes_a_nest_with_ids_from_its_own_and_its_routes_inside() {
        let mut p = song(50);
        let folder = PathBuf::from("/lib/bridge");
        p.adopt(library(), NestId(50), "Bridge", &folder);
        p.validate().expect("a valid song");
        let nest = p.nest(NestId(50)).expect("Bridge");
        assert_eq!(nest.master, 51, "the master is the folder's 0 from the nest's id on");
        assert_eq!(nest.source.as_deref(), Some(folder.as_path()));
        assert_eq!(nest.meter, NestMeter::Own { changes: vec![SigChange { beat: 0.0, num: 3, den: 4 }] });
        assert!(matches!(&nest.tempo, NestTempo::Follow { kept } if kept[0].bpm == 90.0));
        let keys = p.track(52).expect("Keys is the folder's 1");
        assert_eq!((keys.nest, keys.sends[0].target), (Some(NestId(50)), 53), "its send follows Verb");
        let fill = p.nest(NestId(61)).expect("Fill is the folder's 10");
        assert_eq!(fill.source.as_deref(), Some(folder.as_path()), "the nest inside came with it");
        assert_eq!(p.references(), BTreeMap::from([(NestId(50), BTreeSet::from([NestId(50), NestId(61)]))]));
    }

    #[test]
    fn a_folder_that_grew_into_the_songs_ids_takes_ids_after_them_and_the_stems_follow() {
        let mut p = song(50);
        // The song plays Keys (the folder's 1) as a stem, and took id 53.
        Arc::make_mut(&mut p.tracks[0]).clips.push(nest_clip(53, 50, 0.0, json!({ "track": 52 })));
        p.adopt(library(), NestId(50), "Bridge", Path::new("/lib/bridge"));
        p.validate().expect("a valid song");
        let stem = p.clip(53).expect("the stem");
        let ClipContent::Nest { play: NestPlay::Track(track), .. } = stem.content else {
            panic!("a stem");
        };
        assert_eq!(p.track(track).map(|t| t.name.as_str()), Some("Keys"), "the stem still plays Keys");
    }

    #[test]
    fn owning_a_reference_owns_the_nests_inside_and_keeps_the_path() {
        let mut p = song(50);
        p.adopt(library(), NestId(50), "Bridge", Path::new("/lib/bridge"));
        let group = p.references()[&NestId(50)].clone();
        p.own_reference(&group);
        assert!(p.references().is_empty());
        for id in group {
            let nest = p.nest(id).expect("a nest");
            assert_eq!((nest.source.as_deref(), nest.origin.as_deref()), (None, Some(Path::new("/lib/bridge"))));
        }
    }
}
