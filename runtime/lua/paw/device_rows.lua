-- The device panel as a grid of rows, so that the grammar works on it: its
-- rows are the devices of the cursor track, each followed by its
-- parameters. `j` `k` go from row to row, `w` `b` from device to device;
-- `+` `-` (and `Ctrl-a` `Ctrl-x` with a count) change the parameter under
-- the cursor, or a device's wet/dry mix on its own row; `d` `y` `p` cut,
-- copy and paste whole devices or the settings of parameters; `gc` bypasses;
-- `V` over rows and any of these does it to them all, and `.` again.
local api, util = paw.api, paw.util
local keymap = paw.keymap
local panel = paw.ui.views.devices
local M = {}

local function rows() return panel:rows() end

--- The row a device's heading is on, and the last row of its parameters.
local function span_of(index)
  local list = rows()
  local id = list[index] and list[index].device.id
  if not id then return nil end
  local first, last
  for i, row in ipairs(list) do
    if row.device.id == id then
      first, last = first or i, i
    end
  end
  return first, last
end

local function to(index)
  panel.row = util.clamp(index, 1, math.max(1, #rows()))
  api.ui_redraw()
end

--- The devices whose heading a region covers, and the parameter rows it
--- covers of the others: { device ids }, { { device, param } }.
local function in_region(region)
  local list, devices, params, whole = rows(), {}, {}, {}
  for i = region.r0, region.r1 do
    local row = list[i]
    if row and not row.param and not row.picture then
      whole[row.device.id] = true
      devices[#devices + 1] = row.device.id
    end
  end
  for i = region.r0, region.r1 do
    local row = list[i]
    if row and row.param and not whole[row.device.id] then params[#params + 1] = row end
  end
  return devices, params
end

-- Rows are the panel's rows; there are no columns.
panel.grid = {
  get = function() return panel.row, 0 end,
  set = function(row) to(row) end,
  step = function() return 1 end,
  rows = true,
}

-- Keys ----------------------------------------------------------------------------------

local map = keymap.set
local lines = { motion = true, linewise = true }
local far_lines = { motion = true, linewise = true, jump = true }
local function dmap(lhs, rhs, desc, opts) map(lhs, rhs, util.merge({ view = "devices", desc = desc }, opts)) end
local function step(n) return function(ctx) to(panel.row + n * (ctx.count or 1)) end end

dmap("j", step(1), "Next row", lines)
dmap("k", step(-1), "Previous row", lines)
dmap("<Down>", step(1), "Next row", lines)
dmap("<Up>", step(-1), "Previous row", lines)
dmap("gg", function(ctx) to(ctx.count or 1) end, "The first row, or row N", far_lines)
dmap("G", function(ctx) to(ctx.count or #rows()) end, "The last row, or row N", far_lines)
dmap("w", function(ctx)
  for _ = 1, ctx.count or 1 do
    local _, last = span_of(panel.row)
    if not last or not rows()[last + 1] then break end
    to(last + 1)
  end
end, "The next device", lines)
dmap("b", function(ctx)
  for _ = 1, ctx.count or 1 do
    local first = span_of(panel.row)
    if not first then break end
    if first < panel.row then
      to(first)
    elseif first > 1 then
      to((span_of(first - 1)))
    end
  end
end, "This device's heading, or the device before", lines)
dmap("e", function(ctx)
  for _ = 1, ctx.count or 1 do
    local _, last = span_of(panel.row)
    if not last then break end
    if last > panel.row then to(last) else
      local _, after = span_of(last + 1)
      if after then to(after) end
    end
  end
end, "The last parameter of this device, or of the next", lines)

-- The value under the cursor: a step of the parameter's range for each of
-- the count; on a device's own row its wet/dry mix.
local function adjust(sign) return function(ctx) panel:adjust(sign * (ctx.count or 1)) end end
dmap("+", adjust(1), "Raise the parameter, or the device's wet mix", { role = "main+" })
dmap("-", adjust(-1), "Lower the parameter, or the device's wet mix", { role = "main-" })
dmap("<C-a>", adjust(1), "Raise the parameter a step for each of the count", { role = "main+" })
dmap("<C-x>", adjust(-1), "Lower the parameter a step for each of the count", { role = "main-" })

--- Put parameters back at their defaults.
local function reset(params)
  for _, row in ipairs(params) do
    if row.param.default ~= nil then api.device_set_param(row.device.id, row.param.key, row.param.default) end
  end
end

dmap("x", function()
  local _, row = panel:selected()
  if not row then return end
  if row.param then return reset({ row }) end
  paw.cmd("device.remove")
end, "Remove the device; on a parameter, put it back at its default")
dmap("c", function()
  local _, row = panel:selected()
  if not row then return end
  paw.cmd(row.param and "device.value" or "preset")
end, "Change: type the parameter's value; on a device, choose a preset")
dmap("=", "device.value", "Type the parameter's value")
dmap("<CR>", function()
  local _, row = panel:selected()
  if not row then return end
  paw.cmd(row.param and "curve.open" or "device.editor")
end, "Edit the parameter's curve; on a device, show or hide its window")
dmap("]p", "preset.next", "Next preset")
dmap("[p", "preset.prev", "Previous preset")
dmap("<leader>w", "preset.save", "Save the device's settings as a preset")
dmap("<leader>W", "preset.default", "New ones start from this preset")
dmap("a", "device.add", "Add a device")
dmap("gR", "device.restart", "Start a stopped plugin again")
dmap("o", "device.offline", "Set the device offline, or back online")
dmap("<A-j>", function()
  local device = panel:selected()
  if device then device:move(device.index + 1) end
end, "Move the device later in the chain")
dmap("<A-k>", function()
  local device = panel:selected()
  if device and device.index > 1 then device:move(device.index - 1) end
end, "Move the device earlier in the chain")
-- `s` `M` `r` solo, mute and arm the track, as wherever there is a track.
dmap("s", "track.solo", "Solo the track")
dmap("M", "track.mute", "Mute the track")
dmap("r", "track.armed", "Arm the track for recording")
dmap("gS", "device.sidechain", "Choose the track the device listens to (side-chain)")

--- What `K` shows: the device, or the parameter, under the cursor.
function panel:describe()
  local _, row = self:selected()
  if not row then return nil end
  local d = row.device
  local out = { only = true, title = d.name }
  if row.param then
    local p = row.param
    out[#out + 1] = { text = "Parameter  " .. p.name, style = "Title" }
    out[#out + 1] = "  now      " .. paw.frontend.format_value(p, panel.value(row))
    out[#out + 1] = "  from     " .. paw.frontend.format_value(p, p.min) .. " to " .. paw.frontend.format_value(p, p.max)
    if p.default ~= nil then out[#out + 1] = "  default  " .. paw.frontend.format_value(p, p.default) end
    out[#out + 1] = ""
  end
  out[#out + 1] = { text = "Device  " .. d.name, style = "Title" }
  out[#out + 1] = string.format("  %s%s, %d parameters", d.format or "", d.bypass and ", bypassed" or "", #(d.param_info or {}))
  local preset = type(d.meta) == "table" and d.meta.preset
  if preset then out[#out + 1] = "  preset   " .. preset end
  local key = paw.routes.sidechain_text(d)
  if key then out[#out + 1] = "  listens to " .. key end
  return out
end

-- Operators over rows.
local function op(lhs, fn, desc, opts)
  keymap.operator(lhs, fn, util.merge({ view = "devices", desc = desc }, opts))
end
--- The register value for whole devices: one, or several in their order.
local function taken(devices)
  local snaps = {}
  for i, id in ipairs(devices) do snaps[i] = paw.device(id):snapshot() end
  if #snaps == 1 then return { kind = "device", device = snaps[1] }, 1 end
  return { kind = "devices", devices = snaps }, #snaps
end

op("d", function(region, ctx)
  local devices, params = in_region(region)
  if #devices > 0 then
    local value, n = taken(devices)
    keymap.setreg(value, ctx.register)
    for _, id in ipairs(devices) do paw.device(id):remove() end
    paw.notify(n .. (n == 1 and " device cut" or " devices cut"))
  end
  reset(params)
end, "Delete: devices are cut, parameters go back to their defaults")
op("y", function(region, ctx)
  local devices, params = in_region(region)
  if #devices > 0 then
    local value, n = taken(devices)
    keymap.setreg(value, ctx.register, true)
    return paw.notify(n .. (n == 1 and " device yanked" or " devices yanked"))
  end
  local values = {}
  for _, row in ipairs(params) do values[#values + 1] = { key = row.param.key, value = panel.value(row) } end
  keymap.setreg({ kind = "params", values = values }, ctx.register, true)
  paw.notify(#values .. (#values == 1 and " setting yanked" or " settings yanked"))
end, "Yank: devices whole, or the settings of parameters")
op("gc", function(region)
  local list, ids, seen = rows(), {}, {}
  for i = region.r0, region.r1 do
    local row = list[i]
    if row and not seen[row.device.id] then
      seen[row.device.id] = true
      ids[#ids + 1] = row.device.id
    end
  end
  local all = #ids > 0
  for _, id in ipairs(ids) do all = all and api.device_get(id).bypass end
  for _, id in ipairs(ids) do paw.device(id).bypass = not all end
end, "Bypass the devices, or let them play again", { role = "mute" })

-- On a selection the value keys change every parameter selected.
local function vop(lhs, sign, desc, role)
  map(lhs, nil, { view = "devices", mode = "x", desc = desc, role = role, operator = function(region, ctx)
    local list = rows()
    for i = region.r0, region.r1 do
      local row = list[i]
      if row and row.param then
        api.device_set_param(row.device.id, row.param.key, paw.params.step(row.param, panel.value(row), sign * (ctx.count or 1)))
      end
    end
  end })
end
vop("+", 1, "Raise the parameters selected", "main+")
vop("-", -1, "Lower the parameters selected", "main-")
vop("<C-a>", 1, "Raise the parameters selected by the count", "main+")
vop("<C-x>", -1, "Lower the parameters selected by the count", "main-")

local function paste(offset) return function(ctx)
  local value, track = keymap.getreg(ctx.register), paw.cursor.track()
  if not track then return paw.notify("no track selected", "warn") end
  local device = panel:selected()
  -- Settings: onto the device under the cursor, by the parameters' keys.
  if value and value.kind == "params" then
    if not device then return end
    for _, v in ipairs(value.values) do api.device_set_param(device.id, v.key, v.value) end
    return paw.notify(#value.values .. " settings pasted on " .. device.name)
  end
  if not (value and (value.kind == "device" or value.kind == "devices")) then
    return paw.notify("no device in the register: `yy` or `dd` on one first", "warn")
  end
  local at = device and device.index + offset or nil
  -- Several devices, from a selection, go in in their order.
  for i, snap in ipairs(value.devices or { value.device }) do paw.restore_device(snap, track, at and at + i - 1) end
end end
dmap("p", paste(1), "Paste devices after this one, or settings onto it")
dmap("P", paste(0), "Paste devices before this one, or settings onto it")

-- A window of the panel pinned to a track shows that track's devices
-- wherever the cursor goes: two panels show two tracks.
paw.command("devices.pin", function(ctx)
  local L = paw.layout
  local cur = L.current()
  local win = cur and cur.view == "devices" and cur or L.find(paw.ui.layout, "devices", true)
  if not win then return paw.notify("no device panel on the screen: `,d` shows it", "warn") end
  local name = ctx.args[1] and table.concat(ctx.args, " ")
  L.within(win, function()
    if name then
      local id = panel.track_named(name)
      if not id then return paw.notify("no track `" .. name .. "`", "warn") end
      return panel:set_pin(id)
    end
    if panel.pin then return panel:set_pin(nil) end
    local id = panel:track_id()
    if not id then return paw.notify("no track to pin the panel to", "warn") end
    panel:set_pin(id)
  end)
end, { desc = "Keep the device panel on a track whatever the cursor is on, or follow the cursor again: `devices.pin`, `devices.pin Bass`", complete = { "tracks" } })
dmap("<localleader>p", "devices.pin", "Pin the panel to its track, or follow the cursor again")


-- The keys the panel had before the rule (`paw.opt.keys = "classic"`).
local function classic(lhs, rhs, desc, opts) keymap.classic(lhs, rhs, util.merge({ view = "devices", desc = desc, mode = "n" }, opts)) end
classic("l", adjust(1), "Raise the parameter")
classic("h", adjust(-1), "Lower the parameter")
classic("L", function() panel:adjust(10) end, "Raise the parameter a lot")
classic("H", function() panel:adjust(-10) end, "Lower the parameter a lot")
classic("b", "device.bypass", "Bypass the device")
classic("e", "device.editor", "Show or hide the plugin's window")
classic("<CR>", "device.editor", "Show or hide the plugin's window")
classic("s", "preset", "Choose a preset")
classic(">", "preset.next", "Next preset")
classic("<lt>", "preset.prev", "Previous preset")
classic("w", "preset.save", "Save as a preset")
classic("W", "preset.default", "New ones start from this preset")
classic("K", "device.sidechain", "Choose the track the device listens to (side-chain)")
classic("x", "device.remove", "Remove the device")

return M
