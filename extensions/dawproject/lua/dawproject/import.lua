-- Reading a DAWproject file into paw.
--
--   local result = require("dawproject.import").file("song.dawproject")
--   print(result.report:text())     -- what could not be carried over, grouped
--
-- The tracks of <Structure> become paw's tracks in the same order (a
-- nested track goes into its folder); <Arrangement> gives their clips and
-- automation. Audio in the archive is copied into a folder beside it.
local api = paw.api
local xml = require("dawproject.xml")
local b64 = paw.bytes
local vst3 = require("dawproject.vst3")
local reports = require("dawproject.report")

local M = {}

local INF = math.huge

--- A gain as decibels, from -120 to 24.
local function db(gain) return paw.util.clamp(require("paw.dsp").db(gain or 0), -120, 24) end

local function num(v, default)
  local n = tonumber(v)
  if n == nil then return default end
  return n
end

local function truthy(v) return v == "true" or v == "1" end

--- A value of a parameter element in paw's units: a volume in dB, a pan
--- from -1 to 1.
local function level(e)
  if not e then return nil end
  local v, unit = num(e.attr.value, 0), e.attr.unit
  if unit == "decibel" then return v end
  if unit == "normalized" then return db(v * num(e.attr.max, 1)) end
  return db(v)
end

local function pan(e)
  if not e then return nil end
  local v = num(e.attr.value, 0.5)
  if e.attr.unit == "normalized" or (num(e.attr.min, -1) >= 0) then return math.max(-1, math.min(1, v * 2 - 1)) end
  return math.max(-1, math.min(1, v))
end

-- Devices ------------------------------------------------------------------------------

local PLUGINS = { ClapPlugin = true, Vst3Plugin = true, Vst2Plugin = true, AuPlugin = true, Device = true,
  BuiltinDevice = true, Equalizer = true, Compressor = true, NoiseGate = true, Limiter = true }

local function installed(kind)
  for _, t in ipairs(api.device_types()) do
    if t.kind == kind then return t end
  end
end

local function find_vst3(name, vendor, class)
  for _, t in ipairs(api.device_types()) do
    if t.format == "vst3" and class and t.id ~= "" and t.id == class:upper() then return t end
  end
  for _, t in ipairs(api.device_types()) do
    if t.format == "vst3" and t.name == name and (not vendor or t.vendor == "" or t.vendor == vendor) then return t end
  end
  for _, t in ipairs(api.device_types()) do
    if t.format == "vst3" and t.name:lower() == (name or ""):lower() then return t end
  end
end

--- The paw key of a parameter element of a device: by the plugin's own id
--- (`parameterID` of a CLAP or VST3 plugin, which a DAW writes signed), by
--- name, by key, or by its place (`parameterID` of a device of paw).
local function param_key(dev, pe, plugin)
  local infos = api.device_get(dev).param_info or {}
  local name = (pe.attr.name or ""):lower()
  local own = plugin and tonumber(pe.attr.parameterID)
  if own then
    if own < 0 then own = own + 2 ^ 32 end
    local id = string.format("%d", own)
    for _, p in ipairs(infos) do
      if p.id == id then return p end
    end
  end
  for _, p in ipairs(infos) do
    if p.name:lower() == name or p.key:lower() == name then return p end
  end
  local index = not plugin and tonumber(pe.attr.parameterID)
  if index and name == "" then return infos[index + 1] end
end

local function import_device(e, track, ctx, label, position)
  local tag = e.name
  local name = e.attr.deviceName or e.attr.name or tag
  local where = label .. ": " .. name
  local state_el = e:child("State")
  local state = state_el and state_el.attr.path and ctx.files[state_el.attr.path]
  local enabled = e:child("Enabled")
  local bypass = enabled and enabled.attr.value == "false"
  local id, why
  local function add(kind, opts)
    local ok, dev = pcall(api.device_add, track, kind, opts or {})
    if not ok then return nil, "could not load here: " .. tostring(dev):gsub("\n.*", "") end
    if bypass then api.device_set(dev, "bypass", true) end
    return dev
  end
  local set_params = false
  local device_id = e.attr.deviceID or ""
  if tag == "ClapPlugin" then
    local kind = "clap:" .. device_id
    if installed(kind) then
      id, why = add(kind, { state = state and b64.base64(state) or nil })
    else
      why = "not installed here"
    end
  elseif tag == "Vst3Plugin" then
    local t = find_vst3(name, e.attr.deviceVendor, device_id ~= "" and device_id or nil)
    if t then
      local s, class = nil, nil
      if state then s, class = vst3.state(state) end
      id, why = add(t.kind, { state = s and b64.base64(s) or nil })
      if not id and s then
        id, why = add(t.kind)
        ctx.report:add("Plugin settings", where .. ": the plugin did not take its state; defaults used")
      end
      if id then api.device_set(id, "meta", { dawproject = { class = class or device_id } }) end
    else
      why = "not installed here"
    end
  elseif (tag == "Device" or tag == "BuiltinDevice") and device_id:match("^paw:") then
    id, why = add(device_id:sub(5))
    set_params = true
  elseif (tag == "Device" or tag == "BuiltinDevice") and device_id:match("^lv2:") then
    if installed(device_id) then id, why = add(device_id) else why = "not installed here" end
    set_params = true
  elseif tag == "Vst2Plugin" then
    why = "VST2 plugins are not hosted here"
  elseif tag == "AuPlugin" then
    why = "Audio Units are not hosted on Linux"
  else
    why = "a device of another program"
  end
  if not id then
    ctx.report:add("Plugins and devices left as placeholders", where .. " (" .. tostring(why) .. ")")
    ctx.placeholders[track] = ctx.placeholders[track] or {}
    table.insert(ctx.placeholders[track], {
      name = name, format = tag, position = position, reason = why,
      xml = xml.write(e):gsub("^<%?xml[^\n]*\n", ""), state = state and b64.base64(state) or nil,
    })
    return nil
  end
  ctx.devices = ctx.devices + 1
  -- Its parameters, as automation targets (and their values for devices
  -- that have no state of their own).
  local params = e:child("Parameters")
  local unknown = {}
  for _, pe in ipairs(params and params.children or {}) do
    local p = param_key(id, pe, tag == "ClapPlugin" or tag == "Vst3Plugin")
    if p then
      if pe.attr.id then
        ctx.params[pe.attr.id] = { kind = "param", track = track, device = id, key = p.key, min = p.min, max = p.max,
          own_min = num(pe.attr.min), own_max = num(pe.attr.max) }
      end
      local v = num(pe.attr.value)
      if set_params and v then pcall(api.device_set_param, id, p.key, v) end
    elseif set_params then
      unknown[#unknown + 1] = pe.attr.name or "?"
    end
  end
  if #unknown > 0 then ctx.report:add("Plugin settings", where .. ": parameters not found here: " .. table.concat(unknown, ", ")) end
  return id
end

-- Structure ----------------------------------------------------------------------------

local function import_channel(c, track, ctx, label)
  ctx.channels[c.attr.id or ""] = track
  local vol, p, mute = c:child("Volume"), c:child("Pan"), c:child("Mute")
  if vol then api.track_set(track, "volume", level(vol)) end
  if p then api.track_set(track, "pan", pan(p)) end
  if mute and mute.attr.value == "true" then api.track_set(track, "mute", true) end
  if track ~= 0 and c.attr.solo == "true" then api.track_set(track, "solo", true) end
  if vol and vol.attr.id then ctx.params[vol.attr.id] = { kind = "volume", track = track, max = num(vol.attr.max, 1) } end
  if p and p.attr.id then ctx.params[p.attr.id] = { kind = "pan", track = track } end
  if mute and mute.attr.id then ctx.params[mute.attr.id] = { kind = "mute", track = track, label = label } end
  local devices = c:child("Devices")
  local position = 0
  for _, d in ipairs(devices and devices.children or {}) do
    if PLUGINS[d.name] then
      position = position + 1
      import_device(d, track, ctx, label, position)
    end
  end
end

--- The tracks of <Structure> (and channels with no track), and the tracks
--- nested in a track.
local function import_tracks(parent_el, parent_track, ctx)
  for _, e in ipairs(parent_el.children) do
    if e.name == "Track" or (e.name == "Channel" and not parent_track) then
      local c = e.name == "Channel" and e or e:child("Channel")
      local name = e.attr.name or (c and c.attr.name) or nil
      if c and c.attr.role == "master" and not ctx.merge then
        ctx.tracks[e.attr.id or ""] = 0
        import_channel(c, 0, ctx, "Master")
      elseif c and c.attr.role == "master" then
        -- Merged: what goes to the file's master goes to this project's.
        ctx.tracks[e.attr.id or ""] = false
        ctx.channels[c.attr.id or ""] = 0
        ctx.report:add("The master of the file (merged: the project keeps its own)", e.attr.name or "Master")
      else
        local id = api.track_add({ name = name })
        local t = { id = id, el = e, channel = c, parent = parent_track, name = api.track_get(id, "name") }
        ctx.list[#ctx.list + 1] = t
        ctx.tracks[e.attr.id or ""] = id
        if e.attr.color and e.attr.color:match("^#%x%x%x%x%x%x$") then api.track_set(id, "color", e.attr.color:lower()) end
        if c then import_channel(c, id, ctx, t.name) end
        if e.name == "Track" then import_tracks(e, t, ctx) end
      end
    end
  end
end

local function routing(ctx)
  for _, t in ipairs(ctx.list) do
    local c = t.channel
    local dest = c and c.attr.destination and ctx.channels[c.attr.destination]
    if dest == nil and t.parent then dest = t.parent.id end
    if dest and dest ~= 0 and dest ~= t.id then
      local ok, err = pcall(api.track_set, t.id, "output", dest)
      if not ok then ctx.report:add("Routing", t.name .. ": " .. tostring(err)) end
    elseif c and c.attr.destination and dest == nil then
      ctx.report:add("Routing", t.name .. ": to a channel that is not in the file")
    end
    local sends_el = c and c:child("Sends")
    local sends = {}
    for _, s in ipairs(sends_el and sends_el:all("Send") or {}) do
      local target = ctx.channels[s.attr.destination or ""]
      local enable = s:child("Enable")
      local what = t.name .. " -> " .. tostring(s.attr.destination)
      if not target or target == 0 then
        ctx.report:add("Sends to channels that are not tracks", what)
      elseif enable and enable.attr.value == "false" then
        ctx.report:add("Sends that are off (left out)", what)
      else
        sends[#sends + 1] = { target = target, level = level(s:child("Volume")) or 0, pre = s.attr.type == "pre" or nil }
        local sp = s:child("Pan")
        if sp and math.abs(pan(sp)) > 1e-6 then ctx.report:add("Send pan", what) end
        local sv = s:child("Volume")
        if sv and sv.attr.id then ctx.params[sv.attr.id] = { kind = "send", label = what } end
      end
    end
    if #sends > 0 then
      local ok, err = pcall(api.track_set, t.id, "sends", sends)
      if not ok then ctx.report:add("Routing", t.name .. ": sends: " .. tostring(err)) end
    end
  end
end

-- Clips --------------------------------------------------------------------------------

local CONTENT = { Timeline = true, Lanes = true, Notes = true, Clips = true, ClipSlot = true, markers = true,
  Warps = true, Audio = true, Video = true, Points = true }

local function content_of(e)
  for _, c in ipairs(e.children) do
    if CONTENT[c.name] then return c end
  end
end

--- A MIDI expression of a Points timeline as a controller move of paw, or nil.
local function move_of(target, unit, v)
  local expr = target.attr.expression
  if expr == "channelController" then
    return { type = "cc", number = num(target.attr.controller, 0), value = math.max(0, math.min(1, v)) }
  elseif expr == "pitchBend" then
    return { type = "bend", value = math.max(-1, math.min(1, unit == "normalized" and v * 2 - 1 or v)) }
  elseif expr == "channelPressure" then
    return { type = "pressure", value = math.max(0, math.min(1, v)) }
  elseif expr == "polyPressure" then
    return { type = "pressure", key = num(target.attr.key, 60), value = math.max(0, math.min(1, v)) }
  elseif expr == "programChange" then
    return { type = "program", program = math.max(0, math.min(127, math.floor(v + 0.5))), value = 0 }
  end
end

--- Notes and controller moves of a MIDI content (Notes, or Lanes holding
--- Notes and Points), at their times in content units.
local function midi_content(e, ctx, label, notes, moves)
  if e.name == "Notes" then
    local rel = 0
    for _, n in ipairs(e:all("Note")) do
      local vel = num(n.attr.vel, 100 / 127)
      local channel = num(n.attr.channel, 0)
      notes[#notes + 1] = {
        start = num(n.attr.time, 0), length = num(n.attr.duration, 0.25), pitch = num(n.attr.key, 60),
        velocity = math.max(1, math.min(127, math.floor(vel * 127 + 0.5))),
        meta = channel ~= 0 and { channel = channel + 1 } or nil,
      }
      if n.attr.rel and math.abs(num(n.attr.rel, vel) - vel) > 1e-6 then rel = rel + 1 end
      if #n.children > 0 then ctx.report:count("Per-note expressions", label) end
    end
    if rel > 0 then ctx.report:count("Note-off velocities", label, rel) end
  elseif e.name == "Lanes" then
    for _, c in ipairs(e.children) do midi_content(c, ctx, label, notes, moves) end
  elseif e.name == "Points" then
    local target = e:child("Target")
    local unit = e.attr.unit
    for _, pt in ipairs(e.children) do
      if pt.name ~= "Target" then
        local m = target and move_of(target, unit, num(pt.attr.value, 0))
        if m then
          m.start = num(pt.attr.time, 0)
          moves[#moves + 1] = m
        else
          ctx.report:count("Expressions other than MIDI controllers", label .. ": " .. tostring(target and target.attr.expression))
        end
      end
    end
  else
    ctx.report:add("Clip contents paw cannot read", label .. ": " .. e.name)
  end
end

--- The beats of a time in a timeline's unit.
local function to_beats(t, unit)
  if unit == "seconds" then return api.tempo_beat(t) end
  return t
end

local function audio_path(file, ctx, label)
  local path = file and file.attr.path
  if not path then return nil end
  if file.attr.external == "true" then
    if path:sub(1, 1) ~= "/" then path = ctx.dir .. "/" .. path end
    if not io.open(path, "rb") then
      ctx.report:add("Missing media", label .. ": " .. path)
      return nil
    end
    return path
  end
  if ctx.extracted[path] then return ctx.extracted[path] end
  local data = ctx.files[path]
  if not data then
    ctx.report:add("Missing media", label .. ": " .. path .. " is not in the file")
    return nil
  end
  pcall(api.fs_mkdir, ctx.media_dir)
  local out = ctx.media_dir .. "/" .. (path:match("([^/]+)$") or "audio.wav")
  local f = assert(io.open(out, "wb"))
  f:write(data)
  f:close()
  ctx.extracted[path] = out
  return out
end

local import_clip

--- One <Clip>. `place` turns a time of the parent timeline into a beat of
--- the arrangement; `lo` and `hi` are the beats the parent lets it play in;
--- `outer` holds what a parent clip adds (fades, mute, name).
import_clip = function(c, track, ctx, place, parent_unit, lo, hi, outer)
  local T = num(c.attr.time, 0)
  local ps = num(c.attr.playStart, 0)
  local cu = c.attr.contentTimeUnit or parent_unit
  local D = num(c.attr.duration)
  if not D and c.attr.playStop then D = num(c.attr.playStop) - ps end
  local start = place(T)
  local stop = D and place(T + D) or hi
  if stop == INF then stop = start + 4 end
  local a, b = math.max(start, lo), math.min(stop, hi)
  if b - a <= 1e-9 then return end
  local name = c.attr.name or outer.name
  local label = ctx.label .. ": " .. (name or "clip")
  local muted = c.attr.enable == "false" or outer.muted
  local fu = c.attr.fadeTimeUnit or parent_unit
  local function fade_beats(at, len, back)
    if not len or len <= 0 then return 0 end
    if fu == "seconds" then
      local s = api.tempo_seconds(at)
      return back and (at - api.tempo_beat(s - len)) or (api.tempo_beat(s + len) - at)
    end
    return len
  end
  local fade_in = fade_beats(a, num(c.attr.fadeInTime, 0), false)
  local fade_out = fade_beats(b, num(c.attr.fadeOutTime, 0), true)
  if num(c.attr.fadeInTime, 0) < 0 then ctx.report:add("Crossfades (fade in before the clip)", label) end
  if fade_in == 0 then fade_in = outer.fade_in or 0 end
  if fade_out == 0 then fade_out = outer.fade_out or 0 end
  -- Content time at a beat of the arrangement.
  local function content_at(beat)
    if cu == "seconds" then return ps + api.tempo_seconds(beat) - api.tempo_seconds(start) end
    return ps + (beat - start)
  end
  local loop_start, loop_end = num(c.attr.loopStart), num(c.attr.loopEnd)
  local looping = loop_start and loop_end and loop_end > loop_start
    and content_at(stop) > loop_end + 1e-6
  local content = content_of(c)
  if c.attr.reference then
    content = ctx.ids[c.attr.reference]
    if not content then return ctx.report:add("Clips of a timeline that is not in the file", label) end
  end
  if not content then return ctx.report:add("Empty clips", label) end
  if content.name == "Clips" then
    -- Clips inside a clip: each placed by the content's time.
    local function inner_place(x)
      if cu == "seconds" then return api.tempo_beat(api.tempo_seconds(start) + (x - ps)) end
      return start + (x - ps)
    end
    if looping then ctx.report:add("Loops of clips that hold clips (played once)", label) end
    local inner = content:all("Clip")
    for _, ic in ipairs(inner) do
      import_clip(ic, track, ctx, inner_place, cu, a, b, {
        name = name, muted = muted, fade_in = #inner == 1 and fade_in or 0, fade_out = #inner == 1 and fade_out or 0,
      })
    end
    return
  end
  if content.name == "Audio" or content.name == "Warps" then
    local audio = content.name == "Audio" and content or content:child("Audio")
    if not audio then return ctx.report:add("Clip contents paw cannot read", label .. ": warps of " .. tostring(content_of(content) and content_of(content).name)) end
    local path = audio_path(audio:child("File"), ctx, label)
    if not path then return end
    -- File seconds at the clip's content time, and how many times as long
    -- the clip plays them.
    local file_at, stretch = function(x) return x end, 1
    if content.name == "Warps" then
      local warps = content:all("Warp")
      if #warps >= 2 then
        local w0, w1 = warps[1], warps[#warps]
        local t0, t1 = num(w0.attr.time, 0), num(w1.attr.time, 1)
        local c0, c1 = num(w0.attr.contentTime, 0), num(w1.attr.contentTime, 1)
        if c1 > c0 and t1 > t0 then
          local per = (c1 - c0) / (t1 - t0)
          file_at = function(x) return c0 + (x - t0) * per end
          -- Seconds on the timeline for a unit of the content.
          local unit_seconds = (content.attr.timeUnit or cu) == "seconds" and 1 or 60 / api.tempo_at(start)
          stretch = unit_seconds / per
          if (content.attr.contentTimeUnit or "seconds") ~= "seconds" then
            ctx.report:add("Warps to a content in beats (read as seconds)", label)
          end
        end
        if #warps > 2 then ctx.report:count("Warp points between the first and the last (stretched evenly)", label) end
      end
    end
    if cu ~= "seconds" and content.name == "Audio" then
      ctx.report:add("Audio in beats (read as seconds)", label)
    end
    local opts = {
      name = name, start = a, file = path, offset = math.max(0, file_at(content_at(a))), length = b - a,
      stretch = math.abs(stretch - 1) > 1e-9 and stretch or nil,
    }
    if looping then
      local function beats_from(at, x)
        -- x is in content units
        if cu == "seconds" then return api.tempo_beat(api.tempo_seconds(at) + x) - at end
        return x
      end
      if opts.stretch then
        ctx.report:add("Loops of stretched audio (played once)", label)
      else
        local into = (content_at(a) - loop_start) % (loop_end - loop_start)
        opts["loop"] = true
        opts.loop_length = beats_from(a, loop_end - loop_start)
        opts.loop_start = -beats_from(a, into)
        opts.offset = math.max(0, file_at(loop_start + into))
      end
    end
    local ok, id = pcall(api.clip_add, track, opts)
    if not ok then return ctx.report:add("Unreadable media", label .. ": " .. tostring(id):gsub("\n.*", "")) end
    if fade_in > 0 then pcall(api.clip_set, id, "fade_in", math.min(fade_in, b - a)) end
    if fade_out > 0 then pcall(api.clip_set, id, "fade_out", math.min(fade_out, b - a)) end
    if muted then api.clip_set(id, "muted", true) end
    ctx.clips = ctx.clips + 1
    return
  end
  if content.name == "Video" then return ctx.report:add("Video", label) end
  -- MIDI: notes and moves at content times; in paw, from the clip's start.
  local notes, moves = {}, {}
  midi_content(content, ctx, label, notes, moves)
  if cu == "seconds" then
    ctx.report:add("MIDI clips timed in seconds (read at the tempo of their start)", label)
  end
  local scale = cu == "seconds" and api.tempo_at(start) / 60 or 1
  local base = content_at(a)
  for _, n in ipairs(notes) do
    n.start = (n.start - base) * scale
    n.length = n.length * scale
  end
  for _, m in ipairs(moves) do m.start = (m.start - base) * scale end
  table.sort(moves, function(x, y) return x.start < y.start end)
  local opts = { name = name, start = a, length = b - a, notes = notes, controls = moves }
  if looping then
    opts["loop"] = true
    opts.loop_length = (loop_end - loop_start) * scale
    opts.loop_start = (loop_start - base) * scale
    -- paw keeps the repeat within one length before the clip.
    while opts.loop_start < -opts.loop_length do opts.loop_start = opts.loop_start + opts.loop_length end
    while opts.loop_start > 1e-9 do opts.loop_start = opts.loop_start - opts.loop_length end
  end
  local ok, id = pcall(api.clip_add, track, opts)
  if not ok then return ctx.report:add("Clips that could not be added", label .. ": " .. tostring(id):gsub("\n.*", "")) end
  if muted then api.clip_set(id, "muted", true) end
  if fade_in > 0 or fade_out > 0 then ctx.report:count("Fades on MIDI clips", label) end
  ctx.clips = ctx.clips + 1
end

-- Automation ---------------------------------------------------------------------------

local function import_points(p, ctx, unit)
  local target = p:child("Target")
  local where = ctx.label
  if not target then return end
  if target.attr.expression then
    return ctx.report:count("Expressions on the arrangement (outside clips)", where .. ": " .. target.attr.expression)
  end
  local dest = ctx.params[target.attr.parameter or ""]
  if not dest then return ctx.report:add("Automation of parameters paw does not have", where .. ": " .. tostring(target.attr.parameter)) end
  if dest.kind == "mute" or dest.kind == "send" then
    return ctx.report:add("Automation of " .. (dest.kind == "mute" and "mute" or "send levels"), dest.label or where)
  end
  local pu = p.attr.unit
  local function convert(v)
    if dest.kind == "volume" then
      if pu == "decibel" then return v end
      if pu == "normalized" then return db(v * (dest.max or 1)) end
      return db(v)
    elseif dest.kind == "pan" then
      if pu == "normalized" or pu == nil then return math.max(-1, math.min(1, v * 2 - 1)) end
      return math.max(-1, math.min(1, v))
    end
    if pu == "normalized" then return dest.min + v * (dest.max - dest.min) end
    return math.max(dest.min, math.min(dest.max, v))
  end
  local points, holds = {}, {}
  for _, pt in ipairs(p.children) do
    if pt.name == "RealPoint" then
      points[#points + 1] = { to_beats(num(pt.attr.time, 0), unit), convert(num(pt.attr.value, 0)) }
      if pt.attr.interpolation ~= "linear" then holds[#points] = true end
    elseif pt.name ~= "Target" then
      ctx.report:count("Automation points other than real values", where)
    end
  end
  if #points == 0 then return end
  local opts = { target = dest.kind, points = points }
  if dest.kind == "param" then opts.target, opts.device, opts.param = "param", dest.device, dest.key end
  local ok, id = pcall(api.lane_add, dest.track, opts)
  if not ok then return ctx.report:add("Automation", where .. ": " .. tostring(id)) end
  local stored, shapes = api.lane_points(id), {}
  for i in pairs(holds) do
    if stored[i] and i < #stored then shapes[#shapes + 1] = { beat = stored[i][1], shape = "hold", tension = 0 } end
  end
  if #shapes > 0 then api.lane_set_shapes(id, shapes) end
end

--- Walk the arrangement's lanes, with the track and time unit each one
--- inherits.
local function walk_lanes(e, ctx, track, unit)
  local t = e.attr.track and ctx.tracks[e.attr.track]
  if t == false then
    if #e.children > 0 then ctx.report:add("The master of the file (merged: the project keeps its own)", "its clips and automation") end
    return
  end
  if e.attr.track and t == nil then
    return ctx.report:add("Lanes of tracks that are not in the file", tostring(e.attr.track))
  end
  track = t or track
  unit = e.attr.timeUnit or unit
  if track then ctx.label = track == 0 and "Master" or api.track_get(track, "name") end
  if e.name == "Lanes" then
    for _, c in ipairs(e.children) do walk_lanes(c, ctx, track, unit) end
  elseif e.name == "Clips" then
    if not track then return ctx.report:add("Clips not on a track", "arrangement") end
    if track == 0 then return ctx.report:add("Clips on the master (left out)", "Master") end
    for _, c in ipairs(e:all("Clip")) do
      import_clip(c, track, ctx, function(x) return to_beats(x, unit) end, unit, -INF, INF, {})
    end
  elseif e.name == "Points" then
    import_points(e, ctx, unit)
  elseif e.name == "Notes" or e.name == "Audio" or e.name == "Warps" then
    if not track or track == 0 then return ctx.report:add("Content not on a track", e.name) end
    -- Content straight on a track: one clip that holds it.
    local clip = xml.element("Clip", { time = "0" })
    clip.children = { e }
    local last = 4
    for _, n in ipairs(e:all("Note")) do last = math.max(last, num(n.attr.time, 0) + num(n.attr.duration, 0)) end
    clip.attr.duration = tostring(last)
    import_clip(clip, track, ctx, function(x) return to_beats(x, unit) end, unit, -INF, INF, {})
  elseif e.name == "markers" or e.name == "Markers" then
    ctx.report:add("Markers of a track (left out)", ctx.label or "?")
  else
    ctx.report:add("Timelines paw cannot read", e.name)
  end
end

local function import_markers(m, ctx)
  local unit = m.attr.timeUnit or "beats"
  local list = {}
  for _, e in ipairs(m:all("Marker")) do
    local marker = { name = e.attr.name or "", beat = to_beats(num(e.attr.time, 0), unit) }
    if e.attr.color and e.attr.color:match("^#%x%x%x%x%x%x$") then marker.color = e.attr.color:lower() end
    local len = e.attr.comment and tonumber(e.attr.comment:match("^paw region: ([%d.]+) beats$"))
    if len then marker.length = len end
    list[#list + 1] = marker
  end
  if #list == 0 then return end
  local meta = api.project_get().meta or {}
  local all = type(meta.markers) == "table" and meta.markers or {}
  local top = 0
  for _, x in ipairs(all) do top = math.max(top, tonumber(x.id) or 0) end
  for i, x in ipairs(list) do
    x.id = top + i
    all[#all + 1] = x
  end
  meta.markers = all
  api.project_set("meta", meta)
end

--- The tempo map of the transport and the arrangement, in beats.
local function tempo_map(root, arr, ctx)
  local transport = root:child("Transport")
  local tempo = transport and transport:child("Tempo")
  local sig = transport and transport:child("TimeSignature")
  local bpm = math.max(1, math.min(999, num(tempo and tempo.attr.value, 120)))
  local tempos = { { beat = 0, bpm = bpm, ramp = false } }
  local sigs = { { beat = 0, num = num(sig and sig.attr.numerator, 4), den = num(sig and sig.attr.denominator, 4) } }
  local ta = arr and arr:child("TempoAutomation")
  if ta then
    local unit = ta.attr.timeUnit or "beats"
    if unit == "seconds" then ctx.report:add("Tempo", "tempo points in seconds were read as beats") end
    local list = {}
    for _, pt in ipairs(ta:all("RealPoint")) do
      list[#list + 1] = { beat = num(pt.attr.time, 0), bpm = math.max(1, math.min(999, num(pt.attr.value, bpm))),
        ramp = pt.attr.interpolation == "linear" }
    end
    table.sort(list, function(x, y) return x.beat < y.beat end)
    if #list > 0 then
      if list[1].beat > 1e-9 then table.insert(list, 1, { beat = 0, bpm = bpm, ramp = false }) end
      tempos = list
    end
  end
  local sa = arr and arr:child("TimeSignatureAutomation")
  if sa then
    local list = {}
    for _, pt in ipairs(sa:all("TimeSignaturePoint")) do
      list[#list + 1] = { beat = num(pt.attr.time, 0), num = num(pt.attr.numerator, 4), den = num(pt.attr.denominator, 4) }
    end
    table.sort(list, function(x, y) return x.beat < y.beat end)
    if #list > 0 then
      if list[1].beat > 1e-9 then table.insert(list, 1, sigs[1]) end
      sigs = list
    end
  end
  return tempos, sigs
end

local function index_ids(e, ids)
  if e.attr.id then ids[e.attr.id] = e end
  for _, c in ipairs(e.children) do index_ids(c, ids) end
end

--- Import the files of an archive (name to contents). `opts.path` is
--- where it was read from; `opts.merge` adds its tracks to the project.
function M.files(files, opts)
  opts = opts or {}
  local text = files["project.xml"]
  if not text then error("not a DAWproject file: there is no project.xml", 0) end
  local root = xml.parse(text)
  if root.name ~= "Project" then error("not a DAWproject file: project.xml holds <" .. root.name .. ">", 0) end
  local path = opts.path or "untitled.dawproject"
  local dir = path:match("^(.*)/[^/]*$") or "."
  local stem = (path:match("([^/]+)$") or path):gsub("%.[Dd][Aa][Ww][Pp][Rr][Oo][Jj][Ee][Cc][Tt]$", "")
  local ctx = {
    files = files, dir = dir, media_dir = opts.media_dir or (dir .. "/" .. stem .. " media"),
    report = reports.new("Not carried over from " .. (path:match("([^/]+)$") or path) .. ":"),
    tracks = {}, channels = {}, params = {}, list = {}, placeholders = {}, extracted = {}, ids = {},
    clips = 0, devices = 0, merge = opts.merge,
  }
  index_ids(root, ctx.ids)
  local arr = root:child("Arrangement")
  local tempos, sigs = tempo_map(root, arr, ctx)
  if opts.merge then
    local p = api.project_get()
    if #tempos > 1 or #sigs > 1 or math.abs(tempos[1].bpm - p.tempo) > 1e-9 then
      ctx.report:add("Tempo", string.format("the project keeps its own tempo map (%g BPM); the file's (%g BPM) is not used",
        p.tempo, tempos[1].bpm))
    end
  else
    api.project_new()
    api.tempo_set_points(tempos, sigs)
    local meta_text = files["metadata.xml"]
    local title
    if meta_text then
      local ok, m = pcall(xml.parse, meta_text)
      local t = ok and m:child("Title")
      title = t and t.text
    end
    api.project_set("name", title and title ~= "" and title or stem)
  end
  local structure = root:child("Structure")
  if structure then import_tracks(structure, nil, ctx) end
  routing(ctx)
  for track, holders in pairs(ctx.placeholders) do
    local meta = api.track_get(track, "meta") or {}
    meta.dawproject_placeholders = holders
    api.track_set(track, "meta", meta)
  end
  if arr then
    for _, c in ipairs(arr.children) do
      if c.name == "Lanes" then
        walk_lanes(c, ctx, nil, c.attr.timeUnit or "beats")
      elseif c.name == "Markers" then
        import_markers(c, ctx)
      end
    end
  end
  local scenes = root:child("Scenes")
  if scenes and #scenes.children > 0 then ctx.report:count("Scenes of the clip launcher", "scenes", #scenes.children) end
  local ids = {}
  for i, t in ipairs(ctx.list) do ids[i] = t.id end
  return { tracks = ids, report = ctx.report, clips = ctx.clips, devices = ctx.devices }
end

--- Read a .dawproject file and import it.
function M.file(path, opts)
  opts = opts or {}
  opts.path = path
  local f = io.open(path, "rb")
  if not f then error("cannot open " .. path, 0) end
  local data = f:read("*a")
  f:close()
  local files, why = paw.zip.read(data)
  if not files then error(path .. ": " .. why, 0) end
  return M.files(files, opts)
end

return M
