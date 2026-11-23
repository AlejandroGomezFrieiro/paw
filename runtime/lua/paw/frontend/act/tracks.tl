-- The pointer's gestures on tracks: faders, pans, flags, the input and
-- the engine, names, colours, order, heights and folds.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local commands = require("paw.commands")
local type types = require("paw.types")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")

local paw = host.paw
local A = M.act
local track_flag = host.track_flag
local track_number = host.track_number
local type Choice = host.Choice

function A.track_command(id: integer, line: string)
  A.select(id)
  commands.exec(line)
end

function A.set_volume(track: integer, db: number)
  api.track_set(track, {volume = util.fader_db(track_number(track, "volume"), db)})
end

--- A fader, a pan or a parameter is under the pointer (`on`), or let go:
--- in touch mode it writes automation for as long as it is held. `device`
--- and `param` name a parameter; 0 and "" for a fader or a pan.
function A.hold(track: integer, target: string, device: integer, param: string, on: boolean)
  if target ~= "param" then
    device, param = nil, nil
  end
  api.automation_hold(track, target, device, param, on)
end

function A.set_pan(track: integer, pan: number)
  api.track_set(track, {pan = util.clamp(pan, -1, 1)})
end

function A.toggle(track: integer, flag: string)
  local patch: {string: boolean} = {[flag] = not track_flag(track, flag)}
  api.track_set(track, patch as types.Track)
end

local function nth(list: {Choice}, group: string, index: integer): Choice
  local n = 0
  for _, choice in ipairs(list) do
    if choice.group == group then
      n = n + 1
      if n == index then
        return choice
      end
    end
  end
end

--- Choose a track's input from its menu (`M.input_menu`): the `index`th
--- entry, from 1, under the heading `group`.
function A.choose_input(track: integer, group: string, index: integer)
  local choice = nth(paw.audio.choices(track), group, index)
  if not choice then
    return
  end
  paw.audio.choose(track, choice)
  A.select(track)
end

--- Choose an audio device or a block size from `M.engine_menu`.
function A.choose_engine(group: string, index: integer)
  local choice = nth(paw.audio.engine_choices(), group, index)
  if choice then
    paw.audio.choose_engine(choice)
  end
end

--- A click on a device of a track's chain, as a mixer strip lists them: the
--- track becomes the cursor's and the device panel gets the keyboard, on
--- the `index`th device, from 1.
function A.pick_device(track: integer, index: integer)
  A.select(track)
  local panel = paw.ui.views.devices
  for row, entry in ipairs(panel:rows()) do
    if not entry.param and entry.device.index == index then
      panel.row = row
    end
  end
  paw.ui.focus("devices")
end

function A.rename_track(track: integer, name: string)
  name = name:match("^%s*(.-)%s*$")
  if name ~= "" then
    api.track_set(track, {name = name})
  end
end

--- Give a track one of the theme's colours by name, any `#rrggbb`, or "none".
function A.color_track(track: integer, colour: string)
  A.track_command(track, "track.color " .. colour)
end

--- Drag a track's header to another place among the drawn rows, from 1.
--- It goes into the group of the track drawn above it where it lands (or
--- into that track, if it is an open group), and out of its own group if it
--- lands outside it. A group takes its tracks along.
function A.move_track(track: integer, index: integer)
  local groups = paw.groups
  -- The row is among the tracks that are drawn; the list may hold more.
  local rows = groups.rows()
  local target = rows[util.clamp(index, 1, #rows) as integer]
  -- `track_move` counts among the tracks of the track's place.
  for place, id in ipairs(paw.routes.peers(track)) do
    if id == target then
      api.track_move(track, place)
    end
  end
  local above: integer
  rows = groups.rows()
  for i, id in ipairs(rows) do
    if id == track then
      above = rows[i - 1]
    end
  end
  local want: integer
  if above then
    want = groups.is_group(above) and not groups.folded(above) and above or groups.of(above)
  end
  if want ~= groups.of(track) then
    if want then
      -- A group cannot go inside itself; then it stays in its own group.
      pcall(groups.add, track, want)
    else
      while groups.of(track) do
        groups.remove(track, true)
      end
    end
  end
  if groups.is_group(track) then
    groups.gather(track)
  end
  local group = groups.of(track)
  if group then
    groups.gather(group)
  end
end

--- Drag a track's bottom edge: its height, as a share of the zoom's height
--- that every track has (`1` for that height, which is then not kept).
function A.set_track_height(track: integer, share: number)
  api.track_set(track, {height = share})
end

--- A press on one of a track's M, S or R buttons swept down across others:
--- each it crosses is set as the first was (`flag` is "mute", "solo" or
--- "armed").
function A.set_flag(track: integer, flag: string, on: boolean)
  if flag ~= "mute" and flag ~= "solo" and flag ~= "armed" then
    error("not a flag of a track: " .. tostring(flag), 2)
  end
  local patch: {string: boolean} = {[flag] = on and true or false}
  api.track_set(track, patch as types.Track)
end

--- The same, for the drawn tracks from row `row0` to `row1` (from 1, either
--- way round): where a sweep has gone so far.
function A.sweep_flag(row0: integer, row1: integer, flag: string, on: boolean)
  local rows = paw.groups.rows()
  for row = math.max(1, math.min(row0, row1)), math.min(#rows, math.max(row0, row1)) do
    A.set_flag(rows[row], flag, on)
  end
end

--- Fold a group or a fold of tracks away, or open it: a click on its
--- triangle. View state of the window (paw/folds.tl).
function A.fold(track: integer)
  paw.folds.toggle(track)
end
