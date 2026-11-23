-- Whether a bake that the project keeps (a frozen track, later a frozen
-- block of a subproject) is up to date or stale: what its sound was made
-- from, as a key, and the words that `K` says of it.
--
-- A key has one stamp for each part of what plays in the bake: the clips,
-- the devices, the automation, the mix of the tracks that feed it, and the
-- tempo. The key of the bake is made when the bake is made, and is kept
-- with it. To check the bake, paw makes the key again and compares the
-- parts: the parts that differ are the reason that it is stale. The key is
-- made from the content, not from ids or counters: an undo gives the old
-- key back, and the bake is up to date again.
--
-- The stamps come from what the kernel gives: the stamps of the notes and
-- controllers (`clip.stamp`, `clip.control_stamp`), and the fields of the
-- clips, devices and lanes. paw never hashes the notes here. Not in a key:
-- a plugin's saved state (its parameters are), and the list of edits of an
-- audio clip (their count is). This is the provenance that the media design
-- gives each kept bake (`input_key`, backlog/docs/designs/media.md 2.8),
-- made in Lua until the kernel has it.
--
-- With a `derived.Ctx`, `M.make` records what it reads: a node of
-- `paw.derived` that makes the key is then stale only after an edit of what
-- the bake plays, and an edit of any other track costs no work.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local derived = require("paw.derived")
local type types = require("paw.types")

--- What a bake plays: these tracks, from `from` to `to` in beats (the whole
--- song when nil). `own` is the track whose devices make the bake, and whose
--- fader, pan and mute come after it (a frozen track): only the mix of the
--- other tracks is in the key.
local record Scope
  tracks: {integer}
  own: integer
  from: number
  to: number
end

--- What a bake was made from: a stamp for each part (16 hex digits; the
--- tempo's is the kernel's `tempo_stamp`).
local record Key
  clips: string
  devices: string
  automation: string
  mix: string
  tempo: string
end

local record M
  type Scope = Scope
  type Key = Key
  --- The parts of a key, in the order that `K` names them.
  parts: {string}
end

M.parts = {"clips", "devices", "automation", "mix", "tempo"}

-- Two hashes of 32 bits of a text, as 16 hex digits: a collision of two
-- different contents is about 2^-64. The products stay below 2^53, so the
-- doubles of LuaJIT hold them exactly.
local function stamp(text: string): string
  local a, b = 5381, 0
  for i = 1, #text do
    local byte = text:byte(i)
    a = (a * 33 + byte) % 4294967296
    b = (b * 65599 + byte) % 4294967296
  end
  return string.format("%08x%08x", a, b)
end

local project_int = api.project_get as function(string): integer

local function num(x: number): string
  return x and string.format("%.17g", x) or "-"
end

-- Record a source that the key reads, when a node of the graph makes it.
local function source(ctx: derived.Ctx, name: string)
  if ctx then
    ctx:source(name)
  end
end

-- The clips of one track, in the scope's time, as text.
local function clips_text(ctx: derived.Ctx, track: integer, scope: Scope, out: {string})
  source(ctx, "track:" .. track .. ":clips")
  local ok, list = pcall(api.clip_list, track) as (boolean, {types.Clip})
  if not ok then
    return
  end
  for i = 1, #list do
    local c = list[i]
    local inside = (not scope.to or c.start < scope.to) and (not scope.from or c.start + c.length > scope.from)
    if inside then
      out[#out + 1] = table.concat(
        {
          tostring(c.kind),
          num(c.start),
          num(c.length),
          tostring(c.muted),
          tostring(c.loop),
          num(c.loop_start),
          num(c.loop_length),
          -- MIDI: the notes and controllers by their stamps, and the overrides.
          num(c.stamp),
          num(c.control_stamp),
          tostring(c.transpose),
          tostring(c.velocity),
          -- Audio: the file and how it plays.
          tostring(c.file),
          num(c.offset),
          num(c.gain),
          num(c.fade_in),
          num(c.fade_out),
          tostring(c.timebase),
          num(c.stretch),
          num(c.pitch),
          tostring(c.stretch_mode),
          num(c.source_tempo),
          tostring(c.formants),
          tostring(c.edits),
          -- A block of a subproject: the subproject, and what it plays of it.
          tostring(c.nest),
        },
        ","
      )
      for k = 1, c.warp and #c.warp or 0 do
        local w = c.warp[k]
        out[#out + 1] = num(w.source) .. ">" .. num(w.target)
      end
    end
  end
end

-- A table of numbers by name, in the order of the names.
local function sorted_text(map: {string: number}): string
  local names: {string} = {}
  for name in pairs(map or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  for i = 1, #names do
    names[i] = names[i] .. "=" .. num(map[names[i]])
  end
  return table.concat(names, ",")
end

-- The devices of one track, in order, as text.
local function devices_text(ctx: derived.Ctx, t: types.Track, out: {string})
  source(ctx, "track:" .. t.id .. ":devices")
  for i = 1, #t.devices do
    local ok, d = pcall(api.device_get, t.devices[i]) as (boolean, types.Device)
    if ok then
      local outputs: {string} = {}
      for pair, to in pairs(d.outputs or {}) do
        outputs[#outputs + 1] = pair .. ">" .. to
      end
      table.sort(outputs)
      out[#out + 1] = table.concat(
        {
          d.kind,
          tostring(d.bypass),
          tostring(d.offline),
          tostring(d.sidechain),
          tostring(d.sidechain_pre),
          table.concat(outputs, ","),
          sorted_text(d.params),
        },
        ";"
      )
    end
  end
end

-- The automation of one track, in the scope's time, as text.
local function automation_text(ctx: derived.Ctx, track: integer, scope: Scope, out: {string})
  source(ctx, "track:" .. track .. ":lanes")
  local ok, lanes = pcall(api.lane_list, track) as (boolean, {types.Lane})
  if not ok then
    return
  end
  for i = 1, #lanes do
    local lane = lanes[i]
    out[#out + 1] = table.concat(
      {
        tostring(lane.target),
        tostring(lane.device),
        tostring(lane.param),
        tostring(lane.enabled),
        table.concat(lane.states or {}, ","),
      },
      ";"
    )
    local points = api.lane_points(lane.id)
    for k = 1, #points do
      local p = points[k]
      if (not scope.from or p[1] >= scope.from) and (not scope.to or p[1] <= scope.to) then
        out[#out + 1] = num(p[1]) .. ":" .. num(p[2])
      end
    end
    local shapes = api.lane_shapes(lane.id)
    for k = 1, #shapes do
      local s = shapes[k]
      out[#out + 1] = num(s.beat) .. ":" .. tostring(s.shape) .. ":" .. num(s.tension)
    end
  end
end

-- The mix of a track that plays into the bake: its fader, pan, mute and
-- where it plays.
local function mix_text(ctx: derived.Ctx, t: types.Track, out: {string})
  for _, field in ipairs({"volume", "pan", "mute", "output"}) do
    source(ctx, "track:" .. t.id .. ":" .. field)
  end
  out[#out + 1] = table.concat({tostring(t.id), num(t.volume), num(t.pan), tostring(t.mute), tostring(t.output)}, ";")
end

--- The key of what `scope` plays now. With `ctx`, from inside a node of
--- `paw.derived`: the node then reads again only after an edit of it.
function M.make(scope: Scope, ctx?: derived.Ctx): Key
  local clips, devices, automation, mix: {string}, {string}, {string}, {string} = {}, {}, {}, {}
  for i = 1, #scope.tracks do
    local id = scope.tracks[i]
    local ok, t = pcall(api.track_get, id) as (boolean, types.Track)
    if ok then
      clips[#clips + 1] = "#"
      clips_text(ctx, id, scope, clips)
      devices[#devices + 1] = "#"
      devices_text(ctx, t, devices)
      automation[#automation + 1] = "#"
      automation_text(ctx, id, scope, automation)
      if id ~= scope.own then
        mix_text(ctx, t, mix)
      end
    end
  end
  local tempo = ctx and ctx:tempo() or project_int("tempo_stamp")
  return {
    clips = stamp(table.concat(clips, "\n")),
    devices = stamp(table.concat(devices, "\n")),
    automation = stamp(table.concat(automation, "\n")),
    mix = stamp(table.concat(mix, "\n")),
    tempo = num(tempo),
  }
end

--- The parts of `now` that differ from `saved`, in the order of `M.parts`.
--- Empty when the bake is up to date.
function M.changed(saved: Key, now: Key): {string}
  local out: {string} = {}
  local a, b = saved as {string: string}, now as {string: string}
  for i = 1, #M.parts do
    local part = M.parts[i]
    if a[part] ~= b[part] then
      out[#out + 1] = part
    end
  end
  return out
end

--- What `K` says of a bake of `name`: "up to date", or "stale: Drums
--- changed since: devices" with the parts that changed.
function M.describe(name: string, saved: Key, now: Key): string
  local parts = M.changed(saved, now)
  if #parts == 0 then
    return "up to date"
  end
  return "stale: " .. name .. " changed since: " .. table.concat(parts, ", ")
end

return M
