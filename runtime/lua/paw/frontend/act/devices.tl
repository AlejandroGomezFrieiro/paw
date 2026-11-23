-- The pointer's gestures on devices: their parameters, bypass, order,
-- offline and restart.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local util = require("paw.util")
local type types = require("paw.types")
local M = require("paw.frontend.core")
local host = require("paw.frontend.host")

local paw = host.paw
local A = M.act

--- Set a device offline, or back online.
function A.toggle_offline(id: integer)
  paw.loading.toggle(paw.device(id))
end

--- Start a plugin again that has stopped working.
function A.restart_device(id: integer)
  local ok, err = pcall(api.device_restart, id) as (boolean, string)
  if not ok then
    paw.notify(tostring(err):match("^[^\n]*"), "error")
  end
end

-- Devices.

local function param_of(device: integer, key: string): types.ParamInfo
  for _, p in ipairs(api.device_get(device).param_info) do
    if p.key == key then
      return p
    end
  end
  error("the device has no parameter `" .. tostring(key) .. "`", 3)
end

--- Set a parameter from a slider's position, 0 to 1 across its range.
function A.set_param(device: integer, key: string, fraction: number)
  local p = param_of(device, key)
  api.device_set_param(device, key, paw.params.from_fraction(p, fraction))
end

--- Back to where the device starts out: a double click on a slider.
function A.reset_param(device: integer, key: string)
  api.device_set_param(device, key, param_of(device, key).default)
end

function A.toggle_bypass(device: integer)
  api.device_set(device, {bypass = not api.device_get(device).bypass})
end

function A.add_device(kind: string, query?: string): integer
  return paw.fx.add(assert(paw.cursor.track(), "no track selected"), kind, {query = query}).id
end

--- Move a device one place earlier (-1) or later (1) in its track's chain.
function A.move_device(device: integer, by: integer)
  local d = api.device_get(device)
  api.device_move(device, d.track, util.clamp(d.index + by, 1, #api.track_get(d.track).devices) as integer)
end
