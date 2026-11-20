-- The tempo lane: the tempo map drawn as a curve in a row under the ruler, in
-- steps where a change holds and in slopes where it ramps. It is a way to
-- look at the map and to edit it with the pointer; every edit is one made to
-- `paw.tempo`, so the grid, the ruler and the clips that follow the tempo
-- follow the lane, and undo takes it back.
--
--   paw.tempolane.toggle()            -- show or hide the row
--   paw.tempolane.range()             -- the tempo at its bottom and its top
--   paw.tempolane.add(17, 96)         -- a change to 96 bpm at beat 17
--   paw.tempolane.move(17, 20, 100)   -- the change at beat 17 to beat 20, at 100 bpm
--   paw.tempolane.remove(20)
--   paw.tempolane.draw({ { 8, 120 }, { 9, 118 }, ... })  -- a stroke of the pencil
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
local type commands = require("paw.commands")

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
local paw = (_G as {string:Paw}).paw

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
function M.shown(): boolean return shown end

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
--- song does not show as a wall.
function M.range(): number, number
  local lo, hi: number, number = math.huge, 0
  for _, p in ipairs(paw.tempo.points()) do
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

local function clamp_bpm(bpm: number): number return math.max(1, math.min(999, bpm)) end

--- A tempo change at a beat, which holds. If a change is there, it gets the tempo.
function M.add(beat: number, bpm: number)
  api.tempo_set(math.max(0, beat), clamp_bpm(bpm))
end

--- The change at `beat` to another beat and tempo. The start's change
--- keeps its beat and changes its tempo.
function M.move(beat: number, to?: number, bpm?: number): boolean
  local map = api.tempo_points()
  local index: integer
  for i, p in ipairs(map.tempos) do
    if math.abs(p.beat - beat) < 1e-6 then index = i end
  end
  if not index then return false end
  local point = map.tempos[index]
  point.bpm = clamp_bpm(bpm or point.bpm)
  if index > 1 then
    table.remove(map.tempos, index)
    -- Not onto another change, and never to the start.
    local target = math.max(options.opt.grid, to or point.beat)
    for i = #map.tempos, 1, -1 do
      if math.abs(map.tempos[i].beat - target) < 1e-6 then table.remove(map.tempos, i) end
    end
    point.beat = target
    map.tempos[#map.tempos + 1] = point
    table.sort(map.tempos, function(a: types.TempoPoint, b: types.TempoPoint): boolean return a.beat < b.beat end)
  end
  api.tempo_set_points(map.tempos, map.signatures)
  return true
end

--- Remove the change at `beat`. You cannot remove the change at the start.
function M.remove(beat: number): boolean
  for i, p in ipairs(paw.tempo.points()) do
    if i > 1 and math.abs(p.beat - beat) < 1e-6 then
      api.tempo_remove(p.beat)
      return true
    end
  end
  return false
end

--- Make the change at `beat` ramp to the next, or hold again.
function M.ramp(beat: number, on?: boolean): boolean
  for _, p in ipairs(paw.tempo.points()) do
    if math.abs(p.beat - beat) < 1e-6 then
      if on == nil then on = not p.ramp end
      api.tempo_set(p.beat, p.bpm, on)
      return on
    end
  end
end

--- A stroke of the pencil: `points` are `{ beat, bpm }` as they were drawn.
--- They replace the changes over the stretch drawn across (the start's
--- stays, with its tempo taken from the stroke if it reaches it), each a
--- slope to the next, at most one to `step` beats.
function M.draw(points: {StrokePoint}, step?: number)
  if #points == 0 then return end
  table.sort(points, function(a: StrokePoint, b: StrokePoint): boolean return a[1] < b[1] end)
  step = step or math.max(0.5, options.opt.grid)
  local from, to = math.max(0, points[1][1]), math.max(0, points[#points][1])
  local map = api.tempo_points()
  local out: {types.TempoPoint} = {}
  for i, p in ipairs(map.tempos) do
    if i == 1 or p.beat < from - 1e-9 or p.beat > to + 1e-9 then out[#out + 1] = p end
  end
  local last: number
  for i, p in ipairs(points) do
    local beat = math.max(0, p[1])
    if not last or beat - last >= step - 1e-9 or i == #points then
      local bpm = clamp_bpm(p[2])
      local at: integer
      for j, q in ipairs(out) do
        if math.abs(q.beat - beat) < 1e-6 then at = j end
      end
      if at == 1 then
        out[1].bpm = bpm
      elseif at then
        out[at].bpm = bpm
      else
        out[#out + 1] = { beat = beat, bpm = bpm, ramp = i < #points }
      end
      last = beat
    end
  end
  -- The stroke's last change holds: what comes after it was not drawn.
  for _, p in ipairs(out) do
    if math.abs(p.beat - last) < 1e-6 and p.beat > 0 then p.ramp = false end
  end
  table.sort(out, function(a: types.TempoPoint, b: types.TempoPoint): boolean return a.beat < b.beat end)
  api.tempo_set_points(out, map.signatures)
end

--- Define the tempo lane's commands with `command`.
function M.commands(command: TempoModule.Define)
  command("tempo.lane", function(ctx: commands.Context): commands.Result
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
  end, {
    desc = "Show or hide the tempo curve under the ruler: `tempo.lane`, `tempo.lane on`, `tempo.lane off`",
    label = "Tempo lane",
    complete = function(): {string} return { "on", "off" } end,
  })

  command("tempo.move", function(ctx: commands.Context): commands.Result
    local a = ctx.args
    local to = a[1]
    if not to then error("tempo.move: say where to, a bar (17) or a bar and beat (17.3)", 0) end
    local from = paw.tempo.point_at(a[2] and paw.tempo.place(a[2]) or paw.cursor.beat)
    if from.beat == 0 then error("the start's tempo does not move", 0) end
    local target = paw.tempo.place(to)
    M.move(from.beat, target, from.bpm)
    paw.notify(string.format("%g bpm moved to %s", from.bpm, paw.time.format(target)))
  end, {
    desc = "Move the tempo change at or before the cursor (or at a bar) to another bar: `tempo.move 17`, `tempo.move 17 9`",
    label = "Move a tempo change",
  })
end

return M
