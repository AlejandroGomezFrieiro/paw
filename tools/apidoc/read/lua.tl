-- The reader of the running program and of the Lua of the runtime: the
-- modules that `paw` reaches, their public functions with the `---` comment
-- over each, the values of `paw.api`, the options, and what the doc comments
-- of the modules still in Lua type (`@type`, `@call`).
local api = require("paw.api")
local model = require("apidoc.model")
local source = require("apidoc.source")
local names = require("apidoc.names")

local type Function = model.Function
local type Module = model.Module
local type Table = model.Table

local record lua
end

-- The values of the running program, as reflection sees them.
local loaded = package.loaded as {string: any}
local global = (_G as {string: Table}).paw

--- The modules of the runtime as they are reached from `paw`: each a table
--- that `require("paw...")` gives, by its shortest name, and the classes
--- (`paw.Track`), sorted by name.
function lua.modules(): {Module}
  -- The runtime's own: a name under `paw.` that has a file in runtime/lua.
  -- A module of an extension has its own name and its own README.
  local function ours(name: string): boolean
    return source.module_file(name, {".lua", "/init.lua", ".tl", "/init.tl"}) ~= nil
  end
  local name_of: {any: string} = {}
  for name, value in pairs(loaded) do
    if
      type(value) == "table" and (name == "paw" or name:match("^paw%.") ~= nil) and name ~= "paw.api" and ours(name)
    then
      -- A table under two names (paw.frontend is paw.frontend.core) takes
      -- the shorter, whatever the order of `pairs`.
      if not name_of[value] or #name < #name_of[value] then
        name_of[value] = name
      end
    end
  end
  local record Step
    name: string
    table: Table
    depth: integer
  end
  local found: {any: boolean} = {}
  local out: {Module} = {}
  local queue: {Step} = {{name = "paw", table = global, depth = 0}}
  local i = 1
  while queue[i] do
    local step = queue[i]
    i = i + 1
    local class = step.depth == 1 and step.name:match("^paw%.%u")
    if not found[step.table] and (name_of[step.table] or class) then
      found[step.table] = true
      out[#out + 1] = {name = step.name, table = step.table, module = name_of[step.table]}
      if step.depth < 3 then
        local keys: {string} = {}
        for k, v in pairs(step.table) do
          if k is string and type(v) == "table" and not k:match("^_") and k ~= "api" then
            keys[#keys + 1] = k
          end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
          queue[#queue + 1] = {name = step.name .. "." .. k, table = step.table[k] as Table, depth = step.depth + 1}
        end
      end
    end
  end
  table.sort(out, function(a: Module, b: Module): boolean return a.name < b.name end)
  return out
end

--- The `---` comment over the line where a Lua function starts, the file and
--- the line: nil for a function the runtime did not write. A function made
--- by another (`M.join = small(function ... end)`) has its comment over the
--- line that names it `key`.
function lua.doc_of(fn: function(...: any): any..., key: string): {string}, string, integer
  local info = debug.getinfo(fn, "S")
  local path = info.source:match("^@.-(runtime/lua/.*)$")
  if not path then
    return nil
  end
  local lines = source.kept(path)
  local at = info.linedefined
  local first = lines[at] or ""
  if not (
    first:match("^%s*local%s+function")
    or first:match("^%s*function%s")
    or first:match('^%s*[%w_.:%[%]"]+%s*=%s*function')
  ) then
    for i, line in ipairs(lines) do
      if line:match("^%s*[%w_.]*%." .. key .. "%s*=") then
        at = i
        break
      end
    end
  end
  return source.doc_over(lines, at), path, at
end

-- The names of a function's parameters, and `...` for a vararg.
local function params_of(fn: function(...: any): any...): {string}
  local out: {string} = {}
  local info = debug.getinfo(fn, "u")
  for i = 1, info.nparams or 0 do
    out[#out + 1] = debug.getlocal(fn, i)
  end
  if info.isvararg then
    out[#out + 1] = "..."
  end
  return out
end

--- Every public function of `modules`, by module, in order. A function
--- reached under two names is written once, the other name an alias of it;
--- so is a function of `paw.api` under another name.
function lua.functions(modules: {Module}, kernel: model.Kernel): {Function}
  local seen: {any: string} = {}
  local out: {Function} = {}
  for _, mod in ipairs(modules) do
    local keys: {string} = {}
    for k, v in pairs(mod.table) do
      if k is string and type(v) == "function" and not k:match("^_") then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local fn = mod.table[k] as function(...: any): any...
      local full = mod.name .. "." .. k
      local entry: Function = {name = full, module = mod.name, key = k}
      if seen[fn] then
        entry.alias_of = seen[fn]
      elseif kernel.name_of[fn] then
        entry.alias_of = "paw.api." .. kernel.name_of[fn]
      else
        seen[fn] = full
        entry.doc, entry.path, entry.line = lua.doc_of(fn, k)
        entry.params = params_of(fn)
        -- A method, written with `:`: its `self` is not named.
        if entry.params[1] == "self" and mod.name:match("^paw%.%u") then
          entry.method = true
          table.remove(entry.params, 1)
        end
      end
      out[#out + 1] = entry
    end
  end
  return out
end

--- `paw.api` as the program has it, with what `functions` (the reader of
--- the source) shows of each function.
function lua.kernel(functions: {string: model.KernelFunction}): model.Kernel
  local k: model.Kernel = {version = api.version, names = {}, functions = functions, plain = {}, name_of = {}}
  for name, v in pairs(api as {string: any}) do
    if type(v) == "function" then
      k.names[#k.names + 1] = name
      k.name_of[v] = name
    elseif name ~= "version" and (type(v) == "boolean" or type(v) == "string" or type(v) == "number") then
      k.plain[#k.plain + 1] = {name = name, type = type(v)}
    end
  end
  table.sort(k.names)
  -- In the order of their lines `name: type`.
  table.sort(k.plain, function(a: model.Plain, b: model.Plain): boolean return a.name .. ":" < b.name .. ":" end)
  return k
end

--- The options that the runtime defines, by name: the types of their spec
--- (a type or a list of them), or of their default.
function lua.options(): {model.Option}
  local out: {model.Option} = {}
  for _, info in ipairs(paw.option.list()) do
    local spec = paw.option.spec(info.name)
    local list = spec and spec.type or type(info.default)
    out[#out + 1] = {name = info.name, types = list is string and {list} or list, integer = spec and spec.integer}
  end
  return out
end

-- The modules in Lua: the types their doc comments give -----------------------------
--
-- A module that is not ported yet types what an extension or a module in
-- Teal calls with `@type` lines in its `---` comments, as api/ does for
-- the kernel. Over a function, each line is one form of it:
--
--   --- Register a view. ...
--   --- @type function<V is contracts.View>(name: string, def: V): V
--   function M.view(name, def)
--
-- Over a value (`M.views = {}`, or a field of the table that makes the
-- module, `views = {},`), the line is its type: `--- @type {string:contracts.View}`.
-- A function whose module is callable gives the call with `@call` (paw.pick).
-- The types may name `types.X` (runtime/lua/paw/types.tl) and `contracts.X`
-- (runtime/lua/paw/contracts.tl). What a module does not type is
-- `paw.Untyped`, as before.

-- The forms of a function in Lua (`@type` lines) and its call (`@call`).
local function forms_of(fn: function(...: any): any..., key: string): {string}, string
  local doc = lua.doc_of(fn, key)
  local forms: {string} = {}
  local call: string
  for _, line in ipairs(doc or {}) do
    local t = line:match("^@type%s+(function.+)$")
    if t then
      forms[#forms + 1] = t
    end
    call = call or line:match("^@call%s+(function.+)$")
  end
  return forms, call
end

-- The types of the values of a module in Lua, by key: each line that sets
-- one (`M.key =`, `paw.key =`, or `key =` in the table that makes the
-- module) under a `--- @type T` comment. A value that is nil until later
-- (`M.current = nil`) is found too.
local function value_types(file: string): {string: string}
  local lines = source.kept(file)
  local out: {string: string} = {}
  for i, line in ipairs(lines) do
    local key = line:match("^%s*[%w_]+%.([%w_]+)%s*=") or line:match("^%s+([%w_]+)%s*=")
    if key and not out[key] then
      local n = i - 1
      while n > 0 and lines[n]:match("^%s*%-%-%-") do
        local t = lines[n]:match("^%s*%-%-%-%s*@type%s+(.+)$")
        if t then
          out[key] = t
          break
        end
        n = n - 1
      end
    end
  end
  return out
end

-- Whether a type in the source of a module in Teal can be written in
-- partial.d.tl, which names only `types.X`, `contracts.X` and the type's
-- own generic parameters: not a type of the module's own, nor of another
-- module in Teal (which requires partial.d.tl).
local function partial_safe(t: string): boolean
  if not t then
    return false
  end
  local params: {string: boolean} = {}
  for list in t:gmatch("<([^>]*)>") do
    for name in list:gmatch("([%a_][%w_]*)%s+is") do
      params[name] = true
    end
    for name in list:gmatch("^%s*([%a_][%w_]*)%s*$") do
      params[name] = true
    end
    for name in list:gmatch("([%a_][%w_]*)%s*,") do
      params[name] = true
    end
  end
  for word in t:gmatch("%f[%w_.][%a_][%w_.]*") do
    local head = word:match("^([%a_][%w_]*)%.")
    if head then
      if head ~= "types" and head ~= "contracts" then
        return false
      end
    elseif word:match("^%u") and not params[word] then
      return false
    end
  end
  return true
end

--- What the doc comments of the modules in Lua type. `teal_modules` are the
--- modules in Teal, and `teal_values` the Teal type of each of their values,
--- by the value: another name of one in a module in Lua has its type.
function lua.types(modules: {Module}, teal_modules: {model.TealModule}, teal_values: {any: string}): model.LuaTypes
  local is_teal: {string: boolean} = {}
  for _, mod in ipairs(teal_modules) do
    is_teal[mod.name] = true
  end
  local out: model.LuaTypes = {records = {}, forms = {}, top = {}}
  local function file_of(module: string): string
    local file = "runtime/lua/" .. module:gsub("%.", "/")
    return source.read(file .. ".lua") and file .. ".lua" or file .. "/init.lua"
  end
  local function members(t: Table, module: string): {{string}}, string
    local lines: {{string}} = {}
    local keys: {string} = {}
    local valued = value_types(file_of(module))
    for k in pairs(t) do
      if k is string and k:match("^%a[%w_]*$") and not names.KEYWORDS[k] then
        keys[#keys + 1] = k
      end
    end
    for k in pairs(valued) do
      if t[k] == nil and not names.KEYWORDS[k] then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys)
    local call: string
    for _, k in ipairs(keys) do
      local v = t[k]
      local typed = teal_values[v]
      if type(v) == "function" then
        local forms, c = forms_of(v as function(...: any): any..., k)
        -- A function of a module in Teal under another name
        -- (`paw.ui.role` is `paw.roles.define`): the type in its source.
        if #forms == 0 and partial_safe(typed) then
          forms = {typed}
        end
        if #forms > 0 then
          out.forms[v] = forms
        end
        for _, form in ipairs(forms) do
          lines[#lines + 1] = {k, form}
        end
        call = call or c
      elseif valued[k] then
        lines[#lines + 1] = {k, valued[k]}
      elseif type(v) == "table" and partial_safe(typed) and not typed:match("^type ") then
        lines[#lines + 1] = {k, typed}
      end
    end
    return lines, call
  end
  for _, mod in ipairs(modules) do
    local depth = select(2, mod.name:gsub("%.", ""))
    if depth == 1 and mod.module and not is_teal[mod.name] and not mod.name:match("^paw%.%u") then
      local lines, call = members(mod.table, mod.module)
      if #lines > 0 then
        out.records[#out.records + 1] = {
          name = mod.name, table = mod.table, record = names.record(mod.name), lines = lines, call = call
        }
      end
    end
  end
  -- `paw` itself: its functions, and the values that init.lua types.
  for _, line in ipairs((members(global, "paw"))) do
    out.top[line[1]] = out.top[line[1]] or {}
    table.insert(out.top[line[1]], line[2])
  end
  return out
end

return lua
