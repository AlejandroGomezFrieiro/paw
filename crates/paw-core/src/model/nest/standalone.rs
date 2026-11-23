//! A nest, or a view of tracks over a time, as a project of its own
//! (`:export project <folder>/` in its window; `nest.md` 3.6, 4.3).
//!
//! The project that this module makes is a copy: the song does not change.
//! Its tempo and meter are the map of the place where the nest or the view
//! plays, from its start: a nest that follows the song's tempo or meter
//! gets the song's map from its first block, so that it plays as it plays
//! there. The nests inside go along as nests. The session writes the
//! project to a folder (`session/export.rs`).

use std::collections::{BTreeSet, HashSet};
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use paw_engine::{SigPoint, TempoMap, TempoPoint};
use serde_json::{Map, Value};

use super::time::song_tempos_from;
use super::{Nest, NestId, NestMeter, NestTempo, placed_clip, placed_lane};
use crate::model::{ClipContent, Id, MASTER_ID, Project, Track};

/// Two beats closer than this are one.
const EPS: f64 = 1e-9;

/// A project made of a part of another, and what changed on the way.
#[derive(Debug)]
pub struct Standalone {
    pub project: Project,
    /// The routes that pointed out of the part and were cut, in words.
    pub changes: Vec<String>,
}

/// The tempo and meter of `map` from its beat `zero` for `length` beats,
/// as a map that starts at beat 0. A change at or after the end is left out.
fn map_over(map: &TempoMap, zero: f64, length: f64) -> TempoMap {
    let mut tempos = song_tempos_from(map, zero);
    tempos.retain(|p| p.beat < length - EPS);
    TempoMap::new(&tempos, &signatures_over(map, zero, length))
}

/// The meter of `map` from its beat `zero` for `length` beats, from beat 0.
fn signatures_over(map: &TempoMap, zero: f64, length: f64) -> Vec<SigPoint> {
    let (num, den) = map.signature(zero);
    let mut sigs = vec![SigPoint { beat: 0.0, num, den }];
    sigs.extend(
        map.signatures()
            .filter(|s| s.beat > zero + EPS && s.beat < zero + length - EPS)
            .map(|s| SigPoint { beat: s.beat - zero, ..s }),
    );
    sigs
}

/// The markers and regions of `meta.markers` that fit in `from..to`,
/// moved so that `from` is beat 0. None when none fits.
fn markers_over(meta: &Map<String, Value>, from: f64, to: f64) -> Option<Value> {
    let markers = meta.get("markers")?.as_array()?;
    let fits = |m: &Value| {
        let beat = m.get("beat").and_then(Value::as_f64).unwrap_or(f64::NAN);
        let end = beat + m.get("length").and_then(Value::as_f64).unwrap_or(0.0);
        beat >= from - EPS && beat < to - EPS && end <= to + EPS
    };
    let kept: Vec<Value> = markers
        .iter()
        .filter(|m| fits(m))
        .map(|m| {
            let mut m = m.clone();
            let beat = m["beat"].as_f64().unwrap_or(0.0) - from;
            m["beat"] = Value::from(beat);
            m
        })
        .collect();
    (!kept.is_empty()).then_some(Value::Array(kept))
}

/// The key that a subproject's meta gives (`meta.key`, as `paw.harmony`
/// names it), taken out of the meta. None when it has none.
fn key_of(meta: &mut Map<String, Value>) -> Option<String> {
    match meta.remove("key") {
        Some(Value::String(key)) if !key.is_empty() => Some(key),
        _ => None,
    }
}

impl Project {
    /// The map of the place `place`: the song's, or the map of the nest
    /// as it plays where it plays first.
    fn place_map(&self, place: Option<NestId>) -> TempoMap {
        match place.and_then(|id| self.nest(id)) {
            Some(nest) => self.played_map(nest),
            None => (**self.tempo_map()).clone(),
        }
    }

    /// The first block of nest `id`: the place that holds it and the beat
    /// of that place where the nest's beat 0 is. A block of the song comes
    /// before a block inside another nest; then the earliest.
    fn first_block(&self, id: NestId) -> Option<(Option<NestId>, f64)> {
        self.all_tracks()
            .flat_map(|t| t.clips.iter().map(move |c| (t.nest, c)))
            .filter_map(|(place, c)| match &c.content {
                ClipContent::Nest { nest, offset, .. } if *nest == id => Some((place, c.start - offset)),
                _ => None,
            })
            .min_by(|a, b| a.0.is_some().cmp(&b.0.is_some()).then(a.1.total_cmp(&b.1)))
    }

    /// The map of a nest as its first block plays it, from its beat 0: its
    /// own tempo and meter, or those of the place there. A nest that no
    /// block places takes the song's from its start, or the tempo it kept.
    fn played_map(&self, nest: &Nest) -> TempoMap {
        let first = self.first_block(nest.id);
        let (place, zero) = first.unwrap_or((None, 0.0));
        // The graph has no cycle (`check_graph`): the place is a nest above.
        let around = self.place_map(place);
        let tempos: Vec<TempoPoint> = match &nest.tempo {
            NestTempo::Own { .. } => nest.own_tempos(),
            NestTempo::Follow { kept } if first.is_none() && !kept.is_empty() => {
                kept.iter().map(|c| TempoPoint { beat: c.beat, bpm: c.bpm, ramp: c.ramp }).collect()
            }
            NestTempo::Follow { .. } => song_tempos_from(&around, zero),
        };
        let sigs: Vec<SigPoint> = match &nest.meter {
            NestMeter::Own { changes } => {
                changes.iter().map(|c| SigPoint { beat: c.beat, num: c.num, den: c.den }).collect()
            }
            NestMeter::Follow => signatures_over(&around, zero, nest.length),
        };
        TempoMap::new(&tempos, &sigs)
    }

    /// The nests that the clips of `tracks` place, and the nests inside
    /// those, all the way down.
    fn nests_below<'a>(&self, tracks: impl IntoIterator<Item = &'a Track>) -> BTreeSet<NestId> {
        let held = self.nests_held();
        let mut stack: Vec<NestId> = tracks
            .into_iter()
            .flat_map(|t| t.clips.iter().chain(&t.cues))
            .filter_map(|c| match &c.content {
                ClipContent::Nest { nest, .. } => Some(*nest),
                _ => None,
            })
            .collect();
        let mut out = BTreeSet::new();
        while let Some(id) = stack.pop() {
            if out.insert(id) {
                stack.extend(held.get(&Some(id)).into_iter().flatten().copied());
            }
        }
        out
    }

    /// A project of `tracks` (now the song's) with `master`, the nests
    /// that they place, and the tempo and meter of `map`.
    fn made_of(&self, name: &str, master: Track, tracks: Vec<Track>, map: TempoMap) -> Project {
        let inner = self.nests_below(&tracks);
        let mut out = Project { name: name.to_string(), master: Arc::new(master), ..Project::default() };
        out.tracks = tracks.into_iter().map(Arc::new).collect();
        out.tracks.extend(
            self.tracks
                .iter()
                .filter(|t| t.nest.is_some_and(|n| inner.contains(&n)))
                .cloned(),
        );
        out.nests = inner.iter().filter_map(|id| Some((*id, self.nest(*id)?.clone()))).collect();
        out.set_tempo_map(map);
        out
    }

    /// Nest `id` as a project of its own: its tracks are the song's, its
    /// master the master, its markers and data the project's, its key
    /// (`meta.key`) the project's key, and its tempo and meter as its
    /// first block plays them. The nests inside it stay nests.
    pub fn nest_standalone(&self, id: NestId) -> Result<Standalone> {
        let nest = self.nest(id).with_context(|| format!("no subproject {id}"))?;
        let from_master = |to: Id| if to == nest.master { MASTER_ID } else { to };
        let tracks: Vec<Track> = self
            .nest_tracks(id)
            .filter(|t| t.id != nest.master)
            .map(|t| {
                let mut t = (**t).clone();
                t.nest = None;
                t.output = t.output.map(from_master).filter(|o| *o != MASTER_ID);
                t.sends.iter_mut().for_each(|s| s.target = from_master(s.target));
                t
            })
            .collect();
        let mut master = (**self.track(nest.master).context("its master track is gone")?).clone();
        master.id = MASTER_ID;
        master.nest = None;
        let map = map_over(&self.played_map(nest), 0.0, nest.length);
        let mut project = self.made_of(&nest.name, master, tracks, map);
        project.meta = nest.meta.clone();
        project.key = key_of(&mut project.meta).or_else(|| self.key.clone());
        project.validate()?;
        Ok(Standalone { project, changes: Vec::new() })
    }

    /// The tracks `tracks` (of one place) from beat `from` to `to` of that
    /// place as a project named `name`: copies of the tracks with their
    /// devices, their clips and lanes in the time from beat 0, the markers
    /// and regions that fit in the time, the tempo and meter of the time,
    /// and a master with no devices. A route to a track that is not in the
    /// view is cut, and each cut is told. A clip that crosses an edge and
    /// cannot be cut there is an error.
    pub fn view_standalone(&self, name: &str, tracks: &[Id], from: f64, to: f64) -> Result<Standalone> {
        if !(from.is_finite() && to.is_finite() && to - from > EPS) {
            bail!("the view has no time to write");
        }
        let place = self.view_place(tracks)?;
        self.check_cuts(tracks, from, to)?;
        let ids: HashSet<Id> = tracks.iter().copied().collect();
        // The master of the place is the project's master.
        let master_of_place = place.and_then(|n| self.nest(n)).map_or(MASTER_ID, |n| n.master);
        let name_of = |id: Id| self.track(id).map_or_else(|| id.to_string(), |t| t.name.clone());
        let mut changes = Vec::new();
        let mut copies = Vec::new();
        for id in tracks {
            let mut t = (**self.track(*id).context("no track")?).clone();
            t.nest = None;
            t.clips = t
                .clips
                .iter()
                .filter_map(|c| placed_clip(c, -from, 0.0, to - from, c.id).map(Arc::new))
                .collect();
            t.lanes = t.lanes.iter().map(|l| Arc::new(placed_lane(l, &[(-from, 0.0, to - from)]))).collect();
            // A copy cut to the time is the project's own, not a track
            // folder outside that it refers to.
            t.origin = t.source.take().or(t.origin);
            changes.extend(cut_routes(&mut t, &ids, master_of_place, &name_of));
            copies.push(t);
        }
        let mut master = Track::new(MASTER_ID);
        master.name = "Master".into();
        let length = to - from;
        let map = map_over(&self.place_map(place), from, length);
        let mut project = self.made_of(name, master, copies, map);
        let meta = match place.and_then(|n| self.nest(n)) {
            Some(nest) => &nest.meta,
            None => &self.meta,
        };
        project.meta = meta.clone();
        // A subproject keeps its key in its meta; the song in `key`.
        if place.is_some() {
            project.key = key_of(&mut project.meta).or_else(|| self.key.clone());
        }
        match markers_over(meta, from, to) {
            Some(markers) => project.meta.insert("markers".into(), markers),
            None => project.meta.remove("markers"),
        };
        project.validate()?;
        Ok(Standalone { project, changes })
    }

    /// The place of the tracks of a view: one for all, none a master.
    pub fn view_place(&self, tracks: &[Id]) -> Result<Option<NestId>> {
        if tracks.is_empty() {
            bail!("the view has no tracks");
        }
        let mut place = None;
        for (i, id) in tracks.iter().enumerate() {
            let t = self.track(*id).with_context(|| format!("no track {id}"))?;
            if *id == MASTER_ID || t.nest.and_then(|n| self.nest(n)).is_some_and(|n| n.master == *id) {
                bail!("{} is a master track: take a view without it", t.name);
            }
            if i > 0 && t.nest != place {
                bail!("the tracks of the view are of two places: take a view of one");
            }
            place = t.nest;
        }
        Ok(place)
    }

    /// An error for the first clip of `tracks` that crosses an edge of the
    /// time `from..to` and cannot be cut there: an audio or a looped clip.
    pub fn check_cuts(&self, tracks: &[Id], from: f64, to: f64) -> Result<()> {
        let tempo = self.tempo_map();
        for t in tracks.iter().filter_map(|id| self.track(*id)) {
            for c in t.clips.iter().filter(|c| c.start < to - EPS && c.start + c.length > from + EPS) {
                let crosses = c.start < from - EPS || c.start + c.length > to + EPS;
                let cuttable = !c.looped && matches!(c.content, ClipContent::Midi { .. } | ClipContent::Nest { .. });
                if crosses && !cuttable {
                    let at = if c.start < from - EPS { from } else { to };
                    bail!(
                        "the clip {} on {} goes over the edge at bar {}: an audio or looped clip cannot be cut there yet; cut it or move it first",
                        if c.name.is_empty() { "with no name" } else { &c.name },
                        t.name,
                        tempo.bar_of(at) + 1
                    );
                }
            }
        }
        Ok(())
    }
}

/// Cut the routes of a track copy `t` to tracks not in `ids`: its output
/// goes to the master, and its sends, side-chains and output pairs there
/// go. A group that is not in `ids` is no longer its group. A route to
/// `master`, the master of its place, goes to the project's master.
/// Returns what changed, in words.
fn cut_routes(t: &mut Track, ids: &HashSet<Id>, master: Id, name_of: &dyn Fn(Id) -> String) -> Vec<String> {
    let to_master = |id: Id| if id == master { MASTER_ID } else { id };
    t.output = t.output.map(to_master).filter(|o| *o != MASTER_ID);
    t.sends.iter_mut().for_each(|s| s.target = to_master(s.target));
    let outside = |id: Id| id != MASTER_ID && !ids.contains(&id);
    let mut changes = Vec::new();
    if let Some(to) = t.output.filter(|o| outside(*o)) {
        changes.push(format!("{} played into {}: it plays into the master", t.name, name_of(to)));
        t.output = None;
    }
    for s in t.sends.iter().filter(|s| outside(s.target)) {
        changes.push(format!("the send of {} to {} is left out", t.name, name_of(s.target)));
    }
    t.sends.retain(|s| !outside(s.target));
    for d in t.devices.iter_mut() {
        let listens = d.sidechain.filter(|s| outside(*s));
        let pairs: Vec<u32> = d.outputs.iter().filter(|(_, to)| outside(**to)).map(|(n, _)| *n).collect();
        if listens.is_none() && pairs.is_empty() {
            continue;
        }
        let d = Arc::make_mut(d);
        let device = d.name.clone().unwrap_or_else(|| d.kind.clone());
        if let Some(source) = listens {
            changes.push(format!("{device} on {} listened to {}: it has no side-chain", t.name, name_of(source)));
            d.sidechain = None;
        }
        for n in pairs {
            if let Some(to) = d.outputs.remove(&n) {
                changes.push(format!("output pair {n} of {device} on {} played into {}: it is left out", t.name, name_of(to)));
            }
        }
    }
    if t.meta.get("group").and_then(Value::as_u64).is_some_and(outside) {
        t.meta.remove("group");
    }
    changes
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::nest::tests::{add_nest, nest_clip, song};
    use crate::model::{Clip, Note, Notes, Send, TempoChange};
    use serde_json::json;

    fn names(p: &Project) -> Vec<&str> {
        p.tracks.iter().map(|t| t.name.as_str()).collect()
    }

    #[test]
    fn a_nest_takes_the_tempo_of_its_first_block_its_master_is_the_master_and_the_nests_inside_go_along() {
        // The song places Bridge (10) at beat 8, where it slows to 90; Bridge
        // places Fill (20).
        let mut p = song(10);
        Arc::make_mut(&mut p.tracks[0]).clips = vec![nest_clip(2, 10, 8.0, json!("master"))].into();
        add_nest(&mut p, 10, "Bridge", vec![nest_clip(5, 20, 0.0, json!("master"))]);
        add_nest(&mut p, 20, "Fill", Vec::new());
        p.tempo_changes = vec![TempoChange { beat: 8.0, bpm: 90.0, ramp: false }];
        p.refresh_tempo();
        p.validate().expect("a valid song");

        let made = p.nest_standalone(NestId(10)).expect("a project").project;

        assert_eq!(made.name, "Bridge");
        assert_eq!((made.tempo, made.tempo_changes.len()), (90.0, 0), "the song's tempo over the block");
        assert_eq!(made.master.id, MASTER_ID);
        assert_eq!(names(&made), ["Keys", "Keys", "Master"], "its Keys, then Fill's tracks");
        assert_eq!(made.tracks[0].nest, None, "its tracks are the song's");
        assert_eq!(made.nests.keys().copied().collect::<Vec<_>>(), [NestId(20)], "Fill stays a subproject");
    }

    #[test]
    fn a_view_cuts_its_clips_at_its_time_and_tells_each_route_out_of_it_that_it_cuts() {
        let note = |start: f64, id: u64| Note { start, length: 0.5, pitch: 60, velocity: 90, meta: Map::new(), id, attr: None };
        let mut riff: Clip = serde_json::from_value(json!({
            "id": 10, "name": "riff", "start": 0.0, "length": 8.0, "muted": false,
            "content": { "kind": "midi", "notes": [] },
        }))
        .expect("a clip");
        riff.content = ClipContent::Midi { notes: Notes::from(vec![note(1.0, 1), note(5.0, 2)]), controls: Vec::new() };
        let mut bass = Track::new(1);
        bass.name = "Bass".into();
        bass.clips.push(Arc::new(riff));
        bass.sends.push(Send { target: 2, level: -6.0, pre: false });
        let mut verb = Track::new(2);
        verb.name = "Verb".into();
        let p = Project { tracks: vec![Arc::new(bass), Arc::new(verb)], ..Project::default() };

        let made = p.view_standalone("Bridge", &[1], 4.0, 8.0).expect("a project");

        assert_eq!(names(&made.project), ["Bass"]);
        let bass = &made.project.tracks[0];
        assert!(bass.sends.is_empty(), "the send to Verb is cut");
        assert_eq!(made.changes, ["the send of Bass to Verb is left out"]);
        let clip = &bass.clips[0];
        assert_eq!((clip.start, clip.length), (0.0, 4.0), "the clip from the view's start");
        let ClipContent::Midi { notes, .. } = &clip.content else { panic!("a MIDI clip") };
        assert_eq!(notes.iter().map(|n| n.start).collect::<Vec<_>>(), [1.0], "the note at beat 5, now at 1");
        assert_eq!(p.tracks[0].sends.len(), 1, "the song keeps its send");
    }
}
