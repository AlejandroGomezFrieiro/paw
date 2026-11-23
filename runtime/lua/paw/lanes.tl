-- Automation lanes as rows of the arrange view: under a part whose lanes are
-- open, each of its lanes (volume, pan, a device's parameter) is a row of its
-- own, two lines high, that the cursor can stand on.
--
--   paw.lanes.open(part)             -- show the part's lanes as rows
--   paw.lanes.toggle(part)
--   paw.lanes.lines()                 -- every row: { part = id } or { part = id, lane = id }
--   paw.lanes.name(lane), paw.lanes.format(lane, value)
--
-- Which parts have their lanes open is kept for the session (it survives
-- `:reload`), not in the project: opening lanes is not an edit to undo.
-- `paw.groups.rows({ lanes = true })` is `lines()`; the cursor is on a lane
-- when `paw.cursor.lane_id()` says so.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local type types = require("paw.types")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")

--- A part: its id, or the part itself (`paw.part`).
local type PartRef = integer | contracts.PartHandle

--- A lane: its id, or the lane as `paw.api.lane_get` gives it.
local type LaneRef = integer | types.Lane

--- A row of the arrange view: a part, or a lane shown under it.
local record Row
  part: integer
  lane: integer
end

--- The payload of `lanes.changed`: nothing but that the shown lanes changed.
local record Changed
end

-- What this module reads of `paw`, which paw/init.lua makes.
local record Draw
  pan_text: function(number): string
end
local record Groups
  rows: function(): {integer}
end
--- paw/frontend.tl, as far as this module calls it: the frontend names
--- the types of this module, and two modules cannot name each other's types.
local record Frontend
  format_value: function(param: types.ParamInfo, value: number): string
end
local record Paw is partial.Paw
  draw: Draw
  groups: Groups
  frontend: Frontend
end
local paw = (_G as {string: Paw}).paw

local record M
  type Row = Row
  type LaneRef = LaneRef
  type Changed = Changed
  --- The automation modes a part can be in (`part.automation`), in the
  --- order `:automation` steps through them, and what each does.
  modes: {types.AutoMode}
  mode_text: {types.AutoMode: string}
  --- The event `lanes.changed`: the lanes shown (automation or takes) changed.
  changed: events.Event<Changed>
  param_of: function(lane: types.Lane): types.ParamInfo, types.Device
end

M.changed = events.event("lanes.changed")

local open: {integer: boolean} = {}
do
  local saved = api.state_get("lanes_open")
  if type(saved) == "table" then
    for key, on in pairs(saved as {string: boolean}) do
      local id = tonumber(key)
      if on and id then
        open[id as integer] = true
      end
    end
  end
end

local function save()
  local out: {string: boolean} = {}
  for id, on in pairs(open) do
    if on then
      out[tostring(id)] = true
    end
  end
  api.state_set("lanes_open", out)
  api.ui_redraw()
  -- A graphical frontend draws them too.
  events.emit(M.changed, {})
end

local function id_of(part: PartRef): integer
  if part is contracts.PartHandle then
    return part.id
  end
  return part
end

local function lane_of(lane: LaneRef): types.Lane
  -- A test of the table, as `is integer` is a test with math.type, which LuaJIT does not have.
  if lane is types.Lane then
    return lane
  end
  return api.lane_get(lane)
end

--- True if the lanes of a part show as rows.
function M.is_open(part: PartRef): boolean
  return open[id_of(part)] == true
end

--- Show a part's lanes as rows, or hide them (`on` false).
function M.open(part: PartRef, on?: boolean)
  local id = id_of(part)
  open[id] = on ~= false or nil
  save()
end

--- Show the automation lanes of a part, or hide them. Returns true if they show.
function M.toggle(part: PartRef): boolean
  M.open(part, not M.is_open(part))
  return M.is_open(part)
end

--- True if a part has its lanes open.
function M.any_open(): boolean
  return next(open) ~= nil
end

--- The lanes shown under a part: none when they are closed.
function M.shown(part: PartRef): {types.Lane}
  local id = id_of(part)
  if not open[id] then
    return {}
  end
  local ok, list = pcall(api.lane_list, id)
  return ok and list or {}
end

--- Every row of the arrange view in order: each part drawn, then its lanes
--- when they are open.
function M.lines(): {Row}
  local out: {Row} = {}
  for _, id in ipairs(paw.groups.rows()) do
    out[#out + 1] = {part = id}
    for _, lane in ipairs(M.shown(id)) do
      out[#out + 1] = {part = id, lane = lane.id}
    end
  end
  return out
end

--- The parameter a lane moves: its name, and the parameter's description
--- for a device's lane.
local function param_of(lane: types.Lane): types.ParamInfo, types.Device
  if lane.target ~= "param" then
    return nil
  end
  local ok, d = pcall(api.device_get, lane.device)
  if not ok then
    return nil
  end
  for _, p in ipairs(d.param_info) do
    if p.key == lane.param then
      return p, d
    end
  end
end

M.modes = {"read", "touch", "latch", "write", "off"}
M.mode_text = {
  read = "the lanes play; moving a control writes nothing",
  touch = "a control writes while it is held or moved, then the lane takes over again",
  latch = "a control writes from its first move until the song stops",
  write = "everything the lanes move is written over while the song plays",
  off = "the lanes are kept but do not play",
}

--- What a lane is called: Volume, Pan, or its device and parameter.
function M.name(lane: LaneRef): string
  local l = lane_of(lane)
  if l.target == "volume" then
    return "Volume"
  end
  if l.target == "pan" then
    return "Pan"
  end
  if l.target == "state" then
    local ok, d = pcall(api.device_get, l.device)
    return (ok and d and d.name or "?") .. " › state"
  end
  local p, d = param_of(l)
  return (d and d.name or "?") .. " › " .. (p and p.name or tostring(l.param))
end

--- A value of a lane as its target shows it: "-6.0 dB", "L30", "800 Hz".
function M.format(lane: LaneRef, value: number): string
  local l = lane_of(lane)
  if l.target == "volume" then
    return string.format("%.1f dB", value)
  end
  if l.target == "pan" then
    return paw.draw.pan_text(value)
  end
  if l.target == "state" then
    local index = math.floor((value or 0) + 0.5)
    return (l.states or {})[index + 1] or "-"
  end
  local p = param_of(l)
  return p and paw.frontend.format_value(p, value) or string.format("%g", value)
end

--- How far `+` and `-` move a point: a dB, 5% of pan, one choice, or a
--- hundredth of the parameter's range.
function M.step(lane: LaneRef): number
  local l = lane_of(lane)
  if l.target == "volume" then
    return 1
  end
  if l.target == "pan" then
    return 0.05
  end
  if l.target == "state" then
    return 1
  end
  local p = param_of(l)
  if p and #p.choices > 0 then
    return 1
  end
  return (l.max - l.min) / 100
end

--- The parameter's description, for reading typed values.
M.param_of = param_of

-- One entry of a part: quicker than the whole part, which lists its clips (api.rs).
local part_number = api.part_get as function(integer, string): number

--- What a lane's target is at a beat: the curve's value, or with no points
--- yet the target's own value.
function M.value_at(lane: LaneRef, beat: number): number
  local l = lane_of(lane)
  local ok, v = pcall(api.lane_value_at, l.id, beat)
  if ok and v then
    return v
  end
  if l.target == "volume" or l.target == "pan" then
    return part_number(l.part, l.target)
  end
  if l.target == "state" then
    return 0
  end
  local d = api.device_get(l.device)
  return d.params[l.param] or 0
end

--- The point at a beat, within `reach` beats: its index in the lane's
--- points, and the point { beat, value }.
function M.point_at(lane_id: integer, beat: number, reach?: number): integer, types.LanePoint
  local best: types.LanePoint
  local at: integer
  for i, p in ipairs(api.lane_points(lane_id)) do
    local d = math.abs(p[1] - beat)
    if d <= (reach or 1e-9) and (not best or d < math.abs(best[1] - beat)) then
      best, at = p, i
    end
  end
  return at, best
end

--- Change the lane's points with `fn(points)`, which edits the list in place.
function M.edit(lane_id: integer, fn: function({types.LanePoint}))
  local points = api.lane_points(lane_id)
  fn(points)
  table.sort(points, function(a: types.LanePoint, b: types.LanePoint): boolean return a[1] < b[1] end)
  api.lane_set_points(lane_id, points)
end

-- A part that goes away takes its open lanes with it.
events.on(
  kernel.part_removed,
  function(event: kernel.PartId)
    if open[event.id] then
      open[event.id] = nil
      save()
    end
  end
)

return M
