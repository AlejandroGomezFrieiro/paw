//! `paw.api`: devices and plugins.

use std::rc::Rc;

use mlua::{Lua, LuaString, Table, Value as LuaValue};
use serde_json::{Value, json};

use crate::model::Id;

use super::{LuaResult, Shared, changes, from_lua, options, to_lua};

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- devices ---
        // @return {types.DeviceType}
        fn device_types(lua, sh, () => ()) { to_lua(lua, &sh.session.borrow().device_types()) }
        // paw's schema of the chain language, as JSON text: each kind of
        // device that paw has now (with the plugins and the Lua devices of
        // the extensions), and each kind of split and modulator. It is what
        // `paw chain schema` prints, for a language server or another tool.
        // @return string
        fn chain_schema(_, sh, () => ()) { Ok(crate::chain_schema::json(&sh.session.borrow())) }
        // The kind of device installed that answers `query`, `{ kind, format,
        // id, name, vendor }` (each optional), as an entry of `device_types`;
        // nil when none does. It looks by `kind` (an old name too), else by
        // the plugin's own `id` (a CLAP id, a VST3 class id in either case,
        // an LV2 URI), else by `name` with the `vendor` (a kind without a
        // vendor answers any), else by `name` in any case; `format` ("clap",
        // "vst3", "lv2", "builtin") keeps to one format. The list of all
        // kinds is not made, so it is quick with many plugins.
        // `device_find_all` gives all that answer.
        // @param query types.DeviceQuery
        // @return types.DeviceType
        fn device_find(lua, sh, query => LuaValue) {
            let q: crate::session::DeviceQuery = from_lua(lua, query)?;
            let found = sh.session.borrow().device_find(&q);
            // `all = true` is the older way to ask for `device_find_all`.
            if q.all {
                to_lua(lua, &found)
            } else {
                found.into_iter().next().map_or(Ok(LuaValue::Nil), |v| to_lua(lua, &v))
            }
        }
        // Each kind of device installed that answers `query` (see
        // `device_find`): all that answer the first test that finds one.
        // @param query types.DeviceQuery
        // @return {types.DeviceType}
        fn device_find_all(lua, sh, query => LuaValue) {
            let q: crate::session::DeviceQuery = from_lua(lua, query)?;
            to_lua(lua, &sh.session.borrow().device_find(&q))
        }
        // @return types.Device
        fn device_get(lua, sh, id => Id) {
            // A device's parameters are those of the instance the engine
            // runs, so bring the engine up to date first: right after an undo
            // the device would otherwise read as missing.
            let mut session = sh.session.borrow_mut();
            session.flush();
            to_lua(lua, &session.device_view(id).lua()?)
        }
        // @param opts? types.DeviceOptions
        // @return integer
        fn device_add(lua, sh, (track, kind, opts) => (Id, String, LuaValue)) {
            sh.session.borrow_mut().device_add(track, &kind, options(lua, opts)?).lua()
        }
        // @return nil
        fn device_remove(_, sh, id => Id) { sh.session.borrow_mut().doc.device_remove(id).lua() }
        // @return nil
        fn device_move(_, sh, (id, track, index) => (Id, Id, usize)) {
            sh.session.borrow_mut().doc.device_move(id, track, index.saturating_sub(1)).lua()
        }
        // Change a device: a table of the entries to change, as `device_get`
        // gives them, or one `key` and its value. Only the key form clears
        // an entry (`nil`).
        // @type function(id: integer, patch: types.Device)
        // @type function(id: integer, key: string, value: nil)
        fn device_set(lua, sh, (id, key, value) => (Id, LuaValue, LuaValue)) {
            let mut session = sh.session.borrow_mut();
            for (key, value) in changes(lua, key, value)? {
                session.doc.device_set(id, &key, from_lua(lua, value)?).lua()?;
            }
            Ok(())
        }
        // Set a parameter of a device, named by its key, the device's own id for
        // it or its name. The value is a number, or text as the device reads it
        // ("440 Hz", "Saw").
        // @param value number | string
        // @return nil
        fn device_set_param(lua, sh, (id, name, value) => (Id, String, LuaValue)) {
            let mut session = sh.session.borrow_mut();
            let value = match value {
                LuaValue::String(text) => session.param_parse(id, &name, &text.to_str()?).lua()?,
                other => from_lua::<f64>(lua, other)?,
            };
            session.device_set_param(id, &name, value).lua()
        }
        // One parameter of a device, named by its key, the device's own id for it
        // or its name: its entry of `param_info`, with `value` (now) and `text`
        // (that value as the device writes it).
        // @return types.ParamInfo
        fn device_param(lua, sh, (id, name) => (Id, String)) {
            let mut session = sh.session.borrow_mut();
            session.flush();
            to_lua(lua, &session.device_param(id, &name).lua()?)
        }
        // A value of a parameter as text, as the device writes it ("440 Hz").
        // Without a value, the value now.
        // @return string
        fn device_param_text(_, sh, (id, name, value) => (Id, String, Option<f64>)) {
            let mut session = sh.session.borrow_mut();
            session.flush();
            let value = match value {
                Some(value) => value,
                None => session.device_param(id, &name).lua()?["value"].as_f64().unwrap_or_default(),
            };
            session.param_text(id, &name, value).lua()
        }
        // The value that a text stands for, for a parameter, as the device reads it.
        // An error when the device cannot read the text.
        // @return number
        fn device_param_parse(_, sh, (id, name, text) => (Id, String, String)) {
            let mut session = sh.session.borrow_mut();
            session.flush();
            session.param_parse(id, &name, &text).lua()
        }

        // Load a preset into a device, as one undo step:
        // `{ name =, state =, params =, factory =, call = }`. `call = { method =,
        // data = }` is a `device_call` that changes the state of the plugin
        // (`property.set` of an LV2 plugin). The state after it is kept.
        // @param load types.PresetLoad
        // @return nil
        fn device_load(lua, sh, (id, load) => (Id, LuaValue)) {
            sh.session.borrow_mut().device_load(id, options(lua, load)?).lua()
        }
        // The state of a plugin. Give it as `state` when you add a copy of the device.
        // @return string
        fn device_state(_, sh, id => Id) { sh.session.borrow_mut().device_state(id).lua() }

        // Show or hide the window of a plugin. With no second argument, toggle it.
        // @return boolean
        fn device_editor(_, sh, (id, open) => (Id, Option<bool>)) {
            sh.session.borrow_mut().device_editor(id, open).lua()
        }
        // Start again a device that stopped (a plugin that crashed).
        // @return nil
        fn device_restart(_, sh, id => Id) { sh.session.borrow_mut().device_restart(id).lua() }
        // Examine the plugin files again (all, or those that `name` matches). This
        // includes the files that failed before. Returns notes on the files that
        // paw cannot use, or nil without plugins.
        // @return {string}
        fn plugins_rescan(_, sh, name => Option<String>) {
            Ok(sh.session.borrow_mut().registry.rescan(name.as_deref()))
        }
        // Find CLAP and VST3 plugins in one more directory from now on (the
        // directory of an extension), and register the plugins in it. Returns
        // `{ kinds, notes }`: the device kinds found there and the files that paw
        // cannot use. Returns nil where paw cannot find plugins.
        // @return types.PluginDir
        fn plugins_add_dir(lua, sh, dir => String) {
            let found = sh.session.borrow_mut().registry.add_dir(std::path::Path::new(&dir));
            match found {
                Some((kinds, notes)) => to_lua(lua, &json!({ "kinds": kinds, "notes": notes })),
                None => Ok(LuaValue::Nil),
            }
        }
        // The folders where paw looks for plugins, for each format, in the order
        // that paw looks in them: `{ clap = {...}, lv2 = {...}, vst3 = {...} }`.
        // They include the folders that `plugins_add_dir` added. Returns nil where
        // paw cannot find plugins.
        // @return {string: {string}}
        fn plugins_dirs(lua, sh, () => ()) {
            let dirs = sh.session.borrow().registry.plugin_dirs();
            match dirs {
                Some(dirs) => {
                    let table = lua.create_table()?;
                    for (format, folders) in dirs {
                        let folders: Vec<String> =
                            folders.iter().map(|f| f.to_string_lossy().into_owned()).collect();
                        table.raw_set(format, folders)?;
                    }
                    Ok(LuaValue::Table(table))
                }
                None => Ok(LuaValue::Nil),
            }
        }
        // Load an attachment: a native library that an extension ships, which
        // paw offers each CLAP plugin that it makes from now on (see
        // `crates/paw-plugins/include/paw_attach.h`). Returns the name of the
        // attachment.
        // @return string
        fn plugins_attach(_, sh, path => String) {
            sh.session.borrow_mut().registry.attach(std::path::Path::new(&path)).lua()
        }
        // Stop to find plugins in a directory added with `plugins_add_dir`, and
        // make no more devices of `kinds`, the kinds found there. Devices that
        // exist continue to work.
        // @return nil
        fn plugins_remove_dir(_, sh, (dir, kinds) => (String, Vec<String>)) {
            sh.session.borrow_mut().registry.remove_dir(std::path::Path::new(&dir), &kinds);
            Ok(())
        }
        // What a plugin calls its keys, `{ [pitch] = name }` (CLAP `note-name`).
        // @return {integer: string}
        fn device_note_names(lua, sh, id => Id) {
            let names = sh.session.borrow_mut().device_note_names(id);
            let table = lua.create_table_with_capacity(0, names.len())?;
            for (pitch, name) in names {
                table.raw_set(pitch, name)?;
            }
            Ok(table)
        }
        // Add devices that fail on purpose (`test.panic`, `test.nan`). Tests use
        // them to see what a bad device does to the other devices.
        // @return nil
        fn test_devices(_, sh, () => ()) {
            paw_engine::guard::register_test_devices(&mut sh.session.borrow_mut().registry);
            Ok(())
        }
        // Panic, as a bug in the program does. Tests use it to see what paw
        // keeps. The panic ends the program, as a bug outside `paw.api`
        // does, and paw writes a safety copy. With `inside`, it is a bug in
        // this function: the call gives an error, and the program goes on.
        // @return nil
        fn test_panic(_, _sh, (why, inside) => (String, Option<bool>)) {
            if why.is_empty() {
                return Ok(());
            }
            if inside == Some(true) {
                panic!("{why}");
            }
            super::end_program(&why)
        }
        // Make plugins apart from the main loop (true), or wait for each as
        // it is added (false, what scripts start with). Returns what it was.
        // @return boolean
        fn load_apart(_, sh, on => bool) { Ok(sh.session.borrow_mut().set_load_apart(on)) }
        // A request to a device that accepts data from scripts. Bytes in, bytes out.
        // @return string
        fn device_call(lua, sh, (id, method, data) => (Id, String, Option<LuaString>)) {
            let data = data.as_ref().map(|d| d.as_bytes().to_vec()).unwrap_or_default();
            let answer = sh.session.borrow_mut().device_call(id, &method, &data).lua()?;
            lua.create_string(answer)
        }
        // Data for all devices of a kind, now and in the future (also the devices
        // of a render). nil removes the topic. Returns `{ { device, error } }` for
        // the devices that refused it.
        // @return {types.DeviceRefusal}
        fn device_post(lua, sh, (kind, topic, data) => (String, String, Option<LuaString>)) {
            let data = data.as_ref().map(|d| d.as_bytes().to_vec());
            let refused = sh.session.borrow_mut().device_post(&kind, &topic, data.as_deref());
            let list: Vec<Value> = refused
                .into_iter()
                .map(|(device, error)| json!({ "device": device, "error": error }))
                .collect();
            to_lua(lua, &Value::Array(list))
        }
        // Devices of `old`, a kind that was renamed, are made as `new`.
        // @return nil
        fn device_alias(_, sh, (old, new) => (String, String)) {
            sh.session.borrow_mut().registry.alias(&old, &new);
            Ok(())
        }

    }
    Ok(())
}
