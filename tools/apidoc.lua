-- The Lua API's reference, made from the source: the `---` comment over
-- each public function of the `paw` modules, and the `//` comment over
-- each `paw.api` function in crates/paw-core/src/api.rs. Run from the
-- source tree:
--
--   paw --clean --no-plugins -l tools/apidoc.lua          write both files
--   paw --clean --no-plugins -l tools/apidoc.lua check    say what is out of date or undocumented
--
-- It writes runtime/types/paw.lua, a LuaLS meta file (point `workspace.library`
-- at runtime/types, and editors complete `paw.*` in a configuration or an
-- extension), and docs/reference/api.md, the reference `:help` shows (`:help
-- paw.commands.define`). tests/apidoc.lua checks both are up to date and
-- that every public function says what it does.
local api = paw.api
local M = {}

M.META = "runtime/types/paw.lua"
M.PAGE = "docs/reference/api.md"

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function lines_of(path)
  local text = read(path)
  if not text then return nil end
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
  return out
end

-- Modules ---------------------------------------------------------------------------

--- The modules of the runtime as they are reached from `paw`: each a table
--- that `require("paw...")` gives, by its shortest name, and the classes
--- (`paw.Track`). A list of `{ name, table, module }`, sorted by name.
function M.modules()
  -- The runtime's own: an extension may put a module of its under `paw.`
  -- (`package.loaded["paw.sampler"]`), which is its to document.
  local function ours(name)
    local file = "runtime/lua/" .. name:gsub("%.", "/")
    return read(file .. ".lua") or read(file .. "/init.lua") or read(file .. ".tl") or read(file .. "/init.tl")
  end
  local loaded = {}
  for name, value in pairs(package.loaded) do
    if type(value) == "table" and (name == "paw" or name:match("^paw%.")) and name ~= "paw.api" and ours(name) then loaded[value] = name end
  end
  local found, out = {}, {}
  local queue = { { "paw", paw, 0 } }
  local i = 1
  while queue[i] do
    local name, t, depth = queue[i][1], queue[i][2], queue[i][3]
    i = i + 1
    local class = depth == 1 and name:match("^paw%.%u")
    if not found[t] and (loaded[t] or class) then
      found[t] = true
      out[#out + 1] = { name = name, table = t, module = loaded[t] }
      if depth < 3 then
        local keys = {}
        for k, v in pairs(t) do
          if type(k) == "string" and type(v) == "table" and not k:match("^_") and k ~= "api" then keys[#keys + 1] = k end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do queue[#queue + 1] = { name .. "." .. k, t[k], depth + 1 } end
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Functions and their comments -------------------------------------------------------

local sources = {}

--- The `---` comment over the line where a Lua function starts, and the
--- line itself: nil for a function the runtime did not write. A function
--- made by another (`M.join = small(function ... end)`) has its comment over
--- the line that names it `key`.
local function lua_doc(fn, key)
  local info = debug.getinfo(fn, "S")
  local path = info.source:match("^@.-(runtime/lua/.*)$")
  if not path then return nil end
  sources[path] = sources[path] or lines_of(path) or {}
  local lines = sources[path]
  local at = info.linedefined
  local first = lines[at] or ""
  if not (first:match("^%s*local%s+function") or first:match("^%s*function%s") or first:match("^%s*[%w_.:%[%]\"]+%s*=%s*function")) then
    for i, line in ipairs(lines) do
      if line:match("^%s*[%w_.]*%." .. key .. "%s*=") then at = i break end
    end
  end
  local doc = {}
  local n = at - 1
  while n > 0 and lines[n] and lines[n]:match("^%s*%-%-%-") do
    table.insert(doc, 1, (lines[n]:gsub("^%s*%-%-%- ?", "")))
    n = n - 1
  end
  return doc, path, at
end

local function params_of(fn)
  local out = {}
  local info = debug.getinfo(fn, "u")
  for i = 1, info.nparams or 0 do out[#out + 1] = debug.getlocal(fn, i) end
  if info.isvararg then out[#out + 1] = "..." end
  return out
end

--- The `paw.api` functions as api.rs has them: name -> `{ params, types, doc }`.
function M.kernel_functions()
  local out = {}
  local lines = lines_of("crates/paw-core/src/api.rs") or {}
  local comment = {}
  for _, line in ipairs(lines) do
    local name, args, types = line:match("^%s+fn ([%w_]+)%([%w_]+, [%w_]+, (.-) => (.-)%)%s*{")
    if name then
      local params = {}
      if args ~= "()" then
        for p in args:gsub("^%(", ""):gsub("%)$", ""):gmatch("[%w_]+") do params[#params + 1] = p end
      end
      local list = {}
      local inner = types:match("^%((.*)%)$") or types
      local depth, cur = 0, ""
      for ch in inner:gmatch(".") do
        if ch == "<" then depth = depth + 1 elseif ch == ">" then depth = depth - 1 end
        if ch == "," and depth == 0 then list[#list + 1] = cur cur = "" else cur = cur .. ch end
      end
      if cur:match("%S") then list[#list + 1] = cur end
      out[name] = { params = params, types = list, doc = comment }
      comment = {}
    elseif line:match("^%s+//") then
      comment[#comment + 1] = (line:gsub("^%s+// ?", ""))
    elseif not line:match("^%s*$") or #comment > 0 then
      comment = {}
    end
  end
  return out
end

local RUST_TYPES = {
  String = "string", f64 = "number", f32 = "number", i64 = "integer", u64 = "integer", u32 = "integer",
  i32 = "integer", usize = "integer", u8 = "integer", u16 = "integer", Id = "integer", bool = "boolean",
  LuaValue = "any", Table = "table", Function = "function", ["()"] = "nil",
}

local function lua_type(rust)
  rust = rust:gsub("^%s+", ""):gsub("%s+$", "")
  local inner = rust:match("^Option<(.*)>$")
  if inner then return lua_type(inner) .. "?" end
  local vec = rust:match("^Vec<(.*)>$")
  if vec then return lua_type(vec) .. "[]" end
  return RUST_TYPES[rust] or "any"
end

--- Every public function: `{ name, fn, params, doc, path, line, method,
--- alias_of }`, by module, in order. A function reached under two names is
--- written once, the other name an alias of it.
function M.functions()
  local seen, out = {}, {}
  local kernel = {}
  for name, fn in pairs(api) do
    if type(fn) == "function" then kernel[fn] = name end
  end
  for _, mod in ipairs(M.modules()) do
    local names = {}
    for k, v in pairs(mod.table) do
      if type(k) == "string" and type(v) == "function" and not k:match("^_") then names[#names + 1] = k end
    end
    table.sort(names)
    for _, k in ipairs(names) do
      local fn = mod.table[k]
      local full = mod.name .. "." .. k
      local entry = { name = full, module = mod.name, key = k, fn = fn }
      if seen[fn] then
        entry.alias_of = seen[fn]
      elseif kernel[fn] then
        entry.alias_of = "paw.api." .. kernel[fn]
      else
        seen[fn] = full
        local doc, path, line = lua_doc(fn, k)
        entry.doc, entry.path, entry.line = doc, path, line
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

--- The public functions with no `---` comment: their names and where they are.
function M.undocumented()
  local out = {}
  for _, f in ipairs(M.functions()) do
    if not f.alias_of and f.path and #f.doc == 0 then out[#out + 1] = f.name .. "  " .. f.path .. ":" .. f.line end
  end
  return out
end

-- Writing -----------------------------------------------------------------------------

local HEADER = "Generated by tools/apidoc.lua from the source's comments: do not edit."

local function call_name(f)
  return f.method and f.name:gsub("%.([%w_]+)$", ":%1") or f.name
end

--- The LuaLS meta file's text.
function M.meta()
  local out = { "---@meta", "-- " .. HEADER, "-- Point LuaLS at this directory (`workspace.library`) to complete `paw.*`.", "" }
  local function add(line) out[#out + 1] = line end
  for _, mod in ipairs(M.modules()) do
    add("---@class " .. mod.name)
    add(mod.name .. " = {}")
    add("")
  end
  add("---@class paw.api")
  add("paw.api = {}")
  add("---@type string")
  add("paw.api.version = " .. string.format("%q", api.version))
  add("")
  for _, f in ipairs(M.functions()) do
    if f.alias_of then
      add(f.name .. " = " .. f.alias_of)
    else
      for _, line in ipairs(f.doc or {}) do add("--- " .. line) end
      for _, p in ipairs(f.params) do
        if p ~= "..." and not (f.doc and table.concat(f.doc, "\n"):find("@param " .. p .. "%f[^%w_]")) then add("---@param " .. p .. " any") end
      end
      add("function " .. call_name(f) .. "(" .. table.concat(f.params, ", ") .. ") end")
    end
    add("")
  end
  local kernel = M.kernel_functions()
  local names = {}
  for name, fn in pairs(api) do
    if type(fn) == "function" then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local k = kernel[name]
    if k then
      -- The `@param`/`@return` lines are in Teal's notation, for paw.d.tl.
      for _, line in ipairs(k.doc) do if not line:match("^@") then add("--- " .. line) end end
      for i, p in ipairs(k.params) do add("---@param " .. p .. " " .. lua_type(k.types[i] or "LuaValue")) end
      add("function paw.api." .. name .. "(" .. table.concat(k.params, ", ") .. ") end")
    else
      add("---@type fun(...): any")
      add("paw.api." .. name .. " = nil")
    end
    add("")
  end
  return table.concat(out, "\n")
end

local function signature(f)
  return call_name(f) .. "(" .. table.concat(f.params or {}, ", ") .. ")"
end

--- The `:help` page's Markdown.
function M.page()
  local out = { "# Lua API reference", "", "<!-- " .. HEADER .. " -->", "",
    "Each public function of the `paw` modules, module by module, with the",
    "comment from its source. [Scripts](scripting.md) and",
    "[Extensions](extensions.md) tell how the functions work together. The",
    "functions of the kernel (`paw.api`, plain data in and out) are at the end.",
    "`runtime/types/paw.lua` contains the same data for editors (LuaLS).", "" }
  local function add(line) out[#out + 1] = line end
  local by_module = {}
  for _, f in ipairs(M.functions()) do
    by_module[f.module] = by_module[f.module] or {}
    table.insert(by_module[f.module], f)
  end
  for _, mod in ipairs(M.modules()) do
    local list = by_module[mod.name]
    if list then
      add("## Module " .. mod.name)
      add("")
      for _, f in ipairs(list) do
        if f.alias_of then
          add("- `" .. f.name .. "`: the same as `" .. f.alias_of .. "`.")
        else
          local sig = signature(f)
          local doc = {}
          for _, line in ipairs(f.doc or {}) do
            if not line:match("^@") then doc[#doc + 1] = line end
          end
          -- Runs of prose and of examples (the lines indented in the
          -- comment), in order: the first prose after the name, the rest
          -- under it. An empty line ends a paragraph of prose.
          local runs = {}
          local ended = false
          for _, line in ipairs(doc) do
            local code = line:match("^  ") ~= nil
            local last = runs[#runs]
            if line == "" then
              ended = true
            else
              if not last or last.code ~= code or ended then
                last = { code = code }
                runs[#runs + 1] = last
              end
              ended = false
              last[#last + 1] = code and line:gsub("^  ", "") or line
            end
          end
          local first = runs[1] and not runs[1].code and table.remove(runs, 1)
          add("- `" .. sig .. "`" .. (first and ": " .. table.concat(first, " ") or ""))
          for _, run in ipairs(runs) do
            add("")
            if run.code then
              add("  ```lua")
              for _, line in ipairs(run) do add("  " .. line) end
              add("  ```")
            else
              add("  " .. table.concat(run, " "))
            end
          end
        end
      end
      add("")
    end
  end
  add("## Module paw.api")
  add("")
  local kernel = M.kernel_functions()
  local names = {}
  for name, fn in pairs(api) do
    if type(fn) == "function" then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local k = kernel[name]
    local params = k and table.concat(k.params, ", ") or "..."
    local prose = {}
    for _, line in ipairs(k and k.doc or {}) do if not line:match("^@") then prose[#prose + 1] = line end end
    local doc = #prose > 0 and ": " .. table.concat(prose, " ") or ""
    add("- `paw.api." .. name .. "(" .. params .. ")`" .. doc)
  end
  add("")
  return table.concat(out, "\n")
end

-- Teal ---------------------------------------------------------------------------------
--
-- runtime/types/paw.d.tl declares the `paw` global for the files written in
-- Teal. It holds what Teal cannot see by itself:
--
-- - `paw.api`, the functions of the kernel, written in Rust. Their types come
--   from api.rs: the Rust type of each parameter, or a `// @param name T`
--   line of its comment, and a `// @return T, U` line. T is in Teal's
--   notation and may name the records of runtime/lua/paw/types.tl as
--   `types.Name`. A function with no `@return` returns `any...`.
-- - the runtime's modules that are written in Teal, each by its own types
--   (`local type HarmonyReadModule = require("paw.harmony.read")`).
--
-- A module written in Lua is not declared: it is typed by porting it to
-- Teal. Each `any` in the file must be on the allow-list
-- (runtime/types/any-allowed.txt), with its reason, and the count only goes
-- down (docs/explanation/about-teal.md).

M.TEAL = "runtime/types/paw.d.tl"
M.TEAL_API = "runtime/types/paw/api.d.tl"
M.ANY = "runtime/types/any-allowed.txt"

local RUST_TEAL = {
  String = "string", f64 = "number", f32 = "number", i64 = "integer", u64 = "integer", u32 = "integer",
  i32 = "integer", usize = "integer", u8 = "integer", u16 = "integer", Id = "integer", bool = "boolean",
  LuaValue = "any", Table = "{any:any}", Function = "function(...: any): any...", LuaString = "string",
}

local function rust_teal(rust)
  rust = rust:gsub("^%s+", ""):gsub("%s+$", "")
  local inner = rust:match("^Option<(.*)>$")
  if inner then return rust_teal(inner), true end
  local vec = rust:match("^Vec<(.*)>$")
  if vec then return "{" .. (rust_teal(vec)) .. "}" end
  return RUST_TEAL[rust] or "any"
end

-- Lua's keywords, which cannot name a parameter in Teal either.
local KEYWORDS = {}
for word in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%a+") do KEYWORDS[word] = true end

--- The Teal type of a kernel function, from api.rs.
local function kernel_sig(k)
  local typed, rets = {}, nil
  for _, line in ipairs(k.doc) do
    local name, opt, t = line:match("^@param%s+([%w_]+)(%??)%s+(.+)$")
    if name then typed[name] = { t = t, optional = opt == "?" } end
    local r = line:match("^@return%s+(.+)$")
    if r then rets = r end
  end
  local params = {}
  for i, p in ipairs(k.params) do
    local t, opt
    if typed[p] then
      t, opt = typed[p].t, typed[p].optional
    else
      t, opt = rust_teal(k.types[i] or "LuaValue")
    end
    params[#params + 1] = (KEYWORDS[p] and p .. "_" or p) .. (opt and "?: " or ": ") .. t
  end
  local ret = rets == nil and ": any..." or (rets == "nil" and "" or ": " .. rets)
  return "function(" .. table.concat(params, ", ") .. ")" .. ret
end

--- The modules of the runtime written in Teal, by name: `{ name, module, file }`.
function M.teal_modules()
  local out = {}
  for _, mod in ipairs(M.modules()) do
    local file = mod.module and "runtime/lua/" .. mod.module:gsub("%.", "/")
    for _, candidate in ipairs({ file and file .. ".tl", file and file .. "/init.tl" }) do
      -- Under any name: `paw.option` is the module paw.options.
      if read(candidate) then
        out[#out + 1] = { name = mod.name, module = mod.module, file = candidate }
        break
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- The Teal type of each value that a module written in Teal gives, by the
--- value, for the names that are another way to it (`paw.on` is
--- `paw.events.on`, `paw.opt` is `paw.option.opt`): the function's
--- signature in its source, or the field's type in the module's record, with
--- the types that the module gives (`type Handler = Handler`) named as
--- `Alias.Handler`.
local function teal_values(mods, alias_of)
  local out = {}
  for _, mod in ipairs(mods) do
    local text = read(mod.file) or ""
    local alias = alias_of(mod)
    local exported = {}
    for name in text:gmatch("\n%s+type ([%w_]+) =") do exported[name] = true end
    local function qualify(t)
      return (t:gsub("%f[%w_.][%a_][%w_]*%f[^%w_]", function(word)
        return exported[word] and alias .. "." .. word or word
      end))
    end
    local record = text:match("\nlocal record M\n(.-)\nend\n") or ""
    local value = package.loaded[mod.module]
    for name, v in pairs(type(value) == "table" and value or {}) do
      if type(name) == "string" then
        local t
        if type(v) == "function" then
          local rest = text:match("\nfunction M%." .. name .. "(%f[^%w_][^\n]*)")
          local generics = rest and rest:match("^<[^>]*>") or ""
          local sig = rest and rest:sub(#generics + 1):match("^(%b().-)%s*$")
          -- A signature alone: not a function written on one line.
          if sig and not sig:find("%f[%w_]return%f[^%w_]") and not sig:find("%f[%w_]end%f[^%w_]") then
            t = "function" .. generics .. sig
          end
        else
          t = record:match("\n%s+" .. name .. ": ([^\n]+)") or record:match("^%s+" .. name .. ": ([^\n]+)")
        end
        if t and not out[v] then out[v] = qualify(t) end
      end
    end
  end
  return out
end

--- The text of runtime/types/paw.d.tl, the text of
--- runtime/types/paw/api.d.tl (the kernel's functions, as the module
--- `paw.api` that a module in Teal requires), and their `any` by the name
--- of what has them: `{ [name] = count }`.
function M.teal()
  local anys = {}
  local function count(name, text)
    local n = 0
    for _ in text:gmatch("%f[%w_]any%f[^%w_]") do n = n + 1 end
    for _ in text:gmatch("%f[%w_]Untyped%f[^%w_]") do n = n + 1 end
    if n > 0 then anys[name] = (anys[name] or 0) + n end
    return text
  end
  local out = { "-- " .. HEADER, "-- The `paw` global for the files written in Teal (tlconfig.lua's",
    "-- global_env_def): the kernel's functions, and the modules of the runtime",
    "-- that are written in Teal.", "" }
  local mods = M.teal_modules()
  out[#out + 1] = "local type Api = require(\"paw.api\")"
  local tree = { children = {}, order = {}, lines = {} }
  local function alias_of(mod)
    return (mod.name:gsub("^paw%.", ""):gsub("[._](%l)", string.upper):gsub("^%l", string.upper)) .. "Module"
  end
  local values = teal_values(mods, alias_of)
  for _, mod in ipairs(mods) do
    local alias = alias_of(mod)
    out[#out + 1] = "local type " .. alias .. " = require(\"" .. mod.module .. "\")"
    local node = tree
    local parts = {}
    for part in mod.name:gmatch("[^.]+") do parts[#parts + 1] = part end
    for i = 2, #parts - 1 do
      local key = parts[i]
      if not node.children[key] then
        node.children[key] = { children = {}, order = {}, lines = {} }
        node.order[#node.order + 1] = key
      end
      node = node.children[key]
    end
    node.lines[#node.lines + 1] = parts[#parts] .. ": " .. alias
  end
  out[#out + 1] = ""
  out[#out + 1] = "global record paw"
  out[#out + 1] = "   api: Api"
  local kout = { "-- " .. HEADER, "-- The functions of the kernel, written in Rust (crates/paw-core/src/api.rs):",
    "-- `local api = require(\"paw.api\")` in a module written in Teal.", "" }
  if read("runtime/lua/paw/types.tl") then
    kout[#kout + 1] = "local type types = require(\"paw.types\")"
    kout[#kout + 1] = ""
  end
  kout[#kout + 1] = "local record api"
  kout[#kout + 1] = "   version: string"
  local kernel = M.kernel_functions()
  local names = {}
  for name, fn in pairs(api) do
    if type(fn) == "function" then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local sig = kernel[name] and kernel_sig(kernel[name]) or "function(...: any): any..."
    kout[#kout + 1] = "   " .. count("paw.api." .. name, name .. ": " .. sig)
  end
  kout[#kout + 1] = "end"
  kout[#kout + 1] = ""
  kout[#kout + 1] = "return api"
  kout[#kout + 1] = ""
  -- What is still written in Lua: `paw.Untyped`, which any use takes and
  -- whose value is cast (`paw.cursor.track_id() as integer`). Each one is
  -- on the allow-list until its module is ported.
  out[#out + 1] = "   record Untyped"
  out[#out + 1] = "      " .. count("paw.Untyped", "metamethod __call: function(Untyped, ...: any): Untyped")
  out[#out + 1] = "      " .. count("paw.Untyped", "metamethod __index: function(Untyped, any): Untyped")
  out[#out + 1] = "   end"
  local function untyped(node, path, value)
    local taken = { api = path == "paw" or nil }
    for _, key in ipairs(node.order) do taken[key] = true end
    for _, line in ipairs(node.lines) do taken[line:match("^([%w_]+)")] = true end
    local keys = {}
    for k in pairs(type(value) == "table" and value or {}) do
      if type(k) == "string" and k:match("^%a[%w_]*$") and not KEYWORDS[k] and not taken[k] then keys[#keys + 1] = k end
    end
    for _, k in ipairs(keys) do
      -- Another name of a value of a module in Teal has its type.
      local typed = values[value[k]]
      node.lines[#node.lines + 1] = typed and k .. ": " .. typed or count(path .. "." .. k, k .. ": Untyped")
    end
  end
  local function emit(node, depth, path, value)
    local pad = string.rep("   ", depth)
    untyped(node, path, value)
    table.sort(node.order)
    for _, key in ipairs(node.order) do
      out[#out + 1] = pad .. "record " .. key
      emit(node.children[key], depth + 1, path .. "." .. key, value and value[key])
      out[#out + 1] = pad .. "end"
    end
    table.sort(node.lines)
    for _, line in ipairs(node.lines) do out[#out + 1] = pad .. line end
  end
  emit(tree, 1, "paw", paw)
  out[#out + 1] = "end"
  out[#out + 1] = ""
  return table.concat(out, "\n"), table.concat(kout, "\n"), anys
end

--- The `any` that may stay in paw.d.tl, by name: `{ [name] = { count, why } }`.
function M.allowed()
  local out = {}
  for _, line in ipairs(lines_of(M.ANY) or {}) do
    local name, n, why = line:match("^(%S+)%s+(%d+)%s+(.*)$")
    if name and not name:match("^#") then out[name] = { count = tonumber(n), why = why } end
  end
  return out
end

--- The `any` of paw.d.tl that the allow-list does not allow: a list of lines.
function M.any_problems(anys)
  local allowed, out = M.allowed(), {}
  for name, n in pairs(anys) do
    local a = allowed[name]
    if not a then
      out[#out + 1] = "new any: " .. name .. " (" .. n .. "): give it a type in its doc comment"
    elseif n > a.count then
      out[#out + 1] = "more any: " .. name .. " (" .. n .. ", allowed " .. a.count .. ")"
    end
  end
  table.sort(out)
  return out
end

--- The allow-list with each count lowered to what paw.d.tl has. Nothing is
--- added or raised here: only by hand, with the reason. So the count only
--- goes down.
function M.lowered(anys)
  local out = {}
  for _, line in ipairs(lines_of(M.ANY) or {}) do
    local name, n, why = line:match("^(%S+)%s+(%d+)%s+(.*)$")
    if name and not name:match("^#") then
      local now = math.min(tonumber(n), anys[name] or 0)
      if now > 0 then out[#out + 1] = name .. " " .. now .. " " .. why end
    else
      out[#out + 1] = line
    end
  end
  while out[#out] == "" do out[#out] = nil end
  return table.concat(out, "\n") .. "\n"
end

--- What is out of date: a list of the files whose text differs.
function M.stale()
  local out = {}
  if read(M.META) ~= M.meta() then out[#out + 1] = M.META end
  if read(M.PAGE) ~= M.page() then out[#out + 1] = M.PAGE end
  local teal, kernel, anys = M.teal()
  if read(M.TEAL) ~= teal then out[#out + 1] = M.TEAL end
  if read(M.TEAL_API) ~= kernel then out[#out + 1] = M.TEAL_API end
  if read(M.ANY) ~= M.lowered(anys) then out[#out + 1] = M.ANY end
  return out
end

function M.write()
  os.execute("mkdir -p runtime/types/paw")
  local teal, kernel, anys = M.teal()
  for path, text in pairs({ [M.META] = M.meta(), [M.PAGE] = M.page(), [M.TEAL] = teal, [M.TEAL_API] = kernel, [M.ANY] = M.lowered(anys) }) do
    local f = assert(io.open(path, "w"))
    f:write(text)
    f:close()
  end
end

local mode = ...
if mode == "module" then return M end
if mode == "check" then
  local gaps, stale = M.undocumented(), M.stale()
  local _, _, anys = M.teal()
  local loose = M.any_problems(anys)
  for _, gap in ipairs(gaps) do print("undocumented: " .. gap) end
  for _, path in ipairs(stale) do print("out of date: " .. path .. " (run tools/apidoc.lua)") end
  for _, line in ipairs(loose) do print(line) end
  api.quit((#gaps == 0 and #stale == 0 and #loose == 0) and 0 or 1)
else
  M.write()
  print("wrote " .. M.META .. ", " .. M.PAGE .. ", " .. M.TEAL .. ", " .. M.TEAL_API .. " and " .. M.ANY)
  api.quit(0)
end
