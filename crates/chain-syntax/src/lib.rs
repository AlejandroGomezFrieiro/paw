#![doc = include_str!("../README.md")]

mod assist;
mod check;
mod context;
mod diagnostic;
mod format;
mod graph;
mod lex;
mod param_schema;
mod parse;
mod print;
mod schema;
mod tree;
mod value;

#[cfg(test)]
mod props;

pub use assist::{Completion, CompletionKind, Hover, complete, definition, hover};
pub use check::check;
pub use context::{CONTEXT_VERSION, Context, ContextError, Lane, Outside, OutsideEnd};
pub use diagnostic::{Code, Diagnostic, Severity, Span};
pub use format::{format, format_with, normalize};
pub use param_schema::{ParamError, ParamSchema, ParamType, params_of_json_schema};
pub use parse::{Parsed, parse};
pub use print::print;
pub use schema::{
    Count, Kind, Param, ParamValue, Port, PropValue, Props, SCHEMA_VERSION, Schema, SchemaError,
    SplitKind, Stream, Tier, TimeBase,
};
pub use tree::{
    Arrow, Body, Branch, Check, Checks, Compare, Content, Document, End, Field, GraphNode, Header,
    Item, Link, Mods, Modulator, Node, Role, Spanned, Trivia, VERSION, VERSION_1, Wire,
};
pub use value::{Dimension, Feel, Note, Number, Reference, Unit, Value};

/// Parses `text` and checks it against `schema` and the optional
/// `context` of the text: the tree, and the diagnostics of both, in the
/// order of the text. The check runs only on a text that parses with no
/// error, so a parse error does not bring false errors of the check with
/// it.
pub fn check_text(text: &str, schema: &Schema, context: Option<&Context>) -> Parsed {
    let mut parsed = parse(text);
    if !parsed.has_errors() {
        parsed
            .diagnostics
            .extend(check(&parsed.document, schema, context));
    }
    parsed
}
