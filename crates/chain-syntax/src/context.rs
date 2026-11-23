//! The context of one text, as JSON: what the host knows outside the text.
//! It gives the lanes of the part, with their streams, and the lanes and
//! nodes of other parts that an outside end `@"path"` can name. The schema
//! is the same for each text of a host. The context is not: a host writes
//! it for one part.
//!
//! The context is optional. With no context, each lane and each outside end
//! gives the warning W302, and its type is not checked.

use serde::{Deserialize, Serialize};

use crate::schema::Props;

/// The version of the context format that this crate reads and writes.
pub const CONTEXT_VERSION: u32 = 2;

/// What the host knows outside one text.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Context {
    /// The version of the format: [`CONTEXT_VERSION`].
    pub chain_context: u32,
    /// The lanes of the part, which a wire names as `"Name"`.
    #[serde(default)]
    pub lanes: Vec<Lane>,
    /// The lanes and nodes of other parts, which a wire or a source names
    /// as `@"path"`.
    #[serde(default)]
    pub outside: Vec<Outside>,
}

/// A lane: a row of time that keeps one stream.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct Lane {
    pub name: String,
    /// The kind of stream that the lane keeps.
    pub stream: String,
    /// The values of the properties of the stream, such as `channels`.
    #[serde(default, skip_serializing_if = "Props::is_empty")]
    pub props: Props,
}

/// A lane or a node of another part, by its path.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Outside {
    /// The path that the text writes after `@`: `Strings/Violin I/Notes`.
    pub path: String,
    #[serde(flatten)]
    pub end: OutsideEnd,
}

/// What an outside path names.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum OutsideEnd {
    /// A lane, with its stream.
    Lane {
        stream: String,
        #[serde(default, skip_serializing_if = "Props::is_empty")]
        props: Props,
    },
    /// A node: its role word (`bus`) and, for a producer or an input or
    /// output, its kind. Its ports come from the schema.
    Node {
        node: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        kind: Option<String>,
    },
}

/// Why a context did not load.
#[derive(Debug, thiserror::Error)]
#[non_exhaustive]
pub enum ContextError {
    #[error("the context is not valid JSON for a chain context: {0}")]
    Json(#[from] serde_json::Error),
    #[error(
        "the context is in version {0} of the format; this reader knows version {CONTEXT_VERSION}"
    )]
    Version(u32),
}

impl Context {
    /// An empty context of the current version.
    pub fn new() -> Self {
        Self {
            chain_context: CONTEXT_VERSION,
            ..Self::default()
        }
    }

    /// Reads a context from its JSON.
    ///
    /// # Errors
    ///
    /// [`ContextError::Json`] when the text is not a context, and
    /// [`ContextError::Version`] when it is a version that this crate does
    /// not read.
    pub fn from_json(text: &str) -> Result<Self, ContextError> {
        let context: Self = serde_json::from_str(text)?;
        if context.chain_context != CONTEXT_VERSION {
            return Err(ContextError::Version(context.chain_context));
        }
        Ok(context)
    }

    /// The context as JSON, with an indent.
    pub fn to_json(&self) -> String {
        // A context holds only strings, numbers, booleans and lists.
        serde_json::to_string_pretty(self).unwrap_or_default()
    }

    /// The lane of the part with this name.
    pub fn lane(&self, name: &str) -> Option<&Lane> {
        self.lanes.iter().find(|lane| lane.name == name)
    }

    /// The lane or node of another part at this path.
    pub fn outside(&self, path: &str) -> Option<&Outside> {
        self.outside.iter().find(|outside| outside.path == path)
    }
}
