//! Checks of the values that a script gives to an edit: a field's new value
//! from JSON, whether it changes anything, numbers, notes, controller moves
//! and fades.

use anyhow::{Result, anyhow, bail};
use serde::de::DeserializeOwned;
use serde_json::{Map, Value};

use crate::model::{Control, Note};

/// Free-form data from a script. An empty Lua table arrives as an empty
/// list, and means an empty map here.
pub(crate) fn de_meta(key: &str, value: Value) -> Result<Map<String, Value>> {
    match value {
        Value::Array(list) if list.is_empty() => Ok(Map::new()),
        value => de(key, value),
    }
}

/// Whether `key` of a view already holds `value`: setting it would change
/// nothing, and makes no undo step. Numbers are compared as numbers.
pub(crate) fn holds(view: &Result<Value>, key: &str, value: &Value) -> bool {
    fn same(a: &Value, b: &Value) -> bool {
        match (a, b) {
            (Value::Number(a), Value::Number(b)) => a.as_f64() == b.as_f64(),
            (Value::Array(a), Value::Array(b)) => {
                a.len() == b.len() && a.iter().zip(b).all(|(a, b)| same(a, b))
            }
            (Value::Object(a), Value::Object(b)) => {
                a.len() == b.len() && a.iter().all(|(k, v)| b.get(k).is_some_and(|w| same(v, w)))
            }
            _ => a == b,
        }
    }
    view.as_ref()
        .is_ok_and(|view| view.get(key).is_some_and(|old| same(old, value)))
}

pub(crate) fn de<T: DeserializeOwned>(key: &str, value: Value) -> Result<T> {
    serde_json::from_value(value).map_err(|err| anyhow!("bad value for `{key}`: {err}"))
}

/// One field of a patch ([`patch!`]): left out, cleared with nil (the key
/// form `clip_set(id, key, nil)` gives `null`), or set to a value.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) enum Patch<T> {
    #[default]
    Keep,
    Clear,
    Set(T),
}

impl<T> Patch<T> {
    /// The new value of a field that has no empty state: nil is an error
    /// that names `key`.
    pub(crate) fn value(self, key: &str) -> Result<Option<T>> {
        match self {
            Self::Keep => Ok(None),
            Self::Set(value) => Ok(Some(value)),
            Self::Clear => bail!("`{key}` cannot be nil"),
        }
    }

    /// The change of a field that nil clears: `Some(None)` clears it.
    pub(crate) fn change(self) -> Option<Option<T>> {
        match self {
            Self::Keep => None,
            Self::Clear => Some(None),
            Self::Set(value) => Some(Some(value)),
        }
    }

    /// The change of a field that nil sets to its default.
    pub(crate) fn or_default(self) -> Option<T>
    where
        T: Default,
    {
        self.change().map(Option::unwrap_or_default)
    }
}

/// A patch of `paw.api` (`clip_set`, `part_set` ...): what the setter says
/// of a key that the patch does not have.
pub(crate) trait Settable: DeserializeOwned {
    /// The start of the error for an unknown key, as "parts have no
    /// settable field `x`" has it.
    const NO_FIELD: &'static str;
}

/// One change of a patch ([`patch!`]).
pub(crate) trait Change {
    /// The key of the change, as Lua names the field.
    fn key(&self) -> &'static str;
}

/// One table for each patch of `paw.api`: each row gives the key of a
/// field as Lua names it, the field, its type, its change and what nil
/// does. The macro makes the patch (a struct of [`Patch`] fields that
/// serde reads, with its JSON Schema), the enum of its changes,
/// `changes()` (the changes in the order of the rows) and [`Change::key`].
///
/// What nil does to a field:
/// - `value`: nil is refused, as the field has no empty state.
/// - `clear`: nil clears the field. The change holds an `Option`.
/// - `default`: nil sets the default of the type (an empty map or list).
macro_rules! patch {
    (
        $(#[$meta:meta])*
        $vis:vis struct $patch:ident => $change:ident, $no_field:literal {
            $(
                $(#[$field_meta:meta])*
                $key:literal $field:ident: $ty:ty => $variant:ident $nil:ident,
            )*
        }
    ) => {
        #[derive(Debug, Default, serde::Deserialize, schemars::JsonSchema)]
        $(#[$meta])*
        #[serde(default, deny_unknown_fields)]
        $vis struct $patch {
            $(
                $(#[$field_meta])*
                #[serde(rename = $key)]
                $field: $crate::session::document::values::Patch<$ty>,
            )*
        }

        /// One change of a patch, typed: what one of its fields gives.
        #[derive(Clone, Debug, PartialEq)]
        $vis enum $change {
            $( $variant(patch!(@held $nil $ty)), )*
        }

        impl $patch {
            /// The changes of the patch, in the order of its rows.
            $vis fn changes(self) -> anyhow::Result<Vec<$change>> {
                let mut out = Vec::new();
                $(
                    if let Some(value) = patch!(@take $nil self.$field, $key) {
                        out.push($change::$variant(value));
                    }
                )*
                Ok(out)
            }
        }

        impl $crate::session::document::values::Change for $change {
            fn key(&self) -> &'static str {
                match self {
                    $( Self::$variant(_) => $key, )*
                }
            }
        }

        impl $crate::session::document::values::Settable for $patch {
            const NO_FIELD: &'static str = $no_field;
        }
    };
    (@held value $ty:ty) => { $ty };
    (@held clear $ty:ty) => { Option<$ty> };
    (@held default $ty:ty) => { $ty };
    (@take value $patch:expr, $key:literal) => { $patch.value($key)? };
    (@take clear $patch:expr, $key:literal) => { $patch.change() };
    (@take default $patch:expr, $key:literal) => { $patch.or_default() };
}
pub(crate) use patch;

/// A field that is given is read as an `Option`: `null` clears it. A field
/// that is not given is `Keep`, by `#[serde(default)]` on the patch.
impl<'de, T: serde::Deserialize<'de>> serde::Deserialize<'de> for Patch<T> {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> std::result::Result<Self, D::Error> {
        Ok(Option::<T>::deserialize(deserializer)?.map_or(Self::Clear, Self::Set))
    }
}

/// The schema of a field that is given: its value, or `null`.
impl<T: schemars::JsonSchema> schemars::JsonSchema for Patch<T> {
    fn inline_schema() -> bool {
        true
    }

    fn schema_name() -> std::borrow::Cow<'static, str> {
        Option::<T>::schema_name()
    }

    fn json_schema(generator: &mut schemars::SchemaGenerator) -> schemars::Schema {
        Option::<T>::json_schema(generator)
    }
}

/// What a script gives for a field that takes a word or a table: a port's
/// name or "none", a channel as a number, `false`, an empty table, or a
/// table of the field's own shape `T`. The setter of the field decides
/// what each means.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Given<T> {
    Word(String),
    Number(f64),
    Flag(bool),
    /// An empty table: a view's table with nothing in it reads back so.
    Empty,
    Table(T),
}

impl<'de, T: serde::Deserialize<'de>> serde::Deserialize<'de> for Given<T> {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> std::result::Result<Self, D::Error> {
        deserializer.deserialize_any(GivenVisitor(std::marker::PhantomData))
    }
}

struct GivenVisitor<T>(std::marker::PhantomData<T>);

impl<'de, T: serde::Deserialize<'de>> serde::de::Visitor<'de> for GivenVisitor<T> {
    type Value = Given<T>;

    fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("a word, a number or a table")
    }

    fn visit_str<E: serde::de::Error>(self, word: &str) -> std::result::Result<Given<T>, E> {
        Ok(Given::Word(word.to_string()))
    }

    fn visit_bool<E: serde::de::Error>(self, on: bool) -> std::result::Result<Given<T>, E> {
        Ok(Given::Flag(on))
    }

    fn visit_f64<E: serde::de::Error>(self, n: f64) -> std::result::Result<Given<T>, E> {
        Ok(Given::Number(n))
    }

    #[expect(clippy::cast_precision_loss, reason = "a channel or port number is small")]
    fn visit_i64<E: serde::de::Error>(self, n: i64) -> std::result::Result<Given<T>, E> {
        Ok(Given::Number(n as f64))
    }

    #[expect(clippy::cast_precision_loss, reason = "a channel or port number is small")]
    fn visit_u64<E: serde::de::Error>(self, n: u64) -> std::result::Result<Given<T>, E> {
        Ok(Given::Number(n as f64))
    }

    // An empty table can arrive as a list.
    fn visit_seq<A: serde::de::SeqAccess<'de>>(self, mut seq: A) -> std::result::Result<Given<T>, A::Error> {
        match seq.next_element::<serde::de::IgnoredAny>()? {
            None => Ok(Given::Empty),
            Some(_) => Err(serde::de::Error::custom("a table of named fields, not a list")),
        }
    }

    // A map with no key is empty whatever `T` makes of it: a `T` with a
    // field that must be given fails on it.
    fn visit_map<A: serde::de::MapAccess<'de>>(self, map: A) -> std::result::Result<Given<T>, A::Error> {
        let mut seen = false;
        let table = T::deserialize(serde::de::value::MapAccessDeserializer::new(Seen { map, seen: &mut seen }));
        match table {
            _ if !seen => Ok(Given::Empty),
            Ok(table) => Ok(Given::Table(table)),
            Err(error) => Err(error),
        }
    }
}

/// The table of a [`Given`] that takes none: a word or a number alone.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum NoTable {}

impl<'de> serde::Deserialize<'de> for NoTable {
    fn deserialize<D: serde::Deserializer<'de>>(_: D) -> std::result::Result<Self, D::Error> {
        Err(serde::de::Error::custom("a word or a number, not a table"))
    }
}

impl<T> Given<T> {
    /// A whole number from 0 up that a script gave, or none for nothing
    /// (nil or an empty table); `what` names it in the error.
    pub(crate) fn id(given: Option<Self>, what: &str) -> anyhow::Result<Option<u64>> {
        match given {
            None | Some(Given::Empty) => Ok(None),
            #[expect(clippy::cast_possible_truncation, clippy::cast_sign_loss, reason = "a whole number from 0 up")]
            Some(Given::Number(n)) if n >= 0.0 && n.fract() == 0.0 => Ok(Some(n as u64)),
            Some(_) => bail!("{what} is given by its id"),
        }
    }
}

/// A map that notes whether it gave a key.
struct Seen<'s, A> {
    map: A,
    seen: &'s mut bool,
}

impl<'de, A: serde::de::MapAccess<'de>> serde::de::MapAccess<'de> for Seen<'_, A> {
    type Error = A::Error;

    fn next_key_seed<K: serde::de::DeserializeSeed<'de>>(
        &mut self,
        seed: K,
    ) -> std::result::Result<Option<K::Value>, A::Error> {
        // A key that `T` refuses (an unknown field) is a key too.
        let key = self.map.next_key_seed(seed);
        *self.seen |= !matches!(key, Ok(None));
        key
    }

    fn next_value_seed<V: serde::de::DeserializeSeed<'de>>(&mut self, seed: V) -> std::result::Result<V::Value, A::Error> {
        self.map.next_value_seed(seed)
    }
}

/// One table for each view of `paw.api` (`part_get`, `project_get`):
/// the struct that serde writes, with its JSON Schema, and `field`, which
/// writes the one field that a key names without the others. A field's key
/// is its name.
macro_rules! view {
    (
        $(#[$meta:meta])*
        $vis:vis struct $view:ident<$life:lifetime> {
            $(
                $(#[$field_meta:meta])*
                $field:ident: $ty:ty,
            )*
        }
    ) => {
        #[derive(serde::Serialize, schemars::JsonSchema)]
        $(#[$meta])*
        $vis struct $view<$life> {
            $( $(#[$field_meta])* $field: $ty, )*
        }

        impl $view<'_> {
            /// The field that `key` names, written by `serializer`; nil
            /// for a key that the view does not have.
            $vis fn field<S: serde::Serializer>(&self, key: &str, serializer: S) -> std::result::Result<S::Ok, S::Error> {
                use serde::Serialize as _;
                match key {
                    $( stringify!($field) => self.$field.serialize(serializer), )*
                    _ => serializer.serialize_none(),
                }
            }
        }
    };
}
pub(crate) use view;

/// `value`, or an error naming `what` if it is NaN or infinite.
pub(crate) fn finite(what: &str, value: f64) -> Result<f64> {
    if value.is_finite() {
        Ok(value)
    } else {
        bail!("{what} must be a finite number, not {value}")
    }
}

pub(crate) fn sorted(mut notes: Vec<Note>) -> Vec<Note> {
    notes.sort_by(|a, b| a.start.total_cmp(&b.start).then(a.pitch.cmp(&b.pitch)));
    notes
}

pub(crate) fn check_controls(mut controls: Vec<Control>) -> Result<Vec<Control>> {
    if let Some((control, problem)) = controls
        .iter()
        .find_map(|c| c.problem().map(|problem| (c, problem)))
    {
        bail!("a controller move cannot be {control:?}: {problem}");
    }
    controls.sort_by(|a, b| a.start.total_cmp(&b.start));
    Ok(controls)
}

/// A fade is a number of beats from 0 up.
pub(crate) fn check_fade(beats: f64) -> Result<f64> {
    if !beats.is_finite() || beats < 0.0 {
        bail!("a fade is a number of beats from 0 up");
    }
    Ok(beats)
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::Given;

    #[derive(Debug, PartialEq, serde::Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Port {
        port: String,
    }

    /// What a script gives for a field of a word or a table reads as one of
    /// its kinds, and a table of a wrong shape is refused.
    #[test]
    fn a_word_or_a_table_reads_as_what_was_given() {
        let read = |value| serde_json::from_value::<Given<Port>>(value).map_err(|e| e.to_string());
        assert_eq!(read(json!("none")), Ok(Given::Word("none".into())));
        assert_eq!(read(json!(2)), Ok(Given::Number(2.0)));
        assert_eq!(read(json!(false)), Ok(Given::Flag(false)));
        assert_eq!(read(json!({})), Ok(Given::Empty), "an empty table, though `port` must be given");
        assert_eq!(read(json!([])), Ok(Given::Empty), "an empty table that came as a list");
        assert_eq!(read(json!({ "port": "a" })), Ok(Given::Table(Port { port: "a".into() })));
        assert!(read(json!({ "prot": "a" })).unwrap_err().contains("unknown field `prot`"));
        assert!(read(json!([1])).is_err());
    }
}
