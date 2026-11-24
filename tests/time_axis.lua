-- The time axis (paw/axis.tl): every row of the arrange view, the ruler,
-- the playhead and the cursor put a beat in the same column, the one that
-- holds it, at each zoom and scroll, with and without a time fold.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api

local W, H = 110, 24

test("the axis puts a beat in the cell that holds it, and a stretch in the cells it covers", function()
  local ax = paw.axis.new(0.3, math.sqrt(2))
  for _, beat in ipairs({ 0.3, 1, 4.375, 7.25, 12 }) do
    local exact = (beat - 0.3) * math.sqrt(2)
    local x = ax:x_of(beat)
    eq(x <= exact + 1e-9 and exact < x + 1, true, "beat " .. beat .. " at " .. exact .. " is in cell " .. x)
    local from, to = ax:cell_span(x)
    eq(from <= beat + 1e-9 and beat < to, true, "and the cell's span holds it")
  end
  -- A cell's left edge is in that cell, not the one before it.
  eq(paw.axis.new(0, 4):x_of(2.25), 9, "an edge on a cell's left side")
  eq({ paw.axis.new(0, 2):range(1, 1.1) }, { 2, 3 }, "a short stretch takes one cell")
  eq({ paw.axis.new(0, 2):range(1, 2.5) }, { 2, 5 }, "a long one each cell it covers")
end)

-- The text and the background of each cell of the screen, row by row (from 0).
local function frame()
  local f = api.ui_frame_snapshot(W, H)
  local rows = {}
  for y = 0, H - 1 do
    local text, debug_cells = f.text[y + 1], f.cells[y + 1]
    local chars = {}
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      chars[#chars + 1] = ch
    end
    local row = {}
    for ch, bg in debug_cells:gmatch("Cell { ch: '(.-)', fg: .-, bg: (.-), attrs: %d+ }") do
      if ch ~= "\\0" then
        local r, g, b = bg:match("Rgb%((%d+), (%d+), (%d+)%)")
        row[#row + 1] = { chars[#row + 1], r and string.format("#%02x%02x%02x", r, g, b) or bg }
      end
    end
    rows[y] = row
  end
  return rows
end

local function text_of(row, from)
  local out = {}
  for x = from or 1, #row do
    out[#out + 1] = row[x][1]
  end
  return table.concat(out)
end

--- The row whose text has `words`.
local function row_with(rows, words)
  for y = 0, H - 1 do
    if text_of(rows[y]):find(words, 1, true) then return y end
  end
  error("no row has " .. words)
end

--- The column of the rule before the timeline, from 1: the timeline's
--- column x is the screen's `at + x`, from 0.
local function rule_of(rows)
  for x, cell in ipairs(rows[0]) do
    if cell[1] == "│" then return x end
  end
  error("no rule on the ruler")
end

local NOTE = { ["▄"] = true, ["▀"] = true, ["█"] = true }

--- The first column of the timeline (`at`, from 0) with a note's glyph,
--- in `count` rows from `y`.
local function first_note(rows, at, y, count)
  local best
  for r = y, y + count - 1 do
    for x = at + 1, #rows[r] do
      if NOTE[rows[r][x][1]] then
        best = math.min(best or x, x)
        break
      end
    end
  end
  return best and best - at - 1
end

local function scenario()
  T.start()
  paw.ui.focus("arrange")
  paw.project.tempo = 120
  paw.opt.grid = 0.25
  local vox = paw.add_part({ name = "Vox" })
  local notes = {}
  for i, at in ipairs({ 1.5, 3.125, 5 }) do
    notes[i] = { pitch = 60 + i * 3, start = at, length = 0.75 }
  end
  local take = vox:add_clip({ name = "vox", start = 4.375, length = 7.25, notes = notes })
  paw.takes.new(take.id, "b")
  paw.takes.show_lanes(vox.id, true)
  local keys = paw.add_part({ name = "Keys" })
  keys:add_clip({ name = "k2", start = 9.5, length = 4, notes = { { pitch = 64, start = 0, length = 1 } } })
  api.lane_add(keys.id, { target = "volume", points = { { 2, -6 }, { 7.375, 0 }, { 13, -12 } } })
  paw.lanes.open(keys.id, true)
  paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 8, 16, true
  paw.transport.punch_start, paw.transport.punch_end, paw.transport.punch_enabled = 5.5, 10.25, true
  paw.markers.add(4.375, "verse")
  paw.transport.seek(11.125)
  paw.cursor.set_part(vox.id)
  paw.cursor.set_beat(0)
  paw.opt.zoom = 1
  T.after(function()
    paw.transport.loop_enabled, paw.transport.punch_enabled = false, false
  end)
end

--- Each thing drawn at a beat is in the column that the axis gives that
--- beat: the bar numbers and the playhead's cap on the ruler, the loop's
--- and the punch's edges, the marker, the notes of the clip and of its
--- takes, a point of automation, the cursor and a selection.
local function check_aligned(what)
  T.settle()
  local view = paw.ui.views:get("arrange")
  local rows = frame()
  local ax = view.axis
  local ruler = rows[0]
  local at = rule_of(rows)
  local tw = #ruler - at
  local function shown(beat)
    local x = ax:x_of(beat)
    return x >= 0 and x < tw and not ax:fold_at(x) and x
  end
  local function col_of(row, ch)
    local out = {}
    for x = at + 1, #row do
      if row[x][1] == ch then out[#out + 1] = x - at - 1 end
    end
    return out
  end
  local where = what .. " (zoom " .. paw.opt.zoom .. ", scroll " .. view.scroll .. ")"

  -- The bar numbers: each one shown is where its bar starts.
  local labels = 0
  for x = at + 1, #ruler do
    local before = ruler[x - 1][1]
    if ruler[x][1]:match("^%d$") and not before:match("^[%d▾]$") then
      local digits = {}
      for k = x, #ruler do
        if not ruler[k][1]:match("^%d$") then break end
        digits[#digits + 1] = ruler[k][1]
      end
      local number = tonumber(table.concat(digits))
      -- Not a number cut at the right edge, nor one in a fold's name.
      if x + #digits <= #ruler and not ax:fold_at(x - at - 1) then
        labels = labels + 1
        eq(x - at - 1, ax:x_of(paw.time.bar_start(number)), "bar " .. number .. " on the ruler, " .. where)
      end
    end
  end
  eq(labels > 0, true, "the ruler shows bars, " .. where)

  -- The playhead's cap.
  if shown(11.125) then eq(col_of(ruler, "▼")[1], ax:x_of(11.125), "the playhead's cap, " .. where) end

  -- The loop's and the punch's edges sit in the cell before their beat
  -- (before its fold, when a fold holds the beat).
  local edges = {}
  for _, beat in ipairs({ 5.5, 8, 10.25, 16 }) do
    edges[ax:x_of(beat) - 1] = true
  end
  for _, e in ipairs(col_of(ruler, paw.draw.g.loop_in)) do
    eq(edges[e] or false, true, "an edge of the loop or the punch at column " .. e .. ", " .. where)
  end

  -- The marker.
  local markers = row_with(rows, "verse")
  if shown(4.375) then eq(col_of(rows[markers], "▼")[1], ax:x_of(4.375), "the marker, " .. where) end

  -- The first note of the clip, and of each of its takes, 1.5 beats in:
  -- the box starts a part of a cell in, and the note is where the ruler
  -- puts its beat, not that part of a cell later.
  if shown(5.875) and shown(4.375) then
    local vox = row_with(rows, "Vox")
    eq(first_note(rows, at, vox, 3), ax:x_of(5.875), "the clip's first note, " .. where)
    for _, name in ipairs({ "take 1", "take 2" }) do
      local take = row_with(rows, name)
      eq(first_note(rows, at, take, 2), ax:x_of(5.875), "the first note of " .. name .. ", " .. where)
    end
  end

  -- A point of automation on its lane row.
  local lane = rows[row_with(rows, "Volume")]
  local points = col_of(lane, paw.draw.g.point)
  local want = {}
  for _, beat in ipairs({ 2, 7.375, 13 }) do
    want[#want + 1] = shown(beat) or nil
  end
  eq(points, want, "the points of the lane, " .. where)

  -- The cursor.
  eq(view.caret.x - at, ax:x_of(paw.cursor.beat), "the cursor, " .. where)
end

test("each row, the ruler, the playhead and the cursor put a beat in one column at each zoom and scroll", function()
  scenario()
  -- The cursor to the clip's start, off the grid, then along it.
  T.keys("w")
  eq(paw.cursor.beat, 4.375, "the cursor at the clip's start")
  check_aligned("zoom 1")
  T.keys("zi")
  check_aligned("zoomed in once")
  T.keys("zi3l")
  check_aligned("zoomed in twice, the cursor moved")
  T.keys("zozozo")
  check_aligned("zoomed out")
  T.keys("zizi")
  T.keys(":zoom 1.4142<CR>")
  check_aligned("a zoom with a fraction")
  T.keys("zl")
  check_aligned("scrolled a bar")
  T.keys("zh")
  -- A wheel's zoom leaves a scroll with a fraction.
  paw.ui.views:get("arrange").scroll = 0.3
  check_aligned("a scroll with a fraction")
end)

test("the columns stay one after a time fold, at each zoom", function()
  scenario()
  paw.folds.make({ kind = "range", from = 6.5, to = 9 })
  T.keys("w")
  check_aligned("a fold")
  T.keys("zi")
  check_aligned("a fold, zoomed in")
  T.keys(":zoom 1.4142<CR>")
  check_aligned("a fold, a zoom with a fraction")
end)

-- The take lanes against the ruler, as the owner sees them while recording:
-- the clip starts between two cells (beat 4.375), at zoom 2, then with a
-- time fold at a zoom with a fraction.
test("the takes, the clips, the lanes and the ruler line up on the screen", function()
  scenario()
  T.keys("wzi")
  T.settle()
  T.expect_screen("takes_zoom_2", 100, 16, { rows = { 1, 12 } })
  paw.folds.make({ kind = "range", from = 6.5, to = 9 })
  T.keys(":zoom 1.4142<CR>")
  T.settle()
  T.expect_screen("takes_fold", 100, 16, { rows = { 1, 12 } })
end)

test("a selection made with the keys covers the cells of its beats", function()
  scenario()
  T.keys("zizi")
  T.keys("wv3l")
  T.settle()
  local view = paw.ui.views:get("arrange")
  local rows = frame()
  local vox = rows[row_with(rows, "Vox")]
  local at = rule_of(rows)
  local visual = require("paw.theme").groups.Visual.bg
  local first, last
  for x = at + 1, #vox do
    if vox[x][2] == visual then
      first, last = first or x - at - 1, x - at - 1
    end
  end
  local region = paw.keymap.selection()
  eq({ first, last + 1 }, { view.axis:range(region.c0, region.c1) }, "the selection's cells")
  T.keys("<Esc>")
end)

test("the cursor keeps its exact beat and the ruler's column over a long run of keys", function()
  api.engine_restart({ test_input = { frequency = 440, level = -12, channels = 2 } })
  T.after(function() api.engine_restart({}) end)
  T.start()
  paw.ui.focus("arrange")
  paw.project.tempo = 120
  paw.opt.grid = 0.25
  -- A take punched in and out between two grid lines, as a recording leaves it.
  local mic = paw.add_part({ name = "mic" })
  mic.input, mic.armed = "1", true
  paw.transport.punch_start, paw.transport.punch_end, paw.transport.punch_enabled = 4.375, 6.625, true
  T.after(function() paw.transport.punch_enabled = false end)
  paw.transport.seek(3)
  paw.transport.record()
  T.until_beat(7)
  T.stop()
  paw.flush()
  local take = mic:clips()[1]:get()
  eq(take.start .. "+" .. take.length, "4.375+2.25", "the take, off the grid at both ends")
  paw.cursor.set_part(mic.id)
  paw.cursor.set_beat(0)
  local view = paw.ui.views:get("arrange")
  local function at(keys, beat)
    T.keys(keys)
    T.settle()
    eq(paw.cursor.beat, beat, "the cursor's beat after " .. keys)
    -- The frame first: the caret and the axis are those of the frame drawn last.
    local rule = rule_of(frame())
    eq(view.caret.x - rule, view.axis:x_of(beat), "its column after " .. keys .. " at zoom " .. paw.opt.zoom)
  end
  -- The clip's edges are exact, and a grid key goes to a grid line.
  at("w", 4.375)
  at("l", 4.5)
  at("3l", 5.25)
  at("e", 6.625)
  at("h", 6.5)
  at("b", 4.375)
  at("zi", 4.375)
  at("2h", 4)
  at(":zoom 1.4142<CR>", 4)
  at("8l", 6)
  at("zl", 6)
  at("0", 0)
  -- A tenth of a beat: thirty steps there and back are exact.
  paw.opt.grid = 0.1
  for _ = 1, 30 do
    T.keys("l")
  end
  at("", 3)
  at("30h", 0)
  -- A tempo change moves no beat.
  api.tempo_set(2, 90)
  at("7l", 0.7)
end)

-- Every mark that names a time is in the column that the axis gives that
-- time, whatever the ruler does with its label. The test reads the frame
-- only: the glyph of a mark on its row against `axis:x_of(beat)`.
local function marks_scenario()
  T.start()
  paw.ui.focus("arrange")
  paw.project.tempo = 120
  paw.opt.grid = 0.25
  -- 4/4 up to bar 5, then 6/8 (3 beats a bar) from beat 16, 4/4 again from beat 25.
  api.signature_set(16, 6, 8)
  api.signature_set(25, 4, 4)
  api.tempo_set(12, 90)
  api.tempo_set(20, 100)
  api.tempo_set(30.5, 110)
  local piano = paw.add_part({ name = "Piano" })
  piano:add_clip({ name = "clipA", start = 16, length = 8, notes = { { pitch = 60, start = 0, length = 1 } } })
  paw.markers.add(16, "Verse", { length = 9 })
  paw.markers.add(12, "mk")
  paw.transport.seek(21.25)
  paw.cursor.set_part(piano.id)
  paw.cursor.set_beat(16)
  paw.opt.zoom = 1
end

--- The columns of a glyph on a row of the timeline, from 0.
local function glyph_columns(row, at, glyph)
  local out = {}
  for x = at + 1, #row do
    if row[x][1] == glyph then out[#out + 1] = x - at - 1 end
  end
  return out
end

local function check_marks(what)
  T.settle()
  local view = paw.ui.views:get("arrange")
  local rows = frame()
  local ax = view.axis
  local at = rule_of(rows)
  local tw = #rows[0] - at
  local where = what .. " (zoom " .. paw.opt.zoom .. ", scroll " .. view.scroll .. ")"
  local function shown(list)
    local out = {}
    for _, beat in ipairs(list) do
      local x = ax:x_of(beat)
      if x >= 0 and x < tw and not ax:fold_at(x) then out[#out + 1] = x end
    end
    return out
  end
  local ruler = rows[0]
  -- A column with the marks of two kinds (zoomed far out, a cell holds many
  -- beats) shows the glyph of one: each glyph is in a column of its kind, and each
  -- column of a mark has a glyph.
  local meter, tempo = shown({ 16, 25 }), shown({ 12, 20, 30.5 })
  local function kinds(columns)
    local set = {}
    for _, x in ipairs(columns) do
      set[x] = true
    end
    return set
  end
  local wanted = { ["‖"] = kinds(meter), ["▾"] = kinds(tempo) }
  local drawn = {}
  for glyph, columns in pairs(wanted) do
    for _, x in ipairs(glyph_columns(ruler, at, glyph)) do
      eq(columns[x] or false, true, "the " .. glyph .. " at column " .. x .. " is a mark's column, " .. where)
      drawn[x] = true
    end
  end
  -- The playhead's cap goes over a mark that shares its cell.
  for _, x in ipairs(glyph_columns(ruler, at, "▼")) do
    drawn[x] = true
  end
  for _, x in ipairs(meter) do
    eq(drawn[x] or false, true, "a meter mark has its glyph at " .. x .. ", " .. where)
  end
  for _, x in ipairs(tempo) do
    eq(drawn[x] or false, true, "a tempo mark has its glyph at " .. x .. ", " .. where)
  end
  eq(glyph_columns(ruler, at, "▼"), shown({ 21.25 }), "the playhead's cap, " .. where)
  -- A bar's number starts at its column. Next to a mark on a bar line the
  -- number comes after the mark's value, so digits within 8 cells of a mark
  -- glyph are not read.
  local function near_mark(x)
    for k = math.max(at + 1, x - 8), x - 1 do
      if ruler[k][1] == "▾" or ruler[k][1] == "‖" then return true end
    end
    return false
  end
  for x = at + 1, #ruler do
    local before = ruler[x - 1][1]
    local value = near_mark(x)
    if
      ruler[x][1]:match("^%d$")
      and not value
      and not before:match("^%d$")
      and before ~= "▾"
      and before ~= "‖"
      and before ~= "/"
    then
      local digits = {}
      for k = x, #ruler do
        if not ruler[k][1]:match("^%d$") then break end
        digits[#digits + 1] = ruler[k][1]
      end
      local number = tonumber(table.concat(digits))
      if x + #digits <= #ruler then
        eq(x - at - 1, ax:x_of(paw.time.bar_start(number)), "bar " .. number .. " on the ruler, " .. where)
      end
    end
  end
  -- The section's first cell and its name, the marker, and the clip's first cell.
  local function first_cell(name, glyph, beat)
    -- A name too long for its box is not drawn: nothing to check then.
    local found = pcall(row_with, rows, name)
    if not found then return end
    local row = rows[row_with(rows, name)]
    -- The cell where the name starts (a byte index would miscount the glyphs).
    local from
    for x = 1, #row - #name + 1 do
      if text_of(row, x):sub(1, #name) == name then
        from = x
        break
      end
    end
    if from and beat and shown({ beat })[1] then
      eq(row[from - 1][1], glyph, "the cell before " .. name .. ", " .. where)
      eq(from - 2 - at, ax:x_of(beat), name .. " starts at its column, " .. where)
    end
  end
  first_cell("Verse", "▏", 16)
  first_cell("clipA", "▏", 16)
  if shown({ 12 })[1] and pcall(row_with, rows, "mk") then
    eq(glyph_columns(rows[row_with(rows, "mk")], at, "▼")[1], shown({ 12 })[1], "the marker, " .. where)
  end
  eq(view.caret.x - at, ax:x_of(paw.cursor.beat), "the cursor, " .. where)
end

-- A 6/8 section at bar 47, whose number the ruler draws: the meter mark, the
-- section, the clip and the cursor all start in one column, and the bar
-- number gives way to the value.
test("a meter change at a bar with a number keeps the column of its bar", function()
  T.start()
  paw.ui.focus("arrange")
  paw.project.tempo = 120
  api.signature_set(184, 6, 8)
  paw.markers.add(184, "Part A", { length = 24 })
  local piano = paw.add_part({ name = "Piano" })
  piano:add_clip({ name = "take", start = 184, length = 8, notes = { { pitch = 60, start = 0, length = 1 } } })
  paw.cursor.set_part(piano.id)
  paw.cursor.set_beat(184)
  local view = paw.ui.views:get("arrange")
  view.scroll = 170
  T.settle()
  local rows = frame()
  local at = rule_of(rows)
  local column = view.axis:x_of(184)
  eq(glyph_columns(rows[0], at, "‖"), { column }, "the meter mark is in the column of bar 47")
  eq(view.caret.x - at, column, "the cursor is in that column")
  local bar = rows[0]
  eq(bar[at + column + 2][1] .. bar[at + column + 3][1] .. bar[at + column + 4][1], "6/8", "the value follows the mark")
  T.expect_screen("meter_at_bar_47", 100, 16, { rows = { 1, 3 } })
end)

test(
  "every mark of time on the ruler and the rows is in the column of the axis, with meter and tempo changes",
  function()
    marks_scenario()
    local view = paw.ui.views:get("arrange")
    check_marks("zoom 1")
    T.keys("zi")
    check_marks("zoomed in")
    T.keys("zi")
    check_marks("zoomed in twice")
    T.keys(":zoom 1.4142<CR>")
    check_marks("a zoom with a fraction")
    T.keys("zozozozo")
    check_marks("zoomed out")
    paw.opt.zoom = 1
    view.scroll = 10.3
    check_marks("scrolled")
    paw.cursor.set_beat(20)
    check_marks("the cursor on a beat inside a 6/8 bar")
  end
)
