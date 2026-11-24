//! `paw.api`: the file formats of extensions and of other programs.
#![expect(clippy::cast_possible_truncation, reason = "debt: pay down")]
#![expect(clippy::cast_possible_wrap, reason = "debt: pay down")]
#![expect(clippy::cast_sign_loss, reason = "debt: pay down")]

use std::rc::Rc;

use mlua::{Lua, LuaSerdeExt, LuaString, Table, Value as LuaValue};
use serde_json::Value;

use super::{Shared, from_lua, to_lua};

/// Bytes as a Lua string, or nil and the reason they could not be made.
fn bytes_or_why(lua: &Lua, bytes: anyhow::Result<Vec<u8>>) -> mlua::Result<(LuaValue, LuaValue)> {
    Ok(match bytes {
        Ok(bytes) => (LuaValue::String(lua.create_string(&bytes)?), LuaValue::Nil),
        Err(err) => (LuaValue::Nil, LuaValue::String(lua.create_string(format!("{err:#}"))?)),
    })
}

#[expect(clippy::too_many_lines, reason = "one registration for each Lua function of the table, in a list")]
pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- JSON, for what extensions keep in files ---

        // JSON text of a value; `pretty` lays it out on lines, indented.
        // @return string
        fn json_encode(lua, _sh, (value, pretty) => (LuaValue, Option<bool>)) {
            let value: Value = from_lua(lua, value)?;
            let text = if pretty.unwrap_or(false) {
                serde_json::to_string_pretty(&value)
            } else {
                serde_json::to_string(&value)
            };
            text.map_err(|err| mlua::Error::runtime(format!("{err}")))
        }
        // Nil and the reason, when the text is not JSON.
        // @return any, string
        fn json_decode(lua, _sh, text => LuaString) {
            match serde_json::from_slice::<Value>(&text.as_bytes()) {
                Ok(value) => Ok((to_lua(lua, &value)?, LuaValue::Nil)),
                Err(err) => Ok((LuaValue::Nil, LuaValue::String(lua.create_string(format!("{err}"))?))),
            }
        }
        // --- XML and TOML, for the files of other programs ---

        // The root element of an XML text, or nil and what is wrong (with the
        // byte). An element is `{ name, attr, order, children, text }`:
        // `attr` maps each attribute to its text, `order` lists them as
        // written, `children` holds the child elements, `text` the text and
        // CDATA directly in it (nil when there is none). References are
        // read; an entity a DTD defines is kept as it is written. UTF-16
        // with a byte order mark is read too. `opts.spans` gives each element
        // `span = { from, open, close, to, lead, tail }`, the bytes it takes
        // in the text, so that `xml_encode` can write what is not changed
        // byte for byte. `opts.meta` is set as the metatable of each element.
        // @param opts? types.XmlDecodeOptions
        // @return types.XmlElement, string
        fn xml_decode(lua, _sh, (text, opts) => (LuaString, Option<Table>)) {
            let spans = opts.as_ref().and_then(|o| o.get::<Option<bool>>("spans").ok().flatten()).unwrap_or(false);
            let meta = opts.as_ref().and_then(|o| o.get::<Option<Table>>("meta").ok().flatten());
            Ok(match crate::xml::decode(lua, &text.as_bytes(), spans, meta)? {
                Ok(root) => (LuaValue::Table(root), LuaValue::Nil),
                Err(why) => (LuaValue::Nil, LuaValue::String(lua.create_string(why)?)),
            })
        }
        // The XML text of an element (as `xml_decode` gives them, or made
        // with the same fields). Attributes are written in `order`, then the
        // others by name; numbers as the shortest text that reads back the
        // same, or with at most `opts.digits` digits after the point.
        // `opts.indent` puts each element on a line, indented by it.
        // `opts.declaration` is written first (true: the usual one).
        // `opts.source` is the text the tree was read from with `spans`:
        // what did not change is written as it was, byte for byte, and the
        // text around the root element too.
        // @param root types.XmlElement
        // @param opts? types.XmlEncodeOptions
        // @return string
        fn xml_encode(_, _sh, (root, opts) => (Table, Option<Table>)) {
            let get = |k: &str| opts.as_ref().map_or(Ok(LuaValue::Nil), |o| o.get::<LuaValue>(k));
            let source = match get("source")? { LuaValue::String(s) => Some(s.as_bytes().to_vec()), _ => None };
            let enc = crate::xml::EncodeOpts {
                indent: match get("indent")? { LuaValue::String(s) => Some(s.to_string_lossy()), _ => None },
                digits: match get("digits")? { LuaValue::Integer(n) => Some(n as usize), LuaValue::Number(n) => Some(n as usize), _ => None },
                source,
            };
            let body = crate::xml::encode(&root, &enc)?;
            let mut out = String::new();
            match get("declaration")? {
                LuaValue::Boolean(true) => out.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"),
                LuaValue::String(s) => out.push_str(&s.to_string_lossy()),
                _ => {}
            }
            let span: Option<Table> = root.get("span")?;
            match (&enc.source, span) {
                (Some(src), Some(span)) if out.is_empty() => {
                    let (from, to): (usize, usize) = (span.get("from")?, span.get("to")?);
                    if from >= 1 && to <= src.len() {
                        out.push_str(&String::from_utf8_lossy(&src[..from - 1]));
                        out.push_str(&body);
                        out.push_str(&String::from_utf8_lossy(&src[to..]));
                        return Ok(out);
                    }
                    out.push_str(&body);
                }
                _ => {
                    out.push_str(&body);
                    if enc.indent.is_some() {
                        out.push('\n');
                    }
                }
            }
            Ok(out)
        }
        // The table of a TOML text, or nil and what is wrong (`line 4: ...`).
        // Each table keeps the order of its keys in its metatable,
        // `getmetatable(t).__keys`. A date or a time is its text.
        // @return any, string
        fn toml_decode(lua, _sh, text => String) {
            Ok(match crate::toml_api::decode(lua, &text)? {
                Ok(v) => (v, LuaValue::Nil),
                Err(why) => (LuaValue::Nil, LuaValue::String(lua.create_string(why)?)),
            })
        }
        // The TOML text of a table; with `inline`, of any value on one line
        // (`{ a = 1, b = "x" }`). The keys of a table come in the order of
        // its metatable's `__keys`, then the others by name. A list of
        // tables is an array of tables.
        // @return string
        fn toml_encode(_, _sh, (value, inline) => (LuaValue, Option<bool>)) {
            crate::toml_api::encode(&value, inline.unwrap_or(false))
        }
        // Mark a table (a new one without `t`) as a JSON array, so that
        // `json_encode` writes it as `[]` when it is empty. Returns it.
        // @type function<T>(t?: {T}): {T}
        fn json_array(lua, _sh, t => Option<Table>) {
            let t = match t { Some(t) => t, None => lua.create_table()? };
            t.set_metatable(Some(lua.array_metatable()))?;
            Ok(t)
        }
        // The JSON Schema of the data of `paw.api` that has one, as JSON
        // text with indents: its definitions by the name of their Teal record
        // (`types.Clip`), from the Rust types that read and write the data.
        // @return string
        fn api_schema(_, _sh, () => ()) {
            serde_json::to_string_pretty(&crate::api_schema::definitions()).map_err(mlua::Error::external)
        }
        // --- bytes, for the file formats extensions read and write ---

        // Base64 of bytes. `opts.url` uses the URL alphabet (`-_`), and
        // `opts.pad = false` leaves out the `=` at the end.
        // @param opts? types.Base64Options
        // @return string
        fn base64_encode(_, _sh, (data, opts) => (LuaString, Option<Table>)) {
            let url = opts.as_ref().and_then(|o| o.get::<Option<bool>>("url").ok().flatten()).unwrap_or(false);
            let pad = opts.as_ref().and_then(|o| o.get::<Option<bool>>("pad").ok().flatten()).unwrap_or(true);
            Ok(crate::codec::base64_encode(&data.as_bytes(), url, pad))
        }
        // The bytes of base64 text, either alphabet, with or without its
        // padding; spaces and line ends are left out. Nil and the reason
        // when it is not base64.
        // @return string, string
        fn base64_decode(lua, _sh, text => LuaString) {
            bytes_or_why(lua, crate::codec::base64_decode(&text.as_bytes()))
        }
        // Compress `data` with deflate, as `format` says: "raw", "zlib" or "gzip".
        // @return string, string
        fn deflate(lua, _sh, (data, format) => (LuaString, String)) {
            bytes_or_why(lua, crate::codec::deflate(&data.as_bytes(), &format))
        }
        // The bytes `data` holds compressed as `format` says ("raw", "zlib"
        // or "gzip"), and the number of bytes of `data` the compressed
        // stream took (what follows is not part of it). Nil and the reason
        // when they are not compressed so.
        // @return string, integer | string
        fn inflate(lua, _sh, (data, format) => (LuaString, String)) {
            Ok(match crate::codec::inflate(&data.as_bytes(), &format) {
                Ok((bytes, used)) => (LuaValue::String(lua.create_string(&bytes)?), super::lua_integer(used as i64)),
                Err(err) => (LuaValue::Nil, LuaValue::String(lua.create_string(format!("{err:#}"))?)),
            })
        }
        // The CRC-32 of bytes, as zip and gzip use it.
        // @return integer
        fn crc32(_, _sh, data => LuaString) {
            Ok(crate::codec::crc32(&data.as_bytes()))
        }
        // --- tempo maps of other programs ---

        // A tempo map from points placed in seconds, as other programs keep
        // them: `tempos` is `{ { seconds, bpm, ramp } }`, `signatures` is
        // `{ { seconds, num, den } }`. Each point's beat follows from the
        // stretch before it, held, or ramped linearly in time. Returns
        // `{ tempos, signatures, beat, seconds }`: the points in beats, as
        // `tempo_set_points` takes them, and two functions that convert
        // with this map, `beat(seconds)` and `seconds(beat)`.
        // @param tempos {types.TempoSecondsPoint}
        // @param signatures? {types.SigSecondsPoint}
        // @return types.TempoMapInSeconds
        fn tempo_from_seconds(lua, _sh, (tempos, signatures) => (Table, Option<Table>)) {
            crate::tempo_api::from_seconds(lua, &tempos, signatures.as_ref())
        }
    }
    Ok(())
}
