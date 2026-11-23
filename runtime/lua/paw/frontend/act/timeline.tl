-- The pointer's gestures on the timeline: the record button, the loop and
-- punch ranges, the ruler, take lanes, and a stretch of time chosen.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")
local clips = require("paw.frontend.act.clips")
local timegrid = require("paw.timegrid")

local paw = host.paw
local A = M.act
local snap = host.snap
local to_arrange = host.to_arrange
local track_flag = host.track_flag

--- The record button. With nothing being recorded: arm the selected track
--- if no track is armed, then record from the playhead. Otherwise: end the
--- take and stop.
function A.record()
  local t = api.transport_get()
  if t.recording or t.take then
    paw.transport.recording = false
    if t.playing then
      paw.transport.stop()
    end
    return
  end
  local armed = false
  for _, id in ipairs(api.track_list({all = true})) do
    armed = armed or track_flag(id, "armed")
  end
  if not armed then
    local track = paw.cursor.track()
    if not track then
      return paw.notify("nothing to record on: select a track, or arm one with its R button", "warn")
    end
    track.armed = true
    paw.notify("recording on " .. track.name .. ": it was armed for you (its R button)")
  end
  paw.transport.record()
end

--- Drag along the ruler: loop that stretch. Too short a drag is a click,
--- which only moves the playhead.
function A.set_loop(from: number, to: number)
  from, to = snap(math.min(from, to)), snap(math.max(from, to))
  if to - from < timegrid.step() then
    return paw.transport.seek(from)
  end
  paw.transport.loop_start, paw.transport.loop_end = from, to
  paw.transport.loop_enabled = true
end

--- Drag an edge of the loop, "start" or "end", to a beat on the grid; it
--- stays at least a grid step long.
function A.set_loop_edge(edge: string, beat: number)
  local t = paw.transport
  beat = snap(beat)
  if edge == "start" then
    t.loop_start = math.min(beat, t.loop_end - timegrid.step())
  else
    t.loop_end = math.max(beat, t.loop_start + timegrid.step())
  end
end

--- Drag an edge of the punch range, "start" or "end", to a beat on the
--- grid (anywhere with `free`); it stays at least a grid step long.
function A.set_punch_edge(edge: string, beat: number, free?: boolean)
  local t = paw.transport
  beat = free and math.max(0, beat) or snap(beat)
  local least = free and 1 / 64 or timegrid.step()
  if edge == "start" then
    t.punch_start = math.min(beat, t.punch_end - least)
  else
    t.punch_end = math.max(beat, t.punch_start + least)
  end
end

--- Punch in and out between two beats, on the grid, and turn punching on.
function A.set_punch(from: number, to: number)
  from, to = snap(math.min(from, to)), snap(math.max(from, to))
  if to - from < timegrid.step() then
    return
  end
  paw.transport.punch_start, paw.transport.punch_end = from, to
  paw.transport.punch_enabled = true
end

--- Show a track's take lanes under its clips, or hide them. Returns
--- whether they show now.
function A.take_lanes(track: integer): boolean
  return paw.takes.toggle_lanes(track)
end

--- A drag across take lane `take` of a track, from beat `from` to `to`:
--- that take plays over the stretch (see `paw.takes.comp`). The ends land
--- on the grid unless `free` (Shift). A stretch shorter than a grid step is
--- a click, which chooses the take for the piece under the pointer. One
--- undo step. Returns how many pieces play the take now.
function A.comp(track: integer, take: integer, from: number, to: number, free?: boolean): integer
  local a, b = math.min(from, to), math.max(from, to)
  if not free then
    a, b = snap(a), snap(b)
  end
  a = math.max(0, a)
  if b - a < (free and 1 / 64 or timegrid.step()) - 1e-9 then
    return A.take_click(track, take, math.min(from, to)) and 1 or 0
  end
  local n = paw.takes.comp(track, take, a, b)
  if n > 0 then
    paw.cursor.set_track(track)
  end
  return n
end

--- A click on take lane `take` of a track: the piece under the pointer
--- plays that take. Returns its clip, or nil when there is none there.
function A.take_click(track: integer, take: integer, beat: number): integer
  local c = paw.takes.choose_at(track, take, beat)
  if c then
    clips.set_pointing(true)
    to_arrange()
    paw.cursor.set_track(track)
    clips.set_pointing(false)
  end
  return c and c.id or nil
end

--- A click on the ruler: the edit cursor goes to the beat, on the grid,
--- and the playhead with it.
function A.ruler_click(beat: number)
  beat = snap(beat)
  clips.set_pointing(true)
  paw.cursor.set_beat(beat)
  clips.set_pointing(false)
  paw.transport.seek(beat)
end

--- Drag across empty lanes: select that stretch of time on those tracks,
--- as visual mode does, for the keys and the menu to act on. Rows are
--- places in the track list, from 1.
function A.select_range(row0: integer, beat0: number, row1: integer, beat1: number)
  local tracks = paw.groups.rows()
  if #tracks == 0 then
    return
  end
  to_arrange()
  local clamp = util.clamp
  paw.cursor.set_track(tracks[clamp(row0, 1, #tracks) as integer])
  paw.cursor.set_beat(snap(math.min(beat0, beat1)))
  paw.keymap.visual_start("v")
  paw.cursor.set_track(tracks[clamp(row1, 1, #tracks) as integer])
  paw.cursor.set_beat(snap(math.max(beat0, beat1)))
end
