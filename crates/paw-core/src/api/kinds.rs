//! `paw.api`: the kinds of each family, as `paw.kinds` puts them.

use std::rc::Rc;

use mlua::{Lua, Table, Value as LuaValue};
use serde_json::Value;

use super::{LuaResult, Shared, from_lua, to_lua};

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- kinds ---
        // The kind `name` of `family` is now `spec`, put by the extension
        // `owner` (nil for the core). A nil `spec` takes the kind away.
        // `paw.kinds` calls it each time the entry on top of a kind changes.
        // @return nil
        fn kinds_put(lua, sh, (family, name, spec, owner) => (String, String, LuaValue, Option<String>)) {
            let spec: Option<Value> = if spec.is_nil() { None } else { Some(from_lua(lua, spec)?) };
            sh.session.borrow_mut().doc.kinds.put(&family, &name, spec, owner).lua()
        }
        // The kinds of `family` (of every family when nil), each with its
        // owner and the schema of its data.
        // @return {types.KindInfo}
        fn kinds_list(lua, sh, family => Option<String>) {
            to_lua(lua, &sh.session.borrow().doc.kinds.list(family.as_deref()).lua()?)
        }
        // Check a stream type `{ base, props }` against its stream kind. The
        // error names a property that the kind does not take.
        // @type function(ty: types.StreamType)
        fn stream_check(lua, sh, ty => LuaValue) {
            let ty: paw_types::stream::StreamType = from_lua(lua, ty)?;
            sh.session.borrow().doc.kinds.check_stream(&ty).lua()
        }
    }
    Ok(())
}
