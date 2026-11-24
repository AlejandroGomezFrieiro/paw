-- Where each view shows things with an address (paw/address.tl), so that
-- diagnostics, hover and fixes work on whatever is under the cursor in any
-- view, and `]d` `[d` go between what a view can show (see `paw.ui.locator`).
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type objects = require("paw.objects")
local type Roll = require("paw.views.pianoroll")

local type Location = contracts.Location

--- The piano roll (paw/views/pianoroll.tl).
local type PianoRoll = Roll.PianoRoll

--- A row of the device panel: a device, a parameter of it, or its picture.
local record DeviceRow
  device: objects.Device
  param: types.ParamInfo
  picture: boolean
end

--- The inspector (paw/views/inspector.lua), as far as this module reads
--- it: its rows, the row of its cursor, and `show`, which puts the cursor
--- of the devices view on a device and gives the row of a parameter.
local record Devices
  row: integer
  rows: function(self: Devices): {DeviceRow}
  show: function(self: Devices, device: integer, key?: string): integer
end

-- No module requires this one, so it sees the global `paw` with its types.
local A = paw.address

--- The row of each part that the window in front shows, by id: the
--- parts of the song, or of the subproject that the window is inside.
--- The master (of the song, or of the subproject) is the row after the last.
local function rows(): {integer: integer}
  local inside = paw.scope.nest()
  local list = api.part_list(inside and {nest = inside.id} or nil)
  local out: {integer: integer} = {}
  for i, id in ipairs(list) do
    out[id] = i
  end
  out[inside and api.nest_get(inside.id).master or 0] = #list + 1
  return out
end

local function time_of(location: Location): number
  local t = location.selector and location.selector.time
  return t and t[1] or nil
end

-- The piano roll: notes and stretches of its clip.
local roll = paw.ui.views:get("pianoroll") as PianoRoll
paw.ui.locator(
  "pianoroll",
  {
    at = function(): Location
      local id = roll.clip_id
      if not id then
        return nil
      end
      local n = api.clip_note_at(id, roll.pitch, roll.beat)
      if n and n.id then
        return A.location(A.note(id, n.id))
      end
      return A.location(A.clip(id), {time = {roll.beat, roll.beat}, pitch = {roll.pitch, roll.pitch}})
    end,
    position = function(): {number} return {roll.beat, 127 - roll.pitch} end,
    place = function(location: Location, anywhere?: boolean): {number}
      local p = A.parse(location.uri)
      if not p or not p.clip or (p.kind ~= "clip" and p.kind ~= "note") then
        return nil
      end
      if p.clip ~= roll.clip_id then
        return anywhere and {0} or nil
      end
      local first: types.Note
      local ids = p.kind == "note" and {p.note} or (location.selector and location.selector.notes) or {}
      for _, id in ipairs(ids) do
        local n = A.find_note(p.clip, id)
        if n and (not first or n.start < first.start or (n.start == first.start and n.pitch > first.pitch)) then
          first = n
        end
      end
      if first then
        return {first.start, 127 - first.pitch}
      end
      return {time_of(location) or 0, 0}
    end,
    go = function(location: Location)
      local p = A.parse(location.uri)
      if p.clip ~= roll.clip_id then
        roll:edit(paw.clip(p.clip))
      end
      local at = paw.ui.locators.pianoroll.place(location)
      if at and at[2] and at[2] > 0 then
        roll:set(127 - at[2] as integer, at[1])
      else
        roll:set(nil, at and at[1] or 0)
      end
    end,
  }
)

-- The arrange view: clips, parts and what is on them, stretches of time.
local function arrange_place(location: Location): {number}
  local p = A.parse(location.uri)
  if not p or p.kind == "render" or (p.kind == "project" and not time_of(location)) then
    return nil
  end
  local row = rows()
  if p.kind == "project" or p.kind == "tempo" or p.kind == "marker" then
    return {time_of(location) or 0, 0}
  end
  if p.clip then
    local ok, c = pcall(api.clip_get, p.clip)
    if not ok then
      return nil
    end
    return {c.start + (time_of(location) or 0), row[c.part] or 0}
  end
  local part = A.part_of(location.uri)
  if part and row[part] then
    return {time_of(location) or 0, row[part]}
  end
  return nil
end

paw.ui.locator(
  "arrange",
  {
    at = function(): Location
      local clip = paw.cursor.clip()
      if clip then
        return A.location(A.clip(clip.id), {time = {paw.cursor.beat - clip.start, paw.cursor.beat - clip.start}})
      end
      local id = paw.cursor.part_id()
      return id and A.location(A.part(id), {time = {paw.cursor.beat, paw.cursor.beat}}) or nil
    end,
    position = function(): {number} return {paw.cursor.beat, rows()[paw.cursor.part_id() or 0] or 0} end,
    place = arrange_place,
    go = function(location: Location)
      local at = arrange_place(location)
      local part = A.part_of(location.uri)
      if not part then
        local p = A.parse(location.uri)
        local ok, c: boolean, types.Clip
        if p and p.clip then
          ok, c = pcall(api.clip_get, p.clip)
        end
        part = ok and c.part or nil
      end
      -- The master has no row: the cursor keeps its part.
      if part and part ~= 0 then
        paw.cursor.set_part(part)
      end
      if at then
        paw.cursor.set_beat(math.max(0, at[1]))
      end
    end,
  }
)

-- The mixer: a strip for each part.
paw.ui.locator(
  "mixer",
  {
    at = function(): Location local id = paw.cursor.part_id(); return id and A.location(A.part(id)) or nil end,
    position = function(): {number} return {rows()[paw.cursor.part_id() or 0] or 0} end,
    place = function(location: Location): {number}
      local part = A.part_of(location.uri)
      local row = part and rows()[part]
      return row and {row} or nil
    end,
    go = function(location: Location)
      local part = A.part_of(location.uri)
      if part then
        paw.cursor.set_part(part)
      end
    end,
  }
)

-- The inspector: the node under the cursor of the devices view.
local devices = paw.ui.views:get("inspector") as Devices
local function device_row(device: integer, param: string): integer
  for i, row in ipairs(devices:rows()) do
    if
      row.device
      and row.device.id == device
      and not row.picture
      and ((param == nil and not row.param) or (row.param and row.param.key == param))
    then
      return i
    end
  end
end
paw.ui.locator(
  "inspector",
  {
    at = function(): Location
      local row = devices:rows()[devices.row or 1]
      if not (row and row.device) then
        local id = paw.cursor.part_id()
        return id and A.location(A.part(id)) or nil
      end
      if row.param then
        return A.location(A.param(row.device.id, row.param.key))
      end
      return A.location(A.device(row.device.id))
    end,
    position = function(): {number} return {devices.row or 1} end,
    place = function(location: Location, anywhere?: boolean): {number}
      local p = A.parse(location.uri)
      if not p or (p.kind ~= "device" and p.kind ~= "param") then
        return nil
      end
      if anywhere then
        return {0}
      end
      if p.part ~= paw.cursor.part_id() then
        return nil
      end
      -- A device that the inspector does not show is in the part: its
      -- place is the start, where `go` shows it.
      return {device_row(p.device, p.param) or 0}
    end,
    go = function(location: Location)
      local p = A.parse(location.uri)
      if p.part ~= paw.cursor.part_id() then
        paw.cursor.set_part(p.part)
      end
      devices:show(p.device, p.param)
      api.ui_redraw()
    end,
  }
)

return true
