//! The chain of each part as a tree of engine slots, which the engine
//! compiles into the plan its processor runs.
//!
//! A part with no chain plays its devices in series. A part with one
//! plays its splits: the kind of each split is looked up in the registry of
//! split kinds. A kind that the engine does not play (one that no loaded
//! extension defines, one that an extension defines but the engine has no
//! sound for yet, or `outs`) plays its first branch in series, and the
//! sync says so in a warning.

use std::collections::HashMap;

use paw_engine::plan::{self, Splitter, Tree};
use paw_engine::{DeviceSlot, db_to_gain};

use crate::model::chain::{self, BuiltinSplit, SplitImpl, SplitKinds, default_crossovers};
use crate::model::ids::NodeId;
use crate::model::{DeviceInst, Id, Part};

/// What a tree of a part is built from.
pub(super) struct Slots<'a> {
    /// The engine slot of each device that the engine runs.
    pub devices: &'a HashMap<Id, DeviceSlot>,
    /// The frames by which a device's output is behind its input.
    pub latency: &'a dyn Fn(&DeviceInst) -> u32,
    pub kinds: &'a SplitKinds,
}

/// The tree of `part`, and the warnings of the splits that do not play as
/// their kind says.
pub(super) fn tree_of(part: &Part, slots: &Slots) -> (Tree, Vec<String>) {
    let devices: HashMap<Id, &DeviceInst> = part.devices.iter().map(|d| (d.id, &**d)).collect();
    let mut walk = Walk { slots, devices, notes: Vec::new() };
    let nodes = match &part.chain {
        None => part.devices.iter().filter_map(|d| walk.device(d.id)).collect(),
        Some(chain) => vec![walk.split(&chain.root)],
    };
    (Tree { nodes }, walk.notes)
}

struct Walk<'a> {
    slots: &'a Slots<'a>,
    devices: HashMap<Id, &'a DeviceInst>,
    notes: Vec<String>,
}

impl Walk<'_> {
    /// A device the engine runs; `None` for one it does not (offline).
    fn device(&self, id: Id) -> Option<plan::Node> {
        let slot = *self.slots.devices.get(&id)?;
        let latency = self.devices.get(&id).map_or(0, |d| (self.slots.latency)(d));
        Some(plan::Node::Device { slot, latency })
    }

    fn nodes(&mut self, nodes: &[chain::Node]) -> Vec<plan::Node> {
        nodes
            .iter()
            .filter_map(|node| match node {
                chain::Node::Device(id) => self.device(id.get()),
                chain::Node::Split(split) => Some(self.split(split)),
            })
            .collect()
    }

    fn branch(&mut self, branch: &chain::Branch) -> plan::Branch {
        plan::Branch {
            tag: branch.id.get(),
            nodes: self.nodes(&branch.nodes),
            gain: db_to_gain(branch.gain),
            pan: branch.pan as f32,
            mute: branch.mute,
            solo: branch.solo,
            zone: branch.zone.map(|z| (z.low, z.high)),
        }
    }

    fn split(&mut self, split: &chain::Split) -> plan::Node {
        let all = |walk: &mut Self, splitter| (splitter, split.branches.iter().map(|b| walk.branch(b)).collect());
        let (splitter, branches) = match self.slots.kinds.get(&split.kind) {
            Some(SplitImpl::Builtin(builtin)) => match builtin {
                BuiltinSplit::Chain | BuiltinSplit::Layer => all(self, Splitter::Layer),
                BuiltinSplit::Band => all(self, Splitter::Band(crossovers(split))),
                BuiltinSplit::Ms => all(self, Splitter::MidSide),
                BuiltinSplit::Lr => all(self, Splitter::LeftRight),
                BuiltinSplit::Key => all(self, Splitter::Keys),
                BuiltinSplit::Vel => all(self, Splitter::Velocities),
                // The branch that the index chooses plays; the others rest.
                BuiltinSplit::Select => {
                    let index = split.values.get("index").and_then(|v| v.as_u64()).unwrap_or(0) as usize;
                    let chosen = split.branches.get(index).or(split.branches.first());
                    (Splitter::Layer, chosen.map(|b| self.branch(b)).into_iter().collect())
                }
                BuiltinSplit::Outs => {
                    self.note(split.id, &format!("the engine does not play the kind `{}` yet", split.kind));
                    return self.first_branch(split);
                }
            },
            Some(SplitImpl::Declared(_)) => {
                self.note(split.id, &format!("the engine does not play the kind `{}` yet", split.kind));
                return self.first_branch(split);
            }
            None => {
                self.note(split.id, &format!("no loaded extension defines its kind `{}`", split.kind));
                return self.first_branch(split);
            }
        };
        plan::Node::Split(Box::new(plan::Split {
            tag: split.id.get(),
            splitter,
            branches,
            mix: split.mix.0 as f32,
            gain: db_to_gain(split.gain),
        }))
    }

    /// The first branch of `split` in series, as a rack at unity.
    fn first_branch(&mut self, split: &chain::Split) -> plan::Node {
        let branch = split.branches.first().map(|b| plan::Branch {
            tag: b.id.get(),
            nodes: self.nodes(&b.nodes),
            gain: 1.0,
            pan: 0.0,
            mute: false,
            solo: false,
            zone: None,
        });
        plan::Node::Split(Box::new(plan::Split {
            tag: split.id.get(),
            splitter: Splitter::Layer,
            branches: branch.into_iter().collect(),
            mix: 1.0,
            gain: 1.0,
        }))
    }

    fn note(&mut self, split: NodeId, why: &str) {
        self.notes.push(format!("split {split} plays its first branch: {why}"));
    }
}

/// The crossovers of a band split in Hz, or ones spread over the range of
/// music when it has none that fit.
fn crossovers(split: &chain::Split) -> Vec<f32> {
    let bands = split.branches.len();
    let given: Option<Vec<f64>> = split.values.get("xover").and_then(|v| serde_json::from_value(v.clone()).ok());
    given
        .filter(|x| x.len() + 1 == bands)
        .unwrap_or_else(|| default_crossovers(bands))
        .into_iter()
        .map(|f| f as f32)
        .collect()
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use serde_json::json;

    use super::*;

    /// Part 1 with devices 2 and 3, and a chain whose split 52 is of
    /// `kind`, with device 3 in its first branch (at -6 dB) and an empty
    /// second.
    fn part(kind: &str) -> Part {
        let mut part: Part = serde_json::from_value(json!({
            "id": 1, "name": "Keys", "volume": 0.0, "pan": 0.0, "mute": false, "solo": false,
            "armed": false, "output": null, "sends": [], "color": null, "clips": [],
            "devices": [
                { "id": 2, "kind": "synth", "bypass": false, "params": {} },
                { "id": 3, "kind": "delay", "bypass": false, "params": {} },
            ],
        }))
        .unwrap();
        let chain = json!({ "root": { "id": 50, "kind": "chain", "branches": [{ "id": 51, "nodes": [
            { "device": 2 },
            { "split": { "id": 52, "kind": kind, "branches": [
                { "id": 53, "gain": -6.0, "nodes": [{ "device": 3 }] },
                { "id": 54, "nodes": [] },
            ] } },
        ] }] } });
        part.chain = Some(Arc::new(serde_json::from_value(chain).unwrap()));
        part
    }

    fn tree(kind: &str) -> (Tree, Vec<String>) {
        let devices = HashMap::from([(2, DeviceSlot(7)), (3, DeviceSlot(8))]);
        let slots = Slots { devices: &devices, latency: &|_| 0, kinds: &SplitKinds::builtin() };
        tree_of(&part(kind), &slots)
    }

    /// The split in the root's branch, after the synth.
    fn inner(tree: &Tree) -> &plan::Split {
        let [plan::Node::Split(root)] = tree.nodes.as_slice() else { panic!("the root is a split: {tree:?}") };
        let [synth, plan::Node::Split(split)] = root.branches[0].nodes.as_slice() else { panic!("{tree:?}") };
        assert_eq!(*synth, plan::Node::Device { slot: DeviceSlot(7), latency: 0 });
        split
    }

    #[test]
    fn a_split_of_an_absent_kind_plays_its_first_branch_and_says_so() {
        let (tree, notes) = tree("drums.transient");
        let split = inner(&tree);
        assert_eq!(split.splitter, Splitter::Layer);
        let branches = &split.branches[..];
        assert_eq!(branches.len(), 1, "only the first branch");
        assert_eq!(branches[0].nodes, [plan::Node::Device { slot: DeviceSlot(8), latency: 0 }]);
        assert_eq!(branches[0].gain, 1.0, "in series, at unity");
        assert_eq!(notes, ["split 52 plays its first branch: no loaded extension defines its kind `drums.transient`"]);
    }
}
