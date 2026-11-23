-- Addresses: a URI for everything a language server, a lint or a person
-- could talk about, built from ids so that it survives edits.
--
--   paw://project
--   paw://track/12                        paw://track/0 is the master
--   paw://track/12/device/3               paw://track/12/device/3/param/cutoff
--   paw://track/12/send/5                 the send to track 5
--   paw://clip/7                          paw://clip/7/note/41 (the note's own id)
--   paw://clip/7/control/cc/74            paw://lane/9
--   paw://tempo                           paw://marker/5
--   paw://render/<the file's path, %-encoded>
--
-- A note's id is the model's: every note has one from the moment it is
-- made, kept through every move and change, and only a note that is copied
-- next to its original gets a new one (crates/paw-core/src/model.rs,
-- `Note::id`).
--
-- A **selector** narrows an address to a part of it: `{ time = { from, to } }`
-- (beats), `{ notes = { ids } }`, `{ pitch = { lo, hi } }`, `{ value = x }`.
-- A **location** is `{ uri = ..., selector = ... }`.
--
-- A **workspace edit** is a list of changes, each `{ uri, set = { ... } }`,
-- `{ uri, insert = { ... } }` or `{ uri, delete = true }`: `paw.address.edit`
-- checks every one before it does anything and makes them one undo step.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local render = require("paw.render")
local kernel = require("paw.events.kernel")
local util = require("paw.util")
local registry = require("paw.registry")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type objects = require("paw.objects")
local type MarkersModule = require("paw.markers")

--- A value that this module passes on and never reads.
local record Value
end

--- What an address names: a record of `paw.api` (`types.Track`,
--- `types.Clip`, ...), a note with its `place`, a parameter, a render, or
--- an item of an extension's scheme. The kind of the address tells which.
local interface Thing
end

--- An address in parts (`paw.address.parse`). `kind` is "project",
--- "tempo", "track", "device", "param", "send", "clip", "note", "control",
--- "lane", "marker", "render" or the name of a scheme.
local record Parts
  kind: string
  uri: string
  segments: {string}
  fragment: string
  track: integer
  device: integer
  param: string
  send: integer
  clip: integer
  note: integer
  control: string
  number: integer
  lane: integer
  marker: integer
  path: string
end

--- What a change of a workspace edit inserts: notes into a clip (`notes`,
--- or one note given as the insert itself), a device (`device` its kind,
--- `params`, `index`) or a clip (`clip`) into a track.
local record Insert
  pitch: objects.Pitch
  start: number
  length: number
  velocity: integer
  notes: {objects.NoteInput}
  device: string
  params: {string: number}
  index: integer
  clip: types.ClipOptions
end

--- One change of a workspace edit: what it sets, inserts or deletes.
local record Change
  uri: string
  set: {string: Value}
  insert: Insert
  delete: boolean
end

--- A kind of address of an extension (`paw.address.scheme`).
local record Scheme
  resolve: function(uri: string, parts: Parts): Thing
  of: function(object: Thing): string
  children: function(uri: string, parts: Parts): {string}
  parent: function(uri: string, parts: Parts): string
  go: function(location: contracts.Location, parts: Parts): boolean
  where: function(location: contracts.Location, parts: Parts): string
  edit: function(change: Change, parts: Parts)
end

--- A parameter as `paw.address.resolve` gives it.
local record Param is Thing
  key: string
  value: number
  info: types.ParamInfo
  device: integer
end

--- The options of a render (paw/render.tl), which this module keeps.
local record RenderValue
end
local type RenderOptions = {string: RenderValue}

--- A file that was rendered (`paw.address.renders`): what the render
--- returned (`types.RenderResult`), with the options it was made with and
--- when (`at`).
local record Rendered is Thing
  path: string
  opts: RenderOptions
  at: number
end

--- The payload of `address.changed`: the addresses that changed, the
--- project's count of edits, and for a render what it wrote.
local record Changed
  uris: {string}
  revision: integer
  rendered: Rendered
end

--- The payload of the kernel's events of a track, clip, device or lane.
local record WithId
  id: integer
  track: integer -- the track of a clip, lane or device, when the event names it
end

-- What this module reads of `paw`, which paw/init.lua makes.
local record Paw
  Track: objects.Track
  Clip: objects.Clip
  Device: objects.Device
  markers: MarkersModule
  clip: function(id: integer): objects.Clip
  render: function(path: string, opts: RenderOptions)
  defer: function(fn: function(), ms?: number): integer
  cancel: function(handle: integer)
end
local paw = (_G as {string: Paw}).paw

local record M
  type Thing = Thing
  type Parts = Parts
  type Insert = Insert
  type Change = Change
  type Scheme = Scheme
  type Param = Param
  type Rendered = Rendered
  type RenderOptions = RenderOptions
  type Changed = Changed
  --- The kinds of address of extensions, by name, with the extension that
  --- added each one. `paw.address.scheme` puts one.
  schemes: registry.Registry<Scheme>
  --- The event `address.changed`: things with addresses changed.
  changed: events.Event<Changed>
  --- What was rendered, by path.
  renders: {string: Rendered}
end

M.schemes = registry.new("addresses", "address schemes")
M.changed = events.event("address.changed")

local function decode(s: string): string
  return (s:gsub("%%(%x%x)", function(h: string): string return string.char(tonumber(h, 16) as integer) end))
end
local function encode(s: string): string
  return (s:gsub("[^%w%-%._~/]", function(c: string): string return string.format("%%%02X", c:byte()) end))
end

--- An address in parts: `{ kind = "note", track?, device?, param?, send?,
--- clip?, note?, lane?, marker?, control?, number?, path?, segments }`, or
--- nil when it is not one. The fragment (`#mix`) is kept as `fragment`.
function M.parse(uri: string): Parts
  if not (uri is string) then
    return nil
  end
  local body, fragment = uri:match("^paw://([^#]*)#?(.*)$")
  if not body then
    return nil
  end
  local seg: {string} = {}
  for part in body:gmatch("[^/]+") do
    seg[#seg + 1] = part
  end
  local out: Parts = {segments = seg, fragment = fragment ~= "" and fragment or nil, uri = uri}
  local head = seg[1]
  local function int(s: string): integer
    return tonumber(s) as integer
  end
  if head == "project" or head == "tempo" then
    out.kind = head
  elseif head == "track" then
    out.track = int(seg[2])
    out.kind = "track"
    if seg[3] == "device" then
      out.device, out.kind = int(seg[4]), "device"
      if seg[5] == "param" then
        out.param, out.kind = seg[6] and decode(seg[6]), "param"
      end
    elseif seg[3] == "send" then
      out.send, out.kind = int(seg[4]), "send"
    end
  elseif head == "clip" then
    out.clip, out.kind = int(seg[2]), "clip"
    if seg[3] == "note" then
      out.note, out.kind = int(seg[4]), "note"
    elseif seg[3] == "control" then
      out.control, out.number, out.kind = seg[4], int(seg[5]), "control"
    end
  elseif head == "lane" then
    out.lane, out.kind = int(seg[2]), "lane"
  elseif head == "marker" then
    out.marker, out.kind = int(seg[2]), "marker"
  elseif head == "render" then
    out.path, out.kind = decode(body:sub(#"render/" + 1)), "render"
  elseif head and M.schemes:get(head) then
    out.kind = head
  else
    return nil
  end
  return out
end

-- Constructors ---------------------------------------------------------------

--- The addresses of the project, the tempo map, a track, a clip and a note.
--- Also the addresses of a lane, a marker, a rendered file and a send, as
--- `parse` reads them.
function M.project(): string
  return "paw://project"
end
--- The tempo map's address.
function M.tempo(): string
  return "paw://tempo"
end
--- A track's address.
function M.track(id: integer): string
  return "paw://track/" .. id
end
--- A clip's address.
function M.clip(id: integer): string
  return "paw://clip/" .. id
end
--- A note's address: its clip, and the note's id there.
function M.note(clip: integer, id: integer): string
  return "paw://clip/" .. clip .. "/note/" .. id
end
--- An automation lane's address.
function M.lane(id: integer): string
  return "paw://lane/" .. id
end
--- A marker's address.
function M.marker(id: integer): string
  return "paw://marker/" .. id
end
--- A rendered file's address.
function M.render(path: string): string
  return "paw://render/" .. encode(path)
end
--- The address of a track's send to another.
function M.send(track: integer, target: integer): string
  return "paw://track/" .. track .. "/send/" .. target
end

--- A device's address, under its track's.
function M.device(id: integer): string
  local d = api.device_get(id)
  return "paw://track/" .. d.track .. "/device/" .. id
end

--- A device parameter's address, by its key.
function M.param(device: integer, key: string): string
  return M.device(device) .. "/param/" .. encode(key)
end

--- A location: an address and, optionally, a part of it.
function M.location(uri: string, selector?: contracts.Selector): contracts.Location
  return {uri = uri, selector = selector}
end

--- What `paw.address.of` reads of a table of `paw.api`.
local record Fields
  id: integer
  param_info: {types.ParamInfo}
  kind: string
  track: integer
  length: number
  sends: {types.Send}
  devices: {integer}
end

--- The address of an object of the Lua interface (`paw.track(3)`,
--- `paw.clip(7)`, a device), or of a table from `paw.api` (with its fields).
function M.of(object: string | Thing): string, string
  if object is string then
    if M.parse(object) then
      return object
    end
    return nil
  end
  if type(object) ~= "table" then
    return nil
  end
  local mt = getmetatable(object as {string: Value}) as Value
  local t = object as Fields
  if mt == paw.Track as Value then
    return M.track(t.id)
  end
  if mt == paw.Clip as Value then
    return M.clip(t.id)
  end
  if mt == paw.Device as Value then
    return M.device(t.id)
  end
  if t.param_info and t.id then
    return M.device(t.id)
  end
  if t.kind and t.track and t.id and t.length then
    return M.clip(t.id)
  end
  if t.sends and t.devices and t.id then
    return M.track(t.id)
  end
  for name, scheme in pairs(M.schemes:entries()) do
    local uri = scheme.of and scheme.of(object)
    if uri then
      return uri, name
    end
  end
  return nil
end

-- Resolving ------------------------------------------------------------------

-- A clip's notes, all of them.
local clip_notes = api.clip_notes as function(id: integer): {types.Note}

local function try<A, R>(fn: function(A): R, value: A): R
  local ok, v = pcall(fn, value)
  if ok then
    return v
  end
end

--- The note of a clip with an id, and its place in the clip (from 1).
function M.find_note(clip: integer, id: integer): types.Note, integer
  local notes = try(clip_notes, clip)
  for place, n in ipairs(notes or {}) do
    if n.id == id then
      return n, place
    end
  end
end

--- A note as `paw.address.resolve` gives it: with its place and its clip.
local record PlacedNote is Thing
  start: number
  length: number
  pitch: integer
  velocity: integer
  id: integer
  meta: types.Meta
  attr: types.NoteAttr
  place: integer
  clip: integer
end

--- What an address names, as `paw.api` has it (a note also says its
--- `place`; a parameter is `{ key, value, info }`), or nil when it is gone.
function M.resolve(uri: string): Thing
  local p = M.parse(uri)
  if not p then
    return nil
  end
  if p.kind == "project" then
    return api.project_get() as Thing
  end
  if p.kind == "tempo" then
    return api.tempo_points() as Thing
  end
  if p.kind == "track" then
    return p.track and try(api.track_get, p.track) as Thing
  end
  if p.kind == "device" or p.kind == "param" then
    local d = p.device and try(api.device_get, p.device)
    if not d or d.track ~= p.track then
      return nil
    end
    if p.kind == "device" then
      return d as Thing
    end
    for _, info in ipairs(d.param_info or {}) do
      if info.key == p.param then
        return {key = p.param, value = d.params[p.param], info = info, device = d.id} as Param
      end
    end
    return nil
  end
  if p.kind == "send" then
    local t = p.track and try(api.track_get, p.track)
    for _, s in ipairs(t and t.sends or {}) do
      if s.target == p.send then
        return s as Thing
      end
    end
    return nil
  end
  if p.kind == "clip" then
    return p.clip and try(api.clip_get, p.clip) as Thing
  end
  if p.kind == "note" then
    local n, place = M.find_note(p.clip, p.note)
    if n then
      return util.merge(n as {string: Value}, {place = place as Value, clip = p.clip as Value}) as PlacedNote
    end
    return nil
  end
  if p.kind == "control" then
    local out: {types.Control} = {}
    for _, c in ipairs(try(api.clip_controls, p.clip) or {}) do
      if c.type as string == p.control and (not p.number or c.number == p.number) then
        out[#out + 1] = c
      end
    end
    return try(api.clip_get, p.clip) and out as Thing or nil
  end
  if p.kind == "lane" then
    return p.lane and try(api.lane_get, p.lane) as Thing
  end
  if p.kind == "marker" then
    for _, m in ipairs(paw.markers and paw.markers.list() or {}) do
      if m.id == p.marker then
        return m as Thing
      end
    end
    return nil
  end
  if p.kind == "render" then
    return M.renders[p.path] or (io.open(p.path) and {path = p.path} as Rendered) or nil
  end
  local scheme = M.schemes:get(p.kind)
  return scheme and scheme.resolve(uri, p)
end

--- The address that holds this one (a note's clip, a device's track), or nil.
function M.parent(uri: string): string
  local p = M.parse(uri)
  if not p then
    return nil
  end
  if p.kind == "note" or p.kind == "control" then
    return M.clip(p.clip)
  end
  if p.kind == "param" then
    return "paw://track/" .. p.track .. "/device/" .. p.device
  end
  if p.kind == "device" or p.kind == "send" then
    return M.track(p.track)
  end
  if p.kind == "clip" then
    local c = try(api.clip_get, p.clip)
    return c and M.track(c.track) or nil
  end
  if p.kind == "lane" then
    local l = try(api.lane_get, p.lane)
    return l and l.track and M.track(l.track) or M.project()
  end
  if p.kind == "project" then
    return nil
  end
  local scheme = M.schemes:get(p.kind)
  if scheme and scheme.parent then
    return scheme.parent(uri, p)
  end
  return M.project()
end

--- What an address holds, one level down.
function M.children(uri: string): {string}
  local p = M.parse(uri)
  local out: {string} = {}
  if not p then
    return out
  end
  if p.kind == "project" then
    for _, id in ipairs(api.track_list()) do
      out[#out + 1] = M.track(id)
    end
    out[#out + 1] = M.track(0)
    out[#out + 1] = M.tempo()
  elseif p.kind == "track" then
    local t = try(api.track_get, p.track)
    for _, d in ipairs(t and t.devices or {}) do
      out[#out + 1] = "paw://track/" .. p.track .. "/device/" .. d
    end
    for _, s in ipairs(t and t.sends or {}) do
      out[#out + 1] = M.send(p.track, s.target)
    end
    for _, c in ipairs(t and try(api.clip_list, p.track) or {}) do
      out[#out + 1] = M.clip(c.id)
    end
  elseif p.kind == "device" then
    local d = try(api.device_get, p.device)
    for _, info in ipairs(d and d.param_info or {}) do
      out[#out + 1] = uri .. "/param/" .. encode(info.key)
    end
  elseif p.kind == "clip" then
    for _, n in ipairs(try(clip_notes, p.clip) or {}) do
      if n.id then
        out[#out + 1] = M.note(p.clip, n.id)
      end
    end
  elseif M.schemes:get(p.kind) and M.schemes:get(p.kind).children then
    out = M.schemes:get(p.kind).children(uri, p)
  end
  return out
end

--- True if `uri` is `ancestor` or is inside it (a note inside its clip, a
--- parameter inside its device and track). All addresses are inside the project.
function M.within(uri: string, ancestor: string): boolean
  if ancestor == M.project() then
    return true
  end
  local at = uri
  for _ = 1, 8 do
    if not at then
      return false
    end
    if at == ancestor or at:sub(1, #ancestor + 1) == ancestor .. "/" then
      return true
    end
    at = M.parent(at)
  end
  return false
end

--- The track an address belongs to, if any.
function M.track_of(uri: string): integer
  local at = uri
  for _ = 1, 8 do
    local p = at and M.parse(at)
    if not p then
      return nil
    end
    if p.track then
      return p.track
    end
    at = M.parent(at)
  end
end

--- Add a kind of address, `paw://<name>/...`, for the data of an extension
--- (the phrases of the vocal editor, the measures of a score).
--- `spec.resolve(uri, parts)` gives the item or nil. The optional fields are
--- `of(object)`, `children(uri, parts)` and `parent(uri, parts)`. For the
--- quickfix list, `go(location, parts)` goes to an item and
--- `where(location, parts)` names it in a few words. `edit(change, parts)`
--- applies the change of a workspace edit to it. It must make its edits
--- through `paw.api`, so the edits join the undo step.
function M.scheme(name: string, spec: Scheme)
  assert(spec is Scheme and spec.resolve, "usage: paw.address.scheme(name, { resolve = fn, ... })")
  M.schemes:put(name, spec)
end

-- Workspace edits ------------------------------------------------------------

local TRACK_FIELDS: {string: boolean} = {
  volume = true, pan = true, mute = true, solo = true, name = true, output = true, armed = true
}
local CLIP_FIELDS: {string: boolean} = {start = true, length = true, name = true, muted = true}
local NOTE_FIELDS: {string: boolean} = {
  pitch = true, start = true, length = true, velocity = true, meta = true, attr = true
}

-- Check one change; return what to do, or nil and why not.
local function plan(change: Change): Parts, string
  local p = M.parse(change.uri)
  if not p then
    return nil, "not an address: " .. tostring(change.uri)
  end
  local what = change.delete and "delete" or change.insert and "insert" or change.set and "set"
  if not what then
    return nil, change.uri .. ": a change sets, inserts or deletes"
  end
  if p.kind ~= "render" and not M.resolve(change.uri) then
    return nil, change.uri .. " is gone"
  end
  local function only(fields: {string: boolean}, set: {string: Value}): boolean, string
    for k in pairs(set) do
      if not fields[k] then
        return nil, string.format("%s: cannot set `%s`", change.uri, k)
      end
    end
    return true
  end
  if p.kind == "note" then
    if what == "insert" then
      return nil, "notes are inserted into their clip"
    end
    if what == "set" then
      local ok, err = only(NOTE_FIELDS, change.set)
      if not ok then
        return nil, err
      end
    end
  elseif p.kind == "clip" then
    if what == "set" then
      local ok, err = only(CLIP_FIELDS, change.set)
      if not ok then
        return nil, err
      end
    elseif what == "insert" and not (change.insert.notes or change.insert.pitch) then
      return nil, change.uri .. ": a clip takes notes"
    end
  elseif p.kind == "track" then
    if what == "set" then
      local ok, err = only(TRACK_FIELDS, change.set)
      if not ok then
        return nil, err
      end
    elseif what == "insert" and not (change.insert.device or change.insert.clip) then
      return nil, change.uri .. ": a track takes a device or a clip"
    elseif what == "delete" and p.track == 0 then
      return nil, "the master track stays"
    end
  elseif p.kind == "device" then
    if what == "insert" then
      return nil, "nothing is inserted into a device"
    end
  elseif p.kind == "param" then
    if what ~= "set" or change.set.value == nil then
      return nil, change.uri .. ": a parameter takes `set = { value = ... }`"
    end
  elseif p.kind == "send" then
    if what == "insert" then
      return nil, "nothing is inserted into a send"
    end
  elseif p.kind == "render" then
    if what ~= "set" then
      return nil, "a render is rendered again with `set`"
    end
  elseif M.schemes:get(p.kind) then
    if not M.schemes:get(p.kind).edit then
      return nil, p.kind .. " addresses cannot be edited"
    end
  else
    return nil, p.kind .. " addresses cannot be edited"
  end
  return p
end

-- A setter of the kernel, by one key and its value.
local clip_set = api.clip_set as function(id: integer, key: string, value: Value)
local track_set = api.track_set as function(id: integer, key: string, value: Value)
local device_set = api.device_set as function(id: integer, key: string, value: Value)

--- A render to make again after an edit, with what was set.
local record Rerender
  path: string
  opts: RenderOptions
end

--- Do a workspace edit. paw checks each change first, and does nothing
--- unless it can do all changes. Then it makes all of them as one undo step
--- with the label `label`. Returns true, or nil and the reason.
---   paw.address.edit({ { uri = "paw://track/3", set = { volume = -6 } },
---                      { uri = "paw://clip/7/note/41", set = { pitch = 62 } } }, "Lower the bass")
function M.edit(changes: {Change}, label?: string): boolean, string
  local plans: {Parts} = {}
  for i, change in ipairs(changes or {}) do
    local p, why = plan(change)
    if not p then
      return nil, why
    end
    plans[i] = p
  end
  if label then
    api.undo_label(label)
  end
  -- Notes go clip by clip in one edit each, by their places before it.
  local by_clip: {integer: objects.NotesEditInput} = {}
  local renders: {Rerender} = {}
  local function clip_edit(id: integer): objects.NotesEditInput
    by_clip[id] = by_clip[id] or {set = {}, remove = {}, add = {}}
    return by_clip[id]
  end
  for i, change in ipairs(changes) do
    local p = plans[i]
    if p.kind == "note" then
      local _, place = M.find_note(p.clip, p.note)
      local e = clip_edit(p.clip)
      if change.delete then
        e.remove[#e.remove + 1] = place
      else
        e.set[#e.set + 1] = util.merge(change.set, {index = place as Value}) as objects.NoteChangeInput
      end
    elseif p.kind == "clip" then
      if change.delete then
        api.clip_remove(p.clip)
      elseif change.insert then
        local e = clip_edit(p.clip)
        for _, n in ipairs(change.insert.notes or {change.insert as objects.NoteInput}) do
          e.add[#e.add + 1] = n
        end
      else
        for k, v in pairs(change.set) do
          clip_set(p.clip, k, v)
        end
      end
    elseif p.kind == "track" then
      if change.delete then
        api.track_remove(p.track)
      elseif change.insert and change.insert.device then
        api.device_add(p.track, change.insert.device, {params = change.insert.params, index = change.insert.index})
      elseif change.insert then
        api.clip_add(p.track, change.insert.clip)
      else
        for k, v in pairs(change.set) do
          track_set(p.track, k, v)
        end
      end
    elseif p.kind == "device" then
      if change.delete then
        api.device_remove(p.device)
      else
        for k, v in pairs(change.set) do
          if k == "params" then
            for key, value in pairs(v as {string: number | string}) do
              api.device_set_param(p.device, key, value)
            end
          else
            device_set(p.device, k, v)
          end
        end
      end
    elseif p.kind == "param" then
      api.device_set_param(p.device, p.param, change.set.value as number | string)
    elseif p.kind == "send" then
      local sends: {types.Send} = {}
      for _, s in ipairs(api.track_get(p.track).sends) do
        if s.target ~= p.send then
          sends[#sends + 1] = s
        elseif not change.delete then
          sends[#sends + 1] = util.merge(s as {string: Value}, change.set) as types.Send
        end
      end
      api.track_set(p.track, {sends = sends})
    elseif p.kind == "render" then
      renders[#renders + 1] = {path = p.path, opts = change.set as RenderOptions}
    else
      M.schemes:get(p.kind).edit(change, p)
    end
  end
  for id, e in pairs(by_clip) do
    paw.clip(id):edit_notes(e)
  end
  -- A render is not an edit of the project: it is made again afterwards,
  -- with what was set over the options it was made with.
  for _, r in ipairs(renders) do
    local before = M.renders[r.path] and M.renders[r.path].opts or {}
    paw.render(r.path, util.merge(util.merge(before, r.opts), {background = true as RenderValue}))
  end
  return true
end

-- Renders ----------------------------------------------------------------------

--- What was rendered, by path: what the render returned, with the options
--- it was made with (`opts`). The `render` subject and addresses read it.
M.renders = {}

-- The project's count of edits, read alone (`project_get(key)`, which Teal does not see).
local function edits(): integer
  return (api.project_get as function(string): integer)("edits")
end

local pending_opts: {string: RenderOptions} = {}
-- A measure of the sound also emits `render.before`, with no path: it writes no file.
events.on(
  render.before,
  function(e: render.Before)
    if e.path then
      pending_opts[e.path] = e.opts as RenderOptions
    end
  end
)
local function rendered(info: types.RenderResult)
  if not (info is types.RenderResult) or not info.path then
    return
  end
  local entry = util.merge(
    info as {string: Value}, {opts = (pending_opts[info.path] or {}) as Value, at = api.now() as Value}
  ) as Rendered
  pending_opts[info.path] = nil
  M.renders[info.path] = entry
  events.emit(M.changed, {uris = {M.render(info.path)}, revision = edits(), rendered = entry})
end
events.on(kernel.render_done, rendered)
events.on(render.finished, rendered)
-- Another project, other renders.
events.on(kernel.project_loaded, function() M.renders = {} end)

-- Change events --------------------------------------------------------------

-- The kernel says what changed by id (`track.changed { id }`, `clip.added
-- { id, track }`, `device.removed { id, track }`, `lane.*`, `project.*`); these
-- become one `address.changed { uris, revision }` for the edit, after the
-- kernel's own `changed`, so that whoever watches addresses never diffs
-- snapshots.
local pending: {string: boolean} = {}
local scheduled: integer = nil
local function tell()
  -- Told now (at the kernel's `changed`): the timer is not needed any more.
  if scheduled then
    paw.cancel(scheduled)
  end
  scheduled = nil
  if not next(pending) then
    return
  end
  local uris: {string} = {}
  for uri in pairs(pending) do
    uris[#uris + 1] = uri
  end
  table.sort(uris)
  pending = {}
  events.emit(M.changed, {uris = uris, revision = edits()})
end
local function changed(uris: {string})
  for _, uri in ipairs(uris) do
    pending[uri] = true
  end
  if not scheduled then
    scheduled = paw.defer(tell, 0)
  end
end
local function family(name: string): events.Event<WithId>
  return events.event(name)
end
events.on(
  family("track.*"),
  function(e: WithId)
    if e.id then
      changed({M.track(e.id)})
    end
  end
)
events.on(
  family("clip.*"),
  function(e: WithId)
    if e.id then
      changed({M.clip(e.id)})
    end
  end
)
events.on(
  family("device.*"),
  function(e: WithId)
    if not e.id then
      return
    end
    -- The event names the track: a removed device has none to ask, and a
    -- failed read costs much more than a good one.
    local track = e.track
    if not track then
      local ok, d = pcall(api.device_get, e.id)
      track = ok and d.track or nil
    end
    changed({track and ("paw://track/" .. track .. "/device/" .. e.id) or M.project()})
  end
)
events.on(
  family("lane.*"),
  function(e: WithId)
    if e.id then
      changed({M.lane(e.id)})
    end
  end
)
events.on(events.pattern("project.*"), function() changed({M.project()}) end)
-- What changes without an event of its own (the tempo map, the project's
-- meta) is the project's.
events.on(kernel.changed, function() changed({M.project()}); tell() end)

--- True if an address matches a pattern: `paw://track/*` (one level),
--- `paw://track/**` (any depth), or an exact address.
function M.matches(pattern: string, uri: string): boolean
  if pattern == uri then
    return true
  end
  local lua = "^"
    .. pattern:gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*%*", "\1"):gsub("%*", "[^/]*"):gsub("\1", ".*")
    .. "$"
  return uri:match(lua) ~= nil
end

return M
