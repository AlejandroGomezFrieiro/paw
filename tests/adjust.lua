-- Tests of adjusting the last command (`:adjust`, `<leader>.`): the command
-- runs again in place of its undo step. Loaded by tests/suite.lua with its
-- helpers.
local T = ...
local test, eq, near, keys = T.test, T.eq, T.near, T.keys
local api = paw.api

--- Track T with clips a, b, c (a note on each beat); the roll is open on clip b
--- and the notes of b are off the grid: 60 at 0.1, 61 at 1.3, 62 at 2, 63 at 3.
local function song()
  local t = T.three_clips()
  T.after(function()
    paw.keymap.feed("<Esc><Esc>")
    paw.ui.views.pianoroll.clip_id = nil
    paw.ui.hide("pianoroll")
    paw.ui.focus("arrange")
  end)
  local b = t:clips()[2]
  b:set_note(1, { start = 0.1 })
  b:set_note(2, { start = 1.3 })
  api.undo_checkpoint()
  paw.cursor.set_track(t)
  paw.cursor.set_beat(4)
  keys("<CR>")
  eq(paw.ui.focused, "pianoroll", "the roll is open on clip b")
  return t, b
end

local function starts(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do
    out[#out + 1] = n.start
  end
  table.sort(out)
  return out
end

local function pitches(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do
    out[#out + 1] = n.pitch
  end
  table.sort(out)
  return table.concat(out, " ")
end

local function states() return #api.undo_tree().states end

local function last_message() return paw.ui.messages[#paw.ui.messages].text end

test("adjust: <leader>. changes the grid of :quantize in place of its undo step", function()
  local _, b = song()
  local before = states()
  keys(":%quantize 1/16<CR>")
  near(starts(b)[2], 1.25, 1e-9, "snapped to 1/16")
  eq(states(), before + 1, ":quantize is one step")
  keys("<Space>.")
  eq(
    require("paw.views.cmdline").state().before,
    "adjust grid=1/16 strength=100",
    "the command line holds the parameters"
  )
  keys(" grid=1/8<CR>")
  near(starts(b)[2], 1.5, 1e-9, "snapped to 1/8")
  eq(states(), before + 1, "the new state took the place of the old one")
  keys("u")
  near(starts(b)[2], 1.3, 1e-9, "u returns to the notes before :quantize")
  eq(starts(b)[1], 0.1, "all of them")
end)

test("adjust: strength moves each note part of the way, and . repeats the adjusted command", function()
  local _, b = song()
  keys(":%quantize 1/16 strength=100<CR>")
  keys(":adjust strength=50<CR>")
  near(starts(b)[2], 1.275, 1e-9, "half of the way to 1.25")
  near(starts(b)[1], 0.05, 1e-9, "half of the way to 0")
  keys("u")
  b:set_note(3, { start = 2.3 })
  api.undo_checkpoint()
  keys(".")
  near(starts(b)[3], 2.275, 1e-9, ". repeats it with the adjusted strength")
end)

test("adjust: :transpose takes new semitones, in one undo step", function()
  local _, b = song()
  local before = states()
  keys(":%transpose 12<CR>")
  eq(pitches(b), "72 73 74 75", "an octave up")
  keys(":adjust 7<CR>")
  eq(pitches(b), "67 68 69 70", "seven semitones above the first ones")
  eq(states(), before + 1, "one step")
  keys("u")
  eq(pitches(b), "60 61 62 63", "u returns to the start")
end)

test("adjust: it says why when there is nothing to adjust", function()
  local _, b = song()
  keys(":%d<CR>")
  eq(#b:notes(), 0, "the notes are gone")
  local before = states()
  keys(":adjust 7<CR>")
  eq(last_message():find("has nothing to adjust", 1, true) ~= nil, true, last_message())
  eq(states(), before, "and nothing changed")
  keys("u:%quantize 1/16<CR>u")
  keys(":adjust grid=1/8<CR>")
  eq(last_message(), "adjust works on the last change", "after u")
  near(starts(b)[2], 1.3, 1e-9, "nothing changed")
end)
