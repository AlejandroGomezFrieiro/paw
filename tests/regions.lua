-- Nested regions (paw/markers.tl): a region inside another's time is its
-- child. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh, keys = T.test, T.eq, T.fresh, T.keys
local api = paw.api

local function said() return paw.ui.message and paw.ui.message.text or "" end

local function start()
  fresh()
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
end

--- Intro (bars 1-4), Chorus 2 (5-12) with Verse A (5-8) and Verse B
--- (9-12), Outro (13-16), and a marker Hit in Verse B. 4/4: a bar is 4 beats.
local function song()
  local m = paw.markers
  local r = {
    intro = m.add(0, "Intro", { length = 16 }),
    verse_a = m.add(16, "Verse A", { length = 16 }),
    chorus = m.add(16, "Chorus 2", { length = 32 }),
    verse_b = m.add(32, "Verse B", { length = 16 }),
    outro = m.add(48, "Outro", { length = 16 }),
    hit = m.add(40, "Hit"),
  }
  api.undo_checkpoint()
  return r
end

local function starts(...)
  local out = {}
  for i, name in ipairs({ ... }) do
    out[i] = tostring(paw.markers.find(name).beat)
  end
  return table.concat(out, " ")
end

test("regions nest by time: 2ar takes the region around, ]r and [r keep the level, the list is a tree", function()
  start()
  local r = song()
  eq(#paw.markers.tree(), 3, "three regions at the top")
  eq(paw.markers.parent(r.verse_a.id).name, "Chorus 2", "the region made first still goes inside the larger one")
  eq(paw.markers.parent(r.hit.id).name, "Verse B", "a marker belongs to the innermost region")
  local bass = paw.add_part({ name = "Bass" })
  bass:add_clip({ start = 16, length = 4 })
  bass:add_clip({ start = 36, length = 4 })
  paw.cursor.set_part(bass)
  api.undo_checkpoint()
  paw.cursor.set_beat(17)
  keys("dar")
  eq(#bass:clips(), 1, "dar: the innermost region, Verse A")
  keys("u")
  keys("d2ar")
  eq(#bass:clips(), 0, "d2ar: the region around it, Chorus 2")
  keys("u")
  keys("]r")
  eq(paw.cursor.beat, 32, "]r from Verse A: Verse B, at the same level")
  keys("[r")
  eq(paw.cursor.beat, 16, "[r: Verse A again")
  paw.cursor.set_beat(4)
  keys("2]r")
  eq(paw.cursor.beat, 48, "2]r from the Intro: the Outro, two regions on at the top level")
  keys('g"')
  local text = table.concat(api.ui_snapshot(160, 48), "\n")
  eq(
    text:find("region  Chorus 2", 1, true) ~= nil and text:find("region    Verse A", 1, true) ~= nil,
    true,
    "the list indents a region under the one around it:\n" .. text
  )
end)

test("regions that overlap without nesting are siblings, and ar takes the one that starts later", function()
  start()
  paw.markers.add(0, "Intro", { length = 36 })
  local pre = paw.markers.add(24, "Pre", { length = 24 })
  eq(paw.markers.parent(pre.id), nil, "Pre is not inside the Intro")
  eq(paw.markers.around(30).name, "Pre", "where both are, the later one")
end)

test(
  "moving a region takes the regions and markers inside it, in one undo step; region.move! moves it alone",
  function()
    start()
    song()
    keys(":region.move Chorus 2 +2<CR>")
    eq(starts("Chorus 2", "Verse A", "Verse B", "Hit", "Intro"), "24 24 40 48 0", "two bars later, with what is inside")
    keys("u")
    eq(starts("Chorus 2", "Verse A", "Verse B", "Hit"), "16 16 32 40", "one undo step puts them all back")
    keys(":region.move! Chorus 2 +2<CR>")
    eq(starts("Chorus 2", "Verse A", "Verse B"), "24 16 32", "the bang moves the region alone")
  end
)

test("a region made shorter says which regions are no longer inside it", function()
  start()
  local r = song()
  keys(":marker.set id=" .. r.chorus.id .. " length=24<CR>")
  eq(said(), "Verse B is no longer inside Chorus 2", "the message")
  eq(paw.markers.parent(r.verse_b.id), nil, "it is at the top level now")
end)

test(":region.remove moves the regions inside up a level; :region.remove! removes them too", function()
  start()
  local r = song()
  keys(":region.remove Chorus 2<CR>")
  eq(paw.markers.depth(r.verse_a.id), 1, "Verse A is at the top level")
  keys("u")
  keys(":region.remove! Chorus 2<CR>")
  eq(
    #paw.markers.regions() .. " " .. tostring(paw.markers.find("Hit") ~= nil),
    "2 true",
    "Intro and Outro stay, and the marker"
  )
end)

test(":export regions names each file by its path, and level= chooses the regions", function()
  start()
  T.tone("tone", 64)
  paw.project.tempo = 480
  song()
  paw.markers.add(48, "Verse A", { length = 8 })
  eq(paw.markers.region("Outro/Verse A").beat, 48, "a path of names finds a region when names repeat")
  local function planned(level)
    local out = {}
    for i, r in ipairs(paw.export.plan("regions level=" .. level).renders) do
      out[i] = r.file:match("[^/]+$")
    end
    return table.concat(out, ", ")
  end
  eq(
    planned("leaves"),
    "01 Intro.wav, 02 Chorus 2 - Verse A.wav, 03 Chorus 2 - Verse B.wav, 04 Outro - Verse A.wav",
    "the regions with none inside, named by their path"
  )
  eq(planned(1), "01 Intro.wav, 02 Chorus 2.wav, 03 Outro.wav", "level=1: the top level")
end)

test("a region scope's children are its regions inside, and :narrow takes the one of that name inside", function()
  start()
  song()
  paw.markers.add(64, "Chorus 3", { length = 16 })
  local verse = paw.markers.add(64, "Verse A", { length = 8 })
  paw.add_part({ name = "Bass" })
  keys(":narrow Chorus 3<CR>")
  local names = {}
  for i, s in ipairs(paw.scope.children()) do
    names[i] = s.name
  end
  eq(table.concat(names, ", "), "Verse A", "the regions one level inside")
  keys(":narrow Verse A<CR>")
  eq(
    paw.scope.current().id .. " " .. paw.scope.breadcrumb(),
    verse.id .. " Song › Chorus 3 › Verse A",
    "the Verse A of Chorus 3"
  )
  keys(":widen!<CR>")
end)

--- How many times paw made the tree of regions.
local function trees_made()
  for _, s in ipairs(require("paw.derived").stats()) do
    if s.name == "markers.tree" then return s.made end
  end
end

test("the tree of regions is made again after a change of a region, not after an edit of a note", function()
  start()
  song()
  local clip = paw.add_part({ name = "Bass" }):add_clip({ start = 0, length = 4 })
  api.undo_checkpoint()
  eq(#paw.markers.tree(), 3, "three regions at the top")
  local made = trees_made()
  clip:add_note({ pitch = 40, start = 0, length = 1 })
  api.undo_checkpoint()
  -- The events of the edit come, as at the end of a key.
  paw.flush()
  eq(#paw.markers.tree(), 3, "the same tree after a note edit")
  eq(trees_made(), made, "a note edit does not make the tree again")
  paw.markers.add(64, "Coda", { length = 16 })
  api.undo_checkpoint()
  eq(#paw.markers.tree(), 4, "a new region is in the tree")
  eq(trees_made(), made + 1, "made again once")
  keys("u")
  eq(#paw.markers.tree(), 3, "u takes the region away")
  eq(trees_made(), made + 1, "u gives back the tree of before without a make")
end)
