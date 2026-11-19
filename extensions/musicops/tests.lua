-- Tests of musicops, loaded by tests/suite.lua with its helpers.
local T = ...
local api = paw.api
local eq, test = T.eq, T.test

local mo, scale
local function load()
  if not mo then
    -- As config/init.lua does: utau first, so that musicops' phrase keys
    -- (`(` `)`) win over the vocal editor's phoneme keys there.
    if not package.loaded["utau"] then paw.ext.load("extensions/utau") end
    paw.ext.load("extensions/musicops")
    assert(paw.ext.loaded.musicops.ok, paw.ext.loaded.musicops.error)
    mo = require("musicops")
    scale = mo.scale
  end
  for name, value in pairs({
    musicops_scale_lock = false, musicops_seed = 7, musicops_strum = 0.125, musicops_arp_step = 0.25,
    musicops_phrase_rest = 0.5, musicops_ramp = 30, musicops_strength = 1, musicops_swing = 0,
  }) do paw.opt[name] = value end
  paw.opt.note_grid = 0.25
  return mo
end

--- Notes as text, in time order: "60@0+1" or with velocities "60@0+1v100".
local function str(notes, vel)
  local list = {}
  for i, n in ipairs(notes) do list[i] = n end
  table.sort(list, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.pitch < b.pitch
  end)
  local out = {}
  for i, n in ipairs(list) do
    out[i] = string.format("%d@%g+%g", n.pitch, n.start, n.length) .. (vel and ("v" .. n.velocity) or "")
  end
  return table.concat(out, " ")
end

local function N(pitch, start, length, velocity, meta)
  return { pitch = pitch, start = start, length = length or 1, velocity = velocity or 100, meta = meta }
end

local CHORD = { N(60, 0, 1), N(64, 0, 1), N(67, 0, 1) }

test("musicops: time functions on known notes", function()
  load()
  -- Humanize: reproducible, within its bounds, and the same notes for the same seed.
  local line = { N(60, 0, 1, 100), N(62, 1, 1, 100), N(64, 2, 1, 100), N(65, 3, 1, 100) }
  local a = mo.humanize(line, { timing = 0.0625, velocity = 10, seed = 42 })
  eq(str(a, true), str(mo.humanize(line, { timing = 0.0625, velocity = 10, seed = 42 }), true), "the same seed, the same result")
  eq(str(a, true) ~= str(mo.humanize(line, { timing = 0.0625, velocity = 10, seed = 43 }), true), true, "another seed, another")
  for i, n in ipairs(a) do
    eq(math.abs(n.start - line[i].start) <= 0.0625, true, "start within the timing")
    eq(math.abs(n.velocity - 100) <= 10 and n.velocity % 1 == 0, true, "whole velocity within the range")
    eq(n.pitch, line[i].pitch, "pitch untouched")
  end
  eq(str(mo.humanize(line, { timing = 0, velocity = 0, seed = 3 }), true), str(line, true), "no amount, no change")
  local r = mo.random(42)
  local first = r()
  eq(first, (42 + 1) * 16807 % 2147483647 / 2147483646 - 1 / 2147483646, "Park-Miller from the seed")
  eq(str(mo.humanize({ N(60, 1, 1, 100) }, { timing = 0.5, velocity = 20, seed = 42 }), true),
    string.format("60@%g+1v%d", 1 + (first * 2 - 1) * 0.5, 100 + math.floor((r() * 2 - 1) * 20 + 0.5)), "exactly the generator's numbers")
  eq(line[1].start, 0, "the notes given are not changed")

  -- Quantize: all the way, half way, with swing, lengths.
  local loose = { N(60, 0.125 + 0.0625, 0.375), N(62, 0.5 + 0.0625, 0.5), N(64, 1.125 - 0.0625, 0.625) }
  eq(str(mo.quantize(loose, { grid = 0.5 })), "60@0+0.375 62@0.5+0.5 64@1+0.625", "to the grid")
  eq(str(mo.quantize(loose, { grid = 0.5, strength = 0.5 })), "60@0.09375+0.375 62@0.53125+0.5 64@1.03125+0.625", "half way")
  eq(str(mo.quantize({ N(60, 0, 1), N(62, 0.5, 1), N(64, 1, 1), N(65, 1.5, 1) }, { grid = 0.5, swing = 0.5 })),
    "60@0+1 62@0.75+1 64@1+1 65@1.75+1", "swing delays every second grid line")
  eq(str(mo.quantize(loose, { grid = 0.5, lengths = true })), "60@0+0.5 62@0.5+0.5 64@1+0.5", "and lengths")

  -- Legato, staccato, set_length.
  local spaced = { N(60, 0, 0.25), N(64, 0, 0.5), N(62, 1, 0.5), N(65, 1.5, 1) }
  eq(str(mo.legato(spaced)), "60@0+1 64@0+1 62@1+0.5 65@1.5+1", "each note held to the next; the last stays")
  eq(str(mo.legato(spaced, { gap = 0.125 })), "60@0+0.875 64@0+0.875 62@1+0.375 65@1.5+1", "less a gap")
  eq(str(mo.staccato(spaced)), "60@0+0.125 64@0+0.25 62@1+0.25 65@1.5+0.5", "half as long")
  eq(str(mo.staccato(spaced, { factor = 0.25 })), "60@0+0.0625 64@0+0.125 62@1+0.125 65@1.5+0.25", "a quarter")
  eq(str(mo.set_length(spaced, { length = 0.5 })), "60@0+0.5 64@0+0.5 62@1+0.5 65@1.5+0.5", "one length")

  -- Reverse, double and half time.
  local phrase = { N(60, 0, 1), N(62, 1, 0.5), N(64, 2, 2) }
  eq(str(mo.reverse(phrase)), "64@0+2 62@2.5+0.5 60@3+1", "backwards within its span")
  eq(str(mo.reverse(mo.reverse(phrase))), str(phrase), "twice is the original")
  local late = { N(60, 1, 1), N(62, 2, 1), N(64, 3, 0.5) }
  eq(str(mo.double_time(late)), "60@1+0.5 62@1.5+0.5 64@2+0.25", "double time from the first note")
  eq(str(mo.half_time(late)), "60@1+2 62@3+2 64@5+1", "half time")
  eq(str(mo.double_time(late, { anchor = 0 })), "60@0.5+0.5 62@1+0.5 64@1.5+0.25", "around another anchor")
  eq(str(mo.stretch(late, { factor = 1.5 })), "60@1+1.5 62@2.5+1.5 64@4+0.75", "any factor")
end)

test("musicops: chord functions on known notes", function()
  load()
  eq(str(mo.strum(CHORD, { step = 0.125 })), "60@0+1 64@0.125+0.875 67@0.25+0.75", "strummed up, ends kept")
  eq(str(mo.strum(CHORD, { step = 0.125, dir = "down" })), "67@0+1 64@0.125+0.875 60@0.25+0.75", "strummed down")
  local two = { N(60, 0, 1), N(64, 0, 1), N(62, 2, 1), N(65, 2, 1) }
  eq(str(mo.strum(two, { step = 0.25 })), "60@0+1 64@0.25+0.75 62@2+1 65@2.25+0.75", "each chord on its own")

  eq(str(mo.arpeggiate(CHORD, { step = 0.25 })), "60@0+0.25 64@0.25+0.25 67@0.5+0.25 60@0.75+0.25", "up")
  eq(str(mo.arpeggiate(CHORD, { step = 0.25, mode = "down" })), "67@0+0.25 64@0.25+0.25 60@0.5+0.25 67@0.75+0.25", "down")
  eq(str(mo.arpeggiate({ N(60, 0, 2), N(64, 0, 2), N(67, 0, 2) }, { step = 0.25, mode = "updown" })),
    "60@0+0.25 64@0.25+0.25 67@0.5+0.25 64@0.75+0.25 60@1+0.25 64@1.25+0.25 67@1.5+0.25 64@1.75+0.25", "up and down")
  local played = { N(67, 0, 1, 90), N(60, 0.03125, 0.96875, 80, { tag = "c" }), N(64, 0.0625, 0.9375, 70) }
  local arp = mo.arpeggiate(played, { step = 0.25, mode = "played" })
  eq(str(arp, true), "67@0+0.25v90 60@0.25+0.25v80 64@0.5+0.25v70 67@0.75+0.25v90", "in the order they were played")
  eq(arp[2].meta.tag .. tostring(arp[2].meta ~= played[2].meta), "ctrue", "each new note copies its source's meta")
  eq(str(mo.arpeggiate(CHORD, { step = 0.25, gate = 0.5 })), "60@0+0.125 64@0.25+0.125 67@0.5+0.125 60@0.75+0.125", "gate")
  eq(str(mo.arpeggiate({ N(60, 0, 0.5), N(64, 0, 0.5), N(72, 1, 1) }, { step = 0.25 })), "60@0+0.25 64@0.25+0.25 72@1+1", "a lone note stays")

  eq(str(mo.invert(CHORD)), "64@0+1 67@0+1 72@0+1", "first inversion")
  eq(str(mo.invert(CHORD, { times = 2 })), "67@0+1 72@0+1 76@0+1", "second inversion")
  eq(str(mo.invert(CHORD, { dir = -1 })), "55@0+1 60@0+1 64@0+1", "inverted down")
  eq(str(mo.invert(two)), "64@0+1 72@0+1 65@2+1 74@2+1", "each chord")

  eq(str(mo.add_octave({ N(60, 0, 1), N(120, 1, 1) })), "60@0+1 72@0+1 120@1+1", "doubled an octave up, within range")
  eq(str(mo.remove_overlaps({ N(60, 0, 2), N(60, 1, 1), N(60, 1, 0.5), N(62, 0, 4) })), "60@0+1 62@0+4 60@1+1",
    "overlapping notes of a pitch are cut, doubled ones go")

  local groups = mo.chords({ N(60, 0, 1), N(64, 0.03125, 1), N(67, 0.5, 1) })
  eq(#groups .. " " .. #groups[1] .. " " .. #groups[2], "2 2 1", "chords by how close they start")
  local ph = mo.phrases({ N(60, 0, 1), N(62, 1.25, 0.5), N(64, 3, 1), N(65, 4.75, 1) }, 0.5)
  eq(#ph, 3, "a rest longer than half a beat ends a phrase")
  eq(ph[1].start .. "-" .. ph[1].finish .. " " .. ph[2].start .. "-" .. ph[2].finish, "0-1.75 3-4", "where they are")
  eq(str(mo.sounding({ N(60, 0, 2), N(64, 1, 1), N(67, 2, 1) }, 1.5)), "60@0+2 64@1+1", "what sounds at a beat")
end)

test("musicops: pitch and velocity functions on known notes", function()
  load()
  local cmaj = { N(60, 0), N(64, 1), N(71, 2), N(61, 3) }
  eq(str(mo.transpose_scale(cmaj, 1, "C major")), "62@0+1 65@1+1 72@2+1 63@3+1", "a step up the scale; C# stays a sharp")
  eq(str(mo.transpose_scale(cmaj, -1, "C major")), "59@0+1 62@1+1 69@2+1 60@3+1", "a step down")
  eq(str(mo.transpose_scale(cmaj, 7, "C major")), "72@0+1 76@1+1 83@2+1 73@3+1", "seven steps is an octave")
  eq(str(mo.transpose_scale({ N(62, 0), N(65, 1) }, 2, "D minor")), "65@0+1 69@1+1", "in D minor")
  eq(str(mo.transpose(cmaj, -12)), "48@0+1 52@1+1 59@2+1 49@3+1", "semitones")
  eq(str(mo.snap_scale({ N(61, 0), N(63, 1), N(66, 2), N(60, 3) }, "C major")), "62@0+1 64@1+1 67@2+1 60@3+1",
    "to the nearest in the key, halfway goes up")
  eq(str(mo.snap_scale({ N(61, 0), N(66, 1) }, "C major", { dir = "down" })), "60@0+1 65@1+1", "or down")
  eq(str(mo.snap_scale({ N(61, 0), N(63, 1) }, "A minor_pentatonic")), "62@0+1 64@1+1", "any scale")
  local melody = { N(60, 0), N(62, 1), N(64, 2), N(65, 3), N(67, 4) }
  eq(str(mo.mirror(melody, { axis = 64, key = "C major" })), "67@0+1 65@1+1 64@2+1 62@3+1 60@4+1", "mirrored in the key")
  eq(str(mo.mirror(melody, { axis = 64 })), "68@0+1 66@1+1 64@2+1 63@3+1 61@4+1", "in semitones")
  eq(str(mo.mirror(melody)), "60@0+1 58@1+1 56@2+1 55@3+1 53@4+1", "around the first note")

  local even = { N(60, 0, 1, 64), N(62, 1, 1, 64), N(64, 2, 1, 64), N(65, 3, 1, 64) }
  eq(str(mo.crescendo(even, { amount = 30 }), true), "60@0+1v64 62@1+1v74 64@2+1v84 65@3+1v94", "crescendo")
  eq(str(mo.diminuendo(even, { amount = 30 }), true), "60@0+1v64 62@1+1v54 64@2+1v44 65@3+1v34", "diminuendo")
  eq(str(mo.ramp(even, { from = 10, to = 100 }), true), "60@0+1v10 62@1+1v40 64@2+1v70 65@3+1v100", "a ramp")
  eq(str(mo.crescendo(even, { amount = 100 }), true), "60@0+1v64 62@1+1v97 64@2+1v127 65@3+1v127", "never past 127")
  local mixed = { N(60, 0, 1, 40), N(62, 1, 1, 80), N(64, 2, 1, 120) }
  eq(str(mo.compress(mixed), true), "60@0+1v60 62@1+1v80 64@2+1v100", "compressed to half the spread")
  eq(str(mo.compress(mixed, { ratio = 1.5 }), true), "60@0+1v20 62@1+1v80 64@2+1v127", "expanded")
  eq(str(mo.set_velocity(mixed), true), "60@0+1v80 62@1+1v80 64@2+1v80", "levelled")
  eq(str(mo.set_velocity(mixed, { velocity = 99 }), true), "60@0+1v99 62@1+1v99 64@2+1v99", "set")
  eq(str(mo.accent({ N(60, 0, 1, 80), N(62, 0.5, 1, 80), N(64, 1, 1, 80) }, { amount = 15 }), true),
    "60@0+1v95 62@0.5+1v80 64@1+1v95", "accents on the beat")

  local kept = mo.staccato({ N(60, 0, 1, 100, { lyric = "la" }) })
  eq(kept[1].meta.lyric, "la", "meta stays with the note")
end)

test("musicops: keys and scales", function()
  load()
  local d = scale.parse("D minor")
  eq(d.root .. " " .. d.scale .. " " .. #d.steps, "2 minor 7", "parsed")
  eq(scale.name("bb"), "Bb major", "major when no scale is named, spelled as the key is written")
  eq(scale.name("F# Harmonic Minor"), "F# harmonic_minor", "names are forgiving")
  eq(pcall(scale.parse, "H minor"), false, "a bad root is an error")
  eq(pcall(scale.parse, "C nonsense"), false, "and an unknown scale")
  eq(scale.contains("C major", 64) and not scale.contains("C major", 63), true, "contains")
  eq(scale.step("C major", 71, 1) .. " " .. scale.step("C major", 60, -1) .. " " .. scale.step("D minor", 62, 7), "72 59 74", "steps")
  eq(scale.snap("E major", 0) >= 0 and scale.step("B major", 0, 1) > 0, true, "the bottom of the range does not break")
end)

test("musicops: the project's key is saved and undone", function()
  load()
  T.fresh()
  eq(scale.project(), nil, "a new project has no key")
  eq(scale.name(scale.current()), "C major", "and works in C major")
  paw.cmd("key", { "D", "minor" })
  api.undo_checkpoint()
  eq(scale.name(scale.current()), "D minor", "set by the command")
  eq(api.project_get().key, "D minor", "kept as the project's key")
  paw.cmd("musicops.key", { "G", "dorian" })
  api.undo_checkpoint()
  paw.undo()
  eq(scale.name(scale.current()), "D minor", "undone")
  paw.undo()
  eq(scale.project(), nil, "undone to none")
  paw.redo()
  eq(scale.name(scale.current()), "D minor", "redone")
  local path = paw.project.save(T.scratch .. "/musicops-key.json")
  T.fresh()
  eq(scale.project(), nil, "a new project again")
  paw.project.load(path)
  eq(scale.name(scale.current()), "D minor", "loaded with the project")
  paw.cmd("key", { "off" })
  eq(scale.project(), nil, "cleared")
  paw.cmd("key", { "X", "minor" })
  eq(scale.project(), nil, "a bad key changes nothing")
end)

--- A clip open in the piano roll.
local function roll_with(notes, length)
  T.fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  load()
  local t = paw.add_track({ name = "P" })
  local clip = t:add_clip({ start = 0, length = length or 8, notes = notes })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  api.undo_checkpoint()
  local roll = paw.ui.views.pianoroll
  roll:edit(clip)
  roll:set_step(nil)  -- insert mode's note length, which other tests may have changed
  roll:set(notes[1] and notes[1].pitch or 60, 0)
  return clip, roll, t
end

local function done()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.hide("pianoroll")
  paw.ui.focus("arrange")
  paw.opt.musicops_scale_lock = false
end

test("musicops: operators in the piano roll, with . and counts", function()
  local clip, roll = roll_with({
    N(60, 0, 1), N(62, 1, 1), N(64, 2, 1),          -- a phrase
    N(60, 4, 1), N(64, 4, 1), N(67, 4, 1),          -- a chord
    N(62, 6, 1), N(65, 6, 1), N(69, 6, 1),          -- another
  })
  T.keys("gzkip")
  eq(T.melody(clip):sub(1, 20), "62@0+1 64@1+1 65@2+1", "gzkip: the phrase a step up the scale")
  T.keys(".")
  eq(T.melody(clip):sub(1, 20), "64@0+1 65@1+1 67@2+1", ". does it again")
  paw.undo()
  paw.undo()
  eq(T.melody(clip):sub(1, 20), "60@0+1 62@1+1 64@2+1", "each one undo step")
  T.keys("vip2gzk")
  eq(T.melody(clip):sub(1, 20), "64@0+1 65@1+1 67@2+1", "a count in visual mode is the amount: two steps")
  paw.undo()
  T.keys("gzj2w")
  eq(T.melody(clip):sub(1, 20), "59@0+1 60@1+1 64@2+1", "with a motion: two notes a step down")
  paw.undo()

  roll:set(60, 4)
  T.keys("gzsih")
  eq(T.melody(clip):match("60@4.-67@%S+"), "60@4+1 64@4.125+0.875 67@4.25+0.75", "gzsih strums the chord at the cursor")
  roll:set(62, 6)
  T.keys(".")
  eq(T.melody(clip):match("62@6.-$"), "62@6+1 65@6.125+0.875 69@6.25+0.75", ". strums the next one")
  paw.undo()
  paw.undo()
  roll:set(60, 4)
  T.keys("gzSih")
  eq(T.melody(clip):match("67@4.-60@%S+"), "67@4+1 64@4.125+0.875 60@4.25+0.75", "gzS strums down")
  paw.undo()
  T.keys("gzpih")
  eq(T.melody(clip):match("60@4.-$"), "60@4+0.25 64@4.25+0.25 67@4.5+0.25 60@4.75+0.25 62@6+1 65@6+1 69@6+1", "gzp arpeggiates")
  paw.undo()
  T.keys("vah4gzP")
  eq(T.melody(clip):match("6%d@4.-$"), "67@4+0.25 64@4.25+0.25 60@4.5+0.25 67@4.75+0.25 62@6+1 65@6+1 69@6+1",
    "a count sets the steps per beat")
  paw.undo()
  T.keys("gzuih")
  eq(T.melody(clip):match("64@4.-72@%S+"), "64@4+1 67@4+1 72@4+1", "gzu inverts the chord")
  T.keys("vah2gzU")
  eq(T.melody(clip):match("5%d@4.-64@%S+"), "55@4+1 60@4+1 64@4+1", "two inversions down from the first")
  paw.undo()
  paw.undo()

  -- Velocity, time.
  roll:set(60, 0)
  T.keys("gz>ip")
  local vel = {}
  for _, n in ipairs(clip:notes()) do if n.start < 4 then vel[#vel + 1] = n.velocity end end
  eq(table.concat(vel, " "), "100 115 127", "a crescendo over the phrase")
  paw.undo()
  T.keys("vip20gz<lt>")
  vel = {}
  for _, n in ipairs(clip:notes()) do if n.start < 4 then vel[#vel + 1] = n.velocity end end
  eq(table.concat(vel, " "), "100 90 80", "a diminuendo of the count")
  paw.undo()
  T.keys("gzrip")
  eq(T.melody(clip):sub(1, 20), "64@0+1 62@1+1 60@2+1", "gzr reverses the phrase")
  paw.undo()
  T.keys("gzdip")
  eq(T.melody(clip):sub(1, 28), "60@0+0.5 62@0.5+0.5 64@1+0.5", "gzd doubles the time")
  paw.undo()
  T.keys("gzDip")
  eq(T.melody(clip):sub(1, 13) .. " " .. tostring(T.melody(clip):find("64@4+2", 1, true) ~= nil), "60@0+2 62@2+2 true",
    "gzD halves it")
  eq(clip.length, 8, "the clip still holds it")
  paw.undo()
  T.keys("gztip")
  eq(T.melody(clip):sub(1, 26), "60@0+0.5 62@1+0.5 64@2+0.5", "gzt staccato")
  T.keys("gzlip")
  eq(T.melody(clip):sub(1, 22), "60@0+1 62@1+1 64@2+0.5", "gzl legato")
  paw.undo()
  paw.undo()
  T.keys("gzhh")
  local moved = 0
  for _, n in ipairs(clip:notes()) do if n.pitch == 60 and n.start % 1 ~= 0 then moved = moved + 1 end end
  eq(moved > 0, true, "gzhh humanizes every note of the pitch")
  paw.undo()
  local s = clip:notes()
  s[2].start = 1.0625
  clip:set_notes(s)
  api.undo_checkpoint()
  T.keys("gzqip")
  eq(T.melody(clip):sub(1, 20), "60@0+1 62@1+1 64@2+1", "gzq quantizes")
  paw.undo()
  T.keys("vip50gzq")
  eq(T.melody(clip):sub(1, 26), "60@0+1 62@1.03125+1 64@2+1", "half way with a count of 50")
  done()
end)

test("musicops: phrase and chord text objects and motions", function()
  local clip, roll = roll_with({
    N(60, 0, 1), N(62, 1, 0.5), N(64, 2, 1),        -- one phrase: the rests are half a beat at most
    N(65, 4, 1), N(67, 5, 1),                       -- a second
    N(48, 7, 1), N(52, 7, 1), N(55, 7.5, 0.5),      -- a chord, and a note starting while it sounds
  })
  roll:set(64, 2.5)
  T.keys("dip")
  eq(T.melody(clip), "65@4+1 67@5+1 48@7+1 52@7+1 55@7.5+0.5", "dip deletes the phrase around the cursor")
  eq(roll.beat, 0, "the cursor goes to where it started")
  paw.undo()
  roll:set(60, 3.5)
  T.keys("yap")
  local reg = paw.keymap.getreg()
  eq(#reg.notes .. " " .. reg.length, "2 3", "yap from a rest: the next phrase and the rest after it")
  roll:set(60, 0)
  T.keys("d2ip")
  eq(T.melody(clip), "48@7+1 52@7+1 55@7.5+0.5", "a count takes more phrases")
  paw.undo()
  roll:set(60, 0)
  T.keys(")")
  eq(roll.pitch .. "@" .. roll.beat, "65@4", ") goes to the next phrase")
  T.keys(")")
  eq(roll.beat, 7, "and the next")
  T.keys(")")
  eq(roll.beat, 8, "then the end of the clip")
  T.keys("(")
  eq(roll.beat, 7, "( goes back")
  T.keys("2(")
  eq(roll.pitch .. "@" .. roll.beat, "60@0", "with a count")
  roll:set(60, 1)
  T.keys("d)")
  eq(T.melody(clip), "60@0+1 65@4+1 67@5+1 48@7+1 52@7+1 55@7.5+0.5", "d) deletes to the next phrase")
  paw.undo()
  paw.opt.musicops_phrase_rest = 0.25
  roll:set(60, 0)
  T.keys("dip")
  eq(T.melody(clip), "64@2+1 65@4+1 67@5+1 48@7+1 52@7+1 55@7.5+0.5", "the rest that ends a phrase is an option")
  paw.undo()
  paw.opt.musicops_phrase_rest = 0.5

  roll:set(48, 7.25)
  T.keys("yih")
  eq(#paw.keymap.getreg().notes, 2, "yih: the two notes of the chord")
  T.keys("yah")
  eq(#paw.keymap.getreg().notes, 3, "yah: and the note that starts while it sounds")
  T.keys("vih")
  local sel = paw.keymap.selection()
  eq(sel.kind .. " " .. sel.r0 .. "-" .. sel.r1 .. " " .. sel.c0, "block 48-52 7", "vih selects the chord")
  T.keys("<Esc>")
  roll:set(60, 6.5)
  T.keys("yih")
  eq(#paw.keymap.getreg().notes, 3, "between chords there is no chord: the register is unchanged")
  done()
end)

test("musicops: operators in the arrange view", function()
  load()
  T.fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  local t = paw.add_track({ name = "A" })
  local a = t:add_clip({ name = "a", start = 0, length = 4, notes = { N(60, 0, 1), N(62, 1, 1), N(64, 2, 1) } })
  local b = t:add_clip({ name = "b", start = 4, length = 4, notes = { N(60, 0, 1), N(64, 0, 1), N(67, 0, 1) } })
  local u = paw.add_track({ name = "U" })
  local c = u:add_clip({ name = "c", start = 0, length = 4, notes = { N(67, 0, 1) } })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0)
  paw.opt.grid = 1
  api.undo_checkpoint()
  T.keys("gzkic")
  eq(T.melody(a) .. " | " .. T.melody(b), "62@0+1 64@1+1 65@2+1 | 60@0+1 64@0+1 67@0+1", "gzkic: the clip's notes a step up")
  paw.cursor.set_beat(4)
  T.keys(".")
  eq(T.melody(b), "62@0+1 65@0+1 69@0+1", ". on the next clip")
  paw.undo()
  paw.undo()
  paw.cursor.set_beat(0)
  T.keys("gzkk")
  eq(T.melody(a) .. " | " .. T.melody(b), "62@0+1 64@1+1 65@2+1 | 62@0+1 65@0+1 69@0+1", "gzkk: every clip of the track")
  eq(T.melody(c), "67@0+1", "not the next track")
  paw.undo()
  T.keys("2gzjj")
  eq(T.melody(a) .. " | " .. T.melody(c), "59@0+1 60@1+1 62@2+1 | 65@0+1", "a count takes more tracks")
  paw.undo()
  T.keys("gzs2W")
  eq(T.melody(b), "60@0+1 64@0.125+0.875 67@0.25+0.75", "gzs over two bars strums the chord in the second clip")
  paw.undo()
  T.keys("gzd2l")
  eq(T.melody(a), "60@0+0.5 62@0.5+0.5 64@2+1", "only the notes inside the region, here two beats")
  paw.undo()
  paw.cursor.set_beat(4)
  T.keys("v3gzu")
  eq(T.melody(b), "72@0+1 76@0+1 79@0+1", "in visual mode a count: three inversions")
  paw.undo()
  paw.cursor.set_beat(0)
  paw.cmd("key", { "D", "major" })
  api.undo_checkpoint()
  T.keys("gznic")
  eq(T.melody(a), "61@0+1 62@1+1 64@2+1", "gzn snaps to the project's key: C to C#")
  paw.undo()
  paw.undo()
  eq(scale.project(), nil, "the key went with undo")
  T.keys("gzhic")
  eq(T.melody(a) ~= "60@0+1 62@1+1 64@2+1", true, "gzh humanizes")
  local once = T.melody(a)
  paw.undo()
  T.keys("gzhic")
  eq(T.melody(a), once, "the same seed gives the same result")
  paw.undo()
end)

test("musicops: operators and text objects in the vocal editor", function()
  load()
  T.fresh()
  paw.keymap.feed("<Esc><Esc>")
  paw.ui.focus("arrange")
  if not package.loaded["utau"] then paw.ext.load("extensions/utau") end
  local editor = require("utau.editor").editor
  local track = paw.add_track({ name = "Vocal" })
  track:add_device(require("utau").DEVICE)
  local clip = track:add_clip({ start = 0, length = 8, notes = {
    N(60, 0, 1, 100, { lyric = "ka" }), N(62, 1, 1, 100, { lyric = "ki" }), N(64, 2, 1, 100, { lyric = "ku" }),
    N(65, 4, 1, 100, { lyric = "ke" }),
  } })
  paw.cursor.set_track(track)
  paw.cursor.set_beat(0)
  api.undo_checkpoint()
  paw.keymap.feed("<CR>")
  eq(paw.ui.focused, "utau", "the vocal editor is open")
  local function lyrics()
    local out = {}
    for _, n in ipairs(clip:notes()) do out[#out + 1] = n.meta.lyric .. n.pitch end
    return table.concat(out, " ")
  end
  T.keys("gzkip")
  eq(lyrics(), "ka62 ki64 ku65 ke65", "gzkip: the phrase up a step, lyrics kept")
  T.keys(")")
  eq(editor.beat, 4, ") to the next phrase")
  T.keys(".")
  eq(lyrics(), "ka62 ki64 ku65 ke67", ". repeats it there")
  paw.undo()
  paw.undo()
  editor.pitch, editor.beat = 60, 0
  T.keys("gzrip")
  eq(lyrics(), "ku64 ki62 ka60 ke65", "gzr: sung backwards")
  paw.undo()
  T.keys("vip2gzj")
  eq(lyrics(), "ka57 ki59 ku60 ke65", "a visual count")
  paw.undo()
  T.keys("dah")
  eq(lyrics(), "ki62 ku64 ke65", "dah: the note sounding at the cursor")
  paw.undo()
  T.keys("vip<C-a>")
  eq(lyrics(), "ka61 ki63 ku65 ke65", "unlocked, <C-a> on a selection is the editor's own: a semitone")
  paw.undo()
  paw.opt.musicops_scale_lock = true
  T.keys("vip<C-a>")
  eq(lyrics(), "ka62 ki64 ku65 ke65", "locked, a step of the scale")
  paw.undo()
  paw.opt.musicops_scale_lock = false
  paw.keymap.feed("<Esc>")
  paw.ui.hide("utau")
  paw.ui.focus("arrange")
end)

test("musicops: the scale lock keeps entry and transposing in the key", function()
  local clip, roll = roll_with({ N(64, 0, 1), N(67, 1, 1) })
  paw.cmd("key", { "C", "major" })
  api.undo_checkpoint()
  T.keys("<C-a>")
  eq(T.melody(clip), "65@0+1 67@1+1", "unlocked: a semitone")
  paw.undo()
  T.keys("gzL")
  eq(paw.opt.musicops_scale_lock, true, "gzL turns the lock on")
  roll:set(64, 0)
  T.keys("<C-a>")
  eq(T.melody(clip) .. " " .. roll.pitch, "65@0+1 67@1+1 65", "locked: a step of the scale, and the cursor follows")
  T.keys("2<C-a>")
  eq(T.melody(clip), "69@0+1 67@1+1", "with a count")
  paw.undo()
  paw.undo()
  T.keys("0vip<C-x>")
  eq(T.melody(clip), "62@0+1 65@1+1", "on a selection")
  paw.undo()
  roll:set(60, 2)
  paw.opt.octave = 4
  T.keys("IwW<Esc>")
  eq(T.melody(clip), "64@0+1 67@1+1 62@2+0.25 62@2.25+0.25", "C# is entered as D")
  paw.undo()
  roll:set(60, 2)
  T.keys("i2k4l<Esc>")
  eq(T.melody(clip), "64@0+1 67@1+1 64@2+1", "a note drawn moves by steps of the scale: 2k from C is E")
  paw.undo()
  paw.cmd("key", { "A", "minor_pentatonic" })
  roll:set(60, 2)
  T.keys("Iaws<Esc>")
  eq(T.melody(clip), "64@0+1 67@1+1 60@2+0.25 62@2.25+0.25 62@2.5+0.25", "in the project's key")
  paw.undo()
  paw.cmd("musicops.lock", { "off" })
  roll:set(60, 2)
  T.keys("Iw<Esc>")
  eq(T.melody(clip), "64@0+1 67@1+1 61@2+0.25", "unlocked again: chromatic")
  done()
end)

test("musicops: apply a function by command", function()
  local clip = roll_with({ N(60, 0, 1), N(64, 0, 1), N(67, 0, 1) })
  paw.cmd("musicops.apply", { "arpeggiate", mode = "down", step = 0.5 })
  eq(T.melody(clip), "67@0+0.5 64@0.5+0.5", "the clip in the piano roll")
  paw.cmd("musicops.apply", { "transpose_scale", 1, key = "C major" })
  eq(T.melody(clip), "69@0+0.5 65@0.5+0.5", "with a positional argument")
  done()
end)

test("musicops: inverting a unison or a chord at the edge of the range ends and stays in 0..127", function()
  load()
  eq(str(mo.invert({ N(60, 0, 1), N(60, 0, 1) })), "60@0+1 72@0+1", "two equal notes: one goes up an octave")
  eq(str(mo.invert({ N(60, 0, 1), N(60, 0, 1) }, { dir = -1 })), "48@0+1 60@0+1", "and down")
  eq(str(mo.invert({ N(120, 0, 1), N(124, 0, 1) })), "120@0+1 124@0+1", "a note that would pass 127 stays")
  eq(str(mo.invert({ N(3, 0, 1), N(7, 0, 1) }, { dir = -1 })), "3@0+1 7@0+1", "one that would pass 0 stays")
  local clip = roll_with({ N(60, 0, 1), N(60, 0, 1) })
  T.keys("gzuih")
  eq(T.melody(clip), "60@0+1 72@0+1", "gzu on a unison, by keys")
  done()
end)

test("musicops: pitch operators leave drum tracks alone and say so", function()
  local clip, _, t = roll_with({ N(36, 0, 1), N(42, 1, 1) })
  t.meta = { drums = { map = "custom", rows = { { note = 36, name = "Kick" }, { note = 42, name = "Hat" } } } }
  T.keys("gzkip")
  eq(T.melody(clip), "36@0+1 42@1+1", "gzk does not move the kit's sounds")
  eq(paw.ui.message.text:find("drum tracks alone", 1, true) ~= nil, true, "the message says why")
  T.keys("gzoip")
  eq(T.melody(clip), "36@0+1 42@1+1", "nor does gzo")
  T.keys("gzhip")
  eq(T.melody(clip) ~= "36@0+1 42@1+1", true, "humanize still acts on drums")
  done()
end)

test("musicops: legato on ten thousand notes is quick", function()
  load()
  local notes = {}
  for i = 1, 10000 do notes[i] = N(60 + i % 12, (i - 1) * 0.25 + (i % 3) * 0.01, 0.1) end
  local t0 = api.now()
  local out = mo.legato(notes)
  eq(#out, 10000, "every note kept")
  eq(api.now() - t0 < 200, true, "in well under a second: " .. (api.now() - t0) .. " ms")
end)
