//! The schema of a host, as JSON: the kinds of stream that its lanes and
//! wires carry, the kinds of device, split, modulator, producer and input
//! or output that it has, the parameters and ports of each, and the
//! parameters and ports of each role of a graph node. The language knows no
//! host: all that the check knows of the kinds comes from here.
//!
//! The format is versioned by its field `chain_schema`. The reference page
//! of the schema gives each field.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::tree::{GraphNode, Role};
use crate::value::Unit;

/// The version of the schema format that this crate reads and writes.
pub const SCHEMA_VERSION: u32 = 2;

/// The kinds of a host.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Schema {
    /// The version of the format: [`SCHEMA_VERSION`].
    pub chain_schema: u32,
    /// The host that wrote the schema, for people. The check does not read it.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub host: String,
    /// The kinds of stream that a port, a lane or a wire carries.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub streams: Vec<Stream>,
    /// The ports of a kind that gives none.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub default_ports: Vec<Port>,
    /// The parameters and ports of each role of a graph node that has no
    /// kind of its own: `strip`, `bus`, `master`, `send` and `vca`. The
    /// `kind` of each entry is the role word.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub nodes: Vec<Kind>,
    #[serde(default)]
    pub devices: Vec<Kind>,
    #[serde(default)]
    pub splits: Vec<SplitKind>,
    #[serde(default)]
    pub modulators: Vec<Kind>,
    /// The kinds of a `producer` node.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub producers: Vec<Kind>,
    /// The kinds of an `io` node: an input or an output of the host.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub io: Vec<Kind>,
    /// Prefixes of kinds that can be missing from the schema, such as the
    /// plugins of a format (`clap:`). A missing kind with one of them gives
    /// a warning, and its fields are not checked. A missing kind without
    /// one is an error.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub open_prefixes: Vec<String>,
}

/// A kind of stream: `audio`, `midi`, `curve`, or any word of the host.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Stream {
    /// The word that ports and the context name the stream by.
    pub stream: String,
    /// The name to show, for people.
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub name: String,
    /// What the time of the stream counts, for people and tools.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub time: Option<TimeBase>,
    /// A lane of this stream can record from an input.
    #[serde(default, skip_serializing_if = "is_false")]
    pub records: bool,
    /// The stream can feed a parameter of a node (`"Volume" -> #1.gain`).
    #[serde(default, skip_serializing_if = "is_false")]
    pub control: bool,
    /// The properties of the stream, such as `channels`, with their
    /// types and defaults. A port asks for values of these.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub props: Vec<Param>,
}

/// What the time of a stream counts.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum TimeBase {
    Samples,
    Beats,
    Seconds,
}

/// An input or an output of a kind.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Port {
    /// The word that a wire names the port by: `#3.side`.
    pub port: String,
    /// The kind of stream that the port carries.
    pub stream: String,
    /// The values of properties of the stream that the port needs (an
    /// input) or gives (an output). A property that an output does not
    /// give has the default of the stream.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub props: Props,
    /// The port that a wire with no port joins, and that inserts in series
    /// join. A kind has at most one main input and one main output of each
    /// stream.
    #[serde(default, skip_serializing_if = "is_false")]
    pub main: bool,
    /// An output. A port is an input when this is false.
    #[serde(default, skip_serializing_if = "is_false")]
    pub out: bool,
}

/// Values of the properties of a stream, by their keys.
pub type Props = BTreeMap<String, PropValue>;

/// The value of a property of a stream.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum PropValue {
    Switch(bool),
    Number(f64),
    Text(String),
}

impl std::fmt::Display for PropValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Switch(on) => f.write_str(if *on { "on" } else { "off" }),
            Self::Number(number) => write!(f, "{number}"),
            Self::Text(text) => f.write_str(text),
        }
    }
}

/// When a kind runs.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Tier {
    /// In the live graph, as the host plays.
    #[default]
    Live,
    /// In the host, out of the live graph, as the source changes.
    Kernel,
    /// In a job, whose result a lane keeps.
    Bake,
}

impl Tier {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Live => "live",
            Self::Kernel => "kernel",
            Self::Bake => "bake",
        }
    }

    fn is_live(&self) -> bool {
        *self == Self::Live
    }
}

/// A kind of device, modulator, producer or input or output, or a role of
/// a graph node.
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
    /// The inputs and outputs. None takes the `default_ports` of the schema.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ports: Option<Vec<Port>>,
    /// When the kind runs. Live by default.
    #[serde(default, skip_serializing_if = "Tier::is_live")]
    pub tier: Tier,
    /// A producer with one input and one output that turns one type of
    /// stream into another. A host can put one on a wire whose two ends
    /// differ.
    #[serde(default, skip_serializing_if = "is_false")]
    pub converts: bool,
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

/// One parameter of a kind, or one property of a stream.
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
    /// one), `@in` (the input of the chain), `@"path"` (a stream of
    /// another part), or a text that the host gives a meaning to.
    Source {
        /// The kind of stream that the source must give. None takes any.
        #[serde(default, skip_serializing_if = "Option::is_none")]
        stream: Option<String>,
    },
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
    #[error(
        "the schema is in version {0} of the format; this reader knows version {SCHEMA_VERSION}"
    )]
    Version(u32),
}

impl Schema {
    /// An empty schema of the current version.
    pub fn new(host: impl Into<String>) -> Self {
        Self {
            chain_schema: SCHEMA_VERSION,
            host: host.into(),
            ..Self::default()
        }
    }

    /// Reads a schema from its JSON.
    ///
    /// # Errors
    ///
    /// [`SchemaError::Json`] when the text is not a schema, and
    /// [`SchemaError::Version`] when it is a version that this crate does
    /// not read.
    pub fn from_json(text: &str) -> Result<Self, SchemaError> {
        // The version first, so that a schema of another version gets the
        // message of its version and not an error of a field.
        #[derive(Deserialize)]
        struct Versioned {
            chain_schema: u32,
        }
        let Versioned { chain_schema } = serde_json::from_str(text)?;
        if chain_schema != SCHEMA_VERSION {
            return Err(SchemaError::Version(chain_schema));
        }
        Ok(serde_json::from_str(text)?)
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
        self.modulators
            .iter()
            .find(|modulator| modulator.kind == kind)
    }

    pub fn producer(&self, kind: &str) -> Option<&Kind> {
        self.producers.iter().find(|producer| producer.kind == kind)
    }

    pub fn stream(&self, stream: &str) -> Option<&Stream> {
        self.streams.iter().find(|entry| entry.stream == stream)
    }

    /// The entry of a role in `nodes`, or the kind of a producer or an
    /// input or output.
    pub fn graph_kind(&self, role: Role, kind: Option<&str>) -> Option<&Kind> {
        let (list, word) = match role {
            Role::Producer => (&self.producers, kind?),
            Role::Io => (&self.io, kind?),
            role => (&self.nodes, role.as_str()),
        };
        list.iter().find(|entry| entry.kind == word)
    }

    /// The kind of a node line of version 2.
    pub fn kind_of(&self, node: &GraphNode) -> Option<&Kind> {
        self.graph_kind(node.role, node.kind.as_deref())
    }

    /// The kind of an insert that is not a split: a device, or a producer
    /// that runs live.
    pub fn insert(&self, kind: &str) -> Option<&Kind> {
        self.device(kind).or_else(|| self.producer(kind))
    }

    /// The ports of a kind: its own, or the default ports.
    pub fn ports<'a>(&'a self, kind: &'a Kind) -> &'a [Port] {
        kind.ports.as_deref().unwrap_or(&self.default_ports)
    }

    /// Whether a kind that the schema does not have may still be right.
    pub fn is_open(&self, kind: &str) -> bool {
        self.open_prefixes
            .iter()
            .any(|prefix| kind.starts_with(prefix.as_str()))
    }
}
