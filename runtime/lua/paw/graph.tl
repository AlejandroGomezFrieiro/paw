-- The devices graph of a track: splits and branches that give the track's
-- devices a shape. The kernel keeps it (crates/paw-core/src/model/graph.rs)
-- beside the flat list of devices; this module reads it and makes each
-- edit as one undo step that says what it did.
--
--   paw.graph.get(track)                     -- the graph, or nil: in series
--   paw.graph.wrap({ comp, eq }, "layer")    -- a new split around them
--   paw.graph.set(branch, { gain = -6 })
--
-- Until the engine runs a graph, it plays the devices in the graph's signal
-- order, in series. Written in Teal (paw/lang.tl): the build compiles it to
-- Lua.
local api = require("paw.api")
local type types = require("paw.types")

local record Graph
  --- What shows the message of each edit. paw.graph is below the screen
  --- (tools/layers.txt): paw/init.lua sets this to `paw.notify`.
  say: function(message: string)
  --- What a graph edit gives back: the id it made, if any, and the message
  --- it showed.
  record Done
    id: integer
    message: string
  end
  --- What `paw.graph.find` gives: the split, the branch or the macro with
  --- that id, and the splits around it from the root, outermost first.
  record Found
    split: types.GraphSplit
    branch: types.GraphBranch
    macro: types.GraphMacro
    path: {types.GraphSplit}
  end
end

Graph.say = function(_: string) end

--- The graph of the track `track`, or nil when it has none: then its
--- devices play in series, in the order of the track's list.
function Graph.get(track: integer): types.Graph
  return api.graph_get(track)
end

--- The words of the kinds of split: `chain`, `layer`, `band`, `ms`, `lr`,
--- `key`, `vel`, `select`, `outs`, and the kinds that extensions defined.
function Graph.kinds(): {string}
  return api.graph_kinds()
end

--- Let a graph have a split of a new kind, for an extension: `spec`
--- gives the fewest (`min`) and the most (`max`) branches, and how many a
--- new split of the kind gets (`first`).
function Graph.define_kind(word: string, spec: types.GraphKindSpec)
  api.graph_kind_define(word, spec)
end

--- The split, the branch or the macro with the id `id` in `graph`, and
--- the splits around it. Nil when the graph does not have it.
function Graph.find(graph: types.Graph, id: integer): Graph.Found
  local function walk(split: types.GraphSplit, path: {types.GraphSplit}): Graph.Found
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
  return walk(graph.root, {})
end

--- The name of a node in a message: a device's name, a split's name or
--- its kind.
local function name_of(id: integer): string
  local ok, device = pcall(api.device_get, id) as (boolean, types.Device)
  if ok and device then
    return device.name or device.kind
  end
  local tracks = api.track_list()
  tracks[#tracks + 1] = 0 -- the master track
  for _, t in ipairs(tracks) do
    local g = api.graph_get(t)
    local found = g and Graph.find(g, id)
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
  end
  return tostring(id)
end

--- Show the message of an edit, and give it with the id it made.
local function done(message: string, id?: integer): Graph.Done
  Graph.say(message)
  return {id = id, message = message}
end

--- A note on a split that the engine does not run yet.
local function series(kind: string): string
  if kind == "chain" then
    return ""
  end
  return "; it plays its branches in series until the engine runs graphs"
end

--- Wrap the nodes `nodes` (devices or splits in a row of one branch) in a
--- new split of `kind`, as one undo step. They go into its first branch.
--- `opts.branches` gives how many branches (the kind's first count when
--- nil), `opts.name` its name, `opts.values` values of its kind
--- (`{ xover = { 120, 2000 } }` for a band split).
function Graph.wrap(nodes: {integer}, kind: string, opts?: types.GraphWrapOptions): Graph.Done
  local id = api.graph_wrap(nodes, kind, opts)
  local word = #nodes == 1 and name_of(nodes[1]) or (#nodes .. " nodes")
  return done(string.format("wrapped %s in a %s split%s", word, kind, series(kind)), id)
end

--- Take the split `split` away, as one undo step. With `keep` (a branch
--- of it), that branch takes its place and the devices of the other
--- branches leave the track; without, its branches go in its place one
--- after the other.
function Graph.unwrap(split: integer, keep?: integer): Graph.Done
  local name = name_of(split)
  local gone = api.graph_unwrap(split, keep)
  local message = "unwrapped " .. name
  if gone > 0 then
    message = message .. string.format(", removed %d device%s", gone, gone == 1 and "" or "s")
  end
  return done(message)
end

--- Add an empty branch to the split `split`, as one undo step:
--- `opts.name`, and `opts.index` (from 1; the end when nil).
function Graph.add_branch(split: integer, opts?: types.GraphBranchOptions): Graph.Done
  local id = api.graph_branch_add(split, opts)
  return done("added a branch to " .. name_of(split), id)
end

--- Move the node `id` in its graph, as one undo step: `{ before = id }`,
--- `{ after = id }` or `{ branch = id, index = n }` (from 1).
function Graph.move(id: integer, place: types.GraphPlace): Graph.Done
  api.graph_move(id, place)
  local to = place.before and ("before " .. name_of(place.before))
    or place.after and ("after " .. name_of(place.after))
    or ("into " .. name_of(place.branch))
  return done(string.format("moved %s %s", name_of(id), to))
end

--- Remove what `id` names, as one undo step: a split or a branch with its
--- devices, a macro with its links, or a device.
function Graph.remove(id: integer): Graph.Done
  local name = name_of(id)
  api.graph_remove(id)
  return done("removed " .. name)
end

--- The words of a patch in a message: `gain -6, pan 0.2`.
local function patch_words(patch: types.GraphPatch): string
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
  if patch.meta then
    words[#words + 1] = "meta"
  end
  return table.concat(words, ", ")
end

--- Change a split (`name`, `mix`, `gain`, `kind`, `values`, `meta`), a
--- branch (`name`, `gain`, `pan`, `mute`, `solo`, `zone`) or a macro
--- (`name`, `value`), as one undo step. A new `kind` keeps the branches.
function Graph.set(id: integer, patch: types.GraphPatch): Graph.Done
  api.graph_set(id, patch)
  return done(string.format("set %s of %s", patch_words(patch), name_of(id)))
end

--- Add a macro named `name` to the split `split`, as one undo step.
function Graph.add_macro(split: integer, name: string): Graph.Done
  local id = api.graph_macro_add(split, name)
  return done(string.format("added the macro %s to %s", name, name_of(split)), id)
end

--- Link the macro `macro` to the parameter `param` of `device` in its
--- split, with `depth` from -1 to 1; a nil depth removes the link. One
--- undo step.
function Graph.link(macro: integer, device: integer, param: string, depth?: number): Graph.Done
  api.graph_link(macro, device, param, depth)
  if depth == nil then
    return done(string.format("unlinked %s from %s.%s", name_of(macro), name_of(device), param))
  end
  return done(
    string.format("linked %s to %s.%s at %d %%", name_of(macro), name_of(device), param, math.floor(depth * 100 + 0.5))
  )
end

--- Let `device` take its key from the node `from` of its graph, from
--- `"in"` (the input of the graph), or (nil) from no node of the graph.
--- One undo step.
function Graph.tap(device: integer, from: integer | string): Graph.Done
  api.graph_tap(device, from)
  if from == nil then
    return done(name_of(device) .. " takes its key from no node")
  end
  local source = from == "in" and "the input" or name_of(from as integer)
  return done(string.format("%s takes its key from %s", name_of(device), source))
end

--- Make the split `split` the first instance of a new linked rack named
--- `name`: a change of the rack in one instance reaches the others.
function Graph.link_rack(split: integer, name?: string): Graph.Done
  local id = api.rack_define(split, name)
  return done(string.format("linked rack %s: 1 instance", name or name_of(split)), id)
end

--- Put a new instance of the linked rack `rack` at `place` (as
--- `paw.graph.move` takes it).
function Graph.place_rack(rack: integer, place: types.GraphPlace): Graph.Done
  local id = api.rack_place(rack, place)
  return done("placed an instance of " .. name_of(id), id)
end

--- Change the linked rack to what the instance `split` is now: each other
--- instance follows, and keeps its own values.
function Graph.apply_rack(split: integer): Graph.Done
  api.rack_apply(split)
  return done("the linked rack is now as " .. name_of(split))
end

--- Give the instance `split` each value of its linked rack.
function Graph.reset_rack(split: integer): Graph.Done
  local count = api.rack_reset(split)
  return done(string.format("%s: removed %d override%s", name_of(split), count, count == 1 and "" or "s"))
end

--- Turn the instance `split` into a copy that follows no linked rack.
function Graph.unlink_rack(split: integer): Graph.Done
  api.rack_unlink(split)
  return done(name_of(split) .. " is a copy now, not linked")
end

--- Change a value of the linked rack `rack` by its key (`"<id>.gain"`,
--- `"<id>.params.<key>"`, with an id of the rack's definition), in each
--- instance that does not override it.
function Graph.set_rack(rack: integer, key: string, value: number | boolean): Graph.Done
  api.rack_set(rack, key, value)
  return done(string.format("set %s of the linked rack", key))
end

--- The keys of the values that the instance `split` overrides.
function Graph.overrides(split: integer): {string}
  return api.rack_overrides(split)
end

--- The linked racks of the project.
function Graph.racks(): {types.RackDef}
  return api.rack_list()
end

return Graph
