-- The notes that the piano roll shows behind its own (`paw.roll_clips`):
-- the notes of the other parts that sound in the span of the edited
-- clips. They are three kinds of node of `paw.derived` (the design
-- `derived.md`, D2):
--
--   roll.part        what the choice of the parts reads of one part: its
--                     colour, whether it is drums, its group
--   roll.part_clips  the MIDI clips of one part: their places and the
--                     stamps of their notes
--   roll.context      the notes behind the roll, for one request. Its key
--                     is what the roll asks for: the active clip and its
--                     place, the edited clips, the span, the shown parts,
--                     the options, the scope. Its inputs are the context
--                     clips (each with its part's colour, its place and
--                     its stamp); its value their notes, in the beats of
--                     the roll.
--
-- So an edit of an edited clip (its notes are not context) reads the clips
-- of its part again, finds the same context clips, and makes no notes
-- again. An edit of a context clip changes the inputs: the notes are made
-- again.
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
  is_drums: function(t: types.Part): boolean
end
local record Scope
  parts: function(): {integer}
  breadcrumb: function(): string
end
local record Paw is partial.Paw
  draw: DrawModule
  groups: GroupsModule
  harmony: Harmony
end
local runtime = (_G as {string: Paw}).paw
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

--- A part near the roll, as `paw.roll_clips.parts` gives it.
local record Part
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
  part: integer
  color: string
end

--- A context clip, as the node compares them: what its notes are made of.
local record Portion
  id: integer
  part: integer
  color: string
  start: number
  length: number
  stamp: integer
  transpose: integer
end

--- A MIDI clip of a part, as the node of the part's clips keeps it.
local record Placed
  id: integer
  start: number
  length: number
  stamp: integer
  transpose: integer
end

local record M
  type Request = Request
  type Part = Part
  type Note = Note
end

-- The fields of a part that its colour and its choice read: the colour,
-- the group (in `meta`), and whether it is drums (`meta`, the name, the
-- devices). Its place in the list is the source `parts`.
local FIELDS = {"name", "color", "meta", "devices"}

--- What the choice of the parts reads of a part.
local record Look
  name: string
  color: string
  drums: boolean
  master: boolean
  group: integer -- the group it belongs to
  head: boolean -- it is the head of a group
end

local function same_look(a: Look, b: Look): boolean
  return a.name == b.name
    and a.color == b.color
    and a.drums == b.drums
    and a.master == b.master
    and a.group == b.group
    and a.head == b.head
end

--- A part as its choice reads it, through the graph when `ctx` is there.
--- Nil for a part that is gone.
local function look(ctx: derived.Ctx, id: integer): Look
  local t: types.Part
  if ctx then
    -- Its colour by its place in the list, or by its group's colour.
    ctx:parts()
    t = ctx:part(id, FIELDS)
  else
    local ok, got = pcall(api.part_get, id)
    t = ok and got or nil
  end
  if not t then
    return nil
  end
  local group = runtime.groups.of(id)
  if ctx and group then
    ctx:part(group, FIELDS)
  end
  return {
    name = t.name,
    color = runtime.draw.part_colour(t),
    drums = runtime.harmony.is_drums(t),
    master = t.master,
    group = group,
    head = runtime.groups.is_group(id),
  }
end

-- Each part's look is a node: an edit reads again only the parts it changed.
local look_spec: derived.Spec<integer, Look, boolean> = {
  name = "roll.part",
  kind = "family",
  make = function(ctx: derived.Ctx, id: integer): Look return look(ctx, id) end,
  same = same_look,
  -- The parts of a large song.
  limit = 1024,
}
local looks = derived.node(look_spec)

--- A part's look: from the node when `ctx` is there.
local function look_of(ctx: derived.Ctx, id: integer): Look
  if ctx then
    return ctx:get(looks, id)
  end
  return look(nil, id)
end

--- The clips of a part, or none.
local function clips_of(id: integer): {types.Clip}
  local ok, list = pcall(api.clip_list, id)
  return ok and list or {}
end

local function scope(): Scope
  return rawget(runtime as {string: Scope}, "scope")
end

--- Whether a part's notes show, before the toggles: by `paw.opt.roll_context`.
--- `group` is the group of the active clip's part.
local function chosen(id: integer, t: Look, group: integer, listed: {integer: boolean}): boolean
  local option = opt.roll_context
  if option is {string | number} then
    return listed[id] or false
  elseif option == "group" then
    return not t.drums and group ~= nil and (t.group == group or id == group)
  elseif option == "none" then
    return false
  end
  return not t.drums
end

--- The parts whose notes can show behind the roll, but not the part of
--- the active clip. With `midi`, only those with a MIDI clip (the list
--- that `paw.roll_clips.parts` gives); without, each part whose notes
--- show could have context clips.
local function parts(ctx: derived.Ctx, req: Request, midi: boolean): {Part}
  local a = req.active
  local own = look_of(ctx, a.part)
  local group = own and (own.group or (own.head and a.part)) or nil
  local listed: {integer: boolean} = {}
  local option = opt.roll_context
  if option is {string | number} then
    for _, id in ipairs(option) do
      listed[math.tointeger(id)] = true
    end
  end
  local out: {Part} = {}
  -- In a narrowed window (`paw.scope`), the scope's parts alone.
  local s = scope()
  if ctx then
    ctx:parts()
  end
  local ids = s and s.parts() or api.part_list()
  for _, id in ipairs(ids) do
    local t = id ~= a.part and look_of(ctx, id)
    if t and not t.master then
      local has_midi = not midi
      if midi then
        for _, c in ipairs(clips_of(id)) do
          has_midi = has_midi or c.kind == "midi"
        end
      end
      if has_midi then
        local on = chosen(id, t, group, listed)
        if req.shown[id] ~= nil then
          on = req.shown[id]
        end
        out[#out + 1] = {id = id, name = t.name, color = t.color, drums = t.drums, on = on}
      end
    end
  end
  return out
end

--- The parts near the roll: `{ id, name, color, drums, on }` each.
function M.parts(req: Request): {Part}
  return parts(nil, req, true)
end

-- Each part's MIDI clips are a node of their own: an edit of a clip reads
-- the clips of its part again, and not those of the other parts.
local function same_placed(a: {Placed}, b: {Placed}): boolean
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    local x, y = a[i], b[i]
    if
      x.id ~= y.id or x.start ~= y.start or x.length ~= y.length or x.stamp ~= y.stamp or x.transpose ~= y.transpose
    then
      return false
    end
  end
  return true
end

local clips_spec: derived.Spec<integer, {Placed}, boolean> = {
  name = "roll.part_clips",
  kind = "family",
  make = function(ctx: derived.Ctx, part: integer): {Placed}
    local out: {Placed} = {}
    for _, c in ipairs(ctx:clips(part)) do
      if c.kind == "midi" then
        out[#out + 1] = {id = c.id, start = c.start, length = c.length, stamp = c.stamp, transpose = c.transpose or 0}
      end
    end
    return out
  end,
  same = same_placed,
  -- The parts of a large song.
  limit = 1024,
}
local part_clips = derived.node(clips_spec)

--- The context clips: the MIDI clips of the active clip's part and of the
--- shown parts that sound in the span, but not the edited clips.
local function portions(ctx: derived.Ctx, req: Request): {Portion}
  local a = req.active
  local own = look_of(ctx, a.part)
  local looked: {Part} = {{id = a.part, on = true, color = own and own.color or nil}}
  for _, t in ipairs(parts(ctx, req, false)) do
    looked[#looked + 1] = t
  end
  local out: {Portion} = {}
  for _, t in ipairs(looked) do
    if t.on then
      for _, c in ipairs(ctx:get(part_clips, t.id)) do
        if not req.editable[c.id] and c.start < req.to - EPS and c.start + c.length > req.from + EPS then
          out[#out + 1] = {
            id = c.id,
            part = t.id,
            color = t.color,
            start = c.start,
            length = c.length,
            stamp = c.stamp,
            transpose = c.transpose,
          }
        end
      end
    end
  end
  return out
end

local function same_portions(a: {Portion}, b: {Portion}): boolean
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    local x, y = a[i], b[i]
    if
      x.id ~= y.id
      or x.part ~= y.part
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
local function notes(req: Request, list: {Portion}): {Note}
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
      -- At the pitch it plays at: the clip's transpose added.
      local pitch = n.pitch + c.transpose
      if n.start >= -EPS and n.start < c.length - EPS and pitch >= 0 and pitch <= 127 then
        out[#out + 1] = {
          pitch = pitch,
          start = n.start + shift,
          length = math.min(n.length, c.length - n.start),
          velocity = n.velocity,
          clip = c.id,
          part = c.part,
          color = c.color,
        }
      end
    end
  end
  return out
end

local spec: derived.Spec<Request, {Note}, {Portion}> = {
  name = "roll.context",
  kind = "memo",
  id = function(req: Request): string return req.id end,
  inputs = function(ctx: derived.Ctx, req: Request): {Portion} return portions(ctx, req) end,
  same_inputs = same_portions,
  make = function(_: derived.Ctx, req: Request, _: {Note}, list: {Portion}): {Note} return notes(req, list) end,
  -- An undo of an edit of a context clip gives its notes back.
  undo = true,
  -- One value for each window of the roll, and a few more.
  limit = 16,
}
local context = derived.node(spec)

--- What the roll asks for: the active clip, the ids of the edited clips,
--- the span in song beats, and the toggles of the parts.
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
  local id = table.concat(
    {
      active.id,
      active.part,
      active.start,
      table.concat(ids, ","),
      from,
      to,
      table.concat(marks, ","),
      option is {string | number} and "[" .. table.concat(option as {string}, ",") .. "]" or tostring(option),
      opt.roll_context_max,
      s and s.breadcrumb() or "",
    },
    "|"
  )
  return {id = id, active = active, editable = editable, from = from, to = to, shown = toggles}
end

--- The context notes of a request: `{ pitch, start, length, velocity,
--- clip, part, color }` each.
function M.notes(req: Request): {Note}
  return (context:get(req, true))
end

return M
