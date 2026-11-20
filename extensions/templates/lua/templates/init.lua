-- Templates: what they hold, and where they are kept.
--
--   local templates = require("templates")
--   templates.save_track(track, "Lead vocal")        -- its devices, settings, sends and lanes
--   templates.save_fx(track, "Vocal chain")          -- its devices alone
--   templates.save_group(group, "String section")    -- a group with every track in it
--   templates.load("Lead vocal")                     -- make it again, here
--
-- A template is a JSON file of what `Track:snapshot()` gives, in
-- `<data directory>/templates/<kind>/<name>.json` (`~/.local/share/paw` by
-- default; `paw.opt.templates_dir` puts them elsewhere). Clips are left out
-- unless asked for: a template is a way of working, not a piece of music.
-- Plugins come back with the state they had.
local api = paw.api
local M = { kinds = { "track", "group", "fx" } }

local titles = { track = "track", group = "group of tracks", fx = "device chain" }

function M.dir()
  local dir = paw.opt.templates_dir
  if dir and dir ~= "" then return dir end
  return api.env().data_dir .. "/templates"
end

local function file_name(name)
  local text = tostring(name or ""):gsub("[/\\:%*%?\"<>|%c]", "_"):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then error("a template needs a name", 3) end
  return text
end

--- The name a template is kept under: `name` with the characters a file
--- name cannot hold made `_`.
M.file_name = file_name

function M.path(kind, name)
  return M.dir() .. "/" .. kind .. "/" .. file_name(name) .. ".json"
end

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

--- Devices as a template keeps them: without the tracks they listened to
--- or played their further output pairs into.
local function unrouted(devices)
  for _, device in ipairs(devices) do
    device.sidechain, device.sidechain_pre, device.outputs = nil, nil, nil
  end
  return devices
end

--- A track as a template keeps it: without what ties it to one project
--- (the tracks it played into or listened to, its place in a group), and
--- without its clips unless `clips` is set.
local function portable(track, clips)
  local snap = track:snapshot()
  snap.output, snap.sends = nil, {}
  unrouted(snap.devices)
  if not clips then snap.clips = {} end
  if snap.meta then
    snap.meta.group, snap.meta.group_head, snap.meta.group_folded = nil, nil, nil
    if next(snap.meta) == nil then snap.meta = nil end
  end
  return snap
end

--- Save a track: `opts.clips` keeps its clips too. Returns the file's path.
function M.save_track(track, name, opts)
  track = type(track) == "table" and track or paw.track(track)
  return write("track", name, portable(track, opts and opts.clips))
end

--- Save a track's devices, with their settings, as a chain to add elsewhere.
function M.save_fx(track, name)
  track = type(track) == "table" and track or paw.track(track)
  local devices = {}
  for i, device in ipairs(track:devices()) do devices[i] = device:snapshot() end
  if #devices == 0 then error("the track has no devices to save", 2) end
  return write("fx", name, { devices = unrouted(devices) })
end

--- Save a group: the group's own track and every track in it, groups
--- inside it included.
function M.save_group(group, name, opts)
  group = type(group) == "table" and group or paw.track(group)
  if not paw.groups.is_group(group.id) then error("not a group", 2) end
  local function pack(id)
    local node = { track = portable(paw.track(id), opts and opts.clips), members = {} }
    for i, member in ipairs(paw.groups.members(id)) do
      node.members[i] = paw.groups.is_group(member) and pack(member)
        or { track = portable(paw.track(member), opts and opts.clips) }
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

--- Make a template again. A track or a group is made below the cursor
--- track; a device chain is added to the end of the cursor track's (or of
--- `opts.track`'s). Returns what was made: a track, or the devices.
function M.load(name, opts)
  opts = opts or {}
  local kind, full = find(name, opts.kind)
  if not kind then error("no template `" .. tostring(name) .. "`", 2) end
  local data = read(kind, full or name)
  local below = paw.cursor.index() and paw.cursor.index() + 1 or nil
  if kind == "track" then
    local track = paw.restore_track(data, below)
    paw.cursor.set_track(track)
    return track, kind
  elseif kind == "fx" then
    local track = opts.track and paw.track(opts.track) or paw.cursor.track()
    if not track then error("no track to add the devices to", 2) end
    local made = {}
    for i, device in ipairs(data.devices or {}) do made[i] = paw.restore_device(device, track) end
    return made, kind
  end
  -- A group: its own track first, then its members under it, in order.
  local function unpack_node(node, index, into)
    local track = paw.restore_track(node.track, index)
    if node.members then
      local m = api.track_get(track.id, "meta") or {}
      m.group_head = true
      api.track_set(track.id, "meta", m)
    end
    if into then paw.groups.add(track, into) end
    for _, member in ipairs(node.members or {}) do
      unpack_node(member, nil, track)
    end
    return track
  end
  local group = unpack_node(data, below)
  paw.cursor.set_track(group)
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
