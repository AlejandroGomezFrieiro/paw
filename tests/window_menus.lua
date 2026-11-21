-- Tests of the window's menus (paw/window_menus.tl): built in the kernel,
-- shown by the window, an entry chosen by its place. Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

local function find(items, label)
  for i, item in ipairs(items) do
    if item.label == label then return i, item end
  end
end

test("a clip's menu in the window is the terminal's, and an entry chosen does what it says", function()
  fresh()
  local t = paw.add_track({ name = "A" })
  local clip = t:add_clip({ start = 4, length = 4, name = "c", notes = { { pitch = 60, start = 0, length = 1 } } })
  local items = paw.frontend.menu("clip", { clip.id, 5 })
  local at, mute = find(items, "Mute")
  assert(mute and mute.enabled, "Mute is offered")
  local stretch_at, stretch = find(items, "Stretch and loop")
  assert(stretch.items and not stretch.items[1].enabled, "stretching is for audio clips: greyed on MIDI")
  paw.frontend.act.menu_choose("clip", { clip.id, 5 }, { at })
  eq(api.clip_get(clip.id).muted, true)
  -- A submenu's entry, by its place in each menu.
  local loop_at = #stretch.items
  paw.frontend.act.menu_choose("clip", { clip.id, 5 }, { stretch_at, loop_at })
  eq(api.clip_get(clip.id).loop, true)
  assert(items[#items - 1].separator, "separators are told as such")
end)

test("the window's own menus say what the window does itself", function()
  fresh()
  local file = paw.frontend.menu("file", {})
  local _, quit = find(file, "Quit")
  eq(quit.window, "quit")
  local _, recent = find(file, "Open recent")
  eq(recent.items[#recent.items].label, "Clear the list")
  -- "+ Track" makes one; an entry the window does is not run here.
  local before = #api.track_list()
  local add = paw.frontend.menu("add_track", {})
  eq(add[2].window, "import")
  paw.frontend.act.menu_choose("add_track", {}, { 1 })
  eq(#api.track_list(), before + 1)
  paw.frontend.act.menu_choose("add_track", {}, { 2 })
  eq(#api.track_list(), before + 1)
end)

test("a track's output menu routes it, and its header menu offers a VCA", function()
  fresh()
  local a = paw.add_track({ name = "A" })
  local bus = paw.add_track({ name = "Bus" })
  local items = paw.frontend.menu("output", { a.id })
  local _, master = find(items, "Master")
  eq(master.checked, true)
  local bus_at = find(items, "Bus")
  paw.frontend.act.menu_choose("output", { a.id }, { bus_at })
  eq(api.track_get(a.id).output, bus.id)
  assert(find(paw.frontend.menu("track", { a.id }), "New VCA with this track…"), "the VCA entries")
end)
