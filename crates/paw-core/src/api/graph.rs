//! `paw.api`: the devices graph of a track and linked racks
//! (`model/graph.rs`, `model/racks.rs`). `paw.graph` (paw/graph.tl) is the
//! typed module over these.

use std::rc::Rc;

use mlua::{Lua, Table, Value as LuaValue};
use serde::Deserialize;
use serde_json::json;

use crate::model::Id;
use crate::model::graph::KindSpec;
use crate::session::{Place, WrapOpts};

use super::{LuaResult, Shared, changes, from_lua, options, to_lua};

/// A place as Lua gives it: an `index` counts from 1.
fn place(lua: &Lua, value: LuaValue) -> mlua::Result<Place> {
    let mut place: Place = from_lua(lua, value)?;
    place.index = place.index.map(|i| i.saturating_sub(1));
    Ok(place)
}

/// What `graph_branch_add` takes.
#[derive(Default, Deserialize)]
struct BranchOpts {
    name: Option<String>,
    /// From 1; the end when not given.
    index: Option<usize>,
}

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- the devices graph ---

        // The graph of a track's devices, or nil when the track has none (its
        // devices play in series, in the order of `track.devices`).
        // @return types.Graph
        fn graph_get(lua, sh, track => Id) {
            let session = sh.session.borrow();
            let t = session.doc.project.track(track).ok_or_else(|| mlua::Error::runtime(format!("no track {track}")))?;
            match &t.graph {
                Some(graph) => to_lua(lua, &**graph),
                None => Ok(LuaValue::Nil),
            }
        }
        // The words of the kinds of split: the built-in kinds first, then the
        // kinds that extensions defined.
        // @return {string}
        fn graph_kinds(_, sh, () => ()) { Ok(sh.session.borrow().doc.graph_kinds()) }
        // Let a graph have a split of a new kind: `spec` gives the fewest
        // (`min`) and the most (`max`) branches, and how many a new split
        // gets (`first`).
        // @param spec types.GraphKindSpec
        // @return nil
        fn graph_kind_define(lua, sh, (word, spec) => (String, LuaValue)) {
            let spec: KindSpec = from_lua(lua, spec)?;
            sh.session.borrow_mut().doc.graph_kind_define(&word, spec).lua()
        }
        // Wrap nodes (devices or splits in a row of one branch) in a new split
        // of `kind`, as one undo step. They go into its first branch. Gives
        // the split's id.
        // @param opts? types.GraphWrapOptions
        // @return integer
        fn graph_wrap(lua, sh, (nodes, kind, opts) => (Vec<Id>, String, LuaValue)) {
            let opts: WrapOpts = options(lua, opts)?;
            sh.session.borrow_mut().doc.graph_wrap(&nodes, &kind, opts).lua()
        }
        // Take a split away, as one undo step. With `keep` (a branch of it),
        // that branch takes its place and the devices of the others leave the
        // track; without, its branches go in its place one after the other.
        // Gives how many devices left the track.
        // @return integer
        fn graph_unwrap(_, sh, (split, keep) => (Id, Option<Id>)) {
            sh.session.borrow_mut().doc.graph_unwrap(split, keep).lua()
        }
        // Add an empty branch to a split, as one undo step: `{ name =, index = }`
        // (from 1; the end when not given). Gives its id.
        // @param opts? types.GraphBranchOptions
        // @return integer
        fn graph_branch_add(lua, sh, (split, opts) => (Id, LuaValue)) {
            let opts: BranchOpts = options(lua, opts)?;
            let index = opts.index.map(|i| i.saturating_sub(1));
            sh.session.borrow_mut().doc.graph_branch_add(split, opts.name, index).lua()
        }
        // Move a node in its graph, as one undo step: `{ before = id }`,
        // `{ after = id }` or `{ branch = id, index = n }` (from 1).
        // @param to types.GraphPlace
        // @return nil
        fn graph_move(lua, sh, (id, to) => (Id, LuaValue)) {
            let to = place(lua, to)?;
            sh.session.borrow_mut().doc.graph_move(id, &to).lua()
        }
        // Remove a split or a branch with its devices, a macro with its links,
        // or a device, as one undo step.
        // @return nil
        fn graph_remove(_, sh, id => Id) { sh.session.borrow_mut().doc.graph_remove(id).lua() }
        // Change a split (`name`, `mix`, `gain`, `kind`, `values`, `meta`), a
        // branch (`name`, `gain`, `pan`, `mute`, `solo`, `zone`) or a macro
        // (`name`, `value`): a table of the entries to change, or one `key` and
        // its value. One undo step.
        // @type function(id: integer, patch: types.GraphPatch)
        // @type function(id: integer, key: string, value: nil)
        fn graph_set(lua, sh, (id, key, value) => (Id, LuaValue, LuaValue)) {
            let mut session = sh.session.borrow_mut();
            let changes = changes(lua, key, value)?
                .into_iter()
                .map(|(key, value)| Ok((key, from_lua::<serde_json::Value>(lua, value)?)))
                .collect::<mlua::Result<Vec<_>>>()?;
            for (key, value) in changes {
                session.doc.graph_set(id, &key, value).lua()?;
            }
            Ok(())
        }
        // Add a macro to a split, as one undo step. Gives its id.
        // @return integer
        fn graph_macro_add(_, sh, (split, name) => (Id, String)) {
            sh.session.borrow_mut().doc.graph_macro_add(split, &name).lua()
        }
        // Link a macro to a parameter of a device in its split, with a depth
        // from -1 to 1; no depth removes the link. One undo step.
        // @return nil
        fn graph_link(_, sh, (source, device, param, depth) => (Id, Id, String, Option<f64>)) {
            sh.session.borrow_mut().doc.graph_link(source, device, &param, depth).lua()
        }
        // Let a device take its key from a node of its graph that comes before
        // it, from `"in"` (the input of the graph), or (nil) from no node of
        // the graph. One undo step.
        // @param from integer | string
        // @return nil
        fn graph_tap(lua, sh, (device, from) => (Id, LuaValue)) {
            let from = match from {
                LuaValue::Nil => None,
                LuaValue::String(s) if s.to_str()? == "in" => Some(None),
                other => Some(Some(from_lua::<Id>(lua, other)?)),
            };
            sh.session.borrow_mut().doc.graph_tap(device, from).lua()
        }

        // --- linked racks ---

        // Make a split the first instance of a new linked rack named `name`.
        // Gives the id of the rack's definition.
        // @return integer
        fn rack_define(_, sh, (split, name) => (Id, Option<String>)) {
            sh.session.borrow_mut().doc.rack_define(split, name.as_deref().unwrap_or("")).lua()
        }
        // Put a new instance of a linked rack in a graph, at a place as
        // `graph_move` takes it. Gives the instance's id.
        // @param to types.GraphPlace
        // @return integer
        fn rack_place(lua, sh, (rack, to) => (Id, LuaValue)) {
            let to = place(lua, to)?;
            sh.session.borrow_mut().doc.rack_place(rack, &to).lua()
        }
        // Change the definition of a linked rack to what the instance `split` is
        // now: each other instance follows it, and keeps its overrides.
        // @return nil
        fn rack_apply(_, sh, split => Id) { sh.session.borrow_mut().doc.rack_apply(split).lua() }
        // Give an instance each value of its definition. Gives how many
        // overrides went.
        // @return integer
        fn rack_reset(_, sh, split => Id) { sh.session.borrow_mut().doc.rack_reset(split).lua() }
        // Turn an instance into a copy that follows no definition.
        // @return nil
        fn rack_unlink(_, sh, split => Id) { sh.session.borrow_mut().doc.rack_unlink(split).lua() }
        // Change a value of a definition, by its key (`"<id>.gain"`,
        // `"<id>.params.<key>"`, with an id of the definition), in each
        // instance that does not override it.
        // @param value number | boolean | types.Meta
        // @return nil
        fn rack_set(lua, sh, (rack, key, value) => (Id, String, LuaValue)) {
            let value: serde_json::Value = from_lua(lua, value)?;
            sh.session.borrow_mut().doc.rack_set(rack, &key, value).lua()
        }
        // The keys of the values that an instance overrides.
        // @return {string}
        fn rack_overrides(_, sh, split => Id) { sh.session.borrow().doc.project.rack_overrides(split).lua() }
        // The definitions of the linked racks of the project.
        // @return {types.RackDef}
        fn rack_list(lua, sh, () => ()) {
            let session = sh.session.borrow();
            let list: Vec<_> = session
                .doc
                .project
                .racks
                .iter()
                .map(|r| json!({ "id": r.id, "name": r.name, "split": r.split }))
                .collect();
            to_lua(lua, &list)
        }
    }
    Ok(())
}
