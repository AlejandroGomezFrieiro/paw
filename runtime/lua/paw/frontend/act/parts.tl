-- The pointer's gestures on parts: faders, pans, flags, the input and
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
local part_flag = host.part_flag
local part_number = host.part_number
local type Choice = host.Choice

function A.part_command(id: integer, line: string)
  A.select(id)
  commands.exec(line)
end

function A.set_volume(part: integer, db: number)
  api.part_set(part, {volume = util.fader_db(part_number(part, "volume"), db)})
end

--- A fader, a pan or a parameter is under the pointer (`on`), or let go:
--- in touch mode it writes automation for as long as it is held. `device`
--- and `param` name a parameter; 0 and "" for a fader or a pan.
function A.hold(part: integer, target: string, device: integer, param: string, on: boolean)
  if target ~= "param" then
    device, param = nil, nil
  end
  api.automation_hold(part, target, device, param, on)
end

function A.set_pan(part: integer, pan: number)
  api.part_set(part, {pan = util.clamp(pan, -1, 1)})
end

function A.toggle(part: integer, flag: string)
  local patch: {string: boolean} = {[flag] = not part_flag(part, flag)}
  api.part_set(part, patch as types.PartChanges)
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

--- Choose a part's input from its menu (`M.input_menu`): the `index`th
--- entry, from 1, under the heading `group`.
function A.choose_input(part: integer, group: string, index: integer)
  local choice = nth(paw.audio.choices(part), group, index)
  if not choice then
    return
  end
  paw.audio.choose(part, choice)
  A.select(part)
end

--- Choose an audio device or a block size from `M.engine_menu`.
function A.choose_engine(group: string, index: integer)
  local choice = nth(paw.audio.engine_choices(), group, index)
  if choice then
    paw.audio.choose_engine(choice)
  end
end

--- A click on a device of a part's chain, as a mixer strip lists them: the
--- part becomes the cursor's and the inspector gets the keyboard, on
--- the `index`th device, from 1.
function A.pick_device(part: integer, index: integer)
  A.select(part)
  local device = api.part_get(part).devices[index]
  if device then
    host.devices():show(device)
  end
  paw.ui.focus("inspector")
end

function A.rename_part(part: integer, name: string)
  name = name:match("^%s*(.-)%s*$")
  if name ~= "" then
    api.part_set(part, {name = name})
  end
end

--- Give a part one of the theme's colours by name, any `#rrggbb`, or "none".
function A.color_part(part: integer, colour: string)
  A.part_command(part, "part.color " .. colour)
end

--- Drag a part's header to another place among the drawn rows, from 1.
--- It goes into the group of the part drawn above it where it lands (or
--- into that part, if it is an open group), and out of its own group if it
--- lands outside it. A group takes its parts along.
function A.move_part(part: integer, index: integer)
  local groups = paw.groups
  -- The row is among the parts that are drawn; the list may hold more.
  local rows = groups.rows()
  local target = rows[util.clamp(index, 1, #rows) as integer]
  -- `part_move` counts among the parts of the part's place.
  for place, id in ipairs(paw.routes.peers(part)) do
    if id == target then
      api.part_move(part, place)
    end
  end
  local above: integer
  rows = groups.rows()
  for i, id in ipairs(rows) do
    if id == part then
      above = rows[i - 1]
    end
  end
  local want: integer
  if above then
    want = groups.is_group(above) and not groups.folded(above) and above or groups.of(above)
  end
  if want ~= groups.of(part) then
    if want then
      -- A group cannot go inside itself; then it stays in its own group.
      pcall(groups.add, part, want)
    else
      while groups.of(part) do
        groups.remove(part, true)
      end
    end
  end
  if groups.is_group(part) then
    groups.gather(part)
  end
  local group = groups.of(part)
  if group then
    groups.gather(group)
  end
end

--- Drag a part's bottom edge: its height, as a share of the zoom's height
--- that every part has (`1` for that height, which is then not kept).
function A.set_part_height(part: integer, share: number)
  api.part_set(part, {height = share})
end

--- A press on one of a part's M, S or R buttons swept down across others:
--- each it crosses is set as the first was (`flag` is "mute", "solo" or
--- "armed").
function A.set_flag(part: integer, flag: string, on: boolean)
  if flag ~= "mute" and flag ~= "solo" and flag ~= "armed" then
    error("not a flag of a part: " .. tostring(flag), 2)
  end
  local patch: {string: boolean} = {[flag] = on and true or false}
  api.part_set(part, patch as types.PartChanges)
end

--- The same, for the drawn parts from row `row0` to `row1` (from 1, either
--- way round): where a sweep has gone so far.
function A.sweep_flag(row0: integer, row1: integer, flag: string, on: boolean)
  local rows = paw.groups.rows()
  for row = math.max(1, math.min(row0, row1)), math.min(#rows, math.max(row0, row1)) do
    A.set_flag(rows[row], flag, on)
  end
end

--- Fold a group or a fold of parts away, or open it: a click on its
--- triangle. View state of the window (paw/folds.tl).
function A.fold(part: integer)
  paw.folds.toggle(part)
end
