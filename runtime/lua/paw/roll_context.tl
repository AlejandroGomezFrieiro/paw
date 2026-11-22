-- The notes that the piano roll shows behind its own (`paw.roll_clips`):
-- the notes of the other tracks that sound in the span of the edited
-- clips. They are a node of `paw.derived` (`roll.context`, the design
-- `derived.md`, D2):
--
--   key     what the roll asks for: the active clip and its place, the
--           edited clips, the span, the shown tracks, the options, the scope
--   inputs  the context clips: for each, its track's colour, its place and
--           its notes' stamp, read through the graph from the tracks and
--           their clips
--   value   the notes of those clips, in the beats of the roll
--
-- So an edit of an edited clip (its notes are not context) reads the clip
-- lists again, finds the same context clips, and makes no notes again.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local derived = require("paw.derived")
local options = require("paw.options")
local type types = require("paw.types")
local type partial = require("paw.partial")
local type DrawModule = require("paw.draw")
local type GroupsModule = require("paw.groups")

-- What this module reads of `paw`, which paw/init.lua makes. paw/harmony.tl
-- and paw/scope.tl name many types: this module declares only what it calls.
local record Harmony
  is_drums: function(t: types.Track): boolean
end
local record Scope
  tracks: function(): {integer}
  breadcrumb: function(): string
end
local record Paw is partial.Paw
  draw: DrawModule
  groups: GroupsModule
  harmony: Harmony
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

local EPS = 1e-9

--- What the roll asks for. `active` is the active clip, `editable` the ids
--- of the edited clips (their notes are not context), `from` and `to` the
--- span in song beats, `shown` the toggles over `paw.opt.roll_context`.
local record Request
  id: string
  active: types.Clip
  editable: {integer: boolean}
  from: number
  to: number
  shown: {integer: boolean}
end

--- A track near the roll, as `paw.roll_clips.tracks` gives it.
local record Track
  id: integer
  name: string
  color: string
  drums: boolean
  on: boolean
end

--- A note behind the roll, in the beats of the roll.
local record Note
  pitch: integer
  start: number
  length: number
  velocity: integer
  clip: integer
  track: integer
  color: string
end

--- A context clip, as the node compares them: what its notes are made of.
local record Part
  id: integer
  track: integer
  color: string
  start: number
  length: number
  stamp: integer
end

local record M
  type Request = Request
  type Track = Track
  type Note = Note
  node: derived.Node<Request, {Note}, {Part}>
end

-- The fields of a track that its colour and its choice read: the colour,
-- the group (in `meta`), and whether it is drums (`meta`, the name, the
-- devices). Its place in the list is the source `tracks`.
local FIELDS = {"name", "color", "meta", "devices"}

--- A track, read through the graph when `ctx` is there.
local function track_of(ctx: derived.Ctx, id: integer): types.Track
  if ctx then
    return ctx:track(id, FIELDS)
  end
  local ok, t = pcall(api.track_get, id)
  return ok and t or nil
end

--- The clips of a track, read through the graph when `ctx` is there.
local function clips_of(ctx: derived.Ctx, id: integer): {types.Clip}
  if ctx then
    return ctx:clips(id)
  end
  local ok, list = pcall(api.clip_list, id)
  return ok and list or {}
end

local function scope(): Scope
  return rawget(paw as {string: Scope}, "scope")
end

--- Whether a track's notes show, before the toggles: by `paw.opt.roll_context`.
local function chosen(id: integer, drums: boolean, group: integer, listed: {integer: boolean}): boolean
  local option = opt.roll_context
  if option is {string | number} then
    return listed[id] or false
  elseif option == "group" then
    return not drums and group ~= nil and (paw.groups.of(id) == group or id == group)
  elseif option == "none" then
    return false
  end
  return not drums
end

--- The tracks whose notes can show behind the roll, but not the track of
--- the active clip. With `midi`, only those with a MIDI clip (the list
--- that `paw.roll_clips.tracks` gives); without, each track whose notes
--- show could have context clips.
local function tracks(ctx: derived.Ctx, req: Request, midi: boolean): {Track}
  local a = req.active
  local group = paw.groups.of(a.track) or (paw.groups.is_group(a.track) and a.track) or nil
  local listed: {integer: boolean} = {}
  local option = opt.roll_context
  if option is {string | number} then
    for _, id in ipairs(option) do
      listed[math.tointeger(id)] = true
    end
  end
  local out: {Track} = {}
  -- In a narrowed window (`paw.scope`), the scope's tracks alone.
  local s = scope()
  if ctx then
    ctx:tracks()
  end
  local ids = s and s.tracks() or api.track_list()
  for _, id in ipairs(ids) do
    local t = id ~= a.track and track_of(ctx, id)
    if t and not t.master then
      local has_midi = not midi
      if midi then
        for _, c in ipairs(clips_of(ctx, id)) do
          has_midi = has_midi or c.kind == "midi"
        end
      end
      if has_midi then
        local drums = paw.harmony.is_drums(t)
        local on = chosen(id, drums, group, listed)
        if req.shown[id] ~= nil then
          on = req.shown[id]
        end
        out[#out + 1] = {id = id, name = t.name, color = paw.draw.track_colour(t), drums = drums, on = on}
      end
    end
  end
  return out
end

--- The tracks near the roll: `{ id, name, color, drums, on }` each.
function M.tracks(req: Request): {Track}
  return tracks(nil, req, true)
end

--- The context clips: the MIDI clips of the active clip's track and of the
--- shown tracks that sound in the span, but not the edited clips.
local function parts(ctx: derived.Ctx, req: Request): {Part}
  local a = req.active
  local own = track_of(ctx, a.track)
  local looked: {Track} = {{id = a.track, on = true, color = own and paw.draw.track_colour(own) or nil}}
  for _, t in ipairs(tracks(ctx, req, false)) do
    looked[#looked + 1] = t
  end
  local out: {Part} = {}
  for _, t in ipairs(looked) do
    if t.on then
      for _, c in ipairs(clips_of(ctx, t.id)) do
        if
          c.kind == "midi"
          and not req.editable[c.id]
          and c.start < req.to - EPS
          and c.start + c.length > req.from + EPS
        then
          out[#out + 1] = {id = c.id, track = t.id, color = t.color, start = c.start, length = c.length, stamp = c.stamp}
        end
      end
    end
  end
  return out
end

local function same_parts(a: {Part}, b: {Part}): boolean
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    local x, y = a[i], b[i]
    if
      x.id ~= y.id
      or x.track ~= y.track
      or x.color ~= y.color
      or x.start ~= y.start
      or x.length ~= y.length
      or x.stamp ~= y.stamp
    then
      return false
    end
  end
  return true
end

--- The notes of the context clips that sound in the span, at most
--- `paw.opt.roll_context_max` of them.
local function notes(req: Request, list: {Part}): {Note}
  local out: {Note} = {}
  local max = opt.roll_context_max
  local from, to = req.from, req.to
  for _, c in ipairs(list) do
    local shift = c.start - req.active.start
    -- Only what the clip lets sound, and only within the span.
    local found = api.clip_notes(c.id, {from = math.max(0, from - c.start), to = math.min(c.length, to - c.start)})
    for _, n in ipairs(found) do
      if #out >= max then
        break
      end
      if n.start >= -EPS and n.start < c.length - EPS then
        out[#out + 1] = {
          pitch = n.pitch,
          start = n.start + shift,
          length = math.min(n.length, c.length - n.start),
          velocity = n.velocity,
          clip = c.id,
          track = c.track,
          color = c.color,
        }
      end
    end
  end
  return out
end

local spec: derived.Spec<Request, {Note}, {Part}> = {
  name = "roll.context",
  kind = "memo",
  id = function(req: Request): string return req.id end,
  inputs = function(ctx: derived.Ctx, req: Request): {Part} return parts(ctx, req) end,
  same_inputs = same_parts,
  make = function(_: derived.Ctx, req: Request, _: {Note}, list: {Part}): {Note} return notes(req, list) end,
  -- An undo of an edit of a context clip gives its notes back.
  undo = true,
  -- One value for each window of the roll, and a few more.
  limit = 16,
}
M.node = derived.node(spec)

--- What the roll asks for: the active clip, the ids of the edited clips,
--- the span in song beats, and the toggles of the tracks.
function M.request(active: types.Clip, ids: {integer}, from: number, to: number, shown: {integer: boolean}): Request
  local editable: {integer: boolean} = {}
  for _, id in ipairs(ids) do
    editable[id] = true
  end
  -- The toggles go in the key in order, and in a copy: the roll's table changes.
  local toggles: {integer: boolean} = {}
  local on: {integer} = {}
  for id, v in pairs(shown) do
    toggles[id] = v
    on[#on + 1] = id
  end
  table.sort(on)
  local marks: {string} = {}
  for i, id in ipairs(on) do
    marks[i] = id .. (toggles[id] and "+" or "-")
  end
  local option = opt.roll_context
  local s = scope()
  local id = table.concat({
    active.id,
    active.track,
    active.start,
    table.concat(ids, ","),
    from,
    to,
    table.concat(marks, ","),
    option is {string | number} and "[" .. table.concat(option as {string}, ",") .. "]" or tostring(option),
    opt.roll_context_max,
    s and s.breadcrumb() or "",
  }, "|")
  return {id = id, active = active, editable = editable, from = from, to = to, shown = toggles}
end

--- The context notes of a request: `{ pitch, start, length, velocity,
--- clip, track, color }` each.
function M.notes(req: Request): {Note}
  return (M.node:get(req, true))
end

return M
