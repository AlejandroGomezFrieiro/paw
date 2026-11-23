-- Reading a REAPER project into paw.
--
--   local result = require("interop.rpp.import").file("song.rpp")
--   print(result.report:text())     -- what could not be carried over, grouped
--
-- Times in a project file are in seconds; here they become beats by the
-- file's tempo map (its TEMPO line and TEMPOENVEX points: tempo changes,
-- ramps and time signatures), which the project takes. MIDI is in ticks per
-- quarter note, so it becomes beats directly, except in sources that ignore
-- the project tempo, which run at a tempo of their own.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local fmt = require("interop.rpp.format")
local midi = require("interop.rpp.midi")
local fx = require("interop.rpp.fx")
local interop = require("interop")
local reports = require("interop.report")
local type types = require("paw.types")

local api = paw.api

local type Node = fmt.Node
local type Report = reports.Report

local record M
  --- A plugin that could not come across, kept in the part's meta
  --- (`rpp_placeholders`) to be written back where it was.
  record Placeholder
    name: string
    format: string
    --- Its place in the chain, from 1.
    position: integer
    reason: string
    bypass: boolean
    --- Its block, as REAPER wrote it.
    rpp: string
  end

  SHAPES: {integer: types.LaneShape}
end

local type Placeholder = M.Placeholder
local type Marker = interop.Marker

--- What an import keeps while it runs.
local record Ctx
  --- The folder of the file, and REAPER's recording folder in it.
  dir: string
  record_path: string
  report: Report
  --- Seconds in the file to beats in the project.
  beat: function(seconds: number): number
  --- The tempo at the start of the project, in BPM.
  tempo: number
  clips: integer
  devices: integer
  --- The parts that got a MIDI clip.
  midi_parts: {integer: boolean}
end

local SUPPORTED_AUDIO: {string: boolean} = {
  wav = true,
  wave = true,
  aif = true,
  aiff = true,
  flac = true,
  mp3 = true,
  ogg = true,
}

--- A gain as decibels, from -120 to 24.
local db = interop.db

local exists = api.fs_exists

local function dirname(path: string): string
  return path:match("^(.*)/[^/]*$") or "."
end

local function basename(path: string): string
  return path:match("([^/]+)$") or path
end

local clamp = paw.util.clamp

--- The first line of an error, as text.
local function first_line(err: string): string
  return (tostring(err):gsub("\n.*", ""))
end

--- Where REAPER finds a media file: an absolute path as it is, a relative
--- one from the project's folder; failing that, a file of the same name in
--- the project's recording folder or the project folder itself.
function M.resolve(file: string, dir: string, record_path?: string): string, string
  file = file:gsub("\\", "/")
  local base = file:match("([^/]+)$") or file
  local tries: {string} = {}
  if file:sub(1, 1) == "/" then
    tries[#tries + 1] = file
  else
    tries[#tries + 1] = dir .. "/" .. file
  end
  if record_path and record_path ~= "" then
    local rp = record_path:gsub("\\", "/")
    tries[#tries + 1] = (rp:sub(1, 1) == "/" and rp or dir .. "/" .. rp) .. "/" .. base
  end
  tries[#tries + 1] = dir .. "/" .. base
  for _, path in ipairs(tries) do
    if exists(path) then
      return path
    end
  end
  return nil, tries[1]
end

-- Items ----------------------------------------------------------------------------

--- A take of an item: its lines (the first take's follow the item's own),
--- and the tokens of the `TAKE` line that starts it.
local record Take
  lines: {Node}
  flags: {fmt.Token}
end

--- Split an item's children into takes. Each `TAKE` line starts another.
--- Returns the takes and the index of the active one.
local function takes_of(item: Node): {Take}, integer
  local current: Take = {lines = {}}
  local takes: {Take} = {current}
  local active = 1
  for _, c in ipairs(item.children) do
    if c:name() == "TAKE" and not c.children then
      current = {lines = {}, flags = c.tokens}
      takes[#takes + 1] = current
      for i = 2, #c.tokens do
        if c.tokens[i] == "SEL" then
          active = #takes
        end
      end
    else
      current.lines[#current.lines + 1] = c
    end
  end
  return takes, active
end

local function take_get(take: Take, name: string): Node
  for _, c in ipairs(take.lines) do
    if c:name() == name then
      return c
    end
  end
end

local function item_label(part_name: string, item: Node, take: Take): string
  local name = take and take_get(take, "NAME")
  return string.format("%s: %s at %.3f s", part_name, name and name:arg(1) or "item", item:getn("POSITION") or 0)
end

-- Envelopes -----------------------------------------------------------------------

local ENVELOPES: {string: types.LaneTarget} = {
  VOLENV2 = "volume",
  PANENV2 = "pan",
  MASTERVOLENV2 = "volume",
  MASTERPANENV2 = "pan",
}

--- REAPER's point shapes as paw's: 0 linear, 1 square (paw's "hold"),
--- 2 slow start and end (paw's "smooth"). Fast start, fast end and Bezier
--- have no match: they become straight lines or smooth, and are counted.
M.SHAPES = {[0] = "linear", [1] = "hold", [2] = "smooth", [5] = "smooth"}

--- The shape of each stretch of a lane, by the place of its point.
local type Shapes = {integer: types.LaneShape}

--- The points of an envelope block, as { beat, value } with `convert`
--- turning a value of the file into paw's, and the shape of each stretch
--- by its point's place.
local function lane_points(
  env: Node, convert: function(number): number, ctx: Ctx, label: string
): {types.LanePoint}, Shapes
  local points: {types.LanePoint} = {}
  local shapes: Shapes = {}
  local odd = 0
  for _, pt in ipairs(env:all("PT")) do
    local t, v, shape = pt:argn(1) or 0, pt:argn(2) or 0, pt:argn(3) or 0
    points[#points + 1] = {ctx.beat(t), convert(v)}
    local as = M.SHAPES[math.tointeger(shape)]
    if not as or shape == 5 then
      odd = odd + 1
    end
    if as and as ~= "linear" then
      shapes[#points] = as
    end
  end
  if odd > 0 then
    ctx.report:count("Envelope curve shapes (fast start, fast end and Bezier made straight or smooth)", label, odd)
  end
  return points, shapes
end

--- Add a lane with its points and their shapes. Returns its id, or nil.
local function add_lane(part: integer, opts: types.LaneOptions, shapes: Shapes, ctx: Ctx, label: string): integer
  local ok, id = pcall(api.lane_add, part, opts) as (boolean, integer)
  if not ok then
    ctx.report:add("Envelopes", label .. ": " .. tostring(id))
    return nil
  end
  if next(shapes) then
    local stored = api.lane_points(id)
    local list: {types.LaneSegment} = {}
    for i, shape in pairs(shapes) do
      if stored[i] and i < #stored then
        list[#list + 1] = {beat = stored[i][1], shape = shape, tension = 0}
      end
    end
    if #list > 0 then
      api.lane_set_shapes(id, list)
    end
  end
  return id
end

-- Volume points are amplitudes in the file. VOLTYPE 1 ("fader scaling")
-- changes only how REAPER draws them and what its API calls take: a point
-- inserted through the API as ScaleToEnvelopeMode(1, 0.3) is saved as 0.3.
-- REAPER's pan envelopes run from +1 (left) to -1 (right).
local CONVERT: {string: function(number): number} = {
  volume = function(v: number): number return db(v) end,
  pan = function(v: number): number return clamp(-v, -1, 1) end,
}

local function enabled_of(env: Node): boolean
  local active = env:child("ACT")
  return not active or active:argn(1) ~= 0
end

local function import_envelopes(block: Node, part: integer, ctx: Ctx, label: string)
  for _, env in ipairs(block:blocks()) do
    local name = env:name()
    local target = ENVELOPES[name]
    local has_points = env:child("PT") ~= nil
    if target and has_points then
      local points, shapes = lane_points(env, CONVERT[target], ctx, label .. " " .. target)
      add_lane(
        part, {target = target, enabled = enabled_of(env), points = points}, shapes, ctx, label .. ": " .. target
      )
    elseif has_points and name:match("ENV") and name ~= "TEMPOENVEX" then
      ctx.report:add("Envelopes other than track volume and pan", label .. ": " .. name)
    end
  end
end

-- Sources --------------------------------------------------------------------------

--- The events of a MIDI source: those of the block, or of the .mid file
--- it refers to. Nil when the file is missing or does not read.
local function source_events(source: Node, ctx: Ctx, label: string): midi.Source
  local src = midi.read_source(source)
  if not src.file then
    return src
  end
  local path = M.resolve(src.file, ctx.dir, ctx.record_path)
  if not path then
    ctx.report:add("Missing media", label .. ": " .. src.file)
    return nil
  end
  local f = assert(io.open(path, "rb"))
  local data = f:read("*a")
  f:close()
  local smf, why = midi.read_smf(data)
  if not smf then
    ctx.report:add("Unreadable media", label .. ": " .. src.file .. ": " .. why)
    return nil
  end
  smf.qn = true
  return smf
end

--- The notes and controller moves a MIDI source holds, in beats from the
--- source's start, and its length in beats.
local function midi_source(source: Node, ctx: Ctx, label: string): {types.Note}, number, {types.Control}
  local src = source_events(source, ctx, label)
  if not src then
    return nil
  end
  -- Ticks are quarter notes; a source that ignores the project tempo runs
  -- at its own, which at the project's tempo is a different number of beats.
  local scale = 1 / src.ppq
  if src.ignore_tempo and src.ignore_tempo > 0 then
    scale = scale * ctx.tempo / src.ignore_tempo
  end
  for what, n in pairs(src.other) do
    ctx.report:count("MIDI other than notes", label .. ": " .. what, n)
  end
  if src.muted > 0 then
    ctx.report:count("Muted MIDI notes (left out)", label, src.muted)
  end
  local notes: {types.Note} = {}
  local controls: {types.Control} = {}
  local channels = 0
  for i, n in ipairs(src.notes) do
    notes[i] = {
      start = n.tick * scale,
      length = n.length * scale,
      pitch = n.pitch,
      velocity = math.floor(n.velocity),
      -- The channel goes in the note's meta, from 1; channel 1 is the default.
      meta = n.channel and n.channel ~= 0 and {channel = n.channel + 1} or nil,
    }
  end
  for i, c in ipairs(src.controls or {}) do
    if c.channel ~= 0 then
      channels = channels + 1
    end
    controls[i] = {
      start = c.tick * scale,
      type = c.type,
      number = c.number,
      value = c.value,
      key = c.key,
      program = c.program,
      bank = c.bank,
    }
  end
  if channels > 0 then
    ctx.report:count("MIDI controllers on channels other than 1 (played on channel 1)", label, channels)
  end
  return notes, src.length * scale, controls
end

--- A note of a source cut to `start` and `stop`, in beats from the clip's
--- start.
local function cut_note(n: types.Note, start: number, stop: number): types.Note
  return {
    pitch = n.pitch,
    start = start,
    length = stop - start,
    velocity = math.max(1, math.min(127, n.velocity)),
    meta = n.meta,
  }
end

--- A controller move of a source at `at` beats from the clip's start.
local function moved(c: types.Control, at: number): types.Control
  return {
    start = at, type = c.type, number = c.number, value = c.value, key = c.key, program = c.program, bank = c.bank
  }
end

--- The repeat of a looped clip, as `paw.api.clip_add` takes it.
local record Looping
  loop: boolean
  loop_length: number
  loop_start: number
end

--- Notes and controller moves of a source as a clip of `len` beats that
--- starts `offset` beats into it. A looped item becomes a looped clip:
--- the source is its repeated stretch, which begins `offset` beats before
--- the clip's start.
local function clip_notes(
  notes: {types.Note}, controls: {types.Control}, source_len: number, offset: number, len: number, loop: boolean
): {types.Note}, {types.Control}, Looping
  local out: {types.Note} = {}
  local moves: {types.Control} = {}
  if loop then
    offset = offset % source_len
    for _, n in ipairs(notes) do
      if n.start < source_len - 1e-9 then
        out[#out + 1] = cut_note(n, n.start - offset, n.start - offset + math.min(n.length, source_len - n.start))
      end
    end
    for _, c in ipairs(controls) do
      if c.start < source_len - 1e-9 then
        moves[#moves + 1] = moved(c, c.start - offset)
      end
    end
    return out, moves, {loop = true, loop_length = source_len, loop_start = -offset}
  end
  for _, n in ipairs(notes) do
    local s = n.start - offset
    local e = s + n.length
    if e > 0 and s < len - 1e-9 then
      -- A note running over the item's start plays from it.
      local start, stop = math.max(0, s), math.min(len, e)
      if stop - start > 1e-9 then
        out[#out + 1] = cut_note(n, start, stop)
      end
    end
  end
  for _, c in ipairs(controls) do
    local at = c.start - offset
    if at >= -1e-9 and at < len - 1e-9 then
      moves[#moves + 1] = moved(c, math.max(0, at))
    end
  end
  return out, moves, {}
end

--- A section of a source: its start and length in seconds.
local record Section
  start: number
  length: number
end

--- What an item plays: the settings of the item and its active take that
--- apply to MIDI and audio both.
local record Item
  part: integer
  part_name: string
  label: string
  name: string
  --- Its start and length in beats.
  start: number
  length: number
  loop: boolean
  muted: boolean
  --- Fades in seconds.
  fade_in: number
  fade_out: number
  --- The gain of the item and of the take, as amplitudes.
  item_volume: number
  take_volume: number
  --- The rate of the take, and the pitch shift in semitones it gives.
  rate: number
  semitones: number
  --- The offset into the source, in seconds.
  offset: number
  --- The source, and its kind ("MIDI", "WAVE", ...).
  source: Node
  kind: string
  section: Section
end

--- A fade's length is its second number, or its third when REAPER made
--- it as a crossfade; its shape is the first.
local function fade_of(line: Node, ctx: Ctx, part_name: string): number
  if not line then
    return 0
  end
  local len = (line:argn(3) or 0) > 0 and line:argn(3) or (line:argn(2) or 0)
  if len > 0 and (line:argn(1) or 1) ~= 1 then
    ctx.report:count("Fade shapes (paw fades on a quarter sine)", part_name)
  end
  return len
end

--- The volume and pan of the active take: in the item's VOLPAN for the
--- first take, in TAKEVOLPAN for the others.
local function take_volpan(item: Node, take: Take, active: integer): number, number
  local volpan = item:child("VOLPAN")
  if active == 1 then
    return volpan and volpan:argn(1) or 1, volpan and volpan:argn(2) or 0
  end
  local tvp = take_get(take, "TAKEVOLPAN")
  return tvp and tvp:argn(2) or 1, tvp and tvp:argn(1) or 0
end

--- Count what an item has that paw does not keep: take envelopes and
--- stretch markers.
local function report_item_parts(item: Node, ctx: Ctx, label: string)
  for _, c in ipairs(item.children) do
    local name = c:name()
    if c.children and name:match("ENV$") and c:child("PT") then
      ctx.report:add("Take envelopes", label .. ": " .. name)
    elseif name == "SM" then
      ctx.report:count("Stretch markers", label)
    end
  end
end

--- The source of a take, through a section of it. Nil (and the report
--- says so) when the take has none.
local function item_source(it: Item, take: Take, ctx: Ctx): boolean
  for _, c in ipairs(take.lines) do
    if c.children and c:name() == "SOURCE" then
      it.source = c
    end
  end
  if not it.source then
    ctx.report:add("Empty items", it.label)
    return false
  end
  it.kind = it.source:arg(1)
  -- A section of a source: an offset into it (and maybe reversed), and
  -- for a looped item the stretch that repeats.
  if it.kind == "SECTION" then
    local source = it.source
    it.section = {start = source:getn("STARTPOS") or 0, length = source:getn("LENGTH")}
    it.offset = it.offset + it.section.start
    if (source:getn("MODE") or 0) ~= 0 then
      ctx.report:add("Reversed or looped sections (played forward)", it.label)
    end
    it.source = source:blocks("SOURCE")[1]
    if not it.source then
      ctx.report:add("Empty items", it.label)
      return false
    end
    it.kind = it.source:arg(1)
  end
  return true
end

--- Read an item and its active take. Nil when it plays nothing.
local function read_item(item: Node, part: integer, part_name: string, ctx: Ctx): Item
  local takes, active = takes_of(item)
  local take = takes[active]
  local it: Item = {part = part, part_name = part_name, label = item_label(part_name, item, take)}
  if #takes > 1 then
    ctx.report:count("Takes other than the active one (left out)", part_name, #takes - 1)
  end
  local pos, len = item:getn("POSITION") or 0, item:getn("LENGTH") or 0
  it.loop = item:getn("LOOP") == 1
  it.muted = (item:getn("MUTE") or 0) ~= 0
  it.fade_in, it.fade_out =
    fade_of(item:child("FADEIN"), ctx, part_name), fade_of(item:child("FADEOUT"), ctx, part_name)
  local volpan = item:child("VOLPAN")
  it.item_volume = volpan and volpan:argn(3) or 1
  local take_pan: number
  it.take_volume, take_pan = take_volpan(item, take, active)
  if it.take_volume < 0 then
    ctx.report:add("Polarity (take phase invert)", it.label)
  end
  if math.abs(take_pan) > 1e-9 then
    ctx.report:add("Take pan", it.label)
  end
  -- PLAYRATE rate, keep pitch, semitones: an audio clip plays its file
  -- 1/rate times as long, at the same pitch or (rate not keeping pitch)
  -- 12 log2(rate) semitones higher, plus the pitch shift.
  local rate_line = take_get(take, "PLAYRATE")
  it.rate = rate_line and rate_line:argn(1) or 1
  if it.rate <= 0 then
    it.rate = 1
  end
  it.semitones = rate_line and rate_line:argn(3) or 0
  if rate_line and rate_line:argn(2) == 0 then
    it.semitones = it.semitones + 12 * math.log(it.rate) / math.log(2)
  end
  local chanmode = take_get(take, "CHANMODE")
  if chanmode and (chanmode:argn(1) or 0) ~= 0 then
    ctx.report:add("Take channel mode", it.label)
  end
  report_item_parts(item, ctx, it.label)
  local soffs = take_get(take, "SOFFS")
  it.offset = soffs and soffs:argn(1) or 0
  local name_line = take_get(take, "NAME")
  it.name = name_line and name_line:arg(1) or nil
  if not item_source(it, take, ctx) then
    return nil
  end
  it.start = ctx.beat(pos)
  it.length = ctx.beat(pos + len) - it.start
  if it.length <= 0 then
    return nil
  end
  return it
end

--- A MIDI item as a MIDI clip.
local function import_midi_item(it: Item, ctx: Ctx)
  local notes, source_len, controls = midi_source(it.source, ctx, it.label)
  if not notes then
    return
  end
  if math.abs(db(it.item_volume * math.abs(it.take_volume))) > 0.01 then
    ctx.report:add("Item volume on MIDI items", it.label)
  end
  if math.abs(it.rate - 1) > 1e-9 then
    ctx.report:add("Play rate of MIDI items (played at 1x)", string.format("%s: rate %g", it.label, it.rate))
  end
  if math.abs(it.semitones) > 1e-9 then
    ctx.report:add("Pitch shift of MIDI items", it.label)
  end
  if it.fade_in > 0 or it.fade_out > 0 then
    ctx.report:count("Fades on MIDI items", it.part_name)
  end
  local offset = it.offset * api.tempo_at(it.start) / 60
  local list, moves, looping = clip_notes(notes, controls, source_len, offset, it.length, it.loop and source_len > 0)
  local ok, id = pcall(
    api.clip_add,
    it.part,
    {
      name = it.name,
      start = it.start,
      length = it.length,
      notes = list,
      controls = moves,
      loop = looping.loop,
      loop_length = looping.loop_length,
      loop_start = looping.loop_start,
    } as types.ClipOptions
  ) as (boolean, integer)
  if not ok then
    ctx.report:add("Items that could not be added", it.label .. ": " .. tostring(id))
    return
  end
  if it.muted then
    api.clip_set(id, {muted = true})
  end
  ctx.clips = ctx.clips + 1
  ctx.midi_parts[it.part] = true
end

--- The file of an audio source that paw plays, found on disk. Nil (and the
--- report says why) when there is none.
local function audio_file(it: Item, ctx: Ctx): string
  local file = it.source:get("FILE")
  if not file then
    ctx.report:add("Unsupported sources", it.label .. ": " .. tostring(it.kind))
    return nil
  end
  local ext = (file:match("%.([%w]+)$") or ""):lower()
  if not SUPPORTED_AUDIO[ext] then
    ctx.report:add("Unsupported sources", it.label .. ": " .. tostring(it.kind) .. " " .. file)
    return nil
  end
  local path = M.resolve(file, ctx.dir, ctx.record_path)
  if not path then
    ctx.report:add("Missing media", it.label .. ": " .. file)
    return nil
  end
  return path
end

--- A looped audio item that plays past its file in one clip per pass, at
--- a rate a looped clip of paw does not take. Returns the clips.
local function audio_passes(it: Item, opts: types.ClipOptions, natural: number): {integer}
  local ids: {integer} = {}
  local whole = natural + it.offset / it.rate * api.tempo_at(it.start) / 60
  local at, stop = it.start + natural, it.start + it.length
  while at < stop - 1e-9 and whole > 1e-9 do
    ids[#ids + 1] = api.clip_add(
      it.part,
      {
        name = opts.name,
        start = at,
        file = opts.file,
        offset = 0,
        gain = opts.gain,
        stretch = opts.stretch,
        pitch = opts.pitch,
        length = math.min(whole, stop - at),
      }
    )
    at = at + whole
  end
  return ids
end

--- An audio item as an audio clip: looped, cut to the item's length, or
--- one clip per pass of a loop at another rate.
local function import_audio_item(it: Item, ctx: Ctx)
  local path = audio_file(it, ctx)
  if not path then
    return
  end
  local gain = db(it.item_volume * math.abs(it.take_volume))
  local function beats_from(at: number, seconds: number): number
    return ctx.beat(api.tempo_seconds(at) + seconds) - at
  end
  local opts: types.ClipOptions = {
    name = it.name,
    start = it.start,
    file = path,
    offset = it.offset,
    gain = gain,
    stretch = math.abs(it.rate - 1) > 1e-9 and 1 / it.rate or nil,
    pitch = it.semitones,
  }
  local ok, id = pcall(api.clip_add, it.part, opts) as (boolean, integer)
  if not ok then
    ctx.report:add("Unreadable media", it.label .. ": " .. first_line(tostring(id)))
    return
  end
  ctx.clips = ctx.clips + 1
  local natural = api.clip_get(id).length
  local ids = {id}
  local section = it.section
  -- A looped item plays the source (or its section) again from its start.
  local repeat_seconds = section and section.length
    or (api.tempo_seconds(it.start + natural) - api.tempo_seconds(it.start) + it.offset)
  if
    it.loop and math.abs(it.rate - 1) <= 1e-9 and repeat_seconds > 1e-6 and (it.length > natural + 1e-9 or section)
  then
    -- A looped clip: the repeated stretch begins where the source (or the
    -- section) does, which is the take's offset into it before the clip.
    local base = section and section.start or 0
    local into = (it.offset - base) % repeat_seconds
    api.clip_remove(id)
    opts.length, opts.loop = it.length, true
    opts.loop_length = beats_from(it.start, repeat_seconds)
    opts.loop_start = -beats_from(it.start, into)
    opts.offset = base + into
    ids = {api.clip_add(it.part, opts)}
  elseif it.length <= natural + 1e-9 or not it.loop then
    api.clip_set(id, {length = it.length})
  else
    for _, piece in ipairs(audio_passes(it, opts, natural)) do
      ids[#ids + 1] = piece
    end
  end
  if it.fade_in > 0 then
    api.clip_set(ids[1], {fade_in = math.min(beats_from(it.start, it.fade_in), it.length)})
  end
  if it.fade_out > 0 then
    local last = api.clip_get(ids[#ids])
    local stop = last.start + last.length
    api.clip_set(ids[#ids], {fade_out = math.min(stop - ctx.beat(api.tempo_seconds(stop) - it.fade_out), last.length)})
  end
  if it.muted then
    for _, c in ipairs(ids) do
      api.clip_set(c, {muted = true})
    end
  end
end

local function import_item(item: Node, part: integer, part_name: string, ctx: Ctx)
  local it = read_item(item, part, part_name, ctx)
  if not it then
    return
  end
  if it.kind == "MIDI" then
    import_midi_item(it, ctx)
  else
    import_audio_item(it, ctx)
  end
end

-- Parts ---------------------------------------------------------------------------

--- The parameter of `params` that a `PARMENV` names: `index[:ident]`.
--- REAPER counts the parameters of a plugin from 0 in the plugin's own
--- order, which is the order paw lists them in, and after the colon gives
--- the plugin's own id for a CLAP or VST3 parameter (signed, 32 bits).
--- The id wins: it finds the parameter in a version of the plugin that
--- orders them otherwise.
function M.param_of(token: fmt.Token, params: {types.ParamInfo}): types.ParamInfo
  local place, ident = tostring(token):match("^(%d+):?(.*)$")
  local n = tonumber(ident)
  if n then
    if n < 0 then
      n = n + 2 ^ 32
    end
    local id = string.format("%d", math.floor(n))
    for _, p in ipairs(params) do
      if p.id == id then
        return p
      end
    end
  end
  local index = math.tointeger(tonumber(place))
  local info = index and params[index + 1]
  -- A name after the colon (REAPER's own "wet", "bypass") must be the parameter's.
  if info and ident ~= "" and not n and info.id ~= ident and info.key ~= ident then
    return nil
  end
  return info
end

--- A plugin parameter envelope (`<PARMENV index[:ident] min max default`,
--- after the plugin it belongs to) as a lane of the device (see
--- `param_of`); the values go from min to max, which become the range of
--- the parameter in paw.
local function import_param_env(env: Node, device: integer, part: integer, part_name: string, ctx: Ctx)
  local where = part_name .. ": " .. tostring(env:arg(1))
  local params = device and api.device_get(device).param_info or {}
  local info = M.param_of(env.tokens[2], params)
  if not info then
    ctx.report:add(
      "Plugin parameter automation",
      where .. (device and " (no such parameter here)" or " (its plugin did not come across)")
    )
    return
  end
  local lo, hi = env:argn(2) or 0, env:argn(3) or 1
  if hi <= lo then
    lo, hi = 0, 1
  end
  local function convert(v: number): number
    local f = clamp((v - lo) / (hi - lo), 0, 1)
    return info.min + f * (info.max - info.min)
  end
  local points, shapes = lane_points(env, convert, ctx, where)
  add_lane(
    part,
    {target = "param", device = device, param = info.key, enabled = enabled_of(env), points = points},
    shapes,
    ctx,
    where
  )
end

local function import_chain(
  chain: Node, part: integer, part_name: string, ctx: Ctx, chain_bypassed: boolean
): {Placeholder}
  local bypass, offline = false, false
  local position = 0
  local placeholders: {Placeholder} = {}
  local last: integer -- the device of the plugin before, for its envelopes
  for _, c in ipairs(chain.children) do
    local name = c:name()
    if name == "BYPASS" and not c.children then
      bypass, offline = c:argn(1) == 1, c:argn(2) == 1
    elseif c.children and fx.PLUGIN_BLOCKS[name] then
      position = position + 1
      local notes: {string} = {}
      local d = fx.describe(c)
      local id: integer
      local why: string
      if offline then
        why = "offline in REAPER"
      else
        id, why = fx.import(c, part, bypass or chain_bypassed, notes)
      end
      local where = string.format("%s: %s", part_name, d.display)
      last = id
      if id then
        ctx.devices = ctx.devices + 1
        for _, note in ipairs(notes) do
          ctx.report:add("Plugin settings", where .. ": " .. note)
        end
      else
        ctx.report:add("Plugins left as placeholders", where .. " (" .. why .. ")")
        placeholders[#placeholders + 1] = {
          name = d.display,
          format = d.format,
          position = position,
          reason = why,
          bypass = bypass,
          rpp = fmt.write(c),
        }
      end
    elseif c.children and name == "PARMENV" and c:child("PT") then
      import_param_env(c, last, part, part_name, ctx)
    end
  end
  return placeholders
end

--- Keep the plugins that could not come across in the part's meta.
local function keep_placeholders(part: integer, holders: {Placeholder})
  if #holders == 0 then
    return
  end
  local meta = api.part_get(part).meta or {}
  meta.rpp_placeholders = holders
  api.part_set(part, {meta = meta})
end

-- Project --------------------------------------------------------------------------

--- The file's tempo map, in beats. Points are in seconds in the file; the
--- core places each one's beat from the stretch before it, held or ramped
--- linearly in time (REAPER's shapes 1 and 0).
local function tempo_map(project: Node, ctx: Ctx): types.TempoMapInSeconds
  local tempo_line = project:child("TEMPO")
  local bpm = tempo_line and tempo_line:argn(1) or 120
  local num, den = tempo_line and tempo_line:argn(2) or 4, tempo_line and tempo_line:argn(3) or 4
  local tempos: {types.TempoSecondsPoint} = {{seconds = 0, bpm = bpm, ramp = false}}
  local sigs: {types.SigSecondsPoint} = {{seconds = 0, num = math.floor(num), den = math.floor(den)}}
  local env = project:child("TEMPOENVEX")
  local shapes = 0
  for _, pt in ipairs(env and env:all("PT") or {}) do
    local t, v, shape, sig = math.max(0, pt:argn(1) or 0), pt:argn(2), pt:argn(3) or 1, pt:argn(4)
    if shape ~= 0 and shape ~= 1 then
      shapes = shapes + 1
    end
    tempos[#tempos + 1] = {seconds = t, bpm = v or tempos[#tempos].bpm, ramp = shape == 0}
    if sig and sig > 0 then
      local s: types.SigSecondsPoint = {seconds = t, num = math.floor(sig % 65536), den = math.floor(sig / 65536)}
      if s.num >= 1 and s.num <= 64 and s.den >= 1 and s.den <= 64 then
        sigs[#sigs + 1] = s
      end
    end
  end
  if shapes > 0 then
    ctx.report:count("Tempo curve shapes (made straight ramps)", "tempo", shapes)
  end
  return api.tempo_from_seconds(tempos, sigs)
end

--- REAPER's colour of a part, marker or region (a native colour, which
--- on Linux is red + green * 256 + blue * 65536, with 0x1000000 set when
--- the colour is in use) as #rrggbb, or nil.
function M.colour(native: number | string): string
  local n = math.floor(tonumber(native) or 0)
  if n < 0x1000000 then
    return nil
  end
  n = n % 0x1000000
  return string.format("#%02x%02x%02x", n % 256, math.floor(n / 256) % 256, math.floor(n / 65536))
end

--- Markers and regions as paw keeps them (`paw.markers`), in beats.
local function read_markers(project: Node, ctx: Ctx): {Marker}
  local list: {Marker} = {}
  local open: {number: Marker} = {}
  for _, line in ipairs(project:all("MARKER")) do
    local id, t, name, flags = line:argn(1), line:argn(2) or 0, line:arg(3) or "", line:argn(4) or 0
    local beat = ctx.beat(t)
    if flags % 2 == 1 then
      local r = open[id]
      if r then
        r.length = math.max(0, beat - r.beat)
        open[id] = nil
      else
        r = {name = name, beat = beat, color = M.colour(line:argn(5)), length = 0}
        open[id] = r
        list[#list + 1] = r
      end
    else
      list[#list + 1] = {name = name, beat = beat, color = M.colour(line:argn(5))}
    end
  end
  table.sort(list, function(a: Marker, b: Marker): boolean return a.beat < b.beat end)
  for i, m in ipairs(list) do
    m.id = i
  end
  return list
end

--- The file's markers and regions, after those of the project.
local function import_markers(project: Node, ctx: Ctx)
  local markers = read_markers(project, ctx)
  if #markers == 0 then
    return
  end
  interop.add_markers(markers)
end

--- A new project with the file's tempo map, name and loop; when merged,
--- the project keeps its own (the report says so).
local function begin_project(project: Node, path: string, merge: boolean, ctx: Ctx)
  local map = tempo_map(project, ctx)
  local bpm = map.tempos[1].bpm
  if merge then
    ctx.tempo = paw.project.tempo
    if #map.tempos > 1 or #map.signatures > 1 or math.abs(bpm - ctx.tempo) > 1e-9 then
      ctx.report:add(
        "Tempo",
        string.format(
          "the project keeps its own tempo map (%g BPM at the start); the file's (%g BPM, %d changes) is not used",
          ctx.tempo,
          bpm,
          #map.tempos + #map.signatures - 2
        )
      )
    end
    return
  end
  api.project_new()
  ctx.tempo = bpm
  api.tempo_set_points(map.tempos, map.signatures)
  api.project_set({name = (basename(path):gsub("%.[Rr][Pp][Pp]$", ""))})
  -- Loop points are the project's "loop" selection; LOOP is the repeat switch.
  local sel = project:child("SELECTION")
  local a, b = sel and sel:argn(1), sel and sel:argn(2)
  if a and b and b > a then
    api.transport_set({loop_start = ctx.beat(a)})
    api.transport_set({loop_end = ctx.beat(b)})
  end
  api.transport_set({loop_enabled = project:getn("LOOP") == 1 and a ~= nil and b ~= nil and b > a})
end

--- The master part: its volume, pan, mute, plugins and envelopes.
local function import_master(project: Node, ctx: Ctx)
  local mv = project:child("MASTER_VOLUME")
  if mv then
    api.part_set(0, {volume = db(mv:argn(1))})
    api.part_set(0, {pan = clamp(mv:argn(2) or 0, -1, 1)})
  end
  if ((project:getn("MASTERMUTESOLO") or 0) % 2) == 1 then
    api.part_set(0, {mute = true})
  end
  local mfx = project:child("MASTERFXLIST")
  if mfx then
    keep_placeholders(0, import_chain(mfx, 0, "Master", ctx, project:getn("MASTER_FX") == 0))
  end
  import_envelopes(project, 0, ctx, "Master")
end

--- A part of the file as it became a part of paw.
local record Part
  block: Node
  id: integer
  name: string
  --- The place of its folder part in the list, or nil.
  parent: integer
end

--- Parts, in order, with their folder parents (`ISBUS` opens a folder
--- with 1 and closes that many with a negative depth).
local function add_parts(project: Node): {Part}
  local parts: {Part} = {}
  local stack: {integer} = {}
  for _, block in ipairs(project:blocks("TRACK")) do
    local t: Part = {block = block, parent = stack[#stack]}
    t.name = block:get("NAME") or ""
    local vp = block:child("VOLPAN")
    t.id = api.part_add(
      {
        name = t.name ~= "" and t.name or nil,
        volume = db(vp and vp:argn(1) or 1),
        pan = clamp(vp and vp:argn(2) or 0, -1, 1),
      }
    )
    if t.name == "" then
      t.name = api.part_get(t.id).name
    end
    local colour = M.colour(block:getn("PEAKCOL"))
    if colour then
      api.part_set(t.id, {color = colour})
    end
    parts[#parts + 1] = t
    local isbus = block:child("ISBUS")
    local depth = isbus and isbus:argn(2) or 0
    if depth > 0 then
      stack[#stack + 1] = #parts
    elseif depth < 0 then
      for _ = 1, -depth do
        stack[#stack] = nil
      end
    end
  end
  return parts
end

--- Mute, solo, arm, input and monitoring of a part.
local function part_state(t: Part)
  local block = t.block
  local ms = block:child("MUTESOLO")
  if ms and (ms:argn(1) or 0) ~= 0 then
    api.part_set(t.id, {mute = true})
  end
  if ms and (ms:argn(2) or 0) ~= 0 then
    api.part_set(t.id, {solo = true})
  end
  local rec = block:child("REC")
  if not rec then
    return
  end
  if rec:argn(1) == 1 then
    api.part_set(t.id, {armed = true})
  end
  local input = math.floor(rec:argn(2) or -1)
  if input >= 0 and input < 512 then
    pcall(api.part_set, t.id, {input = tostring(input + 1)})
  elseif input >= 1024 and input < 2048 then
    local first = input - 1024 + 1
    pcall(api.part_set, t.id, {input = first .. "/" .. (first + 1)})
  end
  -- A MIDI input (4096 and up): paw records MIDI on armed parts without
  -- an audio input.
  if rec:argn(3) == 1 and input >= 0 and input < 4096 then
    pcall(api.part_set, t.id, {monitor = true})
  end
end

--- The sends of each part, by the id of the part that sends.
local type Sends = {integer: {types.Send}}

--- The receives of a part (`AUXRECV`) as sends of the parts they come
--- from.
local function read_receives(t: Part, parts: {Part}, sends: Sends, ctx: Ctx)
  for _, aux in ipairs(t.block:all("AUXRECV")) do
    local src = parts[math.floor(aux:argn(1) or -1) + 1]
    if not src then
      ctx.report:add("Routing", t.name .. ": receive from a track that does not exist")
    else
      local mode, vol, pan, mute = aux:argn(2) or 0, aux:argn(3) or 1, aux:argn(4) or 0, aux:argn(5) or 0
      local what = src.name .. " -> " .. t.name
      if mute ~= 0 then
        ctx.report:add("Muted sends (left out)", what)
      elseif (aux:argn(8) or 0) < 0 then
        ctx.report:add("MIDI-only sends", what)
      else
        sends[src.id] = sends[src.id] or {}
        -- Modes: 0 after the fader, 3 before the fader (after the
        -- plugins), 1 before the plugins.
        table.insert(sends[src.id], {target = t.id, level = db(vol), pre = mode ~= 0 or nil})
        if mode == 1 then
          ctx.report:add("Pre-FX sends (made pre-fader, after the plugins)", what)
        end
        if math.abs(pan) > 1e-9 then
          ctx.report:add("Send pan", what)
        end
        if (aux:argn(8) or 0) > 0 or (aux:argn(9) or 0) > 0 then
          ctx.report:add("Send channel mapping (sent as channels 1/2)", what)
        end
      end
    end
  end
end

--- The state and routing of each part: into its folder, and the sends
--- that its receives make.
local function route_parts(parts: {Part}, ctx: Ctx): Sends
  local sends: Sends = {}
  for _, t in ipairs(parts) do
    part_state(t)
    local block = t.block
    local main = block:child("MAINSEND")
    local main_on = not main or main:argn(1) ~= 0
    if t.parent and main_on then
      local folder = parts[t.parent]
      local ok, err = pcall(api.part_set, t.id, {output = folder.id}) as (boolean, string)
      if not ok then
        ctx.report:add("Routing", t.name .. ": into folder " .. folder.name .. ": " .. tostring(err))
      end
    end
    if not main_on then
      ctx.report:add("Tracks with the master/parent send off (here they still play through their output)", t.name)
    end
    if block:child("HWOUT") then
      ctx.report:add("Hardware outputs", t.name)
    end
    read_receives(t, parts, sends, ctx)
  end
  return sends
end

--- The sends, plugins, envelopes and items of each part.
local function fill_parts(parts: {Part}, sends: Sends, ctx: Ctx)
  for _, t in ipairs(parts) do
    if sends[t.id] then
      local ok, err = pcall(api.part_set, t.id, {sends = sends[t.id]}) as (boolean, string)
      if not ok then
        ctx.report:add("Routing", t.name .. ": sends: " .. tostring(err))
      end
    end
    local block = t.block
    local chain = block:child("FXCHAIN")
    if chain then
      keep_placeholders(t.id, import_chain(chain, t.id, t.name, ctx, block:getn("FX") == 0))
    end
    import_envelopes(block, t.id, ctx, t.name)
    for _, item in ipairs(block:blocks("ITEM")) do
      import_item(item, t.id, t.name, ctx)
    end
    if block:child("FREEZE") then
      ctx.report:add("Frozen tracks (the frozen audio is not used)", t.name)
    end
  end
end

--- Something to hear MIDI parts with, when asked for: `instrument` on
--- each MIDI part left with no device.
local function add_instruments(parts: {Part}, instrument: string, ctx: Ctx)
  for _, t in ipairs(parts) do
    if ctx.midi_parts[t.id] and #api.part_get(t.id).devices == 0 then
      local ok, err = pcall(api.device_add, t.id, instrument, {}) as (boolean, string)
      if not ok then
        ctx.report:add("Instruments", t.name .. ": " .. tostring(err))
      end
    end
  end
end

--- Import a parsed project. `opts.path` is where it was read from (media
--- paths are relative to its folder); `opts.merge` adds its parts to the
--- current project instead of replacing it; `opts.instrument` is a device
--- kind to give MIDI parts whose instrument could not be carried over.
function M.doc(doc: Node, opts?: interop.Options): interop.Result
  opts = opts or {}
  local project = doc.project
  if not project then
    error("not a REAPER project: no <REAPER_PROJECT block")
  end
  local path = opts.path or "untitled.rpp"
  local ctx: Ctx = {
    dir = opts.dir or dirname(path),
    report = reports.new("Not carried over from " .. basename(path) .. ":"),
    record_path = project:get("RECORD_PATH"),
    beat = api.tempo_beat,
    clips = 0,
    devices = 0,
    midi_parts = {},
  }
  begin_project(project, path, opts.merge, ctx)
  import_markers(project, ctx)
  if not opts.merge then
    import_master(project, ctx)
  end
  local parts = add_parts(project)
  fill_parts(parts, route_parts(parts, ctx), ctx)
  if opts.instrument then
    add_instruments(parts, opts.instrument, ctx)
  end
  local ids: {integer} = {}
  for i, t in ipairs(parts) do
    ids[i] = t.id
  end
  return {parts = ids, report = ctx.report, clips = ctx.clips, devices = ctx.devices, tempo = ctx.tempo}
end

--- Read a file and import it.
function M.file(path: string, opts?: interop.Options): interop.Result
  opts = opts or {}
  opts.path = path
  return M.doc(fmt.read(path), opts)
end

return M
