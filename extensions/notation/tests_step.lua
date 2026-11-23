-- Tests of step input in notation (notation/step.tl): a MIDI controller
-- enters notes in the insert modes `i`, `I` and `R`. Keys are sent with
-- paw.midi.inject from a test port of the null backend. Loaded by tests/suite.lua.
local T = ...
local test, eq, fresh, keys = T.test, T.eq, T.fresh, T.keys
local paw = require("paw")
local api = paw.api

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation")
end

--- A part with a clip open as notation, quarter notes, `typed` entered from bar 1.
local function song(typed)
  fresh()
  local view = load()
  api.midi_test_ports({ "Test Keys" })
  local part = paw.add_part({ name = "Lead" })
  part:add_device("synth")
  local clip = part:add_clip({ start = 0, length = 8, name = "tune", notes = {} })
  paw.flush()
  api.undo_checkpoint()
  paw.keymap.set_mode("n")
  view:edit(clip)
  view.value, view.dot, view.voice, view.triplets, view.tuplet = 1, false, 1, false, nil
  view:set(35, 0)
  if typed then
    keys("i" .. typed .. "<Esc>")
    api.undo_checkpoint()
  end
  paw.step.use()
  return view, clip
end

local function down(pitch) paw.midi.inject({ type = "note_on", pitch = pitch, velocity = 100, port = "Test Keys" }) end
local function up(pitch) paw.midi.inject({ type = "note_off", pitch = pitch, port = "Test Keys" }) end
local function play(pitch)
  down(pitch)
  up(pitch)
  paw.flush()
end
local function pedal(pressed)
  paw.midi.inject({ type = "cc", number = 64, value = pressed and 1 or 0, port = "Test Keys" })
  paw.flush()
end

--- The notes as "pitch@start+length", in time order.
local function written(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do
    out[#out + 1] = string.format("%d@%g+%g", n.pitch, n.start, n.length)
  end
  table.sort(out, function(a, b) return tonumber(a:match("@([%d.]+)")) < tonumber(b:match("@([%d.]+)")) end)
  return table.concat(out, " ")
end

local function done(fn)
  return function()
    local ok, err = xpcall(fn, debug.traceback)
    paw.keymap.set_mode("n")
    api.midi_test_ports({})
    paw.harmony.set_key(nil)
    if not ok then error(err, 0) end
  end
end

test(
  "notation step input: i, a chord held, the next key, Esc, and u takes back the whole insert",
  done(function()
    local view, clip = song()
    keys("i")
    eq(paw.step.active(), "notation", "the insert mode listens")
    down(60)
    down(64)
    down(67)
    up(60)
    up(64)
    up(67)
    paw.flush()
    eq(view.beat, 1, "the caret steps on after the last release")
    play(62)
    eq(view.beat, 2, "and after the next key")
    eq(#clip:notes(), 4, "four notes")
    eq(written(clip):find("62@1", 1, true) ~= nil, true, "D4 is the next note, one beat on")
    keys("<Esc>")
    eq(paw.step.active(), nil, "normal mode does not listen")
    keys("u")
    eq(#clip:notes(), 0, "u takes back all of it")
  end)
)

test(
  "notation step input: in R a key changes the pitch of the next note and the rhythm stays",
  done(function()
    local view, clip = song("cde")
    view:set(35, 0)
    keys("R")
    play(65)
    play(67)
    keys("<Esc>")
    eq(written(clip), "65@0+1 67@1+1 64@2+1", "two notes re-pitched in turn, lengths kept")
  end)
)

test(
  "notation step input: in I a key pushes the later music along by the value",
  done(function()
    local view, clip = song("cd")
    view:set(35, 0)
    keys("I")
    play(67)
    keys("<Esc>")
    eq(written(clip), "67@0+1 60@1+1 62@2+1", "the notes after it move one beat")
  end)
)

test(
  "notation step input: in F major, pitch 70 is written Bb",
  done(function()
    local view, clip = song()
    paw.harmony.set_key("F major")
    paw.flush()
    keys("i")
    play(70)
    keys("<Esc>")
    eq(clip:notes()[1].pitch, 70, "the pitch played")
    local model = require("notation.model")
    local note = model.events(view:layout())[1].notes[1]
    eq(note.step % 7, 6, "the letter is B")
    eq(note.alter, -1, "flat, not A sharp")
  end)
)

test(
  "notation step input: the pedal with no key held enters a rest",
  done(function()
    local view, clip = song()
    keys("i")
    play(60)
    pedal(true)
    pedal(false)
    play(62)
    keys("<Esc>")
    eq(view.beat, 3, "the caret went on over the rest")
    eq(written(clip), "60@0+1 62@2+1", "a rest between the two notes")
  end)
)
