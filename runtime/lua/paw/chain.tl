-- The chain of an owner's devices: splits and branches that give the
-- devices a shape. The kernel keeps it (crates/paw-core/src/model/chain.rs)
-- beside the flat list of devices; this module reads it and makes each
-- edit as one undo step that says what it did.
--
--   local c = paw.chain.of({ part = 3 })    -- the handle of a part's chain
--   paw.chain.get(c)                         -- the chain, or nil: in series
--   paw.chain.wrap(c, { comp, eq }, "layer") -- a new split around them
--   paw.chain.set(c, branch, { gain = -6 })
--
-- The engine plays the chain: a split sends its input into each branch and
-- sums them again. A split of a kind that the engine does not play (`outs`,
-- or a kind that no loaded extension defines) plays its first branch.
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local registry = require("paw.registry")
local type types = require("paw.types")

local record Chain
  --- What shows the message of each edit. paw.chain is below the screen
  --- (tools/layers.txt): paw/init.lua sets this to `paw.notify`.
  say: function(message: string)
  --- What an edit of a chain gives back: the id it made, if any, and the
  --- message it showed.
  record Done
    id: integer
    message: string
  end
  --- What `paw.chain.find` gives: the split, the branch or the macro with
  --- that id, and the splits around it from the root, outermost first.
  record Found
    split: types.ChainSplit
    branch: types.ChainBranch
    macro: types.ChainMacro
    path: {types.ChainSplit}
  end
end

Chain.say = function(_: string) end

--- The handle of the chain of `owner`, which each other function of
--- paw.chain takes: `{ part = id }` for the chain of a part. An error
--- when the owner is not in the project.
function Chain.of(owner: types.ChainOwner): types.ChainOwner
  api.chain_get(owner)
  return {part = owner.part}
end

--- The chain of the owner `h`, or nil when it has none: then its devices
--- play in series, in the order of the owner's list.
function Chain.get(h: types.ChainOwner): types.Chain
  return api.chain_get(h)
end

--- The names of the kinds of split: `chain`, `layer`, `band`, `ms`, `lr`,
--- `key`, `vel`, `select`, `outs`, and the kinds that extensions defined.
function Chain.kinds(): {string}
  return api.chain_kinds()
end

--- The meters of the chain of `h`, as the engine measured them last:
--- `latency`, the latency of the chain in ms; `peaks`, the peak of each
--- device, split and branch by its id (linear, falling as a meter of a
--- part falls); `time`, the nanoseconds that each device ran since the
--- engine started.
function Chain.meters(h: types.ChainOwner): types.ChainMeters
  return api.chain_meters(h)
end

--- Let a chain have a split of a new kind, for an extension: `spec` gives
--- the fewest (`min`) and the most (`max`) branches, and how many a new
--- split of the kind gets (`first`). The name is words joined by dots,
--- such as `drums.transient`. A kind of paw cannot be defined again.
function Chain.define_kind(name: string, spec: types.SplitKindSpec)
  api.chain_kind_define(name, spec, registry.owner and registry.owner())
end

--- The split, the branch or the macro with the id `id` in `chain`, and
--- the splits around it. Nil when the chain does not have it.
function Chain.find(chain: types.Chain, id: integer): Chain.Found
  local function walk(split: types.ChainSplit, path: {types.ChainSplit}): Chain.Found
    local here = {table.unpack(path)}
    here[#here + 1] = split
    if split.id == id then
      return {split = split, path = path}
    end
    for _, m in ipairs(split.macros or {}) do
      if m.id == id then
        return {macro = m, path = here}
      end
    end
    for _, b in ipairs(split.branches) do
      if b.id == id then
        return {branch = b, path = here}
      end
      for _, n in ipairs(b.nodes) do
        if n.split then
          local found = walk(n.split, here)
          if found then
            return found
          end
        end
      end
    end
    return nil
  end
  return walk(chain.root, {})
end

--- The name of a node of the chain of `h` in a message: a device's name, a
--- split's name or its kind.
local function name_of(h: types.ChainOwner, id: integer): string
  local ok, device = pcall(api.device_get, id) as (boolean, types.Device)
  if ok and device then
    return device.name or device.kind
  end
  local chain = api.chain_get(h)
  local found = chain and Chain.find(chain, id)
  if found and found.split then
    local s = found.split
    if s.name and s.name ~= "" then
      return s.name
    end
    return s.kind .. " split"
  elseif found and found.branch then
    local b = found.branch
    return (b.name and b.name ~= "") and ("branch " .. b.name) or "a branch"
  elseif found and found.macro then
    return "macro " .. found.macro.name
  end
  return tostring(id)
end

--- Show the message of an edit, and give it with the id it made.
local function done(message: string, id?: integer): Chain.Done
  Chain.say(message)
  return {id = id, message = message}
end

--- A note on a split that the engine does not play yet.
local function series(kind: string): string
  if kind == "outs" then
    return "; it plays its first branch until the engine plays outs splits"
  end
  return ""
end

--- Wrap the nodes `nodes` (devices or splits in a row of one branch) of
--- the chain of `h` in a new split of `kind`, as one undo step. They go
--- into its first branch. `opts.branches` gives how many branches (the
--- kind's first count when nil), `opts.name` its name, `opts.values`
--- values of its kind (`{ xover = { 120, 2000 } }` for a band split).
function Chain.wrap(h: types.ChainOwner, nodes: {integer}, kind: string, opts?: types.ChainWrapOptions): Chain.Done
  local id = api.chain_wrap(h, nodes, kind, opts)
  local word = #nodes == 1 and name_of(h, nodes[1]) or (#nodes .. " nodes")
  return done(string.format("wrapped %s in a %s split%s", word, kind, series(kind)), id)
end

--- Take the split `split` away, as one undo step. With `keep` (a branch
--- of it), that branch takes its place and the devices of the other
--- branches leave the owner; without, its branches go in its place one
--- after the other.
function Chain.unwrap(h: types.ChainOwner, split: integer, keep?: integer): Chain.Done
  local name = name_of(h, split)
  local gone = api.chain_unwrap(h, split, keep)
  local message = "unwrapped " .. name
  if gone > 0 then
    message = message .. string.format(", removed %d device%s", gone, gone == 1 and "" or "s")
  end
  return done(message)
end

--- Add an empty branch to the split `split`, as one undo step:
--- `opts.name`, and `opts.index` (from 1; the end when nil).
function Chain.add_branch(h: types.ChainOwner, split: integer, opts?: types.ChainBranchOptions): Chain.Done
  local id = api.chain_branch_add(h, split, opts)
  return done("added a branch to " .. name_of(h, split), id)
end

--- Move the node `id` in its chain, as one undo step: `{ before = id }`,
--- `{ after = id }` or `{ branch = id, index = n }` (from 1).
function Chain.move(h: types.ChainOwner, id: integer, place: types.ChainPlace): Chain.Done
  api.chain_move(h, id, place)
  local to = place.before and ("before " .. name_of(h, place.before))
    or place.after and ("after " .. name_of(h, place.after))
    or ("into " .. name_of(h, place.branch))
  return done(string.format("moved %s %s", name_of(h, id), to))
end

--- Remove what `id` names, as one undo step: a split or a branch with its
--- devices, a macro with its links, or a device.
function Chain.remove(h: types.ChainOwner, id: integer): Chain.Done
  local name = name_of(h, id)
  api.chain_remove(h, id)
  return done("removed " .. name)
end

--- The words of a patch in a message: `gain -6, pan 0.2`.
local function patch_words(patch: types.ChainPatch): string
  local words: {string} = {}
  local function say(key: string, value: string | number | boolean)
    if value ~= nil then
      words[#words + 1] = key .. " " .. tostring(value)
    end
  end
  say("name", patch.name)
  say("kind", patch.kind)
  say("mix", patch.mix)
  say("gain", patch.gain)
  say("pan", patch.pan)
  say("mute", patch.mute)
  say("solo", patch.solo)
  say("value", patch.value)
  if patch.values then
    words[#words + 1] = "values"
  end
  if patch.zone then
    words[#words + 1] = string.format("zone %d-%d", patch.zone.low, patch.zone.high)
  end
  return table.concat(words, ", ")
end

--- Change a split (`name`, `mix`, `gain`, `kind`, `values`), a branch
--- (`name`, `gain`, `pan`, `mute`, `solo`, `zone`) or a macro (`name`,
--- `value`), as one undo step. A new `kind` keeps the branches.
function Chain.set(h: types.ChainOwner, id: integer, patch: types.ChainPatch): Chain.Done
  api.chain_set(h, id, patch)
  return done(string.format("set %s of %s", patch_words(patch), name_of(h, id)))
end

--- Add a macro named `name` to the split `split`, as one undo step.
function Chain.add_macro(h: types.ChainOwner, split: integer, name: string): Chain.Done
  local id = api.chain_macro_add(h, split, name)
  return done(string.format("added the macro %s to %s", name, name_of(h, split)), id)
end

--- Link the macro `macro` to the parameter `param` of `device` in its
--- split, with `depth` from -1 to 1; a nil depth removes the link. One
--- undo step.
function Chain.link(h: types.ChainOwner, macro: integer, device: integer, param: string, depth?: number): Chain.Done
  api.chain_link(h, macro, device, param, depth)
  if depth == nil then
    return done(string.format("unlinked %s from %s.%s", name_of(h, macro), name_of(h, device), param))
  end
  return done(
    string.format(
      "linked %s to %s.%s at %d %%", name_of(h, macro), name_of(h, device), param, math.floor(depth * 100 + 0.5)
    )
  )
end

--- Let `device` take its key from the node `from` of its chain, from
--- `"in"` (the input of the chain), or (nil) from no node of the chain.
--- One undo step.
function Chain.tap(h: types.ChainOwner, device: integer, from: integer | string): Chain.Done
  api.chain_tap(h, device, from)
  if from == nil then
    return done(name_of(h, device) .. " takes its key from no node")
  end
  local source = from == "in" and "the input" or name_of(h, from as integer)
  return done(string.format("%s takes its key from %s", name_of(h, device), source))
end

--- Make the split `split` the first instance of a new linked rack named
--- `name`: a change of the rack in one instance reaches the others.
function Chain.link_rack(h: types.ChainOwner, split: integer, name?: string): Chain.Done
  local id = api.rack_define(h, split, name)
  return done(string.format("linked rack %s: 1 instance", name or name_of(h, split)), id)
end

--- Put a new instance of the linked rack `rack` at `place` in the chain
--- of `h` (as `paw.chain.move` takes it).
function Chain.place_rack(h: types.ChainOwner, rack: integer, place: types.ChainPlace): Chain.Done
  local id = api.rack_place(h, rack, place)
  return done("placed an instance of " .. name_of(h, id), id)
end

--- Change the linked rack to what the instance `split` is now: each other
--- instance follows, and keeps its own values.
function Chain.apply_rack(h: types.ChainOwner, split: integer): Chain.Done
  api.rack_apply(h, split)
  return done("the linked rack is now as " .. name_of(h, split))
end

--- Give the instance `split` each value of its linked rack.
function Chain.reset_rack(h: types.ChainOwner, split: integer): Chain.Done
  local count = api.rack_reset(h, split)
  return done(string.format("%s: removed %d override%s", name_of(h, split), count, count == 1 and "" or "s"))
end

--- Turn the instance `split` into a copy that follows no linked rack.
function Chain.unlink_rack(h: types.ChainOwner, split: integer): Chain.Done
  api.rack_unlink(h, split)
  return done(name_of(h, split) .. " is a copy now, not linked")
end

--- Change a value of the linked rack `rack` by its key, in each instance
--- that does not override it. The key is a reference of the chain
--- language with an id of the rack's definition: `"#<id>.gain"` for a
--- split, a branch or a macro, `"#<id>.<param>"` for a parameter of a
--- device.
function Chain.set_rack(rack: integer, key: string, value: number | boolean): Chain.Done
  api.rack_set(rack, key, value)
  return done(string.format("set %s of the linked rack", key))
end

--- The keys of the values that the instance `split` overrides, as
--- `paw.chain.set_rack` takes them.
function Chain.overrides(h: types.ChainOwner, split: integer): {string}
  return api.rack_overrides(h, split)
end

--- The linked racks of the project.
function Chain.racks(): {types.RackDef}
  return api.rack_list()
end

return Chain
