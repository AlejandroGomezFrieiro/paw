-- The tempo lane: the tempo map drawn as a curve in a row under the ruler, in
-- steps where a change holds and in slopes where it ramps. It is a way to
-- look at the map and to edit it with the pointer; every edit changes the
-- tempo map, so the grid, the ruler and the clips that follow the tempo
-- follow the lane, and undo takes it back. Beats are of the window's time:
-- inside a subproject with its own tempo, the lane shows and edits its own
-- map; inside one that follows the song, the song's map at its place.
-- The other edits of the window's time (the flags on the ruler, `:tempo`,
-- `:timesig`, the curve editor of paw://tempo) go through it too, signature
-- changes included.
--
--   paw.tempolane.toggle()            -- show or hide the row
--   paw.tempolane.range()             -- the tempo at its bottom and its top
--   paw.tempolane.add(17, 96)         -- a change to 96 bpm at beat 17
--   paw.tempolane.move(17, 20, 100)   -- the change at beat 17 to beat 20, at 100 bpm
--   paw.tempolane.remove(20)
--   paw.tempolane.draw({ { 8, 120 }, { 9, 118 }, ... })  -- a stroke of the pencil
--   paw.tempolane.set_points({ { beat = 0, bpm = 120 }, ... })  -- every change
--   paw.tempolane.signature_set(16, 6, 8)    -- 6/8 from beat 16
--   paw.tempolane.signature_move(16, 24)  paw.tempolane.signature_remove(24)
--
-- Whether the row is shown is kept for the session (it survives `:reload`),
-- not in the project, as for the automation lanes.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local util = require("paw.util")
local options = require("paw.options")
local type types = require("paw.types")
local type TempoModule = require("paw.tempo")
local type objects = require("paw.objects")
local type CursorModule = require("paw.cursor")
local type CommandModule = require("paw.command")

--- A point of a stroke of the pencil: `{ beat, bpm }`.
local type StrokePoint = {number}

--- The payload of `lanes.changed`: nothing.
local record LanesChanged
end

-- What this module reads of `paw`, which paw/init.lua makes.
local record Paw
  tempo: TempoModule
  cursor: CursorModule
  time: objects.Time
  notify: function(text: string, level?: string)
end
local paw = (_G as {string: Paw}).paw

local record M
  type StrokePoint = StrokePoint
end

local lanes_changed = events.event("lanes.changed") as events.Event<LanesChanged>

local shown = api.state_get("tempo_lane") == true

local function changed()
  api.ui_redraw()
  -- A graphical frontend draws it too.
  events.emit(lanes_changed, {})
end

--- True if the row shows.
function M.shown(): boolean
  return shown
end

--- Show the row, or hide it (`on` false).
function M.show(on?: boolean)
  shown = on ~= false
  api.state_set("tempo_lane", shown)
  changed()
end

--- Show the tempo lane, or hide it. Returns true if it shows.
function M.toggle(): boolean
  M.show(not shown)
  return shown
end

--- The tempo at the bottom and at the top of the row. The range keeps a
--- small space around the slowest and the fastest tempo of the map, in tens
--- of beats a minute. The range is at least 80 and centered. So a steady
--- song does not show as a wall. The map is the window's: inside a
--- subproject with its own tempo, its own.
function M.range(): number, number
  local lo, hi: number, number = math.huge, 0
  for _, p in ipairs(paw.time.tempo_points()) do
    lo, hi = math.min(lo, p.bpm), math.max(hi, p.bpm)
  end
  lo = math.max(0, math.floor((lo - 30) / 10) * 10)
  hi = math.ceil((hi + 30) / 10) * 10
  if hi - lo < 80 then
    local extra = (80 - (hi - lo)) / 2
    lo = math.max(0, lo - extra)
    hi = lo + 80
  end
  return lo, hi
end

--- Where a tempo is in the row, 0 at the bottom, 1 at the top.
function M.fraction(bpm: number): number
  local lo, hi = M.range()
  return util.clamp((bpm - lo) / (hi - lo), 0, 1)
end

--- The tempo at a height in the row (a fraction, 0 at the bottom), to a
--- whole beat a minute and never below 20.
function M.bpm(fraction: number): number
  local lo, hi = M.range()
  return math.max(20, math.floor(lo + util.clamp(fraction, 0, 1) * (hi - lo) + 0.5))
end

local function clamp_bpm(bpm: number): number
  return math.max(1, math.min(999, bpm))
end

-- The maps that an edit of the window's time changes. The lane, the flags
-- on the ruler, `:tempo`, `:tempo.*`, `:timesig` and the curve editor of
-- paw://tempo edit through them: this is the one place of the rule. The
-- beats given to them are beats of the window's time.
--
-- Tempo: in the song, or in a subproject that follows the song's tempo,
-- the song's map at the song's beat of each one (`paw.time.song_beat`). In
-- a subproject with its own tempo, that own map, whose beats are the
-- window's.
--
-- Meter: in a subproject with its own meter, that own meter. In a
-- subproject with its own tempo that follows the song's meter, the meter
-- that it shows (the song's at its start) becomes its own meter with the
-- edit: its beats do not line up with the song's, so a change of the
-- song's map does not show there. Else the song's map at the song's beat.
--
-- Each edit writes the map once: one undo step.
local record EditMap
  -- Its tempo points, the start's first, in its own beats.
  tempos: {types.TempoPoint}
  -- The beat of this map of a beat of the window's time.
  beat: function(window_beat: number): number
  -- Replace its tempo points.
  write: function(tempos: {types.TempoPoint})
end

--- The signature map that an edit changes, as `EditMap` is for the tempo.
local record MeterMap
  -- Its signature points, the start's first, in its own beats.
  signatures: {types.SigPoint}
  beat: function(window_beat: number): number
  write: function(signatures: {types.SigPoint})
end

local function same_beat(a: number, b: number): boolean
  return math.abs(a - b) < 1e-6
end

local function by_beat(a: types.TempoPoint, b: types.TempoPoint): boolean
  return a.beat < b.beat
end

--- The beat of an own map of a beat of the window's time: the same.
local function same(beat: number): number
  return beat
end

--- The map that a tempo edit changes, read now.
local function edit_map(): EditMap
  local own = paw.time.own()
  if own and own.own_tempo then
    local nest = api.clip_get(own.clip).nest
    return {
      tempos = api.nest_get(nest).tempo.points as {types.TempoPoint},
      beat = same,
      write = function(tempos: {types.TempoPoint})
        local tempo: types.NestTempo = {mode = "own", points = tempos as {types.TempoChange}}
        api.nest_set(nest, {tempo = tempo} as types.Nest)
      end,
    }
  end
  local map = api.tempo_points()
  return {
    tempos = map.tempos,
    beat = paw.time.song_beat,
    write = function(tempos: {types.TempoPoint}) api.tempo_set_points(tempos, map.signatures) end,
  }
end

--- The signatures of a list, without the bars that `tempo_points` adds.
local function plain_signatures(list: {types.SigPoint}): {types.SigPoint}
  local out: {types.SigPoint} = {}
  for i, s in ipairs(list) do
    out[i] = {beat = s.beat, num = s.num, den = s.den}
  end
  return out
end

--- The map that a signature edit changes, read now.
local function meter_map(): MeterMap
  local own = paw.time.own()
  if own then
    local nest = api.clip_get(own.clip).nest
    local meter = api.nest_get(nest).meter
    -- Its own meter, or the meter that its own tempo shows.
    local signatures = plain_signatures(
      meter.mode == "own" and meter.changes as {types.SigPoint} or own:points().signatures
    )
    return {
      signatures = signatures,
      beat = same,
      write = function(list: {types.SigPoint})
        local meter_out: types.NestMeter = {mode = "own", changes = plain_signatures(list) as {types.SigChange}}
        api.nest_set(nest, {meter = meter_out} as types.Nest)
      end,
    }
  end
  local map = api.tempo_points()
  return {
    signatures = plain_signatures(map.signatures),
    beat = paw.time.song_beat,
    write = function(signatures: {types.SigPoint}) api.tempo_set_points(map.tempos, signatures) end,
  }
end

--- The index in `tempos` of the point at `beat`, or nil.
local function index_at(tempos: {types.TempoPoint}, beat: number): integer
  for i, p in ipairs(tempos) do
    if same_beat(p.beat, beat) then
      return i
    end
  end
end

--- The tempo points the lane shows and edits, the start's first, in beats
--- of the window's time: `paw.time.tempo_points`.
function M.points(): {types.TempoPoint}
  return paw.time.tempo_points()
end

--- The point of the lane in effect at a beat of the window's time (the
--- last one at or before it, else the first), and its index.
function M.point_at(beat: number): types.TempoPoint, integer
  local points = M.points()
  local found, index = points[1], 1
  for i, p in ipairs(points) do
    if p.beat <= beat + 1e-9 then
      found, index = p, i
    end
  end
  return found, index
end

--- A tempo change at a beat, which holds. If a change is there, it gets the tempo.
function M.add(beat: number, bpm: number)
  local map = edit_map()
  local at = math.max(0, map.beat(beat))
  local i = index_at(map.tempos, at)
  if i then
    map.tempos[i].bpm = clamp_bpm(bpm)
  else
    map.tempos[#map.tempos + 1] = {beat = at, bpm = clamp_bpm(bpm), ramp = false}
    table.sort(map.tempos, by_beat)
  end
  map.write(map.tempos)
end

--- The change at `beat` to another beat and tempo. The start's change
--- keeps its beat and changes its tempo.
function M.move(beat: number, to?: number, bpm?: number): boolean
  local map = edit_map()
  local index = index_at(map.tempos, map.beat(beat))
  if not index then
    return false
  end
  local point = map.tempos[index]
  point.bpm = clamp_bpm(bpm or point.bpm)
  if index > 1 then
    table.remove(map.tempos, index)
    -- Not onto another change, and never to the start.
    local target = math.max(options.opt.grid, to and map.beat(to) or point.beat)
    local there = index_at(map.tempos, target)
    while there do
      table.remove(map.tempos, there)
      there = index_at(map.tempos, target)
    end
    point.beat = target
    map.tempos[#map.tempos + 1] = point
    table.sort(map.tempos, by_beat)
  end
  map.write(map.tempos)
  return true
end

--- Remove the change at `beat`. You cannot remove the change at the start.
function M.remove(beat: number): boolean
  local map = edit_map()
  local index = index_at(map.tempos, map.beat(beat))
  if not index or index == 1 then
    return false
  end
  table.remove(map.tempos, index)
  map.write(map.tempos)
  return true
end

--- Make the change at `beat` ramp to the next, or hold again.
function M.ramp(beat: number, on?: boolean): boolean
  local map = edit_map()
  local index = index_at(map.tempos, map.beat(beat))
  if not index then
    return nil
  end
  local point = map.tempos[index]
  if on == nil then
    on = not point.ramp
  end
  point.ramp = on
  map.write(map.tempos)
  return on
end

--- A stroke of the pencil: `points` are `{ beat, bpm }` as they were drawn.
--- They replace the changes over the stretch drawn across (the start's
--- stays, with its tempo taken from the stroke if it reaches it), each a
--- slope to the next, at most one to `step` beats.
function M.draw(points: {StrokePoint}, step?: number)
  if #points == 0 then
    return
  end
  local map = edit_map()
  local stroke: {StrokePoint} = {}
  for i, p in ipairs(points) do
    stroke[i] = {math.max(0, map.beat(p[1])), p[2]}
  end
  table.sort(stroke, function(a: StrokePoint, b: StrokePoint): boolean return a[1] < b[1] end)
  step = step or math.max(0.5, options.opt.grid)
  local from, to = stroke[1][1], stroke[#stroke][1]
  local out: {types.TempoPoint} = {}
  for i, p in ipairs(map.tempos) do
    if i == 1 or p.beat < from - 1e-9 or p.beat > to + 1e-9 then
      out[#out + 1] = p
    end
  end
  local last: number
  for i, p in ipairs(stroke) do
    local beat = p[1]
    if not last or beat - last >= step - 1e-9 or i == #stroke then
      local bpm = clamp_bpm(p[2])
      local at = index_at(out, beat)
      if at then
        out[at].bpm = bpm
      else
        out[#out + 1] = {beat = beat, bpm = bpm, ramp = i < #stroke}
      end
      last = beat
    end
  end
  -- The stroke's last change holds: what comes after it was not drawn.
  for _, p in ipairs(out) do
    if same_beat(p.beat, last) and p.beat > 0 then
      p.ramp = false
    end
  end
  table.sort(out, by_beat)
  map.write(out)
end

--- Replace every tempo point of the window's time with `points`, beats of
--- the window, as the curve editor of paw://tempo writes them. The map
--- starts with a change at its start: when no point is there, one with the
--- first point's tempo holds until it.
function M.set_points(points: {types.TempoPoint})
  if #points == 0 then
    return
  end
  local map = edit_map()
  local out: {types.TempoPoint} = {}
  for i, p in ipairs(points) do
    out[i] = {beat = math.max(0, map.beat(p.beat)), bpm = p.bpm, ramp = p.ramp}
  end
  table.sort(out, by_beat)
  if out[1].beat > 1e-9 then
    table.insert(out, 1, {beat = 0, bpm = out[1].bpm, ramp = false})
  end
  out[1].beat = 0
  map.write(out)
end

-- Signature changes ---------------------------------------------------------------------

--- The index in `signatures` of the change at `beat`, or nil.
local function signature_index(signatures: {types.SigPoint}, beat: number): integer
  for i, s in ipairs(signatures) do
    if same_beat(s.beat, beat) then
      return i
    end
  end
end

local function by_signature_beat(a: types.SigPoint, b: types.SigPoint): boolean
  return a.beat < b.beat
end

--- Start a bar of `num`/`den` at a beat of the window's time, or change
--- the signature that starts there.
function M.signature_set(beat: number, num: integer, den: integer)
  local map = meter_map()
  local at = math.max(0, map.beat(beat))
  local i = signature_index(map.signatures, at)
  if i then
    map.signatures[i].num, map.signatures[i].den = num, den
  else
    map.signatures[#map.signatures + 1] = {beat = at, num = num, den = den}
    table.sort(map.signatures, by_signature_beat)
  end
  map.write(map.signatures)
end

--- Remove the signature change at a beat of the window's time. You cannot
--- remove the one at the start.
function M.signature_remove(beat: number): boolean
  local map = meter_map()
  local index = signature_index(map.signatures, map.beat(beat))
  if not index or index == 1 then
    return false
  end
  table.remove(map.signatures, index)
  map.write(map.signatures)
  return true
end

--- Move the signature change at `beat` to beat `to`, both of the window's
--- time; a change there goes. The one at the start does not move, and
--- none moves onto it.
function M.signature_move(beat: number, to: number): boolean
  local map = meter_map()
  local index = signature_index(map.signatures, map.beat(beat))
  local target = map.beat(to)
  if not index or index == 1 or same_beat(target, map.signatures[1].beat) or target < 0 then
    return false
  end
  local point = table.remove(map.signatures, index)
  point.beat = target
  local there = signature_index(map.signatures, point.beat)
  if there then
    table.remove(map.signatures, there)
  end
  map.signatures[#map.signatures + 1] = point
  table.sort(map.signatures, by_signature_beat)
  map.write(map.signatures)
  return true
end

--- Define the tempo lane's commands with `command`.
function M.commands(command: TempoModule.Define)
  command(
    "tempo.lane",
    function(ctx: CommandModule.Context): CommandModule.Result
      local word = ctx.args[1]
      if word == "on" or word == "off" then
        M.show(word == "on")
      elseif word == nil then
        M.toggle()
      else
        paw.notify("tempo.lane: `on`, `off`, or nothing to toggle", "warn")
        return
      end
      paw.notify(shown and "tempo lane shown under the ruler" or "tempo lane hidden")
    end,
    {
      desc = "Show or hide the tempo curve under the ruler: `tempo.lane`, `tempo.lane on`, `tempo.lane off`",
      label = "Tempo lane",
      complete = function(): {string} return {"on", "off"} end,
    }
  )

  command(
    "tempo.move",
    function(ctx: CommandModule.Context): CommandModule.Result
      local a = ctx.args
      local to = a[1]
      if not to then
        error("tempo.move: say where to, a bar (17) or a bar and beat (17.3)", 0)
      end
      local from, index = M.point_at(a[2] and paw.tempo.place(a[2]) or paw.cursor.beat)
      if index == 1 then
        error("the start's tempo does not move", 0)
      end
      local target = paw.tempo.place(to)
      M.move(from.beat, target, from.bpm)
      paw.notify(string.format("%g bpm moved to %s", from.bpm, paw.time.format(target)))
    end,
    {
      desc = "Move the tempo change at or before the cursor (or at a bar) to another bar: `tempo.move 17`, `tempo.move 17 9`",
      label = "Move a tempo change",
    }
  )
end

return M
