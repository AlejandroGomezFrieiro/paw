//! Promote a subproject to a view (`nest.md` 3.9): its parts come back
//! into the song in a group named after it, at the place of its return
//! row. The Lua side (`paw.nest.promote`) adds what is not part data: the
//! regions, the meter in the song's map and the view that remains.

use super::*;
use std::collections::HashSet;

use crate::model::nest::placed_lane;
use crate::model::{ClipContent, Lane, NestId, NestPlay, Target};

/// What [`Session::nest_promote`] did, for the Lua side and its message.
#[derive(Debug, Serialize)]
pub(crate) struct Promoted {
    /// The group part that took the place of the return row; none for a
    /// subproject saved per part.
    pub group: Option<Id>,
    /// The subproject's parts, now the song's (or the place's), in order;
    /// per part, the rows its clips went back to.
    pub parts: Vec<Id>,
    /// The song's beats where the block's window starts and ends.
    pub from: f64,
    pub to: f64,
    /// The song's beat of the subproject's beat 0.
    pub zero: f64,
    /// The targets of lanes that the return row and the subproject's
    /// master both had, now one lane of the group part.
    pub combined: Vec<String>,
}

/// A block of a subproject saved per part: its row, the clip, and the
/// part of the subproject that it plays.
struct RowBlock {
    row: Id,
    clip: Id,
    part: Id,
}

/// The block that a promote starts from, and where it is.
struct Block {
    nest: NestId,
    row: Id,
    zero: f64,
    from: f64,
    to: f64,
    /// The row holds other blocks: it stays, without this one, and the
    /// group goes after it with copies of its devices and lanes.
    keep_row: bool,
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
        let p = &self.doc.project;
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
            .all_parts()
            .flat_map(|t| t.clips.iter())
            .filter(|o| o.id != clip && matches!(&o.content, ClipContent::Nest { nest: n, .. } if n == nest))
            .map(|o| o.start)
            .collect();
        if let Some(at) = others.first() {
            let bar = p.tempo_map().bar_of(*at) + 1;
            bail!("{name} plays at bar {bar} too: promote works on a subproject with one block for now");
        }
        let held = p.part(row).context("no row")?;
        // Blocks of other subprojects may share the row (a block made a
        // subproject of its own with `:nest.unique`): the row stays for them.
        if held.clips.iter().any(|o| o.id != clip && !matches!(o.content, ClipContent::Nest { .. })) {
            bail!("the row {} holds other clips besides the block: move them first", held.name);
        }
        let keep_row = held.clips.len() > 1;
        Ok(Block { nest: *nest, row, zero: c.start - offset, from: c.start, to: c.start + c.length, keep_row })
    }

    /// Promote the subproject of block `clip` (see the module): its parts
    /// become parts of the place of its return row, in a group named after
    /// it at the row's place, their clips at the row's beats and cut at the
    /// block. The group part gets the master's devices, then the row's
    /// (the same instances), the sum of their faders in dB, the row's pan,
    /// sends, output, mute and colour, and their lanes (volume lanes added
    /// in dB). The row, the master and the subproject go. One undo step.
    #[expect(clippy::too_many_lines, reason = "a sequence of steps in one place; the split into named steps is open work")]
    pub(crate) fn nest_promote(&mut self, clip: Id) -> Result<Promoted> {
        if let Some((b, blocks)) = self.per_part_blocks(clip)? {
            return self.promote_per_part(b, blocks);
        }
        let b = self.promote_block(clip)?;
        let group_id = self.doc.new_id();
        let p = &self.doc.project;
        let nest = p.nest(b.nest).context("no subproject")?.clone();
        let row = p.part(b.row).context("no row")?.clone();
        let master = p.part(nest.master).context("no master")?.clone();
        // The group part: the row's place, name and mix, and the master's devices first.
        let mut group = (*row).clone();
        group.id = group_id;
        group.name = nest.name.clone();
        group.clips = Default::default();
        // The row's devices and lanes move to the group, or are copied when
        // the row stays.
        let (row_devices, row_lanes) = if b.keep_row {
            self.doc.copy_devices_and_lanes(&row, &Default::default())
        } else {
            (row.devices.clone(), row.lanes.clone())
        };
        if b.keep_row {
            group.chain = row
                .chain
                .as_ref()
                .map(|g| Arc::new(self.doc.copy_chain(g, &row.devices, &row_devices)));
        }
        let p = &self.doc.project;
        group.devices = master.devices.iter().chain(row_devices.iter()).cloned().collect();
        group.volume = master.volume + row.volume;
        group.meta.insert("group_head".into(), json!(true));
        let mut combined = Vec::new();
        let mut lanes: Vec<Arc<Lane>> = row_lanes;
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
        // The subproject's parts, now the place's, their clips in the song's time.
        let mut members = Vec::new();
        for t in p.nest_parts(b.nest).filter(|t| t.id != nest.master) {
            let mut moved = (**t).clone();
            moved.nest = row.nest;
            if moved.output.is_none_or(|o| o == nest.master) {
                moved.output = Some(group_id);
            }
            if moved.parent.is_none() {
                moved.parent = Some(group_id);
            }
            moved.clips = t
                .clips
                .iter()
                .filter_map(|c| crate::model::nest::placed_clip(c, b.zero, b.from, b.to, c.id).map(Arc::new))
                .collect();
            moved.lanes = t.lanes.iter().map(|l| Arc::new(placed_lane(l, &place))).collect();
            members.push(Arc::new(moved));
        }
        let parts: Vec<Id> = members.iter().map(|t| t.id).collect();
        let at = p.parts.iter().position(|t| t.id == b.row).context("no row")? + usize::from(b.keep_row);
        self.doc.edit(|p| {
            let gone: HashSet<Id> = p
                .nest_parts(b.nest)
                .map(|t| t.id)
                .chain((!b.keep_row).then_some(b.row))
                .collect();
            let mut list: Vec<Arc<Part>> = Vec::with_capacity(p.parts.len() + members.len() + 1);
            for (i, t) in p.parts.iter().enumerate() {
                if i == at {
                    list.push(Arc::new(group.clone()));
                    list.extend(members.iter().cloned());
                }
                if !gone.contains(&t.id) {
                    list.push(t.clone());
                }
            }
            if at == p.parts.len() {
                list.push(Arc::new(group.clone()));
                list.extend(members.iter().cloned());
            }
            p.parts = list;
            if b.keep_row {
                // The row keeps its other blocks, and what plays into it.
                if let Some(row) = p.part_mut(b.row) {
                    row.clips = row.clips.iter().filter(|c| c.id != clip).cloned().collect();
                }
                p.nests.remove(&b.nest);
                return Ok(());
            }
            // What played into the row now plays into the group.
            for t in p.parts.iter_mut() {
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
        Ok(Promoted { group: Some(group_id), parts, from: b.from, to: b.to, zero: b.zero, combined })
    }

    /// The blocks of a subproject saved per part (`<Space>zw`), when
    /// `clip` is one: each row and the part its block plays. None for a
    /// block of the mix or of a stem row.
    fn per_part_blocks(&self, clip: Id) -> Result<Option<(Block, Vec<RowBlock>)>> {
        let p = &self.doc.project;
        let (row, _) = p.find_clip(clip).with_context(|| format!("no clip {clip}"))?;
        let c = p.clip(clip).with_context(|| format!("no clip {clip}"))?;
        let is_stem_row = |row: Id| p.part(row).is_some_and(|t| t.meta.contains_key("nest_stem"));
        let ClipContent::Nest { nest, offset, play: NestPlay::Part(_) } = &c.content else {
            return Ok(None);
        };
        if is_stem_row(row) {
            return Ok(None);
        }
        let held = p.nest(*nest).context("its subproject is gone")?;
        let block = Block { nest: *nest, row, zero: c.start - offset, from: c.start, to: c.start + c.length, keep_row: false };
        let mut blocks = Vec::new();
        for t in p.all_parts() {
            for o in t.clips.iter() {
                let ClipContent::Nest { nest: n, offset: off, play } = &o.content else {
                    continue;
                };
                if n != nest {
                    continue;
                }
                let same = (o.start - c.start).abs() < 1e-9 && (o.length - c.length).abs() < 1e-9 && (off - offset).abs() < 1e-9;
                match play {
                    NestPlay::Part(part) if same && !is_stem_row(t.id) => blocks.push(RowBlock { row: t.id, clip: o.id, part: *part }),
                    _ => {
                        let bar = p.tempo_map().bar_of(o.start) + 1;
                        bail!(
                            "{} plays at bar {bar} on {} too: promote works on a subproject with one place for now",
                            held.name,
                            t.name
                        );
                    }
                }
            }
        }
        for t in p.nest_parts(*nest).filter(|t| t.id != held.master) {
            if !crate::sync::passes(t) {
                bail!(
                    "{} in {} has a sound of its own (devices, fader, pan or lanes): its clips cannot go back to a row as they are",
                    t.name,
                    held.name
                );
            }
            if !t.clips.is_empty() && !blocks.iter().any(|b| b.part == t.id) {
                bail!("{} in {} has clips that no block plays", t.name, held.name);
            }
        }
        Ok(Some((block, blocks)))
    }

    /// Promote a subproject saved per part: the clips of each of its
    /// parts go back to the row of the block that plays it, cut at the
    /// block; the blocks, the subproject and its parts go.
    fn promote_per_part(&mut self, b: Block, blocks: Vec<RowBlock>) -> Result<Promoted> {
        let mut p = self.doc.project.clone();
        let gone_clips: HashSet<Id> = blocks.iter().map(|x| x.clip).collect();
        let mut rows = Vec::new();
        for RowBlock { row, part, .. } in &blocks {
            let source = p.part(*part).context("no part")?.clone();
            let t = p.part_mut(*row).context("no row")?;
            let mut list: Vec<Arc<crate::model::Clip>> =
                t.clips.iter().filter(|c| !gone_clips.contains(&c.id)).cloned().collect();
            list.extend(
                source
                    .clips
                    .iter()
                    .filter_map(|c| crate::model::nest::placed_clip(c, b.zero, b.from, b.to, c.id).map(Arc::new)),
            );
            list.sort_by(|a, b| a.start.total_cmp(&b.start).then(a.id.cmp(&b.id)));
            t.clips = list.into_iter().collect();
            if !rows.contains(row) {
                rows.push(*row);
            }
        }
        p.parts.retain(|t| t.nest != Some(b.nest));
        p.nests.remove(&b.nest);
        p.validate()?;
        self.doc.edit(|project| {
            *project = p;
            Ok(())
        })?;
        Ok(Promoted { group: None, parts: rows, from: b.from, to: b.to, zero: b.zero, combined: Vec::new() })
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
