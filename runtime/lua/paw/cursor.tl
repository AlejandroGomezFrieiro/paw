-- The edit cursor: a track and a position. Commands act on it and views
-- draw it. It survives a reload.
--
-- The position is a whole number of ticks (paw/timegrid.tl): `tick`, and
-- `want`, the tick that the last move of time asked for, which a bound
-- (the scope, a fold) can keep the cursor from. `beat` is the tick in
-- beats, for the API: a beat set from outside becomes a tick once, here.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local util = require("paw.util")
local timegrid = require("paw.timegrid")
local type objects = require("paw.objects")
local type partial = require("paw.partial")
local type KeymapModule = require("paw.keymap")
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
  keymap: KeymapModule
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
  --- The beat of the cursor: its tick in beats. A beat set here becomes
  --- the nearest tick.
  beat: number
  --- The position of the cursor in ticks (read only: `set_tick` sets it).
  tick: integer
  --- The tick that the last move of time asked for: a move by rows keeps
  --- it when a bound kept the cursor from it.
  want: integer
  lens: function(): integer
  over: function(old: number, new: number): number
  stop: function(track: integer, beat: number): integer
  shift: function(track: integer, beat: number): number
  master_reachable: function(): boolean
end

M.changed = events.event("cursor.changed")

local track_id: integer
local lane_id: integer -- the automation lane row the cursor is on, if any
local tick, want = 0, 0

-- `beat`, `tick` and `want` are read through the module's metatable, so
-- that the tick is the one truth. A write of `beat` (a test, an old
-- caller) puts the cursor at the nearest tick, as `set_beat` does, but
-- with no bound and no event.
setmetatable(
  M,
  {
    __index = function(_: M, key: string): number
      if key == "beat" then
        return timegrid.beat(tick)
      elseif key == "tick" then
        return tick
      elseif key == "want" then
        return want
      end
    end,
    __newindex = function(self: M, key: string, value: number)
      if key == "beat" then
        tick = timegrid.tick(value)
        want = tick
      else
        rawset(self as {string: number}, key, value)
      end
    end,
  } as metatable<M>
)

do
  local saved = api.state_get("cursor") as Place
  if saved then
    track_id, tick, lane_id = saved.track, timegrid.tick(saved.beat or 0), saved.lane
    want = tick
  end
end

-- Each seat has a cursor of its own, starting where the instance's is.
paw.seats.keep(
  "cursor",
  function(): number... return track_id, tick, lane_id, want end,
  function(track: number, at: number, lane: number, wanted: number)
    track_id, tick, lane_id, want = track as integer, at as integer, lane as integer, (wanted or at) as integer
  end,
  function(track: number, at: number, lane: number, wanted: number): number...
    return track, at or 0, lane, wanted or at or 0
  end
)

local function save()
  local beat = timegrid.beat(tick)
  -- The instance's own is the one that outlives a reload.
  if paw.seats.current == 0 then
    api.state_set("cursor", {track = track_id, beat = beat, lane = lane_id} as Place)
  end
  events.emit(M.changed, {track = track_id, beat = beat, lane = lane_id})
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

--- A function that gives the row that stands for a track at a beat for a
--- move by rows, or nil when the track is its own row: paw/folds.tl sets
--- it, so that a closed block fold is one row for `j` and `k`.
M.stop = nil

--- The row that stands for a track in a move by rows (`M.stop`), or nil
--- when the track and its lane rows are rows of their own. After an
--- operator, every track is its own row, as an operator acts on tracks.
local function stop_of(track: integer): integer
  if not M.stop or paw.keymap.motion_for then
    return nil
  end
  return M.stop(track, M.beat)
end

--- The rows a move by rows stops on: a row that stands for others once,
--- in place of them and of their lane rows.
local function stops(lines: {Row}): {Row}
  local out: {Row} = {}
  for _, line in ipairs(lines) do
    local stop = stop_of(line.track)
    local last = out[#out]
    if not stop then
      out[#out + 1] = line
    elseif not (last and last.track == stop and last.lane == nil) then
      out[#out + 1] = {track = stop}
    end
  end
  return out
end

--- Move by rows. In normal mode, the rows of open automation lanes count.
--- After an operator or in a selection, only tracks count, as for `dj`.
--- From the last track, a move down goes on to the master, and from the
--- master a move up returns to the tracks. A closed block fold at the
--- cursor's beat is one row (`paw.cursor.stop`).
function M.move_track(delta: integer)
  local reach = master_reachable()
  local lanes = paw.lanes.any_open() and paw.keymap.mode == "n"
  local lines: {Row}
  if lanes then
    lines = paw.groups.rows({lanes = true})
  else
    lines = {}
    for i, id in ipairs(paw.groups.rows()) do
      lines[i] = {track = id}
    end
  end
  lines = stops(lines)
  if #lines == 0 then
    return
  end
  -- Where the cursor is among the stops: on the master after the last,
  -- on the row that stands for its own.
  local id, lane = M.track_id(), lanes and M.lane_id() or nil
  local stop = stop_of(id)
  if stop then
    id, lane = stop, nil
  end
  local at: integer
  if M.on_master() then
    at = #lines + 1
  else
    for i, line in ipairs(lines) do
      if line.track == id and line.lane == lane then
        at = i
        break
      end
    end
  end
  at = at or 1
  if reach and at + delta > #lines then
    return M.set_track(0)
  end
  local to = lines[util.clamp(at + delta, 1, #lines) as integer]
  M.set_track(to.track, to.lane)
end

--- A function that gives where the cursor goes when it moves from one
--- beat to another: paw/folds.tl sets it, so that the cursor takes a
--- folded span as one step and stays on its column.
M.over = nil

--- Put the cursor at a tick: not before 0, in the scope's time
--- (`paw.timegrid.bounds`), and over a fold as one step (`over`). `want`
--- becomes the tick asked for. A tick with a fraction is an error in the
--- tests, and is rounded else.
function M.set_tick(at: integer)
  at = timegrid.checked(at, "cursor.set_tick")
  want = at
  at = math.max(0, at)
  local from, to: number, number
  if timegrid.bounds then
    from, to = timegrid.bounds()
  end
  if from then
    at = math.min(math.max(at, timegrid.tick(from)), timegrid.tick(to))
  end
  if M.over then
    at = timegrid.tick(M.over(timegrid.beat(tick), timegrid.beat(at)))
  end
  tick = at
  save()
end

--- Put the cursor at a beat: the nearest tick, as `set_tick`.
function M.set_beat(beat: number)
  M.set_tick(timegrid.tick(beat))
end

-- Another project starts at its start, on its first track.
events.on(kernel.project_loaded, function() track_id, lane_id, tick, want = nil, nil, 0, 0; save() end)

--- A position at the nearest line of the arrange grid.
function M.snap(beat: number): number
  local g = timegrid.window({bare = true})
  return timegrid.beat(g:nearest(timegrid.tick(beat)))
end

--- `beat` moved by `n` lines of the arrange grid (of a grid of `grid`
--- beats, when given), with the same offset after its line
--- (`paw.timegrid` `steps`). A beat on a line stays on one, a long run of
--- steps gives the exact beat, and a place between two lines (the end of
--- a take) keeps its distance from the line.
function M.step(beat: number, n: integer, grid?: number): number
  local g = timegrid.window({setting = grid, bare = true})
  return timegrid.beat(g:steps(timegrid.tick(beat), n))
end

--- A function that gives, for a track whose clips the window draws later
--- than their beats, how much later at a beat of the window; or nil:
--- paw/nest.tl sets it, for the tracks of a subproject open in place under
--- its return row (each block of the row draws them at its own place).
M.shift = nil

--- The clip under the cursor, if any.
function M.clip(): objects.Clip
  local track = M.track()
  if not track then
    return nil
  end
  local shift = M.shift and M.shift(track.id, M.beat) or 0
  return track:clip_at(M.beat - shift)
end

return M
