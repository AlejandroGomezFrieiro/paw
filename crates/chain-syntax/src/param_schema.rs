//! The words of a parameter in a schema: a small part of JSON Schema
//! (`type`, `minimum`, `maximum`, `enum`, `default`, `format`, `items`,
//! `minItems`, `maxItems`), and the words that JSON Schema does not have:
//! `unit`, `ascending`, and `stream` and `main` for a parameter of the
//! type `source`.
//!
//! [`ParamSchema`] is the form on the wire. [`ParamValue`] is the form
//! that the check reads: a schema converts to it, and a schema whose words
//! do not agree (an `enum` on a number) does not load.

use serde::{Deserialize, Serialize};

use crate::schema::{Count, Param, ParamValue, PropValue, SchemaError};
use crate::value::Unit;

/// The type of a parameter: a JSON Schema type, or `source`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ParamType {
    Number,
    /// A number with no fraction.
    Integer,
    Boolean,
    /// A text, one of an `enum`, or a note value with `format: "note"`.
    String,
    /// A list of numbers, each as its `items` says.
    Array,
    /// Where a signal comes from: `@id`, `@in`, `@"path"` or a word.
    Source,
}

/// What a parameter takes, as JSON Schema words.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ParamSchema {
    #[serde(rename = "type")]
    pub kind: ParamType,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub minimum: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub maximum: Option<f64>,
    /// The choices of a text.
    #[serde(default, rename = "enum", skip_serializing_if = "Vec::is_empty")]
    pub choices: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub default: Option<PropValue>,
    /// `note` for a note value such as `1/4`. Other formats are only for
    /// people, as in JSON Schema.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub format: Option<String>,
    /// What each number of a list takes.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub items: Option<Box<ParamSchema>>,
    #[serde(default, rename = "minItems", skip_serializing_if = "Option::is_none")]
    pub min_items: Option<usize>,
    #[serde(default, rename = "maxItems", skip_serializing_if = "Option::is_none")]
    pub max_items: Option<usize>,
    /// Each number of a list is greater than the one before it.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub ascending: bool,
    /// The unit of a number, and of `minimum`, `maximum` and `default`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unit: Option<Unit>,
    /// The kind of stream that a source must give. None takes any.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stream: Option<String>,
    /// The source is the main input of its kind: a wire with no port
    /// feeds it.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub main: bool,
}

/// Why the words of a parameter do not make a parameter.
#[derive(Debug, PartialEq, thiserror::Error)]
#[non_exhaustive]
pub enum ParamError {
    #[error("a parameter of the type {kind} has no `{}`", .words.join("`, `"))]
    Misplaced { kind: String, words: Vec<&'static str> },
    #[error("the default `{shown}` is not {want}")]
    Default { shown: String, want: &'static str },
    #[error("the `items` of a list are numbers")]
    Items,
    #[error("{0}")]
    Words(String),
}

/// The format of a note value.
const NOTE: &str = "note";

impl ParamSchema {
    /// A schema of `kind` with no other word.
    pub fn of(kind: ParamType) -> Self {
        Self {
            kind,
            minimum: None,
            maximum: None,
            choices: Vec::new(),
            default: None,
            format: None,
            items: None,
            min_items: None,
            max_items: None,
            ascending: false,
            unit: None,
            stream: None,
            main: false,
        }
    }

    /// The words that this schema has and its type does not take.
    fn misplaced(&self) -> Vec<&'static str> {
        let number = matches!(self.kind, ParamType::Number | ParamType::Integer);
        let words = [
            ("minimum", self.minimum.is_some() && !number),
            ("maximum", self.maximum.is_some() && !number),
            ("unit", self.unit.is_some() && !number),
            ("enum", !self.choices.is_empty() && self.kind != ParamType::String),
            ("items", self.items.is_some() && self.kind != ParamType::Array),
            ("minItems", self.min_items.is_some() && self.kind != ParamType::Array),
            ("maxItems", self.max_items.is_some() && self.kind != ParamType::Array),
            ("ascending", self.ascending && self.kind != ParamType::Array),
            ("stream", self.stream.is_some() && self.kind != ParamType::Source),
            ("main", self.main && self.kind != ParamType::Source),
            ("default", self.default.is_some() && matches!(self.kind, ParamType::Array | ParamType::Source)),
        ];
        words.into_iter().filter(|(_, wrong)| *wrong).map(|(word, _)| word).collect()
    }
}

/// The default of a parameter, when it is of the type `want`.
fn default_of<T>(
    default: Option<PropValue>,
    want: &'static str,
    take: impl FnOnce(PropValue) -> Option<T>,
) -> Result<Option<T>, ParamError> {
    match default {
        None => Ok(None),
        Some(value) => {
            let shown = value.to_string();
            take(value).map(Some).ok_or(ParamError::Default { shown, want })
        }
    }
}

impl TryFrom<ParamSchema> for ParamValue {
    type Error = ParamError;

    fn try_from(schema: ParamSchema) -> Result<Self, ParamError> {
        let words = schema.misplaced();
        if !words.is_empty() {
            let kind = serde_json::to_value(schema.kind).unwrap_or_default().to_string();
            return Err(ParamError::Misplaced { kind, words });
        }
        let ParamSchema { kind, minimum, maximum, choices, default, format, items, min_items, max_items, ascending, unit, stream, main } = schema;
        Ok(match kind {
            ParamType::Number | ParamType::Integer => ParamValue::Number {
                unit,
                min: minimum,
                max: maximum,
                default: default_of(default, "a number", |v| match v {
                    PropValue::Number(n) => Some(n),
                    _ => None,
                })?,
                integer: kind == ParamType::Integer,
            },
            ParamType::Boolean => ParamValue::Switch {
                default: default_of(default, "`true` or `false`", |v| match v {
                    PropValue::Switch(on) => Some(on),
                    _ => None,
                })?,
            },
            ParamType::String => {
                let default = default_of(default, "a text", |v| match v {
                    PropValue::Text(text) => Some(text),
                    _ => None,
                })?;
                if !choices.is_empty() {
                    ParamValue::Choice { choices, default }
                } else if format.as_deref() == Some(NOTE) {
                    ParamValue::Note { default }
                } else {
                    ParamValue::Text { default }
                }
            }
            ParamType::Array => {
                let each = items.map_or_else(|| ParamSchema::of(ParamType::Number), |items| *items);
                if !matches!(each.kind, ParamType::Number | ParamType::Integer) {
                    return Err(ParamError::Items);
                }
                let count = (min_items.is_some() || max_items.is_some())
                    .then(|| Count { min: min_items.unwrap_or(0), max: max_items.unwrap_or(usize::MAX) });
                ParamValue::List { unit: each.unit, min: each.minimum, max: each.maximum, count, ascending }
            }
            ParamType::Source => ParamValue::Source { stream, main },
        })
    }
}

impl From<ParamValue> for ParamSchema {
    fn from(value: ParamValue) -> Self {
        match value {
            ParamValue::Number { unit, min, max, default, integer } => Self {
                minimum: min,
                maximum: max,
                default: default.map(PropValue::Number),
                unit,
                ..Self::of(if integer { ParamType::Integer } else { ParamType::Number })
            },
            ParamValue::Switch { default } => Self { default: default.map(PropValue::Switch), ..Self::of(ParamType::Boolean) },
            ParamValue::Choice { choices, default } => {
                Self { choices, default: default.map(PropValue::Text), ..Self::of(ParamType::String) }
            }
            ParamValue::Text { default } => Self { default: default.map(PropValue::Text), ..Self::of(ParamType::String) },
            ParamValue::Note { default } => Self {
                default: default.map(PropValue::Text),
                format: Some(NOTE.into()),
                ..Self::of(ParamType::String)
            },
            ParamValue::List { unit, min, max, count, ascending } => Self {
                items: Some(Box::new(Self { minimum: min, maximum: max, unit, ..Self::of(ParamType::Number) })),
                min_items: count.map(|count| count.min),
                max_items: count.map(|count| count.max),
                ascending,
                ..Self::of(ParamType::Array)
            },
            ParamValue::Source { stream, main } => Self { stream, main, ..Self::of(ParamType::Source) },
        }
    }
}

/// The parameters of the JSON Schema of an object, in the order of `keys`:
/// a host makes the schema of a kind from a typed struct (with `schemars`,
/// say), and gives the order of its fields, which a JSON object does not
/// keep. Each property gives its `title` as the name, its `description`,
/// and its type words. A property that is a `$ref` or that `keys` does not
/// name is left out. The `type` of an optional field (`["number",
/// "null"]`) is its first type that is not `null`.
///
/// # Errors
///
/// [`SchemaError::Param`] for a property whose words do not make a
/// parameter.
pub fn params_of_json_schema(schema: &serde_json::Value, keys: &[&str]) -> Result<Vec<Param>, SchemaError> {
    let Some(properties) = schema.get("properties").and_then(serde_json::Value::as_object) else {
        return Ok(Vec::new());
    };
    keys.iter()
        .filter_map(|key| properties.get(*key).map(|property| (*key, property)))
        .map(|(key, property)| {
            let mut words = property.clone();
            let text = |word: &str| property.get(word).and_then(serde_json::Value::as_str).unwrap_or_default().to_owned();
            if let Some(list) = words.get("type").and_then(serde_json::Value::as_array) {
                let first = list.iter().find(|kind| kind.as_str() != Some("null")).cloned();
                words["type"] = first.unwrap_or_default();
            }
            // A null default is no default.
            if words.get("default").is_some_and(serde_json::Value::is_null)
                && let Some(map) = words.as_object_mut()
            {
                map.remove("default");
            }
            let param = |source| SchemaError::Param { key: key.to_owned(), source };
            let schema: ParamSchema =
                serde_json::from_value(words).map_err(|error| param(ParamError::Words(error.to_string())))?;
            let value = ParamValue::try_from(schema).map_err(param)?;
            Ok(Param { key: key.to_owned(), name: text("title"), label: String::new(), description: text("description"), value })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn round_trip(value: ParamValue) {
        let schema = ParamSchema::from(value.clone());
        let json = serde_json::to_string(&schema).unwrap();
        let read: ParamSchema = serde_json::from_str(&json).unwrap();
        assert_eq!(ParamValue::try_from(read).ok(), Some(value), "{json}");
    }

    #[test]
    fn each_type_of_parameter_round_trips_through_its_json_schema_words() {
        round_trip(ParamValue::Number { unit: Some(Unit::Decibel), min: Some(-60.0), max: Some(12.0), default: Some(0.0), integer: false });
        round_trip(ParamValue::Number { unit: None, min: Some(1.0), max: Some(16.0), default: Some(1.0), integer: true });
        round_trip(ParamValue::Switch { default: Some(true) });
        round_trip(ParamValue::Choice { choices: vec!["peak".into(), "rms".into()], default: Some("rms".into()) });
        round_trip(ParamValue::Text { default: None });
        round_trip(ParamValue::Note { default: Some("1/4".into()) });
        round_trip(ParamValue::List { unit: Some(Unit::Hertz), min: Some(20.0), max: Some(20000.0), count: Some(Count { min: 1, max: 5 }), ascending: true });
        round_trip(ParamValue::Source { stream: Some("audio".into()), main: true });
    }

    #[test]
    fn a_word_that_the_type_does_not_take_is_refused_by_name() {
        let schema: ParamSchema = serde_json::from_str(r#"{"type": "number", "enum": ["a"]}"#).unwrap();
        let error = ParamValue::try_from(schema).unwrap_err();
        assert_eq!(error.to_string(), "a parameter of the type \"number\" has no `enum`");
        let schema: ParamSchema = serde_json::from_str(r#"{"type": "boolean", "default": 3}"#).unwrap();
        let error = ParamValue::try_from(schema).unwrap_err();
        assert_eq!(error.to_string(), "the default `3` is not `true` or `false`");
    }

    #[test]
    fn the_json_schema_of_an_object_gives_its_parameters_in_the_order_of_its_fields() {
        let schema = serde_json::json!({
            "type": "object",
            "properties": {
                "gain": {"type": "number", "format": "double", "minimum": -60, "maximum": 12, "default": 0, "unit": "dB", "title": "Gain"},
                "sync": {"type": ["string", "null"], "format": "note", "default": null, "description": "A note value."},
                "shape": {"type": "string", "enum": ["sine", "saw"], "default": "sine"}
            }
        });
        let params = params_of_json_schema(&schema, &["shape", "gain", "sync"]).unwrap();
        let keys: Vec<&str> = params.iter().map(|param| param.key.as_str()).collect();
        assert_eq!(keys, ["shape", "gain", "sync"]);
        assert_eq!(params[1].name, "Gain");
        assert_eq!(params[1].value, ParamValue::Number { unit: Some(Unit::Decibel), min: Some(-60.0), max: Some(12.0), default: Some(0.0), integer: false });
        assert_eq!(params[2].value, ParamValue::Note { default: None });
        assert_eq!(params[2].description, "A note value.");
    }
}
