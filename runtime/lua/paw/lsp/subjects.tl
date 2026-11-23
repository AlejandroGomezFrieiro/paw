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
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local A = require("paw.address")
local options = require("paw.options")
local document = require("paw.lsp.document")
local type rpc = require("paw.lsp.rpc")
local type types = require("paw.types")
local type partial = require("paw.partial")
local type UiModule = require("paw.ui")
local type HarmonyModule = require("paw.harmony")
local type TempoModule = require("paw.tempo")
local type CursorModule = require("paw.cursor")
local type SeatsModule = require("paw.seats")
local type MarkersModule = require("paw.markers")
local type RollClipsModule = require("paw.roll_clips")
local type Roll = require("paw.views.pianoroll")

--- The piano roll's view (paw/views/pianoroll.tl), and the clips that it
--- edits with the active one (paw/roll_clips.tl).
local type PianoRoll = Roll.PianoRoll

local record Paw is partial.Paw
  ui: UiModule
  harmony: HarmonyModule
  tempo: TempoModule
  cursor: CursorModule
  seats: SeatsModule
  markers: MarkersModule
  roll_clips: RollClipsModule
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

--- What a server is attached to besides the subjects: `focus` (what the
--- cursor is on or the piano roll edits, or all), `tracks` (patterns of
--- their names) and `drums` (tracks that play drums, or the others).
local record Where
  focus: boolean
  tracks: {string}
  drums: boolean
end

--- A subject (`paw.lsp.subject`): what there is to show (`targets`), the
--- document of an address (`build`), and what makes it worth sending again
--- (`depends`, address patterns). `key(address)` is a fast value that
--- changes with the document (else the document's JSON is hashed); `own(uri)`
--- says the URI is an address of this subject's own (a clip for `clip`).
--- `focus = false` attaches to all, not to what the cursor is on.
local record Subject
  name: string
  language: string
  own: function(uri: string): boolean
  targets: function(where: Where): {string}
  build: function(address: string, where?: Where, key?: string): rpc.Payload
  key: function(address: string): string
  depends: {string}
  focus: boolean
end

--- A parameter's range, unit and name, by its key.
local record Unit
  min: number
  max: number
  unit: string
  name: string
end

--- A device as a subject shows it.
local record DeviceDoc
  id: integer
  address: string
  name: string
  kind: string
  format: string
  bypass: boolean
  params: {string: number}
  units: {string: Unit}
end

--- A send as a subject shows it.
local record SendDoc
  target: integer
  level: number
  pre: boolean
end

--- A clip of a track's document.
local record ClipDoc
  id: integer
  address: string
  name: string
  kind: types.ClipKind
  start: number
  length: number
  muted: boolean
  notes: integer
  file: string
end

--- A track as a subject shows it: its chain of devices with their
--- parameters, its routing, and (`track`) what its clips are.
local record TrackDoc
  id: integer
  address: string
  name: string
  master: boolean
  volume: number
  pan: number
  mute: boolean
  solo: boolean
  output: integer
  sends: {SendDoc}
  devices: {DeviceDoc}
  drums: boolean
  clips: {ClipDoc}
end

--- The loudness a mix is meant for.
local record Targets
  loudness_lufs: number
  true_peak_dbtp: number
end

--- The last render: where, and the options it was made with.
local record RenderRef
  path: string
  opts: A.RenderOptions
end

--- The `mix` subject's document.
local record MixDoc
  tracks: {TrackDoc}
  master: TrackDoc
  tempo: {types.TempoPoint}
  signatures: {types.SigPoint}
  sample_rate: integer
  targets: Targets
  render: RenderRef
end

--- A track in the `project` subject's document.
local record ProjectTrack
  id: integer
  address: string
  name: string
  clips: integer
  devices: integer
end

--- The `project` subject's document.
local record ProjectDoc
  name: string
  path: string
  tracks: {ProjectTrack}
  length: number
  tempo: {types.TempoPoint}
  markers: {MarkersModule.Marker}
end

--- The `render` subject's document: what the render measured, with its options.
local record RenderDoc
  path: string
  format: string
  sample_rate: integer
  bits: integer
  channels: integer
  seconds: number
  frames: integer
  peak: number
  loudness: number
  gain: number
  opts: A.RenderOptions
  master: TrackDoc
end

local record M
  type Where = Where
  type Subject = Subject
  type Unit = Unit
  type DeviceDoc = DeviceDoc
  type SendDoc = SendDoc
  type ClipDoc = ClipDoc
  type TrackDoc = TrackDoc
  type Targets = Targets
  type RenderRef = RenderRef
  type MixDoc = MixDoc
  type ProjectTrack = ProjectTrack
  type ProjectDoc = ProjectDoc
  type RenderDoc = RenderDoc
  --- The subjects, by name.
  list: {string: Subject}
end
M.list = {}

--- Add or replace a subject.
function M.define(name: string, spec: Subject)
  assert(
    type(spec) == "table" and spec.build and spec.targets,
    "usage: paw.lsp.subject(name, { targets = fn, build = fn, ... })"
  )
  spec.name = name
  spec.language = spec.language or ("paw-" .. name)
  spec.depends = spec.depends or {"paw://**"}
  M.list[name] = spec
end

--- The URI of the document a subject makes of an address.
function M.uri(name: string, address: string): string
  local spec = M.list[name]
  if spec and spec.own then
    return address
  end
  return address .. "#" .. name
end

--- A document URI in its parts: the subject and the address.
function M.split(uri: string): string, string
  local address, name = tostring(uri):match("^(.-)#(.+)$")
  if address then
    return name, address
  end
  for n, spec in pairs(M.list) do
    if spec.own and spec.own(uri) then
      return n, uri
    end
  end
end

-- Shell-style patterns with `*` and `?`, ignoring case.
local function glob(pattern: string, text: string): boolean
  local lua = "^" .. pattern:lower():gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0"):gsub("%*", ".*"):gsub("%?", ".") .. "$"
  return tostring(text):lower():match(lua) ~= nil
end

--- Whether a track passes an attachment's `where`: its name matches one of
--- `tracks` (when given), and it plays drums or not as `drums` says.
function M.track_passes(track: types.Track, where?: Where): boolean
  where = where or {}
  if where.tracks then
    local any = false
    for _, p in ipairs(where.tracks) do
      any = any or glob(p, track.name)
    end
    if not any then
      return false
    end
  end
  if where.drums ~= nil and where.drums ~= paw.harmony.is_drums(track) then
    return false
  end
  return true
end

-- The seats: each person's terminal or window.
local function each_seat(look: function())
  local seats = paw.seats and paw.seats.list() or {}
  if #seats <= 1 then
    look()
  else
    for _, seat in ipairs(seats) do
      paw.seats.within(seat, look)
    end
  end
end

-- The clips open in a piano roll, the active one and every other it edits
-- with it (paw.roll_clips): each seat (each person's terminal or window)
-- has its own, and the servers are shared, so they get all of them.
local function open_clips(): {integer}
  local open: {integer: boolean} = {}
  local out: {integer} = {}
  local function add(id: integer)
    if id and not open[id] and pcall(api.clip_get, id) then
      open[id] = true
      out[#out + 1] = id
    end
  end
  each_seat(
    function()
      local view = paw.ui.views:get("pianoroll") as PianoRoll
      add(view and view.clip_id)
      for _, id in ipairs(paw.roll_clips and paw.roll_clips.ids() or {}) do
        add(id)
      end
    end
  )
  return out
end

-- The track each seat's cursor is on.
local function focused_tracks(): {integer}
  local seen: {integer: boolean} = {}
  local out: {integer} = {}
  each_seat(
    function()
      local id = paw.cursor.track_id()
      if id and not seen[id] then
        seen[id], out[#out + 1] = true, id
      end
    end
  )
  return out
end

local function all_tracks(): {integer}
  local out: {integer} = {}
  for _, id in ipairs(api.track_list()) do
    out[#out + 1] = id
  end
  out[#out + 1] = 0
  return out
end

local function device_of(id: integer): DeviceDoc
  local d = api.device_get(id)
  local units: {string: Unit} = {}
  for _, info in ipairs(d.param_info or {}) do
    units[info.key] = {min = info.min, max = info.max, unit = info.unit, name = info.name}
  end
  return {
    id = d.id,
    address = A.device(d.id),
    name = d.name,
    kind = d.kind,
    format = d.format,
    bypass = d.bypass,
    params = d.params,
    units = units,
  }
end

local function track_of(id: integer): TrackDoc
  local t = api.track_get(id)
  local devices: {DeviceDoc} = {}
  for _, d in ipairs(t.devices or {}) do
    devices[#devices + 1] = device_of(d)
  end
  local sends: {SendDoc} = {}
  for _, s in ipairs(t.sends or {}) do
    sends[#sends + 1] = {target = s.target, level = s.level, pre = s.pre or false}
  end
  return {
    id = id,
    address = A.track(id),
    name = t.name,
    master = id == 0,
    volume = t.volume,
    pan = t.pan,
    mute = t.mute,
    solo = t.solo,
    output = t.output,
    sends = sends,
    devices = devices,
    drums = paw.harmony.is_drums(t) or nil,
  }
end

-- The kind of address a URI is, or nil.
local function kind_of(uri: string): string
  local p = A.parse(uri)
  return p and p.kind
end

-- Built in ---------------------------------------------------------------------

-- A MIDI clip, with what sounds with it: MIDI LSP's take document
-- (paw/lsp/document.tl). By focus, the clips open in a piano roll.
M.define(
  "clip",
  {
    language = "paw-clip",
    own = function(uri: string): boolean return kind_of(uri) == "clip" end,
    targets = function(where: Where): {string}
      local ids: {integer} = {}
      if where.focus == false then
        for _, t in ipairs(all_tracks()) do
          for _, c in ipairs(api.clip_list(t)) do
            if c.kind == "midi" then
              ids[#ids + 1] = c.id
            end
          end
        end
      else
        ids = open_clips()
      end
      local out: {string} = {}
      for _, id in ipairs(ids) do
        local ok, c = pcall(api.clip_get, id) as (boolean, types.Clip)
        if ok and c.kind == "midi" and M.track_passes(api.track_get(c.track), where) then
          out[#out + 1] = A.clip(id)
        end
      end
      return out
    end,
    key = function(address: string): string return document.key_of(A.parse(address).clip) end,
    build = function(address: string, _?: Where, key?: string): rpc.Payload
      return document.build(A.parse(address).clip, key) as rpc.Payload
    end,
    depends = {"paw://clip/*", "paw://track/*", "paw://project"},
  }
)

-- One track: its chain of devices with their parameters, its routing, and
-- what its clips are. By focus, the track a cursor is on.
M.define(
  "track",
  {
    language = "paw-track",
    own = function(uri: string): boolean return kind_of(uri) == "track" end,
    targets = function(where: Where): {string}
      local out: {string} = {}
      for _, id in ipairs(where.focus and focused_tracks() or all_tracks()) do
        local ok, t = pcall(api.track_get, id) as (boolean, types.Track)
        if ok and M.track_passes(t, where) then
          out[#out + 1] = A.track(id)
        end
      end
      return out
    end,
    build = function(address: string): rpc.Payload
      local id = A.parse(address).track
      local out = track_of(id)
      out.clips = {}
      for _, c in ipairs(api.clip_list(id)) do
        out.clips[#out.clips + 1] = {
          id = c.id,
          address = A.clip(c.id),
          name = c.name,
          kind = c.kind,
          start = c.start,
          length = c.length,
          muted = c.muted,
          notes = c.note_count,
          file = c.file,
        }
      end
      return out as rpc.Payload
    end,
    depends = {"paw://track/**", "paw://clip/*"},
  }
)

options.define("loudness_target", -14) -- LUFS a mix is meant to sit at (for a mix server)
options.define("true_peak_target", -1) -- dBTP it should stay under

-- The mix: every track with its fader, pan, mute and solo, sends, where it
-- goes, its devices and their parameters; the master; the tempo; the
-- loudness it is meant for; the options of the last render.
M.define(
  "mix",
  {
    language = "paw-mix",
    targets = function(): {string} return {A.project()} end,
    build = function(): rpc.Payload
      local tracks: {TrackDoc} = {}
      for _, id in ipairs(api.track_list()) do
        tracks[#tracks + 1] = track_of(id)
      end
      local last: A.Rendered
      for _, r in pairs(A.renders) do
        if not last or r.at > last.at then
          last = r
        end
      end
      local e = api.engine_get()
      local doc: MixDoc = {
        tracks = tracks,
        master = track_of(0),
        tempo = paw.tempo.points(),
        signatures = paw.tempo.signatures(),
        sample_rate = e.sample_rate,
        targets = {loudness_lufs = opt.loudness_target, true_peak_dbtp = opt.true_peak_target},
        render = last and {path = last.path, opts = last.opts} or nil,
      }
      return doc as rpc.Payload
    end,
    depends = {"paw://track/**", "paw://project"},
  }
)

-- The whole project, summarised: tracks with what is on them, markers, the
-- tempo, how long it is.
M.define(
  "project",
  {
    language = "paw-project",
    own = function(uri: string): boolean return uri == A.project() end,
    targets = function(): {string} return {A.project()} end,
    build = function(): rpc.Payload
      local p = api.project_get()
      local tracks: {ProjectTrack} = {}
      local finish = 0.0
      for _, id in ipairs(api.track_list()) do
        local t = api.track_get(id)
        local clips = api.clip_list(id)
        for _, c in ipairs(clips) do
          finish = math.max(finish, c.start + c.length)
        end
        tracks[#tracks + 1] = {
          id = id, address = A.track(id), name = t.name, clips = #clips, devices = #(t.devices or {})
        }
      end
      local doc: ProjectDoc = {
        name = p.name,
        path = p.path,
        tracks = tracks,
        length = finish,
        tempo = paw.tempo.points(),
        markers = paw.markers and paw.markers.list() or {},
      }
      return doc as rpc.Payload
    end,
    depends = {"paw://track/*", "paw://clip/*", "paw://project"},
  }
)

-- A rendered file: where, its format, rate and depth, how long, and what
-- the render measured (peak, loudness) with the options it was made with.
M.define(
  "render",
  {
    language = "paw-render",
    own = function(uri: string): boolean return kind_of(uri) == "render" end,
    targets = function(): {string}
      local out: {string} = {}
      for path in pairs(A.renders) do
        out[#out + 1] = A.render(path)
      end
      table.sort(out)
      return out
    end,
    key = function(address: string): string
      local r = A.renders[A.parse(address).path]
      return r and tostring(r.at) or nil
    end,
    build = function(address: string): rpc.Payload
      local rendered = A.renders[A.parse(address).path]
      if not rendered then
        return nil
      end
      -- What the render returned (`types.RenderResult`), as paw.address keeps it.
      local r = rendered as types.RenderResult
      local doc: RenderDoc = {
        path = r.path,
        format = r.format,
        sample_rate = r.sample_rate,
        bits = r.bits,
        channels = r.channels,
        seconds = r.seconds,
        frames = r.frames,
        peak = r.peak,
        loudness = r.loudness,
        gain = r.gain,
        opts = rendered.opts,
        master = track_of(0),
      }
      return doc as rpc.Payload
    end,
    depends = {"paw://render/**"},
  }
)

return M
