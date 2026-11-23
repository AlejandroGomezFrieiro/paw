-- Reading a DAWproject file into paw.
--
--   local result = require("interop.dawproject.import").file("song.dawproject")
--   print(result.report:text())     -- what could not be carried over, grouped
--
-- The tracks of <Structure> become paw's tracks in the same order (a
-- nested track goes into its folder); <Arrangement> gives their clips and
-- automation. Audio in the archive is copied into a folder beside it.
--
-- Written in Teal (paw/lang.tl): paw compiles it as it loads.
local xml = require("interop.dawproject.xmlio")
local vst3 = require("interop.dawproject.vst3")
local interop = require("interop")
local reports = require("interop.report")
local type types = require("paw.types")
local type pawxml = require("paw.xml")

local api = paw.api
local b64 = paw.bytes

local type Element = pawxml.Element
local type Report = reports.Report

local record M
  --- A device or plugin that could not come across, kept in the track's
  --- meta (`dawproject_placeholders`) to be written back where it was.
  record Placeholder
    name: string
    format: string
    --- Its place among the devices of the channel, from 1.
    position: integer
    reason: string
    --- Its element, as XML.
    xml: string
    --- Its state file, base64.
    state: string
  end

  --- What a VST3 plugin keeps in its device's meta (`meta.dawproject`):
  --- its class id, for the file it is written to.
  record DeviceMeta
    class: string
  end
end

local type Placeholder = M.Placeholder

local INF = math.huge

--- A gain as decibels, from -120 to 24.
local db = interop.db

--- What a parameter element of the file stands for: a parameter of a
--- device, or the volume, pan or mute of a track, or the level of a send.
local enum ParamKind
  "param"
  "volume"
  "pan"
  "mute"
  "send"
end

local record Param
  kind: ParamKind
  track: integer
  --- A parameter of a device: the device, its key, and its range in paw
  --- and in the file.
  device: integer
  key: string
  min: number
  max: number
  own_min: number
  own_max: number
  --- What the report names for a mute or a send.
  label: string
end

--- A track of the file as it became a track of paw.
local record TrackEntry
  id: integer
  el: Element
  channel: Element
  parent: TrackEntry
  name: string
end

--- What an import keeps while it runs.
local record Ctx
  --- The files of the archive by name.
  files: {string: string}
  --- The folder of the file, and where its audio goes.
  dir: string
  media_dir: string
  report: Report
  --- The tracks of paw by the id of their element in the file; the
  --- elements of a master that a merge leaves out are in `dropped`.
  tracks: {string: integer}
  dropped: {string: boolean}
  --- The track of each channel, by the channel's id.
  channels: {string: integer}
  --- What each parameter element stands for, by its id.
  params: {string: Param}
  --- The new tracks in order.
  list: {TrackEntry}
  placeholders: {integer: {Placeholder}}
  --- The audio files of the archive written to disk, by their name in it.
  extracted: {string: string}
  --- Every element of the project with an id.
  ids: {string: Element}
  clips: integer
  devices: integer
  merge: boolean
  --- The track whose lanes are being read, for the report.
  label: string
end

--- An attribute as the file has it: text.
local function attr(e: Element, key: string): string
  local v = e.attr[key]
  if v == nil then
    return nil
  end
  return tostring(v)
end

--- An attribute as a number, or `default` when there is none.
local function num(e: Element, key: string, default?: number): number
  local n = tonumber(e and attr(e, key))
  if n == nil then
    return default
  end
  return n
end

local clamp = paw.util.clamp

--- The first line of an error, as text.
local function first_line(err: string): string
  return (tostring(err):gsub("\n.*", ""))
end

--- A value of a parameter element in paw's units: a volume in dB, a pan
--- from -1 to 1.
local function level(e: Element): number
  if not e then
    return nil
  end
  local v, unit = num(e, "value", 0), attr(e, "unit")
  if unit == "decibel" then
    return v
  end
  if unit == "normalized" then
    return db(v * num(e, "max", 1))
  end
  return db(v)
end

local function pan(e: Element): number
  if not e then
    return nil
  end
  local v = num(e, "value", 0.5)
  if attr(e, "unit") == "normalized" or (num(e, "min", -1) >= 0) then
    return clamp(v * 2 - 1, -1, 1)
  end
  return clamp(v, -1, 1)
end

-- Devices ------------------------------------------------------------------------------

local PLUGINS: {string: boolean} = {
  ClapPlugin = true,
  Vst3Plugin = true,
  Vst2Plugin = true,
  AuPlugin = true,
  Device = true,
  BuiltinDevice = true,
  Equalizer = true,
  Compressor = true,
  NoiseGate = true,
  Limiter = true,
}

--- The parameter of a device that a parameter element names: by the
--- plugin's own id (`parameterID` of a CLAP or VST3 plugin, which a DAW
--- writes signed), by name, by key, or by its place (`parameterID` of a
--- device of paw).
local function param_key(dev: integer, pe: Element, plugin: boolean): types.ParamInfo
  local infos = api.device_get(dev).param_info or {}
  local name = (attr(pe, "name") or ""):lower()
  local own = plugin and num(pe, "parameterID")
  if own then
    if own < 0 then
      own = own + 2 ^ 32
    end
    local id = string.format("%d", math.floor(own))
    for _, p in ipairs(infos) do
      if p.id == id then
        return p
      end
    end
  end
  for _, p in ipairs(infos) do
    if p.name:lower() == name or p.key:lower() == name then
      return p
    end
  end
  local index = not plugin and math.tointeger(num(pe, "parameterID"))
  if index and name == "" then
    return infos[index + 1]
  end
end

--- A device element on its way into a track: what finds it, its state
--- file, and its bypass.
local record DeviceIn
  el: Element
  track: integer
  name: string
  device_id: string
  state: string
  bypass: boolean
end

--- Add a device of `kind`; nil and why when it does not load here.
local function add_device(d: DeviceIn, kind: string, opts?: types.DeviceOptions): integer, string
  local ok, dev = pcall(api.device_add, d.track, kind, opts or {}) as (boolean, integer)
  if not ok then
    return nil, "could not load here: " .. first_line(tostring(dev))
  end
  if d.bypass then
    api.device_set(dev, {bypass = true})
  end
  return dev
end

--- A VST3 plugin with its state from its .vstpreset; with its defaults
--- when the plugin refuses the state.
local function add_vst3(d: DeviceIn, ctx: Ctx, where: string): integer, string
  local t = interop.find_plugin(
    {
      format = "vst3",
      id = d.device_id ~= "" and d.device_id or nil,
      name = d.name,
      vendor = attr(d.el, "deviceVendor"),
    }
  )
  if not t then
    return nil, "not installed here"
  end
  local s, class: string, string
  if d.state then
    s, class = vst3.state(d.state)
  end
  local id, why = add_device(d, t.kind, {state = s and b64.base64(s) or nil})
  if not id and s then
    id, why = add_device(d, t.kind)
    ctx.report:add("Plugin settings", where .. ": the plugin did not take its state; defaults used")
  end
  if id then
    local meta: M.DeviceMeta = {class = class or d.device_id}
    api.device_set(id, {meta = {dawproject = meta}})
  end
  return id, why
end

--- Add the device an element names. Returns its id (or nil and why), and
--- whether its parameter values come from the file (a device with no
--- state of its own).
local function add_from(d: DeviceIn, ctx: Ctx, where: string): integer, string, boolean
  local tag = d.el.name
  local device_id = d.device_id
  local builtin = tag == "Device" or tag == "BuiltinDevice"
  if tag == "ClapPlugin" then
    local kind = "clap:" .. device_id
    if not interop.installed(kind) then
      return nil, "not installed here"
    end
    local id, why = add_device(d, kind, {state = d.state and b64.base64(d.state) or nil})
    return id, why
  elseif tag == "Vst3Plugin" then
    local id, why = add_vst3(d, ctx, where)
    return id, why
  elseif builtin and device_id:match("^paw:") then
    local id, why = add_device(d, device_id:sub(5))
    return id, why, true
  elseif builtin and device_id:match("^lv2:") then
    if not interop.installed(device_id) then
      return nil, "not installed here", true
    end
    local id, why = add_device(d, device_id)
    return id, why, true
  elseif tag == "Vst2Plugin" then
    return nil, "VST2 plugins are not hosted here"
  elseif tag == "AuPlugin" then
    return nil, "Audio Units are not hosted on Linux"
  end
  return nil, "a device of another program"
end

--- The parameters of a device, as automation targets (and their values
--- for devices that have no state of their own).
local function device_params(e: Element, id: integer, track: integer, set_params: boolean, ctx: Ctx, where: string)
  local tag = e.name
  local params = e:child("Parameters")
  local unknown: {string} = {}
  for _, pe in ipairs(params and params.children or {}) do
    local p = param_key(id, pe, tag == "ClapPlugin" or tag == "Vst3Plugin")
    if p then
      local pid = attr(pe, "id")
      if pid then
        ctx.params[pid] = {
          kind = "param",
          track = track,
          device = id,
          key = p.key,
          min = p.min,
          max = p.max,
          own_min = num(pe, "min"),
          own_max = num(pe, "max"),
        }
      end
      local v = num(pe, "value")
      if set_params and v then
        pcall(api.device_set_param, id, p.key, v)
      end
    elseif set_params then
      unknown[#unknown + 1] = attr(pe, "name") or "?"
    end
  end
  if #unknown > 0 then
    ctx.report:add("Plugin settings", where .. ": parameters not found here: " .. table.concat(unknown, ", "))
  end
end

local function import_device(e: Element, track: integer, ctx: Ctx, label: string, position: integer): integer
  local tag = e.name
  local name = attr(e, "deviceName") or attr(e, "name") or tag
  local where = label .. ": " .. name
  local state_el = e:child("State")
  local state_path = state_el and attr(state_el, "path")
  local enabled = e:child("Enabled")
  local d: DeviceIn = {
    el = e,
    track = track,
    name = name,
    device_id = attr(e, "deviceID") or "",
    state = state_path and ctx.files[state_path],
    bypass = enabled and attr(enabled, "value") == "false",
  }
  local id, why, set_params = add_from(d, ctx, where)
  if not id then
    ctx.report:add("Plugins and devices left as placeholders", where .. " (" .. tostring(why) .. ")")
    ctx.placeholders[track] = ctx.placeholders[track] or {}
    table.insert(
      ctx.placeholders[track],
      {
        name = name,
        format = tag,
        position = position,
        reason = why,
        xml = paw.xml.encode(e, {indent = "  ", digits = 12}),
        state = d.state and b64.base64(d.state) or nil,
      }
    )
    return nil
  end
  ctx.devices = ctx.devices + 1
  device_params(e, id, track, set_params, ctx, where)
  return id
end

-- Structure ----------------------------------------------------------------------------

local function import_channel(c: Element, track: integer, ctx: Ctx, label: string)
  ctx.channels[attr(c, "id") or ""] = track
  local vol, p, mute = c:child("Volume"), c:child("Pan"), c:child("Mute")
  if vol then
    api.track_set(track, {volume = level(vol)})
  end
  if p then
    api.track_set(track, {pan = pan(p)})
  end
  if mute and attr(mute, "value") == "true" then
    api.track_set(track, {mute = true})
  end
  if track ~= 0 and attr(c, "solo") == "true" then
    api.track_set(track, {solo = true})
  end
  if vol and attr(vol, "id") then
    ctx.params[attr(vol, "id")] = {kind = "volume", track = track, max = num(vol, "max", 1)}
  end
  if p and attr(p, "id") then
    ctx.params[attr(p, "id")] = {kind = "pan", track = track}
  end
  if mute and attr(mute, "id") then
    ctx.params[attr(mute, "id")] = {kind = "mute", track = track, label = label}
  end
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
local function import_tracks(parent_el: Element, parent_track: TrackEntry, ctx: Ctx)
  for _, e in ipairs(parent_el.children) do
    if e.name == "Track" or (e.name == "Channel" and not parent_track) then
      local c = e.name == "Channel" and e or e:child("Channel")
      local name = attr(e, "name") or (c and attr(c, "name")) or nil
      local key = attr(e, "id") or ""
      local master = c and attr(c, "role") == "master"
      if master and not ctx.merge then
        ctx.tracks[key] = 0
        import_channel(c, 0, ctx, "Master")
      elseif master then
        -- Merged: what goes to the file's master goes to this project's.
        ctx.dropped[key] = true
        ctx.channels[attr(c, "id") or ""] = 0
        ctx.report:add("The master of the file (merged: the project keeps its own)", attr(e, "name") or "Master")
      else
        local id = api.track_add({name = name})
        local t: TrackEntry = {id = id, el = e, channel = c, parent = parent_track, name = api.track_get(id).name}
        ctx.list[#ctx.list + 1] = t
        ctx.tracks[key] = id
        local color = attr(e, "color")
        if color and color:match("^#%x%x%x%x%x%x$") then
          api.track_set(id, {color = color:lower()})
        end
        if c then
          import_channel(c, id, ctx, t.name)
        end
        if e.name == "Track" then
          import_tracks(e, t, ctx)
        end
      end
    end
  end
end

--- The sends of a channel, as paw's sends of its track.
local function channel_sends(t: TrackEntry, c: Element, ctx: Ctx)
  local sends_el = c and c:child("Sends")
  local sends: {types.Send} = {}
  for _, s in ipairs(sends_el and sends_el:all("Send") or {}) do
    local dest = attr(s, "destination")
    local target = ctx.channels[dest or ""]
    local enable = s:child("Enable")
    local what = t.name .. " -> " .. tostring(dest)
    if not target or target == 0 then
      ctx.report:add("Sends to channels that are not tracks", what)
    elseif enable and attr(enable, "value") == "false" then
      ctx.report:add("Sends that are off (left out)", what)
    else
      sends[#sends + 1] = {
        target = target, level = level(s:child("Volume")) or 0, pre = attr(s, "type") == "pre" or nil
      }
      local sp = s:child("Pan")
      if sp and math.abs(pan(sp)) > 1e-6 then
        ctx.report:add("Send pan", what)
      end
      local sv = s:child("Volume")
      if sv and attr(sv, "id") then
        ctx.params[attr(sv, "id")] = {kind = "send", label = what}
      end
    end
  end
  if #sends > 0 then
    local ok, err = pcall(api.track_set, t.id, {sends = sends}) as (boolean, string)
    if not ok then
      ctx.report:add("Routing", t.name .. ": sends: " .. tostring(err))
    end
  end
end

--- The output of each track (its channel's destination, else its folder)
--- and its sends.
local function routing(ctx: Ctx)
  for _, t in ipairs(ctx.list) do
    local c = t.channel
    local destination = c and attr(c, "destination")
    local dest = destination and ctx.channels[destination]
    if dest == nil and t.parent then
      dest = t.parent.id
    end
    if dest and dest ~= 0 and dest ~= t.id then
      local ok, err = pcall(api.track_set, t.id, {output = dest}) as (boolean, string)
      if not ok then
        ctx.report:add("Routing", t.name .. ": " .. tostring(err))
      end
    elseif destination and dest == nil then
      ctx.report:add("Routing", t.name .. ": to a channel that is not in the file")
    end
    channel_sends(t, c, ctx)
  end
end

-- Clips --------------------------------------------------------------------------------

local CONTENT: {string: boolean} = {
  Timeline = true,
  Lanes = true,
  Notes = true,
  Clips = true,
  ClipSlot = true,
  markers = true,
  Warps = true,
  Audio = true,
  Video = true,
  Points = true,
}

local function content_of(e: Element): Element
  for _, c in ipairs(e.children) do
    if CONTENT[c.name] then
      return c
    end
  end
end

--- A MIDI expression of a Points timeline as a controller move of paw, or nil.
local function move_of(target: Element, unit: string, v: number): types.Control
  local expr = attr(target, "expression")
  if expr == "channelController" then
    return {type = "cc", number = math.floor(num(target, "controller", 0)), value = clamp(v, 0, 1)}
  elseif expr == "pitchBend" then
    return {type = "bend", value = clamp(unit == "normalized" and v * 2 - 1 or v, -1, 1)}
  elseif expr == "channelPressure" then
    return {type = "pressure", value = clamp(v, 0, 1)}
  elseif expr == "polyPressure" then
    return {type = "pressure", key = math.floor(num(target, "key", 60)), value = clamp(v, 0, 1)}
  elseif expr == "programChange" then
    return {type = "program", program = math.floor(clamp(math.floor(v + 0.5), 0, 127)), value = 0}
  end
end

--- Notes and controller moves of a MIDI content (Notes, or Lanes holding
--- Notes and Points), at their times in content units.
local function midi_content(e: Element, ctx: Ctx, label: string, notes: {types.Note}, moves: {types.Control})
  if e.name == "Notes" then
    local rel = 0
    for _, n in ipairs(e:all("Note")) do
      local vel = num(n, "vel", 100 / 127)
      local channel = num(n, "channel", 0)
      notes[#notes + 1] = {
        start = num(n, "time", 0),
        length = num(n, "duration", 0.25),
        pitch = math.floor(num(n, "key", 60)),
        velocity = math.floor(clamp(math.floor(vel * 127 + 0.5), 1, 127)),
        meta = channel ~= 0 and {channel = channel + 1} or nil,
      }
      if attr(n, "rel") and math.abs(num(n, "rel", vel) - vel) > 1e-6 then
        rel = rel + 1
      end
      if #n.children > 0 then
        ctx.report:count("Per-note expressions", label)
      end
    end
    if rel > 0 then
      ctx.report:count("Note-off velocities", label, rel)
    end
  elseif e.name == "Lanes" then
    for _, c in ipairs(e.children) do
      midi_content(c, ctx, label, notes, moves)
    end
  elseif e.name == "Points" then
    local target = e:child("Target")
    local unit = attr(e, "unit")
    for _, pt in ipairs(e.children) do
      if pt.name ~= "Target" then
        local m = target and move_of(target, unit, num(pt, "value", 0))
        if m then
          m.start = num(pt, "time", 0)
          moves[#moves + 1] = m
        else
          ctx.report:count(
            "Expressions other than MIDI controllers", label .. ": " .. tostring(target and attr(target, "expression"))
          )
        end
      end
    end
  else
    ctx.report:add("Clip contents paw cannot read", label .. ": " .. e.name)
  end
end

--- The beats of a time in a timeline's unit.
local function to_beats(t: number, unit: string): number
  if unit == "seconds" then
    return api.tempo_beat(t)
  end
  return t
end

--- The path of an audio file on disk: an external file where it is, or a
--- file of the archive written beside it (once).
local function audio_path(file: Element, ctx: Ctx, label: string): string
  local path = file and attr(file, "path")
  if not path then
    return nil
  end
  if attr(file, "external") == "true" then
    if path:sub(1, 1) ~= "/" then
      path = ctx.dir .. "/" .. path
    end
    if not io.open(path, "rb") then
      ctx.report:add("Missing media", label .. ": " .. path)
      return nil
    end
    return path
  end
  if ctx.extracted[path] then
    return ctx.extracted[path]
  end
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

--- What a parent clip adds to the clips in it: its name, mute and fades.
local record Outer
  name: string
  muted: boolean
  fade_in: number
  fade_out: number
end

--- A clip of the file, placed on the arrangement: the beats it plays in
--- (`a` to `b`), its fades in beats, and how its content time runs.
local record Clip
  el: Element
  track: integer
  name: string
  label: string
  muted: boolean
  --- Its start and stop in beats, and the part it plays.
  start: number
  stop: number
  a: number
  b: number
  fade_in: number
  fade_out: number
  --- The unit of its content time, and the content time at its start.
  unit: string
  play_start: number
  --- Its loop in content time, when it loops past its end.
  looping: boolean
  loop_start: number
  loop_end: number
  content: Element
end

--- Content time at a beat of the arrangement.
local function content_at(clip: Clip, beat: number): number
  if clip.unit == "seconds" then
    return clip.play_start + api.tempo_seconds(beat) - api.tempo_seconds(clip.start)
  end
  return clip.play_start + (beat - clip.start)
end

--- Beats from `at` that `x` content units take.
local function content_beats(clip: Clip, at: number, x: number): number
  if clip.unit == "seconds" then
    return api.tempo_beat(api.tempo_seconds(at) + x) - at
  end
  return x
end

local import_clip: function(
  c: Element,
  track: integer,
  ctx: Ctx,
  place: function(number): number,
  parent_unit: string,
  lo: number,
  hi: number,
  outer: Outer
)

--- Clips inside a clip: each placed by the content's time.
local function inner_clips(clip: Clip, ctx: Ctx)
  local function inner_place(x: number): number
    if clip.unit == "seconds" then
      return api.tempo_beat(api.tempo_seconds(clip.start) + (x - clip.play_start))
    end
    return clip.start + (x - clip.play_start)
  end
  if clip.looping then
    ctx.report:add("Loops of clips that hold clips (played once)", clip.label)
  end
  local inner = clip.content:all("Clip")
  for _, ic in ipairs(inner) do
    import_clip(
      ic,
      clip.track,
      ctx,
      inner_place,
      clip.unit,
      clip.a,
      clip.b,
      {
        name = clip.name,
        muted = clip.muted,
        fade_in = #inner == 1 and clip.fade_in or 0,
        fade_out = #inner == 1 and clip.fade_out or 0,
      }
    )
  end
end

--- The seconds of a file at a content time of a clip.
local type FileAt = function(x: number): number

--- How an audio clip reads its file: the file's seconds at a content time,
--- and how many times as long the clip plays them (from the first and the
--- last warp point).
local function warp_of(clip: Clip, ctx: Ctx): FileAt, number
  local content = clip.content
  local file_at: FileAt = function(x: number): number return x end
  local stretch = 1.0
  if content.name ~= "Warps" then
    return file_at, stretch
  end
  local warps = content:all("Warp")
  if #warps < 2 then
    return file_at, stretch
  end
  local w0, w1 = warps[1], warps[#warps]
  local t0, t1 = num(w0, "time", 0), num(w1, "time", 1)
  local c0, c1 = num(w0, "contentTime", 0), num(w1, "contentTime", 1)
  if c1 > c0 and t1 > t0 then
    local per = (c1 - c0) / (t1 - t0)
    file_at = function(x: number): number return c0 + (x - t0) * per end
    -- Seconds on the timeline for a unit of the content.
    local unit_seconds = (attr(content, "timeUnit") or clip.unit) == "seconds" and 1 or 60 / api.tempo_at(clip.start)
    stretch = unit_seconds / per
    if (attr(content, "contentTimeUnit") or "seconds") ~= "seconds" then
      ctx.report:add("Warps to a content in beats (read as seconds)", clip.label)
    end
  end
  if #warps > 2 then
    ctx.report:count("Warp points between the first and the last (stretched evenly)", clip.label)
  end
  return file_at, stretch
end

--- An audio clip (Audio, or Warps that hold Audio).
local function audio_clip(clip: Clip, ctx: Ctx)
  local content = clip.content
  local audio = content.name == "Audio" and content or content:child("Audio")
  if not audio then
    local inside = content_of(content)
    ctx.report:add("Clip contents paw cannot read", clip.label .. ": warps of " .. tostring(inside and inside.name))
    return
  end
  local path = audio_path(audio:child("File"), ctx, clip.label)
  if not path then
    return
  end
  local file_at, stretch = warp_of(clip, ctx)
  if clip.unit ~= "seconds" and content.name == "Audio" then
    ctx.report:add("Audio in beats (read as seconds)", clip.label)
  end
  local a, b = clip.a, clip.b
  local opts: types.ClipOptions = {
    name = clip.name,
    start = a,
    file = path,
    offset = math.max(0, file_at(content_at(clip, a))),
    length = b - a,
    stretch = math.abs(stretch - 1) > 1e-9 and stretch or nil,
  }
  if clip.looping then
    if opts.stretch then
      ctx.report:add("Loops of stretched audio (played once)", clip.label)
    else
      local into = (content_at(clip, a) - clip.loop_start) % (clip.loop_end - clip.loop_start)
      opts.loop = true
      opts.loop_length = content_beats(clip, a, clip.loop_end - clip.loop_start)
      opts.loop_start = -content_beats(clip, a, into)
      opts.offset = math.max(0, file_at(clip.loop_start + into))
    end
  end
  local ok, id = pcall(api.clip_add, clip.track, opts) as (boolean, integer)
  if not ok then
    ctx.report:add("Unreadable media", clip.label .. ": " .. first_line(tostring(id)))
    return
  end
  if clip.fade_in > 0 then
    pcall(api.clip_set, id, {fade_in = math.min(clip.fade_in, b - a)})
  end
  if clip.fade_out > 0 then
    pcall(api.clip_set, id, {fade_out = math.min(clip.fade_out, b - a)})
  end
  if clip.muted then
    api.clip_set(id, {muted = true})
  end
  ctx.clips = ctx.clips + 1
end

--- A MIDI clip: notes and moves at content times; in paw, from the
--- clip's start.
local function midi_clip(clip: Clip, ctx: Ctx)
  local notes: {types.Note} = {}
  local moves: {types.Control} = {}
  midi_content(clip.content, ctx, clip.label, notes, moves)
  if clip.unit == "seconds" then
    ctx.report:add("MIDI clips timed in seconds (read at the tempo of their start)", clip.label)
  end
  local scale = clip.unit == "seconds" and api.tempo_at(clip.start) / 60 or 1
  local base = content_at(clip, clip.a)
  for _, n in ipairs(notes) do
    n.start = (n.start - base) * scale
    n.length = n.length * scale
  end
  for _, m in ipairs(moves) do
    m.start = (m.start - base) * scale
  end
  table.sort(moves, function(x: types.Control, y: types.Control): boolean return x.start < y.start end)
  local opts: types.ClipOptions = {
    name = clip.name,
    start = clip.a,
    length = clip.b - clip.a,
    notes = notes,
    controls = moves,
  }
  if clip.looping then
    opts.loop = true
    opts.loop_length = (clip.loop_end - clip.loop_start) * scale
    opts.loop_start = (clip.loop_start - base) * scale
    -- paw keeps the repeat within one length before the clip.
    while opts.loop_start < -opts.loop_length do
      opts.loop_start = opts.loop_start + opts.loop_length
    end
    while opts.loop_start > 1e-9 do
      opts.loop_start = opts.loop_start - opts.loop_length
    end
  end
  local ok, id = pcall(api.clip_add, clip.track, opts) as (boolean, integer)
  if not ok then
    ctx.report:add("Clips that could not be added", clip.label .. ": " .. first_line(tostring(id)))
    return
  end
  if clip.muted then
    api.clip_set(id, {muted = true})
  end
  if clip.fade_in > 0 or clip.fade_out > 0 then
    ctx.report:count("Fades on MIDI clips", clip.label)
  end
  ctx.clips = ctx.clips + 1
end

--- A clip element placed on the arrangement, or nil when it plays nothing
--- between `lo` and `hi`.
local function place_clip(
  c: Element,
  track: integer,
  ctx: Ctx,
  place: function(number): number,
  parent_unit: string,
  lo: number,
  hi: number,
  outer: Outer
): Clip
  local time = num(c, "time", 0)
  local ps = num(c, "playStart", 0)
  local duration = num(c, "duration")
  if not duration and attr(c, "playStop") then
    duration = num(c, "playStop") - ps
  end
  local start = place(time)
  local stop = duration and place(time + duration) or hi
  if stop == INF then
    stop = start + 4
  end
  local a, b = math.max(start, lo), math.min(stop, hi)
  if b - a <= 1e-9 then
    return nil
  end
  local name = attr(c, "name") or outer.name
  local clip: Clip = {
    el = c,
    track = track,
    name = name,
    label = ctx.label .. ": " .. (name or "clip"),
    muted = attr(c, "enable") == "false" or outer.muted,
    start = start,
    stop = stop,
    a = a,
    b = b,
    unit = attr(c, "contentTimeUnit") or parent_unit,
    play_start = ps,
  }
  local fade_unit = attr(c, "fadeTimeUnit") or parent_unit
  local function fade_beats(at: number, len: number, back: boolean): number
    if not len or len <= 0 then
      return 0
    end
    if fade_unit == "seconds" then
      local s = api.tempo_seconds(at)
      return back and (at - api.tempo_beat(s - len)) or (api.tempo_beat(s + len) - at)
    end
    return len
  end
  clip.fade_in = fade_beats(a, num(c, "fadeInTime", 0), false)
  clip.fade_out = fade_beats(b, num(c, "fadeOutTime", 0), true)
  if num(c, "fadeInTime", 0) < 0 then
    ctx.report:add("Crossfades (fade in before the clip)", clip.label)
  end
  if clip.fade_in == 0 then
    clip.fade_in = outer.fade_in or 0
  end
  if clip.fade_out == 0 then
    clip.fade_out = outer.fade_out or 0
  end
  clip.loop_start, clip.loop_end = num(c, "loopStart"), num(c, "loopEnd")
  clip.looping = clip.loop_start
    and clip.loop_end
    and clip.loop_end > clip.loop_start
    and content_at(clip, stop) > clip.loop_end + 1e-6
  return clip
end

--- One <Clip>. `place` turns a time of the parent timeline into a beat of
--- the arrangement; `lo` and `hi` are the beats the parent lets it play in;
--- `outer` holds what a parent clip adds (fades, mute, name).
import_clip = function(
  c: Element,
  track: integer,
  ctx: Ctx,
  place: function(number): number,
  parent_unit: string,
  lo: number,
  hi: number,
  outer: Outer
)
  local clip = place_clip(c, track, ctx, place, parent_unit, lo, hi, outer)
  if not clip then
    return
  end
  local content = content_of(c)
  local reference = attr(c, "reference")
  if reference then
    content = ctx.ids[reference]
    if not content then
      ctx.report:add("Clips of a timeline that is not in the file", clip.label)
      return
    end
  end
  if not content then
    ctx.report:add("Empty clips", clip.label)
    return
  end
  clip.content = content
  if content.name == "Clips" then
    inner_clips(clip, ctx)
  elseif content.name == "Audio" or content.name == "Warps" then
    audio_clip(clip, ctx)
  elseif content.name == "Video" then
    ctx.report:add("Video", clip.label)
  else
    midi_clip(clip, ctx)
  end
end

-- Automation ---------------------------------------------------------------------------

--- A value of an automation point in paw's units for its target.
local function automation_value(dest: Param, unit: string, v: number): number
  if dest.kind == "volume" then
    if unit == "decibel" then
      return v
    end
    if unit == "normalized" then
      return db(v * (dest.max or 1))
    end
    return db(v)
  elseif dest.kind == "pan" then
    if unit == "normalized" or unit == nil then
      return clamp(v * 2 - 1, -1, 1)
    end
    return clamp(v, -1, 1)
  end
  if unit == "normalized" then
    return dest.min + v * (dest.max - dest.min)
  end
  return clamp(v, dest.min, dest.max)
end

local function import_points(p: Element, ctx: Ctx, unit: string)
  local target = p:child("Target")
  local where = ctx.label
  if not target then
    return
  end
  local expression = attr(target, "expression")
  if expression then
    ctx.report:count("Expressions on the arrangement (outside clips)", where .. ": " .. expression)
    return
  end
  local parameter = attr(target, "parameter")
  local dest = ctx.params[parameter or ""]
  if not dest then
    ctx.report:add("Automation of parameters paw does not have", where .. ": " .. tostring(parameter))
    return
  end
  if dest.kind == "mute" or dest.kind == "send" then
    ctx.report:add("Automation of " .. (dest.kind == "mute" and "mute" or "send levels"), dest.label or where)
    return
  end
  local point_unit = attr(p, "unit")
  local points: {types.LanePoint} = {}
  local holds: {integer: boolean} = {}
  for _, pt in ipairs(p.children) do
    if pt.name == "RealPoint" then
      points[#points + 1] = {
        to_beats(num(pt, "time", 0), unit), automation_value(dest, point_unit, num(pt, "value", 0))
      }
      if attr(pt, "interpolation") ~= "linear" then
        holds[#points] = true
      end
    elseif pt.name ~= "Target" then
      ctx.report:count("Automation points other than real values", where)
    end
  end
  if #points == 0 then
    return
  end
  local opts: types.LaneOptions = {target = dest.kind as types.LaneTarget, points = points}
  if dest.kind == "param" then
    opts.device, opts.param = dest.device, dest.key
  end
  local ok, id = pcall(api.lane_add, dest.track, opts) as (boolean, integer)
  if not ok then
    ctx.report:add("Automation", where .. ": " .. tostring(id))
    return
  end
  local stored = api.lane_points(id)
  local shapes: {types.LaneSegment} = {}
  for i in pairs(holds) do
    if stored[i] and i < #stored then
      shapes[#shapes + 1] = {beat = stored[i][1], shape = "hold", tension = 0}
    end
  end
  if #shapes > 0 then
    api.lane_set_shapes(id, shapes)
  end
end

--- Content straight on a track: one clip that holds it.
local function bare_content(e: Element, track: integer, unit: string, ctx: Ctx)
  local clip = xml.element("Clip", {time = "0"})
  clip.children = {e}
  local last = 4.0
  for _, n in ipairs(e:all("Note")) do
    last = math.max(last, num(n, "time", 0) + num(n, "duration", 0))
  end
  clip.attr.duration = tostring(last)
  import_clip(clip, track, ctx, function(x: number): number return to_beats(x, unit) end, unit, -INF, INF, {})
end

--- Walk the arrangement's lanes, with the track and time unit each one
--- inherits.
local function walk_lanes(e: Element, ctx: Ctx, track: integer, unit: string)
  local key = attr(e, "track")
  if key and ctx.dropped[key] then
    if #e.children > 0 then
      ctx.report:add("The master of the file (merged: the project keeps its own)", "its clips and automation")
    end
    return
  end
  local t = key and ctx.tracks[key]
  if key and t == nil then
    ctx.report:add("Lanes of tracks that are not in the file", key)
    return
  end
  track = t or track
  unit = attr(e, "timeUnit") or unit
  if track then
    ctx.label = track == 0 and "Master" or api.track_get(track).name
  end
  if e.name == "Lanes" then
    for _, c in ipairs(e.children) do
      walk_lanes(c, ctx, track, unit)
    end
  elseif e.name == "Clips" then
    if not track then
      ctx.report:add("Clips not on a track", "arrangement")
      return
    end
    if track == 0 then
      ctx.report:add("Clips on the master (left out)", "Master")
      return
    end
    for _, c in ipairs(e:all("Clip")) do
      import_clip(c, track, ctx, function(x: number): number return to_beats(x, unit) end, unit, -INF, INF, {})
    end
  elseif e.name == "Points" then
    import_points(e, ctx, unit)
  elseif e.name == "Notes" or e.name == "Audio" or e.name == "Warps" then
    if not track or track == 0 then
      ctx.report:add("Content not on a track", e.name)
      return
    end
    bare_content(e, track, unit, ctx)
  elseif e.name == "markers" or e.name == "Markers" then
    ctx.report:add("Markers of a track (left out)", ctx.label or "?")
  else
    ctx.report:add("Timelines paw cannot read", e.name)
  end
end

local function import_markers(m: Element)
  local unit = attr(m, "timeUnit") or "beats"
  local list: {interop.Marker} = {}
  for _, e in ipairs(m:all("Marker")) do
    local marker: interop.Marker = {name = attr(e, "name") or "", beat = to_beats(num(e, "time", 0), unit)}
    local color = attr(e, "color")
    if color and color:match("^#%x%x%x%x%x%x$") then
      marker.color = color:lower()
    end
    local comment = attr(e, "comment")
    local len = comment and tonumber(comment:match("^paw region: ([%d.]+) beats$"))
    if len then
      marker.length = len
    end
    list[#list + 1] = marker
  end
  if #list == 0 then
    return
  end
  interop.add_markers(list)
end

--- The tempo changes of <TempoAutomation>, in beats. Points in seconds
--- are placed in beats by the core, each from the stretch before it.
local function tempo_automation(ta: Element, bpm: number): {types.TempoPoint}
  local function bpm_of(pt: Element): number
    return clamp(num(pt, "value", bpm), 1, 999)
  end
  local points = ta:all("RealPoint")
  local list: {types.TempoPoint} = {}
  if attr(ta, "timeUnit") == "seconds" then
    if #points == 0 then
      return list
    end
    local seconds: {types.TempoSecondsPoint} = {{seconds = 0, bpm = bpm, ramp = false}}
    for _, pt in ipairs(points) do
      seconds[#seconds + 1] = {
        seconds = num(pt, "time", 0), bpm = bpm_of(pt), ramp = attr(pt, "interpolation") == "linear"
      }
    end
    list = api.tempo_from_seconds(seconds).tempos
  else
    for _, pt in ipairs(points) do
      list[#list + 1] = {beat = num(pt, "time", 0), bpm = bpm_of(pt), ramp = attr(pt, "interpolation") == "linear"}
    end
  end
  table.sort(list, function(x: types.TempoPoint, y: types.TempoPoint): boolean return x.beat < y.beat end)
  return list
end

--- The tempo map of the transport and the arrangement, in beats.
local function tempo_map(root: Element, arr: Element): {types.TempoPoint}, {types.SigPoint}
  local transport = root:child("Transport")
  local tempo = transport and transport:child("Tempo")
  local sig = transport and transport:child("TimeSignature")
  local bpm = clamp(num(tempo, "value", 120), 1, 999)
  local tempos: {types.TempoPoint} = {{beat = 0, bpm = bpm, ramp = false}}
  local sigs: {types.SigPoint} = {
    {beat = 0, num = math.floor(num(sig, "numerator", 4)), den = math.floor(num(sig, "denominator", 4))},
  }
  local ta = arr and arr:child("TempoAutomation")
  if ta then
    local list = tempo_automation(ta, bpm)
    if #list > 0 then
      if list[1].beat > 1e-9 then
        table.insert(list, 1, {beat = 0, bpm = bpm, ramp = false})
      end
      tempos = list
    end
  end
  local sa = arr and arr:child("TimeSignatureAutomation")
  if sa then
    local list: {types.SigPoint} = {}
    for _, pt in ipairs(sa:all("TimeSignaturePoint")) do
      list[#list + 1] = {
        beat = num(pt, "time", 0),
        num = math.floor(num(pt, "numerator", 4)),
        den = math.floor(num(pt, "denominator", 4)),
      }
    end
    table.sort(list, function(x: types.SigPoint, y: types.SigPoint): boolean return x.beat < y.beat end)
    if #list > 0 then
      if list[1].beat > 1e-9 then
        table.insert(list, 1, sigs[1])
      end
      sigs = list
    end
  end
  return tempos, sigs
end

local function index_ids(e: Element, ids: {string: Element})
  local id = attr(e, "id")
  if id then
    ids[id] = e
  end
  for _, c in ipairs(e.children) do
    index_ids(c, ids)
  end
end

--- A new project with the file's tempo map and title; when merged, the
--- project keeps its own (the report says so).
local function begin_project(files: {string: string}, root: Element, arr: Element, stem: string, ctx: Ctx)
  local tempos, sigs = tempo_map(root, arr)
  if ctx.merge then
    local p = api.project_get()
    if #tempos > 1 or #sigs > 1 or math.abs(tempos[1].bpm - p.tempo) > 1e-9 then
      ctx.report:add(
        "Tempo",
        string.format(
          "the project keeps its own tempo map (%g BPM); the file's (%g BPM) is not used", p.tempo, tempos[1].bpm
        )
      )
    end
    return
  end
  api.project_new()
  api.tempo_set_points(tempos, sigs)
  local meta_text = files["metadata.xml"]
  local title: string
  if meta_text then
    local ok, m = pcall(xml.parse, meta_text) as (boolean, Element)
    local t = ok and m:child("Title")
    title = t and t.text
  end
  api.project_set({name = title and title ~= "" and title or stem})
end

--- Keep the devices that could not come across in their tracks' meta.
local function keep_placeholders(ctx: Ctx)
  for track, holders in pairs(ctx.placeholders) do
    local meta = api.track_get(track).meta or {}
    meta.dawproject_placeholders = holders
    api.track_set(track, {meta = meta})
  end
end

--- Import the files of an archive (name to contents). `opts.path` is
--- where it was read from; `opts.merge` adds its tracks to the project.
function M.files(files: {string: string}, opts?: interop.Options): interop.Result
  opts = opts or {}
  local text = files["project.xml"]
  if not text then
    error("not a DAWproject file: there is no project.xml", 0)
  end
  local root = xml.parse(text)
  if root.name ~= "Project" then
    error("not a DAWproject file: project.xml holds <" .. root.name .. ">", 0)
  end
  local path = opts.path or "untitled.dawproject"
  local dir = path:match("^(.*)/[^/]*$") or "."
  local name = path:match("([^/]+)$") or path
  local stem = name:gsub("%.[Dd][Aa][Ww][Pp][Rr][Oo][Jj][Ee][Cc][Tt]$", "")
  local ctx: Ctx = {
    files = files,
    dir = dir,
    media_dir = opts.media_dir or (dir .. "/" .. stem .. " media"),
    report = reports.new("Not carried over from " .. name .. ":"),
    tracks = {},
    dropped = {},
    channels = {},
    params = {},
    list = {},
    placeholders = {},
    extracted = {},
    ids = {},
    clips = 0,
    devices = 0,
    merge = opts.merge,
  }
  index_ids(root, ctx.ids)
  local arr = root:child("Arrangement")
  begin_project(files, root, arr, stem, ctx)
  local structure = root:child("Structure")
  if structure then
    import_tracks(structure, nil, ctx)
  end
  routing(ctx)
  keep_placeholders(ctx)
  for _, c in ipairs(arr and arr.children or {}) do
    if c.name == "Lanes" then
      walk_lanes(c, ctx, nil, attr(c, "timeUnit") or "beats")
    elseif c.name == "Markers" then
      import_markers(c)
    end
  end
  local scenes = root:child("Scenes")
  if scenes and #scenes.children > 0 then
    ctx.report:count("Scenes of the clip launcher", "scenes", #scenes.children)
  end
  local ids: {integer} = {}
  for i, t in ipairs(ctx.list) do
    ids[i] = t.id
  end
  return {tracks = ids, report = ctx.report, clips = ctx.clips, devices = ctx.devices}
end

--- Read a .dawproject file and import it.
function M.file(path: string, opts?: interop.Options): interop.Result
  opts = opts or {}
  opts.path = path
  local f = io.open(path, "rb")
  if not f then
    error("cannot open " .. path, 0)
  end
  local data = f:read("*a")
  f:close()
  local files, why = paw.zip.read(data)
  if not files then
    error(path .. ": " .. tostring(why), 0)
  end
  return M.files(files, opts)
end

return M
