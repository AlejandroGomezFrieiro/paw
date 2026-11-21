//! The door of a custom clip's data: what a kind's `serialize` gives,
//! checked to be plain data and made a JSON value.
//!
//! The core does not read the data, but it saves and loads it, so it takes
//! only what it can save cleanly: tables, strings, numbers and booleans
//! (a JSON null reads as nil). A function, userdata, cdata, a table that holds itself,
//! NaN or an infinite number, or a string that is not UTF-8 is refused with
//! where it is (`.frames[3]: a function is not data`), so that the kind's
//! code can say which clip and which field.

use std::ffi::c_void;
use std::fmt::Write as _;

use mlua::{Lua, LuaSerdeExt, LuaString, Table, Value as LuaValue};
use serde_json::{Map, Number, Value};

use super::from_lua;
use crate::model::KindData;

/// What to say of binary data, which a clip keeps in a media file.
const BINARY: &str = "binary data goes in a media file: give it in `media`";

/// Options for `clip_add` or `clip_set_custom` with their `data` taken out
/// and made a [`KindData`], and the bodies of their signals checked. The
/// table given is not changed.
pub(super) fn split(lua: &Lua, opts: LuaValue) -> mlua::Result<(LuaValue, Option<KindData>)> {
    let LuaValue::Table(table) = opts else {
        return Ok((opts, None));
    };
    let data = table.raw_get::<LuaValue>("data")?;
    if let LuaValue::Table(signals) = table.raw_get::<LuaValue>("signals")? {
        for (i, signal) in signals.sequence_values::<LuaValue>().enumerate() {
            let body = match signal? {
                LuaValue::Table(s) => match s.raw_get::<LuaValue>("to")? {
                    LuaValue::Table(to) => to.raw_get::<LuaValue>("body")?,
                    _ => LuaValue::Nil,
                },
                _ => LuaValue::Nil,
            };
            if !body.is_nil() {
                to_value(lua, &body, &format!("signals[{}].to.body", i + 1)).map_err(mlua::Error::runtime)?;
            }
        }
    }
    if data.is_nil() {
        return Ok((LuaValue::Table(table), None));
    }
    let rest = lua.create_table()?;
    for pair in table.pairs::<LuaValue, LuaValue>() {
        let (key, value) = pair?;
        if !matches!(&key, LuaValue::String(s) if s.as_bytes().as_ref() == b"data") {
            rest.raw_set(key, value)?;
        }
    }
    Ok((LuaValue::Table(rest), Some(kind_data(lua, data)?)))
}

/// `{ json = value }` or `{ text = { ext, text } }`.
fn kind_data(lua: &Lua, data: LuaValue) -> mlua::Result<KindData> {
    if let LuaValue::Table(t) = &data {
        let json = t.raw_get::<LuaValue>("json")?;
        if !json.is_nil() {
            return Ok(KindData::Json(to_value(lua, &json, "").map_err(mlua::Error::runtime)?.into()));
        }
        if let LuaValue::Table(text) = t.raw_get::<LuaValue>("text")?
            && let LuaValue::String(s) = text.raw_get::<LuaValue>("text")?
            && s.to_str().is_err()
        {
            return Err(mlua::Error::runtime(format!("the text data is not UTF-8: {BINARY}")));
        }
    }
    from_lua(lua, data).map_err(|err| {
        mlua::Error::runtime(format!("the data is `{{ json = value }}` or `{{ text = {{ ext, text }} }}`: {err}"))
    })
}

/// A Lua value as plain JSON, or what is wrong and where (`path` names
/// the value itself; empty for the top).
pub(super) fn to_value(lua: &Lua, value: &LuaValue, path: &str) -> Result<Value, String> {
    let mut path = path.to_string();
    let array = lua.array_metatable().to_pointer();
    Walk { open: Vec::new(), array }.value(value, &mut path)
}

struct Walk {
    /// The tables from the top to here: one met again is a cycle.
    open: Vec<*const c_void>,
    /// The metatable that marks an empty table as a list.
    array: *const c_void,
}

impl Walk {
    fn value(&mut self, value: &LuaValue, path: &mut String) -> Result<Value, String> {
        let wrong = |path: &str, what: &str| {
            let at = if path.is_empty() { "the value" } else { path };
            Err(format!("{at}: {what}"))
        };
        Ok(match value {
            LuaValue::Nil => Value::Null,
            LuaValue::LightUserData(ud) if ud.0.is_null() => Value::Null,
            LuaValue::Boolean(b) => Value::Bool(*b),
            LuaValue::Integer(i) => Value::from(*i),
            LuaValue::Number(n) => match Number::from_f64(*n) {
                Some(n) => Value::Number(n),
                None => return wrong(path, "NaN or an infinite number is not data"),
            },
            LuaValue::String(s) => match s.to_str() {
                Ok(s) => Value::String(s.to_string()),
                Err(_) => return wrong(path, &format!("a string that is not UTF-8 is not data: {BINARY}")),
            },
            LuaValue::Table(t) => {
                let ptr = t.to_pointer();
                if self.open.contains(&ptr) {
                    return wrong(path, "a table that holds itself is not data");
                }
                self.open.push(ptr);
                let out = self.table(t, path);
                self.open.pop();
                out?
            }
            LuaValue::Other(_) => return wrong(path, "a cdata is not data"),
            other => return wrong(path, &format!("a {} is not data", other.type_name())),
        })
    }

    /// A list (keys 1 to n, or empty with `paw.api.json_array`) or a map
    /// (string keys).
    fn table(&mut self, t: &Table, path: &mut String) -> Result<Value, String> {
        let len = t.raw_len();
        let mut count = 0;
        let mut strings = true;
        for pair in t.pairs::<LuaValue, LuaValue>() {
            let (key, _) = pair.map_err(|e| e.to_string())?;
            count += 1;
            strings &= matches!(key, LuaValue::String(_));
        }
        let mark = path.len();
        if count > 0 && count == len {
            let mut list = Vec::with_capacity(len);
            for i in 1..=len {
                let item: LuaValue = t.raw_get(i).map_err(|e| e.to_string())?;
                let _ = write!(path, "[{i}]");
                list.push(self.value(&item, path)?);
                path.truncate(mark);
            }
            return Ok(Value::Array(list));
        }
        if count == 0 {
            let array = t.metatable().is_some_and(|m| m.to_pointer() == self.array);
            return Ok(if array { Value::Array(Vec::new()) } else { Value::Object(Map::new()) });
        }
        if !strings {
            let at = if path.is_empty() { "the value" } else { path.as_str() };
            return Err(format!(
                "{at}: a table is a list (keys 1 to n, no holes) or a map (string keys), not both"
            ));
        }
        let mut map = Map::new();
        for pair in t.pairs::<LuaString, LuaValue>() {
            let (key, item) = pair.map_err(|e| e.to_string())?;
            let Ok(key) = key.to_str().map(|k| k.to_string()) else {
                let at = if path.is_empty() { "the value" } else { path.as_str() };
                return Err(format!("{at}: a key that is not UTF-8 is not data"));
            };
            let _ = write!(path, ".{key}");
            map.insert(key, self.value(&item, path)?);
            path.truncate(mark);
        }
        Ok(Value::Object(map))
    }
}

