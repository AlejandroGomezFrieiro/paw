//! `paw.api`: automation lanes.

use std::rc::Rc;

use mlua::{Lua, Table, Value as LuaValue};

use crate::model::Id;

use super::{LuaResult, Shared, changes, from_lua, to_lua};

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- automation ---
        // @return {types.Lane}
        fn lane_list(lua, sh, track => Id) { to_lua(lua, &sh.session.borrow().lane_list(track).lua()?) }
        // @return types.Lane
        fn lane_get(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().lane_view(id).lua()?) }
        // @param opts types.LaneOptions
        // @return integer
        fn lane_add(lua, sh, (track, opts) => (Id, LuaValue)) {
            sh.session.borrow_mut().lane_add(track, from_lua(lua, opts)?).lua()
        }
        // @return nil
        fn lane_remove(_, sh, id => Id) { sh.session.borrow_mut().doc.lane_remove(id).lua() }
        // Change a lane: a table of the entries to change, as `lane_get`
        // gives them, or one `key` and its value. Only the key form clears
        // an entry (`nil`).
        // @type function(id: integer, patch: types.Lane)
        // @type function(id: integer, key: string, value: nil)
        fn lane_set(lua, sh, (id, key, value) => (Id, LuaValue, LuaValue)) {
            let mut session = sh.session.borrow_mut();
            for (key, value) in changes(lua, key, value)? {
                session.lane_set(id, &key, from_lua(lua, value)?).lua()?;
            }
            Ok(())
        }
        // @return {types.LanePoint}
        fn lane_points(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().doc.lane_points(id).lua()?) }
        // @param points {types.LanePoint}
        // @return nil
        fn lane_set_points(lua, sh, (id, points) => (Id, LuaValue)) {
            let points: Vec<(f64, f64)> = from_lua(lua, points)?;
            sh.session.borrow_mut().lane_set_points(id, points, false).lua()
        }
        // @return nil
        fn lane_add_point(_, sh, (id, beat, value) => (Id, f64, f64)) {
            sh.session.borrow_mut().lane_set_points(id, vec![(beat, value)], true).lua()
        }
        // @return number
        fn lane_value_at(_, sh, (id, beat) => (Id, f64)) { sh.session.borrow().doc.lane_value_at(id, beat).lua() }
        // The shapes of the stretches that are not straight, `{ beat, shape, tension }`
        // each by the beat of the point they leave: "hold" or "smooth".
        // @return {types.LaneSegment}
        fn lane_shapes(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().doc.lane_shapes(id).lua()?) }
        // @param shapes {types.LaneSegment}
        // @return nil
        fn lane_set_shapes(lua, sh, (id, shapes) => (Id, LuaValue)) {
            let shapes: Vec<crate::model::Segment> = from_lua(lua, shapes)?;
            sh.session.borrow_mut().doc.lane_set_shapes(id, shapes).lua()
        }
        // The states of a state lane, whole: `{ name, state, params, call =
        // { method, data }, program, bank }` each. A point's value is the
        // index of one, from 0.
        // @return {types.LaneState}
        fn lane_states(lua, sh, id => Id) { to_lua(lua, &sh.session.borrow().doc.lane_states(id).lua()?) }
        // Replace the states of a state lane, as one undo step. A point
        // that names a state no longer there names the last.
        // @param states {types.LaneState}
        // @return nil
        fn lane_set_states(lua, sh, (id, states) => (Id, LuaValue)) {
            let states: Vec<crate::model::LaneState> = from_lua(lua, states)?;
            sh.session.borrow_mut().doc.lane_set_states(id, states).lua()
        }
        // Add a state to a state lane, or replace the one of its name, as
        // one undo step. Returns its index, from 0.
        // @param state types.LaneState
        // @return integer
        fn lane_add_state(lua, sh, (id, state) => (Id, LuaValue)) {
            let state: crate::model::LaneState = from_lua(lua, state)?;
            sh.session.borrow_mut().doc.lane_add_state(id, state).lua()
        }
        // A control is held (a fader under the pointer) or let go: in touch
        // mode it writes automation for as long as it is held. The control
        // is named as a lane's target is.
        // @return nil
        fn automation_hold(_, sh, (track, target, device, param, on) => (Id, String, Option<Id>, Option<String>, bool)) {
            sh.session.borrow_mut().automation_hold_named(track, &target, device, param, on).lua()
        }

    }
    Ok(())
}
