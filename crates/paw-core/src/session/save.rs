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
//! With a row of its own, a track moves into the subproject whole (its
//! devices are the same instances) when all of it is in the time and
//! everything that plays into it moves too. Any other track with clips in
//! the time stays in the song with the rest of its clips, and a copy goes
//! in: its clips in the time, and copies of its devices and of its lanes
//! there. So a route of the song never changes because a track left: a
//! group or a bus that the song still plays into stays. One new return row
//! plays the mix, into the bus that the tracks played into, and inside its
//! group when that bus is a group. A view of one group whose tracks all
//! move makes the group track the return row. Routes at the boundary
//! change as 4.7 says, and each change is told.

use super::*;
use std::collections::HashSet;

use crate::model::nest::{placed_clip, placed_lane};
use crate::model::{Clip, Clips, Nest, NestId, NestMeter, NestTempo, Send, Target};

/// Two beats closer than this are one.
const EPS: f64 = 1e-9;

/// What [`Session::nest_save`] takes.
#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct SaveOpts {
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
pub(crate) struct HostRow {
    pub row: Id,
    pub track: Id,
}

/// What [`Session::nest_save`] did, for the Lua side and its message.
#[derive(Debug, Serialize)]
pub(crate) struct Saved {
    pub nest: NestId,
    /// Per track: each row that gets a block.
    pub rows: Vec<HostRow>,
    /// With a row of its own: the return row.
    pub row: Option<Id>,
    /// The subproject's tracks, without its master, in order.
    pub tracks: Vec<Id>,
    /// The routes that changed at the boundary, in words.
    pub changes: Vec<String>,
    /// With a row of its own: the song's group that the return row is in.
    pub group: Option<Id>,
    /// With a row of its own that plays into the master because the tracks
    /// played into several buses: those buses, which no longer process the
    /// time. The row's meta `nest_buses` keeps the bus of each track, for
    /// `:nest.outputs stems`.
    pub buses: Vec<Id>,
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

/// Whether track `f` plays into track `id`: its output, a send, a device's
/// output pair, or as a member of the group `id`.
fn feeds(f: &Track, id: Id) -> bool {
    f.output == Some(id)
        || group_of(f) == Some(id)
        || f.sends.iter().any(|s| s.target == id)
        || f.devices.iter().any(|d| d.outputs.values().any(|o| *o == id))
}

/// The tracks of `selected` that move into the subproject whole: all of
/// each is in the time, and every track that plays into it moves whole
/// too. A track that a track of the song still plays into (a group with
/// members outside the time, a bus that the rest of the song sends to)
/// stays, so that no route of the song changes.
fn whole_tracks(p: &Project, selected: &[Arc<Track>], from: f64, to: f64) -> HashSet<Id> {
    let mut whole: HashSet<Id> = selected.iter().filter(|t| inside(t, from, to)).map(|t| t.id).collect();
    // Remove each track that a track outside the set plays into, until
    // none is left: a removal can make another track lose its place.
    loop {
        let fed: Vec<Id> = whole
            .iter()
            .copied()
            .filter(|&id| p.all_tracks().any(|f| f.id != id && !whole.contains(&f.id) && feeds(f, id)))
            .collect();
        if fed.is_empty() {
            return whole;
        }
        for id in fed {
            whole.remove(&id);
        }
    }
}

/// Whether track `t` is inside group `g`, at any depth.
fn in_group(p: &Project, t: &Track, g: Id) -> bool {
    let mut at = group_of(t);
    for _ in 0..32 {
        match at {
            Some(id) if id == g => return true,
            Some(id) => at = p.track(id).and_then(|t| group_of(t)),
            None => return false,
        }
    }
    false
}

/// The outermost group that track `t` is inside, or `t` itself.
fn outermost(p: &Project, t: &Track) -> Id {
    let mut top = t.id;
    let mut at = group_of(t);
    for _ in 0..32 {
        match at.and_then(|g| p.track(g)) {
            Some(g) => {
                top = g.id;
                at = group_of(g);
            }
            None => break,
        }
    }
    top
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
    pub(crate) fn nest_save(&mut self, opts: SaveOpts) -> Result<Saved> {
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
        let place = self.doc.project.view_place(&opts.tracks)?;
        self.doc.project.check_cuts(&opts.tracks, from, to)?;
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
        self.doc.edit(|project| {
            *project = p;
            Ok(())
        })?;
        Ok(Saved { nest: id, rows, row: None, tracks, changes: Vec::new(), group: None, buses: Vec::new() })
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
        let whole = whole_tracks(p, &selected, from, to);
        let head = selected.first().filter(|g| {
            is_group(g)
                && g.clips.is_empty()
                && whole.contains(&g.id)
                && selected[1..].iter().all(|t| in_group(p, t, g.id) && whole.contains(&t.id))
        });
        let head = head.map(|g| g.id);
        // The tracks that go in: whole ones, and those with clips in the
        // time. A group that stays (members outside the time) does not go
        // in: its members inside play into the subproject's master, and the
        // return row plays into the group, so its devices act once.
        let taken: HashSet<Id> = selected
            .iter()
            .filter(|t| Some(t.id) != head)
            .filter(|t| whole.contains(&t.id) || t.clips.iter().any(|c| overlaps(c, from, to)))
            .map(|t| t.id)
            .collect();
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
        let fresh_id = self.doc.new_id();
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
        // The return row, and the buses that no longer get the time.
        let mut changes = Vec::new();
        let mut buses = Vec::new();
        let mut row = match head.and_then(|h| p.track(h)) {
            Some(g) => {
                let mut row = (**g).clone();
                row.meta.remove("group_head");
                row.meta.remove("group_folded");
                row
            }
            None => {
                let mut row = Track::new(fresh_id);
                row.name = nest.name.clone();
                row.nest = place;
                // Where the tracks that leave played: one place, else the
                // master, and the buses that the time no longer goes through.
                let outs: BTreeSet<Option<Id>> = order
                    .iter()
                    .filter(|t| t.output.is_none_or(|o| !taken.contains(&o)))
                    .map(|t| t.output)
                    .collect();
                if outs.len() == 1 {
                    row.output = outs.into_iter().next().flatten();
                    if let Some(g) = row.output.and_then(|o| p.track(o)).filter(|g| is_group(g)) {
                        row.meta.insert("group".into(), json!(g.id));
                    }
                } else {
                    buses.extend(outs.into_iter().flatten());
                    let of_track: Map<String, Value> = order
                        .iter()
                        .filter_map(|t| t.output.filter(|o| buses.contains(o)).map(|o| (ids[&t.id].to_string(), json!(o))))
                        .collect();
                    row.meta.insert("nest_buses".into(), Value::Object(of_track));
                }
                row
            }
        };
        let row_group = group_of(&row).filter(|_| head.is_none());
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
                            "the send {} → {} ({:+} dB) is now {}'s",
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
        // A track that moved whole leaves the song's list; nothing that
        // stays plays into it (`whole_tracks`).
        let into = |id: &Id| moved.contains(id);
        // The row after the last track of its group; else above the first
        // track that goes in, or above the outermost group of that track,
        // so that it does not split a group. The subproject's tracks go at
        // the end of the list.
        let row = Arc::new(row);
        let mut list: Vec<Arc<Track>> = Vec::with_capacity(p.tracks.len() + made.len() + 1);
        let mut slot = None;
        for t in p.tracks.iter() {
            if t.id == first {
                slot = Some(list.len());
            }
            if t.id == row_id {
                list.push(row.clone());
            } else if !into(&t.id) {
                list.push(t.clone());
            }
        }
        if fresh_row {
            let at = match row_group {
                Some(g) => list.iter().rposition(|t| t.id == g || in_group(&p, t, g)).map_or(list.len(), |i| i + 1),
                None => {
                    let top = p.track(first).map_or(first, |t| outermost(&p, t));
                    let above_group = if top == first { None } else { list.iter().position(|t| t.id == top) };
                    above_group.or(slot).unwrap_or(list.len())
                }
            };
            list.insert(at, row.clone());
        }
        list.extend(made);
        p.tracks = list;
        p.nests.insert(id, Arc::new(nest));
        p.validate()?;
        self.doc.edit(|project| {
            *project = p;
            Ok(())
        })?;
        Ok(Saved { nest: id, rows: Vec::new(), row: Some(row_id), tracks, changes, group: row_group, buses })
    }
}
