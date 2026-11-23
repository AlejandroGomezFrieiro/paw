//! The kinds of split: a word for each, the built-in kinds of the core, and
//! the kinds that extensions add.
//!
//! A split names its kind with a word (`"band"`), and keeps the values of
//! its kind in `Split::values` (the crossovers of a band split). The core
//! knows the built-in kinds and checks their values. An extension adds a
//! kind with the number of branches it takes, and its values are its own.

use std::collections::BTreeMap;
use std::ops::RangeInclusive;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};

use super::{GraphError, MAX_BRANCHES, Split};
use crate::model::Word;

/// The built-in kinds of split.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Builtin {
    /// One branch in series: a rack, and the root of each graph.
    Chain,
    /// A copy of the input into each branch, summed.
    Layer,
    /// Frequency bands, one for each branch. Values: `xover`, the
    /// crossovers in Hz, low to high, one fewer than the branches.
    Band,
    /// Mid (branch 1) and side (branch 2).
    Ms,
    /// Left (branch 1) and right (branch 2).
    Lr,
    /// The notes go to the branches whose key zone holds them.
    Key,
    /// The notes go to the branches whose velocity zone holds them.
    Vel,
    /// One branch hears the input at a time. Values: `index` (from 0),
    /// `fade` (ms), `mode` (manual, round-robin, keyswitch, cc).
    Select,
    /// The output pairs of the device before the split, one for each branch.
    Outs,
}

/// The modes of a `select` split.
const SELECT_MODES: [&str; 4] = ["manual", "round-robin", "keyswitch", "cc"];

impl Builtin {
    const ALL: [Builtin; 9] =
        [Self::Chain, Self::Layer, Self::Band, Self::Ms, Self::Lr, Self::Key, Self::Vel, Self::Select, Self::Outs];

    pub fn of(word: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|kind| kind.word() == word)
    }

    pub fn word(self) -> &'static str {
        match self {
            Self::Chain => "chain",
            Self::Layer => "layer",
            Self::Band => "band",
            Self::Ms => "ms",
            Self::Lr => "lr",
            Self::Key => "key",
            Self::Vel => "vel",
            Self::Select => "select",
            Self::Outs => "outs",
        }
    }

    fn spec(self) -> KindSpec {
        let (min, max) = match self {
            Self::Chain => (1, 1),
            Self::Band => (2, 6),
            Self::Ms | Self::Lr => (2, 2),
            Self::Layer | Self::Key | Self::Vel | Self::Select | Self::Outs => (1, MAX_BRANCHES),
        };
        let first = match self {
            Self::Chain => 1,
            Self::Band => 3,
            _ => 2,
        };
        KindSpec { min, max, first }
    }

    /// The values of a new split of the kind with `branches` branches.
    fn first_values(self, branches: usize) -> Map<String, Value> {
        let mut values = Map::new();
        match self {
            Self::Band => {
                values.insert("xover".into(), json!(default_crossovers(branches)));
            }
            Self::Select => {
                values.insert("index".into(), json!(0));
            }
            _ => {}
        }
        values
    }

    /// Check the values of a split of the kind.
    fn check(self, split: &Split) -> Result<(), GraphError> {
        let count = split.branches.len();
        match self {
            Self::Band => {
                let xover: Vec<f64> = value(split, "xover", "a list of frequencies")?.unwrap_or_default();
                check_crossovers(&xover, count)
            }
            Self::Select => {
                let index: usize = value(split, "index", "a branch from 0")?.unwrap_or(0);
                if index >= count {
                    return Err(GraphError::SelectIndex { index, count });
                }
                let fade: f64 = value(split, "fade", "a time in ms")?.unwrap_or(0.0);
                super::in_range("the fade", fade, 0.0..=10_000.0)?;
                let mode: String = value(split, "mode", "a mode")?.unwrap_or_else(|| "manual".into());
                if !SELECT_MODES.contains(&mode.as_str()) {
                    return Err(GraphError::Value { key: "mode", want: "manual, round-robin, keyswitch or cc" });
                }
                Ok(())
            }
            _ => Ok(()),
        }
    }
}

/// The value `key` of the split, read as `T`; `None` when it has none.
fn value<T: serde::de::DeserializeOwned>(
    split: &Split,
    key: &'static str,
    want: &'static str,
) -> Result<Option<T>, GraphError> {
    split
        .values
        .get(key)
        .map(|v| serde_json::from_value(v.clone()).map_err(|_| GraphError::Value { key, want }))
        .transpose()
}

fn check_crossovers(xover: &[f64], bands: usize) -> Result<(), GraphError> {
    if xover.len() + 1 != bands {
        return Err(GraphError::CrossoverCount { bands, count: xover.len() });
    }
    if let Some(bad) = xover.iter().find(|f| !f.is_finite() || **f <= 0.0) {
        return Err(GraphError::CrossoverValue(*bad));
    }
    match xover.windows(2).find(|pair| pair[1] <= pair[0]) {
        Some(pair) => Err(GraphError::CrossoverOrder { before: pair[0], next: pair[1] }),
        None => Ok(()),
    }
}

/// Crossovers that spread `bands` bands over the range of music.
pub fn default_crossovers(bands: usize) -> Vec<f64> {
    match bands {
        0 | 1 => Vec::new(),
        2 => vec![1000.0],
        3 => vec![120.0, 2000.0],
        4 => vec![120.0, 800.0, 4000.0],
        5 => vec![100.0, 400.0, 1600.0, 6000.0],
        n => {
            // Even steps on a log scale from 80 Hz to 10 kHz.
            let steps = (n - 2) as f64;
            (0..n - 1).map(|i| (80.0 * 125.0f64.powf(i as f64 / steps)).round()).collect()
        }
    }
}

/// What a kind of split takes.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct KindSpec {
    /// The fewest and the most branches.
    pub min: usize,
    pub max: usize,
    /// How many branches a new split of the kind gets.
    pub first: usize,
}

impl KindSpec {
    pub fn branches(&self) -> RangeInclusive<usize> {
        self.min..=self.max
    }
}

/// The kinds of split that the project can have: the built-in kinds, and
/// those extensions defined. Not part of the project.
#[derive(Clone, Debug, Default)]
pub struct SplitKinds {
    added: BTreeMap<Word, KindSpec>,
}

impl SplitKinds {
    /// Add a kind (an extension's). A built-in kind cannot change.
    pub fn define(&mut self, word: Word, spec: KindSpec) -> Result<(), GraphError> {
        if Builtin::of(word.as_str()).is_some() {
            return Err(GraphError::BuiltinKind(word.to_string()));
        }
        if spec.min == 0 || spec.min > spec.max || spec.max > MAX_BRANCHES || !spec.branches().contains(&spec.first) {
            return Err(GraphError::KindBranches(word.to_string()));
        }
        self.added.insert(word, spec);
        Ok(())
    }

    /// What the kind `word` takes; `None` for a kind that no one defined.
    pub fn spec(&self, word: &str) -> Option<KindSpec> {
        Builtin::of(word)
            .map(Builtin::spec)
            .or_else(|| self.added.iter().find(|(w, _)| w.as_str() == word).map(|(_, spec)| *spec))
    }

    /// The word of a known kind, and the values of a new split of it with
    /// `branches` branches.
    pub fn new_split_kind(&self, word: &str, branches: usize) -> Result<(Word, Map<String, Value>), GraphError> {
        if self.spec(word).is_none() {
            return Err(GraphError::UnknownKind(word.to_owned()));
        }
        let parsed: Word = word.parse().map_err(|_| GraphError::UnknownKind(word.to_owned()))?;
        let values = Builtin::of(word).map(|b| b.first_values(branches)).unwrap_or_default();
        Ok((parsed, values))
    }

    /// How many branches a new split of `word` gets.
    pub fn first_branches(&self, word: &str) -> Result<usize, GraphError> {
        self.spec(word).map(|s| s.first).ok_or_else(|| GraphError::UnknownKind(word.to_owned()))
    }

    /// Check one split against its kind: the number of branches, and the
    /// values of a built-in kind.
    pub fn check(&self, split: &Split) -> Result<(), GraphError> {
        let word = split.kind.as_str();
        let spec = self.spec(word).ok_or_else(|| GraphError::UnknownKind(word.to_owned()))?;
        let count = split.branches.len();
        if !spec.branches().contains(&count) {
            return Err(GraphError::Branches { kind: word.to_owned(), range: spec.branches(), count });
        }
        Builtin::of(word).map_or(Ok(()), |b| b.check(split))
    }

    /// Every kind's word: the built-in kinds first.
    pub fn words(&self) -> Vec<String> {
        Builtin::ALL.iter().map(|b| b.word().to_owned()).chain(self.added.keys().map(Word::to_string)).collect()
    }
}
