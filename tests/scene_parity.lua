-- Tests that a view shows the same in a terminal and in a graphical
-- frontend. A frontend is sent a view as a scene (crates/paw-scene,
-- paw/scene.tl): the nodes its writes to its buffers make (`buf:text`,
-- `buf:fill`), and the strips it keeps as pictures. So every view must draw
-- through the buffer it is given (what it writes, written again on a screen
-- of its own, is its drawing cell for cell), and its scene lowered to cells
-- must be that drawing. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

-- The sizes every view is drawn at: a small terminal and a big one; and
-- the cell of a window, in pixels.
local SIZES = { { 80, 24 }, { 150, 45 } }
local CELL = { w = 8, h = 17 }

--- What a view writes to its buffers while it is drawn by itself at a
--- size, as calls of `api.grid_text`, `api.grid_fill` and `api.grid_image`
--- (`buf:image` in half blocks) in the screen's cells, and the snapshot it
--- makes.
local function record(name, width, height)
  local Buf = paw.ui.Buf
  local text, fill, image = Buf.text, Buf.fill, Buf.image
  local writes = {}
  Buf.text = function(self, x, y, s, style)
    writes[#writes + 1] = { "text", self.x + x, self.y + y, s, style, self.cx, self.cy, self.cw, self.ch }
    return text(self, x, y, s, style)
  end
  Buf.fill = function(self, x, y, w, h, char, style)
    writes[#writes + 1] = { "fill", self.x + x, self.y + y, w, h, char, style, self.cx, self.cy, self.cw, self.ch }
    return fill(self, x, y, w, h, char, style)
  end
  Buf.image = function(self, x, y, w, h, key)
    writes[#writes + 1] = { "image", key, self.x + x, self.y + y, w, h, self.cx, self.cy, self.cw, self.ch }
    return image(self, x, y, w, h, key)
  end
  local ok, snap = pcall(api.ui_view_snapshot, name, width, height)
  Buf.text, Buf.fill, Buf.image = text, fill, image
  if not ok then error(snap, 0) end
  return writes, snap
end

-- A view that writes again what another wrote.
local replay = {}
paw.ui.view("scene_parity_replay", {
  render = function()
    for _, w in ipairs(replay) do
      if w[1] == "text" then
        api.grid_text(unpack(w, 2, 9))
      elseif w[1] == "image" then
        api.grid_image(unpack(w, 2, 10))
      else
        api.grid_fill(unpack(w, 2, 11))
      end
    end
  end,
})

--- The first row where two drawings differ, as text, or nil.
local function differs(a, b)
  for y = 1, math.max(#a.rows, #b.rows) do
    local left, right = api.json_encode(a.rows[y] or {}), api.json_encode(b.rows[y] or {})
    if left ~= right then return string.format("row %d:\n  drawn %s\n  again %s", y - 1, left, right) end
  end
end

-- A view that writes to the screen around its buffer, which the check
-- below must notice.
paw.ui.view("scene_parity_around", {
  render = function(_, buf)
    buf:text(0, 0, "through", "Normal")
    api.grid_text(0, 1, "around", "Error", 0, 0, buf.width, buf.height)
  end,
})

-- A view with a strip of pixels under its cells, and one that paints.
paw.ui.view("scene_parity_strip", {
  render = function(_, buf)
    buf:fill(0, 0, buf.width, buf.height, " ", "Normal")
    local drawn = buf:strip(
      2,
      1,
      10,
      3,
      { key = "probe", under = true, draw = function(g, px) g:rect(0, 0, px.w, px.h, { fill = "#204060" }) end }
    )
    buf:text(0, 0, drawn and "pixels" or "cells", "Title")
    buf:text(3, 2, "+", "Normal")
  end,
})
paw.ui.view("scene_parity_paint", {
  paint = function(_, g, ctx) g:rect(0, 0, ctx.width, ctx.height, { fill = "#102030" }) end,
})
local OWN =
  { scene_parity_replay = true, scene_parity_around = true, scene_parity_strip = true, scene_parity_paint = true }

--- Every view there is, but this file's own, by name.
local function views()
  local out = {}
  for name in pairs(paw.ui.views:entries()) do
    if not OWN[name] then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

--- Where a view's drawing at a size is not what it wrote, or nil.
local function written(name, width, height)
  local writes, snap = record(name, width, height)
  replay = writes
  local again = api.ui_view_snapshot("scene_parity_replay", width, height)
  replay = {}
  return differs(snap, again)
end

--- A view's scene, as a window is sent it, `width` by `height` units: the
--- patch that brings an empty window up to it, decoded.
local function scene_of(name, width, height, id)
  paw.ui.render_scene(name, width, height, CELL)
  local patch = api.scene_end(0, id or "parity")
  return patch and api.json_decode(patch)
end

--- Where a view's scene lowered to cells is not what a window that draws
--- its cells shows (the strips under them kept as pictures), or nil.
local function lowered(name, width, height)
  local view = paw.ui.views:get(name)
  -- A view that paints is a picture, with no cells to compare.
  if view.paint then return nil end
  -- The two drawings are made one after the other, and a meter falls and
  -- a held peak lets go in between (the sound of an earlier test, on a
  -- slow machine): the meters stand still while they are drawn.
  local meter = api.part_meter
  api.part_meter = function() return 0.5, 0.25 end
  local draw = require("paw.draw")
  draw.clear_peak(0)
  for _, id in ipairs(api.part_list()) do
    draw.clear_peak(id)
  end
  paw.ui.pictures = {}
  local ok, snap = pcall(api.ui_view_snapshot, name, width, height)
  paw.ui.pictures = nil
  if not ok then
    api.part_meter = meter
    error(snap, 0)
  end
  -- A view that cannot draw by itself (a buffer's, with no buffer) shows
  -- where it failed, which differs with who asked.
  for _, row in ipairs(snap.rows) do
    if row[1] and row[1].text:find("^stack traceback:") then
      api.part_meter = meter
      return nil
    end
  end
  api.scene_forget(0)
  local err
  ok, err = pcall(scene_of, name, width, height)
  api.part_meter = meter
  if not ok then error(err, 0) end
  return differs(snap, api.scene_cells(0, "parity"))
end

--- The views among `names` that `check` finds fault with, and where.
local function all_checked(names, check)
  local bad = {}
  for _, name in ipairs(names) do
    for _, size in ipairs(SIZES) do
      local where = check(name, size[1], size[2])
      if where then bad[#bad + 1] = name .. " at " .. size[1] .. "x" .. size[2] .. ", " .. where end
    end
  end
  return table.concat(bad, "\n")
end

test("every view draws only through its buffer, at a small size and a big one", function()
  fresh()
  eq(all_checked(views(), written), "", "views whose drawing is not what they wrote")
  eq(written("scene_parity_around", 40, 4) ~= nil, true, "a view writing around its buffer is noticed")
end)

test("every view's scene lowered to cells is its drawing", function()
  fresh()
  eq(all_checked(views(), lowered), "", "views whose scene is not their drawing")
  api.scene_forget(0)
end)

test("a scene drawn again is sent as what changed of it", function()
  fresh()
  api.scene_forget(0)
  local first = scene_of("scene_parity_strip", 30, 6, "again")
  eq(first.full, true, "the first is the whole scene")
  eq(first.size[1] == 30 and first.size[2] == 6, true, "of the size asked")
  eq(scene_of("scene_parity_strip", 30, 6, "again"), nil, "drawn the same, it says nothing")
  -- A larger window: the fill of the background is another node, the rest
  -- stays as it was.
  local wider = scene_of("scene_parity_strip", 40, 6, "again")
  local keys = {}
  for _, node in ipairs(wider.set or {}) do
    keys[#keys + 1] = node.k
  end
  table.sort(keys)
  eq(table.concat(keys, " "), "f0,0,40,6 f0,0,40,6#2", "the backgrounds, new")
  eq(#(wider.drop or {}), 2, "and the old ones gone")
  eq(wider.full, nil, "not the whole scene")
  api.scene_forget(0)
end)

test("a strip under a view's cells is a picture under them in its scene", function()
  fresh()
  api.scene_forget(0)
  local patch = scene_of("scene_parity_strip", 30, 6)
  local picture, texts
  for _, node in ipairs(patch.set) do
    if node.t == "picture" then picture = node end
    if node.t == "run" then texts = (texts or "") .. node.text .. "|" end
  end
  eq(texts, "pixels|+|", "the view knew it had pixels, and drew its cells over them")
  eq(picture.under, true, "under the cells")
  eq(api.json_encode(picture.r), "[2,1,10,3]", "where the strip is, in cells")
  eq(picture.px[1] == 10 * CELL.w and picture.px[2] == 3 * CELL.h, true, "drawn at the window's cell")
  eq(picture.ops[1][6], "#204060", "the strip's drawing")
  -- Lowered to cells it is what the cells say: a picture has none.
  local cells = api.scene_cells(0, "parity")
  eq(cells.rows[3][1].text:sub(4, 4), "+", "the cell over the picture")
  api.scene_forget(0)
end)

test("a view that paints is one picture of the whole in its scene", function()
  fresh()
  api.scene_forget(0)
  local patch = scene_of("scene_parity_paint", 20.5, 4)
  eq(#patch.set, 1, "one node")
  local picture = patch.set[1]
  eq(picture.t, "picture", "a picture")
  eq(api.json_encode(picture.r), "[0,0,20.5,4]", "over the whole window, fractions and all")
  eq(picture.px[1] == 20.5 * CELL.w and picture.px[2] == 4 * CELL.h, true, "painted at its size in pixels")
  eq(picture.ops[1][6], "#102030", "its drawing")
  api.scene_forget(0)
end)

test(
  "the piano roll with notes on its plane, two clips edited, a drawing and a selection is its drawing in its scene",
  function()
    fresh()
    local saved = paw.opt.note_zoom
    T.after(function()
      paw.opt.note_zoom = saved
      paw.ui.views:get("pianoroll"):set_step(nil)
      paw.keymap.feed("<Esc><Esc>")
      paw.roll_clips.only()
      paw.ui.hide("pianoroll")
      api.scene_forget(0)
    end)
    local t = paw.add_part({ name = "keys" })
    local u = paw.add_part({ name = "bass" })
    local a = t:add_clip({
      start = 0,
      length = 8,
      notes = {
        { pitch = 60, start = 0, length = 1 },
        { pitch = 64, start = 1.25, length = 0.33 },
        { pitch = 67, start = 2.1, length = 3 },
      },
    })
    local b = u:add_clip({ start = 2, length = 4, notes = { { pitch = 48, start = 0.5, length = 2 } } })
    paw.roll_clips.open({ a.id, b.id }, a.id)
    local roll = paw.ui.views:get("pianoroll")
    roll.top, roll.scroll, roll.pitch, roll.beat = 70, 0, 64, 1.25
    paw.frontend.act.select_note(a.id, 3, "only")
    -- Notes between cells at every zoom: a column a beat, two, five.
    for _, zoom in ipairs({ 1, 2, 5 }) do
      paw.opt.note_zoom = zoom
      eq(all_checked({ "pianoroll" }, written), "", "at " .. zoom .. " columns a beat, drawn through its buffer")
      eq(all_checked({ "pianoroll" }, lowered), "", "at " .. zoom .. " columns a beat, its scene is its drawing")
    end
    -- Insert mode's drawing, and visual mode's selection over the notes.
    paw.ui.show("pianoroll")
    paw.ui.focus("pianoroll")
    paw.keymap.feed("ill")
    eq(all_checked({ "pianoroll" }, lowered), "", "drawing a note")
    paw.keymap.feed("<Esc>vj")
    eq(all_checked({ "pianoroll" }, lowered), "", "with a selection")
    api.scene_forget(0)
    local patch = scene_of("pianoroll", 120, 40)
    local notes = 0
    for _, node in ipairs(patch.set) do
      if node.role == "note" then notes = notes + 1 end
    end
    eq(notes >= 4, true, "its notes are roles in the scene: " .. notes)
  end
)

test(
  "the arrange view with clips on its plane, an audio clip, lanes and take lanes as rows and a selection is its drawing in its scene",
  function()
    fresh()
    local saved = paw.opt.zoom
    T.after(function()
      paw.opt.zoom = saved
      paw.keymap.feed("<Esc><Esc>")
      api.scene_forget(0)
    end)
    local t = paw.add_part({ name = "keys" })
    local u = paw.add_part({ name = "loop" })
    local short = t:add_clip({
      start = 0.5,
      length = 3.3,
      notes = { { pitch = 60, start = 0, length = 1 }, { pitch = 67, start = 2, length = 1 } },
    })
    paw.takes.new(short.id) -- its take mark, too long to follow its name
    t:add_clip({ start = 5, length = 2 })
    local samples = {}
    for i = 1, 48000 do
      samples[i] = 0.5 * math.sin(i / 30)
    end
    u:add_clip({ file = T.write_wav(T.scratch .. "/parity-arrange.wav", samples), start = 2.25, length = 2 })
    paw.frontend.act.lane(t.id, "volume")
    paw.lanes.toggle(t.id)
    paw.flush()
    -- Clips between cells at every zoom: a column a beat, two, three and a half.
    for _, zoom in ipairs({ 1, 2, 3.5 }) do
      paw.opt.zoom = zoom
      eq(all_checked({ "arrange" }, written), "", "at " .. zoom .. " columns a beat, drawn through its buffer")
      eq(all_checked({ "arrange" }, lowered), "", "at " .. zoom .. " columns a beat, its scene is its drawing")
    end
    paw.ui.focus("arrange")
    paw.keymap.feed("vl")
    eq(all_checked({ "arrange" }, lowered), "", "with a selection")
    paw.keymap.feed("<Esc>")
    api.scene_forget(0)
    local patch = scene_of("arrange", 150, 45)
    local clips = 0
    for _, node in ipairs(patch.set) do
      if node.role == "clip" then clips = clips + 1 end
    end
    eq(clips, 3, "its clips are roles in the scene")
  end
)

-- Once every other test has run, since loading every extension changes
-- what the tests of the core see.
T.last("every bundled extension's view draws only through its buffer, and its scene is its drawing", function()
  fresh()
  for _, entry in ipairs(api.read_dir("extensions")) do
    if entry.is_dir then paw.ext.load("extensions/" .. entry.name) end
  end
  eq(
    paw.ui.views:get("notation") ~= nil and paw.ui.views:get("undotree") ~= nil,
    true,
    "the extensions' views are among them"
  )
  eq(all_checked(views(), written), "", "views whose drawing is not what they wrote")
  eq(all_checked(views(), lowered), "", "views whose scene is not their drawing")
  api.scene_forget(0)
end)
