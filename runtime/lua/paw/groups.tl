-- Groups of parts: a part that others belong to, as the strings of an
-- orchestra belong to "Strings". The members sound through the group (their
-- output is the group, so its fader, mute and devices act on all of them),
-- are drawn under it, a step in, and can be folded away into it.
--
--   local strings = paw.groups.make({ violins, violas, cellos }, "Strings")
--   paw.groups.fold(strings, true)
--   paw.groups.add(basses, strings)
--   paw.groups.remove(violas)
--
-- A group is a full part (clips, lanes, devices) marked in its `meta`
-- (`group_head`, a key that this module declares with `paw.meta.define`),
-- and each member names its group in its field `parent`, so groups are
-- saved, undone and copied with the parts. Groups hold groups to any
-- depth, and the kernel refuses a move that puts a group inside itself.
-- Whether a group is folded is view state of each window
-- (paw/folds.tl), not of the project.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local util = require("paw.util")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type LanesModule = require("paw.lanes")
local type VcaModule = require("paw.vca")
local type objects = require("paw.objects")
local type FoldsModule = require("paw.folds")
local type CursorModule = require("paw.cursor")

--- A part: its id, or the part itself (`paw.part`).
local type PartRef = integer | contracts.PartHandle

--- What this module keeps in a part's `meta`: on a group `group_head`
--- and `group_link`.
local record Marks
  group_head: boolean
  group_link: boolean
end

--- What `rows` takes in Lua: `{ lanes = true }` gives the rows of
--- `paw.lanes.lines()`, which Teal calls itself.
local record RowOptions
  lanes: boolean
end

-- What this module reads of `paw`, which paw/init.lua makes.
-- paw/scope.tl names this module's types, so this one declares only the
-- part of it that it reads.
local record Scope
  group: function(): integer
  parts: function(): {integer}
end
local record Paw is partial.Paw
  lanes: LanesModule
  vca: VcaModule
  scope: Scope
  folds: FoldsModule
  cursor: CursorModule
  add_part: function(opts?: objects.PartInput): objects.Part
end
local paw = (_G as {string: Paw}).paw

local record M
  type PartRef = PartRef
  rows: function(): {integer}
  gather: function(group: integer)
  --- The parts to draw under a row besides its group's members, or nil:
  --- paw/nest.tl sets it, for a return row whose subproject is open in place.
  under: function(row: integer): {integer}
end

local volumes: {integer: number} = {}

local function id_of(part: PartRef): integer
  if part is contracts.PartHandle then
    return part.id
  end
  return part
end

-- One entry of a part: quicker than the whole part, which lists its clips (api.rs).
local part_meta = api.part_get as function(integer, string): types.Meta
local part_integer = api.part_get as function(integer, string): integer
local part_number = api.part_get as function(integer, string): number

-- What the kernel says of a part's marks: an empty table for a part
-- that is not there.
local function read_marks(id: integer): Marks
  local ok, m = pcall(part_meta, id, "meta")
  return ok and m as Marks or {}
end

-- The marks and the group of each part that was asked for, kept until the
-- project or an event changes. A frame asks for them many times for each
-- part drawn (the rows, the headers, the tree of the part column), and
-- each read is a call into the kernel. The key is `paw.events.stamp()`,
-- as for the kept windows of the screen and the regions of paw/scope.tl.
-- The tables are only read: a change starts from `read_marks`.
-- In `kept_group`, a part in no group: no part has a negative id.
local NO_GROUP = -1
local kept_marks: {integer: Marks} = {}
local kept_group: {integer: integer} = {}
local kept_stamp = -1

local function keep_current()
  local now = events.stamp()
  if now ~= kept_stamp then
    kept_marks, kept_group, kept_stamp = {}, {}, now
  end
end

local function meta(id: integer): Marks
  keep_current()
  local m = kept_marks[id]
  if not m then
    m = read_marks(id)
    kept_marks[id] = m
  end
  return m
end

local function set_meta(id: integer, m: Marks)
  api.part_set(id, {meta = m as types.Meta})
end

-- Where a part sounds: a table of changes cannot say "the master" (nil),
-- the key form can.
local function set_output(id: integer, output: integer)
  if output == nil then
    api.part_set(id, "output", nil)
  else
    api.part_set(id, {output = output})
  end
end

-- `part_get(id, "id")`: one field, which fails when the part is gone,
-- without the list of clips that the whole part has.
local part_id_of = api.part_get as function(integer, string): integer

--- True if a part is a group.
function M.is_group(part: PartRef): boolean
  return meta(id_of(part)).group_head == true
end

--- The group a part belongs to (its id), or nil.
function M.of(part: PartRef): integer
  local id = id_of(part)
  keep_current()
  local kept = kept_group[id]
  if kept == nil then
    local ok, group = pcall(part_integer, id, "parent") as (boolean, integer)
    -- A member keeps the id of a group that is no longer a group.
    if ok and group and pcall(part_id_of, group, "id") and M.is_group(group) then
      kept = group
    else
      kept = NO_GROUP
    end
    kept_group[id] = kept
  end
  if kept ~= NO_GROUP then
    return kept
  end
end

--- The parts that belong to a group, in the order of the part list.
function M.members(group: PartRef): {integer}
  local gid = id_of(group)
  local out: {integer} = {}
  for _, id in ipairs(api.part_list({all = true})) do
    if M.of(id) == gid then
      out[#out + 1] = id
    end
  end
  return out
end

--- The groups that a part is inside, the nearest first. The kernel keeps
--- the groups from a cycle, and the walk stops at one that a file brought.
local function around(part: PartRef): {integer}
  local out: {integer} = {}
  local seen: {integer: boolean} = {}
  local at = M.of(part)
  while at and not seen[at] do
    seen[at] = true
    out[#out + 1] = at
    at = M.of(at)
  end
  return out
end

--- How many groups a part is inside.
function M.depth(part: PartRef): integer
  return #around(part)
end

--- True if the parts of a group are folded and hidden, in the window a
--- view shows (paw/folds.tl).
function M.folded(group: PartRef): boolean
  return paw.folds ~= nil and paw.folds.group_closed(id_of(group))
end

--- The subproject a part is in, or nil for a part of the song.
local part_nest = api.part_get as function(integer, string): integer
local function place_of(id: integer): integer
  local ok, nest = pcall(part_nest, id, "nest") as (boolean, integer)
  return ok and nest or nil
end

--- The group that a new part goes into when it is added next to `part`
--- (`o`, `O`, `:nest.new`): below an open group's own row, that group;
--- else the group of `part`. Nil at the top level, and for a group in
--- another place (a subproject) than `part`.
function M.home(part: PartRef, above?: boolean): integer
  local id = id_of(part)
  local group = M.of(id)
  if not above and M.is_group(id) and not M.folded(id) then
    group = id
  end
  if group and place_of(group) == place_of(id) then
    return group
  end
end

--- True if a part is hidden: inside a folded group. Inside group `top`
--- (the group of a narrowed window), only the groups inside it count. `top`
--- itself is open there.
function M.hidden(part: PartRef, top?: integer): boolean
  if top and id_of(part) == top then
    return false
  end
  for _, at in ipairs(around(part)) do
    if at == top then
      return false
    end
    if M.folded(at) then
      return true
    end
  end
  return false
end

--- The parts that are drawn, in order: all but those folded away in the
--- window (`paw.folds`), and in a scope only those of the scope (`paw.scope`). Rows of the
--- arrange view and of a graphical frontend are places in this list.
--- With `{ lanes = true }`, every row: `{ part = id }` for a part and
--- `{ part = id, lane = id }` for an automation lane shown under it
--- (see `paw.lanes`).
local function rows(opts?: RowOptions): {integer}
  if opts and opts.lanes then
    return paw.lanes.lines() as {integer}
  end
  local out, vcas: {integer}, {integer} = {}, {}
  local scope = paw.scope and paw.scope.group()
  for _, id in ipairs(paw.scope and paw.scope.parts() or api.part_list()) do
    if not M.hidden(id, scope) then
      -- VCAs come after the parts they move.
      local list = paw.vca.is_vca(id) and vcas or out
      list[#list + 1] = id
      local extra = M.under and M.under(id)
      if extra then
        for _, inner in ipairs(extra) do
          list[#list + 1] = inner
        end
      end
    end
  end
  for _, id in ipairs(vcas) do
    out[#out + 1] = id
  end
  return paw.folds and paw.folds.collapse(out) or out
end
-- Teal sees the form without options; it calls `paw.lanes.lines()` for the rows with lanes.
M.rows = rows as function(): {integer}

local function position(id: integer): integer
  for i, other in ipairs(api.part_list({all = true})) do
    if other == id then
      return i
    end
  end
end

--- Put a group's members right under it, in the order they are in.
local function gather(group: integer)
  local at = position(group)
  for _, id in ipairs(M.members(group)) do
    local from = position(id)
    -- Moving a part from above the group shifts the group up by one.
    if from < at then
      api.part_move(id, at)
    else
      at = at + 1
      if from ~= at then
        api.part_move(id, at)
      end
    end
    -- A member that is a group brings its own members along.
    if M.is_group(id) then
      gather(id)
      at = position(id) + #M.members(id)
    else
      at = position(id)
    end
  end
end
M.gather = gather

--- Put a part into its group `group`, or at the top level (nil).
local function set_parent(id: integer, group: integer)
  if group == nil then
    api.part_set(id, "parent", nil)
  else
    api.part_set(id, {parent = group})
  end
end

--- Put a part into a group: it then sounds through the group, unless it
--- was sent somewhere of its own. A group cannot go inside itself, nor
--- inside a group that it holds: the error says so.
function M.add(part: PartRef, group: PartRef)
  local tid, gid = id_of(part), id_of(group)
  if tid ~= gid and not M.is_group(gid) then
    error("not a group", 2)
  end
  local old = M.of(tid)
  local ok, err = pcall(set_parent, tid, gid) as (boolean, string)
  if not ok then
    error((tostring(err):gsub("^[^:]*:%d+: ", ""):gsub("^runtime error: ", "")), 2)
  end
  local t = api.part_get(tid)
  if t.output == nil or t.output == old then
    set_output(tid, gid)
  end
  gather(gid)
end

--- Remove a part from its group, up one level. It sounds where the group
--- sounds, and it is in the parent group of the group, if any. It moves out
--- of the rows of the group, unless `stay`.
function M.remove(part: PartRef, stay?: boolean): boolean
  local tid = id_of(part)
  local group = M.of(tid)
  if not group then
    return false
  end
  if part_integer(tid, "output") == group then
    set_output(tid, part_integer(group, "output"))
  end
  set_parent(tid, M.of(group))
  -- Out of the group's block of rows: after its last member.
  local members = M.members(group)
  local last = position(members[#members] or group)
  if not stay and position(tid) < last then
    api.part_move(tid, last)
  end
  return true
end

--- A new group that contains `parts` (ids or parts), above the first of
--- them. Returns the part of the group.
function M.make(parts?: {PartRef}, name?: string): contracts.PartHandle
  local ids: {integer} = {}
  for i, part in ipairs(parts or {}) do
    ids[i] = id_of(part)
  end
  local first: integer
  for _, id in ipairs(ids) do
    local at = position(id)
    if at and (not first or at < first) then
      first = at
    end
  end
  local group = paw.add_part({name = name or "Group", index = first})
  local gm = read_marks(group.id)
  gm.group_head = true
  set_meta(group.id, gm)
  -- Parts that were together in a group stay in it, one level down.
  local outer = ids[1] and M.of(ids[1])
  local same = outer ~= nil
  for _, id in ipairs(ids) do
    same = same and M.of(id) == outer
  end
  if same and outer then
    M.add(group.id, outer)
  end
  for _, id in ipairs(ids) do
    M.add(id, group.id)
  end
  return group
end

--- Undo a group: its members go up a level and the group, if it holds
--- nothing of its own (no clips, no devices), goes away.
function M.dissolve(group: PartRef): boolean
  local gid = id_of(group)
  if not M.is_group(gid) then
    return false
  end
  local outer = M.of(gid)
  for _, id in ipairs(M.members(gid)) do
    if part_integer(id, "output") == gid then
      set_output(id, part_integer(gid, "output"))
    end
    set_parent(id, outer)
  end
  local t = api.part_get(gid)
  if #t.clips == 0 and #t.devices == 0 then
    api.part_remove(gid)
  else
    local m = read_marks(gid)
    m.group_head = nil
    set_meta(gid, m)
  end
  return true
end

--- Fold a group away, or open it, in the current window: `on` nil flips
--- it. View state: no undo step (paw/folds.tl).
function M.fold(group: PartRef, on?: boolean)
  paw.folds.set_group(id_of(group), on)
end

--- Note the faders of a group's members: linked faders move by what they
--- have moved since.
local function note(group: integer)
  for _, id in ipairs(M.members(group)) do
    volumes[id] = part_number(id, "volume")
  end
end

--- True if the faders of the members of a group are linked. When one moves,
--- the others move by the same number of dB. This is separate from the
--- routing, which a group also has.
function M.linked(group: PartRef): boolean
  return meta(id_of(group)).group_link == true
end

--- Link the faders of a group's members, or let them go: `on` nil flips it.
function M.link(group: PartRef, on?: boolean)
  local gid = id_of(group)
  if not M.is_group(gid) then
    error("not a group", 2)
  end
  if on == nil then
    on = not M.linked(gid)
  end
  local m = read_marks(gid)
  m.group_link = on and true or nil
  set_meta(gid, m)
  note(gid)
end

events.on(
  events.pattern("part.*"),
  function(payload: events.Payload, name: string)
    -- A removed part has no group to read: the read would only fail.
    if name == "part.removed" then
      return
    end
    local event = payload as kernel.PartId
    local group = event.id and M.of(event.id)
    if not group or not M.linked(group) then
      return
    end
    -- Undo, redo and opening a project restore every fader themselves.
    if event.restored or name == "part.added" then
      return note(group)
    end
    if name ~= "part.changed" then
      return
    end
    local now = part_number(event.id, "volume")
    local before = volumes[event.id]
    volumes[event.id] = now
    if before == nil or before == now then
      return
    end
    for _, id in ipairs(M.members(group)) do
      if id ~= event.id then
        local was = volumes[id] or part_number(id, "volume")
        volumes[id] = util.clamp(was + now - before, -120, 24)
        api.part_set(id, {volume = volumes[id]})
      end
    end
  end
)

-- A group that is removed lets its members go: the kernel puts them at the
-- top level, and they sound on the master.

return M
