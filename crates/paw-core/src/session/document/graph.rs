//! The edits of a track's devices graph (`model/graph.rs`) and of linked
//! racks (`model/racks.rs`). Each is one undo step, and each refuses a
//! graph that `Graph::validate` refuses, with its message, and changes
//! nothing then.
//!
//! The first edit of a track with no graph makes the graph of its devices
//! in series. An edit inside a linked rack that changes its parts (not a
//! value) changes the rack's definition, and so each other instance.

use std::collections::{BTreeSet, HashSet};
use std::sync::Arc;

use anyhow::{Context, Result, anyhow, bail};
use serde::Deserialize;
use serde_json::{Map, Value};

use super::Document;
use crate::model::graph::{Branch, Graph, KindSpec, Macro, Node, Split, Tap, Zone, fit_track};
use crate::model::{DeviceInst, Id, Project, Word};
use crate::session::{de, de_meta};

/// Where a node goes: before or after a node, or into a branch at an index
/// (from 0; past the end for the end). Lua gives `{ before = id }`,
/// `{ after = id }` or `{ branch = id, index = n }`.
#[derive(Clone, Debug, Default, Deserialize)]
pub struct Place {
    pub before: Option<Id>,
    pub after: Option<Id>,
    pub branch: Option<Id>,
    pub index: Option<usize>,
}

/// What a wrap makes, besides its kind.
#[derive(Clone, Debug, Default, Deserialize)]
pub struct WrapOpts {
    /// How many branches; the kind's first count when not given.
    pub branches: Option<usize>,
    pub name: Option<String>,
    /// Values of the kind, over its first values.
    #[serde(default)]
    pub values: Map<String, Value>,
}

impl Place {
    /// The branch and the index in it that the place names in `graph`.
    fn resolve(&self, graph: &Graph) -> Result<(Id, usize)> {
        let near = |id: Id, after: usize| {
            graph
                .root
                .place_of(id)
                .map(|(branch, at)| (branch, at + after))
                .with_context(|| format!("no node {id} in the graph"))
        };
        match (self.before, self.after, self.branch) {
            (Some(id), None, None) => near(id, 0),
            (None, Some(id), None) => near(id, 1),
            (None, None, Some(branch)) => {
                let b = graph.root.branch(branch).with_context(|| format!("no branch {branch} in the graph"))?;
                Ok((branch, self.index.unwrap_or(usize::MAX).min(b.nodes.len())))
            }
            _ => bail!("a place is one of {{ before = id }}, {{ after = id }} or {{ branch = id, index = n }}"),
        }
    }
}

/// The ids of the linked racks that hold any of `ids`, or are one of them.
fn linked_around(graph: &Graph, ids: &[Id]) -> BTreeSet<Id> {
    ids.iter().flat_map(|id| graph.root.path_to(*id)).filter(|s| s.linked.is_some()).map(|s| s.id).collect()
}

impl Document {
    /// An edit of the graph of `track`: `f` changes a copy of it (the
    /// devices in series when the track has none), and may add devices to
    /// the track. The devices that leave the graph leave the track, with
    /// their lanes. The result must pass `Graph::validate`. With
    /// `structural`, a linked rack around one of `touched` (before or
    /// after) gives its new parts to its definition.
    fn graph_edit<R>(
        &mut self,
        track: Id,
        touched: &[Id],
        structural: bool,
        f: impl FnOnce(&mut Graph, &mut Vec<DeviceInst>, &mut dyn FnMut() -> Id) -> Result<R>,
    ) -> Result<R> {
        let kinds = self.split_kinds.clone();
        let mut next = self.next_id;
        let result = self.edit(|p| {
            let mut new_id = || {
                next += 1;
                next - 1
            };
            let t = p.track(track).with_context(|| format!("no track {track}"))?;
            let mut graph = match &t.graph {
                Some(graph) => (**graph).clone(),
                None => Graph::serial(t.devices.iter().map(|d| d.id), &mut new_id),
            };
            let before: HashSet<Id> = graph.devices().into_iter().collect();
            let mut linked = if structural { linked_around(&graph, touched) } else { BTreeSet::new() };
            let mut added = Vec::new();
            let result = f(&mut graph, &mut added, &mut new_id)?;
            let after: HashSet<Id> = graph.devices().into_iter().collect();
            let gone: HashSet<Id> = before.difference(&after).copied().collect();
            let mut ids: Vec<Id> = t.devices.iter().map(|d| d.id).filter(|id| !gone.contains(id)).collect();
            ids.extend(added.iter().map(|d| d.id));
            graph.validate(&ids, &kinds).map_err(|e| anyhow!("{e}"))?;
            if structural {
                linked.extend(linked_around(&graph, touched));
            }
            let t = p.track_mut(track).context("no track")?;
            t.devices.retain(|d| !gone.contains(&d.id));
            t.lanes.retain(|l| l.target.device().is_none_or(|d| !gone.contains(&d)));
            t.devices.extend(added.into_iter().map(Arc::new));
            t.graph = Some(Arc::new(graph));
            fit_track(t);
            for split in linked {
                if p.graph_track(split).is_some() {
                    p.rack_apply(split, true, &mut new_id)?;
                }
            }
            Ok(result)
        });
        self.next_id = self.next_id.max(next);
        result
    }

    /// The track whose graph (or chain, for a device of a track with no
    /// graph) holds `id`.
    fn graph_track_of(&self, id: Id) -> Result<Id> {
        self.project
            .graph_track(id)
            .or_else(|| self.project.find_device(id).map(|(track, _)| track))
            .with_context(|| format!("no node {id} in a graph"))
    }

    /// Wrap the nodes `nodes` (one or more in a row of one branch, in any
    /// order) in a new split of `kind`. They go into its first branch.
    /// Gives the split's id.
    pub fn graph_wrap(&mut self, nodes: &[Id], kind: &str, opts: WrapOpts) -> Result<Id> {
        let first = *nodes.first().context("nothing to wrap")?;
        let track = self.graph_track_of(first)?;
        let count = match opts.branches {
            Some(n) => n,
            None => self.split_kinds.first_branches(kind).map_err(|e| anyhow!("{e}"))?,
        };
        let (word, mut values) = self.split_kinds.new_split_kind(kind, count).map_err(|e| anyhow!("{e}"))?;
        values.extend(opts.values);
        self.graph_edit(track, nodes, true, |graph, _, new_id| {
            let (branch, mut places) = (graph.root.place_of(first).map(|(b, _)| b), Vec::new());
            for id in nodes {
                match graph.root.place_of(*id) {
                    Some((b, at)) if Some(b) == branch => places.push(at),
                    Some(_) => bail!("the nodes to wrap are not in one branch"),
                    None => bail!("no node {id} in the graph"),
                }
            }
            places.sort_unstable();
            places.dedup();
            if places.windows(2).any(|w| w[1] != w[0] + 1) {
                bail!("the nodes to wrap are not in a row");
            }
            let branch = graph.root.branch_mut(branch.context("no branch")?).context("no branch")?;
            let mut split = Split::new(word, values, count, new_id);
            if let Some(name) = opts.name {
                split.name = name;
            }
            let at = places[0];
            let inside: Vec<Node> = branch.nodes.drain(at..at + places.len()).collect();
            if let Some(first) = split.branches.first_mut() {
                first.nodes = inside;
            }
            let id = split.id;
            branch.nodes.insert(at, Node::Split(Box::new(split)));
            Ok(id)
        })
    }

    /// Take the split `split` away. With `keep`, the nodes of that branch
    /// take its place and the devices of the other branches leave the
    /// track; without, the branches go in its place one after the other.
    /// Gives how many devices left the track.
    pub fn graph_unwrap(&mut self, split: Id, keep: Option<Id>) -> Result<usize> {
        let track = self.graph_track_of(split)?;
        self.graph_edit(track, &[split], true, |graph, _, _| {
            if graph.root.id == split {
                bail!("the root of the graph cannot be unwrapped");
            }
            let before = graph.devices().len();
            let (branch, at) = graph.root.place_of(split).with_context(|| format!("{split} is not a split"))?;
            let Some(Node::Split(s)) = graph.root.take(split) else { bail!("{split} is not a split") };
            let nodes: Vec<Node> = match keep {
                Some(keep) => {
                    let kept = s.branches.into_iter().find(|b| b.id == keep);
                    kept.with_context(|| format!("branch {keep} is not a branch of split {split}"))?.nodes
                }
                None => s.branches.into_iter().flat_map(|b| b.nodes).collect(),
            };
            let place = graph.root.branch_mut(branch).context("no branch")?;
            place.nodes.splice(at..at, nodes);
            Ok(before - graph.devices().len())
        })
    }

    /// Add an empty branch to the split `split`, at `index` (from 0; the
    /// end when not given). Gives its id.
    pub fn graph_branch_add(&mut self, split: Id, name: Option<String>, index: Option<usize>) -> Result<Id> {
        let track = self.graph_track_of(split)?;
        self.graph_edit(track, &[split], true, |graph, _, new_id| {
            let s = graph.root.split_mut(split).with_context(|| format!("{split} is not a split"))?;
            let mut branch = Branch::new(new_id());
            branch.name = name.unwrap_or_default();
            let id = branch.id;
            let at = index.unwrap_or(usize::MAX).min(s.branches.len());
            s.branches.insert(at, branch);
            // A band split gets a crossover for its new band.
            if s.kind.as_str() == "band" {
                let count = s.branches.len();
                s.values.insert("xover".into(), serde_json::json!(crate::model::graph::default_crossovers(count)));
            }
            Ok(id)
        })
    }

    /// Move the node `id` to `place`, in the same graph.
    pub fn graph_move(&mut self, id: Id, place: &Place) -> Result<()> {
        let track = self.graph_track_of(id)?;
        let to = [place.before, place.after, place.branch].into_iter().flatten().collect::<Vec<_>>();
        self.graph_edit(track, &[&[id][..], &to].concat(), true, |graph, _, _| {
            if graph.root.id == id {
                bail!("the root of the graph cannot move");
            }
            if let Some(Node::Split(s)) =
                graph.root.place_of(id).and_then(|(b, at)| graph.root.branch(b)?.nodes.get(at))
                && to.iter().any(|t| !s.path_to(*t).is_empty())
            {
                bail!("a split cannot move into itself");
            }
            let node = graph.root.take(id).with_context(|| format!("no node {id} in the graph"))?;
            let (branch, at) = place.resolve(graph)?;
            let b = graph.root.branch_mut(branch).context("no branch")?;
            b.nodes.insert(at.min(b.nodes.len()), node);
            Ok(())
        })
    }

    /// Remove what `id` names in a graph: a split with its devices, a
    /// branch with its devices, a macro with its links, or a device.
    pub fn graph_remove(&mut self, id: Id) -> Result<()> {
        let track = self.graph_track_of(id)?;
        self.graph_edit(track, &[id], true, |graph, _, _| {
            if graph.root.id == id {
                bail!("the root of the graph cannot be removed");
            }
            if graph.root.take(id).is_some() {
                return Ok(());
            }
            let owner = graph.root.path_to(id).last().map(|s| s.id).with_context(|| format!("no {id} in the graph"))?;
            let s = graph.root.split_mut(owner).context("no split")?;
            if let Some(at) = s.branches.iter().position(|b| b.id == id) {
                s.branches.remove(at);
                if s.kind.as_str() == "band" {
                    let count = s.branches.len();
                    s.values.insert("xover".into(), serde_json::json!(crate::model::graph::default_crossovers(count)));
                }
            } else if let Some(at) = s.macros.iter().position(|m| m.id == id) {
                s.macros.remove(at);
                s.links.retain(|l| l.source != id);
            }
            Ok(())
        })
    }

    /// Set a value of the split, branch or macro `id`: see `paw.graph.set`.
    pub fn graph_set(&mut self, id: Id, key: &str, value: Value) -> Result<()> {
        let track = self.graph_track_of(id)?;
        let kinds = self.split_kinds.clone();
        // A new kind keeps the branches; it is a new part of a linked rack.
        let structural = key == "kind";
        self.graph_edit(track, &[id], structural, |graph, _, _| {
            if let Some(s) = graph.root.split_mut(id) {
                return set_split(s, key, value, &kinds);
            }
            if let Some(b) = graph.root.branch_mut(id) {
                return set_branch(b, key, value);
            }
            let owner = graph.root.path_to(id).last().map(|s| s.id);
            let m = owner
                .and_then(|o| graph.root.split_mut(o))
                .and_then(|s| s.macros.iter_mut().find(|m| m.id == id))
                .with_context(|| format!("no split, branch or macro {id} in a graph"))?;
            match key {
                "name" => m.name = de(key, value)?,
                "value" => m.value = de(key, value)?,
                _ => bail!("a macro has no value `{key}`: say name or value"),
            }
            Ok(())
        })
    }

    /// Add a macro named `name` to the split `split`. Gives its id.
    pub fn graph_macro_add(&mut self, split: Id, name: &str) -> Result<Id> {
        let track = self.graph_track_of(split)?;
        self.graph_edit(track, &[split], true, |graph, _, new_id| {
            let s = graph.root.split_mut(split).with_context(|| format!("{split} is not a split"))?;
            let id = new_id();
            s.macros.push(Macro { id, name: name.to_owned(), value: 0.0 });
            Ok(id)
        })
    }

    /// Link the macro `source` to the parameter `param` of `device`, with
    /// `depth`; `None` removes the link.
    pub fn graph_link(&mut self, source: Id, device: Id, param: &str, depth: Option<f64>) -> Result<()> {
        let track = self.graph_track_of(source)?;
        self.graph_edit(track, &[source], true, |graph, _, _| {
            let owner = graph.root.path_to(source).last().map(|s| s.id).context("no macro")?;
            let s = graph.root.split_mut(owner).context("no split")?;
            if !s.macros.iter().any(|m| m.id == source) {
                bail!("{source} is not a macro");
            }
            s.links.retain(|l| !(l.source == source && l.device == device && l.param == param));
            if let Some(depth) = depth {
                s.links.push(crate::model::graph::Link { source, device, param: param.to_owned(), depth });
            }
            Ok(())
        })
    }

    /// Let `device` take its key from the node `from` of its graph, from
    /// the graph's input (`Some(None)`), or from no node of it (`None`).
    pub fn graph_tap(&mut self, device: Id, from: Option<Option<Id>>) -> Result<()> {
        let track = self.graph_track_of(device)?;
        self.graph_edit(track, &[device], true, |graph, _, _| {
            graph.taps.retain(|t| t.device != device);
            if let Some(from) = from {
                graph.taps.push(Tap { device, from });
            }
            Ok(())
        })
    }

    /// A copy of `graph` for the copies `to` of the devices `from` (in the
    /// same order), with new ids for its own parts.
    pub(in crate::session) fn copy_graph(
        &mut self,
        graph: &Graph,
        from: &[Arc<DeviceInst>],
        to: &[Arc<DeviceInst>],
    ) -> Graph {
        let mut ids: std::collections::HashMap<Id, Id> = from.iter().zip(to).map(|(a, b)| (a.id, b.id)).collect();
        let mut copy = graph.clone();
        copy.map_ids(&mut |id| *ids.entry(id).or_insert_with(|| self.new_id()));
        copy
    }

    /// Let extensions use a kind of split (`paw.graph.define_kind`).
    pub fn graph_kind_define(&mut self, word: &str, spec: KindSpec) -> Result<()> {
        let word: Word = word.parse().map_err(|e| anyhow!("{e}"))?;
        self.split_kinds.define(word, spec).map_err(|e| anyhow!("{e}"))
    }

    /// The words of the kinds of split.
    pub fn graph_kinds(&self) -> Vec<String> {
        self.split_kinds.words()
    }

    // --- linked racks ---

    /// Run `f` on the project with ids from the document, as one edit.
    fn rack_edit<R>(&mut self, f: impl FnOnce(&mut Project, &mut dyn FnMut() -> Id) -> Result<R>) -> Result<R> {
        let mut next = self.next_id;
        let result = self.edit(|p| {
            let mut new_id = || {
                next += 1;
                next - 1
            };
            f(p, &mut new_id)
        });
        self.next_id = self.next_id.max(next);
        result
    }

    /// Make the split `split` a linked rack named `name`: the first instance
    /// of a new definition. Gives the definition's id.
    pub fn rack_define(&mut self, split: Id, name: &str) -> Result<Id> {
        self.rack_edit(|p, new_id| p.rack_define(split, name, new_id))
    }

    /// Put a new instance of the rack definition `rack` at `place` in the
    /// graph that `place` names. Gives the instance split's id.
    pub fn rack_place(&mut self, rack: Id, place: &Place) -> Result<Id> {
        let near = [place.before, place.after, place.branch]
            .into_iter()
            .flatten()
            .next()
            .context("a place names a node or a branch")?;
        let track = self.graph_track_of(near)?;
        let mut next = self.next_id;
        let made = {
            let mut new_id = || {
                next += 1;
                next - 1
            };
            self.project.rack_instance(rack, &mut new_id)?
        };
        self.next_id = next;
        self.graph_edit(track, &[], false, |graph, added, _| {
            let (split, devices) = made;
            let id = split.id;
            let (branch, at) = place.resolve(graph)?;
            let b = graph.root.branch_mut(branch).context("no branch")?;
            b.nodes.insert(at, Node::Split(Box::new(split)));
            added.extend(devices);
            Ok(id)
        })
    }

    /// Make the definition of the instance `split` what it is now: each
    /// other instance follows, and keeps its overrides.
    pub fn rack_apply(&mut self, split: Id) -> Result<()> {
        self.rack_edit(|p, new_id| p.rack_apply(split, false, new_id))
    }

    /// Give the instance `split` each value of its definition. Gives how
    /// many overrides went.
    pub fn rack_reset(&mut self, split: Id) -> Result<usize> {
        self.rack_edit(|p, new_id| p.rack_reset(split, new_id))
    }

    /// Make the instance `split` a copy that follows no definition.
    pub fn rack_unlink(&mut self, split: Id) -> Result<()> {
        self.rack_edit(|p, _| p.rack_unlink(split))
    }

    /// Change a value of the definition `rack` (`<id>.<field>`), in each
    /// instance that does not override it.
    pub fn rack_set(&mut self, rack: Id, key: &str, value: Value) -> Result<()> {
        self.rack_edit(|p, new_id| p.rack_set(rack, key, value, new_id))
    }
}

fn set_split(s: &mut Split, key: &str, value: Value, kinds: &crate::model::graph::SplitKinds) -> Result<()> {
    match key {
        "name" => s.name = de(key, value)?,
        "mix" => s.mix = de(key, value)?,
        "gain" => s.gain = de(key, value)?,
        "meta" => s.meta = de_meta(key, value)?,
        // A new kind keeps the branches, with the first values of the kind.
        "kind" => {
            let word: String = de(key, value)?;
            let (word, values) = kinds.new_split_kind(&word, s.branches.len()).map_err(|e| anyhow!("{e}"))?;
            s.kind = word;
            s.values = values;
        }
        // The values given change, the others stay.
        "values" => {
            let values: Map<String, Value> = de_meta(key, value)?;
            s.values.extend(values);
        }
        _ => bail!("a split has no value `{key}`: say name, mix, gain, kind, values or meta"),
    }
    Ok(())
}

fn set_branch(b: &mut Branch, key: &str, value: Value) -> Result<()> {
    match key {
        "name" => b.name = de(key, value)?,
        "gain" => b.gain = de(key, value)?,
        "pan" => b.pan = de(key, value)?,
        "mute" => b.mute = de(key, value)?,
        "solo" => b.solo = de(key, value)?,
        // An empty table, as Lua gives `{}`, is no zone.
        "zone" => {
            b.zone = match value {
                Value::Array(a) if a.is_empty() => None,
                value => de::<Option<Zone>>(key, value)?,
            }
        }
        _ => bail!("a branch has no value `{key}`: say name, gain, pan, mute, solo or zone"),
    }
    Ok(())
}

#[cfg(test)]
mod tests;
