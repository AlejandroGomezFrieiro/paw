-- Writing paw's project as a REAPER project.
--
--   local result = require("interop.rpp.export").file("song.rpp")
--   print(result.report:text())     -- what could not be written, grouped
--
-- The file is laid out the way REAPER 7 writes its own: the same lines in the
-- same order, with REAPER's defaults for the settings paw does not have.
-- Beats become seconds by the project's tempo map, which is written as
-- REAPER's tempo envelope (TEMPOENVEX) when it has more than one point.
local api = paw.api
local fmt = require("interop.rpp.format")
local midi = require("interop.rpp.midi")
local fx = require("interop.rpp.fx")
local reports = require("interop.report")

local M = {}

M.PPQ = 960

local function amp(db)
  if db <= -120 then return 0 end
  return 10 ^ (db / 20)
end

-- GUIDs ------------------------------------------------------------------------------

local function guid_maker(seed)
  local state = seed % 2147483647
  if state <= 0 then state = state + 2147483646 end
  local function hex(n)
    local out = {}
    for i = 1, n do
      state = (state * 16807) % 2147483647
      out[i] = string.format("%X", state % 16)
    end
    return table.concat(out)
  end
  return function()
    return "{" .. hex(8) .. "-" .. hex(4) .. "-" .. hex(4) .. "-" .. hex(4) .. "-" .. hex(12) .. "}"
  end
end

--- A colour as #rrggbb to REAPER's native colour (red + green * 256 +
--- blue * 65536 on Linux, with 0x1000000 to say it is in use), or nil.
function M.native_colour(colour)
  local r, g, b = tostring(colour or ""):match("^#(%x%x)(%x%x)(%x%x)$")
  if not r then return nil end
  return 0x1000000 + tonumber(r, 16) + tonumber(g, 16) * 256 + tonumber(b, 16) * 65536
end

-- Pieces -----------------------------------------------------------------------------

local function relative(path, dir)
  if dir and path:sub(1, #dir + 1) == dir .. "/" then return path:sub(#dir + 2) end
  return path
end

local SOURCE_TYPES = { wav = "WAVE", wave = "WAVE", aif = "WAVE", aiff = "WAVE", flac = "FLAC", mp3 = "MP3", ogg = "VORBIS" }

--- REAPER's point shape for each of paw's: hold is square (1), smooth is
--- slow start and end (2).
local SHAPES = { hold = 1, smooth = 2 }

--- The shape number of each point of a lane, by its beat.
local function shapes_of(lane, ctx, label)
  local out = {}
  for _, s in ipairs(api.lane_shapes(lane.id)) do
    out[s.beat] = SHAPES[s.shape] or 0
    if s.shape == "smooth" and math.abs(s.tension or 0) > 1e-9 then
      ctx.report:count("Tension of smooth automation curves (REAPER's slow start and end has none)", label)
    end
  end
  return out
end

--- How REAPER names a parameter of a CLAP or VST3 plugin after its place:
--- the plugin's own id for it, as a signed 32-bit number. Nil for others.
local function reaper_ident(info, format)
  local n = (format == "clap" or format == "vst3") and tonumber(info.id)
  if not n or n ~= math.floor(n) or n < 0 or n >= 2 ^ 32 then return nil end
  return string.format("%d", n >= 2 ^ 31 and n - 2 ^ 32 or n)
end

--- A plugin parameter's lane as `<PARMENV`: the parameter by its place
--- among the plugin's (from 0) and, as REAPER writes it, the plugin's own
--- id for it after a colon (`5:-1611133501`), the values as a share of
--- its range.
local function param_envelope(lane, index, info, format, ctx, label)
  local ident = reaper_ident(info, format)
  local env = fmt.block("PARMENV", ident and (index - 1) .. ":" .. ident or index - 1, 0, 1, 0)
  env:add(fmt.line("EGUID", ctx.guid()))
  env:add(fmt.line("ACT", lane.enabled and 1 or 0, -1))
  env:add(fmt.line("VIS", 1, 1, 1))
  env:add(fmt.line("LANEHEIGHT", 0, 0))
  env:add(fmt.line("ARM", 0))
  env:add(fmt.line("DEFSHAPE", 0, -1, -1))
  local shapes = shapes_of(lane, ctx, label)
  local span = info.max - info.min
  for _, p in ipairs(api.lane_points(lane.id)) do
    local f = span ~= 0 and (p[2] - info.min) / span or 0
    env:add(fmt.line("PT", string.format("%.12f", ctx.sec(p[1])), math.max(0, math.min(1, f)), shapes[p[1]] or 0))
  end
  return env
end

local function envelope(name, lane, ctx, label)
  local env = fmt.block(name)
  env:add(fmt.line("EGUID", ctx.guid()))
  env:add(fmt.line("ACT", lane.enabled and 1 or 0, -1))
  env:add(fmt.line("VIS", 1, 1, 1))
  env:add(fmt.line("LANEHEIGHT", 0, 0))
  env:add(fmt.line("ARM", 0))
  env:add(fmt.line("DEFSHAPE", 0, -1, -1))
  -- Points are amplitudes whatever the scaling; REAPER 7 marks volume
  -- envelopes with fader scaling, which only changes how they are drawn.
  if name:match("VOLENV") then env:add(fmt.line("VOLTYPE", 1)) end
  local points = api.lane_points(lane.id)
  local shapes = shapes_of(lane, ctx, label or name)
  for _, p in ipairs(points) do
    local value
    if lane.target == "volume" then
      value = amp(p[2])
    else
      value = -p[2] -- REAPER's pan envelopes run from +1 (left) to -1 (right)
    end
    env:add(fmt.line("PT", string.format("%.12f", ctx.sec(p[1])), value, shapes[p[1]] or 0))
  end
  return env
end

local function fx_chain(name, track, t, ctx, label)
  local chain = fmt.block(name)
  -- The parameter lanes of each device, written after its plugin.
  local lanes_of = {}
  for _, lane in ipairs(api.lane_list(track)) do
    if lane.target == "param" then
      lanes_of[lane.device] = lanes_of[lane.device] or {}
      table.insert(lanes_of[lane.device], lane)
    end
  end
  local function param_lanes(device, written)
    for _, lane in ipairs(lanes_of[device] or {}) do
      local index, info
      local d = api.device_get(device)
      for i, p in ipairs(d.param_info or {}) do
        if p.key == lane.param then index, info = i, p end
      end
      if written and index then
        chain:add(param_envelope(lane, index, info, d.format, ctx, label .. ": " .. lane.param))
      else
        ctx.report:add("Plugin parameter automation", label .. ": " .. tostring(lane.param)
          .. (written and "" or " (its device is not written)"))
      end
    end
  end
  chain:add(fmt.line("SHOW", 0))
  chain:add(fmt.line("LASTSEL", 0))
  chain:add(fmt.line("DOCKED", 0))
  local count = 0
  -- The kinds of device, looked up as they are met.
  local types = require("interop").device_types()
  local function add(block, bypass)
    chain:add(fmt.line("BYPASS", bypass and 1 or 0, 0, 0))
    chain:add(block)
    chain:add(fmt.line("FLOATPOS", 0, 0, 0, 0))
    chain:add(fmt.line("FXID", ctx.guid()))
    chain:add(fmt.line("WAK", 0, 0))
    count = count + 1
  end
  -- Plugins kept from an imported REAPER project go back as they were, at
  -- their places in the chain.
  local entries = {}
  for _, device in ipairs(t.devices) do entries[#entries + 1] = { device = device } end
  local holders = {}
  for _, holder in ipairs((t.meta or {}).rpp_placeholders or {}) do
    if holder.rpp then holders[#holders + 1] = holder end
  end
  table.sort(holders, function(x, y) return (x.position or 0) < (y.position or 0) end)
  for _, holder in ipairs(holders) do
    table.insert(entries, math.max(1, math.min(holder.position or #entries + 1, #entries + 1)), { holder = holder })
  end
  for _, entry in ipairs(entries) do
    if entry.holder then
      local block = fmt.parse(entry.holder.rpp).children[1]
      if block and block.children then add(block, entry.holder.bypass) end
    else
      local device = entry.device
      local d = api.device_get(device)
      local info = types[d.kind]
      if info and info.format ~= "builtin" then
        local ok, block, why = pcall(fx.export, device, info)
        if ok and block then
          add(block, d.bypass)
          if why then ctx.report:count("Plugin settings", why) end
          param_lanes(device, true)
        else
          ctx.report:add("Plugins not written", label .. ": " .. d.kind .. " (" .. tostring(ok and why or block) .. ")")
          param_lanes(device, false)
        end
      else
        ctx.report:add("Built-in devices (no REAPER equivalent)", label .. ": " .. d.kind)
        param_lanes(device, false)
      end
    end
  end
  return count > 0 and chain or nil
end

local function item_common(item, clip, ctx, looped)
  local stop = clip.start + clip.length
  item:add(fmt.line("POSITION", ctx.sec(clip.start)))
  item:add(fmt.line("SNAPOFFS", 0))
  item:add(fmt.line("LENGTH", ctx.sec(stop) - ctx.sec(clip.start)))
  item:add(fmt.line("LOOP", looped and 1 or 0))
  item:add(fmt.line("ALLTAKES", 0))
  -- Fade lengths in seconds; shape 1 is REAPER's default.
  local fin = (clip.fade_in or 0) > 0 and ctx.sec(clip.start + clip.fade_in) - ctx.sec(clip.start) or 0
  local fout = (clip.fade_out or 0) > 0 and ctx.sec(stop) - ctx.sec(stop - clip.fade_out) or 0
  item:add(fmt.line("FADEIN", 1, fin, 0, 1, 0, 0, 0))
  item:add(fmt.line("FADEOUT", 1, fout, 0, 1, 0, 0, 0))
  item:add(fmt.line("MUTE", clip.muted and 1 or 0, 0))
  item:add(fmt.line("SEL", 0))
  item:add(fmt.line("IGUID", ctx.guid()))
  ctx.iid = ctx.iid + 1
  item:add(fmt.line("IID", ctx.iid))
  item:add(fmt.line("NAME", clip.name or "")):quoted(1)
end

--- The repeat of a looped clip: { from, beats } in beats from its start,
--- or nil.
local function repeat_of(clip)
  if clip["loop"] and (clip.loop_length or 0) > 0 then return clip.loop_start or 0, clip.loop_length end
end

local function audio_item(clip, ctx, label)
  local item = fmt.block("ITEM")
  local stretch = clip.stretch or 1
  local from, beats = repeat_of(clip)
  if from and math.abs(stretch - 1) > 1e-9 then
    ctx.report:add("Loops of stretched audio clips (written without the loop)", label)
    from = nil
  end
  item_common(item, clip, ctx, from ~= nil)
  item:add(fmt.line("VOLPAN", 1, 0, amp(clip.gain or 0), -1))
  -- A looped clip repeats a stretch of its file that begins `lead`
  -- seconds before the clip's start (see paw's audio_regions). When that
  -- is not the start of the file, the item plays a section of it.
  local offset, section = clip.offset or 0, nil
  if from then
    local period = ctx.sec(clip.start + beats) - ctx.sec(clip.start)
    local begins = offset + from * period / beats
    section = { start = begins, length = period }
    offset = offset - begins
  end
  item:add(fmt.line("SOFFS", offset))
  -- The rate keeps the pitch; paw's pitch is REAPER's pitch shift.
  item:add(fmt.line("PLAYRATE", 1 / stretch, 1, clip.pitch or 0, -1, 0, 0.0025))
  item:add(fmt.line("CHANMODE", 0))
  item:add(fmt.line("GUID", ctx.guid()))
  local ext = (clip.file:match("%.(%w+)$") or ""):lower()
  local source = item
  if section then
    source = item:add(fmt.block("SOURCE", "SECTION"))
    source:add(fmt.line("LENGTH", section.length))
    source:add(fmt.line("STARTPOS", section.start))
    source:add(fmt.line("OVERLAP", 0))
  end
  source = source:add(fmt.block("SOURCE", SOURCE_TYPES[ext] or "WAVE"))
  source:add(fmt.line("FILE", relative(clip.file, ctx.dir))):quoted(1)
  if not SOURCE_TYPES[ext] then ctx.report:add("Media REAPER may not read", clip.file) end
  if clip.stretch_mode and clip.stretch_mode ~= "auto" then
    ctx.report:add("Stretch modes (REAPER uses its own)", label .. ": " .. tostring(clip.stretch_mode))
  end
  if clip.warp and #clip.warp > 0 then ctx.report:add("Warp markers", label) end
  return item
end

--- Controller moves of a clip as ticks, for the events of a source.
local function control_ticks(controls, from, to, shift)
  local out = {}
  for _, c in ipairs(controls) do
    if c.start >= from - 1e-9 and c.start < to - 1e-9 then
      out[#out + 1] = {
        tick = math.floor((c.start - shift) * M.PPQ + 0.5), type = c.type, number = c.number, value = c.value,
        key = c.key, program = c.program, bank = c.bank,
      }
    end
  end
  return out
end

local function midi_item(clip, ctx, label)
  local item = fmt.block("ITEM")
  -- A looped clip: its repeated stretch is the source, which the item
  -- starts into by the stretch's distance before the clip's start.
  local from, beats = repeat_of(clip)
  local lo, hi, shift = 0, clip.length, 0
  if from then lo, hi, shift = from, from + beats, from end
  item_common(item, clip, ctx, from ~= nil)
  item:add(fmt.line("VOLPAN", 1, 0, 1, -1))
  item:add(fmt.line("SOFFS", from and -from * 60 / api.tempo_at(clip.start) or 0))
  item:add(fmt.line("PLAYRATE", 1, 1, 0, -1, 0, 0.0025))
  item:add(fmt.line("CHANMODE", 0))
  item:add(fmt.line("GUID", ctx.guid()))
  local source = item:add(fmt.block("SOURCE", "MIDI"))
  source:add(fmt.line("HASDATA", 1, M.PPQ, "QN"))
  source:add(fmt.line("CCINTERP", 32))
  source:add(fmt.line("POOLEDEVTS", ctx.guid()))
  local notes, rounded, attrs = {}, 0, 0
  local shown = {}
  -- Notes before the clip's start are hidden by a trim, and not played;
  -- in a looped clip, those outside the repeated stretch.
  for _, n in ipairs(api.clip_notes(clip.id)) do
    if n.start >= lo - 1e-9 and n.start < hi - 1e-9 then
      shown[#shown + 1] = { start = n.start - shift, length = n.length, pitch = n.pitch, velocity = n.velocity,
        meta = n.meta, attr = n.attr }
    end
  end
  for _, n in ipairs(shown) do
    local tick = math.floor(n.start * M.PPQ + 0.5)
    local stop = math.floor((n.start + n.length) * M.PPQ + 0.5)
    if math.abs(tick - n.start * M.PPQ) > 1e-6 or math.abs(stop - (n.start + n.length) * M.PPQ) > 1e-6 then
      rounded = rounded + 1
    end
    if n.attr then attrs = attrs + 1 end
    local channel = n.meta and tonumber(n.meta.channel)
    notes[#notes + 1] = {
      tick = tick, length = math.max(1, stop - tick), pitch = n.pitch, velocity = n.velocity,
      channel = channel and math.max(0, math.min(15, channel - 1)) or 0,
    }
  end
  if rounded > 0 then ctx.report:count("Note times rounded to 1/960 beat", label, rounded) end
  -- A REAPER project keeps MIDI 1.0, where a note has no attribute.
  if attrs > 0 then ctx.report:count("Note attributes (MIDI 2.0 articulations)", label, attrs) end
  local length = math.floor((hi - lo) * M.PPQ + 0.5)
  local controls = control_ticks(api.clip_controls(clip.id), lo, hi, shift)
  local other = 0
  for i = #controls, 1, -1 do
    local c = controls[i]
    if c.type ~= "cc" and c.type ~= "bend" and c.type ~= "pressure" and c.type ~= "program" or (c.key and c.type ~= "pressure") then
      other = other + 1
      table.remove(controls, i)
    end
  end
  if other > 0 then ctx.report:count("Controllers MIDI 1.0 has no event for (registered, assignable, per note)", label, other) end
  for _, line in ipairs(midi.event_lines(notes, length, controls)) do source:add(line) end
  source:add(fmt.line("CCINTERP", 32))
  source:add(fmt.line("GUID", ctx.guid()))
  source:add(fmt.line("IGNTEMPO", 0, 120, 4, 4))
  return item
end

-- Tracks and folders -----------------------------------------------------------------

--- Folder depth changes for REAPER (`ISBUS`), and which tracks' outputs a
--- folder cannot express (they become sends from a track whose parent send
--- is off). A track is in a folder when it follows its output track
--- directly, or follows a sibling in that folder.
local function layout(list)
  local index = {}
  for i, t in ipairs(list) do index[t.id] = i end
  local depth, stack, unfoldered = {}, {}, {}
  for i, t in ipairs(list) do
    depth[i] = 0
    local parent = t.output
    local inside = false
    for _, open in ipairs(stack) do
      if open == parent then inside = true end
    end
    if parent and not inside then unfoldered[t.id] = true end
    -- Close folders until the innermost open one is the parent (or none is).
    local pops = 0
    while #stack > 0 and stack[#stack] ~= (inside and parent or nil) do
      stack[#stack] = nil
      pops = pops + 1
    end
    if pops > 0 then depth[i - 1] = depth[i - 1] - pops end
    local nxt = list[i + 1]
    if nxt and nxt.output == t.id then
      depth[i] = 1
      stack[#stack + 1] = t.id
    end
  end
  if #list > 0 then depth[#list] = depth[#list] - #stack end
  return depth, unfoldered, index
end

local function track_block(t, i, ctx, depth, unfoldered, index, receives)
  local guid = ctx.guid()
  local block = fmt.block("TRACK", guid)
  block:add(fmt.line("NAME", t.name or "")):quoted(1)
  block:add(fmt.line("PEAKCOL", M.native_colour(t.color) or 16576))
  block:add(fmt.line("BEAT", -1))
  block:add(fmt.line("AUTOMODE", 0))
  block:add(fmt.line("VOLPAN", amp(t.volume or 0), t.pan or 0, -1, -1, 1))
  block:add(fmt.line("MUTESOLO", t.mute and 1 or 0, t.solo and 2 or 0, 0))
  block:add(fmt.line("IPHASE", 0))
  block:add(fmt.line("PLAYOFFS", 0, 1))
  local d = depth[i] or 0
  block:add(fmt.line("ISBUS", d > 0 and 1 or (d < 0 and 2 or 0), d))
  block:add(fmt.line("BUSCOMP", 0, 0, 0, 0, 0))
  block:add(fmt.line("SHOWINMIX", 1, 0.6667, 0.5, 1, 0.5, 0, 0, 0, 0))
  block:add(fmt.line("SEL", 0))
  local input, monitor = -1, 0
  if t.input then
    local a, b = t.input:match("^(%d+)/(%d+)$")
    if a then input = 1024 + tonumber(a) - 1 else input = (tonumber(t.input) or 1) - 1 end
  end
  if t.monitor then monitor = 1 end
  block:add(fmt.line("REC", t.armed and 1 or 0, input, monitor, 0, 0, 0, 0, 0))
  block:add(fmt.line("VU", 2))
  block:add(fmt.line("TRACKHEIGHT", 0, 0, 0, 0, 0, 0, 0))
  block:add(fmt.line("INQ", 0, 0, 0, 0.5, 100, 0, 0, 100))
  block:add(fmt.line("NCHAN", 2))
  block:add(fmt.line("FX", 1))
  block:add(fmt.line("TRACKID", guid))
  block:add(fmt.line("PERF", 0))
  block:add(fmt.line("MIDIOUT", -1))
  block:add(fmt.line("MAINSEND", unfoldered[t.id] and 0 or 1, 0))
  for _, r in ipairs(receives[t.id] or {}) do
    -- Mode 0 is after the fader, 3 before it (after the plugins).
    block:add(fmt.line("AUXRECV", index[r.from] - 1, r.pre and 3 or 0, amp(r.level), 0, 0, 0, 0, 0, 0, "-1:U", 0, -1, "")):quoted(13)
  end
  return block
end

--- REAPER's tempo envelope for a map with more than one point, or nil: a
--- point per tempo change (shape 0 ramps, 1 holds) and per signature
--- change, the signature packed as num + den * 65536.
function M.tempo_envelope(ctx)
  local map = api.tempo_points()
  if #map.tempos == 1 and #map.signatures == 1 then return nil end
  local points = {}
  local function at(beat)
    for _, p in ipairs(points) do
      if math.abs(p.beat - beat) < 1e-9 then return p end
    end
    local p = { beat = beat }
    points[#points + 1] = p
    return p
  end
  for _, t in ipairs(map.tempos) do
    local p = at(t.beat)
    p.bpm, p.ramp = t.bpm, t.ramp
  end
  for _, s in ipairs(map.signatures) do
    local p = at(s.beat)
    p.sig = s.num + s.den * 65536
  end
  table.sort(points, function(a, b) return a.beat < b.beat end)
  local env = fmt.block("TEMPOENVEX")
  env:add(fmt.line("EGUID", ctx.guid()))
  env:add(fmt.line("ACT", 0, -1))
  env:add(fmt.line("VIS", 1, 0, 1))
  env:add(fmt.line("LANEHEIGHT", 0, 0))
  env:add(fmt.line("ARM", 0))
  env:add(fmt.line("DEFSHAPE", 1, -1, -1))
  local ramp = false
  for _, p in ipairs(points) do
    -- A signature change inside a ramp keeps the ramp going through it.
    if p.bpm == nil then p.bpm, p.ramp = api.tempo_at(p.beat), ramp end
    ramp = p.ramp
    local t = string.format("%.12f", api.tempo_seconds(p.beat))
    if p.sig then
      env:add(fmt.line("PT", t, p.bpm, p.ramp and 0 or 1, p.sig, 0, 1))
    else
      env:add(fmt.line("PT", t, p.bpm, p.ramp and 0 or 1))
    end
  end
  return env
end

--- Build the document for the current project. `opts.dir` is the folder
--- the file will be in (media under it are written relative to it).
function M.doc(opts)
  opts = opts or {}
  local p = api.project_get()
  local tr = api.transport_get()
  local ctx = {
    tempo = p.tempo, sec = api.tempo_seconds, dir = opts.dir, iid = 0,
    guid = guid_maker(opts.seed or (os.time() + math.floor(api.now()))),
    report = reports.new("Not written to " .. (opts.name or "the REAPER project") .. ":"),
  }
  local doc = fmt.document("\r\n")
  local root = doc:add(fmt.block("REAPER_PROJECT", 0.1, "7.0/paw-rpp", opts.timestamp or os.time(), 0)):quoted(2)
  local function line(...) return root:add(fmt.line(...)) end
  line("RIPPLE", 0, 0)
  line("GROUPOVERRIDE", 0, 0, 0, 0)
  line("AUTOXFADE", 129)
  line("ENVATTACH", 3)
  line("POOLEDENVATTACH", 0)
  line("PANLAW", 1)
  line("PROJOFFS", 0, 0, 0)
  line("MAXPROJLEN", 0, 0)
  line("GRID", 3199, 8, 1, 8, 1, 0, 0, 0)
  line("TIMEMODE", 1, 5, -1, 30, 0, 0, -1, 0)
  line("PANMODE", 3)
  line("CURSOR", 0)
  line("ZOOM", 100, 0, 0)
  local looped = tr.loop_end and tr.loop_start and tr.loop_end > tr.loop_start
  line("LOOP", (tr.loop_enabled and looped) and 1 or 0)
  line("LOOPGRAN", 0, 4)
  line("RECORD_PATH", "Media", ""):quoted(1)
  line("TIMELOCKMODE", 1)
  line("TEMPOENVLOCKMODE", 1)
  line("ITEMMIX", 1)
  line("DEFPITCHMODE", 589824, 0)
  line("TAKELANE", 1)
  line("SAMPLERATE", 44100, 0, 0)
  line("LOCK", 1)
  line("GLOBAL_AUTO", -1)
  line("TEMPO", p.tempo, p.sig_num, p.sig_den, 0)
  line("PLAYRATE", 1, 0, 0.25, 4)
  local a, b = 0, 0
  if looped then a, b = ctx.sec(tr.loop_start), ctx.sec(tr.loop_end) end
  line("SELECTION", a, b)
  line("SELECTION2", a, b)
  line("MASTERAUTOMODE", 0)
  line("MASTERTRACKHEIGHT", 0, 0)
  line("MASTERPEAKCOL", 16576)
  local master = api.track_get(0)
  line("MASTERMUTESOLO", master.mute and 1 or 0)
  line("MASTERHWOUT", 0, 0, 1, 0, 0, 0, 0, -1)
  line("MASTER_NCH", 2, 2)
  line("MASTER_VOLUME", amp(master.volume or 0), master.pan or 0, -1, -1, 1)
  line("MASTER_PANMODE", 3)
  line("MASTER_FX", 1)
  line("MASTER_SEL", 0)
  local master_chain = fx_chain("MASTERFXLIST", 0, master, ctx, "Master")
  if master_chain then root:add(master_chain) end
  for _, lane in ipairs(api.lane_list(0)) do
    if lane.target == "volume" or lane.target == "pan" then
      root:add(envelope(lane.target == "volume" and "MASTERVOLENV2" or "MASTERPANENV2", lane, ctx, "Master " .. lane.target))
    end
  end
  -- Markers and regions (paw.markers: `project.meta.markers`, a region
  -- with a length), in beats; and `project.meta.regions` as older
  -- versions of this extension kept them.
  local meta = p.meta or {}
  local n = 0
  local function colour(c) return M.native_colour(c) or 0 end
  for _, m in ipairs(type(meta.markers) == "table" and meta.markers or {}) do
    n = n + 1
    if m.length then
      line("MARKER", n, ctx.sec(m.beat or 0), m.name or "", 1, colour(m.color), 1, "R", ctx.guid(), 0):quoted(3)
      line("MARKER", n, ctx.sec((m.beat or 0) + m.length), "", 1):quoted(3)
    else
      line("MARKER", n, ctx.sec(m.beat or 0), m.name or "", 0, colour(m.color), 1, "B", ctx.guid(), 0):quoted(3)
    end
  end
  for _, r in ipairs(type(meta.regions) == "table" and meta.regions or {}) do
    n = n + 1
    line("MARKER", n, ctx.sec(r.start or 0), r.name or "", 1, colour(r.color), 1, "R", ctx.guid(), 0):quoted(3)
    line("MARKER", n, ctx.sec((r.start or 0) + (r.length or 0)), "", 1):quoted(3)
  end
  -- Song sections (`project.meta.sections`, as the sections extension
  -- keeps them) become regions, each up to where the next starts.
  local ok, sections = pcall(require, "sections")
  local parts = ok and sections.list() or {}
  for _, s in ipairs(parts) do
    n = n + 1
    line("MARKER", n, ctx.sec(s.start), s.name, 1, 0, 1, "B", ctx.guid(), 0):quoted(3)
    line("MARKER", n, ctx.sec(s.finish), "", 1):quoted(3)
  end
  if #parts > 0 then ctx.report:count("Sections written as regions (they come back as regions)", "sections", #parts) end
  local tempo_env = M.tempo_envelope(ctx)
  if tempo_env then root:add(tempo_env) end
  root:add(fmt.block("PROJBAY"))

  local list = {}
  for i, id in ipairs(api.track_list()) do list[i] = api.track_get(id) end
  local depth, unfoldered, index = layout(list)
  local receives = {}
  for _, t in ipairs(list) do
    if unfoldered[t.id] then
      receives[t.output] = receives[t.output] or {}
      table.insert(receives[t.output], { from = t.id, level = 0 })
      ctx.report:add("Routing written as a send (REAPER folders need the child right after its parent)",
        t.name .. " -> " .. api.track_get(t.output, "name"))
    end
    for _, s in ipairs(t.sends or {}) do
      receives[s.target] = receives[s.target] or {}
      table.insert(receives[s.target], { from = t.id, level = s.level, pre = s.pre })
    end
  end
  for i, t in ipairs(list) do
    local block = root:add(track_block(t, i, ctx, depth, unfoldered, index, receives))
    for _, lane in ipairs(api.lane_list(t.id)) do
      if lane.target == "volume" or lane.target == "pan" then
        block:add(envelope(lane.target == "volume" and "VOLENV2" or "PANENV2", lane, ctx, t.name .. " " .. lane.target))
      end
    end
    local chain = fx_chain("FXCHAIN", t.id, t, ctx, t.name)
    if chain then block:add(chain) end
    for _, clip in ipairs(api.clip_list(t.id)) do
      local label = t.name .. ": " .. (clip.name or "clip")
      if clip.kind == "audio" then
        block:add(audio_item(clip, ctx, label))
      else
        block:add(midi_item(clip, ctx, label))
      end
    end
    local cues = #api.cue_list(t.id)
    if cues > 0 then ctx.report:count("Clips off the timeline (the clip launcher's slots)", t.name, cues) end
  end
  return doc, ctx.report
end

--- Write the current project to a file.
function M.file(path, opts)
  opts = opts or {}
  opts.dir = opts.dir or (path:match("^(.*)/[^/]*$") or ".")
  opts.name = path:match("([^/]+)$") or path
  if opts.dir:sub(1, 1) ~= "/" then
    local pwd = os.getenv("PWD")
    if pwd then opts.dir = pwd .. (opts.dir == "." and "" or "/" .. opts.dir) end
  end
  local doc, report = M.doc(opts)
  fmt.save(doc, path)
  return { report = report, doc = doc }
end

return M
