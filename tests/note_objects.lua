-- The text objects of the piano roll, typed as keys: the note, the chord,
-- the phrase, the voice and the pitch.
local T = ...
local test, eq, keys, melody = T.test, T.eq, T.keys, T.melody
local paw = require("paw")
local api = paw.api

local function N(pitch, start, length) return { pitch = pitch, start = start, length = length, velocity = 100 } end

--- A clip of two phrases in the piano roll: a melody over two chords, a
--- rest, then a broken C major chord.
local function song()
  T.fresh()
  paw.keymap.feed("<Esc><Esc>")
  local t = paw.add_track({ name = "P" })
  local clip = t:add_clip({ start = 0, length = 8, notes = {
    N(48, 0, 2), N(52, 0, 2), N(55, 0, 2), N(72, 0, 1), N(74, 1, 1),
    N(50, 2, 2), N(53, 2, 2), N(57, 2, 2), N(76, 2, 2),
    N(60, 5, 0.5), N(64, 5.5, 0.5), N(67, 6, 0.5), N(72, 6.5, 0.5),
  } })
  api.undo_checkpoint()
  local roll = paw.ui.views.pianoroll
  roll:edit(clip)
  paw.ui.focus("pianoroll")
  return clip, roll
end

local function yanked() return #paw.keymap.getreg().notes end

test("the piano roll's text objects take notes, chords, phrases, voices and pitches", function()
  local clip, roll = song()
  roll:set(74, 1)
  keys("din")
  eq(melody(clip):find("74@", 1, true), nil, "din deletes the note")
  paw.undo()
  roll:set(72, 0)
  keys("y2in")
  eq(yanked(), 2, "2in: the note and the next of its voice")

  roll:set(52, 0)
  keys("yic")
  eq(yanked(), 4, "ic: the notes that start together")
  keys("y2ic")
  eq(yanked(), 8, "2ic: and the next chord")
  keys("vicicy")
  eq(yanked(), 8, "ic again in visual mode takes in the next chord")

  roll:set(74, 1)
  keys("dip")
  eq(melody(clip), "60@5+0.5 64@5.5+0.5 67@6+0.5 72@6.5+0.5", "dip deletes the phrase")
  paw.undo()
  roll:set(60, 4.5)
  keys("yap")
  eq(yanked() .. " " .. paw.keymap.getreg().length, "4 3", "yap from a rest: the next phrase and the rest after it")
  paw.opt.phrase_rest = 1.5
  T.after(function() paw.opt.phrase_rest = 0.5 end)
  keys("dip")
  eq(melody(clip), "", "a longer phrase_rest makes one phrase")
  paw.undo()
  paw.opt.phrase_rest = 0.5
  roll:set(60, 0)
  keys(")")
  eq(roll.pitch .. "@" .. roll.beat, "60@5", ") goes to the next phrase")

  roll:set(52, 0)
  keys("yiv")
  eq(yanked(), 2, "iv: the inner voice, the third from the top")
  roll:set(48, 0)
  keys("div")
  eq(melody(clip), "52@0+2 55@0+2 72@0+1 74@1+1 53@2+2 57@2+2 76@2+2", "div deletes the bass line and no note between its notes")
  paw.undo()

  roll:set(72, 0)
  keys("di=")
  eq(melody(clip):find("72@", 1, true), nil, "di= deletes every note of the pitch")
  paw.undo()
  roll:set(60, 5)
  keys("ya=")
  eq(yanked(), 4, "a=: every C, in every octave")

  roll:set(60, 5)
  keys("yac")
  eq(yanked(), 4, "ac: the broken chord, as the harmony reads it")
end)
