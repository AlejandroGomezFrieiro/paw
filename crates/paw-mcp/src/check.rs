//! Check a tool's arguments against its own schema before anything is done:
//! known names, required ones, JSON types and ranges, so that a model hears
//! of a typo, in words, instead of having it ignored.

use serde_json::{Map, Value, json};

use crate::format::items;
use crate::music::num;
use crate::tools::ToolError;

fn err<T>(msg: impl Into<String>) -> Result<T, ToolError> {
    Err(ToolError(msg.into()))
}

/// Check arguments against a tool's schema: known names, required ones, and
/// JSON types, so a model hears about a typo instead of having it ignored.
pub(crate) fn validate(schema: &Value, args: &Map<String, Value>) -> Result<(), ToolError> {
    check_object(schema, args, "")
}

fn check_object(schema: &Value, args: &Map<String, Value>, at: &str) -> Result<(), ToolError> {
    let props = schema["properties"]
        .as_object()
        .cloned()
        .unwrap_or_default();
    for key in args.keys() {
        if !props.contains_key(key) && schema["additionalProperties"] == json!(false) {
            let known: Vec<&String> = props.keys().collect();
            return err(format!(
                "unknown argument `{at}{key}`; the arguments are: {}",
                known
                    .iter()
                    .map(|k| k.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            ));
        }
    }
    for key in items(&schema["required"]) {
        let key = key.as_str().unwrap_or("");
        if args.get(key).is_none_or(Value::is_null) {
            return err(format!("missing required argument `{at}{key}`"));
        }
    }
    for (key, value) in args {
        if value.is_null() {
            continue;
        }
        let sub = props.get(key).or_else(|| {
            schema["additionalProperties"]
                .is_object()
                .then_some(&schema["additionalProperties"])
        });
        if let Some(sub) = sub {
            check_value(sub, value, &format!("{at}{key}"))?;
        }
    }
    Ok(())
}

fn type_ok(ty: &str, value: &Value) -> bool {
    match ty {
        "string" => value.is_string(),
        "number" => value.is_number(),
        "integer" => {
            value.is_i64() || value.is_u64() || value.as_f64().is_some_and(|f| f.fract() == 0.0)
        }
        "boolean" => value.is_boolean(),
        "array" => value.is_array(),
        "object" => value.is_object(),
        "null" => value.is_null(),
        _ => true,
    }
}

fn check_value(schema: &Value, value: &Value, at: &str) -> Result<(), ToolError> {
    if let Some(options) = schema["anyOf"].as_array() {
        if options.iter().any(|o| check_value(o, value, at).is_ok()) {
            return Ok(());
        }
        // Report against the option of the right type, if one is.
        if let Some(o) = options.iter().find(|o| match &o["type"] {
            Value::String(t) => type_ok(t, value),
            _ => false,
        }) {
            return check_value(o, value, at);
        }
        return err(format!("`{at}` has the wrong type"));
    }
    let types: Vec<&str> = match &schema["type"] {
        Value::String(t) => vec![t.as_str()],
        Value::Array(ts) => ts.iter().filter_map(Value::as_str).collect(),
        _ => vec![],
    };
    if !types.is_empty() && !types.iter().any(|t| type_ok(t, value)) {
        return err(format!(
            "`{at}` must be {}, not {}",
            types.join(" or "),
            match value {
                Value::String(s) => format!("the string \"{s}\""),
                other => other.to_string(),
            }
        ));
    }
    if let Some(allowed) = schema["enum"].as_array()
        && !allowed.contains(value)
    {
        return err(format!(
            "`{at}` must be one of {}",
            allowed
                .iter()
                .map(Value::to_string)
                .collect::<Vec<_>>()
                .join(", ")
        ));
    }
    if let Some(n) = value.as_f64()
        && (schema["minimum"].as_f64().is_some_and(|m| n < m)
            || schema["maximum"].as_f64().is_some_and(|m| n > m)
            || schema["exclusiveMinimum"].as_f64().is_some_and(|m| n <= m))
    {
        let mut range = Vec::new();
        if let Some(m) = schema["minimum"].as_f64() {
            range.push(format!("at least {}", num(m)));
        }
        if let Some(m) = schema["exclusiveMinimum"].as_f64() {
            range.push(format!("above {}", num(m)));
        }
        if let Some(m) = schema["maximum"].as_f64() {
            range.push(format!("at most {}", num(m)));
        }
        return err(format!("`{at}` must be {}, not {n}", range.join(" and ")));
    }
    match value {
        Value::Object(map)
            if schema["properties"].is_object() || schema["additionalProperties"].is_object() =>
        {
            check_object(schema, map, &format!("{at}."))
        }
        Value::Array(list) if schema["items"].is_object() => {
            for (i, item) in list.iter().enumerate() {
                check_value(&schema["items"], item, &format!("{at}[{i}]"))?;
            }
            Ok(())
        }
        _ => Ok(()),
    }
}

