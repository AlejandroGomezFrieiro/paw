//! TOML for what extensions keep in files (`paw.api.toml_decode`,
//! `toml_encode`). A table read keeps the order of its keys in its
//! metatable, `__keys`, and a table written puts the keys of `__keys`
//! first, then the others by name.

use mlua::{Lua, Table, Value as LuaValue};
use toml_edit::{Array, ArrayOfTables, DocumentMut, InlineTable, Item, Value};

fn ordered(lua: &Lua, keys: Vec<String>) -> mlua::Result<Table> {
    let meta = lua.create_table()?;
    meta.set("__keys", keys)?;
    Ok(meta)
}

fn value_to_lua(lua: &Lua, v: &Value) -> mlua::Result<LuaValue> {
    Ok(match v {
        Value::String(s) => LuaValue::String(lua.create_string(s.value())?),
        Value::Integer(i) => crate::api::lua_integer(*i.value()),
        Value::Float(f) => LuaValue::Number(*f.value()),
        Value::Boolean(b) => LuaValue::Boolean(*b.value()),
        // A date or a time, as its text.
        Value::Datetime(d) => LuaValue::String(lua.create_string(d.value().to_string())?),
        Value::Array(a) => {
            let t = lua.create_table()?;
            for x in a.iter() {
                t.push(value_to_lua(lua, x)?)?;
            }
            LuaValue::Table(t)
        }
        Value::InlineTable(it) => {
            let t = lua.create_table()?;
            let mut keys = Vec::new();
            for (k, x) in it.iter() {
                t.set(k, value_to_lua(lua, x)?)?;
                keys.push(k.to_string());
            }
            t.set_metatable(Some(ordered(lua, keys)?))?;
            LuaValue::Table(t)
        }
    })
}

fn item_to_lua(lua: &Lua, item: &Item) -> mlua::Result<LuaValue> {
    Ok(match item {
        Item::None => LuaValue::Nil,
        Item::Value(v) => value_to_lua(lua, v)?,
        Item::Table(table) => {
            let t = lua.create_table()?;
            let mut keys = Vec::new();
            for (k, x) in table.iter() {
                t.set(k, item_to_lua(lua, x)?)?;
                keys.push(k.to_string());
            }
            t.set_metatable(Some(ordered(lua, keys)?))?;
            LuaValue::Table(t)
        }
        Item::ArrayOfTables(list) => {
            let t = lua.create_table()?;
            for table in list.iter() {
                t.push(item_to_lua(lua, &Item::Table(table.clone()))?)?;
            }
            LuaValue::Table(t)
        }
    })
}

/// A table of TOML text, or what is wrong and on which line.
pub(crate) fn decode(lua: &Lua, text: &str) -> mlua::Result<Result<LuaValue, String>> {
    match text.parse::<DocumentMut>() {
        Ok(doc) => Ok(Ok(item_to_lua(lua, doc.as_item())?)),
        Err(err) => {
            let line = err.span().map_or(1, |s| text[..s.start.min(text.len())].matches('\n').count() + 1);
            Ok(Err(format!("line {line}: {}", err.message().trim())))
        }
    }
}

/// The keys of a table in the order they are written.
fn keys_of(t: &Table) -> mlua::Result<Vec<String>> {
    let mut first: Vec<String> = Vec::new();
    if let Some(meta) = t.metatable()
        && let Some(keys) = meta.get::<Option<Table>>("__keys")?
    {
        for k in keys.sequence_values::<String>() {
            let k = k?;
            if !first.contains(&k) && !t.get::<LuaValue>(k.as_str())?.is_nil() {
                first.push(k);
            }
        }
    }
    let mut rest = Vec::new();
    for pair in t.pairs::<LuaValue, LuaValue>() {
        let (k, _) = pair?;
        let k = match k {
            LuaValue::String(s) => s.to_string_lossy(),
            LuaValue::Integer(i) => i.to_string(),
            LuaValue::Number(n) => n.to_string(),
            other => return Err(mlua::Error::runtime(format!("a TOML key cannot be a {}", other.type_name()))),
        };
        if !first.contains(&k) {
            rest.push(k);
        }
    }
    rest.sort();
    first.extend(rest);
    Ok(first)
}

/// A list: a table with only 1..n, or an empty table.
fn is_list(t: &Table) -> bool {
    let n = t.raw_len();
    n > 0 && t.pairs::<LuaValue, LuaValue>().count() == n || t.pairs::<LuaValue, LuaValue>().next().is_none()
}

fn get(t: &Table, k: &str) -> mlua::Result<LuaValue> {
    let v: LuaValue = t.raw_get(k)?;
    if v.is_nil()
        && let Ok(i) = k.parse::<i64>()
    {
        return t.raw_get(i);
    }
    Ok(v)
}

fn to_value(v: &LuaValue) -> mlua::Result<Value> {
    Ok(match v {
        LuaValue::String(s) => Value::from(s.to_string_lossy()),
        LuaValue::Integer(i) => Value::from(crate::api::wide_integer(*i)),
        LuaValue::Number(n) if n.fract() == 0.0 && n.abs() < 9.0e15 => Value::from(*n as i64),
        LuaValue::Number(n) => Value::from(*n),
        LuaValue::Boolean(b) => Value::from(*b),
        LuaValue::Table(t) if is_list(t) => {
            let mut a = Array::new();
            for x in t.sequence_values::<LuaValue>() {
                a.push(to_value(&x?)?);
            }
            Value::Array(a)
        }
        LuaValue::Table(t) => {
            let mut it = InlineTable::new();
            for k in keys_of(t)? {
                it.insert(&k, to_value(&get(t, &k)?)?);
            }
            Value::InlineTable(it)
        }
        other => return Err(mlua::Error::runtime(format!("TOML cannot hold a {}", other.type_name()))),
    })
}

fn to_item(v: &LuaValue) -> mlua::Result<Item> {
    match v {
        LuaValue::Table(t) if !is_list(t) => {
            let mut table = toml_edit::Table::new();
            for k in keys_of(t)? {
                table.insert(&k, to_item(&get(t, &k)?)?);
            }
            Ok(Item::Table(table))
        }
        // A list of tables is an array of tables.
        LuaValue::Table(t)
            if t.raw_len() > 0 && t.sequence_values::<LuaValue>().all(|x| matches!(x, Ok(LuaValue::Table(ref e)) if !is_list(e))) =>
        {
            let mut list = ArrayOfTables::new();
            for x in t.sequence_values::<LuaValue>() {
                if let Item::Table(table) = to_item(&x?)? {
                    list.push(table);
                }
            }
            Ok(Item::ArrayOfTables(list))
        }
        other => Ok(Item::Value(to_value(other)?)),
    }
}

/// The TOML text of a value: a table as a document, or with `inline`, any
/// value on one line.
pub(crate) fn encode(value: &LuaValue, inline: bool) -> mlua::Result<String> {
    if inline {
        let mut v = to_value(value)?;
        v.decor_mut().clear();
        return Ok(v.to_string().trim().to_string());
    }
    match to_item(value)? {
        Item::Table(table) => Ok(DocumentMut::from(table).to_string()),
        _ => Err(mlua::Error::runtime("a TOML document is a table")),
    }
}
