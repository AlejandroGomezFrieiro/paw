-- Plugins offline: opening a project without them, setting one device
-- offline, and remembering the plugins that could not be loaded.
--
--   paw.open("song", { plugins_offline = true })   -- every plugin offline
--   :edit song offline                                  -- the same
--   :plugins.online                                     -- bring them all up
--   :device.offline                                     -- the selected device, on or off
--   device:set_offline(true)
--
-- A plugin that could not be loaded when a project was opened (it failed,
-- or hung past its time limit) is remembered in the project's state
-- directory, and the next time the project is opened it is opened offline,
-- with a message saying so, until it loads again.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local type types = require("paw.types")
local type objects = require("paw.objects")
local type partial = require("paw.partial")
local type CommandModule = require("paw.command")
local type registry = require("paw.registry")
local type contracts = require("paw.contracts")

--- A device that could not be loaded, as the project remembers it.
local record Stopped
  kind: string
  name: string
  reason: string
end

--- What is remembered of a project's plugins: `stopped` maps device ids
--- (as strings) to what is known of the device.
local record Memory
  stopped: {string: Stopped}
end

--- A device that could not be loaded last time, as a list item.
local record Suggested
  id: integer
  kind: string
  name: string
  reason: string
end

--- How a project is opened: every plugin offline, or the devices (by id)
--- that are, and `all_online` to ignore what is remembered.
local record OpenOptions
  plugins_offline: boolean
  offline: {integer}
  all_online: boolean
end

--- The inspector (paw/views/inspector.lua), as far as this module calls it.
local record Inspector
  selected: function(self: Inspector): objects.Device
end

--- `paw.ui`, as far as this module reads it: the views.
local record Ui
  views: registry.Registry<contracts.View>
end

local record Paw is partial.Paw
  command: CommandModule
  ui: Ui
  master: objects.Part
  parts: function(): {objects.Part}
end
local paw = (_G as {string: Paw}).paw

local record M
  type Stopped = Stopped
  type Memory = Memory
  type Suggested = Suggested
  type OpenOptions = OpenOptions
end

local env = api.env()

--- The directory the program keeps things about a project in, outside the
--- project file: one per project file.
function M.project_dir(path: string): string
  local hash = 5381
  for i = 1, #path do
    hash = (hash * 33 + path:byte(i)) % 4294967296
  end
  local name = path:match("([^/]+)%.[^./]*$") or path:match("([^/]+)$") or "project"
  local safe = name:gsub("[^%w%-_]", "_")
  return string.format("%s/projects/%s-%08x", env.state_dir, safe, hash)
end

local function memory_file(path: string): string
  return M.project_dir(path) .. "/plugins.json"
end

--- What is remembered of a project's plugins: `stopped` maps device ids
--- (as strings) to `{ kind, name, reason }`.
function M.memory(path?: string): Memory
  local file = path and io.open(memory_file(path), "rb")
  if not file then
    return {stopped = {}}
  end
  local text = file:read("*a")
  file:close()
  local ok, decoded = pcall(api.json_decode, text) as (boolean, Memory)
  if not ok or type(decoded) ~= "table" then
    return {stopped = {}}
  end
  local data = decoded
  data.stopped = type(data.stopped) == "table" and data.stopped or {}
  return data
end

local function remember(path: string, data: Memory)
  local dir = M.project_dir(path)
  pcall(api.fs_mkdir, dir)
  local file = io.open(memory_file(path), "wb")
  if not file then
    return
  end
  file:write(api.json_encode(data, true))
  file:close()
end

--- The devices of the project at `path` that could not be loaded last time,
--- as a list of `{ id, kind, name, reason }`.
function M.suggested(path: string): {Suggested}
  local out: {Suggested} = {}
  for id, entry in pairs(M.memory(path).stopped) do
    out[#out + 1] = {id = math.tointeger(tonumber(id)), kind = entry.kind, name = entry.name, reason = entry.reason}
  end
  table.sort(out, function(a: Suggested, b: Suggested): boolean return a.id < b.id end)
  return out
end

events.on(
  kernel.device_stopped,
  function(event: kernel.DeviceTrouble)
    local path = api.project_get().path
    if not event.loading or not path then
      return
    end
    local data = M.memory(path)
    local ok, device = pcall(api.device_get, event.device) as (boolean, types.Device)
    data.stopped[tostring(event.device)] = {
      kind = ok and device.kind or nil,
      name = event.name,
      reason = event.reason,
    }
    remember(path, data)
  end
)

-- One that loads is no longer suggested offline.
events.on(
  kernel.device_ready,
  function(event: kernel.DeviceReady)
    local path = api.project_get().path
    if not path then
      return
    end
    local data = M.memory(path)
    if data.stopped[tostring(event.id)] then
      data.stopped[tostring(event.id)] = nil
      remember(path, data)
    end
  end
)

--- Open a project, offline as `opts` says (`plugins_offline`, or
--- `offline`, a list of device ids), and with the devices that could not
--- be loaded last time offline as well.
function M.open(path: string, opts?: OpenOptions)
  opts = opts or {}
  local offline: {integer} = {}
  for _, id in ipairs(opts.offline or {}) do
    offline[#offline + 1] = id
  end
  local held: {Suggested} = {}
  if not opts.plugins_offline and not opts.all_online then
    for _, entry in ipairs(M.suggested(path)) do
      offline[#offline + 1] = entry.id
      held[#held + 1] = entry
    end
  end
  api.project_load(path, {plugins_offline = opts.plugins_offline or false, offline = #offline > 0 and offline or nil})
  -- Only those that are there, and the same plugin, count.
  local names: {string} = {}
  for _, entry in ipairs(held) do
    local ok, device = pcall(api.device_get, entry.id) as (boolean, types.Device)
    if ok and device.kind == entry.kind and device.offline then
      names[#names + 1] = entry.name
    end
  end
  if opts.plugins_offline then
    paw.notify(
      "opened with every plugin offline: `:plugins.online` brings them up, `o` in the device panel one at a time"
    )
  elseif #names > 0 then
    paw.notify(
      string.format(
        "%s could not be loaded last time and %s offline: `:plugins.online` tries again",
        table.concat(names, ", "),
        #names == 1 and "is" or "are"
      ),
      "warn"
    )
  end
end

--- Every device of the project, with its part.
local function each_device(fn: function(device: objects.Device))
  for _, part in ipairs(paw.parts()) do
    for _, device in ipairs(part:devices()) do
      fn(device)
    end
  end
  for _, device in ipairs(paw.master:devices()) do
    fn(device)
  end
end

--- Bring every offline device up. Returns how many.
function M.online(): integer
  local count = 0
  each_device(
    function(device: objects.Device)
      if device.offline then
        device:set_offline(false)
        count = count + 1
      end
    end
  )
  return count
end

-- What runs code from outside paw, in a process of its own: plugins, and
-- devices written in Lua (`paw.luadev`).
local PLUGIN_FORMATS: {string: boolean} = {clap = true, lv2 = true, vst3 = true, lua = true}

--- Set every plugin offline, devices written in Lua too. Returns how many.
function M.offline(): integer
  local count = 0
  each_device(
    function(device: objects.Device)
      local d = device:get()
      if not d.offline and PLUGIN_FORMATS[d.format] then
        device:set_offline(true)
        count = count + 1
      end
    end
  )
  return count
end

paw.command(
  "plugins.online",
  function()
    local count = M.online()
    paw.notify(
      count == 0 and "no device is offline" or string.format("%d device%s coming up", count, count == 1 and "" or "s")
    )
  end,
  {desc = "Bring every offline device up"}
)

paw.command(
  "plugins.offline",
  function()
    local count = M.offline()
    paw.notify(string.format("%d plugin%s offline", count, count == 1 and "" or "s"))
  end,
  {desc = "Set every plugin offline, devices written in Lua too: not run, passed over, kept with its state"}
)

--- Set one device offline, or back online.
function M.toggle(device: objects.Device)
  local on = not device.offline
  device:set_offline(on)
  paw.notify(string.format("%s is %s", device:get().name, on and "offline" or "coming up"))
end

paw.command(
  "device.offline",
  function()
    local panel = paw.ui.views:get("inspector") as Inspector
    local device = panel and panel:selected()
    if not device then
      paw.notify("select a device in the device panel first", "warn")
      return
    end
    M.toggle(device)
  end,
  {desc = "Set the selected device offline (not run, kept with its state), or back online"}
)

return M
