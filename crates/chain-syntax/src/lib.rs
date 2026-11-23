#![doc = include_str!("../README.md")]

mod assist;
mod check;
mod diagnostic;
mod format;
mod lex;
mod parse;
mod print;
mod schema;
mod tree;
mod value;

#[cfg(test)]
mod props;

pub use assist::{Completion, CompletionKind, Hover, complete, definition, hover};
pub use check::check;
pub use diagnostic::{Code, Diagnostic, Severity, Span};
pub use format::{format, format_with, normalize};
pub use parse::{Parsed, parse};
pub use print::print;
pub use schema::{Count, Kind, Param, ParamValue, SCHEMA_VERSION, Schema, SchemaError, SplitKind};
pub use tree::{
    Body, Branch, Check, Checks, Compare, Content, Document, Field, Header, Link, Mods, Modulator, Node, Spanned,
    Trivia, VERSION,
};
pub use value::{Dimension, Feel, Note, Number, Reference, Unit, Value};

/// Parses `text` and checks it against `schema`: the tree, and the
/// diagnostics of both, in the order of the text. The check runs only on a
/// text that parses with no error, so a parse error does not bring false
/// errors of the check with it.
pub fn check_text(text: &str, schema: &Schema) -> Parsed {
    let mut parsed = parse(text);
    if !parsed.has_errors() {
        parsed.diagnostics.extend(check(&parsed.document, schema));
    }
    parsed
}
