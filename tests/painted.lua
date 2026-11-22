-- Tests of braille in the window's cells and of comping with the mouse in the
-- terminal. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fresh, render = T.test, T.eq, T.near, T.fresh, T.render
local api = paw.api

local function start()
  fresh()
  api.engine_restart({ backend = "null" })
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  for name in pairs(paw.canvas.open_views) do
    paw.canvas.close(name)
  end
  paw.ui.focus("arrange")
end

-- Braille ---------------------------------------------------------------------------

paw.ui.view("braille_probe", {
  title = "Braille",
  render = function(_, buf) buf:text(0, 0, "a⣿b⠁", "Normal") end,
})

--- The dots a drawing has: the small rectangles, as `x,y` of their corners.
local function dots(ops)
  local out = {}
  for _, op in ipairs(ops) do
    if op[1] == "r" and op[4] < 4 and op[5] < 4 then out[#out + 1] = op end
  end
  return out
end

test("braille is drawn as dots, since the window's font has none", function()
  start()
  paw.canvas.cell = { w = 10, h = 20 }
  local ops = {}
  local g = paw.canvas.Painter.sub(
    setmetatable({ ops = ops, x = 0, y = 0, width = 100, height = 40 }, paw.canvas.Painter),
    0,
    0,
    100,
    40
  )
  g:mono(0, 0, "a⣿b⠁⠀", { color = "#ffffff" })
  local runs = {}
  for _, op in ipairs(ops) do
    if op[1] == "m" then runs[#runs + 1] = op[6] end
  end
  eq(table.concat(runs), "a b  ", "the run keeps its cells, braille left blank")
  local found = dots(ops)
  eq(#found, 9, "eight dots for the full cell, one for the other, none for the blank pattern")
  -- The full cell is the second one: its dots are in two columns of four.
  local columns, rows = {}, {}
  for i = 1, 8 do
    columns[math.floor(found[i][2] * 10 + 0.5)] = true
    rows[math.floor(found[i][3] * 10 + 0.5)] = true
  end
  local n_columns, n_rows = 0, 0
  for _ in pairs(columns) do
    n_columns = n_columns + 1
  end
  for _ in pairs(rows) do
    n_rows = n_rows + 1
  end
  eq(n_columns, 2, "in two columns")
  eq(n_rows, 4, "and four rows")
  eq(found[1][2] >= 10 and found[8][2] < 20, true, "inside its cell")
  -- Dot 1 is the top left of its cell.
  near(found[9][2] + found[9][4] / 2, 30 + 2.5, 0.01, "the lone dot of the fourth cell is its top left one")
  near(found[9][3] + found[9][5] / 2, 2.5, 0.01, "at the top")
end)

test("a view drawn in cells shows braille as dots in a window", function()
  start()
  paw.canvas.open_view("braille_probe")
  local drawing = paw.canvas.paint("braille_probe", 400, 200, { cell = { w = 10, h = 20 }, fresh = true })
  local text = {}
  for _, op in ipairs(drawing.ops) do
    if op[1] == "m" then text[#text + 1] = op[6] end
  end
  eq(table.concat(text):find("[\226][\160-\163]") == nil, true, "no braille is left to the font")
  eq(#dots(drawing.ops), 9, "its dots are drawn instead")
  paw.canvas.close("braille_probe")
end)

paw.ui.view("curve_probe", {
  title = "Curve",
  render = function(_, buf)
    paw.draw.curve(buf, 0, 4, function(i) return i / (2 * buf.width) end, "Normal")
  end,
})

test("a curve in a window is drawn in braille dots, as in the terminal", function()
  start()
  paw.opt.braille, paw.opt.ascii, paw.opt.curve_glyphs = true, false, "braille"
  paw.canvas.open_view("curve_probe")
  local drawing = paw.canvas.paint("curve_probe", 400, 200, { cell = { w = 10, h = 20 }, fresh = true })
  local text = {}
  for _, op in ipairs(drawing.ops) do
    if op[1] == "m" then text[#text + 1] = op[6] end
  end
  local shown = table.concat(text)
  eq(
    shown:find("▁", 1, true) == nil and shown:find("─", 1, true) == nil and shown:find("▔", 1, true) == nil,
    true,
    "not as lines"
  )
  eq(#dots(drawing.ops) > 20, true, "but as dots")
  paw.canvas.close("curve_probe")
end)

test("a curve in a window is drawn in sextants as rectangles, the font having none", function()
  start()
  paw.opt.braille, paw.opt.ascii, paw.opt.curve_glyphs = true, false, "sextant"
  paw.canvas.open_view("curve_probe")
  local drawing = paw.canvas.paint("curve_probe", 400, 200, { cell = { w = 10, h = 20 }, fresh = true })
  local text = {}
  for _, op in ipairs(drawing.ops) do
    if op[1] == "m" then text[#text + 1] = op[6] end
  end
  eq(table.concat(text):find("[\240-\244]") == nil, true, "no sextant is left to the font")
  local rects = 0
  for _, op in ipairs(drawing.ops) do
    if op[1] == "r" and op[4] == 5 then rects = rects + 1 end
  end
  eq(rects > 20, true, "but rectangles of half a cell")
  paw.canvas.close("curve_probe")
  paw.opt.curve_glyphs = "sextant"
end)

-- Comping with the mouse ---------------------------------------------------------------

--- A track with an audio clip of eight beats whose three takes are three
--- stretches of one file, the third playing; its take lanes shown.
local function three_takes()
  local source = T.tone("source", 32)
  paw.project.tempo = 120
  local wav = render({ tail = 0, bits = 32 })
  source:remove()
  local t = paw.add_track({ name = "vox" })
  t:add_clip({
    file = wav.path,
    start = 0,
    length = 8,
    offset = 8,
    meta = {
      takes = {
        active = 3,
        origin = 8,
        list = {
          { name = "vox.1", file = wav.path, offset = 0, gain = 0 },
          { name = "vox.2", file = wav.path, offset = 4, gain = -6 },
          { name = "vox.3" },
        },
      },
    },
  })
  paw.takes.show_lanes(t.id, true)
  -- A cell is a quarter of a beat, and the ends of a drag land on beats.
  paw.opt.zoom, paw.opt.grid = 4, 1
  api.undo_checkpoint()
  return t
end

--- Draw the arrange view in the terminal and say where a take lane is: its
--- row, and where beat `beat` is.
local function lanes_view(t)
  api.ui_view_snapshot("arrange", 120, 30)
  local arrange = paw.ui.views.arrange
  paw.ui.rects =
    { { name = "arrange", x = 0, y = 0, w = 120, h = 29 }, { name = "status", x = 0, y = 29, w = 120, h = 1 } }
  local rows = {}
  for _, row in ipairs(arrange.geometry.layout.rows) do
    if row.kind == "take" and row.id == t.id then rows[row.take] = row.y end
  end
  local g = arrange.geometry
  return rows, function(beat) return g.hw + math.floor((beat - arrange.scroll) * g.zoom + 0.5) end, g
end

--- Which take each clip of a track plays, with where it starts.
local function plays(t)
  local out = {}
  for _, c in ipairs(t:clips()) do
    out[#out + 1] = c.start .. "+" .. c.length .. ":" .. select(2, paw.takes.count(c.id))
  end
  return table.concat(out, " ")
end

test("dragging across a take lane with the mouse in the terminal comps that stretch from the take", function()
  start()
  local t = three_takes()
  local rows, x_of = lanes_view(t)
  eq(rows[1] ~= nil and rows[3] ~= nil, true, "three take lanes are on the screen")
  local function mouse(kind, x, y) paw.ui.mouse({ kind = kind, x = x, y = y, button = "left", mods = "" }) end
  mouse("down", x_of(2), rows[1])
  mouse("drag", x_of(4) - 1, rows[1])
  eq(paw.ui.views.arrange.comp ~= nil, true, "the stretch is marked while the button is down")
  mouse("up", x_of(6) - 1, rows[1])
  api.undo_checkpoint()
  eq(plays(t), "0+2:3 2+4:1 6+2:3", "take 1 plays over the dragged stretch, the clip cut at its ends")
  paw.undo()
  eq(#t:clips(), 1, "and it was one undo step")
  paw.redo()
end)

test(
  "a drag that ends outside the arrange view still comps, and a click chooses the take for the piece under it",
  function()
    start()
    local t = three_takes()
    local rows, x_of = lanes_view(t)
    local function mouse(kind, x, y) paw.ui.mouse({ kind = kind, x = x, y = y, button = "left", mods = "" }) end
    mouse("down", x_of(1), rows[2])
    mouse("up", x_of(4) - 1, 29)
    api.undo_checkpoint()
    eq(plays(t), "0+1:3 1+3:2 4+4:3", "the release below the lane belongs to the drag")
    -- A click on lane 1 gives the piece under it that take.
    mouse("down", x_of(5), rows[1])
    mouse("up", x_of(5), rows[1])
    eq(plays(t), "0+1:3 1+3:2 4+4:1", "a click does the same for the piece under it")
  end
)

test("clicking a take lane's label makes it the active take", function()
  start()
  local t = three_takes()
  local rows = lanes_view(t)
  local function mouse(kind, x, y) paw.ui.mouse({ kind = kind, x = x, y = y, button = "left", mods = "" }) end
  mouse("down", 3, rows[2])
  mouse("up", 3, rows[2])
  eq(plays(t), "0+8:2", "the whole track plays take 2")
  mouse("down", 3, rows[1])
  mouse("up", 3, rows[1])
  eq(plays(t), "0+8:1", "and then take 1")
end)
