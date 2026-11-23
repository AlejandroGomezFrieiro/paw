//! What the server knows of the host: its schema, from a file, from a
//! command or from the client, and an optional context.

use std::path::PathBuf;
use std::process::Command;

use chain_syntax::{Context, Schema};
use serde::Deserialize;
use serde_json::Value;

/// Where the schema of the host comes from.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SchemaSource {
    /// A JSON file.
    File(PathBuf),
    /// A program and its arguments, which print the schema as JSON (for
    /// paw: `paw chain schema`).
    Command(Vec<String>),
    /// The JSON text itself.
    Json(String),
}

impl SchemaSource {
    /// Reads the schema.
    ///
    /// # Errors
    ///
    /// A message for people when the file or the program cannot be read,
    /// or when its text is not a schema.
    pub fn load(&self) -> Result<Schema, String> {
        let text = match self {
            Self::File(path) => std::fs::read_to_string(path).map_err(|error| {
                format!("cannot read the schema file {}: {error}", path.display())
            })?,
            Self::Command(words) => run(words)?,
            Self::Json(text) => text.clone(),
        };
        Schema::from_json(&text).map_err(|error| format!("{}: {error}", self.describe()))
    }

    /// The source in a few words, for a message.
    fn describe(&self) -> String {
        match self {
            Self::File(path) => format!("the schema file {}", path.display()),
            Self::Command(words) => format!("the schema of `{}`", words.join(" ")),
            Self::Json(_) => "the schema that the client gave".into(),
        }
    }
}

/// What a program prints on its standard output.
fn run(words: &[String]) -> Result<String, String> {
    let shown = words.join(" ");
    let (program, arguments) = words.split_first().ok_or("the schema command is empty")?;
    let output = Command::new(program)
        .args(arguments)
        .output()
        .map_err(|error| format!("cannot run the schema command `{shown}`: {error}"))?;
    if !output.status.success() {
        let said = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "the schema command `{shown}` failed ({}): {}",
            output.status,
            said.trim()
        ));
    }
    String::from_utf8(output.stdout)
        .map_err(|_| format!("the schema command `{shown}` printed text that is not UTF-8"))
}

/// The `initializationOptions` that the server reads. Each is optional.
///
/// ```json
/// { "schema": { "chain_schema": 2, ... }, "schemaPath": "/path/schema.json",
///   "schemaCommand": ["paw", "chain", "schema"], "chainContext": { "chain_context": 2, ... } }
/// ```
#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InitOptions {
    /// The schema itself: a JSON object, or its text.
    #[serde(default)]
    pub schema: Option<Value>,
    #[serde(default)]
    pub schema_path: Option<PathBuf>,
    #[serde(default)]
    pub schema_command: Option<Vec<String>>,
    /// What the host knows outside the text. See [`Host::context`].
    #[serde(default)]
    pub chain_context: Option<Value>,
}

impl InitOptions {
    /// The options of an `initialize` request. Options that are not an
    /// object of this shape count as none, and give a message.
    pub fn read(value: Option<Value>) -> (Self, Vec<String>) {
        match value {
            None | Some(Value::Null) => (Self::default(), Vec::new()),
            Some(value) => match serde_json::from_value(value) {
                Ok(options) => (options, Vec::new()),
                Err(error) => (
                    Self::default(),
                    vec![format!("the initializationOptions are not read: {error}")],
                ),
            },
        }
    }

    /// The source of the schema that the client gives, if it gives one:
    /// `schema`, else `schemaPath`, else `schemaCommand`.
    pub fn schema_source(&self) -> Option<SchemaSource> {
        if let Some(schema) = &self.schema {
            let text = match schema {
                Value::String(text) => text.clone(),
                other => other.to_string(),
            };
            return Some(SchemaSource::Json(text));
        }
        if let Some(path) = &self.schema_path {
            return Some(SchemaSource::File(path.clone()));
        }
        self.schema_command.clone().map(SchemaSource::Command)
    }
}

/// What the server knows of the host.
#[derive(Clone, Debug, Default)]
pub struct Host {
    /// The kinds of the host. Without a schema, the server gives only the
    /// errors of the parser, formats the layout only, and completes and
    /// hovers nothing.
    pub schema: Option<Schema>,
    /// The lanes of the part and the outside ends that the host knows, as
    /// `chainContext` in the `initializationOptions` or the notification
    /// `chain/context`. None by default: the check then gives W302 for
    /// each lane and outside end.
    pub context: Option<Context>,
}

/// The context in a JSON value. Null and an empty object are no context.
///
/// # Errors
///
/// A message for people when the value is not a context.
pub fn read_context(value: Value) -> Result<Option<Context>, String> {
    match value {
        Value::Null => Ok(None),
        Value::Object(map) if map.is_empty() => Ok(None),
        value => Context::from_json(&value.to_string())
            .map(Some)
            .map_err(|error| format!("the chain context is not read: {error}")),
    }
}
