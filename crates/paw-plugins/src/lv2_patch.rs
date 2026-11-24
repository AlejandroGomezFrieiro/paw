//! LV2 properties: what a plugin holds besides its control ports, such as
//! the file of a model or an impulse response. A plugin lists them as
//! `patch:writable` and `patch:readable` in its description; the host sets
//! one with a `patch:Set` message on the plugin's control port, and the
//! plugin tells a new value back the same way on its notify port.
//!
//! This module builds and reads those messages. They are atoms: an object
//! (`atom:Object`) whose type is `patch:Set`, with the property's URID under
//! `patch:property` and the value under `patch:value`.

use crate::bytes::ne_u32;
use anyhow::{Result, bail};
use serde_json::{Value, json};

/// The URIDs the messages are made of.
#[derive(Clone, Copy, Debug)]
pub(crate) struct PatchUrids {
    pub object: u32,
    pub urid: u32,
    pub path: u32,
    pub string: u32,
    pub float: u32,
    pub double: u32,
    pub int: u32,
    pub long: u32,
    pub bool_: u32,
    pub set: u32,
    pub get: u32,
    pub property: u32,
    pub value: u32,
}

/// What kind of value a property takes, from its `rdfs:range`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) enum Kind {
    Path,
    String,
    Float,
    Double,
    Int,
    Long,
    Bool,
    /// A range this host does not write: the property is listed, not set.
    Other,
}

impl Kind {
    pub(crate) fn from_range(uri: &str) -> Self {
        match uri.strip_prefix("http://lv2plug.in/ns/ext/atom#") {
            Some("Path") => Kind::Path,
            Some("String") => Kind::String,
            Some("Float") => Kind::Float,
            Some("Double") => Kind::Double,
            Some("Int") => Kind::Int,
            Some("Long") => Kind::Long,
            Some("Bool") => Kind::Bool,
            _ => Kind::Other,
        }
    }

    pub(crate) fn name(self) -> &'static str {
        match self {
            Kind::Path => "path",
            Kind::String => "string",
            Kind::Float | Kind::Double => "number",
            Kind::Int | Kind::Long => "integer",
            Kind::Bool => "boolean",
            Kind::Other => "other",
        }
    }
}

/// A property a plugin lists.
#[derive(Clone, Debug)]
pub(crate) struct Property {
    pub uri: String,
    pub urid: u32,
    pub label: String,
    pub kind: Kind,
    /// The range as the plugin gives it, for a kind this host does not write.
    pub range: String,
    pub writable: bool,
    pub readable: bool,
    /// The file name extensions a path takes (`mod:fileTypes`), when the
    /// plugin says.
    pub file_types: Vec<String>,
}

impl Property {
    /// The short name scripts can use: the end of the URI after `#`, `/`
    /// or `:` (`model`, `sfzfile`).
    pub(crate) fn key(&self) -> &str {
        self.uri.rsplit(['#', '/', ':']).next().unwrap_or(&self.uri)
    }

    pub(crate) fn json(&self, value: Option<&Value>) -> Value {
        json!({
            "uri": self.uri,
            "key": self.key(),
            "label": self.label,
            "type": self.kind.name(),
            "range": self.range,
            "writable": self.writable,
            "readable": self.readable,
            "file_types": self.file_types,
            "value": value.cloned().unwrap_or(Value::Null),
        })
    }
}

/// Find a property by its URI, its short name, or its label (in capital or
/// small letters), in this order.
pub(crate) fn find<'a>(properties: &'a [Property], name: &str) -> Option<&'a Property> {
    properties
        .iter()
        .find(|p| p.uri == name)
        .or_else(|| properties.iter().find(|p| p.key() == name))
        .or_else(|| {
            properties
                .iter()
                .find(|p| p.label.eq_ignore_ascii_case(name))
        })
}

fn pad8(n: usize) -> usize {
    n.div_ceil(8) * 8
}

fn push_u32(out: &mut Vec<u8>, v: u32) {
    out.extend_from_slice(&v.to_ne_bytes());
}

/// Append a property of an object: key, context and the value atom, padded.
fn push_property(out: &mut Vec<u8>, key: u32, kind: u32, body: &[u8]) {
    push_u32(out, key);
    push_u32(out, 0);
    push_u32(out, body.len() as u32);
    push_u32(out, kind);
    out.extend_from_slice(body);
    out.resize(pad8(out.len()), 0);
}

/// An object atom of type `otype` holding `properties` (already encoded).
fn object(u: &PatchUrids, otype: u32, properties: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(16 + properties.len());
    push_u32(&mut out, 8 + properties.len() as u32);
    push_u32(&mut out, u.object);
    push_u32(&mut out, 0);
    push_u32(&mut out, otype);
    out.extend_from_slice(properties);
    out
}

/// The value atom's type and body for `value`, as `kind` takes it.
fn encode(u: &PatchUrids, kind: Kind, value: &Value) -> Result<(u32, Vec<u8>)> {
    let number = || {
        value
            .as_f64()
            .or_else(|| value.as_str().and_then(|s| s.trim().parse().ok()))
            .ok_or_else(|| anyhow::anyhow!("the value must be a number, not {value}"))
    };
    Ok(match kind {
        Kind::Path | Kind::String => {
            let Some(text) = value.as_str() else {
                bail!("the value must be a text, not {value}");
            };
            if text.contains('\0') {
                bail!("the value cannot hold a NUL character");
            }
            let mut body = text.as_bytes().to_vec();
            body.push(0);
            (if kind == Kind::Path { u.path } else { u.string }, body)
        }
        Kind::Float => (u.float, (number()? as f32).to_ne_bytes().to_vec()),
        Kind::Double => (u.double, number()?.to_ne_bytes().to_vec()),
        Kind::Int => (u.int, (number()?.round() as i32).to_ne_bytes().to_vec()),
        Kind::Long => (u.long, (number()?.round() as i64).to_ne_bytes().to_vec()),
        Kind::Bool => {
            let on = match value {
                Value::Bool(b) => *b,
                _ => number()? != 0.0,
            };
            (u.bool_, (on as i32).to_ne_bytes().to_vec())
        }
        Kind::Other => bail!("this host cannot write a value of that kind"),
    })
}

/// A `patch:Set` message that sets `property` to `value`.
pub(crate) fn set_message(u: &PatchUrids, property: &Property, value: &Value) -> Result<Vec<u8>> {
    let (kind, body) = encode(u, property.kind, value)?;
    let mut props = Vec::new();
    push_property(&mut props, u.property, u.urid, &property.urid.to_ne_bytes());
    push_property(&mut props, u.value, kind, &body);
    Ok(object(u, u.set, &props))
}

/// A `patch:Get` message, which asks the plugin to tell its properties.
pub(crate) fn get_message(u: &PatchUrids) -> Vec<u8> {
    object(u, u.get, &[])
}

/// Whether an atom (header and body) is a `patch:Set` object.
pub(crate) fn is_set(u: &PatchUrids, atom: &[u8]) -> bool {
    atom.len() >= 16 && ne_u32(atom, 4) == Some(u.object) && ne_u32(atom, 12) == Some(u.set)
}

/// The property and value of a `patch:Set` object: (URID of the property,
/// value). None for any other atom, or a value of a kind not read here.
pub(crate) fn parse_set(u: &PatchUrids, atom: &[u8]) -> Option<(u32, Value)> {
    if !is_set(u, atom) {
        return None;
    }
    let end = (8 + ne_u32(atom, 0)? as usize).min(atom.len());
    let (mut property, mut value) = (None, None);
    let mut at = 16;
    while at + 16 <= end {
        let key = ne_u32(atom, at)?;
        let size = ne_u32(atom, at + 8)? as usize;
        let kind = ne_u32(atom, at + 12)?;
        let body = atom.get(at + 16..at + 16 + size)?;
        if key == u.property && kind == u.urid && size >= 4 {
            property = ne_u32(body, 0);
        } else if key == u.value {
            value = decode(u, kind, body);
        }
        at += pad8(16 + size);
    }
    Some((property?, value?))
}

fn decode(u: &PatchUrids, kind: u32, body: &[u8]) -> Option<Value> {
    let text = || {
        let end = body.iter().position(|b| *b == 0).unwrap_or(body.len());
        Value::String(String::from_utf8_lossy(&body[..end]).into_owned())
    };
    let bytes4 = || body.get(..4).map(|b| <[u8; 4]>::try_from(b).unwrap());
    let bytes8 = || body.get(..8).map(|b| <[u8; 8]>::try_from(b).unwrap());
    Some(if kind == u.path || kind == u.string {
        text()
    } else if kind == u.float {
        json!(f32::from_ne_bytes(bytes4()?) as f64)
    } else if kind == u.double {
        json!(f64::from_ne_bytes(bytes8()?))
    } else if kind == u.int {
        json!(i32::from_ne_bytes(bytes4()?))
    } else if kind == u.long {
        json!(i64::from_ne_bytes(bytes8()?))
    } else if kind == u.bool_ {
        json!(i32::from_ne_bytes(bytes4()?) != 0)
    } else {
        return None;
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const U: PatchUrids = PatchUrids {
        object: 1,
        urid: 2,
        path: 3,
        string: 4,
        float: 5,
        double: 6,
        int: 7,
        long: 8,
        bool_: 9,
        set: 10,
        get: 11,
        property: 12,
        value: 13,
    };

    fn property(kind: Kind) -> Property {
        Property {
            uri: "http://example.org/plugin#model".into(),
            urid: 42,
            label: "Neural Model".into(),
            kind,
            range: String::new(),
            writable: true,
            readable: false,
            file_types: vec!["nam".into()],
        }
    }

    #[test]
    fn a_set_message_reads_back() {
        for (kind, value) in [
            (Kind::Path, json!("/models/amp.nam")),
            (Kind::String, json!("hello")),
            (Kind::Float, json!(0.5)),
            (Kind::Double, json!(-1.25)),
            (Kind::Int, json!(7)),
            (Kind::Long, json!(1_i64 << 40)),
            (Kind::Bool, json!(true)),
        ] {
            let message = set_message(&U, &property(kind), &value).unwrap();
            assert_eq!(message.len() % 8, 0, "{kind:?}: padded to 8 bytes");
            assert_eq!(ne_u32(&message, 0).unwrap() as usize + 8, message.len(), "{kind:?}: size");
            assert_eq!(parse_set(&U, &message), Some((42, value)), "{kind:?}");
        }
    }

    #[test]
    fn numbers_come_as_text_too_and_wrong_values_are_refused() {
        let message = set_message(&U, &property(Kind::Float), &json!("2.5")).unwrap();
        assert_eq!(parse_set(&U, &message), Some((42, json!(2.5))));
        assert!(set_message(&U, &property(Kind::Path), &json!(3)).is_err());
        assert!(set_message(&U, &property(Kind::Float), &json!("loud")).is_err());
        assert!(set_message(&U, &property(Kind::Other), &json!("x")).is_err());
    }

    #[test]
    fn other_atoms_are_not_read() {
        let get = get_message(&U);
        assert!(!is_set(&U, &get));
        assert_eq!(parse_set(&U, &get), None);
        assert_eq!(parse_set(&U, &[0; 4]), None);
        // A message cut short is not read past its end.
        let message = set_message(&U, &property(Kind::Path), &json!("/a/b.nam")).unwrap();
        assert_eq!(parse_set(&U, &message[..message.len() - 16]), None);
    }

    #[test]
    fn properties_are_found_by_uri_key_or_label() {
        let list = [property(Kind::Path)];
        assert!(find(&list, "http://example.org/plugin#model").is_some());
        assert!(find(&list, "model").is_some());
        assert!(find(&list, "neural model").is_some());
        assert!(find(&list, "gain").is_none());
        let mut sfizz = property(Kind::Path);
        sfizz.uri = "http://sfztools.github.io/sfizz:sfzfile".into();
        assert_eq!(sfizz.key(), "sfzfile");
    }
}
