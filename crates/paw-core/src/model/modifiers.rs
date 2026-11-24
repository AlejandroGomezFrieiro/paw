//! The modifier stack of a clip: a list of pure transforms that change
//! what the clip plays, and not its notes.
//!
//! A [`Modifier`] is one entry of a [`Stack`]: a kind, the version of its
//! data, on or off, an optional scope, and the kind's parameters as plain
//! JSON. The kinds are a family of the kinds core ([`ModifierFamily`]): the
//! built-in kinds (`transpose`, `velocity`) are entries of owner
//! `paw.modifiers`, and run in Rust by a `match` on [`Builtin`]. An
//! extension kind is [`ModImpl::Extern`]: [`evaluate`] stops at it and
//! gives an [`ExternJob`], which the kernel runs outside the sync. A kind
//! that no one defined waits: the stack passes its input through it, and
//! the file keeps the entry as it was read.
//!
//! [`ChainKey`] names the result after each entry: the key of the source,
//! then one step for each entry that is on. The sync keeps results by
//! these keys (`sync/stacks.rs`), so that copies with the same notes and
//! the same stack evaluate one time, and a change of entry 3 runs entries
//! 3 to the end only.
//!
//! This module uses no engine type, no OS call and no `mlua`.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use std::fmt;
use std::ops::Range;
use std::sync::Arc;

use serde::{Deserialize, Deserializer, Serialize};
use serde_json::{Value, json};

use super::kinds::{KindId, Kinds, ModifierFamily, Owner, Version};
use super::{Control, Note, Notes};

/// The name of a kind of modifier.
pub type ModKind = KindId<ModifierFamily>;

/// The registry of the kinds of modifier. Not part of the project.
pub type ModKinds = Kinds<ModifierFamily, ModImpl>;

/// The owner of the built-in kinds.
const PAW: Owner = Owner::Paw("paw.modifiers");

/// One modifier of a clip's stack: its kind, its values, whether it is off,
/// the beats that it changes, and the version of its values.
// The same struct holds a step of a media recipe.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
pub struct Modifier {
    // In the order of their names, as the files have their keys.
    /// `transpose`, `velocity`, or a kind of an extension.
    #[schemars(with = "String")]
    pub kind: ModKind,
    /// The entry is off and changes nothing. The file leaves `off` out for
    /// an entry that is on.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub off: bool,
    /// The values of the kind, as the file has them. The file leaves
    /// `params` out when there are none.
    #[serde(default, skip_serializing_if = "Value::is_null")]
    #[schemars(with = "Option<Value>", extend("x-teal" = "Meta"))]
    pub params: Arc<Value>,
    /// The beats of the clip that the entry changes. Left out, the entry
    /// changes all of the clip.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope: Option<Scope>,
    /// The version of the kind's values; left out for 1.
    #[serde(default, skip_serializing_if = "Version::is_one")]
    #[schemars(with = "Option<u32>")]
    pub version: Version,
}

impl Modifier {
    /// An entry that is on, of version 1, for all of the clip.
    pub fn new(kind: ModKind, params: Value) -> Self {
        Self { kind, off: false, params: Arc::new(params), scope: None, version: Version::ONE }
    }

    pub fn is_on(&self) -> bool {
        !self.off
    }
}

/// The beats of a clip, from `from` up to `to`, in which an entry changes
/// the notes and the controller moves that start there.
#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize, schemars::JsonSchema)]
#[schemars(rename = "ModifierScope")]
pub struct Scope {
    pub from: f64,
    pub to: f64,
}

impl Scope {
    fn holds(scope: Option<Scope>, at: f64) -> bool {
        scope.is_none_or(|s| at >= s.from && at < s.to)
    }
}

/// The modifiers of a clip, top to bottom: the first entry changes the
/// notes first.
#[derive(Clone, Debug, Default, PartialEq, Serialize, schemars::JsonSchema)]
#[serde(transparent)]
pub struct Stack(pub Vec<Modifier>);

impl Stack {
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// True when an entry is on: the clip plays a result, not its notes.
    pub fn changes(&self) -> bool {
        self.0.iter().any(Modifier::is_on)
    }
}

/// The fields of a clip's old `overrides`: a stack that a project saved
/// before stacks were made reads them as two entries.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct OldOverrides {
    #[serde(default)]
    transpose: i64,
    #[serde(default)]
    velocity: i64,
}

impl<'de> Deserialize<'de> for Stack {
    /// A list of entries, or the object of the old `overrides` field (a
    /// transpose and a velocity change), folded into two entries. The two
    /// commute, so their order changes no note. paw writes the list only.
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        use serde::de::Error;
        match Value::deserialize(deserializer)? {
            list @ Value::Array(_) => serde_json::from_value(list).map(Self).map_err(D::Error::custom),
            old @ Value::Object(_) => {
                let old: OldOverrides = serde_json::from_value(old).map_err(D::Error::custom)?;
                let mut entries = Vec::new();
                if old.transpose != 0 {
                    entries.push(Modifier::new(BuiltinKind::Transpose.kind(), json!({ "semitones": old.transpose })));
                }
                if old.velocity != 0 {
                    entries.push(Modifier::new(BuiltinKind::Velocity.kind(), json!({ "add": old.velocity })));
                }
                Ok(Self(entries))
            }
            other => Err(D::Error::custom(format!("a stack is a list of modifiers, not {other}"))),
        }
    }
}

/// The built-in kinds of modifier, as the registry holds them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BuiltinKind {
    Transpose,
    Velocity,
}

impl BuiltinKind {
    pub const ALL: [BuiltinKind; 2] = [Self::Transpose, Self::Velocity];

    pub fn word(self) -> &'static str {
        match self {
            Self::Transpose => "transpose",
            Self::Velocity => "velocity",
        }
    }

    /// The name of the one value of the kind.
    pub fn main(self) -> &'static str {
        match self {
            Self::Transpose => "semitones",
            Self::Velocity => "add",
        }
    }

    pub fn kind(self) -> ModKind {
        self.word().parse().expect("a built-in kind has a valid name")
    }
}

/// What the registry holds for each kind of modifier.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ModImpl {
    /// A kind of the core, run in Rust in the sync.
    Builtin(BuiltinKind),
    /// A kind of an extension, run by the kernel after the sync: the
    /// version of its data that it reads, and whether each output note
    /// comes from one input note alone.
    Extern { version: Version, local: bool },
}

/// The verbs of the registry of modifier kinds. A trait, because the
/// registry type [`Kinds`] is of `paw-types`.
pub trait ModRegistry: Sized {
    /// The registry with the built-in kinds, of owner `paw.modifiers`.
    fn builtin() -> Self;
}

impl ModRegistry for ModKinds {
    fn builtin() -> Self {
        let mut kinds = Self::default();
        for builtin in BuiltinKind::ALL {
            kinds.put(builtin.kind(), ModImpl::Builtin(builtin), PAW);
        }
        kinds
    }
}

/// The highest change of a transpose or a velocity: a note goes at most
/// this far, either way.
const MAX_CHANGE: i64 = 127;

/// A built-in modifier with its parameters read.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Builtin {
    /// Semitones up (down below 0). A note that this takes outside 0 to
    /// 127 does not play.
    Transpose { semitones: i8 },
    /// What is added to the velocity of each note, which then stays in 1
    /// to 127.
    Velocity { add: i8 },
}

/// The version of the data of the built-in kinds.
const BUILTIN_VERSION: Version = Version::ONE;

impl Builtin {
    /// Read the parameters of an entry of the kind `which`.
    pub fn read(which: BuiltinKind, params: &Value) -> Result<Self, ModError> {
        let word = which.word();
        let bad = |reason: String| ModError::Params { kind: word.to_owned(), reason };
        let empty = serde_json::Map::new();
        let fields = match params {
            Value::Null => &empty,
            Value::Object(fields) => fields,
            other => return Err(bad(format!("its values are a table, not {other}"))),
        };
        let main = which.main();
        if let Some(other) = fields.keys().find(|k| *k != main) {
            return Err(bad(format!("it has no value `{other}`: say `{main}`")));
        }
        // Lua gives each number as a float: a whole float is a whole number.
        let whole = |v: &Value| v.as_i64().or_else(|| v.as_f64().filter(|f| f.fract() == 0.0).map(|f| f as i64));
        let value = match fields.get(main) {
            None => 0,
            Some(v) => whole(v)
                .filter(|n| (-MAX_CHANGE..=MAX_CHANGE).contains(n))
                .and_then(|n| i8::try_from(n).ok())
                .ok_or_else(|| bad(format!("{main} is a whole number from -127 to 127, not {v}")))?,
        };
        Ok(match which {
            BuiltinKind::Transpose => Self::Transpose { semitones: value },
            BuiltinKind::Velocity => Self::Velocity { add: value },
        })
    }

    /// The values as a file writes them: whole numbers.
    pub fn params(self) -> Value {
        match self {
            Self::Transpose { semitones } => json!({ "semitones": semitones }),
            Self::Velocity { add } => json!({ "add": add }),
        }
    }

    /// The pitch that a note of `pitch` plays at, or `None` when it does
    /// not play.
    fn pitch(self, pitch: u8) -> Option<u8> {
        match self {
            Self::Transpose { semitones } => {
                u8::try_from(i16::from(pitch) + i16::from(semitones)).ok().filter(|p| *p <= 127)
            }
            Self::Velocity { .. } => Some(pitch),
        }
    }

    /// `note` as it plays, or `None` when it does not play.
    fn note(self, note: &Note) -> Option<Note> {
        let mut out = note.clone();
        out.pitch = self.pitch(note.pitch)?;
        if let Self::Velocity { add } = self {
            out.velocity = crate::model::Velocity((i16::from(note.velocity.0) + i16::from(add)).clamp(1, 127) as u8);
        }
        Some(out)
    }

    /// A controller move as it plays: a move of one key (a note's own bend
    /// or pressure) follows its note to the new key, and does not play when
    /// its note does not. The other moves play as they are.
    fn control(self, control: &Control) -> Option<Control> {
        match control.key {
            Some(key) => Some(Control { key: Some(self.pitch(key)?), ..control.clone() }),
            None => Some(control.clone()),
        }
    }

    /// The content after this modifier, in `scope`. Each note changes
    /// alone and keeps its start, so the notes stay in order and in runs.
    fn apply(self, input: &Midi, scope: Option<Scope>) -> Midi {
        let notes = input.notes.map_runs(|run| {
            run.iter()
                .filter_map(|n| if Scope::holds(scope, n.start) { self.note(n) } else { Some(n.clone()) })
                .collect()
        });
        let controls = input
            .controls
            .iter()
            .filter_map(|c| if Scope::holds(scope, c.start) { self.control(c) } else { Some(c.clone()) })
            .collect();
        Midi { notes, controls }
    }
}

/// The content of a MIDI clip as a stack takes it and gives it.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Midi {
    pub notes: Notes,
    pub controls: Arc<[Control]>,
}

impl Midi {
    /// The key of this content as the source of a chain: its notes by
    /// their stamp ([`Notes::stamp`]), its controller moves by value.
    pub fn source_key(&self) -> ChainKey {
        let mut hash = ChainKey::hasher();
        hash.update(b"midi");
        hash.update(&self.notes.stamp().to_le_bytes());
        for control in self.controls.iter() {
            let text = serde_json::to_vec(control).unwrap_or_default();
            hash.update(&(text.len() as u64).to_le_bytes());
            hash.update(&text);
        }
        ChainKey::of(hash)
    }
}

/// A name of the result after an entry of a stack: 128 bits of BLAKE3 with
/// a key of its own, stable from one run of paw to the next, so that a
/// result on disk can use it.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct ChainKey([u8; 16]);

impl fmt::Debug for ChainKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.iter().try_for_each(|b| write!(f, "{b:02x}"))
    }
}

impl ChainKey {
    /// The context of the keyed hash: a change of what goes into a key
    /// changes it.
    const CONTEXT: &'static str = "paw 2026-11-24 modifier chain key 1";

    fn hasher() -> blake3::Hasher {
        blake3::Hasher::new_derive_key(Self::CONTEXT)
    }

    fn of(hash: blake3::Hasher) -> Self {
        let mut key = [0; 16];
        key.copy_from_slice(&hash.finalize().as_bytes()[..16]);
        Self(key)
    }

    /// The key of a source of `bytes`.
    pub fn source(bytes: &[u8]) -> Self {
        let mut hash = Self::hasher();
        hash.update(bytes);
        Self::of(hash)
    }

    /// The key of the result after `entry`, from the key of its input: the
    /// kind, the version, the parameters as canonical text (their keys are
    /// in order), and the scope. Each part has its length first, so that no
    /// two entries give the same bytes.
    pub fn then(self, entry: &Modifier) -> Self {
        let mut hash = Self::hasher();
        hash.update(&self.0);
        let params = serde_json::to_vec(&*entry.params).unwrap_or_default();
        for part in [entry.kind.as_str().as_bytes(), &entry.version.get().to_le_bytes(), &params] {
            hash.update(&(part.len() as u64).to_le_bytes());
            hash.update(part);
        }
        if let Some(scope) = entry.scope {
            hash.update(&scope.from.to_bits().to_le_bytes());
            hash.update(&scope.to.to_bits().to_le_bytes());
        }
        Self::of(hash)
    }
}

/// Why an entry did not run: the stack passes its input through it.
#[derive(Clone, Debug, PartialEq)]
pub enum Skipped {
    /// No one defined the kind: it waits for its extension.
    Waits(ModKind),
    /// The entry is of a newer version than the kind reads.
    Newer(ModKind),
    /// The kind failed on it.
    Error(ModError),
}

impl fmt::Display for Skipped {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Waits(kind) => write!(f, "`{kind}` waits: no extension that is loaded defines it"),
            Self::Newer(kind) => write!(f, "`{kind}` is of a newer version than this paw reads"),
            Self::Error(error) => error.fmt(f),
        }
    }
}

/// An error of a modifier. The text is what the user reads.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum ModError {
    #[error("{kind}: {reason}")]
    Params { kind: String, reason: String },
    #[error("{kind}: over its time limit of {limit_ms} ms")]
    OverLimit { kind: String, limit_ms: u32 },
    #[error("{kind}: {message}")]
    Failed { kind: String, message: String },
}

/// An entry of an extension kind for the kernel to run: its input, its key
/// after it, and the entries after it, which evaluation goes on with.
#[derive(Clone, Debug)]
pub struct ExternJob {
    /// The key of the result after the entry.
    pub key: ChainKey,
    pub entry: Modifier,
    pub input: Midi,
    /// The entries after it, to evaluate with its result.
    pub rest: Range<usize>,
}

/// Where an evaluation stopped.
#[derive(Debug)]
pub enum Progress {
    /// The result after the last entry of the range, and its key.
    Done { key: ChainKey, result: Midi },
    /// An extension kind: the kernel runs the job, then evaluates `rest`.
    Needs(ExternJob),
}

#[cfg(test)]
thread_local! {
    /// How many entries ran on this thread: what the tests count.
    pub(crate) static APPLIED: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

/// Run the entries `range` of `stack` over `input`, whose key is `key`.
/// The built-in kinds run here. An entry that is off is not in the chain.
/// An entry that cannot run passes its input through and goes in
/// `skipped` with its place. At an extension kind, evaluation stops with
/// the job for the kernel.
pub fn evaluate(
    kinds: &ModKinds,
    stack: &[Modifier],
    range: Range<usize>,
    mut key: ChainKey,
    mut input: Midi,
    skipped: &mut Vec<(usize, Skipped)>,
) -> Progress {
    for at in range.clone() {
        let Some(entry) = stack.get(at).filter(|m| m.is_on()) else {
            continue;
        };
        let next = key.then(entry);
        match kinds.get(&entry.kind) {
            None => skipped.push((at, Skipped::Waits(entry.kind.clone()))),
            Some(ModImpl::Extern { version, .. }) if entry.version > *version => {
                skipped.push((at, Skipped::Newer(entry.kind.clone())));
            }
            Some(ModImpl::Extern { .. }) => {
                return Progress::Needs(ExternJob { key: next, entry: entry.clone(), input, rest: at + 1..range.end });
            }
            Some(ModImpl::Builtin(_)) if entry.version > BUILTIN_VERSION => {
                skipped.push((at, Skipped::Newer(entry.kind.clone())));
            }
            Some(ModImpl::Builtin(which)) => match Builtin::read(*which, &entry.params) {
                Ok(builtin) => {
                    #[cfg(test)]
                    APPLIED.with(|n| n.set(n.get() + 1));
                    input = builtin.apply(&input, entry.scope);
                }
                Err(error) => skipped.push((at, Skipped::Error(error))),
            },
        }
        // A skipped entry is in the chain too, with the same step as when
        // it runs. The key does not yet hold whether the entry can run: a
        // kind that is defined later gives another result with the same
        // key. A registry of kinds at run time (M3) must add this to the
        // key.
        key = next;
    }
    Progress::Done { key, result: input }
}

/// Check the entries of a stack that a user or an extension gives: each
/// built-in kind's parameters, which it gives back as a file writes them
/// (Lua gives `3.0` for `3`). A kind that no one defined passes: it waits.
pub fn check(kinds: &ModKinds, mut stack: Stack) -> Result<Stack, ModError> {
    for entry in &mut stack.0 {
        if let Some(Scope { from, to }) = entry.scope
            && !(from >= 0.0 && from < to && to.is_finite())
        {
            return Err(ModError::Params {
                kind: entry.kind.to_string(),
                reason: format!("its scope is from {from} to {to}: it starts at 0 or later, and ends after its start"),
            });
        }
        if let Some(ModImpl::Builtin(which)) = kinds.get(&entry.kind) {
            if entry.version > BUILTIN_VERSION {
                return Err(ModError::Params {
                    kind: entry.kind.to_string(),
                    reason: format!("this paw reads version 1, not {}", entry.version),
                });
            }
            entry.params = Arc::new(Builtin::read(*which, &entry.params)?.params());
        }
    }
    Ok(stack)
}

#[cfg(test)]
mod tests;
