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
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local util = require("paw.util")
local read = require("paw.harmony.read")
local voice = require("paw.harmony.voice")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type MusicModule = require("paw.music")
local type ReadModule = require("paw.harmony.read")
local type VoiceModule = require("paw.harmony.voice")

--- A key: its tonic (`root`, a pitch class) and its scale (`mode`), with
--- the scale's steps above the tonic and its name ("D minor"). A key that
--- the reading found has the stretch of the song it is over: `at` and
--- `length` in project beats.
local record Key
  root: integer
  scale: string
  steps: {integer}
  tonic: integer
  mode: string
  name: string
  at: number
  length: number
end

--- What may stand for a key: its name ("D minor", "F# dorian", "Bb") or a
--- key. Lua gives `{ root = "D", scale = "minor" }` too.
local type KeyArg = string | Key

--- What every stretch of the reading has: where it starts and how long it is.
local interface Span
  at: number
  length: number
end

--- A chord that sounds: pitch classes 0..11, its symbol (`name`) and its
--- numeral in the key there (`roman`).
local record Chord is Span
  root: integer
  bass: integer
  quality: string
  tones: {integer}
  name: string
  roman: string
end

--- A chord as a provider gives it: `root`, `quality`, `at` and `length`
--- are enough, and a root or bass may be a name ("A", "F#"). The other
--- fields that it gives are kept.
local record ProvidedChord is Span
  root: integer | string
  bass: integer | string
  quality: string
  tones: {integer}
  name: string
  roman: string
end

--- A key as a provider gives it: `at`, `length`, `tonic` and `mode` are
--- enough, or `root` and `scale`.
local record ProvidedKey is Span
  tonic: integer | string
  mode: string
  root: integer | string
  scale: string
end

--- Reads chords and keys between two project beats: the lists, or nil to
--- let the next provider answer.
local type ProviderFn = function(from: number, to: number): {ProvidedChord}, {ProvidedKey}

--- A provider by its name, and its priority (the highest answers first).
local record Provider
  name: string
  fn: ProviderFn
  priority: number
end

--- A note of the song, in project beats, with its track and its clip.
local record SongNote is read.Note
  track: integer
  clip: integer
end

--- An instrument's range: the words in a track's name or its devices'
--- names that tell it, and the pitches of a part for it.
local record Range
  words: {string}
  low: integer
  high: integer
  name: string
end

--- The range that a track names in its `meta`.
local record OwnRange
  low: integer
  high: integer
end

--- What this module reads of a track's `meta`: `range`, and `drums`, the
--- drum map that the drums extension keeps.
local record TrackMarks
  range: OwnRange
  drums: types.Meta
end

--- The whole song's reading: its chords and keys, the project's own key
--- (`set`), and the provider of the first answer.
local record Reading
  stamp: string
  chords: {Chord}
  keys: {Key}
  set: Key
  provider: string
end

--- The payload of `harmony.changed`: the provider of the new reading.
local record Changed
  provider: string
end

--- What `paw.opt.chords` may be: "names", "roman", "both" or false.
local type LabelHow = string | boolean

-- What this module reads of `paw`, which paw/init.lua makes.
local record Time
  bar: function(at?: number): number
  bar_start: function(n: integer): number
end
local record Glyphs
  beat: string
end
local record Draw
  g: Glyphs
end
--- A row of cells to draw on (`paw.buf`).
local record Buf
  width: integer
  text: function(Buf, x: integer, y: integer, text: string, hl?: string)
end
local record Paw is partial.Paw
  music: MusicModule
  time: Time
  draw: Draw
end
local paw = (_G as {string:Paw}).paw

--- A value that `copy` passes on and never reads.
local record Value
end

local record M
  type Key = Key
  type KeyArg = KeyArg
  type Span = Span
  type Chord = Chord
  type ProvidedChord = ProvidedChord
  type ProvidedKey = ProvidedKey
  type ProviderFn = ProviderFn
  type SongNote = SongNote
  type Range = Range
  type Buf = Buf
  type Changed = Changed
  type LabelHow = LabelHow
  read: ReadModule
  voice: VoiceModule
  --- Every scale known by name, as semitones above the root.
  scales: {string:{integer}}
  --- Words in a track's name, or its devices', and the range a part for it is written in.
  ranges: {Range}
  default_range: Range
  --- The event that says the reading changed.
  changed: events.Event<Changed>
  parse_key: function(spec: KeyArg): Key
  key_name: function(key: KeyArg): string
  key: function(beat?: number): Key
  invalidate: function()
  schedule: function()
end

M.read = read
M.voice = voice
M.changed = events.event("harmony.changed")

local opt = options.opt
options.define("chords", "names" as LabelHow, { type = { "string", "boolean" }, values = { "names", "roman", "both", false } }) -- chord symbols in the piano roll's ruler: "names", "roman", "both" or false
options.define("harmony_step", 0.5)        -- beats: the shortest chord the built-in reading finds is about twice this

local function copy<T>(t: T): T
  local out: {string:Value} = {}
  for k, v in pairs(t as {string:Value}) do out[k] = v end
  return out as T
end

-- Theory: pitch classes, keys and scales -------------------------------------------

local SHARPS = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local FLATS = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
-- Without a key: the names most often written.
local PLAIN = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }
local LETTERS: {string:integer} = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }

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
local ALIASES: {string:string} = { ionian = "major", aeolian = "minor", maj = "major", min = "minor", m = "minor" }
-- Scales whose third is minor, for naming and numerals.
local MINORISH: {string:boolean} = { minor = true, harmonic_minor = true, melodic_minor = true, dorian = true, phrygian = true,
  locrian = true, minor_pentatonic = true, blues = true }
-- The degree of a mode's tonic in the major scale with the same signature.
local MODE_OFFSET: {string:integer} = { minor = 9, dorian = 2, phrygian = 4, lydian = 5, mixolydian = 7, locrian = 11,
  harmonic_minor = 9, melodic_minor = 9, minor_pentatonic = 9, blues = 9 }

--- Names of the known scales, sorted.
function M.scale_names(): {string}
  local out: {string} = {}
  for name in pairs(M.scales) do out[#out + 1] = name end
  table.sort(out)
  return out
end

--- A pitch class (0..11) from a name such as "C", "f#", "Bb", or a number.
function M.pitch_class(name: string | number): integer
  if name is number then return (name % 12) as integer end
  local letter, accidental = tostring(name):match("^([A-Ga-g])([#b]?)$")
  if not letter then error("not a key root: " .. tostring(name), 2) end
  return (LETTERS[letter:upper()] + (accidental == "#" and 1 or accidental == "b" and -1 or 0)) % 12
end

--- Whether a key is written with flats: F, Bb, Eb, Ab, Db, Gb major and
--- their relative minors and modes.
local function flat_key(key: Key): boolean
  -- The major key with the same signature: a mode's tonic less its degree.
  local steps = M.scales[key.scale]
  local offset = 0
  if key.scale ~= "major" and steps then offset = MODE_OFFSET[key.scale] or 0 end
  local major = (key.root - offset) % 12
  return major == 5 or major == 10 or major == 3 or major == 8 or major == 1 or major == 6
end

--- The name of a pitch class: spelled as `key` writes it (sharps or
--- flats), else the names most often written (C#, Eb, F#, Ab, Bb).
function M.pc_name(pc: integer, key?: KeyArg): string
  pc = pc % 12
  if not key then return PLAIN[pc + 1] end
  local k = M.parse_key(key)
  if k.root == 0 and (k.scale == "major" or k.scale == "lydian" or k.scale == "mixolydian") then return PLAIN[pc + 1] end
  return (flat_key(k) and FLATS or SHARPS)[pc + 1]
end

local function make_key(root: integer, scale: string): Key
  local steps = M.scales[scale]
  local key: Key = { root = root, scale = scale, steps = steps, tonic = root, mode = scale }
  key.name = M.key_name(key)
  return key
end

--- A key from a name ("D minor", "F# dorian", "Bb") or a table
--- (`{ root = "D", scale = "minor" }`, `{ tonic = 2, mode = "minor" }`, or a
--- key). A key is `{ tonic, mode, name, root = tonic, scale = mode, steps }`.
function M.parse_key(spec: KeyArg): Key
  if spec is Key then
    if spec.steps and spec.root then return spec end
    -- In Lua, a root may be a name.
    local root = (spec.root or spec.tonic) as string | number
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
function M.key_name(key: KeyArg): string
  local k: Key
  if key is Key and key.steps then k = key else k = M.parse_key(key) end
  local root = (k.root == 0 or not flat_key(k)) and (k.root == 0 and "C" or SHARPS[k.root + 1]) or FLATS[k.root + 1]
  -- D# minor and A# minor are written Eb and Bb more often than not.
  if not flat_key(k) and (k.root == 3 or k.root == 10) and MINORISH[k.scale] then root = FLATS[k.root + 1] end
  return root .. " " .. k.scale
end

local function member(key: Key, pitch: integer): integer
  local rel = (pitch - key.root) % 12
  for i, s in ipairs(key.steps) do
    if s == rel then return i end
  end
end

--- True if a pitch (or pitch class) is in a key.
function M.in_key(key: KeyArg, pitch: integer): boolean
  return member(M.parse_key(key), pitch) ~= nil
end

--- The pitch of the key nearest to `pitch`: `dir` "nearest" (the default;
--- halfway between two goes up), "up" or "down". Stays within 0..127.
function M.snap(key: KeyArg, pitch: integer, dir?: string): integer
  local k = M.parse_key(key)
  dir = dir or "nearest"
  if member(k, pitch) then return pitch end
  for d = 1, 12 do
    local up, down = pitch + d, pitch - d
    if dir ~= "down" and up <= 127 and member(k, up) then return up end
    if dir ~= "up" and down >= 0 and member(k, down) then return down end
  end
  return pitch
end

--- A pitch as an absolute scale degree (0 is the root in octave -1) and the
--- semitones it lies above that degree (non-zero for notes outside it).
function M.degree(key: KeyArg, pitch: integer): integer, integer
  local k = M.parse_key(key)
  local below = pitch
  while not member(k, below) do below = below - 1 end
  local octave = math.floor((below - k.root) / 12)
  return octave * #k.steps + member(k, below) - 1, pitch - below
end

--- The pitch of an absolute scale degree.
function M.degree_pitch(key: KeyArg, degree: integer): integer
  local k = M.parse_key(key)
  local n = #k.steps
  return k.root + k.steps[degree % n + 1] + 12 * math.floor(degree / n)
end

--- Move a pitch by `n` scale degrees. A pitch outside the key keeps its
--- distance from the scale note below it.
function M.step(key: KeyArg, pitch: integer, n: integer): integer
  local degree, offset = M.degree(key, pitch)
  return M.degree_pitch(key, degree + n) + offset
end

-- The project's key ----------------------------------------------------------------
--
-- Kept in the project as `project.key`, its name as `M.key_name` gives it
-- (`"D minor"`), and read back with `M.parse_key`.

--- The key set for the project, or nil when none is.
function M.project_key(): Key
  local name = api.project_get().key
  if name then return M.parse_key(name) end
end

--- Set the project's key (one edit), or clear it with nil. Returns the key.
function M.set_key(spec?: KeyArg): Key
  local key = spec ~= nil and M.parse_key(spec) or nil
  if key then api.project_set({ key = M.key_name(key) }) else api.project_set("key", nil) end
  return key
end

-- Chord names --------------------------------------------------------------------

-- Other names providers give qualities.
local ALIAS: {string:string} = { major = "maj", minor = "min", M = "maj", m = "min", dom7 = "7", dominant7 = "7", ["dom"] = "7",
  maj7 = "maj7", min7 = "m7", ["half-dim"] = "m7b5", hdim7 = "m7b5", ["m7b5"] = "m7b5", diminished = "dim",
  augmented = "aug", dim7 = "dim7", ["min7b5"] = "m7b5", ["5"] = "5", power = "5" }

local ROMAN = { "I", "bII", "II", "bIII", "III", "IV", "#IV", "V", "bVI", "VI", "bVII", "VII" }

--- A chord's symbol: "G7", "F/A", "Bbmaj7", spelled as `key` writes it.
function M.chord_name(chord: Chord, key?: KeyArg): string
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
function M.chord_roman(chord: Chord, key: KeyArg): string
  local k = M.parse_key(key)
  local q = read.by_quality[chord.quality] or {}
  local numeral = ROMAN[(chord.root - k.root) % 12 + 1]
  if q.minor then numeral = numeral:lower() end
  return numeral .. (q.roman or "")
end

--- A chord from its symbol: "G7", "F#m7b5", "C/E", "Bbmaj7". Nil when it
--- is not one.
function M.parse_chord(text: string): Chord
  local root, rest = tostring(text):match("^([A-Ga-g][#b]?)(.*)$")
  if not root then return nil end
  local bass: string
  rest = rest:gsub("/([A-Ga-g][#b]?)$", function(b: string): string bass = b return "" end)
  for _, q in ipairs(read.qualities) do
    if q.suffix == rest then
      local chord: Chord = { root = M.pitch_class(root), quality = q.name, tones = {} }
      chord.bass = bass and M.pitch_class(bass) or chord.root
      for i, s in ipairs(q.steps) do chord.tones[i] = (chord.root + s) % 12 end
      chord.name = M.chord_name(chord)
      return chord
    end
  end
end

--- The pitch classes of a chord of `quality` on `root`, root first.
function M.tones(root: integer, quality: string): {integer}
  local q = assert(read.by_quality[quality], "unknown chord quality " .. tostring(quality))
  local out: {integer} = {}
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

--- A track as `range` and `is_drums` take it: its id or its table. In Lua,
--- a track (`paw.track`) too.
local function track_of(track: integer | types.Track): types.Track
  if track is types.Track then
    local handle = track as contracts.TrackHandle
    if handle.get then return handle:get() end
    return track
  end
  if track == nil then return nil end
  return api.track_get(track)
end

--- The range of a part for a track, `{ low, high, name }`. This is the
--- range of the track (`track.meta.range = { low, high }`). If not, paw
--- guesses it from the words of its name and the names of its devices. If
--- not, it is C3 to C6.
function M.range(track: integer | types.Track): Range
  local t = track_of(track)
  if not t then return M.default_range end
  local own = type(t.meta) == "table" and (t.meta as TrackMarks).range
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
function M.is_drums(track: integer | types.Track): boolean
  local t: types.Track
  if track is types.Track then t = track else t = api.track_get(track) end
  if type(t.meta) == "table" and (t.meta as TrackMarks).drums then return true end
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

-- One entry of the project: quicker than the whole project (api.rs).
local project_edits = api.project_get as function(string): integer

local cached_notes: {SongNote}
local cached_edits: integer
--- Each note of the pitched tracks, in project beats, each with `track` and
--- `clip`. The list does not contain muted clips and tracks, or notes that a
--- trim of the edges of the clip hides. paw keeps the list until the project
--- changes. This is what sounds, for the reading and for snippets. The
--- context notes of the piano roll, `paw.roll_clips.context`, are what the
--- roll shows, in its own beats, and only of the tracks selected to show.
function M.notes(): {SongNote}
  local edits = project_edits("edits")
  if cached_edits == edits then return cached_notes end
  local out: {SongNote} = {}
  for _, id in ipairs(api.track_list()) do
    local t = api.track_get(id)
    if not t.mute and not M.is_drums(t) then
      for _, c in ipairs(api.clip_list(id)) do
        if c.kind == "midi" and not c.muted then
          local notes = api.clip_notes(c.id)
          for _, n in ipairs(notes) do
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
  cached_edits, cached_notes = edits, out
  return out
end

--- Bar starts from the first bar to past `last`, by the tempo map.
local function bar_starts(last: number): {number}
  local bars, n: {number}, integer = {}, 1
  repeat
    bars[#bars + 1] = paw.time.bar_start(n)
    n = n + 1
  until bars[#bars] > last or n > 100000
  return bars
end

--- The built-in provider: chords and keys read from the notes.
function M.builtin(from: number, to: number): {ProvidedChord}, {ProvidedKey}
  local notes = M.notes()
  local last = 0.0
  for _, n in ipairs(notes) do last = math.max(last, n.start + n.length) end
  local chords = read.chords(notes, { from = from, to = to, step = opt.harmony_step, bar = paw.time.bar(0) })
  local keys = read.keys(notes, bar_starts(last), chords)
  -- The reading's chords and keys are what a provider gives, with numbers for roots.
  return chords as {ProvidedChord}, keys as {ProvidedKey}
end

local providers: {Provider} = { { name = "builtin", fn = M.builtin, priority = 0 } }
local cache: Reading = { stamp = nil }
local last_text: string   -- the last reading in words, to tell when it changes

--- Add a provider. `fn(from, to)` returns chords and keys, or nil to let
--- the next provider answer. The lists have the shapes that `chords` and
--- `key` give. `root`, `quality`, `at` and `length` are enough for a chord.
--- `at`, `length`, `tonic` and `mode` are enough for a key. The highest
--- `priority` (default 50) answers first. A new provider with the same
--- name replaces the old one. `fn` nil removes it.
function M.provide(name: string, fn?: ProviderFn, priority?: number)
  for i = #providers, 1, -1 do
    if providers[i].name == name then table.remove(providers, i) end
  end
  if fn then providers[#providers + 1] = { name = name, fn = fn, priority = priority or 50 } end
  table.sort(providers, function(a: Provider, b: Provider): boolean return a.priority > b.priority end)
  M.invalidate()
end

--- Forget the reading: a provider whose answer changed calls this.
function M.invalidate()
  cache.stamp = nil
  M.schedule()
end

--- Fill in what a chord or key from a provider may leave out.
local function complete_key(k: ProvidedKey): Key
  local root = k.tonic or k.root
  local key = M.parse_key({ root = root ~= nil and M.pitch_class(root) or nil, scale = k.mode or k.scale })
  return { at = k.at, length = k.length, tonic = key.root, mode = key.scale, name = key.name, root = key.root, scale = key.scale, steps = key.steps }
end

local function signature(): string
  local stamp = project_edits("edits")
  local parts = { tostring(stamp), tostring(opt.harmony_step) }
  for _, p in ipairs(providers) do parts[#parts + 1] = p.name end
  return table.concat(parts, "|")
end

--- True if the reading agrees with the project, so `key` and `chords` answer
--- immediately. A view that paw draws on each key asks this first, because
--- to read a long song again takes some time.
function M.fresh(): boolean
  return cache.stamp == signature()
end

--- The whole song's reading: `{ chords, keys, provider }`.
local function reading(): Reading
  local sig = signature()
  if cache.stamp == sig then return cache end
  -- The highest-priority provider that answers wins over the stretch its
  -- answer covers; the ones below fill in the rest of the song (a language
  -- server hears the clip it is sent, the built-in reading everything).
  local chords, keys, by, covered: {ProvidedChord}, {ProvidedKey}, string, {{number, number}} = {}, {}, nil, {}
  -- What of `x` lies outside the stretches covered already: the longer
  -- piece left, or nil.
  local function free<T is Span>(x: T): T
    local a, z = x.at, x.at + x.length
    for _, span in ipairs(covered) do
      if a < span[2] - 1e-9 and z > span[1] + 1e-9 then
        if span[1] - a >= z - span[2] then z = math.min(z, span[1]) else a = math.max(a, span[2]) end
      end
    end
    if z - a < 1e-9 then return nil end
    if a == x.at and z == x.at + x.length then return x end
    local cut = copy(x)
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
  local full: {Key} = {}
  for i, k in ipairs(keys) do full[i] = complete_key(k) end
  table.sort(full, function(a: Key, b: Key): boolean return a.at < b.at end)
  local list: {Chord} = {}
  for _, c in ipairs(chords) do
    -- What the provider says is kept (a server's `function`, `cadence`,
    -- its own name and numeral); what it leaves out is filled in.
    local chord = copy(c as Chord)
    chord.root = M.pitch_class(c.root)
    chord.bass = M.pitch_class(c.bass or c.root)
    chord.quality = read.by_quality[c.quality] and c.quality or ALIAS[c.quality] or c.quality
    if not chord.tones then
      chord.tones = read.by_quality[chord.quality] and M.tones(chord.root, chord.quality) or { chord.root }
    end
    list[#list + 1] = chord
  end
  table.sort(list, function(a: Chord, b: Chord): boolean return a.at < b.at end)
  cache = { stamp = sig, chords = list, keys = full, set = set, provider = by }
  local parts: {string} = {}
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
  if last_text and text ~= last_text then events.emit(M.changed, { provider = by }) end
  last_text = text
  return cache
end

--- The key at `beat` (the start when nil): the project's when one is set,
--- else the one read there, else C major. `{ tonic, mode, name, ... }`.
function M.key(beat?: number): Key
  local r = cache.stamp == signature() and cache or reading()
  if r.set then return r.set end
  beat = beat or 0
  local found: Key
  for _, k in ipairs(r.keys) do
    if k.at <= beat + 1e-9 then found = k end
  end
  found = found or r.keys[1]
  if found then return found end
  return M.parse_key("C major")
end

--- The keys read over the song, `{ at, length, tonic, mode, name }` each.
--- When the project has its own key, that key is over all of the song.
function M.keys(): {Key}
  local r = reading()
  if r.set then
    local key = complete_key({ tonic = r.set.tonic, mode = r.set.mode })
    key.at, key.length = 0, math.huge
    return { key }
  end
  return r.keys
end

--- The chords that sound between `from` and `to` (project beats; all of
--- them when nil), in time order.
function M.chords(from?: number, to?: number): {Chord}
  local out: {Chord} = {}
  for _, c in ipairs(reading().chords) do
    if (not to or c.at < to) and (not from or c.at + c.length > from) then out[#out + 1] = c end
  end
  return out
end

--- The chord that sounds at `beat`, or nil.
function M.at(beat: number): Chord
  for _, c in ipairs(reading().chords) do
    if c.at <= beat + 1e-9 and beat < c.at + c.length - 1e-9 then return c end
  end
end

--- The first chord that starts after `beat`.
function M.next(beat: number): Chord
  for _, c in ipairs(reading().chords) do
    if c.at > beat + 1e-9 then return c end
  end
end

--- The last chord that starts before `beat` and is not the one at it.
function M.prev(beat: number): Chord
  local found: Chord
  local here = M.at(beat)
  for _, c in ipairs(reading().chords) do
    if c.at < beat - 1e-9 and c ~= here then found = c end
  end
  return found
end

--- The provider the current reading came from.
function M.provider(): string
  return reading().provider
end

--- A chord's label as `paw.opt.chords` (or `how`) asks: its name, its
--- numeral, or both ("G7 V7").
function M.label(chord: Chord, how?: LabelHow): string
  how = how or opt.chords
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
function M.draw(buf: Buf, scroll: number, span: number, zoom: number, origin: number, how?: LabelHow)
  how = how or opt.chords
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
      if label ~= "" then buf:text(x0 + 1, 0, util.fit(label, math.max(0, math.min(api.str_width(label), x1 - x0 - 1))), "RulerChord") end
    end
  end
end

local pending: integer
--- Some time after the project changes, paw makes the reading again. So
--- `harmony.changed` comes even when nothing asks.
function M.schedule()
  if pending then return end
  pending = paw.defer(function()
    pending = nil
    reading()
  end, 30)
end
events.on(kernel.changed, function() M.schedule() end)

return M
