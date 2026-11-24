-- A small song to look around in: `paw -e 'dofile("examples/demo-song.lua")'`.
-- Eight bars in A minor, Am F C E twice: drums, a bass line, keys (chords,
-- then a phrase in two voices), a melody over the second half that leaves
-- its last bar open, and a reverb they are sent to.
paw.project.tempo = 108
local function clip(part, start, length, name, notes)
  return part:add_clip({ start = start, length = length, name = name, notes = notes })
end
local function note(pitch, start, length, velocity)
  return { pitch = pitch, start = start, length = length, velocity = velocity }
end

local drums = paw.add_part({ name = "Drums", volume = -2 })
drums:add_device("drums")
for bar = 0, 7 do
  local fill, n = bar % 4 == 3, {}
  if bar % 4 == 0 then n[#n + 1] = note(49, 0, 0.5, 90) end
  for s = 0, 7 do
    local t = s * 0.5
    if s == 0 or s == 4 or s == 5 and not fill then n[#n + 1] = note(36, t, 0.25, 110) end
    if s == 2 or s == 6 and not fill then n[#n + 1] = note(38, t, 0.25, 105) end
    if not (fill and s >= 6) then
      n[#n + 1] = note(s == 7 and bar % 2 == 1 and 46 or 42, t, 0.25, s % 2 == 0 and 92 or 58)
    end
  end
  if fill then
    for i, t in ipairs({ 3, 3.25, 3.5, 3.75 }) do
      n[#n + 1] = note(i < 3 and 38 or 45, t, 0.25, 70 + i * 12)
    end
  end
  clip(drums, bar * 4, 4, fill and "fill" or "beat", n)
end

-- The bass: eighths on the root, up an octave on the off-beats of 2 and 4,
-- the last eighth stepping to the next chord's root.
local bass = paw.add_part({ name = "Bass", volume = -5 })
bass:add_device("synth", { wave = 1, cutoff = 520, release = 0.08 })
local roots, names = { 33, 29, 36, 28 }, { "Am", "F", "C", "E" }
for bar = 0, 7 do
  local r, nextr, n = roots[bar % 4 + 1], roots[(bar + 1) % 4 + 1], {}
  for s = 0, 7 do
    local p = (s == 3 or s == 5) and r + 12 or r
    if s == 7 then p = nextr + (nextr > r and -1 or 2) end
    n[#n + 1] = note(p, s * 0.5, 0.42, s % 2 == 0 and 100 or 78)
  end
  clip(bass, bar * 4, 4, names[bar % 4 + 1], n)
end

-- The keys: the chords held in the first half; in the second a phrase in two
-- voices, a line moving over a held C (a B under E).
local keys = paw.add_part({ name = "Keys", volume = -9, pan = -0.3 })
keys:add_device("synth", { wave = 3, attack = 0.02, release = 0.5, cutoff = 3000 })
keys:add_device("delay", { time = 417, feedback = 0.3, mix = 0.18 })
local chords = { { 57, 60, 64 }, { 57, 60, 65 }, { 55, 60, 64 }, { 56, 59, 64 } }
local n = {}
for bar = 0, 3 do
  for _, p in ipairs(chords[bar + 1]) do
    n[#n + 1] = note(p, bar * 4, 2.5, 78)
    n[#n + 1] = note(p, bar * 4 + 2.5, 1.5, 64)
  end
end
clip(keys, 0, 16, "chords", n)
n = {}
local lines = { { 64, 69, 72, 69 }, { 65, 69, 72, 69 }, { 64, 67, 72, 67 }, { 64, 68, 71, 68 } }
for bar = 0, 3 do
  n[#n + 1] = note(bar == 3 and 59 or 60, bar * 4, 4, 70)
  for b, p in ipairs(lines[bar + 1]) do
    n[#n + 1] = note(p, bar * 4 + b - 1, 1, b == 1 and 84 or 72)
  end
end
clip(keys, 16, 16, "phrase", n)

-- The melody, as it was played: a three-bar phrase and a bar left open.
local lead = paw.add_part({ name = "Lead", volume = -7, pan = 0.2 })
lead:add_device("synth", { wave = 2, cutoff = 2200, attack = 0.01, release = 0.25 })
local tune = {
  { 76, 0, 1 },
  { 74, 1, 0.5 },
  { 72, 1.5, 0.5 },
  { 74, 2, 1 },
  { 76, 3, 1 },
  { 72, 4, 1.5 },
  { 69, 5.5, 0.5 },
  { 69, 6, 2 },
  { 67, 8, 1 },
  { 72, 9, 1 },
  { 76, 10, 1 },
  { 79, 11, 1 },
}
n = {}
for i, t in ipairs(tune) do
  n[i] = note(t[1], t[2], t[3] * 0.9, 64 + (i * 23) % 36)
end
clip(lead, 16, 16, "melody", n)
lead:automate("volume"):set_points({ { 14, -20 }, { 16, -7 }, { 28, -7 }, { 32, -12 } })

local verb = paw.add_part({ name = "Reverb" })
verb:add_device("reverb", { size = 0.7, decay = 2.2, mix = 1 })
lead:send(verb, -10)
keys:send(verb, -14)
drums:send(verb, -24)
paw.transport.loop_start, paw.transport.loop_end = 0, 32
paw.cursor.set_part(keys)
paw.flush()

-- Given a path, render the song to it: `paw -l examples/demo-song.lua song.wav`.
local out = ...
if out then
  local info = paw.render(out, { tail = 2 })
  print(string.format("wrote %s: %.1f s, peak %.1f dB", out, info.seconds, 20 * math.log10(info.peak)))
end
