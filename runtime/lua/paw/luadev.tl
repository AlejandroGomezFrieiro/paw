-- `paw.luadev`: devices written in Lua (see docs/reference/lua-devices.md). Scripts are `.lua` files in `devices` in the
-- configuration directory and in each extension, and show among the devices
-- as `lua:<file name>`. A script that changes on the disk is loaded again,
-- and devices made from it start again with their parameters as they were.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local options = require("paw.options")
local registry = require("paw.registry")
local type types = require("paw.types")
local type objects = require("paw.objects")
local type partial = require("paw.partial")
local type CommandModule = require("paw.command")
local type CursorModule = require("paw.cursor")
local type UiModule = require("paw.ui")

--- A directory of scripts, as `M.dirs` keeps it.
local record Dir
  dir: string
  rank: integer
end

--- The inspector (paw/views/inspector.lua), as far as this module calls it.
local record Inspector
  selected: function(self: Inspector): objects.Device
end

local record Paw is partial.Paw
  command: CommandModule
  cursor: CursorModule
  ui: UiModule
  master: objects.Part
  parts: function(): {objects.Part}
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

local record M
  type Dir = Dir

  --- The directories looked in besides the user's, by path, with the
  --- extension that added each one. A directory that goes (`remove_dir`,
  --- or the unload of its extension) is looked in no more.
  dirs: registry.Registry<Dir>
  --- Where a script of the same name wins: an extension's, then the user's.
  RANK_EXTENSION: integer
  RANK_CONFIG: integer
  check: function(): types.LuaDeviceScan
  --- The event `luadev.checked`: paw checked the devices in Lua again.
  checked: events.Event<types.LuaDeviceScan>
end

M.checked = events.event("luadev.checked")
M.RANK_EXTENSION = 0
M.RANK_CONFIG = 1

--- Every device in the project made from one of `kinds` (a set), or from
--- any Lua script when `kinds` is nil.
local function devices_of(kinds?: {string: boolean}): {objects.Device}
  local out: {objects.Device} = {}
  local function look(part: objects.Part)
    for _, device in ipairs(part:devices()) do
      local kind = device.kind
      if kind:match("^lua:") and (kinds == nil or kinds[kind]) and not device.offline then
        out[#out + 1] = device
      end
    end
  end
  for _, part in ipairs(paw.parts()) do
    look(part)
  end
  look(paw.master)
  return out
end

--- Start `devices` again from their scripts. Returns how many started and
--- the first reason one did not.
local function restart(devices: {objects.Device}): integer, string
  local started, failed = 0, nil as string
  for _, device in ipairs(devices) do
    local ok, err = pcall(device.restart, device) as (boolean, string)
    if ok then
      started = started + 1
    else
      failed = failed or tostring(err):match("^[^\n]*")
    end
  end
  return started, failed
end

local function report(found: types.LuaDeviceScan)
  for _, e in ipairs(found.errors or {}) do
    paw.notify(string.format("%s did not load: %s", e.path:match("[^/]*$"), e.error), "error")
  end
end

-- The kinds that the last directory that went had (`remove_dir` gives them).
local removed: {string} = {}
M.dirs = registry.new(
  "device_dirs",
  "devices written in Lua",
  {
    changed = function(dir: string, value: Dir)
      if not value then
        removed = api.lua_devices_remove(dir)
      end
    end,
  }
)

local timer: integer

--- Look at the scripts' files every `paw.opt.lua_devices_watch` ms (0 for
--- never). Started by itself once a directory is added.
function M.watch()
  if timer then
    paw.cancel(timer)
  end
  timer = nil
  local ms = opt.lua_devices_watch
  if ms and ms > 0 then
    timer = paw.every(ms, function() M.check() end)
  end
end

--- Look for devices in `dir` too. `rank` (default `M.RANK_EXTENSION`) says
--- whose script wins where two directories have one of the same name.
function M.add_dir(dir: string, rank?: integer): types.LuaDeviceScan
  local found = api.lua_devices_add(dir, rank or M.RANK_EXTENSION)
  if not M.dirs:get(dir) then
    M.dirs:put(dir, {dir = dir, rank = rank or M.RANK_EXTENSION})
  end
  report(found)
  M.watch()
  return found
end

--- The kinds of the scripts found in `dir`.
function M.kinds_in(dir: string): {string}
  local out: {string} = {}
  for _, s in ipairs(api.lua_devices()) do
    if s.active and s.path:match("^(.*)/[^/]*$") == dir then
      out[#out + 1] = s.kind
    end
  end
  return out
end

--- Stop to find scripts in `dir`. paw stops to offer the devices of its
--- scripts (a script with the same name in a different folder takes their
--- place). The devices that exist continue to work. Returns the kinds of
--- the scripts that were there.
function M.remove_dir(dir: string): {string}
  if not M.dirs:get(dir) then
    return api.lua_devices_remove(dir)
  end
  M.dirs:remove(dir)
  return removed
end

--- Look at every script again: those that changed are loaded, and the
--- devices made from them start again with the parameters they had.
--- Returns what `paw.api.lua_devices_rescan` found.
function M.check(): types.LuaDeviceScan
  local found = api.lua_devices_rescan()
  report(found)
  if #found.changed > 0 then
    local kinds: {string: boolean} = {}
    for _, kind in ipairs(found.changed) do
      kinds[kind] = true
    end
    local devices = devices_of(kinds)
    local started, failed = restart(devices)
    if failed then
      paw.notify(failed, "error")
    elseif started > 0 then
      paw.notify(
        string.format(
          "%s changed: %d device%s loaded again", table.concat(found.changed, ", "), started, started == 1 and "" or "s"
        )
      )
    end
  end
  events.emit(M.checked, found)
  return found
end

options.define("lua_devices_watch", 1000)
events.on(
  options.changed,
  function(e: options.Changed)
    if e.name == "lua_devices_watch" then
      M.watch()
    end
  end
)

paw.command(
  "device.reload",
  function()
    -- The device chosen in the panel if it is written in Lua, else every one
    -- on the part.
    M.check()
    local chosen: objects.Device
    if paw.ui.focused == "inspector" then
      chosen = (paw.ui.views:get("inspector") as Inspector):selected()
    end
    local devices: {objects.Device}
    if chosen and chosen.kind:match("^lua:") then
      devices = {chosen}
    else
      local part = paw.cursor.part()
      devices = {}
      for _, device in ipairs(part and part:devices() or {}) do
        if device.kind:match("^lua:") and not device.offline then
          devices[#devices + 1] = device
        end
      end
    end
    if #devices == 0 then
      paw.notify("no device written in Lua here", "warn")
      return
    end
    local started, failed = restart(devices)
    if failed then
      paw.notify(failed, "error")
      return
    end
    paw.notify(started == 1 and "loaded again from its script" or started .. " devices loaded again from their scripts")
  end,
  {desc = "Load a device written in Lua again from its file, keeping its parameters"}
)

paw.command(
  "device.scripts",
  function()
    local lines: {string} = {}
    for _, s in ipairs(api.lua_devices()) do
      lines[#lines + 1] = string.format(
        "%-20s %-24s %s%s", s.kind, s.name, s.path, s.active and "" or "  (hidden by another)"
      )
      if s.error then
        lines[#lines + 1] = "    " .. s.error
      end
    end
    if #lines == 0 then
      lines[1] = "No devices written in Lua: put .lua files in " .. api.env().config_dir .. "/devices"
    end
    paw.ui.page("Devices written in Lua", lines)
  end,
  {desc = "List the devices written in Lua, where their files are, and any that did not load"}
)

return M
