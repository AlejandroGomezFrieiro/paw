-- Groups of tracks: a track that others belong to, as the strings of an
-- orchestra belong to "Strings". The members sound through the group (their
-- output is the group, so its fader, mute and devices act on all of them),
-- are drawn under it, a step in, and can be folded away into it.
--
--   local strings = paw.groups.make({ violins, violas, cellos }, "Strings")
--   paw.groups.fold(strings, true)
--   paw.groups.add(basses, strings)
--   paw.groups.remove(violas)
--
-- A group is an ordinary track marked in its `meta`, and each member names
-- its group in its own, so groups are saved, undone and copied with the
-- tracks. Groups may hold groups. Whether a group is folded is view state
-- of each window (paw/folds.tl), not of the project.
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

--- A track: its id, or the track itself (`paw.track`).
local type TrackRef = integer | contracts.TrackHandle

--- What this module keeps in a track's `meta`: on a group `group_head`
--- and `group_link`; on a member its group's id.
local record Marks
  group_head: boolean
  group_link: boolean
  group: integer
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
  tracks: function(): {integer}
end
local record Paw is partial.Paw
  lanes: LanesModule
  vca: VcaModule
  scope: Scope
  folds: FoldsModule
  cursor: CursorModule
  add_track: function(opts?: objects.TrackInput): objects.Track
end
local paw = (_G as {string: Paw}).paw

local record M
  type TrackRef = TrackRef
  rows: function(): {integer}
  gather: function(group: integer)
end

local volumes: {integer: number} = {}

local function id_of(track: TrackRef): integer
  if track is contracts.TrackHandle then
    return track.id
  end
  return track
end

-- One entry of a track: quicker than the whole track, which lists its clips (api.rs).
local track_meta = api.track_get as function(integer, string): types.Meta
local track_integer = api.track_get as function(integer, string): integer
local track_number = api.track_get as function(integer, string): number

local function meta(id: integer): Marks
  local ok, m = pcall(track_meta, id, "meta")
  return ok and m as Marks or {}
end

local function set_meta(id: integer, m: Marks)
  api.track_set(id, {meta = m as types.Meta})
end

-- Where a track sounds: a table of changes cannot say "the master" (nil),
-- the key form can.
local function set_output(id: integer, output: integer)
  if output == nil then
    api.track_set(id, "output", nil)
  else
    api.track_set(id, {output = output})
  end
end

-- `track_get(id, "id")`: one field, which fails when the track is gone,
-- without the list of clips that the whole track has.
local track_id_of = api.track_get as function(integer, string): integer

--- True if a track is a group.
function M.is_group(track: TrackRef): boolean
  return meta(id_of(track)).group_head == true
end

--- The group a track belongs to (its id), or nil.
function M.of(track: TrackRef): integer
  local group = meta(id_of(track)).group
  if group and pcall(track_id_of, group, "id") and M.is_group(group) then
    return group
  end
end

--- The tracks that belong to a group, in the order of the track list.
function M.members(group: TrackRef): {integer}
  local gid = id_of(group)
  local out: {integer} = {}
  for _, id in ipairs(api.track_list({all = true})) do
    if M.of(id) == gid then
      out[#out + 1] = id
    end
  end
  return out
end

--- How many groups a track is inside.
function M.depth(track: TrackRef): integer
  local depth, at = 0, M.of(track)
  while at and depth < 16 do
    depth, at = depth + 1, M.of(at)
  end
  return depth
end

--- True if the tracks of a group are folded and hidden, in the window a
--- view shows (paw/folds.tl).
function M.folded(group: TrackRef): boolean
  return paw.folds ~= nil and paw.folds.group_closed(id_of(group))
end

--- True if a track is hidden: inside a folded group. Inside group `top`
--- (the group of a narrowed tab), only the groups inside it count. `top`
--- itself is open there.
function M.hidden(track: TrackRef, top?: integer): boolean
  if top and id_of(track) == top then
    return false
  end
  local at, steps = M.of(track), 0
  while at and at ~= top and steps < 16 do
    if M.folded(at) then
      return true
    end
    at, steps = M.of(at), steps + 1
  end
  return false
end

--- The tracks that are drawn, in order: all but those folded away in the
--- window (`paw.folds`), and in a scope only those of the scope (`paw.scope`). Rows of the
--- arrange view and of a graphical frontend are places in this list.
--- With `{ lanes = true }`, every row: `{ track = id }` for a track and
--- `{ track = id, lane = id }` for an automation lane shown under it
--- (see `paw.lanes`).
local function rows(opts?: RowOptions): {integer}
  if opts and opts.lanes then
    return paw.lanes.lines() as {integer}
  end
  local out, vcas: {integer}, {integer} = {}, {}
  local scope = paw.scope and paw.scope.group()
  for _, id in ipairs(paw.scope and paw.scope.tracks() or api.track_list()) do
    if not M.hidden(id, scope) then
      -- VCAs come after the tracks they move.
      local list = paw.vca.is_vca(id) and vcas or out
      list[#list + 1] = id
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
  for i, other in ipairs(api.track_list({all = true})) do
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
    -- Moving a track from above the group shifts the group up by one.
    if from < at then
      api.track_move(id, at)
    else
      at = at + 1
      if from ~= at then
        api.track_move(id, at)
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

--- Put a track into a group: it then sounds through the group, unless it
--- was sent somewhere of its own.
function M.add(track: TrackRef, group: TrackRef)
  local tid, gid = id_of(track), id_of(group)
  if tid == gid or not M.is_group(gid) then
    error("not a group", 2)
  end
  -- A group cannot go inside itself.
  local at = gid
  while at do
    if at == tid then
      error("a group cannot be put inside itself", 2)
    end
    at = M.of(at)
  end
  local t = api.track_get(tid)
  local old = M.of(tid)
  if t.output == nil or t.output == old then
    set_output(tid, gid)
  end
  local m = meta(tid)
  m.group = gid
  set_meta(tid, m)
  gather(gid)
end

--- Remove a track from its group, up one level. It sounds where the group
--- sounds, and it is in the parent group of the group, if any. It moves out
--- of the rows of the group, unless `stay`.
function M.remove(track: TrackRef, stay?: boolean): boolean
  local tid = id_of(track)
  local group = M.of(tid)
  if not group then
    return false
  end
  if track_integer(tid, "output") == group then
    set_output(tid, track_integer(group, "output"))
  end
  local m = meta(tid)
  m.group = M.of(group)
  set_meta(tid, m)
  -- Out of the group's block of rows: after its last member.
  local members = M.members(group)
  local last = position(members[#members] or group)
  if not stay and position(tid) < last then
    api.track_move(tid, last)
  end
  return true
end

--- A new group that contains `tracks` (ids or tracks), above the first of
--- them. Returns the track of the group.
function M.make(tracks?: {TrackRef}, name?: string): contracts.TrackHandle
  local ids: {integer} = {}
  for i, track in ipairs(tracks or {}) do
    ids[i] = id_of(track)
  end
  local first: integer
  for _, id in ipairs(ids) do
    local at = position(id)
    if at and (not first or at < first) then
      first = at
    end
  end
  local group = paw.add_track({name = name or "Group", index = first})
  local gm = meta(group.id)
  gm.group_head = true
  set_meta(group.id, gm)
  -- Tracks that were together in a group stay in it, one level down.
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
function M.dissolve(group: TrackRef): boolean
  local gid = id_of(group)
  if not M.is_group(gid) then
    return false
  end
  local outer = M.of(gid)
  for _, id in ipairs(M.members(gid)) do
    if track_integer(id, "output") == gid then
      set_output(id, track_integer(gid, "output"))
    end
    local m = meta(id)
    m.group = outer
    set_meta(id, m)
  end
  local t = api.track_get(gid)
  if #t.clips == 0 and #t.devices == 0 then
    api.track_remove(gid)
  else
    local m = meta(gid)
    m.group_head = nil
    set_meta(gid, m)
  end
  return true
end

--- Fold a group away, or open it, in the current window: `on` nil flips
--- it. View state: no undo step (paw/folds.tl).
function M.fold(group: TrackRef, on?: boolean)
  paw.folds.set_group(id_of(group), on)
end

--- Note the faders of a group's members: linked faders move by what they
--- have moved since.
local function note(group: integer)
  for _, id in ipairs(M.members(group)) do
    volumes[id] = track_number(id, "volume")
  end
end

--- True if the faders of the members of a group are linked. When one moves,
--- the others move by the same number of dB. This is separate from the
--- routing, which a group also has.
function M.linked(group: TrackRef): boolean
  return meta(id_of(group)).group_link == true
end

--- Link the faders of a group's members, or let them go: `on` nil flips it.
function M.link(group: TrackRef, on?: boolean)
  local gid = id_of(group)
  if not M.is_group(gid) then
    error("not a group", 2)
  end
  if on == nil then
    on = not M.linked(gid)
  end
  local m = meta(gid)
  m.group_link = on and true or nil
  set_meta(gid, m)
  note(gid)
end

events.on(
  events.pattern("track.*"),
  function(payload: events.Payload, name: string)
    local event = payload as kernel.TrackId
    local group = event.id and M.of(event.id)
    if not group or not M.linked(group) then
      return
    end
    -- Undo, redo and opening a project restore every fader themselves.
    if event.restored or name == "track.added" then
      return note(group)
    end
    if name ~= "track.changed" then
      return
    end
    local now = track_number(event.id, "volume")
    local before = volumes[event.id]
    volumes[event.id] = now
    if before == nil or before == now then
      return
    end
    for _, id in ipairs(M.members(group)) do
      if id ~= event.id then
        local was = volumes[id] or track_number(id, "volume")
        volumes[id] = util.clamp(was + now - before, -120, 24)
        api.track_set(id, {volume = volumes[id]})
      end
    end
  end
)

-- A group that is removed lets its members go: they keep sounding, on the
-- master, and stand at the top level.
events.on(
  kernel.track_removed,
  function(event: kernel.TrackId)
    if event.restored then
      return
    end
    for _, id in ipairs(api.track_list({all = true})) do
      local m = meta(id)
      if m.group == event.id then
        m.group = nil
        set_meta(id, m)
      end
    end
  end
)

return M
