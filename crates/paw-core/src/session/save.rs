//! Save a view as a subproject (`nest.md` 3.6, 4.6, 4.7): `<Space>zw`, per
//! track, and `<Space>zW`, with a row of its own. The Lua side
//! (`paw.nest.save`) adds what is not track data: the blocks, the markers
//! and regions, and the place of the window.
//!
//! Per track, the tracks keep their devices and mix: the clips of each row
//! in the time move into a track of the subproject that has no sound of
//! its own, and a block on the row plays it there (the pass mode of
//! `sync/nests.rs`), so the song sounds the same to the sample.
//!
//! With a row of its own, a track that has nothing outside the time moves
//! into the subproject whole (its devices are the same instances), and a
//! track that has goes in as a copy: its clips in the time, and copies of
//! its devices and of its lanes there. One new return row plays the mix; a
//! view of one group whose tracks all move makes the group track the
//! return row. Routes at the boundary change as 4.7 says, and each change
//! is told.

use super::*;
use std::collections::HashSet;

use crate::model::nest::{placed_clip, placed_lane};
use crate::model::{Clip, ClipContent, Clips, Nest, NestId, NestMeter, NestTempo, Send, Target};

/// Two beats closer than this are one.
const EPS: f64 = 1e-9;

/// What [`Session::nest_save`] takes.
#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SaveOpts {
    /// The subproject's name.
    pub name: String,
    /// The tracks of the view, in their order: of one place.
    pub tracks: Vec<Id>,
    /// The time of the view, in the beats of that place.
    pub from: f64,
    pub to: f64,
    #[serde(default)]
    pub meter: NestMeter,
    /// A row of its own (`<Space>zW`) rather than per track.
    #[serde(default)]
    pub own_row: bool,
}

/// A row that gets a block per track, and the track of the subproject the
/// block plays.
#[derive(Debug, Serialize)]
pub struct HostRow {
    pub row: Id,
    pub track: Id,
}

/// What [`Session::nest_save`] did, for the Lua side and its message.
#[derive(Debug, Serialize)]
pub struct Saved {
    pub nest: NestId,
    /// Per track: each row that gets a block.
    pub rows: Vec<HostRow>,
    /// With a row of its own: the return row.
    pub row: Option<Id>,
    /// The subproject's tracks, without its master, in order.
    pub tracks: Vec<Id>,
    /// The routes that changed at the boundary, in words.
    pub changes: Vec<String>,
}

fn overlaps(c: &Clip, from: f64, to: f64) -> bool {
    c.start < to - EPS && c.start + c.length > from + EPS
}

/// Whether the time holds all of a track: its clips, cues and lanes.
fn inside(t: &Track, from: f64, to: f64) -> bool {
    let within = |b: f64| b >= from - EPS && b <= to + EPS;
    t.cues.is_empty()
        && t.clips.iter().all(|c| within(c.start) && within(c.start + c.length))
        && t.lanes.iter().all(|l| l.points.iter().all(|p| within(p.0)))
}

fn is_vca(t: &Track) -> bool {
    t.meta.get("vca").and_then(Value::as_bool) == Some(true)
}

fn is_group(t: &Track) -> bool {
    t.meta.get("group_head").and_then(Value::as_bool) == Some(true)
}

fn group_of(t: &Track) -> Option<Id> {
    t.meta.get("group").and_then(Value::as_u64)
}

fn device_name(d: &DeviceInst) -> &str {
    d.name.as_deref().unwrap_or(&d.kind)
}

/// A lane moved by `-from`, all of its points inside the time.
fn shifted_lane(lane: &crate::model::Lane, from: f64) -> crate::model::Lane {
    let mut moved = lane.clone();
    moved.points.iter_mut().for_each(|p| p.0 -= from);
    moved.shapes.iter_mut().for_each(|s| s.beat -= from);
    moved
}

impl Session {
    /// The place of the tracks of a view: one for all, none a master.
    fn save_place(&self, tracks: &[Id]) -> Result<Option<NestId>> {
        let p = &self.doc.project;
        let mut place = None;
        for (i, id) in tracks.iter().enumerate() {
            let t = p.track(*id).with_context(|| format!("no track {id}"))?;
            if *id == MASTER_ID || t.nest.and_then(|n| p.nest(n)).is_some_and(|n| n.master == *id) {
                bail!("{} is a master track: it cannot go into a subproject", t.name);
            }
            if i > 0 && t.nest != place {
                bail!("the tracks of the view are of two places: save a view of one");
            }
            place = t.nest;
        }
        Ok(place)
    }

    /// An error for the first clip that crosses an edge of the time and
    /// cannot be cut there.
    fn check_cuts(&self, tracks: &[Id], from: f64, to: f64) -> Result<()> {
        let tempo = self.doc.project.tempo_map();
        for t in tracks.iter().filter_map(|id| self.doc.project.track(*id)) {
            for c in t.clips.iter().filter(|c| overlaps(c, from, to)) {
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

    /// A clip cut at `from` and `to`: the parts that stay (before and
    /// after), and the part inside, in beats from `from`. The part that
    /// starts where the clip starts keeps its id.
    fn cut_clip(&mut self, c: &Arc<Clip>, from: f64, to: f64) -> (Vec<Arc<Clip>>, Option<Arc<Clip>>) {
        let head = c.start < from - EPS;
        let tail = c.start + c.length > to + EPS;
        let mut kept = Vec::new();
        if head {
            kept.extend(placed_clip(c, 0.0, f64::NEG_INFINITY, from, c.id).map(Arc::new));
        }
        let id = if head { self.doc.new_id() } else { c.id };
        let inner = placed_clip(c, -from, 0.0, to - from, id).map(Arc::new);
        if tail {
            let id = self.doc.new_id();
            kept.extend(placed_clip(c, 0.0, to, f64::INFINITY, id).map(Arc::new));
        }
        (kept, inner)
    }

    /// Save a view as a subproject (see the module). One undo step.
    pub fn nest_save(&mut self, opts: SaveOpts) -> Result<Saved> {
        let (from, to) = (opts.from, opts.to);
        if !(from.is_finite() && to.is_finite() && to - from > EPS) {
            bail!("a subproject needs some time");
        }
        let name = opts.name.trim().to_string();
        if name.is_empty() {
            bail!("a subproject needs a name");
        }
        if opts.tracks.is_empty() {
            bail!("the view has no tracks to save");
        }
        let place = self.save_place(&opts.tracks)?;
        self.check_cuts(&opts.tracks, from, to)?;
        let id = NestId(self.doc.new_id());
        let mut master = Track::new(self.doc.new_id());
        master.name = "Master".into();
        master.nest = Some(id);
        let nest = Nest {
            id,
            name,
            length: to - from,
            tempo: NestTempo::default(),
            meter: opts.meter.clone(),
            master: master.id,
            kind: None,
            meta: Map::new(),
            source: None,
            origin: None,
        };
        if opts.own_row {
            self.save_own_row(&opts, nest, master, place)
        } else {
            self.save_per_track(&opts, nest, master)
        }
    }

    /// `<Space>zw`: per track.
    fn save_per_track(&mut self, opts: &SaveOpts, nest: Nest, master: Track) -> Result<Saved> {
        let (from, to) = (opts.from, opts.to);
        let mut rows = Vec::new();
        let mut kept: Vec<(Id, Clips)> = Vec::new();
        let mut made = vec![Arc::new(master)];
        for &row in &opts.tracks {
            let t = self.doc.project.track(row).context("no track")?.clone();
            if !t.clips.iter().any(|c| overlaps(c, from, to)) {
                continue;
            }
            let mut inner = Track::new(self.doc.new_id());
            inner.name = t.name.clone();
            inner.color = t.color.clone();
            inner.nest = Some(nest.id);
            let mut stay = Vec::new();
            let mut moved = Vec::new();
            for c in t.clips.iter() {
                if !overlaps(c, from, to) {
                    stay.push(c.clone());
                    continue;
                }
                let (parts, inside) = self.cut_clip(c, from, to);
                stay.extend(parts);
                moved.extend(inside);
            }
            stay.sort_by(|a, b| a.start.total_cmp(&b.start).then(a.id.cmp(&b.id)));
            inner.clips = moved.into_iter().collect();
            rows.push(HostRow { row, track: inner.id });
            kept.push((row, stay.into_iter().collect()));
            made.push(Arc::new(inner));
        }
        if rows.is_empty() {
            bail!("the view has no clips to save");
        }
        let tracks = made.iter().skip(1).map(|t| t.id).collect();
        let id = nest.id;
        let mut p = self.doc.project.clone();
        for (row, clips) in kept {
            p.track_mut(row).context("no row")?.clips = clips;
        }
        p.tracks.extend(made);
        p.nests.insert(id, Arc::new(nest));
        p.validate()?;
        self.edit(|project| {
            *project = p;
            Ok(())
        })?;
        Ok(Saved { nest: id, rows, row: None, tracks, changes: Vec::new() })
    }

    /// `<Space>zW`: a row of its own (see the module).
    fn save_own_row(&mut self, opts: &SaveOpts, nest: Nest, master: Track, place: Option<NestId>) -> Result<Saved> {
        let (from, to) = (opts.from, opts.to);
        let p = &self.doc.project;
        let selected: Vec<Arc<Track>> = opts
            .tracks
            .iter()
            .filter_map(|id| p.track(*id))
            .filter(|t| !is_vca(t))
            .cloned()
            .collect();
        let chosen: HashSet<Id> = selected.iter().map(|t| t.id).collect();
        // A track is inside a group when the group is above it.
        let below = |t: &Track, head: Id| {
            let mut at = group_of(t);
            for _ in 0..32 {
                match at {
                    Some(g) if g == head => return true,
                    Some(g) => at = p.track(g).and_then(|t| group_of(t)),
                    None => return false,
                }
            }
            false
        };
        // A group whose members are all chosen is whole when they are.
        let members_chosen = |head: Id| {
            p.all_tracks()
                .filter(|t| group_of(t) == Some(head) || t.output == Some(head))
                .all(|t| chosen.contains(&t.id))
        };
        let whole: HashSet<Id> = selected
            .iter()
            .filter(|t| inside(t, from, to) && (!is_group(t) || members_chosen(t.id)))
            .map(|t| t.id)
            .collect();
        let head = selected.first().filter(|g| {
            is_group(g)
                && g.clips.is_empty()
                && whole.contains(&g.id)
                && selected[1..].iter().all(|t| below(t, g.id) && whole.contains(&t.id))
        });
        let head = head.map(|g| g.id);
        // The tracks that go in: whole ones, those with clips in the time,
        // and the groups above them.
        let mut taken: HashSet<Id> = selected
            .iter()
            .filter(|t| Some(t.id) != head)
            .filter(|t| whole.contains(&t.id) || t.clips.iter().any(|c| overlaps(c, from, to)))
            .map(|t| t.id)
            .collect();
        for t in &selected {
            if taken.contains(&t.id) {
                let mut at = group_of(t);
                while let Some(g) = at.filter(|g| chosen.contains(g) && Some(*g) != head) {
                    taken.insert(g);
                    at = p.track(g).and_then(|t| group_of(t));
                }
            }
        }
        if taken.is_empty() {
            bail!("the view has nothing to save");
        }
        let order: Vec<Arc<Track>> = selected.iter().filter(|t| taken.contains(&t.id)).cloned().collect();
        // Each track that goes in, by its id in the song: the same id when it
        // moves whole, a new one for a copy.
        let mut ids: HashMap<Id, Id> = HashMap::new();
        for t in &order {
            let id = if whole.contains(&t.id) { t.id } else { self.doc.new_id() };
            ids.insert(t.id, id);
        }
        let p = &self.doc.project;
        let moved: HashSet<Id> = order.iter().filter(|t| whole.contains(&t.id)).map(|t| t.id).collect();
        // A side-chain or an output pair across the new boundary is refused.
        for t in p.all_tracks() {
            let inside = taken.contains(&t.id);
            for d in &t.devices {
                if let Some(s) = d.sidechain.and_then(|s| p.track(s)) {
                    // From outside into the subproject, or from a track that
                    // leaves the song to one that stays.
                    let (crosses, missing) = if inside {
                        (!taken.contains(&s.id), &s.name)
                    } else {
                        (moved.contains(&s.id), &t.name)
                    };
                    if crosses {
                        bail!(
                            "{} on {} listens to {}: take {missing} in too, or use <Space>zw",
                            device_name(d),
                            t.name,
                            s.name
                        );
                    }
                }
                if inside && let Some(to) = d.outputs.values().find(|o| !taken.contains(o)) {
                    let to = p.track(*to).map_or_else(|| to.to_string(), |t| t.name.clone());
                    bail!(
                        "{} on {} plays an output pair into {to}: take {to} in too, or use <Space>zw",
                        device_name(d),
                        t.name
                    );
                }
            }
        }
        // The return row.
        let mut changes = Vec::new();
        let mut row = match head.and_then(|h| p.track(h)) {
            Some(g) => {
                let mut row = (**g).clone();
                row.meta.remove("group_head");
                row.meta.remove("group_folded");
                row
            }
            None => {
                let mut row = Track::new(self.doc.new_id());
                row.name = nest.name.clone();
                row.nest = place;
                // The common output of the tracks that leave, else the master.
                let outs: BTreeSet<Option<Id>> = order
                    .iter()
                    .filter(|t| t.output.is_none_or(|o| !taken.contains(&o)))
                    .map(|t| t.output)
                    .collect();
                if outs.len() == 1 {
                    row.output = outs.into_iter().next().flatten();
                } else {
                    changes.push(format!("the tracks played into {} places: {} plays into the master", outs.len(), row.name));
                }
                row
            }
        };
        let row_id = row.id;
        let mut made = vec![Arc::new(master)];
        let mut stay: Vec<(Id, Clips)> = Vec::new();
        let mut vcas: Vec<u64> = row.meta.get("vcas").and_then(Value::as_array).map_or_else(Vec::new, |l| {
            l.iter().filter_map(Value::as_u64).collect()
        });
        let order_ids: Vec<Id> = order.iter().map(|t| t.id).collect();
        for song_id in order_ids {
            let t = self.doc.project.track(song_id).context("no track")?.clone();
            let mut inner = (*t).clone();
            inner.id = ids[&song_id];
            inner.nest = Some(nest.id);
            if whole.contains(&song_id) {
                inner.clips = t
                    .clips
                    .iter()
                    .filter_map(|c| placed_clip(c, -from, 0.0, to - from, c.id).map(Arc::new))
                    .collect();
                inner.lanes = t.lanes.iter().map(|l| Arc::new(shifted_lane(l, from))).collect();
            } else {
                let mut kept = Vec::new();
                let mut moved = Vec::new();
                for c in t.clips.iter() {
                    if !overlaps(c, from, to) {
                        kept.push(c.clone());
                        continue;
                    }
                    let (parts, inside) = self.cut_clip(c, from, to);
                    kept.extend(parts);
                    moved.extend(inside);
                }
                kept.sort_by(|a, b| a.start.total_cmp(&b.start).then(a.id.cmp(&b.id)));
                stay.push((song_id, kept.into_iter().collect()));
                inner.clips = moved.into_iter().collect();
                inner.cues = Clips::new();
                inner.armed = false;
                inner.monitor = false;
                inner.source = None;
                inner.origin = None;
                inner.chain_source = None;
                inner.chain_origin = None;
                // Copies of its devices, and of its lanes in the time.
                let mut devices: HashMap<Id, Id> = HashMap::new();
                inner.devices = t
                    .devices
                    .iter()
                    .map(|d| {
                        let copy = DeviceInst { id: self.doc.new_id(), ..(**d).clone() };
                        devices.insert(d.id, copy.id);
                        Arc::new(copy)
                    })
                    .collect();
                let place = [(-from, 0.0, to - from)];
                inner.lanes = t
                    .lanes
                    .iter()
                    .map(|l| {
                        let mut lane = placed_lane(l, &place);
                        lane.id = self.doc.new_id();
                        lane.target = match &lane.target {
                            Target::Param { device, param } => Target::Param {
                                device: devices.get(device).copied().unwrap_or(*device),
                                param: param.clone(),
                            },
                            Target::State { device } => Target::State { device: devices.get(device).copied().unwrap_or(*device) },
                            other => other.clone(),
                        };
                        Arc::new(lane)
                    })
                    .collect();
            }
            let p = &self.doc.project;
            let name_of = |id: Id| p.track(id).map_or_else(|| id.to_string(), |t| t.name.clone());
            // Where it plays: inside, or into the master.
            inner.output = t.output.and_then(|o| ids.get(&o).copied());
            // Its sends to tracks that stay out become the return row's.
            let mut sends = Vec::new();
            for s in &t.sends {
                match ids.get(&s.target) {
                    Some(&target) => sends.push(Send { target, ..s.clone() }),
                    None if s.target == row_id => {}
                    None => {
                        if !row.sends.iter().any(|r| r.target == s.target) {
                            row.sends.push(s.clone());
                        }
                        changes.push(format!(
                            "the send of {} to {} ({:+} dB) is now {}'s",
                            t.name,
                            name_of(s.target),
                            s.level,
                            row.name
                        ));
                    }
                }
            }
            inner.sends = sends;
            for d in inner.devices.iter_mut() {
                if d.sidechain.is_some() || !d.outputs.is_empty() {
                    let d = Arc::make_mut(d);
                    d.sidechain = d.sidechain.and_then(|s| ids.get(&s).copied());
                    d.outputs = d.outputs.iter().filter_map(|(k, o)| ids.get(o).map(|o| (*k, *o))).collect();
                }
            }
            match group_of(&t).and_then(|g| ids.get(&g)) {
                Some(&g) => {
                    inner.meta.insert("group".into(), json!(g));
                }
                None => {
                    inner.meta.remove("group");
                }
            }
            // Its VCAs move the return row.
            if let Some(list) = inner.meta.remove("vcas").as_ref().and_then(Value::as_array) {
                for v in list.iter().filter_map(Value::as_u64) {
                    if !vcas.contains(&v) {
                        vcas.push(v);
                        changes.push(format!("the VCA {} now moves {}", name_of(v), row.name));
                    }
                }
            }
            made.push(Arc::new(inner));
        }
        if !vcas.is_empty() {
            row.meta.insert("vcas".into(), json!(vcas));
        }
        let tracks: Vec<Id> = made.iter().skip(1).map(|t| t.id).collect();
        let first = order.first().map(|t| t.id).context("nothing to save")?;
        let id = nest.id;
        let fresh_row = head.is_none();
        let mut p = self.doc.project.clone();
        for (song_id, clips) in stay {
            p.track_mut(song_id).context("no track")?.clips = clips;
        }
        // What played into a track that moved now plays into the row.
        let into = |id: &Id| moved.contains(id);
        for t in p.tracks.iter_mut().filter(|t| !into(&t.id) && t.id != row_id) {
            if t.output.as_ref().is_some_and(into) || t.sends.iter().any(|s| into(&s.target)) {
                let t = Arc::make_mut(t);
                if t.output.as_ref().is_some_and(into) {
                    t.output = Some(row_id);
                }
                for s in t.sends.iter_mut().filter(|s| into(&s.target)) {
                    s.target = row_id;
                }
            }
        }
        // The row at the place of the first track that goes in, the
        // subproject's tracks at the end of the list.
        let at = p.tracks.iter().position(|t| t.id == first).unwrap_or(p.tracks.len());
        let row = Arc::new(row);
        let mut list: Vec<Arc<Track>> = Vec::with_capacity(p.tracks.len() + made.len() + 1);
        for (i, t) in p.tracks.iter().enumerate() {
            if i == at && fresh_row {
                list.push(row.clone());
            }
            if t.id == row_id {
                list.push(row.clone());
            } else if !into(&t.id) {
                list.push(t.clone());
            }
        }
        list.extend(made);
        p.tracks = list;
        p.nests.insert(id, Arc::new(nest));
        p.validate()?;
        self.edit(|project| {
            *project = p;
            Ok(())
        })?;
        Ok(Saved { nest: id, rows: Vec::new(), row: Some(row_id), tracks, changes })
    }
}
