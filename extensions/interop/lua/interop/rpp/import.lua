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
local api = paw.api
local fmt = require("interop.rpp.format")
local midi = require("interop.rpp.midi")
local fx = require("interop.rpp.fx")
local reports = require("interop.report")

local M = {}

local SUPPORTED_AUDIO = { wav = true, wave = true, aif = true, aiff = true, flac = true, mp3 = true, ogg = true }

--- A gain as decibels, from -120 to 24.
local db = require("interop").db

local exists = paw.api.fs_exists

local function dirname(path) return path:match("^(.*)/[^/]*$") or "." end

--- Where REAPER finds a media file: an absolute path as it is, a relative
--- one from the project's folder; failing that, a file of the same name in
--- the project's recording folder or the project folder itself.
function M.resolve(file, dir, record_path)
  file = file:gsub("\\", "/")
  local base = file:match("([^/]+)$") or file
  local tries = {}
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
    if exists(path) then return path end
  end
  return nil, tries[1]
end

-- Items ----------------------------------------------------------------------------

--- Split an item's children into takes. The first take's lines follow the
--- item's own; each `TAKE` line starts another. Returns the takes and the
--- index of the active one.
local function takes_of(item)
  local takes, current = {}, { lines = {} }
  takes[1] = current
  local active = 1
  for _, c in ipairs(item.children) do
    if c.tokens[1] == "TAKE" and not c.children then
      current = { lines = {}, flags = c.tokens }
      takes[#takes + 1] = current
      for i = 2, #c.tokens do
        if c.tokens[i] == "SEL" then active = #takes end
      end
    else
      current.lines[#current.lines + 1] = c
    end
  end
  return takes, active
end

local function take_get(take, name)
  for _, c in ipairs(take.lines) do
    if c.tokens[1] == name then return c end
  end
end

local function item_label(track_name, item, take)
  local name = take and take_get(take, "NAME")
  return string.format("%s: %s at %.3f s", track_name, name and name:arg(1) or "item", item:getn("POSITION") or 0)
end

-- Envelopes -----------------------------------------------------------------------

local ENVELOPES = {
  VOLENV2 = "volume",
  PANENV2 = "pan",
  MASTERVOLENV2 = "volume",
  MASTERPANENV2 = "pan",
}

--- REAPER's point shapes as paw's: 0 linear, 1 square (paw's "hold"),
--- 2 slow start and end (paw's "smooth"). Fast start, fast end and Bezier
--- have no match: they become straight lines or smooth, and are counted.
local SHAPES = { [0] = "linear", [1] = "hold", [2] = "smooth", [5] = "smooth" }
M.SHAPES = SHAPES

--- The points of an envelope block, as { beat, value } with `convert`
--- turning a value of the file into paw's, and the shape of each stretch
--- by its point's place.
local function lane_points(env, convert, ctx, label)
  local points, shapes, odd = {}, {}, 0
  for _, pt in ipairs(env:all("PT")) do
    local t, v, shape = pt:argn(1) or 0, pt:argn(2) or 0, pt:argn(3) or 0
    points[#points + 1] = { ctx.beat(t), convert(v) }
    local as = SHAPES[shape]
    if not as or shape == 5 then odd = odd + 1 end
    if as and as ~= "linear" then shapes[#points] = as end
  end
  if odd > 0 then
    ctx.report:count("Envelope curve shapes (fast start, fast end and Bezier made straight or smooth)", label, odd)
  end
  return points, shapes
end

--- Add a lane with its points and their shapes. Returns its id, or nil.
local function add_lane(track, opts, shapes, ctx, label)
  local ok, id = pcall(api.lane_add, track, opts)
  if not ok then
    ctx.report:add("Envelopes", label .. ": " .. tostring(id))
    return nil
  end
  if next(shapes) then
    local stored, list = api.lane_points(id), {}
    for i, shape in pairs(shapes) do
      if stored[i] and i < #stored then list[#list + 1] = { beat = stored[i][1], shape = shape, tension = 0 } end
    end
    if #list > 0 then api.lane_set_shapes(id, list) end
  end
  return id
end

-- Volume points are amplitudes in the file. VOLTYPE 1 ("fader scaling")
-- changes only how REAPER draws them and what its API calls take: a point
-- inserted through the API as ScaleToEnvelopeMode(1, 0.3) is saved as 0.3.
-- REAPER's pan envelopes run from +1 (left) to -1 (right).
local CONVERT = {
  volume = db,
  pan = function(v) return math.max(-1, math.min(1, -v)) end,
}

local function enabled_of(env)
  local active = env:child("ACT")
  return not active or active:argn(1) ~= 0
end

local function import_envelopes(block, track, ctx, label)
  for _, env in ipairs(block:blocks()) do
    local name = env.tokens[1]
    local target = ENVELOPES[name]
    local has_points = env:child("PT") ~= nil
    if target and has_points then
      local points, shapes = lane_points(env, CONVERT[target], ctx, label .. " " .. target)
      add_lane(
        track,
        { target = target, enabled = enabled_of(env), points = points },
        shapes,
        ctx,
        label .. ": " .. target
      )
    elseif has_points and name:match("ENV") and name ~= "TEMPOENVEX" then
      ctx.report:add("Envelopes other than track volume and pan", label .. ": " .. name)
    end
  end
end

-- Sources --------------------------------------------------------------------------

--- The notes a MIDI source holds, in beats from the source's start, and its
--- length in beats.
local function midi_source(source, ctx, label)
  local src = midi.read_source(source)
  if src.file then
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
    src = smf
    src.qn = true
  end
  -- Ticks are quarter notes; a source that ignores the project tempo runs
  -- at its own, which at the project's tempo is a different number of beats.
  local scale = 1 / src.ppq
  if src.ignore_tempo and src.ignore_tempo > 0 then scale = scale * ctx.tempo / src.ignore_tempo end
  for what, n in pairs(src.other) do
    ctx.report:count("MIDI other than notes", label .. ": " .. what, n)
  end
  if src.muted > 0 then ctx.report:count("Muted MIDI notes (left out)", label, src.muted) end
  local notes, controls, channels = {}, {}, 0
  for i, n in ipairs(src.notes) do
    notes[i] =
      { start = n.tick * scale, length = n.length * scale, pitch = n.pitch, velocity = n.velocity, channel = n.channel }
  end
  for i, c in ipairs(src.controls or {}) do
    if c.channel ~= 0 then channels = channels + 1 end
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

--- Notes and controller moves of a source as a clip of `len` beats that
--- starts `offset` beats into it. A looped item becomes a looped clip:
--- the source is its repeated stretch, which begins `offset` beats before
--- the clip's start.
local function clip_notes(notes, controls, source_len, offset, len, loop)
  local out, moves = {}, {}
  local function note(n, start, stop)
    out[#out + 1] = {
      pitch = n.pitch,
      start = start,
      length = stop - start,
      velocity = math.max(1, math.min(127, n.velocity)),
      meta = n.channel and n.channel ~= 0 and { channel = n.channel + 1 } or nil,
    }
  end
  local function move(c, at)
    moves[#moves + 1] =
      { start = at, type = c.type, number = c.number, value = c.value, key = c.key, program = c.program, bank = c.bank }
  end
  if loop then
    offset = offset % source_len
    for _, n in ipairs(notes) do
      if n.start < source_len - 1e-9 then
        note(n, n.start - offset, n.start - offset + math.min(n.length, source_len - n.start))
      end
    end
    for _, c in ipairs(controls) do
      if c.start < source_len - 1e-9 then move(c, c.start - offset) end
    end
    return out, moves, { loop = true, loop_length = source_len, loop_start = -offset }
  end
  for _, n in ipairs(notes) do
    local s = n.start - offset
    local e = s + n.length
    if e > 0 and s < len - 1e-9 then
      -- A note running over the item's start plays from it.
      local start, stop = math.max(0, s), math.min(len, e)
      if stop - start > 1e-9 then note(n, start, stop) end
    end
  end
  for _, c in ipairs(controls) do
    local at = c.start - offset
    if at >= -1e-9 and at < len - 1e-9 then move(c, math.max(0, at)) end
  end
  return out, moves, {}
end

local function import_item(item, track, track_name, ctx)
  local takes, active = takes_of(item)
  local take = takes[active]
  local label = item_label(track_name, item, take)
  if #takes > 1 then ctx.report:count("Takes other than the active one (left out)", track_name, #takes - 1) end
  local pos, len = item:getn("POSITION") or 0, item:getn("LENGTH") or 0
  local loop = item:getn("LOOP") == 1
  local muted = (item:getn("MUTE") or 0) ~= 0
  -- A fade's length is its second number, or its third when REAPER made
  -- it as a crossfade; its shape is the first.
  local function fade(line)
    if not line then return 0 end
    local len = (line:argn(3) or 0) > 0 and line:argn(3) or (line:argn(2) or 0)
    if len > 0 and (line:argn(1) or 1) ~= 1 then
      ctx.report:count("Fade shapes (paw fades on a quarter sine)", track_name)
    end
    return len
  end
  local fade_in, fade_out = fade(item:child("FADEIN")), fade(item:child("FADEOUT"))
  local volpan = item:child("VOLPAN")
  local item_vol = volpan and volpan:argn(3) or 1
  local take_vol, take_pan
  if active == 1 then
    take_vol, take_pan = volpan and volpan:argn(1) or 1, volpan and volpan:argn(2) or 0
  else
    local tvp = take_get(take, "TAKEVOLPAN")
    take_pan, take_vol = tvp and tvp:argn(1) or 0, tvp and tvp:argn(2) or 1
  end
  if take_vol < 0 then ctx.report:add("Polarity (take phase invert)", label) end
  if math.abs(take_pan) > 1e-9 then ctx.report:add("Take pan", label) end
  -- PLAYRATE rate, keep pitch, semitones: an audio clip plays its file
  -- 1/rate times as long, at the same pitch or (rate not keeping pitch)
  -- 12 log2(rate) semitones higher, plus the pitch shift.
  local rate_line = take_get(take, "PLAYRATE")
  local rate = rate_line and rate_line:argn(1) or 1
  if rate <= 0 then rate = 1 end
  local semitones = rate_line and rate_line:argn(3) or 0
  if rate_line and rate_line:argn(2) == 0 then semitones = semitones + 12 * math.log(rate) / math.log(2) end
  local chanmode = take_get(take, "CHANMODE")
  if chanmode and (chanmode:argn(1) or 0) ~= 0 then ctx.report:add("Take channel mode", label) end
  for _, c in ipairs(item.children) do
    if c.children and c.tokens[1]:match("ENV$") and c:child("PT") then
      ctx.report:add("Take envelopes", label .. ": " .. c.tokens[1])
    elseif c.tokens[1] == "SM" then
      ctx.report:count("Stretch markers", label)
    end
  end
  local soffs = (take_get(take, "SOFFS") and take_get(take, "SOFFS"):argn(1)) or 0
  local name_line = take_get(take, "NAME")
  local name = name_line and name_line:arg(1) or nil
  local source
  for _, c in ipairs(take.lines) do
    if c.children and c.tokens[1] == "SOURCE" then source = c end
  end
  if not source then
    ctx.report:add("Empty items", label)
    return
  end
  local kind = source.tokens[2]
  -- A section of a source: an offset into it (and maybe reversed), and
  -- for a looped item the stretch that repeats.
  local section
  if kind == "SECTION" then
    section = { start = source:getn("STARTPOS") or 0, length = source:getn("LENGTH") }
    soffs = soffs + section.start
    if (source:getn("MODE") or 0) ~= 0 then ctx.report:add("Reversed or looped sections (played forward)", label) end
    source = source:blocks("SOURCE")[1]
    kind = source and source.tokens[2]
    if not source then
      ctx.report:add("Empty items", label)
      return
    end
  end
  local start_b = ctx.beat(pos)
  local len_b = ctx.beat(pos + len) - start_b
  if len_b <= 0 then return end
  if kind == "MIDI" then
    local notes, source_len, controls = midi_source(source, ctx, label)
    if not notes then return end
    if math.abs(db(item_vol * math.abs(take_vol))) > 0.01 then ctx.report:add("Item volume on MIDI items", label) end
    if math.abs(rate - 1) > 1e-9 then
      ctx.report:add("Play rate of MIDI items (played at 1x)", string.format("%s: rate %g", label, rate))
    end
    if math.abs(semitones) > 1e-9 then ctx.report:add("Pitch shift of MIDI items", label) end
    if fade_in > 0 or fade_out > 0 then ctx.report:count("Fades on MIDI items", track_name) end
    local offset = soffs * api.tempo_at(start_b) / 60
    local list, moves, looping = clip_notes(notes, controls, source_len, offset, len_b, loop and source_len > 0)
    local ok, id = pcall(api.clip_add, track, {
      name = name,
      start = start_b,
      length = len_b,
      notes = list,
      controls = moves,
      ["loop"] = looping.loop,
      loop_length = looping.loop_length,
      loop_start = looping.loop_start,
    })
    if not ok then return ctx.report:add("Items that could not be added", label .. ": " .. tostring(id)) end
    if muted then api.clip_set(id, "muted", true) end
    ctx.clips = ctx.clips + 1
    ctx.midi_tracks[track] = true
    return
  end
  local file_line = source:child("FILE")
  local file = file_line and file_line:arg(1)
  local ext = file and (file:match("%.([%w]+)$") or ""):lower()
  if not file then
    ctx.report:add("Unsupported sources", label .. ": " .. tostring(kind))
    return
  end
  if not SUPPORTED_AUDIO[ext] then
    ctx.report:add("Unsupported sources", label .. ": " .. tostring(kind) .. " " .. file)
    return
  end
  local path = M.resolve(file, ctx.dir, ctx.record_path)
  if not path then
    ctx.report:add("Missing media", label .. ": " .. file)
    return
  end
  local gain = db(item_vol * math.abs(take_vol))
  local function beats_from(at, seconds) return ctx.beat(api.tempo_seconds(at) + seconds) - at end
  local opts = {
    name = name,
    start = start_b,
    file = path,
    offset = soffs,
    gain = gain,
    stretch = math.abs(rate - 1) > 1e-9 and 1 / rate or nil,
    pitch = semitones,
  }
  local ok, id = pcall(api.clip_add, track, opts)
  if not ok then return ctx.report:add("Unreadable media", label .. ": " .. tostring(id):gsub("\n.*", "")) end
  ctx.clips = ctx.clips + 1
  local natural = api.clip_get(id).length
  local ids = { id }
  -- A looped item plays the source (or its section) again from its start.
  local repeat_seconds = section and section.length
    or (api.tempo_seconds(start_b + natural) - api.tempo_seconds(start_b) + soffs)
  if loop and math.abs(rate - 1) <= 1e-9 and repeat_seconds > 1e-6 and (len_b > natural + 1e-9 or section) then
    -- A looped clip: the repeated stretch begins where the source (or the
    -- section) does, which is the take's offset into it before the clip.
    local base = section and section.start or 0
    local into = (soffs - base) % repeat_seconds
    api.clip_remove(id)
    opts.length, opts["loop"] = len_b, true
    opts.loop_length = beats_from(start_b, repeat_seconds)
    opts.loop_start = -beats_from(start_b, into)
    opts.offset = base + into
    id = api.clip_add(track, opts)
    ids = { id }
  elseif len_b <= natural + 1e-9 or not loop then
    api.clip_set(id, "length", len_b)
  else
    -- Looped at another rate: one clip per pass.
    local whole = natural + soffs / rate * api.tempo_at(start_b) / 60
    local at, stop = start_b + natural, start_b + len_b
    while at < stop - 1e-9 and whole > 1e-9 do
      local piece = api.clip_add(
        track,
        {
          name = name,
          start = at,
          file = path,
          offset = 0,
          gain = gain,
          stretch = opts.stretch,
          pitch = semitones,
          length = math.min(whole, stop - at),
        }
      )
      ids[#ids + 1] = piece
      at = at + whole
    end
  end
  if fade_in > 0 then api.clip_set(ids[1], "fade_in", math.min(beats_from(start_b, fade_in), len_b)) end
  if fade_out > 0 then
    local last = api.clip_get(ids[#ids])
    local stop = last.start + last.length
    api.clip_set(ids[#ids], "fade_out", math.min(stop - ctx.beat(api.tempo_seconds(stop) - fade_out), last.length))
  end
  if muted then
    for _, c in ipairs(ids) do
      api.clip_set(c, "muted", true)
    end
  end
end

-- Tracks ---------------------------------------------------------------------------

--- The parameter of `params` that a `PARMENV` names: `index[:ident]`.
--- REAPER counts the parameters of a plugin from 0 in the plugin's own
--- order, which is the order paw lists them in, and after the colon gives
--- the plugin's own id for a CLAP or VST3 parameter (signed, 32 bits).
--- The id wins: it finds the parameter in a version of the plugin that
--- orders them otherwise.
local function param_of(token, params)
  local index, ident = tostring(token):match("^(%d+):?(.*)$")
  local n = tonumber(ident)
  if n then
    if n < 0 then n = n + 2 ^ 32 end
    local id = string.format("%d", n)
    for _, p in ipairs(params) do
      if p.id == id then return p end
    end
  end
  index = tonumber(index)
  local info = index and params[index + 1]
  -- A name after the colon (REAPER's own "wet", "bypass") must be the parameter's.
  if info and ident ~= "" and not n and info.id ~= ident and info.key ~= ident then return nil end
  return info
end
M.param_of = param_of

--- A plugin parameter envelope (`<PARMENV index[:ident] min max default`,
--- after the plugin it belongs to) as a lane of the device (see
--- `param_of`); the values go from min to max, which become the range of
--- the parameter in paw.
local function import_param_env(env, device, track, track_name, ctx)
  local where = track_name .. ": " .. tostring(env.tokens[2])
  local params = device and api.device_get(device).param_info or {}
  local info = param_of(env.tokens[2], params)
  if not info then
    ctx.report:add(
      "Plugin parameter automation",
      where .. (device and " (no such parameter here)" or " (its plugin did not come across)")
    )
    return
  end
  local lo, hi = tonumber(env.tokens[3]) or 0, tonumber(env.tokens[4]) or 1
  if hi <= lo then
    lo, hi = 0, 1
  end
  local function convert(v)
    local f = math.max(0, math.min(1, (v - lo) / (hi - lo)))
    return info.min + f * (info.max - info.min)
  end
  local points, shapes = lane_points(env, convert, ctx, where)
  add_lane(
    track,
    { target = "param", device = device, param = info.key, enabled = enabled_of(env), points = points },
    shapes,
    ctx,
    where
  )
end

local function import_chain(chain, track, track_name, ctx, chain_bypassed)
  local bypass, offline = false, false
  local position, placeholders = 0, {}
  local last -- the device of the plugin before, for its envelopes
  for _, c in ipairs(chain.children) do
    local name = c.tokens[1]
    if name == "BYPASS" and not c.children then
      bypass, offline = c:argn(1) == 1, c:argn(2) == 1
    elseif c.children and fx.PLUGIN_BLOCKS[name] then
      position = position + 1
      local notes = {}
      local d = fx.describe(c)
      local id, why
      if offline then
        why = "offline in REAPER"
      else
        id, why = fx.import(c, track, bypass or chain_bypassed, notes)
      end
      local where = string.format("%s: %s", track_name, d.display)
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
      import_param_env(c, last, track, track_name, ctx)
    end
  end
  return placeholders
end

local function set_meta(track, key, value)
  local meta = api.track_get(track, "meta") or {}
  meta[key] = value
  api.track_set(track, "meta", meta)
end

-- Project --------------------------------------------------------------------------

--- The file's tempo map, in beats: { tempos = { { beat, bpm, ramp } },
--- signatures = { { beat, num, den } } }. Points are in seconds in the
--- file; the core places each one's beat from the stretch before it, held
--- or ramped linearly in time (REAPER's shapes 1 and 0).
local function tempo_map(project, ctx)
  local tempo_line = project:child("TEMPO")
  local bpm = tempo_line and tempo_line:argn(1) or 120
  local num, den = tempo_line and tempo_line:argn(2) or 4, tempo_line and tempo_line:argn(3) or 4
  local tempos = { { seconds = 0, bpm = bpm, ramp = false } }
  local sigs = { { seconds = 0, num = math.floor(num), den = math.floor(den) } }
  local env = project:child("TEMPOENVEX")
  local shapes = 0
  for _, pt in ipairs(env and env:all("PT") or {}) do
    local t, v, shape, sig = math.max(0, pt:argn(1) or 0), pt:argn(2), pt:argn(3) or 1, pt:argn(4)
    if shape ~= 0 and shape ~= 1 then shapes = shapes + 1 end
    tempos[#tempos + 1] = { seconds = t, bpm = v or tempos[#tempos].bpm, ramp = shape == 0 }
    if sig and sig > 0 then
      local s = { seconds = t, num = math.floor(sig % 65536), den = math.floor(sig / 65536) }
      if s.num >= 1 and s.num <= 64 and s.den >= 1 and s.den <= 64 then sigs[#sigs + 1] = s end
    end
  end
  if shapes > 0 then ctx.report:count("Tempo curve shapes (made straight ramps)", "tempo", shapes) end
  return api.tempo_from_seconds(tempos, sigs)
end

--- REAPER's colour of a track, marker or region (a native colour, which
--- on Linux is red + green * 256 + blue * 65536, with 0x1000000 set when
--- the colour is in use) as #rrggbb, or nil.
function M.colour(native)
  native = tonumber(native) or 0
  if native < 0x1000000 then return nil end
  native = native % 0x1000000
  return string.format("#%02x%02x%02x", native % 256, math.floor(native / 256) % 256, math.floor(native / 65536))
end

--- Markers and regions as paw keeps them (`paw.markers`): { id, beat,
--- name, color, length (a region) }, in beats.
local function import_markers(project, ctx)
  local list, open = {}, {}
  for _, line in ipairs(project:all("MARKER")) do
    local id, t, name, flags = line:argn(1), line:argn(2) or 0, line:arg(3) or "", line:argn(4) or 0
    local beat = ctx.beat(t)
    if flags % 2 == 1 then
      local r = open[id]
      if r then
        r.length = math.max(0, beat - r.beat)
        open[id] = nil
      else
        r = { name = name, beat = beat, color = M.colour(line:argn(5)), length = 0 }
        open[id] = r
        list[#list + 1] = r
      end
    else
      list[#list + 1] = { name = name, beat = beat, color = M.colour(line:argn(5)) }
    end
  end
  table.sort(list, function(a, b) return a.beat < b.beat end)
  for i, m in ipairs(list) do
    m.id = i
  end
  return list
end

--- Import a parsed project. `opts.path` is where it was read from (media
--- paths are relative to its folder); `opts.merge` adds its tracks to the
--- current project instead of replacing it; `opts.instrument` is a device
--- kind to give MIDI tracks whose instrument could not be carried over.
function M.doc(doc, opts)
  opts = opts or {}
  local project = doc.project
  if not project then error("not a REAPER project: no <REAPER_PROJECT block") end
  local path = opts.path or "untitled.rpp"
  local ctx = {
    dir = opts.dir or dirname(path),
    report = reports.new("Not carried over from " .. (path:match("([^/]+)$") or path) .. ":"),
    record_path = project:get("RECORD_PATH"),
    clips = 0,
    devices = 0,
    midi_tracks = {},
  }
  local map = tempo_map(project, ctx)
  local bpm = map.tempos[1].bpm
  -- Seconds in the file to beats in the project.
  ctx.beat = api.tempo_beat
  if opts.merge then
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
  else
    api.project_new()
    ctx.tempo = bpm
    api.tempo_set_points(map.tempos, map.signatures)
    api.project_set("name", ((path:match("([^/]+)$") or path):gsub("%.[Rr][Pp][Pp]$", "")))
    -- Loop points are the project's "loop" selection; LOOP is the repeat switch.
    local sel = project:child("SELECTION")
    local a, b = sel and sel:argn(1), sel and sel:argn(2)
    if a and b and b > a then
      api.transport_set("loop_start", ctx.beat(a))
      api.transport_set("loop_end", ctx.beat(b))
    end
    api.transport_set("loop_enabled", project:getn("LOOP") == 1 and a ~= nil and b ~= nil and b > a)
  end

  -- Markers and regions, as paw.markers keeps them; merged after those
  -- of the project.
  local markers = import_markers(project, ctx)
  if #markers > 0 then
    local meta = api.project_get().meta or {}
    local list = type(meta.markers) == "table" and meta.markers or {}
    local top = 0
    for _, m in ipairs(list) do
      top = math.max(top, tonumber(m.id) or 0)
    end
    for i, m in ipairs(markers) do
      m.id = top + i
      list[#list + 1] = m
    end
    meta.markers = list
    api.project_set("meta", meta)
  end

  -- The master track.
  if not opts.merge then
    local mv = project:child("MASTER_VOLUME")
    if mv then
      api.track_set(0, "volume", db(mv:argn(1)))
      api.track_set(0, "pan", math.max(-1, math.min(1, mv:argn(2) or 0)))
    end
    if ((project:getn("MASTERMUTESOLO") or 0) % 2) == 1 then api.track_set(0, "mute", true) end
    local mfx = project:child("MASTERFXLIST")
    if mfx then
      local holders = import_chain(mfx, 0, "Master", ctx, project:getn("MASTER_FX") == 0)
      if #holders > 0 then set_meta(0, "rpp_placeholders", holders) end
    end
    import_envelopes(project, 0, ctx, "Master")
  end

  -- Tracks, in order, with their folder parents.
  local tracks, stack = {}, {}
  for _, block in ipairs(project:blocks("TRACK")) do
    local t = { block = block, parent = stack[#stack] }
    t.name = block:get("NAME") or ""
    local vp = block:child("VOLPAN")
    t.id = api.track_add({
      name = t.name ~= "" and t.name or nil,
      volume = db(vp and vp:argn(1) or 1),
      pan = math.max(-1, math.min(1, vp and vp:argn(2) or 0)),
    })
    if t.name == "" then t.name = api.track_get(t.id, "name") end
    local colour = M.colour(block:getn("PEAKCOL"))
    if colour then api.track_set(t.id, "color", colour) end
    tracks[#tracks + 1] = t
    local isbus = block:child("ISBUS")
    local depth = isbus and isbus:argn(2) or 0
    if depth > 0 then
      stack[#stack + 1] = #tracks
    elseif depth < 0 then
      for _ = 1, -depth do
        stack[#stack] = nil
      end
    end
  end

  local sends = {}
  for i, t in ipairs(tracks) do
    local block = t.block
    local ms = block:child("MUTESOLO")
    if ms and (ms:argn(1) or 0) ~= 0 then api.track_set(t.id, "mute", true) end
    if ms and (ms:argn(2) or 0) ~= 0 then api.track_set(t.id, "solo", true) end
    local rec = block:child("REC")
    if rec then
      if rec:argn(1) == 1 then api.track_set(t.id, "armed", true) end
      local input = rec:argn(2) or -1
      if input >= 0 and input < 1024 and input < 512 then
        pcall(api.track_set, t.id, "input", tostring(input + 1))
      elseif input >= 1024 and input < 2048 then
        local first = input - 1024 + 1
        pcall(api.track_set, t.id, "input", first .. "/" .. (first + 1))
      elseif input >= 4096 then
        -- MIDI input: paw records MIDI on armed tracks without an audio input.
      end
      if rec:argn(3) == 1 and input >= 0 and input < 4096 then pcall(api.track_set, t.id, "monitor", true) end
    end
    local main = block:child("MAINSEND")
    local main_on = not main or main:argn(1) ~= 0
    if t.parent and main_on then
      local ok, err = pcall(api.track_set, t.id, "output", tracks[t.parent].id)
      if not ok then
        ctx.report:add("Routing", t.name .. ": into folder " .. tracks[t.parent].name .. ": " .. tostring(err))
      end
    end
    if not main_on then
      ctx.report:add("Tracks with the master/parent send off (here they still play through their output)", t.name)
    end
    if block:child("HWOUT") then ctx.report:add("Hardware outputs", t.name) end
    for _, aux in ipairs(block:all("AUXRECV")) do
      local src = tracks[(aux:argn(1) or -1) + 1]
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
          table.insert(sends[src.id], { target = t.id, level = db(vol), pre = mode ~= 0 or nil })
          if mode == 1 then ctx.report:add("Pre-FX sends (made pre-fader, after the plugins)", what) end
          if math.abs(pan) > 1e-9 then ctx.report:add("Send pan", what) end
          if (aux:argn(8) or 0) > 0 or (aux:argn(9) or 0) > 0 then
            ctx.report:add("Send channel mapping (sent as channels 1/2)", what)
          end
        end
      end
    end
  end
  for i, t in ipairs(tracks) do
    if sends[t.id] then
      local ok, err = pcall(api.track_set, t.id, "sends", sends[t.id])
      if not ok then ctx.report:add("Routing", t.name .. ": sends: " .. tostring(err)) end
    end
    local block = t.block
    local chain = block:child("FXCHAIN")
    if chain then
      local holders = import_chain(chain, t.id, t.name, ctx, block:getn("FX") == 0)
      if #holders > 0 then set_meta(t.id, "rpp_placeholders", holders) end
    end
    import_envelopes(block, t.id, ctx, t.name)
    for _, item in ipairs(block:blocks("ITEM")) do
      import_item(item, t.id, t.name, ctx)
    end
    if block:child("FREEZE") then ctx.report:add("Frozen tracks (the frozen audio is not used)", t.name) end
  end

  -- Something to hear MIDI tracks with, when asked for.
  if opts.instrument then
    for _, t in ipairs(tracks) do
      if ctx.midi_tracks[t.id] and #api.track_get(t.id).devices == 0 then
        local ok, err = pcall(api.device_add, t.id, opts.instrument, {})
        if not ok then ctx.report:add("Instruments", t.name .. ": " .. tostring(err)) end
      end
    end
  end

  local ids = {}
  for i, t in ipairs(tracks) do
    ids[i] = t.id
  end
  return { tracks = ids, report = ctx.report, clips = ctx.clips, devices = ctx.devices, tempo = ctx.tempo }
end

--- Read a file and import it.
function M.file(path, opts)
  opts = opts or {}
  opts.path = path
  return M.doc(fmt.read(path), opts)
end

return M
