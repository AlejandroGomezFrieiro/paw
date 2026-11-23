//! `paw.api.lua_devices*`: where devices written in Lua are found, and
//! looking at their files again (see the `paw-luadev` crate).

use std::path::Path;
use std::rc::Rc;

use paw_luadev::Scanned;
use mlua::{Lua, Table};

use crate::api::{Shared, guarded};

fn scanned(lua: &Lua, scanned: Scanned) -> mlua::Result<Table> {
    let out = lua.create_table()?;
    out.set("added", scanned.added)?;
    out.set("changed", scanned.changed)?;
    let errors = lua.create_table()?;
    for (kind, path, why) in scanned.errors {
        let e = lua.create_table()?;
        e.set("kind", kind)?;
        e.set("path", path.to_string_lossy().into_owned())?;
        e.set("error", why)?;
        errors.push(e)?;
    }
    out.set("errors", errors)?;
    Ok(out)
}

pub(crate) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    // Look for devices in `dir` from now on; a script there wins over one
    // of the same name in a directory of a lower `rank` (0 by default).
    // Returns `{ added, changed, errors }`: kinds, kinds, and
    // `{ kind, path, error }` for scripts that did not load.
    // @return types.LuaDeviceScan
    let sh = shared.clone();
    api.set(
        "lua_devices_add",
        lua.create_function(guarded!("lua_devices_add", move |lua, (dir, rank): (String, Option<u8>)| {
            let mut session = sh.session.borrow_mut();
            let found = paw_luadev::add_dir(&mut session.registry, Path::new(&dir), rank.unwrap_or(0));
            scanned(lua, found)
        }))?,
    )?;
    // Look in `dir` no more: a script of the same name elsewhere makes its
    // scripts' kinds from now on, or nothing does. Returns the kinds of
    // the scripts that were there.
    // @return {string}
    let sh = shared.clone();
    api.set(
        "lua_devices_remove",
        lua.create_function(guarded!("lua_devices_remove", move |_, dir: String| {
            let mut session = sh.session.borrow_mut();
            Ok(paw_luadev::remove_dir(&mut session.registry, Path::new(&dir)))
        }))?,
    )?;
    // Look at every script again, loading those that changed. Same answer
    // as `lua_devices_add`; `changed` are the kinds whose devices are now
    // behind their file.
    // @return types.LuaDeviceScan
    let sh = shared.clone();
    api.set(
        "lua_devices_rescan",
        lua.create_function(guarded!("lua_devices_rescan", move |lua, ()| {
            let mut session = sh.session.borrow_mut();
            scanned(lua, paw_luadev::rescan(&mut session.registry))
        }))?,
    )?;
    // Every script found: `{ kind, path, name, category, error, active }`,
    // `active` false for one hidden by a script of the same name in a
    // directory of a higher rank.
    // @return {types.LuaDeviceScript}
    api.set(
        "lua_devices",
        lua.create_function(guarded!("lua_devices", |lua, ()| {
            let list = lua.create_table()?;
            for s in paw_luadev::scripts() {
                let t = lua.create_table()?;
                t.set("kind", s.kind)?;
                t.set("path", s.path.to_string_lossy().into_owned())?;
                t.set("name", s.name)?;
                t.set("category", s.category)?;
                t.set("error", s.error)?;
                t.set("active", s.active)?;
                list.push(t)?;
            }
            Ok(list)
        }))?,
    )?;
    Ok(())
}
