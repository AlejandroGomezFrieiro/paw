-- Tests of `K`: what is under the cursor, in a float next to it that
-- leaves the keys where they are (paw.ui.hover), and of `:info`, which says
-- all of it in a page. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq = T.test, T.eq
local api = paw.api
local keys = T.keys

-- The golden screens: 100 by 30, without the status line and the
-- command line, whose processor load changes from run to run.
local W, H = 100, 30
local SCREEN = { rows = { 1, 28 }, styles = false }

--- The song of the screens of the design: Drums (Kick, Snare) and Keys
--- (Piano, Pad) as groups, and Bass; the regions Intro, Verse and Chorus,
--- 8 bars each; a clip of 24 bars on each part. Seven parts.
local function song()
  T.start()
  api.engine_restart({})
  paw.opt.zoom, paw.opt.grid = 1, 4
  local parts = {}
  for i, name in ipairs({ "Kick", "Snare", "Piano", "Pad", "Bass" }) do
    local t = paw.add_part({ name = name })
    local notes = {}
    for beat = 0, 92, 4 do
      notes[#notes + 1] = { pitch = 45 + i * 3, start = beat, length = 2 }
    end
    t:add_clip({ name = name, start = 0, length = 96, notes = notes })
    parts[name] = t
  end
  paw.groups.make({ parts.Kick, parts.Snare }, "Drums")
  paw.groups.make({ parts.Piano, parts.Pad }, "Keys")
  paw.markers.add(0, "Intro", { length = 32 })
  paw.markers.add(32, "Verse", { length = 32 })
  paw.markers.add(64, "Chorus", { length = 32 })
  paw.flush()
  api.undo_checkpoint()
  paw.ui.views:get("arrange").scroll = 0
  paw.cursor.set_part(parts.Kick)
  paw.cursor.set_beat(0)
  return parts
end

--- The screen at the size of the golden screens, as text.
local function screen(h) return table.concat(api.ui_snapshot(W, h or H), "\n") end

test("K opens a float under the cursor, as wide as its text, and the song stays in view", function()
  local t = song()
  paw.cursor.set_part(t.Piano)
  keys("9|")
  screen()
  keys("K")
  eq(paw.ui.hovered and paw.ui.hovered.title, "Clip  Piano", "the clip's title on the border")
  eq(paw.ui.focused, "arrange", "the keys stay in the song")
  T.expect_screen("clip", W, H, SCREEN)
end)

test("the next key closes the float of K and does what it does", function()
  local t = song()
  paw.cursor.set_part(t.Piano)
  screen()
  keys("Kj")
  eq(paw.ui.hovered, nil, "j closes the float")
  eq(paw.cursor.part_id(), t.Pad.id, "and goes down a part")
end)

test("K again goes into the float, where j and k scroll and Esc closes it", function()
  local t = song()
  paw.cursor.set_part(t.Piano)
  keys("9|")
  screen()
  keys("KK")
  eq(paw.ui.focused, "pager", "the keys are in the float")
  T.expect_screen("clip_entered", W, H, SCREEN)
  keys("<Esc>")
  eq({ paw.ui.float == nil, paw.ui.focused }, { true, "arrange" }, "Esc closes it, the keys are in the song again")
end)

test("the float of K is at most half the window high; its last row says that K again shows all of it", function()
  local t = song()
  paw.cursor.set_part(t.Piano)
  screen(20)
  keys("K")
  local text = screen(20)
  eq(text:find("K again: all of it", 1, true) ~= nil, true, text)
  eq(text:find("output  Keys", 1, true), nil, "the lines after it wait for K again:\n" .. text)
end)

test(":info shows all of it in a page", function()
  local t = song()
  paw.cursor.set_part(t.Piano)
  keys(":info<CR>")
  eq(paw.ui.float and paw.ui.float.title, "Under the cursor", "a page")
  eq(paw.ui.hovered, nil, "not the float of K")
end)

test("K on a closed fold says what it holds and its keys, over the cursor when there is no room under it", function()
  local t = song()
  paw.cursor.set_part(t.Piano)
  keys("9|<C-v>j16lzf")
  screen()
  keys("K")
  T.expect_screen("fold", W, H, SCREEN)
end)

test("K on a block of a subproject says subproject, its parts and the places where it plays", function()
  local t = song()
  paw.cursor.set_part(t.Bass)
  keys("9|:nest.new Bridge 8<CR>:part.add Organ<CR>zw")
  local row = paw.part("Bridge")
  local block = api.clip_list(row.id)[1]
  api.clip_add(row.id, { nest = block.nest, start = 96 })
  paw.flush()
  api.undo_checkpoint()
  paw.cursor.set_part(row)
  keys("9|")
  screen()
  keys("K")
  eq(paw.ui.hovered.title, "⧉ Bridge", "the block's mark and name")
  T.expect_screen("block", W, H, SCREEN)
end)
