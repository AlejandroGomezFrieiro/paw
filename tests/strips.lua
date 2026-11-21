-- Tests of pictures under the cells (`buf:strip`) beyond the curve editor's:
-- `paw.plot`'s bars and waveform and their twins in cells, an audio clip's
-- waveform in the arrange view, the piano roll's controller strip. Loaded
-- by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local W, H = 120, 36
local PIXELS = { graphics = true, cell = { w = 10, h = 20 }, under = true }

--- The rows of the screen from the one that holds `from` (the first row
--- of the view `from` names when there is one), `count` of them: what a
--- test compares, apart from meters that fall back as time passes.
local function screen(from, count)
  local lines = api.ui_snapshot(W, H)
  local top
  for _, r in ipairs(paw.ui.rects) do
    if r.name == from then top = r.y + 1 end
  end
  for i, line in ipairs(lines) do
    if not top and line:find(from, 1, true) then top = i end
  end
  return table.concat(lines, "\n", top, math.min(#lines, top + count - 1))
end

--- Pictures on, for the rest of a test.
local function pictures()
  api.ui_caps_set(PIXELS)
  T.after(function() api.ui_caps_set({ graphics = false, cell = { w = 0, h = 0 } }) end)
end

--- The strip kept under `key` in the last drawing, or nil.
local function strip(key)
  for _, s in ipairs(paw.ui.rects.surfaces or {}) do
    if s.key == key then return s end
  end
end

--- What a strip draws, as `paint_surfaces` asks it.
local function ops_of(s)
  local cw, ch = s.cell.w, s.cell.h
  return paw.canvas.draw(s.draw, {
    w = s.whole_w * cw, h = s.whole_h * ch, cell = s.cell,
    view = { x = s.left * cw, y = s.top * ch, w = s.w * cw, h = s.h * ch },
  })
end

local function count(ops, kind, colour)
  local n = 0
  for _, op in ipairs(ops) do
    if op[1] == kind and (not colour or op[6] == colour or op[3] == colour or op[5] == colour) then n = n + 1 end
  end
  return n
end

--- A view that runs `draw(buf)` in a float of its own, and the screen drawn.
local function in_cells(draw)
  paw.ui.view("plot_test", { render = function(_, buf) draw(buf) end })
  paw.ui.open("plot_test", { width = 24, height = 8 })
  local lines = api.ui_snapshot(W, H)
  paw.ui.close()
  return table.concat(lines, "\n")
end

test("paw.plot draws bars and a waveform in pixels, and each has a twin in cells", function()
  fresh()
  local px = { w = 400, h = 80, cell = { w = 10, h = 20 } }
  local ops = paw.canvas.draw(function(g, p)
    paw.plot.bars(g, p, { items = { { beat = 0, value = 1 }, { beat = 2, value = 0.5, bright = true } }, pixels_per_beat = 40 })
  end, px)
  eq(count(ops, "r"), 4, "a bar and its head for each")
  local peaks = {}
  for i = 1, 400 do peaks[i] = { -0.5, i == 200 and 1 or 0.5, 0.3 } end
  ops = paw.canvas.draw(function(g, p) paw.plot.wave(g, p, { peaks = function(n) eq(n, 400, "a peak a pixel") return peaks end }) end, px)
  local fills = 0
  for _, op in ipairs(ops) do if op[1] == "p" and op[5] ~= "" then fills = fills + 1 end end
  eq(fills >= 2, true, "the wave and its RMS band, filled")
  local P = require("paw.theme").palette
  eq(count(ops, "r", paw.plot.alpha(P.red, 0.8)), 1, "the column at full scale in red")

  local shown = in_cells(function(buf)
    paw.plot.bars_cells(buf:sub(0, 0, 10, 2), { items = { { beat = 1, value = 1 }, { beat = 3, value = 0.5 } }, zoom = 1 })
    paw.plot.curve_cells(buf:sub(0, 2, 20, 2), { points = { { beat = 0, value = 0 }, { beat = 10, value = 1 } }, zoom = 2 })
    paw.plot.wave_cells(buf:sub(0, 4, 16, 2), { peaks = function(n) local out = {} for i = 1, n do out[i] = { -0.9, 0.9 } end return out end })
  end)
  eq(shown:find("█", 1, true) ~= nil, true, "bars in eighth blocks")
  local sextant = false
  for cp = 0x1FB00, 0x1FB3B do if shown:find(paw.draw.sextant(cp - 0x1FB00 + 1), 1, true) then sextant = true end end
  eq(sextant or shown:find("▐", 1, true) ~= nil, true, "the curve in sextants")
end)

--- A mono 16-bit file of `seconds` at 48 kHz of a loud square wave.
local function loud_file(name, seconds)
  local n = math.floor(48000 * seconds)
  local hi, lo = string.char(0xff, 0x7f), string.char(0x01, 0x80)
  local parts = {}
  for i = 1, n do parts[i] = (math.floor(i / 50) % 2 == 0) and hi or lo end
  local data = table.concat(parts)
  local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
  local function u32(v) return u16(v % 65536) .. u16(math.floor(v / 65536)) end
  local path = T.scratch .. "/" .. name .. ".wav"
  T.write_file(path, "RIFF" .. u32(36 + #data) .. "WAVEfmt " .. u32(16) .. u16(1) .. u16(1) .. u32(48000)
    .. u32(96000) .. u16(2) .. u16(16) .. "data" .. u32(#data) .. data)
  return path
end

test("an audio clip's waveform is a strip under its cells, of the whole clip, kept as it scrolls", function()
  fresh()
  local t = paw.add_track({ name = "loop" })
  local clip = t:add_clip({ start = 0, file = loud_file("loud", 8) })
  paw.cursor.set_track(t)
  paw.opt.zoom, paw.opt.track_height = 8, 4
  T.after(function() paw.opt.zoom, paw.opt.track_height = 2, "auto" end)
  local cells = screen("loop", 4)
  eq(strip("arrange:wave:" .. clip.id), nil, "no pictures: cells")

  pictures()
  api.ui_snapshot(W, H)
  local s = strip("arrange:wave:" .. clip.id)
  eq(s ~= nil and s.under, true, "a strip under the clip's cells")
  local length = api.clip_get(clip.id).length
  eq(s.whole_w, math.max(1, math.floor(length * 8 + 0.5)), "as wide as the whole clip")
  local first = ops_of(s)
  eq(count(first, "p") >= 2, true, "drawn in pixels")
  eq(count(first, "r", paw.plot.alpha(require("paw.theme").palette.red, 0.8)) >= 1, true, "full scale in red")

  -- Scrolled four beats on: the clip's start is off the left edge, the
  -- strip the same, and what it draws there the same as before.
  paw.ui.views.arrange.scroll = 4
  api.ui_snapshot(W, H)
  s = strip("arrange:wave:" .. clip.id)
  eq(s.left, 32, "four beats of it off the left")
  local again, seen, same = ops_of(s), {}, 0
  for _, op in ipairs(first) do seen[table.concat(op, " ")] = true end
  for _, op in ipairs(again) do if seen[table.concat(op, " ")] then same = same + 1 end end
  eq(same >= 2, true, "stretches drawn before are drawn the same: " .. same)
  paw.ui.views.arrange.scroll = 0

  -- Pictures off: the cells as before.
  paw.opt.graphics = false
  T.after(function() paw.opt.graphics = true end)
  eq(screen("loop", 4), cells, "graphics off draws the same cells")
end)

test("the piano roll's controller strip is a strip under its cells, the moves marked", function()
  fresh()
  local roll = paw.ui.views.pianoroll
  local t = paw.add_track({ name = "keys" })
  local clip = t:add_clip({ name = "riff", start = 0, length = 8, notes = { { pitch = 60, start = 0, length = 1 } },
    controls = { { start = 1, type = "bend", value = 0.5 }, { start = 3, type = "bend", value = -0.5 } } })
  roll:edit(clip)
  roll.top, roll.scroll, roll.pitch, roll.beat = 72, 0, 60, 0
  local strip_view = require("paw.views.pianoroll_strip")
  strip_view.show("bend")
  T.after(function() strip_view.show(nil) end)
  local cells = screen("pianoroll", 30)
  pictures()
  api.ui_snapshot(W, H)
  local s = strip("pianoroll:strip")
  eq(s ~= nil and s.under, true, "a strip under the controller's cells")
  local ops = ops_of(s)
  eq(count(ops, "p") >= 1, true, "the value held, as a line")
  local marks = 0
  local colour = paw.draw.track_colour(api.track_get(t.id))
  for _, op in ipairs(ops) do if op[1] == "r" and op[6] == colour and op[4] == 4 then marks = marks + 1 end end
  eq(marks, 2, "a mark on each move")
  paw.opt.graphics = false
  T.after(function() paw.opt.graphics = true end)
  eq(screen("pianoroll", 30), cells, "graphics off draws the same cells")
end)

test("a picture of pixels is half blocks in a terminal without images and a picture in a window's scene", function()
  fresh()
  -- Red, green; blue and clear below.
  local key = paw.canvas.image(string.char(255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 0, 0, 0, 0), 2, 2)
  paw.ui.view("image_test", { render = function(_, buf) buf:image(1, 0, 2, 1, key) end })
  local snap, runs = api.ui_view_snapshot("image_test", 4, 1), {}
  for _, run in ipairs(snap.rows[1]) do
    if run.text:find("[^ ]") then runs[#runs + 1] = run.text .. " " .. run.fg .. " " .. run.bg end
  end
  eq(table.concat(runs, ", "), "▀ #ff0000 #0000ff, ▀ #00ff00 " .. snap.bg, "two pixels a cell, the clear one the background")
  api.scene_forget(0, "image")
  paw.ui.render_scene("image_test", 4, 1, { w = 8, h = 16 })
  local patch = api.json_decode(api.scene_end(0, "image"))
  local picture
  for _, n in ipairs(patch.set) do
    if n.t == "picture" then picture = n end
  end
  eq(api.json_encode(picture and picture.ops), api.json_encode({ { "i", 0, 0, 16, 16, key, 0, 0, 1, 1 } }), "the window gets the picture by its key")
  eq(api.canvas_pixels(key).w, 2, "and asks for its pixels once")
  api.scene_forget(0)
end)
