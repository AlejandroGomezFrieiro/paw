//! The edits of a chain. Each is a pure function: it takes a chain and
//! gives a new one, or the reason it refuses. An edit does not know the
//! owner of the chain, the undo history or the devices' state; the session
//! finds the owner, calls the edit, checks the result (`Chain::check`),
//! makes one undo step and gives the message.
//!
//! An edit that makes a node takes it made (a split from `Split::new`, a
//! branch, a macro): the caller gives the ids.

use serde_json::{Map, Value, json};

use super::{Branch, BuiltinSplit, Chain, ChainError, Link, Macro, Node, Split, SplitKind, Tap, Zone};
use crate::model::ids::{DeviceId, NodeId, ParamKey};

/// Where a node goes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Place {
    Before(NodeId),
    After(NodeId),
    /// Into a branch at an index from 0; past the end is the end.
    Into { branch: NodeId, index: usize },
}

/// Where a device takes its key from.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum KeyFrom {
    /// The input of the chain.
    Input,
    /// The output of a node that comes before the device.
    Node(NodeId),
}

/// A change of one value of a split, a branch or a macro.
#[derive(Clone, Debug, PartialEq)]
pub enum Change {
    /// Of each.
    Name(String),
    /// Of a split.
    Mix(f64),
    /// Of a split or a branch.
    Gain(f64),
    /// Of a split: a new kind keeps the branches, with the kind's first
    /// values.
    Kind(SplitKind, Map<String, Value>),
    /// Of a split: the values given change, the others stay.
    Values(Map<String, Value>),
    /// Of a branch.
    Pan(f64),
    Mute(bool),
    Solo(bool),
    Zone(Option<Zone>),
    /// Of a macro.
    Value(f64),
}

impl Change {
    fn key(&self) -> &'static str {
        match self {
            Self::Name(_) => "name",
            Self::Mix(_) => "mix",
            Self::Gain(_) => "gain",
            Self::Kind(..) => "kind",
            Self::Values(_) => "values",
            Self::Pan(_) => "pan",
            Self::Mute(_) => "mute",
            Self::Solo(_) => "solo",
            Self::Zone(_) => "zone",
            Self::Value(_) => "value",
        }
    }
}

/// The values that each item has, as a refusal says them.
pub const SPLIT_VALUES: &str = "name, mix, gain, kind or values";
pub const BRANCH_VALUES: &str = "name, gain, pan, mute, solo or zone";
pub const MACRO_VALUES: &str = "name or value";

/// A copy of `chain` that `f` changes.
fn edited(chain: &Chain, f: impl FnOnce(&mut Chain) -> Result<(), ChainError>) -> Result<Chain, ChainError> {
    let mut copy = chain.clone();
    f(&mut copy)?;
    Ok(copy)
}

impl Place {
    /// The branch and the index in it that the place names in `chain`.
    fn resolve(self, chain: &Chain) -> Result<(NodeId, usize), ChainError> {
        let near = |id: NodeId, after: usize| {
            chain.root.place_of(id).map(|(branch, at)| (branch, at + after)).ok_or(ChainError::NoNode(id))
        };
        match self {
            Self::Before(id) => near(id, 0),
            Self::After(id) => near(id, 1),
            Self::Into { branch, index } => {
                let b = chain.root.branch(branch).ok_or(ChainError::NoBranch(branch))?;
                Ok((branch, index.min(b.nodes.len())))
            }
        }
    }

    /// The node or branch that the place names.
    pub fn near(self) -> NodeId {
        match self {
            Self::Before(id) | Self::After(id) | Self::Into { branch: id, .. } => id,
        }
    }
}

/// Put `node` at `place`.
fn put(chain: &mut Chain, node: Node, place: Place) -> Result<(), ChainError> {
    let (branch, at) = place.resolve(chain)?;
    let b = chain.root.branch_mut(branch).ok_or(ChainError::NoBranch(branch))?;
    b.nodes.insert(at.min(b.nodes.len()), node);
    Ok(())
}

/// A band split gets the crossovers of its count of bands.
fn fit_crossovers(split: &mut Split) {
    if split.kind == BuiltinSplit::Band.kind() {
        let count = split.branches.len();
        split.values.insert("xover".into(), json!(super::default_crossovers(count)));
    }
}

/// Wrap the nodes `nodes` (one or more in a row of one branch, in any
/// order) in `split`, a new split: they go into its first branch, and it
/// takes their place.
pub fn wrap(chain: &Chain, nodes: &[NodeId], mut split: Split) -> Result<Chain, ChainError> {
    edited(chain, |chain| {
        let first = *nodes.first().ok_or(ChainError::NothingToWrap)?;
        let branch = chain.root.place_of(first).map(|(b, _)| b);
        let mut places = Vec::new();
        for id in nodes {
            match chain.root.place_of(*id) {
                Some((b, at)) if Some(b) == branch => places.push(at),
                Some(_) => return Err(ChainError::WrapBranches),
                None => return Err(ChainError::NoNode(*id)),
            }
        }
        places.sort_unstable();
        places.dedup();
        if places.windows(2).any(|w| w[1] != w[0] + 1) {
            return Err(ChainError::WrapRow);
        }
        let branch = branch.ok_or(ChainError::NoNode(first))?;
        let branch = chain.root.branch_mut(branch).ok_or(ChainError::NoBranch(branch))?;
        let at = places[0];
        let inside: Vec<Node> = branch.nodes.drain(at..at + places.len()).collect();
        if let Some(first) = split.branches.first_mut() {
            first.nodes = inside;
        }
        branch.nodes.insert(at, Node::Split(Box::new(split)));
        Ok(())
    })
}

/// Take the split `split` away. With `keep` (a branch of it), the nodes of
/// that branch take its place, and the devices of the other branches leave
/// the chain; without, the branches go in its place one after the other.
pub fn unwrap(chain: &Chain, split: NodeId, keep: Option<NodeId>) -> Result<Chain, ChainError> {
    edited(chain, |chain| {
        if chain.root.id == split {
            return Err(ChainError::RootFixed("unwrapped"));
        }
        let (branch, at) = chain.root.place_of(split).ok_or(ChainError::NotSplit(split))?;
        let Some(Node::Split(s)) = chain.root.take(split) else { return Err(ChainError::NotSplit(split)) };
        let nodes: Vec<Node> = match keep {
            Some(keep) => {
                let kept = s.branches.into_iter().find(|b| b.id == keep);
                kept.ok_or(ChainError::NotBranchOf { branch: keep, split })?.nodes
            }
            None => s.branches.into_iter().flat_map(|b| b.nodes).collect(),
        };
        let place = chain.root.branch_mut(branch).ok_or(ChainError::NoBranch(branch))?;
        place.nodes.splice(at..at, nodes);
        Ok(())
    })
}

/// Add `branch`, a new empty branch, to the split `split` at `index` (from
/// 0; the end when `None`).
pub fn add_branch(chain: &Chain, split: NodeId, branch: Branch, index: Option<usize>) -> Result<Chain, ChainError> {
    edited(chain, |chain| {
        let s = chain.root.split_mut(split).ok_or(ChainError::NotSplit(split))?;
        let at = index.unwrap_or(usize::MAX).min(s.branches.len());
        s.branches.insert(at, branch);
        fit_crossovers(s);
        Ok(())
    })
}

/// Move the node `id` to `place`.
pub fn move_node(chain: &Chain, id: NodeId, place: Place) -> Result<Chain, ChainError> {
    edited(chain, |chain| {
        if chain.root.id == id {
            return Err(ChainError::RootFixed("moved"));
        }
        if let Some(Node::Split(s)) = chain.root.place_of(id).and_then(|(b, at)| chain.root.branch(b)?.nodes.get(at))
            && !s.path_to(place.near()).is_empty()
        {
            return Err(ChainError::IntoItself);
        }
        let node = chain.root.take(id).ok_or(ChainError::NoNode(id))?;
        put(chain, node, place)
    })
}

/// Put `split`, a split made outside the chain (an instance of a linked
/// rack), at `place`.
pub fn insert(chain: &Chain, split: Split, place: Place) -> Result<Chain, ChainError> {
    edited(chain, |chain| put(chain, Node::Split(Box::new(split)), place))
}

/// Remove what `id` names: a split with its devices, a branch with its
/// devices, a macro with its links, or a device.
pub fn remove(chain: &Chain, id: NodeId) -> Result<Chain, ChainError> {
    edited(chain, |chain| {
        if chain.root.id == id {
            return Err(ChainError::RootFixed("removed"));
        }
        if chain.root.take(id).is_some() {
            return Ok(());
        }
        let owner = chain.root.path_to(id).last().map(|s| s.id).ok_or(ChainError::NoItem(id))?;
        let s = chain.root.split_mut(owner).ok_or(ChainError::NotSplit(owner))?;
        if let Some(at) = s.branches.iter().position(|b| b.id == id) {
            s.branches.remove(at);
            fit_crossovers(s);
        } else if let Some(at) = s.macros.iter().position(|m| m.id == id) {
            s.macros.remove(at);
            s.links.retain(|l| l.source != id);
        }
        Ok(())
    })
}

/// Change one value of the split, the branch or the macro `id`.
pub fn set(chain: &Chain, id: NodeId, change: Change) -> Result<Chain, ChainError> {
    edited(chain, |chain| {
        let key = change.key();
        let refuse = |what, say| ChainError::NoValue { what, key, say };
        if let Some(s) = chain.root.split_mut(id) {
            match change {
                Change::Name(name) => s.name = name,
                Change::Mix(mix) => s.mix = super::Factor(mix),
                Change::Gain(gain) => s.gain = gain,
                Change::Kind(kind, values) => {
                    s.kind = kind;
                    s.values = values;
                }
                Change::Values(values) => s.values.extend(values),
                _ => return Err(refuse("a split", SPLIT_VALUES)),
            }
            return Ok(());
        }
        if let Some(b) = chain.root.branch_mut(id) {
            match change {
                Change::Name(name) => b.name = name,
                Change::Gain(gain) => b.gain = gain,
                Change::Pan(pan) => b.pan = pan,
                Change::Mute(mute) => b.mute = mute,
                Change::Solo(solo) => b.solo = solo,
                Change::Zone(zone) => b.zone = zone,
                _ => return Err(refuse("a branch", BRANCH_VALUES)),
            }
            return Ok(());
        }
        let m = macro_mut(chain, id)?;
        match change {
            Change::Name(name) => m.name = name,
            Change::Value(value) => m.value = value,
            _ => return Err(refuse("a macro", MACRO_VALUES)),
        }
        Ok(())
    })
}

/// The macro `id`.
fn macro_mut(chain: &mut Chain, id: NodeId) -> Result<&mut Macro, ChainError> {
    let owner = chain.root.path_to(id).last().map(|s| s.id).ok_or(ChainError::NoItem(id))?;
    let s = chain.root.split_mut(owner).ok_or(ChainError::NoItem(id))?;
    s.macros.iter_mut().find(|m| m.id == id).ok_or(ChainError::NoItem(id))
}

/// Add `m`, a new macro, to the split `split`.
pub fn add_macro(chain: &Chain, split: NodeId, m: Macro) -> Result<Chain, ChainError> {
    edited(chain, |chain| {
        let s = chain.root.split_mut(split).ok_or(ChainError::NotSplit(split))?;
        s.macros.push(m);
        Ok(())
    })
}

/// Link the macro `source` to the parameter `param` of `device`, with
/// `depth`; `None` removes the link.
pub fn link(
    chain: &Chain,
    source: NodeId,
    device: DeviceId,
    param: ParamKey,
    depth: Option<f64>,
) -> Result<Chain, ChainError> {
    edited(chain, |chain| {
        let owner = chain.root.path_to(source).last().map(|s| s.id).ok_or(ChainError::NotMacro(source))?;
        let s = chain.root.split_mut(owner).ok_or(ChainError::NotMacro(source))?;
        if !s.macros.iter().any(|m| m.id == source) {
            return Err(ChainError::NotMacro(source));
        }
        s.links.retain(|l| !(l.source == source && l.device == device && l.param == param));
        if let Some(depth) = depth {
            s.links.push(Link { source, device, param, depth });
        }
        Ok(())
    })
}

/// Let `device` take its key from `from`, or (`None`) from no node of the
/// chain.
pub fn tap(chain: &Chain, device: DeviceId, from: Option<KeyFrom>) -> Result<Chain, ChainError> {
    edited(chain, |chain| {
        chain.taps.retain(|t| t.device != device);
        if let Some(from) = from {
            let from = match from {
                KeyFrom::Input => None,
                KeyFrom::Node(node) => Some(node),
            };
            chain.taps.push(Tap { device, from });
        }
        Ok(())
    })
}

#[cfg(test)]
mod tests;
