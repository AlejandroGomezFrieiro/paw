-- Tests of surfaces: the cells a view that paints keeps for its pixels in a
-- terminal that shows images (`buf:surface`), the pointer over them in
-- pixels, and the music fonts' metadata. The pixels themselves are made
-- in the frontend; crates/paw-raster and crates/paw-tui test those.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh, after = T.test, T.eq, T.fresh, T.after
local api = paw.api

local W, H = 100, 30

--- Tables alike in what they hold.
local function same(got, want, what) eq(paw.inspect(got), paw.inspect(want), what) end

--- A terminal that shows images, cells of 10 by 20 pixels, until the test ends.
local function images(on)
  api.ui_caps_set({ graphics = on ~= false, cell = { w = 10, h = 20 }, pixel_mouse = true, fg = "#cdd6f4" })
  after(function() api.ui_caps_set({ graphics = false, cell = { w = 0, h = 0 } }) end)
end

local probe = paw.ui.view("surface_probe", {
  title = "Probe",
  render = function(self, buf)
    buf:text(0, 0, "title row", "Normal")
    if buf:surface(0, 1, buf.width, buf.height - 1) then return end
    buf:text(0, 1, "drawn in cells", "Normal")
  end,
  paint = function(self, g, ctx)
    self.ctx = ctx
    g:rect(0, 0, ctx.width, ctx.height, { fill = "#202020" })
  end,
  pointer = function(self, e) self.events[#self.events + 1] = e end,
  events = {},
})

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  paw.ui.focus("arrange")
  probe.events, probe.ctx = {}, nil
  paw.mouse.forget()
  -- The tests after these find the screen as it was.
  after(function()
    while paw.ui.float do paw.ui.close() end
    paw.ui.focus("arrange")
    paw.mouse.forget()
  end)
end

--- Open the probe floating, draw the screen, and return its surface.
local function shown()
  paw.ui.open("surface_probe", { title = "Probe", width = 40, height = 12 })
  local lines = api.ui_snapshot(W, H)
  return (paw.ui.rects.surfaces or {})[1], lines
end

test("a view keeps cells for its pixels where the terminal shows images, and draws cells elsewhere", function()
  start()
  local s, lines = shown()
  eq(s, nil, "no images: no surface")
  eq(table.concat(lines, "\n"):find("drawn in cells", 1, true) ~= nil, true, "the cells are drawn")

  images()
  local s, lines = shown()
  eq(s and s.name, "surface_probe", "a surface for the view")
  -- The float is 40 by 12 with a border: inside 38 by 10, less the title row.
  same({ s.w, s.h, s.cell.w, s.cell.h }, { 38, 9, 10, 20 }, "its cells and their size")
  local row = {}
  for ch in lines[s.y + 1]:gmatch("[%z\1-\127\194-\244][\128-\191]*") do row[#row + 1] = ch end
  eq(table.concat(row, "", s.x + 1, s.x + s.w):find("%S"), nil, "its cells are blank")
  eq(table.concat(lines, "\n"):find("drawn in cells", 1, true), nil, "no cells drawn")
  same(probe.ctx and { probe.ctx.width, probe.ctx.height }, { 380, 180 }, "painted in pixels of whole cells")
  eq(probe.ctx.surface, true, "told it is a surface")
  eq(probe.ctx.cell.w, 10, "told the terminal's cell size")
  eq(probe.ctx.fg, "#cdd6f4", "and its colours")

  paw.opt.graphics = false
  after(function() paw.opt.graphics = true end)
  eq(shown(), nil, "paw.opt.graphics off keeps cells")
end)

test("a view that is all pixels says so, and the window's views keep cells", function()
  start()
  images()
  paw.ui.view("surface_whole", {
    surface = true,
    render = function(_, buf) buf:text(0, 0, "never", "Normal") end,
    paint = function(_, g, ctx) g:rect(0, 0, ctx.width, ctx.height, { fill = "#000000" }) end,
  })
  after(function() paw.ui.views.surface_whole = nil end)
  paw.ui.open("surface_whole", { width = 20, height = 6 })
  local lines = api.ui_snapshot(W, H)
  local s = paw.ui.rects.surfaces[1]
  same({ s.name, s.w, s.h }, { "surface_whole", 18, 4 }, "the whole inside of the float")
  eq(table.concat(lines, "\n"):find("never", 1, true), nil, "its cells are not drawn")
  paw.ui.close()
  api.ui_snapshot(W, H)
  eq(paw.ui.rects.surfaces, nil, "the arrange view keeps cells")
end)

test("the pointer over a surface reaches the view's pointer in pixels of its drawing", function()
  start()
  images()
  local s = shown()
  local x0, y0 = s.x * 10, s.y * 20
  local function m(kind, x, y, extra)
    local e = { kind = kind, x = math.floor(x / 10), y = math.floor(y / 20), button = kind:match("scroll") and "" or "left", mods = "", px = x, py = y }
    for k, v in pairs(extra or {}) do e[k] = v end
    paw.ui.mouse(e)
  end
  m("move", x0 + 37, y0 + 45, { button = "" })
  m("down", x0 + 37, y0 + 45, { mods = "C" })
  m("drag", x0 + 52, y0 + 49)
  -- Out of the surface, the drag is still the surface's.
  m("drag", x0 - 30, y0 - 50)
  m("up", x0 - 30, y0 - 50)
  local got = {}
  for _, e in ipairs(probe.events) do got[#got + 1] = { e.kind, e.x, e.y, e.ctrl } end
  same(got, {
    { "hover", 37, 45, false }, { "down", 37, 45, true }, { "move", 52, 49, false },
    { "move", -30, -50, false }, { "up", -30, -50, false },
  }, "hover, press, drags and release, exact to the pixel")
  eq(paw.ui.focused, "surface_probe", "a press gives it the keyboard")

  probe.events = {}
  m("down", x0 + 5, y0 + 5)
  m("up", x0 + 5, y0 + 5)
  m("down", x0 + 6, y0 + 6)
  local kinds = {}
  for _, e in ipairs(probe.events) do kinds[#kinds + 1] = e.kind end
  same(kinds, { "down", "up", "down", "double" }, "a second press on the cell is a double click")
  m("up", x0 + 6, y0 + 6)

  probe.events = {}
  m("scroll_up", x0 + 5, y0 + 5)
  same({ probe.events[1].kind, probe.events[1].dy, probe.events[1].dx }, { "wheel", 60, 0 }, "a notch up is three rows")

  -- A terminal that reports cells: the middle of the cell.
  probe.events = {}
  paw.ui.mouse({ kind = "down", x = s.x + 2, y = s.y + 1, button = "left", mods = "" })
  same({ probe.events[1].x, probe.events[1].y }, { 25, 30 }, "the middle of the cell")
  same({ probe.events[1].col, probe.events[1].row }, { s.x + 2, s.y + 1 }, "and the screen cell, for a menu")
  paw.ui.mouse({ kind = "up", x = s.x + 2, y = s.y + 1, button = "left", mods = "" })

  -- The title row is cells: the view's on_mouse would have it, not pointer.
  probe.events = {}
  paw.ui.mouse({ kind = "down", x = s.x + 2, y = s.y - 1, button = "left", mods = "" })
  eq(#probe.events, 0, "outside the surface it is not pixels")
end)

test("a music font's metadata is read from the font built in", function()
  local leland = api.smufl()
  eq(leland.fontName, "Leland")
  eq(leland.glyphs.gClef, 0xE050, "glyph names to code points")
  eq(leland.glyphBBoxes.noteheadBlack.bBoxNE[1] > 1, true, "a black notehead is over a staff space wide")
  eq(leland.engravingDefaults.staffLineThickness > 0, true)
  eq(api.smufl("Bravura").fontName, "Bravura")
  eq(api.smufl("petaluma").fontName, "Petaluma")
  eq(api.smufl("Times"), nil)
end)

test("a drawing marks glyphs, barlines and layers for the frontend to make into pixels", function()
  paw.ui.view("surface_marks", {
    paint = function(_, g)
      local part = g:sub(10, 20, 200, 100)
      part:glyph(5, 40, 32, 0xE050)
      part:cut(100, 0, 80)
      part:layer("caret")
      part:glyph(500, 40, 32, 0xE0A4)
    end,
  })
  after(function() paw.ui.views.surface_marks = nil end)
  local window_cell = paw.canvas.cell
  local ops = paw.canvas.paint("surface_marks", 400, 200, { surface = true, glyphs = true, cell = { w = 11, h = 23 } }).ops
  same(ops, {
    { "g", 15, 60, 32, 0xE050, paw.canvas.palette.text, "Leland" },
    { "cut", 110, 20, 100 },
    { "layer", "caret" },
  }, "placed from the part's corner, and a glyph outside it left out")
  eq(paw.canvas.cell, window_cell, "a terminal's cell is not taken for the window's")
end)
