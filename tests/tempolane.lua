-- The tempo lane under the ruler, and the pre-roll before a punch. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local paw = require("paw")
local api = paw.api
local act = paw.frontend.act

local function with_input(fn)
  api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })
  local ok, err = xpcall(fn, debug.traceback)
  api.engine_restart({ backend = "null" })
  if not ok then error(err, 0) end
end

--- 120 bpm all through, with the lane shown.
local function lane()
  fresh()
  paw.project.tempo = 120
  paw.tempolane.show(true)
end

--- A test that leaves the lane hidden, as the other tests find it.
local function lane_test(name, fn)
  test(name, function()
    local ok, err = xpcall(fn, debug.traceback)
    paw.tempolane.show(false)
    if not ok then error(err, 0) end
  end)
end

local function shape(points)
  local out = {}
  for i, p in ipairs(points or paw.tempo.points()) do
    out[i] = string.format("%g@%g%s", p.bpm, p.beat, p.ramp and ">" or "")
  end
  return table.concat(out, " ")
end

lane_test("tempo lane: shown or hidden by command, and the window is told what to draw", function()
  fresh()
  paw.tempolane.show(false)
  paw.tempo.set(16, 90)
  eq(paw.frontend.state(-1).project.tempo_lane, nil, "nothing while it is hidden")
  paw.cmd("tempo.lane")
  eq(paw.tempolane.shown(), true, "the command shows it")
  local shown = paw.frontend.state(-1).project.tempo_lane
  eq(shape(shown.points), "120@0 90@16", "the whole map")
  eq(shown.lo <= 75 and shown.hi >= 135 and shown.hi - shown.lo >= 60, true, "over a range with room round the tempos")
  paw.cmd("tempo.lane", { "off" })
  eq(paw.tempolane.shown(), false, "and hides it")
  paw.keymap.feed("zT")
  eq(paw.tempolane.shown(), true, "zT toggles it")
  act.tempo_lane(false)
  eq(paw.tempolane.shown(), false, "so does the window's gesture")
end)

lane_test("tempo lane: the terminal draws two rows under the ruler, with the curve and a mark per change", function()
  lane()
  paw.tempo.set(8, 120, { ramp = true })
  paw.tempo.set(16, 90)
  paw.ui.focus("arrange")
  local text = table.concat(api.ui_snapshot(120, 24), "\n")
  eq(text:find("tempo", 1, true) ~= nil, true, "the lane is named")
  eq(text:find("120 bpm", 1, true) ~= nil, true, "with the tempo at the cursor")
  eq(text:find("↗", 1, true) ~= nil, true, "a ramping change is marked")
  eq(text:find("◆", 1, true) ~= nil, true, "and a holding one")
  paw.tempolane.show(false)
  local _, hidden = table.concat(api.ui_snapshot(120, 24), "\n"):gsub("120 bpm", "")
  eq(hidden, 1, "hidden, only the status line says it")
end)

lane_test("tempo lane: a click adds a change that the whole song follows, and undo takes it back", function()
  lane()
  api.undo_checkpoint()
  local lo, hi = paw.tempolane.range()
  eq(lo .. " " .. hi, "80 160", "a steady 120 is drawn over 80 to 160")
  act.tempo_point_add(16.2, 0.75)
  eq(shape(), "120@0 140@16", "a change on the grid at the height clicked")
  near(paw.tempo.beats_to_seconds(32), 16 * 0.5 + 16 * 60 / 140, 1e-9, "the song's time follows")
  eq(paw.tempo.at(20), 140, "as does the tempo at a beat")
  api.undo_checkpoint()
  paw.undo()
  eq(shape(), "120@0", "undone in one step")
  paw.redo()
  eq(shape(), "120@0 140@16", "and redone")
end)

lane_test("tempo lane: a change is dragged to a beat and a height, the first one only in height", function()
  lane()
  act.tempo_point_add(8, 0.5)
  act.tempo_point_add(16, 0.5)
  eq(shape(), "120@0 120@8 120@16", "three changes")
  act.tempo_point_move(8, 12.4, 1)
  eq(shape(), "120@0 160@12 120@16", "moved later and up")
  act.tempo_point_move(12, 16, 0)
  eq(shape(), "120@0 90@16", "dropped on another, it takes its place")
  act.tempo_point_move(0, 4, 1)
  eq(shape(), "150@0 90@16", "the start's change keeps its beat")
  eq(paw.project.tempo, 150, "and the project's tempo is its tempo")
end)

lane_test("tempo lane: a change is removed, and made to ramp or hold", function()
  lane()
  act.tempo_point_add(8, 1)
  act.tempo_point_add(16, 0)
  eq(shape(), "120@0 160@8 90@16", "set up")
  eq(act.tempo_point_ramp(8), true, "ramps")
  eq(shape(), "120@0 160@8> 90@16", "to the next change")
  near(paw.tempo.beats_to_seconds(16), 8 * 0.5 + 8 * 60 / 125, 1e-9, "the ramp averages 125")
  eq(act.tempo_point_ramp(8), false, "holds again")
  act.tempo_point_remove(8)
  eq(shape(), "120@0 90@16", "removed")
  act.tempo_point_remove(0)
  eq(shape(), "120@0 90@16", "the first change cannot be")
end)

lane_test("tempo lane: the pencil draws a curve of ramps over the stretch it crosses", function()
  lane()
  act.tempo_point_add(24, 0.5)
  act.tempo_draw({ { 4, 0.5 }, { 5, 0.6 }, { 6, 0.8 }, { 7, 1 }, { 8, 1 } })
  local pts = paw.tempo.points()
  eq(pts[1].beat .. " " .. pts[2].beat .. " " .. pts[#pts - 1].beat .. " " .. pts[#pts].beat, "0 4 8 24", "a change to each step, the rest kept")
  eq(pts[2].ramp and pts[3].ramp, true, "each slopes to the next")
  eq(pts[#pts - 1].bpm >= pts[2].bpm, true, "rising as it was drawn")
  eq(pts[#pts - 1].ramp, false, "the stroke's last change holds, what follows was not drawn")
  -- Drawn over a stretch, it replaces what was there.
  act.tempo_draw({ { 2, 0 }, { 10, 0 } })
  local between = 0
  for _, p in ipairs(paw.tempo.points()) do
    if p.beat > 2 and p.beat < 10 then between = between + 1 end
  end
  eq(between <= 1, true, "the changes it crossed are replaced by the stroke's")
end)

lane_test("tempo lane: commands move a change, and they are undone one step at a time", function()
  lane()
  api.undo_checkpoint()
  paw.cmd("tempo", { "96", "at", "5" })
  api.undo_checkpoint()
  eq(shape(), "120@0 96@16", "a change at bar 5")
  paw.cmd("tempo.move", { "9", "5" })
  eq(shape(), "120@0 96@32", "moved to bar 9")
  api.undo_checkpoint()
  paw.undo()
  eq(shape(), "120@0 96@16", "undone")
  T.fails(function() paw.cmd("tempo.move", { "9", "1" }) end, "start", "the start's tempo does not move")
end)

-- Pre-roll ------------------------------------------------------------------------

--- A take punched over bars 3 and 4 (beats 8 to 16) at 120 bpm, on a mic.
local function punched()
  fresh()
  paw.project.tempo = 120
  paw.project.save(T.scratch .. "/preroll.json")
  local mic = paw.add_track({ name = "mic" })
  mic.input, mic.armed = "1", true
  paw.cmd("punch", { "3", "4" })
  return mic
end

test("pre-roll: it is set in bars or seconds and the kernel is told", function()
  fresh()
  paw.cmd("preroll", { "2" })
  eq(paw.opt.pre_roll .. " " .. paw.transport.pre_roll, "2 2", "bars, as an option and in the kernel")
  paw.cmd("preroll", { "1.5s" })
  eq(paw.opt.pre_roll .. " " .. paw.opt.pre_roll_seconds .. " " .. paw.transport.pre_roll_seconds, "0 1.5 1.5", "seconds")
  paw.cmd("preroll")
  eq(paw.opt.pre_roll_seconds, 0, "alone it turns it off")
  paw.cmd("preroll")
  eq(paw.opt.pre_roll, 2, "and on again, to the last bars")
  eq(paw.frontend.state(-1).project.pre_roll, 2, "the window is told")
  paw.cmd("preroll", { "off" })
  eq(paw.transport.pre_roll, 0, "off")
  paw.opt.pre_roll_seconds = 0
end)

test("pre-roll: recording with punch on starts playing bars before the punch in, and the take starts at the punch in", function()
  with_input(function()
    local mic = punched()
    paw.cmd("preroll", { "1" })
    paw.transport.seek(8)
    paw.transport.record()
    local at = api.transport_get().position
    eq(at >= 4 and at < 5, true, "playing from a bar before the punch in: " .. at)
    T.until_beat(8.5)
    eq(paw.transport.position > 8, true, "past the punch in")
    paw.transport.stop()
    paw.flush()
    local clips = mic:clips()
    eq(#clips, 1, "one take")
    local c = clips[1]:get()
    eq(c.start, 8, "starting exactly at the punch in")
    eq(c.offset, 0, "from the start of its file")
    eq(c.length > 0.5 and c.length < 4, true, "holding what was played after it")
    -- From between the pre-roll's start and the punch in: back to its start.
    clips[1]:remove()
    paw.transport.seek(6)
    paw.transport.record()
    at = api.transport_get().position
    eq(at >= 4 and at < 5, true, "from a playhead inside the pre-roll, back to its start: " .. at)
    paw.transport.stop()
    -- From further back than the pre-roll, the playhead stays.
    paw.transport.seek(1)
    paw.transport.record()
    at = api.transport_get().position
    eq(at >= 1 and at < 2, true, "from earlier than that, where it was: " .. at)
    paw.transport.stop()
    -- Inside the range, or with punch off, there is none.
    paw.transport.seek(10)
    paw.transport.record()
    at = api.transport_get().position
    eq(at >= 10 and at < 11, true, "from inside the range, none: " .. at)
    paw.transport.stop()
    paw.transport.punch_enabled = false
    paw.transport.seek(8)
    paw.transport.record()
    at = api.transport_get().position
    eq(at >= 8 and at < 9, true, "without punch, none: " .. at)
    paw.transport.stop()
    paw.cmd("preroll", { "off" })
  end)
end)

test("pre-roll: seconds count back from the bars, and a count-in comes first", function()
  with_input(function()
    punched()
    paw.opt.pre_roll, paw.opt.pre_roll_seconds = 1, 1
    paw.transport.seek(8)
    paw.transport.record()
    local at = api.transport_get().position
    -- A bar is 2 s at 120 bpm: 4, and a second (2 beats) before that.
    eq(at >= 2 and at < 3, true, "a bar and a second before: " .. at)
    paw.transport.stop()
    paw.opt.pre_roll_seconds = 0
    paw.opt.count_in = 1
    paw.transport.seek(8)
    paw.transport.record()
    local t = api.transport_get()
    eq(t.counting, 4, "the count comes first")
    eq(t.position, 4, "and the playhead waits at the pre-roll's start")
    paw.transport.stop()
    paw.opt.count_in, paw.opt.pre_roll = 0, 0
  end)
end)
