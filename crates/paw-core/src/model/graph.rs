//! The devices graph of a track: a tree of splits and branches that names
//! the track's devices by id.
//!
//! `Track::devices` stays the flat list of every device of the track, and a
//! track with no graph plays them in series, in the order of the list. A
//! graph gives the same devices a shape. Its root is a split of kind
//! `chain` with one branch. A branch holds devices and splits in series. A
//! split sends its input into each of its branches and sums them again.
//!
//! The ids of splits, branches and macros come from the project's one space
//! of ids, as the ids of devices do: one id names one node of the project.
//!
//! What stays true after each edit (`Project::fit_graphs`): each device of
//! the track is in the graph one time, the graph names no other device, and
//! `Track::devices` is in the graph's signal order (depth first). The engine
//! plays `Track::devices` in series until it runs a plan of the graph, so a
//! graph plays its devices in its signal order.
//!
//! The text form on disk (the chain language) maps to and from these types:
//! [`Graph`] for a track, [`Split`] for a container line, [`Branch`] for a
//! `|` line, [`Node::Device`] for a device line.

use std::collections::{BTreeSet, HashSet};
use std::ops::RangeInclusive;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use std::sync::Arc;

use super::racks::RackLink;
use super::{Id, Project, Track, Word};

mod kinds;
pub use kinds::{Builtin, KindSpec, SplitKinds, default_crossovers};

#[cfg(test)]
mod props;
#[cfg(test)]
mod tests;

/// The most branches a split can have.
pub const MAX_BRANCHES: usize = 16;

/// The graph of a track's devices.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Graph {
    /// A split of kind `chain` with one branch: the track's chain.
    pub root: Split,
    /// The devices that take their key (side-chain) from a node of this
    /// graph, or from the graph's input.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub taps: Vec<Tap>,
}

/// A container: it splits the signal into its branches, runs each branch,
/// and merges them again. A rack is a split of kind `chain` with a name.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Split {
    pub id: Id,
    /// The kind (`chain`, `band`, an extension's word): see `graph/kinds.rs`.
    pub kind: Word,
    /// The values that only the kind has (the crossovers of a band split).
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub values: Map<String, Value>,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    /// The dry and wet mix of the whole split, 0 (dry) to 1 (wet).
    #[serde(default = "one", skip_serializing_if = "is_one")]
    pub mix: f64,
    /// The gain after the merge, in dB.
    #[serde(default, skip_serializing_if = "is_zero")]
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
    pub linked: Option<RackLink>,
    /// Free data for extensions.
    #[serde(default, skip_serializing_if = "Map::is_empty")]
    pub meta: Map<String, Value>,
}

/// One path through a split: nodes in series.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Branch {
    pub id: Id,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    /// In dB.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub gain: f64,
    /// -1 (left) to 1 (right).
    #[serde(default, skip_serializing_if = "is_zero")]
    pub pan: f64,
    #[serde(default, skip_serializing_if = "is_false")]
    pub mute: bool,
    #[serde(default, skip_serializing_if = "is_false")]
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
    /// A device of the track, by id.
    Device(Id),
    Split(Box<Split>),
}

/// A value of a container that links move parameters with.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Macro {
    pub id: Id,
    pub name: String,
    /// 0 to 1.
    #[serde(default)]
    pub value: f64,
}

/// A macro of a split that moves a parameter of a device inside it.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Link {
    /// The macro.
    pub source: Id,
    pub device: Id,
    /// The key of the parameter.
    pub param: String,
    /// How far the full range of the macro moves the parameter, as a share
    /// of its range: -1 to 1.
    pub depth: f64,
}

/// A device that takes its key from inside the graph.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Tap {
    /// The device that listens.
    pub device: Id,
    /// The node whose output it hears; `None` for the input of the graph.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub from: Option<Id>,
}

fn one() -> f64 {
    1.0
}

fn is_one(value: &f64) -> bool {
    *value == 1.0
}

fn is_zero(value: &f64) -> bool {
    *value == 0.0
}

fn is_false(value: &bool) -> bool {
    !*value
}

/// Why a graph is refused. The text is what the user reads.
#[derive(Clone, Debug, PartialEq, thiserror::Error)]
pub enum GraphError {
    #[error("the root of a graph is a chain with one branch")]
    Root,
    #[error(
        "no kind of split is called `{0}`: say chain, layer, band, ms, lr, key, vel, select, outs or a kind of an extension"
    )]
    UnknownKind(String),
    #[error("`{0}` is a kind of split of paw: an extension cannot define it again")]
    BuiltinKind(String),
    #[error("the kind of split `{0}` takes from 1 to 16 branches, and its first count in that range")]
    KindBranches(String),
    #[error("the value `{key}` of the split is {want}")]
    Value { key: &'static str, want: &'static str },
    #[error("the graph names device {0}, which is not on its track")]
    NotOnTrack(Id),
    #[error("the linked rack {0} is inside another linked rack")]
    NestedLink(Id),
    #[error("the id {0} is in the graph twice")]
    Twice(Id),
    #[error("a {kind} split takes {} to {} branches, not {count}", .range.start(), .range.end())]
    Branches { kind: String, range: RangeInclusive<usize>, count: usize },
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
    #[error("device {device} takes its key from node {from}, which the graph does not have")]
    TapUnknown { device: Id, from: Id },
    #[error("device {device} takes its key from node {from}, which comes later in the signal")]
    TapLater { device: Id, from: Id },
    #[error("device {device} takes its key from node {from}, which holds it: that is a loop")]
    TapLoop { device: Id, from: Id },
    #[error("device {0} takes its key from the graph two times")]
    TapTwice(Id),
    #[error("the link from {macro_id} moves device {device}, which is not in its split")]
    LinkOutside { macro_id: Id, device: Id },
    #[error("the link from {0} does not start at a macro of its split")]
    LinkSource(Id),
}

impl Branch {
    /// An empty branch.
    pub fn new(id: Id) -> Self {
        Self { id, name: String::new(), gain: 0.0, pan: 0.0, mute: false, solo: false, zone: None, nodes: Vec::new() }
    }
}

impl Node {
    pub fn id(&self) -> Id {
        match self {
            Self::Device(id) => *id,
            Self::Split(split) => split.id,
        }
    }
}

impl Split {
    /// A split of `kind` (with its `values`) and `branches` empty
    /// branches, ids from `new_id`.
    pub fn new(kind: Word, values: Map<String, Value>, branches: usize, new_id: &mut dyn FnMut() -> Id) -> Self {
        Self {
            id: new_id(),
            kind,
            values,
            name: String::new(),
            mix: 1.0,
            gain: 0.0,
            branches: (0..branches).map(|_| Branch::new(new_id())).collect(),
            macros: Vec::new(),
            links: Vec::new(),
            linked: None,
            meta: Map::new(),
        }
    }

    /// Call `f` with each device of the split, in signal order.
    pub fn each_device(&self, f: &mut impl FnMut(Id)) {
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
    pub fn devices(&self) -> Vec<Id> {
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
    pub fn ids(&self) -> Vec<Id> {
        let mut out = Vec::new();
        self.each_split(&mut |split| {
            out.push(split.id);
            out.extend(split.macros.iter().map(|m| m.id));
            for branch in &split.branches {
                out.push(branch.id);
                out.extend(branch.nodes.iter().filter_map(|n| match n {
                    Node::Device(id) => Some(*id),
                    Node::Split(_) => None,
                }));
            }
        });
        out
    }

    /// Give each id of the tree, and each id it refers to, the id `f`
    /// gives for it. `f` must give one id for one id.
    pub fn map_ids(&mut self, f: &mut impl FnMut(Id) -> Id) {
        self.each_split_mut(&mut |split| {
            split.id = f(split.id);
            for m in &mut split.macros {
                m.id = f(m.id);
            }
            for link in &mut split.links {
                link.source = f(link.source);
                link.device = f(link.device);
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
                        *id = f(*id);
                    }
                }
            }
        });
    }

    /// The split of the tree with the id `id`, this one included.
    pub fn split(&self, id: Id) -> Option<&Split> {
        let mut found = None;
        self.each_split(&mut |split| {
            if split.id == id && found.is_none() {
                found = Some(split);
            }
        });
        found
    }

    pub fn split_mut(&mut self, id: Id) -> Option<&mut Split> {
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
    pub fn branch(&self, id: Id) -> Option<&Branch> {
        let mut found = None;
        self.each_split(&mut |split| {
            if found.is_none() {
                found = split.branches.iter().find(|b| b.id == id);
            }
        });
        found
    }

    pub fn branch_mut(&mut self, id: Id) -> Option<&mut Branch> {
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
    pub fn place_of(&self, id: Id) -> Option<(Id, usize)> {
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

    /// The split that holds the branch `id`.
    pub fn split_of_branch(&self, id: Id) -> Option<&Split> {
        let mut found = None;
        self.each_split(&mut |split| {
            if found.is_none() && split.branches.iter().any(|b| b.id == id) {
                found = Some(split);
            }
        });
        found
    }

    /// The splits from this one down to the node, branch or macro `id`,
    /// outermost first; empty when the tree does not hold it.
    pub fn path_to(&self, id: Id) -> Vec<&Split> {
        let holds = |split: &Split| {
            split.id == id || split.macros.iter().any(|m| m.id == id) || split.branches.iter().any(|b| b.id == id)
        };
        if holds(self) {
            return vec![self];
        }
        for branch in &self.branches {
            for node in &branch.nodes {
                match node {
                    Node::Device(device) if *device == id => return vec![self],
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
    pub fn take(&mut self, id: Id) -> Option<Node> {
        let (branch, at) = self.place_of(id)?;
        Some(self.branch_mut(branch)?.nodes.remove(at))
    }
}

impl Graph {
    /// The devices `devices` in series, as a graph with ids from `new_id`.
    pub fn serial(devices: impl IntoIterator<Item = Id>, new_id: &mut dyn FnMut() -> Id) -> Self {
        let mut root = Split::new(Builtin::Chain.word().parse().expect("a word"), Map::new(), 1, new_id);
        root.branches[0].nodes = devices.into_iter().map(Node::Device).collect();
        Self { root, taps: Vec::new() }
    }

    /// The devices of the graph, in signal order.
    pub fn devices(&self) -> Vec<Id> {
        self.root.devices()
    }

    /// Give each id of the graph, and each id it refers to, the id `f`
    /// gives for it (see `Split::map_ids`).
    pub fn map_ids(&mut self, f: &mut impl FnMut(Id) -> Id) {
        self.root.map_ids(f);
        for tap in &mut self.taps {
            tap.device = f(tap.device);
            tap.from = tap.from.map(&mut *f);
        }
    }

    /// True when the devices of the graph, in signal order, are `devices`.
    pub fn names_in_order(&self, devices: impl ExactSizeIterator<Item = Id>) -> bool {
        let count = devices.len();
        let mut devices = devices;
        let (mut same, mut seen) = (true, 0);
        self.root.each_device(&mut |id| {
            same &= devices.next() == Some(id);
            seen += 1;
        });
        same && seen == count
    }

    /// Make the graph name each of `devices` one time and no other device:
    /// a device that is not on the track any more goes, and a device that
    /// the graph does not name goes into the root, after the top node that
    /// holds the device before it in `devices`. So a device added at the
    /// end of the list goes at the end of the root. Taps and links of a
    /// device that went go too. True when it changed the graph.
    pub fn fit(&mut self, devices: &[Id]) -> bool {
        let on_track: HashSet<Id> = devices.iter().copied().collect();
        let mut seen = HashSet::new();
        let mut changed = false;
        self.root.each_split_mut(&mut |split| {
            for branch in &mut split.branches {
                let before = branch.nodes.len();
                branch.nodes.retain(|n| match n {
                    Node::Device(id) => on_track.contains(id) && seen.insert(*id),
                    Node::Split(_) => true,
                });
                changed |= branch.nodes.len() != before;
            }
            let before = split.links.len();
            split.links.retain(|l| on_track.contains(&l.device));
            changed |= split.links.len() != before;
        });
        let before = self.taps.len();
        self.taps.retain(|t| {
            on_track.contains(&t.device)
                && t.from.is_none_or(|from| on_track.contains(&from) || self.root.split(from).is_some())
        });
        changed |= self.taps.len() != before;
        for (i, &device) in devices.iter().enumerate() {
            if seen.contains(&device) {
                continue;
            }
            let previous = devices[..i].iter().rev().find(|d| seen.contains(*d));
            let top = &mut self.root.branches[0].nodes;
            let at = previous.and_then(|p| top.iter().position(|n| holds(n, *p))).map_or(0, |at| at + 1);
            top.insert(at, Node::Device(device));
            seen.insert(device);
            changed = true;
        }
        changed
    }

    /// Check the graph against the devices of its track. The first problem
    /// found is the error.
    pub fn validate(&self, devices: &[Id], kinds: &SplitKinds) -> Result<(), GraphError> {
        if Builtin::of(self.root.kind.as_str()) != Some(Builtin::Chain) || self.root.branches.len() != 1 {
            return Err(GraphError::Root);
        }
        let on_track: HashSet<Id> = devices.iter().copied().collect();
        let mut ids = BTreeSet::new();
        for id in self.root.ids() {
            if !ids.insert(id) {
                return Err(GraphError::Twice(id));
            }
        }
        let mut result = Ok(());
        self.root.each_split(&mut |split| {
            if result.is_ok() {
                result = kinds.check(split).and_then(|()| check_split(split, &on_track));
            }
            if result.is_ok() && split.linked.is_some() {
                split.each_split(&mut |inner| {
                    if inner.id != split.id && inner.linked.is_some() {
                        result = Err(GraphError::NestedLink(inner.id));
                    }
                });
            }
        });
        result?;
        self.check_taps()
    }

    /// A tap hears a node that the signal passes before the listener: the
    /// input, or a node that ends before the listener starts.
    fn check_taps(&self) -> Result<(), GraphError> {
        let order = Order::of(&self.root);
        let mut listeners = HashSet::new();
        for tap in &self.taps {
            if !listeners.insert(tap.device) {
                return Err(GraphError::TapTwice(tap.device));
            }
            let Some(from) = tap.from else { continue };
            let (Some(&(start, end)), Some(&(listener, _))) = (order.span.get(&from), order.span.get(&tap.device))
            else {
                return Err(GraphError::TapUnknown { device: tap.device, from });
            };
            if start <= listener && listener < end {
                return Err(GraphError::TapLoop { device: tap.device, from });
            }
            if end > listener {
                return Err(GraphError::TapLater { device: tap.device, from });
            }
        }
        Ok(())
    }
}

impl Project {
    /// Make each graph name its track's devices again, and put the devices
    /// in the graph's signal order (see the head of this file). An edit of
    /// `Track::devices` that does not know the graph (a device added at the
    /// end, removed, or moved to another track) leaves the graph behind
    /// until this runs. A track whose graph is true is not touched.
    pub fn fit_graphs(&mut self) {
        for t in self.tracks.iter_mut().chain(std::iter::once(&mut self.master)) {
            let Some(graph) = &t.graph else { continue };
            if !graph.names_in_order(t.devices.iter().map(|d| d.id)) {
                fit_track(Arc::make_mut(t));
            }
        }
    }
}

/// Fit the track's graph to its devices, then sort the devices into the
/// graph's signal order.
pub(crate) fn fit_track(t: &mut Track) {
    let Some(graph) = &mut t.graph else { return };
    let ids: Vec<Id> = t.devices.iter().map(|d| d.id).collect();
    let graph = Arc::make_mut(graph);
    graph.fit(&ids);
    let order: std::collections::HashMap<Id, usize> =
        graph.devices().into_iter().enumerate().map(|(i, id)| (id, i)).collect();
    t.devices.sort_by_key(|d| order.get(&d.id).copied().unwrap_or(usize::MAX));
}

/// True when the node is the device `device` or holds it.
fn holds(node: &Node, device: Id) -> bool {
    match node {
        Node::Device(id) => *id == device,
        Node::Split(split) => split.devices().contains(&device),
    }
}

/// The checks of one split that do not depend on its kind, not of the
/// splits in it.
fn check_split(split: &Split, on_track: &HashSet<Id>) -> Result<(), GraphError> {
    in_range("the mix", split.mix, 0.0..=1.0)?;
    in_range("the gain", split.gain, -120.0..=24.0)?;
    for branch in &split.branches {
        in_range("the gain of a branch", branch.gain, -120.0..=24.0)?;
        in_range("the pan of a branch", branch.pan, -1.0..=1.0)?;
        if let Some(Zone { low, high }) = branch.zone
            && (low > high || high > 127)
        {
            return Err(GraphError::Zone { low, high });
        }
        for node in &branch.nodes {
            if let Node::Device(id) = node
                && !on_track.contains(id)
            {
                return Err(GraphError::NotOnTrack(*id));
            }
        }
    }
    for m in &split.macros {
        in_range("a macro", m.value, 0.0..=1.0)?;
    }
    let inside = split.devices();
    for link in &split.links {
        if !split.macros.iter().any(|m| m.id == link.source) {
            return Err(GraphError::LinkSource(link.source));
        }
        if !inside.contains(&link.device) {
            return Err(GraphError::LinkOutside { macro_id: link.source, device: link.device });
        }
        in_range("the depth of a link", link.depth, -1.0..=1.0)?;
    }
    Ok(())
}

pub(super) fn in_range(what: &'static str, value: f64, range: RangeInclusive<f64>) -> Result<(), GraphError> {
    if range.contains(&value) { Ok(()) } else { Err(GraphError::Range { what, value, range }) }
}

/// Where each node is in the signal: `(start, end)`, where a device spans
/// one step and a split spans the steps of the nodes in it. A node `a` ends
/// before `b` starts when `a.end <= b.start`.
struct Order {
    span: std::collections::HashMap<Id, (usize, usize)>,
}

impl Order {
    fn of(root: &Split) -> Self {
        fn walk(split: &Split, at: &mut usize, span: &mut std::collections::HashMap<Id, (usize, usize)>) {
            let start = *at;
            for branch in &split.branches {
                for node in &branch.nodes {
                    match node {
                        Node::Device(id) => {
                            span.insert(*id, (*at, *at + 1));
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
        let mut span = std::collections::HashMap::new();
        walk(root, &mut 0, &mut span);
        Self { span }
    }
}
