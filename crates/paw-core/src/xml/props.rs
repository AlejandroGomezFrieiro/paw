//! Property tests of the XML that extensions write: a tree written as the
//! DAWproject writer writes it (`extensions/interop/.../xmlio.lua`) and read
//! again.

use mlua::{Lua, Table};
use proptest::collection::{btree_map, vec};
use proptest::prelude::*;

use super::{EncodeOpts, decode, encode};
use crate::props::config;

/// The digits after the point that the DAWproject writer gives a number.
const DIGITS: usize = 12;

#[derive(Clone, Debug)]
enum Value {
    Text(String),
    Number(f64),
}

/// An element as the writer makes it: text in an element with no
/// children, as DAWproject and MusicXML have it.
#[derive(Clone, Debug)]
struct Element {
    name: String,
    /// In the order they are written.
    attrs: Vec<(String, Value)>,
    text: Option<String>,
    children: Vec<Element>,
}

fn name() -> impl Strategy<Value = String> {
    "[A-Za-z][A-Za-z0-9]{0,6}"
}

/// Text with the characters that XML must escape, and some that are not
/// ASCII. No carriage return: an XML reader can make a line end of it.
fn text() -> &'static str {
    "[ -~\n\tñさ€]{1,10}"
}

fn value() -> impl Strategy<Value = Value> {
    use prop::num::f64::{NEGATIVE, NORMAL, POSITIVE, SUBNORMAL, ZERO};
    prop_oneof![
        "[ -~\n\r\tñさ€]{0,10}".prop_map(Value::Text),
        (-1000i32..1000).prop_map(|n| Value::Number(n.into())),
        (POSITIVE | NEGATIVE | NORMAL | SUBNORMAL | ZERO).prop_map(Value::Number),
    ]
}

/// Attributes with names of their own, in any order.
fn attrs() -> impl Strategy<Value = Vec<(String, Value)>> {
    btree_map("[a-z][a-zA-Z0-9]{0,5}", value(), 0..4)
        .prop_map(|attrs| attrs.into_iter().collect::<Vec<_>>())
        .prop_shuffle()
}

fn element() -> impl Strategy<Value = Element> {
    let leaf = (name(), attrs(), prop::option::of(text()))
        .prop_map(|(name, attrs, text)| Element { name, attrs, text, children: Vec::new() });
    leaf.prop_recursive(3, 24, 4, |inner| {
        (name(), attrs(), vec(inner, 1..4))
            .prop_map(|(name, attrs, children)| Element { name, attrs, text: None, children })
    })
}

/// The Lua table of an element, as `paw.xml.element` makes it.
fn table(lua: &Lua, el: &Element) -> mlua::Result<Table> {
    let t = lua.create_table()?;
    t.set("name", el.name.as_str())?;
    let attr = lua.create_table()?;
    let order = lua.create_table()?;
    for (key, value) in &el.attrs {
        match value {
            Value::Text(text) => attr.set(key.as_str(), text.as_str())?,
            Value::Number(n) => attr.set(key.as_str(), *n)?,
        }
        order.push(key.as_str())?;
    }
    t.set("attr", attr)?;
    t.set("order", order)?;
    let children = lua.create_table()?;
    for child in &el.children {
        children.push(table(lua, child)?)?;
    }
    t.set("children", children)?;
    if let Some(text) = &el.text {
        t.set("text", text.as_str())?;
    }
    Ok(t)
}

/// That the element read is the element written. A number may differ by
/// the rounding to [`DIGITS`] digits after the point. The text of an
/// element with children is the line ends and indents of the layout.
fn check(want: &Element, got: &Table) -> mlua::Result<()> {
    assert_eq!(got.get::<String>("name")?, want.name);
    let attr: Table = got.get("attr")?;
    let order: Vec<String> = got.get::<Table>("order")?.sequence_values().collect::<mlua::Result<_>>()?;
    let keys: Vec<&str> = want.attrs.iter().map(|(key, _)| key.as_str()).collect();
    assert_eq!(order, keys, "the attributes of <{}> in order", want.name);
    for (key, value) in &want.attrs {
        let read: String = attr.get(key.as_str())?;
        match value {
            Value::Text(text) => assert_eq!(&read, text, "<{} {key}>", want.name),
            Value::Number(n) => {
                let back: f64 = read.parse().unwrap_or(f64::NAN);
                assert!((back - n).abs() <= 1e-12, "<{} {key}>: {n} is read as {read}", want.name);
            }
        }
    }
    let text: Option<String> = got.get("text")?;
    match (&want.text, want.children.is_empty()) {
        (Some(_), _) | (None, true) => assert_eq!(text, want.text, "the text of <{}>", want.name),
        (None, false) => assert!(
            text.as_deref().is_none_or(|t| t.trim().is_empty()),
            "<{}> has the text {text:?}",
            want.name
        ),
    }
    let children: Vec<Table> = got.get::<Table>("children")?.sequence_values().collect::<mlua::Result<_>>()?;
    assert_eq!(children.len(), want.children.len(), "the children of <{}>", want.name);
    for (want, got) in want.children.iter().zip(&children) {
        check(want, got)?;
    }
    Ok(())
}

proptest! {
    #![proptest_config(config())]

    /// A tree written as a DAWproject file (indented, numbers with 12
    /// digits) and read again gives its names, attributes, text and
    /// children.
    #[test]
    fn an_xml_tree_comes_back_the_same(root in element()) {
        let lua = Lua::new();
        let opts = EncodeOpts { indent: Some("  ".into()), digits: Some(DIGITS), source: None };
        let written = encode(&table(&lua, &root).expect("a Lua table"), &opts).expect("the tree is written");
        let text = format!("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n{written}\n");

        let read = decode(&lua, text.as_bytes(), false, None).expect("no Lua error");

        let read = read.unwrap_or_else(|why| panic!("{why} in\n{text}"));
        check(&root, &read).expect("the tree is read");
    }
}
