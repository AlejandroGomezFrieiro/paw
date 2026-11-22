-- Folds: parts of the song drawn in place, as Vim's folds hide lines. A
-- fold of tracks draws its rows as one row with its name; a group is a
-- fold by itself, folded into its own row. A time fold draws a region or
-- a range of bars as one narrow column with its name and its bars
-- (`Bridge ▸ 8`); every region is a fold by itself, closed by its level
-- (`zm`, `zr`, as the `foldlevel` option of Vim).
--
--   paw.folds.make({ kind = "tracks", tracks = { 3, 4, 5 } })  -- `Vjjzf`: "Fold 1"
--   paw.folds.make({ kind = "region", id = 7 })               -- `zfar`
--   paw.folds.toggle()      -- `za` at the cursor
--   paw.folds.delete()      -- `zd`: the fold goes, never a track
--   paw.folds.all(true)     -- `zM`; `all(false)` is `zR`
--   paw.folds.level(-1)     -- `zm`; `level(1)` is `zr`
--
-- The song plays through a time fold unchanged: only the views draw it.
-- `time_map` gives a view the map from beats to its columns, with the
-- folded spans in it.
--
-- Folds are view state, as in Vim: each window keeps its own
-- (`win.folds`), a split starts with those of the window it comes from,
-- a fold is never an undo step, and the project's screen (`screen.json`)
-- keeps them. A view reads the folds of the window it draws, through
-- `paw.scope.window`: the mixer and the other views of a tab show those
-- of its arrange window.
--
-- A fold that holds every track of the scope the window shows is open
-- there: `znn` on a fold enters it, and `zw` comes back to it, closed as
-- it was.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type CursorModule = require("paw.cursor")
local type objects = require("paw.objects")

local type Fold = contracts.Fold
local type Window = contracts.Window

-- paw/scope.tl and paw/groups.tl name this module's types, so this one
-- declares only the parts of them that it reads.
local record Scopes
  window: function(win?: Window): Window
  holder: function(win?: Window): Window
  current: function(win?: Window): contracts.Scope
  tracks: function(s?: contracts.Scope): {integer}
  limits_tracks: function(s?: contracts.Scope): boolean
  span: function(s?: contracts.Scope): number, number
end
local record Groups
  is_group: function(id: integer): boolean
  of: function(id: integer): integer
  members: function(id: integer): {integer}
  rows: function(): {integer}
end
-- paw/markers.tl reaches this module through paw/ruler.tl: the part of
-- it that this one reads, the regions and their tree.
local record Region
  id: integer
  beat: number
  name: string
  length: number
end
local record RegionNode
  region: Region
  depth: integer
end
local record ById
  id: integer
end
local record Markers
  find: function(which: ById): Region
  walk: function(): {RegionNode}
  path: function(beat: number): {Region}
end
local record Paw is partial.Paw
  scope: Scopes
  groups: Groups
  cursor: CursorModule
  markers: Markers
  time: objects.Time
end
local paw = (_G as {string: Paw}).paw

--- A closed stretch of time in a view: its beats, the fold, its label,
--- and the columns it takes (`cells`, at least 3), which are `width`
--- beats of the view at its zoom.
local record TimeSpan
  from: number
  to: number
  fold: Fold
  label: string
  cells: integer
  width: number
end

--- The map from beats to the places of a view with time folds (`time_map`):
--- `view(beat)` is where a beat is drawn, in beats of the view (a beat
--- inside a folded span is drawn at its column's start), and `beat(v)` the
--- beat drawn at a place (the start of a folded span on its column).
local record TimeMap
  spans: {TimeSpan}
  view: function(beat: number): number
  beat: function(v: number): number
end

local record M
  type Fold = Fold
  type TimeSpan = TimeSpan
  type TimeMap = TimeMap
  time_at: function(beat: number, win?: Window): TimeSpan
  --- One more each time a window's folds change: what caches of drawn
  --- rows are kept by.
  generation: integer
end
M.generation = 0

local changed: events.Event<events.Payload> = events.event("fold.changed")

local function exists(id: integer): boolean
  return id ~= nil and (pcall(api.track_get, id))
end

local function name_of(id: integer): string
  return (api.track_get as function(integer, string): string)(id, "name")
end

--- The folds of a window that a view shows (the one being drawn, else the
--- current one). Empty when it has none.
function M.list(win?: Window): {Fold}
  local w = paw.scope.window(win)
  return w and w.folds or {}
end

--- The folds of the window that an action changes, made if it has none.
local function own(win?: Window): {Fold}, Window
  local w = paw.scope.holder(win)
  if not w then
    error("no window to fold in", 0)
  end
  w.folds = w.folds or {}
  return w.folds, w
end

local function touched()
  M.generation = M.generation + 1
  events.emit(changed, {})
  -- The cursor does not stay inside a time fold: it goes to its column.
  local s = M.time_at(paw.cursor.beat)
  if s and paw.cursor.beat > s.from then
    paw.cursor.set_beat(s.from)
  end
  api.ui_redraw()
end

local function group_entry(folds: {Fold}, group: integer): Fold, integer
  for i, f in ipairs(folds) do
    if f.kind == "group" and f.id == group then
      return f, i
    end
  end
end

-- Time folds ----------------------------------------------------------------------------

local function is_time(f: Fold): boolean
  return f.kind == "region" or f.kind == "range"
end

local function region_entry(folds: {Fold}, id: integer): Fold, integer
  for i, f in ipairs(folds) do
    if f.kind == "region" and f.id == id then
      return f, i
    end
  end
end

--- Whether a region is closed in a window: as its entry says, else by its
--- level (`foldlevel`: the regions deeper than it are closed).
local function region_closed(id: integer, depth: integer, w: Window): boolean
  local entry = w and region_entry(w.folds or {}, id)
  if entry then
    return entry.closed == true
  end
  return w ~= nil and w.foldlevel ~= nil and depth > w.foldlevel
end

--- The beats of a time fold, or nil when its region is gone.
local function span_of(f: Fold): number, number
  if f.kind == "region" then
    local r = paw.markers and paw.markers.find({id = f.id})
    if r and r.length then
      return r.beat, r.beat + r.length
    end
    return nil
  end
  return f.from, f.to
end

--- How many bars a stretch of time covers.
local function bars(from: number, to: number): integer
  local time = paw.time
  return time.bar_of(math.max(from, to - 1e-6)) - time.bar_of(from) + 1
end

--- True if a group is folded into its row in a window (the one a view
--- shows by default).
function M.group_closed(group: integer, win?: Window): boolean
  local f = group_entry(M.list(win), group)
  return f ~= nil and f.closed == true
end

--- Whether a fold holds a track: a group holds itself and every track
--- inside it, at any depth.
local function holds(f: Fold, id: integer): boolean
  if f.kind == "group" then
    local at, steps = id, 0
    while at and steps < 32 do
      if at == f.id then
        return true
      end
      at, steps = paw.groups.of(at), steps + 1
    end
    return false
  end
  for _, other in ipairs(f.tracks or {}) do
    if other == id then
      return true
    end
  end
  return false
end

--- How many tracks a fold holds.
local function size(f: Fold): integer
  if f.kind == "group" then
    local n = 1
    for _, id in ipairs(paw.groups.members(f.id)) do
      n = n + size({kind = "group", id = id})
    end
    return n
  end
  local n = 0
  for _, id in ipairs(f.tracks or {}) do
    if exists(id) then
      n = n + 1
    end
  end
  return n
end

--- Whether a fold of tracks holds every track of the scope a window
--- shows: then it is open there, as the window shows its inside.
local function is_whole_scope(f: Fold, win?: Window): boolean
  local s = paw.scope.current(win)
  if not (s and f.kind == "tracks" and paw.scope.limits_tracks(s)) then
    return false
  end
  for _, id in ipairs(paw.scope.tracks(s)) do
    if not holds(f, id) then
      return false
    end
  end
  return true
end

--- The rows that a window draws, from the rows of its tracks without
--- its folds of tracks: each closed fold of tracks keeps its first row,
--- which stands for all of it.
function M.collapse(rows: {integer}, win?: Window): {integer}
  local closed: {Fold} = {}
  for _, f in ipairs(M.list(win)) do
    if f.kind == "tracks" and f.closed and not is_whole_scope(f, win) then
      closed[#closed + 1] = f
    end
  end
  if #closed == 0 then
    return rows
  end
  local seen: {Fold: boolean} = {}
  local out: {integer} = {}
  for _, id in ipairs(rows) do
    local keep = true
    for _, f in ipairs(closed) do
      if holds(f, id) then
        keep = not seen[f]
        seen[f] = true
        break
      end
    end
    if keep then
      out[#out + 1] = id
    end
  end
  return out
end

--- The closed fold of tracks that the row of a track stands for in a
--- window (the one a view shows by default), or nil: the track is the
--- first row of that fold.
function M.row(id: integer, win?: Window): Fold
  for _, f in ipairs(M.list(win)) do
    if f.kind == "tracks" and f.closed and holds(f, id) and not is_whole_scope(f, win) then
      -- Its first track drawn, in the order of the track list.
      for _, other in ipairs(api.track_list()) do
        if holds(f, other) then
          if other == id then
            return f
          end
          break
        end
      end
    end
  end
end

--- The name a fold shows: its own, else its group's.
function M.name(f: Fold): string
  if f.name then
    return f.name
  end
  if f.kind == "group" and exists(f.id) then
    return name_of(f.id)
  end
  if f.kind == "region" then
    local r = paw.markers and paw.markers.find({id = f.id})
    return r and r.name or "Region"
  end
  return "Fold"
end

--- What a fold holds, in words: `3 tracks`, `8 bars`.
function M.describe(f: Fold): string
  if is_time(f) then
    local from, to = span_of(f)
    local n = from and bars(from, to) or 0
    return string.format("%d bar%s", n, n == 1 and "" or "s")
  end
  local n = size(f)
  return string.format("%d track%s", n, n == 1 and "" or "s")
end

--- How many tracks of a fold are there.
function M.count(f: Fold): integer
  return size(f)
end

--- The closed time folds of a window (the one a view shows by default),
--- in order of time: the outermost of folds inside each other, and folds
--- that overlap as one. A fold that holds all the time of the window's
--- scope is open there.
function M.time_spans(win?: Window): {TimeSpan}
  local w = paw.scope.window(win)
  if not w then
    return {}
  end
  local list: {TimeSpan} = {}
  local function add(f: Fold, from: number, to: number, name: string)
    if from and to > from then
      list[#list + 1] = {from = from, to = to, fold = f, label = name .. " ▸ " .. bars(from, to)}
    end
  end
  if w.foldlevel or w.folds then
    for _, node in ipairs(paw.markers and paw.markers.walk() or {}) do
      local r = node.region
      if region_closed(r.id, node.depth, w) then
        local f = region_entry(w.folds or {}, r.id) or {kind = "region", id = r.id, closed = true}
        add(f, r.beat, r.beat + r.length, f.name or r.name)
      end
    end
  end
  for _, f in ipairs(w.folds or {}) do
    if f.kind == "range" and f.closed then
      add(f, f.from, f.to, f.name or "Fold")
    end
  end
  if #list == 0 then
    return list
  end
  local s_from, s_to = paw.scope.span(paw.scope.current(w))
  table.sort(
    list,
    function(a: TimeSpan, b: TimeSpan): boolean
      if a.from ~= b.from then
        return a.from < b.from
      end
      return a.to > b.to
    end
  )
  local out: {TimeSpan} = {}
  for _, s in ipairs(list) do
    local whole = s_from and s.from <= s_from + 1e-9 and s.to >= s_to - 1e-9
    local last = out[#out]
    if whole then
      -- The window shows its inside.
    elseif last and s.from < last.to - 1e-9 then
      last.to = math.max(last.to, s.to)
    else
      out[#out + 1] = s
    end
  end
  return out
end

local function identity(beat: number): number
  return beat
end

--- The map from beats to the places of a view at `zoom` columns a beat,
--- with the closed time folds of a window (the one a view shows by
--- default). Each folded span takes the columns of its label and two more.
function M.time_map(zoom: number, win?: Window): TimeMap
  local spans = M.time_spans(win)
  if #spans == 0 then
    return {spans = spans, view = identity, beat = identity}
  end
  for _, s in ipairs(spans) do
    s.cells = math.max(3, math.min(24, api.str_width(s.label) + 2))
    s.width = s.cells / zoom
  end
  local map: TimeMap = {spans = spans}
  map.view = function(beat: number): number
    local cut = 0.0
    for _, s in ipairs(spans) do
      if beat <= s.from then
        break
      end
      if beat < s.to then
        return s.from - cut
      end
      cut = cut + (s.to - s.from) - s.width
    end
    return beat - cut
  end
  map.beat = function(v: number): number
    local cut = 0.0
    for _, s in ipairs(spans) do
      local at = s.from - cut
      if v < at then
        break
      end
      if v < at + s.width then
        return s.from
      end
      cut = cut + (s.to - s.from) - s.width
    end
    return v + cut
  end
  return map
end

--- The closed time fold that a beat is on (`from` up to `to`), in a window.
function M.time_at(beat: number, win?: Window): TimeSpan
  for _, s in ipairs(M.time_spans(win)) do
    if beat >= s.from - 1e-9 and beat < s.to - 1e-9 then
      return s
    end
  end
end

--- Where the cursor goes when it moves from beat `old` to `new`: a beat
--- inside a closed time fold is its start, or its end when the cursor
--- moves on from its start, so that a motion takes a fold as one step.
function M.over(old: number, new: number): number
  for _, s in ipairs(M.time_spans()) do
    if new > s.from + 1e-9 and new < s.to - 1e-9 then
      if old and new > old and old >= s.from - 1e-9 then
        return s.to
      end
      return s.from
    end
  end
  return new
end

--- The regions at a beat as folds, the innermost first, in a window: each
--- with its entry when it has one, and whether it is closed.
local function regions_around(beat: number, win?: Window): {Fold}
  local w = paw.scope.window(win)
  local out: {Fold} = {}
  local path = paw.markers and paw.markers.path(beat) or {}
  for i = #path, 1, -1 do
    local r = path[i]
    if r.length then
      local entry = w and region_entry(w.folds or {}, r.id)
      out[#out + 1] = entry or {kind = "region", id = r.id, closed = region_closed(r.id, i, w)}
    end
  end
  return out
end

--- The folds at a track, in a window: the groups it is in (or is) and the
--- folds of tracks that hold it, the smallest first.
local function around(id: integer, win?: Window): {Fold}
  local out: {Fold} = {}
  local folds = M.list(win)
  local at = paw.groups.is_group(id) and id or paw.groups.of(id)
  local steps = 0
  while at and steps < 32 do
    out[#out + 1] = group_entry(folds, at) or {kind = "group", id = at}
    at, steps = paw.groups.of(at), steps + 1
  end
  for _, f in ipairs(folds) do
    if f.kind == "tracks" and holds(f, id) and not is_whole_scope(f, win) then
      out[#out + 1] = f
    end
  end
  table.sort(out, function(a: Fold, b: Fold): boolean return size(a) < size(b) end)
  return out
end

--- The fold at a track (the cursor's by default), in a window: the
--- largest closed one, which its row stands for, else the smallest. Nil
--- when the track is in none.
function M.at(id?: integer, win?: Window): Fold
  if not id then
    -- At the cursor: a closed time fold it is on comes first.
    local s = M.time_at(paw.cursor.beat, win)
    if s then
      return s.fold
    end
  end
  id = id or paw.cursor.track_id()
  local list = (id and id ~= 0) and around(id, win) or {}
  for i = #list, 1, -1 do
    if list[i].closed then
      return list[i]
    end
  end
  if list[1] and (list[1].kind ~= "group" or #paw.groups.members(list[1].id) > 0) then
    return list[1]
  end
  -- Else the innermost region at the cursor.
  return regions_around(paw.cursor.beat, win)[1]
end

--- Whether a track is drawn in the rows of the current window.
local function shown(id: integer): boolean
  for _, row in ipairs(paw.groups.rows()) do
    if row == id then
      return true
    end
  end
  return false
end

--- The cursor does not stay on a track that is folded away: it goes to the
--- row that stands for it.
function M.reveal()
  local id = paw.cursor.track_id()
  if not id or id == 0 or shown(id) then
    return
  end
  for _, row in ipairs(paw.groups.rows()) do
    local f = M.row(row)
    if f and holds(f, id) then
      return paw.cursor.set_track(row)
    end
    if paw.groups.is_group(row) and M.group_closed(row) and holds({kind = "group", id = row}, id) then
      return paw.cursor.set_track(row)
    end
  end
end

--- Close or open a fold of a window: `on` nil flips it. A group that is
--- opened keeps no entry.
local function set(f: Fold, on: boolean, win?: Window): boolean
  local folds = own(win)
  if on == nil then
    on = not f.closed
  end
  if f.kind == "group" then
    local entry, i = group_entry(folds, f.id)
    if not on then
      if i then
        table.remove(folds, i)
      end
    elseif entry then
      entry.closed = true
    else
      folds[#folds + 1] = {kind = "group", id = f.id, closed = true}
    end
  elseif f.kind == "region" then
    local entry = region_entry(folds, f.id)
    if not entry then
      entry = {kind = "region", id = f.id}
      folds[#folds + 1] = entry
    end
    entry.closed = on
  else
    f.closed = on
  end
  -- The cursor goes to the start of a time fold that it is in, its column.
  local from, to = span_of(f)
  if on and is_time(f) and from and paw.cursor.beat > from and paw.cursor.beat < to then
    paw.cursor.set_beat(from)
  end
  touched()
  M.reveal()
  return on
end

--- Fold a group into its row, or open it, in a window: `on` nil flips it.
function M.set_group(group: integer, on?: boolean, win?: Window)
  if not paw.groups.is_group(group) then
    return
  end
  set({kind = "group", id = group, closed = M.group_closed(group, paw.scope.holder(win))}, on, win)
end

--- Toggle the fold at a track (the cursor's by default), as `za`.
--- Returns it, or nil and the reason.
function M.toggle(id?: integer, win?: Window): Fold, string
  local f = M.at(id, win)
  if not f then
    return nil, "no fold here: `zf` makes one"
  end
  f.closed = set(f, nil, win)
  return f
end

--- Close the fold at the cursor, as `zc`; on a closed fold, the one
--- around it. Returns it, or nil and the reason.
function M.close(id?: integer, win?: Window): Fold, string
  id = id or paw.cursor.track_id()
  local list = id and around(id, win) or {}
  for _, f in ipairs(list) do
    if not f.closed and size(f) > 1 then
      set(f, true, win)
      return f
    end
  end
  for _, f in ipairs(regions_around(paw.cursor.beat, win)) do
    if not f.closed then
      set(f, true, win)
      return f
    end
  end
  return nil, #list == 0 and "no fold here: `zf` makes one" or "every fold here is closed"
end

--- Open the fold at the cursor (the one its row stands for). Returns it,
--- or nil and the reason.
function M.open(id?: integer, win?: Window): Fold, string
  local f = M.at(id, win)
  if not (f and f.closed) then
    return nil, "no closed fold here"
  end
  set(f, false, win)
  return f
end

--- A name for a new fold: `Fold 1`, or the next number free in the window.
local function new_name(folds: {Fold}): string
  local used: {string: boolean} = {}
  for _, f in ipairs(folds) do
    if f.name then
      used[f.name] = true
    end
  end
  local n = 1
  while used["Fold " .. n] do
    n = n + 1
  end
  return "Fold " .. n
end

--- Make a fold of what a scope covers (`zf{motion}`), closed, in a
--- window: a group folds into its row (`zfag`), tracks into one row named
--- `Fold 1` (`Vjjzf`). Returns it, or nil and the reason.
function M.make(spec: contracts.Scope, win?: Window): Fold, string
  if not spec then
    return nil, "nothing to fold"
  end
  local folds = own(win)
  if spec.kind == "group" then
    if not paw.groups.is_group(spec.id) then
      return nil, "not a group"
    end
    M.set_group(spec.id, true, win)
    return (group_entry(folds, spec.id))
  end
  if spec.kind == "track" then
    spec = {kind = "tracks", tracks = {spec.id}}
  end
  if spec.kind == "tracks" or (spec.kind == "range" and spec.tracks and not spec.from) then
    if not spec.tracks or #spec.tracks < 2 then
      return nil, "a fold of tracks holds two or more"
    end
    local f: Fold = {kind = "tracks", tracks = {}, name = spec.name or new_name(folds), closed = true}
    for i, id in ipairs(spec.tracks) do
      f.tracks[i] = id
    end
    folds[#folds + 1] = f
    touched()
    M.reveal()
    return f
  end
  if spec.kind == "region" then
    local from = span_of({kind = "region", id = spec.id})
    if not from then
      return nil, "no region there"
    end
    local f: Fold = {kind = "region", id = spec.id}
    set(f, true, win)
    return (region_entry(folds, spec.id))
  end
  if spec.kind == "range" and spec.from and spec.to and spec.to > spec.from then
    -- Time on every track of the window: a time fold. On some tracks only,
    -- a block, which does not fold yet.
    local all = paw.scope.tracks(paw.scope.current(paw.scope.holder(win)))
    if spec.tracks and #spec.tracks < #all then
      return nil, "a fold of time takes every track: `ggVG` and the bars, or `zfar`"
    end
    local f: Fold = {kind = "range", from = spec.from, to = spec.to, name = spec.name or new_name(folds)}
    folds[#folds + 1] = f
    set(f, true, win)
    return f
  end
  return nil, "nothing to fold there: `zfar` a region, `zfag` a group, `Vjzf` tracks"
end

--- Delete the fold at a track (the cursor's by default), as `zd`: the
--- fold goes, its tracks stay, drawn as before. Returns it, or nil and the
--- reason.
function M.delete(id?: integer, win?: Window): Fold, string
  local f = M.at(id, win)
  local folds = own(win)
  for i, other in ipairs(folds) do
    if other == f or (f and f.kind == "region" and other.kind == "region" and other.id == f.id) then
      table.remove(folds, i)
      touched()
      return f
    end
  end
  if f and f.kind == "region" then
    return nil, "a region folds by its level: `zr` opens a level, `zR` all"
  end
  return nil, "no fold here"
end

--- Delete every fold of a window, as `zE`. Returns how many there were.
function M.clear(win?: Window): integer
  local folds, w = own(win)
  local n = #folds
  w.folds, w.foldlevel = {}, nil
  touched()
  return n
end

--- Close every fold of a window, every group too (`zM`), or open them
--- all (`zR`).
function M.all(on: boolean, win?: Window)
  local folds, w = own(win)
  -- The regions follow the level: all of them closed, or all open.
  for i = #folds, 1, -1 do
    if folds[i].kind == "region" then
      table.remove(folds, i)
    end
  end
  w.foldlevel = on and 0 or nil
  if on then
    for _, id in ipairs(api.track_list()) do
      if paw.groups.is_group(id) and #paw.groups.members(id) > 0 and not group_entry(folds, id) then
        folds[#folds + 1] = {kind = "group", id = id, closed = true}
      end
    end
    for _, f in ipairs(folds) do
      f.closed = true
    end
  else
    local keep: {Fold} = {}
    for _, f in ipairs(folds) do
      if f.kind ~= "group" then
        f.closed = false
        keep[#keep + 1] = f
      end
    end
    w.folds = keep
  end
  touched()
  M.reveal()
end

--- The deepest level of regions.
local function deepest(): integer
  local n = 0
  for _, node in ipairs(paw.markers and paw.markers.walk() or {}) do
    n = math.max(n, node.depth)
  end
  return n
end

--- Close one more level of regions in a window (`zm`, `delta` -1: the
--- deepest open level first), or open one (`zr`, 1), as the `foldlevel`
--- option of Vim. The regions that `za` or `zf` opened or closed follow
--- the level again. Returns the level: how many levels stay open.
function M.level(delta: integer, win?: Window): integer
  local folds, w = own(win)
  local max = deepest()
  local now = w.foldlevel or max
  local new = math.max(0, math.min(max, math.min(now, max) + delta))
  for i = #folds, 1, -1 do
    if folds[i].kind == "region" then
      table.remove(folds, i)
    end
  end
  w.foldlevel = new < max and new or nil
  local s = M.time_at(paw.cursor.beat, win)
  if s then
    paw.cursor.beat = s.from
  end
  touched()
  return new
end

-- The cursor takes a folded span as one step (`l`, `w`, `b`, `e`).
paw.cursor.over = M.over

-- Back from a scope, the cursor goes to the row of the fold it is in.
local scope_changed: events.Event<events.Payload> = events.event("scope.changed")
events.on(scope_changed, function() M.reveal() end)

return M
