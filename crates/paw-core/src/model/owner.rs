//! The owners of chains. A chain (`model/chain.rs`) does not know its
//! owner: this module finds the owner by its handle, and keeps each chain
//! in step with the list of its owner's devices.
//!
//! A part owns a chain (`Part::chain`). Each lookup of
//! an owner goes through [`Project::owner`] and [`Project::owner_mut`], so
//! that a new kind of owner (a part, a strip) is one variant of
//! [`OwnerRef`] and one arm of each lookup.

use std::collections::HashMap;
use std::sync::Arc;

use serde::{Deserialize, Serialize};

use super::chain::Chain;
use super::ids::{DeviceId, PartId};
use super::{Project, Part};

/// A handle of an owner of a chain, as the API gives it (`{ part = 3 }`).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum OwnerRef {
    Part(PartId),
}

impl std::fmt::Display for OwnerRef {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Part(id) => write!(f, "part {id}"),
        }
    }
}

impl Project {
    /// The part that `owner` names.
    pub(crate) fn owner(&self, owner: OwnerRef) -> Option<&Part> {
        match owner {
            OwnerRef::Part(id) => self.part(id.get()).map(|t| &**t),
        }
    }

    pub(crate) fn owner_mut(&mut self, owner: OwnerRef) -> Option<&mut Part> {
        match owner {
            OwnerRef::Part(id) => self.part_mut(id.get()),
        }
    }

    /// The chain of `owner`, or `None` when it has none (its devices play
    /// in series).
    pub(crate) fn chain_of(&self, owner: OwnerRef) -> Option<&Arc<Chain>> {
        self.owner(owner)?.chain.as_ref()
    }

    /// Each owner that has a chain, with the chain.
    pub(crate) fn chains(&self) -> impl Iterator<Item = (OwnerRef, &Arc<Chain>)> {
        self.all_parts().filter_map(|t| t.chain.as_ref().map(|c| (OwnerRef::Part(t.id.into()), c)))
    }

    /// Make each chain name its owner's devices again, and put the devices
    /// in the chain's signal order (see the head of `model/chain.rs`). An
    /// edit of the list of devices that does not know the chain (a device
    /// added at the end, removed, or moved to another part) leaves the
    /// chain behind until this runs. An owner whose chain is true is not
    /// touched.
    pub fn fit_chains(&mut self) {
        for t in self.parts.iter_mut().chain(std::iter::once(&mut self.master)) {
            let Some(chain) = &t.chain else { continue };
            if !chain.names_in_order(t.devices.iter().map(|d| DeviceId::from(d.id))) {
                Arc::make_mut(t).fit_chain();
            }
        }
    }
}

impl Part {
    /// The ids of the devices, in the order of the list.
    pub(crate) fn device_ids(&self) -> Vec<DeviceId> {
        self.devices.iter().map(|d| DeviceId::from(d.id)).collect()
    }

    /// Fit the chain to the devices, then sort the devices into the chain's
    /// signal order.
    pub(crate) fn fit_chain(&mut self) {
        let ids = self.device_ids();
        let Some(chain) = &mut self.chain else { return };
        let chain = Arc::make_mut(chain);
        chain.fit(&ids);
        let order: HashMap<DeviceId, usize> = chain.devices().into_iter().enumerate().map(|(i, id)| (id, i)).collect();
        self.devices.sort_by_key(|d| order.get(&DeviceId::from(d.id)).copied().unwrap_or(usize::MAX));
    }
}
