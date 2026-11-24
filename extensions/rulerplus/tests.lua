-- Tests for the rulerplus extension; run by tests/suite.lua.
local T = ...
local test, eq, after = T.test, T.eq, T.after
local paw = require("paw")
local api = paw.api

--- A part with C major for two bars, then F major for two, and the
--- extension loaded, unloaded after the test.
local function song()
  T.fresh()
  local keys = paw.add_part({ name = "Keys" })
  local notes = {}
  for i, chord in ipairs({ { "C4", "E4", "G4" }, { "F4", "A4", "C5" } }) do
    for _, pitch in ipairs(chord) do
      notes[#notes + 1] = { pitch = pitch, start = (i - 1) * 8, length = 8 }
    end
  end
  keys:add_clip({ start = 0, length = 16, notes = notes })
  paw.cursor.set_part(keys)
  paw.ext.load("extensions/rulerplus")
  after(function()
    if paw.ext.loaded.rulerplus then paw.ext.unload("rulerplus") end
    paw.opt.relativebar = false
  end)
  paw.flush()
  -- The ruler draws the chords once they are read, a moment after the edit.
  T.advance_until(function() return paw.harmony.fresh() end, "the chords to be read", 2000)
end

--- A line of the ruler (1: the bars, 2: the row `harmony`), from the
--- start of the bars.
local function ruler(n)
  local line = api.ui_snapshot(120, 24)[n or 1]
  return line:sub(line:find("│", 1, true) + #"│")
end

test("rulerplus: the chord and the key where they change, and a mark on each phrase that \\p changes", function()
  song()
  local bars, harmony, key = ruler(1), ruler(2), ruler(3)
  eq(harmony:find("^C ") ~= nil, true, "bar 1: its chord, on the row under the bars: " .. harmony)
  eq(key:find("^in C major") ~= nil, true, "and the key under it: " .. key)
  eq(harmony:find("F", 1, true), 17, "bar 3 (column 16): the chord changes, in the column of the bar: " .. harmony)
  eq(select(2, harmony:gsub("C", "")), 1, "bar 2 keeps the chord, and says nothing: " .. harmony)
  eq(bars:find("┃5", 1, true) ~= nil and bars:find("┃9", 1, true) ~= nil, true, "a phrase of 4 bars: " .. bars)
  paw.keymap.feed("\\p")
  bars = ruler()
  eq(bars:find("┃5", 1, true) == nil and bars:find("┃9", 1, true) ~= nil, true, "\\p: a phrase of 8 bars: " .. bars)
end)

test("rulerplus: with relativebar the counts have a sign, and 3W goes to the bar marked +3", function()
  song()
  paw.cursor.set_beat(paw.time.bar_start(4))
  paw.keymap.feed(":set rbar<CR>")
  local line = ruler()
  eq(line:find("-2", 1, true) ~= nil and line:find("+3", 1, true) ~= nil, true, "behind and ahead: " .. line)
  paw.keymap.feed("3W")
  eq(paw.time.bar_of(paw.cursor.beat), 7, "3W lands on the bar marked +3")
end)

test("rulerplus: :ext.unload removes its row and its marks and puts the ruler back as it was", function()
  song()
  paw.ext.unload("rulerplus")
  local before = table.concat(api.ui_snapshot(120, 24), "\n", 1, 4)
  paw.ext.load("extensions/rulerplus")
  eq(paw.ruler.rows:get("harmony") ~= nil and paw.marks.namespaces:get("rulerplus.phrase") ~= nil, true, "loaded")
  eq(table.concat(paw.opt.rulerrows, ","), "bars,harmony,beats,regions,tempo", "its row after the bars")
  paw.keymap.feed(":ext.unload rulerplus<CR>")
  eq(paw.ruler.rows:get("harmony"), nil, "the row goes")
  eq(paw.marks.namespaces:get("rulerplus.phrase"), nil, "the namespace goes")
  eq(table.concat(paw.opt.rulerrows, ","), "bars,beats,regions,tempo", "paw.opt.rulerrows")
  eq(table.concat(api.ui_snapshot(120, 24), "\n", 1, 4), before, "the ruler")
end)

test("rulerplus: the user's route of its marks stays after :ext.unload", function()
  song()
  after(function() paw.ruler.route("rulerplus.phrase", nil) end)
  paw.ruler.route("rulerplus.phrase", "row:regions")
  paw.keymap.feed(":ext.unload rulerplus<CR>")
  eq(paw.marks.namespaces:get("rulerplus.phrase"), nil, "the namespace goes")
  eq(paw.ruler.routes["rulerplus.phrase"], "row:regions", "the route stays")
  paw.ext.load("extensions/rulerplus")
  eq(paw.ruler.routes["rulerplus.phrase"], "row:regions", "and sends the marks again")
end)
