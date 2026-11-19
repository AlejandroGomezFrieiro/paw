-- `paw.harmony`: which chords and which key sound at each moment of the song,
-- over every pitched track, and the theory to work with them (keys, scales,
-- chord names, Roman numerals, voicings, an instrument's range).
--
--   paw.harmony.chords(0, 16)     --> { { at = 0, length = 4, root = 9, quality = "min", name = "Am", roman = "i", ... }, ... }
--   paw.harmony.at(8)  paw.harmony.next(8)  paw.harmony.prev(8)
--   paw.harmony.key(8)            --> { tonic = 9, mode = "minor", name = "A minor", ... }
--   paw.harmony.provide("my-server", function(from, to) return chords, keys end, 100)
--
-- The reading comes from providers: the highest-priority one that answers
-- wins. The built-in one (`paw.harmony.read`) reads the notes themselves; a
-- language server can answer instead. A reading is kept until the project
-- changes, so asking on every key press costs nothing. `harmony.changed` is
-- emitted when it changes.
local api = paw.api
local read = require("paw.harmony.read")
local M = { read = read, voice = require("paw.harmony.voice") }

paw.option.define("chords", "names", { type = { "string", "boolean" }, values = { "names", "roman", "both", false } }) -- chord symbols in the piano roll's ruler: "names", "roman", "both" or false
paw.option.define("harmony_step", 0.5)        -- beats: the shortest chord the built-in reading finds is about twice this

-- Theory: pitch classes, keys and scales -------------------------------------------

local SHARPS = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local FLATS = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
-- Without a key: the names most often written.
local PLAIN = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }
local LETTERS = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

--- Every scale known by name, as semitones above the root.
M.scales = {
  major = { 0, 2, 4, 5, 7, 9, 11 },
  minor = { 0, 2, 3, 5, 7, 8, 10 },
  harmonic_minor = { 0, 2, 3, 5, 7, 8, 11 },
  melodic_minor = { 0, 2, 3, 5, 7, 9, 11 },
  dorian = { 0, 2, 3, 5, 7, 9, 10 },
  phrygian = { 0, 1, 3, 5, 7, 8, 10 },
  lydian = { 0, 2, 4, 6, 7, 9, 11 },
  mixolydian = { 0, 2, 4, 5, 7, 9, 10 },
  locrian = { 0, 1, 3, 5, 6, 8, 10 },
  pentatonic = { 0, 2, 4, 7, 9 },
  minor_pentatonic = { 0, 3, 5, 7, 10 },
  blues = { 0, 3, 5, 6, 7, 10 },
  whole_tone = { 0, 2, 4, 6, 8, 10 },
  chromatic = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 },
}
for name, steps in pairs(paw.music.scales) do
  if not M.scales[name] then M.scales[name] = steps end
end
local ALIASES = { ionian = "major", aeolian = "minor", maj = "major", min = "minor", m = "minor" }
-- Scales whose third is minor, for naming and numerals.
local MINORISH = { minor = true, harmonic_minor = true, melodic_minor = true, dorian = true, phrygian = true,
  locrian = true, minor_pentatonic = true, blues = true }

--- Names of the known scales, sorted.
function M.scale_names()
  local out = {}
  for name in pairs(M.scales) do out[#out + 1] = name end
  table.sort(out)
  return out
end

--- A pitch class (0..11) from a name such as "C", "f#", "Bb", or a number.
function M.pitch_class(name)
  if type(name) == "number" then return name % 12 end
  local letter, accidental = tostring(name):match("^([A-Ga-g])([#b]?)$")
  if not letter then error("not a key root: " .. tostring(name), 2) end
  return (LETTERS[letter:upper()] + (accidental == "#" and 1 or accidental == "b" and -1 or 0)) % 12
end

--- Whether a key is written with flats: F, Bb, Eb, Ab, Db, Gb major and
--- their relative minors and modes.
local function flat_key(key)
  -- The major key with the same signature: a mode's tonic less its degree.
  local steps = M.scales[key.scale]
  local offset = 0
  if key.scale ~= "major" and steps then
    offset = ({ minor = 9, dorian = 2, phrygian = 4, lydian = 5, mixolydian = 7, locrian = 11,
      harmonic_minor = 9, melodic_minor = 9, minor_pentatonic = 9, blues = 9 })[key.scale] or 0
  end
  local major = (key.root - offset) % 12
  return major == 5 or major == 10 or major == 3 or major == 8 or major == 1 or major == 6
end

--- The name of a pitch class: spelled as `key` writes it (sharps or
--- flats), else the names most often written (C#, Eb, F#, Ab, Bb).
function M.pc_name(pc, key)
  pc = pc % 12
  if not key then return PLAIN[pc + 1] end
  key = M.parse_key(key)
  if key.root == 0 and (key.scale == "major" or key.scale == "lydian" or key.scale == "mixolydian") then return PLAIN[pc + 1] end
  return (flat_key(key) and FLATS or SHARPS)[pc + 1]
end

local function make_key(root, scale)
  local steps = M.scales[scale]
  local key = { root = root, scale = scale, steps = steps, tonic = root, mode = scale }
  key.name = M.key_name(key)
  return key
end

--- A key from a name ("D minor", "F# dorian", "Bb") or a table
--- (`{ root = "D", scale = "minor" }`, `{ tonic = 2, mode = "minor" }`, or a
--- key). A key is `{ tonic, mode, name, root = tonic, scale = mode, steps }`.
function M.parse_key(spec)
  if type(spec) == "table" then
    if spec.steps and spec.root then return spec end
    local root = spec.root or spec.tonic
    return M.parse_key((root and SHARPS[M.pitch_class(root) + 1] or "C") .. " " .. (spec.scale or spec.mode or "major"))
  end
  local root, scale = tostring(spec):match("^%s*(%S+)%s*(.-)%s*$")
  if not root then error("not a key: " .. tostring(spec), 2) end
  scale = scale:lower():gsub("[%s%-]+", "_")
  if scale == "" then scale = "major" end
  scale = ALIASES[scale] or scale
  if not M.scales[scale] then error("unknown scale `" .. scale .. "`; known: " .. table.concat(M.scale_names(), " "), 2) end
  return make_key(M.pitch_class(root), scale)
end

--- "D minor", "Bb major": the tonic spelled as its key writes it.
function M.key_name(key)
  if not key.steps then key = M.parse_key(key) end
  local root = (key.root == 0 or not flat_key(key)) and (key.root == 0 and "C" or SHARPS[key.root + 1]) or FLATS[key.root + 1]
  -- D# minor and A# minor are written Eb and Bb more often than not.
  if not flat_key(key) and (key.root == 3 or key.root == 10) and MINORISH[key.scale] then root = FLATS[key.root + 1] end
  return root .. " " .. key.scale
end

local function member(key, pitch)
  local rel = (pitch - key.root) % 12
  for i, s in ipairs(key.steps) do
    if s == rel then return i end
  end
end

--- True if a pitch (or pitch class) is in a key.
function M.in_key(key, pitch)
  return member(M.parse_key(key), pitch) ~= nil
end

--- The pitch of the key nearest to `pitch`: `dir` "nearest" (the default;
--- halfway between two goes up), "up" or "down". Stays within 0..127.
function M.snap(key, pitch, dir)
  key = M.parse_key(key)
  dir = dir or "nearest"
  if member(key, pitch) then return pitch end
  for d = 1, 12 do
    local up, down = pitch + d, pitch - d
    if dir ~= "down" and up <= 127 and member(key, up) then return up end
    if dir ~= "up" and down >= 0 and member(key, down) then return down end
  end
  return pitch
end

--- A pitch as an absolute scale degree (0 is the root in octave -1) and the
--- semitones it lies above that degree (non-zero for notes outside it).
function M.degree(key, pitch)
  key = M.parse_key(key)
  local below = pitch
  while not member(key, below) do below = below - 1 end
  local octave = math.floor((below - key.root) / 12)
  return octave * #key.steps + member(key, below) - 1, pitch - below
end

--- The pitch of an absolute scale degree.
function M.degree_pitch(key, degree)
  key = M.parse_key(key)
  local n = #key.steps
  return key.root + key.steps[degree % n + 1] + 12 * math.floor(degree / n)
end

--- Move a pitch by `n` scale degrees. A pitch outside the key keeps its
--- distance from the scale note below it.
function M.step(key, pitch, n)
  local degree, offset = M.degree(key, pitch)
  return M.degree_pitch(key, degree + n) + offset
end

-- The project's key ----------------------------------------------------------------
--
-- Kept in the project as `project.key`, its name as `M.key_name` gives it
-- (`"D minor"`), and read back with `M.parse_key`.

--- The key set for the project, or nil when none is.
function M.project_key()
  local name = api.project_get().key
  if name then return M.parse_key(name) end
end

--- Set the project's key (one edit), or clear it with nil. Returns the key.
function M.set_key(spec)
  local key = spec ~= nil and M.parse_key(spec) or nil
  api.project_set("key", key and M.key_name(key) or nil)
  return key
end

-- Chord names --------------------------------------------------------------------

-- Other names providers give qualities.
local ALIAS = { major = "maj", minor = "min", M = "maj", m = "min", dom7 = "7", dominant7 = "7", ["dom"] = "7",
  maj7 = "maj7", min7 = "m7", ["half-dim"] = "m7b5", hdim7 = "m7b5", ["m7b5"] = "m7b5", diminished = "dim",
  augmented = "aug", dim7 = "dim7", ["min7b5"] = "m7b5", ["5"] = "5", power = "5" }

local ROMAN = { "I", "bII", "II", "bIII", "III", "IV", "#IV", "V", "bVI", "VI", "bVII", "VII" }

--- A chord's symbol: "G7", "F/A", "Bbmaj7", spelled as `key` writes it.
function M.chord_name(chord, key)
  local q = read.by_quality[chord.quality]
  local root = M.pc_name(chord.root, key)
  -- A diminished chord outside the key leads up to the note above its
  -- root, which is named as that note's leading note: G#dim7 to A minor.
  local dim = chord.quality == "dim" or chord.quality == "dim7" or chord.quality == "m7b5"
  if dim and not (key and M.in_key(key, chord.root)) then root = SHARPS[chord.root % 12 + 1] end
  local name = root .. (q and q.suffix or chord.quality)
  if chord.bass and chord.bass ~= chord.root then name = name .. "/" .. M.pc_name(chord.bass, key) end
  return name
end

--- The Roman numeral of a chord in `key`, counted from the tonic as in the
--- major scale ("bVII", "vi", "V7", "ii°"). The name shows an inversion as "V7/B".
function M.chord_roman(chord, key)
  key = M.parse_key(key)
  local q = read.by_quality[chord.quality] or {}
  local numeral = ROMAN[(chord.root - key.root) % 12 + 1]
  if q.minor then numeral = numeral:lower() end
  return numeral .. (q.roman or "")
end

--- A chord from its symbol: "G7", "F#m7b5", "C/E", "Bbmaj7". Nil when it
--- is not one.
function M.parse_chord(text)
  local root, rest = tostring(text):match("^([A-Ga-g][#b]?)(.*)$")
  if not root then return nil end
  local bass
  rest = rest:gsub("/([A-Ga-g][#b]?)$", function(b) bass = b return "" end)
  for _, q in ipairs(read.qualities) do
    if q.suffix == rest then
      local chord = { root = M.pitch_class(root), quality = q.name, tones = {} }
      chord.bass = bass and M.pitch_class(bass) or chord.root
      for i, s in ipairs(q.steps) do chord.tones[i] = (chord.root + s) % 12 end
      chord.name = M.chord_name(chord)
      return chord
    end
  end
end

--- The pitch classes of a chord of `quality` on `root`, root first.
function M.tones(root, quality)
  local q = assert(read.by_quality[quality], "unknown chord quality " .. tostring(quality))
  local out = {}
  for i, s in ipairs(q.steps) do out[i] = (root + s) % 12 end
  return out
end

-- Instruments' ranges --------------------------------------------------------------

-- Words in a track's name, or its devices', and the range a part for it is
-- written in: comfortable rather than the instrument's whole compass, so
-- that chords written for it sit where it sounds well. As MIDI LSP guesses.
M.ranges = {
  { words = { "piccolo" }, low = 74, high = 103 },
  { words = { "flute" }, low = 60, high = 91 },
  { words = { "oboe" }, low = 58, high = 86 },
  { words = { "clarinet" }, low = 50, high = 86 },
  { words = { "bassoon" }, low = 34, high = 70 },
  { words = { "horn" }, low = 41, high = 72 },
  { words = { "trumpet" }, low = 55, high = 79 },
  { words = { "trombone" }, low = 40, high = 70 },
  { words = { "tuba" }, low = 28, high = 55 },
  { words = { "violin" }, low = 55, high = 91 },
  { words = { "viola" }, low = 48, high = 79 },
  { words = { "cello" }, low = 36, high = 67 },
  { words = { "contrabass", "double bass" }, low = 28, high = 55 },
  { words = { "soprano" }, low = 60, high = 79 },
  { words = { "alto" }, low = 55, high = 74 },
  { words = { "tenor" }, low = 48, high = 67 },
  { words = { "baritone" }, low = 43, high = 62 },
  { words = { "choir", "vox", "vocal", "voice", "singer" }, low = 48, high = 76 },
  { words = { "bass" }, low = 28, high = 55 },
  { words = { "guitar", "gtr" }, low = 40, high = 76 },
  { words = { "lead" }, low = 60, high = 88 },
  { words = { "piano", "keys", "rhodes", "organ", "pad", "strings", "synth", "chords" }, low = 48, high = 84 },
}
M.default_range = { low = 48, high = 84 }   -- C3 to C6

--- The range of a part for a track, `{ low, high, name }`. This is the
--- range of the track (`track.meta.range = { low, high }`). If not, paw
--- guesses it from the words of its name and the names of its devices. If
--- not, it is C3 to C6.
function M.range(track)
  local t = type(track) == "table" and track.get and track:get() or type(track) == "number" and api.track_get(track) or track
  if not t then return M.default_range end
  local own = type(t.meta) == "table" and t.meta.range
  if type(own) == "table" and own.low and own.high then return { low = own.low, high = own.high, name = "set" } end
  local texts = { (t.name or ""):lower() }
  for _, id in ipairs(t.devices or {}) do
    local ok, d = pcall(api.device_get, id)
    if ok then texts[#texts + 1] = ((d.name or "") .. " " .. (d.kind or "")):lower() end
  end
  for _, text in ipairs(texts) do
    for _, r in ipairs(M.ranges) do
      for _, word in ipairs(r.words) do
        if text:find(word, 1, true) then return { low = r.low, high = r.high, name = word } end
      end
    end
  end
  return M.default_range
end

--- True if the harmony does not use a track: a drum track (a drum map in
--- its meta, as the drums extension keeps it, or a drum device or name).
function M.is_drums(track)
  local t = type(track) == "number" and api.track_get(track) or track
  if type(t.meta) == "table" and t.meta.drums then return true end
  local name = (t.name or ""):lower()
  for _, word in ipairs({ "drum", "perc", "kit", "beat" }) do
    if name:find(word, 1, true) then return true end
  end
  for _, id in ipairs(t.devices or {}) do
    local ok, d = pcall(api.device_get, id)
    if ok and d.kind == "drums" then return true end
  end
  return false
end

-- The song's notes and the reading ----------------------------------------------------

local notes_cache = {}
--- Each note of the pitched tracks, in project beats, each with `track` and
--- `clip`. The list does not contain muted clips and tracks, or notes that a
--- trim of the edges of the clip hides. paw keeps the list until the project
--- changes. This is what sounds, for the reading and for snippets. The
--- context notes of the piano roll, `paw.roll_clips.context`, are what the
--- roll shows, in its own beats, and only of the tracks selected to show.
function M.notes()
  local edits = api.project_get("edits")
  if notes_cache.edits == edits then return notes_cache.notes end
  local out = {}
  for _, id in ipairs(api.track_list()) do
    local t = api.track_get(id)
    if not t.mute and not M.is_drums(t) then
      for _, c in ipairs(api.clip_list(id)) do
        if c.kind == "midi" and not c.muted then
          for _, n in ipairs(api.clip_notes(c.id)) do
            if n.start >= 0 and n.start < c.length then
              out[#out + 1] = {
                pitch = n.pitch, start = c.start + n.start, length = math.min(n.length, c.length - n.start),
                velocity = n.velocity, track = id, clip = c.id,
              }
            end
          end
        end
      end
    end
  end
  notes_cache.edits, notes_cache.notes = edits, out
  return out
end

--- Bar starts from the first bar to past `last`, by the tempo map.
local function bar_starts(last)
  local bars, n = {}, 1
  repeat
    bars[#bars + 1] = paw.time.bar_start(n)
    n = n + 1
  until bars[#bars] > last or n > 100000
  return bars
end

--- The built-in provider: chords and keys read from the notes.
function M.builtin(from, to)
  local notes = M.notes()
  local last = 0
  for _, n in ipairs(notes) do last = math.max(last, n.start + n.length) end
  local chords = read.chords(notes, { from = from, to = to, step = paw.opt.harmony_step, bar = paw.time.bar(0) })
  local keys = read.keys(notes, bar_starts(last), chords)
  return chords, keys
end

local providers = { { name = "builtin", fn = M.builtin, priority = 0 } }
local cache = { stamp = nil }
local last_text   -- the last reading in words, to tell when it changes

--- Add a provider. `fn(from, to)` returns chords and keys, or nil to let
--- the next provider answer. The lists have the shapes that `chords` and
--- `key` give. `root`, `quality`, `at` and `length` are enough for a chord.
--- `at`, `length`, `tonic` and `mode` are enough for a key. The highest
--- `priority` (default 50) answers first. A new provider with the same
--- name replaces the old one. `fn` nil removes it.
function M.provide(name, fn, priority)
  for i = #providers, 1, -1 do
    if providers[i].name == name then table.remove(providers, i) end
  end
  if fn then providers[#providers + 1] = { name = name, fn = fn, priority = priority or 50 } end
  table.sort(providers, function(a, b) return a.priority > b.priority end)
  M.invalidate()
end

--- Forget the reading: a provider whose answer changed calls this.
function M.invalidate()
  cache.stamp = nil
  M.schedule()
end

--- Fill in what a chord or key from a provider may leave out.
local function complete_key(k)
  local key = M.parse_key({ root = k.tonic or k.root, scale = k.mode or k.scale })
  return { at = k.at, length = k.length, tonic = key.root, mode = key.scale, name = key.name, root = key.root, scale = key.scale, steps = key.steps }
end

local function signature()
  local stamp = api.project_get("edits")
  local parts = { tostring(stamp), tostring(paw.opt.harmony_step) }
  for _, p in ipairs(providers) do parts[#parts + 1] = p.name end
  return table.concat(parts, "|")
end

--- True if the reading agrees with the project, so `key` and `chords` answer
--- immediately. A view that paw draws on each key asks this first, because
--- to read a long song again takes some time.
function M.fresh() return cache.stamp == signature() end

--- The whole song's reading: `{ chords, keys, provider }`.
local function reading()
  local sig = signature()
  if cache.stamp == sig then return cache end
  -- The highest-priority provider that answers wins over the stretch its
  -- answer covers; the ones below fill in the rest of the song (a language
  -- server hears the clip it is sent, the built-in reading everything).
  local chords, keys, by, covered = {}, {}, nil, {}
  -- What of `x` lies outside the stretches covered already: the longer
  -- piece left, or nil.
  local function free(x)
    local a, z = x.at, x.at + x.length
    for _, span in ipairs(covered) do
      if a < span[2] - 1e-9 and z > span[1] + 1e-9 then
        if span[1] - a >= z - span[2] then z = math.min(z, span[1]) else a = math.max(a, span[2]) end
      end
    end
    if z - a < 1e-9 then return nil end
    if a == x.at and z == x.at + x.length then return x end
    local cut = {}
    for k, v in pairs(x) do cut[k] = v end
    cut.at, cut.length = a, z - a
    return cut
  end
  for _, p in ipairs(providers) do
    local ok, c, k = pcall(p.fn, 0, math.huge)
    if ok and c then
      by = by or p.name
      local from, to = math.huge, -math.huge
      for _, chord in ipairs(c) do
        chords[#chords + 1] = free(chord)
        from, to = math.min(from, chord.at), math.max(to, chord.at + chord.length)
      end
      for _, key in ipairs(k or {}) do
        keys[#keys + 1] = free(key)
        from, to = math.min(from, key.at), math.max(to, key.at + key.length)
      end
      if to > from then covered[#covered + 1] = { from, to } end
    elseif not ok then
      paw.notify("harmony provider " .. p.name .. ": " .. tostring(c), "warn")
    end
  end
  local set = M.project_key()
  local full = {}
  for i, k in ipairs(keys) do full[i] = complete_key(k) end
  table.sort(full, function(a, b) return a.at < b.at end)
  local list = {}
  for _, c in ipairs(chords) do
    -- What the provider says is kept (a server's `function`, `cadence`,
    -- its own name and numeral); what it leaves out is filled in.
    local chord = {}
    for k, v in pairs(c) do chord[k] = v end
    chord.root = M.pitch_class(c.root)
    chord.bass = M.pitch_class(c.bass or c.root)
    chord.quality = read.by_quality[c.quality] and c.quality or ALIAS[c.quality] or c.quality
    if not chord.tones then
      chord.tones = read.by_quality[chord.quality] and M.tones(chord.root, chord.quality) or { chord.root }
    end
    list[#list + 1] = chord
  end
  table.sort(list, function(a, b) return a.at < b.at end)
  cache = { stamp = sig, chords = list, keys = full, set = set, provider = by }
  local parts = {}
  for _, chord in ipairs(list) do
    local key = M.key(chord.at)
    chord.name = chord.name or M.chord_name(chord, key)
    chord.roman = chord.roman or M.chord_roman(chord, key)
    parts[#parts + 1] = string.format("%g:%g:%s", chord.at, chord.length, chord.name)
  end
  for _, k in ipairs(full) do parts[#parts + 1] = string.format("%g:%s", k.at, k.name) end
  parts[#parts + 1] = set and set.name or ""
  -- Listeners hear of a reading that differs from the one before.
  local text = table.concat(parts, " ")
  if last_text and text ~= last_text then paw.emit("harmony.changed", { provider = by }) end
  last_text = text
  return cache
end

--- The key at `beat` (the start when nil): the project's when one is set,
--- else the one read there, else C major. `{ tonic, mode, name, ... }`.
function M.key(beat)
  local r = cache.stamp == signature() and cache or reading()
  if r.set then return r.set end
  beat = beat or 0
  local found
  for _, k in ipairs(r.keys) do
    if k.at <= beat + 1e-9 then found = k end
  end
  found = found or r.keys[1]
  if found then return found end
  return M.parse_key("C major")
end

--- The keys read over the song, `{ at, length, tonic, mode, name }` each.
--- When the project has its own key, that key is over all of the song.
function M.keys()
  local r = reading()
  if r.set then
    local key = complete_key(r.set)
    key.at, key.length = 0, math.huge
    return { key }
  end
  return r.keys
end

--- The chords that sound between `from` and `to` (project beats; all of
--- them when nil), in time order.
function M.chords(from, to)
  local out = {}
  for _, c in ipairs(reading().chords) do
    if (not to or c.at < to) and (not from or c.at + c.length > from) then out[#out + 1] = c end
  end
  return out
end

--- The chord that sounds at `beat`, or nil.
function M.at(beat)
  for _, c in ipairs(reading().chords) do
    if c.at <= beat + 1e-9 and beat < c.at + c.length - 1e-9 then return c end
  end
end

--- The first chord that starts after `beat`.
function M.next(beat)
  for _, c in ipairs(reading().chords) do
    if c.at > beat + 1e-9 then return c end
  end
end

--- The last chord that starts before `beat` and is not the one at it.
function M.prev(beat)
  local found
  local here = M.at(beat)
  for _, c in ipairs(reading().chords) do
    if c.at < beat - 1e-9 and c ~= here then found = c end
  end
  return found
end

--- The provider the current reading came from.
function M.provider()
  return reading().provider
end

--- A chord's label as `paw.opt.chords` (or `how`) asks: its name, its
--- numeral, or both ("G7 V7").
function M.label(chord, how)
  how = how or paw.opt.chords
  if how == "roman" then return chord.roman end
  if how == "both" then return chord.name .. " " .. chord.roman end
  return chord.name
end

--- Draw the chords on a row of cells. `buf` is one row high, and shows
--- `span` beats from `scroll` at `zoom` columns for each beat. Beats count
--- from `origin` (the start of a clip, or 0 for the song). Each symbol
--- starts on the left edge of the cell where its chord starts. It stops
--- where the next symbol starts. The labels are as `paw.opt.chords` (or
--- `how`) tells.
function M.draw(buf, scroll, span, zoom, origin, how)
  how = how or paw.opt.chords
  if not how then return end
  local list = M.chords(origin + scroll, origin + scroll + span)
  local g = paw.draw.g
  for i, c in ipairs(list) do
    local x0 = math.floor((c.at - origin - scroll) * zoom + 0.5)
    local nxt = list[i + 1]
    local x1 = nxt and math.floor((nxt.at - origin - scroll) * zoom + 0.5) or buf.width
    local label = M.label(c, how)
    if x0 < 0 then
      -- Begun before the view: named at its left edge if there is room.
      x0 = 0
      if x1 - x0 < api.str_width(label) + 1 then label = "" end
    end
    if x1 > x0 then
      buf:text(x0, 0, g.beat, "RulerChordEdge")
      if label ~= "" then buf:text(x0 + 1, 0, paw.util.fit(label, math.max(0, math.min(api.str_width(label), x1 - x0 - 1))), "RulerChord") end
    end
  end
end

local pending
--- Some time after the project changes, paw makes the reading again. So
--- `harmony.changed` comes even when nothing asks.
function M.schedule()
  if pending then return end
  pending = paw.defer(function()
    pending = nil
    reading()
  end, 30)
end
paw.on("changed", function() M.schedule() end)

return M
