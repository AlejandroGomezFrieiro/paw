-- Tests for the sections extension; run by tests/suite.lua.
local T = ...
local test, eq, near = T.test, T.eq, T.near
local paw = require("paw")
local api = paw.api

local function load()
  if not package.loaded["sections.ui"] then paw.ext.load("extensions/sections") end
  return require("sections")
end

local keys = T.keys

--- Where a track's clips are, in time order: "a@0+8 b@8+8".
local function layout(t)
  local list = api.clip_list(t.id)
  table.sort(list, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.name < b.name
  end)
  for i, c in ipairs(list) do list[i] = string.format("%s@%g+%g", c.name, c.start, c.length) end
  return table.concat(list, " ")
end

--- The sections as "Intro@0 Verse@8".
local function names(S)
  local out = {}
  for i, s in ipairs(S.list()) do out[i] = s.name .. "@" .. s.start end
  return table.concat(out, " ")
end

--- A lane's points as "0:-60 16:0".
local function points(lane)
  local out = {}
  for i, p in ipairs(api.lane_points(lane.id)) do out[i] = string.format("%g:%g", p[1], p[2]) end
  return table.concat(out, " ")
end

--- A song of four sections of two bars (Intro, Verse, Chorus, Outro). Track
--- A has a clip per section named after it; track B one long pad from beat 4
--- to 28 whose note at each beat is pitch 60 + beats into the pad; track A
--- has volume automation.
local function song()
  T.fresh()
  local S = load()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  local a = paw.add_track({ name = "A" })
  local b = paw.add_track({ name = "B" })
  for i, name in ipairs({ "i", "v", "c", "o" }) do
    a:add_clip({ name = name, start = (i - 1) * 8, length = 8, notes = { { pitch = 50 + i, start = 0, length = 1 } } })
  end
  local notes = {}
  for beat = 0, 23 do notes[#notes + 1] = { pitch = 60 + beat, start = beat, length = 1 } end
  b:add_clip({ name = "pad", start = 4, length = 24, notes = notes })
  local lane = a:automate("volume")
  lane:set_points({ { 0, -60 }, { 16, 0 }, { 24, -6 } })
  for i, name in ipairs({ "Intro", "Verse", "Chorus", "Outro" }) do S.add(name, (i - 1) * 8) end
  paw.cursor.set_track(a)
  paw.cursor.set_beat(0)
  paw.opt.grid, paw.opt.ripple = 1, false
  api.undo_checkpoint()
  paw.flush()
  return S, a, b, lane
end

--- The first note of the clip of a track that starts at a beat.
local function first_note(t, start)
  for _, c in ipairs(t:clips()) do
    if math.abs(c.start - start) < 1e-9 then
      local list = c:notes()
      table.sort(list, function(x, y) return x.start < y.start end)
      return list[1] and string.format("%d@%g", list[1].pitch, list[1].start)
    end
  end
end

test("sections: stored in the project, through undo, save and load", function()
  local S = song()
  eq(names(S), "Intro@0 Verse@8 Chorus@16 Outro@24", "added in order")
  eq(S.list()[4].finish, 32, "the last section runs to the end of the project")
  eq(S.at(10).name, "Verse", "the section a beat lies in")
  eq(S.find("cho").name, "Chorus", "found by the start of a name")
  local changes = 0
  local handle = paw.on("sections.changed", function() changes = changes + 1 end)
  S.rename("Verse", "Verse 1")
  S.remove("Outro")
  api.undo_checkpoint()
  paw.flush()
  eq(names(S), "Intro@0 Verse 1@8 Chorus@16", "renamed and removed")
  eq(S.list()[3].finish, 32, "Chorus now runs to the end")
  eq(changes, 1, "one event for one change")
  paw.undo()
  paw.flush()
  eq(names(S), "Intro@0 Verse@8 Chorus@16 Outro@24", "undone")
  eq(changes, 2, "undo reports the change too")
  paw.redo()
  paw.flush()
  eq(names(S), "Intro@0 Verse 1@8 Chorus@16", "redone")
  T.fails(function() S.add("Again", 8) end, "starts there already", "two sections at a beat")
  local path = T.scratch .. "/sections.json"
  paw.project.save(path)
  paw.project.new()
  paw.flush()
  eq(names(S), "", "a new project has none")
  paw.project.load(path)
  paw.flush()
  eq(names(S), "Intro@0 Verse 1@8 Chorus@16", "loaded back")
  eq(changes, 5, "new and load report the change")
  paw.off(handle)
end)

test("sections: ]s and [s move between starts, alone and after operators", function()
  local S, a, b = song()
  keys("]s")
  eq(paw.cursor.beat, 8, "]s goes to the next section")
  keys("2]s")
  eq(paw.cursor.beat, 24, "2]s goes two on")
  keys("]s")
  eq(paw.cursor.beat, 32, "past the last section, to the end of the project")
  paw.cursor.set_beat(20)
  keys("[s")
  eq(paw.cursor.beat, 16, "[s goes to the start of this section")
  keys("[s")
  eq(paw.cursor.beat, 8, "and again to the one before")
  paw.cursor.set_beat(10)
  keys("d]s")
  eq(layout(a), "i@0+8 v@8+2 c@16+8 o@24+8", "d]s deletes up to the next section, on the cursor's track")
  eq(layout(b), "pad@4+24", "and nowhere else")
  paw.undo()
  paw.cursor.set_beat(12)
  keys("v[sd")
  eq(layout(a), "i@0+8 v@12+4 c@16+8 o@24+8", "v[s selects back to the section start")
  eq(#S.list(), 4, "deleting time leaves the markers")
end)

test("sections: is and as with operators and in visual mode", function()
  local S, a, b = song()
  paw.cursor.set_beat(10)
  keys("dis")
  eq(layout(a), "i@0+8 c@16+8 o@24+8", "dis empties the section on track A")
  eq(layout(b), "pad@4+4 pad@16+12", "and on track B, cutting the pad at its edges")
  paw.undo()
  paw.cursor.set_beat(10)
  keys("yis")
  local value = paw.keymap.getreg()
  eq(value.kind .. " " .. value.length .. " " .. #value.rows, "range 8 2", "yis yanks the section on every track")
  paw.cursor.set_beat(10)
  keys("glis")
  eq(paw.transport.loop_start .. "-" .. paw.transport.loop_end, "8-16", "glis loops the section")
  eq(paw.transport.loop_enabled, true, "and turns looping on")
  paw.cursor.set_beat(18)
  paw.keymap.feed("vis")
  local sel = paw.keymap.selection()
  eq(string.format("%d-%d %g-%g", sel.r0, sel.r1, sel.c0, sel.c1), "1-2 16-24", "vis selects the section on every track")
  paw.keymap.feed("<Esc>")
  paw.cursor.set_beat(2)
  keys("d2is")
  eq(layout(a), "c@16+8 o@24+8", "d2is takes two sections")
  paw.undo()
  -- A pickup: a section starting half way through a bar.
  S.set_start("Chorus", 14)
  api.undo_checkpoint()
  paw.cursor.set_beat(15)
  keys("das")
  eq(layout(a), "i@0+8 v@8+4 o@24+8", "das widens the section to whole bars")
end)

test("sections: moving a section past its neighbour, on every track, as one undo step", function()
  local S, a, b, lane = song()
  local cutoff = b:add_device("synth"):automate("cutoff")
  cutoff:set_points({ { 8, 300 }, { 16, 3000 } })
  api.undo_checkpoint()
  paw.cursor.set_beat(9)
  keys(",SL")
  eq(points(cutoff), "8:300 8:3000 16:3000 16:300 24:3000", "a device parameter's automation moves too")
  eq(names(S), "Intro@0 Chorus@8 Verse@16 Outro@24", "the markers swap")
  eq(layout(a), "i@0+8 c@8+8 v@16+8 o@24+8", "track A's clips swap")
  eq(layout(b), "pad@4+4 pad@8+8 pad@16+8 pad@24+4", "track B's pad is cut at the edges and its pieces swap")
  eq(first_note(b, 8), "72@0", "the chorus's notes moved with it")
  eq(first_note(b, 16), "64@0", "and the verse's")
  eq(points(lane), "0:-60 8:-30 8:0 16:-6 16:-30 24:0 24:-6", "the automation moves with its section")
  near(api.lane_value_at(lane.id, 12), -3, 1e-9, "the chorus sounds as it did")
  eq(paw.cursor.beat, 16, "the cursor goes with the section")
  paw.undo()
  eq(names(S), "Intro@0 Verse@8 Chorus@16 Outro@24", "one undo puts the markers back")
  eq(layout(a) .. " | " .. layout(b), "i@0+8 v@8+8 c@16+8 o@24+8 | pad@4+24", "and every clip")
  eq(points(lane), "0:-60 16:0 24:-6", "and the automation")
  paw.cursor.set_beat(24)
  keys(",SH")
  eq(names(S), "Intro@0 Verse@8 Outro@16 Chorus@24", ",SH moves it earlier")
  eq(layout(a), "i@0+8 v@8+8 o@16+8 c@24+8", "with its clips")
  paw.undo()
  paw.cursor.set_beat(0)
  keys("2,SL")
  eq(names(S), "Verse@0 Chorus@8 Intro@16 Outro@24", "a count moves it further")
  keys(".")
  eq(names(S), "Verse@0 Chorus@8 Outro@16 Intro@24", ". does it again")
end)

test("sections: duplicate, delete closing the gap, insert elsewhere", function()
  local S, a, b, lane = song()
  paw.cursor.set_beat(17)
  keys(",S&")
  eq(names(S), "Intro@0 Verse@8 Chorus@16 Chorus@24 Outro@32", "duplicated after itself")
  eq(layout(a), "i@0+8 v@8+8 c@16+8 c@24+8 o@32+8", "on track A")
  eq(layout(b), "pad@4+12 pad@16+8 pad@24+8 pad@32+4", "and track B")
  eq(first_note(b, 24), "72@0", "the copy has the notes")
  eq(points(lane), "0:-60 16:0 24:-6 24:0 32:-6", "and the automation")
  paw.undo()
  eq(layout(a) .. " | " .. layout(b), "i@0+8 v@8+8 c@16+8 o@24+8 | pad@4+24", "one undo")

  paw.cursor.set_beat(9)
  keys(",Sd")
  eq(names(S), "Intro@0 Chorus@8 Outro@16", "delete closes the gap")
  eq(layout(a), "i@0+8 c@8+8 o@16+8", "on track A")
  eq(layout(b), "pad@4+4 pad@8+12", "and track B")
  eq(points(lane), "0:-60 8:-30 8:0 16:-6", "the automation closes up too")
  -- Put it back before the Outro: the register brings clips, automation and marker.
  paw.cursor.set_beat(17)
  keys(",SP")
  eq(names(S), "Intro@0 Chorus@8 Verse@16 Outro@24", ",SP inserts it before this section")
  eq(layout(a), "i@0+8 c@8+8 v@16+8 o@24+8", "on track A")
  eq(layout(b), "pad@4+4 pad@8+8 pad@16+8 pad@24+4", "and track B")
  eq(first_note(b, 16), "64@0", "with the verse's notes")
  paw.undo()
  paw.undo()
  eq(names(S), "Intro@0 Verse@8 Chorus@16 Outro@24", "both undone")

  -- A copy of the Intro after the Outro, chosen by name.
  paw.cursor.set_beat(25)
  keys(":section.copy Intro after=true<CR>")
  eq(names(S), "Intro@0 Verse@8 Chorus@16 Outro@24 Intro@32", "a copy inserted after the outro")
  eq(layout(a), "i@0+8 v@8+8 c@16+8 o@24+8 i@32+8", "with its clip")
  eq(layout(b), "pad@4+24 pad@36+4", "the copy holds the part of the pad that was in the intro")
end)

test("sections: commands and keys to add, rename, remove and go to", function()
  local S = song()
  paw.cursor.set_beat(28)
  keys(",SaBridge<CR>")
  eq(names(S), "Intro@0 Verse@8 Chorus@16 Outro@24 Bridge@28", ",Sa asks for a name")
  keys(",Sr<C-u>Middle 8<CR>")
  eq(S.current().name, "Middle 8", ",Sr renames the section at the cursor")
  keys(",Sx")
  eq(names(S), "Intro@0 Verse@8 Chorus@16 Outro@24", ",Sx removes the marker")
  paw.cmd("section.add", { "Solo", at = 4 })
  eq(S.at(5).name, "Solo", "section.add at=")
  paw.cmd("section.goto", { "chorus" })
  eq(paw.cursor.beat, 16, "section.goto by name")
  -- First as it is without the picker, which is put back at the end.
  local real_pick = paw.pick
  paw.pick = nil
  paw.cursor.set_beat(0)
  keys(",Ss")
  keys("Out<Tab><CR>")
  eq(paw.cursor.beat, 24, "without a picker, ,Ss asks for a name with completion")
  keys("<C-o>")
  eq(paw.cursor.beat, 0, "and <C-o> comes back")
  -- With a picker, the list goes there.
  local seen
  paw.pick = function(opts) seen = opts end
  local ok, err = pcall(function()
    keys(",Ss")
    eq(seen and seen.title, "Go to section", "the picker is used when there is one")
    eq(#seen.items, 5, "with every section")
    eq(seen.items[3].start, 8, "each with its start")
    seen.on_choose(seen.items[3])
    eq(paw.cursor.beat, 8, "choosing jumps there")
  end)
  paw.pick = nil
  if not ok then error(err, 0) end
  paw.cmd("section.list")
  local screen = table.concat(api.ui_snapshot(100, 30), "\n")
  eq(screen:find("Chorus", 1, true) ~= nil, true, "section.list shows them")
  paw.keymap.feed("q")
  paw.ui.close()
  paw.pick = real_pick
end)

test("sections: drawn on the ruler", function()
  local S = song()
  local arrange = paw.ui.views.arrange
  local lines = api.ui_snapshot(100, 30)
  -- The ruler's second row, under the bars.
  local ruler = lines[2]
  eq(lines[1]:find("Intro", 1, true), nil, "not on the row of bar numbers")
  for _, name in ipairs({ "Intro", "Verse", "Chorus" }) do
    eq(ruler:find("▍" .. name, 1, true) ~= nil, true, name .. " on the ruler: " .. ruler)
  end
  -- Scrolled past the start of the Verse, its name stays at the left.
  paw.cursor.set_beat(12)
  api.ui_snapshot(100, 30)
  arrange.scroll = 10
  ruler = api.ui_snapshot(100, 30)[2]
  eq(ruler:find("‹Verse", 1, true) ~= nil, true, "the section at the left edge keeps its name in view: " .. ruler)
  S.rename("Verse", "Hook")
  ruler = api.ui_snapshot(100, 30)[2]
  eq(ruler:find("‹Hook", 1, true) ~= nil, true, "and follows a rename")
end)

test("sections: a click on a section in the ruler's second row goes to its start, from either frontend", function()
  local S = song()
  local arrange = paw.ui.views.arrange
  api.ui_snapshot(100, 30)
  arrange.scroll = 0
  api.ui_snapshot(100, 30)
  local rect
  for _, r in ipairs(paw.ui.rects) do if r.name == "arrange" then rect = r end end
  local g = arrange.geometry
  -- Inside the Chorus, a beat after its start.
  local x = rect.x + g.hw + math.floor(17 * g.zoom)
  paw.ui.mouse({ kind = "down", x = x, y = rect.y + 1, button = "left", mods = "" })
  paw.ui.mouse({ kind = "up", x = x, y = rect.y + 1, button = "left", mods = "" })
  eq(paw.cursor.beat, 16, "a click goes to the Chorus's start")
  eq(#paw.frontend.band_state().entries, 0, "and no band of the window's repeats the ruler's row")
  S.set({})
end)

test("sections: the list in a window of its own goes to, renames and adds sections", function()
  local S = song()
  paw.canvas.open_view("sections")
  local cell = { w = 10, h = 20 }
  local painted = paw.canvas.paint("sections", 600, 200, { cell = cell, fresh = true })
  local text = {}
  for _, op in ipairs(painted.ops) do if op[1] == "m" then text[#text + 1] = op[6] end end
  text = table.concat(text, " ")
  eq(text:find("Verse", 1, true) ~= nil and text:find("Outro", 1, true) ~= nil, true, "it lists them: " .. text)
  for _, key in ipairs({ "j", "<CR>" }) do paw.canvas.key("sections", key) end
  eq(paw.cursor.beat, 8, "Enter goes to the Verse")
  eq(paw.canvas.open_views.sections ~= nil, true, "and the window stays open")
  -- A click on a row chooses it, a second goes there.
  local click = { kind = "down", x = 15, y = 2 * cell.h + 5, button = "left" }
  paw.canvas.pointer("sections", click)
  eq(paw.cursor.beat, 8, "one click chooses the Chorus")
  paw.canvas.pointer("sections", click)
  eq(paw.cursor.beat, 16, "a second goes there")
  for _, key in ipairs({ "r", "<C-u>", "H", "o", "o", "k", "<CR>" }) do paw.canvas.key("sections", key) end
  eq(names(S), "Intro@0 Verse@8 Hook@16 Outro@24", "r renames the one chosen")
  paw.cursor.set_beat(4)
  for _, key in ipairs({ "a", "P", "i", "c", "k", "<CR>" }) do paw.canvas.key("sections", key) end
  eq(names(S), "Intro@0 Pick@4 Verse@8 Hook@16 Outro@24", "a adds one at the cursor")
  paw.canvas.key("sections", "q")
  eq(paw.canvas.open_views.sections, nil, "q closes the window")
end)
