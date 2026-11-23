//! A linked instance: a part of the project that follows a definition. A
//! change of the definition reaches each instance, and what one instance
//! overrides stays on that instance.
//!
//! [`Linked`] does not know where the definition is (a rack definition of
//! the project now, a template of a store later) or what kind of part the
//! instance is. `D` names the definition, and `O` is what one instance has
//! of its own. Linked clips have the same shape: the name of a link, and
//! the transpose and velocity of `model::Overrides`. [`Keyed`] is the
//! overrides of a part whose values have keys: it decides which value an
//! instance keeps when its definition changes.

use std::collections::{BTreeMap, BTreeSet};

use serde::{Deserialize, Serialize};

/// The link from an instance to the definition it follows.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Linked<D, O> {
    /// The definition.
    pub of: D,
    /// What this instance has of its own.
    #[serde(default)]
    pub overrides: O,
}

/// The keys of the values that an instance keeps when its definition
/// changes. The kind of part gives each value its key.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct Keyed(pub BTreeSet<String>);

impl Keyed {
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// The value of each key after the definition changed from `old` to
    /// `new`, for an instance whose values are `here`. The instance keeps
    /// the value of a key that it overrides, or whose value differs from
    /// `old` (it changed here since the last change). Else it takes the
    /// value of `new`. The keys that it keeps become its overrides.
    pub fn follow<V: PartialEq + Clone>(
        &mut self,
        old: Option<&BTreeMap<String, V>>,
        new: &BTreeMap<String, V>,
        here: &BTreeMap<String, V>,
    ) -> BTreeMap<String, V> {
        let mut out = BTreeMap::new();
        let mut kept = BTreeSet::new();
        for (key, value) in new {
            let mine = here.get(key);
            let changed_here = matches!((old.and_then(|o| o.get(key)), mine), (Some(was), Some(now)) if was != now);
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

    #[test]
    fn an_instance_follows_the_definition_but_keeps_what_it_changed() {
        let mut overrides = Keyed::default();
        let old = values(&[("a", 1), ("b", 1)]);
        let new = values(&[("a", 2), ("b", 2), ("c", 3)]);
        let here = values(&[("a", 1), ("b", 9)]);
        let out = overrides.follow(Some(&old), &new, &here);
        assert_eq!(out, values(&[("a", 2), ("b", 9), ("c", 3)]));
        assert_eq!(overrides, Keyed(BTreeSet::from(["b".to_owned()])));
        // The override stays at the next change, though the definition now
        // has the same value.
        let newer = values(&[("a", 4), ("b", 9), ("c", 3)]);
        let out = overrides.follow(Some(&new), &newer, &out);
        assert_eq!(out["b"], 9);
        assert!(overrides.0.contains("b"));
    }
}
