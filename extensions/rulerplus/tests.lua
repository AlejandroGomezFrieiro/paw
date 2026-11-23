-- Tests for the rulerplus extension; run by tests/suite.lua.
local T = ...
local test, eq, after = T.test, T.eq, T.after
local paw = require("paw")
local api = paw.api

--- A track with C major for two bars, then F major for two, and the
--- extension loaded, unloaded after the test.
local function song()
  T.fresh()
  local keys = paw.add_track({ name = "Keys" })
  local notes = {}
  for i, chord in ipairs({ { "C4", "E4", "G4" }, { "F4", "A4", "C5" } }) do
    for _, pitch in ipairs(chord) do
      notes[#notes + 1] = { pitch = pitch, start = (i - 1) * 8, length = 8 }
    end
  end
  keys:add_clip({ start = 0, length = 16, notes = notes })
  paw.cursor.set_track(keys)
  paw.ext.load("extensions/rulerplus")
  after(function()
    if paw.ext.loaded.rulerplus then paw.ext.unload("rulerplus") end
    paw.opt.relativebar = false
  end)
  paw.flush()
  -- The ruler draws the chords once they are read, a moment after the edit.
  T.advance_until(function() return paw.harmony.fresh() end, "the chords to be read", 2000)
end

--- The ruler's line, from the start of the bars.
local function ruler()
  local line = api.ui_snapshot(120, 24)[1]
  return line:sub(line:find("│", 1, true) + #"│")
end

test("rulerplus: the chord and the key where they change, and a mark on each phrase that \\p changes", function()
  song()
  local line = ruler()
  eq(line:find(" C (C) 2", 1, true) ~= nil, true, "bar 1: its chord and the key, the number under the corner: " .. line)
  eq(line:find("3 F", 1, true) ~= nil, true, "bar 3: the chord changes: " .. line)
  eq(line:find("2 C", 1, true), nil, "bar 2 keeps the chord, and says nothing: " .. line)
  eq(line:find("┃5", 1, true) ~= nil and line:find("┃9", 1, true) ~= nil, true, "a phrase of 4 bars: " .. line)
  paw.keymap.feed("\\p")
  line = ruler()
  eq(line:find("┃5", 1, true) == nil and line:find("┃9", 1, true) ~= nil, true, "\\p: a phrase of 8 bars: " .. line)
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

test("rulerplus: :ext.unload puts the bar labels back as they were", function()
  T.fresh()
  local labels = {}
  for k, v in pairs(paw.ruler.labels:entries()) do
    labels[k] = v
  end
  local shown = table.concat(paw.opt.barlabel, ",")
  local before = ruler()
  paw.ext.load("extensions/rulerplus")
  paw.keymap.feed(":ext.unload rulerplus<CR>")
  for k, v in pairs(labels) do
    eq(paw.ruler.labels:get(k), v, "the part " .. k)
  end
  for k in pairs(paw.ruler.labels:entries()) do
    eq(labels[k] ~= nil, true, "no part left: " .. k)
  end
  eq(table.concat(paw.opt.barlabel, ","), shown, "paw.opt.barlabel")
  eq(ruler(), before, "the ruler")
end)
