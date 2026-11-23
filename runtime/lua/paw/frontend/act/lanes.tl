-- The pointer's gestures on automation lanes and on a MIDI clip's
-- controller moves.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local type types = require("paw.types")
local type objects = require("paw.objects")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")
local timegrid = require("paw.timegrid")

local paw = host.paw
local A = M.act
local by_beat = host.by_beat
local note_snap = host.note_snap
local snap = host.snap
local type Point = host.Point

--- The lanes of a lane's part are no longer shown as rows.
function A.hide_lane_rows(lane: integer)
  paw.lanes.open(api.lane_get(lane).part, false)
end

--- Show a part's lanes as rows of their own under it, or hide them. A
--- part that has none yet gets one for its fader, to draw on.
function A.lane_rows(part: integer): boolean
  if not paw.lanes.is_open(part) and #api.lane_list(part) == 0 then
    A.lane(part, "volume")
  end
  return paw.lanes.toggle(part)
end

-- Automation. A lane is drawn over a stretch of its range (`lane_span`),
-- and a frontend names a height in it as a fraction, 0 at the bottom.

local function lane_value(lane: integer, fraction: number): number
  local lo, hi = M.lane_span(api.lane_get(lane))
  return lo + util.clamp(fraction, 0, 1) * (hi - lo)
end

--- The lane of a part for "volume", "pan", or a parameter (by key) of one
--- of its devices: the one there is, or a new one.
function A.lane(part: integer, target: types.LaneTarget, device?: integer, param?: string): integer
  for _, lane in ipairs(api.lane_list(part)) do
    if lane.target == target and (target ~= "param" or (lane.device == device and lane.param == param)) then
      return lane.id
    end
  end
  return api.lane_add(part, {target = target, device = device, param = param})
end

function A.add_point(lane: integer, beat: number, fraction: number)
  api.lane_add_point(lane, snap(beat), lane_value(lane, fraction))
end

function A.move_point(lane: integer, index: integer, beat: number, fraction: number)
  local points = api.lane_points(lane)
  table.remove(points, index)
  points[#points + 1] = {snap(beat), lane_value(lane, fraction)}
  api.lane_set_points(lane, points)
end

--- Draw over a lane with a pencil: `points` are `{ beat, fraction }` as
--- they were drawn. They replace what the lane held over the stretch drawn
--- across, at most one to a quarter of a grid step.
function A.draw_lane(lane: integer, points: {Point})
  if #points == 0 then
    return
  end
  table.sort(points, by_beat)
  local step = timegrid.step() / 4
  local from, to = math.max(0, points[1][1]), math.max(0, points[#points][1])
  local out: {types.LanePoint} = {}
  for _, p in ipairs(api.lane_points(lane)) do
    if p[1] < from - 1e-9 or p[1] > to + 1e-9 then
      out[#out + 1] = p
    end
  end
  local last: number
  for i, p in ipairs(points) do
    local beat = math.max(0, p[1])
    if not last or beat - last >= step - 1e-9 or i == #points then
      out[#out + 1] = {beat, lane_value(lane, p[2])}
      last = beat
    end
  end
  api.lane_set_points(lane, out)
end

function A.toggle_lane(lane: integer)
  api.lane_set(lane, {enabled = not api.lane_get(lane).enabled})
end

function A.clear_lane(lane: integer)
  api.lane_set_points(lane, {})
end

-- Controller moves in a MIDI clip: the pitch wheel, pressure, or a control
-- change by number. Heights are fractions, 0 at the bottom; the wheel rests
-- in the middle.

local function control_value(kind: types.ControlType, fraction: number): number
  fraction = util.clamp(fraction, 0, 1)
  return kind == "bend" and fraction * 2 - 1 or fraction
end

--- Draw controller moves with a pencil: `points` are `{ beat, fraction }`
--- in the clip. They replace the moves of that kind over the stretch drawn
--- across, one to a note-grid step.
function A.draw_controls(clip: integer, kind: types.ControlType, number: integer, points: {Point})
  if #points == 0 then
    return
  end
  table.sort(points, by_beat)
  local c = paw.clip(clip)
  local grid = timegrid.step("note")
  local from, to = note_snap(points[1][1]), note_snap(points[#points][1])
  local same = function(control: types.Control): boolean
    return control.type == kind and control.key == nil and (kind ~= "cc" or control.number == number)
  end
  local out: {objects.ControlInput} = {}
  for _, control in ipairs(c:controls()) do
    if not (same(control) and control.start >= from - 1e-9 and control.start <= to + 1e-9) then
      out[#out + 1] = control as objects.ControlInput
    end
  end
  -- Each step takes the height drawn nearest to it.
  local steps, nearest: {number: number}, {number: number} = {}, {}
  for _, p in ipairs(points) do
    local at = note_snap(p[1])
    local off = math.abs(p[1] - at)
    if not nearest[at] or off < nearest[at] then
      steps[at], nearest[at] = p[2], off
    end
  end
  for beat = from, to + 1e-9, grid do
    local fraction = steps[note_snap(beat)]
    if fraction and beat < c.length then
      out[#out + 1] = {
        start = note_snap(beat),
        type = kind,
        number = kind == "cc" and number or nil,
        value = control_value(kind, fraction),
      }
    end
  end
  c:set_controls(out)
end

--- Remove the moves of one kind from a clip.
function A.clear_controls(clip: integer, kind: types.ControlType, number: integer)
  local c = paw.clip(clip)
  local out: {objects.ControlInput} = {}
  for _, control in ipairs(c:controls()) do
    if not (control.type == kind and control.key == nil and (kind ~= "cc" or control.number == number)) then
      out[#out + 1] = control as objects.ControlInput
    end
  end
  c:set_controls(out)
end

-- Moves of the strip chosen, moved and taken away, drawn as a line, and
-- the event list: `paw.controls` says what each does.
-- A window names a mode by number: 0 alone, 1 add, 2 toggle.
local modes: {integer: string} = {[0] = "only", [1] = "add", [2] = "toggle"}
local function mode_of(mode: integer | string): string
  return modes[mode as integer] or mode as string
end
function A.select_control(clip: integer, place: integer, mode: integer | string)
  paw.controls.select(clip, place, mode_of(mode))
end
function A.select_controls(
  clip: integer,
  kind: string,
  number: integer,
  beat0: number,
  low: number,
  beat1: number,
  high: number,
  mode: integer | string
): integer
  return paw.controls.select_box(clip, kind, number, beat0, low, beat1, high, mode_of(mode))
end
function A.select_all_controls(clip: integer, kind: string, number: integer): integer
  return paw.controls.select_box(clip, kind, number, -1, 0, paw.clip(clip).length + 1, 1)
end
function A.clear_control_selection(clip: integer)
  paw.controls.clear(clip)
end
function A.move_controls(clip: integer, dbeat: number, dfraction: number, free?: boolean | integer): integer
  return paw.controls.move(clip, dbeat, dfraction, free == true or free == 1)
end
function A.remove_chosen_controls(clip: integer): integer
  return paw.controls.remove(clip)
end
function A.line_controls(
  clip: integer,
  kind: string,
  number: integer,
  beat0: number,
  f0: number,
  beat1: number,
  f1: number,
  free?: boolean | integer
): integer
  return paw.controls.line(clip, kind, number, beat0, f0, beat1, f1, free == true or free == 1)
end

--- The event list of the clip in the piano roll, in a window of its own.
function A.open_event_list(clip: integer)
  paw.canvas.open_view("eventlist", {title = "Events · " .. paw.clip(clip).name, width = 520, height = 440})
end

function A.remove_point(lane: integer, index: integer)
  local points = api.lane_points(lane)
  table.remove(points, index)
  api.lane_set_points(lane, points)
end
