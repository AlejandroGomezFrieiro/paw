-- A short song for the render tests (tests/media.lua, tests/flac.lua).
-- Their reference samples come from this song: do not change it. The demo
-- song for people is examples/demo-song.lua.
local paw = require("paw")
local music = paw.music

paw.project.new()
paw.project.name = "demo"
paw.project.tempo = 112

-- Drums: a pattern written as text, one character per 16th note.
local drums = paw.add_track({ name = "Drums" })
drums:add_device("drums")
local function pattern(rows, bars)
  local notes = {}
  for pitch, steps in pairs(rows) do
    for bar = 0, bars - 1 do
      for i = 1, #steps do
        local ch = steps:sub(i, i)
        if ch ~= "." then
          notes[#notes + 1] = {
            pitch = pitch,
            start = bar * 4 + (i - 1) * 0.25,
            length = 0.25,
            velocity = ch == "X" and 120 or 80,
          }
        end
      end
    end
  end
  return notes
end
local beat =
  { [36] = "X.....x...X.....", [38] = "....X.......X..x", [42] = "x.x.x.x.x.x.x.x.", [46] = "..............x." }
for bar = 0, 3 do
  drums:add_clip({ name = "beat", start = bar * 8, length = 8, notes = pattern(beat, 2) })
end

-- Bass: the root of each chord, in eighth notes.
local bass = paw.add_track({ name = "Bass", volume = -4 })
bass:add_device("synth", { wave = 2, cutoff = 500, resonance = 0.3, release = 0.08, sustain = 0.8 })
local roots = { "A1", "F1", "C2", "G1" }
for i, root in ipairs(roots) do
  local notes = {}
  for step = 0, 15 do
    local octave = (step % 4 == 3) and 12 or 0
    notes[#notes + 1] = { pitch = music.pitch(root) + octave, start = step * 0.5, length = 0.4 }
  end
  bass:add_clip({ name = root, start = (i - 1) * 8, length = 8, notes = notes })
end

-- Lead: walk up and down A minor pentatonic, through a delay.
local lead = paw.add_track({ name = "Lead", volume = -8, pan = 0.2 })
lead:add_device("synth", { wave = 1, cutoff = 2400, attack = 0.01, release = 0.3 })
lead:add_device("delay", { time = 60000 / 112 * 0.75, feedback = 0.4, mix = 0.3 })
local degrees = { 1, 3, 4, 5, 4, 3, 5, 6, 8, 6, 5, 4, 3, 4, 1, 1 }
local notes = {}
for i, degree in ipairs(degrees) do
  notes[i] = { pitch = music.degree("A4", "minor_pentatonic", degree), start = (i - 1) * 1, length = 0.9 }
end
lead:add_clip({ name = "melody", start = 16, length = 16, notes = notes })

-- Pads: a chord per two bars, sent through a bus with its own fader.
local bus = paw.add_track({ name = "Pad bus", volume = -10 })
local pad = paw.add_track({ name = "Pad", output = bus, index = 4 })
pad:add_device("synth", { wave = 3, attack = 0.4, release = 0.8, cutoff = 1500 })
local chords = { { "A3", "C4", "E4" }, { "F3", "A3", "C4" }, { "C3", "E3", "G3" }, { "G3", "B3", "D4" } }
for i, chord in ipairs(chords) do
  local held = {}
  for _, pitch in ipairs(chord) do
    held[#held + 1] = { pitch = pitch, start = 0, length = 8, velocity = 70 }
  end
  pad:add_clip({ name = "chord", start = (i - 1) * 8, length = 8, notes = held })
end

paw.transport.loop_start, paw.transport.loop_end = 0, 32

-- Given a path, render instead of leaving the project open.
local out = ...
if out then
  local info = paw.render(out, { tail = 2 })
  print(string.format("wrote %s: %.1f s, peak %.1f dB", out, info.seconds, 20 * math.log10(info.peak)))
end
