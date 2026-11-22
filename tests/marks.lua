-- Taking marks and markers away: `:delmarks`, and removing the marker at the
-- cursor by key or by the pointer. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
  paw.add_track({ name = "Bass" })
  paw.keymap.delmarks("a-zA-Z")
end

local function set(names)
  for name in names:gmatch(".") do
    paw.keymap.feed("m" .. name)
  end
end

local function held()
  local out = {}
  for name in pairs(paw.keymap.marks("arrange")) do
    out[#out + 1] = name
  end
  table.sort(out)
  return table.concat(out)
end

test("marks: :delmarks takes away letters, ranges and all lowercase ones", function()
  start()
  set("abcdeX")
  paw.keymap.feed(":delmarks b<CR>")
  eq(held(), "Xacde", "one letter")
  paw.keymap.feed(":delm c-d<CR>")
  eq(held(), "Xae", "a range, by the short name")
  paw.keymap.feed(":delmarks a e<CR>")
  eq(held(), "X", "several letters")
  set("pq")
  paw.keymap.feed(":delmarks!<CR>")
  eq(held(), "X", "the bang removes every lowercase mark and keeps the capital")
  paw.keymap.feed(":delmarks X<CR>")
  eq(held(), "", "a capital by name")
end)

test("marks: :delmarks says what is wrong and completes the marks that exist", function()
  start()
  set("mk")
  eq(paw.keymap.delmarks("9"), nil, "a digit is not a mark")
  eq(select(2, paw.keymap.delmarks("d-a")) ~= nil, true, "a backwards range is refused")
  eq(paw.keymap.delmarks("z"), 0, "an unset mark is nothing to remove")
  eq(held(), "km", "nothing was removed by those")
  local names = {}
  for _, c in ipairs(paw.commands.complete("delmarks ")) do
    names[#names + 1] = c.label
  end
  eq(table.concat(names, ","), "k,m", "completion lists the marks that are set")
end)

test("marks: gx removes the marker at the cursor", function()
  start()
  paw.markers.add(8, "Verse")
  paw.markers.add(24, "Chorus")
  paw.cursor.set_beat(8)
  paw.keymap.feed("gx")
  eq(#paw.markers.list() .. paw.markers.list()[1].name, "1Chorus", "gx took the marker under the cursor")
  paw.cursor.set_beat(0)
  paw.keymap.feed("gx")
  eq(#paw.markers.list(), 1, "and does nothing where there is none")
end)

test("marks: gx keeps regions and gX removes the region the cursor is in, not its clips", function()
  start()
  local bass = paw.tracks()[1]
  bass:add_clip({ start = 4, length = 4 })
  paw.markers.add(4, "Verse", { length = 8 })
  paw.markers.add(6, "Hit")
  paw.cursor.set_beat(4)
  paw.keymap.feed("gx")
  eq(#paw.markers.list(), 2, "gx on a region's start removes no region")
  paw.cursor.set_beat(6)
  paw.keymap.feed("gx")
  eq(paw.markers.find("Hit"), nil, "gx removes the marker")
  paw.cursor.set_beat(9)
  paw.keymap.feed("gX")
  eq(#paw.markers.list(), 0, "gX removes the region from inside it")
  eq(#bass:clips(), 1, "and its clip stays")
end)

test("marks: dir empties a region on the track, dar on every track, and the region stays", function()
  start()
  local bass = paw.tracks()[1]
  local keys = paw.add_track({ name = "Keys" })
  for _, t in ipairs({ bass, keys }) do
    t:add_clip({ start = 0, length = 4 })
    t:add_clip({ start = 4, length = 4 })
    t:add_clip({ start = 8, length = 4 })
  end
  paw.markers.add(4, "Verse", { length = 4 })
  paw.cursor.set_track(bass)
  paw.cursor.set_beat(5)
  paw.keymap.feed("dir")
  eq(#bass:clips() .. " " .. #keys:clips(), "2 3", "dir takes the region's clip on this track only")
  paw.keymap.feed("dar")
  eq(#bass:clips() .. " " .. #keys:clips(), "2 2", "dar takes it on every track")
  eq(paw.markers.region("Verse") ~= nil, true, "and the region stays")
end)
