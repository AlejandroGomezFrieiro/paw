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
local api = paw.api
local M = {}

local env = api.env()
--- How many are remembered.
M.max = 20
--- Where they are kept.
M.file = env.state_dir .. "/recent.json"
local recording = not env.clean and not env.scripted

--- Keep the list in `file`, and remember projects for all start options,
--- for tests. `use()` sets all back to the old values.
function M.use(file)
  if file then
    M.file, recording = file, true
  else
    M.file, recording = env.state_dir .. "/recent.json", not env.clean and not env.scripted
  end
end

local function read()
  local handle = io.open(M.file, "rb")
  if not handle then return {} end
  local text = handle:read("*a")
  handle:close()
  local ok, data = pcall(api.json_decode, text)
  return ok and type(data) == "table" and data or {}
end

local function write(list)
  pcall(paw.api.fs_mkdir, (M.file:match("^(.*)/[^/]*$") or "."))
  local handle = io.open(M.file .. ".tmp", "wb")
  if not handle then return end
  handle:write(api.json_encode(list, true))
  handle:close()
  os.rename(M.file .. ".tmp", M.file)
end

local exists = paw.api.fs_exists

local function place(entry) return entry.path:match("^(.*)/[^/]*$") or "." end

--- The projects opened or saved last, newest first: `{ path, name, time }`
--- (`time` is when, in seconds since 1970). A file that is gone is left out.
function M.list()
  local out = {}
  for _, entry in ipairs(read()) do
    if type(entry) == "table" and type(entry.path) == "string" and exists(entry.path) then
      out[#out + 1] = { path = entry.path, name = entry.name, time = tonumber(entry.time) or 0 }
    end
  end
  return out
end

--- Forget them all.
function M.clear()
  if exists(M.file) then write({}) end
end

local function remember(path)
  if not recording or not path then return end
  if path:sub(1, 1) ~= "/" then path = (os.getenv("PWD") or ".") .. "/" .. path end
  local name = path:match("([^/]+)%.[^./]*$") or path:match("([^/]+)$") or path
  local list = { { path = path, name = name, time = os.time() } }
  for _, entry in ipairs(read()) do
    if type(entry) == "table" and entry.path ~= path and #list < M.max then list[#list + 1] = entry end
  end
  write(list)
end

paw.on("project.loaded", function(e) remember(e.path) end)
paw.on("project.saved", function(e) remember(e.path) end)

--- Open a project from the list, by its place in the list or its path. If
--- it does not open, paw tells you. Returns true if it opened.
function M.open(which)
  local path = which
  if type(which) == "number" then
    local entry = M.list()[which]
    if not entry then
      paw.notify("there are " .. #M.list() .. " recent projects", "warn")
      return false
    end
    path = entry.path
  end
  local ok, err = pcall(paw.open, path)
  if not ok then
    paw.notify("could not open " .. path .. ": " .. tostring(err):gsub("^[^:]*:%d+: ", ""), "error")
    return false
  end
  paw.notify("opened " .. path)
  return true
end

--- At the start, with no project named: open the newest one when
--- `paw.opt.reopen_last` asks for it. A project that will not open is a
--- message, not the end of the program.
function M.reopen_last()
  if not paw.opt.reopen_last or not recording then return false end
  local entry = M.list()[1]
  return entry ~= nil and M.open(entry.path)
end

--- What the window's menu shows: `{ label, path }` each.
function M.menu()
  local out = {}
  for i, entry in ipairs(M.list()) do
    out[i] = { label = entry.name .. "  (" .. place(entry) .. ")", path = entry.path }
  end
  return out
end

paw.command("recent", function(ctx)
  if not paw.project.guard("recent") then return end
  local list = M.list()
  if #list == 0 then return paw.notify("no project has been opened yet") end
  local which = tonumber(ctx.args[1])
  if which then return M.open(which) end
  paw.pick("recent")
end, { desc = "Open a recent project: `recent` chooses from a list, `recent 2` opens the second" })

-- The picker of them: `Alt-d` forgets one.
paw.pick.sources:put("recent", {
  desc = "Open a recent project",
  title = "Recent projects",
  empty = "No project has been opened yet.",
  items = function()
    local items = {}
    for i, entry in ipairs(M.list()) do
      items[i] = {
        text = string.format("%s  %s  %s", entry.name, place(entry), os.date("%Y-%m-%d %H:%M", entry.time)),
        path = entry.path,
      }
    end
    return items
  end,
  on_choose = function(item) M.open(item.path) end,
  delete = function(items)
    local gone = {}
    for _, item in ipairs(items) do
      gone[item.path] = true
    end
    local kept = {}
    for _, entry in ipairs(read()) do
      if type(entry) == "table" and not gone[entry.path] then kept[#kept + 1] = entry end
    end
    write(kept)
  end,
})
paw.project.allow_discard("recent")

paw.command("recent.clear", function()
  M.clear()
  paw.notify("the list of recent projects is empty")
end, { desc = "Forget the recent projects" })

return M
