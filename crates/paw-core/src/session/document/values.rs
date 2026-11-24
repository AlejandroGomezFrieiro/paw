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

/// One field of a patch (`ClipPatch`): left out, cleared with nil (the key
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
            Self::Clear => bail!("bad value for `{key}`: it is not nil"),
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
}

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
