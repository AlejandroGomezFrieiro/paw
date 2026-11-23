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
    paw.ui.views:get("pianoroll").clip_id = nil
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
  keys("<Space>.:")
  eq(
    require("paw.views.cmdline").state().before,
    "adjust grid=1/16 strength=100",
    "the command line holds the parameters"
  )
  keys(" grid=1/8<CR>")
  near(starts(b)[2], 1.5, 1e-9, "snapped to 1/8")
  eq(states(), before + 1, "the new state took the place of the old one")
  keys("<Esc>u")
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

--- The panel's rows, as text.
local function panel_rows()
  local snap = api.ui_view_snapshot("adjust", 56, 6)
  local out = {}
  for _, row in ipairs(snap.rows) do
    local text = ""
    for _, cell in ipairs(row) do
      text = text .. cell.text
    end
    out[#out + 1] = text
  end
  return out
end

test("adjust panel: j and - change the strength live, in one undo step", function()
  local _, b = song()
  local before = states()
  keys(":%quantize 1/16 strength=100<CR>")
  keys("<Space>.")
  eq(paw.ui.focused, "adjust", "the panel is open")
  eq(paw.ui.float.title, "Quantize · 4 notes", "it says the command and its range")
  keys("j--")
  eq(panel_rows()[2]:find("strength%s+90") ~= nil, true, "the panel shows 90 at once: " .. panel_rows()[2])
  T.until_(function() return paw.commands.adjusting() == "adjust grid=1/16 strength=90" end, "the command to run")
  near(starts(b)[2], 1.3 + (1.25 - 1.3) * 0.9, 1e-9, "the notes moved 90% of the way")
  eq(states(), before + 1, "one undo step for all of it")
  keys("<Esc>")
  eq(paw.ui.focused ~= "adjust", true, "Esc closes the panel")
  near(starts(b)[2], 1.255, 1e-9, "and keeps the result")
  keys("u")
  near(starts(b)[2], 1.3, 1e-9, "u returns to the notes before :quantize")
  eq(starts(b)[1], 0.1, "all of them")
end)

test("adjust panel: a count multiplies the step, and keys that come quickly run the command once", function()
  song()
  keys(":%quantize 1/16 strength=100<CR>")
  local runs = 0
  local id = paw.on("command.post", function(e)
    if e.name == "quantize" then runs = runs + 1 end
  end)
  keys("<Space>.j-----")
  keys("2-")
  eq(runs, 0, "nothing runs while the keys come")
  T.until_(function() return runs > 0 end, "the command to run after the settle")
  T.until_(function() return paw.commands.adjusting() == "adjust grid=1/16 strength=65" end, "the last value")
  eq(runs, 1, "the command ran once")
  paw.off(id)
  keys("<Esc>")
end)

test("adjust panel: Esc at once keeps the change that waits", function()
  local _, b = song()
  keys(":%quantize 1/16 strength=100<CR><Space>.j-<Esc>")
  eq(paw.commands.adjusting(), "adjust grid=1/16 strength=95", "run before the panel closed")
  keys("u")
  near(starts(b)[2], 1.3, 1e-9, "u undoes the whole command")
end)
