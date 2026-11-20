-- How long notation takes on a big clip. Loaded by tests/suite.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api

test("notation: a clip of ten thousand notes opens and is drawn in well under a second", function()
  fresh()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  local view = require("notation")
  local notes = require("notation.bench").notes(690)
  eq(#notes > 10000, true, "ten thousand notes: " .. #notes)
  local track = paw.add_track({ name = "Big" })
  local clip = track:add_clip({ start = 0, length = 690 * 4, name = "big", notes = notes })
  paw.flush()
  api.undo_checkpoint()
  paw.ui.focus("arrange")
  paw.cursor.set_track(track)
  paw.cursor.beat = 0
  api.ui_snapshot(150, 45)
  collectgarbage()
  local t = api.now()
  paw.keymap.feed(":notation<CR>")
  local text = table.concat(api.ui_snapshot(150, 45), "\n")
  local took = api.now() - t
  eq(view.clip_id, clip.id, "the clip is open")
  eq(paw.ui.focused, "notation", "and has the keyboard")
  eq(text:find("big", 1, true) ~= nil, true, "and is drawn, named")
  -- The target is 200 ms; the bound is loose, for a busy machine.
  eq(took < 1000, true, string.format("opened and drawn in %.0f ms", took))
  -- The cursor moves at once, the events sorted once for the layout.
  t = api.now()
  for _ = 1, 20 do paw.keymap.feed("l") end
  api.ui_snapshot(150, 45)
  took = api.now() - t
  eq(view.beat > 0, true, "the cursor moved")
  eq(took < 1000, true, string.format("twenty moves and a draw in %.0f ms", took))
  paw.ui.focus("arrange")
end)
