-- Tests of state lanes: a lane whose points each give a device one of a few
-- states (parameters, a program, a request, a whole saved state), from the
-- point on. Loaded by tests/suite.lua with its helpers. The tests with real
-- plugins are in extensions/plugstate/tests.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
  for _, id in ipairs(api.part_list()) do
    paw.lanes.open(id, false)
  end
end

local function points(lane)
  local out = {}
  for i, p in ipairs(api.lane_points(lane)) do
    out[i] = string.format("%g:%g", p[1], p[2])
  end
  return table.concat(out, " ")
end

--- The samples of a render at 16 bits, as numbers from -1 to 1, of the
--- left channel.
local function samples(info)
  local data = T.read_file(info.path)
  local at = data:find("data", 1, true) + 8
  local out = {}
  for i = at, #data - 1, 4 do
    local lo, hi = data:byte(i, i + 1)
    local v = lo + hi * 256
    if v >= 32768 then v = v - 65536 end
    out[#out + 1] = v / 32768
  end
  return out
end

local function peak(list, from, to)
  local p = 0
  for i = from + 1, to do
    p = math.max(p, math.abs(list[i] or 0))
  end
  return p
end

--- A part that holds A3 for 8 beats through a gain device, and that
--- device's state lane: `quiet` (-60 dB) and `loud` (0 dB).
local function gain_lane()
  local t = T.tone("tone", 8, "A3")
  local gain = t:add_device("gain", { gain = 0 })
  local lane = gain:automate_state()
  eq(lane:add_state({ name = "quiet", params = { gain = -60 } }), 0, "the first state")
  eq(lane:add_state({ name = "loud", params = { gain = 0 } }), 1, "the second")
  return t, gain, lane
end

test("a state lane gives its device each state from the frame of its point, in a render", function()
  start()
  local _, _, lane = gain_lane()
  lane:set_state(0, "quiet")
  lane:set_state(2, "loud")
  lane:set_state(3.37, "quiet")
  local info = T.render({ tail = 0, bits = 16 })
  local a = samples(info)
  local per = info.sample_rate * 60 / paw.tempo.at(0)
  local at = math.floor(2 * per + 0.5)
  local loud = peak(a, at + 4000, at + 4400)
  eq(loud > 0.05, true, "loud after the point")
  -- The gain device ramps to a new value over the block that starts at
  -- the point: it starts to move on the point's frame.
  eq(peak(a, at - 200, at) < loud * 0.01, true, "quiet up to the point's frame")
  eq(peak(a, at, at + 24) > loud * 0.001, true, "louder from the frame of the point")
  eq(peak(a, at + 512, at + 900) > loud * 0.9, true, "and loud within a block")
  local back = math.floor(3.37 * per + 0.5)
  eq(peak(a, back - 400, back) > loud * 0.9, true, "loud up to the next point")
  eq(peak(a, back + 2400, back + 2600) < loud * 0.01, true, "and quiet again after it")
  local b = samples(T.render({ tail = 0, bits = 16 }))
  local same = #a == #b
  for i = 1, #a, 7 do
    same = same and a[i] == b[i]
  end
  eq(same, true, "a second render is the same, sample for sample")
end)

test("a state lane keeps its states and points in the project and through undo", function()
  start()
  local t, gain, lane = gain_lane()
  api.undo_checkpoint()
  lane:set_state(4, "loud")
  api.undo_checkpoint()
  eq(points(lane.id), "4:1", "a point gives a state by its index")
  eq(table.concat(api.lane_get(lane.id).states, " "), "quiet loud", "the lane names its states")
  eq(paw.lanes.format(lane:get(), 1), "loud", "a value reads as its state")
  eq(paw.lanes.name(lane.id), "Gain › state", "the lane names its device")
  paw.undo()
  eq(points(lane.id), "", "undo takes the point back")
  paw.redo()
  eq(points(lane.id), "4:1", "redo")
  T.fails(function() lane:set_state(5, "none") end, "no state `none`", "a state the lane has not got")
  T.fails(function() lane:add_state({ name = "empty" }) end, "needs a `state`", "a state that does nothing")
  T.fails(function() lane:add_state({ name = "p", program = 200 }) end, "0 to 127", "a program out of range")
  eq(lane:add_state({ name = "loud", params = { gain = -6 } }), 1, "a state of the same name is replaced")

  local saved = {
    paw.project.save(T.scratch .. "/states.json"),
    paw.project.save(T.scratch .. "/states-folder"),
  }
  for _, path in ipairs(saved) do
    fresh()
    paw.project.load(path)
    local loaded = paw.parts()[1]:devices()[2]:state_lane()
    eq(loaded ~= nil, true, path .. ": the lane comes back")
    eq(points(loaded.id), "4:1", path .. ": its points")
    eq(loaded:states()[2].params.gain, -6, path .. ": and its states")
  end
  local _ = { t, gain }
end)

test("on a state lane's row \\s keeps the device's state at the cursor, c chooses a state, + steps", function()
  start()
  local t = T.tone("tone", 8, "A3")
  t:add_device("gain", { gain = -12 })
  paw.cursor.set_part(t)
  paw.cursor.set_beat(0)
  paw.keymap.feed("<leader>al")
  paw.keymap.feed("state<CR>")
  local id = paw.cursor.lane_id()
  eq(id ~= nil and api.lane_get(id).target, "state", "the picker makes a state lane, and the cursor is on its row")
  T.keys("\\s")
  eq(points(id), "0:0", "\\s keeps the state now, given from the cursor")
  eq(table.concat(api.lane_get(id).states, " "), "A", "named with a letter")
  paw.device(api.lane_get(id).device):set("gain", 0)
  T.keys("4l\\s")
  eq(points(id), "0:0 4:1", "and another, later")
  eq(api.lane_states(id)[2].params.gain, 0, "with the parameters as they are now")
  T.keys("-")
  eq(points(id), "0:0 4:0", "- steps the point to the state before")
  T.keys("c")
  paw.keymap.feed("B<CR>")
  api.undo_checkpoint()
  eq(points(id), "0:0 4:1", "c chooses a state by its name")
  local text = table.concat(api.ui_snapshot(140, 30), "\n")
  eq(text:find("Gain › state", 1, true) ~= nil, true, "the row names the lane")
  eq(text:find("B", 1, true) ~= nil, true, "and the state of a point")
end)
