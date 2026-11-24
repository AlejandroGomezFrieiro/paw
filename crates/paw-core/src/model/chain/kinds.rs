//! The kinds of split: the built-in kinds of the core, the kinds that
//! extensions add, and their registry.
//!
//! A split names its kind (`"band"`) and keeps the values of its kind in
//! `Split::values` (the crossovers of a band split). The registry is a
//! [`Kinds`] of the split family: the built-in kinds are entries of owner
//! `paw.chain`, and an extension adds a kind with the number of branches
//! it takes. The core checks the values of a built-in kind; an extension's
//! values are its own.
#![expect(clippy::cast_precision_loss, reason = "debt: pay down")]

use std::ops::RangeInclusive;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};

use super::{ChainError, MAX_BRANCHES, Split};
use crate::model::kinds::{KindId, Kinds, Owner, SplitFamily};

/// The name of a kind of split.
pub type SplitKind = KindId<SplitFamily>;

/// The registry of the kinds of split. Not part of the project.
pub type SplitKinds = Kinds<SplitFamily, SplitImpl>;

/// The owner of the built-in kinds.
const PAW: Owner = Owner::Paw("paw.chain");

/// What paw keeps for a kind of split.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SplitImpl {
    /// A kind of the core, which paw checks and plays.
    Builtin(BuiltinSplit),
    /// A kind that an extension defined: the branches it takes.
    Declared(KindSpec),
}

/// The built-in kinds of split.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BuiltinSplit {
    /// One branch in series: a rack, and the root of each chain.
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

impl BuiltinSplit {
    pub const ALL: [BuiltinSplit; 9] =
        [Self::Chain, Self::Layer, Self::Band, Self::Ms, Self::Lr, Self::Key, Self::Vel, Self::Select, Self::Outs];

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

    /// The kind's name.
    pub fn kind(self) -> SplitKind {
        self.word().parse().expect("a built-in kind is a kind name")
    }

    pub fn spec(self) -> KindSpec {
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
    fn check(self, split: &Split) -> Result<(), ChainError> {
        let count = split.branches.len();
        match self {
            Self::Band => {
                let xover: Vec<f64> = value(split, "xover", "a list of frequencies")?.unwrap_or_default();
                check_crossovers(&xover, count)
            }
            Self::Select => {
                let index: usize = value(split, "index", "a branch from 0")?.unwrap_or(0);
                if index >= count {
                    return Err(ChainError::SelectIndex { index, count });
                }
                let fade: f64 = value(split, "fade", "a time in ms")?.unwrap_or(0.0);
                super::in_range("the fade", fade, 0.0..=10_000.0)?;
                let mode: String = value(split, "mode", "a mode")?.unwrap_or_else(|| "manual".into());
                if !SELECT_MODES.contains(&mode.as_str()) {
                    return Err(ChainError::Value { key: "mode", want: "manual, round-robin, keyswitch or cc" });
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
) -> Result<Option<T>, ChainError> {
    split
        .values
        .get(key)
        .map(|v| serde_json::from_value(v.clone()).map_err(|_| ChainError::Value { key, want }))
        .transpose()
}

fn check_crossovers(xover: &[f64], bands: usize) -> Result<(), ChainError> {
    if xover.len() + 1 != bands {
        return Err(ChainError::CrossoverCount { bands, count: xover.len() });
    }
    if let Some(bad) = xover.iter().find(|f| !f.is_finite() || **f <= 0.0) {
        return Err(ChainError::CrossoverValue(*bad));
    }
    match xover.windows(2).find(|pair| pair[1] <= pair[0]) {
        Some(pair) => Err(ChainError::CrossoverOrder { before: pair[0], next: pair[1] }),
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

impl SplitImpl {
    pub fn spec(self) -> KindSpec {
        match self {
            Self::Builtin(builtin) => builtin.spec(),
            Self::Declared(spec) => spec,
        }
    }
}

/// The verbs of the registry of split kinds. A trait, because the
/// registry type [`Kinds`] is of `paw-types` and the split kinds are of
/// the chain.
pub trait SplitRegistry: Sized {
    /// The registry with the built-in kinds, of owner `paw.chain`.
    fn builtin() -> Self;
    /// Add a kind of `owner` (an extension's). A built-in kind cannot
    /// change.
    fn define(&mut self, kind: SplitKind, spec: KindSpec, owner: Owner) -> Result<(), ChainError>;
    /// The kind `word` names, and the values of a new split of it with
    /// `branches` branches.
    fn new_split_kind(&self, word: &str, branches: usize) -> Result<(SplitKind, Map<String, Value>), ChainError>;
    /// How many branches a new split of `word` gets.
    fn first_branches(&self, word: &str) -> Result<usize, ChainError>;
    /// Check one split against its kind: the number of branches, and the
    /// values of a built-in kind. A kind that no one has defined passes.
    fn check(&self, split: &Split) -> Result<(), ChainError>;
    /// Every kind's name: the built-in kinds first, in their order.
    fn words(&self) -> Vec<String>;
}

/// The defined kind that `word` names, as a user typed it.
fn known(kinds: &SplitKinds, word: &str) -> Result<(SplitKind, SplitImpl), ChainError> {
    let unknown = || ChainError::UnknownKind(word.to_owned());
    let kind: SplitKind = word.parse().map_err(|_| unknown())?;
    let found = *kinds.get(&kind).ok_or_else(unknown)?;
    Ok((kind, found))
}

impl SplitRegistry for SplitKinds {
    fn builtin() -> Self {
        let mut kinds = Self::default();
        for builtin in BuiltinSplit::ALL {
            kinds.put(builtin.kind(), SplitImpl::Builtin(builtin), PAW);
        }
        kinds
    }

    fn define(&mut self, kind: SplitKind, spec: KindSpec, owner: Owner) -> Result<(), ChainError> {
        if self.owner(&kind) == Some(&PAW) {
            return Err(ChainError::BuiltinKind(kind.to_string()));
        }
        if spec.min == 0 || spec.min > spec.max || spec.max > MAX_BRANCHES || !spec.branches().contains(&spec.first) {
            return Err(ChainError::KindBranches(kind.to_string()));
        }
        self.put(kind, SplitImpl::Declared(spec), owner);
        Ok(())
    }

    fn new_split_kind(&self, word: &str, branches: usize) -> Result<(SplitKind, Map<String, Value>), ChainError> {
        let (kind, found) = known(self, word)?;
        let values = match found {
            SplitImpl::Builtin(builtin) => builtin.first_values(branches),
            SplitImpl::Declared(_) => Map::new(),
        };
        Ok((kind, values))
    }

    fn first_branches(&self, word: &str) -> Result<usize, ChainError> {
        known(self, word).map(|(_, found)| found.spec().first)
    }

    fn check(&self, split: &Split) -> Result<(), ChainError> {
        let Some(found) = self.get(&split.kind) else { return Ok(()) };
        let spec = found.spec();
        let count = split.branches.len();
        if !spec.branches().contains(&count) {
            return Err(ChainError::Branches { kind: split.kind.clone(), range: spec.branches(), count });
        }
        match found {
            SplitImpl::Builtin(builtin) => builtin.check(split),
            SplitImpl::Declared(_) => Ok(()),
        }
    }

    fn words(&self) -> Vec<String> {
        let builtin = BuiltinSplit::ALL.iter().map(|b| b.word().to_owned());
        let added = self.iter().filter(|(_, found)| matches!(found, SplitImpl::Declared(_))).map(|(k, _)| k.to_string());
        builtin.chain(added).collect()
    }
}
