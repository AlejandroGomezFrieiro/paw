//! The edits of the chain of an owner (`model/chain.rs`) and of linked
//! racks (`model/racks.rs`). The session finds the owner, calls the pure
//! edit of `model/chain/edit.rs`, checks the result, and makes one undo
//! step. A refused edit gives its message and changes nothing.
//!
//! The first edit of an owner with no chain makes the chain of its devices
//! in series. An edit inside a linked rack that changes its parts (not a
//! value) changes the rack's definition, and so each other instance.

use std::collections::{BTreeSet, HashSet};
use std::sync::Arc;

use anyhow::{Context, Result, bail};
use serde::Deserialize;
use serde_json::{Map, Value};

use super::Document;
use crate::model::chain::edit::{self, Change, KeyFrom};
use crate::model::chain::{Branch, Chain, KindSpec, Macro, Split, SplitKinds, Zone};
use crate::model::ids::{DefId, DeviceId, NodeId, ParamKey};
use crate::model::kinds::Owner;
use crate::model::owner::OwnerRef;
use crate::model::racks::RackDef;
use crate::model::{DeviceInst, Project};
use crate::session::{de, de_meta};

/// Where a node goes, as Lua gives it: `{ before = id }`, `{ after = id }`
/// or `{ branch = id, index = n }` (from 0 here; past the end for the end).
#[derive(Clone, Debug, Default, Deserialize)]
pub(crate) struct Place {
    pub before: Option<NodeId>,
    pub after: Option<NodeId>,
    pub branch: Option<NodeId>,
    pub index: Option<usize>,
}

impl TryFrom<&Place> for edit::Place {
    type Error = anyhow::Error;

    fn try_from(place: &Place) -> Result<Self> {
        Ok(match (place.before, place.after, place.branch) {
            (Some(id), None, None) => Self::Before(id),
            (None, Some(id), None) => Self::After(id),
            (None, None, Some(branch)) => Self::Into { branch, index: place.index.unwrap_or(usize::MAX) },
            _ => bail!("a place is one of {{ before = id }}, {{ after = id }} or {{ branch = id, index = n }}"),
        })
    }
}

/// What a wrap makes, besides its kind.
#[derive(Clone, Debug, Default, Deserialize)]
pub(crate) struct WrapOpts {
    /// How many branches; the kind's first count when not given.
    pub branches: Option<usize>,
    pub name: Option<String>,
    /// Values of the kind, over its first values.
    #[serde(default)]
    pub values: Map<String, Value>,
}

/// What an edit made: the new chain, the devices it adds to the owner, and
/// what the edit gives back.
struct Edited<R> {
    chain: Chain,
    added: Vec<DeviceInst>,
    out: R,
}

impl<R> Edited<R> {
    fn of(chain: Chain, out: R) -> Self {
        Self { chain, added: Vec::new(), out }
    }
}

/// The ids of the linked racks that hold any of `ids`, or are one of them.
fn linked_around(chain: &Chain, ids: &[NodeId]) -> BTreeSet<NodeId> {
    ids.iter().flat_map(|id| chain.root.path_to(*id)).filter(|s| s.linked.is_some()).map(|s| s.id).collect()
}

impl Document {
    /// The chain of `owner` now: its own, or its devices in series when it
    /// has none.
    fn chain_now(&self, owner: OwnerRef, new_id: &mut dyn FnMut() -> NodeId) -> Result<Chain> {
        let t = self.project.owner(owner).with_context(|| format!("no {owner}"))?;
        Ok(match &t.chain {
            Some(chain) => (**chain).clone(),
            None => Chain::serial(t.device_ids(), new_id),
        })
    }

    /// An edit of the chain of `owner`: `f` gives the new chain from the
    /// chain now (the devices in series when the owner has none), and may
    /// add devices to the owner. The devices that leave the chain leave
    /// the owner, with their lanes. The result must pass `Chain::check`.
    /// With `structural`, a linked rack around one of `touched` (before or
    /// after) gives its new parts to its definition.
    fn chain_edit<R>(
        &mut self,
        owner: OwnerRef,
        touched: &[NodeId],
        structural: bool,
        f: impl FnOnce(&Chain, &mut dyn FnMut() -> NodeId) -> Result<Edited<R>>,
    ) -> Result<R> {
        let kinds = self.split_kinds.clone();
        let mut next = self.next_id;
        let mut new_id = || {
            next += 1;
            NodeId::new(next - 1)
        };
        let chain = self.chain_now(owner, &mut new_id)?;
        let mut linked = if structural { linked_around(&chain, touched) } else { BTreeSet::new() };
        let Edited { chain: made, added, out } = f(&chain, &mut new_id)?;
        let before: HashSet<DeviceId> = chain.devices().into_iter().collect();
        let after: HashSet<DeviceId> = made.devices().into_iter().collect();
        let gone: HashSet<u64> = before.difference(&after).map(|d| d.get()).collect();
        let t = self.project.owner(owner).context("no owner")?;
        let mut ids: Vec<DeviceId> = t.device_ids().into_iter().filter(|id| !gone.contains(&id.get())).collect();
        ids.extend(added.iter().map(|d| DeviceId::from(d.id)));
        made.check(&ids, &kinds)?;
        if structural {
            linked.extend(linked_around(&made, touched));
        }
        let result = self.edit(|p| {
            let t = p.owner_mut(owner).context("no owner")?;
            t.devices.retain(|d| !gone.contains(&d.id));
            t.lanes.retain(|l| l.target.device().is_none_or(|d| !gone.contains(&d)));
            t.devices.extend(added.into_iter().map(Arc::new));
            t.chain = Some(Arc::new(made));
            t.fit_chain();
            for split in linked {
                if p.chain_of(owner).is_some_and(|c| c.holds(split)) {
                    p.rack_apply(owner, split, true, &mut new_id)?;
                }
            }
            Ok(out)
        });
        self.next_id = self.next_id.max(next);
        result
    }

    /// Wrap the nodes `nodes` (one or more in a row of one branch, in any
    /// order) in a new split of `kind`. They go into its first branch.
    /// Gives the split's id.
    pub(crate) fn chain_wrap(&mut self, owner: OwnerRef, nodes: &[NodeId], kind: &str, opts: WrapOpts) -> Result<NodeId> {
        let count = match opts.branches {
            Some(n) => n,
            None => self.split_kinds.first_branches(kind)?,
        };
        let (kind, mut values) = self.split_kinds.new_split_kind(kind, count)?;
        values.extend(opts.values);
        self.chain_edit(owner, nodes, true, |chain, new_id| {
            let mut split = Split::new(kind, values, count, new_id);
            split.name = opts.name.unwrap_or_default();
            let id = split.id;
            Ok(Edited::of(edit::wrap(chain, nodes, split)?, id))
        })
    }

    /// Take the split `split` away: see `edit::unwrap`. Gives how many
    /// devices left the owner.
    pub(crate) fn chain_unwrap(&mut self, owner: OwnerRef, split: NodeId, keep: Option<NodeId>) -> Result<usize> {
        self.chain_edit(owner, &[split], true, |chain, _| {
            let made = edit::unwrap(chain, split, keep)?;
            let gone = chain.devices().len() - made.devices().len();
            Ok(Edited::of(made, gone))
        })
    }

    /// Add an empty branch to the split `split`, at `index` (from 0; the
    /// end when not given). Gives its id.
    pub(crate) fn chain_branch_add(
        &mut self,
        owner: OwnerRef,
        split: NodeId,
        name: Option<String>,
        index: Option<usize>,
    ) -> Result<NodeId> {
        self.chain_edit(owner, &[split], true, |chain, new_id| {
            let mut branch = Branch::new(new_id());
            branch.name = name.unwrap_or_default();
            let id = branch.id;
            Ok(Edited::of(edit::add_branch(chain, split, branch, index)?, id))
        })
    }

    /// Move the node `id` to `place`, in the same chain.
    pub(crate) fn chain_move(&mut self, owner: OwnerRef, id: NodeId, place: &Place) -> Result<()> {
        let to = edit::Place::try_from(place)?;
        self.chain_edit(owner, &[id, to.near()], true, |chain, _| Ok(Edited::of(edit::move_node(chain, id, to)?, ())))
    }

    /// Remove what `id` names: a split with its devices, a branch with its
    /// devices, a macro with its links, or a device.
    pub(crate) fn chain_remove(&mut self, owner: OwnerRef, id: NodeId) -> Result<()> {
        self.chain_edit(owner, &[id], true, |chain, _| Ok(Edited::of(edit::remove(chain, id)?, ())))
    }

    /// Set a value of the split, branch or macro `id`: see `paw.chain.set`.
    pub(crate) fn chain_set(&mut self, owner: OwnerRef, id: NodeId, key: &str, value: Value) -> Result<()> {
        let change = self.change(owner, id, key, value)?;
        // A new kind keeps the branches; it is a new part of a linked rack.
        let structural = matches!(change, Change::Kind(..));
        self.chain_edit(owner, &[id], structural, |chain, _| Ok(Edited::of(edit::set(chain, id, change)?, ())))
    }

    /// The change that `key` and `value` name for the item `id`.
    fn change(&self, owner: OwnerRef, id: NodeId, key: &str, value: Value) -> Result<Change> {
        let chain = self.project.chain_of(owner);
        let split = chain.and_then(|c| c.root.split(id));
        Ok(match key {
            "name" => Change::Name(de(key, value)?),
            "mix" => Change::Mix(de(key, value)?),
            "gain" => Change::Gain(de(key, value)?),
            "pan" => Change::Pan(de(key, value)?),
            "mute" => Change::Mute(de(key, value)?),
            "solo" => Change::Solo(de(key, value)?),
            "value" => Change::Value(de(key, value)?),
            "values" => Change::Values(de_meta(key, value)?),
            // An empty table, as Lua gives `{}`, is no zone.
            "zone" => Change::Zone(match value {
                Value::Array(a) if a.is_empty() => None,
                value => de::<Option<Zone>>(key, value)?,
            }),
            "kind" => {
                let word: String = de(key, value)?;
                let branches = split.map_or(1, |s| s.branches.len());
                let (kind, values) = self.split_kinds.new_split_kind(&word, branches)?;
                Change::Kind(kind, values)
            }
            _ => {
                let (what, say) = match (split, chain.and_then(|c| c.root.branch(id))) {
                    (Some(_), _) => ("a split", edit::SPLIT_VALUES),
                    (None, Some(_)) => ("a branch", edit::BRANCH_VALUES),
                    (None, None) => ("a macro", edit::MACRO_VALUES),
                };
                bail!("{what} has no value `{key}`: say {say}")
            }
        })
    }

    /// Add a macro named `name` to the split `split`. Gives its id.
    pub(crate) fn chain_macro_add(&mut self, owner: OwnerRef, split: NodeId, name: &str) -> Result<NodeId> {
        self.chain_edit(owner, &[split], true, |chain, new_id| {
            let m = Macro { id: new_id(), name: name.to_owned(), value: 0.0 };
            let id = m.id;
            Ok(Edited::of(edit::add_macro(chain, split, m)?, id))
        })
    }

    /// Link the macro `source` to the parameter `param` of `device`, with
    /// `depth`; `None` removes the link.
    pub(crate) fn chain_link(
        &mut self,
        owner: OwnerRef,
        source: NodeId,
        device: DeviceId,
        param: &str,
        depth: Option<f64>,
    ) -> Result<()> {
        self.chain_edit(owner, &[source], true, |chain, _| {
            Ok(Edited::of(edit::link(chain, source, device, ParamKey::from(param), depth)?, ()))
        })
    }

    /// Let `device` take its key from `from`, or from no node of its chain.
    pub(crate) fn chain_tap(&mut self, owner: OwnerRef, device: DeviceId, from: Option<KeyFrom>) -> Result<()> {
        self.chain_edit(owner, &[device.into()], true, |chain, _| Ok(Edited::of(edit::tap(chain, device, from)?, ())))
    }

    /// A copy of `chain` for the copies `to` of the devices `from` (in the
    /// same order), with new ids for its own parts.
    pub(in crate::session) fn copy_chain(
        &mut self,
        chain: &Chain,
        from: &[Arc<DeviceInst>],
        to: &[Arc<DeviceInst>],
    ) -> Chain {
        let mut ids: std::collections::HashMap<NodeId, NodeId> =
            from.iter().zip(to).map(|(a, b)| (NodeId::new(a.id), NodeId::new(b.id))).collect();
        let mut copy = chain.clone();
        copy.map_ids(&mut |id| *ids.entry(id).or_insert_with(|| NodeId::new(self.new_id())));
        copy
    }

    /// Let a chain have a split of a new kind (`paw.chain.define_kind`), of
    /// the extension `owner` (the user's when `None`).
    pub(crate) fn chain_kind_define(&mut self, word: &str, spec: KindSpec, owner: Option<&str>) -> Result<()> {
        let kind = word.parse()?;
        let owner = owner.map_or(Owner::User, |name| Owner::Extension(name.into()));
        Ok(self.split_kinds.define(kind, spec, owner)?)
    }

    /// The names of the kinds of split.
    pub(crate) fn chain_kinds(&self) -> Vec<String> {
        self.split_kinds.words()
    }

    /// The registry of the kinds of split.
    pub(crate) fn split_kinds(&self) -> &SplitKinds {
        &self.split_kinds
    }

    // --- linked racks ---

    /// Run `f` on the project with ids from the document, as one edit.
    fn rack_edit<R>(&mut self, f: impl FnOnce(&mut Project, &mut dyn FnMut() -> NodeId) -> Result<R>) -> Result<R> {
        let mut next = self.next_id;
        let result = self.edit(|p| {
            let mut new_id = || {
                next += 1;
                NodeId::new(next - 1)
            };
            f(p, &mut new_id)
        });
        self.next_id = self.next_id.max(next);
        result
    }

    /// Make the split `split` a linked rack named `name`: the first instance
    /// of a new definition. Gives the definition's id.
    pub(crate) fn rack_define(&mut self, owner: OwnerRef, split: NodeId, name: &str) -> Result<DefId<RackDef>> {
        self.rack_edit(|p, new_id| p.rack_define(owner, split, name, new_id))
    }

    /// Put a new instance of the rack definition `rack` at `place` in the
    /// chain of `owner`. Gives the instance split's id.
    pub(crate) fn rack_place(&mut self, owner: OwnerRef, rack: DefId<RackDef>, place: &Place) -> Result<NodeId> {
        let to = edit::Place::try_from(place)?;
        let mut next = self.next_id;
        let made = {
            let mut new_id = || {
                next += 1;
                NodeId::new(next - 1)
            };
            self.project.rack_instance(rack, &mut new_id)?
        };
        self.next_id = next;
        self.chain_edit(owner, &[], false, |chain, _| {
            let (split, devices) = made;
            let id = split.id;
            let chain = edit::insert(chain, split, to)?;
            Ok(Edited { chain, added: devices, out: id })
        })
    }

    /// Make the definition of the instance `split` what it is now: each
    /// other instance follows, and keeps its overrides.
    pub(crate) fn rack_apply(&mut self, owner: OwnerRef, split: NodeId) -> Result<()> {
        self.rack_edit(|p, new_id| p.rack_apply(owner, split, false, new_id))
    }

    /// Give the instance `split` each value of its definition. Gives how
    /// many overrides went.
    pub(crate) fn rack_reset(&mut self, owner: OwnerRef, split: NodeId) -> Result<usize> {
        self.rack_edit(|p, new_id| p.rack_reset(owner, split, new_id))
    }

    /// Make the instance `split` a copy that follows no definition.
    pub(crate) fn rack_unlink(&mut self, owner: OwnerRef, split: NodeId) -> Result<()> {
        self.rack_edit(|p, _| p.rack_unlink(owner, split))
    }

    /// Change a value of the definition `rack` (`#<id>.<field>`), in each
    /// instance that does not override it.
    pub(crate) fn rack_set(&mut self, rack: DefId<RackDef>, key: &str, value: Value) -> Result<()> {
        self.rack_edit(|p, new_id| p.rack_set(rack, key, value, new_id))
    }
}

#[cfg(test)]
mod tests;
