-- `paw.audition`: hear something before choosing it, without the project or
-- its undo history keeping a trace. The pickers use it as their selection
-- moves (`audition` in `paw.pick`), and scripts can too:
--
--   paw.audition.try(function() paw.fx.load(device, "Plate") end)  -- an edit that can be taken back
--   paw.audition.phrase(track.id, notes, { length = 4, label = "loop bar 5" })
--   paw.audition.file("/samples/kick.wav")
--   paw.audition.stop()                       -- silence, and take the edit back
--
-- A trial (`try`) makes its edits as any others, so that they are heard and
-- seen; `revert` puts the project back exactly as it was, and `keep` makes
-- them one undo step. A phrase is played through a track as notes played
-- live, over and over until stopped, and is not played while the transport
-- runs: the song is what is heard then. A file is heard on its own over
-- everything else at `paw.opt.audition_level` dB.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local options = require("paw.options")
local seats = require("paw.seats")
local type types = require("paw.types")
local type partial = require("paw.partial")
local type HarmonyModule = require("paw.harmony")
local type MidifileModule = require("paw.midifile")
local type objects = require("paw.objects")
local type CursorModule = require("paw.cursor")

--- A note of a phrase: `start` in beats from the start of the phrase. Its
--- own `track` wins over the phrase's.
local record PhraseNote
  pitch: integer
  start: number
  length: number
  velocity: number
  track: integer
  drum: boolean
end

--- A phrase that plays: through `track`, `length` beats long, again and
--- again unless `loop` is false, from beat `at` of the project at its
--- tempo, or at its own `tempo`. `silent` says why it is not heard.
local record Phrase
  track: integer
  notes: {PhraseNote}
  length: number
  label: string
  key: string
  loop: boolean
  at: number
  tempo: number
  silent: string
end

--- What `phrase` takes besides the track and the notes.
local record PhraseOptions
  length: number
  label: string
  key: string
  loop: boolean
  at: number
  tempo: number
end

--- What a track plays, as `builtin` and `track_phrase` give it.
local record Built
  notes: {PhraseNote}
  length: number
  label: string
  at: number
end

--- A note played lately.
local record Heard
  track: integer
  pitch: integer
  velocity: number
end

--- What is heard now (`state`): a phrase, or a file as
--- `paw.api.preview_get` gives it.
local record State
  kind: string
  label: string
  track: integer
  notes: {PhraseNote}
  length: number
  silent: string
  file: string
  level: number
  state: types.PreviewState
  error: string
  position: number
  outline: {number}
  trial: boolean
end

--- A line of the outline of a sound file, and the column of the position.
local record OutlineLine
  text: string
  at: integer
end

--- The payload of `option.changed`, as far as this module reads it.
local record OptionChanged
  name: string
  value: options.Value
end

-- What this module reads of `paw`, which paw/init.lua makes.
local record Paw is partial.Paw
  harmony: HarmonyModule
  midifile: MidifileModule
  time: objects.Time
  cursor: CursorModule
  add_track: function(opts?: objects.TrackInput): objects.Track
end
local paw = (_G as {string: Paw}).paw

-- Lua 5.1's and LuaJIT's functions that Teal's library leaves out.
local record Value
end
local record Lua51
  unpack: function<T>({T}, ?integer, ?integer): T...
end
local record LuaTable
  maxn: function<T>({T}): integer
end
local lua51 = _G as Lua51
local maxn = (table as LuaTable).maxn

local record M
  type PhraseNote = PhraseNote
  type Phrase = Phrase
  type PhraseOptions = PhraseOptions
  type Built = Built
  type Heard = Heard
  type State = State
  type OutlineLine = OutlineLine
  --- The notes played lately, newest last.
  heard: {Heard}
  --- Counts what was asked to be heard, so that a picker can tell whether an
  --- item asked for anything: what came before is stopped when it did not.
  asked: integer
  revert: function()
end

local opt = options.opt
options.define("audition_level", -12) -- dB a sound file heard in a picker plays at
options.define("audition_delay", 150) -- ms the selection rests on an item before it is heard

local EPS = 1e-9

-- What is heard now: `{ label, track, notes, length, key }` for a phrase.
local phrase: Phrase
local timers, sounding: {integer}, {string: boolean} = {}, {}
M.heard = {}
M.asked = 0

seats.keep(
  "audition",
  function(): Phrase return phrase end,
  function(p: Phrase) phrase = p end,
  function(): Phrase return nil end
)

local function silence()
  for _, t in ipairs(timers) do
    paw.cancel(t)
  end
  timers = {}
  for key in pairs(sounding) do
    local track, pitch = key:match("^(%d+):(%d+)$")
    pcall(api.note_off, tonumber(track) as integer, tonumber(pitch) as integer)
  end
  sounding = {}
end

-- Trials -----------------------------------------------------------------------

--- Make the edits of `fn` as a trial, in place of the last trial. You hear
--- and see them, and `revert` removes them with no trace. Returns the
--- results of `fn`. If `fn` fails, paw removes the edits and raises the error.
function M.try<R>(fn: function(): (R...)): R...
  M.revert()
  api.trial_begin()
  local result = {pcall(fn as function(): Value...)} as {Value}
  if not result[1] then
    M.revert()
    error(result[2], 0)
  end
  return (lua51.unpack as function({Value}, integer, integer): R...)(result, 2, maxn(result))
end

--- Put the project back as it was before the trial, if there is one.
function M.revert()
  if api.trial_active() then
    api.trial_end(false)
  end
end

--- Keep the trial's edits as one undo step.
function M.keep()
  if api.trial_active() then
    api.trial_end(true)
  end
end

-- Phrases ----------------------------------------------------------------------

--- Milliseconds between two beats: at a phrase's own tempo when it has
--- one, else at the project's there.
local function ms_between(from: number, to: number, tempo: number): number
  if tempo then
    return math.max(0, (to - from) * 60000 / tempo)
  end
  return math.max(0, (paw.time.to_seconds(to) - paw.time.to_seconds(from)) * 1000)
end

local function remember(track: integer, n: PhraseNote)
  local heard = M.heard
  heard[#heard + 1] = {track = track, pitch = n.pitch, velocity = n.velocity}
  if #heard > 256 then
    table.remove(heard, 1)
  end
end

local function pass()
  local p = phrase
  if not p then
    return
  end
  local at, tempo = p.at, p.tempo
  for _, n in ipairs(p.notes) do
    local track = n.track or p.track
    local on = ms_between(at, at + n.start, tempo)
    local off = math.max(on + 20, ms_between(at, at + math.min(n.start + n.length, p.length), tempo) - 5)
    local key = track .. ":" .. n.pitch
    timers[#timers + 1] = paw.defer(
      function()
        if phrase ~= p then
          return
        end
        sounding[key] = true
        remember(track, n)
        pcall(api.note_on, track, n.pitch, n.velocity)
      end,
      on
    )
    timers[#timers + 1] = paw.defer(function() sounding[key] = nil; pcall(api.note_off, track, n.pitch) end, off)
  end
  timers[#timers + 1] = paw.defer(
    function()
      if phrase ~= p then
        return
      end
      -- Each pass leaves its own timers behind: only the next pass's are kept.
      timers = {}
      if p.loop then
        pass()
      else
        phrase = nil
      end
    end,
    ms_between(at, at + p.length, tempo)
  )
end

--- Play `notes` through a track, again each `opts.length` beats (or one
--- time with `loop = false`). The notes are `{ pitch, start, length,
--- velocity }`, with `start` in beats from the start of the phrase. The
--- `track` of a note wins over the `track` of the phrase. `opts.label` tells
--- what the phrase is. A phrase with the same `opts.key` as the phrase that
--- plays continues and does not start again. So only the sound changes.
--- `opts.tempo` is its tempo. If not given, it is the tempo of the project
--- at `opts.at` (the cursor). paw plays nothing while the transport runs.
function M.phrase(track: integer, notes: {PhraseNote}, opts?: PhraseOptions): Phrase
  M.asked = M.asked + 1
  opts = opts or {}
  local length = opts.length or 4
  if phrase and opts.key and phrase.key == opts.key and phrase.track == track then
    phrase.label = opts.label or phrase.label
    return phrase
  end
  silence()
  phrase = {
    track = track,
    notes = notes,
    length = length,
    label = opts.label,
    key = opts.key,
    loop = opts.loop ~= false,
    at = opts.at or paw.cursor.beat or 0,
    tempo = opts.tempo,
  }
  if api.transport_get().playing then
    phrase.silent = "the song is playing"
    return phrase
  end
  pass()
  return phrase
end

--- A bar of a pattern for a drum track, by General MIDI note.
local DRUMS: {{integer, number, integer}} = {
  {36, 0, 110},
  {42, 0, 80},
  {42, 0.5, 70},
  {38, 1, 105},
  {42, 1, 80},
  {42, 1.5, 70},
  {36, 2, 110},
  {42, 2, 80},
  {36, 2.5, 90},
  {42, 2.5, 70},
  {38, 3, 105},
  {42, 3, 80},
  {42, 3.5, 70},
}

--- A phrase for a track with nothing to play. For a drum track, it is a bar
--- of a beat. For other tracks, it is the tonic chord of the key, held,
--- then as an arpeggio up and down, in the range of the track.
--- `{ notes, length, label }`.
function M.builtin(track?: integer, at?: number): Built
  at = at or paw.cursor.beat or 0
  local notes: {PhraseNote} = {}
  if track and paw.harmony.is_drums(track) then
    for i, d in ipairs(DRUMS) do
      notes[i] = {pitch = d[1], start = d[2], length = 0.25, velocity = d[3]}
    end
    return {notes = notes, length = 4, label = "a built-in beat"}
  end
  local key = paw.harmony.key(at)
  local range = track and paw.harmony.range(track) or paw.harmony.default_range
  -- The tonic nearest the middle of the range, a third and a fifth above.
  local middle = math.floor((range.low + range.high) / 2)
  local root = middle - ((middle - key.root) % 12)
  if root + 7 > range.high then
    root = root - 12
  end
  local chord = {root, paw.harmony.step(key, root, 2), paw.harmony.step(key, root, 4)}
  for _, pitch in ipairs(chord) do
    notes[#notes + 1] = {pitch = pitch, start = 0, length = 1.75, velocity = 90}
  end
  local line = {chord[1], chord[2], chord[3], chord[1] + 12, chord[3], chord[2]}
  for i, pitch in ipairs(line) do
    notes[#notes + 1] = {pitch = pitch, start = 2 + (i - 1) / 3, length = 1 / 3, velocity = 85}
  end
  return {notes = notes, length = 4, label = "a built-in phrase in " .. paw.harmony.key_name(key)}
end

--- What a track plays around the cursor, as a phrase. This is the bar of
--- its MIDI clip at the cursor. If not, it is the last bar with notes before
--- the cursor. If not, it is the first bar with notes. It is `builtin` when
--- the track has no notes. `{ notes, length, label, at }`.
function M.track_phrase(track?: integer): Built
  local cursor = paw.cursor.beat or 0
  local bars: {number: {PhraseNote}} = {}
  for _, c in ipairs(track and api.clip_list(track) or {}) do
    if c.kind == "midi" and not c.muted then
      local clip_notes = api.clip_notes(c.id)
      for _, n in ipairs(clip_notes) do
        local s = c.start + n.start
        if n.start >= -EPS and n.start < c.length - EPS then
          local bar = paw.time.bar_floor(s + EPS)
          local list = bars[bar] or {}
          bars[bar] = list
          list[#list + 1] = {pitch = n.pitch, start = s - bar, length = n.length, velocity = n.velocity}
        end
      end
    end
  end
  local here = paw.time.bar_floor(cursor + EPS)
  local chosen = bars[here] and here
  if not chosen then
    local before, first: number, number
    for bar in pairs(bars) do
      if bar <= here and (not before or bar > before) then
        before = bar
      end
      if not first or bar < first then
        first = bar
      end
    end
    chosen = before or first
  end
  if not chosen then
    local b = M.builtin(track, cursor)
    b.at = cursor
    return b
  end
  local length = paw.time.bar(chosen)
  local notes: {PhraseNote} = {}
  for _, n in ipairs(bars[chosen]) do
    if n.start < length - EPS then
      notes[#notes + 1] = n
    end
  end
  table.sort(notes, function(a: PhraseNote, b: PhraseNote): boolean return a.start < b.start end)
  return {notes = notes, length = length, at = chosen, label = "loop bar " .. paw.time.bar_of(chosen)}
end

--- True if a track has an instrument to play notes.
function M.has_instrument(track: integer): boolean
  local category: {string: string} = {}
  for _, info in ipairs(paw.device_types()) do
    category[info.kind] = info.category
  end
  for _, id in ipairs(api.track_get(track).devices) do
    local ok, d = pcall(api.device_get, id)
    if ok and not d.bypass and category[d.kind] == "instrument" then
      return true
    end
  end
  return false
end

--- Play what a track plays around the cursor, through the track, again and
--- again (`track_phrase`). So you hear a sound that you try on the track
--- with its own notes. The loop continues while only the sound changes.
--- Returns what you hear, in words.
function M.through(track: integer): string
  M.asked = M.asked + 1
  if api.transport_get().playing then
    silence()
    phrase = nil
    return "with the song"
  end
  if not M.has_instrument(track) then
    silence()
    phrase = nil
    return "heard when the song plays"
  end
  local p = M.track_phrase(track)
  M.phrase(track, p.notes, {length = p.length, at = p.at, label = p.label, key = p.label .. "@" .. tostring(p.at)})
  return p.label
end

--- A track to play notes through: the cursor's when it has an instrument,
--- else one added as a trial (with the built-in synth, or drums) that
--- `revert` takes away. `drums` asks for a drum kit.
function M.player(drums?: boolean): integer
  local track = paw.cursor.track_id()
  if track and M.has_instrument(track) and (not drums or paw.harmony.is_drums(track)) then
    return track
  end
  if not api.trial_active() then
    api.trial_begin()
  end
  local t = paw.add_track({name = drums and "Audition drums" or "Audition"})
  t:add_device(drums and "drums" or "synth")
  return t.id
end

--- Play the first `bars` bars of a MIDI file (2 when nil), at its own tempo,
--- once: pitched parts through `player()`, its drums (channel 10) through
--- a kit. Returns the label.
function M.midi_file(path: string, bars?: integer): string
  local file, why = paw.midifile.read(path)
  if not file then
    error(why, 0)
  end
  local ppq = file.ppq
  local sig = file.signatures[1] or {num = 4, den = 4}
  local length = (bars or 2) * sig.num * 4 / sig.den
  local tempo = file.tempos[1] and file.tempos[1].bpm or 120
  local notes, has: {PhraseNote}, {string: boolean} = {}, {}
  for _, track in ipairs(file.tracks) do
    for _, n in ipairs(track.notes) do
      local start = n.tick / ppq
      if start < length then
        local drum = n.channel == 9
        has[drum and "drums" or "notes"] = true
        notes[#notes + 1] = {
          pitch = n.pitch, start = start, length = math.max(n.length / ppq, 1 / 16), velocity = n.velocity, drum = drum
        }
      end
    end
  end
  if #notes == 0 then
    return "nothing in its first bars"
  end
  local pitched = has.notes and M.player(false)
  local kit = has.drums and M.player(true)
  for _, n in ipairs(notes) do
    n.track = n.drum and kit or pitched
  end
  M.phrase(pitched or kit, notes, {length = length, loop = false, tempo = tempo})
  return string.format("first %d bars at %g BPM", bars or 2, tempo)
end

-- Files ------------------------------------------------------------------------

--- Hear a sound file on its own, from its start, in place of whatever was.
function M.file(path: string)
  M.asked = M.asked + 1
  silence()
  phrase = nil
  api.preview_level(opt.audition_level)
  api.preview_play(path)
end

local option_changed: events.Event<OptionChanged> = events.event("option.changed")
events.on(
  option_changed,
  function(e: OptionChanged)
    if e.name == "audition_level" then
      pcall(api.preview_level, tonumber(e.value) or -12)
    end
  end
)

-- Stopping ---------------------------------------------------------------------

--- Stop the sound of the audition (phrase and file). A trial does not change.
function M.quiet()
  silence()
  phrase = nil
  api.preview_stop()
end

--- Stop what is heard and take a trial back.
function M.stop()
  M.quiet()
  M.revert()
end

--- What you hear now: `{ kind = "phrase", label, track, notes, length,
--- silent }`, `{ kind = "file", file, state, position, length, outline }`
--- or nil. `trial` is true while the edits of a trial stay.
function M.state(): State
  local file = api.preview_get()
  local out: State
  if file then
    -- Every field of the preview, as the kernel gives it.
    local fields: {string: Value} = {}
    for k, v in pairs(file as {string: Value}) do
      fields[k] = v
    end
    out = fields as State
    out.kind = "file"
  elseif phrase then
    out = {
      kind = "phrase",
      label = phrase.label,
      track = phrase.track,
      notes = phrase.notes,
      length = phrase.length,
      silent = phrase.silent,
    }
  end
  if out then
    out.trial = api.trial_active()
  end
  return out
end

-- Drawing ----------------------------------------------------------------------

local BARS = {" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}

--- The outline of a sound file as `rows` lines `width` columns wide. The
--- loudest part of each column goes up from the bottom. If `position`
--- (seconds of `length`) is given, the column of that position is marked.
function M.outline_lines(
  outline: {number}, width: integer, rows: integer, position?: number, length?: number
): {OutlineLine}
  local out: {OutlineLine} = {}
  if not outline or #outline == 0 or width < 1 then
    return out
  end
  local heights: {number} = {}
  for x = 1, width do
    local from = math.floor((x - 1) * #outline / width) + 1
    local to = math.max(from, math.floor(x * #outline / width))
    local peak = 0.0
    for i = from, to do
      peak = math.max(peak, outline[i] or 0)
    end
    -- Loudness as heard: decibels from -48 up to full scale.
    local db = peak > 0 and 20 * math.log10(peak) or -96
    heights[x] = math.max(0, math.min(1, (db + 48) / 48)) * rows * 8
  end
  local at = position and length and length > 0 and math.floor(position / length * width) + 1 or nil
  for row = rows, 1, -1 do
    local cells: {string} = {}
    for x = 1, width do
      local h = heights[x] - (row - 1) * 8
      cells[x] = BARS[math.max(0, math.min(8, math.floor(h + 0.5))) + 1]
    end
    out[#out + 1] = {text = table.concat(cells), at = at}
  end
  return out
end

return M
