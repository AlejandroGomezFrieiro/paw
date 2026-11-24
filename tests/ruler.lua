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

test("paw.marks: del, clear and get keep the marks of a namespace in the order of their beats", function()
  T.fresh()
  local ns = paw.marks.namespace("test.todo", {})
  T.after(function() paw.marks.namespaces:remove("test.todo") end)
  paw.marks.set(ns, 32, { label = "late" })
  local early = paw.marks.set(ns, 4, { label = "early" })
  local middle = paw.marks.set("test.todo", 16, { label = "middle" })
  local function labels()
    local out = {}
    for _, m in ipairs(paw.marks.get(ns)) do
      out[#out + 1] = m.label
    end
    return table.concat(out, ",")
  end
  T.eq(labels(), "early,middle,late", "get: by beat")
  paw.marks.set(ns, 40, { id = early, label = "early" })
  T.eq(labels(), "middle,late,early", "set with an id moves the mark")
  T.eq(paw.marks.del(ns, middle), true, "del: the mark was there")
  T.eq(paw.marks.del(ns, middle), false, "del: it is gone")
  T.eq(labels(), "late,early", "del")
  paw.marks.clear(ns, 30, 40)
  T.eq(labels(), "early", "clear from 30 up to 40 keeps beat 40")
  paw.marks.set(ns, 8, { label = "again" })
  paw.marks.clear(ns)
  T.eq(labels(), "", "clear with no time")
end)

test("paw.ruler.route: a route that is not row: or over: gives a clear message", function()
  local ok, err = pcall(paw.ruler.route, "paw.cues", 5)
  T.eq(ok, false, "refused")
  T.eq(tostring(err):find('a route is "row:<row>" or "over:<row>", not 5', 1, true) ~= nil, true, tostring(err))
end)
