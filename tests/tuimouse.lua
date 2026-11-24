-- Tests of the pointer in the terminal: presses, drags, releases, the wheel
-- and modifiers fed to `paw.ui.mouse` in screen cells, as the terminal
-- sends them, and what they did read back through the API and the screen.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api

local W, H = 140, 44
local arrange = paw.ui.views:get("arrange")
local roll = paw.ui.views:get("pianoroll")

local function shot(height) return api.ui_snapshot(W, height or H) end
local function screen() return table.concat(shot(), "\n") end

local function m(kind, x, y, button, mods)
  paw.ui.mouse({ kind = kind, x = x, y = y, button = button or "left", mods = mods or "" })
end
local function click(x, y, button, mods)
  m("down", x, y, button, mods)
  m("up", x, y, button, mods)
end
local function drag(x0, y0, x1, y1, button, mods)
  m("down", x0, y0, button, mods)
  m("drag", x0 + (x1 > x0 and 1 or x1 < x0 and -1 or 0), y0 + (y1 > y0 and 1 or y1 < y0 and -1 or 0), button, mods)
  m("drag", x1, y1, button, mods)
  m("up", x1, y1, button, mods)
end
--- Let time pass since the last press, so that the next is not a double click.
local function apart() paw.mouse.forget() end

local function start()
  fresh()
  api.engine_restart({})
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  require("paw.menu").close(0)
  for _, name in ipairs({ "pianoroll", "mixer", "devices" }) do
    paw.ui.hide(name)
  end
  paw.ui.focus("arrange")
  arrange.scroll, arrange.top = 0, 1
  paw.opt.mouse, paw.opt.zoom, paw.opt.grid, paw.opt.part_height = true, 4, 1, 3
  paw.opt.note_zoom, paw.opt.note_grid, paw.opt.note_snap = 8, 0.25, true
  paw.tempolane.show(false)
  apart()
end

--- The arrange view's column of a beat, and the line a part's row starts on.
local function x_of(beat)
  local g = arrange.geometry
  return g.hw + math.floor((beat - arrange.scroll) * g.zoom + 0.5)
end
local function row_y(id, kind)
  for _, row in ipairs(arrange.geometry.layout.rows) do
    if row.id == id and row.kind == (kind or "part") then return row.y end
  end
end

--- Where text is on the screen: its column and line.
--- The column of the hit `name` that the head of part `id` asked for
--- (paw/heads.tl): a chip (`mute`, `solo`, `monitor`), `volume` or `pan`.
local function hit_x(id, name)
  for _, hit in ipairs(arrange.head_hits) do
    if hit.subject.part == id and hit.name == name then return hit.x end
  end
  error("no hit " .. name .. " on the head of part " .. id)
end

local function find(text)
  for y, line in ipairs(shot()) do
    local i = line:find(text, 1, true)
    if i then return api.str_width(line:sub(1, i - 1)), y - 1 end
  end
end

--- The character in a cell of the screen.
local function cell(x, y)
  local col = 0
  for ch in (shot()[y + 1] or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if col == x then return ch end
    col = col + api.str_width(ch)
  end
end

local function clips(t)
  local out = {}
  for _, c in ipairs(api.clip_list(t.id)) do
    out[#out + 1] = string.format("%s@%g+%g", c.name, c.start, c.length)
  end
  return table.concat(out, " ")
end

--- Two parts with two clips of four beats on the first, at 0 and 8.
local function two_parts()
  start()
  local a = paw.add_part({ name = "A" })
  local b = paw.add_part({ name = "B" })
  a:add_clip({ name = "x", start = 0, length = 4 })
  a:add_clip({ name = "y", start = 8, length = 4 })
  paw.cursor.set_part(a)
  paw.cursor.set_beat(0)
  api.undo_checkpoint()
  shot()
  return a, b
end

-- The arrange view -------------------------------------------------------------------------

test("a click on an empty lane puts the cursor on that part at that beat and lets go of the chosen clips", function()
  local a, b = two_parts()
  click(x_of(1), row_y(a.id))
  eq(#paw.frontend.chosen_clips(), 1, "a click on a clip chooses it")
  click(x_of(5) + 1, row_y(b.id) + 1)
  eq(paw.cursor.part_id(), b.id, "the cursor is on the part clicked")
  eq(paw.cursor.beat, 5, "at the grid step the cell is in")
  eq(#paw.frontend.chosen_clips(), 0, "and the chosen clip is let go")
  eq(paw.ui.focused, "arrange", "the arrange view has the keyboard")
end)

test("a click two bars after a time fold puts the cursor on the beat drawn there", function()
  local _, b = two_parts()
  T.after(function() paw.folds.clear() end)
  paw.folds.make({ kind = "range", from = 4, to = 20 })
  shot()
  -- The fold's column, then bars 6 and 7 of the song (beats 20 to 28).
  local after = arrange.geometry.hw + arrange.axis:x_of(20)
  eq(after < x_of(20), true, "the bars after the fold are drawn further left")
  click(after + 8 * arrange.geometry.zoom, row_y(b.id) + 1)
  eq(paw.cursor.beat, 28, "two bars after the fold: beat 28")
  apart()
  click(arrange.geometry.hw + arrange.axis:x_of(4) + 1, row_y(b.id) + 1)
  eq(paw.cursor.beat, 4, "a click on the fold's column: its start")
end)

test("a click on a clip chooses it, Ctrl and a click adds another, Shift takes in those between", function()
  local a = two_parts()
  a:add_clip({ name = "z", start = 16, length = 4 })
  shot()
  click(x_of(1), row_y(a.id))
  eq(paw.frontend.chosen_clips()[1], a:clips()[1].id, "the clip clicked is chosen")
  click(x_of(9), row_y(a.id), "left", "C")
  eq(#paw.frontend.chosen_clips(), 2, "Ctrl adds the second")
  eq(paw.keymap.mode, "x", "two chosen clips are visual mode's selection")
  paw.keymap.feed("<Esc>")
  apart()
  click(x_of(1), row_y(a.id))
  click(x_of(17), row_y(a.id), "left", "S")
  eq(#paw.frontend.chosen_clips(), 3, "Shift takes in the clips from the first to the third")
end)

test("dragging a clip moves it by whole grid steps, onto another part, as one undo step", function()
  local a, b = two_parts()
  m("down", x_of(1), row_y(a.id))
  m("drag", x_of(2), row_y(a.id))
  m("drag", x_of(3), row_y(b.id))
  eq(cell(x_of(2) + 1, row_y(b.id)), "x", "the clip is drawn where it would land while the button is down")
  eq(clips(a), "x@0+4 y@8+4", "nothing moves until the button is let go")
  m("up", x_of(3), row_y(b.id))
  api.undo_checkpoint()
  eq(clips(b), "x@2+4", "the clip lands two beats on, on the part below")
  eq(clips(a), "y@8+4", "and leaves its own part")
  paw.undo()
  eq(clips(a), "x@0+4 y@8+4", "one undo takes the whole drag back")
end)

test("Ctrl and a drag drops a copy of the clip and leaves it where it was", function()
  local a = two_parts()
  drag(x_of(1), row_y(a.id), x_of(13), row_y(a.id), "left", "C")
  eq(clips(a), "x@0+4 y@8+4 x@12+4", "a copy at beat 12, the clip where it was")
end)

test("dragging the last cell of a clip trims its end, and its first cell its start", function()
  local a = two_parts()
  local last = x_of(4) - 1
  drag(last, row_y(a.id), last + 8, row_y(a.id))
  eq(clips(a), "x@0+6 y@8+4", "the end follows the pointer, onto the grid")
  shot()
  drag(x_of(0), row_y(a.id), x_of(1), row_y(a.id))
  eq(clips(a), "x@1+5 y@8+4", "the start moves in, the end stays")
end)

test("a drag across empty lanes selects that stretch of time on the parts it crosses", function()
  local a, b = two_parts()
  drag(x_of(4), row_y(a.id) + 1, x_of(8) - 1, row_y(b.id) + 1)
  local sel = paw.keymap.selection()
  eq(paw.keymap.mode, "x", "visual mode")
  eq(sel and (sel.r0 .. "-" .. sel.r1 .. " " .. sel.c0 .. "-" .. sel.c1), "1-2 4-8", "two parts, beats 4 to 8")
end)

test("a drag with the right button draws a box that chooses the clips it touches", function()
  local a, b = two_parts()
  b:add_clip({ name = "w", start = 4, length = 4 })
  shot()
  m("down", x_of(2), row_y(a.id) + 1, "right")
  m("drag", x_of(5), row_y(b.id) + 1, "right")
  eq(cell(x_of(3), row_y(a.id) + 1), paw.draw.g.h, "the box is drawn")
  m("up", x_of(5), row_y(b.id) + 1, "right")
  eq(#paw.frontend.chosen_clips(), 2, "x and w are chosen, y is not")
end)

test("a double click on a clip opens it in the piano roll, and on an empty lane makes a clip of a bar", function()
  local a, b = two_parts()
  click(x_of(1), row_y(a.id))
  click(x_of(1), row_y(a.id))
  eq(paw.ui.focused, "pianoroll", "the piano roll has the clip")
  eq(roll.clip_id, a:clips()[1].id, "the clip clicked")
  paw.ui.hide("pianoroll")
  paw.ui.focus("arrange")
  shot()
  apart()
  click(x_of(5), row_y(b.id) + 1)
  click(x_of(5), row_y(b.id) + 1)
  eq(clips(b), "midi@4+4", "a clip of one bar in the bar clicked")
end)

test("a right click on a clip opens its menu at the pointer, and its entries do what the window's do", function()
  local a = two_parts()
  click(x_of(9), row_y(a.id), "right")
  local text = screen()
  eq(text:find("Split at the pointer", 1, true) ~= nil, true, "the clip's menu is open")
  local x, y = find("Mute")
  eq(x ~= nil and x >= x_of(9) - 30, true, "near the pointer")
  click(x, y)
  eq(a:clips()[2].muted, true, "Mute mutes the clip clicked")
  eq(screen():find("Split at the pointer", 1, true), nil, "and the menu is gone")
end)

test("a menu answers the keys: j and k move, l opens a submenu, Enter chooses, Esc lets go", function()
  local a, b = two_parts()
  click(3, row_y(a.id) + 1, "right")
  eq(screen():find("Bounce to audio", 1, true) ~= nil, true, "the part's menu")
  paw.keymap.feed("jl")
  eq(screen():find("Coral", 1, true) ~= nil, true, "the colours open beside it")
  paw.keymap.feed("<CR>")
  eq(a:get().color ~= nil, true, "Enter chooses the first, coral")
  click(3, row_y(a.id) + 1, "right")
  paw.keymap.feed("<Esc>")
  eq(screen():find("Bounce to audio", 1, true), nil, "Esc lets the menu go")
  paw.keymap.feed("j")
  eq(paw.cursor.part_id(), b.id, "and the keys are the view's again")
end)

test("a click outside a menu lets it go without doing anything else", function()
  local a, b = two_parts()
  click(x_of(1), row_y(a.id), "right")
  click(x_of(20), row_y(b.id) + 1)
  eq(screen():find("Split at the pointer", 1, true), nil, "the menu is gone")
  eq(paw.cursor.part_id(), a.id, "the click did not reach the lane")
end)

test("a header's M, S, R and I switch, and a press on M swept down mutes the parts it crosses", function()
  local a, b = two_parts()
  local c = paw.add_part({ name = "C" })
  shot()
  click(hit_x(a.id, "solo"), row_y(a.id))
  eq(a:get().solo, true, "S solos")
  click(hit_x(a.id, "monitor"), row_y(a.id))
  eq(a:get().monitor, true, "I monitors")
  drag(hit_x(a.id, "mute"), row_y(a.id), hit_x(a.id, "mute"), row_y(c.id))
  eq(tostring(a:get().mute) .. tostring(b:get().mute) .. tostring(c:get().mute), "truetruetrue", "all three muted")
end)

test("a click on a header's in button opens the menu of the part's input", function()
  local a = two_parts()
  shot()
  click(hit_x(a.id, "input"), row_y(a.id) + 1)
  eq(screen():find("Monitor: hear the input without arming", 1, true) ~= nil, true, "the input menu")
  paw.keymap.feed("<Esc>")
end)

test("the volume on a header drags sideways a decibel a cell, and a double click puts it at 0 dB", function()
  local a = two_parts()
  local y = row_y(a.id) + 1
  drag(10, y, 16, y)
  near(a:get().volume, 6, 1e-6, "six cells right is +6 dB")
  drag(16, y, 4, y)
  near(a:get().volume, -6, 1e-6, "and back twelve")
  apart()
  click(10, y)
  click(10, y)
  near(a:get().volume, 0, 1e-6, "a double click: 0 dB")
end)

test("two clicks are a double click only when the second comes within the double click time", function()
  local a = two_parts()
  local y = row_y(a.id) + 1
  drag(10, y, 16, y)
  apart()
  click(10, y)
  T.advance(paw.mouse.double_ms + 1)
  click(10, y)
  near(a:get().volume, 6, 1e-6, "a second click after the double click time: two clicks")
  apart()
  click(10, y)
  T.advance(paw.mouse.double_ms)
  click(10, y)
  near(a:get().volume, 0, 1e-6, "a second click at the end of the double click time: 0 dB")
end)

test("dragging a part's header down puts the part in another place", function()
  local a, b = two_parts()
  drag(6, row_y(a.id), 6, row_y(b.id) + 1)
  eq(api.part_list()[1], b.id, "B is first")
  eq(api.part_list()[2], a.id, "A after it")
end)

test(
  "the ruler: a click moves the playhead, a drag loops what it crosses, a double click turns the loop off",
  function()
    two_parts()
    click(x_of(6), 0)
    eq(api.transport_get().position, 6, "the playhead at beat 6")
    apart()
    drag(x_of(4), 0, x_of(8) - 1, 0)
    local t = api.transport_get()
    eq(t.loop_enabled and t.loop_start .. "-" .. t.loop_end, "4-8", "a loop over the cells dragged across")
    shot()
    apart()
    click(x_of(2), 0)
    click(x_of(2), 0)
    eq(api.transport_get().loop_enabled, false, "a double click turns it off")
  end
)

test("the loop's edges drag on the ruler", function()
  two_parts()
  paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 4, 8, true
  shot()
  drag(x_of(8) - 1, 0, x_of(12) - 1, 0)
  eq(api.transport_get().loop_end, 12, "the end follows")
  shot()
  drag(x_of(4) - 1, 0, x_of(2) - 1, 0)
  eq(api.transport_get().loop_start, 2, "and the start")
end)

test("a tempo flag on the ruler drags to another beat, a right click on it offers to remove it", function()
  two_parts()
  api.tempo_set(8, 90)
  shot()
  local x = find("▾90")
  drag(x, 0, x + 8, 0)
  local tempos = api.tempo_points().tempos
  eq(tempos[2] and tempos[2].beat, 10, "the change moves two beats on, onto the grid")
  shot()
  x = find("▾90")
  click(x, 0, "right")
  local rx, ry = find("Remove tempo change")
  click(rx, ry)
  eq(#api.tempo_points().tempos, 1, "and is removed")
end)

test("the tempo lane: a click adds a change, a drag on one moves it, a right click on one removes it", function()
  two_parts()
  paw.tempolane.show(true)
  shot()
  local y0 = arrange.geometry.layout.ruler_rows - 2
  click(x_of(8), y0 + 1)
  local tempos = api.tempo_points().tempos
  eq(#tempos, 2, "a change at the beat clicked")
  eq(tempos[2].beat, 8, "at beat 8")
  shot()
  local x = x_of(8)
  local line = paw.tempolane.fraction(tempos[2].bpm) >= 0.5 and y0 or y0 + 1
  apart()
  drag(x, line, x + 8, line - 2)
  tempos = api.tempo_points().tempos
  eq(tempos[2].beat, 10, "dragged two beats on")
  shot()
  line = paw.tempolane.fraction(tempos[2].bpm) >= 0.5 and y0 or y0 + 1
  apart()
  click(x_of(10), line, "right")
  eq(#api.tempo_points().tempos, 1, "and removed with the right button")
  paw.tempolane.show(false)
end)

--- Tempo points as text: "120@0 90@8".
local function tempo_text(points)
  local out = {}
  for i, p in ipairs(points) do
    out[i] = string.format("%g@%g", p.bpm, p.beat)
  end
  return table.concat(out, " ")
end

--- A row Cue with a block at bar 5 (beat 16) of a subproject Cue of 16
--- beats, entered with znn, its tempo `time` ("own" or "follow"), the
--- tempo lane shown and painted from the subproject's start.
local function in_cue(time)
  start()
  local row = paw.add_part({ name = "Cue" })
  local nest = api.nest_add({ name = "Cue", length = 16 })
  api.part_add({ name = "Synth", nest = nest })
  api.clip_add(row.id, { nest = nest, start = 16 })
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_part(row.id)
  paw.cursor.set_beat(17)
  -- A new subproject follows the song's time already.
  if time ~= "follow" then paw.keymap.feed(":nest.time " .. time .. "<CR>") end
  paw.keymap.feed("znn")
  paw.tempolane.show(true)
  T.after(function() paw.tempolane.show(false) end)
  arrange.scroll = 0
  shot()
  api.undo_checkpoint()
  return nest
end

test(
  "the tempo lane inside a subproject with its own tempo: a click makes a change in its map, not the song's",
  function()
    local nest = in_cue("own")
    -- The lower row of the lane is the slower half: below 120.
    click(x_of(8), arrange.geometry.layout.ruler_rows - 1)
    local own = api.nest_get(nest).tempo.points
    eq(#own .. " " .. own[2].beat, "2 8", "a change at its beat 8")
    eq(own[2].bpm < 120, true, "slower, as the row clicked")
    eq(tempo_text(api.tempo_points().tempos), "120@0", "the song's map as it was")
    api.undo_checkpoint()
    paw.keymap.feed("u")
    eq(tempo_text(api.nest_get(nest).tempo.points), "120@0", "u takes it back in one step")
  end
)

test("the tempo lane inside a subproject that follows the song: a click makes a change at the song's beat", function()
  in_cue("follow")
  click(x_of(8), arrange.geometry.layout.ruler_rows - 1)
  local song = api.tempo_points().tempos
  eq(#song .. " " .. song[2].beat, "2 24", "its beat 8 is the song's beat 24")
  api.undo_checkpoint()
  apart()
  shot()
  -- The change shows at its beat 8 in the window: a drag moves it from there.
  local line = paw.tempolane.fraction(song[2].bpm) >= 0.5 and arrange.geometry.layout.ruler_rows - 2
    or arrange.geometry.layout.ruler_rows - 1
  drag(x_of(8), line, x_of(10), line)
  eq(api.tempo_points().tempos[2].beat, 26, "dragged two beats on, in the song's beats")
  api.undo_checkpoint()
  paw.keymap.feed("u")
  eq(api.tempo_points().tempos[2].beat, 24, "u takes the drag back in one step")
  paw.keymap.feed("u")
  eq(tempo_text(api.tempo_points().tempos), "120@0", "and the click in another")
end)

--- Signature changes as text: "0:4/4 8:2/4".
local function meter_text(changes)
  local out = {}
  for i, s in ipairs(changes or {}) do
    out[i] = string.format("%g:%d/%d", s.beat, s.num, s.den)
  end
  return table.concat(out, " ")
end

test("inside a subproject, the flags on the ruler move and remove the changes of the window's map", function()
  -- Each row: how the subproject keeps time, and the map that its flags
  -- stand for: its own, or the song's from its start at beat 16.
  local cases = {
    { time = "own", own = true, offset = 0 },
    { time = "follow", own = false, offset = 16 },
  }
  local tempo, signature = "120@0 90@%d", "0:4/4 %d:2/4"
  for _, case in ipairs(cases) do
    local nest = in_cue(case.time)
    local function tempos() return tempo_text(case.own and api.nest_get(nest).tempo.points or api.tempo_points().tempos) end
    local function meter()
      local n = api.nest_get(nest)
      return meter_text(case.own and n.meter.changes or api.tempo_points().signatures)
    end
    local function at(pattern, beat) return string.format(pattern, beat + case.offset) end
    paw.tempolane.add(4, 90)
    paw.tempolane.signature_set(8, 2, 4)
    api.undo_checkpoint()
    eq(tempos() .. " | " .. meter(), at(tempo, 4) .. " | " .. at(signature, 8), case.time .. ": the changes")
    -- A drag of two beats moves the tempo change, one of four the signature
    -- change, to a bar line of 2/4.
    shot()
    local x, y = find("▾90")
    drag(x, y, x + 8, y)
    eq(tempos(), at(tempo, 6), case.time .. ": the tempo change dragged to its beat 6")
    api.undo_checkpoint()
    apart()
    shot()
    x, y = find("‖2/4")
    drag(x, y, x + 16, y)
    eq(meter(), at(signature, 12), case.time .. ": the signature change dragged to its beat 12")
    api.undo_checkpoint()
    paw.keymap.feed("u")
    eq(meter(), at(signature, 8), case.time .. ": u takes the drag back in one step")
    -- A right click on each offers to remove it.
    for _, flag in ipairs({ { "▾90", "Remove tempo change" }, { "‖2/4", "Remove signature change" } }) do
      apart()
      shot()
      x, y = find(flag[1])
      click(x, y, "right")
      click(find(flag[2]))
      api.undo_checkpoint()
    end
    eq(tempos() .. " | " .. meter(), "120@0 | 0:4/4", case.time .. ": both removed")
    paw.keymap.feed("u")
    eq(meter(), at(signature, 8), case.time .. ": u brings the signature change back in one step")
  end
end)

test("a marker drags in its band under the ruler, and a click on it goes there", function()
  two_parts()
  local mk = paw.markers.add(8, "Chorus")
  shot()
  local x, y = find("Chorus")
  drag(x, y, x + 8, y)
  eq(paw.markers.find({ id = mk.id }).beat, 10, "two beats on")
  shot()
  x, y = find("Chorus")
  apart()
  paw.cursor.set_beat(0)
  click(x, y)
  eq(paw.cursor.beat, 10, "a click goes to it")
end)

test(
  "the regions' lane has a row for each level: a click on a row takes its region, a drag takes the regions inside",
  function()
    two_parts()
    paw.markers.add(16, "Chorus 2", { length = 16 })
    paw.markers.add(20, "Verse A", { length = 8 })
    paw.markers.add(20, "Riff", { length = 4 })
    shot()
    local x, y = find("▾Chorus 2")
    local x2, y2 = find("▾Verse A")
    local x3, y3 = find("▏Riff")
    eq(
      string.format("%d %d %d %d", x2 - x, y2 - y, x3 - x, y3 - y),
      "16 1 16 2",
      "a row for each level, each under its parent"
    )
    paw.opt.regionlevels = 2
    T.after(function() paw.opt.regionlevels = 3 end)
    eq(select(2, find("+▏Riff")), y2, "regionlevels=2: the third level shares the last row, marked +")
    paw.opt.regionlevels = 3
    shot()
    apart()
    paw.cursor.set_beat(0)
    click(x2 + 4, y2)
    eq(paw.cursor.beat, 20, "a click on Verse A's row goes to it")
    apart()
    drag(x, y, x + 8, y)
    eq(paw.markers.find("Riff").beat .. " " .. paw.markers.find("Chorus 2").beat, "22 18", "Chorus 2 took Riff along")
  end
)

test("automation lanes shown as rows: a click adds a point, a right click on it removes it, a drag draws", function()
  local a = two_parts()
  paw.frontend.act.lane_rows(a.id)
  shot()
  local lane = api.lane_list(a.id)[1].id
  local y = row_y(a.id, "lane")
  click(x_of(2), y)
  eq(#api.lane_points(lane), 1, "a point")
  near(api.lane_points(lane)[1][1], 2, 1e-9, "at beat 2")
  shot()
  apart()
  click(x_of(2), y, "right")
  eq(#api.lane_points(lane), 0, "removed")
  shot()
  drag(x_of(4), y, x_of(8), y + 1)
  eq(#api.lane_points(lane) >= 2, true, "a stroke draws points")
end)

test("a warp marker of an audio clip drags along it", function()
  start()
  local source = T.tone("source", 8)
  local wav = T.render({ tail = 0, bits = 32 })
  source:remove()
  local t = paw.add_part({ name = "audio" })
  local clip = t:add_clip({ file = wav.path, start = 0, length = 8 })
  paw.frontend.act.warp_add(clip.id, 4)
  shot()
  local warps = api.clip_get(clip.id).warp
  eq(#warps, 1, "a warp marker")
  drag(x_of(warps[1].beat), row_y(t.id) + 1, x_of(warps[1].beat) + 4, row_y(t.id) + 1)
  local _, off = paw.stretch.warp_near(api.clip_get(clip.id), 5)
  near(off, 0, 1e-6, "it plays a beat later")
end)

test("the wheel scrolls the parts, with Shift sideways, and with Ctrl zooms in time where the pointer is", function()
  local a = two_parts()
  m("scroll_down", x_of(2), row_y(a.id), "", "S")
  eq(arrange.scroll, paw.time.bar(), "a bar sideways")
  m("scroll_up", x_of(2), row_y(a.id), "", "S")
  eq(arrange.scroll, 0, "and back")
  local x = x_of(8)
  m("scroll_up", x, row_y(a.id), "", "C")
  eq(paw.opt.zoom > 4, true, "Ctrl and the wheel zoom in")
  shot()
  near(arrange.scroll + (x - arrange.geometry.hw) / arrange.geometry.zoom, 8, 0.01, "keeping beat 8 under the pointer")
end)

test("the pointer going over a clip says on the status line what it is and what a click does", function()
  local a = two_parts()
  m("move", x_of(9), row_y(a.id), "")
  local text = screen()
  eq(text:find("click chooses", 1, true) ~= nil, true, "the status line says what a click does")
  m("move", 2, H - 1, "")
  eq(screen():find("click chooses", 1, true), nil, "and nothing once the pointer has left")
end)

test("with paw.opt.mouse off the pointer reaches nothing, and the terminal is asked to keep it", function()
  local a = two_parts()
  paw.opt.mouse = false
  click(x_of(9), row_y(a.id))
  eq(#paw.frontend.chosen_clips(), 0, "the click was not taken")
  paw.opt.mouse = true
  click(x_of(9), row_y(a.id))
  eq(#paw.frontend.chosen_clips(), 1, "and is again with it on")
end)

-- The piano roll -------------------------------------------------------------------------------

--- A clip of two bars open in the piano roll, with notes as given, and where
--- a pitch and a beat are on the screen.
local function rolled(notes)
  start()
  local t = paw.add_part({ name = "keys" })
  local clip = t:add_clip({ name = "riff", start = 0, length = 8, notes = notes or {} })
  roll:edit(clip)
  roll.top, roll.scroll, roll.pitch, roll.beat = 72, 0, 60, 0
  api.undo_checkpoint()
  shot()
  local rect
  for _, r in ipairs(paw.ui.rects) do
    if r.name == "pianoroll" then rect = r end
  end
  local g = roll.geometry
  local function at(pitch, beat)
    return rect.x + g.keys + math.floor((beat - roll.scroll) * g.zoom + 0.5), rect.y + g.head + (roll.top - pitch)
  end
  return clip, at, rect
end

local function notes_of(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do
    out[#out + 1] = string.format("%d@%g+%g", n.pitch, n.start, n.length)
  end
  return table.concat(out, " ")
end

test("a click on empty grid draws a note of the roll's length, and a drag draws it as long as the drag", function()
  local clip, at = rolled()
  local x, y = at(64, 1)
  click(x, y)
  eq(notes_of(clip), "64@1+0.25", "a click: a note of one step where it was clicked")
  eq(paw.frontend.chosen_notes(clip.id)[1], 1, "which is chosen")
  x, y = at(67, 2)
  m("down", x, y)
  m("drag", x + 3, y)
  eq(shot()[y + 1]:find("G4", 1, true) ~= nil, true, "the note is drawn as it is dragged")
  m("drag", x + 7, y)
  m("up", x + 7, y)
  eq(notes_of(clip), "64@1+0.25 67@2+1", "dragged across eight cells, a beat long")
  paw.ui.views:get("pianoroll"):set_step(nil)
end)

test("a click on a note chooses it, a drag moves it, and Ctrl leaves a copy behind", function()
  local clip, at = rolled({ { pitch = 60, start = 0, length = 1 }, { pitch = 62, start = 2, length = 1 } })
  local x, y = at(60, 0.5)
  click(x, y)
  eq(paw.frontend.chosen_notes(clip.id)[1], 1, "chosen")
  eq(notes_of(clip), "60@0+1 62@2+1", "and left as it was")
  local x2, y2 = at(62, 2.5)
  click(x2, y2, "left", "C")
  eq(#paw.frontend.chosen_notes(clip.id), 2, "Ctrl adds the other")
  apart()
  drag(x, y, x + 8, y - 2)
  api.undo_checkpoint()
  eq(notes_of(clip), "62@1+1 64@3+1", "both move a beat on and two semitones up")
  paw.undo()
  eq(notes_of(clip), "60@0+1 62@2+1", "one undo step")
  shot()
  apart()
  drag(x, y, x + 32, y, "left", "C")
  eq(notes_of(clip), "60@0+1 62@2+1 60@4+1", "a copy four beats on")
end)

test("a clip opened by keys after one the pointer opened keeps the zoom", function()
  start()
  local t = paw.add_part({ name = "keys" })
  local short = t:add_clip({ name = "short", start = 0, length = 1, notes = {} })
  t:add_clip({ name = "long", start = 4, length = 8, notes = {} })
  paw.frontend.act.open_clip(short.id)
  paw.keymap.feed(":e roll://long<CR>")
  shot()
  eq(roll:clip().name .. " " .. paw.opt.note_zoom, "long 8", "the zoom to fit the short clip is not used")
end)

test("dragging a note's last cell resizes it, and its first cell moves its start", function()
  local clip, at = rolled({ { pitch = 60, start = 1, length = 1 } })
  local x, y = at(60, 2)
  drag(x - 1, y, x + 7, y)
  eq(notes_of(clip), "60@1+2", "a beat longer")
  shot()
  x, y = at(60, 1)
  drag(x, y, x - 4, y)
  eq(notes_of(clip), "60@0.5+2.5", "starts half a beat earlier, ends where it did")
end)

test("the right button: a box chooses notes, a click removes a note, on empty grid opens the menu", function()
  local clip, at = rolled({
    { pitch = 60, start = 0, length = 1 },
    { pitch = 62, start = 2, length = 1 },
    { pitch = 70, start = 4, length = 1 },
  })
  local x0, y0 = at(63, 0)
  local x1, y1 = at(59, 3)
  drag(x0, y0, x1, y1, "right")
  eq(table.concat(paw.frontend.chosen_notes(clip.id), ","), "1,2", "the two notes in the box")
  local x, y = at(70, 4.5)
  click(x, y, "right")
  eq(notes_of(clip), "60@0+1 62@2+1", "a right click removes the note")
  x, y = at(66, 6)
  click(x, y, "right")
  local ex, ey = find("Choose every note")
  eq(ex ~= nil, true, "the grid's menu")
  click(ex, ey)
  eq(#paw.frontend.chosen_notes(clip.id), 2, "whose first entry chooses every note")
end)

test("a double click on a note removes it, and Alt and a drag erases every note it crosses", function()
  local clip, at = rolled({
    { pitch = 60, start = 0, length = 1 },
    { pitch = 62, start = 2, length = 1 },
    { pitch = 62, start = 4, length = 1 },
  })
  local x, y = at(60, 0.5)
  click(x, y)
  click(x, y)
  eq(notes_of(clip), "62@2+1 62@4+1", "double click: gone")
  shot()
  local x0, y0 = at(62, 1)
  local x1 = at(62, 6)
  drag(x0, y0, x1, y0, "left", "A")
  eq(notes_of(clip), "", "the stroke erased both")
end)

test("the piano roll's keyboard sounds a key, and a right drag down it chooses the notes of those pitches", function()
  local clip, at, rect = rolled({
    { pitch = 60, start = 0, length = 1 },
    { pitch = 64, start = 2, length = 1 },
    { pitch = 67, start = 4, length = 1 },
  })
  local _, y60 = at(60, 0)
  local _, y64 = at(64, 0)
  click(rect.x + 1, y60)
  drag(rect.x + 1, y64, rect.x + 1, y60, "right")
  eq(table.concat(paw.frontend.chosen_notes(clip.id), ","), "1,2", "C4 to E4")
end)

test("drawing across the velocity strip sets how hard the notes under the stroke play", function()
  local clip, at, rect = rolled({ { pitch = 60, start = 0, length = 1 }, { pitch = 62, start = 1, length = 1 } })
  local g = roll.geometry
  eq(g.vel > 0, true, "the strip is shown")
  local top = rect.y + g.head + g.rows
  local x0 = at(60, 0)
  local x1 = at(62, 1)
  drag(x0, top, x1, top)
  local notes = clip:notes()
  eq(notes[1].velocity > 100 and notes[2].velocity > 100, true, "both near the top")
  shot()
  click(x1, top + g.vel - 1)
  eq(clip:notes()[2].velocity < 40 and clip:notes()[1].velocity > 100, true, "a click sets the one under it")
end)

test(
  "the strip under the piano roll shows a controller chosen by its name, drawn on and its moves chosen and moved",
  function()
    local clip, at, rect = rolled()
    local strip = require("paw.views.pianoroll_strip")
    local g = roll.geometry
    local top = rect.y + g.head + g.rows
    click(rect.x + 1, top + g.vel - 1)
    local mx, my = find("Modulation")
    eq(mx ~= nil, true, "a menu of what the strip shows")
    click(mx, my)
    eq(strip.shown().number, 1, "it shows modulation")
    eq(cell(rect.x + 1, top + g.vel - 1), "m", "and says so")
    local function moves()
      local out = {}
      for _, c in ipairs(clip:controls()) do
        out[#out + 1] = string.format("%g:%.2f", c.start, c.value)
      end
      return table.concat(out, " ")
    end
    local x0 = at(60, 0)
    local x1 = at(60, 1)
    drag(x0, top, x1, top)
    eq(#clip:controls() >= 3, true, "drawn with the button held: a move a step the pointer crossed, " .. moves())
    eq(clip:controls()[1].value > 0.8, true, "near the top")
    shot()
    apart()
    -- The head of the move at beat 0 is the top of its bar.
    local level = clip:controls()[1].value * g.vel * 8
    local head = top + g.vel - 1 - math.floor((level - 1) / 8)
    drag(x0, head, x0 + 8, head)
    eq(clip:controls()[#clip:controls()].start >= 1, true, "a move's head dragged moves it on: " .. moves())
    apart()
    shot()
    drag(at(60, 4), top + g.vel - 1, at(60, 6), top, "right")
    local last = clip:controls()[#clip:controls()]
    eq(last.start >= 5.5 and last.value > 0.6, true, "the right button draws a line up: " .. moves())
    strip.show(nil)
  end
)

test("a click on the piano roll's ruler moves the playhead into the clip", function()
  local clip, at = rolled()
  clip.start = 4
  shot()
  -- Stopped, and the engine has seen it: a block that plays after the
  -- click would move the playhead on from where the click put it.
  paw.transport.stop()
  T.next_block(2)
  local x, y = at(60, 2)
  click(x, y - (roll.top - 60) - 1)
  T.next_block(2)
  eq(api.transport_get().position, 6, "beat 2 of a clip at 4")
end)

test("the wheel in the piano roll scrolls the pitches, and Ctrl zooms in time", function()
  local _, at = rolled()
  local x, y = at(60, 1)
  m("scroll_up", x, y, "", "")
  eq(roll.top, 74, "two rows up")
  m("scroll_down", x, y, "", "C")
  eq(paw.opt.note_zoom < 8, true, "zoomed out")
end)

-- The mixer and the device panel -------------------------------------------------------------------

local function mixer_node()
  local function find(node)
    if node.view == "mixer" then return node end
    for _, child in ipairs(node) do
      local found = find(child)
      if found then return found end
    end
  end
  return find(paw.ui.layout)
end

local function mixed()
  start()
  local a = paw.add_part({ name = "A" })
  local b = paw.add_part({ name = "B" })
  a:add_device("synth")
  api.part_set(a.id, "sends", { { target = b.id, level = -6 } })
  paw.cursor.set_part(a)
  paw.ui.show("mixer")
  -- Tall enough for the strips to show their devices and sends, until
  -- the test ends.
  local node = mixer_node()
  local size = node.size
  T.after(function()
    node.size = size
    paw.ui.hide("mixer")
    paw.ui.hide("devices")
  end)
  node.size = 30
  api.undo_checkpoint()
  shot(90)
  local rect
  for _, r in ipairs(paw.ui.rects) do
    if r.name == "mixer" then rect = r end
  end
  local s = paw.ui.views:get("mixer").geometry.strips[1]
  -- From the strip's own lines (under the title bar) to the screen.
  local function at(x, y) return rect.x + x, rect.y + 1 + y end
  return a, b, s, at
end

test(
  "a mixer fader drags up and down, its pan follows the pointer, its buttons switch, double clicks put them back",
  function()
    local a, _, s, at = mixed()
    local fx = s.x + math.floor(s.w / 2) + 1
    local x, y = at(fx, s.fader + s.rows - 2)
    drag(x, y, x, y - 3)
    eq(a:get().volume > 0, true, "dragged up, louder")
    apart()
    click(x, y)
    click(x, y)
    near(a:get().volume, 0, 1e-9, "a double click: 0 dB")
    local px, py = at(s.x + 1, s.pan)
    click(px, py)
    near(a:get().pan, -1, 1e-9, "the pan's left end")
    apart()
    drag(px, py, px + s.pan_w - 1, py)
    near(a:get().pan, 1, 1e-9, "dragged to its right end")
    local mx, my = at(s.x + 1, s.chips)
    click(mx, my)
    eq(a:get().mute, true, "M mutes")
  end
)

test("a send in a mixer strip drags sideways, and a click on a device picks it in the device panel", function()
  local a, _, s, at = mixed()
  local x, y = at(s.x + 2, s.sends)
  drag(x, y, x + 3, y)
  near(a:get().sends[1].level, -3, 1e-9, "three cells, three decibels")
  x, y = at(s.x + 2, s.devices)
  click(x, y)
  eq(paw.ui.focused, "devices", "the device panel has the keyboard")
end)

test("a right click on a mixer strip opens the part's menu", function()
  local _, _, s, at = mixed()
  local x, y = at(s.x + 2, 0)
  click(x, y, "right")
  eq(screen():find("Bounce to audio", 1, true) ~= nil, true, "the part's menu")
  paw.keymap.feed("<Esc>")
end)

test(
  "a parameter's slider in the device panel follows the pointer, a double click puts it back, on and off bypass",
  function()
    start()
    local t = paw.add_part({ name = "S" })
    local d = t:add_device("synth")
    paw.cursor.set_part(t)
    paw.ui.show("devices")
    shot()
    local rect
    for _, r in ipairs(paw.ui.rects) do
      if r.name == "devices" then rect = r end
    end
    local panel = paw.ui.views:get("devices")
    -- The " on " chip at the right of the device's line.
    local x, y = rect.x + rect.w - 4, rect.y + 1
    click(x, y)
    eq(api.device_get(d.id).bypass, true, "the device is bypassed")
    apart()
    shot()
    click(rect.x + rect.w - 5, y)
    eq(api.device_get(d.id).bypass, false, "and back on")
    local row
    for i, entry in ipairs(panel:rows()) do
      if entry.param and not row then row = i end
    end
    local p = panel:rows()[row].param
    local ly = rect.y + row - panel.scroll
    local lay = panel.layout(rect.w)
    local bar_at, bar = lay.bar_at, lay.bar
    click(rect.x + bar_at + bar - 1, ly)
    near(paw.params.fraction(p, api.device_get(d.id).params[p.key]), 1 - 0.5 / bar, 0.02, "the last cell of the slider")
    apart()
    click(rect.x + bar_at, ly)
    click(rect.x + bar_at, ly)
    near(api.device_get(d.id).params[p.key], p.default, 1e-6, "a double click: back to the default")
  end
)

test(
  "in the piano roll a note of another clip edited with the active one is chosen and dragged in its own clip",
  function()
    start()
    local t = paw.add_part({ name = "keys" })
    local first = t:add_clip({ name = "a", start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
    local second = t:add_clip({ name = "b", start = 4, length = 4, notes = { { pitch = 62, start = 1, length = 1 } } })
    roll:edit(first)
    paw.roll_clips.open({ first.id, second.id }, first.id)
    roll.top, roll.scroll = 72, 0
    shot()
    local rect
    for _, r in ipairs(paw.ui.rects) do
      if r.name == "pianoroll" then rect = r end
    end
    local g = roll.geometry
    local function at(pitch, beat)
      return rect.x + g.keys + math.floor(beat * g.zoom + 0.5), rect.y + g.head + (roll.top - pitch)
    end
    local x, y = at(62, 5.5)
    click(x, y)
    eq(paw.frontend.chosen_notes(second.id)[1], 1, "the second clip's note is chosen")
    apart()
    drag(x, y, x + 8, y)
    eq(notes_of(second), "62@2+1", "and moved a beat on in its own clip")
    eq(notes_of(first), "60@0+1", "the active clip's notes as they were")
  end
)

test("the command line's list: a click puts a candidate in the line, a second click runs it", function()
  start()
  paw.keymap.feed(":tempo.la")
  local x, y = find("tempo.lane")
  eq(x ~= nil, true, "the list is shown")
  local lines = shot()
  -- The candidate in the list, not the text typed on the bottom line.
  if y == H - 1 then
    for i = #lines - 1, 1, -1 do
      local at = lines[i]:find("tempo.lane", 1, true)
      if at then
        x, y = api.str_width(lines[i]:sub(1, at - 1)), i - 1
        break
      end
    end
  end
  click(x, y)
  eq(require("paw.views.cmdline").state().before, "tempo.lane", "the candidate is in the line")
  click(x, y)
  eq(require("paw.views.cmdline").state(), nil, "and run")
  eq(paw.tempolane.shown(), true, "it ran")
  paw.tempolane.show(false)
end)

test("a picker's row is chosen with two clicks", function()
  start()
  local chosen
  paw.pick({
    title = "Fruit",
    items = { { text = "apple" }, { text = "banana" }, { text = "cherry" } },
    on_choose = function(item) chosen = item.text end,
  })
  local x, y = find("banana")
  click(x, y)
  click(x, y)
  eq(chosen, "banana", "two clicks choose it")
end)
