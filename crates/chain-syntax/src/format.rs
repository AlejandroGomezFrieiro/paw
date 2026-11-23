//! The formatter: the canonical text of a chain. Without a schema it
//! changes only the layout. With a schema it also writes the fields in the
//! order of the schema and leaves out each field at its default. Neither
//! changes what the text means.

use crate::diagnostic::Diagnostic;
use crate::parse::parse;
use crate::print::print;
use crate::schema::{Param, ParamValue, Schema};
use crate::tree::{Body, Content, Document, Field, Node};
use crate::value::{Note, Number, Value};

/// The canonical text of `text`.
///
/// # Errors
///
/// The diagnostics of the parser, when the text has an error: the
/// formatter does not change a text that it cannot read.
pub fn format(text: &str) -> Result<String, Vec<Diagnostic>> {
    let parsed = parse(text);
    if parsed.has_errors() {
        return Err(parsed.diagnostics);
    }
    Ok(print(&parsed.document))
}

/// The canonical text of `text` under `schema`: [`format`], with the
/// fields in the order of the schema and no field at its default.
///
/// # Errors
///
/// As [`format`].
pub fn format_with(text: &str, schema: &Schema) -> Result<String, Vec<Diagnostic>> {
    let parsed = parse(text);
    if parsed.has_errors() {
        return Err(parsed.diagnostics);
    }
    let mut document = parsed.document;
    normalize(&mut document, schema);
    Ok(print(&document))
}

/// Puts the fields of each item of `document` whose kind the schema
/// knows in the order of the schema, and removes each field at its default.
/// A field that the schema does not name stays, after the others.
pub fn normalize(document: &mut Document, schema: &Schema) {
    body(&mut document.root, None, schema);
}

fn body(body: &mut Body, branch_params: Option<&[Param]>, schema: &Schema) {
    match &mut body.content {
        Content::Nodes(nodes) => self::nodes(nodes, schema),
        Content::Branches(branches) => {
            for branch in branches {
                if let Some(params) = branch_params {
                    fields(&mut branch.fields, params);
                }
                self::nodes(&mut branch.nodes, schema);
            }
        }
    }
    if let Some(mods) = &mut body.mods {
        for modulator in &mut mods.modulators {
            if let Some(kind) = schema.modulator(&modulator.kind) {
                fields(&mut modulator.fields, &kind.params);
            }
        }
    }
}

fn nodes(nodes: &mut [Node], schema: &Schema) {
    for node in nodes {
        let (params, branch_params) = match schema.split(&node.kind) {
            Some(split) => (Some(split.params.as_slice()), Some(split.branch_params.as_slice())),
            None => (schema.device(&node.kind).map(|device| device.params.as_slice()), None),
        };
        if let Some(params) = params {
            fields(&mut node.fields, params);
        }
        body(&mut node.body, branch_params, schema);
    }
}

fn fields(fields: &mut Vec<Field>, params: &[Param]) {
    let place = |field: &Field| params.iter().position(|param| param.key == field.key).unwrap_or(params.len());
    // A stable sort keeps the order of the fields that the schema does not name.
    fields.sort_by_key(place);
    fields.retain(|field| {
        params.iter().find(|param| param.key == field.key).and_then(default).is_none_or(|default| default != field.value)
    });
}

/// The default of a parameter, as a value of the language.
fn default(param: &Param) -> Option<Value> {
    match &param.value {
        ParamValue::Number { unit, default, .. } => {
            let value = (*default)?;
            Some(Value::Number(match unit {
                Some(unit) => Number::with(unit.to_base(value), unit.dimension()),
                None => Number::plain(value),
            }))
        }
        ParamValue::Switch { default } => Some(Value::Text(if (*default)? { "on" } else { "off" }.into())),
        ParamValue::Choice { default, .. } | ParamValue::Text { default } => default.clone().map(Value::Text),
        ParamValue::Note { default } => default.as_deref()?.parse::<Note>().ok().map(Value::Note),
        ParamValue::List { .. } | ParamValue::Source => None,
    }
}
