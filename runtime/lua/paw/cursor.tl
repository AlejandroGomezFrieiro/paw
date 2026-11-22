-- The edit cursor: a track and a position in beats. Commands act on it and
-- views draw it. It survives a reload.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local util = require("paw.util")
local options = require("paw.options")
local type objects = require("paw.objects")
local type partial = require("paw.partial")
local type SeatsModule = require("paw.seats")
local type types = require("paw.types")

--- Where the cursor is: the payload of `cursor.changed`, and what it keeps
--- over a reload. `track` is 0 on the master; `lane` is the lane row it
--- is on, if any.
local record Place
  track: integer
  beat: number
  lane: integer
end

--- A row of the arrange view (`paw.groups.rows({ lanes = true })`): a
--- track, or a lane shown under it.
local record Row
  track: integer
  lane: integer
end

--- What `paw.groups.rows` takes.
local record RowsOptions
  lanes: boolean
end

-- What this module reads of `paw`, which paw/init.lua makes: the parts of
-- the modules in Lua that their doc comments type, and the rest here.
local record Groups
  rows: function(): {integer}
  rows: function(opts: RowsOptions): {Row}
end
local record Lanes
  any_open: function(): boolean
  shown: function(track: integer): {types.Lane}
end
-- paw/ui.tl names this module's types (through paw/layout.tl and
-- paw/commands.tl), so this one declares only the part of it that it reads.
local record Ui
  focused: string
end
local record Paw is partial.Paw
  ui: Ui
  seats: SeatsModule
  groups: Groups
  lanes: Lanes
  track: function(which: number | string): objects.Track
end
local paw = (_G as {string: Paw}).paw

local record M
  type Place = Place
  --- The event `cursor.changed`: the cursor moved, or another seat's did.
  changed: events.Event<Place>
  --- The beat of the cursor.
  beat: number
  lens: function(): integer
  bounds: function(): number, number
  over: function(old: number, new: number): number
  shift: function(track: integer): number
  master_reachable: function(): boolean
end

M.beat = 0
M.changed = events.event("cursor.changed")

local track_id: integer
local lane_id: integer -- the automation lane row the cursor is on, if any
do
  local saved = api.state_get("cursor") as Place
  if saved then
    track_id, M.beat, lane_id = saved.track, saved.beat or 0, saved.lane
  end
end

-- Each seat has a cursor of its own, starting where the instance's is.
paw.seats.keep(
  "cursor",
  function(): number... return track_id, M.beat, lane_id end,
  function(track: number, beat: number, lane: number)
    track_id, M.beat, lane_id = track as integer, beat, lane as integer
  end,
  function(track: number, beat: number, lane: number): number... return track, beat or 0, lane end
)

local function save()
  -- The instance's own is the one that outlives a reload.
  if paw.seats.current == 0 then
    api.state_set("cursor", {track = track_id, beat = M.beat, lane = lane_id} as Place)
  end
  events.emit(M.changed, {track = track_id, beat = M.beat, lane = lane_id})
  api.ui_redraw()
end

--- A function that gives the track that keys and commands act on in
--- place of the cursor's, or nil: a device panel pinned to a track
--- (paw/views/devices.lua) sets it, for while its window has the keyboard.
M.lens = nil

-- `track_get(id, "id")`: one field, which fails when the track is gone,
-- without the list of clips that the whole track has. `track_id` runs
-- many times in each frame.
local track_id_of = api.track_get as function(integer, string): integer

--- The id of the track of the cursor, or of the first track when that track
--- does not exist now. Nil when the project has no tracks. 0 when the
--- cursor is on the master track (`on_master`).
function M.track_id(): integer
  local lens = M.lens and M.lens()
  if lens then
    return lens
  end
  if track_id == 0 then
    return 0
  end
  if track_id and pcall(track_id_of, track_id, "id") then
    return track_id
  end
  track_id = api.track_list()[1]
  return track_id
end

--- True if the cursor is on the master track: the row after the last
--- track in the arrange view, the strip after the last in the mixer.
function M.on_master(): boolean
  return track_id == 0
end

--- True if a move of the cursor can go on from the last track to the
--- master: a move of its own in normal mode, in the views that draw the
--- master after the tracks. After an operator or in a selection, only
--- tracks count.
local function master_reachable(): boolean
  local keymap = paw.keymap
  return keymap.mode == "n" and not keymap.motion_for and (paw.ui.focused == "arrange" or paw.ui.focused == "mixer")
end
M.master_reachable = master_reachable

--- The track the cursor is on, as a `paw.Track`, or nil.
function M.track(): objects.Track
  local id = M.track_id()
  return id and paw.track(id) or nil
end

local nest_field = api.track_get as function(id: integer, key: string): integer

--- 1-based position of the cursor track among the tracks of its place:
--- the song's, or its subproject's (as `paw.api.track_move` counts).
function M.index(): integer
  local id = M.track_id()
  local ok, nest = pcall(nest_field, id, "nest") as (boolean, integer)
  for i, other in ipairs(api.track_list({nest = ok and nest or nil})) do
    if other == id then
      return i
    end
  end
end

--- 1-based row of the cursor track among the tracks that are drawn: the
--- same as `index` until a group is folded. On the master, the row after
--- the last track.
function M.row(): integer
  local id = M.track_id()
  if id == 0 then
    return #paw.groups.rows() + 1
  end
  for i, other in ipairs(paw.groups.rows()) do
    if other == id then
      return i
    end
  end
end

--- The automation lane row of the cursor: a lane of the cursor track that
--- shows as a row (see `paw.lanes`). Nil when the cursor is on the track.
function M.lane_id(): integer
  if not lane_id then
    return nil
  end
  local id = M.track_id()
  for _, lane in ipairs(id and paw.lanes.shown(id) or {}) do
    if lane.id == lane_id then
      return lane_id
    end
  end
end

--- 1-based row of the cursor among every row drawn, lanes included.
function M.line(): integer
  local id, lane = M.track_id(), M.lane_id()
  for i, line in ipairs(paw.groups.rows({lanes = true})) do
    if line.track == id and line.lane == lane then
      return i
    end
  end
end

--- Put the cursor on a track, or with `lane` on one of its lane rows.
function M.set_track(track: integer | objects.Track, lane?: integer)
  track_id = track is objects.Track and track.id or track as integer
  lane_id = lane
  save()
end

--- Move by rows. In normal mode, the rows of open automation lanes count.
--- After an operator or in a selection, only tracks count, as for `dj`.
--- From the last track, a move down goes on to the master, and from the
--- master a move up returns to the tracks.
function M.move_track(delta: integer)
  local reach = master_reachable()
  if paw.lanes.any_open() and paw.keymap.mode == "n" then
    local lines = paw.groups.rows({lanes = true})
    if #lines == 0 then
      return
    end
    local at = M.on_master() and #lines + 1 or (M.line() or 1)
    if reach and at + delta > #lines then
      return M.set_track(0)
    end
    local to = lines[util.clamp(at + delta, 1, #lines) as integer]
    return M.set_track(to.track, to.lane)
  end
  local list = paw.groups.rows()
  if #list == 0 then
    return
  end
  local at = M.row() or 1
  if reach and at + delta > #list then
    return M.set_track(0)
  end
  M.set_track(list[util.clamp(at + delta, 1, #list) as integer])
end

--- A function that gives the time the cursor stays in, `from, to` in beats,
--- or nil for all of it: paw/scope.tl sets it, for the scope shown.
M.bounds = nil

--- A function that gives where the cursor goes when it moves from one
--- beat to another: paw/folds.tl sets it, so that the cursor takes a
--- folded span as one step and stays on its column.
M.over = nil

--- Put the cursor at a beat (not before 0, and in the scope's time).
function M.set_beat(beat: number)
  beat = math.max(0, beat)
  local from, to: number, number
  if M.bounds then
    from, to = M.bounds()
  end
  if from then
    beat = math.min(math.max(beat, from), to)
  end
  if M.over then
    beat = M.over(M.beat, beat)
  end
  M.beat = beat
  save()
end

-- Another project starts at its start, on its first track.
events.on(kernel.project_loaded, function() track_id, lane_id, M.beat = nil, nil, 0; save() end)

--- Round a position to the arrange grid.
function M.snap(beat: number): number
  return util.round(beat, options.opt.grid)
end

--- A function that gives, for a track whose clips the window draws later
--- than their beats, how much later; or nil: paw/nest.tl sets it, for the
--- tracks of a subproject open in place under its return row.
M.shift = nil

--- The clip under the cursor, if any.
function M.clip(): objects.Clip
  local track = M.track()
  if not track then
    return nil
  end
  local shift = M.shift and M.shift(track.id) or 0
  return track:clip_at(M.beat - shift)
end

return M
