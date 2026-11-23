//! Linked instances: parts of the project that follow a definition. A
//! change of the definition reaches each instance, and what one instance
//! overrides stays on that instance.
//!
//! A kind of definition is [`Linkable`]: it names the type of what one
//! instance has of its own (`Overrides`). [`Linked`] is the link of one
//! instance, and [`Defs`] holds the definitions of one kind in the project.
//! Each kind follows its definition in its own way: a linked rack is a copy
//! that follows (`model/racks.rs`), with [`Keyed`] to say which values it
//! keeps.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::sync::Arc;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use super::ids::DefId;

/// A kind of definition that instances link to.
pub trait Linkable: Clone {
    /// What one instance has of its own.
    type Overrides: Clone + Default + PartialEq + fmt::Debug + Serialize + DeserializeOwned;

    /// The id of the definition in the project.
    fn id(&self) -> DefId<Self>;
}

/// The link from an instance to the definition it follows.
#[derive(Serialize, Deserialize)]
#[serde(bound = "")]
pub struct Linked<D: Linkable> {
    /// The definition.
    pub of: DefId<D>,
    /// What this instance has of its own.
    #[serde(default)]
    pub overrides: D::Overrides,
}

impl<D: Linkable> Linked<D> {
    /// A new instance of `of`, with nothing of its own.
    pub fn new(of: DefId<D>) -> Self {
        Self { of, overrides: D::Overrides::default() }
    }
}

// By hand: a derive would ask `D` for each trait, and the link holds no `D`.
impl<D: Linkable> Clone for Linked<D> {
    fn clone(&self) -> Self {
        Self { of: self.of, overrides: self.overrides.clone() }
    }
}

impl<D: Linkable> PartialEq for Linked<D> {
    fn eq(&self, other: &Self) -> bool {
        self.of == other.of && self.overrides == other.overrides
    }
}

impl<D: Linkable> fmt::Debug for Linked<D> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Linked").field("of", &self.of).field("overrides", &self.overrides).finish()
    }
}

/// The definitions of one kind in the project, in the order they were
/// made. The file holds them as a list, each with its id.
#[derive(Serialize, Deserialize)]
#[serde(transparent, bound(serialize = "D: Serialize", deserialize = "D: Deserialize<'de>"))]
pub struct Defs<D>(Vec<Arc<D>>);

impl<D> Default for Defs<D> {
    fn default() -> Self {
        Self(Vec::new())
    }
}

impl<D> Clone for Defs<D> {
    fn clone(&self) -> Self {
        Self(self.0.clone())
    }
}

impl<D: fmt::Debug> fmt::Debug for Defs<D> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_list().entries(self.0.iter()).finish()
    }
}

impl<D: Linkable> Defs<D> {
    pub fn get(&self, id: DefId<D>) -> Option<&Arc<D>> {
        self.0.iter().find(|d| d.id() == id)
    }

    /// Add a definition at the end.
    pub fn push(&mut self, def: D) {
        self.0.push(Arc::new(def));
    }

    /// Put `def` in the place of the definition with its id. False when no
    /// definition has that id.
    pub fn replace(&mut self, def: D) -> bool {
        match self.0.iter_mut().find(|d| d.id() == def.id()) {
            Some(slot) => {
                *slot = Arc::new(def);
                true
            }
            None => false,
        }
    }

    pub fn iter(&self) -> impl Iterator<Item = &Arc<D>> {
        self.0.iter()
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

/// The keys of the values that an instance keeps when its definition
/// changes. The kind of definition gives each value its key.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent, bound(serialize = "K: Serialize", deserialize = "K: Deserialize<'de>"))]
pub struct Keyed<K: Ord>(pub BTreeSet<K>);

impl<K: Ord> Default for Keyed<K> {
    fn default() -> Self {
        Self(BTreeSet::new())
    }
}

impl<K: Ord + Clone> Keyed<K> {
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// The value of each key after the definition changed from `old` to
    /// `new`, for an instance whose values are `here`. The instance keeps
    /// the value of a key that it overrides, or whose value differs from
    /// `old` (it changed here since the last change). A key that `old` did
    /// not have, and the instance has, also changed here: a parameter that
    /// the definition left at its default, and the instance set. Else it
    /// takes the value of `new`. The keys that it keeps become its
    /// overrides.
    pub fn follow<V: PartialEq + Clone>(
        &mut self,
        old: Option<&BTreeMap<K, V>>,
        new: &BTreeMap<K, V>,
        here: &BTreeMap<K, V>,
    ) -> BTreeMap<K, V> {
        let mut out = BTreeMap::new();
        let mut kept = BTreeSet::new();
        for (key, value) in new {
            let mine = here.get(key);
            let changed_here = match (old, mine) {
                (Some(old), Some(now)) => old.get(key) != Some(now),
                _ => false,
            };
            match mine {
                Some(mine) if self.0.contains(key) || changed_here => {
                    kept.insert(key.clone());
                    out.insert(key.clone(), mine.clone());
                }
                _ => {
                    out.insert(key.clone(), value.clone());
                }
            }
        }
        self.0 = kept;
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn values(pairs: &[(&str, i32)]) -> BTreeMap<String, i32> {
        pairs.iter().map(|(k, v)| ((*k).to_owned(), *v)).collect()
    }

    fn keys(keys: &[&str]) -> Keyed<String> {
        Keyed(keys.iter().map(|k| (*k).to_owned()).collect())
    }

    #[test]
    fn an_instance_follows_the_definition_but_keeps_what_it_changed() {
        let mut overrides = Keyed::default();
        let old = values(&[("a", 1), ("b", 1)]);
        let new = values(&[("a", 2), ("b", 2), ("c", 3)]);
        let here = values(&[("a", 1), ("b", 9)]);
        let out = overrides.follow(Some(&old), &new, &here);
        assert_eq!(out, values(&[("a", 2), ("b", 9), ("c", 3)]));
        assert_eq!(overrides, keys(&["b"]));
        // The override stays at the next change, though the definition now
        // has the same value.
        let newer = values(&[("a", 4), ("b", 9), ("c", 3)]);
        let out = overrides.follow(Some(&new), &newer, &out);
        assert_eq!(out["b"], 9);
        assert!(overrides.0.contains("b"));
    }

    #[test]
    fn a_value_that_only_the_instance_had_is_its_own() {
        let mut overrides = Keyed::default();
        let old = values(&[("a", 1)]);
        let new = values(&[("a", 1), ("b", 2), ("c", 3)]);
        let here = values(&[("a", 1), ("b", 9)]);
        let out = overrides.follow(Some(&old), &new, &here);
        assert_eq!(out, values(&[("a", 1), ("b", 9), ("c", 3)]));
        assert_eq!(overrides, keys(&["b"]));
    }
}
