-- Subjects: what a server is shown. Each is a projection of part of the
-- project into plain data, named by the address it projects (the clip, the
-- track, the project, the rendered file), sent as a document whose version
-- moves when the projection does.
--
--   paw.lsp.subject("lyrics", {
--     language = "paw-lyrics",
--     targets = function(where) return { "paw://track/3" } end,  -- what there is to show
--     build = function(address, where) return { words = ... } end,
--     depends = { "paw://clip/**" },                             -- what makes it worth sending again
--   })
--
-- `where` is the attachment's `where` (`focus`, `tracks`, `drums`, ...).
-- The document's URI is the address, or the address and `#<subject>` when
-- the subject is not the address's own (`paw://project#mix`).
local api = paw.api
local A = paw.address
local document = require("paw.lsp.document")

local M = { list = {} }

--- Add or replace a subject.
function M.define(name, spec)
  assert(type(spec) == "table" and spec.build and spec.targets, "usage: paw.lsp.subject(name, { targets = fn, build = fn, ... })")
  spec.name = name
  spec.language = spec.language or ("paw-" .. name)
  spec.depends = spec.depends or { "paw://**" }
  M.list[name] = spec
end

--- The URI of the document a subject makes of an address.
function M.uri(name, address)
  local spec = M.list[name]
  if spec and spec.own then return address end
  return address .. "#" .. name
end

--- A document URI in its parts: the subject and the address.
function M.split(uri)
  local address, name = tostring(uri):match("^(.-)#(.+)$")
  if address then return name, address end
  for n, spec in pairs(M.list) do
    if spec.own and spec.own(uri) then return n, uri end
  end
end

-- Shell-style patterns with `*` and `?`, ignoring case.
local function glob(pattern, text)
  local lua = "^" .. pattern:lower():gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0"):gsub("%*", ".*"):gsub("%?", ".") .. "$"
  return tostring(text):lower():match(lua) ~= nil
end

--- Whether a track passes an attachment's `where`: its name matches one of
--- `tracks` (when given), and it plays drums or not as `drums` says.
function M.track_passes(track, where)
  where = where or {}
  if where.tracks then
    local any = false
    for _, p in ipairs(where.tracks) do any = any or glob(p, track.name) end
    if not any then return false end
  end
  if where.drums ~= nil and where.drums ~= paw.harmony.is_drums(track) then return false end
  return true
end

-- The clips open in a piano roll, the active one and every other it edits
-- with it (paw.roll_clips): each seat (each person's terminal or window)
-- has its own, and the servers are shared, so they get all of them.
local function open_clips()
  local open, out = {}, {}
  local function add(id)
    if id and not open[id] and pcall(api.clip_get, id) then
      open[id] = true
      out[#out + 1] = id
    end
  end
  local function look()
    local view = paw.ui.views.pianoroll
    add(view and view.clip_id)
    for _, id in ipairs(paw.roll_clips and paw.roll_clips.ids() or {}) do add(id) end
  end
  local seats = paw.seats and paw.seats.list() or {}
  if #seats <= 1 then look() else for _, seat in ipairs(seats) do paw.seats.within(seat, look) end end
  return out
end

-- The track each seat's cursor is on.
local function focused_tracks()
  local seen, out = {}, {}
  local function look()
    local id = paw.cursor.track_id()
    if id and not seen[id] then seen[id], out[#out + 1] = true, id end
  end
  local seats = paw.seats and paw.seats.list() or {}
  if #seats <= 1 then look() else for _, seat in ipairs(seats) do paw.seats.within(seat, look) end end
  return out
end

local function all_tracks()
  local out = {}
  for _, id in ipairs(api.track_list()) do out[#out + 1] = id end
  out[#out + 1] = 0
  return out
end

local function device_of(id)
  local d = api.device_get(id)
  return { id = d.id, address = A.device(d.id), name = d.name, kind = d.kind, format = d.format, bypass = d.bypass,
    params = d.params, units = (function()
      local out = {}
      for _, info in ipairs(d.param_info or {}) do out[info.key] = { min = info.min, max = info.max, unit = info.unit, name = info.name } end
      return out
    end)() }
end

local function track_of(id)
  local t = api.track_get(id)
  local devices = {}
  for _, d in ipairs(t.devices or {}) do devices[#devices + 1] = device_of(d) end
  local sends = {}
  for _, s in ipairs(t.sends or {}) do sends[#sends + 1] = { target = s.target, level = s.level, pre = s.pre or false } end
  return {
    id = id, address = A.track(id), name = t.name, master = id == 0, volume = t.volume, pan = t.pan,
    mute = t.mute, solo = t.solo, output = t.output, sends = sends, devices = devices,
    drums = paw.harmony.is_drums(t) or nil,
  }
end

-- Built in ---------------------------------------------------------------------

-- A MIDI clip, with what sounds with it: MIDI LSP's take document
-- (paw/lsp/document.lua). By focus, the clips open in a piano roll.
M.define("clip", {
  language = "paw-clip",
  own = function(uri) return A.parse(uri) and A.parse(uri).kind == "clip" end,
  targets = function(where)
    local ids = {}
    if where.focus == false then
      for _, t in ipairs(all_tracks()) do
        for _, c in ipairs(api.clip_list(t)) do if c.kind == "midi" then ids[#ids + 1] = c.id end end
      end
    else
      ids = open_clips()
    end
    local out = {}
    for _, id in ipairs(ids) do
      local ok, c = pcall(api.clip_get, id)
      if ok and c.kind == "midi" and M.track_passes(api.track_get(c.track), where) then out[#out + 1] = A.clip(id) end
    end
    return out
  end,
  key = function(address) return document.key_of(A.parse(address).clip) end,
  build = function(address, _, key) return document.build(A.parse(address).clip, key) end,
  depends = { "paw://clip/*", "paw://track/*", "paw://project" },
})

-- One track: its chain of devices with their parameters, its routing, and
-- what its clips are. By focus, the track a cursor is on.
M.define("track", {
  language = "paw-track",
  own = function(uri) return A.parse(uri) and A.parse(uri).kind == "track" end,
  targets = function(where)
    local out = {}
    for _, id in ipairs(where.focus and focused_tracks() or all_tracks()) do
      local ok, t = pcall(api.track_get, id)
      if ok and M.track_passes(t, where) then out[#out + 1] = A.track(id) end
    end
    return out
  end,
  build = function(address)
    local id = A.parse(address).track
    local out = track_of(id)
    out.clips = {}
    for _, c in ipairs(api.clip_list(id)) do
      out.clips[#out.clips + 1] = { id = c.id, address = A.clip(c.id), name = c.name, kind = c.kind, start = c.start,
        length = c.length, muted = c.muted, notes = c.note_count, file = c.file }
    end
    return out
  end,
  depends = { "paw://track/**", "paw://clip/*" },
})

paw.option.define("loudness_target", -14)  -- LUFS a mix is meant to sit at (for a mix server)
paw.option.define("true_peak_target", -1)  -- dBTP it should stay under

-- The mix: every track with its fader, pan, mute and solo, sends, where it
-- goes, its devices and their parameters; the master; the tempo; the
-- loudness it is meant for; the options of the last render.
M.define("mix", {
  language = "paw-mix",
  targets = function() return { A.project() } end,
  build = function()
    local tracks = {}
    for _, id in ipairs(api.track_list()) do tracks[#tracks + 1] = track_of(id) end
    local last
    for _, r in pairs(A.renders) do if not last or r.at > last.at then last = r end end
    local e = api.engine_get()
    return {
      tracks = tracks, master = track_of(0),
      tempo = paw.tempo.points(), signatures = paw.tempo.signatures(),
      sample_rate = e.sample_rate,
      targets = { loudness_lufs = paw.opt.loudness_target, true_peak_dbtp = paw.opt.true_peak_target },
      render = last and { path = last.path, opts = last.opts } or nil,
    }
  end,
  depends = { "paw://track/**", "paw://project" },
})

-- The whole project, summarised: tracks with what is on them, markers, the
-- tempo, how long it is.
M.define("project", {
  language = "paw-project",
  own = function(uri) return uri == A.project() end,
  targets = function() return { A.project() } end,
  build = function()
    local p = api.project_get()
    local tracks, finish = {}, 0
    for _, id in ipairs(api.track_list()) do
      local t = api.track_get(id)
      local clips = api.clip_list(id)
      for _, c in ipairs(clips) do finish = math.max(finish, c.start + c.length) end
      tracks[#tracks + 1] = { id = id, address = A.track(id), name = t.name, clips = #clips, devices = #(t.devices or {}) }
    end
    return { name = p.name, path = p.path, tracks = tracks, length = finish, tempo = paw.tempo.points(),
      markers = paw.markers and paw.markers.list() or {} }
  end,
  depends = { "paw://track/*", "paw://clip/*", "paw://project" },
})

-- A rendered file: where, its format, rate and depth, how long, and what
-- the render measured (peak, loudness) with the options it was made with.
M.define("render", {
  language = "paw-render",
  own = function(uri) return A.parse(uri) and A.parse(uri).kind == "render" end,
  targets = function()
    local out = {}
    for path in pairs(A.renders) do out[#out + 1] = A.render(path) end
    table.sort(out)
    return out
  end,
  key = function(address)
    local r = A.renders[A.parse(address).path]
    return r and tostring(r.at) or nil
  end,
  build = function(address)
    local r = A.renders[A.parse(address).path]
    if not r then return nil end
    return {
      path = r.path, format = r.format, sample_rate = r.sample_rate, bits = r.bits, channels = r.channels,
      seconds = r.seconds, frames = r.frames, peak = r.peak, loudness = r.loudness, gain = r.gain, opts = r.opts,
      master = track_of(0),
    }
  end,
  depends = { "paw://render/**" },
})

return M
