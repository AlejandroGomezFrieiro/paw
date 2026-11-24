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
local api = paw.api
local M = {}

local env = api.env()

--- The directory the program keeps things about a project in, outside the
--- project file: one per project file.
function M.project_dir(path)
  local hash = 5381
  for i = 1, #path do
    hash = (hash * 33 + path:byte(i)) % 4294967296
  end
  local name = path:match("([^/]+)%.[^./]*$") or path:match("([^/]+)$") or "project"
  return string.format("%s/projects/%s-%08x", env.state_dir, name:gsub("[^%w%-_]", "_"), hash)
end

local function memory_file(path) return M.project_dir(path) .. "/plugins.json" end

--- What is remembered of a project's plugins: `stopped` maps device ids
--- (as strings) to `{ kind, name, reason }`.
function M.memory(path)
  local file = path and io.open(memory_file(path), "rb")
  if not file then return { stopped = {} } end
  local text = file:read("*a")
  file:close()
  local ok, data = pcall(api.json_decode, text)
  if not ok or type(data) ~= "table" then return { stopped = {} } end
  data.stopped = type(data.stopped) == "table" and data.stopped or {}
  return data
end

local function remember(path, data)
  local dir = M.project_dir(path)
  pcall(paw.api.fs_mkdir, dir)
  local file = io.open(memory_file(path), "wb")
  if not file then return end
  file:write(api.json_encode(data, true))
  file:close()
end

--- The devices of the project at `path` that could not be loaded last time,
--- as a list of `{ id, kind, name, reason }`.
function M.suggested(path)
  local out = {}
  for id, entry in pairs(M.memory(path).stopped) do
    out[#out + 1] = { id = tonumber(id), kind = entry.kind, name = entry.name, reason = entry.reason }
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

paw.on("device.stopped", function(event)
  local path = api.project_get("path")
  if not event.loading or not path then return end
  local data = M.memory(path)
  local ok, device = pcall(api.device_get, event.device)
  data.stopped[tostring(event.device)] = {
    kind = ok and device.kind or nil,
    name = event.name,
    reason = event.reason,
  }
  remember(path, data)
end)

-- One that loads is no longer suggested offline.
paw.on("device.ready", function(event)
  local path = api.project_get("path")
  if not path then return end
  local data = M.memory(path)
  if data.stopped[tostring(event.id)] then
    data.stopped[tostring(event.id)] = nil
    remember(path, data)
  end
end)

--- Open a project, offline as `opts` says (`plugins_offline`, or
--- `offline`, a list of device ids), and with the devices that could not
--- be loaded last time offline as well.
function M.open(path, opts)
  opts = opts or {}
  local offline = {}
  for _, id in ipairs(opts.offline or {}) do
    offline[#offline + 1] = id
  end
  local held = {}
  if not opts.plugins_offline and not opts.all_online then
    for _, entry in ipairs(M.suggested(path)) do
      offline[#offline + 1] = entry.id
      held[#held + 1] = entry
    end
  end
  api.project_load(path, { plugins_offline = opts.plugins_offline or false, offline = #offline > 0 and offline or nil })
  -- Only those that are there, and the same plugin, count.
  local names = {}
  for _, entry in ipairs(held) do
    local ok, device = pcall(api.device_get, entry.id)
    if ok and device.kind == entry.kind and device.offline then names[#names + 1] = entry.name end
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
local function each_device(fn)
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
function M.online()
  local count = 0
  each_device(function(device)
    if device.offline then
      device:set_offline(false)
      count = count + 1
    end
  end)
  return count
end

-- What runs code from outside paw, in a process of its own: plugins, and
-- devices written in Lua (`paw.luadev`).
local PLUGIN_FORMATS = { clap = true, lv2 = true, vst3 = true, lua = true }

--- Set every plugin offline, devices written in Lua too. Returns how many.
function M.offline()
  local count = 0
  each_device(function(device)
    local d = device:get()
    if not d.offline and PLUGIN_FORMATS[d.format] then
      device:set_offline(true)
      count = count + 1
    end
  end)
  return count
end

paw.command("plugins.online", function()
  local count = M.online()
  paw.notify(
    count == 0 and "no device is offline" or string.format("%d device%s coming up", count, count == 1 and "" or "s")
  )
end, { desc = "Bring every offline device up" })

paw.command("plugins.offline", function()
  local count = M.offline()
  paw.notify(string.format("%d plugin%s offline", count, count == 1 and "" or "s"))
end, { desc = "Set every plugin offline, devices written in Lua too: not run, passed over, kept with its state" })

--- Set one device offline, or back online.
function M.toggle(device)
  local on = not device.offline
  device:set_offline(on)
  paw.notify(string.format("%s is %s", device:get().name, on and "offline" or "coming up"))
end

paw.command("device.offline", function()
  local device = paw.ui.views:get("inspector") and paw.ui.views:get("inspector"):selected()
  if not device then return paw.notify("select a device in the device panel first", "warn") end
  M.toggle(device)
end, { desc = "Set the selected device offline (not run, kept with its state), or back online" })

return M
