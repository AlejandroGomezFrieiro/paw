-- `paw.query`: find things by where they sit in the project, as a
-- Tree-sitter query or a CSS selector finds nodes in a tree.
--
--   clip[name~=pizz] > note[pitch>=C5]     the high notes of the pizzicato clips
--   group[name=Strings] track              every track inside the Strings group
--   note[lyric^=la], note[art=staccato]    two kinds of note at once
--   clip:has(note[vel>120])                clips with a very loud note
--
-- The tree: the project holds its tracks (a group holds its members),
-- markers and regions; a track holds its clips, devices and automation
-- lanes; a MIDI clip holds its notes and controller moves (`cc`); a lane
-- holds its points. A step names a kind (`track` `group` `clip` `note`
-- `cc` `device` `lane` `point` `marker` `region`, or `*` for any), then
-- tests in brackets. `a > b` is a `b` right inside an `a`, `a b` one
-- anywhere inside it, and `,` joins two queries.
--
-- A test is `field op value`: `=` `!=` `<` `<=` `>` `>=`, `~=` a regular
-- expression (`paw.regex`) holds, `^=` starts with, `$=` ends with, `*=`
-- holds the words. `value|value` is either. A field alone holds when it is
-- set (`[mute]`), `!field` when it is not. Pitches are written `c4`, `c#4`
-- or `60`, `c` meaning any octave; lengths in beats or as a note value
-- (`len<1/8`); text is compared without case.
--
-- In Lua, the same as text or as a table of steps, each a string or a table
-- of the kind and its tests, with `">"` between two for a step right inside:
--
--   paw.query("clip[name~=pizz] > note[pitch>=C5]")
--   paw.query({ { "clip", name = "~= pizz" }, ">", { "note", pitch = ">= C5", function(n) return n.data.velocity > 90 end } })
--
-- Each result is a node (`paw.contracts.QueryNode`): `{ kind, id, data,
-- parent, track, clip, location, text }`, `data` the thing as `paw.api`
-- gives it. `paw.query.field(kind, name, get)` adds a field; the fields of
-- `paw.ex.field` are fields here as well.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local A = require("paw.address")
local music = require("paw.music")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type objects = require("paw.objects")
local type MarkersModule = require("paw.markers")
local type MusicModule = require("paw.music")
local type AttrModule = require("paw.attr")
local type LanesModule = require("paw.lanes")
local type RegexModule = require("paw.regex")
local type QfModule = require("paw.qf")

local type Node = contracts.QueryNode
local type Data = contracts.QueryData
local type Value = contracts.QueryValue
local type Field = contracts.QueryField

--- A value that a test compares: one of a field's, or the field's own.
local type Scalar = number | string | boolean

--- A test of a node.
local type Test = function(node: Node): boolean

--- A test of a step that is a query of its own: `:has(query)`.
local record Has
  has: {Step}
end

--- One step of a query: a kind (or `*`), its tests, and how it joins the
--- step before it (`>` right inside, ` ` anywhere inside).
local record Step
  kind: string
  tests: {Test | Has}
  comb: string
end

--- A step in the table form: the kind first, then tests as fields
--- (`name = "~= pizz"`) or functions.
local record TableStep
  {string | Test}
  metamethod __index: function(TableStep, string): Scalar
end

--- A query in the table form (steps, with `">"` between two for a step
--- right inside), or a query that `paw.query.parse` read: its chains of
--- steps, and its text.
local record QueryTable
  {string | TableStep}
  selectors: {{Step}}
  text: string
end

--- A query: text, or the table form.
local type Query = string | QueryTable

--- What `paw.query.select` takes: the title of the list, `loc` for the
--- window's location list, and `choose = false` to choose nothing.
local record SelectOptions
  title: string
  loc: boolean
  choose: boolean
end

--- A marker or a region, as the data of its node.
local type Marker = MarkersModule.Marker

--- A point of a lane, as the data of its node.
local record Point
  beat: number
  value: number
end

--- What `paw.ex` reads its fields from (paw/ex.lua).
local record ExItem
  kind: string
  track: integer
  clip: types.Clip
  note: types.Note
  place: integer
  at: number
end

--- A field of `paw.ex.field`: the level it is of, and how it reads an item.
local record ExField
  level: string
  get: function(item: ExItem): Value
end

--- paw/ex.lua, as far as this module reads it.
local record Ex
  fields: {string:ExField}
end

--- paw/scope.lua: the tracks of the tab, narrowed to a group or not.
local record Scope
  tracks: function(): {integer}
end

--- A note's meta, as far as this module reads it.
local record Notation
  art: {string:boolean}
end
local record NoteMeta
  lyric: string
  comment: string
  channel: integer
  notation: Notation
  articulation: string | {string}
end

local record Paw is partial.Paw
  ex: Ex
  scope: Scope
  markers: MarkersModule
  music: MusicModule
  attr: AttrModule
  lanes: LanesModule
  regex: RegexModule
  time: objects.Time
  qf: QfModule
end
local paw = (_G as {string:Paw}).paw

local record M
  type Node = Node
  type Test = Test
  type Step = Step
  type TableStep = TableStep
  type QueryTable = QueryTable
  type Query = Query
  type SelectOptions = SelectOptions
  --- The kinds of node.
  KINDS: {contracts.QueryKind}
  --- The fields that `paw.query.field` added, by kind (`*`: of every kind), then by name.
  fields: {string:{string:Field}}
  metamethod __call: function(M, q: Query): {Node}
end

local function fail(text: string, ...: string)
  error(string.format(text, ...), 0)
end

-- The tree -------------------------------------------------------------------------

M.KINDS = { "track", "group", "clip", "note", "cc", "device", "lane", "point", "marker", "region" }
local KIND: {string:boolean} = {}
for _, k in ipairs(M.KINDS) do KIND[k] = true end

-- What each kind can hold, at any depth: where looking for a kind goes.
local HOLDS: {string:{string:boolean}} = {
  project = { track = true, group = true, clip = true, note = true, cc = true, device = true, lane = true, point = true, marker = true, region = true },
  track = { track = true, group = true, clip = true, note = true, cc = true, device = true, lane = true, point = true },
  clip = { note = true, cc = true },
  lane = { point = true },
}
HOLDS.group = HOLDS.track

local function holds(node_kind: string, wanted: string): boolean
  local h = HOLDS[node_kind]
  return h and (wanted == "*" or h[wanted]) or false
end

local function try<T, R>(fn: function(T): R, value: T): R
  local ok, v = pcall(fn, value)
  if ok then return v end
end

--- The tracks of the project as a tree: the ones in no group, and each
--- group's members, in the order of the track list.
local record Tracks
  data: {integer:types.Track}
  members: {integer:{integer}}
  top: {integer}
  index: {integer:integer}
end

--- What one run of a query reads once.
local record Cache
  tracks: Tracks
end

--- What this module reads of a track's `meta` (paw/groups.tl).
local record GroupMeta
  group: integer
  group_head: boolean
end

local function group_meta(t: types.Track): GroupMeta return (t.meta or {}) as GroupMeta end

--- The tracks of the project as a tree: the ones in no group, and each
--- group's members, in the order of the track list. In a tab narrowed to a
--- group, that group's tracks, as Ex ranges see them.
local function track_tree(cache: Cache): Tracks
  if cache.tracks then return cache.tracks end
  local ids = paw.scope and paw.scope.tracks() or api.track_list()
  local data: {integer:types.Track} = {}
  local members: {integer:{integer}} = {}
  local top: {integer} = {}
  for _, id in ipairs(ids) do data[id] = api.track_get(id) end
  for _, id in ipairs(ids) do
    local g = group_meta(data[id]).group
    if g and data[g] and group_meta(data[g]).group_head then
      members[g] = members[g] or {}
      members[g][#members[g] + 1] = id
    else
      top[#top + 1] = id
    end
  end
  local index: {integer:integer} = {}
  for i, id in ipairs(ids) do index[id] = i end
  cache.tracks = { data = data, members = members, top = top, index = index }
  return cache.tracks
end

local function track_node(cache: Cache, id: integer, parent: Node): Node
  local t = track_tree(cache)
  local d = t.data[id]
  local group = group_meta(d).group_head == true
  return { kind = (group and "group" or "track") as contracts.QueryKind, id = id, data = d as Data, parent = parent, track = id, index = t.index[id] }
end

local function track_of(node: Node): types.Track return node.data as types.Track end
local function clip_data(node: Node): types.Clip return node.data as types.Clip end

--- The children of a node, those of `wanted` kind or that may hold one.
local function children(cache: Cache, node: Node, wanted: string, out?: {Node}): {Node}
  out = out or {}
  local function want(kind: string): boolean return wanted == "*" or kind == wanted or holds(kind, wanted) end
  local k = node.kind
  if k == "project" then
    local t = track_tree(cache)
    if want("track") or want("group") then
      for _, id in ipairs(t.top) do out[#out + 1] = track_node(cache, id, node) end
    end
    if wanted == "*" or wanted == "marker" or wanted == "region" then
      for _, m in ipairs(paw.markers and paw.markers.list() or {}) do
        out[#out + 1] = { kind = (m.length and "region" or "marker") as contracts.QueryKind, id = m.id, data = m as Data, parent = node }
      end
    end
  elseif k == "track" or k == "group" then
    local t = track_tree(cache)
    if k == "group" and (want("track") or want("group")) then
      for _, id in ipairs(t.members[node.id] or {}) do out[#out + 1] = track_node(cache, id, node) end
    end
    if want("clip") then
      for _, c in ipairs(api.clip_list(node.id)) do
        out[#out + 1] = { kind = "clip", id = c.id, data = c as Data, parent = node, track = node.id, clip = c.id }
      end
    end
    if want("device") then
      for i, id in ipairs(track_of(node).devices or {}) do
        local d = try(api.device_get, id)
        if d then out[#out + 1] = { kind = "device", id = id, data = d as Data, parent = node, track = node.id, index = i } end
      end
    end
    if want("lane") then
      for _, l in ipairs(try(api.lane_list, node.id) or {}) do
        out[#out + 1] = { kind = "lane", id = l.id, data = l as Data, parent = node, track = node.id }
      end
    end
  elseif k == "clip" then
    if clip_data(node).kind ~= "midi" then return out end
    if wanted == "*" or wanted == "note" then
      local notes = api.clip_notes(node.id)
      for i, n in ipairs(notes) do
        out[#out + 1] = { kind = "note", id = n.id, data = n as Data, parent = node, track = node.track, clip = node.id, place = i }
      end
    end
    if wanted == "*" or wanted == "cc" then
      for i, c in ipairs(try(api.clip_controls, node.id) or {}) do
        out[#out + 1] = { kind = "cc", id = i, data = c as Data, parent = node, track = node.track, clip = node.id, place = i }
      end
    end
  elseif k == "lane" then
    for i, p in ipairs(try(api.lane_points, node.id) or {}) do
      local point: Point = { beat = p[1] or (p as Point).beat, value = p[2] or (p as Point).value }
      out[#out + 1] = { kind = "point", id = i, data = point as Data, parent = node, track = node.track, place = i }
    end
  end
  return out
end

--- Every node of `wanted` kind inside `node`, in the order of the tree.
local function descendants(cache: Cache, node: Node, wanted: string, out?: {Node}): {Node}
  out = out or {}
  for _, child in ipairs(children(cache, node, wanted)) do
    if wanted == "*" or (child.kind as string) == wanted or (wanted == "track" and child.kind == "group") then out[#out + 1] = child end
    if holds(child.kind, wanted) then descendants(cache, child, wanted, out) end
  end
  return out
end

-- Where a node is, as an address --------------------------------------------------

local function clip_of(node: Node): Node
  local at = node
  while at and at.kind ~= "clip" do at = at.parent end
  return at
end

--- What a note and a controller move have: where they start in the clip.
local record Timed
  start: number
end

--- The beat of the song a node starts at, or nil.
local function song_beat(node: Node): number
  local k = node.kind
  if k == "note" or k == "cc" then
    local c = clip_of(node)
    return c and clip_data(c).start + ((node.data as Timed).start or 0)
  elseif k == "clip" then
    return clip_data(node).start
  elseif k == "marker" or k == "region" then
    return (node.data as Marker).beat
  elseif k == "point" then
    return (node.data as Point).beat
  end
end

--- A node's location, as the quickfix list and `paw.qf.go` take them.
function M.location(node: Node): contracts.Location
  local k = node.kind
  if k == "track" or k == "group" then return { uri = A.track(node.id) } end
  if k == "clip" then return { uri = A.clip(node.id) } end
  if k == "note" then
    local d = node.data as types.Note
    if d.id then return { uri = A.note(node.clip, d.id) } end
    return { uri = A.clip(node.clip), selector = { time = { d.start, d.start }, pitch = { d.pitch, d.pitch } } }
  end
  if k == "cc" then
    local d = node.data as types.Control
    return { uri = A.clip(node.clip) .. "/control/" .. tostring(d.type or "cc") .. (d.number and "/" .. d.number or ""), selector = { time = { d.start, d.start } } }
  end
  if k == "device" then return { uri = A.device(node.id) } end
  if k == "lane" then return { uri = A.lane(node.id) } end
  if k == "point" then
    local d = node.data as Point
    return { uri = A.lane(node.parent.id), selector = { time = { d.beat, d.beat } } }
  end
  if k == "marker" or k == "region" then
    local d = node.data as Marker
    return { uri = A.marker(node.id), selector = { time = { d.beat, d.beat + (d.length or 0) } } }
  end
  return { uri = A.project() }
end

local function track_name(node: Node): string
  local at = node
  while at and at.kind ~= "track" and at.kind ~= "group" do at = at.parent end
  return at and at.data.name or ""
end

--- A node in a few words, for the quickfix list: `C5 vel 100 at 5.1.00 · Violins pizz`.
function M.describe(node: Node): string
  local k = node.kind
  local at = song_beat(node)
  local when = at and paw.time.format(at) or ""
  if k == "note" then
    local d = node.data as types.Note
    local c = clip_of(node)
    local m = d.meta as NoteMeta
    local lyric = type(m) == "table" and type(m.lyric) == "string" and " “" .. m.lyric .. "”" or ""
    return string.format("%s vel %d len %g%s at %s · %s", paw.music.name(d.pitch), d.velocity or 0, d.length or 0, lyric, when, c and c.data.name or "")
  elseif k == "cc" then
    local d = node.data as types.Control
    return string.format("%s %s = %g at %s · %s", tostring(d.type or "cc"), tostring(d.number or ""), d.value or 0, when, clip_of(node).data.name)
  elseif k == "clip" then
    return string.format("clip %s at %s on %s", node.data.name, when, track_name(node))
  elseif k == "track" or k == "group" then
    return k .. " " .. node.data.name
  elseif k == "device" then
    return string.format("device %s on %s", node.data.name, track_name(node))
  elseif k == "lane" then
    local d = node.data as types.Lane
    return string.format("lane %s on %s", paw.lanes and paw.lanes.name(d) or tostring(d.target), track_name(node))
  elseif k == "point" then
    return string.format("point %g at %s on %s", (node.data as Point).value, when, track_name(node))
  elseif k == "marker" or k == "region" then
    return string.format("%s %s at %s", k, paw.markers.label(node.data as Marker), when)
  end
  return k
end

-- Fields ----------------------------------------------------------------------------

M.fields = {}

--- Add a field to a kind of node: `get(node)` returns its value (a number,
--- text, a boolean, or a list of texts any of which may match).
---   paw.query.field("note", "channel", function(node) return node.data.meta.channel end)
function M.field(kind: string, name: string, get: Field)
  assert(KIND[kind] or kind == "*", "no kind of node `" .. tostring(kind) .. "`")
  M.fields[kind] = M.fields[kind] or {}
  M.fields[kind][name:lower()] = get
end

local function meta(node: Node): NoteMeta
  local m = node.data.meta
  return type(m) == "table" and m as NoteMeta or {}
end

--- A note's articulations: its attribute's (`paw.attr`: the tag, the name
--- and the code, so `pz`, `pizzicato` and `11.A` all find a pizzicato),
--- those the score marks (`meta.notation.art`, a set) and any named in
--- `meta.articulation` (a name or a list of them).
function M.articulations(node: Node): {string}
  local out: {string} = {}
  local m = meta(node)
  local attr = (node.data as types.Note).attr
  local d = attr and paw.attr.describe(attr)
  if d then
    out[#out + 1] = d.tag
    if d.code then
      -- "Staccato off the string" is found as that and as `staccato`.
      local name = (d.name:match("^[^,]*")):lower()
      out[#out + 1] = d.code
      out[#out + 1] = name
      if name:match("^%S+") ~= name then out[#out + 1] = name:match("^%S+") end
    end
  end
  local art = type(m.notation) == "table" and m.notation.art
  if type(art) == "table" then
    for name, on in pairs(art) do
      if on then out[#out + 1] = tostring(name) end
    end
  end
  local own = m.articulation
  if own is string then out[#out + 1] = own end
  if own is {string} then
    for _, name in ipairs(own) do out[#out + 1] = tostring(name) end
  end
  table.sort(out)
  return out
end
local articulations = M.articulations

local function note(n: Node): types.Note return n.data as types.Note end
local function marker(n: Node): Marker return n.data as Marker end

local note_fields: {string:Field} = {
  vel = function(n: Node): Value return note(n).velocity end,
  len = function(n: Node): Value return note(n).length end,
  ["end"] = function(n: Node): Value return note(n).start + note(n).length end,
  at = function(n: Node): Value return song_beat(n) end,
  bar = function(n: Node): Value return paw.time.bar_of(song_beat(n)) end,
  lyric = function(n: Node): Value return meta(n).lyric end,
  art = function(n: Node): Value return articulations(n) end,
  channel = function(n: Node): Value return meta(n).channel or 1 end,
}
for name, get in pairs(note_fields) do M.field("note", name, get) end
local clip_fields: {string:Field} = {
  ["end"] = function(n: Node): Value return clip_data(n).start + clip_data(n).length end,
  bar = function(n: Node): Value return paw.time.bar_of(clip_data(n).start) end,
  notes = function(n: Node): Value return clip_data(n).note_count end,
  muted = function(n: Node): Value return clip_data(n).muted end,
  track = function(n: Node): Value return track_name(n) end,
}
for name, get in pairs(clip_fields) do M.field("clip", name, get) end
for _, kind in ipairs({ "track", "group" }) do
  M.field(kind, "index", function(n: Node): Value return n.index end)
  M.field(kind, "group", function(n: Node): Value return n.kind == "group" end)
  M.field(kind, "devices", function(n: Node): Value return #(track_of(n).devices or {}) end)
end
for _, kind in ipairs({ "marker", "region" }) do
  M.field(kind, "name", function(n: Node): Value return paw.markers.label(marker(n)) end)
  M.field(kind, "start", function(n: Node): Value return marker(n).beat end)
  M.field(kind, "end", function(n: Node): Value return marker(n).beat + (marker(n).length or 0) end)
  M.field(kind, "bar", function(n: Node): Value return paw.time.bar_of(marker(n).beat) end)
end
M.field("device", "index", function(n: Node): Value return n.index end)
M.field("device", "track", function(n: Node): Value return track_name(n) end)
M.field("lane", "name", function(n: Node): Value
  local l = n.data as types.Lane
  return paw.lanes and paw.lanes.name(l) or tostring(l.target)
end)
M.field("lane", "points", function(n: Node): Value return (n.data as types.Lane).point_count end)
M.field("cc", "at", function(n: Node): Value return song_beat(n) end)
M.field("point", "at", function(n: Node): Value return song_beat(n) end)
M.field("*", "comment", function(n: Node): Value return meta(n).comment end)

-- The level `paw.ex` gives its fields.
local EX_LEVEL: {string:string} = { note = "note", clip = "clip", track = "track", group = "track" }

-- What `paw.ex` reads of each node, made when first asked for.
local ex_items: {Node:ExItem} = setmetatable({}, { __mode = "k" })

--- What `paw.ex` reads its fields from: `{ kind, track, clip, note, place, at }`.
local function ex_item(node: Node): ExItem
  if ex_items[node] then return ex_items[node] end
  local level = EX_LEVEL[node.kind]
  local item: ExItem = { kind = level, track = node.track }
  if level == "note" then
    item.clip, item.note, item.place, item.at = clip_data(clip_of(node)), note(node), node.place, song_beat(node)
  elseif level == "clip" then
    item.clip, item.at = clip_data(node), clip_data(node).start
  else
    item.at = 0
  end
  ex_items[node] = item
  return item
end

--- A node's field, or nil.
function M.get(node: Node, name: string): Value
  name = name:lower()
  local own = M.fields[node.kind] and M.fields[node.kind][name] or (node.kind == "group" and M.fields.track and M.fields.track[name])
  if own then return own(node) end
  local ex = paw.ex and paw.ex.fields[name]
  if ex and ex.level == EX_LEVEL[node.kind] then return ex.get(ex_item(node)) end
  if M.fields["*"][name] then return M.fields["*"][name](node) end
  local v = (node.data as {string:Value})[name]
  if type(v) == "table" then return nil end
  return v
end

-- Reading a query -------------------------------------------------------------------

local pitch_word = music.pitch_word

local OPS = { "!=", "<=", ">=", "~=", "^=", "$=", "*=", "=", "<", ">" }

local function number_of(text: string): number | boolean
  local n = tonumber(text)
  if n then return n end
  local a, b = text:match("^(%d+)/(%d+)$")
  if a and tonumber(b) > 0 then return 4 * tonumber(a) / tonumber(b) end
  if text == "true" or text == "yes" then return true end
  if text == "false" or text == "no" then return false end
end

local function compare(op: string, got: number, want: number): boolean
  if op == "=" then return math.abs(got - want) < 1e-6 end
  if op == "!=" then return math.abs(got - want) >= 1e-6 end
  if op == "<" then return got < want - 1e-6 end
  if op == "<=" then return got <= want + 1e-6 end
  if op == ">" then return got > want + 1e-6 end
  if op == ">=" then return got >= want - 1e-6 end
end

--- A test of one value against what a field holds.
local type ValueTest = function(v: Scalar): boolean

--- A test of one value against what a field holds.
local function value_test(field: string, op: string, text: string, whole: string): ValueTest
  if op == "~=" then
    local re, err = paw.regex.try(text)
    if not re then fail("%s", err) end
    return function(v: Scalar): boolean return v ~= nil and re:find(tostring(v)) ~= nil end
  end
  local low = text:lower()
  if op == "^=" or op == "$=" or op == "*=" then
    return function(v: Scalar): boolean
      if v == nil then return false end
      local s = tostring(v):lower()
      if op == "^=" then return s:sub(1, #low) == low end
      if op == "$=" then return #low <= #s and s:sub(-#low) == low end
      return s:find(low, 1, true) ~= nil
    end
  end
  if field == "pitch" then
    local p = pitch_word(text)
    if not p then fail("`%s`: `%s` is not a pitch (`c4`, `c#4`, `c`, `60`)", whole, text) end
    if p.class then
      if op ~= "=" and op ~= "!=" then fail("`%s`: compare a pitch in any octave with `=` or `!=`", whole) end
      return function(v: Scalar): boolean return v is number and ((v % 12 == p.class) == (op == "=")) end
    end
    return function(v: Scalar): boolean return v is number and compare(op, v, p.pitch) end
  end
  local n = number_of(text)
  if n is boolean then
    if op ~= "=" and op ~= "!=" then fail("`%s`: compare true or false with `=` or `!=`", whole) end
    return function(v: Scalar): boolean return ((v and v ~= 0) and true or false) == n == (op == "=") end
  end
  local num = n as number
  return function(v: Scalar): boolean
    if v is number and num then return compare(op, v, num) end
    if op == "=" or op == "!=" then return (v ~= nil and tostring(v):lower() == low) == (op == "=") end
    -- Text compared in order, as a dictionary would.
    if v == nil or num then return false end
    local s = tostring(v):lower()
    if op == "<" then return s < low elseif op == "<=" then return s <= low elseif op == ">" then return s > low end
    return s >= low
  end
end

--- A test of a node: `field`, `!field`, or `field op value|value`.
local function test_of(text: string, whole: string): Test
  text = text:match("^%s*(.-)%s*$")
  if text == "" then fail("`%s`: an empty test", whole) end
  local neg, bare = text:match("^(!?)([%a_][%w_]*)$")
  if bare then
    return function(node: Node): boolean
      local got = M.get(node, bare)
      local v: Scalar
      if got is {string} then v = #got > 0 else v = got end
      local set = v ~= nil and v ~= false and v ~= 0 and v ~= ""
      return set ~= (neg == "!")
    end
  end
  local name, rest = text:match("^([%a_][%w_]*)%s*(.*)$")
  if not name then fail("`%s`: a test is a field, an operator and a value: `pitch>=c5`", whole) end
  local op: string
  for _, o in ipairs(OPS) do
    if rest:sub(1, #o) == o then op = o break end
  end
  if not op then fail("`%s`: `%s` needs an operator: = != < <= > >= ~= ^= $= *=", whole, name) end
  local value = rest:sub(#op + 1):match("^%s*(.-)%s*$")
  local quoted = value:match('^"(.*)"$') or value:match("^'(.*)'$")
  -- `a|b` is either, but inside quotes and in a regular expression `|` is its own.
  local alts: {ValueTest} = {}
  if quoted or op == "~=" then
    alts[1] = value_test(name:lower(), op, quoted or value, whole)
  else
    for part in value:gmatch("[^|]+") do alts[#alts + 1] = value_test(name:lower(), op, part, whole) end
  end
  if #alts == 0 then fail("`%s`: `%s` needs a value", whole, name) end
  -- With `!=` every value must differ; else any one may match.
  local all = op == "!="
  local function one(v: Scalar): boolean
    for _, t in ipairs(alts) do
      local ok = t(v)
      if all and not ok then return false end
      if not all and ok then return true end
    end
    return all
  end
  return function(node: Node): boolean
    local v = M.get(node, name)
    if v is {string} then
      if all then
        for _, x in ipairs(v) do
          if not one(x) then return false end
        end
        return true
      end
      for _, x in ipairs(v) do
        if one(x) then return true end
      end
      return false
    end
    return one(v)
  end
end

--- Split `text` at `sep` (a character) where it is not inside brackets,
--- parentheses or quotes.
local function split_top(text: string, sep: string): {string}
  local out: {string} = {}
  local depth, at = 0, 1
  local quote: string = nil
  for i = 1, #text do
    local c = text:sub(i, i)
    if quote then
      if c == quote then quote = nil end
    elseif c == '"' or c == "'" then
      quote = c
    elseif c == "[" or c == "(" then
      depth = depth + 1
    elseif c == "]" or c == ")" then
      depth = depth - 1
    elseif c == sep and depth == 0 then
      out[#out + 1] = text:sub(at, i - 1)
      at = i + 1
    end
  end
  out[#out + 1] = text:sub(at)
  return out
end

local parse_selector: function(text: string, whole: string): {Step}

--- One step: `kind[test][test]:has(query)`.
local function parse_step(text: string, whole: string): Step
  local kind, rest = text:match("^([%a_%*][%w_]*)(.*)$")
  if not kind then fail("`%s`: a step starts with a kind: %s or *", whole, table.concat(M.KINDS, " ")) end
  kind = kind:lower()
  if kind ~= "*" and not KIND[kind] then fail("`%s`: no kind `%s` (%s, or *)", whole, kind, table.concat(M.KINDS, " ")) end
  local tests: {Test | Has} = {}
  while rest ~= "" do
    if rest:sub(1, 1) == "[" then
      local depth = 0
      local close: integer = nil
      local quote: string = nil
      for i = 1, #rest do
        local c = rest:sub(i, i)
        if quote then
          if c == quote then quote = nil end
        elseif c == '"' or c == "'" then
          quote = c
        elseif c == "[" then
          depth = depth + 1
        elseif c == "]" then
          depth = depth - 1
          if depth == 0 then close = i break end
        end
      end
      if not close then fail("`%s`: a `[` is not closed", whole) end
      for _, part in ipairs(split_top(rest:sub(2, close - 1), ",")) do tests[#tests + 1] = test_of(part, whole) end
      rest = rest:sub(close + 1)
    elseif rest:sub(1, 5) == ":has(" then
      local depth = 0
      local close: integer = nil
      for i = 5, #rest do
        local c = rest:sub(i, i)
        if c == "(" then depth = depth + 1 elseif c == ")" then
          depth = depth - 1
          if depth == 0 then close = i break end
        end
      end
      if not close then fail("`%s`: `:has(` is not closed", whole) end
      local inner = parse_selector(rest:sub(6, close - 1), whole)
      tests[#tests + 1] = { has = inner }
      rest = rest:sub(close + 1)
    else
      fail("`%s`: after `%s`, `[test]` or `:has(query)`, not `%s`", whole, kind, rest)
    end
  end
  return { kind = kind, tests = tests }
end

--- A chain of steps joined by `>` (right inside) and spaces (anywhere inside).
parse_selector = function(text: string, whole: string): {Step}
  local steps: {Step} = {}
  local comb = " "
  local i, n = 1, #text
  while i <= n do
    local c = text:sub(i, i)
    if c:match("%s") then
      i = i + 1
    elseif c == ">" then
      if #steps == 0 then fail("`%s`: `>` with nothing before it", whole) end
      comb = ">"
      i = i + 1
    else
      -- A step runs to the next space or `>` outside brackets and quotes.
      local depth, j = 0, i
      local quote: string = nil
      while j <= n do
        local ch = text:sub(j, j)
        if quote then
          if ch == quote then quote = nil end
        elseif ch == '"' or ch == "'" then
          quote = ch
        elseif ch == "[" or ch == "(" then
          depth = depth + 1
        elseif ch == "]" or ch == ")" then
          depth = depth - 1
        elseif depth == 0 and (ch:match("%s") or ch == ">") then
          break
        end
        j = j + 1
      end
      local step = parse_step(text:sub(i, j - 1), whole)
      step.comb = comb
      steps[#steps + 1] = step
      comb = " "
      i = j
    end
  end
  if #steps == 0 then fail("`%s`: an empty query", whole) end
  if comb == ">" then fail("`%s`: `>` with nothing after it", whole) end
  return steps
end

--- A step from the table form: `{ "clip", name = "~= pizz", function(node) end }`.
local function table_step(t: TableStep, whole: string): Step
  local step = parse_step(tostring(t[1] or "*"), whole)
  for key, v in pairs(t as {string | integer:Scalar | Test}) do
    if key is string then
      local text = tostring(v)
      local op: string = nil
      for _, o in ipairs(OPS) do
        if text:sub(1, #o) == o then op = o break end
      end
      if v is boolean or v is number or not op then text = "=" .. text end
      step.tests[#step.tests + 1] = test_of(key .. text, whole)
    elseif v is Test then
      step.tests[#step.tests + 1] = v
    end
  end
  return step
end

--- Read a query (text or the table form) once, to run it often. Raises an
--- error that says what is wrong with it.
function M.parse(q: Query): QueryTable
  if q is QueryTable and q.selectors then return q end
  local selectors: {{Step}} = {}
  if q is string then
    for _, part in ipairs(split_top(q, ",")) do
      if part:match("%S") then selectors[#selectors + 1] = parse_selector(part, q) end
    end
    if #selectors == 0 then fail("an empty query") end
  elseif q is QueryTable then
    local steps: {Step} = {}
    local comb = " "
    for _, s in ipairs(q) do
      if s == ">" then
        comb = ">"
      else
        local step = s is TableStep and table_step(s, "query") or parse_step(tostring(s), tostring(s))
        step.comb, comb = comb, " "
        steps[#steps + 1] = step
      end
    end
    if #steps == 0 then fail("an empty query") end
    selectors[1] = steps
  else
    fail("a query is text or a table")
  end
  return { selectors = selectors, text = q is string and q or nil }
end

-- Running a query --------------------------------------------------------------------

local function key_of(node: Node): string
  return node.kind .. ":" .. tostring(node.clip or node.track or "") .. ":" .. tostring(node.id) .. ":" .. tostring(node.place or "")
end

local run_steps: function(cache: Cache, steps: {Step}, from: {Node}, first?: boolean): {Node}

local function passes(cache: Cache, step: Step, node: Node): boolean
  if step.kind ~= "*" and (node.kind as string) ~= step.kind and not (step.kind == "track" and node.kind == "group") then return false end
  for _, t in ipairs(step.tests) do
    if t is Has then
      if #run_steps(cache, t.has, { node }, true) == 0 then return false end
    elseif not t(node) then
      return false
    end
  end
  return true
end

--- Run a chain of steps from the nodes `from`; with `first`, stop at the first found.
run_steps = function(cache: Cache, steps: {Step}, from: {Node}, first?: boolean): {Node}
  local set = from
  for _, step in ipairs(steps) do
    -- What is inside one node is found once; from several, a node inside
    -- two of them (a group and its member) would be found twice.
    local out: {Node} = {}
    local seen: {string:boolean} = #set > 1 and {} or nil
    for _, node in ipairs(set) do
      local found = step.comb == ">" and children(cache, node, step.kind) or descendants(cache, node, step.kind)
      for _, child in ipairs(found) do
        local key = seen and key_of(child)
        if not (seen and seen[key]) and passes(cache, step, child) then
          if seen then seen[key] = true end
          out[#out + 1] = child
          if first and step == steps[#steps] then return out end
        end
      end
    end
    set = out
    if #set == 0 then break end
  end
  return set
end

-- A node's location is made when it is first asked for: most of a hundred
-- thousand notes found are never gone to.
local lazy: metatable<Node> = { __index = function(node: Node, key: string): contracts.Location
  if key == "location" then
    local loc = M.location(node)
    rawset(node as {string:contracts.Location}, "location", loc)
    return loc
  end
end }

--- Every node a query finds, in the order of the tree (each query of a
--- list of them in turn, none twice).
---   for _, n in ipairs(paw.query("note[pitch>=c6]")) do print(n.data.pitch) end
function M.run(q: Query): {Node}
  local parsed = M.parse(q)
  local cache: Cache = {}
  local root: Node = { kind = "project", data = {} }
  local out: {Node} = {}
  local seen: {string:boolean} = #parsed.selectors > 1 and {} or nil
  for _, steps in ipairs(parsed.selectors) do
    for _, node in ipairs(run_steps(cache, steps, { root })) do
      local key = seen and key_of(node)
      if not (seen and seen[key]) then
        if seen then seen[key] = true end
        out[#out + 1] = setmetatable(node, lazy)
      end
    end
  end
  return out
end

--- The nodes as quickfix entries.
function M.entries(nodes: {Node}): {QfModule.Item}
  local out: {QfModule.Item} = {}
  for i, node in ipairs(nodes) do out[i] = { location = node.location or M.location(node), text = M.describe(node) } end
  return out
end

--- Select the items that a query finds, where paw can select them. These
--- are its clips in the arrange view, and its notes in the piano roll (the
--- notes of each clip). Put all found items in the quickfix list (the location list
--- of the window with `opts.loc`). Returns the nodes.
function M.select(q: Query, opts?: SelectOptions): {Node}
  opts = opts or {}
  local nodes = M.run(q)
  local title = (opts.title or "select") .. " " .. (q is string and q or "")
  paw.qf.set(M.entries(nodes), { title = title, win = opts.loc or nil, source = "query" })
  if opts.choose == false then return nodes end
  local clips: {integer:boolean} = {}
  local notes: {integer:{integer:boolean}} = {}
  local first_note: Node
  for _, node in ipairs(nodes) do
    if node.kind == "clip" then
      clips[node.id] = true
    elseif node.kind == "note" then
      notes[node.clip] = notes[node.clip] or {}
      notes[node.clip][node.place] = true
      first_note = first_note or node
    end
  end
  if next(notes) then
    for clip, places in pairs(notes) do paw.frontend.choose_notes(clip, places) end
    paw.qf.go({ location = first_note.location })
  elseif next(clips) then
    paw.frontend.choose_clips(clips)
  end
  api.ui_redraw()
  return nodes
end

return setmetatable(M, { __call = function(_: M, q: Query): {Node} return M.run(q) end } as metatable<M>)
