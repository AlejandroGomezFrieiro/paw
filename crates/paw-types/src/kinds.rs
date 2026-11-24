//! The kinds core: families of kinds, the typed id of a kind, the
//! versioned record of a kind's data, and the registry with owners and a
//! stack of shadowed entries.
//!
//! A family is a type (`SplitFamily`, `ClipFamily`, ...). The core defines
//! the families, and extensions add kinds to them, never families. A kind
//! id names its family in its type, so a split kind cannot stand where a
//! modifier kind goes. Each family has one rule for a kind that no one has
//! defined (`Family::ABSENT`). Every family keeps the data of an unknown
//! kind as it was read: the rule changes what paw does, not what it saves.
//!
//! [`Kinds`] has the verbs of `paw.registry` (`runtime/lua/paw/registry.tl`):
//! an entry put over the entry of another owner keeps that entry below it,
//! and the entry below comes back when the one on top goes.
//!
//! The module uses no engine type, no OS call and no `mlua`. The registry
//! of one family gets its own verbs in the crate that knows the family's
//! entries, as a trait on [`Kinds`] (the split kinds of a chain, the
//! modifier kinds of a stack).

use std::collections::BTreeMap;
use std::fmt;
use std::marker::PhantomData;
use std::num::NonZeroU32;
use std::str::FromStr;
use std::sync::Arc;

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

mod sealed {
    pub trait Sealed {}
}

/// What paw does with a kind that no one has defined. The data of the kind
/// stays as it was read in each case.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Absent {
    /// The last kept result plays (a clip's sound, a lane's clips).
    Keep,
    /// The signal or the value goes through as if the item were not there.
    PassThrough,
    /// The item is listed, and paw does not make it.
    Refuse,
}

/// A family of kinds. Only this module defines families.
pub trait Family: sealed::Sealed + 'static {
    /// The name of the family in messages and in `paw.kinds`.
    const NAME: &'static str;
    /// What paw does with a kind of this family that no one has defined.
    const ABSENT: Absent;
}

macro_rules! families {
    ($($(#[$doc:meta])* $family:ident = $name:literal, $absent:ident;)*) => {
        $(
            $(#[$doc])*
            #[derive(Debug)]
            pub enum $family {}
            impl sealed::Sealed for $family {}
            impl Family for $family {
                const NAME: &'static str = $name;
                const ABSENT: Absent = Absent::$absent;
            }
        )*
    };
}

families! {
    /// The kinds of stream that a lane holds and a port takes (`midi`,
    /// `audio`, ...). No entries yet.
    StreamFamily = "stream", Keep;
    /// The kinds of clip: a lane keeps its clips, and their kept sound plays.
    ClipFamily = "clip", Keep;
    /// The kinds of part: a label and defaults.
    PartFamily = "part", Keep;
    /// The declared keys of `meta`.
    MetaFamily = "meta", Keep;
    /// The kinds of split of a chain: an absent kind plays its first branch
    /// in series.
    SplitFamily = "split", PassThrough;
    /// The kinds of modifier of a stack: an absent entry waits, and the
    /// notes play as they are.
    ModifierFamily = "modifier", PassThrough;
    /// The kinds of modulator: an absent one leaves the base value.
    ModulatorFamily = "modulator", PassThrough;
    /// The kinds of producer: an absent one keeps its last result.
    ProducerFamily = "producer", Keep;
    /// The kinds of template: an absent one is listed, and not made.
    TemplateFamily = "template", Refuse;
    /// The kinds of device: an absent one is bypassed, its values kept.
    DeviceFamily = "device", PassThrough;
}

/// Why a kind id or a stored record is refused. The text is what the user
/// reads.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum KindError {
    #[error(
        "`{0}` is not a name of a kind: say lowercase words joined by dots, as `band` or `drums.transient`, of at most 64 bytes"
    )]
    Name(String),
    #[error("a version of a kind is a whole number from 1, not {0}")]
    Version(i64),
    #[error("the data of the kind `{kind}` at version {version} cannot be read: {why}")]
    Data { kind: String, version: Version, why: String },
}

/// The name of a kind of the family `F`: lowercase words joined by dots
/// (`band`, `drums.transient`), at most 64 bytes. A word starts with a
/// letter and has letters, digits, `_` and `-`. The file and Lua hold the
/// text.
pub struct KindId<F: Family> {
    name: Arc<str>,
    family: PhantomData<fn() -> F>,
}

impl<F: Family> KindId<F> {
    /// The most bytes of a name.
    pub const MAX_LEN: usize = 64;

    pub fn as_str(&self) -> &str {
        &self.name
    }

    fn is_word(word: &str) -> bool {
        let mut chars = word.chars();
        chars.next().is_some_and(|c| c.is_ascii_lowercase())
            && chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
    }
}

impl<F: Family> FromStr for KindId<F> {
    type Err = KindError;

    fn from_str(text: &str) -> Result<Self, KindError> {
        if text.len() <= Self::MAX_LEN && text.split('.').all(Self::is_word) {
            Ok(Self { name: text.into(), family: PhantomData })
        } else {
            Err(KindError::Name(text.to_owned()))
        }
    }
}

// By hand: a derive would ask `F` for each trait, and a family is never a
// value.
impl<F: Family> Clone for KindId<F> {
    fn clone(&self) -> Self {
        Self { name: self.name.clone(), family: PhantomData }
    }
}

impl<F: Family> PartialEq for KindId<F> {
    fn eq(&self, other: &Self) -> bool {
        self.name == other.name
    }
}

impl<F: Family> Eq for KindId<F> {}

impl<F: Family> PartialOrd for KindId<F> {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl<F: Family> Ord for KindId<F> {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.name.cmp(&other.name)
    }
}

impl<F: Family> std::hash::Hash for KindId<F> {
    fn hash<H: std::hash::Hasher>(&self, state: &mut H) {
        self.name.hash(state);
    }
}

impl<F: Family> fmt::Debug for KindId<F> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}", F::NAME, self.name)
    }
}

impl<F: Family> fmt::Display for KindId<F> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.name)
    }
}

impl<F: Family> Serialize for KindId<F> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.name)
    }
}

impl<'de, F: Family> Deserialize<'de> for KindId<F> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let text = String::deserialize(deserializer)?;
        text.parse().map_err(serde::de::Error::custom)
    }
}

/// The version of a kind's data, from 1. A file that has no version holds
/// version 1, and paw does not write version 1.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(try_from = "i64", into = "u32")]
pub struct Version(NonZeroU32);

impl Version {
    pub const ONE: Self = Self(NonZeroU32::MIN);

    pub fn get(self) -> u32 {
        self.0.get()
    }

    /// True for version 1, which a file does not write.
    pub fn is_one(&self) -> bool {
        *self == Self::ONE
    }
}

impl Default for Version {
    fn default() -> Self {
        Self::ONE
    }
}

impl TryFrom<i64> for Version {
    type Error = KindError;

    fn try_from(n: i64) -> Result<Self, KindError> {
        u32::try_from(n).ok().and_then(NonZeroU32::new).map(Self).ok_or(KindError::Version(n))
    }
}

impl From<Version> for u32 {
    fn from(version: Version) -> u32 {
        version.get()
    }
}

impl fmt::Display for Version {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}

/// The data of one item of a kind of the family `F`, as a file holds it:
/// the kind, the version of its data, and the data. paw keeps the data of a
/// kind that no one has defined, and writes it again as it was read.
#[derive(Serialize, Deserialize)]
#[serde(bound = "")]
pub struct Stored<F: Family> {
    // In the order of their names, as the files have their keys.
    #[serde(default)]
    pub data: Arc<Value>,
    pub kind: KindId<F>,
    #[serde(default, skip_serializing_if = "Version::is_one")]
    pub version: Version,
}

impl<F: Family> Clone for Stored<F> {
    fn clone(&self) -> Self {
        Self { kind: self.kind.clone(), version: self.version, data: self.data.clone() }
    }
}

impl<F: Family> PartialEq for Stored<F> {
    fn eq(&self, other: &Self) -> bool {
        self.kind == other.kind && self.version == other.version && self.data == other.data
    }
}

impl<F: Family> fmt::Debug for Stored<F> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Stored").field("kind", &self.kind).field("version", &self.version).field("data", &self.data).finish()
    }
}

/// The data of a kind that Rust reads: its version now, and how to read
/// the data of an older version.
pub trait Versioned: Sized {
    /// The version that paw writes now.
    const VERSION: Version;
    /// Read the data of the version `from`, which is at most `VERSION`.
    fn migrate(data: &Value, from: Version) -> Result<Self, String>;
    /// The data to write, at `VERSION`.
    fn store(&self) -> Value;
}

/// A stored record after a read: ready to use, of a newer version than
/// this paw reads (kept and not changed), or of a kind that no one has
/// defined (kept, and the family's `ABSENT` rule applies).
#[derive(Debug)]
pub enum Loaded<F: Family, T> {
    Ready(T),
    Newer(Stored<F>),
    Absent(Stored<F>),
}

impl<F: Family, T: PartialEq> PartialEq for Loaded<F, T> {
    fn eq(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Ready(a), Self::Ready(b)) => a == b,
            (Self::Newer(a), Self::Newer(b)) | (Self::Absent(a), Self::Absent(b)) => a == b,
            _ => false,
        }
    }
}

impl<F: Family> Stored<F> {
    /// Read the record as `T`, a kind that Rust reads. `defined` says if the
    /// registry has an entry for the kind.
    pub fn load<T: Versioned>(self, defined: bool) -> Result<Loaded<F, T>, KindError> {
        if !defined {
            return Ok(Loaded::Absent(self));
        }
        if self.version > T::VERSION {
            return Ok(Loaded::Newer(self));
        }
        T::migrate(&self.data, self.version).map(Loaded::Ready).map_err(|why| KindError::Data {
            kind: self.kind.to_string(),
            version: self.version,
            why,
        })
    }

    /// The record of `value`, at the version that paw writes now.
    pub fn of<T: Versioned>(kind: KindId<F>, value: &T) -> Self {
        Self { kind, version: T::VERSION, data: Arc::new(value.store()) }
    }
}

/// Who put an entry in a registry.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Owner {
    /// The core, by its feature (`paw.chain`).
    Paw(&'static str),
    /// The user's configuration.
    User,
    /// An extension, by its name.
    Extension(Arc<str>),
}

impl fmt::Display for Owner {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Paw(feature) => f.write_str(feature),
            Self::User => f.write_str("the user"),
            Self::Extension(name) => f.write_str(name),
        }
    }
}

/// The kinds of the family `F`, each with the entry `S` that paw keeps for
/// it and the owner that put it. Each kind has a stack of entries: the last
/// put is on top, and `get` gives it.
pub struct Kinds<F: Family, S> {
    entries: BTreeMap<KindId<F>, Vec<(Owner, S)>>,
}

impl<F: Family, S> Default for Kinds<F, S> {
    fn default() -> Self {
        Self { entries: BTreeMap::new() }
    }
}

impl<F: Family, S: Clone> Clone for Kinds<F, S> {
    fn clone(&self) -> Self {
        Self { entries: self.entries.clone() }
    }
}

impl<F: Family, S: fmt::Debug> fmt::Debug for Kinds<F, S> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_map().entries(self.entries.iter()).finish()
    }
}

impl<F: Family, S> Kinds<F, S> {
    /// Put `value` at `kind`. A put by the owner of the entry on top
    /// replaces that entry. A put by another owner goes over it, and the
    /// entry below comes back when the new one goes.
    pub fn put(&mut self, kind: KindId<F>, value: S, owner: Owner) {
        let stack = self.entries.entry(kind).or_default();
        match stack.last_mut() {
            Some((top, slot)) if *top == owner => *slot = value,
            _ => stack.push((owner, value)),
        }
    }

    /// The entry on top at `kind`, or `None` when no one defined the kind.
    pub fn get(&self, kind: &KindId<F>) -> Option<&S> {
        self.entries.get(kind).and_then(|stack| stack.last()).map(|(_, value)| value)
    }

    /// The owner of the entry on top at `kind`.
    pub fn owner(&self, kind: &KindId<F>) -> Option<&Owner> {
        self.entries.get(kind).and_then(|stack| stack.last()).map(|(owner, _)| owner)
    }

    /// Remove the entry on top at `kind`, so that the entry below comes
    /// back. Gives the entry removed.
    pub fn remove(&mut self, kind: &KindId<F>) -> Option<S> {
        let stack = self.entries.get_mut(kind)?;
        let (_, value) = stack.pop()?;
        if stack.is_empty() {
            self.entries.remove(kind);
        }
        Some(value)
    }

    /// Remove every entry that `owner` put, on top or below another. Gives
    /// how many went.
    pub fn unload(&mut self, owner: &Owner) -> usize {
        let mut gone = 0;
        self.entries.retain(|_, stack| {
            let before = stack.len();
            stack.retain(|(by, _)| by != owner);
            gone += before - stack.len();
            !stack.is_empty()
        });
        gone
    }

    /// The kinds where `owner` put an entry, in the order of their names.
    pub fn owned_by<'a>(&'a self, owner: &'a Owner) -> impl Iterator<Item = &'a KindId<F>> + 'a {
        self.entries.iter().filter(move |(_, stack)| stack.iter().any(|(by, _)| by == owner)).map(|(kind, _)| kind)
    }

    /// Each kind with its entry on top, in the order of their names.
    pub fn iter(&self) -> impl Iterator<Item = (&KindId<F>, &S)> {
        self.entries.iter().filter_map(|(kind, stack)| stack.last().map(|(_, value)| (kind, value)))
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn kind(name: &str) -> KindId<SplitFamily> {
        name.parse().expect("a kind name")
    }

    #[test]
    fn an_unload_of_the_owner_on_top_gives_the_entry_below_back() {
        let mut kinds: Kinds<SplitFamily, &str> = Kinds::default();
        let ext = Owner::Extension("drums".into());
        kinds.put(kind("band"), "paw's", Owner::Paw("paw.chain"));
        kinds.put(kind("band"), "the extension's", ext.clone());
        kinds.put(kind("drums.transient"), "its own", ext.clone());
        assert_eq!(kinds.get(&kind("band")), Some(&"the extension's"));
        assert_eq!(kinds.owned_by(&ext).map(KindId::as_str).collect::<Vec<_>>(), ["band", "drums.transient"]);
        assert_eq!(kinds.unload(&ext), 2);
        assert_eq!(kinds.get(&kind("band")), Some(&"paw's"), "the entry below comes back");
        assert_eq!(kinds.get(&kind("drums.transient")), None);
    }

    #[test]
    fn a_put_by_the_owner_on_top_replaces_and_a_remove_takes_the_top() {
        let mut kinds: Kinds<SplitFamily, i32> = Kinds::default();
        kinds.put(kind("layer"), 1, Owner::Paw("paw.chain"));
        kinds.put(kind("layer"), 2, Owner::User);
        kinds.put(kind("layer"), 3, Owner::User);
        assert_eq!(kinds.owner(&kind("layer")), Some(&Owner::User));
        assert_eq!(kinds.remove(&kind("layer")), Some(3), "the user's second put replaced its first");
        assert_eq!(kinds.get(&kind("layer")), Some(&1));
        assert_eq!(kinds.remove(&kind("layer")), Some(1));
        assert_eq!(kinds.remove(&kind("layer")), None);
    }

    #[test]
    fn a_kind_id_is_dot_joined_lowercase_words() {
        for good in ["band", "drums.transient", "a-b_c.d2"] {
            assert_eq!(kind(good).as_str(), good);
        }
        let long = "a".repeat(65);
        for bad in ["", "Band", "drums.", ".x", "a..b", "2x", "a b", long.as_str()] {
            assert!(bad.parse::<KindId<SplitFamily>>().is_err(), "{bad:?} is refused");
        }
        let read: KindId<SplitFamily> = serde_json::from_value(json!("drums.transient")).unwrap();
        assert_eq!(serde_json::to_value(&read).unwrap(), json!("drums.transient"), "serde as its text");
        assert!(serde_json::from_value::<KindId<SplitFamily>>(json!("Not.a.kind")).is_err());
    }

    /// A record whose version 1 held `gain` and version 2 holds `db`.
    #[derive(Debug, PartialEq)]
    struct Gain {
        db: f64,
    }

    impl Versioned for Gain {
        const VERSION: Version = Version(NonZeroU32::new(2).unwrap());
        fn migrate(data: &Value, from: Version) -> Result<Self, String> {
            let field = if from.get() == 1 { "gain" } else { "db" };
            data[field].as_f64().map(|db| Self { db }).ok_or_else(|| format!("no `{field}`"))
        }
        fn store(&self) -> Value {
            json!({ "db": self.db })
        }
    }

    #[test]
    fn a_stored_record_loads_ready_newer_or_absent_and_keeps_its_bytes() {
        let read = |text: &str| serde_json::from_str::<Stored<ModifierFamily>>(text).unwrap();
        let old = read(r#"{"data":{"gain":-3.0},"kind":"gain"}"#);
        assert_eq!(old.version, Version::ONE, "no version is version 1");
        assert_eq!(old.clone().load::<Gain>(true), Ok(Loaded::Ready(Gain { db: -3.0 })));
        let newer = read(r#"{"data":{"x":1},"kind":"gain","version":3}"#);
        assert_eq!(newer.clone().load::<Gain>(true), Ok(Loaded::Newer(newer.clone())));
        assert_eq!(old.clone().load::<Gain>(false), Ok(Loaded::Absent(old.clone())));
        for (record, text) in [(&old, r#"{"data":{"gain":-3.0},"kind":"gain"}"#), (&newer, r#"{"data":{"x":1},"kind":"gain","version":3}"#)] {
            assert_eq!(serde_json::to_string(record).unwrap(), text, "written as it was read");
        }
        let written = Stored::<ModifierFamily>::of(kind_m("gain"), &Gain { db: 1.0 });
        assert_eq!(serde_json::to_value(&written).unwrap(), json!({ "data": { "db": 1.0 }, "kind": "gain", "version": 2 }));
        assert!(serde_json::from_str::<Stored<ModifierFamily>>(r#"{"kind":"gain","version":0}"#).is_err());
    }

    fn kind_m(name: &str) -> KindId<ModifierFamily> {
        name.parse().unwrap()
    }

    #[test]
    fn each_family_has_its_absent_rule() {
        assert_eq!(SplitFamily::ABSENT, Absent::PassThrough);
        assert_eq!(ProducerFamily::ABSENT, Absent::Keep);
        assert_eq!(TemplateFamily::ABSENT, Absent::Refuse);
        assert_eq!(StreamFamily::NAME, "stream");
    }
}
