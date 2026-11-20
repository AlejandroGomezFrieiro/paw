-- Motions and text objects that follow the project's tree (`paw.query`),
-- as Tree-sitter's do in Neovim:
--
--   ]]  [[    the next or previous clip of the same kind on the track
--   ]s  [s    the next or previous track beside this one in its group
--   [{  ]}    up to the group the track is in; to the group's last track
--   [u  ]u    up to the group (as `[{`); down into the group: its first track
--   ig  ag    the tracks of the group the cursor is in; with the group track
--   ]]  [[    in the piano roll: the next or previous note of the same pitch
--
-- `:select` and `:query` run a query (docs/reference/queries.md).
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local commands = require("paw.commands")
local type types = require("paw.types")
local type contracts = require("paw.contracts")

local type Context = commands.Context

--- The piano roll, as far as its motions read it (paw/views/pianoroll.lua).
local record Roll
  pitch: integer
  beat: number
  clip: function(Roll): contracts.TrackHandle
  ordered: function(Roll): {types.Note}
  set: function(Roll, integer, number)
end

--- A node that a query finds, as far as this module counts it (paw/query.lua).
local record Node
  kind: string
end

--- How `:select`, `:query` and `:lquery` run a query (`paw.query.select`).
local record SelectOptions
  choose: boolean
  title: string
  loc: boolean
end
local type Select = function(string, SelectOptions): {Node}

-- The global `paw` (runtime/types/paw.d.tl): no module of the global
-- requires this one, so it sees the global's types.
local keymap = paw.keymap
local cursor = paw.cursor
local groups = paw.groups

local record M
end

local EPS = 1e-9

-- Clips of the same kind ------------------------------------------------------------

--- What makes clips of a kind: their name without a number or "copy" at
--- the end (`Verse 2` is a `Verse`), and whether they are MIDI or audio.
function M.clip_kind(clip: types.Clip): string
  local name = tostring(clip.name or ""):lower()
  name = name:gsub("%s*%(?copy%)?%s*$", ""):gsub("[%s%-_.#]*%d+$", ""):gsub("%s+$", "")
  return clip.kind .. "\0" .. name
end

--- The clip `count` clips of the kind after (`dir` 1) or before (-1) the one
--- under the cursor, on its track; nil when there is none.
function M.same_clip(dir: integer, count?: integer): types.Clip
  local track = cursor.track()
  if not track then return nil end
  local here = cursor.clip()
  local list = api.clip_list(track.id)
  table.sort(list, function(a: types.Clip, b: types.Clip): boolean return a.start < b.start end)
  local kind = here and M.clip_kind(here:get())
  local beat, found: number, types.Clip = cursor.beat, nil
  for _ = 1, count or 1 do
    local step: types.Clip
    for i = dir > 0 and 1 or #list, dir > 0 and #list or 1, dir do
      local c = list[i]
      local after = dir > 0 and c.start > beat + EPS or dir < 0 and c.start < beat - EPS
      if after and (not kind or M.clip_kind(c) == kind) and (not here or c.id ~= here.id) then
        step = c
        break
      end
    end
    if not step then break end
    found, beat = step, step.start
  end
  return found
end

local function to_same_clip(dir: integer): function(contracts.KeyContext)
  return function(ctx: contracts.KeyContext)
    local c = M.same_clip(dir, ctx.count)
    if not c then return paw.notify(dir > 0 and "no later clip of this kind on the track" or "no earlier clip of this kind on the track", "warn") end
    cursor.set_beat(c.start)
  end
end

-- Tracks in their groups ------------------------------------------------------------

--- The tracks drawn beside a track in its group (or at the top level), in order.
local function siblings(id: integer): {integer}
  local parent = groups.of(id)
  local out: {integer} = {}
  for _, other in ipairs(groups.rows()) do
    if groups.of(other) == parent then out[#out + 1] = other end
  end
  return out
end

local function to_sibling(dir: integer): function(contracts.KeyContext)
  return function(ctx: contracts.KeyContext)
    local id = cursor.track_id()
    if not id then return end
    local list = siblings(id)
    for i, other in ipairs(list) do
      if other == id then
        local to = list[i + dir * (ctx.count or 1)]
        if not to then return paw.notify(dir > 0 and "the last track of its group" or "the first track of its group", "warn") end
        cursor.set_track(to)
        return
      end
    end
  end
end

local function to_parent(ctx: contracts.KeyContext)
  local id = cursor.track_id()
  for _ = 1, ctx.count or 1 do
    local up = id and groups.of(id)
    if not up then break end
    id = up
  end
  if not id or id == cursor.track_id() then return paw.notify("the track is in no group", "warn") end
  cursor.set_track(id)
end

--- The rows (places in the track list) a group takes; see below.
local group_rows: function(group: integer): integer, integer

--- To the last track of the group the cursor's track is in (of the group
--- around that one, when it is there already; a count goes out further).
local function to_group_end(ctx: contracts.KeyContext)
  local id = cursor.track_id()
  local list = api.track_list()
  for _ = 1, ctx.count or 1 do
    local group = id and groups.of(id)
    if not group then break end
    local _, finish = group_rows(group)
    if list[finish] == id then
      group = groups.of(group)
      if not group then break end
      _, finish = group_rows(group)
    end
    id = list[finish]
  end
  if not id or id == cursor.track_id() then return paw.notify("the track is in no group, or at its end", "warn") end
  cursor.set_track(id)
end

local function to_child()
  local id = cursor.track_id()
  local first = id and groups.is_group(id) and groups.members(id)[1]
  if not first then return paw.notify("not a group with tracks in it", "warn") end
  if groups.folded(id) then groups.fold(id, false) end
  cursor.set_track(first)
end

--- The group the cursor is in: the track itself when it is one, else the
--- group it belongs to.
local function cursor_group(): integer
  local id = cursor.track_id()
  if not id then return nil end
  if groups.is_group(id) then return id end
  return groups.of(id)
end

--- The rows (places in the track list) a group takes, members and members'
--- members included: from the group track, and from its first member.
group_rows = function(group: integer): integer, integer
  local list = api.track_list()
  local at: integer
  for i, id in ipairs(list) do
    if id == group then at = i end
  end
  local finish = at
  local function inside(id: integer): boolean
    local up = groups.of(id)
    while up do
      if up == group then return true end
      up = groups.of(up)
    end
  end
  while list[finish + 1] and inside(list[finish + 1]) do finish = finish + 1 end
  return at, finish
end

local function group_object(with_head: boolean): function(): contracts.Region
  return function(): contracts.Region
    local group = cursor_group()
    if not group then return nil end
    local at, finish = group_rows(group)
    local first = with_head and at or at + 1
    if finish < first then return nil end
    return { view = "arrange", kind = "line", r0 = first, r1 = finish, c0 = 0, c1 = 0 }
  end
end

-- Notes of the same pitch --------------------------------------------------------------

local function to_same_note(dir: integer): function(contracts.KeyContext)
  return function(ctx: contracts.KeyContext)
    local roll = paw.ui.views.pianoroll as Roll
    if not roll:clip() then return end
    local pitch = roll.pitch
    local beat = roll.beat
    local notes = roll:ordered()
    local found: types.Note
    for _ = 1, ctx.count or 1 do
      local step: types.Note
      for i = dir > 0 and 1 or #notes, dir > 0 and #notes or 1, dir do
        local n = notes[i]
        if n.pitch == pitch and (dir > 0 and n.start > beat + EPS or dir < 0 and n.start < beat - EPS) then
          step = n
          break
        end
      end
      if not step then break end
      found, beat = step, step.start
    end
    if not found then return paw.notify("no other " .. paw.music.name(pitch) .. (dir > 0 and " after it" or " before it"), "warn") end
    roll:set(pitch, found.start)
  end
end

-- Keys ---------------------------------------------------------------------------------

--- How a key of this module is mapped (`paw.keymap.set`).
local record KeyOptions
  view: string
  desc: string
  motion: boolean
  linewise: boolean
  jump: boolean
end
local function amap(lhs: string, fn: function(contracts.KeyContext), desc: string, opts: KeyOptions)
  opts.view, opts.desc = "arrange", desc
  keymap.set(lhs, fn, opts)
end
-- `]c` `[c`, not `]]` `[[`: `]` and `[` pan at once, and a second press
-- is a second step of the pan.
amap("]c", to_same_clip(1), "The next clip of the same kind on the track", { motion = true, jump = true })
amap("[c", to_same_clip(-1), "The clip of the same kind before, on the track", { motion = true, jump = true })
amap("]s", to_sibling(1), "The next track in the same group", { motion = true, linewise = true })
amap("[s", to_sibling(-1), "The track before in the same group", { motion = true, linewise = true })
amap("[{", to_parent, "Up to the group the track is in", { motion = true, linewise = true, jump = true })
amap("]}", to_group_end, "The last track of the group", { motion = true, linewise = true, jump = true })
amap("[u", to_parent, "Up to the group the track is in (as [{)", { motion = true, linewise = true, jump = true })
amap("]u", to_child, "Down into the group: its first track", { motion = true, linewise = true })
keymap.textobject("ig", group_object(false), { view = "arrange", desc = "The tracks of the group" })
keymap.textobject("ag", group_object(true), { view = "arrange", desc = "The group with its tracks" })

-- `]n` `[n`, not `]]` `[[`: `]` and `[` change the velocity at once.
keymap.set("]n", to_same_note(1), { view = "pianoroll", desc = "The next note of the same pitch", motion = true, jump = true })
keymap.set("[n", to_same_note(-1), { view = "pianoroll", desc = "The note of the same pitch before", motion = true, jump = true })

-- Commands -------------------------------------------------------------------------------

local function query_text(ctx: Context): string return (ctx.args[1] as string or ""):match("^%s*(.-)%s*$") end

local function run(ctx: Context, opts: SelectOptions): {Node}
  local q = query_text(ctx)
  if q == "" then
    paw.notify("usage: " .. ctx.name .. " clip[name~=pizz] > note[pitch>=c5]", "warn")
    return nil
  end
  local ok, nodes = pcall(paw.query.select as Select, q, opts)
  if not ok then
    paw.notify(tostring(nodes), "error")
    return nil
  end
  local counts, order: {string:integer}, {string} = {}, {}
  for _, n in ipairs(nodes) do
    local k = n.kind == "group" and "track" or n.kind
    if not counts[k] then order[#order + 1] = k end
    counts[k] = (counts[k] or 0) + 1
  end
  local parts: {string} = {}
  for _, k in ipairs(order) do parts[#parts + 1] = counts[k] .. " " .. k .. (counts[k] == 1 and "" or "s") end
  paw.notify(#nodes == 0 and "nothing in the project is " .. q or ((opts.choose == false and "found " or "chose ") .. table.concat(parts, ", ")))
  return nodes
end

local function complete_query(text: string): {string}
  local out: {string} = {}
  for _, k in ipairs(paw.query.KINDS as {string}) do
    if k:sub(1, #text) == text then out[#out + 1] = k end
  end
  return out
end

commands.define("select", function(ctx: Context): commands.Result run(ctx, {}) end, { raw = true, complete = complete_query,
  desc = "Choose what a query finds (its clips, or its notes in the piano roll) and list it in the quickfix list: `select clip[name~=pizz] > note[pitch>=c5]`" })
commands.define("query", function(ctx: Context): commands.Result run(ctx, { choose = false, title = "query" }) end, { raw = true, complete = complete_query,
  desc = "List what a query finds in the quickfix list: `query note[lyric=la]`, `query group[name=Strings] clip`" })
commands.define("lquery", function(ctx: Context): commands.Result run(ctx, { choose = false, title = "query", loc = true }) end, { raw = true, complete = complete_query,
  desc = "As `query`, into the window's location list" })

return M
