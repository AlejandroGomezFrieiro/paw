-- The song of "Make music with paw", lesson 1, finished: four bars of
-- drums, bass and keys at 100 BPM, with the loop over them.
--
--   paw -e 'dofile(os.getenv("PAW_HOME") .. "/examples/tutorials/make-music/1-first-song.lua")'
--
-- It is also the practice project of lesson 2. The notes are the notes that
-- the keys of lesson 1 draw (docs/tutorials/make-music/01-first-song.md).
paw.project.tempo = 100

local function note(pitch, start, length) return { pitch = pitch, start = start, length = length } end

-- Kick on 1 and 3, snare on 2 and 4, a closed hi-hat on each eighth.
local beat = {}
for eighth = 0, 7 do
  beat[#beat + 1] = note(42, eighth / 2, 0.25)
end
for _, n in ipairs({ note(36, 0, 0.25), note(38, 1, 0.25), note(36, 2, 0.25), note(38, 3, 0.25) }) do
  beat[#beat + 1] = n
end
local drums = paw.add_part({ name = "Drums" })
drums:add_device("drums")
for bar = 0, 3 do
  drums:add_clip({ name = "beat", start = bar * 4, length = 4, notes = beat })
end

-- A whole note on each root: A, F, C, G.
local bass = paw.add_part({ name = "Bass" })
bass:add_device("synth")
bass:add_clip({
  name = "bass",
  start = 0,
  length = 16,
  notes = {
    note("A2", 0, 4),
    note("F2", 4, 4),
    note("C3", 8, 4),
    note("G2", 12, 4),
  },
})

-- The chords Am, F, C and G, one in each bar.
local keys = paw.add_part({ name = "Keys" })
keys:add_device("synth")
local chords = {}
for bar, chord in ipairs({ { "A3", "C4", "E4" }, { "A3", "C4", "F4" }, { "G3", "C4", "E4" }, { "G3", "B3", "D4" } }) do
  for _, pitch in ipairs(chord) do
    chords[#chords + 1] = note(pitch, (bar - 1) * 4, 4)
  end
end
keys:add_clip({ name = "chords", start = 0, length = 16, notes = chords })

paw.transport.loop_start, paw.transport.loop_end, paw.transport.loop_enabled = 0, 16, true
paw.cursor.set_part(drums)
