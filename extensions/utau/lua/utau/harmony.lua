-- Harmony and double tracks: a second vocal track made from the first.
--
-- The new track goes right under the source, as a copy of it (the voice,
-- every curve, the lyrics and note properties), a little quieter and panned
-- to one side. For a harmony its notes move a diatonic interval in a key:
-- the project's key when one is set (`paw.harmony.project_key`), else the key the melody is in, found with the
-- Krumhansl-Schmuckler profiles. A double sings the same notes with small,
-- repeatable differences: each note's onset moves up to 18 ticks either way
-- (a timing take, kept as the first phoneme's offset), and its tuning up to
-- 8 cents either way.
local api = paw.api
local utau = require("utau")

local M = {}

M.SCALES = {
  major = { 0, 2, 4, 5, 7, 9, 11 },
  minor = { 0, 2, 3, 5, 7, 8, 10 },
}
for name, steps in pairs(paw.music and paw.music.scales or {}) do
  if not M.SCALES[name] then M.SCALES[name] = steps end
end
M.NAMES = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }

-- steps: scale degrees; semis: fixed semitones.
M.INTERVALS = {
  { id = "3up", name = "third above", steps = 2 },
  { id = "3down", name = "third below", steps = -2 },
  { id = "5up", name = "fifth above", steps = 4 },
  { id = "4down", name = "fourth below", steps = -3 },
  { id = "6down", name = "sixth below", steps = -5 },
  { id = "8up", name = "octave above", semis = 12 },
  { id = "8down", name = "octave below", semis = -12 },
  { id = "double", name = "double", semis = 0 },
}
M.INTERVAL = {}
for _, iv in ipairs(M.INTERVALS) do
  M.INTERVAL[iv.id] = iv
end

-- Krumhansl-Kessler key profiles, index 1 = tonic.
M.PROFILES = {
  major = { 6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 },
  minor = { 6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 },
}

local function correlation(x, y)
  local n, mx, my = #x, 0, 0
  for i = 1, n do
    mx, my = mx + x[i], my + y[i]
  end
  mx, my = mx / n, my / n
  local sxy, sxx, syy = 0, 0, 0
  for i = 1, n do
    local dx, dy = x[i] - mx, y[i] - my
    sxy, sxx, syy = sxy + dx * dy, sxx + dx * dx, syy + dy * dy
  end
  if sxx == 0 or syy == 0 then return 0 end
  return sxy / math.sqrt(sxx * syy)
end

--- The key of a melody, `{ { pitch, length }, ... }`: `{ tonic = 0..11, scale = "major" | "minor" }`.
function M.detect_key(list)
  local hist = {}
  for i = 1, 12 do
    hist[i] = 0
  end
  for _, n in ipairs(list) do
    hist[n[1] % 12 + 1] = hist[n[1] % 12 + 1] + (n[2] or 1)
  end
  local best, score
  for _, scale in ipairs({ "major", "minor" }) do
    for tonic = 0, 11 do
      local profile = {}
      for pc = 0, 11 do
        profile[pc + 1] = M.PROFILES[scale][(pc - tonic) % 12 + 1]
      end
      local r = correlation(hist, profile)
      if not score or r > score + 1e-12 then
        best, score = { tonic = tonic, scale = scale }, r
      end
    end
  end
  return best
end

--- `pitch` moved `steps` scale degrees in a key. A note outside the scale
--- keeps its distance from the scale degree below it.
function M.transpose(pitch, steps, key)
  local scale = key.steps or M.SCALES[key.scale] or M.SCALES.major
  local rel = (pitch - key.tonic) % 12
  local base = pitch - rel
  local degree, chroma = 1, 0
  for i = #scale, 1, -1 do
    if scale[i] <= rel then
      degree, chroma = i, rel - scale[i]
      break
    end
  end
  local n = #scale
  local nd = degree - 1 + steps
  local octave = math.floor(nd / n)
  return base + scale[nd - octave * n + 1] + 12 * octave + chroma
end

function M.apply(pitch, iv, key)
  if iv.semis then return pitch + iv.semis end
  return M.transpose(pitch, iv.steps, key)
end

function M.key_name(key) return M.NAMES[key.tonic % 12 + 1] .. " " .. (key.scale or "major") end

local LETTERS = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

--- A key from a name ("D minor", "F#", "Bb major").
function M.parse_key(text)
  local root, scale = tostring(text):match("^%s*([A-Ga-g][#b]?)%s*(.-)%s*$")
  if not root then error("not a key: " .. tostring(text), 0) end
  scale = scale:lower():gsub("[%s%-_]+", "_"):gsub("^_", "")
  if scale == "" or scale == "maj" or scale == "ionian" then scale = "major" end
  if scale == "m" or scale == "min" or scale == "aeolian" then scale = "minor" end
  local steps = M.SCALES[scale]
  if not steps then error("unknown scale `" .. scale .. "`", 0) end
  local pc = LETTERS[root:sub(1, 1):upper()] + (root:sub(2) == "#" and 1 or root:sub(2) == "b" and -1 or 0)
  return { tonic = pc % 12, scale = scale, steps = steps }
end

--- The project's key (`paw.harmony.project_key`), or nil; nil too when
--- its scale is not one of this module's.
function M.project_key()
  local key = paw.harmony.project_key()
  if not key then return nil end
  local ok, mine = pcall(M.parse_key, paw.harmony.key_name(key))
  if ok then return mine end
end

--- The notes of a track as `{ pitch, length }`, rests left out.
local function melody(track_id)
  local list = {}
  for _, c in ipairs(api.clip_list(track_id)) do
    if c.kind == "midi" then
      for _, n in ipairs(api.clip_notes(c.id)) do
        local lyric = n.meta and n.meta.lyric
        if lyric ~= "R" and lyric ~= "r" then list[#list + 1] = { n.pitch, n.length } end
      end
    end
  end
  return list
end

--- The key a harmony of a track is in: the project's, else the melody's.
function M.key_of(track_id)
  local key = M.project_key()
  if key then return key, "project" end
  local list = melody(track_id)
  if #list == 0 then return { tonic = 0, scale = "major" }, "default" end
  return M.detect_key(list), "detected"
end

--- A small number from -1 to 1, the same for the same note and take.
local function wobble(seed, take)
  local s = (seed * 2654435761 + take * 40503) % 4294967296
  s = (s * 1103515245 + 12345) % 2147483648
  local u = s / 2147483648 * 2 - 1
  return u * math.abs(u)
end
M.wobble = wobble

M.TIMING_RANGE = 18 -- ticks either way
M.TUNING_RANGE = 8 -- cents either way

--- Make a harmony or double track of a vocal track. `opts`: `interval`
--- (an id of M.INTERVALS, "3up" by default), `key` (a name; the project's or
--- the melody's when absent), `preset` (a singer preset for the new track),
--- `gain` (dB, -3), `pan` (±0.3), `take` (which variation a double sings, 1).
--- Returns the new track and what was done.
function M.create(track_id, opts)
  opts = opts or {}
  if not utau.device_of(track_id) then error("not a vocal track", 0) end
  local iv = M.INTERVAL[opts.interval or "3up"] or error("no interval `" .. tostring(opts.interval) .. "`", 0)
  local key, source
  if opts.key then
    key, source = M.parse_key(opts.key), "given"
  else
    key, source = M.key_of(track_id)
  end
  local index = 0
  for i, id in ipairs(api.track_list()) do
    if id == track_id then index = i end
  end
  local src = paw.track(track_id)
  local snap = src:snapshot()
  snap.name = string.format("%s (%s)", src.name, iv.name)
  snap.volume = (snap.volume or 0) + (opts.gain or -3)
  local pan = opts.pan
  if pan == nil then pan = (iv.steps or iv.semis or 0) < 0 and -0.3 or 0.3 end
  snap.pan = math.max(-1, math.min(1, (snap.pan or 0) + pan))
  snap.mute = false
  local take = opts.take or 1
  local count = 0
  for _, clip in ipairs(snap.clips) do
    clip.meta = nil -- a new part, not a copy that should take the source's curves again
    for _, n in ipairs(clip.notes or {}) do
      n.pitch = math.max(0, math.min(127, M.apply(n.pitch, iv, key)))
      if iv.id == "double" then
        local seed = math.floor(n.start * 480 + 0.5) * 131 + n.pitch
        n.meta = n.meta or {}
        local props = require("utau.notes").copy(n.meta.utau) or {}
        local tu = (props.tu or 0) + math.floor(wobble(seed, take + 1000) * M.TUNING_RANGE + 0.5)
        props.tu = tu ~= 0 and tu or nil
        local offset = math.floor(wobble(seed, take) * M.TIMING_RANGE + 0.5)
        local ph = {}
        for _, p in ipairs(props.ph or {}) do
          if p.index ~= 0 then ph[#ph + 1] = p end
        end
        if offset ~= 0 then table.insert(ph, 1, { index = 0, offset = offset }) end
        props.ph = #ph > 0 and ph or nil
        n.meta.utau = next(props) and props or nil
      end
      count = count + 1
    end
  end
  local track = paw.restore_track(snap, index + 1)
  if opts.preset then require("utau.singer_presets").apply(track.id, opts.preset) end
  utau.schedule()
  return track, { notes = count, key = key, key_source = source, interval = iv }
end

return M
