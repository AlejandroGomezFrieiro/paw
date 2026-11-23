-- The pointer's gestures on the tempo map: the tempo and signature
-- changes on the ruler, and the tempo lane under it.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local options = require("paw.options")
local type TempolaneModule = require("paw.tempolane")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")

local paw = host.paw
local opt = options.opt
local A = M.act
local snap = host.snap
local type Point = host.Point

--- A tempo (`kind` "tempo") or signature change flagged on the ruler at
--- `beat`: "move" it to beat `to` (on the grid; a signature to the bar
--- line nearest), "edit" its value through a prompt, or "remove" it.
function A.tempo_mark(action: string, kind: string, beat: number, to?: number)
  local map = api.tempo_points()
  local tempos, signatures = map.tempos, map.signatures
  local index: integer
  local beats: {number} = {}
  if kind == "tempo" then
    for i, p in ipairs(tempos) do
      beats[i] = p.beat
    end
  else
    for i, p in ipairs(signatures) do
      beats[i] = p.beat
    end
  end
  for i, b in ipairs(beats) do
    if math.abs(b - beat) < 1e-6 then
      index = i
    end
  end
  if not index or index == 1 then
    return
  end
  local was = beats[index]
  if action == "remove" then
    if kind == "tempo" then
      api.tempo_remove(was)
    else
      api.signature_remove(was)
    end
  elseif action == "move" then
    local moved: number
    if kind == "tempo" then
      local point = table.remove(tempos, index)
      point.beat = math.max(opt.grid, paw.cursor.snap(to))
      tempos[#tempos + 1] = point
      moved = point.beat
    else
      local point = table.remove(signatures, index)
      -- To the nearest bar line, so that the bars before it stay whole.
      local n = paw.time.bar_of(to)
      local a, b = paw.time.bar_start(n), paw.time.bar_start(n + 1)
      point.beat = math.max(paw.time.bar_start(2), (to - a < b - to) and a or b)
      signatures[#signatures + 1] = point
      moved = point.beat
    end
    if math.abs(moved - was) > 1e-9 then
      api.tempo_set_points(tempos, signatures)
    end
  elseif action == "edit" then
    local where = "bar " .. paw.time.bar_of(was)
    if kind == "tempo" then
      local point = tempos[index]
      paw.ui.input(
        {prompt = "tempo at " .. where .. ": ", text = string.format("%g", point.bpm)},
        function(text: string)
          local bpm = tonumber(text)
          if bpm then
            api.tempo_set(point.beat, bpm)
          end
        end
      )
    else
      local point = signatures[index]
      paw.ui.input(
        {prompt = "signature at " .. where .. ": ", text = point.num .. "/" .. point.den},
        function(text: string)
          local n, d = tostring(text):match("^%s*(%d+)%s*/%s*(%d+)%s*$")
          if n then
            api.signature_set(point.beat, tonumber(n) as integer, tonumber(d) as integer)
          end
        end
      )
    end
  end
end

-- The tempo lane under the ruler. A frontend names a height in it as a
-- fraction, 0 at the bottom, as for the automation lanes.

--- Show the tempo lane, or hide it.
function A.tempo_lane(on?: boolean): boolean
  if on == nil then
    return paw.tempolane.toggle()
  end
  paw.tempolane.show(on)
  return on
end

--- A click on the lane: a tempo change at the beat, on the grid.
function A.tempo_point_add(beat: number, fraction: number)
  paw.tempolane.add(snap(beat), paw.tempolane.bpm(fraction))
end

--- A change dragged to a beat and a height. The first change, the start's,
--- only changes its tempo.
function A.tempo_point_move(beat: number, to: number, fraction: number)
  paw.tempolane.move(beat, snap(to), paw.tempolane.bpm(fraction))
end

function A.tempo_point_remove(beat: number)
  paw.tempolane.remove(beat)
end

--- Make the change at `beat` ramp to the next, or hold again.
function A.tempo_point_ramp(beat: number): boolean
  return paw.tempolane.ramp(beat)
end

--- Draw over the lane with a pencil: `points` are `{ beat, fraction }`.
function A.tempo_draw(points: {Point})
  local out: {TempolaneModule.StrokePoint} = {}
  for i, p in ipairs(points) do
    out[i] = {snap(p[1]), paw.tempolane.bpm(p[2])}
  end
  paw.tempolane.draw(out)
end
