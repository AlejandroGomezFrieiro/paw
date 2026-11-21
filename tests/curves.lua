-- Tests of the curve editor: curves read and written by their address (a
-- lane, a parameter, a clip's controller, a note's expression, the tempo
-- map), the editor as a buffer in windows, its keys, insert mode, the
-- tools and waves, the mouse, and automating a parameter from the device
-- panel. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api
local L = paw.layout
local curves = paw.curves
local editor = paw.curves.editor

local W, H = 160, 48
local initial = L.capture()

--- The tabs and windows as they were, and no window of its own left open.
local function tidy()
  require("paw.menu").close(0)
  L.restore(initial)
  for name in pairs(paw.canvas.open_views) do paw.canvas.close(name) end
  paw.ui.focus("arrange")
end

local function start()
  T.after(tidy)
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  require("paw.menu").close(0)
  paw.mouse.forget()
  L.restore(initial)
  for name in pairs(paw.canvas.open_views) do paw.canvas.close(name) end
  paw.ui.focus("arrange")
end

local keys = T.keys

local function screen() return table.concat(api.ui_snapshot(W, H), "\n") end

local function beats(points)
  local out = {}
  for i, q in ipairs(points) do out[i] = string.format("%g", q.beat) end
  return table.concat(out, " ")
end

--- A track with a volume lane of points `{ beat, value }`, and the editor
--- open on it with the cursor at beat 0.
local function lane_with(points)
  local t = paw.add_track({ name = "Pad" })
  local lane = t:automate("volume")
  lane:set_points(points or {})
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  api.undo_checkpoint()
  local win = editor.open(paw.address.lane(lane.id), { beat = 0 })
  win.state.grid = 0.25
  return t, lane, win
end

-- Curves by address ----------------------------------------------------------------

test("curves in cells are connected sextants, and steep jumps have no gaps", function()
  local draw = paw.draw
  eq(draw.sextant(0), " ", "no sextants is a space")
  eq(draw.sextant(21), "▌", "the left column is a half block")
  eq(draw.sextant(42), "▐", "the right column")
  eq(draw.sextant(63), "█", "all six is the full block")
  eq(draw.sextant(1), "\240\159\172\128", "the top left one is U+1FB00")
  eq(draw.sextant(62), "\240\159\172\187", "and 62 of them are U+1FB3B")
  local function plot(value, glyphs)
    local was = paw.opt.curve_glyphs
    paw.opt.curve_glyphs = glyphs
    local cells = {}
    local buf = { width = 6, text = function(_, x, y, ch) cells[y * 6 + x] = ch end }
    draw.curve(buf, 0, 2, value, "Normal")
    paw.opt.curve_glyphs = was
    return cells
  end
  -- A step from the bottom to the top at the middle of six columns: six
  -- sextant rows over two cell rows. The line runs along the bottom, then
  -- goes up the left of the fourth column with no gap, and along the top.
  local cells = plot(function(i) return i < 6 and 0 or 1 end, "sextant")
  eq(cells[6 + 0], draw.sextant(48), "along the bottom")
  eq(cells[6 + 2], draw.sextant(48), "to the step")
  eq(cells[6 + 3], draw.sextant(1 + 4), "the lower cell of the jump, filled up from the bottom")
  eq(cells[3], draw.sextant(1 + 2 + 4 + 16), "the upper cell, filled to the top")
  eq(cells[4], draw.sextant(3), "along the top")
  paw.opt.ascii = false
  local braille = plot(function(i) return i / 12 end, "braille")
  local any = false
  for _, ch in pairs(braille) do any = any or ch:find("^\226[\160-\163]") ~= nil end
  eq(any, true, "braille on request")
  local lines = plot(function(i) return i / 12 end, "line")
  local ok = true
  for _, ch in pairs(lines) do ok = ok and (ch == "▁" or ch == "─" or ch == "▔") end
  eq(ok, true, "and lines")
end)

test("every kind of curve reads and writes through its address", function()
  start()
  local t = paw.add_track({ name = "Lead" })
  local lane = t:automate("pan")
  local c = curves.target(paw.address.lane(lane.id))
  c.write({ { beat = 0, value = -1 }, { beat = 4, value = 1, shape = "hold" } })
  eq(beats(c.points()), "0 4", "a lane's points")
  eq(c.points()[2].shape, "hold", "and the shape of the stretch that leaves a point")

  local d = t:add_device("synth")
  local p = curves.target(paw.address.param(d.id, "cutoff"))
  eq(#p.points(), 0, "a parameter with no lane is flat")
  eq(d:lane("cutoff"), nil, "and has no lane until it is written")
  p.write({ { beat = 2, value = p.min } })
  eq(d:lane("cutoff") ~= nil, true, "its first point makes the lane")

  local clip = t:add_clip({ start = 8, length = 8, notes = { { pitch = 60, start = 0, length = 4 } } })
  local cc = curves.target(paw.address.clip(clip.id) .. "/control/cc/74")
  cc.write({ { beat = 8, value = 0 }, { beat = 10, value = 1 } })
  local moves = api.clip_controls(clip.id)
  eq(#moves, 2, "a controller's moves")
  eq(moves[2].start, 2, "kept from the clip's start, read in the project's beats")
  eq(cc.format(1), "127", "and shown from 0 to 127")
  local own = curves.target(paw.address.clip(clip.id) .. "/control/pressure#key=60")
  own.write({ { beat = 8, value = 0.5 } })
  eq(#own.points(), 1, "a note's own pressure")
  eq(#curves.target(paw.address.clip(clip.id) .. "/control/pressure").points(), 0, "is not the channel's")

  local tempo = curves.target("paw://tempo")
  tempo.write({ { beat = 0, value = 100, shape = "linear" }, { beat = 8, value = 140, shape = "hold" } })
  local mid = paw.tempo.at(4)
  eq(mid > 110 and mid < 130, true, "the tempo ramps where its stretch is straight")
  eq(paw.tempo.at(12), 140, "and holds after")
  eq(curves.target("paw://track/1/send/2"), nil, "a send is not a curve yet")
end)

test("a lane's held and smooth stretches are played as drawn", function()
  start()
  local t = paw.add_track({ name = "Pad" })
  local lane = t:automate("volume")
  local c = curves.target(paw.address.lane(lane.id))
  c.write({ { beat = 0, value = -24, shape = "hold" }, { beat = 4, value = 0, shape = "smooth" }, { beat = 8, value = -12 } })
  near(api.lane_value_at(lane.id, 3.9), -24, 1e-9, "a held value jumps at the next point")
  near(api.lane_value_at(lane.id, 6), -6, 1e-6, "a smooth stretch is half way at its middle")
  near(curves.value_at(c.points(), 5), api.lane_value_at(lane.id, 5), 1e-3, "and the editor draws what plays")
  lane:set_points({ { 0, -24 }, { 2, -12 }, { 8, -12 } })
  local shapes = api.lane_shapes(lane.id)
  eq(#shapes .. " " .. shapes[1].shape, "1 hold", "a shape goes with the point it leaves from")
end)

test("a shape a curve lacks is written as the steps it plays as", function()
  start()
  local t = paw.add_track({ name = "Lead" })
  local clip = t:add_clip({ start = 0, length = 4, notes = {} })
  local cc = curves.target(paw.address.clip(clip.id) .. "/control/cc/1")
  cc.write(curves.fit(cc, { { beat = 0, value = 0, shape = "linear" }, { beat = 1, value = 1 } }))
  eq(#cc.points(), 17, "a ramp of a controller is a move every sixteenth of a beat")
  near(cc.points()[9].value, 0.5, 1e-9, "on the line")
end)

-- The buffer -------------------------------------------------------------------------

test("a curve is a buffer named by its address, shown in a window split off", function()
  start()
  local _, lane = lane_with({ { 0, -12 }, { 4, 0 } })
  local uri = paw.address.lane(lane.id)
  local buf = paw.buf.current()
  eq(buf.name, uri, "named by its address")
  eq(paw.layout.title(buf), "Volume", "and called what it moves")
  local text = screen()
  eq(text:find("2 points", 1, true) ~= nil, true, "the editor shows how many points")
  eq(text:find("-12.0 dB", 1, true) ~= nil, true, "and the value in its unit")
  eq(text:find("[\240][\159][\172-\175]") ~= nil or text:find("[▌▐█]") ~= nil, true, "the curve drawn in sextants")
  paw.commands.exec("close")
  paw.commands.exec("vs " .. uri)
  eq(paw.win.current().view, "curve", ":vs takes an address")
  eq(paw.buf.current().name, uri, "and shows the same buffer")
  paw.commands.exec("sp paw://tempo")
  eq(paw.buf.current().name, "paw://tempo", "the tempo map is a curve too")
end)

test("lane rows, the device panel and the piano roll open their curves with gC", function()
  start()
  local t = paw.add_track({ name = "Pad" })
  local lane = t:automate("volume")
  local d = t:add_device("synth")
  local clip = t:add_clip({ start = 4, length = 4, notes = { { pitch = 60, start = 0, length = 2 } } })
  paw.lanes.open(t)
  paw.cursor.set_track(t.id, lane.id)
  keys("gC")
  eq(paw.buf.current().name, paw.address.lane(lane.id), "a lane row's curve")
  L.restore(initial)
  paw.cursor.set_track(t)
  paw.ui.focus("devices")
  local devices = paw.ui.views.devices
  for i, row in ipairs(devices:rows()) do
    if row.param and row.param.key == "cutoff" then devices.row = i end
  end
  keys("gC")
  eq(paw.buf.current().name, paw.address.param(d.id, "cutoff"), "a parameter's curve")
  L.restore(initial)
  paw.ui.views.pianoroll:edit(clip)
  keys("gC")
  eq(paw.buf.current().name, paw.address.clip(clip.id) .. "/control/cc/1", "the strip's controller")
  L.restore(initial)
  paw.ui.views.pianoroll:edit(clip)
  paw.ui.views.pianoroll.pitch, paw.ui.views.pianoroll.beat = 60, 0
  keys("gX")
  eq(paw.buf.current().name, paw.address.clip(clip.id) .. "/control/cc/1#key=60", "the note's own")
  eq(editor.current().state.beat, 4, "the cursor where the roll's was, in the project's beats")
end)

test("in the device panel A automates the parameter at its value, on the lane row", function()
  start()
  local t = paw.add_track({ name = "Pad" })
  local d = t:add_device("synth")
  paw.cursor.set_track(t)
  paw.cursor.set_beat(6)
  local value = d:get().params.cutoff
  api.undo_checkpoint()
  paw.ui.focus("devices")
  local devices = paw.ui.views.devices
  for i, row in ipairs(devices:rows()) do
    if row.param and row.param.key == "cutoff" then devices.row = i end
  end
  keys("A")
  local lane = d:lane("cutoff")
  eq(lane ~= nil, true, "a lane for it")
  local points = lane:points()
  eq(#points, 1, "with one point")
  eq(points[1][1], 6, "at the cursor's beat")
  near(points[1][2], value, 1e-6, "at the value it has")
  eq(paw.lanes.is_open(t), true, "the lanes shown as rows")
  eq(paw.cursor.lane_id(), lane.id, "the cursor on its row")
  eq(paw.ui.messages[#paw.ui.messages].text:find("automated", 1, true) ~= nil, true, "and it says so")
  keys("u")
  eq(d:lane("cutoff"), nil, "one undo step")
end)

-- Keys -------------------------------------------------------------------------------

test("points are words: w b move between them, x removes, + raises, o adds at the cursor", function()
  start()
  local _, lane = lane_with({ { 0, -12 }, { 2, -6 }, { 4, 0 } })
  keys("w")
  eq(editor.current().state.beat, 2, "w to the next point")
  near(editor.current().state.value, -6, 1e-9, "the cursor takes its value")
  keys("w+")
  near(lane:points()[3][2], 1, 1e-9, "+ raises the point under the cursor a step")
  keys("b")
  keys("x")
  eq(#lane:points(), 2, "x removes it")
  keys("0")
  eq(editor.current().state.beat, 0, "0 to the first")
  keys("lllkko")
  local points = lane:points()
  eq(#points, 3, "o adds a point")
  eq(points[2][1], 0.75, "at the cursor's beat, three grid steps on")
  near(points[2][2], -10, 1e-9, "at its value, two steps up")
  keys("u")
  eq(#lane:points(), 2, "one undo step")
end)

test("~ gives a stretch its shape, and ] [ bend a smooth one", function()
  start()
  local _, lane = lane_with({ { 0, -12 }, { 4, 0 } })
  keys("~")
  eq(api.lane_shapes(lane.id)[1].shape, "hold", "straight, then held")
  keys("~")
  eq(api.lane_shapes(lane.id)[1].shape, "smooth", "then smooth")
  -- `]` waits a moment for `]g`, as at the keyboard.
  local wait = paw.opt.timeoutlen
  paw.opt.timeoutlen = 20
  keys("2]")
  paw.wait(150)
  paw.opt.timeoutlen = wait
  near(api.lane_shapes(lane.id)[1].tension, 0.5, 1e-9, "] bends it")
  keys("~")
  eq(#api.lane_shapes(lane.id), 0, "and back to straight")
end)

test("insert mode draws the value as the cursor moves and writes it on Esc as one step", function()
  start()
  local _, lane = lane_with({ { 0, -12 }, { 8, -12 } })
  local before = api.undo_current()
  paw.keymap.feed("lli")
  eq(paw.keymap.mode, "i", "i draws")
  paw.keymap.feed("kkllkk")
  eq(#lane:points(), 2, "nothing is written while drawing")
  eq(screen():find("INS", 1, true) ~= nil, true, "the window says it draws")
  keys("<Esc>")
  eq(paw.keymap.mode, "n", "Esc leaves")
  local points = lane:points()
  eq(beats(curves.target(paw.address.lane(lane.id)).points()), "0 0.5 0.75 1 8", "a point at each step the cursor drew at")
  near(points[2][2], -10, 1e-9, "raised two steps")
  near(points[3][2], -10, 1e-9, "on along")
  near(points[4][2], -8, 1e-9, "and two more")
  keys("u")
  eq(api.undo_current(), before, "one undo step")
  eq(#lane:points(), 2, "undone whole")
end)

test("a selection's points are deleted, moved, raised, smoothed and quantized", function()
  start()
  local _, lane = lane_with({ { 0, 0 }, { 1, -6 }, { 2, 0 }, { 3, -6 }, { 4, 0 } })
  keys("vllllllll+")
  near(lane:points()[2][2], -5, 1e-9, "+ raises the points selected")
  keys("<Esc>0vllllllllgs")
  near(lane:points()[2][2], -2, 1e-9, "gs smooths them")
  near(lane:points()[4][2], -6, 1e-9, "and not the rest")
  keys("<Esc>0wvllL")
  eq(lane:points()[2][1], 1.25, "L moves them a grid step later")
  keys("<Esc>0v$gq")
  eq(lane:points()[2][1], 1.25, "on the grid already")
  editor.current().state.grid = 1
  keys("<Esc>0v$gq")
  eq(beats(curves.target(paw.address.lane(lane.id)).points()), "0 1 2 3 4", "gq quantizes to the window's grid")
  keys("<Esc>0wvd")
  eq(#lane:points(), 4, "d deletes")
  keys("$lp")
  eq(beats(curves.target(paw.address.lane(lane.id)).points()), "0 2 3 4 5", "p puts them at the cursor")
end)

test("gS thins a curve drawn finely and keeps its shape", function()
  start()
  local points = {}
  for i = 0, 32 do points[#points + 1] = { i / 8, i <= 16 and -24 + i or -8 } end
  local _, lane = lane_with(points)
  keys("gSS")
  eq(#lane:points(), 3, "a ramp and a level are three points")
  near(api.lane_value_at(lane.id, 1), -16, 1e-6, "the same curve")
end)

test("g~ draws a wave whose choices step within one undo step", function()
  start()
  local _, lane = lane_with({ { 0, -30 } })
  local before = api.undo_current()
  paw.keymap.feed("v" .. string.rep("l", 16) .. "g~")
  eq(require("paw.menu").is_open(), true, "a menu of waves")
  keys("<CR>")
  local sine = #lane:points()
  eq(sine > 4, true, "a sine over the selection")
  eq(screen():find("[sine]", 1, true) ~= nil, true, "its choices on the bottom line")
  eq(#api.lane_shapes(lane.id) > 0, true, "smooth stretches on a lane")
  keys("<C-n>")
  eq(#api.lane_shapes(lane.id), 0, "the next wave, a triangle, is straight")
  eq(screen():find("[triangle]", 1, true) ~= nil, true, "and named")
  keys("<Tab><C-n>")
  eq(screen():find("[1/8]", 1, true) ~= nil, true, "Tab goes on to the rate")
  keys("<C-y>")
  eq(screen():find("[1/8]", 1, true), nil, "Ctrl-y keeps it")
  keys("u")
  eq(api.undo_current(), before, "the wave and its choices are one undo step")
end)

test(":curve.generate makes a wave by name, rate and depth", function()
  start()
  local _, lane = lane_with({ { 0, -24 } })
  paw.keymap.feed("v" .. string.rep("l", 8))
  paw.commands.exec("curve.generate square rate=1 depth=0.5")
  keys("<Esc>")
  local c = curves.target(paw.address.lane(lane.id))
  eq(c.points()[1].shape, "hold", "a square holds")
  local hi, lo = c.points()[1].value, c.points()[2].value
  eq(hi > lo, true, "high, then low")
  near(c.frac(hi) - c.frac(lo), 0.5, 1e-6, "half the height apart")
end)

-- The mouse -----------------------------------------------------------------------

local function geo()
  local r
  for _, rect in ipairs(paw.ui.arrange(W, H)) do
    if rect.name == "curve" then r = rect end
  end
  return r, editor.current().state
end

local function at(beat, f)
  local r, s = geo()
  local x = r.x + s.geo.x + math.floor((beat - s.left) * s.zoom)
  local y = r.y + s.geo.y + math.floor((1 - f) * (s.geo.rows - 0.01))
  return x, y
end

local function m(kind, x, y, button) paw.ui.mouse({ kind = kind, x = x, y = y, button = button or "left", mods = "" }) end

test("the mouse adds and drags points, draws over empty space and opens menus", function()
  start()
  local _, lane = lane_with({ { 0, -12 } })
  screen()
  local c = curves.target(paw.address.lane(lane.id))
  local x, y = at(2, 0.5)
  m("down", x, y) m("up", x, y)
  paw.mouse.forget()
  eq(#lane:points(), 2, "a click adds a point")
  eq(lane:points()[2][1], 2, "where it was clicked")
  local x2, y2 = at(3, 0.9)
  m("down", x, y) m("drag", x2, y2) m("up", x2, y2)
  paw.mouse.forget()
  eq(lane:points()[2][1], 3, "a point dragged moves in time")
  eq(c.frac(lane:points()[2][2]) > 0.8, true, "and in value")
  local a = at(4, 0.2)
  local b = at(6, 0.2)
  m("down", a, y) m("drag", b, y) m("up", b, y)
  paw.mouse.forget()
  eq(#lane:points() >= 5, true, "a drag over empty space draws: " .. beats(curves.target(paw.address.lane(lane.id)).points()))
  m("down", a, y, "right") m("up", a, y, "right")
  eq(screen():find("Remove the point", 1, true) ~= nil, true, "a right click on a point opens its menu")
  require("paw.menu").close(0)
  paw.mouse.forget()
  local ex, ey = at(7, 0.95)
  m("down", ex, ey, "right") m("up", ex, ey, "right")
  eq(screen():find("Thin out the points", 1, true) ~= nil, true, "elsewhere the curve's menu")
  require("paw.menu").close(0)
end)

test("an automation lane's and a parameter's menus open the curve", function()
  start()
  local t = paw.add_track({ name = "Pad" })
  local d = t:add_device("synth")
  local items = require("paw.mouse_menus").param(d.id, "cutoff")
  eq(items[1].label, "Automate this parameter", "the parameter's menu")
  items[1].run()
  eq(d:lane("cutoff") ~= nil, true, "it automates")
  items[2].run()
  eq(paw.buf.current().name, paw.address.param(d.id, "cutoff"), "and opens the curve")
end)

-- Windows -----------------------------------------------------------------------

test("a curve opens in a window of its own and draws there", function()
  start()
  lane_with({ { 0, -12 }, { 4, 0 } })
  paw.commands.exec("curve.window")
  eq(paw.canvas.open_views.curve ~= nil, true, "a window of its own")
  local lines = {}
  for _, row in ipairs(api.ui_view_snapshot("curve", 80, 20).rows) do
    local parts = {}
    for _, run in ipairs(row) do parts[#parts + 1] = run.text end
    lines[#lines + 1] = table.concat(parts)
  end
  eq(table.concat(lines, "\n"):find("2 points", 1, true) ~= nil, true, "drawn in cells")
end)

test("in a window of its own the plot is drawn in pixels between the cells' backgrounds and their text", function()
  start()
  lane_with({ { 0, -12 }, { 4, 0 } })
  paw.commands.exec("curve.window")
  T.after(function() paw.canvas.close("curve") end)
  local function drawing()
    local d = paw.canvas.paint("curve", 800, 400, { fresh = true })
    local kinds, sextants, first_poly, last_back, first_text = {}, 0, nil, 0, nil
    for i, op in ipairs(d.ops) do
      kinds[op[1]] = (kinds[op[1]] or 0) + 1
      if op[1] == "p" and not first_poly then first_poly = i end
      if op[1] == "m" then
        if op[8] == "" and not first_text and first_poly then first_text = i end
      end
      -- The window draws the cells' sextants and dots as rectangles smaller than a cell.
      if op[1] == "r" and op[4] < paw.canvas.cell.w - 0.01 and op[5] < paw.canvas.cell.h - 0.01 then sextants = sextants + 1 end
      if op[1] == "r" and i > 1 and not first_poly then last_back = i end
    end
    return kinds, sextants, first_poly, last_back, first_text
  end
  local kinds, sextants, first_poly, last_back, first_text = drawing()
  eq((kinds.p or 0) >= 2, true, "the line and the area under it, in pixels")
  local dots = sextants
  eq(first_poly > last_back, true, "over the cells' backgrounds")
  eq(first_text ~= nil and first_text > first_poly, true, "and under their text")
  paw.opt.graphics = false
  T.after(function() paw.opt.graphics = true end)
  kinds, sextants = drawing()
  eq(kinds.p, nil, "graphics off: cells")
  eq(sextants > dots + 20, true, string.format("the line in cells there and not with pictures: %d, %d", sextants, dots))
end)

-- Pictures ------------------------------------------------------------------------

test("where the terminal shows pictures the plot is a strip under the cells, one for each window", function()
  start()
  local _, lane = lane_with({ { 0, -12 }, { 4, 0 } })
  local function plot_text(lines, s)
    local out = {}
    for row = s.y, s.y + s.h - 1 do
      local chars = {}
      for ch in lines[row + 1]:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
      out[#out + 1] = table.concat(chars, "", s.x + 1, math.min(#chars, s.x + s.w))
    end
    return table.concat(out, "\n")
  end
  local cells = api.ui_snapshot(W, H)
  eq(paw.ui.rects.surfaces, nil, "no pictures: cells")

  api.ui_caps_set({ graphics = true, cell = { w = 10, h = 20 }, under = true })
  T.after(function() api.ui_caps_set({ graphics = false, cell = { w = 0, h = 0 } }) end)
  local lines = api.ui_snapshot(W, H)
  local s = paw.ui.rects.surfaces and paw.ui.rects.surfaces[1]
  local win = editor.current()
  eq(s and s.key, "curve:" .. win.id, "a strip for the window")
  eq(s.under, true, "under the cells")
  eq(s.paint, nil, "drawn by the editor, not the view's paint")
  local geo = win.state.geo
  eq(s.w, geo.w, "over the plot")
  eq(s.h, geo.rows)
  local before, after = plot_text(cells, s), plot_text(lines, s)
  eq(before ~= after, true, "the curve is not drawn in cells as well")
  eq(after:find("●", 1, true) ~= nil or after:find(paw.draw.g.point, 1, true) ~= nil, true, "the points stay cells")
  eq(table.concat(lines, "\n"):find("2 points", 1, true) ~= nil, true, "and so does the rest")

  -- What the strip draws: the curve and its fill, cut at the bars.
  local ops = paw.canvas.draw(function(g, px)
    local t = editor.target(win)
    editor.picture(g, px, t, t.points(), { left = 0, zoom = 4 })
  end, { w = 400, h = 200, cell = { w = 10, h = 20 } })
  local kinds = {}
  for _, op in ipairs(ops) do kinds[op[1]] = (kinds[op[1]] or 0) + 1 end
  eq((kinds.cut or 0) >= 1, true, "cut at a bar: " .. paw.inspect(ops[1]))
  eq(kinds.p, 2 * ((kinds.cut or 0) + 1), "a line and a fill between cuts")
  for _, op in ipairs(ops) do
    if op[1] == "cut" then eq(op[2] % 10, 0, "on a cell's edge") end
  end

  -- The same curve in two windows: two strips, each its own.
  paw.commands.exec("vs")
  api.ui_snapshot(W, H)
  local keys = {}
  for _, strip in ipairs(paw.ui.rects.surfaces or {}) do keys[#keys + 1] = strip.key end
  eq(#keys, 2, "a strip in each window")
  eq(keys[1] ~= keys[2], true, "kept apart")

  -- A terminal that cannot put text over a picture under it, or pictures off: cells.
  api.ui_caps_set({ graphics = true, cell = { w = 10, h = 20 }, under = false })
  api.ui_snapshot(W, H)
  eq(paw.ui.rects.surfaces, nil, "no strip under the text there")
  api.ui_caps_set({ graphics = true, cell = { w = 10, h = 20 }, under = true })
  paw.opt.graphics = false
  T.after(function() paw.opt.graphics = true end)
  api.ui_snapshot(W, H)
  eq(paw.ui.rects.surfaces, nil, "paw.opt.graphics off keeps cells")
end)
