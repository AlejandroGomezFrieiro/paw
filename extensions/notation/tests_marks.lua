-- Marks that play (dynamics, hairpins, articulations) follow what is written
-- in notation, and `notation.apply-marks` brings back MIDI that drifted from
-- them; the piano roll's edits are never overwritten by another edit. Loaded
-- by tests.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation")
end

local keys = T.keys

--- A track with an empty clip open as notation, `bars` bars long.
local function song(bars)
  fresh()
  local view = load()
  local track = paw.add_track({ name = "Lead" })
  track:add_device("synth")
  local clip = track:add_clip({ start = 0, length = (bars or 2) * 4, name = "tune", notes = {} })
  paw.flush()
  paw.keymap.set_mode("n")
  view:edit(clip)
  paw.ui.focus("notation")
  view.value, view.dot, view.voice, view.triplets = 1, false, 1, false
  api.undo_checkpoint()
  return view, clip
end

--- Four quarters in bar 1 under a p, and an f from bar 2 (with a note in it, if asked).
local function dynamics(fifth)
  local view, clip = song(2)
  keys("icdef<Esc>")
  view:set(35, 0)
  paw.cmd("notation.dyn", { "p" })
  api.undo_checkpoint()
  view:set(nil, 4)
  paw.cmd("notation.dyn", { "f" })
  api.undo_checkpoint()
  if fifth then
    view:set(35, 4)
    keys("ig<Esc>")
  end
  return view, clip
end

local function vel(clip)
  local out = {}
  for i, n in ipairs(clip:notes()) do out[i] = n.velocity end
  return table.concat(out, " ")
end

local function lengths(clip)
  local out = {}
  for i, n in ipairs(clip:notes()) do out[i] = string.format("%g", n.length) end
  return table.concat(out, " ")
end

-- Notation edits follow the marks --------------------------------------------------------------------

test("marks follow: a note entered under a dynamic takes its velocity, and under a hairpin the ramp's", function()
  local view, clip = dynamics()
  eq(vel(clip), "52 52 52 52", "bar 1 is p")
  view:set(35, 4)
  keys("ia<Esc>")
  eq(vel(clip), "52 52 52 52 96", "a note entered in bar 2 is f")
  paw.commands.exec("2notation.cresc")
  api.undo_checkpoint()
  view:set(37, 6)
  keys("ib<Esc>")
  local entered
  for _, n in ipairs(clip:notes()) do
    if n.start == 6 then entered = n end
  end
  eq(entered ~= nil and entered.velocity > 96 and entered.velocity < 127, true, "a note halfway up a crescendo from the f is between: " .. vel(clip))
end)

test("marks follow: a note moved in notation takes the dynamic where it lands, and one that stays under the same dynamic keeps the roll's", function()
  local view, clip = dynamics()
  -- The roll gives the first note its own velocity; moving another note in notation leaves it be.
  clip:set_note(1, { velocity = 33 })
  api.undo_checkpoint()
  view:set(41, 3)
  keys("2L")
  local moved
  for _, n in ipairs(clip:notes()) do
    if n.start == 5 then moved = n end
  end
  eq(moved ~= nil, true, "the F moved into bar 2: " .. vel(clip))
  eq(moved and moved.velocity, 96, "and plays at the f there")
  eq(clip:notes()[1].velocity, 33, "the roll's velocity on another note stays")
  view:set(41, 1)
  keys("L")
  eq(clip:notes()[2].velocity, 52, "a note moved within its p is still p")
end)

test("marks follow: a roll edit, then a notation edit elsewhere, leaves the roll edit alone", function()
  local view, clip = dynamics()
  clip:set_note(2, { velocity = 33, length = 0.25 })
  clip:set_note(3, { pitch = 67 })
  api.undo_checkpoint()
  view:set(35, 4)
  keys("ic<Esc>")
  eq(clip:notes()[2].velocity, 33, "the roll's velocity")
  eq(clip:notes()[2].length, 0.25, "the roll's length")
  eq(clip:notes()[3].pitch, 67, "the roll's pitch")
  eq(clip:notes()[5].velocity, 96, "while the new note follows the f")
  -- A mark written elsewhere is a change of the marks, and says so: it sets the notes it reaches.
  view:set(nil, 4)
  paw.cmd("notation.dyn", { "mf" })
  api.undo_checkpoint()
  eq(clip:notes()[2].velocity, 33, "a dynamic after it does not reach it")
end)

-- notation.apply-marks -----------------------------------------------------------------------------

test("apply-marks: MIDI that drifted plays as the marks say again, in one undo step; a range and the selection limit it", function()
  local view, clip = dynamics(true)
  clip:set_note(1, { velocity = 10 })
  clip:set_note(3, { velocity = 11 })
  clip:set_note(5, { velocity = 12 })
  api.undo_checkpoint()
  eq(vel(clip), "10 52 11 52 12", "drifted in the roll")
  paw.commands.exec("1notation.apply-marks")
  api.undo_checkpoint()
  eq(vel(clip), "52 52 52 52 12", "a range of bars: bar 1 only")
  keys("u")
  eq(vel(clip), "10 52 11 52 12", "one undo step")
  view:set(35, 2)
  keys("vl:notation.apply-marks<CR>")
  eq(vel(clip), "10 52 52 52 12", "the selection: its two notes (the second was right already)")
  paw.cmd("notation.apply-marks")
  api.undo_checkpoint()
  eq(vel(clip), "52 52 52 52 96", "with no range, the whole clip")
  local before = vel(clip)
  paw.cmd("notation.apply-marks")
  eq(vel(clip), before, "again: nothing more to do")
end)

test("apply-marks: articulations set the length, an accent is not added twice, and taking the mark away puts back what was there", function()
  local view, clip = song(1)
  keys("icdef<Esc>")
  view:set(35, 0)
  paw.cmd("notation.dyn", { "mf" })
  view:set(36, 1)
  keys("g'g>")
  api.undo_checkpoint()
  eq(clip:notes()[2].length, 0.5, "staccato")
  eq(clip:notes()[2].velocity, 100, "and an accent on the mf")
  clip:set_note(2, { velocity = 20, length = 1 })
  api.undo_checkpoint()
  paw.cmd("notation.apply-marks")
  api.undo_checkpoint()
  eq(clip:notes()[2].length, 0.5, "the staccato's length again")
  eq(clip:notes()[2].velocity, 100, "the accent on the mf again")
  paw.cmd("notation.apply-marks")
  eq(clip:notes()[2].velocity, 100, "not twice")
  eq(lengths(clip), "1 0.5 1 1", "the other notes keep their lengths")
  view:set(36, 1)
  keys("g>")
  eq(clip:notes()[2].velocity, 20, "taking the accent away puts back what the note had before the marks were applied")
end)

test("apply-marks: g@ asks first, hears and shows the change while it is open, and Esc leaves nothing; Enter writes it", function()
  local view, clip = dynamics(true)
  clip:set_note(2, { velocity = 5 })
  clip:set_note(5, { velocity = 6 })
  api.undo_checkpoint()
  local before, state = vel(clip), api.undo_current()
  view:set(35, 0)
  keys("g@ib")
  eq(require("notation.popover").active(), true, "the prompt is open")
  eq(vel(clip), "52 52 52 52 6", "the bar's notes are heard as the marks say")
  eq(view.ghost ~= nil, true, "and shown")
  keys("<Esc>")
  eq(require("notation.popover").active(), false, "Esc closes it")
  eq(vel(clip), before, "and leaves the notes as they were")
  eq(api.undo_current(), state, "with no step of its own")
  keys("g@ib<CR>")
  eq(vel(clip), "52 52 52 52 6", "Enter writes it, over the bar only")
  keys("u")
  eq(vel(clip), before, "one undo step")
  view:set(35, 4)
  keys("vg@")
  eq(require("notation.popover").active(), true, "on a selection too")
  keys("<CR>")
  eq(clip:notes()[5].velocity, 96, "the selected note")
  eq(clip:notes()[2].velocity, 5, "and the rest as they were")
end)
