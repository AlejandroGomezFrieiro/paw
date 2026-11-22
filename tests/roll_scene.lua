-- Tests of the piano roll as a window shows it: from its scene (its grid a
-- plane of beats and pitches, each note on it a role a window paints
-- between cells), with the pointer coming back in fractions of a cell
-- (`scene.input`) to the same gestures the terminal's mouse reaches.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local roll = paw.ui.views.pianoroll

local W, H, CELL = 160, 30, { w = 8, h = 16 }

-- What the window's watcher keeps of a drag under way.
local held = {}

--- Draw the roll's scene for a window that paints notes and buttons, as
--- the kernel sends it.
local function redraw()
  paw.ui.render_scene("pianoroll", W, H, CELL)
  local patch = api.scene_end(0, "roll")
  return patch and api.json_decode(patch)
end

--- A clip of two bars open in the roll with notes as given; and where a
--- pitch and a beat are in the window's units (the middle of the row).
local function opened(notes)
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  local saved = { zoom = paw.opt.note_zoom, grid = paw.opt.note_grid, snap = paw.opt.note_snap }
  T.after(function()
    paw.opt.note_zoom, paw.opt.note_grid, paw.opt.note_snap = saved.zoom, saved.grid, saved.snap
    roll:set_step(nil)
    paw.mouse.forget()
    api.scene_forget(0)
    paw.ui.hide("pianoroll")
  end)
  paw.opt.note_zoom, paw.opt.note_grid, paw.opt.note_snap = 8, 0.25, true
  local t = paw.add_track({ name = "keys" })
  local clip = t:add_clip({ name = "riff", start = 0, length = 8, notes = notes or {} })
  roll:edit(clip)
  roll.top, roll.scroll, roll.pitch, roll.beat = 72, 0, 60, 0
  api.undo_checkpoint()
  api.scene_forget(0)
  api.scene_roles(0, { "note", "button" })
  redraw()
  local g = roll.geometry
  local function at(pitch, beat) return g.keys + (beat - roll.scroll) * g.zoom, g.head + (roll.top - pitch) + 0.5 end
  return clip, at
end

--- A pointer event from the window, in units of the roll's window; then
--- the roll drawn again, as the kernel does after a turn.
local function input(kind, x, y, extra)
  local e = { kind = kind, x = x, y = y, button = "left" }
  for k, v in pairs(extra or {}) do
    e[k] = v
  end
  local taken = paw.roles.input(0, "roll", roll, nil, e, held)
  api.undo_checkpoint()
  redraw()
  return taken
end

local function drag(x0, y0, x1, y1, extra)
  input("down", x0, y0, extra)
  for i = 1, 4 do
    input("move", x0 + (x1 - x0) * i / 4, y0 + (y1 - y0) * i / 4, extra)
  end
  input("up", x1, y1, extra)
end

local function notes_of(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do
    out[#out + 1] = string.format("%d@%g+%g", n.pitch, n.start, n.length)
  end
  return table.concat(out, " ")
end

test("the roll's scene: its grid a plane, each note on it a role, and a row of tools as buttons", function()
  local clip = opened({ { pitch = 60, start = 1.5, length = 0.5, velocity = 90 } })
  local patch
  api.scene_forget(0)
  patch = redraw()
  local plane, note, tools = nil, nil, {}
  for _, n in ipairs(patch.set) do
    if n.t == "plane" and n.hit and n.hit.kind == "grid" then plane = n end
    if n.role == "note" then note = n end
    if n.role == "button" then tools[#tools + 1] = n.props.label end
  end
  eq(plane ~= nil and plane.x.domain .. " " .. plane.y.domain, "beat pitch", "the grid, a plane of beats and pitches")
  eq(
    plane.x.per .. " " .. plane.y.from .. " " .. plane.y.per,
    "8 73 -1",
    "eight units a beat, a row a pitch down from the top"
  )
  eq(api.json_encode(note.r), "[1.5,60,0.5,1]", "the note where it is in the plane's domain, between cells")
  eq(note.hit.clip .. " " .. note.hit.place, clip.id .. " 1", "named by its clip and place for the pointer")
  eq(note.props.label .. " " .. note.props.velocity, "C4 90", "with what a window paints it by")
  eq(
    table.concat(tools, " "):find("Quantize Step List", 1, true) ~= nil,
    true,
    "the tools: " .. table.concat(tools, " ")
  )
end)

test(
  "in a window a press on empty grid draws a note on the step under the pointer, and a drag draws it as long",
  function()
    local clip, at = opened()
    local x, y = at(64, 1.1)
    input("down", x, y)
    input("up", x, y)
    eq(notes_of(clip), "64@1+0.25", "a click: one step, on the step the pointer was in")
    x, y = at(67, 2.05)
    local x1 = at(67, 2.9)
    drag(x, y, x1, y)
    eq(notes_of(clip), "64@1+0.25 67@2+1", "to the end of the step it was let go in")
  end
)

test(
  "in a window a note wavering under a click is only chosen, and a drag moves it by the beats and rows the pointer went",
  function()
    local clip, at = opened({ { pitch = 60, start = 0, length = 1 } })
    local x, y = at(60, 0.5)
    drag(x, y, x + 0.3, y + 0.2)
    eq(paw.frontend.chosen_notes(clip.id)[1], 1, "chosen")
    eq(notes_of(clip), "60@0+1", "and left where it was")
    paw.mouse.forget()
    drag(x, y, x + 8, y - 2)
    eq(notes_of(clip), "62@1+1", "a beat on and two semitones up")
  end
)

test("in a window the end of a note drags by a fraction of a cell", function()
  local clip, at = opened({ { pitch = 60, start = 1, length = 1 } })
  -- Within the last unit of the note's eight: its end.
  local x, y = at(60, 1.95)
  drag(x, y, x + 4, y)
  eq(notes_of(clip), "60@1+1.5", "half a beat longer")
end)

test("in a window the velocity strip is drawn on and a tool of the row is clicked", function()
  local clip, at = opened({ { pitch = 60, start = 0.1, length = 1 }, { pitch = 62, start = 1, length = 1 } })
  local g = roll.geometry
  eq(g.vel > 0, true, "the strip shows")
  local top = g.head + g.rows
  local x0, x1 = at(60, 0.1), at(62, 1)
  drag(x0, top + 0.1, x1, top + 0.1)
  eq(clip:notes()[1].velocity > 110 and clip:notes()[2].velocity > 110, true, "both near the top")
  -- The quantize button, at the right of the title row of a wide roll.
  local snap = api.ui_view_snapshot("pianoroll", W, H)
  local row, text = snap.rows[1], ""
  for _, run in ipairs(row) do
    text = text .. run.text
  end
  local col = text:find(" Quantize ", 1, true)
  eq(col ~= nil, true, "the title row: " .. text)
  local x = api.str_width(text:sub(1, col - 1)) + 2.5
  input("down", x, 0.5)
  input("up", x, 0.5)
  eq(notes_of(clip), "60@0+1 62@1+1", "the notes quantized")
end)

test(
  "a right click in a window on empty grid opens the grid's menu, which the window is told of and chooses from",
  function()
    local clip, at = opened({ { pitch = 60, start = 0, length = 1 }, { pitch = 62, start = 1, length = 1 } })
    local x, y = at(66, 4)
    input("down", x, y, { button = "right" })
    input("up", x, y, { button = "right" })
    local items, count = require("paw.menu").shown()
    eq(items ~= nil, true, "a menu is open")
    eq(paw.frontend.state(-1).modal.menu, count, "the window is told of it")
    local listed = paw.frontend.menu("shown", {})
    eq(listed[1].label, "Choose every note", "and shows its entries")
    paw.frontend.act.menu_choose("shown", {}, { 1 })
    eq(#paw.frontend.chosen_notes(clip.id), 2, "its first chooses every note")
    eq(require("paw.menu").shown(), nil, "and the menu is let go")
    input("down", x, y, { button = "right" })
    input("up", x, y, { button = "right" })
    paw.frontend.act.menu_dismiss()
    eq(require("paw.menu").shown(), nil, "the window letting go of it lets go of it here too")
  end
)

test("the roll's row of tools works from the terminal too, under the title of a narrow roll", function()
  local clip = opened({ { pitch = 60, start = 0.1, length = 1 } })
  paw.ui.show("pianoroll")
  paw.ui.focus("pianoroll")
  api.ui_snapshot(90, 40)
  local rect
  for _, r in ipairs(paw.ui.rects) do
    if r.name == "pianoroll" then rect = r end
  end
  local snap = api.ui_snapshot(90, 40)
  local text = snap[rect.y + 2]
  local col = text and text:find("Quantize", 1, true)
  eq(col ~= nil, true, "the row under the title: " .. tostring(text))
  local x = paw.api.str_width(text:sub(1, col - 1)) + 1
  paw.ui.mouse({ kind = "down", x = x, y = rect.y + 1, button = "left", mods = "" })
  paw.ui.mouse({ kind = "up", x = x, y = rect.y + 1, button = "left", mods = "" })
  eq(notes_of(clip), "60@0+1", "quantized")
end)

--- The nodes of the roll's scene a window that paints the roll's roles
--- is sent, by role (`role` nil for every node).
local function nodes_of(role)
  api.scene_forget(0)
  api.scene_roles(0, { "note", "button", "keyboard", "playhead", "scrollbar" })
  local patch = redraw()
  local out = {}
  for _, n in ipairs(patch.set) do
    if role == nil or n.role == role then out[#out + 1] = n end
  end
  return out
end

test("a wide roll's title row holds its tools as buttons, and a window gives it no title of its own", function()
  opened()
  local buttons = {}
  for _, n in ipairs(nodes_of("button")) do
    if n.r[2] == 0 then buttons[#buttons + 1] = n.props.label end
  end
  local said = table.concat(buttons, " ")
  eq(
    said:find("Tracks Grid 1/16 Snap Note 1/16 Quantize Step List", 1, true) ~= nil,
    true,
    "in the title row: " .. said
  )
  eq(said:find("Window x", 1, true) ~= nil, true, "with its own window and close: " .. said)
  paw.ui.show("pianoroll")
  -- As a window's main area is: put back after, with the panel it shows.
  local devices = paw.ui.visible("devices")
  T.after(function()
    paw.panes.area(0, 0)
    if not devices then paw.ui.hide("devices") end
  end)
  paw.panes.area(1500, 900)
  local titled
  for _, p in ipairs(paw.panes.state().panes) do
    if p.view == "pianoroll" then titled = p.titled end
  end
  eq(titled, true, "the window shows its title row")
end)

test("the keyboard is a role naming the cursor's key, and the octaves' Cs in cells", function()
  opened()
  local keys = nodes_of("keyboard")[1]
  eq(keys ~= nil and keys.props.top .. " " .. keys.props.cursor, "72 60", "from the top row, the cursor on C4")
  eq(keys.hit.kind, "keys", "and the pointer's")
  local snap = api.ui_view_snapshot("pianoroll", W, H)
  local text = ""
  for _, row in ipairs(snap.rows) do
    for _, run in ipairs(row) do
      text = text .. run.text
    end
  end
  eq(
    text:find("C4", 1, true) ~= nil and text:find("C5", 1, true) ~= nil,
    true,
    "the cursor's key and a C named in cells"
  )
end)

test("past the clip the grid goes on, shaded, with its lines", function()
  opened()
  local g = roll.geometry
  local snap = api.ui_view_snapshot("pianoroll", W, H)
  local text = ""
  for _, run in ipairs(snap.rows[g.head + 3]) do
    text = text .. run.text
  end
  -- Two bars of the clip at eight columns a beat end at column 64.
  local past = text:sub(-30)
  eq(
    past:find(paw.draw.g.bar, 1, true) ~= nil or past:find(paw.draw.g.beat, 1, true) ~= nil,
    true,
    "lines past the end: " .. past
  )
end)

test(
  "the playhead is a role bound to the song's position, and a window that paints it is sent no new scene as the song plays",
  function()
    opened()
    local head = nodes_of("playhead")[1]
    eq(head ~= nil and head.bind, "position", "bound to the position")
    eq(head.props.at, nil, "which the window takes from the live values")
    eq(head.props.per, 8, "at the roll's columns a beat")
    eq(roll.live_roles[1], "playhead", "the roll says it is what moves on its own")
  end
)

test("in a window a scroll bar dragged scrolls the pitches", function()
  opened()
  local bar
  for _, n in ipairs(nodes_of("scrollbar")) do
    if n.props.axis == "y" then bar = n end
  end
  eq(bar ~= nil and bar.props.total, 128, "a bar down the right, over every pitch")
  local top = roll.top
  local x, y = bar.r[1] + 0.5, bar.r[2] + 2.5
  drag(x, y, x, y + 4)
  eq(roll.top < top, true, "dragged down, lower pitches: " .. top .. " to " .. roll.top)
end)

test("in a window a note being dragged is shown where the pointer is, between cells", function()
  local _, at = opened({ { pitch = 60, start = 0, length = 1 } })
  local x, y = at(60, 0.5)
  input("down", x, y)
  input("move", x + 3, y)
  input("move", x + 6, y)
  local ghost
  for _, n in ipairs(nodes_of("note")) do
    if n.props.ghost then ghost = n end
  end
  input("up", x + 6, y)
  eq(ghost ~= nil and ghost.r[1], 0.75, "six units on is three quarters of a beat")
end)

test("the velocity strip's name is a button that opens the menu of what it shows", function()
  opened()
  local name
  for _, n in ipairs(nodes_of("button")) do
    if n.hit and n.hit.kind == "velocity" then name = n end
  end
  eq(name ~= nil and name.props.label, "Velocity", "what it shows")
  input("down", name.r[1] + 1.5, name.r[2] + 0.5)
  input("up", name.r[1] + 1.5, name.r[2] + 0.5)
  local items = require("paw.menu").shown()
  eq(items ~= nil and items[2].label, "Pitch wheel", "a menu of what it can show")
  paw.frontend.act.menu_dismiss()
end)

test("in the roll a jump to a note off screen puts it at the left margin", function()
  opened({ { pitch = 60, start = 0, length = 1 }, { pitch = 60, start = 6, length = 1 } })
  local saved = { view = paw.opt.jumpview, margin = paw.opt.jumpmargin }
  T.after(function()
    paw.opt.jumpview, paw.opt.jumpmargin = saved.view, saved.margin
  end)
  paw.opt.jumpview, paw.opt.jumpmargin = "left", 6
  paw.opt.note_zoom = 32
  redraw()
  eq(roll.scroll, 0, "the note at 6 is off screen")
  paw.keymap.feed("*")
  redraw()
  eq(roll.beat, 6, "the cursor is on the second note")
  eq(roll.scroll, 5, "the note is a beat from the left edge, not at the right")
end)
