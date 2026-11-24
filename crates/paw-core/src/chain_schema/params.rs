//! The parameters of paw's built-in roles, splits and modulators, each
//! kind a typed struct. `schemars` gives the JSON Schema of each struct,
//! and [`chain_syntax::params_of_json_schema`] makes its parameters: the
//! schema of a built-in kind is never written by hand.

use chain_syntax::Param;
use schemars::{JsonSchema, SchemaGenerator, generate::SchemaSettings};
use serde::de::{IgnoredAny, MapAccess, Visitor};
use serde::{Deserialize, Deserializer, Serialize};

/// The parameters of `T`, in the order of its fields, with the defaults of
/// its `Default`.
pub(super) fn params_of<T: JsonSchema + Serialize + Default>() -> Vec<Param> {
    let mut generator = SchemaGenerator::new(SchemaSettings::draft2020_12().with(|s| s.inline_subschemas = true));
    let schema = generator.root_schema_for::<T>();
    // A JSON object does not keep the order of its keys; the text of the
    // struct does.
    let text = serde_json::to_string(&T::default()).unwrap_or_default();
    let Keys(keys) = serde_json::from_str(&text).unwrap_or_default();
    let keys: Vec<&str> = keys.iter().map(String::as_str).collect();
    // The schemas are paw's own structs: a bad one is a bug that the tests
    // of this module find.
    chain_syntax::params_of_json_schema(schema.as_value(), &keys).expect("the parameters of a built-in kind")
}

/// The keys of a JSON object, in the order of the text.
#[derive(Default)]
struct Keys(Vec<String>);

impl<'de> Deserialize<'de> for Keys {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct InOrder;
        impl<'de> Visitor<'de> for InOrder {
            type Value = Keys;
            fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
                f.write_str("an object")
            }
            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Keys, A::Error> {
                let mut keys = Vec::new();
                while let Some((key, IgnoredAny)) = map.next_entry::<String, IgnoredAny>()? {
                    keys.push(key);
                }
                Ok(Keys(keys))
            }
        }
        deserializer.deserialize_map(InOrder)
    }
}

/// The fader of a strip, a bus and the master.
#[derive(Default, Serialize, JsonSchema)]
#[serde(default)]
pub(super) struct Fader {
    #[schemars(range(min = -60, max = 12), extend("unit" = "dB"))]
    gain: f64,
    #[schemars(range(min = -1, max = 1))]
    pan: f64,
}

#[derive(Default, Serialize, JsonSchema)]
#[serde(default)]
pub(super) struct SendParams {
    #[schemars(range(min = -60, max = 12), extend("unit" = "dB"))]
    level: f64,
    pre: bool,
}

#[derive(Default, Serialize, JsonSchema)]
#[serde(default)]
pub(super) struct Vca {
    #[schemars(range(min = -60, max = 12), extend("unit" = "dB"))]
    gain: f64,
}

/// The parameters of each split.
#[derive(Serialize, JsonSchema)]
#[serde(default)]
pub(super) struct Split {
    #[schemars(range(min = 0, max = 100), extend("unit" = "%"))]
    mix: f64,
    #[schemars(range(min = -60, max = 24), extend("unit" = "dB"))]
    gain: f64,
}

impl Default for Split {
    fn default() -> Self {
        Self { mix: 100.0, gain: 0.0 }
    }
}

/// The parameters of each branch of a split, on its `|` line.
#[derive(Default, Serialize, JsonSchema)]
#[serde(default)]
pub(super) struct Branch {
    #[schemars(range(min = -60, max = 24), extend("unit" = "dB"))]
    gain: f64,
    #[schemars(range(min = -1, max = 1))]
    pan: f64,
    mute: bool,
    solo: bool,
}

/// The branch of a key or velocity split: the zone that it plays.
#[derive(Default, Serialize, JsonSchema)]
#[serde(default)]
pub(super) struct Zone {
    /// A range of keys or velocities, such as `C2-B3` or `1-64`.
    zone: Option<String>,
}

/// The selector's own parameters.
#[derive(Serialize, JsonSchema)]
#[serde(default)]
pub(super) struct Select {
    #[schemars(title = "Index", range(min = 1, max = 16))]
    index: u32,
    #[schemars(range(min = 0, max = 1000), extend("unit" = "ms"))]
    fade: f64,
}

impl Default for Select {
    fn default() -> Self {
        Self { index: 1, fade: 10.0 }
    }
}

#[derive(Default, Serialize, JsonSchema)]
#[serde(default)]
pub(super) struct Macro {
    #[schemars(range(min = 0, max = 100), extend("unit" = "%"))]
    value: f64,
}

#[derive(Serialize, JsonSchema)]
#[serde(default)]
pub(super) struct Lfo {
    #[schemars(range(min = 0.01, max = 50), extend("unit" = "Hz"))]
    rate: f64,
    /// A note value that the rate follows, such as `1/4`.
    #[schemars(title = "Sync", extend("format" = "note"))]
    sync: Option<String>,
    // A text and not an enum: the kernel has no LFO that reads the shape yet.
    #[schemars(title = "Shape", extend("enum" = ["sine", "triangle", "square", "saw", "random"]))]
    shape: String,
    #[schemars(range(min = 0, max = 100), extend("unit" = "%"))]
    phase: f64,
}

impl Default for Lfo {
    fn default() -> Self {
        Self { rate: 1.0, sync: None, shape: "sine".into(), phase: 0.0 }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The parameters of `T` as the schema of the chain language writes them.
    fn words<T: JsonSchema + Serialize + Default>() -> serde_json::Value {
        serde_json::to_value(params_of::<T>()).unwrap()
    }

    #[test]
    fn a_built_in_kind_has_the_parameters_of_its_struct_in_the_order_of_its_fields() {
        assert_eq!(
            words::<Branch>(),
            serde_json::json!([
                {"key": "gain", "type": "number", "minimum": -60.0, "maximum": 24.0, "default": 0.0, "unit": "dB"},
                {"key": "pan", "type": "number", "minimum": -1.0, "maximum": 1.0, "default": 0.0},
                {"key": "mute", "type": "boolean", "default": false},
                {"key": "solo", "type": "boolean", "default": false},
            ])
        );
        assert_eq!(
            words::<Lfo>(),
            serde_json::json!([
                {"key": "rate", "type": "number", "minimum": 0.01, "maximum": 50.0, "default": 1.0, "unit": "Hz"},
                {"key": "sync", "name": "Sync", "description": "A note value that the rate follows, such as `1/4`.", "type": "string", "format": "note"},
                {"key": "shape", "name": "Shape", "type": "string", "enum": ["sine", "triangle", "square", "saw", "random"], "default": "sine"},
                {"key": "phase", "type": "number", "minimum": 0.0, "maximum": 100.0, "default": 0.0, "unit": "%"},
            ])
        );
        assert_eq!(
            words::<Select>(),
            serde_json::json!([
                {"key": "index", "name": "Index", "type": "integer", "minimum": 1.0, "maximum": 16.0, "default": 1.0},
                {"key": "fade", "type": "number", "minimum": 0.0, "maximum": 1000.0, "default": 10.0, "unit": "ms"},
            ])
        );
        assert_eq!(
            words::<Zone>(),
            serde_json::json!([{"key": "zone", "description": "A range of keys or velocities, such as `C2-B3` or `1-64`.", "type": "string"}])
        );
    }
}
