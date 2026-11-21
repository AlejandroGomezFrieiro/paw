//! `paw.api`: helper processes, sockets and the control socket's clients.

use std::rc::Rc;

use mlua::{Lua, LuaString, Table, Value as LuaValue};
use serde_json::Value;

use crate::events::ModelEvent;

use super::{LuaResult, Shared, from_lua, options, to_lua};

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- helper processes and sockets ---
        // @param opts? types.SpawnOptions
        // @return integer
        fn proc_spawn(lua, sh, (argv, opts) => (Vec<String>, LuaValue)) {
            sh.io.borrow_mut().spawn(&argv, options(lua, opts)?).lua()
        }
        // @return types.ProcStatus
        fn proc_status(lua, sh, id => u64) { to_lua(lua, &sh.io.borrow_mut().status(id).lua()?) }
        // Ask it to finish and let it: `proc_status` says when it has.
        // @return nil
        fn proc_stop(_, sh, id => u64) { sh.io.borrow_mut().stop(id).lua() }
        // @return nil
        fn proc_kill(_, sh, id => u64) {
            sh.io.borrow_mut().kill(id);
            Ok(())
        }
        // A process started with `pipe = true`: what it wrote ("" when
        // nothing, nil once it closed its output). `proc_write` writes to it.
        // A `proc.output` event says when there is something to read.
        // @return string
        fn proc_read(lua, sh, (id, max) => (u64, Option<usize>)) {
            match sh.io.borrow_mut().read_output(id, max.unwrap_or(1 << 20)).lua()? {
                Some(bytes) => Ok(LuaValue::String(lua.create_string(bytes)?)),
                None => Ok(LuaValue::Nil),
            }
        }
        // @return nil
        fn proc_write(_, sh, (id, data) => (u64, LuaString)) { sh.io.borrow_mut().write_input(id, &data.as_bytes()).lua() }
        // @return nil
        fn proc_close_input(_, sh, id => u64) { sh.io.borrow_mut().close_input(id).lua() }
        // @return integer
        fn sock_listen(_, sh, path => String) { sh.io.borrow_mut().listen(path.into()).lua() }
        // @return integer
        fn sock_connect(_, sh, path => String) { sh.io.borrow_mut().connect(path.into()).lua() }
        // @return integer
        fn sock_accept(_, sh, id => u64) { sh.io.borrow_mut().accept(id).lua() }
        // The bytes that came, "" when none came, nil after the peer closed.
        // @return string
        fn sock_read(lua, sh, (id, max) => (u64, Option<usize>)) {
            match sh.io.borrow_mut().read(id, max.unwrap_or(1 << 20)).lua()? {
                Some(bytes) => Ok(LuaValue::String(lua.create_string(bytes)?)),
                None => Ok(LuaValue::Nil),
            }
        }
        // @return nil
        fn sock_write(_, sh, (id, data) => (u64, LuaString)) { sh.io.borrow_mut().write(id, &data.as_bytes()).lua() }
        // @return nil
        fn sock_close(_, sh, id => u64) {
            sh.io.borrow_mut().close(id);
            Ok(())
        }

        // Connections on the control socket (crates/paw-core/src/rpc.rs). Push an
        // event to one (false when it closed), list them, and tell the terminal
        // of the input that paw handles now (0 for the terminal of paw). Also
        // release the terminal of a connection.
        // @return boolean
        fn rpc_push(lua, sh, (client, event, payload) => (u64, String, LuaValue)) {
            let payload: Value = from_lua(lua, payload)?;
            Ok(sh.clients.push(client, &event, &payload))
        }
        // @return {integer}
        fn rpc_clients(_, sh, () => ()) { Ok(sh.clients.ids()) }
        // @return integer
        fn rpc_version(_, _sh, () => ()) { Ok(crate::rpc::VERSION) }
        // @return integer
        fn ui_client(_, sh, () => ()) { Ok(sh.input_from.get()) }
        // @return nil
        fn ui_seat(_, sh, seat => u64) {
            // The screen is the size of the terminal of the seat entered;
            // a seat without one (a window's) has the size there was at first.
            let (width, height) = sh.sizes.borrow().get(&seat).copied().unwrap_or((80, 24));
            let mut grid = sh.grid.borrow_mut();
            if (grid.width, grid.height) != (width, height) {
                grid.resize(width, height);
            }
            Ok(())
        }
        // @return nil
        fn ui_detach(_, sh, client => u64) {
            sh.detach.borrow_mut().push(client);
            Ok(())
        }

        // @return {string}
        fn log_get(_, sh, () => ()) { Ok(sh.log.borrow().iter().cloned().collect::<Vec<_>>()) }
        // @return {kernel_events.KernelEvent}
        fn events_take(lua, sh, () => ()) {
            // Push pending edits to the engine and hand back the change events.
            let events = {
                let mut session = sh.session.borrow_mut();
                session.write_automation();
                session.flush();
                session.read_ahead();
                session.poll_media();
                std::mem::take(&mut session.events)
            };
            let list = lua.create_table_with_capacity(events.len(), 0)?;
            for ModelEvent { event, restored } in events {
                // `{ name, payload }`, as `KernelEvent` is tagged.
                let event = to_lua(lua, &event)?;
                if restored
                    && let LuaValue::Table(event) = &event
                    && let LuaValue::Table(payload) = event.get("payload")?
                {
                    payload.set("restored", true)?;
                }
                list.push(event)?;
            }
            Ok(list)
        }
    }
    Ok(())
}
