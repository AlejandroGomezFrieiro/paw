//! Typed ids of the model. Each is the number that the files hold, so a
//! file does not change, and each names one kind of thing, so a device id
//! cannot stand where a definition goes.
//!
//! The ids of parts, devices and the nodes of a chain come from the
//! project's one space of ids: one number names one thing of the project.
//! So a device is also a node of the chain that holds it, and
//! [`NodeId::from`] a [`DeviceId`] is the same number.

use std::fmt;
use std::marker::PhantomData;
use std::sync::Arc;

use serde::{Deserialize, Deserializer, Serialize, Serializer};

macro_rules! ids {
    ($($(#[$doc:meta])* $name:ident;)*) => {
        $(
            $(#[$doc])*
            #[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
            #[serde(transparent)]
            pub struct $name(u64);

            impl $name {
                pub const fn new(raw: u64) -> Self {
                    Self(raw)
                }

                /// The number that the files hold.
                pub const fn get(self) -> u64 {
                    self.0
                }
            }

            impl From<u64> for $name {
                fn from(raw: u64) -> Self {
                    Self(raw)
                }
            }

            impl fmt::Display for $name {
                fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                    self.0.fmt(f)
                }
            }
        )*
    };
}

ids! {
    /// A part: the owner of a chain.
    PartId;
    /// A device of a part.
    DeviceId;
    /// A node of a chain: a split, a branch, a macro, or a device in its
    /// place.
    NodeId;
}

impl From<DeviceId> for NodeId {
    /// A device in its place in a chain.
    fn from(device: DeviceId) -> Self {
        Self(device.0)
    }
}

impl From<NodeId> for DeviceId {
    /// The device of a node that is a device. The number is the same; the
    /// chain says whether the node is one.
    fn from(node: NodeId) -> Self {
        Self(node.0)
    }
}

/// The key of a parameter of a device, as its schema names it (`gain`,
/// `ratio`).
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ParamKey(Arc<str>);

impl ParamKey {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl From<&str> for ParamKey {
    fn from(key: &str) -> Self {
        Self(key.into())
    }
}

impl From<String> for ParamKey {
    fn from(key: String) -> Self {
        Self(key.into())
    }
}

impl fmt::Display for ParamKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// The id of a linked definition of the kind `D` (a rack definition).
pub struct DefId<D> {
    raw: u64,
    def: PhantomData<fn() -> D>,
}

impl<D> DefId<D> {
    pub const fn new(raw: u64) -> Self {
        Self { raw, def: PhantomData }
    }

    /// The number that the files hold.
    pub const fn get(self) -> u64 {
        self.raw
    }
}

// By hand: a derive would ask `D` for each trait, and the id holds no `D`.
impl<D> Clone for DefId<D> {
    fn clone(&self) -> Self {
        *self
    }
}

impl<D> Copy for DefId<D> {}

impl<D> PartialEq for DefId<D> {
    fn eq(&self, other: &Self) -> bool {
        self.raw == other.raw
    }
}

impl<D> Eq for DefId<D> {}

impl<D> PartialOrd for DefId<D> {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl<D> Ord for DefId<D> {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.raw.cmp(&other.raw)
    }
}

impl<D> std::hash::Hash for DefId<D> {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.raw.hash(state);
    }
}

impl<D> fmt::Debug for DefId<D> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "DefId({})", self.raw)
    }
}

impl<D> fmt::Display for DefId<D> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.raw.fmt(f)
    }
}

impl<D> Serialize for DefId<D> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_u64(self.raw)
    }
}

impl<'de, D> Deserialize<'de> for DefId<D> {
    fn deserialize<De: Deserializer<'de>>(deserializer: De) -> Result<Self, De::Error> {
        u64::deserialize(deserializer).map(Self::new)
    }
}
