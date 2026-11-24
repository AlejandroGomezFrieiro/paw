-- Recent projects: every project opened or saved is remembered, newest
-- first, in the state directory (`recent.json`). The list belongs to the
-- machine, not to a project, and is not kept when the program runs with
-- --clean or as a script.
--
--   :recent                 -- choose one from a list
--   :recent 2               -- open the second without asking
--   :recent.clear           -- forget them all
--   paw.opt.reopen_last = true   -- start with the project that was open last
--
-- In scripts: `paw.recent.list()` gives `{ { path, name, time } }`, newest
-- first, without the files that are gone; `paw.recent.clear()`.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local events = require("paw.events")
local kernel = require("paw.events.kernel")
local options = require("paw.options")
local pick = require("paw.pick")
local type contracts = require("paw.contracts")
local type partial = require("paw.partial")
local type objects = require("paw.objects")
local type CommandModule = require("paw.command")

--- A project that was opened or saved: where it is, its name, and when
--- (seconds since 1970).
local record Entry
  path: string
  name: string
  time: number
end

--- What the window's menu shows for a project.
local record MenuEntry
  label: string
  path: string
end

--- An item of the picker of recent projects.
local record Item
  text: string
  path: string
end

local record Paw is partial.Paw
  project: objects.Project
  open: function(path: string)
  command: CommandModule
end
local paw = (_G as {string: Paw}).paw
local opt = options.opt

local record M
  type Entry = Entry
  type MenuEntry = MenuEntry

  --- How many are remembered.
  max: integer
  --- Where they are kept.
  file: string
end

local env = api.env()
M.max = 20
M.file = env.state_dir .. "/recent.json"
local recording = not env.clean and not env.scripted

--- Keep the list in `file`, and remember projects for all start options,
--- for tests. `use()` sets all back to the old values.
function M.use(file?: string)
  if file then
    M.file, recording = file, true
  else
    M.file, recording = env.state_dir .. "/recent.json", not env.clean and not env.scripted
  end
end

--- The list as it is in the file: a file that is not there or that is not
--- a list gives an empty list. The entries are not checked yet.
local function read(): {Entry}
  local handle = io.open(M.file, "rb")
  if not handle then
    return {}
  end
  local text = handle:read("*a")
  handle:close()
  local ok, data = pcall(api.json_decode, text) as (boolean, {Entry})
  return ok and type(data) == "table" and data or {}
end

local function write(list: {Entry})
  pcall(api.fs_mkdir, (M.file:match("^(.*)/[^/]*$") or "."))
  local handle = io.open(M.file .. ".tmp", "wb")
  if not handle then
    return
  end
  handle:write(api.json_encode(list, true))
  handle:close()
  os.rename(M.file .. ".tmp", M.file)
end

local exists = api.fs_exists

local function place(entry: Entry): string
  return entry.path:match("^(.*)/[^/]*$") or "."
end

--- The projects opened or saved last, newest first: `{ path, name, time }`
--- (`time` is when, in seconds since 1970). A file that is gone is left out.
function M.list(): {Entry}
  local out: {Entry} = {}
  for _, entry in ipairs(read()) do
    if type(entry) == "table" and type(entry.path) == "string" and exists(entry.path) then
      out[#out + 1] = {path = entry.path, name = entry.name, time = tonumber(entry.time) or 0}
    end
  end
  return out
end

--- Forget them all.
function M.clear()
  if exists(M.file) then
    write({})
  end
end

local function remember(path: string)
  if not recording or not path then
    return
  end
  if path:sub(1, 1) ~= "/" then
    path = (os.getenv("PWD") or ".") .. "/" .. path
  end
  local name = path:match("([^/]+)%.[^./]*$") or path:match("([^/]+)$") or path
  local list: {Entry} = {{path = path, name = name, time = os.time()}}
  for _, entry in ipairs(read()) do
    if type(entry) == "table" and entry.path ~= path and #list < M.max then
      list[#list + 1] = entry
    end
  end
  write(list)
end

events.on(kernel.project_loaded, function(e: kernel.Loaded) remember(e.path) end)
events.on(kernel.project_saved, function(e: kernel.Saved) remember(e.path) end)

--- Open a project from the list, by its place in the list or its path. If
--- it does not open, paw tells you. Returns true if it opened.
function M.open(which: string | number): boolean
  local path: string
  if which is number then
    local entry = M.list()[which as integer]
    if not entry then
      paw.notify("there are " .. #M.list() .. " recent projects", "warn")
      return false
    end
    path = entry.path
  else
    path = which
  end
  local ok, err = pcall(paw.open, path) as (boolean, string)
  if not ok then
    local reason = tostring(err):gsub("^[^:]*:%d+: ", "")
    paw.notify("could not open " .. path .. ": " .. reason, "error")
    return false
  end
  paw.notify("opened " .. path)
  return true
end

--- At the start, with no project named: open the newest one when
--- `paw.opt.reopen_last` asks for it. A project that will not open is a
--- message, not the end of the program.
function M.reopen_last(): boolean
  if not opt.reopen_last or not recording then
    return false
  end
  local entry = M.list()[1]
  return entry ~= nil and M.open(entry.path)
end

--- What the window's menu shows: `{ label, path }` each.
function M.menu(): {MenuEntry}
  local out: {MenuEntry} = {}
  for i, entry in ipairs(M.list()) do
    out[i] = {label = entry.name .. "  (" .. place(entry) .. ")", path = entry.path}
  end
  return out
end

paw.command(
  "recent",
  function(ctx: contracts.CommandContext)
    if not paw.project.guard("recent") then
      return
    end
    local list = M.list()
    if #list == 0 then
      paw.notify("no project has been opened yet")
      return
    end
    local which = tonumber(ctx.args[1])
    if which then
      M.open(which)
      return
    end
    pick("recent")
  end,
  {desc = "Open a recent project: `recent` chooses from a list, `recent 2` opens the second"}
)

-- The picker of them: `Alt-d` forgets one.
pick.sources:put(
  "recent",
  {
    desc = "Open a recent project",
    title = "Recent projects",
    empty = "No project has been opened yet.",
    items = function(): {Item}
      local items: {Item} = {}
      for i, entry in ipairs(M.list()) do
        local when = os.date("%Y-%m-%d %H:%M", math.floor(entry.time))
        items[i] = {text = string.format("%s  %s  %s", entry.name, place(entry), when), path = entry.path}
      end
      return items
    end,
    on_choose = function(item: Item) M.open(item.path) end,
    delete = function(items: {Item})
      local gone: {string: boolean} = {}
      for _, item in ipairs(items) do
        gone[item.path] = true
      end
      local kept: {Entry} = {}
      for _, entry in ipairs(read()) do
        if type(entry) == "table" and not gone[entry.path] then
          kept[#kept + 1] = entry
        end
      end
      write(kept)
    end,
  } as contracts.PickSource<Item>
)
paw.project.allow_discard("recent")

paw.command(
  "recent.clear",
  function() M.clear(); paw.notify("the list of recent projects is empty") end,
  {desc = "Forget the recent projects"}
)

return M
