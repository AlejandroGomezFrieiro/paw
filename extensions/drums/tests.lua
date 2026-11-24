-- Tests of the drums extension; tests/suite.lua runs them.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api

local drums
local function load()
  if not drums then
    paw.ext.load("extensions/drums")
    drums = require("drums")
  end
  return drums
end

--- A clip's hits as "pitch@start", in order; with `vel`, "pitch@start:velocity".
local function hits(clip, vel)
  local notes = clip:notes()
  table.sort(notes, function(a, b)
    if math.abs(a.start - b.start) > 1e-9 then return a.start < b.start end
    return a.pitch < b.pitch
  end)
  local out = {}
  for i, n in ipairs(notes) do
    out[i] = string.format("%d@%g", n.pitch, math.floor(n.start * 1000 + 0.5) / 1000)
      .. (vel and (":" .. n.velocity) or "")
  end
  return table.concat(out, " ")
end

local keys = T.keys

--- A fresh project with a drum part made by the command, its clip open in the grid.
local function drum_part()
  load()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  paw.opt.drums_step, paw.opt.drums_velocity = 0.25, 100
  paw.cmd("drums.part")
  paw.flush()
  local part = paw.cursor.part()
  local clip = part:clips()[1]
  local grid = paw.ui.views:get("drums")
  grid.step = nil
  api.undo_checkpoint()
  return part, clip, grid
end

local function screen(w, h) return table.concat(api.ui_snapshot(w or 120, h or 40), "\n") end

-- Maps and parts -------------------------------------------------------------------

test("drums: the General MIDI map names the pieces a beat needs, in order", function()
  local d = load()
  local names = {}
  for _, row in ipairs(d.maps.gm.rows) do
    names[#names + 1] = row.note .. " " .. row.name
  end
  eq(
    table.concat(names, ", "),
    "36 Kick, 38 Snare, 37 Rim, 39 Clap, 42 Closed hat, 44 Pedal hat, 46 Open hat, "
      .. "50 High tom, 47 Mid tom, 45 Low tom, 49 Crash, 51 Ride, 53 Ride bell, 56 Cowbell, 54 Tambourine",
    "the rows"
  )
  eq(#d.maps["gm-full"].rows, 47, "every General MIDI percussion note is in gm-full")
end)

test("drums: drums.part makes a part ready for drums in one step", function()
  local part, clip = drum_part()
  eq(part.name, "Drums", "named")
  eq(part.color, drums.colour, "coloured")
  eq(part:devices()[1].kind, "drums", "with the built-in kit")
  eq(drums.info(part).map, "gm", "and the General MIDI map")
  eq(#drums.rows(part), 15, "fifteen rows")
  eq(clip.length, paw.time.bar(), "a bar to program")
  eq(paw.ui.focused, "drums", "open in the drum grid")
  eq(paw.ui.views:get("drums").clip_id, clip.id, "on its clip")
  eq(
    paw.ui.visible("drums") and paw.ui.views:get("drums").title,
    "Drum grid",
    "docked, under its title in a window's pane"
  )
  eq(paw.ui.message.text:find("Ctrl-w p goes back", 1, true) ~= nil, true, "the message names the key that goes back")
  paw.ui.focus("arrange")
  local screen = table.concat(api.ui_snapshot(120, 30), "\n")
  eq(
    screen:find(" D Drums", 1, true) ~= nil,
    true,
    "the header's D stands clear of the name: " .. (screen:match("[^\n]*Drums[^\n]*") or "")
  )
end)

test("drums: the map is kept with the part in the project", function()
  local part = drum_part()
  local path = T.scratch .. "/drums-map.json"
  paw.project.save(path)
  paw.project.load(path)
  local again = paw.parts()[1]
  eq(drums.info(again).map, "gm", "the map's name")
  eq(drums.rows(again)[5].name, "Closed hat", "and its rows")
  eq(drums.is_drum(again), true, "still a drum part")
  local _ = part
end)

test("drums: drums.map turns any part into a drum part, and back", function()
  load()
  fresh()
  local synth = paw.add_part({ name = "Plugin kit" })
  synth:add_device("synth")
  paw.cursor.set_part(synth)
  eq(drums.is_drum(synth), false, "an ordinary part to begin with")
  paw.commands.exec("drums.map gm-full")
  eq(drums.info(synth).map, "gm-full", "a drum part with the map chosen")
  eq(synth:devices()[1].kind, "synth", "whatever its instrument")
  eq(#drums.rows(synth), 47, "all its rows")
  paw.commands.exec("drums.map off")
  eq(drums.is_drum(synth), false, "and an ordinary part again")
  T.fails(function() paw.commands.exec("drums.map nosuch") end, "no drum map", "an unknown map")
end)

test("drums: maps are plain tables an init.lua can add to", function()
  load()
  fresh()
  drums.maps.tiny = { label = "two pieces", rows = { { note = "C2", name = "Boom" }, { note = 40, name = "Crack" } } }
  local t = paw.add_part({ name = "T" })
  drums.set_map(t, "tiny")
  eq(drums.rows(t)[1].note, 36, "notes may be given by name")
  eq(drums.rows(t)[2].name, "Crack", "and the rows keep their names")
  drums.maps.tiny = nil
end)

test("drums: a note the map does not name still gets a row", function()
  local part, clip = drum_part()
  clip:add_note({ pitch = 81, start = 0, length = 0.25 })
  local rows = drums.rows(part, clip)
  eq(#rows, 16, "one more row")
  eq(rows[16].note, 81, "for the note")
  eq(rows[16].extra, true, "marked as outside the map")
  eq(rows[16].name, "Open triangle", "named after General MIDI")
  paw.flush()
  eq(screen():find("Open triangle", 1, true) ~= nil, true, "and shown in the grid")
end)

-- The terminal grid -------------------------------------------------------------------

test("drums: Enter toggles a hit, and the grid shows it by name and by how hard", function()
  local _, clip = drum_part()
  keys("<CR>")
  eq(hits(clip, true), "36@0:100", "a kick on the first step")
  keys("2l<CR>")
  eq(hits(clip), "36@0 36@0.5", "and on the third")
  keys("<CR>")
  eq(hits(clip), "36@0", "Enter again takes it out")
  keys("j2l<CR>")
  eq(hits(clip), "36@0 38@1", "a snare on beat two")
  paw.flush()
  local text = screen(120, 30)
  eq(text:find("Kick", 1, true) ~= nil and text:find("Snare", 1, true) ~= nil, true, "rows are named")
  eq(text:find("▇▇", 1, true) ~= nil, true, "a hit at 100 is drawn seven eighths tall")
end)

test("drums: the ruler marks the beats with ticks and no numbers, as the roll's does", function()
  drum_part()
  paw.flush()
  local lines = api.ui_snapshot(140, 30)
  local ruler
  for i, line in ipairs(lines) do
    if line:find("Kick", 1, true) and line:find("·", 1, true) then
      ruler = lines[i - 1]
      break
    end
  end
  eq(type(ruler), "string", "the ruler is above the first row")
  eq(ruler:find("▏", 1, true) ~= nil, true, "beats are ticks: " .. ruler)
  eq(ruler:find("▏%d") == nil, true, "with no number after them: " .. ruler)
end)

test("drums: a new hit is heard", function()
  local part = drum_part()
  eq(T.wakes(function() keys("<CR>") end, part:devices()[1]), true, "the kick sounds when it is entered")
end)

test("drums: + and - make a hit harder and softer", function()
  local _, clip = drum_part()
  keys("<CR>+")
  eq(hits(clip, true), "36@0:116", "harder")
  keys("3-")
  eq(hits(clip, true), "36@0:68", "a count goes three times as far")
  keys("9+")
  eq(hits(clip, true), "36@0:127", "never past 127")
  keys("[h")
  eq(hits(clip, true), "36@0:111", "[ is softer too, as in the piano roll")
end)

test("drums: the step size changes, with triplets", function()
  local _, clip, grid = drum_part()
  keys("]g")
  eq(grid:step_size(), 0.5, "]g is coarser")
  keys("<localleader>3")
  eq(grid:step_size(), 1 / 3, "\\3 makes it triplets")
  keys("[g")
  eq(grid:step_size(), 1 / 6, "[g is finer, still triplets")
  keys("ll<CR>")
  eq(hits(clip), "36@0.333", "a hit on the third sixteenth triplet")
  keys("<localleader>3")
  eq(grid:step_size(), 0.25, "\\3 again is straight")
end)

test("drums: motions move by steps, rows, hits and bars", function()
  local _, clip, grid = drum_part()
  clip.length = 8
  clip:add_notes({ { pitch = 38, start = 1, length = 0.25 }, { pitch = 38, start = 3, length = 0.25 } })
  keys("j")
  eq(grid:piece().name, "Snare", "j is the next row")
  keys("w")
  eq(grid.beat, 1, "w is the next hit on the row")
  keys("w")
  eq(grid.beat, 3, "and the next")
  keys("b")
  eq(grid.beat, 1, "b goes back")
  keys("W")
  eq(grid.beat, 4, "W is the next bar")
  keys("G")
  eq(grid:piece().name, "Tambourine", "G is the last row")
  keys("gg")
  eq(grid:piece().name, "Kick", "gg the first")
  keys("/clap<CR>")
  eq(grid:piece().name, "Clap", "a piece is found by name")
end)

test("drums: dd clears a row, and u brings it back", function()
  local _, clip = drum_part()
  clip:add_notes({
    { pitch = 36, start = 0, length = 0.25 },
    { pitch = 36, start = 2, length = 0.25 },
    { pitch = 38, start = 1, length = 0.25 },
  })
  api.undo_checkpoint()
  keys("dd")
  eq(hits(clip), "38@1", "the kicks are gone, the snare stays")
  paw.undo()
  eq(hits(clip), "36@0 38@1 36@2", "undone")
  keys("2dd")
  eq(hits(clip), "", "2dd clears two rows")
  paw.undo()
  keys("x")
  eq(hits(clip), "38@1 36@2", "x removes the hit under the cursor")
end)

test("drums: & repeats a bar to the end of the clip, or N times", function()
  local _, clip = drum_part()
  clip.length = 16
  clip:add_notes({ { pitch = 36, start = 0, length = 0.25 }, { pitch = 38, start = 1, length = 0.25 } })
  clip:add_note({ pitch = 42, start = 6, length = 0.25 })
  api.undo_checkpoint()
  keys("&")
  eq(hits(clip), "36@0 38@1 36@4 38@5 36@8 38@9 36@12 38@13", "every bar after it is the first again")
  paw.undo()
  keys("1&")
  eq(hits(clip), "36@0 38@1 36@4 38@5", "1& repeats it once, and what was there gives way")
  eq(clip.length, 16, "the clip keeps its length")
  clip.length = 4
  api.undo_checkpoint()
  keys("&")
  eq(clip.length, 8, "a one-bar clip grows to hold the repeat")
end)

test("drums: yank and paste hits, by row and by stretch of time", function()
  local _, clip = drum_part()
  clip.length = 8
  clip:add_notes({ { pitch = 36, start = 0, length = 0.25 }, { pitch = 38, start = 1, length = 0.25 } })
  api.undo_checkpoint()
  keys("yib")
  keys("W")
  keys("P")
  eq(hits(clip), "36@0 38@1 36@4 38@5", "a bar of every row pasted at the next bar")
  paw.undo()
  keys("0yy4jp")
  -- The kick row's hits go on the row the cursor is on: the closed hat.
  eq(hits(clip), "36@0 42@0 38@1", "a row pasted on another row")
end)

test("drums: visual mode selects hits to change together", function()
  local _, clip = drum_part()
  clip:add_notes({
    { pitch = 36, start = 0, length = 0.25 },
    { pitch = 36, start = 1, length = 0.25 },
    { pitch = 38, start = 1, length = 0.25 },
    { pitch = 36, start = 2, length = 0.25 },
  })
  api.undo_checkpoint()
  keys("<C-v>j5l-")
  eq(hits(clip, true), "36@0:84 36@1:84 38@1:84 36@2:100", "a block of two rows and five steps is softer")
  keys("0Vx")
  eq(hits(clip), "38@1", "the cursor is back where the selection began, and V then x clears that row")
end)

test("drums: > and < move hits by a step", function()
  local _, clip = drum_part()
  clip:add_note({ pitch = 36, start = 0, length = 0.25 })
  api.undo_checkpoint()
  keys(">ih")
  eq(hits(clip), "36@0.25", "a step later")
  keys("<lt>ih")
  eq(hits(clip), "36@0", "and back")
end)

test("drums: Enter opens a drum part's clip in the grid, other clips in the piano roll", function()
  load()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  -- Enter opens the roll and the grid in panes that Esc leaves on screen.
  T.after(function()
    paw.ui.hide("pianoroll")
    paw.ui.hide("drums")
  end)
  local keys_part = paw.add_part({ name = "Keys" })
  keys_part:add_device("synth")
  keys_part:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  local beat = drums.make_part({ name = "Beat" })
  beat:add_clip({ start = 0, length = 4 })
  paw.cursor.set_part(keys_part)
  paw.cursor.set_beat(0)
  paw.keymap.feed("<CR>")
  eq(paw.ui.focused, "pianoroll", "an ordinary clip opens in the piano roll")
  paw.keymap.feed("<C-w>p")
  paw.cursor.set_part(beat)
  paw.keymap.feed("<CR>")
  eq(paw.ui.focused, "drums", "a drum part's clip opens in the drum grid")
  paw.keymap.feed("<Esc>")
  eq(paw.ui.focused, "drums", "Esc stays in the grid, as in every view")
  paw.keymap.feed("<C-w>p")
  eq(paw.ui.focused, "arrange", "Ctrl-w p goes back")
end)

test("drums: the key bar shows only keys that are mapped", function()
  load()
  eq(table.concat(paw.ui.keybar.check(), ", "), "", "keys shown with nothing mapped to them")
end)

-- The pointer ----------------------------------------------------------------------
-- The grid is one view for both frontends: a window is sent its scene
-- (paw/scene.tl) and a press there goes through the grid's hit regions in
-- fractions of a cell (paw/roles.tl), as one in the terminal goes in cells.

local CELL = { w = 8, h = 16 }
local held = {}

--- The grid drawn for a window, 100 by 30 units: the patch that makes it.
local function scene()
  api.scene_forget(0, "drums")
  paw.ui.render_scene("drums", 100, 30, CELL)
  return api.json_decode(api.scene_end(0, "drums"))
end

--- The middle of a row's step, in the grid's cells, as the grid lays it out.
local function at(row, cell)
  local grid = paw.ui.views:get("drums")
  local g = grid.geometry
  return g.namew + (cell - grid.scroll) * 3 + 1.5, g.head + (row - grid.first) + 0.5
end

local function pointer(kind, x, y, extra)
  local e = paw.util.merge({ kind = kind, x = x, y = y, button = "left" }, extra or {})
  return paw.roles.input(0, "drums", paw.ui.views:get("drums"), nil, e, held)
end

local function click(row, cell, button)
  scene()
  local x, y = at(row, cell)
  pointer("down", x, y, { button = button or "left" })
  pointer("up", x, y, { button = button or "left" })
  paw.mouse.forget()
end

test("drums: the grid opens on a double click of a drum part's clip only", function()
  load()
  fresh()
  local keys_part = paw.add_part({ name = "Keys" })
  keys_part:add_device("synth")
  local other = keys_part:add_clip({ start = 0, length = 4 })
  paw.frontend.act.open_clip(other.id)
  eq(paw.ui.visible("drums"), false, "not for a clip of another part")
  eq(paw.ui.focused, "pianoroll", "which opens in the piano roll")
  local beat = drums.make_part({ name = "Beat" })
  local clip = beat:add_clip({ start = 0, length = 4 })
  paw.frontend.act.open_clip(clip.id)
  eq(paw.ui.visible("drums"), true, "a drum part's clip opens the drum grid")
  eq(paw.ui.views:get("drums").clip_id, clip.id, "on that clip")
end)

test("drums: a window is sent the grid's rows by name and its hits as roles by velocity", function()
  local _, clip = drum_part()
  clip:add_notes({
    { pitch = 36, start = 0, length = 0.25, velocity = 127 },
    { pitch = 38, start = 1, length = 0.25, velocity = 40 },
  })
  local patch = scene()
  local texts, hit_roles, steps, buttons = {}, {}, 0, {}
  for _, node in ipairs(patch.set) do
    if node.t == "run" then texts[node.text] = true end
    if node.role == "hit" then hit_roles[#hit_roles + 1] = node.props.velocity end
    if node.role == "step" then steps = steps + 1 end
    if node.role == "button" then buttons[#buttons + 1] = node.props.text end
  end
  eq(texts.Kick and texts.Snare and texts["Ride bell"] or false, true, "every row is named")
  table.sort(hit_roles)
  eq(table.concat(hit_roles, " "), "40 127", "a hit is a role with its velocity")
  eq(steps > 100, true, "and every other step a step")
  eq(
    table.concat(buttons, "|"):find(" 1/16 ", 1, true) ~= nil,
    true,
    "the toolbar's buttons: " .. table.concat(buttons, "|")
  )
  api.scene_forget(0)
end)

test("drums: clicking a cell adds a hit, clicking it again removes it, in a window and in the terminal", function()
  local _, clip = drum_part()
  click(1, 0)
  eq(hits(clip, true), "36@0:100", "a kick")
  click(2, 4)
  eq(hits(clip), "36@0 38@1", "a snare")
  click(1, 0)
  eq(hits(clip), "38@1", "the kick is gone")
  click(2, 4, "right")
  eq(hits(clip), "", "right click removes")
  -- The terminal: the same cell, in screen cells.
  paw.ui.focus("drums")
  api.ui_snapshot(120, 40)
  local rect
  for _, r in ipairs(paw.ui.rects) do
    if r.name == "drums" then rect = r end
  end
  local x, y = at(1, 2)
  paw.ui.mouse({ kind = "down", x = rect.x + math.floor(x), y = rect.y + math.floor(y), button = "left", mods = "" })
  paw.ui.mouse({ kind = "up", x = rect.x + math.floor(x), y = rect.y + math.floor(y), button = "left", mods = "" })
  eq(hits(clip), "36@0.5", "a kick on the third step, from the terminal")
  api.scene_forget(0)
end)

test("drums: dragging along a row paints hits, or erases them, as one undo step", function()
  local _, clip = drum_part()
  scene()
  local x0, y = at(5, 0)
  pointer("down", x0, y)
  for cell = 1, 7 do
    local x = at(5, cell)
    pointer("move", x, y + 2)
  end
  pointer("up", (at(5, 7)), y)
  paw.mouse.forget()
  api.undo_checkpoint()
  eq(
    hits(clip),
    "42@0 42@0.25 42@0.5 42@0.75 42@1 42@1.25 42@1.5 42@1.75",
    "eight hats along the row, though the pointer wandered off it"
  )
  scene()
  pointer("down", (at(5, 2)), y)
  pointer("move", (at(5, 5)), y)
  pointer("up", (at(5, 5)), y)
  paw.mouse.forget()
  api.undo_checkpoint()
  eq(hits(clip), "42@0 42@0.25 42@1.5 42@1.75", "a drag from a hit erases")
  paw.undo()
  eq(#clip:notes(), 8, "one undo brings the erased ones back")
  paw.undo()
  eq(#clip:notes(), 0, "and one more takes the painted ones away")
  api.scene_forget(0)
end)

test("drums: the velocity lane sets how hard the row's hits are", function()
  local _, clip, grid = drum_part()
  clip:add_notes({
    { pitch = 36, start = 0, length = 0.25 },
    { pitch = 36, start = 0.5, length = 0.25 },
    { pitch = 38, start = 0.5, length = 0.25 },
  })
  grid.row = 1
  scene()
  local lane = 30 - grid.geometry.lane
  local x0 = at(1, 0)
  pointer("down", x0, lane)
  pointer("move", (at(1, 2)), lane)
  pointer("up", (at(1, 2)), lane)
  paw.mouse.forget()
  eq(
    hits(clip, true),
    "36@0:127 36@0.5:127 38@0.5:100",
    "a stroke at the top makes the kicks it crosses as hard as can be"
  )
  scene()
  pointer("down", x0, lane + 1)
  pointer("up", x0, lane + 1)
  paw.mouse.forget()
  near(clip:notes()[1].velocity, 64, 2, "halfway up is half as hard")
  api.scene_forget(0)
end)

test("drums: the toolbar's buttons set the step and the clip's length", function()
  local _, clip, grid = drum_part()
  local function press(label)
    for _, node in ipairs(scene().set) do
      if node.role == "button" and node.props.text == " " .. label .. " " then
        pointer("down", node.r[1] + 1.5, node.r[2] + 0.5)
        pointer("up", node.r[1] + 1.5, node.r[2] + 0.5)
        paw.mouse.forget()
        return
      end
    end
    error("no button " .. label)
  end
  press("1/8T")
  eq(grid:step_size(), 1 / 3, "triplet eighths")
  press("1/16")
  eq(grid:step_size(), 0.25, "sixteenths")
  press("+")
  eq(clip.length, 2 * paw.time.bar(), "two bars")
  press("−")
  eq(clip.length, paw.time.bar(), "one again")
  api.scene_forget(0)
end)

test("drums: clicking a row's name plays the piece", function()
  local part, _, grid = drum_part()
  scene()
  local _, y = at(2, 0)
  local heard = T.wakes(function()
    pointer("down", 2.5, y)
    paw.mouse.forget()
  end, part:devices()[1])
  eq(grid:piece().name, "Snare", "the row is chosen")
  eq(heard, true, "and heard")
  api.scene_forget(0)
end)

test("drums: the ruler moves the playhead, which the grid shows", function()
  local _, clip, grid = drum_part()
  scene()
  local x = at(1, 4)
  pointer("down", x, grid.geometry.head - 0.5)
  paw.mouse.forget()
  near(paw.transport.position, clip.start + 1, 1e-9, "on the fifth step")
  local snap = api.ui_view_snapshot("drums", 100, 30)
  local found = false
  for _, run in ipairs(snap.rows[grid.geometry.head]) do
    if run.text:find(paw.draw.g.cap, 1, true) then found = true end
  end
  eq(found, true, "the playhead's cap on the ruler")
  api.scene_forget(0)
end)

-- The sound ---------------------------------------------------------------------------

test("drums: the built-in kit plays every row of the General MIDI map", function()
  local part, clip = drum_part()
  paw.project.tempo = 120
  local rows = drums.rows(part)
  clip.length = #rows
  local notes = {}
  for i, row in ipairs(rows) do
    notes[i] = { pitch = row.note, start = i - 1, length = 0.25 }
  end
  clip:add_notes(notes)
  -- A beat is half a second: each piece gets its own.
  local info = T.render({ bits = 16, ["end"] = #rows, tail = 0 })
  for i, row in ipairs(rows) do
    local peak = T.channel_peaks(info, (i - 1) * 0.5 + 0.005, (i - 1) * 0.5 + 0.1)
    eq(peak > 0.02, true, row.name .. " sounds: " .. peak)
  end
end)

test("drums: a closed hat cuts the open hat off", function()
  local _, clip = drum_part()
  paw.project.tempo = 120
  clip:add_note({ pitch = 46, start = 0, length = 0.25 })
  local open = T.channel_peaks(T.render({ bits = 16, ["end"] = 2, tail = 0 }), 0.4, 0.55)
  clip:add_note({ pitch = 42, start = 0.5, length = 0.25 })
  local cut = T.channel_peaks(T.render({ bits = 16, ["end"] = 2, tail = 0 }), 0.4, 0.55)
  eq(open > 0.005, true, "the open hat rings on alone: " .. open)
  eq(cut < 0.0005, true, "and stops when the closed hat comes: " .. cut)
end)

-- A kit of samples ------------------------------------------------------------------

--- A mono 16-bit WAV of `seconds` at `level`, at 48 kHz.
local function wav(path, level, seconds)
  local rate, n = 48000, math.floor(48000 * seconds)
  local function u32(v)
    return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
  end
  local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
  local sample = math.floor(level * 32767 + 0.5)
  local s = u16(sample % 65536)
  local body = s:rep(n)
  T.write_file(
    path,
    "RIFF"
      .. u32(36 + #body)
      .. "WAVEfmt "
      .. u32(16)
      .. u16(1)
      .. u16(1)
      .. u32(rate)
      .. u32(rate * 2)
      .. u16(2)
      .. u16(16)
      .. "data"
      .. u32(#body)
      .. body
  )
end

local kit_dir
local function samples()
  if kit_dir then return kit_dir end
  kit_dir = T.scratch .. "/kit"
  os.execute("mkdir -p '" .. kit_dir .. "'")
  wav(kit_dir .. "/Kick 808.wav", 0.5, 0.1)
  wav(kit_dir .. "/snare_tight.wav", 0.25, 0.1)
  wav(kit_dir .. "/hh closed.wav", 0.4, 0.05)
  wav(kit_dir .. "/OpenHat.wav", 0.3, 1.0)
  wav(kit_dir .. "/zap.wav", 0.2, 0.1)
  T.write_file(kit_dir .. "/notes.txt", "not a sound")
  return kit_dir
end

test("drums: a folder of samples becomes a kit, the files named by what they are", function()
  load()
  local kit = require("drums.kit")
  local pads, rows = kit.from_folder(samples())
  local by_note = {}
  for _, p in ipairs(pads) do
    by_note[p.note] = p.file:match("[^/]+$") .. (p.group > 0 and " g" .. p.group or "")
  end
  eq(by_note[36], "Kick 808.wav", "a kick on 36")
  eq(by_note[38], "snare_tight.wav", "a snare on 38")
  eq(by_note[42], "hh closed.wav g1", "a closed hat on 42, in the hats' group")
  eq(by_note[46], "OpenHat.wav g1", "an open hat on 46, in the same group")
  eq(by_note[60], "zap.wav", "what it does not know goes from 60 up")
  eq(#pads, 5, "and nothing that is not a sound")
  local names = {}
  for i, row in ipairs(rows) do
    names[i] = row.note .. " " .. row.name
  end
  eq(
    table.concat(names, ", "),
    "36 Kick 808, 38 snare_tight, 42 hh closed, 46 OpenHat, 60 zap",
    "rows named after the files, a beat's order"
  )
  eq(kit.classify("BD_01").name, "Kick", "short names too")
  eq(kit.classify("ride-bell").name, "Ride bell", "and two words")
  eq(kit.classify("hat_pedal").name, "Pedal hat", "pedal hats")
end)

test("drums: drums.kit makes a drum part that plays the files", function()
  load()
  fresh()
  paw.project.tempo = 120
  paw.commands.exec("drums.kit " .. samples())
  local part = paw.cursor.part()
  eq(drums.is_drum(part), true, "a drum part")
  eq(part:devices()[1].kind, "sampler", "playing samples")
  eq(drums.rows(part)[1].name, "Kick 808", "its rows named after the files")
  local clip = part:add_clip({
    start = 0,
    length = 4,
    notes = {
      { pitch = 36, start = 0, length = 0.25, velocity = 127 },
      { pitch = 38, start = 1, length = 0.25, velocity = 127 },
      { pitch = 60, start = 2, length = 0.25, velocity = 127 },
    },
  })
  local info = T.render({ bits = 16, ["end"] = 4, tail = 0 })
  near(T.channel_peaks(info, 0.01, 0.09), 0.5, 0.01, "the kick file, as loud as it is")
  near(T.channel_peaks(info, 0.51, 0.59), 0.25, 0.01, "the snare file")
  near(T.channel_peaks(info, 1.01, 1.09), 0.2, 0.01, "the one it did not know")
  eq(T.channel_peaks(info, 0.15, 0.45) < 0.001, true, "and nothing between")

  -- Saved with the project, and heard again when it is opened.
  local path = T.scratch .. "/drums-kit.json"
  paw.project.save(path)
  paw.project.load(path)
  info = T.render({ bits = 16, ["end"] = 4, tail = 0 })
  near(T.channel_peaks(info, 0.01, 0.09), 0.5, 0.01, "the kick after opening the project again")
  local _ = clip
end)

test("drums: a pad's level, pan, tuning and group are set, and undone", function()
  load()
  fresh()
  paw.project.tempo = 120
  local part = drums.make_part({ kit = samples() })
  local kit = require("drums.kit")
  local device = kit.device(part)
  part:add_clip({ start = 0, length = 4, notes = { { pitch = 36, start = 0, length = 0.25, velocity = 127 } } })
  api.undo_checkpoint()
  kit.set_pad(device, 36, { level = -6.0206, pan = -1 })
  api.undo_checkpoint()
  local info = T.render({ bits = 16, ["end"] = 1, tail = 0 })
  local left, right = T.channel_peaks(info, 0.01, 0.09)
  near(left, 0.5 * 0.5 * math.sqrt(2), 0.01, "half as loud, and all on the left")
  eq(right < 0.001, true, "nothing on the right")
  paw.undo()
  info = T.render({ bits = 16, ["end"] = 1, tail = 0 })
  left, right = T.channel_peaks(info, 0.01, 0.09)
  near(left, 0.5, 0.01, "undo puts the pad back")
  near(right, 0.5, 0.01, "in the middle")
  kit.set_pad(device, 36, { tune = 12 })
  eq(kit.pads(device)[1].tune, 12, "tuned an octave up")
  local open, closed = 46, 42
  part:clips()[1]:set_notes({
    { pitch = open, start = 0, length = 0.25, velocity = 127 },
    { pitch = closed, start = 0.5, length = 0.25, velocity = 127 },
  })
  info = T.render({ bits = 16, ["end"] = 2, tail = 0 })
  eq(T.channel_peaks(info, 0.35, 0.6) < 0.001, true, "the closed hat cuts the open one off, by their group")
  kit.set_pad(device, closed, { group = 0 })
  info = T.render({ bits = 16, ["end"] = 2, tail = 0 })
  near(T.channel_peaks(info, 0.35, 0.6), 0.3, 0.01, "and does not once it is out of the group")
end)

test("drums: a kit's files are read again for a render, and a missing one is reported", function()
  load()
  fresh()
  local part = drums.make_part({ kit = samples() })
  local kit = require("drums.kit")
  local device = kit.device(part)
  kit.set_pad(device, 37, { file = T.scratch .. "/nowhere.wav" })
  paw.flush()
  local status = api.device_call(device.id, "status")
  eq(status:find("37 missing", 1, true) ~= nil, true, "the status says which file is missing")
  eq(status:find("36 4800 48000", 1, true) ~= nil, true, "and what the others hold")
end)

-- Swing and beats --------------------------------------------------------------------

test("drums: gs swings every other step of what it covers, and does not add up", function()
  local _, clip = drum_part()
  clip:add_notes({
    { pitch = 42, start = 0, length = 0.25 },
    { pitch = 42, start = 0.25, length = 0.25 },
    { pitch = 42, start = 0.5, length = 0.25 },
    { pitch = 42, start = 0.75, length = 0.25 },
    { pitch = 36, start = 0.25, length = 0.25 },
  })
  paw.opt.drums_swing = 0.33
  api.undo_checkpoint()
  keys("4jgsir")
  eq(
    hits(clip),
    "42@0 36@0.25 42@0.333 42@0.5 42@0.833",
    "the hats' offbeats are a third of a step late; the kick is not touched"
  )
  keys("gsir")
  eq(hits(clip), "42@0 36@0.25 42@0.333 42@0.5 42@0.833", "swinging again changes nothing")
  paw.undo()
  paw.undo()
  keys("50gsic")
  eq(hits(clip), "42@0 36@0.375 42@0.375 42@0.5 42@0.875", "a count is the percent of a step, for every row")
  paw.transport.seek(4)
  keys("g0")
  eq(paw.transport.position, 0, "g0 is the playhead to the start here too")
end)

test("drums: a beat to start from fills the clip", function()
  local _, clip = drum_part()
  clip.length = 8
  clip:add_note({ pitch = 81, start = 0, length = 0.25 })
  paw.commands.exec("drums.beat rock")
  local text = hits(clip)
  eq(text:find("81@", 1, true), nil, "in place of what was there")
  eq(
    paw.ui.message.text:find("1 note outside the drum map went", 1, true) ~= nil,
    true,
    "a note on no row of the map is counted: " .. paw.ui.message.text
  )
  eq(text:find("36@0 42@0 ", 1, true) == 1, true, "kick and hat on one: " .. text)
  eq(text:find("38@1 ", 1, true) ~= nil and text:find("38@5 ", 1, true) ~= nil, true, "snare on two, in both bars")
  eq(#clip:notes(), 2 * (8 + 2 + 3), "every bar of the clip")
  T.fails(function() paw.commands.exec("drums.beat polka") end, "no beat", "an unknown beat")
end)

test("drums: a drum part is a kind of part, made by part.add and opened in the grid", function()
  fresh()
  load()
  paw.ui.focus("arrange")
  local part = paw.cmd("part.add", { "drums" })
  eq(paw.part_kinds.of(part.id), "drums", "part.add drums makes a drum part")
  eq(drums.is_drum(part.id), true, "with a map")
  eq(part:devices()[1].kind, "drums", "and the kit")
  eq(paw.part_kinds.describe(part.id), "Drum part · " .. paw.opt.drums_map .. " map", "described with its map")
  local clip = part:add_clip({ start = 0, length = 4 })
  paw.cursor.set_part(part)
  paw.cursor.set_beat(1)
  paw.cmd("clip.edit")
  eq(paw.ui.focused, "drums", "its clips open in the drum grid")
  eq(clip ~= nil, true, "")
  paw.ui.focus("arrange")
  drums.clear_map(part)
  eq(paw.part_kinds.of(part.id), nil, "without its map it is an ordinary part")
end)
