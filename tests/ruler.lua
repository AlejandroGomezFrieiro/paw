-- The ruler of the arrange view, as a musician reads it: the test project
-- ruler-everything (tests/fixtures/ruler_everything.lua) has each row and
-- mark that paw and its bundled extensions put on the ruler. Its golden
-- screens show the ruler at three zoom levels and in a narrow window.
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test = T.test
local everything = dofile("tests/fixtures/ruler_everything.lua")

--- The ruler and the first part rows, with a time selection made with the keys.
local function screen(name, w)
  T.keys("v4l")
  T.settle()
  T.expect_screen(name, w, 18, { rows = { 1, 13 } })
  T.keys("<Esc>")
end

test("ruler-everything: every row and mark of the ruler at three zoom levels and in a narrow window", function()
  everything(T)
  screen("zoom_1", 120)
  paw.opt.zoom = 2
  screen("zoom_2", 120)
  paw.opt.zoom = 0.5
  screen("zoom_half", 120)
  paw.opt.zoom = 1
  screen("narrow", 64)
end)

test("K on a column of the ruler lists every mark there, with the labels that have no room", function()
  local song = everything(T)
  -- At zoom 1/2 the tempo's value at beat 12 has no room before the phrase
  -- mark of bar 5. The bass has no clip there.
  paw.opt.zoom = 0.5
  paw.cursor.set_part(song.bass.id)
  paw.cursor.set_beat(12)
  T.settle()
  T.screen(120, 18)
  T.keys("K")
  local text = T.hover_text()
  T.eq(text:find("Ruler  column 6", 1, true) ~= nil, true, "the column of the cursor:\n" .. text)
  T.eq(
    text:find("▾ tempo 90  (no room for 90)", 1, true) ~= nil,
    true,
    "the tempo, with its value that is not shown:\n" .. text
  )
  T.eq(text:find("mk", 1, true) ~= nil, true, "the marker there:\n" .. text)
  T.keys("<Esc>")
end)

test("ruler-everything: inside a subproject, the bars of the scope over the song's", function()
  everything(T)
  -- Back to the song, which the next test does not leave by itself.
  T.after(function() paw.keymap.feed("<Esc>zw") end)
  T.keys(":narrow Verse<CR>")
  T.keys(":scope.write! Bridge<CR>")
  T.settle()
  T.expect_screen("subproject", 100, 18, { rows = { 1, 13 } })
end)
