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
--     optional = { notation = "*" },                 -- extensions it uses when they are there
--     provides = { "rhythms" },                      -- names others may require it by
--     needs = { "processes" },                       -- what the build must have
--     cmd = { "euclid" }, keys = { "<leader>re" },   -- it waits for these (paw/lazy.tl)
--   }
local api = paw.api
local registry = require("paw.registry")
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
--- @type function(path: string): string
local function name_of(path)
  local base = path:match("([^/]+)$")
  return (one_file(base) and base:gsub("%.[%w_]+$", "") or base)
end
M.name_of = name_of

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
-- A module that takes entries from extensions keeps them in a registry of
-- paw.registry, which records the owner of each entry as it goes in. The
-- owner is the extension whose code calls `put`, or for a registry made
-- with `made` (the timers), the extension whose files made the entry. An
-- entry put over the entry of another extension goes in `overrides`,
-- which `:checkhealth extensions` reads. paw.ext reads the owners at an
-- unload and in `provides`, and makes no copies.

--- The extension that loads now, or whose code calls: the owner of an
--- entry that it puts. paw/command.tl reads it for the commands too.
function registry.owner() return M.current and M.current.name or M.caller() end

--- The loaded extension whose files made `value`: the owner of an entry
--- of a registry made with `made` (the timers).
function registry.maker(value)
  for name, entry in pairs(M.loaded) do
    if made_by(entry, value) then return name end
  end
end

--- Records that the extension `owner` put an entry over an entry of the
--- extension `previous`. `:checkhealth extensions` gives a warning for it.
function registry.replaced(reg, what, owner, previous)
  local entry = M.loaded[owner]
  if not entry then return end
  entry.overrides = entry.overrides or {}
  entry.overrides[#entry.overrides + 1] = { kind = reg.title, what = what, of = previous }
end

--- What a loaded extension registered: a list of `{ kind, title, items }`,
--- each item a short label, in the order of the registries of
--- `paw.registry`.
function M.provides(name)
  local out = {}
  if not M.loaded[name] then return out end
  for _, reg in ipairs(registry.all()) do
    local items = reg:labels(name)
    if #items > 0 then out[#out + 1] = { kind = reg.kind, title = reg.title, items = items } end
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
  if got.needs ~= nil and type(got.needs) ~= "table" then
    return nil, 'manifest.lua: needs is a list of names, such as { "processes" }'
  end
  for _, field in ipairs({ "requires", "optional" }) do
    if got[field] ~= nil and type(got[field]) ~= "table" then
      return nil, "manifest.lua: " .. field .. ' is a table of names and versions, such as { notation = "*" }'
    end
  end
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

--- True if this build of paw has `feature`, one of the names of
--- `paw.api.build().features` such as `"processes"`. An extension that
--- works without a feature, but has one part that uses it, checks it here.
--- @param feature string
--- @return boolean
function M.build_has(feature)
  for _, have in ipairs(api.build().features) do
    if have == feature then return true end
  end
  return false
end

--- What the `needs` of a manifest names that this build does not have:
--- nil, or the reason it does not load. A name that no build knows is
--- missing too, so that a typo is said.
--- @type function(manifest: contracts.Manifest): string
function M.missing_needs(manifest)
  local missing = {}
  for _, need in ipairs(manifest.needs or {}) do
    if not M.build_has(need) then missing[#missing + 1] = tostring(need) end
  end
  if #missing == 0 then return end
  return "needs " .. table.concat(missing, " and ") .. ", which this build of paw does not have"
end

--- The names of a table of names and versions (`requires`, `optional`), sorted.
local function sorted_names(wants)
  local names = {}
  for name in pairs(wants or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

--- Nil when the loaded extension `other` has a version that `want`
--- accepts, or else what is wrong.
local function wrong_version(other, name, want)
  local version = other.manifest and other.manifest.version
  if want == "*" or want == true or (version and M.satisfies(version, want)) then return nil end
  return "needs "
    .. name
    .. " "
    .. tostring(want)
    .. ", and "
    .. (version and "this is " .. version or "it says no version")
end

--- Load what an extension requires and check the versions. Returns nil,
--- or what is wrong.
local function require_all(entry)
  local requires = entry.manifest.requires or {}
  for _, name in ipairs(sorted_names(requires)) do
    local want = requires[name]
    if name == "paw" then
      if not M.satisfies(api.version, want) then
        return "needs the paw API " .. want .. ", and this is " .. api.version
      end
    else
      local other = holder(name)
      local why = "required by " .. entry.name
      if not other and M.lazy and M.lazy.waiting[name] then other = M.lazy.load(name, why) end
      if not other then
        -- Beside it first, then among those that come with the program.
        local sibling = entry.path:match("^(.*)/[^/]+$")
        if sibling and paw.lang.find(sibling .. "/" .. name .. "/init") then
          other = M.load(sibling .. "/" .. name, why)
        else
          other = M.load_bundled(name, why)
        end
        other = other or holder(name)
      end
      if not other then
        return "needs the extension "
          .. name
          .. ", which is not to be found: put it beside "
          .. entry.name
          .. ", or in "
          .. api.env().config_dir
          .. "/extensions"
      end
      if not other.ok then return "needs the extension " .. name .. ", which failed to load" end
      local wrong = wrong_version(other, name, want)
      if wrong then return wrong end
    end
  end
end

-- The extensions that load together now (`load_dir`, `load_packaged`):
-- name -> path, and the function that loads one of them. Nil between.
local batch, batch_load

--- Load first the extensions of `optional` that load in the same batch.
--- One that is not there, or that waits for a trigger, does not load: the
--- extension works without it. A loaded one of a version that `optional`
--- does not accept gives a warning, and the extension loads.
local function optional_first(entry)
  local wants = entry.manifest.optional or {}
  for _, name in ipairs(sorted_names(wants)) do
    if not M.loaded[name] and batch and batch[name] then batch_load(batch[name]) end
    local other = holder(name)
    local wrong = other and other.ok and wrong_version(other, name, wants[name])
    if wrong then paw.notify("extension " .. entry.name .. " can use " .. wrong:gsub("^needs ", ""), "warn") end
  end
end

-- Loading and unloading ------------------------------------------------------------

local function load_one(path, why)
  local name = name_of(path)
  local known = M.loaded[name]
  if known and known.packaged then return known end
  -- One that waited for a trigger loads now by another way: its stubs go first.
  if M.lazy then M.lazy.forget(name) end
  local entry = { name = name, path = path, ok = true, loaded_by = why }
  M.loaded[name] = entry
  local manifest, merr = M.manifest(path, name)
  entry.manifest = manifest or { name = name }
  entry.version = entry.manifest.version
  -- The build first: an extension that cannot run here loads none of its
  -- requirements. A manifest that does not read has no needs.
  local missing = M.missing_needs(entry.manifest)
  local err = merr or missing or require_all(entry)
  if not err then optional_first(entry) end
  if err then
    entry.ok, entry.error, entry.needs_unmet = false, err, missing ~= nil
    paw.notify("extension " .. name .. " failed: " .. tostring(err), "error")
    return entry
  end
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
  M.current = outer
  if not entry.ok then
    entry.error = err
    paw.notify("extension " .. name .. " failed: " .. tostring(err), "error")
  end
  paw.emit("ext.loaded", { name = name, ok = entry.ok })
  return entry
end

--- Load one extension from a directory or a file (`.lua`, or `.tl` or the
--- extension of another language of `paw.lang`). One the program
--- was built with is not loaded again from elsewhere: the configuration
--- that names the source tree's copy gets the packaged one. `why` says how
--- it came to load, in words for `:extensions` (`entry.loaded_by`).
--- @type function(path: string, why?: string): contracts.ExtEntry
function M.load(path, why)
  -- A line of its own in the file of `paw --startuptime`.
  api.startup_enter()
  local entry = load_one(path, why or (M.started and "paw.ext.load" or "at start"))
  api.startup_leave("extension " .. name_of(path))
  return entry
end

--- Of the device kinds an extension brings (its devices written in Lua and
--- the plugins in directories it added), those on parts and the parts'
--- names: `{ used = { kinds }, parts = { names } }`.
local function devices_in_use(entry)
  local kinds, any = {}, false
  for _, dir in ipairs(paw.luadev.dirs:owned_by(entry.name)) do
    for _, kind in ipairs(paw.luadev.kinds_in(dir)) do
      kinds[kind], any = true, true
    end
  end
  for _, dir in ipairs(paw.plugins.dirs:owned_by(entry.name)) do
    local added = paw.plugins.dirs:get(dir)
    for _, kind in ipairs(added and added.kinds or {}) do
      kinds[kind], any = true, true
    end
  end
  local parts, used, seen = {}, {}, {}
  if not any then return { parts = parts, used = used } end
  local ids = api.part_list()
  ids[#ids + 1] = 0
  for _, id in ipairs(ids) do
    local t = api.part_get(id)
    for _, device in ipairs(t.devices) do
      local kind = api.device_get(device).kind
      if kinds[kind] then
        if not seen[kind] then
          seen[kind], used[#used + 1] = true, kind
        end
        if parts[#parts] ~= t.name then parts[#parts + 1] = t.name end
      end
    end
  end
  return { parts = parts, used = used }
end

--- Unload an extension. paw removes all that it registered (while it
--- loaded, and later from its handlers and timers). paw puts back what it
--- replaced (a command or key of the core that it mapped again). Its
--- options go with their values, and its timers stop. paw stops to offer
--- the devices written in Lua and the plugin directories that it added. paw
--- forgets its modules, so a new load runs them again.
---
--- While a part contains one of its devices, paw does not unload it (as
--- Neovim does not delete a buffer with changes). With `opts.force`, it
--- unloads, and the devices stay and play until you remove them. paw cannot
--- find them when you open the project again without the extension. Returns
--- true (with `opts.force`, the devices that stay on parts, in words), or
--- nil and the reason.
function M.unload(name, opts)
  local entry = M.loaded[name]
  -- One that waits for a trigger (again, after a load that failed): its stubs go.
  local waited = M.lazy and M.lazy.forget(name)
  if not entry and waited then return true end
  if not entry then return nil, "no extension `" .. tostring(name) .. "` is loaded" end
  for _, other in pairs(M.loaded) do
    local requires = other ~= entry and other.ok and other.manifest and other.manifest.requires
    if requires and requires[name] ~= nil then return nil, other.name .. " requires " .. name .. ": unload it first" end
  end
  local devices = devices_in_use(entry)
  local left
  if #devices.parts > 0 then
    local what = table.concat(devices.used, ", ") .. " on " .. table.concat(devices.parts, ", ")
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
  -- `option.changed`). Then the other registries, in the order they were
  -- made.
  local first, rest = {}, {}
  for _, reg in ipairs(registry.all()) do
    local list = (reg.kind == "hooks" or reg.kind == "timers") and first or rest
    list[#list + 1] = reg
  end
  for _, list in ipairs({ first, rest }) do
    for _, reg in ipairs(list) do
      pcall(reg.unload, reg, name)
    end
  end
  -- The kinds of split that it defined (`paw.chain.define_kind`) live in
  -- the kernel: they go too, and a split of one stays, absent.
  api.chain_kinds_unload(name)
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
--- Load a list of extensions together: each one waits for its triggers or
--- loads now (`use`), in the order of `paths`, but an extension that
--- another one of the list names in `optional` comes before it.
--- `start(path)` loads one of them.
local function load_batch(paths, start)
  local outer, outer_load = batch, batch_load
  batch = {}
  for _, path in ipairs(paths) do
    batch[name_of(path)] = path
  end
  local done = {}
  batch_load = function(path)
    if done[path] then return end
    done[path] = true
    start(path)
  end
  for _, path in ipairs(paths) do
    batch_load(path)
  end
  batch, batch_load = outer, outer_load
end

--- Use an extension: it waits for its triggers, or loads now (paw/lazy.tl).
--- `which` is a path, or the name of a bundled extension. `spec` gives
--- triggers in place of those of its manifest, field by field, and
--- `spec.lazy = false` loads it now. Returns the entry when it loaded, or
--- nil when it waits.
--- @type function(which: string, spec?: contracts.Triggers): contracts.ExtEntry
function M.use(which, spec) return M.lazy.use(which, spec, M.started and "paw.ext.use" or "at start") end

--- Load the extensions the program was built with: `dirs` is a list of
--- their directories separated by `:` (`$PAW_EXTENSIONS`, which the flake's
--- `paw.withExtensions` sets). Each one with triggers waits for them.
function M.load_packaged(dirs)
  local paths = {}
  for dir in (dirs or ""):gmatch("[^:]+") do
    paths[#paths + 1] = dir
  end
  load_batch(paths, function(dir)
    local entry = M.lazy.use(dir, nil, "at start")
    local waiting = M.lazy.waiting[name_of(dir)]
    if entry then
      entry.packaged = true
    elseif waiting then
      waiting.packaged = true
    end
  end)
end

--- Use everything in a directory of extensions: each one with triggers
--- waits for them, and the others load now.
function M.load_dir(dir)
  local paths = {}
  for _, item in ipairs(api.read_dir(dir)) do
    if item.is_dir or one_file(item.name) then paths[#paths + 1] = dir .. "/" .. item.name end
  end
  load_batch(paths, function(path)
    -- One loaded already, as another's requirement, is not loaded twice.
    local known = M.loaded[name_of(path)]
    if not (known and known.path == path) then M.lazy.use(path, nil, "at start") end
  end)
end

--- The directory of the extensions that come with paw:
--- `$PAW_HOME/extensions`, or `extensions` under the current directory in a
--- source tree. Nil when there is no such directory.
--- @type function(): string
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
function M.load_bundled(name, why)
  if M.loaded[name] then return M.loaded[name] end
  for _, known in ipairs(M.bundled()) do
    if known == name then return M.load(M.bundled_dir() .. "/" .. name, why) end
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
