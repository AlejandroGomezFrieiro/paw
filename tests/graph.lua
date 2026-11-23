-- The devices graph of a track through paw.graph: each edit says what it
-- did and is one undo step, and a refused edit says why. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, keys = T.test, T.eq, T.keys
local api = paw.api

--- A track with three gain devices, in normal mode; the undo history
--- starts after them.
local function track()
  T.start()
  local t = paw.add_track({ name = "Bus" })
  local ids = {}
  for _ = 1, 3 do
    ids[#ids + 1] = t:add_device("gain").id
  end
  api.undo_checkpoint()
  return t, ids
end

local function order(t) return table.concat(api.track_get(t.id).devices, " ") end

test("a wrap in a layer split says what it did, and u takes the graph away", function()
  local t, d = track()
  eq(paw.graph.get(t.id), nil, "a new track plays its devices in series, with no graph")
  local done = paw.graph.wrap({ d[2], d[3] }, "layer")
  eq(
    done.message,
    "wrapped 2 nodes in a layer split; it plays its branches in series until the engine runs graphs",
    "the message"
  )
  eq(paw.ui.message.text, done.message, "on the message line")
  local split = paw.graph.find(paw.graph.get(t.id), done.id).split
  eq(#split.branches, 2, "a layer split starts with two branches")
  keys("u")
  eq(paw.graph.get(t.id), nil, "one u: no graph again")
  eq(order(t), table.concat(d, " "), "and the devices in their order")
end)

test("a refused graph edit says why and changes nothing", function()
  local t, d = track()
  local split = paw.graph.wrap({ d[2], d[3] }, "band").id
  api.undo_checkpoint()
  local before = paw.graph.get(t.id)
  T.fails(
    function() paw.graph.set(split, { values = { xover = { 2000, 120 } } }) end,
    "the crossovers of a band split go from low to high: 120 Hz comes after 2000 Hz",
    "crossovers out of order"
  )
  T.fails(
    function() paw.graph.tap(d[1], d[3]) end,
    "takes its key from node %d+, which comes later in the signal",
    "a tap to a later node"
  )
  eq(paw.graph.get(t.id), before, "the graph is as it was")
end)

test("a linked rack: a change reaches each instance, and an override stays", function()
  local t, d = track()
  local first = paw.graph.wrap({ d[1] }, "chain").id
  local rack = paw.graph.link_rack(first, "Glue").id
  local second = paw.graph.place_rack(rack, { after = first }).id
  local copy = paw.graph.find(paw.graph.get(t.id), second).split.branches[1].nodes[1].device
  api.device_set_param(copy, "gain", 4)
  local key = paw.graph.racks()[1].split.branches[1].nodes[1].device .. ".params.gain"
  api.undo_checkpoint()
  paw.graph.set_rack(rack, key, -3)
  eq(api.device_get(d[1]).params.gain, -3, "the first instance follows the rack")
  eq(api.device_get(copy).params.gain, 4, "the override stays")
  eq(paw.graph.overrides(second), { key }, "and the instance names it")
  keys("u")
  eq(api.device_get(d[1]).params.gain, 0, "one u")
end)
