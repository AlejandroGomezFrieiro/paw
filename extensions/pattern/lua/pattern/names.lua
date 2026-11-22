-- The words a pattern understands besides note names and numbers: drum names
-- (General MIDI notes) and chord names (semitones above the root). Both are
-- plain tables, so a configuration can add to them or change them:
--
--   require("pattern").drums.kick2 = 35
--   require("pattern").chords.mu = { 0, 2, 4, 7 }
local M = {}

-- A name here wins over a note name, so none of them looks like one (`cb`
-- would be C flat; the cowbell is `cow`). The built-in `drums` device plays
-- 36, 38, 39, 40, 42, 44 and 46; the rest are for General MIDI instruments.
M.drums = {
  bd = 36,
  kick = 36,
  rim = 37,
  rs = 37,
  sn = 38,
  sd = 38,
  snare = 38,
  cp = 39,
  clap = 39,
  sn2 = 40, -- electric snare
  lt = 41, -- low floor tom
  hh = 42,
  ch = 42, -- closed hi-hat
  ft = 43, -- high floor tom
  ph = 44,
  hp = 44, -- pedal hi-hat
  mt = 45, -- low tom
  oh = 46, -- open hi-hat
  lmt = 47, -- low-mid tom
  ht = 48, -- hi-mid tom
  cr = 49,
  crash = 49,
  hit = 50, -- high tom
  rd = 51,
  ride = 51,
  cy = 52, -- Chinese cymbal
  rb = 53, -- ride bell
  tb = 54,
  tamb = 54,
  sp = 55, -- splash
  cow = 56,
  cr2 = 57,
  vs = 58, -- vibraslap
  rd2 = 59,
  cl = 75,
  claves = 75,
  sh = 70,
  maracas = 70,
}

-- Chord shapes, by the names TidalCycles uses and a few short ones.
local shapes = {
  { { "major", "maj", "M" }, { 0, 4, 7 } },
  { { "aug", "plus", "sharp5" }, { 0, 4, 8 } },
  { { "six", "6" }, { 0, 4, 7, 9 } },
  { { "sixNine", "six9", "sixby9", "6by9", "69" }, { 0, 4, 7, 9, 14 } },
  { { "major7", "maj7" }, { 0, 4, 7, 11 } },
  { { "major9", "maj9" }, { 0, 4, 7, 11, 14 } },
  { { "add9", "major9add" }, { 0, 4, 7, 14 } },
  { { "major11", "maj11" }, { 0, 4, 7, 11, 14, 17 } },
  { { "add11" }, { 0, 4, 7, 17 } },
  { { "major13", "maj13" }, { 0, 4, 7, 11, 14, 21 } },
  { { "add13" }, { 0, 4, 7, 21 } },
  { { "dom7", "7" }, { 0, 4, 7, 10 } },
  { { "dom9" }, { 0, 4, 7, 14 } },
  { { "dom11" }, { 0, 4, 7, 17 } },
  { { "dom13" }, { 0, 4, 7, 21 } },
  { { "sevenFlat5", "7f5" }, { 0, 4, 6, 10 } },
  { { "sevenSharp5", "7s5" }, { 0, 4, 8, 10 } },
  { { "sevenFlat9", "7f9" }, { 0, 4, 7, 10, 13 } },
  { { "nine", "9" }, { 0, 4, 7, 10, 14 } },
  { { "eleven", "11" }, { 0, 4, 7, 10, 14, 17 } },
  { { "thirteen", "13" }, { 0, 4, 7, 10, 14, 17, 21 } },
  { { "minor", "min", "m" }, { 0, 3, 7 } },
  { { "diminished", "dim" }, { 0, 3, 6 } },
  { { "minorSharp5", "msharp5", "mS5" }, { 0, 3, 8 } },
  { { "minor6", "min6", "m6" }, { 0, 3, 7, 9 } },
  { { "minorSixNine", "minor69", "min69", "minSixNine", "m69", "mSixNine", "m6by9" }, { 0, 3, 7, 9, 14 } },
  { { "minor7flat5", "min7flat5", "m7flat5", "m7f5" }, { 0, 3, 6, 10 } },
  { { "minorMajor7", "minMaj7", "mmaj7" }, { 0, 3, 7, 11 } },
  { { "diminished7", "dim7" }, { 0, 3, 6, 9 } },
  { { "minor7", "min7", "m7" }, { 0, 3, 7, 10 } },
  { { "minor9", "min9", "m9" }, { 0, 3, 7, 10, 14 } },
  { { "minor11", "min11", "m11" }, { 0, 3, 7, 10, 14, 17 } },
  { { "minor13", "min13", "m13" }, { 0, 3, 7, 10, 14, 17, 21 } },
  { { "one", "1" }, { 0 } },
  { { "five", "5" }, { 0, 7 } },
  { { "sus2" }, { 0, 2, 7 } },
  { { "sus4" }, { 0, 5, 7 } },
  { { "sevenSus2", "7sus2" }, { 0, 2, 7, 10 } },
  { { "sevenSus4", "7sus4" }, { 0, 5, 7, 10 } },
  { { "nineSus4", "ninesus4", "9sus4" }, { 0, 5, 7, 10, 14 } },
  { { "sevenFlat10", "7f10" }, { 0, 4, 7, 10, 15 } },
  { { "minor7sharp9", "m7sharp9", "m7s9" }, { 0, 3, 7, 10, 14 } },
}

M.chords = {}
for _, shape in ipairs(shapes) do
  for _, name in ipairs(shape[1]) do
    M.chords[name] = shape[2]
  end
end

-- Scales for degrees: paw's own, and a few more.
M.scales = setmetatable({
  ionian = { 0, 2, 4, 5, 7, 9, 11 },
  aeolian = { 0, 2, 3, 5, 7, 8, 10 },
  phrygian = { 0, 1, 3, 5, 7, 8, 10 },
  lydian = { 0, 2, 4, 6, 7, 9, 11 },
  mixolydian = { 0, 2, 4, 5, 7, 9, 10 },
  locrian = { 0, 1, 3, 5, 6, 8, 10 },
  harmonic_minor = { 0, 2, 3, 5, 7, 8, 11 },
  melodic_minor = { 0, 2, 3, 5, 7, 9, 11 },
  whole_tone = { 0, 2, 4, 6, 8, 10 },
}, { __index = function(_, name) return paw.music.scales[name] end })

local letters = { c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11 }

--- MIDI number of a note name: a letter, an optional accidental (`#` or `s`
--- sharp, `b` or `f` flat) and an optional octave (4 when left out, so `c`
--- is middle C, 60). Nil for anything else.
function M.note(word)
  local letter, accidental, octave = word:match("^([A-Ga-g])([#sbf]?)(%-?%d*)$")
  if not letter then return nil end
  local pitch = letters[letter:lower()]
  if accidental == "#" or accidental == "s" then pitch = pitch + 1 end
  if accidental == "b" or accidental == "f" then pitch = pitch - 1 end
  if octave == "-" then return nil end
  return (tonumber(octave) or 4) * 12 + 12 + pitch
end

return M
