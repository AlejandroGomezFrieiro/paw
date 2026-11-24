-- The rules of time motions in the arrange view and its lanes
-- (paw/motion.tl), by real keys: grid keys go to grid lines, object keys
-- go to the object, a whole thing moves by steps and keeps its offset, one
-- edge goes to lines, and only `=` puts things on the grid. The owner's
-- case is a take that ends between two lines: 5.3125 beats, on a grid of
-- one beat. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api
local TPQ = paw.timegrid.TPQ
local arrange = paw.ui.views:get("arrange")

--- A take that ends off the grid, at 5.3125 beats (5 beats and 19200 ticks).
local OFF = 5 * TPQ + 19200

--- The project of `fixture` in the arrange view, with a grid of one beat
--- and two columns a beat. Gives its parts by name.
local function start(fixture)
  T.start()
  paw.opt.grid, paw.opt.zoom = 1, 2
  arrange.scroll = 0
  return T.fixture(fixture)
end

--- The clips of a part as `start+length` in beats, in order.
local function clips(part)
  local out = {}
  for _, c in ipairs(api.clip_list(part.id)) do
    out[#out + 1] = string.format("%g+%g", c.start, c.length)
  end
  table.sort(out)
  return table.concat(out, " ")
end

test("time motions: w goes to the end of a take off the grid, and h l go to the lines next to it", function()
  start("part Guitar\n clip take 0+5.3125\n cursor @0")
  T.keys("w")
  eq(paw.cursor.tick, OFF, "w: the exact end of the take")
  T.keys("l")
  eq(paw.cursor.tick, 6 * TPQ, "l from off the grid: the next line")
  T.keys("e")
  eq(paw.cursor.tick, 6 * TPQ, "e after the end: nothing to go to")
  T.keys("0w")
  T.keys("h")
  eq(paw.cursor.tick, 5 * TPQ, "h from off the grid: the line before")
  T.keys("$3l")
  eq(paw.cursor.tick, 8 * TPQ, "3l from off the grid: three lines")
end)

test("time motions: an offset never builds up over w, b, h and l (the owner's bug)", function()
  start("part Guitar\n clip take 0+5.3125\n cursor @0")
  for round = 1, 4 do
    T.keys("w")
    eq(paw.cursor.tick, OFF, "round " .. round .. ": w")
    T.keys("ll")
    eq(paw.cursor.tick, 7 * TPQ, "round " .. round .. ": ll goes to whole lines")
    T.keys("b")
    eq(paw.cursor.tick, 0, "round " .. round .. ": b")
  end
  T.keys("w<Right>")
  eq(paw.cursor.tick, 6 * TPQ, "the arrow is l")
end)

test("time motions: the cursor's cells are the ruler's cell, and off the grid one amber column", function()
  start("part Guitar\n clip take 0+5.3125\n cursor @0")
  paw.opt.zoom = 2
  T.keys("w")
  T.settle()
  T.expect_screen("off-grid", 80, 16, { rows = { 1, 6 } })
  T.keys("l")
  T.settle()
  T.expect_screen("after-l", 80, 16, { rows = { 1, 6 } })
end)

test("time motions: the status line says the offset, the window bar the hundredths, K the ticks", function()
  start("part Guitar\n clip take 0+5.3125\n cursor @0")
  T.keys("w")
  T.settle()
  local text = T.screen(120, 20)
  eq(text:find("grid 1/4 · +.31", 1, true) ~= nil, true, "the status line: the grid and the offset")
  eq(text:find("Song 2.2.31", 1, true) ~= nil, true, "the window bar: the position with its hundredths")
  T.keys("l")
  T.settle()
  text = T.screen(120, 20)
  eq(text:find("+.31", 1, true), nil, "on the grid: no offset")
  eq(text:find("Song 2.3", 1, true) ~= nil, true, "on the grid: bar and beat")
  -- On the empty time area after the take: the exact position.
  paw.cursor.set_beat(9.5)
  T.keys("K")
  eq(
    T.hover_text():find("bar 3, beat 2, tick 480 of 960", 1, true) ~= nil,
    true,
    "K: the bar, the beat and the ticks of 1/960"
  )
  eq(T.hover_text():find("off the grid: +.50", 1, true) ~= nil, true, "K: the offset")
  T.keys("<Esc>")
end)

test("time motions: j and k keep the time, and give back the time that a bound kept away", function()
  local parts = start("part A\n clip a 0+16\npart B\n clip b 0+16\n cursor @0")
  paw.cursor.set_part(parts.A)
  T.keys("w")
  eq(paw.cursor.tick, 16 * TPQ, "w: the end of the clip")
  T.keys("j")
  eq(paw.cursor.tick, 16 * TPQ, "j keeps the tick")
  -- A scope of the first two bars keeps the cursor at its end.
  T.keys("0zn2ib")
  T.after(function() paw.scope.widen(true) end)
  T.keys("$")
  eq(paw.cursor.tick, 8 * TPQ, "$ in the scope: its end")
  eq(paw.cursor.want, 16 * TPQ, "the time that $ asked for")
  T.keys("k")
  eq(paw.cursor.tick, 8 * TPQ, "k in the scope: its end again")
  T.keys("zW")
  T.keys("j")
  eq(paw.cursor.tick, 16 * TPQ, "j out of the scope: the time that $ asked for")
end)

test("time motions: operators and selections go from the cursor up to the target, the end not included", function()
  T.check_keys(
    "part A\n clip a 0+8\n cursor @5.3125",
    "dl",
    "part A\n clip a 0+5.3125\n clip a 6+2\n cursor @5.3125",
    "dl at 5.3125 removes 5.3125 to 6"
  )
  T.check_keys(
    "part A\n clip a 0+5.3125\n clip b 5.3125+2\n cursor @0",
    "de",
    "part A\n clip b 5.3125+2\n cursor @0",
    "de from 0 removes 0 to 5.3125"
  )
  start("part A\n clip a 0+8\n cursor @5.3125")
  T.keys("v")
  local sel = paw.keymap.selection()
  eq({ sel.c0, sel.c1 }, { 5.3125, 6 }, "v at 5.3125: up to the next line")
  T.keys("<Esc>hvl")
  sel = paw.keymap.selection()
  eq({ sel.c0, sel.c1 }, { 5, 6 }, "vl from 5: 5 to 6")
  T.keys("<Esc>")
end)

test("time motions: a whole clip moves by steps and keeps its offset; = puts it on the grid", function()
  local parts = start("part A\n clip a 0.3125+4\n cursor @0.3125")
  T.keys("L")
  eq(clips(parts.A), "1.3125+4", "L: one step later, the same offset")
  eq(paw.cursor.beat, 1.3125, "the cursor goes with it")
  T.keys(">ic")
  eq(clips(parts.A), "2.3125+4", ">ic: one step later")
  T.keys("H")
  eq(clips(parts.A), "1.3125+4", "H: one step earlier")
  T.keys("=ic")
  eq(clips(parts.A), "1+4", "=ic: on the nearest lines")
  T.keys("u")
  eq(clips(parts.A), "1.3125+4", "one u undoes =")
end)

test("time motions: one edge goes to the lines next to it", function()
  local parts = start("part A\n clip a 0+5.3125\n cursor @0")
  T.keys("<A-l>")
  eq(clips(parts.A), "0+6", "Alt-l: the end goes to the next line")
  T.keys("u<A-h>")
  eq(clips(parts.A), "0+5", "Alt-h: the end goes to the line before")
end)

-- tests/time_axis.lua checks that zoom and a change of tempo move no position.
test("time motions: a split is at the exact cursor", function()
  local parts = start("part A\n clip a 0+8\n cursor @5.3125")
  T.keys("S")
  eq(clips(parts.A), "0+5.3125 5.3125+2.6875", "S splits at the cursor, off the grid")
end)

test("time motions: gP goes to the playhead exactly", function()
  start("part A\n clip a 0+8\n cursor @0")
  paw.transport.position = 5.3125
  T.until_(function() return paw.transport.position == 5.3125 end, "the playhead at 5.3125")
  T.keys("gP")
  eq(paw.cursor.tick, OFF, "gP: the exact playhead, not the nearest line")
end)

test("time motions: a lane point is under the cursor in the cursor's cell", function()
  local parts = start("part A\n clip a 0+8\n cursor @0")
  local lane = parts.A:automate("volume")
  api.lane_set_points(lane.id, { { 5.2, -6 }, { 6, -3 } })
  paw.lanes.open(parts.A)
  paw.cursor.set_part(parts.A.id, lane.id)
  T.keys("w")
  eq(paw.cursor.beat, 5.2, "w on a lane: the next point, exact")
  T.keys("hx")
  eq(#api.lane_points(lane.id), 1, "x at 5 removes the point at 5.2, in its cell")
  T.keys("u")
  paw.cursor.set_beat(5.3125)
  T.keys("x")
  eq(paw.ui.messages[#paw.ui.messages].text, "no point under the cursor", "x at 5.3125: the message")
  eq(#api.lane_points(lane.id), 2, "at 5.3125 the cell ends at 6: no point under it")
  T.keys("w")
  T.keys("vlL")
  eq(api.lane_points(lane.id)[2][1], 7, "L moves the selected point a step")
end)

test("time motions: a press of the pointer goes to the line of its cell; with nosnap, exact", function()
  local parts = start("part A\n clip a 8+4\n cursor @0")
  paw.opt.mouse = true
  T.settle()
  api.ui_snapshot(100, 20)
  local g = arrange.geometry
  local y
  for _, row in ipairs(g.layout.rows) do
    if row.id == parts.A.id and row.kind == "part" then y = row.y end
  end
  local function press(column)
    paw.mouse.forget()
    paw.ui.mouse({ kind = "down", x = g.hw + column, y = y, button = "left", mods = "" })
    paw.ui.mouse({ kind = "up", x = g.hw + column, y = y, button = "left", mods = "" })
  end
  press(13)
  eq(paw.cursor.tick, 6 * TPQ, "a press on the second column of beat 6: beat 6")
  paw.opt.snap = false
  press(13)
  eq(paw.cursor.beat, 6.5, "with nosnap: the beat at the cell")
end)
