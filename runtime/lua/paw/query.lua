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
-- Each result is a node: `{ kind, id, data, parent, track, clip, location, text }`,
-- `data` the thing as `paw.api` gives it. `paw.query.field(kind, name, get)`
-- adds a field; the fields of `paw.ex.field` are fields here as well.
local api = paw.api
local A = paw.address

local M = {}

local function fail(text, ...) error(string.format(text, ...), 0) end

-- The tree -------------------------------------------------------------------------

M.KINDS = { "track", "group", "clip", "note", "cc", "device", "lane", "point", "marker", "region" }
local KIND = {}
for _, k in ipairs(M.KINDS) do KIND[k] = true end

-- What each kind can hold, at any depth: where looking for a kind goes.
local HOLDS = {
  project = { track = true, group = true, clip = true, note = true, cc = true, device = true, lane = true, point = true, marker = true, region = true },
  track = { track = true, group = true, clip = true, note = true, cc = true, device = true, lane = true, point = true },
  clip = { note = true, cc = true },
  lane = { point = true },
}
HOLDS.group = HOLDS.track

local function holds(node_kind, wanted)
  local h = HOLDS[node_kind]
  return h and (wanted == "*" or h[wanted]) or false
end

local function try(fn, ...)
  local ok, v = pcall(fn, ...)
  if ok then return v end
end

--- The tracks of the project as a tree: the ones in no group, and each
--- group's members, in the order of the track list. In a tab narrowed to a
--- group, that group's tracks, as Ex ranges see them.
local function track_tree(cache)
  if cache.tracks then return cache.tracks end
  local ids = paw.scope and paw.scope.tracks() or api.track_list()
  local data, members, top = {}, {}, {}
  for _, id in ipairs(ids) do data[id] = api.track_get(id) end
  for _, id in ipairs(ids) do
    local meta = data[id].meta or {}
    local g = meta.group
    if g and data[g] and (data[g].meta or {}).group_head then
      members[g] = members[g] or {}
      members[g][#members[g] + 1] = id
    else
      top[#top + 1] = id
    end
  end
  local index = {}
  for i, id in ipairs(ids) do index[id] = i end
  cache.tracks = { data = data, members = members, top = top, index = index }
  return cache.tracks
end

local function track_node(cache, id, parent)
  local t = track_tree(cache)
  local d = t.data[id]
  local group = (d.meta or {}).group_head == true
  return { kind = group and "group" or "track", id = id, data = d, parent = parent, track = id, index = t.index[id] }
end

--- The children of a node, those of `wanted` kind or that may hold one.
local function children(cache, node, wanted, out)
  out = out or {}
  local function want(kind) return wanted == "*" or kind == wanted or holds(kind, wanted) end
  local k = node.kind
  if k == "project" then
    local t = track_tree(cache)
    if want("track") or want("group") then
      for _, id in ipairs(t.top) do out[#out + 1] = track_node(cache, id, node) end
    end
    if wanted == "*" or wanted == "marker" or wanted == "region" then
      for _, m in ipairs(paw.markers and paw.markers.list() or {}) do
        out[#out + 1] = { kind = m.length and "region" or "marker", id = m.id, data = m, parent = node }
      end
    end
  elseif k == "track" or k == "group" then
    local t = track_tree(cache)
    if k == "group" and (want("track") or want("group")) then
      for _, id in ipairs(t.members[node.id] or {}) do out[#out + 1] = track_node(cache, id, node) end
    end
    if want("clip") then
      for _, c in ipairs(api.clip_list(node.id)) do
        out[#out + 1] = { kind = "clip", id = c.id, data = c, parent = node, track = node.id, clip = c.id }
      end
    end
    if want("device") then
      for i, id in ipairs(node.data.devices or {}) do
        local d = try(api.device_get, id)
        if d then out[#out + 1] = { kind = "device", id = id, data = d, parent = node, track = node.id, index = i } end
      end
    end
    if want("lane") then
      for _, l in ipairs(try(api.lane_list, node.id) or {}) do
        out[#out + 1] = { kind = "lane", id = l.id, data = l, parent = node, track = node.id }
      end
    end
  elseif k == "clip" then
    if node.data.kind ~= "midi" then return out end
    if wanted == "*" or wanted == "note" then
      for i, n in ipairs(api.clip_notes(node.id)) do
        out[#out + 1] = { kind = "note", id = n.id, data = n, parent = node, track = node.track, clip = node.id, place = i }
      end
    end
    if wanted == "*" or wanted == "cc" then
      for i, c in ipairs(try(api.clip_controls, node.id) or {}) do
        out[#out + 1] = { kind = "cc", id = i, data = c, parent = node, track = node.track, clip = node.id, place = i }
      end
    end
  elseif k == "lane" then
    for i, p in ipairs(try(api.lane_points, node.id) or {}) do
      out[#out + 1] = { kind = "point", id = i, data = { beat = p[1] or p.beat, value = p[2] or p.value }, parent = node, track = node.track, place = i }
    end
  end
  return out
end

--- Every node of `wanted` kind inside `node`, in the order of the tree.
local function descendants(cache, node, wanted, out)
  out = out or {}
  for _, child in ipairs(children(cache, node, wanted)) do
    if wanted == "*" or child.kind == wanted or (wanted == "track" and child.kind == "group") then out[#out + 1] = child end
    if holds(child.kind, wanted) then descendants(cache, child, wanted, out) end
  end
  return out
end

-- Where a node is, as an address --------------------------------------------------

local function clip_of(node)
  local at = node
  while at and at.kind ~= "clip" do at = at.parent end
  return at
end

--- The beat of the song a node starts at, or nil.
local function song_beat(node)
  local k, d = node.kind, node.data
  if k == "note" or k == "cc" then
    local c = clip_of(node)
    return c and c.data.start + (d.start or 0)
  elseif k == "clip" then
    return d.start
  elseif k == "marker" or k == "region" then
    return d.beat
  elseif k == "point" then
    return d.beat
  end
end

--- A node's location, as the quickfix list and `paw.qf.go` take them.
function M.location(node)
  local k, d = node.kind, node.data
  if k == "track" or k == "group" then return { uri = A.track(node.id) } end
  if k == "clip" then return { uri = A.clip(node.id) } end
  if k == "note" then
    if d.id then return { uri = A.note(node.clip, d.id) } end
    return { uri = A.clip(node.clip), selector = { time = { d.start, d.start }, pitch = { d.pitch, d.pitch } } }
  end
  if k == "cc" then
    return { uri = A.clip(node.clip) .. "/control/" .. tostring(d.type or "cc") .. (d.number and "/" .. d.number or ""), selector = { time = { d.start, d.start } } }
  end
  if k == "device" then return { uri = A.device(node.id) } end
  if k == "lane" then return { uri = A.lane(node.id) } end
  if k == "point" then return { uri = A.lane(node.parent.id), selector = { time = { d.beat, d.beat } } } end
  if k == "marker" or k == "region" then return { uri = A.marker(node.id), selector = { time = { d.beat, d.beat + (d.length or 0) } } } end
  return { uri = A.project() }
end

local function track_name(node)
  local at = node
  while at and at.kind ~= "track" and at.kind ~= "group" do at = at.parent end
  return at and at.data.name or ""
end

--- A node in a few words, for the quickfix list: `C5 vel 100 at 5.1.00 · Violins pizz`.
function M.describe(node)
  local k, d = node.kind, node.data
  local at = song_beat(node)
  local when = at and paw.time.format(at) or ""
  if k == "note" then
    local c = clip_of(node)
    local lyric = type(d.meta) == "table" and type(d.meta.lyric) == "string" and " “" .. d.meta.lyric .. "”" or ""
    return string.format("%s vel %d len %g%s at %s · %s", paw.music.name(d.pitch), d.velocity or 0, d.length or 0, lyric, when, c and c.data.name or "")
  elseif k == "cc" then
    return string.format("%s %s = %g at %s · %s", tostring(d.type or "cc"), tostring(d.number or ""), d.value or 0, when, clip_of(node).data.name)
  elseif k == "clip" then
    return string.format("clip %s at %s on %s", d.name, when, track_name(node))
  elseif k == "track" or k == "group" then
    return k .. " " .. d.name
  elseif k == "device" then
    return string.format("device %s on %s", d.name, track_name(node))
  elseif k == "lane" then
    return string.format("lane %s on %s", paw.lanes and paw.lanes.name(d) or tostring(d.target), track_name(node))
  elseif k == "point" then
    return string.format("point %g at %s on %s", d.value, when, track_name(node))
  elseif k == "marker" or k == "region" then
    return string.format("%s %s at %s", k, paw.markers.label(d), when)
  end
  return k
end

-- Fields ----------------------------------------------------------------------------

M.fields = {}

--- Add a field to a kind of node: `get(node)` returns its value (a number,
--- text, a boolean, or a list of texts any of which may match).
---   paw.query.field("note", "channel", function(node) return node.data.meta.channel end)
--- @type function(kind: string, name: string, get: contracts.QueryField)
function M.field(kind, name, get)
  assert(KIND[kind] or kind == "*", "no kind of node `" .. tostring(kind) .. "`")
  M.fields[kind] = M.fields[kind] or {}
  M.fields[kind][name:lower()] = get
end

local function meta(node) return type(node.data.meta) == "table" and node.data.meta or {} end

--- A note's articulations: its attribute's (`paw.attr`: the tag, the name
--- and the code, so `pz`, `pizzicato` and `11.A` all find a pizzicato),
--- those the score marks (`meta.notation.art`, a set) and any named in
--- `meta.articulation` (a name or a list of them).
local function articulations(node)
  local out, m = {}, meta(node)
  local d = node.data.attr and paw.attr.describe(node.data.attr)
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
  if type(own) == "string" then out[#out + 1] = own end
  if type(own) == "table" then
    for _, name in ipairs(own) do out[#out + 1] = tostring(name) end
  end
  table.sort(out)
  return out
end
M.articulations = articulations

for name, get in pairs({
  vel = function(n) return n.data.velocity end,
  len = function(n) return n.data.length end,
  ["end"] = function(n) return n.data.start + n.data.length end,
  at = song_beat,
  bar = function(n) return paw.time.bar_of(song_beat(n)) end,
  lyric = function(n) return meta(n).lyric end,
  art = articulations,
  channel = function(n) return meta(n).channel or 1 end,
}) do M.field("note", name, get) end
for name, get in pairs({
  ["end"] = function(n) return n.data.start + n.data.length end,
  bar = function(n) return paw.time.bar_of(n.data.start) end,
  notes = function(n) return n.data.note_count end,
  muted = function(n) return n.data.muted end,
  track = track_name,
}) do M.field("clip", name, get) end
for _, kind in ipairs({ "track", "group" }) do
  M.field(kind, "index", function(n) return n.index end)
  M.field(kind, "group", function(n) return n.kind == "group" end)
  M.field(kind, "devices", function(n) return #(n.data.devices or {}) end)
end
for _, kind in ipairs({ "marker", "region" }) do
  M.field(kind, "name", function(n) return paw.markers.label(n.data) end)
  M.field(kind, "start", function(n) return n.data.beat end)
  M.field(kind, "end", function(n) return n.data.beat + (n.data.length or 0) end)
  M.field(kind, "bar", function(n) return paw.time.bar_of(n.data.beat) end)
end
M.field("device", "index", function(n) return n.index end)
M.field("device", "track", track_name)
M.field("lane", "name", function(n) return paw.lanes and paw.lanes.name(n.data) or tostring(n.data.target) end)
M.field("lane", "points", function(n) return n.data.point_count end)
M.field("cc", "at", song_beat)
M.field("point", "at", song_beat)
M.field("*", "comment", function(n) return meta(n).comment end)

-- The level `paw.ex` gives its fields.
local EX_LEVEL = { note = "note", clip = "clip", track = "track", group = "track" }

--- What `paw.ex` reads its fields from: `{ kind, track, clip, note, place, at }`.
local function ex_item(node)
  if node.ex then return node.ex end
  local level = EX_LEVEL[node.kind]
  local item = { kind = level, track = node.track }
  if level == "note" then
    item.clip, item.note, item.place, item.at = clip_of(node).data, node.data, node.place, song_beat(node)
  elseif level == "clip" then
    item.clip, item.at = node.data, node.data.start
  else
    item.at = 0
  end
  node.ex = item
  return item
end

--- A node's field, or nil.
function M.get(node, name)
  name = name:lower()
  local own = M.fields[node.kind] and M.fields[node.kind][name] or (node.kind == "group" and M.fields.track and M.fields.track[name])
  if own then return own(node) end
  local ex = paw.ex and paw.ex.fields[name]
  if ex and ex.level == EX_LEVEL[node.kind] then return ex.get(ex_item(node)) end
  if M.fields["*"][name] then return M.fields["*"][name](node) end
  local v = node.data[name]
  if type(v) == "table" then return nil end
  return v
end

-- Reading a query -------------------------------------------------------------------

local pitch_word = require("paw.music").pitch_word

local OPS = { "!=", "<=", ">=", "~=", "^=", "$=", "*=", "=", "<", ">" }

local function number_of(text)
  local n = tonumber(text)
  if n then return n end
  local a, b = text:match("^(%d+)/(%d+)$")
  if a and tonumber(b) > 0 then return 4 * tonumber(a) / tonumber(b) end
  if text == "true" or text == "yes" then return true end
  if text == "false" or text == "no" then return false end
end

local function compare(op, got, want)
  if op == "=" then return math.abs(got - want) < 1e-6 end
  if op == "!=" then return math.abs(got - want) >= 1e-6 end
  if op == "<" then return got < want - 1e-6 end
  if op == "<=" then return got <= want + 1e-6 end
  if op == ">" then return got > want + 1e-6 end
  if op == ">=" then return got >= want - 1e-6 end
end

--- A test of one value against what a field holds.
local function value_test(field, op, text, whole)
  if op == "~=" then
    local re, err = paw.regex.try(text)
    if not re then fail("%s", err) end
    return function(v) return v ~= nil and re:find(tostring(v)) ~= nil end
  end
  local low = text:lower()
  if op == "^=" or op == "$=" or op == "*=" then
    return function(v)
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
      return function(v) return type(v) == "number" and ((v % 12 == p.class) == (op == "=")) end
    end
    return function(v) return type(v) == "number" and compare(op, v, p.pitch) end
  end
  local n = number_of(text)
  if type(n) == "boolean" then
    if op ~= "=" and op ~= "!=" then fail("`%s`: compare true or false with `=` or `!=`", whole) end
    return function(v) return ((v and v ~= 0) and true or false) == n == (op == "=") end
  end
  return function(v)
    if type(v) == "number" and n then return compare(op, v, n) end
    if op == "=" or op == "!=" then return (v ~= nil and tostring(v):lower() == low) == (op == "=") end
    -- Text compared in order, as a dictionary would.
    if v == nil or n then return false end
    local s = tostring(v):lower()
    if op == "<" then return s < low elseif op == "<=" then return s <= low elseif op == ">" then return s > low end
    return s >= low
  end
end

--- A test of a node: `field`, `!field`, or `field op value|value`.
local function test_of(text, whole)
  text = text:match("^%s*(.-)%s*$")
  if text == "" then fail("`%s`: an empty test", whole) end
  local neg, bare = text:match("^(!?)([%a_][%w_]*)$")
  if bare then
    return function(node)
      local v = M.get(node, bare)
      if type(v) == "table" then v = #v > 0 end
      local set = v ~= nil and v ~= false and v ~= 0 and v ~= ""
      return set ~= (neg == "!")
    end
  end
  local name, rest = text:match("^([%a_][%w_]*)%s*(.*)$")
  if not name then fail("`%s`: a test is a field, an operator and a value: `pitch>=c5`", whole) end
  local op
  for _, o in ipairs(OPS) do
    if rest:sub(1, #o) == o then op = o break end
  end
  if not op then fail("`%s`: `%s` needs an operator: = != < <= > >= ~= ^= $= *=", whole, name) end
  local value = rest:sub(#op + 1):match("^%s*(.-)%s*$")
  local quoted = value:match('^"(.*)"$') or value:match("^'(.*)'$")
  -- `a|b` is either, but inside quotes and in a regular expression `|` is its own.
  local alts = {}
  if quoted or op == "~=" then
    alts[1] = value_test(name:lower(), op, quoted or value, whole)
  else
    for part in value:gmatch("[^|]+") do alts[#alts + 1] = value_test(name:lower(), op, part, whole) end
  end
  if #alts == 0 then fail("`%s`: `%s` needs a value", whole, name) end
  -- With `!=` every value must differ; else any one may match.
  local all = op == "!="
  local function one(v)
    for _, t in ipairs(alts) do
      local ok = t(v)
      if all and not ok then return false end
      if not all and ok then return true end
    end
    return all
  end
  return function(node)
    local v = M.get(node, name)
    if type(v) == "table" then
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
local function split_top(text, sep)
  local out, depth, at, quote = {}, 0, 1, nil
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

local parse_selector

--- One step: `kind[test][test]:has(query)`.
local function parse_step(text, whole)
  local kind, rest = text:match("^([%a_%*][%w_]*)(.*)$")
  if not kind then fail("`%s`: a step starts with a kind: %s or *", whole, table.concat(M.KINDS, " ")) end
  kind = kind:lower()
  if kind ~= "*" and not KIND[kind] then fail("`%s`: no kind `%s` (%s, or *)", whole, kind, table.concat(M.KINDS, " ")) end
  local tests = {}
  while rest ~= "" do
    if rest:sub(1, 1) == "[" then
      local depth, close, quote = 0, nil, nil
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
      local depth, close = 0, nil
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
parse_selector = function(text, whole)
  local steps, comb = {}, " "
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
      local depth, j, quote = 0, i, nil
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
local function table_step(t, whole)
  local step = parse_step(tostring(t[1] or "*"), whole)
  for key, v in pairs(t) do
    if type(key) == "string" then
      local text = tostring(v)
      local op = nil
      for _, o in ipairs(OPS) do
        if text:sub(1, #o) == o then op = o break end
      end
      if type(v) == "boolean" or type(v) == "number" or not op then text = "=" .. text end
      step.tests[#step.tests + 1] = test_of(key .. text, whole)
    elseif type(v) == "function" then
      step.tests[#step.tests + 1] = v
    end
  end
  return step
end

--- Read a query (text or the table form) once, to run it often. Raises an
--- error that says what is wrong with it.
function M.parse(q)
  if type(q) == "table" and q.selectors then return q end
  local selectors = {}
  if type(q) == "string" then
    for _, part in ipairs(split_top(q, ",")) do
      if part:match("%S") then selectors[#selectors + 1] = parse_selector(part, q) end
    end
    if #selectors == 0 then fail("an empty query") end
  elseif type(q) == "table" then
    local steps, comb = {}, " "
    for _, s in ipairs(q) do
      if s == ">" then
        comb = ">"
      else
        local step = type(s) == "table" and table_step(s, "query") or parse_step(tostring(s), tostring(s))
        step.comb, comb = comb, " "
        steps[#steps + 1] = step
      end
    end
    if #steps == 0 then fail("an empty query") end
    selectors[1] = steps
  else
    fail("a query is text or a table")
  end
  return { selectors = selectors, text = type(q) == "string" and q or nil }
end

-- Running a query --------------------------------------------------------------------

local function key_of(node)
  return node.kind .. ":" .. tostring(node.clip or node.track or "") .. ":" .. tostring(node.id) .. ":" .. tostring(node.place or "")
end

local run_steps

local function passes(cache, step, node)
  if step.kind ~= "*" and node.kind ~= step.kind and not (step.kind == "track" and node.kind == "group") then return false end
  for _, t in ipairs(step.tests) do
    if type(t) == "table" then
      if #run_steps(cache, t.has, { node }, true) == 0 then return false end
    elseif not t(node) then
      return false
    end
  end
  return true
end

--- Run a chain of steps from the nodes `from`; with `first`, stop at the first found.
run_steps = function(cache, steps, from, first)
  local set = from
  for _, step in ipairs(steps) do
    -- What is inside one node is found once; from several, a node inside
    -- two of them (a group and its member) would be found twice.
    local out, seen = {}, #set > 1 and {} or nil
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
local Node = { __index = function(node, key)
  if key == "location" then
    local loc = M.location(node)
    rawset(node, "location", loc)
    return loc
  end
end }

--- Every node a query finds, in the order of the tree (each query of a
--- list of them in turn, none twice).
---   for _, n in ipairs(paw.query("note[pitch>=c6]")) do print(n.data.pitch) end
function M.run(q)
  local parsed = M.parse(q)
  local cache = {}
  local root = { kind = "project", data = {} }
  local out, seen = {}, #parsed.selectors > 1 and {} or nil
  for _, steps in ipairs(parsed.selectors) do
    for _, node in ipairs(run_steps(cache, steps, { root })) do
      local key = seen and key_of(node)
      if not (seen and seen[key]) then
        if seen then seen[key] = true end
        out[#out + 1] = setmetatable(node, Node)
      end
    end
  end
  return out
end

--- The nodes as quickfix entries.
function M.entries(nodes)
  local out = {}
  for i, node in ipairs(nodes) do out[i] = { location = node.location or M.location(node), text = M.describe(node) } end
  return out
end

--- Select the items that a query finds, where paw can select them. These
--- are its clips in the arrange view, and its notes in the piano roll (the
--- notes of each clip). Put all found items in the quickfix list (the location list
--- of the window with `opts.loc`). Returns the nodes.
function M.select(q, opts)
  opts = opts or {}
  local nodes = M.run(q)
  local title = (opts.title or "select") .. " " .. (type(q) == "string" and q or "")
  paw.qf.set(M.entries(nodes), { title = title, win = opts.loc or nil, source = "query" })
  if opts.choose == false then return nodes end
  local clips, notes = {}, {}
  local first_note
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

return setmetatable(M, { __call = function(_, q) return M.run(q) end })
