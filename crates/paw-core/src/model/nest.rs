//! Nests (subprojects, as the user calls them): tracks with a timeline of
//! their own, placed in the song by nest clips.
//!
//! A nest's tracks live in the project's one track list, tagged with the
//! nest ([`Track::nest`]): every function that works on tracks works on
//! them, and their order in the list is their order in the nest. A
//! [`Nest`] keeps what the tracks do not: its name, its length, its tempo
//! and meter, and which of its tracks is its master. A nest clip
//! ([`ClipContent::Nest`]) places a nest on a track of the song or of
//! another nest.
//!
//! The rules ([`check`], part of [`Project::validate`]):
//!
//! - the nest graph (a nest holds the nests of its clips) has no cycle and
//!   is at most [`MAX_DEPTH`] deep;
//! - a nest clip that plays one track names a track of its nest;
//! - the boundary is closed: the output, the sends, the side-chains and
//!   the output pairs of a nest's track stay inside its nest, and no song
//!   track routes into a nest. The nest's master plays into the song only
//!   through the nest's clips: it has no output and no sends.
//!
//! Everything about nests in the model is in this module, so that it can
//! move with the model into a crate of its own.

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fmt;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::{Result, bail};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::{Map, Value};

use super::{ClipContent, Id, MASTER_ID, Project, SigChange, TempoChange, Track};

/// The most nests inside each other: a song clip places a nest at depth 1.
pub const MAX_DEPTH: usize = 8;

/// A nest's own id, never reused in the project. Nests take their ids from
/// the same counter as tracks and clips.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(transparent)]
pub struct NestId(pub u64);

impl fmt::Display for NestId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}

/// A set of tracks with a timeline of its own.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Nest {
    pub id: NestId,
    pub name: String,
    /// Beats (quarter notes) from its start to its end.
    pub length: f64,
    #[serde(default)]
    pub tempo: NestTempo,
    #[serde(default)]
    pub meter: NestMeter,
    /// The track of the nest's mix: its devices and fader. A usual track
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
    /// [`Track::source`] is for a track.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<PathBuf>,
    /// The nest folder outside the project that the nest was copied from.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub origin: Option<PathBuf>,
}

/// The tempo of a nest's timeline.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "lowercase")]
pub enum NestTempo {
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
pub enum NestMeter {
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
    /// The events of one track of the nest, through the devices of the
    /// track the clip is on.
    Track(Id),
    /// The nest's mix: what its master plays.
    Master,
}

/// How audio goes from one track to another, for the messages of the
/// closed boundary.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Route {
    Output,
    Send,
    /// A device on the second track listens to the first.
    SideChain,
    /// An output pair of a device on the first track plays into the second.
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

/// `Project::nests` as a project file has it: a list in the order of the
/// ids, not a map, so that JSON and Lua see the ids as numbers.
pub(super) mod as_list {
    use super::*;

    pub fn serialize<S: Serializer>(
        nests: &BTreeMap<NestId, Arc<Nest>>,
        s: S,
    ) -> std::result::Result<S::Ok, S::Error> {
        s.collect_seq(nests.values())
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(
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
    pub fn nest(&self, id: NestId) -> Option<&Arc<Nest>> {
        self.nests.get(&id)
    }

    pub fn nest_mut(&mut self, id: NestId) -> Option<&mut Nest> {
        self.nests.get_mut(&id).map(Arc::make_mut)
    }

    /// The tracks of a nest, its master included, in their order.
    pub fn nest_tracks(&self, id: NestId) -> impl Iterator<Item = &Arc<Track>> {
        self.tracks.iter().filter(move |t| t.nest == Some(id))
    }

    /// The song's own tracks (no nest's), in their order, without the
    /// master.
    pub fn song_tracks(&self) -> impl Iterator<Item = &Arc<Track>> {
        self.tracks.iter().filter(|t| t.nest.is_none())
    }

    /// How a message names where a track is: "the song" or "the subproject
    /// Bridge".
    fn place_of(&self, track: &Track) -> String {
        match track.nest.and_then(|n| self.nests.get(&n)) {
            Some(nest) => format!("the subproject {}", nest.name),
            None => "the song".into(),
        }
    }

    /// Whether audio may go from track `from` to track `to` by `route`
    /// across the boundary of a nest: an error that says why not.
    pub fn check_route(&self, from: Id, to: Id, route: Route) -> Result<()> {
        let (Some(a), Some(b)) = (self.track(from), self.track(to)) else {
            return Ok(());
        };
        if let Some(nest) = a.nest.and_then(|n| self.nests.get(&n))
            && nest.master == from
            && matches!(route, Route::Output | Route::Send)
        {
            bail!(
                "track {from} ({}) is the master of the subproject {}: it plays into the song through the subproject's clips, and has no output or sends",
                a.name,
                nest.name
            );
        }
        if a.nest != b.nest {
            bail!(
                "track {from} ({}) of {} cannot {} track {to} ({}) of {}: the tracks of a subproject route only to each other",
                a.name,
                self.place_of(a),
                route.verb(),
                b.name,
                self.place_of(b),
            );
        }
        Ok(())
    }

    /// The nests the song plays: those its clips place, and those their
    /// clips place, all the way down.
    pub fn nests_in_use(&self) -> BTreeSet<NestId> {
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
        for t in self.all_tracks() {
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
    check_tracks_and_clips(p)?;
    check_graph(p)?;
    check_boundary(p)
}

/// One nest's own fields, and its master.
pub fn check_nest(p: &Project, id: NestId, nest: &Nest) -> Result<()> {
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
    let master = p.track(nest.master);
    if nest.master == MASTER_ID || master.is_none_or(|t| t.nest != Some(id)) {
        bail!("{name} has no master track of its own (track {})", nest.master);
    }
    Ok(())
}

/// Each tagged track names a nest, and each nest clip a nest and, when it
/// plays one track, a track of that nest.
fn check_tracks_and_clips(p: &Project) -> Result<()> {
    if p.master.nest.is_some() {
        bail!("the song's master track belongs to the song");
    }
    for t in p.all_tracks() {
        if let Some(n) = t.nest
            && !p.nests.contains_key(&n)
        {
            bail!("track {} ({}) belongs to subproject {n}, which is not there", t.id, t.name);
        }
        for c in t.clips.iter().chain(&t.cues) {
            let ClipContent::Nest { nest, play, .. } = &c.content else {
                continue;
            };
            let Some(held) = p.nests.get(nest) else {
                bail!("clip {} places subproject {nest}, which is not there", c.id);
            };
            if let NestPlay::Track(track) = play
                && p.track(*track).is_none_or(|x| x.nest != Some(*nest))
            {
                bail!(
                    "clip {} plays track {track} of the subproject {}, which has no such track",
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

/// The closed boundary: what each track routes to, and what its devices
/// listen to, is in its own nest.
fn check_boundary(p: &Project) -> Result<()> {
    if p.nests.is_empty() {
        return Ok(());
    }
    for t in p.all_tracks() {
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

    /// Add nest `id` named `name` to `p`, with its master (track `id + 1`)
    /// and one more track (`id + 2`, `Keys`) that holds `clips`.
    pub(crate) fn add_nest(p: &mut Project, id: u64, name: &str, clips: Vec<Arc<Clip>>) {
        let nest = NestId(id);
        let mut master = Track::new(id + 1);
        master.name = "Master".into();
        master.nest = Some(nest);
        let mut keys = Track::new(id + 2);
        keys.name = "Keys".into();
        keys.nest = Some(nest);
        for clip in clips {
            keys.clips.push(clip);
        }
        p.tracks.push(Arc::new(keys));
        p.tracks.push(Arc::new(master));
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

    /// A song with one track (id 1) that places nest `first` with its mix.
    pub(crate) fn song(first: u64) -> Project {
        let mut p = Project::default();
        let mut row = Track::new(1);
        row.name = "Ballad".into();
        row.clips.push(nest_clip(2, first, 0.0, json!("master")));
        p.tracks.push(Arc::new(row));
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
    fn a_nest_track_that_sends_to_a_song_bus_is_refused() {
        let mut p = song(10);
        let mut reverb = Track::new(3);
        reverb.name = "Reverb".into();
        p.tracks.push(Arc::new(reverb));
        add_nest(&mut p, 10, "Bridge", Vec::new());
        p.validate().expect("the nest stays inside");
        let keys = p.track_mut(12).expect("Keys");
        keys.sends.push(Send { target: 3, level: 0.0, pre: false });
        assert_eq!(
            refused(&p),
            "track 12 (Keys) of the subproject Bridge cannot send to track 3 (Reverb) of the song: \
             the tracks of a subproject route only to each other"
        );
    }

    #[test]
    fn a_clip_that_plays_a_track_of_another_nest_is_refused() {
        let mut p = song(10);
        add_nest(&mut p, 10, "Bridge", Vec::new());
        p.track_mut(1)
            .expect("Ballad")
            .clips
            .push(nest_clip(4, 10, 32.0, json!({ "track": 1 })));
        let text = refused(&p);
        assert!(text.contains("has no such track"), "{text}");
    }
}
