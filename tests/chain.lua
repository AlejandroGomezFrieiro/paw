-- The chain of a part through paw.chain: each edit says what it did and
-- is one undo step, and a refused edit says why. Loaded by tests/suite.lua
-- with its helpers.
local T = ...
local test, eq, keys = T.test, T.eq, T.keys
local api = paw.api

--- A part with three gain devices, in normal mode, and the handle of its
--- chain; the undo history starts after them.
local function part()
  T.start()
  local t = paw.add_part({ name = "Bus" })
  local ids = {}
  for _ = 1, 3 do
    ids[#ids + 1] = t:add_device("gain").id
  end
  api.undo_checkpoint()
  return t, ids, paw.chain.of({ part = t.id })
end

local function order(t) return table.concat(api.part_get(t.id).devices, " ") end

test("a wrap in a layer split says what it did, and u takes the chain away", function()
  local t, d, h = part()
  eq(paw.chain.get(h), nil, "a new part plays its devices in series, with no chain")
  local done = paw.chain.wrap(h, { d[2], d[3] }, "layer")
  eq(done.message, "wrapped 2 nodes in a layer split", "the message")
  eq(paw.ui.message.text, done.message, "on the message line")
  local split = paw.chain.find(paw.chain.get(h), done.id).split
  eq(#split.branches, 2, "a layer split starts with two branches")
  keys("u")
  eq(paw.chain.get(h), nil, "one u: no chain again")
  eq(order(t), table.concat(d, " "), "and the devices in their order")
end)

test("a refused chain edit says why and changes nothing", function()
  local _, d, h = part()
  local split = paw.chain.wrap(h, { d[2], d[3] }, "band").id
  api.undo_checkpoint()
  local before = paw.chain.get(h)
  T.fails(
    function() paw.chain.set(h, split, { values = { xover = { 2000, 120 } } }) end,
    "the crossovers of a band split go from low to high: 120 Hz comes after 2000 Hz",
    "crossovers out of order"
  )
  T.fails(
    function() paw.chain.tap(h, d[1], d[3]) end,
    "takes its key from node %d+, which comes later in the signal",
    "a tap to a later node"
  )
  T.fails(function() paw.chain.of({ part = 999 }) end, "no part 999", "an owner that is not in the project")
  eq(paw.chain.get(h), before, "the chain is as it was")
end)

test("a linked rack: a change reaches each instance, and an override stays", function()
  local _, d, h = part()
  local first = paw.chain.wrap(h, { d[1] }, "chain").id
  local rack = paw.chain.link_rack(h, first, "Glue").id
  local second = paw.chain.place_rack(h, rack, { after = first }).id
  local copy = paw.chain.find(paw.chain.get(h), second).split.branches[1].nodes[1].device
  api.device_set_param(copy, "gain", 4)
  local key = "#" .. paw.chain.racks()[1].split.branches[1].nodes[1].device .. ".gain"
  api.undo_checkpoint()
  paw.chain.set_rack(rack, key, -3)
  eq(api.device_get(d[1]).params.gain, -3, "the first instance follows the rack")
  eq(api.device_get(copy).params.gain, 4, "the override stays")
  eq(paw.chain.overrides(h, second), { key }, "and the instance names it")
  keys("u")
  eq(api.device_get(d[1]).params.gain, 0, "one u")
end)
