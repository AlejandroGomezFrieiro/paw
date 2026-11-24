//! `paw.api`: the chain of an owner and linked racks (`model/chain.rs`,
//! `model/racks.rs`). `paw.chain` (paw/chain.tl) is the typed module over
//! these. Each function of a chain takes its owner's handle
//! (`{ part = id }`), as `paw.chain.of` gives it.

#![expect(
    clippy::too_many_lines,
    reason = "debt: pay down"
)]

use std::rc::Rc;

use mlua::{Lua, Table, Value as LuaValue};
use serde::Deserialize;
use serde_json::json;

use crate::model::Id;
use crate::model::chain::KindSpec;
use crate::model::chain::edit::KeyFrom;
use crate::model::ids::{DefId, NodeId};
use crate::model::owner::OwnerRef;
use crate::session::{Place, WrapOpts};

use super::{LuaResult, Shared, changes, from_lua, options, to_lua};

/// The owner that a handle names.
fn owner_of(lua: &Lua, value: LuaValue) -> mlua::Result<OwnerRef> {
    from_lua(lua, value).map_err(|_| mlua::Error::runtime("the owner of a chain is { part = id }"))
}

/// A place as Lua gives it: an `index` counts from 1.
fn place(lua: &Lua, value: LuaValue) -> mlua::Result<Place> {
    let mut place: Place = from_lua(lua, value)?;
    place.index = place.index.map(|i| i.saturating_sub(1));
    Ok(place)
}

fn node(id: Id) -> NodeId {
    NodeId::new(id)
}

/// What `chain_branch_add` takes.
#[derive(Default, Deserialize)]
struct BranchOpts {
    name: Option<String>,
    /// From 1; the end when not given.
    index: Option<usize>,
}

pub(super) fn install(lua: &Lua, api: &Table, shared: &Rc<Shared>) -> mlua::Result<()> {
    define! { lua, api, shared;
        // --- the chain of an owner ---

        // The chain of an owner's devices, or nil when it has none (its
        // devices play in series, in the order of `part.devices`).
        // @param owner types.ChainOwner
        // @return types.Chain
        fn chain_get(lua, sh, owner => LuaValue) {
            let owner = owner_of(lua, owner)?;
            let session = sh.session.borrow();
            let t = session.doc.project.owner(owner).ok_or_else(|| mlua::Error::runtime(format!("no {owner}")))?;
            match &t.chain {
                Some(chain) => to_lua(lua, &**chain),
                None => Ok(LuaValue::Nil),
            }
        }
        // The names of the kinds of split: the built-in kinds first, then the
        // kinds that extensions defined.
        // @return {string}
        fn chain_kinds(_, sh, () => ()) { Ok(sh.session.borrow().doc.chain_kinds()) }
        // Let a chain have a split of a new kind, of the extension `by` (the
        // user's when nil): `spec` gives the fewest (`min`) and the most
        // (`max`) branches, and how many a new split gets (`first`).
        // @param spec types.SplitKindSpec
        // @return nil
        fn chain_kind_define(lua, sh, (name, spec, by) => (String, LuaValue, Option<String>)) {
            let spec: KindSpec = from_lua(lua, spec)?;
            sh.session.borrow_mut().doc.chain_kind_define(&name, spec, by.as_deref()).lua()
        }
        // Take away the kinds of split that the extension `by` defined, as
        // it unloads: a split of such a kind stays, absent, with its values.
        // Gives how many kinds went.
        // @return integer
        fn chain_kinds_unload(_, sh, by => String) { Ok(sh.session.borrow_mut().doc.chain_kinds_unload(&by)) }
        // Wrap nodes (devices or splits in a row of one branch) in a new split
        // of `kind`, as one undo step. They go into its first branch. Gives
        // the split's id.
        // @param owner types.ChainOwner
        // @param opts? types.ChainWrapOptions
        // @return integer
        fn chain_wrap(lua, sh, (owner, nodes, kind, opts) => (LuaValue, Vec<Id>, String, LuaValue)) {
            let owner = owner_of(lua, owner)?;
            let opts: WrapOpts = options(lua, opts)?;
            let nodes: Vec<NodeId> = nodes.into_iter().map(node).collect();
            sh.session.borrow_mut().doc.chain_wrap(owner, &nodes, &kind, opts).map(NodeId::get).lua()
        }
        // Take a split away, as one undo step. With `keep` (a branch of it),
        // that branch takes its place and the devices of the others leave the
        // owner; without, its branches go in its place one after the other.
        // Gives how many devices left the owner.
        // @param owner types.ChainOwner
        // @return integer
        fn chain_unwrap(lua, sh, (owner, split, keep) => (LuaValue, Id, Option<Id>)) {
            let owner = owner_of(lua, owner)?;
            sh.session.borrow_mut().doc.chain_unwrap(owner, node(split), keep.map(node)).lua()
        }
        // Add an empty branch to a split, as one undo step: `{ name =, index = }`
        // (from 1; the end when not given). Gives its id.
        // @param owner types.ChainOwner
        // @param opts? types.ChainBranchOptions
        // @return integer
        fn chain_branch_add(lua, sh, (owner, split, opts) => (LuaValue, Id, LuaValue)) {
            let owner = owner_of(lua, owner)?;
            let opts: BranchOpts = options(lua, opts)?;
            let index = opts.index.map(|i| i.saturating_sub(1));
            sh.session.borrow_mut().doc.chain_branch_add(owner, node(split), opts.name, index).map(NodeId::get).lua()
        }
        // Move a node in its chain, as one undo step: `{ before = id }`,
        // `{ after = id }` or `{ branch = id, index = n }` (from 1).
        // @param owner types.ChainOwner
        // @param to types.ChainPlace
        // @return nil
        fn chain_move(lua, sh, (owner, id, to) => (LuaValue, Id, LuaValue)) {
            let owner = owner_of(lua, owner)?;
            let to = place(lua, to)?;
            sh.session.borrow_mut().doc.chain_move(owner, node(id), &to).lua()
        }
        // Remove a split or a branch with its devices, a macro with its links,
        // or a device, as one undo step.
        // @param owner types.ChainOwner
        // @return nil
        fn chain_remove(lua, sh, (owner, id) => (LuaValue, Id)) {
            let owner = owner_of(lua, owner)?;
            sh.session.borrow_mut().doc.chain_remove(owner, node(id)).lua()
        }
        // Change a split (`name`, `mix`, `gain`, `kind`, `values`), a branch
        // (`name`, `gain`, `pan`, `mute`, `solo`, `zone`) or a macro (`name`,
        // `value`): a table of the entries to change, or one `key` and its
        // value. One undo step.
        // @type function(owner: types.ChainOwner, id: integer, patch: types.ChainPatch)
        // @type function(owner: types.ChainOwner, id: integer, key: string, value: nil)
        fn chain_set(lua, sh, (owner, id, key, value) => (LuaValue, Id, LuaValue, LuaValue)) {
            let owner = owner_of(lua, owner)?;
            let mut session = sh.session.borrow_mut();
            let changes = changes(lua, key, value)?
                .into_iter()
                .map(|(key, value)| Ok((key, from_lua::<serde_json::Value>(lua, value)?)))
                .collect::<mlua::Result<Vec<_>>>()?;
            for (key, value) in changes {
                session.doc.chain_set(owner, node(id), &key, value).lua()?;
            }
            Ok(())
        }
        // Add a macro to a split, as one undo step. Gives its id.
        // @param owner types.ChainOwner
        // @return integer
        fn chain_macro_add(lua, sh, (owner, split, name) => (LuaValue, Id, String)) {
            let owner = owner_of(lua, owner)?;
            sh.session.borrow_mut().doc.chain_macro_add(owner, node(split), &name).map(NodeId::get).lua()
        }
        // Link a macro to a parameter of a device in its split, with a depth
        // from -1 to 1; no depth removes the link. One undo step.
        // @param owner types.ChainOwner
        // @return nil
        fn chain_link(lua, sh, (owner, source, device, param, depth) => (LuaValue, Id, Id, String, Option<f64>)) {
            let owner = owner_of(lua, owner)?;
            sh.session.borrow_mut().doc.chain_link(owner, node(source), device.into(), &param, depth).lua()
        }
        // Let a device take its key from a node of its chain that comes before
        // it, from `"in"` (the input of the chain), or (nil) from no node of
        // the chain. One undo step.
        // @param owner types.ChainOwner
        // @param from integer | string
        // @return nil
        fn chain_tap(lua, sh, (owner, device, from) => (LuaValue, Id, LuaValue)) {
            let owner = owner_of(lua, owner)?;
            let from = match from {
                LuaValue::Nil => None,
                LuaValue::String(s) if s.to_str()? == "in" => Some(KeyFrom::Input),
                other => Some(KeyFrom::Node(node(from_lua::<Id>(lua, other)?))),
            };
            sh.session.borrow_mut().doc.chain_tap(owner, device.into(), from).lua()
        }

        // --- linked racks ---

        // Make a split the first instance of a new linked rack named `name`.
        // Gives the id of the rack's definition.
        // @param owner types.ChainOwner
        // @return integer
        fn rack_define(lua, sh, (owner, split, name) => (LuaValue, Id, Option<String>)) {
            let owner = owner_of(lua, owner)?;
            sh.session.borrow_mut().doc.rack_define(owner, node(split), name.as_deref().unwrap_or("")).map(DefId::get).lua()
        }
        // Put a new instance of a linked rack in a chain, at a place as
        // `chain_move` takes it. Gives the instance's id.
        // @param owner types.ChainOwner
        // @param to types.ChainPlace
        // @return integer
        fn rack_place(lua, sh, (owner, rack, to) => (LuaValue, Id, LuaValue)) {
            let owner = owner_of(lua, owner)?;
            let to = place(lua, to)?;
            sh.session.borrow_mut().doc.rack_place(owner, DefId::new(rack), &to).map(NodeId::get).lua()
        }
        // Change the definition of a linked rack to what the instance `split` is
        // now: each other instance follows it, and keeps its overrides.
        // @param owner types.ChainOwner
        // @return nil
        fn rack_apply(lua, sh, (owner, split) => (LuaValue, Id)) {
            let owner = owner_of(lua, owner)?;
            sh.session.borrow_mut().doc.rack_apply(owner, node(split)).lua()
        }
        // Give an instance each value of its definition. Gives how many
        // overrides went.
        // @param owner types.ChainOwner
        // @return integer
        fn rack_reset(lua, sh, (owner, split) => (LuaValue, Id)) {
            let owner = owner_of(lua, owner)?;
            sh.session.borrow_mut().doc.rack_reset(owner, node(split)).lua()
        }
        // Turn an instance into a copy that follows no definition.
        // @param owner types.ChainOwner
        // @return nil
        fn rack_unlink(lua, sh, (owner, split) => (LuaValue, Id)) {
            let owner = owner_of(lua, owner)?;
            sh.session.borrow_mut().doc.rack_unlink(owner, node(split)).lua()
        }
        // Change a value of a definition, by its key (`"#<id>.gain"` for a
        // split, branch or macro, `"#<id>.<param>"` for a parameter of a
        // device, with an id of the definition), in each instance that does
        // not override it.
        // @param value number | boolean | types.Meta
        // @return nil
        fn rack_set(lua, sh, (rack, key, value) => (Id, String, LuaValue)) {
            let value: serde_json::Value = from_lua(lua, value)?;
            sh.session.borrow_mut().doc.rack_set(DefId::new(rack), &key, value).lua()
        }
        // The keys of the values that an instance overrides, as `rack_set`
        // takes them (`"#<id>.gain"`, with the ids of the definition).
        // @param owner types.ChainOwner
        // @return {string}
        fn rack_overrides(lua, sh, (owner, split) => (LuaValue, Id)) {
            let owner = owner_of(lua, owner)?;
            let keys = sh.session.borrow().doc.project.rack_overrides(owner, node(split)).lua()?;
            Ok(keys.iter().map(ToString::to_string).collect::<Vec<_>>())
        }
        // The meters of the chain of an owner, as the engine measured them
        // last: `latency`, the latency of the chain in ms; `peaks`, the peak
        // of the output of each device, split and branch by its id, linear
        // and falling as a part's meter falls; `time`, the nanoseconds each
        // device has run since the engine was made.
        // @param owner types.ChainOwner
        // @return types.ChainMeters
        fn chain_meters(lua, sh, owner => LuaValue) {
            let owner = owner_of(lua, owner)?;
            let meters = sh.session.borrow().chain_meters(owner).ok_or_else(|| mlua::Error::runtime(format!("no {owner}")))?;
            to_lua(lua, &meters)
        }
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
