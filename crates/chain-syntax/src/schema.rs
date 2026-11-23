//! The schema of a host: the kinds of device, split and modulator that it
//! has, and the parameters of each, as JSON. The language knows no host:
//! all that the check knows of the kinds comes from here.
//!
//! The format is versioned by its field `chain_schema`. The reference page
//! of the schema gives each field.

use serde::{Deserialize, Serialize};

use crate::value::Unit;

/// The version of the schema format that this crate reads and writes.
pub const SCHEMA_VERSION: u32 = 1;

/// The kinds of a host.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Schema {
    /// The version of the format: [`SCHEMA_VERSION`].
    pub chain_schema: u32,
    /// The host that wrote the schema, for people. The check does not read it.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host: String,
    #[serde(default)]
    pub devices: Vec<Kind>,
    #[serde(default)]
    pub splits: Vec<SplitKind>,
    #[serde(default)]
    pub modulators: Vec<Kind>,
    /// Prefixes of kinds that can be missing from the schema, such as the
    /// plugins of a format (`clap:`). A missing kind with one of them gives
    /// a warning, and its fields are not checked. A missing kind without
    /// one is an error.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub open_prefixes: Vec<String>,
}

/// A kind of device or modulator.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Kind {
    pub kind: String,
    /// The name to show, for people.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    /// The parameters, in the order that the formatter writes them.
    #[serde(default)]
    pub params: Vec<Param>,
    /// The host knows the parameters only for each instance (some
    /// plugins): any key is allowed, and its value is not checked.
    #[serde(default, skip_serializing_if = "is_false")]
    pub open_params: bool,
}

/// A kind of split: a container that splits the signal into branches.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct SplitKind {
    pub kind: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    /// How many branches the split takes.
    pub branches: Count,
    /// The parameters of the split itself.
    #[serde(default)]
    pub params: Vec<Param>,
    /// The parameters of each branch, on its `|` line.
    #[serde(default)]
    pub branch_params: Vec<Param>,
}

/// A range of counts, both ends included.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Count {
    pub min: usize,
    pub max: usize,
}

impl Count {
    pub fn contains(&self, count: usize) -> bool {
        (self.min..=self.max).contains(&count)
    }
}

/// One parameter of a kind.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Param {
    /// The key that a field names: `threshold`, `b1.freq`, `Drive`.
    pub key: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    /// A unit that the host shows and the language does not have (`°`,
    /// `:1`), for people. Values of the parameter have no unit.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub label: String,
    #[serde(flatten)]
    pub value: ParamValue,
}

/// What a parameter takes, by its `type`.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum ParamValue {
    /// A number. `min`, `max` and `default` are in `unit`.
    Number {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        unit: Option<Unit>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        min: Option<f64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        max: Option<f64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        default: Option<f64>,
        /// Only whole numbers.
        #[serde(default, skip_serializing_if = "is_false")]
        integer: bool,
    },
    /// `on` or `off`.
    Switch {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        default: Option<bool>,
    },
    /// One of the named choices.
    Choice {
        choices: Vec<String>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        default: Option<String>,
    },
    /// Any text: a name that the host gives a meaning to.
    Text {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        default: Option<String>,
    },
    /// A note value, such as `1/4`.
    Note {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        default: Option<String>,
    },
    /// Numbers separated by commas, such as crossovers.
    List {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        unit: Option<Unit>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        min: Option<f64>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        max: Option<f64>,
        /// How many numbers the list holds.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        count: Option<Count>,
        /// Each number is greater than the one before it.
        #[serde(default, skip_serializing_if = "is_false")]
        ascending: bool,
    },
    /// Where a signal comes from: `@id` (a node of the chain before this
    /// one), `@in` (the input of the chain), or a text that the host gives
    /// a meaning to (another track, for example).
    Source,
}

fn is_false(value: &bool) -> bool {
    !value
}

/// Why a schema did not load.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum SchemaError {
    #[error("the schema is not valid JSON for a chain schema: {0}")]
    Json(#[from] serde_json::Error),
    #[error("the schema is in version {0} of the format; this reader knows version {SCHEMA_VERSION}")]
    Version(u32),
}

impl Schema {
    /// An empty schema of the current version.
    pub fn new(host: impl Into<String>) -> Self {
        Self { chain_schema: SCHEMA_VERSION, host: host.into(), ..Self::default() }
    }

    /// Reads a schema from its JSON.
    ///
    /// # Errors
    ///
    /// [`SchemaError::Json`] when the text is not a schema, and
    /// [`SchemaError::Version`] when it is a version that this crate does
    /// not read.
    pub fn from_json(text: &str) -> Result<Self, SchemaError> {
        let schema: Self = serde_json::from_str(text)?;
        if schema.chain_schema != SCHEMA_VERSION {
            return Err(SchemaError::Version(schema.chain_schema));
        }
        Ok(schema)
    }

    /// The schema as JSON, with an indent, as a host writes it to a file.
    pub fn to_json(&self) -> String {
        // A schema holds only strings, numbers, booleans and lists, so it
        // always serializes. A float that is not finite becomes null.
        serde_json::to_string_pretty(self).unwrap_or_default()
    }

    pub fn device(&self, kind: &str) -> Option<&Kind> {
        self.devices.iter().find(|device| device.kind == kind)
    }

    pub fn split(&self, kind: &str) -> Option<&SplitKind> {
        self.splits.iter().find(|split| split.kind == kind)
    }

    pub fn modulator(&self, kind: &str) -> Option<&Kind> {
        self.modulators.iter().find(|modulator| modulator.kind == kind)
    }

    /// Whether a kind that the schema does not have may still be right.
    pub fn is_open(&self, kind: &str) -> bool {
        self.open_prefixes.iter().any(|prefix| kind.starts_with(prefix.as_str()))
    }
}
