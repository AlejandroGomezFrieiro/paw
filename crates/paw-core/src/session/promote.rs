//! Promote a subproject to a view (`nest.md` 3.9): its tracks come back
//! into the song in a group named after it, at the place of its return
//! row. The Lua side (`paw.nest.promote`) adds what is not track data: the
//! regions, the meter in the song's map and the view that remains.

use super::*;
use std::collections::HashSet;

use crate::model::nest::placed_lane;
use crate::model::{ClipContent, Lane, NestId, NestPlay, Target};

/// What [`Session::nest_promote`] did, for the Lua side and its message.
#[derive(Debug, Serialize)]
pub struct Promoted {
    /// The group track that took the place of the return row.
    pub group: Id,
    /// The subproject's tracks, now the song's (or the place's), in order.
    pub tracks: Vec<Id>,
    /// The song's beats where the block's window starts and ends.
    pub from: f64,
    pub to: f64,
    /// The song's beat of the subproject's beat 0.
    pub zero: f64,
    /// The targets of lanes that the return row and the subproject's
    /// master both had, now one lane of the group track.
    pub combined: Vec<String>,
}

/// The block that a promote starts from, and where it is.
struct Block {
    nest: NestId,
    row: Id,
    zero: f64,
    from: f64,
    to: f64,
}

/// Two volume lanes as one: at each point of either, the sum of their dB.
fn summed(a: &Lane, b: &Lane) -> Lane {
    let mut beats: Vec<f64> = a.points.iter().chain(b.points.iter()).map(|p| p.0).collect();
    beats.sort_by(f64::total_cmp);
    beats.dedup_by(|x, y| (*x - *y).abs() < 1e-9);
    Lane {
        points: beats.iter().map(|&t| (t, a.value_at(t) + b.value_at(t))).collect(),
        shapes: Vec::new(),
        ..a.clone()
    }
}

fn target_name(t: &Target) -> String {
    match t {
        Target::Volume => "volume".into(),
        Target::Pan => "pan".into(),
        Target::Param { param, .. } => param.clone(),
        Target::State { .. } => "state".into(),
    }
}

impl Session {
    /// The block `clip` checked for a promote.
    fn promote_block(&self, clip: Id) -> Result<Block> {
        let p = &self.project;
        let (row, _) = p.find_clip(clip).with_context(|| format!("no clip {clip}"))?;
        let c = p.clip(clip).with_context(|| format!("no clip {clip}"))?;
        let ClipContent::Nest { nest, offset, play } = &c.content else {
            bail!("not a block of a subproject");
        };
        let name = &p.nest(*nest).context("its subproject is gone")?.name;
        if *play != NestPlay::Master {
            bail!("a stem row: `:nest.outputs master` first, then promote {name} on its row");
        }
        let others: Vec<f64> = p
            .all_tracks()
            .flat_map(|t| t.clips.iter())
            .filter(|o| o.id != clip && matches!(&o.content, ClipContent::Nest { nest: n, .. } if n == nest))
            .map(|o| o.start)
            .collect();
        if let Some(at) = others.first() {
            let bar = p.tempo_map().bar_of(*at) + 1;
            bail!("{name} plays at bar {bar} too: promote works on a subproject with one block for now");
        }
        let held = p.track(row).context("no row")?;
        if held.clips.len() > 1 {
            bail!("the row {} holds other clips besides the block: move them first", held.name);
        }
        Ok(Block { nest: *nest, row, zero: c.start - offset, from: c.start, to: c.start + c.length })
    }

    /// Promote the subproject of block `clip` (see the module): its tracks
    /// become tracks of the place of its return row, in a group named after
    /// it at the row's place, their clips at the row's beats and cut at the
    /// block. The group track gets the master's devices, then the row's
    /// (the same instances), the sum of their faders in dB, the row's pan,
    /// sends, output, mute and colour, and their lanes (volume lanes added
    /// in dB). The row, the master and the subproject go. One undo step.
    pub fn nest_promote(&mut self, clip: Id) -> Result<Promoted> {
        let b = self.promote_block(clip)?;
        let group_id = self.new_id();
        let p = &self.project;
        let nest = p.nest(b.nest).context("no subproject")?.clone();
        let row = p.track(b.row).context("no row")?.clone();
        let master = p.track(nest.master).context("no master")?.clone();
        // The group track: the row's place, name and mix, and the master's devices first.
        let mut group = (*row).clone();
        group.id = group_id;
        group.name = nest.name.clone();
        group.clips = Default::default();
        group.devices = master.devices.iter().chain(row.devices.iter()).cloned().collect();
        group.volume = master.volume + row.volume;
        group.meta.insert("group_head".into(), json!(true));
        let mut combined = Vec::new();
        let mut lanes: Vec<Arc<Lane>> = row.lanes.clone();
        let place = [(b.zero, b.from, b.to)];
        for lane in &master.lanes {
            let moved = placed_lane(lane, &place);
            match lanes.iter_mut().find(|l| l.target == moved.target) {
                Some(have) if moved.target == Target::Volume => {
                    *have = Arc::new(summed(have, &moved));
                    combined.push(target_name(&moved.target));
                }
                // The row's pan and its other lanes win: the row is what the song heard last.
                Some(_) => combined.push(target_name(&moved.target)),
                None => lanes.push(Arc::new(moved)),
            }
        }
        group.lanes = lanes;
        // The subproject's tracks, now the place's, their clips in the song's time.
        let mut members = Vec::new();
        for t in p.nest_tracks(b.nest).filter(|t| t.id != nest.master) {
            let mut moved = (**t).clone();
            moved.nest = row.nest;
            if moved.output.is_none_or(|o| o == nest.master) {
                moved.output = Some(group_id);
            }
            if !moved.meta.contains_key("group") {
                moved.meta.insert("group".into(), json!(group_id));
            }
            moved.clips = t
                .clips
                .iter()
                .filter_map(|c| crate::model::nest::placed_clip(c, b.zero, b.from, b.to, c.id).map(Arc::new))
                .collect();
            moved.lanes = t.lanes.iter().map(|l| Arc::new(placed_lane(l, &place))).collect();
            members.push(Arc::new(moved));
        }
        let tracks: Vec<Id> = members.iter().map(|t| t.id).collect();
        let at = p.tracks.iter().position(|t| t.id == b.row).context("no row")?;
        self.edit(|p| {
            let gone: HashSet<Id> = p
                .nest_tracks(b.nest)
                .map(|t| t.id)
                .chain(std::iter::once(b.row))
                .collect();
            let mut list: Vec<Arc<Track>> = Vec::with_capacity(p.tracks.len());
            for (i, t) in p.tracks.iter().enumerate() {
                if i == at {
                    list.push(Arc::new(group.clone()));
                    list.extend(members.iter().cloned());
                }
                if !gone.contains(&t.id) {
                    list.push(t.clone());
                }
            }
            p.tracks = list;
            // What played into the row now plays into the group.
            for t in p.tracks.iter_mut() {
                if t.output == Some(b.row) || t.sends.iter().any(|s| s.target == b.row) {
                    let t = Arc::make_mut(t);
                    if t.output == Some(b.row) {
                        t.output = Some(group_id);
                    }
                    for s in t.sends.iter_mut().filter(|s| s.target == b.row) {
                        s.target = group_id;
                    }
                }
            }
            p.nests.remove(&b.nest);
            Ok(())
        })?;
        Ok(Promoted { group: group_id, tracks, from: b.from, to: b.to, zero: b.zero, combined })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Clip;

    fn lane(points: &[(f64, f64)]) -> Lane {
        Lane {
            id: 1,
            target: Target::Volume,
            enabled: true,
            points: points.to_vec(),
            shapes: Vec::new(),
            states: Vec::new(),
        }
    }

    #[test]
    fn a_lane_of_a_nest_plays_at_its_place_with_its_values_at_the_edges() {
        let placed = placed_lane(&lane(&[(0.0, -6.0), (12.0, 0.0)]), &[(128.0, 130.0, 152.0)]);
        assert_eq!(placed.points, vec![(130.0, -5.0), (140.0, 0.0), (152.0, 0.0)]);
    }

    #[test]
    fn a_clip_cut_at_the_block_keeps_the_notes_inside() {
        let clip: Clip = serde_json::from_value(json!({ "id": 5, "name": "", "start": 0.0, "length": 4.0,
            "muted": false, "content": { "kind": "midi", "controls": [], "notes": [
                { "start": 0.0, "length": 1.0, "pitch": 60, "velocity": 100 },
                { "start": 3.0, "length": 1.0, "pitch": 62, "velocity": 100 } ] } }))
        .expect("a clip");
        let placed = crate::model::nest::placed_clip(&clip, 32.0, 34.0, 40.0, 5).expect("inside");
        assert_eq!((placed.start, placed.length), (34.0, 2.0));
        let ClipContent::Midi { notes, .. } = &placed.content else { panic!("a MIDI clip") };
        assert_eq!(notes.iter().map(|n| (n.start, n.pitch)).collect::<Vec<_>>(), vec![(1.0, 62)]);
    }
}
