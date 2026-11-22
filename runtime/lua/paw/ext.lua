-- Extensions: directories (or single files of Lua or Teal) in `<config>/extensions`.
--
--   extensions/euclid/init.lua      run at startup
--   extensions/euclid/manifest.lua  what it is and what it needs (optional)
--   extensions/euclid/lua/...       on the `require` path
--   extensions/scratch.lua          a one-file extension, run at startup
--
-- Any of these files may be in a language that compiles to Lua (paw/lang.tl):
-- `init.tl`, `lua/euclid/rhythm.tl` and `scratch.tl` are Teal, which paw
-- compiles as it loads them. An extension may mix the languages.
--
--   extensions/euclid/devices/*.lua devices written in Lua (see paw.luadev)
--
-- An extension is ordinary Lua using the same `paw` module as the user's
-- `init.lua`; there is no separate plugin interface. What it registers while
-- it loads (commands, keys, views, buffer types, hooks, ...) is recorded as
-- its own: `:extensions` lists it, and `paw.ext.unload(name)` takes it away.
-- So is what it registers later, from a handler or a timer, when a function
-- of its own files is in it (a command's, a key's, a hook's, a timer's).
--
-- A manifest is a Lua file that returns a table:
--
--   return {
--     name = "euclid", version = "1.2.0",
--     description = "Euclidean rhythms as clips",
--     requires = { paw = ">=1.0", sections = "^1" },  -- the API, and other extensions
--     provides = { "rhythms" },                      -- names others may require it by
--   }
local api = paw.api
local M = {}
--- The extensions that paw loaded, or tried to, by name.
--- @type {string:contracts.ExtEntry}
M.loaded = {}
--- The extension that loads now, or nil.
--- @type contracts.ExtEntry
M.current = nil

--- Whether `path` is a one-file extension: a file of Lua, or of a language
--- that compiles to Lua.
local function one_file(path) return path:match("%.lua$") ~= nil or paw.lang.of(path) ~= nil end

--- The name of an extension at `path`: its directory's or file's, without
--- the extension of the file.
local function name_of(path)
  local base = path:match("([^/]+)$")
  return one_file(base) and base:gsub("%.[%w_]+$", "") or base
end

local exists = paw.api.fs_exists

-- Versions --------------------------------------------------------------------------

--- The numbers of a version: "1.2.3" gives { 1, 2, 3 }. A part that is not there is 0.
--- Nil for text that is not a version.
function M.parse_version(text)
  local a, b, c = tostring(text or ""):match("^%s*v?(%d+)%.?(%d*)%.?(%d*)")
  if not a then return nil end
  return { tonumber(a), tonumber(b) or 0, tonumber(c) or 0 }
end

local function compare(a, b)
  for i = 1, 3 do
    if a[i] ~= b[i] then return a[i] < b[i] and -1 or 1 end
  end
  return 0
end

--- True if `version` agrees with `want`. `want` is comparisons with spaces
--- or commas between them. Each is `>=1.2`, `>1`, `<=2`, `<2.0`, `=1.2.3`,
--- `^1.2` (the same first number, at least 1.2), `~1.2` (the same first two
--- numbers) or a version alone, which means `^`. `*` or nothing is any version.
function M.satisfies(version, want)
  local v = M.parse_version(version)
  if not v then return false end
  for part in tostring(want or "*"):gmatch("[^%s,]+") do
    if part ~= "*" then
      local op, rest = part:match("^([<>=~^]*)(.*)$")
      local w = M.parse_version(rest)
      if not w then return false end
      local c = compare(v, w)
      local ok
      if op == ">=" then
        ok = c >= 0
      elseif op == ">" then
        ok = c > 0
      elseif op == "<=" then
        ok = c <= 0
      elseif op == "<" then
        ok = c < 0
      elseif op == "=" then
        ok = c == 0
      elseif op == "~" then
        ok = c >= 0 and v[1] == w[1] and v[2] == w[2]
      else
        ok = c >= 0 and v[1] == w[1]
      end
      if not ok then return false end
    end
  end
  return true
end

-- Whose code it is -----------------------------------------------------------------

--- Whether `source` (a function's, as `debug.getinfo` names it) is one of
--- the files of the extension `entry`.
local function in_files(entry, source)
  if type(source) ~= "string" or source:sub(1, 1) ~= "@" then return false end
  local path = entry.path
  return source == "@" .. path or source:sub(1, #path + 2) == "@" .. path .. "/"
end

local function defined_by(entry, fn) return type(fn) == "function" and in_files(entry, debug.getinfo(fn, "S").source) end

--- Whether `value`, an entry of a registry, is the extension's own: a
--- function of its files, a table with one among its fields, or a table
--- that says it is (`ext`, as a key mapped from its code says).
local function made_by(entry, value)
  if defined_by(entry, value) then return true end
  if type(value) ~= "table" then return false end
  if value.ext == entry.name then return true end
  for _, v in pairs(value) do
    if defined_by(entry, v) then return true end
  end
  return false
end

--- The loaded extension whose code called the function this is called
--- from, or nil for the core's or the user's.
--- @type function(): string
function M.caller()
  for level = 3, 64 do
    local info = debug.getinfo(level, "S")
    if not info then return nil end
    for name, entry in pairs(M.loaded) do
      if in_files(entry, info.source) then return name end
    end
  end
end

-- What extensions own --------------------------------------------------------------
--
-- Each registry an extension can add to is read before and after it loads;
-- what differs is the extension's, kept with what was there before, so that
-- unloading it puts that back. `put(key, value)` sets an entry, nil removes
-- it; `label` says what the entry is in a few words.

local function keyed(kind, title, get, put, label)
  return {
    kind = kind,
    title = title,
    snapshot = function()
      local out = {}
      for k, v in pairs(get() or {}) do
        out[k] = v
      end
      return out
    end,
    put = put or function(key, value) get()[key] = value end,
    label = label,
  }
end

local function two_level(get)
  return function()
    local out = {}
    for a, inner in pairs(get() or {}) do
      for b, v in pairs(inner) do
        out[a .. " " .. b] = v
      end
    end
    return out
  end
end

local function split(key) return key:match("^(%S+) (.*)$") end

M.registries = {
  {
    kind = "commands",
    title = "commands",
    snapshot = function()
      local out = {}
      for _, spec in ipairs(paw.commands.list()) do
        out[spec.name] = spec
      end
      return out
    end,
    put = function(key, value) paw.commands.put(key, value) end,
    label = function(key) return ":" .. key end,
  },
  {
    kind = "keys",
    title = "keys",
    snapshot = function()
      local out = {}
      paw.keymap.each(function(map, mode, scope, keys) out[mode .. " " .. scope .. " " .. keys] = map end)
      return out
    end,
    put = function(key, value)
      local mode, scope, keys = key:match("^(%S+) (%S+) (.*)$")
      paw.keymap.put(mode, scope, keys, value)
    end,
    label = function(_, map)
      return map.lhs .. " (" .. map.mode .. (map.scope ~= "global" and ", " .. map.scope or "") .. ")"
    end,
  },
  {
    kind = "key_groups",
    title = "key groups",
    snapshot = two_level(function() return paw.keymap.groups() end),
    put = function(key, value)
      local scope, keys = split(key)
      local groups = paw.keymap.groups()
      groups[scope] = groups[scope] or {}
      groups[scope][keys] = value
    end,
  },
  {
    kind = "views",
    title = "views",
    snapshot = function()
      local out = {}
      -- A buffer type's view is the buffer type's, listed as that.
      for name, view in pairs(paw.ui.views) do
        if not view.buftype then out[name] = view end
      end
      return out
    end,
    put = function(key, value)
      paw.ui.views[key] = value
      api.ui_redraw()
    end,
  },
  -- The line of keys at the bottom that a view of its shows, by view and mode.
  {
    kind = "keybar",
    title = "key bar lines",
    snapshot = two_level(function() return paw.ui.keybar and paw.ui.keybar.lines end),
    put = function(key, value)
      local view, mode = split(key)
      local lines = paw.ui.keybar.lines
      lines[view] = lines[view] or {}
      lines[view][mode] = value
      if next(lines[view]) == nil then lines[view] = nil end
      api.ui_redraw()
    end,
  },
  keyed("buftypes", "buffer types", function() return paw.layout.types end, function(key, value)
    paw.layout.types[key] = value
    if value then
      paw.layout.buftype(key, value)
    else
      paw.ui.views[key] = nil
    end
  end),
  keyed("textbuf_kinds", "text buffer kinds", function() return paw.textbuf and paw.textbuf.kinds end),
  keyed("track_kinds", "kinds of track", function() return paw.track_kinds.kinds end, function(key, value)
    if value then
      paw.track_kinds.define(key, value)
    else
      paw.track_kinds.remove(key)
    end
  end),
  keyed("clip_kinds", "kinds of clip", function() return paw.clip_kinds.kinds end, function(key, value)
    if value then
      paw.clip_kinds.define(key, value)
    else
      paw.clip_kinds.remove(key)
    end
  end),
  keyed("roles", "roles", function() return paw.roles and paw.roles.registry end, function(key, value)
    paw.roles.registry[key] = value
    -- Frontends that paint roles learn the set changed.
    paw.roles.version = paw.roles.version + 1
    api.ui_redraw()
  end),
  keyed("pickers", "picker sources", function() return paw.pick.sources end),
  {
    kind = "query_fields",
    title = "query fields",
    snapshot = two_level(function() return paw.query and paw.query.fields end),
    put = function(key, value)
      local kind, name = split(key)
      paw.query.fields[kind] = paw.query.fields[kind] or {}
      paw.query.fields[kind][name] = value
    end,
  },
  keyed("ex_fields", "fields of :s and :g", function() return paw.ex and paw.ex.fields end),
  keyed("ex_views", "views of ranges", function() return paw.ex and paw.ex.views end),
  keyed("completers", "completers", function() return paw.commands.completers end),
  keyed(
    "statusline",
    "status line components",
    function() return paw.statusline and paw.statusline.components end,
    function(key, value)
      paw.statusline.components[key] = value
      api.ui_redraw()
    end
  ),
  -- The parts of the track column, its signs and the parts of the bar
  -- labels: `set` puts a changed copy in, so unloading puts back the part
  -- that was there (a built-in one too), and takes away a new one with its
  -- name in `paw.opt.trackcolumn` or `paw.opt.barlabel`.
  keyed(
    "trackcolumn",
    "parts of the track column",
    function() return paw.trackcolumn and paw.trackcolumn.components end,
    function(key, value)
      if value then
        paw.trackcolumn.add(key, value)
      else
        paw.trackcolumn.remove(key)
      end
    end
  ),
  keyed(
    "trackcolumn_signs",
    "signs of the track column",
    function() return paw.trackcolumn and paw.trackcolumn.signs end,
    function(key, value) paw.trackcolumn.sign(key, value) end
  ),
  keyed(
    "barlabel",
    "parts of the bar labels",
    function() return paw.ruler and paw.ruler.labels end,
    function(key, value)
      if value then
        paw.ruler.add(key, value)
      else
        paw.ruler.remove(key)
      end
    end
  ),
  -- The keys of the arrange view's insert mode: `set` puts a changed copy
  -- in, so unloading puts back the kind that was on the key.
  keyed("insert", "keys of insert mode", function() return paw.insert and paw.insert.kinds end, function(key, value)
    if value then
      paw.insert.add(key, value)
    else
      paw.insert.remove(key)
    end
  end, function(key) return key .. " (insert mode)" end),
  keyed("grep", "grep sources", function() return paw.grep and paw.grep.sources end, function(key, value)
    local g = paw.grep
    if value and not g.sources[key] then g.order[#g.order + 1] = key end
    g.sources[key] = value
    if not value then
      for i = #g.order, 1, -1 do
        if g.order[i] == key then table.remove(g.order, i) end
      end
    end
  end),
  keyed("curves", "curve providers", function() return paw.curves and paw.curves.providers end),
  keyed("addresses", "address schemes", function() return paw.address and paw.address.schemes end),
  keyed("complete", "completion sources", function() return paw.complete and paw.complete.sources end),
  keyed("triggers", "controller buttons", function() return paw.learn and paw.learn.triggers end),
  {
    kind = "layers",
    title = "layers",
    snapshot = function()
      local out = {}
      for view, parts in pairs(paw.ui.layers) do
        for part, list in pairs(parts) do
          for _, layer in ipairs(list) do
            out[view .. " " .. part .. " " .. layer.name] = layer
          end
        end
      end
      return out
    end,
    put = function(key, value)
      local view, part, name = key:match("^(%S+) (%S+) (.*)$")
      paw.ui.layer(view, part, name, value and value.order, value and value.paint)
    end,
  },
  keyed("languages", "languages", function() return paw.lang and paw.lang.compilers end),
  keyed("health", "health checks", function() return paw.health and paw.health.checks end),
  keyed("formats", "file formats", function() return paw.formats and paw.formats.registry end, function(key, value)
    if value then
      paw.formats.register(value)
    else
      paw.formats.unregister(key)
    end
  end, function(key) return key end),
  {
    kind = "hooks",
    title = "hooks",
    snapshot = function()
      local out = {}
      for id, h in pairs(require("paw.events").handlers()) do
        out[id] = h
      end
      return out
    end,
    put = function(key, value)
      if not value then paw.off(key) end
    end,
    label = function(_, h) return h.pattern end,
  },
  -- An option goes with its definition, and the value set for it.
  {
    kind = "options",
    title = "options",
    snapshot = function() return paw.option.definitions() end,
    put = function(key, value) paw.option.undefine(key, value) end,
  },
  -- Only its own timers: the core's started while it loaded (a watch the
  -- core starts again) are not.
  keyed("timers", "timers", function() return paw.timers end, function(key, value)
    if not value then paw.cancel(key) end
  end, function() return "timer" end),
  keyed(
    "device_dirs",
    "devices written in Lua",
    function() return paw.luadev and paw.luadev.dirs end,
    function(key, value)
      if not value then paw.luadev.remove_dir(key) end
    end
  ),
  keyed(
    "plugin_dirs",
    "plugin directories",
    function() return paw.plugins and paw.plugins.dirs end,
    function(key, value)
      if not value then paw.plugins.remove_dir(key) end
    end
  ),
}
for _, reg in ipairs(M.registries) do
  reg.strict = reg.kind == "timers" or nil
end

local function snapshot()
  local out = {}
  for _, reg in ipairs(M.registries) do
    local ok, got = pcall(reg.snapshot)
    out[reg.kind] = ok and got or {}
  end
  return out
end

-- Which extension each entry is, by kind and key: an extension that loads
-- another while it loads does not take the other's entries for its own.
local claimed = {}

--- Record what `entry` added since `before` was taken.
local function claim(entry, before)
  local after = snapshot()
  entry.owned = entry.owned or {}
  for _, reg in ipairs(M.registries) do
    local was, now = before[reg.kind] or {}, after[reg.kind] or {}
    local list = entry.owned[reg.kind] or {}
    local function own(key, old)
      local id = reg.kind .. "\0" .. tostring(key)
      local holder = claimed[id]
      if holder and holder.value == now[key] and holder.name ~= entry.name then return end
      -- Another extension's entry replaced: the one loaded last wins, which
      -- `:checkhealth extensions` says.
      if holder and holder.name ~= entry.name and holder.value == old and old ~= nil then
        entry.overrides = entry.overrides or {}
        local what = reg.label and reg.label(key, now[key] or old) or tostring(key)
        entry.overrides[#entry.overrides + 1] = { kind = reg.title, what = what, of = holder.name }
      end
      claimed[id] = { name = entry.name, value = now[key] }
      list[#list + 1] = { key = key, value = now[key], old = old }
    end
    for key, value in pairs(now) do
      if was[key] ~= value and (not reg.strict or made_by(entry, value)) then own(key, was[key]) end
    end
    for key, value in pairs(was) do
      if now[key] == nil and not reg.strict then own(key, value) end
    end
    if #list > 0 then
      table.sort(list, function(a, b) return tostring(a.key) < tostring(b.key) end)
      entry.owned[reg.kind] = list
    end
  end
  entry.settled = after
end

--- Take for `entry`'s own what it registered after it loaded: entries new
--- or changed since then that its files made.
local function adopt(entry)
  if not entry.settled then return end
  local now = snapshot()
  for _, reg in ipairs(M.registries) do
    local settled, list = entry.settled[reg.kind] or {}, entry.owned[reg.kind] or {}
    local mine = {}
    for _, item in ipairs(list) do
      mine[item.key] = item
    end
    for key, value in pairs(now[reg.kind] or {}) do
      local id = reg.kind .. "\0" .. tostring(key)
      local holder = claimed[id]
      if
        value ~= settled[key]
        and not (holder and holder.name ~= entry.name and holder.value == value)
        and made_by(entry, value)
      then
        if mine[key] then
          mine[key].value = value
        else
          list[#list + 1] = { key = key, value = value, old = settled[key] }
        end
        claimed[id] = { name = entry.name, value = value }
        settled[key] = value
      end
    end
    entry.settled[reg.kind] = settled
    if #list > 0 then
      table.sort(list, function(a, b) return tostring(a.key) < tostring(b.key) end)
      entry.owned[reg.kind] = list
    end
  end
end

--- What a loaded extension registered: a list of `{ kind, title, items }`,
--- each item a short label, in the order of `paw.ext.registries`.
function M.provides(name)
  local entry = M.loaded[name]
  if entry then adopt(entry) end
  local out = {}
  for _, reg in ipairs(M.registries) do
    local list = entry and entry.owned and entry.owned[reg.kind]
    if list then
      local items = {}
      for _, item in ipairs(list) do
        if item.value ~= nil then
          items[#items + 1] = reg.label and reg.label(item.key, item.value) or tostring(item.key)
        end
      end
      if #items > 0 then out[#out + 1] = { kind = reg.kind, title = reg.title, items = items } end
    end
  end
  return out
end

-- Manifests ------------------------------------------------------------------------

--- An extension's manifest: `manifest.lua` in its directory. A one-file
--- extension has none. Returns the table (with `name` filled in), or nil
--- and what is wrong with it.
function M.manifest(path, name)
  if one_file(path) then return { name = name } end
  local file = path .. "/manifest.lua"
  if not exists(file) then return { name = name } end
  local chunk, err = loadfile(file)
  if not chunk then return nil, err end
  local ok, got = pcall(chunk)
  if not ok then return nil, got end
  if type(got) ~= "table" then return nil, "manifest.lua returns no table" end
  if got.name and got.name ~= name then return nil, "manifest.lua names it " .. tostring(got.name) end
  got.name = name
  return got
end

--- The loaded extension that is `name`, or that provides it.
local function holder(name)
  if M.loaded[name] then return M.loaded[name] end
  for _, entry in pairs(M.loaded) do
    for _, other in ipairs(entry.manifest and entry.manifest.provides or {}) do
      if other == name then return entry end
    end
  end
end

--- Load what an extension requires and check the versions. Returns nil,
--- or what is wrong.
local function require_all(entry)
  local requires = entry.manifest.requires or {}
  local names = {}
  for name in pairs(requires) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local want = requires[name]
    if name == "paw" then
      if not M.satisfies(api.version, want) then
        return "needs the paw API " .. want .. ", and this is " .. api.version
      end
    else
      local other = holder(name)
      if not other then
        -- Beside it first, then among those that come with the program.
        local sibling = entry.path:match("^(.*)/[^/]+$")
        if sibling and paw.lang.find(sibling .. "/" .. name .. "/init") then
          other = M.load(sibling .. "/" .. name)
        else
          other = M.load_bundled(name)
        end
        other = other or holder(name)
      end
      if not other then return "needs the extension " .. name .. ", which is not to be found" end
      if not other.ok then return "needs the extension " .. name .. ", which failed to load" end
      local version = other.manifest and other.manifest.version
      if want ~= "*" and want ~= true and not (version and M.satisfies(version, want)) then
        return "needs "
          .. name
          .. " "
          .. tostring(want)
          .. ", and "
          .. (version and "this is " .. version or "it says no version")
      end
    end
  end
end

-- Loading and unloading ------------------------------------------------------------

--- Load one extension from a directory or a file (`.lua`, or `.tl` or the
--- extension of another language of `paw.lang`). One the program
--- was built with is not loaded again from elsewhere: the configuration
--- that names the source tree's copy gets the packaged one.
function M.load(path)
  local name = name_of(path)
  local known = M.loaded[name]
  if known and known.packaged then return known end
  local entry = { name = name, path = path, ok = true }
  M.loaded[name] = entry
  local manifest, merr = M.manifest(path, name)
  entry.manifest = manifest or { name = name }
  entry.version = entry.manifest.version
  local err = merr or require_all(entry)
  if err then
    entry.ok, entry.error = false, err
    paw.notify("extension " .. name .. " failed: " .. tostring(err), "error")
    return entry
  end
  local before = snapshot()
  local outer = M.current
  M.current = entry
  local init = path
  if not one_file(path) then
    entry.lua_path = path .. "/lua/?.lua;" .. path .. "/lua/?/init.lua;"
    package.path = entry.lua_path .. package.path
    for _, item in ipairs(api.read_dir(path)) do
      if item.is_dir and item.name == "devices" and paw.luadev then
        paw.luadev.add_dir(path .. "/devices")
        entry.devices = path .. "/devices"
      end
    end
    init = paw.lang.find(path .. "/init")
    if not init then
      paw.snippet.load_dir(path .. "/snippets", "extension")
      claim(entry, before)
      M.current = outer
      paw.emit("ext.loaded", { name = name, ok = true })
      return entry
    end
  end
  local chunk
  chunk, err = paw.lang.loadfile(init)
  if chunk then
    -- Kept out of the compiler, so that the time limit can stop its loops.
    paw.limit.untrusted(chunk)
    entry.ok, err = xpcall(chunk, debug.traceback)
  else
    entry.ok = false
  end
  -- Its snippets, one file per set; the user's own of the same name win.
  if entry.ok and not one_file(path) then paw.snippet.load_dir(path .. "/snippets", "extension") end
  claim(entry, before)
  M.current = outer
  if not entry.ok then
    entry.error = err
    paw.notify("extension " .. name .. " failed: " .. tostring(err), "error")
  end
  paw.emit("ext.loaded", { name = name, ok = entry.ok })
  return entry
end

--- Of the device kinds an extension brings (its devices written in Lua and
--- the plugins in directories it added), those on tracks and the tracks'
--- names: `{ used = { kinds }, tracks = { names } }`.
local function devices_in_use(entry)
  local kinds, any = {}, false
  for _, item in ipairs(entry.owned and entry.owned.device_dirs or {}) do
    for _, kind in ipairs(paw.luadev.kinds_in(item.key)) do
      kinds[kind], any = true, true
    end
  end
  for _, item in ipairs(entry.owned and entry.owned.plugin_dirs or {}) do
    for _, kind in ipairs(item.value and item.value.kinds or {}) do
      kinds[kind], any = true, true
    end
  end
  local tracks, used, seen = {}, {}, {}
  if not any then return { tracks = tracks, used = used } end
  local ids = api.track_list()
  ids[#ids + 1] = 0
  for _, id in ipairs(ids) do
    local t = api.track_get(id)
    for _, device in ipairs(t.devices) do
      local kind = api.device_get(device).kind
      if kinds[kind] then
        if not seen[kind] then
          seen[kind], used[#used + 1] = true, kind
        end
        if tracks[#tracks] ~= t.name then tracks[#tracks + 1] = t.name end
      end
    end
  end
  return { tracks = tracks, used = used }
end

--- Unload an extension. paw removes all that it registered (while it
--- loaded, and later from its handlers and timers). paw puts back what it
--- replaced (a command or key of the core that it mapped again). Its
--- options go with their values, and its timers stop. paw stops to offer
--- the devices written in Lua and the plugin directories that it added. paw
--- forgets its modules, so a new load runs them again.
---
--- While a track contains one of its devices, paw does not unload it (as
--- Neovim does not delete a buffer with changes). With `opts.force`, it
--- unloads, and the devices stay and play until you remove them. paw cannot
--- find them when you open the project again without the extension. Returns
--- true (with `opts.force`, the devices that stay on tracks, in words), or
--- nil and the reason.
function M.unload(name, opts)
  local entry = M.loaded[name]
  if not entry then return nil, "no extension `" .. tostring(name) .. "` is loaded" end
  for _, other in pairs(M.loaded) do
    local requires = other ~= entry and other.ok and other.manifest and other.manifest.requires
    if requires and requires[name] ~= nil then return nil, other.name .. " requires " .. name .. ": unload it first" end
  end
  adopt(entry)
  local devices = devices_in_use(entry)
  local left
  if #devices.tracks > 0 then
    local what = table.concat(devices.used, ", ") .. " on " .. table.concat(devices.tracks, ", ")
    if not (opts and opts.force) then
      return nil,
        what
          .. ": remove "
          .. (#devices.used == 1 and "it" or "them")
          .. " first, or `:ext.unload! "
          .. name
          .. "` leaves "
          .. (#devices.used == 1 and "it" or "them")
          .. " there"
    end
    left = what .. " left there until removed"
  end
  paw.emit("ext.unloading", { name = name })
  -- Its hooks and timers go first, so that none of its code runs on what
  -- the rest of the unload changes (an option that goes emits
  -- `option.changed`); then the others, the last registered first.
  local order = {}
  for i = #M.registries, 1, -1 do
    local kind = M.registries[i].kind
    if kind == "hooks" or kind == "timers" then
      table.insert(order, 1, M.registries[i])
    else
      order[#order + 1] = M.registries[i]
    end
  end
  for _, reg in ipairs(order) do
    local list = entry.owned and entry.owned[reg.kind] or {}
    local now = reg.snapshot()
    for j = #list, 1, -1 do
      local item = list[j]
      -- Something registered over it since is left alone.
      if now[item.key] == item.value then pcall(reg.put, item.key, item.old) end
      claimed[reg.kind .. "\0" .. tostring(item.key)] = nil
    end
  end
  if entry.lua_path then
    local prefix = entry.path .. "/lua/"
    for module, _ in pairs(package.loaded) do
      local file = package.searchpath and package.searchpath(module, entry.lua_path)
        or paw.lang.searchpath(module, entry.lua_path)
      if file and file:sub(1, #prefix) == prefix then package.loaded[module] = nil end
    end
    local from, to = package.path:find(entry.lua_path, 1, true)
    if from then package.path = package.path:sub(1, from - 1) .. package.path:sub(to + 1) end
  end
  M.loaded[name] = nil
  api.ui_redraw()
  paw.emit("ext.unloaded", { name = name })
  return left or true
end

--- Load the extensions the program was built with: `dirs` is a list of
--- their directories separated by `:` (`$PAW_EXTENSIONS`, which the flake's
--- `paw.withExtensions` sets).
function M.load_packaged(dirs)
  for dir in (dirs or ""):gmatch("[^:]+") do
    local entry = M.load(dir)
    entry.packaged = true
  end
end

--- Load everything in a directory of extensions.
function M.load_dir(dir)
  for _, item in ipairs(api.read_dir(dir)) do
    local path = dir .. "/" .. item.name
    -- One loaded already, as another's requirement, is not loaded twice.
    local known = M.loaded[name_of(path)]
    if (item.is_dir or one_file(item.name)) and not (known and known.path == path) then M.load(path) end
  end
end

--- The directory of the extensions that come with paw:
--- `$PAW_HOME/extensions`, or `extensions` under the current directory in a
--- source tree. Nil when there is no such directory.
function M.bundled_dir()
  for _, root in ipairs({ os.getenv("PAW_HOME") or ".", "." }) do
    if #api.read_dir(root .. "/extensions") > 0 then return root .. "/extensions" end
  end
end

--- The names of the bundled extensions, loaded or not, sorted.
--- @type function(): {string}
function M.bundled()
  local dir, out = M.bundled_dir(), {}
  for _, item in ipairs(dir and api.read_dir(dir) or {}) do
    if item.is_dir then out[#out + 1] = item.name end
  end
  table.sort(out)
  return out
end

--- Load a bundled extension by name. A name that is loaded does not change.
--- Returns the entry, or nil and the problem.
function M.load_bundled(name)
  if M.loaded[name] then return M.loaded[name] end
  for _, known in ipairs(M.bundled()) do
    if known == name then return M.load(M.bundled_dir() .. "/" .. name) end
  end
  return nil,
    "no bundled extension `" .. tostring(name) .. "`" .. (M.bundled_dir() and "" or ": set PAW_HOME to the source tree")
end

--- Loaded extensions, sorted by name.
function M.list()
  local out = {}
  for _, entry in pairs(M.loaded) do
    out[#out + 1] = entry
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

return M
