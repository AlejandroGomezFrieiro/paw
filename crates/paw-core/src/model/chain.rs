//! A chain: the inserts of a strip, and the body of a rack. A tree of
//! splits and branches that names its devices by id.
//!
//! A chain does not know its owner. The owner keeps the flat list of its
//! devices (a part's `devices`), and an owner with no
//! chain plays them in series, in the order of the list. A chain gives the
//! same devices a shape. Its root is a split of kind `chain` with one
//! branch. A branch holds devices and splits in series. A split sends its
//! input into each of its branches and sums them again.
//!
//! The ids of splits, branches and macros come from the project's one space
//! of ids, as the ids of devices do: one id names one node of the project.
//!
//! What stays true after each edit (`Project::fit_chains`): each device of
//! the owner is in the chain one time, the chain names no other device, and
//! the owner's list is in the chain's signal order (depth first). The sync
//! turns the chain into a tree of engine slots (`sync/chains.rs`), and the
//! engine runs its compiled plan (`paw_engine::plan`).
//!
//! Each edit is a pure function in `chain/edit.rs`: it takes a chain and
//! gives a new one, or a [`ChainError`].
//!
//! The text form (the chain language) maps to and from these types: [`Chain`]
//! for a document, [`Split`] for a container line, [`Branch`] for a `|`
//! line, [`Node::Device`] for a device line.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::ops::RangeInclusive;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use super::ids::{DefId, DeviceId, NodeId, ParamKey};
use super::linked::Linked;
use super::racks::RackDef;
use super::serde_util::{Factor, is_default};

pub mod edit;
mod kinds;
pub use kinds::{BuiltinSplit, KindSpec, SplitImpl, SplitKind, SplitKinds, SplitRegistry, default_crossovers};

#[cfg(test)]
pub(crate) mod props;
#[cfg(test)]
mod tests;

/// The most branches a split can have.
pub const MAX_BRANCHES: usize = 16;

/// A chain of devices and splits.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Chain {
    /// A split of kind `chain` with one branch.
    pub root: Split,
    /// The devices that take their key (side-chain) from a node of this
    /// chain, or from the chain's input.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub taps: Vec<Tap>,
}

/// A container: it splits the signal into its branches, runs each branch,
/// and merges them again. A rack is a split of kind `chain` with a name.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Split {
    pub id: NodeId,
    /// The kind (`chain`, `band`, an extension's): see `chain/kinds.rs`. A
    /// kind that no one has defined stays as it was read.
    pub kind: SplitKind,
    /// The values that only the kind has (the crossovers of a band split).
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub values: Map<String, Value>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    /// The dry and wet mix of the whole split, 0 (dry) to 1 (wet).
    #[serde(default, skip_serializing_if = "is_default")]
    pub mix: Factor,
    /// The gain after the merge, in dB.
    #[serde(default, skip_serializing_if = "is_default")]
    pub gain: f64,
    pub branches: Vec<Branch>,
    /// The macros of the container: values that links set parameters from.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub macros: Vec<Macro>,
    /// What the macros move: parameters of devices inside this split.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub links: Vec<Link>,
    /// The definition this split is an instance of (a linked rack).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub linked: Option<Linked<RackDef>>,
}

/// One path through a split: nodes in series.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Branch {
    pub id: NodeId,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    /// In dB.
    #[serde(default, skip_serializing_if = "is_default")]
    pub gain: f64,
    /// -1 (left) to 1 (right).
    #[serde(default, skip_serializing_if = "is_default")]
    pub pan: f64,
    #[serde(default, skip_serializing_if = "is_default")]
    pub mute: bool,
    #[serde(default, skip_serializing_if = "is_default")]
    pub solo: bool,
    /// The notes (a `key` split) or velocities (a `vel` split) that the
    /// branch hears; `None` for all.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub zone: Option<Zone>,
    pub nodes: Vec<Node>,
}

/// A range of notes or velocities, 0 to 127, both ends in it.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Zone {
    pub low: u8,
    pub high: u8,
}

/// A node of a branch.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Node {
    /// A device of the owner, by id.
    Device(DeviceId),
    Split(Box<Split>),
}

/// A value of a container that links move parameters with.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Macro {
    pub id: NodeId,
    pub name: String,
    /// 0 to 1.
    #[serde(default)]
    pub value: f64,
}

/// A macro of a split that moves a parameter of a device inside it.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Link {
    /// The macro.
    pub source: NodeId,
    pub device: DeviceId,
    pub param: ParamKey,
    /// How far the full range of the macro moves the parameter, as a share
    /// of its range: -1 to 1.
    pub depth: f64,
}

/// A device that takes its key from inside the chain.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Tap {
    /// The device that listens.
    pub device: DeviceId,
    /// The node whose output it hears; `None` for the input of the chain.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub from: Option<NodeId>,
}

/// Why a chain or an edit of it is refused. The text is what the user
/// reads.
#[derive(Clone, Debug, PartialEq, thiserror::Error)]
pub enum ChainError {
    #[error("the root of a chain is a chain split with one branch")]
    Root,
    #[error(
        "no kind of split is called `{0}`: say chain, layer, band, ms, lr, key, vel, select, outs or a kind of an extension"
    )]
    UnknownKind(String),
    #[error("split {node} is of the kind `{kind}`, which no loaded extension defines: load the extension that defines it")]
    AbsentKind { node: NodeId, kind: SplitKind },
    #[error("`{0}` is a kind of split of paw: an extension cannot define it again")]
    BuiltinKind(String),
    #[error("the kind of split `{0}` takes from 1 to 16 branches, and its first count in that range")]
    KindBranches(String),
    #[error("the value `{key}` of the split is {want}")]
    Value { key: &'static str, want: &'static str },
    #[error("the chain names device {0}, which its owner does not have")]
    NotHeld(DeviceId),
    #[error("the linked rack {0} is inside another linked rack")]
    NestedLink(NodeId),
    #[error("the id {0} is in the chain twice")]
    Twice(NodeId),
    #[error("a {kind} split takes {} to {} branches, not {count}", .range.start(), .range.end())]
    Branches { kind: SplitKind, range: RangeInclusive<usize>, count: usize },
    #[error("a band split with {bands} bands takes {} crossovers, not {count}", .bands - 1)]
    CrossoverCount { bands: usize, count: usize },
    #[error("the crossovers of a band split go from low to high: {next} Hz comes after {before} Hz")]
    CrossoverOrder { before: f64, next: f64 },
    #[error("a crossover is a frequency above 0 Hz, not {0}")]
    CrossoverValue(f64),
    #[error("the select split has {count} branches, so its index is 0 to {}, not {index}", .count - 1)]
    SelectIndex { index: usize, count: usize },
    #[error("a zone goes from low to high in 0 to 127, not {low} to {high}")]
    Zone { low: u8, high: u8 },
    #[error("{what} is {value}: it goes from {} to {}", .range.start(), .range.end())]
    Range { what: &'static str, value: f64, range: RangeInclusive<f64> },
    #[error("device {device} takes its key from node {from}, which the chain does not have")]
    TapUnknown { device: DeviceId, from: NodeId },
    #[error("device {device} takes its key from node {from}, which comes later in the signal")]
    TapLater { device: DeviceId, from: NodeId },
    #[error("device {device} takes its key from node {from}, which holds it: that is a loop")]
    TapLoop { device: DeviceId, from: NodeId },
    #[error("device {0} takes its key from the chain two times")]
    TapTwice(DeviceId),
    #[error("the link from {macro_id} moves device {device}, which is not in its split")]
    LinkOutside { macro_id: NodeId, device: DeviceId },
    #[error("the link from {0} does not start at a macro of its split")]
    LinkSource(NodeId),
    // The edits (`chain/edit.rs`).
    #[error("no node {0} in the chain")]
    NoNode(NodeId),
    #[error("no branch {0} in the chain")]
    NoBranch(NodeId),
    #[error("{0} is not a split")]
    NotSplit(NodeId),
    #[error("{0} is not a macro")]
    NotMacro(NodeId),
    #[error("no split, branch or macro {0} in the chain")]
    NoItem(NodeId),
    #[error("nothing to wrap")]
    NothingToWrap,
    #[error("the nodes to wrap are not in one branch")]
    WrapBranches,
    #[error("the nodes to wrap are not in a row")]
    WrapRow,
    #[error("the root of the chain cannot be {0}")]
    RootFixed(&'static str),
    #[error("branch {branch} is not a branch of split {split}")]
    NotBranchOf { branch: NodeId, split: NodeId },
    #[error("a split cannot move into itself")]
    IntoItself,
    #[error("{what} has no value `{key}`: say {say}")]
    NoValue { what: &'static str, key: &'static str, say: &'static str },
}

impl Branch {
    /// An empty branch.
    pub fn new(id: NodeId) -> Self {
        Self { id, name: String::new(), gain: 0.0, pan: 0.0, mute: false, solo: false, zone: None, nodes: Vec::new() }
    }
}

impl Node {
    /// The node's id: a device's own id, or the split's.
    pub fn id(&self) -> NodeId {
        match self {
            Self::Device(id) => (*id).into(),
            Self::Split(split) => split.id,
        }
    }

    /// True when the node is the device `device` or holds it.
    fn holds(&self, device: DeviceId) -> bool {
        match self {
            Self::Device(id) => *id == device,
            Self::Split(split) => split.devices().contains(&device),
        }
    }
}

impl Split {
    /// A split of `kind` (with its `values`) and `branches` empty
    /// branches, ids from `new_id`.
    pub fn new(
        kind: SplitKind,
        values: Map<String, Value>,
        branches: usize,
        new_id: &mut dyn FnMut() -> NodeId,
    ) -> Self {
        Self {
            id: new_id(),
            kind,
            values,
            name: String::new(),
            mix: Factor::default(),
            gain: 0.0,
            branches: (0..branches).map(|_| Branch::new(new_id())).collect(),
            macros: Vec::new(),
            links: Vec::new(),
            linked: None,
        }
    }

    /// Call `f` with each device of the split, in signal order.
    pub fn each_device(&self, f: &mut impl FnMut(DeviceId)) {
        for branch in &self.branches {
            for node in &branch.nodes {
                match node {
                    Node::Device(id) => f(*id),
                    Node::Split(split) => split.each_device(f),
                }
            }
        }
    }

    /// The devices of the split, in signal order.
    pub fn devices(&self) -> Vec<DeviceId> {
        let mut out = Vec::new();
        self.each_device(&mut |id| out.push(id));
        out
    }

    /// Call `f` with each split in the tree, this one first.
    pub fn each_split<'a>(&'a self, f: &mut impl FnMut(&'a Split)) {
        f(self);
        for branch in &self.branches {
            for node in &branch.nodes {
                if let Node::Split(split) = node {
                    split.each_split(f);
                }
            }
        }
    }

    /// Call `f` with each split in the tree, this one first, to change it.
    pub fn each_split_mut(&mut self, f: &mut impl FnMut(&mut Split)) {
        f(self);
        for branch in &mut self.branches {
            for node in &mut branch.nodes {
                if let Node::Split(split) = node {
                    split.each_split_mut(f);
                }
            }
        }
    }

    /// Every id the tree uses for itself (splits, branches, macros), and
    /// the ids of its devices.
    pub fn ids(&self) -> Vec<NodeId> {
        let mut out = Vec::new();
        self.each_split(&mut |split| {
            out.push(split.id);
            out.extend(split.macros.iter().map(|m| m.id));
            for branch in &split.branches {
                out.push(branch.id);
                out.extend(branch.nodes.iter().filter_map(|n| match n {
                    Node::Device(id) => Some(NodeId::from(*id)),
                    Node::Split(_) => None,
                }));
            }
        });
        out
    }

    /// Give each id of the tree, and each id it refers to, the id `f`
    /// gives for it. `f` must give one id for one id. A device's id is a
    /// node id (one space of ids), so `f` maps it too.
    pub fn map_ids(&mut self, f: &mut impl FnMut(NodeId) -> NodeId) {
        fn device(id: DeviceId, f: &mut impl FnMut(NodeId) -> NodeId) -> DeviceId {
            f(id.into()).into()
        }
        self.each_split_mut(&mut |split| {
            split.id = f(split.id);
            for m in &mut split.macros {
                m.id = f(m.id);
            }
            for link in &mut split.links {
                link.source = f(link.source);
                link.device = device(link.device, f);
            }
            if let Some(linked) = &mut split.linked {
                for id in linked.overrides.ids.values_mut() {
                    *id = f(*id);
                }
            }
            for branch in &mut split.branches {
                branch.id = f(branch.id);
                for node in &mut branch.nodes {
                    if let Node::Device(id) = node {
                        *id = device(*id, f);
                    }
                }
            }
        });
    }

    /// The split of the tree with the id `id`, this one included.
    pub fn split(&self, id: NodeId) -> Option<&Split> {
        let mut found = None;
        self.each_split(&mut |split| {
            if split.id == id && found.is_none() {
                found = Some(split);
            }
        });
        found
    }

    pub fn split_mut(&mut self, id: NodeId) -> Option<&mut Split> {
        if self.id == id {
            return Some(self);
        }
        for branch in &mut self.branches {
            for node in &mut branch.nodes {
                if let Node::Split(split) = node
                    && let Some(found) = split.split_mut(id)
                {
                    return Some(found);
                }
            }
        }
        None
    }

    /// The branch of the tree with the id `id`.
    pub fn branch(&self, id: NodeId) -> Option<&Branch> {
        let mut found = None;
        self.each_split(&mut |split| {
            if found.is_none() {
                found = split.branches.iter().find(|b| b.id == id);
            }
        });
        found
    }

    pub fn branch_mut(&mut self, id: NodeId) -> Option<&mut Branch> {
        for branch in &mut self.branches {
            if branch.id == id {
                return Some(branch);
            }
            for node in &mut branch.nodes {
                if let Node::Split(split) = node
                    && let Some(found) = split.branch_mut(id)
                {
                    return Some(found);
                }
            }
        }
        None
    }

    /// The branch that holds the node `id` (a device or a split), and the
    /// node's index in it.
    pub fn place_of(&self, id: NodeId) -> Option<(NodeId, usize)> {
        let mut found = None;
        self.each_split(&mut |split| {
            for branch in &split.branches {
                if found.is_none()
                    && let Some(at) = branch.nodes.iter().position(|n| n.id() == id)
                {
                    found = Some((branch.id, at));
                }
            }
        });
        found
    }

    /// The splits from this one down to the node, branch or macro `id`,
    /// outermost first; empty when the tree does not hold it.
    pub fn path_to(&self, id: NodeId) -> Vec<&Split> {
        let holds = |split: &Split| {
            split.id == id || split.macros.iter().any(|m| m.id == id) || split.branches.iter().any(|b| b.id == id)
        };
        if holds(self) {
            return vec![self];
        }
        for branch in &self.branches {
            for node in &branch.nodes {
                match node {
                    Node::Device(device) if NodeId::from(*device) == id => return vec![self],
                    Node::Split(split) => {
                        let inner = split.path_to(id);
                        if !inner.is_empty() {
                            let mut path = vec![self];
                            path.extend(inner);
                            return path;
                        }
                    }
                    Node::Device(_) => {}
                }
            }
        }
        Vec::new()
    }

    /// Take the node `id` out of the tree.
    pub fn take(&mut self, id: NodeId) -> Option<Node> {
        let (branch, at) = self.place_of(id)?;
        Some(self.branch_mut(branch)?.nodes.remove(at))
    }

    /// The ids of the linked racks of the tree, this one included.
    pub fn linked_racks(&self) -> Vec<(NodeId, DefId<RackDef>)> {
        let mut out = Vec::new();
        self.each_split(&mut |s| out.extend(s.linked.as_ref().map(|l| (s.id, l.of))));
        out
    }
}

impl Chain {
    /// The devices `devices` in series, as a chain with ids from `new_id`.
    pub fn serial(devices: impl IntoIterator<Item = DeviceId>, new_id: &mut dyn FnMut() -> NodeId) -> Self {
        let mut root = Split::new(BuiltinSplit::Chain.kind(), Map::new(), 1, new_id);
        root.branches[0].nodes = devices.into_iter().map(Node::Device).collect();
        Self { root, taps: Vec::new() }
    }

    /// The devices of the chain, in signal order.
    pub fn devices(&self) -> Vec<DeviceId> {
        self.root.devices()
    }

    /// True when the chain holds the node, branch or macro `id`.
    pub fn holds(&self, id: NodeId) -> bool {
        !self.root.path_to(id).is_empty()
    }

    /// Give each id of the chain, and each id it refers to, the id `f`
    /// gives for it (see `Split::map_ids`).
    pub fn map_ids(&mut self, f: &mut impl FnMut(NodeId) -> NodeId) {
        self.root.map_ids(f);
        for tap in &mut self.taps {
            tap.device = f(tap.device.into()).into();
            tap.from = tap.from.map(&mut *f);
        }
    }

    /// True when the devices of the chain, in signal order, are `devices`.
    pub fn names_in_order(&self, devices: impl ExactSizeIterator<Item = DeviceId>) -> bool {
        let count = devices.len();
        let mut devices = devices;
        let (mut same, mut seen) = (true, 0);
        self.root.each_device(&mut |id| {
            same &= devices.next() == Some(id);
            seen += 1;
        });
        same && seen == count
    }

    /// Make the chain name each of `devices` one time and no other device:
    /// a device that the owner does not have any more goes, and a device
    /// that the chain does not name goes into the root, after the top node
    /// that holds the device before it in `devices`. So a device added at
    /// the end of the list goes at the end of the root. Taps and links of a
    /// device that went go too. True when it changed the chain.
    pub fn fit(&mut self, devices: &[DeviceId]) -> bool {
        let held: HashSet<DeviceId> = devices.iter().copied().collect();
        let mut seen = HashSet::new();
        let mut changed = false;
        self.root.each_split_mut(&mut |split| {
            for branch in &mut split.branches {
                let before = branch.nodes.len();
                branch.nodes.retain(|n| match n {
                    Node::Device(id) => held.contains(id) && seen.insert(*id),
                    Node::Split(_) => true,
                });
                changed |= branch.nodes.len() != before;
            }
            let before = split.links.len();
            split.links.retain(|l| held.contains(&l.device));
            changed |= split.links.len() != before;
        });
        let before = self.taps.len();
        self.taps.retain(|t| {
            held.contains(&t.device)
                && t.from.is_none_or(|from| held.contains(&from.into()) || self.root.split(from).is_some())
        });
        changed |= self.taps.len() != before;
        for (i, &device) in devices.iter().enumerate() {
            if seen.contains(&device) {
                continue;
            }
            let previous = devices[..i].iter().rev().find(|d| seen.contains(*d));
            let top = &mut self.root.branches[0].nodes;
            let at = previous.and_then(|p| top.iter().position(|n| n.holds(*p))).map_or(0, |at| at + 1);
            top.insert(at, Node::Device(device));
            seen.insert(device);
            changed = true;
        }
        changed
    }

    /// Check the chain against the devices of its owner. A split of a kind
    /// that no one has defined passes: it keeps what it was read with
    /// (`SplitFamily::ABSENT`), and the engine that runs chains plays its
    /// first branch. The first problem found is the error.
    pub fn check(&self, devices: &[DeviceId], kinds: &SplitKinds) -> Result<(), ChainError> {
        if self.root.kind != BuiltinSplit::Chain.kind() || self.root.branches.len() != 1 {
            return Err(ChainError::Root);
        }
        let held: HashSet<DeviceId> = devices.iter().copied().collect();
        let mut ids = BTreeSet::new();
        for id in self.root.ids() {
            if !ids.insert(id) {
                return Err(ChainError::Twice(id));
            }
        }
        let mut result = Ok(());
        self.root.each_split(&mut |split| {
            if result.is_ok() {
                result = kinds.check(split).and_then(|()| check_split(split, &held));
            }
            if result.is_ok() && split.linked.is_some() {
                split.each_split(&mut |inner| {
                    if inner.id != split.id && inner.linked.is_some() {
                        result = Err(ChainError::NestedLink(inner.id));
                    }
                });
            }
        });
        result?;
        self.check_taps()
    }

    /// [`Chain::check`], and a split of a kind that no one has defined is
    /// an error too ([`ChainError::AbsentKind`]).
    pub fn validate(&self, devices: &[DeviceId], kinds: &SplitKinds) -> Result<(), ChainError> {
        self.check(devices, kinds)?;
        let mut absent = None;
        self.root.each_split(&mut |split| {
            if absent.is_none() && kinds.get(&split.kind).is_none() {
                absent = Some(ChainError::AbsentKind { node: split.id, kind: split.kind.clone() });
            }
        });
        absent.map_or(Ok(()), Err)
    }

    /// A tap hears a node that the signal passes before the listener: the
    /// input, or a node that ends before the listener starts.
    fn check_taps(&self) -> Result<(), ChainError> {
        let order = Order::of(&self.root);
        let mut listeners = HashSet::new();
        for tap in &self.taps {
            if !listeners.insert(tap.device) {
                return Err(ChainError::TapTwice(tap.device));
            }
            let Some(from) = tap.from else { continue };
            let (Some(&(start, end)), Some(&(listener, _))) =
                (order.span.get(&from), order.span.get(&tap.device.into()))
            else {
                return Err(ChainError::TapUnknown { device: tap.device, from });
            };
            if start <= listener && listener < end {
                return Err(ChainError::TapLoop { device: tap.device, from });
            }
            if end > listener {
                return Err(ChainError::TapLater { device: tap.device, from });
            }
        }
        Ok(())
    }
}

/// The checks of one split that do not depend on its kind, not of the
/// splits in it.
fn check_split(split: &Split, held: &HashSet<DeviceId>) -> Result<(), ChainError> {
    in_range("the mix", split.mix.0, 0.0..=1.0)?;
    in_range("the gain", split.gain, -120.0..=24.0)?;
    for branch in &split.branches {
        in_range("the gain of a branch", branch.gain, -120.0..=24.0)?;
        in_range("the pan of a branch", branch.pan, -1.0..=1.0)?;
        if let Some(Zone { low, high }) = branch.zone
            && (low > high || high > 127)
        {
            return Err(ChainError::Zone { low, high });
        }
        for node in &branch.nodes {
            if let Node::Device(id) = node
                && !held.contains(id)
            {
                return Err(ChainError::NotHeld(*id));
            }
        }
    }
    for m in &split.macros {
        in_range("a macro", m.value, 0.0..=1.0)?;
    }
    let inside = split.devices();
    for link in &split.links {
        if !split.macros.iter().any(|m| m.id == link.source) {
            return Err(ChainError::LinkSource(link.source));
        }
        if !inside.contains(&link.device) {
            return Err(ChainError::LinkOutside { macro_id: link.source, device: link.device });
        }
        in_range("the depth of a link", link.depth, -1.0..=1.0)?;
    }
    Ok(())
}

pub(super) fn in_range(what: &'static str, value: f64, range: RangeInclusive<f64>) -> Result<(), ChainError> {
    if range.contains(&value) { Ok(()) } else { Err(ChainError::Range { what, value, range }) }
}

/// Where each node is in the signal: `(start, end)`, where a device spans
/// one step and a split spans the steps of the nodes in it. A node `a` ends
/// before `b` starts when `a.end <= b.start`.
struct Order {
    span: HashMap<NodeId, (usize, usize)>,
}

impl Order {
    fn of(root: &Split) -> Self {
        fn walk(split: &Split, at: &mut usize, span: &mut HashMap<NodeId, (usize, usize)>) {
            let start = *at;
            for branch in &split.branches {
                for node in &branch.nodes {
                    match node {
                        Node::Device(id) => {
                            span.insert((*id).into(), (*at, *at + 1));
                            *at += 1;
                        }
                        Node::Split(inner) => walk(inner, at, span),
                    }
                }
            }
            // A split ends after its merge, one step after its last node.
            *at += 1;
            span.insert(split.id, (start, *at));
        }
        let mut span = HashMap::new();
        walk(root, &mut 0, &mut span);
        Self { span }
    }
}
