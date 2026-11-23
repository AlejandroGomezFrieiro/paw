//! Nests (subprojects, as the user calls them): parts with a timeline of
//! their own, placed in the song by nest clips.
//!
//! A nest's parts live in the project's one part list, tagged with the
//! nest ([`Part::nest`]): every function that works on parts works on
//! them, and their order in the list is their order in the nest. A
//! [`Nest`] keeps what the parts do not: its name, its length, its tempo
//! and meter, and which of its parts is its master. A nest clip
//! ([`ClipContent::Nest`]) places a nest on a part of the song or of
//! another nest.
//!
//! The rules ([`check`], part of [`Project::validate`]):
//!
//! - the nest graph (a nest holds the nests of its clips) has no cycle and
//!   is at most [`MAX_DEPTH`] deep;
//! - a nest clip that plays one part names a part of its nest;
//! - the boundary is closed: the output, the sends, the side-chains and
//!   the output pairs of a nest's part stay inside its nest, and no song
//!   part routes into a nest. The nest's master plays into the song only
//!   through the nest's clips: it has no output and no sends.
//!
//! Everything about nests in the model is in this module, so that it can
//! move with the model into a crate of its own.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fmt;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{Result, bail};
use paw_types::TempoMap;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::{Map, Value};

use super::{Clip, ClipContent, Control, Id, Lane, MASTER_ID, Note, Notes, Project, SigChange, TempoChange, Part};

mod adopt;
mod standalone;
mod time;
pub(crate) use standalone::Standalone;
pub(crate) use time::{Timing, timed_lane};

/// The most nests inside each other: a song clip places a nest at depth 1.
pub(crate) const MAX_DEPTH: usize = 8;

/// A nest's own id, never reused in the project. Nests take their ids from
/// the same counter as parts and clips.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct NestId(pub u64);

impl fmt::Display for NestId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}

/// A set of parts with a timeline of its own.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub(crate) struct Nest {
    pub id: NestId,
    pub name: String,
    /// Beats (quarter notes) from its start to its end.
    pub length: f64,
    #[serde(default)]
    pub tempo: NestTempo,
    #[serde(default)]
    pub meter: NestMeter,
    /// The part of the nest's mix: its devices and fader. A usual part
    /// of the project's list, tagged with the nest.
    pub master: Id,
    /// An extension's kind of nest (`drums.pattern`); `None` for a plain
    /// nest.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    /// Its markers and regions (`meta.markers`, as the song has them) and
    /// the data of extensions.
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub meta: Map<String, Value>,
    /// A nest folder outside the project that the nest is read from, as
    /// [`Part::source`] is for a part.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<PathBuf>,
    /// The nest folder outside the project that the nest was copied from.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<PathBuf>,
}

/// The tempo of a nest's timeline.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "lowercase")]
pub(crate) enum NestTempo {
    /// The tempo of the place where each clip plays it. `kept` is the
    /// song's map over the nest when it was made, for `own` and export.
    Follow {
        #[serde(default, skip_serializing_if = "Vec::is_empty")]
        kept: Vec<TempoChange>,
    },
    /// Its own map: at least one point, the first at beat 0.
    Own { points: Vec<TempoChange> },
}

impl Default for NestTempo {
    fn default() -> Self {
        Self::Follow { kept: Vec::new() }
    }
}

/// The meter of a nest's timeline.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "lowercase")]
pub(crate) enum NestMeter {
    /// The song's meter at the place where each clip plays it.
    #[default]
    Follow,
    /// Its own: at least one change, the first at beat 0.
    Own { changes: Vec<SigChange> },
}

/// What a nest clip plays of its nest.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NestPlay {
    /// The events of one part of the nest, through the devices of the
    /// part the clip is on.
    Part(Id),
    /// The nest's mix: what its master plays.
    Master,
}

/// How audio goes from one part to another, for the messages of the
/// closed boundary.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Route {
    Output,
    Send,
    /// A device on the second part listens to the first.
    SideChain,
    /// An output pair of a device on the first part plays into the second.
    Pair,
}

impl Route {
    fn verb(self) -> &'static str {
        match self {
            Self::Output => "output to",
            Self::Send => "send to",
            Self::SideChain => "be a side-chain of",
            Self::Pair => "play an output pair into",
        }
    }
}

/// A clip of a nest's timeline placed in the song: its beat `b` is the
/// song's beat `zero + b`, cut at the window `from..to` of song beats, with
/// the id `id`. None when nothing of it is inside the window, or when it is
/// cut at its start and cannot be: a looped clip, an audio clip, a custom
/// clip's sound. A nest clip cut at its start starts later in its nest.
pub(crate) fn placed_clip(clip: &Clip, zero: f64, from: f64, to: f64, id: Id) -> Option<Clip> {
    let start = zero + clip.start;
    let end = (start + clip.length).min(to);
    let first = start.max(from);
    if end <= first {
        return None;
    }
    let mut copy = Clip {
        id,
        start: first,
        length: end - first,
        ..clip.clone()
    };
    let cut = first - start;
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
                    .map(|c| Control { start: c.start - cut, ..c.clone() })
                    .collect();
                ClipContent::Midi { notes, controls }
            }
            ClipContent::Nest { nest, offset, play } => ClipContent::Nest { nest: *nest, offset: offset + cut, play: *play },
            // The rest of a sound from the cut on: its offset in seconds
            // would follow the tempo there, which this does not know.
            _ => return None,
        };
    }
    Some(copy)
}

/// A lane of a nest's part as the song plays it: for each place of the
/// nest, `(zero, from, to)` in song beats, the lane's points from `from` to
/// `to` moved by `zero`, with the value it plays at each edge. The shapes
/// of the curve inside a place move with it. The lane as it is when the
/// nest has no place, or the lane no points.
pub(crate) fn placed_lane(lane: &Lane, places: &[(f64, f64, f64)]) -> Lane {
    if places.is_empty() || lane.points.is_empty() {
        return lane.clone();
    }
    let mut points = Vec::new();
    let mut shapes = Vec::new();
    for &(zero, from, to) in places {
        let (a, b) = (from - zero, to - zero);
        if from.is_finite() {
            points.push((from, lane.value_at(a)));
        }
        for &(beat, value) in lane.points.iter().filter(|p| p.0 > a && p.0 < b) {
            points.push((beat + zero, value));
        }
        for s in lane.shapes.iter().filter(|s| s.beat > a && s.beat < b) {
            shapes.push(super::Segment { beat: s.beat + zero, ..*s });
        }
        if to.is_finite() {
            points.push((to, lane.value_at(b)));
        }
    }
    points.sort_by(|x, y| x.0.total_cmp(&y.0));
    Lane { points, shapes, ..lane.clone() }
}

/// `Project::nests` as a project file has it: a list in the order of the
/// ids, not a map, so that JSON and Lua see the ids as numbers.
pub(super) mod as_list {
    use super::*;

    pub(crate) fn serialize<S: Serializer>(
        nests: &BTreeMap<NestId, Arc<Nest>>,
        s: S,
    ) -> std::result::Result<S::Ok, S::Error> {
        s.collect_seq(nests.values())
    }

    pub(crate) fn deserialize<'de, D: Deserializer<'de>>(
        d: D,
    ) -> std::result::Result<BTreeMap<NestId, Arc<Nest>>, D::Error> {
        let list = Vec::<Nest>::deserialize(d)?;
        let mut nests = BTreeMap::new();
        for nest in list {
            if nests.insert(nest.id, Arc::new(nest)).is_some() {
                return Err(serde::de::Error::custom("two nests have one id"));
            }
        }
        Ok(nests)
    }
}

impl Project {
    pub(crate) fn nest(&self, id: NestId) -> Option<&Arc<Nest>> {
        self.nests.get(&id)
    }

    pub(crate) fn nest_mut(&mut self, id: NestId) -> Option<&mut Nest> {
        self.nests.get_mut(&id).map(Arc::make_mut)
    }

    /// The parts of a nest, its master included, in their order.
    pub(crate) fn nest_parts(&self, id: NestId) -> impl Iterator<Item = &Arc<Part>> {
        self.parts.iter().filter(move |t| t.nest == Some(id))
    }

    /// The song's own parts (no nest's), in their order, without the
    /// master.
    pub(crate) fn song_parts(&self) -> impl Iterator<Item = &Arc<Part>> {
        self.parts.iter().filter(|t| t.nest.is_none())
    }

    /// How a message names where a part is: "the song" or "the subproject
    /// Bridge".
    fn place_of(&self, part: &Part) -> String {
        match part.nest.and_then(|n| self.nests.get(&n)) {
            Some(nest) => format!("the subproject {}", nest.name),
            None => "the song".into(),
        }
    }

    /// Whether audio may go from part `from` to part `to` by `route`
    /// across the boundary of a nest: an error that says why not.
    pub(crate) fn check_route(&self, from: Id, to: Id, route: Route) -> Result<()> {
        let (Some(a), Some(b)) = (self.part(from), self.part(to)) else {
            return Ok(());
        };
        if let Some(nest) = a.nest.and_then(|n| self.nests.get(&n))
            && nest.master == from
            && matches!(route, Route::Output | Route::Send)
        {
            bail!(
                "part {from} ({}) is the master of the subproject {}: it plays into the song through the subproject's clips, and has no output or sends",
                a.name,
                nest.name
            );
        }
        if a.nest != b.nest {
            bail!(
                "part {from} ({}) of {} cannot {} part {to} ({}) of {}: the parts of a subproject route only to each other",
                a.name,
                self.place_of(a),
                route.verb(),
                b.name,
                self.place_of(b),
            );
        }
        Ok(())
    }

    /// The parts of a place: the song's (`None`) or a nest's, without the
    /// nest's master, in their order.
    pub(crate) fn place_parts(&self, place: Option<NestId>) -> impl Iterator<Item = &Arc<Part>> {
        let master = place.and_then(|n| self.nests.get(&n)).map(|n| n.master);
        self.parts
            .iter()
            .filter(move |t| t.nest == place && Some(t.id) != master)
    }

    /// Where in the part list the part at `index` (from 0) among the
    /// parts of a place goes: before the one there now, else after the
    /// place's last part, else at the end.
    pub(crate) fn place_position(&self, place: Option<NestId>, index: usize) -> usize {
        let master = place.and_then(|n| self.nests.get(&n)).map(|n| n.master);
        let mut last = None;
        let mut count = 0;
        for (at, t) in self.parts.iter().enumerate() {
            if t.nest != place || Some(t.id) == master {
                continue;
            }
            if count == index {
                return at;
            }
            count += 1;
            last = Some(at);
        }
        last.map_or(self.parts.len(), |at| at + 1)
    }

    /// Whether nest `nest` may be placed by a clip on a part of `host`
    /// (the song when `None`): an error with the path when it would hold
    /// itself, or be more than [`MAX_DEPTH`] deep.
    pub(crate) fn check_place(&self, nest: NestId, host: Option<NestId>) -> Result<()> {
        let name = |n: NestId| self.nests.get(&n).map_or_else(|| n.to_string(), |x| x.name.clone());
        let Some(host) = host else {
            return Ok(());
        };
        // The nests below `nest`, each with the path that reaches it.
        let held = self.nests_held();
        let mut stack = vec![vec![nest]];
        while let Some(path) = stack.pop() {
            let at = *path.last().expect("a path has a nest");
            if at == host {
                let names: Vec<String> = std::iter::once(host).chain(path).map(name).collect();
                bail!("a subproject cannot hold itself: {}", names.join(" › "));
            }
            if path.len() > MAX_DEPTH {
                continue;
            }
            for next in held.get(&Some(at)).into_iter().flatten() {
                let mut longer = path.clone();
                longer.push(*next);
                stack.push(longer);
            }
        }
        Ok(())
    }

    /// Keep the seconds of the song's blocks of nests with a tempo of their
    /// own as the song's map changes from `old` to `new`: each keeps its
    /// start on its beat, and its length follows its seconds. Blocks inside
    /// nests stay as they are: their place has the same beats as before.
    pub(super) fn fit_own_tempo_blocks(&mut self, old: &TempoMap, new: &TempoMap) {
        let own: BTreeSet<NestId> = self.nests.values().filter(|n| n.has_own_tempo()).map(|n| n.id).collect();
        if own.is_empty() {
            return;
        }
        let is_own = |c: &Clip| matches!(&c.content, ClipContent::Nest { nest, .. } if own.contains(nest));
        for part in self.parts.iter_mut().filter(|t| t.nest.is_none()) {
            if !part.clips.iter().any(|c| is_own(c)) {
                continue;
            }
            for clip in Arc::make_mut(part).clips.iter_mut().filter(|c| is_own(c)) {
                let seconds = old.seconds_between(clip.start, clip.start + clip.length);
                let length = new.beat(new.seconds(clip.start) + seconds) - clip.start;
                if (length - clip.length).abs() > 1e-12 {
                    Arc::make_mut(clip).length = length;
                }
            }
        }
    }

    /// Give the song's blocks of nest `id` the length in song beats that
    /// their part of the nest takes, after the nest's tempo changed from
    /// `was`: each keeps its start and the beats of the nest it plays.
    pub(crate) fn fit_blocks(&mut self, id: NestId, was: &Nest) {
        let Some(now) = self.nests.get(&id).cloned() else {
            return;
        };
        let song = self.map.clone();
        for part in self.parts.iter_mut().filter(|t| t.nest.is_none()) {
            let ours = |c: &Clip| matches!(&c.content, ClipContent::Nest { nest, .. } if *nest == id);
            if !part.clips.iter().any(|c| ours(c)) {
                continue;
            }
            for clip in Arc::make_mut(part).clips.iter_mut().filter(|c| ours(c)) {
                let ClipContent::Nest { offset, .. } = clip.content else {
                    continue;
                };
                let before = was.timing(&song, None, clip.start, offset);
                let after = now.timing(&song, None, clip.start, offset);
                let end = before.nest_beat(clip.start + clip.length);
                let length = after.song_beat(end) - clip.start;
                if (length - clip.length).abs() > 1e-9 {
                    Arc::make_mut(clip).length = length;
                }
            }
        }
    }

    /// The nests the song plays: those its clips place, and those their
    /// clips place, all the way down.
    pub(crate) fn nests_in_use(&self) -> BTreeSet<NestId> {
        let held = self.nests_held();
        let mut used = BTreeSet::new();
        let mut stack: Vec<NestId> = held.get(&None).into_iter().flatten().copied().collect();
        while let Some(id) = stack.pop() {
            if used.insert(id) {
                stack.extend(held.get(&Some(id)).into_iter().flatten().copied());
            }
        }
        used
    }

    /// The nests that each place holds clips of: the song (`None`) or a
    /// nest.
    fn nests_held(&self) -> HashMap<Option<NestId>, BTreeSet<NestId>> {
        let mut held: HashMap<Option<NestId>, BTreeSet<NestId>> = HashMap::new();
        for t in self.all_parts() {
            for c in t.clips.iter().chain(&t.cues) {
                if let ClipContent::Nest { nest, .. } = &c.content {
                    held.entry(t.nest).or_default().insert(*nest);
                }
            }
        }
        held
    }
}

/// The rules of nests, for [`Project::validate`].
pub(super) fn check(p: &Project) -> Result<()> {
    for (id, nest) in &p.nests {
        check_nest(p, *id, nest)?;
    }
    check_parts_and_clips(p)?;
    check_graph(p)?;
    check_boundary(p)
}

/// One nest's own fields, and its master.
pub(crate) fn check_nest(p: &Project, id: NestId, nest: &Nest) -> Result<()> {
    if nest.id != id {
        bail!("the nest kept as {id} says it is {}", nest.id);
    }
    let name = format!("the subproject {}", nest.name);
    if nest.name.trim().is_empty() {
        bail!("subproject {id} has no name");
    }
    if !nest.length.is_finite() || nest.length <= 0.0 {
        bail!("{name} is {} beats long: it needs a length above 0", nest.length);
    }
    let tempo_ok = |points: &[TempoChange]| {
        points.iter().all(|c| {
            c.beat.is_finite() && c.beat >= 0.0 && (1.0..=999.0).contains(&c.bpm)
        })
    };
    match &nest.tempo {
        NestTempo::Follow { kept } if !tempo_ok(kept) => {
            bail!("{name} keeps a tempo out of range: a tempo is 1 to 999 at a beat of at least 0")
        }
        NestTempo::Own { points } if points.first().is_none_or(|c| c.beat != 0.0) || !tempo_ok(points) => {
            bail!("{name} has its own tempo: it needs tempos of 1 to 999, the first at beat 0")
        }
        _ => {}
    }
    if let NestMeter::Own { changes } = &nest.meter {
        let fits = |n: u32| (1..=64).contains(&n);
        if changes.first().is_none_or(|c| c.beat != 0.0)
            || changes.iter().any(|c| !c.beat.is_finite() || !fits(c.num) || !fits(c.den))
        {
            bail!("{name} has its own meter: it needs meters of 1 to 64 over 1 to 64, the first at beat 0");
        }
    }
    let master = p.part(nest.master);
    if nest.master == MASTER_ID || master.is_none_or(|t| t.nest != Some(id)) {
        bail!("{name} has no master part of its own (part {})", nest.master);
    }
    Ok(())
}

/// Each tagged part names a nest, and each nest clip a nest and, when it
/// plays one part, a part of that nest.
fn check_parts_and_clips(p: &Project) -> Result<()> {
    if p.master.nest.is_some() {
        bail!("the song's master part belongs to the song");
    }
    for t in p.all_parts() {
        if let Some(n) = t.nest
            && !p.nests.contains_key(&n)
        {
            bail!("part {} ({}) belongs to subproject {n}, which is not there", t.id, t.name);
        }
        for c in t.clips.iter().chain(&t.cues) {
            let ClipContent::Nest { nest, play, .. } = &c.content else {
                continue;
            };
            let Some(held) = p.nests.get(nest) else {
                bail!("clip {} places subproject {nest}, which is not there", c.id);
            };
            if let NestPlay::Part(part) = play
                && p.part(*part).is_none_or(|x| x.nest != Some(*nest))
            {
                bail!(
                    "clip {} plays part {part} of the subproject {}, which has no such part",
                    c.id,
                    held.name
                );
            }
        }
    }
    Ok(())
}

/// The nest graph has no cycle and is at most [`MAX_DEPTH`] deep.
fn check_graph(p: &Project) -> Result<()> {
    let held = p.nests_held();
    let children = |n: NestId| held.get(&Some(n)).into_iter().flatten().copied();
    let name = |n: NestId| p.nests.get(&n).map_or_else(|| n.to_string(), |x| x.name.clone());
    let path_text = |path: &[NestId]| path.iter().map(|n| name(*n)).collect::<Vec<_>>().join(" › ");
    // The longest chain of nests from each nest down, found depth first.
    let mut deepest: HashMap<NestId, Vec<NestId>> = HashMap::new();
    for &start in p.nests.keys() {
        if deepest.contains_key(&start) {
            continue;
        }
        let mut stack: Vec<(NestId, Vec<NestId>)> = vec![(start, children(start).collect())];
        while let Some((id, pending)) = stack.last_mut() {
            let id = *id;
            let Some(next) = pending.pop() else {
                let below = children(id)
                    .filter_map(|c| deepest.get(&c))
                    .max_by_key(|chain| chain.len())
                    .cloned()
                    .unwrap_or_default();
                let mut chain = vec![id];
                chain.extend(below);
                deepest.insert(id, chain);
                stack.pop();
                continue;
            };
            if let Some(at) = stack.iter().position(|(n, _)| *n == next) {
                let mut path: Vec<NestId> = stack[at..].iter().map(|(n, _)| *n).collect();
                path.push(next);
                bail!("a subproject holds itself: {}", path_text(&path));
            }
            if !deepest.contains_key(&next) {
                stack.push((next, children(next).collect()));
            }
        }
    }
    if let Some(chain) = deepest.values().max_by_key(|c| c.len())
        && chain.len() > MAX_DEPTH
    {
        bail!(
            "subprojects are {} deep ({}): at most {MAX_DEPTH} can be inside each other",
            chain.len(),
            path_text(chain)
        );
    }
    Ok(())
}

/// The closed boundary: what each part routes to, and what its devices
/// listen to, is in its own nest.
fn check_boundary(p: &Project) -> Result<()> {
    if p.nests.is_empty() {
        return Ok(());
    }
    for t in p.all_parts() {
        if let Some(to) = t.output {
            p.check_route(t.id, to, Route::Output)?;
        }
        for s in &t.sends {
            p.check_route(t.id, s.target, Route::Send)?;
        }
        for d in &t.devices {
            if let Some(source) = d.sidechain {
                p.check_route(source, t.id, Route::SideChain)?;
            }
            for to in d.outputs.values() {
                p.check_route(t.id, *to, Route::Pair)?;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::model::{Clip, Send};
    use serde_json::json;

    /// A clip that places nest `nest` at `start`, playing `play`.
    pub(crate) fn nest_clip(id: Id, nest: u64, start: f64, play: Value) -> Arc<Clip> {
        let clip = json!({
            "id": id, "name": "", "start": start, "length": 32.0, "muted": false,
            "content": { "kind": "nest", "nest": nest, "play": play },
        });
        Arc::new(serde_json::from_value(clip).expect("a nest clip"))
    }

    /// Add nest `id` named `name` to `p`, with its master (part `id + 1`)
    /// and one more part (`id + 2`, `Keys`) that holds `clips`.
    pub(crate) fn add_nest(p: &mut Project, id: u64, name: &str, clips: Vec<Arc<Clip>>) {
        let nest = NestId(id);
        let mut master = Part::new(id + 1);
        master.name = "Master".into();
        master.nest = Some(nest);
        let mut keys = Part::new(id + 2);
        keys.name = "Keys".into();
        keys.nest = Some(nest);
        for clip in clips {
            keys.clips.push(clip);
        }
        p.parts.push(Arc::new(keys));
        p.parts.push(Arc::new(master));
        p.nests.insert(
            nest,
            Arc::new(Nest {
                id: nest,
                name: name.into(),
                length: 32.0,
                tempo: NestTempo::default(),
                meter: NestMeter::default(),
                master: id + 1,
                kind: None,
                meta: Map::new(),
                source: None,
                origin: None,
            }),
        );
    }

    /// A song with one part (id 1) that places nest `first` with its mix.
    pub(crate) fn song(first: u64) -> Project {
        let mut p = Project::default();
        let mut row = Part::new(1);
        row.name = "Ballad".into();
        row.clips.push(nest_clip(2, first, 0.0, json!("master")));
        p.parts.push(Arc::new(row));
        p
    }

    fn refused(p: &Project) -> String {
        format!("{:#}", p.validate().expect_err("the project is refused"))
    }

    #[test]
    fn a_cycle_is_refused_with_its_path() {
        let mut p = song(10);
        add_nest(&mut p, 10, "Bridge", vec![nest_clip(100, 20, 0.0, json!("master"))]);
        add_nest(&mut p, 20, "Verse", vec![nest_clip(200, 10, 0.0, json!("master"))]);
        let text = refused(&p);
        assert!(text.contains("Bridge › Verse › Bridge"), "{text}");
    }

    #[test]
    fn nests_eight_deep_load_and_nine_deep_are_refused() {
        let chain = |depth: u64| {
            let mut p = song(10);
            for level in 1..=depth {
                let id = level * 10;
                let inner = (level < depth).then(|| nest_clip(id + 5, id + 10, 0.0, json!("master")));
                add_nest(&mut p, id, &format!("N{level}"), inner.into_iter().collect());
            }
            p
        };
        chain(MAX_DEPTH as u64).validate().expect("8 deep loads");
        let text = refused(&chain(MAX_DEPTH as u64 + 1));
        assert!(text.contains("9 deep (N1 › N2 › N3 › N4 › N5 › N6 › N7 › N8 › N9)"), "{text}");
    }

    #[test]
    fn a_nest_part_that_sends_to_a_song_bus_is_refused() {
        let mut p = song(10);
        let mut reverb = Part::new(3);
        reverb.name = "Reverb".into();
        p.parts.push(Arc::new(reverb));
        add_nest(&mut p, 10, "Bridge", Vec::new());
        p.validate().expect("the nest stays inside");
        let keys = p.part_mut(12).expect("Keys");
        keys.sends.push(Send { target: 3, level: 0.0, pre: false });
        assert_eq!(
            refused(&p),
            "part 12 (Keys) of the subproject Bridge cannot send to part 3 (Reverb) of the song: \
             the parts of a subproject route only to each other"
        );
    }

    #[test]
    fn a_clip_that_plays_a_part_of_another_nest_is_refused() {
        let mut p = song(10);
        add_nest(&mut p, 10, "Bridge", Vec::new());
        p.part_mut(1)
            .expect("Ballad")
            .clips
            .push(nest_clip(4, 10, 32.0, json!({ "part": 1 })));
        let text = refused(&p);
        assert!(text.contains("has no such part"), "{text}");
    }
}
