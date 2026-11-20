-- `paw.midifile`: Standard MIDI Files, read and written.
--
--   :open song.mid                 -- a new project from it (asks nothing: see below)
--   :import song.mid               -- into this one: new tracks below the cursor's, at the cursor
--   :import song.mid tempo=yes     -- and its tempo map from the cursor on
--   :export song.mid               -- the project; `:export song.mid clip`, `selection`
--
--   local file = paw.midifile.read("song.mid")    -- what is in it, in ticks
--   paw.midifile.open("song.mid")   paw.midifile.import("song.mid", { start = 16, tempo = true })
--   paw.midifile.export("out.mid", { clips = { clip.id } })
--   paw.midifile.parse(bytes)   paw.midifile.encode(file)   -- bytes and back
--
-- A file opens as a project of its own: one track for each of the file's
-- tracks that has notes (a format 0 file, whose one track holds every
-- channel, is split by channel), one clip on each, spanning its bars, with
-- the controller moves, pitch bend, pressure and program changes as the
-- clip's controls; the tempo map, time signatures and markers are the
-- project's, lyrics go on the notes they start (`note.meta.lyric`), a
-- note's MIDI 2.0 attribute (an articulation) comes back from the
-- sequencer-specific event this program writes it as (below), and a
-- track that plays on channel 10 alone gets the built-in drum kit. The
-- project has no file: saving it asks for a name and never writes over the
-- .mid. What could not be kept (sysex, key signatures, and the like) is
-- counted in `skipped` and said when the file is opened.
--
-- The reader and the writer (`parse`, `encode`) need nothing of the
-- program, so extensions read MIDI files with them too (extensions/interop).
--
-- Written in Teal (paw/lang.lua): the build compiles it to Lua.
local type types = require("paw.types")
local type Attr = types.NoteAttr
local api = require("paw.api")
local type Untyped = require("paw.untyped")

-- The `paw` global, for its parts still written in Lua. This module is a
-- part of the global's types, so it takes the global as `Untyped`.
local paw = (_G as {string:Untyped}).paw

local record M
  -- The shape of a file, in ticks, as `parse` gives it and `encode` takes it.

  --- A note: where it starts and how long it is in ticks, its key, its
  --- velocity (as in the file: 1 to 127), its channel (from 0), the lyric
  --- it starts and its MIDI 2.0 attribute.
  record Note
    tick: number
    length: number
    pitch: integer
    velocity: number
    channel: integer
    lyric: string
    attr: Attr
  end

  --- What a control is.
  enum ControlType
    "cc"
    "bend"
    "pressure"
    "program"
  end

  --- A control: a controller move (`cc`, with `number`), a pitch bend (0
  --- to 16383, 8192 in the middle), a pressure (with `key` for one
  --- note's) or a program change (with `program`).
  record Control
    tick: number
    type: ControlType
    value: number
    channel: integer
    number: integer
    key: integer
    program: integer
  end

  --- Text at a tick: a lyric or a marker.
  record Text
    tick: number
    text: string
  end

  --- Something at a tick.
  interface Ticked
    tick: number
  end

  --- A tempo from a tick on.
  record Tempo is Ticked
    tick: number
    bpm: number
  end

  --- A time signature from a tick on.
  record Signature is Ticked
    tick: number
    num: integer
    den: integer
  end

  --- A track of a file.
  record Track
    name: string
    instrument: string
    length: integer
    notes: {Note}
    controls: {Control}
    lyrics: {Text}
  end

  --- A Standard MIDI File: its format (0, 1 or 2), the ticks of a beat,
  --- its length in ticks, whether it is timed in frames of SMPTE time
  --- code, its tracks, its tempo map and markers, and what was left out
  --- of it, counted by what it is.
  record File
    format: integer
    ppq: number
    length: integer
    smpte: boolean
    tracks: {Track}
    tempos: {Tempo}
    signatures: {Signature}
    markers: {Text}
    skipped: {string:integer}
  end

  --- The data for one track of the project: its name, its channel, whether
  --- it is a drum kit's (channel 10 alone), and its notes and controls.
  record Part
    name: string
    channel: integer
    drums: boolean
    notes: {Note}
    controls: {Control}
  end

  -- The shape of a clip, in beats, as the project keeps it.

  --- What a note of a clip keeps for this module in its `meta`: its
  --- channel (from 1; nil for channel 1) and its lyric.
  record NoteMeta
    channel: integer
    lyric: string
  end

  --- A note of a clip, in beats from the clip's start.
  record ClipNote
    start: number
    length: number
    pitch: integer
    velocity: integer
    meta: NoteMeta
    attr: Attr
  end

  --- A control of a clip, in beats from the clip's start; its value from
  --- 0 to 1 (from -1 to 1 for a bend).
  record ClipControl
    start: number
    type: ControlType
    value: number
    number: integer
    key: integer
    program: integer
  end

  --- A clip as `track:add_clip` takes it.
  record ClipSpec
    start: number
    length: number
    name: string
    notes: {ClipNote}
    controls: {ClipControl}
  end

  --- What `api.midi2_read` gives: a clip file's notes, controls and length.
  record ClipFile
    length: number
    notes: {ClipNote}
    controls: {ClipControl}
  end

  --- The clip file open alone: its path and its clip, and `opening` while
  --- its project loads.
  record Document
    path: string
    clip: integer
    opening: boolean
  end

  --- What the last export could not keep: note times and values rounded,
  --- and moves left out.
  record Lost
    times: integer
    values: integer
    dropped: integer
  end

  --- What `import` takes: where (`start`, in beats; the cursor by
  --- default), the track (an object or an id) for one clip of it all, and
  --- whether to bring the tempo map in.
  record ImportOptions
    start: number
    track: Untyped | integer
    tempo: boolean
  end

  --- What `export` writes: the tracks (objects or ids), or the clips (ids).
  record ExportOptions
    tracks: {Untyped | integer}
    clips: {integer}
  end

  --- What `open` gives: the tracks made, the notes, and what was left out.
  record Opened
    tracks: {Untyped}
    notes: integer
    skipped: string
  end

  --- What `import` gives: the tracks and clips made, the notes, and what
  --- was left out.
  record Imported
    tracks: {Untyped}
    clips: {Untyped}
    notes: integer
    skipped: string
  end

  extensions: {string}
  document: Document
  last_export: Lost
end

local type Note = M.Note
local type Control = M.Control
local type Track = M.Track
local type File = M.File
local type Part = M.Part

-- What this module reads and sets of the modules still written in Lua.
local record Cursor
  beat: number
end
local record State
  pick_dir: string
end
local record ClipInfo
  kind: string
  muted: boolean
  start: number
  length: number
  control_count: integer
end
local record Device
  kind: string
end
local record TempoPoint
  beat: number
  bpm: number
  ramp: boolean
end
local record SignaturePoint
  beat: number
  num: integer
  den: integer
end
local record MarkerPoint
  beat: number
  name: string
end

M.extensions = { "mid", "midi", "smf", "kar" }

--- True if a path names a MIDI 2.0 clip file (`.midi2`), from its ending.
function M.is_clip_file(path: string): boolean
  return (tostring(path):match("%.([^./]+)$") or ""):lower() == "midi2"
end

-- The clip file open alone, if one is: `{ path, clip }` (see `open_clip`).
M.document = nil

--- Open a MIDI 2.0 clip file alone, as a new project with no file: one
--- track that plays it on the default instrument, the clip, and the piano
--- roll on it. `:w` writes the clip back to its file. Returns the clip.
function M.open_clip(path: string): Untyped, M.ClipFile
  local read = api.midi2_read(path) as M.ClipFile
  local name: string = (path:match("([^/]+)$") or path):gsub("%.[^.]+$", "")
  api.project_new()
  api.project_set("name", name)
  local track = paw.add_track({ name = name })
  track:add_device("synth")
  local clip = track:add_clip({ name = name, start = 0, length = read.length > 0 and read.length or nil,
    notes = read.notes, controls = read.controls })
  api.undo_reset()
  M.document = { path = path, clip = clip.id as integer }
  paw.cursor.set_track(track)
  (paw.cursor as Cursor).beat = 0
  -- `project_new` above says `project.loaded` later: this clip stays open.
  M.document.opening = true
  pcall(paw.ui.views.pianoroll.edit, paw.ui.views.pianoroll, clip)
  return clip, read
end

--- Write the clip open alone back to its file. Returns its path.
function M.write_clip(): string
  local doc = M.document
  local clip = api.clip_get(doc.clip) as ClipInfo
  api.midi2_write(doc.path, { notes = api.clip_notes(doc.clip, nil), controls = api.clip_controls(doc.clip), length = clip.length })
  api.project_mark_saved()
  return doc.path
end

paw.on("project.loaded", function()
  if M.document and M.document.opening then
    M.document.opening = nil
  else
    M.document = nil
  end
end)

--- Bring a MIDI 2.0 clip file in as a clip that refers to it, on a track at
--- a beat. The first edit makes it the project's own. Returns the clip.
function M.import_clip(path: string, track: Untyped, start: number): Untyped
  return track:add_clip({ file = path, start = start })
end

--- True if a path names a MIDI file, from its file ending.
function M.is_midi_file(path: string): boolean
  local ext = (tostring(path):match("%.([^./]+)$") or ""):lower()
  for _, known in ipairs(M.extensions) do
    if ext == known then return true end
  end
  return false
end

-- Reading ----------------------------------------------------------------------

local function be(data: string, pos: integer, n: integer): integer
  local v = 0
  for i = 0, n - 1 do v = v * 256 + (data:byte(pos + i) or 0) end
  return v
end

--- A variable-length number at `p`, and where what follows starts; nil
--- when it runs past `stop`.
local function vlq(data: string, p: integer, stop: integer): integer, integer
  local v = 0
  for _ = 1, 4 do
    if p >= stop then return nil end
    local b = data:byte(p)
    p = p + 1
    v = v * 128 + b % 128
    if b < 128 then return v, p end
  end
  return nil
end

--- Text as UTF-8: files say nothing of their encoding, and most that are
--- not UTF-8 are Latin-1.
local function utf8_text(s: string): string
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    local extra: integer = c < 0x80 and 0 or (c >= 0xC2 and c < 0xE0) and 1 or (c >= 0xE0 and c < 0xF0) and 2
      or (c >= 0xF0 and c < 0xF5) and 3 or nil
    if not extra then break end
    for k = 1, extra do
      local d = s:byte(i + k)
      if not d or d < 0x80 or d >= 0xC0 then extra = nil break end
    end
    if not extra then break end
    i = i + 1 + extra
  end
  if i > n then return (s:gsub("%z", "")) end
  return (s:gsub("%z", ""):gsub("[\128-\255]", function(ch: string): string
    local b = ch:byte()
    return string.char(0xC0 + math.floor(b / 64), 0x80 + b % 64)
  end))
end

--- Pair note-ons with note-offs, first on with first off on each key and
--- channel, so a note struck again before it was let go ends where the file
--- ends it. A note with no length gets a sixty-fourth of a beat; one never
--- let go is held to `end_tick`. Returns the notes in start order.
local record Event
  tick: integer
  on: boolean
  channel: integer
  pitch: integer
  velocity: integer
  attr: Attr
end

local function pair(events: {Event}, end_tick: integer, ppq: number, count: function(string)): {Note}
  local held: {integer:{Note}} = {}
  local notes: {Note} = {}
  for _, e in ipairs(events) do
    local key = e.channel * 128 + e.pitch
    if e.on then
      local list = held[key] or {}
      held[key] = list
      local note: Note = { tick = e.tick, pitch = e.pitch, velocity = e.velocity, channel = e.channel, attr = e.attr }
      list[#list + 1] = note
      notes[#notes + 1] = note
    else
      local list = held[key]
      local note = list and table.remove(list, 1)
      if note then note.length = e.tick - note.tick end
    end
  end
  for _, note in ipairs(notes) do
    if not note.length then
      note.length = math.max(0, end_tick - note.tick)
      count("notes without an end (held to the end)")
    end
    if note.length <= 0 then note.length = math.max(1, ppq / 16) end
  end
  table.sort(notes, function(a: Note, b: Note): boolean
    if a.tick ~= b.tick then return a.tick < b.tick end
    return a.pitch < b.pitch
  end)
  return notes
end

--- Put each lyric on the note it starts: the first at or after it, within
--- a sixteenth, that has none yet and is not a drum's (channel 10).
local function attach_lyrics(track: Track, ppq: number, count: function(string))
  local reach = ppq / 4
  local i = 1
  for _, lyric in ipairs(track.lyrics) do
    local text = lyric.text:gsub("^%s+", ""):gsub("%s+$", "")
    while track.notes[i] and track.notes[i].tick < lyric.tick do i = i + 1 end
    local k, placed = i, false
    while text ~= "" and track.notes[k] and track.notes[k].tick - lyric.tick <= reach do
      if not track.notes[k].lyric and track.notes[k].channel ~= 9 then
        track.notes[k].lyric = text
        placed = true
        break
      end
      k = k + 1
    end
    if text ~= "" and not placed then count("lyrics with no note to go on") end
  end
end

-- A note's attribute has no place in a MIDI 1.0 file. It is kept in a
-- sequencer-specific event (FF 7F) just before the note-on, at its tick:
-- the id for private use (7D), "pawa", then the type and the two bytes of
-- data. Other programs pass over it.
local ATTR_MARK = "\125pawa"

local function attr_meta(attr: Attr): string
  return ATTR_MARK .. string.char(attr.type % 256, math.floor((attr.data or 0) / 256) % 256, (attr.data or 0) % 256)
end

local function meta_attr(body: string): Attr
  if #body ~= #ATTR_MARK + 3 or body:sub(1, #ATTR_MARK) ~= ATTR_MARK then return nil end
  local kind, hi, lo = body:byte(#ATTR_MARK + 1, #ATTR_MARK + 3)
  return kind > 0 and { type = kind, data = hi * 256 + lo } or nil
end

local META_SKIPPED: {integer:string} = {
  [0x01] = "text events", [0x02] = "copyright notices", [0x08] = "program names", [0x09] = "device names",
  [0x20] = "channel prefixes", [0x21] = "port numbers", [0x54] = "SMPTE offsets", [0x59] = "key signatures",
  [0x7F] = "sequencer-specific events",
}

--- The events of one `MTrk` chunk, from `p` up to `stop`, with ticks
--- counted from `offset`.
local function parse_track(data: string, p: integer, stop: integer, offset: integer, file: File, count: function(string)): Track
  local track: Track = { notes = {}, controls = {}, lyrics = {} }
  local tick = offset
  local running: integer
  local events: {Event} = {}
  -- An attribute read, for the next note to start at its tick.
  local record Mark
    tick: integer
    value: Attr
  end
  local attr: Mark
  while p < stop do
    local delta: integer
    delta, p = vlq(data, p, stop)
    if not delta then
      count("a track cut short")
      break
    end
    tick = tick + delta
    local status = p < stop and data:byte(p) or nil
    if not status then
      count("a track cut short")
      break
    end
    if status >= 0x80 then p = p + 1 else status = running end
    if not status then
      count("a track cut short")
      break
    end
    if status == 0xFF then
      local kind = data:byte(p) or 0
      local len: integer
      len, p = vlq(data, p + 1, stop)
      if not len then
        count("a track cut short")
        break
      end
      local body = data:sub(p, math.min(p + len, stop) - 1)
      p = p + len
      if kind == 0x2F then
        break
      elseif kind == 0x51 and len == 3 then
        if file.smpte then
          count("tempo changes (the file is timed in frames)")
        else
          file.tempos[#file.tempos + 1] = { tick = tick, bpm = 60000000 / math.max(1, be(body, 1, 3)) }
        end
      elseif kind == 0x58 and len >= 2 then
        file.signatures[#file.signatures + 1] = { tick = tick, num = math.max(1, body:byte(1)), den = math.floor(2 ^ math.min(6, body:byte(2))) }
      elseif kind == 0x03 then
        track.name = track.name or utf8_text(body)
      elseif kind == 0x04 then
        track.instrument = track.instrument or utf8_text(body)
      elseif kind == 0x05 then
        track.lyrics[#track.lyrics + 1] = { tick = tick, text = utf8_text(body) }
      elseif kind == 0x06 or kind == 0x07 then
        file.markers[#file.markers + 1] = { tick = tick, text = utf8_text(body) }
      elseif kind == 0x7F and meta_attr(body) then
        attr = { tick = tick, value = meta_attr(body) }
      else
        count(META_SKIPPED[kind] or "other meta events")
      end
    elseif status == 0xF0 or status == 0xF7 then
      local len: integer
      len, p = vlq(data, p, stop)
      if not len then
        count("a track cut short")
        break
      end
      p = p + len
      count("sysex")
    elseif status > 0xF0 then
      -- System messages have no place in a file; nothing after one can be trusted.
      count("a track cut short")
      break
    else
      running = status
      local kind, channel = math.floor(status / 16), status % 16
      local two = kind ~= 12 and kind ~= 13
      local d1, d2 = data:byte(p) or 0, two and data:byte(p + 1) or 0
      p = p + (two and 2 or 1)
      if p > stop then
        count("a track cut short")
        break
      end
      d1, d2 = d1 % 128, d2 % 128
      if kind == 9 and d2 > 0 then
        events[#events + 1] = { tick = tick, on = true, channel = channel, pitch = d1, velocity = d2,
          attr = attr and attr.tick == tick and attr.value or nil }
        attr = nil
      elseif kind == 8 or kind == 9 then
        events[#events + 1] = { tick = tick, channel = channel, pitch = d1 }
      elseif kind == 11 then
        track.controls[#track.controls + 1] = { tick = tick, type = "cc", number = d1, value = d2, channel = channel }
      elseif kind == 14 then
        track.controls[#track.controls + 1] = { tick = tick, type = "bend", value = d1 + d2 * 128, channel = channel }
      elseif kind == 13 then
        track.controls[#track.controls + 1] = { tick = tick, type = "pressure", value = d1, channel = channel }
      elseif kind == 10 then
        track.controls[#track.controls + 1] = { tick = tick, type = "pressure", key = d1, value = d2, channel = channel }
      elseif kind == 12 then
        track.controls[#track.controls + 1] = { tick = tick, type = "program", program = d1, channel = channel }
      end
    end
  end
  track.length = tick
  track.notes = pair(events, tick, file.ppq, count)
  attach_lyrics(track, file.ppq, count)
  track.lyrics = nil
  return track
end

--- Sort by tick, keeping the last of several at one tick.
local function settle<T is M.Ticked>(list: {T}): {T}
  local order: {T:integer} = {}
  for i, item in ipairs(list) do order[item] = i end
  table.sort(list, function(a: T, b: T): boolean
    if a.tick ~= b.tick then return a.tick < b.tick end
    return order[a] < order[b]
  end)
  local out: {T} = {}
  for _, item in ipairs(list) do
    if out[#out] and out[#out].tick == item.tick then out[#out] = item else out[#out + 1] = item end
  end
  return out
end

--- Read the bytes of a Standard MIDI File. Returns, in ticks (`ppq` for
--- each beat) from the start:
---
---   { format, ppq, length,
---     tracks = { { name, instrument, length,
---                  notes = { { tick, length, pitch, velocity, channel, lyric, attr } },
---                  controls = { { tick, type, value, channel, number, key, program } } } },
---     tempos = { { tick, bpm } }, signatures = { { tick, num, den } },
---     markers = { { tick, text } }, skipped = { [what] = count } }
---
--- Channels count from 0. The `type` of a control is "cc" (with `number`),
--- "bend", "pressure" or "program" (with `program`). A bend goes from 0 to
--- 16383, with 8192 in the middle. A pressure has `key` for the pressure of
--- one note.
---
--- Values are as in the file. paw reads format 2 files (independent
--- patterns) as one track after the other. paw reads a file timed in frames
--- of SMPTE time code at 120 beats a minute, because its seconds are then
--- correct. Returns nil and a reason when it is not a MIDI file.
function M.parse(data: string): File, string
  -- A RIFF MIDI file (.rmi) holds a plain one.
  if data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "RMID" then
    local at = data:find("MThd", 13, true)
    if at then data = data:sub(at) end
  end
  if #data < 14 or data:sub(1, 4) ~= "MThd" then return nil, "not a MIDI file" end
  local header = be(data, 5, 4)
  local format, ntracks, division = be(data, 9, 2), be(data, 11, 2), be(data, 13, 2)
  if format > 2 then return nil, "not a MIDI file of a format known (it says " .. format .. ")" end
  local file: File = { format = format, tracks = {}, tempos = {}, signatures = {}, markers = {}, skipped = {}, length = 0 }
  local function count(what: string) file.skipped[what] = (file.skipped[what] or 0) + 1 end
  if division >= 32768 then
    local fps: number = 256 - math.floor(division / 256)
    if fps == 29 then fps = 29.97 end
    file.smpte, file.ppq = true, fps * (division % 256) / 2
  else
    file.ppq = division
  end
  if file.ppq <= 0 then return nil, "the file says a beat has no ticks" end
  local pos, offset = 9 + header, 0
  while pos + 8 <= #data + 1 do
    local id, size = data:sub(pos, pos + 3), be(data, pos + 4, 4)
    local stop = math.min(pos + 8 + size, #data + 1)
    if id == "MTrk" then
      local track = parse_track(data, pos + 8, stop, offset, file, count)
      file.tracks[#file.tracks + 1] = track
      file.length = math.max(file.length, track.length)
      if format == 2 then offset = track.length end
    end
    pos = pos + 8 + size
  end
  if #file.tracks == 0 and ntracks > 0 then return nil, "the MIDI file has no tracks in it" end
  if #file.tracks < ntracks then count("tracks missing from the end of the file") end
  if file.smpte then file.tempos = { { tick = 0, bpm = 120 } } end
  file.tempos, file.signatures = settle(file.tempos), settle(file.signatures)
  table.sort(file.markers, function(a: M.Text, b: M.Text): boolean return a.tick < b.tick end)
  return file
end

--- Read a MIDI file from disk: as `parse`, or nil and a reason.
function M.read(path: string): File, string
  local f, err = io.open(path, "rb")
  if not f then return nil, (tostring(err):gsub("^[^:]*: ", "")) end
  local data = f:read("*a")
  f:close()
  return M.parse(data)
end

-- Writing ----------------------------------------------------------------------

local function write_vlq(x: number): string
  local n = math.max(0, math.floor(x + 0.5))
  local bytes = { string.char(n % 128) }
  n = math.floor(n / 128)
  while n > 0 do
    table.insert(bytes, 1, string.char(128 + n % 128))
    n = math.floor(n / 128)
  end
  return table.concat(bytes)
end

local function u32(n: integer): string
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

local function clamp7(v: number): integer return math.max(0, math.min(127, math.floor(v + 0.5))) end

local function meta(kind: integer, body: string): string return "\255" .. string.char(kind) .. write_vlq(#body) .. body end

--- One track's chunk. At a tick: tempo and other meta events first, then
--- notes let go, then controls, then lyrics and the notes they start.
local record Out
  tick: integer
  rank: integer
  bytes: string
  status: integer
  order: integer
end

local function encode_track(track: Track, conductor: File): string
  local events: {Out} = {}
  local function add(tick: number, rank: integer, bytes: string, status?: integer)
    events[#events + 1] = { tick = math.floor(tick + 0.5), rank = rank, bytes = bytes, status = status, order = #events }
  end
  if track.name and track.name ~= "" then add(0, 0, meta(0x03, track.name)) end
  if conductor then
    for _, t in ipairs(conductor.tempos or {}) do
      local us = math.floor(60000000 / t.bpm + 0.5)
      add(t.tick, 0, meta(0x51, string.char(math.floor(us / 65536) % 256, math.floor(us / 256) % 256, us % 256)))
    end
    for _, s in ipairs(conductor.signatures or {}) do
      local power = math.floor(math.log(s.den) / math.log(2) + 0.5)
      add(s.tick, 0, meta(0x58, string.char(s.num, power, 24, 8)))
    end
    for _, m in ipairs(conductor.markers or {}) do add(m.tick, 0, meta(0x06, m.text)) end
  end
  for _, n in ipairs(track.notes or {}) do
    local ch = n.channel or 0
    add(n.tick + n.length, 1, string.char(n.pitch, 0), 0x80 + ch)
    if n.lyric then add(n.tick, 3, meta(0x05, n.lyric)) end
    if n.attr and (n.attr.type or 0) > 0 then add(n.tick, 3, meta(0x7F, attr_meta(n.attr))) end
    add(n.tick, 3, string.char(n.pitch, clamp7(n.velocity)), 0x90 + ch)
  end
  for _, c in ipairs(track.controls or {}) do
    local ch = c.channel or 0
    if c.type == "cc" then
      add(c.tick, 2, string.char(c.number, clamp7(c.value)), 0xB0 + ch)
    elseif c.type == "bend" then
      local v: integer = math.max(0, math.min(16383, math.floor(c.value + 0.5)))
      add(c.tick, 2, string.char(v % 128, math.floor(v / 128)), 0xE0 + ch)
    elseif c.type == "pressure" and c.key then
      add(c.tick, 2, string.char(c.key, clamp7(c.value)), 0xA0 + ch)
    elseif c.type == "pressure" then
      add(c.tick, 2, string.char(clamp7(c.value)), 0xD0 + ch)
    elseif c.type == "program" then
      add(c.tick, 2, string.char(c.program), 0xC0 + ch)
    end
  end
  table.sort(events, function(a: Out, b: Out): boolean
    if a.tick ~= b.tick then return a.tick < b.tick end
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.order < b.order
  end)
  local body: {string} = {}
  local tick = 0
  local running: integer
  for _, e in ipairs(events) do
    local status = ""
    -- Running status: a channel message like the one before leaves out its status byte.
    if e.status and e.status ~= running then status = string.char(e.status) end
    running = e.status
    body[#body + 1] = write_vlq(e.tick - tick) .. status .. e.bytes
    tick = e.tick
  end
  body[#body + 1] = "\0\255\47\0"
  local chunk = table.concat(body)
  return "MTrk" .. u32(#chunk) .. chunk
end

--- The bytes of a Standard MIDI File from the shape that `parse` returns
--- (`format` 0 or 1, `ppq`, `tracks`, and `tempos`, `signatures` and
--- `markers`, which go in the first track). Ticks can be fractions. paw
--- rounds them.
function M.encode(file: File): string
  local tracks: {Track} = file.tracks or {}
  if #tracks == 0 then tracks = { {} } end
  local format = file.format or (#tracks > 1 and 1 or 0)
  if format == 0 and #tracks > 1 then error("a format 0 file has one track", 2) end
  local ppq = math.floor((file.ppq or 960) + 0.5)
  local out = { "MThd", u32(6), string.char(0, format, math.floor(#tracks / 256), #tracks % 256, math.floor(ppq / 256), ppq % 256) }
  for i, track in ipairs(tracks) do out[#out + 1] = encode_track(track, i == 1 and file or nil) end
  return table.concat(out)
end

-- From a file to tracks and clips -----------------------------------------------

--- The data for one track: { name, channel, drums, notes, controls }, in
--- ticks. paw splits the one track of a format 0 file by channel. Each
--- other track with notes is one part. With `merge`, all is one part.
function M.parts(file: File, merge?: boolean): {Part}
  local parts: {Part} = {}
  local function part(name: string, notes: {Note}, controls: {Control})
    local channels: {integer:integer} = {}
    for _, n in ipairs(notes) do channels[n.channel] = (channels[n.channel] or 0) + 1 end
    local main, most, only = 0, -1, true
    for ch, n in pairs(channels) do
      if n > most or (n == most and ch < main) then main, most = ch, n end
    end
    for ch in pairs(channels) do if ch ~= main then only = false end end
    parts[#parts + 1] = {
      name = (name and name ~= "") and name or ("Channel " .. (main + 1)),
      channel = main, drums = only and main == 9, notes = notes, controls = controls,
    }
  end
  if merge then
    local notes: {Note} = {}
    local controls: {Control} = {}
    local name: string
    for _, track in ipairs(file.tracks) do
      for _, n in ipairs(track.notes) do notes[#notes + 1] = n end
      for _, c in ipairs(track.controls) do controls[#controls + 1] = c end
      if #track.notes > 0 then name = name or track.name end
    end
    table.sort(notes, function(a: Note, b: Note): boolean
      if a.tick ~= b.tick then return a.tick < b.tick end
      return a.pitch < b.pitch
    end)
    table.sort(controls, function(a: Control, b: Control): boolean return a.tick < b.tick end)
    if #notes > 0 or #controls > 0 then part(name, notes, controls) end
    return parts
  end
  for _, track in ipairs(file.tracks) do
    if file.format == 0 then
      local record Channel
        notes: {Note}
        controls: {Control}
      end
      local by: {integer:Channel} = {}
      local order: {integer} = {}
      for _, n in ipairs(track.notes) do
        if not by[n.channel] then
          by[n.channel] = { notes = {}, controls = {} }
          order[#order + 1] = n.channel
        end
        table.insert(by[n.channel].notes, n)
      end
      table.sort(order)
      for _, c in ipairs(track.controls) do
        if by[c.channel] then table.insert(by[c.channel].controls, c) else file.skipped["controls on channels with no notes"] = (file.skipped["controls on channels with no notes"] or 0) + 1 end
      end
      for _, ch in ipairs(order) do part(#order == 1 and track.name or nil, by[ch].notes, by[ch].controls) end
    elseif #track.notes > 0 then
      part(track.name, track.notes, track.controls)
    elseif #track.controls > 0 then
      file.skipped["controls on tracks with no notes"] = (file.skipped["controls on tracks with no notes"] or 0) + #track.controls
    end
  end
  return parts
end

--- The bar a beat of the file is in, by the file's own time signatures:
--- its start and end in beats.
local record Segment
  beat: number
  len: number
end

local function bar_of(file: File, beat: number): number, number
  local segs: {Segment} = {}
  for _, s in ipairs(file.signatures) do segs[#segs + 1] = { beat = s.tick / file.ppq, len = s.num * 4 / s.den } end
  if not segs[1] or segs[1].beat > 0 then table.insert(segs, 1, { beat = 0, len = 4 }) end
  local i = 1
  while segs[i + 1] and segs[i + 1].beat <= beat + 1e-9 do i = i + 1 end
  local seg = segs[i]
  local start = seg.beat + math.floor((beat - seg.beat) / seg.len + 1e-9) * seg.len
  local stop = start + seg.len
  if segs[i + 1] and segs[i + 1].beat < stop then stop = segs[i + 1].beat end
  return start, stop
end

--- A clip (as `track:add_clip` takes it) from a part, its file beats moved
--- by `at`: whole bars of the file from the first event to the last.
local function clip_of(file: File, part: Part, at: number): M.ClipSpec
  local ppq = file.ppq
  local first, last: number, number = math.huge, 0
  for _, n in ipairs(part.notes) do
    first, last = math.min(first, n.tick), math.max(last, n.tick + n.length)
  end
  for _, c in ipairs(part.controls) do first, last = math.min(first, c.tick), math.max(last, c.tick) end
  local from = bar_of(file, first / ppq)
  local _, to = bar_of(file, math.max(first / ppq, last / ppq - 1e-6))
  local notes: {M.ClipNote} = {}
  local controls: {M.ClipControl} = {}
  for i, n in ipairs(part.notes) do
    local note_meta: M.NoteMeta
    if n.channel ~= 0 or n.lyric then note_meta = { channel = n.channel ~= 0 and n.channel + 1 or nil, lyric = n.lyric } end
    notes[i] = {
      start = n.tick / ppq - from, length = n.length / ppq, pitch = n.pitch,
      velocity = math.max(1, math.min(127, math.floor(n.velocity))), meta = note_meta, attr = n.attr,
    }
  end
  for i, c in ipairs(part.controls) do
    local control: M.ClipControl = { start = c.tick / ppq - from, type = c.type }
    if c.type == "cc" then
      control.number, control.value = c.number, c.value / 127
    elseif c.type == "bend" then
      control.value = math.max(-1, math.min(1, (c.value - 8192) / 8192))
    elseif c.type == "pressure" then
      control.key, control.value = c.key, c.value / 127
    else
      control.program, control.value = c.program, 0
    end
    controls[i] = control
  end
  return { start = at + from, length = to - from, name = part.name, notes = notes, controls = controls }
end

local function stem(path: string): string return ((path:match("([^/]+)$") or path):gsub("%.[^.]+$", "")) end

--- The file's tempo map in beats from `at`, as `paw.tempo.set_points` takes it.
local function tempo_map(file: File, at: number): {TempoPoint}, {SignaturePoint}
  local tempos: {TempoPoint} = {}
  local signatures: {SignaturePoint} = {}
  for _, t in ipairs(file.tempos) do tempos[#tempos + 1] = { beat = at + t.tick / file.ppq, bpm = math.max(1, math.min(960, t.bpm)) } end
  for _, s in ipairs(file.signatures) do signatures[#signatures + 1] = { beat = at + s.tick / file.ppq, num = s.num, den = s.den } end
  return tempos, signatures
end

--- The tempo map with the file's from `at` on, the project's before.
local function put_tempo_map(file: File, at: number)
  local tempos, signatures = tempo_map(file, at)
  local keep_t: {TempoPoint} = {}
  local keep_s: {SignaturePoint} = {}
  for _, t in ipairs(paw.tempo.points() as {TempoPoint}) do
    if t.beat < at - 1e-9 then keep_t[#keep_t + 1] = { beat = t.beat, bpm = t.bpm, ramp = t.ramp } end
  end
  for _, s in ipairs(paw.tempo.signatures() as {SignaturePoint}) do
    if s.beat < at - 1e-9 then keep_s[#keep_s + 1] = { beat = s.beat, num = s.num, den = s.den } end
  end
  -- The tempo and signature in force where the file starts carry on when it names none there.
  if not tempos[1] or tempos[1].beat > at + 1e-9 then table.insert(tempos, 1, { beat = at, bpm = paw.tempo.at(at) as number }) end
  if not signatures[1] or signatures[1].beat > at + 1e-9 then
    local num, den = paw.tempo.signature_at(at) as (integer, integer)
    if at == 0 or #keep_s == 0 then num, den = 4, 4 end
    table.insert(signatures, 1, { beat = at, num = num, den = den })
  end
  for _, t in ipairs(tempos) do keep_t[#keep_t + 1] = t end
  for _, s in ipairs(signatures) do keep_s[#keep_s + 1] = s end
  paw.tempo.set_points(keep_t, keep_s)
end

--- Add the parts of a file as tracks below `index` (nil: at the end), each
--- with its clip at `at`. Returns the tracks.
local function add_parts(file: File, parts: {Part}, at: number, index: integer): {Untyped}
  local tracks: {Untyped} = {}
  for i, part in ipairs(parts) do
    local track = paw.add_track({ name = part.name, index = index and index + i or nil })
    if part.drums then track:add_device("drums") end
    track:add_clip(clip_of(file, part, at))
    tracks[#tracks + 1] = track
  end
  return tracks
end

local function add_markers(file: File, at: number)
  local markers = paw.markers
  for _, m in ipairs(file.markers) do
    if m.text ~= "" then markers.add(at + m.tick / file.ppq, m.text) end
  end
end

--- What was left out of a file, as one line, or nil.
function M.skipped_text(file: File): string
  local list: {string} = {}
  for what, n in pairs(file.skipped) do list[#list + 1] = n .. " " .. what end
  table.sort(list)
  return #list > 0 and table.concat(list, ", ") or nil
end

local function notes_in(parts: {Part}): integer
  local n = 0
  for _, part in ipairs(parts) do n = n + #part.notes end
  return n
end

--- Open a MIDI file as a new project with no file (see the top of this
--- file). Returns { tracks, notes, skipped }. If paw cannot read the file,
--- it raises an error, and the open project does not change.
function M.open(path: string): M.Opened
  local file, why = M.read(path)
  if not file then error(why, 0) end
  local parts = M.parts(file)
  -- A file cut short or damaged reads as one with nothing in it: the
  -- project open stays open.
  if #parts == 0 then error("there are no notes in it", 0) end
  api.project_new()
  api.project_set("name", stem(path))
  put_tempo_map(file, 0)
  local tracks = add_parts(file, parts, 0, nil)
  add_markers(file, 0)
  -- It opens as a project file does: nothing to undo, nothing changed yet.
  api.undo_reset()
  if tracks[1] then paw.cursor.set_track(tracks[1]) end
  local state = paw.state as State
  state.pick_dir = path:match("^(.*)/[^/]*$") or state.pick_dir
  return { tracks = tracks, notes = notes_in(parts), skipped = M.skipped_text(file) }
end

--- Import a MIDI file into the project. Its parts go on new tracks below
--- the track of the cursor, at the cursor (or `opts.start`). With
--- `opts.track`, all of it goes as one clip on that track. The tempo map
--- does not change, unless `opts.tempo`. Then the tempo map of the file
--- applies from its start. paw adds the markers of the file. Returns
--- { tracks, clips, notes, skipped }.
function M.import(path: string, opts?: M.ImportOptions): M.Imported
  opts = opts or {}
  local file, why = M.read(path)
  if not file then error(why, 0) end
  local at = opts.start or (paw.cursor as Cursor).beat
  local given = opts.track
  local track: Untyped = given is Untyped and given or given and paw.track(given) or nil
  local parts = M.parts(file, track ~= nil)
  if #parts == 0 then error("there are no notes in it", 0) end
  if opts.tempo then put_tempo_map(file, at) end
  local tracks: {Untyped} = {}
  local clips: {Untyped} = {}
  if track then
    local clip = clip_of(file, parts[1], at)
    clip.name = stem(path)
    clips[1] = track:add_clip(clip)
    tracks[1] = track
  else
    tracks = add_parts(file, parts, at, paw.cursor.index() as integer)
    for _, t in ipairs(tracks) do clips[#clips + 1] = t:clips()[1] end
  end
  add_markers(file, at)
  if tracks[1] then paw.cursor.set_track(tracks[1]) end
  return { tracks = tracks, clips = clips, notes = notes_in(parts), skipped = M.skipped_text(file) }
end

-- From the project to a file ---------------------------------------------------

local EXPORT_PPQ = 960

--- The channel a track's notes go out on when they do not say: 10 for a
--- track whose instrument is the drum kit, else 1 (counting from 0 here).
local function default_channel(track: Untyped): integer
  for _, device in ipairs(track:devices() as {Device}) do
    if device.kind == "drums" or device.kind == "sampler" then return 9 end
  end
  return 0
end

--- The tempo map in ticks; a ramp is written as a step every sixteenth.
local function export_tempos(to: number): {M.Tempo}
  local points = paw.tempo.points() as {TempoPoint}
  local out: {M.Tempo} = {}
  for i, t in ipairs(points) do
    out[#out + 1] = { tick = t.beat * EXPORT_PPQ, bpm = t.bpm }
    local nxt = points[i + 1]
    if t.ramp and nxt then
      for beat = t.beat + 0.25, nxt.beat - 1e-9, 0.25 do
        out[#out + 1] = { tick = beat * EXPORT_PPQ, bpm = paw.tempo.at(beat) as number }
      end
    elseif t.ramp then
      for beat = t.beat + 0.25, math.max(t.beat, to) - 1e-9, 0.25 do
        out[#out + 1] = { tick = beat * EXPORT_PPQ, bpm = paw.tempo.at(beat) as number }
      end
    end
  end
  return out
end

--- One track of the file from clips of a track (all its MIDI clips when
--- `clips` is nil): what sounds of them, where it sounds.
--- Whether a time in ticks or a value falls between the steps of MIDI 1.0.
local function between(x: number): boolean return math.abs(x - math.floor(x + 0.5)) > 1e-6 end

local function export_track(track: Untyped, only: {integer:boolean}, lost: M.Lost): Track, number
  local out: Track = { name = track.name as string, notes = {}, controls = {} }
  local channel = default_channel(track)
  local last: number = 0
  for _, clip in ipairs(track:clips() as {Untyped}) do
    local c = clip:get() as ClipInfo
    if c.kind == "midi" and not c.muted and (not only or only[clip.id as integer]) then
      for _, n in ipairs(clip:notes() as {M.ClipNote}) do
        if n.start >= -1e-9 and n.start < c.length - 1e-9 then
          local length = math.min(n.length, c.length - n.start)
          local note_meta: M.NoteMeta = n.meta or {}
          out.notes[#out.notes + 1] = {
            tick = (c.start + n.start) * EXPORT_PPQ, length = length * EXPORT_PPQ, pitch = n.pitch,
            velocity = n.velocity, channel = tonumber(note_meta.channel) and note_meta.channel - 1 or channel,
            lyric = type(note_meta.lyric) == "string" and note_meta.lyric or nil, attr = n.attr,
          }
          last = math.max(last, c.start + n.start + length)
          if between((c.start + n.start) * EXPORT_PPQ) or between(length * EXPORT_PPQ) then lost.times = lost.times + 1 end
        end
      end
      for _, k in ipairs(c.control_count > 0 and clip:controls() as {M.ClipControl} or {}) do
        if k.start >= -1e-9 and k.start < c.length - 1e-9 then
          local raw: Control = { tick = (c.start + k.start) * EXPORT_PPQ, type = k.type, channel = channel, key = k.key, number = k.number, program = k.program }
          if k.type == "cc" or k.type == "pressure" then
            raw.value = k.value * 127
          elseif k.type == "bend" then
            raw.value = 8192 + k.value * 8192
          end
          -- A note's own bend or controller has no form in a MIDI 1.0 file; its pressure does.
          local plain = not k.key or k.type == "pressure"
          if plain and (k.type == "cc" or k.type == "bend" or k.type == "pressure" or k.type == "program") then
            out.controls[#out.controls + 1] = raw
            if raw.value and between(raw.value) then lost.values = lost.values + 1 end
          else
            lost.dropped = lost.dropped + 1
          end
        end
      end
    end
  end
  return out, last
end

--- What the last export could not keep, as one line, or nil: MIDI 1.0
--- has 960 ticks to a beat here, values of 7 bits (14 for the pitch
--- bend), and no controllers of one note but its pressure.
function M.lost_text(): string
  local lost = M.last_export
  local out: {string} = {}
  if not lost then return nil end
  if lost.times > 0 then out[#out + 1] = string.format("rounded %d note time%s to a tick", lost.times, lost.times == 1 and "" or "s") end
  if lost.values > 0 then out[#out + 1] = string.format("rounded %d controller value%s to 7 bits", lost.values, lost.values == 1 and "" or "s") end
  if lost.dropped > 0 then out[#out + 1] = string.format("left out %d move%s of a controller of one note or of an RPN/NRPN", lost.dropped, lost.dropped == 1 and "" or "s") end
  return #out > 0 and table.concat(out, ", ") or nil
end

--- Write a format 1 MIDI file with the tempo map, time signatures and
--- markers. It contains the whole project, `opts.tracks` (tracks or ids),
--- or only `opts.clips` (ids). Returns the number of notes written.
function M.export(path: string, opts?: M.ExportOptions): integer
  opts = opts or {}
  local tracks: {Untyped} = {}
  local only: {integer:boolean}
  if opts.clips then
    only = {}
    local seen: {integer:boolean} = {}
    for _, id in ipairs(opts.clips) do
      only[id] = true
      local track = paw.clip(id):track()
      local track_id = track.id as integer
      if not seen[track_id] then
        seen[track_id] = true
        tracks[#tracks + 1] = track
      end
    end
  elseif opts.tracks then
    for _, t in ipairs(opts.tracks) do tracks[#tracks + 1] = t is Untyped and t or paw.track(t) end
  else
    tracks = paw.tracks() as {Untyped}
  end
  local file: File = { format = 1, ppq = EXPORT_PPQ, tracks = { { name = api.project_get("name") as string } }, signatures = {}, markers = {} }
  local notes = 0
  local last: number = 0
  local lost: M.Lost = { times = 0, values = 0, dropped = 0 }
  M.last_export = lost
  for _, track in ipairs(tracks) do
    local t, ends = export_track(track, only, lost)
    if #t.notes > 0 or #t.controls > 0 then
      file.tracks[#file.tracks + 1] = t
      notes, last = notes + #t.notes, math.max(last, ends)
    end
  end
  file.tempos = export_tempos(last)
  for _, s in ipairs(paw.tempo.signatures() as {SignaturePoint}) do file.signatures[#file.signatures + 1] = { tick = s.beat * EXPORT_PPQ, num = s.num, den = s.den } end
  for _, m in ipairs(paw.markers.list() as {MarkerPoint}) do file.markers[#file.markers + 1] = { tick = m.beat * EXPORT_PPQ, text = m.name } end
  local f, err = io.open(path, "wb")
  if not f then error((tostring(err):gsub("^[^:]*: ", "")), 0) end
  f:write(M.encode(file))
  f:close()
  return notes
end

return M
