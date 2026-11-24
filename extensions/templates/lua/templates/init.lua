-- Templates: what they hold, and where they are kept.
--
--   local templates = require("templates")
--   templates.save_part(part, "Lead vocal")        -- its devices, settings, sends and lanes
--   templates.save_fx(part, "Vocal chain")          -- its devices alone
--   templates.save_group(group, "String section")    -- a group with every part in it
--   templates.load("Lead vocal")                     -- make it again, here
--
-- A template is a JSON file of what `Part:snapshot()` gives, in
-- `<data directory>/templates/<kind>/<name>.json` (`~/.local/share/paw` by
-- default; `paw.opt.templates_dir` puts them elsewhere). Clips are left out
-- unless asked for: a template is a way of working, not a piece of music.
-- Plugins come back with the state they had.
local api = paw.api
local M = { kinds = { "part", "group", "fx" } }

local titles = { part = "part", group = "group of parts", fx = "device chain" }

function M.dir()
  local dir = paw.opt.templates_dir
  if dir and dir ~= "" then return dir end
  return api.env().data_dir .. "/templates"
end

local function file_name(name)
  local text = tostring(name or ""):gsub('[/\\:%*%?"<>|%c]', "_"):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then error("a template needs a name", 3) end
  return text
end

--- The name a template is kept under: `name` with the characters a file
--- name cannot hold made `_`.
M.file_name = file_name

function M.path(kind, name) return M.dir() .. "/" .. kind .. "/" .. file_name(name) .. ".json" end

local function write(kind, name, data)
  local path = M.path(kind, name)
  pcall(paw.api.fs_mkdir, (path:match("^(.*)/[^/]*$")))
  local file = io.open(path, "w")
  if not file then error("cannot write " .. path, 3) end
  file:write(paw.json.encode({ version = 1, kind = kind, name = file_name(name), data = data }, true), "\n")
  file:close()
  return path
end

local function read(kind, name)
  local file = io.open(M.path(kind, name), "r")
  if not file then return nil end
  local data = paw.json.decode(file:read("*a"))
  file:close()
  return data and data.data
end

--- Devices as a template keeps them: without the parts they listened to
--- or played their further output pairs into.
local function unrouted(devices)
  for _, device in ipairs(devices) do
    device.sidechain, device.sidechain_pre, device.outputs = nil, nil, nil
  end
  return devices
end

--- A part as a template keeps it: without what ties it to one project
--- (the parts it played into or listened to, its place in a group), and
--- without its clips unless `clips` is set.
local function portable(part, clips)
  local snap = part:snapshot()
  snap.output, snap.sends, snap.parent = nil, {}, nil
  unrouted(snap.devices)
  if not clips then snap.clips = {} end
  if snap.meta then
    snap.meta.group_head = nil
    if next(snap.meta) == nil then snap.meta = nil end
  end
  return snap
end

--- Save a part: `opts.clips` keeps its clips too. Returns the file's path.
function M.save_part(part, name, opts)
  part = type(part) == "table" and part or paw.part(part)
  return write("part", name, portable(part, opts and opts.clips))
end

--- Save a part's devices, with their settings, as a chain to add elsewhere.
function M.save_fx(part, name)
  part = type(part) == "table" and part or paw.part(part)
  local devices = {}
  for i, device in ipairs(part:devices()) do
    devices[i] = device:snapshot()
  end
  if #devices == 0 then error("the part has no devices to save", 2) end
  return write("fx", name, { devices = unrouted(devices) })
end

--- Save a group: the group's own part and every part in it, groups
--- inside it included.
function M.save_group(group, name, opts)
  group = type(group) == "table" and group or paw.part(group)
  if not paw.groups.is_group(group.id) then error("not a group", 2) end
  local function pack(id)
    local node = { part = portable(paw.part(id), opts and opts.clips), members = {} }
    for i, member in ipairs(paw.groups.members(id)) do
      node.members[i] = paw.groups.is_group(member) and pack(member)
        or { part = portable(paw.part(member), opts and opts.clips) }
    end
    return node
  end
  return write("group", name, pack(group.id))
end

--- Every template there is: `{ kind, name }` each, by kind and then name.
function M.list(kind)
  local out = {}
  for _, k in ipairs(kind and { kind } or M.kinds) do
    local ok, entries = pcall(api.read_dir, M.dir() .. "/" .. k)
    for _, entry in ipairs(ok and entries or {}) do
      local name = entry.name:match("^(.*)%.json$")
      if name and not entry.is_dir then out[#out + 1] = { kind = k, name = name, title = titles[k] } end
    end
  end
  return out
end

--- The kind a name is saved under: the one asked for, or the first that has it.
local function find(name, kind)
  for _, k in ipairs(kind and { kind } or M.kinds) do
    if read(k, name) then return k end
  end
  -- A part of a name is enough when one template alone has it.
  local found
  for _, item in ipairs(M.list(kind)) do
    if item.name:lower():find(tostring(name):lower(), 1, true) then
      if found then return nil end
      found = item
    end
  end
  if found then return found.kind, found.name end
end

--- Make a template again. A part or a group is made below the cursor
--- part; a device chain is added to the end of the cursor part's (or of
--- `opts.part`'s). Returns what was made: a part, or the devices.
function M.load(name, opts)
  opts = opts or {}
  local kind, full = find(name, opts.kind)
  if not kind then error("no template `" .. tostring(name) .. "`", 2) end
  local data = read(kind, full or name)
  local below = paw.cursor.index() and paw.cursor.index() + 1 or nil
  if kind == "part" then
    local part = paw.restore_part(data, below)
    paw.cursor.set_part(part)
    return part, kind
  elseif kind == "fx" then
    local part = opts.part and paw.part(opts.part) or paw.cursor.part()
    if not part then error("no part to add the devices to", 2) end
    local made = {}
    for i, device in ipairs(data.devices or {}) do
      made[i] = paw.restore_device(device, part)
    end
    return made, kind
  end
  -- A group: its own part first, then its members under it, in order.
  local function unpack_node(node, index, into)
    local part = paw.restore_part(node.part, index)
    if node.members then
      local m = api.part_get(part.id, "meta") or {}
      m.group_head = true
      api.part_set(part.id, "meta", m)
    end
    if into then paw.groups.add(part, into) end
    for _, member in ipairs(node.members or {}) do
      unpack_node(member, nil, part)
    end
    return part
  end
  local group = unpack_node(data, below)
  paw.cursor.set_part(group)
  return group, kind
end

function M.delete(name, kind)
  local k, full = find(name, kind)
  if not k then return false end
  return os.remove(M.path(k, full or name)) ~= nil
end

M.titles = titles
package.loaded["templates"] = M
return M
