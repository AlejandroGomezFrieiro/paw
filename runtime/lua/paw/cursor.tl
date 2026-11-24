-- The edit cursor: a part and a position. Commands act on it and views
-- draw it. It survives a reload.
--
-- The position is a whole number of ticks (paw/timegrid.tl): `tick`, and
-- `want`, the tick where the last move of time landed, which a move by
-- rows keeps when a bound (the scope, a fold) took the cursor off it.
-- `beat` is the tick in beats, for the API: a beat set from outside becomes a tick once, here.
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
--- over a reload. `part` is 0 on the master; `lane` is the lane row it
--- is on, if any.
local record Place
  part: integer
  beat: number
  lane: integer
end

--- A row of the arrange view (`paw.groups.rows({ lanes = true })`): a
--- part, or a lane shown under it.
local record Row
  part: integer
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
  shown: function(part: integer): {types.Lane}
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
  part: function(which: number | string): objects.Part
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
  --- The tick where the last move of time landed: a move by rows keeps
  --- it when a bound took the cursor off it.
  want: integer
  set_tick: function(at: integer)
  lens: function(): integer
  over: function(old: number, new: number): number
  stop: function(part: integer, beat: number): integer
  shift: function(part: integer, beat: number): number
  master_reachable: function(): boolean
end

M.changed = events.event("cursor.changed")

local part_id: integer
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
    part_id, tick, lane_id = saved.part, timegrid.tick(saved.beat or 0), saved.lane
    want = tick
  end
end

-- Each seat has a cursor of its own, starting where the instance's is.
paw.seats.keep(
  "cursor",
  function(): number... return part_id, tick, lane_id, want end,
  function(part: number, at: number, lane: number, wanted: number)
    part_id, tick, lane_id, want = part as integer, at as integer, lane as integer, (wanted or at) as integer
  end,
  function(part: number, at: number, lane: number, wanted: number): number...
    return part, at or 0, lane, wanted or at or 0
  end
)

local function save()
  local beat = timegrid.beat(tick)
  -- The instance's own is the one that outlives a reload.
  if paw.seats.current == 0 then
    api.state_set("cursor", {part = part_id, beat = beat, lane = lane_id} as Place)
  end
  events.emit(M.changed, {part = part_id, beat = beat, lane = lane_id})
  api.ui_redraw()
end

--- A function that gives the part that keys and commands act on in
--- place of the cursor's, or nil: a device panel pinned to a part
--- (paw/views/devices.lua) sets it, for while its window has the keyboard.
M.lens = nil

-- `part_get(id, "id")`: one field, which fails when the part is gone,
-- without the list of clips that the whole part has. `part_id` runs
-- many times in each frame.
local part_id_of = api.part_get as function(integer, string): integer

--- The id of the part of the cursor, or of the first part when that part
--- does not exist now. Nil when the project has no parts. 0 when the
--- cursor is on the master part (`on_master`).
function M.part_id(): integer
  local lens = M.lens and M.lens()
  if lens then
    return lens
  end
  if part_id == 0 then
    return 0
  end
  if part_id and pcall(part_id_of, part_id, "id") then
    return part_id
  end
  part_id = api.part_list()[1]
  return part_id
end

--- True if the cursor is on the master part: the row after the last
--- part in the arrange view, the strip after the last in the mixer.
function M.on_master(): boolean
  return part_id == 0
end

--- True if a move of the cursor can go on from the last part to the
--- master: a move of its own in normal mode, in the views that draw the
--- master after the parts. After an operator or in a selection, only
--- parts count.
local function master_reachable(): boolean
  local keymap = paw.keymap
  return keymap.mode == "n" and not keymap.motion_for and (paw.ui.focused == "arrange" or paw.ui.focused == "mixer")
end
M.master_reachable = master_reachable

--- The part the cursor is on, as a `paw.Part`, or nil.
function M.part(): objects.Part
  local id = M.part_id()
  return id and paw.part(id) or nil
end

local nest_field = api.part_get as function(id: integer, key: string): integer

--- 1-based position of the cursor part among the parts of its place:
--- the song's, or its subproject's (as `paw.api.part_move` counts).
function M.index(): integer
  local id = M.part_id()
  local ok, nest = pcall(nest_field, id, "nest") as (boolean, integer)
  for i, other in ipairs(api.part_list({nest = ok and nest or nil})) do
    if other == id then
      return i
    end
  end
end

--- 1-based row of the cursor part among the parts that are drawn: the
--- same as `index` until a group is folded. On the master, the row after
--- the last part.
function M.row(): integer
  local id = M.part_id()
  if id == 0 then
    return #paw.groups.rows() + 1
  end
  for i, other in ipairs(paw.groups.rows()) do
    if other == id then
      return i
    end
  end
end

--- The automation lane row of the cursor: a lane of the cursor part that
--- shows as a row (see `paw.lanes`). Nil when the cursor is on the part.
function M.lane_id(): integer
  if not lane_id then
    return nil
  end
  local id = M.part_id()
  for _, lane in ipairs(id and paw.lanes.shown(id) or {}) do
    if lane.id == lane_id then
      return lane_id
    end
  end
end

--- 1-based row of the cursor among every row drawn, lanes included.
function M.line(): integer
  local id, lane = M.part_id(), M.lane_id()
  for i, line in ipairs(paw.groups.rows({lanes = true})) do
    if line.part == id and line.lane == lane then
      return i
    end
  end
end

--- Put the cursor on a part, or with `lane` on one of its lane rows.
function M.set_part(part: integer | objects.Part, lane?: integer)
  part_id = part is objects.Part and part.id or part as integer
  lane_id = lane
  save()
end

--- A function that gives the row that stands for a part at a beat for a
--- move by rows, or nil when the part is its own row: paw/folds.tl sets
--- it, so that a closed block fold is one row for `j` and `k`.
M.stop = nil

--- The row that stands for a part in a move by rows (`M.stop`), or nil
--- when the part and its lane rows are rows of their own. After an
--- operator, every part is its own row, as an operator acts on parts.
local function stop_of(part: integer): integer
  if not M.stop or paw.keymap.motion_for then
    return nil
  end
  return M.stop(part, M.beat)
end

--- The rows a move by rows stops on: a row that stands for others once,
--- in place of them and of their lane rows.
local function stops(lines: {Row}): {Row}
  local out: {Row} = {}
  for _, line in ipairs(lines) do
    local stop = stop_of(line.part)
    local last = out[#out]
    if not stop then
      out[#out + 1] = line
    elseif not (last and last.part == stop and last.lane == nil) then
      out[#out + 1] = {part = stop}
    end
  end
  return out
end

-- Moves the cursor to a tick without touching `want` (set below).
local place: function(at: integer): boolean

--- Move by rows. In normal mode, the rows of open automation lanes count.
--- After an operator or in a selection, only parts count, as for `dj`.
--- From the last part, a move down goes on to the master, and from the
--- master a move up returns to the parts. A closed block fold at the
--- cursor's beat is one row (`paw.cursor.stop`).
function M.move_part(delta: integer)
  local reach = master_reachable()
  local lanes = paw.lanes.any_open() and paw.keymap.mode == "n"
  local lines: {Row}
  if lanes then
    lines = paw.groups.rows({lanes = true})
  else
    lines = {}
    for i, id in ipairs(paw.groups.rows()) do
      lines[i] = {part = id}
    end
  end
  lines = stops(lines)
  if #lines == 0 then
    return
  end
  -- Where the cursor is among the stops: on the master after the last,
  -- on the row that stands for its own.
  local id, lane = M.part_id(), lanes and M.lane_id() or nil
  local stop = stop_of(id)
  if stop then
    id, lane = stop, nil
  end
  local at: integer
  if M.on_master() then
    at = #lines + 1
  else
    for i, line in ipairs(lines) do
      if line.part == id and line.lane == lane then
        at = i
        break
      end
    end
  end
  at = at or 1
  if reach and at + delta > #lines then
    M.set_part(0)
  else
    local to = lines[util.clamp(at + delta, 1, #lines) as integer]
    M.set_part(to.part, to.lane)
  end
  -- The time that the last move of time asked for, which a bound of the
  -- row before (a closed block fold of its part) can have kept the cursor
  -- from: as Vim's `curswant`.
  if want ~= tick then
    local wanted = want
    place(wanted)
    want = wanted
  end
end

--- A function that gives where the cursor goes when it moves from one
--- beat to another: paw/folds.tl sets it, so that the cursor takes a
--- folded span as one step and stays on its column.
M.over = nil

--- Move the cursor to a tick: not before 0, in the scope's time
--- (`paw.timegrid.bounds`), and over a fold as one step (`over`). It does
--- not change `want`. Gives true when a fold moved the cursor to another
--- tick than the scope allowed.
place = function(at: integer): boolean
  at = math.max(0, at)
  local from, to: number, number
  if timegrid.bounds then
    from, to = timegrid.bounds()
  end
  if from then
    at = math.min(math.max(at, timegrid.tick(from)), timegrid.tick(to))
  end
  local hopped = false
  if M.over then
    local over = timegrid.tick(M.over(timegrid.beat(tick), timegrid.beat(at)))
    hopped = over ~= at
    at = over
  end
  tick = at
  save()
  return hopped
end

--- Put the cursor at a tick, as `place` does. `want` becomes the tick asked
--- for, as Vim's `curswant`: a scope that stops the cursor does not change
--- it. A hop over a closed block is a move that the user sees, so `want`
--- becomes the tick where the cursor lands. A tick with a fraction is an
--- error in the tests, and is rounded else.
function M.set_tick(at: integer)
  at = timegrid.checked(at, "cursor.set_tick")
  want = place(at) and tick or at
end

--- Put the cursor at a beat: the nearest tick, as `set_tick`.
function M.set_beat(beat: number)
  M.set_tick(timegrid.tick(beat))
end

-- Another project starts at its start, on its first part.
events.on(kernel.project_loaded, function() part_id, lane_id, tick, want = nil, nil, 0, 0; save() end)

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

--- A function that gives, for a part whose clips the window draws later
--- than their beats, how much later at a beat of the window; or nil:
--- paw/nest.tl sets it, for the parts of a subproject open in place under
--- its return row (each block of the row draws them at its own place).
M.shift = nil

--- The clip under the cursor, if any.
function M.clip(): objects.Clip
  local part = M.part()
  if not part then
    return nil
  end
  local shift = M.shift and M.shift(part.id, M.beat) or 0
  return part:clip_at(M.beat - shift)
end

return M
