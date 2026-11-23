-- The pointer's gestures on the tempo map: the tempo and signature
-- changes on the ruler, and the tempo lane under it. Beats are of the
-- window's time; `paw.tempolane` finds the map that each edit changes.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local type TempolaneModule = require("paw.tempolane")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")

local paw = host.paw
local A = M.act
local snap = host.snap
local type Point = host.Point

--- A tempo (`kind` "tempo") or signature change flagged on the ruler at
--- `beat`: "move" it to beat `to` (on the grid; a signature to the bar
--- line nearest), "edit" its value through a prompt, or "remove" it.
function A.tempo_mark(action: string, kind: string, beat: number, to?: number)
  local lane = paw.tempolane
  if kind == "tempo" then
    if action == "remove" then
      lane.remove(beat)
    elseif action == "move" then
      lane.move(beat, paw.cursor.snap(to))
    elseif action == "edit" then
      local point = lane.point_at(beat)
      paw.ui.input(
        {prompt = "tempo at bar " .. paw.time.bar_of(beat) .. ": ", text = string.format("%g", point.bpm)},
        function(text: string)
          local bpm = tonumber(text)
          if bpm then
            lane.add(beat, bpm)
          end
        end
      )
    end
  elseif action == "remove" then
    lane.signature_remove(beat)
  elseif action == "move" then
    -- To the nearest bar line, so that the bars before it stay whole.
    local n = paw.time.bar_of(to)
    local a, b = paw.time.bar_start(n), paw.time.bar_start(n + 1)
    lane.signature_move(beat, math.max(paw.time.bar_start(2), (to - a < b - to) and a or b))
  elseif action == "edit" then
    local num, den = paw.time.signature_at(beat)
    paw.ui.input(
      {prompt = "signature at bar " .. paw.time.bar_of(beat) .. ": ", text = num .. "/" .. den},
      function(text: string)
        local n, d = tostring(text):match("^%s*(%d+)%s*/%s*(%d+)%s*$")
        if n then
          lane.signature_set(beat, tonumber(n) as integer, tonumber(d) as integer)
        end
      end
    )
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
