-- Writing paw's project as a DAWproject file: a ZIP archive with
-- project.xml, metadata.xml, the plugin states (plugins/) and the audio
-- files (audio/).
--
--   local result = require("dawproject.export").file("song.dawproject")
--   print(result.report:text())     -- what could not be written, grouped
--
-- Times are in beats on the arrangement (timeUnit="beats"); audio clips
-- play their files in seconds (contentTimeUnit="seconds").
local api = paw.api
local xml = require("dawproject.xmlio")
local media = require("dawproject.media")
local b64 = paw.bytes
local vst3 = require("dawproject.vst3")
local reports = require("dawproject.report")

local M = {}

local function amp(db)
  if db <= -120 then return 0 end
  return 10 ^ (db / 20)
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function el(name, attr, keys) return xml.element(name, attr), keys end

--- A new XML element with its attributes in the order given:
--- `node("Note", "time", 0, "duration", 1)`.
local function node(name, ...)
  local args, n = { ... }, select("#", ...)
  local e = xml.element(name)
  e.order = {}
  for i = 1, n, 2 do
    if args[i + 1] ~= nil then
      e.attr[args[i]] = args[i + 1]
      e.order[#e.order + 1] = args[i]
    end
  end
  return e
end
M.node = node

local function add(parent, child)
  parent.children[#parent.children + 1] = child
  return child
end

-- Pieces -------------------------------------------------------------------------------

local function real(name, ctx, value, unit, min, max, label)
  return node(name, "id", ctx.id(), "name", label, "unit", unit, "min", min, "max", max, "value", value)
end

local function bool(name, ctx, value, label)
  return node(name, "id", ctx.id(), "name", label, "value", value)
end

--- A plugin's own id of a parameter as DAWproject's `parameterID`, a
--- signed 32-bit number: CLAP and VST3 ids are unsigned, so those of
--- 2^31 and above are written below 0 (as Bitwig Studio does).
local function own_param_id(p)
  local n = tonumber(p.id)
  if not n or n ~= math.floor(n) or n < 0 or n >= 2 ^ 32 then return nil end
  return n >= 2 ^ 31 and n - 2 ^ 32 or n
end
M.own_param_id = own_param_id

--- The device of a plugin or of paw, with its parameters and its state as
--- a file. A plugin's parameter is written with the plugin's own id for
--- it; a parameter of paw (or of an LV2 plugin, whose ids are names) with
--- its place among the device's, from 0.
local function device(dev_id, ctx, label)
  local d = api.device_get(dev_id)
  local info = ctx.types[d.kind] or {}
  local format = info.format or d.format or "builtin"
  local role = info.category == "instrument" and "instrument" or (info.category == "midi" and "noteFX" or "audioFX")
  local name, vendor = info.name or d.kind, info.vendor ~= "" and info.vendor or nil
  local e
  if format == "clap" then
    e = node("ClapPlugin", "id", ctx.id(), "name", name, "deviceID", (d.kind:gsub("^clap:", "")), "deviceName", name,
      "deviceRole", role, "deviceVendor", vendor, "loaded", true)
  elseif format == "vst3" then
    e = node("Vst3Plugin", "id", ctx.id(), "name", name, "deviceName", name, "deviceRole", role, "deviceVendor", vendor,
      "loaded", true)
    local cid = d.plugin and d.plugin.id ~= "" and d.plugin.id
      or d.meta and d.meta.dawproject and d.meta.dawproject.class
    if cid then
      e.attr.deviceID = cid
      table.insert(e.order, 3, "deviceID")
    else
      ctx.report:add("VST3 plugins written without their class id (not installed here; a DAW finds them by name)",
        label .. ": " .. name)
    end
  elseif format == "lv2" then
    e = node("Device", "id", ctx.id(), "name", name, "deviceID", d.kind, "deviceName", name, "deviceRole", role,
      "deviceVendor", vendor, "loaded", true)
    ctx.report:add("LV2 plugins (DAWproject has no element for them: written as a device only paw reads)", label .. ": " .. name)
  else
    e = node("BuiltinDevice", "id", ctx.id(), "name", d.kind, "deviceID", "paw:" .. d.kind, "deviceName", d.kind,
      "deviceRole", role, "loaded", true)
    ctx.report:add("Devices of paw (written as built-in devices that only paw reads)", label .. ": " .. d.kind)
  end
  local params = add(e, node("Parameters"))
  ctx.params[dev_id] = {}
  local plugin = format == "clap" or format == "vst3"
  for i, p in ipairs(d.param_info or {}) do
    -- The host's own parameters of a plugin (wet, output) have no id of the plugin's.
    local pid = plugin and own_param_id(p) or (not plugin and i - 1) or nil
    local pe = add(params, node("RealParameter", "id", ctx.id(), "name", p.name, "parameterID", pid, "unit", "linear",
      "min", p.min, "max", p.max, "value", (d.params or {})[p.key] or p.default))
    ctx.params[dev_id][p.key] = { id = pe.attr.id, min = p.min, max = p.max }
  end
  add(e, bool("Enabled", ctx, not d.bypass, "On/Off"))
  local state = (format == "clap" or format == "vst3") and api.device_state(dev_id)
  if state and state ~= "" then
    local bytes = b64.unbase64(state)
    ctx.plugins = ctx.plugins + 1
    local path
    if format == "clap" then
      path = string.format("plugins/%03d.clap-preset", ctx.plugins)
    else
      path = string.format("plugins/%03d.vstpreset", ctx.plugins)
      bytes = vst3.preset(bytes, d.meta and d.meta.dawproject and d.meta.dawproject.class)
    end
    ctx.files[#ctx.files + 1] = { name = path, data = bytes }
    add(e, node("State", "path", path))
  end
  return e
end

--- A device kept from an imported file as it was, with new ids, and its
--- state file again.
local function placeholder(holder, ctx)
  local ok, e = pcall(xml.parse, holder.xml or "")
  if not ok then return nil end
  local function reid(x)
    if x.attr.id then x.attr.id = ctx.id() end
    for _, c in ipairs(x.children) do reid(c) end
  end
  reid(e)
  local st = e:child("State")
  if st and holder.state then
    ctx.plugins = ctx.plugins + 1
    local ext = (st.attr.path or ""):match("(%.[%w%-]+)$") or ""
    st.attr.path = string.format("plugins/%03d%s", ctx.plugins, ext)
    ctx.files[#ctx.files + 1] = { name = st.attr.path, data = b64.unbase64(holder.state) }
  end
  return e
end

-- Tracks -------------------------------------------------------------------------------

local function channel(t, ctx, role)
  local c = node("Channel", "id", ctx.channel[t.id], "role", role, "audioChannels", 2,
    "destination", t.id ~= 0 and (t.output and ctx.channel[t.output] or ctx.channel[0]) or nil,
    "solo", t.id ~= 0 and t.solo or nil)
  local label = t.id == 0 and "Master" or t.name
  -- Devices, and the plugins kept from an imported file at their places.
  local entries = {}
  for _, dev in ipairs(t.devices) do entries[#entries + 1] = { device = dev } end
  local holders = {}
  for _, h in ipairs((t.meta or {}).dawproject_placeholders or {}) do holders[#holders + 1] = h end
  table.sort(holders, function(x, y) return (x.position or 0) < (y.position or 0) end)
  for _, h in ipairs(holders) do
    table.insert(entries, math.max(1, math.min(h.position or #entries + 1, #entries + 1)), { holder = h })
  end
  if #entries > 0 then
    local devs = add(c, node("Devices"))
    for _, entry in ipairs(entries) do
      local e = entry.device and device(entry.device, ctx, label) or placeholder(entry.holder, ctx)
      if e then add(devs, e) end
    end
  end
  local mute = add(c, bool("Mute", ctx, t.mute, "Mute"))
  local pan = add(c, real("Pan", ctx, ((t.pan or 0) + 1) / 2, "normalized", 0, 1, "Pan"))
  if t.sends and #t.sends > 0 then
    local sends = add(c, node("Sends"))
    for _, s in ipairs(t.sends) do
      local send = add(sends, node("Send", "id", ctx.id(), "destination", ctx.channel[s.target], "type", s.pre and "pre" or "post"))
      add(send, real("Volume", ctx, amp(s.level), "linear", 0, 2, "Send"))
    end
  end
  local vol = add(c, real("Volume", ctx, amp(t.volume or 0), "linear", 0, 2, "Volume"))
  ctx.track_params[t.id] = { volume = vol.attr.id, pan = pan.attr.id, mute = mute.attr.id }
  return c
end

local function content_type(t)
  local kinds = {}
  for _, c in ipairs(api.clip_list(t.id)) do kinds[c.kind == "audio" and "audio" or "notes"] = true end
  local list = {}
  if kinds.audio then list[#list + 1] = "audio" end
  if kinds.notes then list[#list + 1] = "notes" end
  if #list == 0 then list[1] = "audio" end
  return table.concat(list, " ")
end

-- Clips --------------------------------------------------------------------------------

local EXPRESSION = { cc = "channelController", bend = "pitchBend", pressure = "channelPressure", program = "programChange" }

--- The controller moves of a MIDI clip as Points timelines, one for each
--- controller (and key).
local function control_points(controls, shift, ctx, label)
  local lanes, order = {}, {}
  local skipped = 0
  for _, c in ipairs(controls) do
    local expr = EXPRESSION[c.type]
    if c.type == "pressure" and c.key then expr = "polyPressure" end
    if not expr or (c.key and c.type ~= "pressure") then
      skipped = skipped + 1
    else
      local key = expr .. ":" .. tostring(c.number or c.key or "")
      if not lanes[key] then
        local p = node("Points", "id", ctx.id(), "unit", expr ~= "programChange" and "normalized" or nil)
        add(p, node("Target", "expression", expr, "channel", 0, "key", c.type == "pressure" and c.key or nil,
          "controller", c.type == "cc" and c.number or nil))
        lanes[key] = p
        order[#order + 1] = p
      end
      if expr == "programChange" then
        add(lanes[key], node("IntegerPoint", "time", c.start + shift, "value", c.program))
        if c.bank then ctx.report:count("Banks of program changes", label) end
      else
        local v = c.value
        if expr == "pitchBend" then v = (v + 1) / 2 end
        add(lanes[key], node("RealPoint", "time", c.start + shift, "value", v, "interpolation", "hold"))
      end
    end
  end
  if skipped > 0 then ctx.report:count("Registered, assignable and per-note controllers", label, skipped) end
  return order
end

local function midi_clip(clip, ctx, label)
  local notes = api.clip_notes(clip.id)
  local controls = api.clip_controls(clip.id)
  -- The content starts at the earliest of the clip, its notes and its loop.
  local first = 0
  for _, n in ipairs(notes) do first = math.min(first, n.start) end
  for _, c in ipairs(controls) do first = math.min(first, c.start) end
  if clip["loop"] then first = math.min(first, clip.loop_start or 0) end
  local shift = -first
  local e = node("Clip", "time", clip.start, "duration", clip.length, "playStart", shift,
    "loopStart", clip["loop"] and (clip.loop_start + shift) or nil,
    "loopEnd", clip["loop"] and (clip.loop_start + clip.loop_length + shift) or nil,
    "enable", clip.muted and "false" or nil, "name", clip.name ~= "" and clip.name or nil)
  local list = node("Notes", "id", ctx.id())
  local attrs = 0
  for _, n in ipairs(notes) do
    local channel = n.meta and tonumber(n.meta.channel)
    add(list, node("Note", "time", n.start + shift, "duration", n.length, "channel", channel and channel - 1 or 0,
      "key", n.pitch, "vel", n.velocity / 127, "rel", n.velocity / 127))
    if n.attr then attrs = attrs + 1 end
  end
  if attrs > 0 then ctx.report:count("Note attributes (MIDI 2.0 articulations)", label, attrs) end
  local points = control_points(controls, shift, ctx, label)
  if #points == 0 then
    add(e, list)
  else
    local lanes = add(e, node("Lanes", "id", ctx.id()))
    add(lanes, list)
    for _, p in ipairs(points) do add(lanes, p) end
  end
  return e
end

--- The `<Audio>` element of a file, embedding it in the archive (once).
local function audio_file(path, ctx, label)
  local entry = ctx.media[path]
  if not entry then
    local data = read(path)
    local ok, probe = pcall(api.fs_sound, path)
    local info = ok and probe.seconds and { channels = probe.channels, rate = probe.rate, seconds = probe.seconds }
      or (data and media.info(data))
    if not data then
      ctx.report:add("Missing audio files (written as a reference to where they were)", label .. ": " .. path)
    end
    if not info then
      ctx.report:add("Audio files whose header paw cannot read (channels, rate and length guessed)", label .. ": " .. path)
      info = { channels = 2, rate = 48000, seconds = 0 }
    end
    local name = path:match("([^/]+)$") or "audio"
    local stem, ext = name:match("^(.*)(%.[^.]*)$")
    stem, ext = stem or name, ext or ""
    local n, inside = 1, "audio/" .. name
    while ctx.taken[inside] do
      n = n + 1
      inside = string.format("audio/%s-%d%s", stem, n, ext)
    end
    entry = { info = info, inside = data and ctx.embed and inside or nil, path = path }
    if entry.inside then
      ctx.taken[inside] = true
      ctx.files[#ctx.files + 1] = { name = inside, data = data }
    end
    ctx.media[path] = entry
  end
  local a = node("Audio", "id", ctx.id(), "duration", entry.info.seconds, "channels", entry.info.channels,
    "sampleRate", entry.info.rate)
  add(a, entry.inside and node("File", "path", entry.inside) or node("File", "path", entry.path, "external", true))
  return a, entry.info
end

local function audio_clip(clip, ctx, label)
  local stretch = clip.stretch or 1
  local offset = clip.offset or 0
  local e = node("Clip", "time", clip.start, "duration", clip.length, "contentTimeUnit", "seconds",
    "playStart", offset * stretch, "fadeTimeUnit", "beats", "fadeInTime", clip.fade_in or 0,
    "fadeOutTime", clip.fade_out or 0, "enable", clip.muted and "false" or nil, "name", clip.name ~= "" and clip.name or nil)
  if clip["loop"] and (clip.loop_length or 0) > 0 then
    -- The repeat begins `lead` seconds before the clip (see paw's audio_regions).
    local period = api.tempo_seconds(clip.start + clip.loop_length) - api.tempo_seconds(clip.start)
    local begins = (offset * stretch) + (clip.loop_start or 0) * period / clip.loop_length
    e.attr.loopStart, e.attr.loopEnd = begins, begins + period
    table.insert(e.order, 5, "loopStart")
    table.insert(e.order, 6, "loopEnd")
  end
  local a, info = audio_file(clip.file, ctx, label)
  if math.abs(stretch - 1) > 1e-9 then
    -- Played slower or faster: the file's seconds against the clip's.
    local w = add(e, node("Warps", "id", ctx.id(), "timeUnit", "seconds", "contentTimeUnit", "seconds"))
    add(w, a)
    add(w, node("Warp", "time", 0, "contentTime", 0))
    add(w, node("Warp", "time", math.max(info.seconds, 1) * stretch, "contentTime", math.max(info.seconds, 1)))
  else
    add(e, a)
  end
  if math.abs(clip.pitch or 0) > 1e-9 then ctx.report:add("Pitch of audio clips", label) end
  if clip.warp and #clip.warp > 0 then ctx.report:add("Warp markers of audio clips", label) end
  return e
end

-- Automation ---------------------------------------------------------------------------

local function lane_points(lane, target, unit, convert, ctx, label)
  local p = node("Points", "id", ctx.id(), "unit", unit)
  add(p, node("Target", "parameter", target))
  local shapes = {}
  for _, s in ipairs(api.lane_shapes(lane.id)) do
    shapes[s.beat] = s.shape
    if s.shape == "smooth" then ctx.report:count("Smooth automation curves (written as straight lines)", label) end
  end
  for _, pt in ipairs(api.lane_points(lane.id)) do
    add(p, node("RealPoint", "time", pt[1], "value", convert(pt[2]), "interpolation", shapes[pt[1]] == "hold" and "hold" or "linear"))
  end
  if not lane.enabled then ctx.report:add("Automation lanes that are off (written as on)", label) end
  return p
end

-- Project ------------------------------------------------------------------------------

--- The tracks in order, nested as folders where a track feeds the track
--- right above it (or a folder it is in), as rpp does for REAPER.
local function nest(list)
  local roots, stack = {}, {}
  for _, t in ipairs(list) do
    while #stack > 0 and stack[#stack].t.id ~= t.output do stack[#stack] = nil end
    local item = { t = t, children = {} }
    if #stack > 0 then
      table.insert(stack[#stack].children, item)
    else
      roots[#roots + 1] = item
    end
    stack[#stack + 1] = item
  end
  return roots
end

--- Build the archive's files for the current project. Returns the list of
--- { name, data }, the report and the project element.
function M.build(opts)
  opts = opts or {}
  local n = 0
  local ctx = {
    id = function()
      n = n + 1
      return "id" .. n
    end,
    report = reports.new("Not written to " .. (opts.name or "the DAWproject file") .. ":"),
    types = setmetatable({}, { __index = function(t, kind) local v = api.device_find({ kind = kind }) or false rawset(t, kind, v) return v end }), params = {}, track_params = {}, channel = {}, track_el = {}, files = {}, media = {}, taken = {},
    plugins = 0, embed = opts.embed ~= false,
  }
  local p = api.project_get()
  local list = {}
  for i, id in ipairs(api.track_list()) do list[i] = api.track_get(id) end
  local master = api.track_get(0)
  for _, t in ipairs(list) do ctx.channel[t.id] = ctx.id() end
  ctx.channel[0] = ctx.id()

  local root = node("Project", "version", "1.0")
  add(root, node("Application", "name", "paw", "version", opts.version or "1.0"))
  local transport = add(root, node("Transport"))
  local tempo = add(transport, real("Tempo", ctx, p.tempo, "bpm", 20, 999, "Tempo"))
  local sig = add(transport, node("TimeSignature", "id", ctx.id(), "numerator", p.sig_num, "denominator", p.sig_den))

  -- Structure: the tracks, then the master.
  local structure = add(root, node("Structure"))
  local feeds = {}
  for _, t in ipairs(list) do
    if t.output then feeds[t.output] = true end
  end
  local function track_el(item, parent)
    local t = item.t
    local ct = content_type(t)
    if #item.children > 0 then ct = ct .. " tracks" end
    local e = add(parent, node("Track", "id", ctx.id(), "name", t.name, "color", t.color, "contentType", ct, "loaded", true))
    ctx.track_el[t.id] = e.attr.id
    add(e, channel(t, ctx, feeds[t.id] and "submix" or "regular"))
    for _, c in ipairs(item.children) do track_el(c, e) end
    if t.armed or t.input or t.monitor then
      ctx.report:add("Record arm, inputs and monitoring (DAWproject has none)", t.name)
    end
    local cues = t.id ~= 0 and #api.cue_list(t.id) or 0
    if cues > 0 then ctx.report:count("Clips off the timeline (the clip launcher's slots)", t.name, cues) end
  end
  for _, item in ipairs(nest(list)) do track_el(item, structure) end
  local mt = add(structure, node("Track", "id", ctx.id(), "name", "Master", "contentType", "audio notes", "loaded", true))
  ctx.track_el[0] = mt.attr.id
  add(mt, channel(master, ctx, "master"))

  -- Arrangement: a lane timeline for each track with its clips and its automation.
  local arr = add(root, node("Arrangement", "id", ctx.id()))
  local lanes = add(arr, node("Lanes", "id", ctx.id(), "timeUnit", "beats"))
  local function automation(t, tl, label)
    for _, lane in ipairs(api.lane_list(t.id)) do
      local where = label .. " " .. (lane.param or lane.target)
      if lane.target == "volume" then
        add(tl, lane_points(lane, ctx.track_params[t.id].volume, "linear", amp, ctx, where))
      elseif lane.target == "pan" then
        add(tl, lane_points(lane, ctx.track_params[t.id].pan, "normalized", function(v) return (v + 1) / 2 end, ctx, where))
      else
        local param = ctx.params[lane.device] and ctx.params[lane.device][lane.param]
        if param then
          add(tl, lane_points(lane, param.id, "linear", function(v) return v end, ctx, where))
        else
          ctx.report:add("Automation of parameters paw did not write", where)
        end
      end
    end
  end
  for _, t in ipairs(list) do
    local tl = add(lanes, node("Lanes", "id", ctx.id(), "track", ctx.track_el[t.id]))
    local clips = add(tl, node("Clips", "id", ctx.id()))
    for _, clip in ipairs(api.clip_list(t.id)) do
      local label = t.name .. ": " .. (clip.name ~= "" and clip.name or "clip")
      add(clips, clip.kind == "audio" and audio_clip(clip, ctx, label) or midi_clip(clip, ctx, label))
    end
    automation(t, tl, t.name)
  end
  local mtl = add(lanes, node("Lanes", "id", ctx.id(), "track", ctx.track_el[0]))
  automation(master, mtl, "Master")

  -- Markers. DAWproject has no regions: a region is a marker at its start
  -- with its length in the comment, which paw reads back.
  local marks = type((p.meta or {}).markers) == "table" and p.meta.markers or {}
  local ok, sections = pcall(require, "sections")
  local parts = ok and sections.list() or {}
  if #marks + #parts > 0 then
    local me = add(arr, node("Markers", "id", ctx.id()))
    for _, m in ipairs(marks) do
      add(me, node("Marker", "time", m.beat or 0, "name", m.name or "", "color", m.color,
        "comment", m.length and string.format("paw region: %s beats", xml.number(m.length)) or nil))
      if m.length then ctx.report:count("Regions written as markers at their start (paw reads them back as regions)", "regions") end
    end
    for _, s in ipairs(parts) do
      add(me, node("Marker", "time", s.start, "name", s.name,
        "comment", string.format("paw region: %s beats", xml.number(s.finish - s.start))))
    end
    if #parts > 0 then ctx.report:count("Sections written as markers (they come back as regions)", "sections", #parts) end
  end

  -- The tempo map, as automation of the tempo and the time signature.
  local map = api.tempo_points()
  if #map.tempos > 1 or map.tempos[1].ramp then
    local ta = add(arr, node("TempoAutomation", "id", ctx.id(), "timeUnit", "beats", "unit", "bpm"))
    add(ta, node("Target", "parameter", tempo.attr.id))
    for _, tp in ipairs(map.tempos) do
      add(ta, node("RealPoint", "time", tp.beat, "value", tp.bpm, "interpolation", tp.ramp and "linear" or "hold"))
    end
  end
  if #map.signatures > 1 then
    local sa = add(arr, node("TimeSignatureAutomation", "id", ctx.id(), "timeUnit", "beats"))
    add(sa, node("Target", "parameter", sig.attr.id))
    for _, s in ipairs(map.signatures) do
      add(sa, node("TimeSignaturePoint", "time", s.beat, "numerator", s.num, "denominator", s.den))
    end
  end
  add(root, node("Scenes"))

  local tr = api.transport_get()
  if tr.loop_enabled then ctx.report:add("The loop of the transport (DAWproject has none)", "loop") end

  local meta = node("MetaData")
  local title = add(meta, node("Title"))
  title.text = p.name or "untitled"
  local files = {
    { name = "project.xml", data = xml.write(root) },
    { name = "metadata.xml", data = xml.write(meta) },
  }
  for _, f in ipairs(ctx.files) do files[#files + 1] = f end
  return files, ctx.report, root
end

--- Write the current project to a file. `opts.embed = false` refers to
--- audio files where they are instead of copying them into the archive.
function M.file(path, opts)
  opts = opts or {}
  opts.name = path:match("([^/]+)$") or path
  local files, report = M.build(opts)
  local f = assert(io.open(path, "wb"))
  f:write(paw.zip.write(files))
  f:close()
  return { report = report, files = files }
end

M.el = el
return M
