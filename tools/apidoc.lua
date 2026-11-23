-- The Lua API's reference, made from the source: the `---` comment over
-- each public function of the `paw` modules, and the `//` comment over
-- each `paw.api` function in crates/paw-core/src/api/. Run from the
-- source tree:
--
--   paw --clean --no-plugins -l tools/apidoc.lua          write both files
--   paw --clean --no-plugins -l tools/apidoc.lua check    say what is out of date or undocumented
--
-- It writes runtime/types/paw.lua, a LuaLS meta file (point `workspace.library`
-- at runtime/types, and editors complete `paw.*` in a configuration or an
-- extension), and docs/reference/api.md, the reference `:help` shows (`:help
-- paw.commands.define`). It also writes the Teal declarations, the kernel's
-- event descriptors and the rows of the runtime's events in
-- docs/reference/events.md. tests/apidoc.lua checks that all are up to date and
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
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    out[#out + 1] = line
  end
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
    if type(value) == "table" and (name == "paw" or name:match("^paw%.")) and name ~= "paw.api" and ours(name) then
      -- A table under two names (paw.frontend is paw.frontend.core) takes
      -- the shorter, whatever the order of `pairs`.
      if not loaded[value] or #name < #loaded[value] then loaded[value] = name end
    end
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
          if type(k) == "string" and type(v) == "table" and not k:match("^_") and k ~= "api" then
            keys[#keys + 1] = k
          end
        end
        table.sort(keys)
        for _, k in ipairs(keys) do
          queue[#queue + 1] = { name .. "." .. k, t[k], depth + 1 }
        end
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
  -- A runtime made by tools/dev-runtime.sh loads the Lua that Teal made, on
  -- the same lines: the doc comments are in the .tl beside it in the checkout.
  sources[path] = sources[path] or lines_of(path) or lines_of((path:gsub("%.lua$", ".tl"))) or {}
  local lines = sources[path]
  local at = info.linedefined
  local first = lines[at] or ""
  if
    not (
      first:match("^%s*local%s+function")
      or first:match("^%s*function%s")
      or first:match('^%s*[%w_.:%[%]"]+%s*=%s*function')
    )
  then
    for i, line in ipairs(lines) do
      if line:match("^%s*[%w_.]*%." .. key .. "%s*=") then
        at = i
        break
      end
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
  for i = 1, info.nparams or 0 do
    out[#out + 1] = debug.getlocal(fn, i)
  end
  if info.isvararg then out[#out + 1] = "..." end
  return out
end

-- The other files that add functions to `paw.api`, each with `api.set("name",
-- lua.create_function(guarded!("name", |lua, args: Types| ...)))` (or
-- tempo_api.rs's `reader!` and `nest_reader!`, whose closures leave out
-- the first argument, `clip`) under its `//` comment.
M.KERNEL_FILES = {
  "crates/paw-core/src/fs_api.rs",
  "crates/paw-core/src/tempo_api.rs",
  "crates/paw-core/src/luadev_api.rs",
  "crates/paw-core/src/scene.rs",
  "crates/paw-core/src/measure/mod.rs",
}

--- Split `text` at the commas that are not inside `()` or `<>`.
local function split_top(text)
  local list, depth, cur = {}, 0, ""
  for ch in text:gmatch(".") do
    if ch == "<" or ch == "(" then
      depth = depth + 1
    elseif ch == ">" or ch == ")" then
      depth = depth - 1
    end
    if ch == "," and depth == 0 then
      list[#list + 1] = cur
      cur = ""
    else
      cur = cur .. ch
    end
  end
  if cur:match("%S") then list[#list + 1] = cur end
  return list
end

--- A kernel function's entry from its argument pattern (`(a, b)`, `a`, `()`)
--- and their Rust types (`(String, f64)`, `String`).
local function kernel_entry(args, types, comment)
  local params = {}
  if args ~= "()" then
    for p in args:gsub("^%(", ""):gsub("%)$", ""):gmatch("[%w_]+") do
      params[#params + 1] = p
    end
  end
  local inner = types:match("^%((.*)%)$") or types
  return { params = params, types = split_top(inner), doc = comment }
end

--- The functions a file of `M.KERNEL_FILES` adds, into `out`.
local function kernel_file(path, out)
  local lines = lines_of(path) or {}
  for i, line in ipairs(lines) do
    local name = line:match('^%s*"([%w_]+)",%s*$') or line:match('^%s*[%w_]*reader!%(lua, api, shared, "([%w_]+)"')
    if name and type(api[name]) == "function" and not out[name] then
      -- The closure's arguments: the last one, `pattern: Types`.
      local text = table.concat(lines, " ", i, math.min(i + 3, #lines))
      local closure = text:match('"' .. name .. '",.-|([^|]*)|')
      local args, types = "()", "()"
      local last = closure and split_top(closure)
      last = last and last[#last]
      if last and last:find(":") then
        args, types = last:match("^%s*(.-)%s*:%s*(.-)%s*$")
      end
      -- A `nest_reader` passes its first argument, the block, before them.
      if line:match("nest_reader!%(") or (lines[i - 4] or ""):match("^%s*nest_reader!%($") then
        local function first(list, item)
          local inner = list:match("^%((.*)%)$") or list
          return "(" .. item .. (inner ~= "" and (", " .. inner) or "") .. ")"
        end
        args, types = first(args, "clip"), first(types, "Id")
      end
      -- The comment over it, past the lines that start the call.
      local n = i - 1
      while
        n > 0
        and (
          lines[n]:match("^%s*api%.set%($")
          or lines[n]:match("^%s*[%w_]*reader!%($")
          or lines[n]:match("^%s*lua,%s*$")
          or lines[n]:match("^%s*api,%s*$")
          or lines[n]:match("^%s*shared,%s*$")
          or lines[n]:match("^%s*let .*;%s*$")
        )
      do
        n = n - 1
      end
      local comment = {}
      while n > 0 and lines[n]:match("^%s*//") and not lines[n]:match("^%s*//!") do
        table.insert(comment, 1, (lines[n]:gsub("^%s*// ?", "")))
        n = n - 1
      end
      out[name] = kernel_entry(args, types, comment)
    end
  end
end

-- The files that define `paw.api` with `define!`: mod.rs and one file for
-- each area, by name.
M.API_DIR = "crates/paw-core/src/api"

local function api_files()
  local out = {}
  for _, entry in ipairs(api.read_dir(M.API_DIR)) do
    if not entry.is_dir and entry.name:match("%.rs$") then out[#out + 1] = M.API_DIR .. "/" .. entry.name end
  end
  return out
end

--- The `paw.api` functions as api/ and `M.KERNEL_FILES` have them:
--- name -> `{ params, types, doc }`.
function M.kernel_functions()
  local out = {}
  for _, path in ipairs(api_files()) do
    local comment = {}
    for _, line in ipairs(lines_of(path) or {}) do
      local name, args, types = line:match("^%s+fn ([%w_]+)%([%w_]+, [%w_]+, (.-) => (.-)%)%s*{")
      if name then
        out[name] = kernel_entry(args, types, comment)
        comment = {}
      elseif line:match("^%s+//") then
        comment[#comment + 1] = (line:gsub("^%s+// ?", ""))
      elseif not line:match("^%s*$") or #comment > 0 then
        comment = {}
      end
    end
  end
  for _, path in ipairs(M.KERNEL_FILES) do
    kernel_file(path, out)
  end
  return out
end

local RUST_TYPES = {
  String = "string",
  f64 = "number",
  f32 = "number",
  i64 = "integer",
  u64 = "integer",
  u32 = "integer",
  i32 = "integer",
  usize = "integer",
  u8 = "integer",
  u16 = "integer",
  Id = "integer",
  bool = "boolean",
  LuaValue = "any",
  Table = "table",
  Function = "function",
  ["()"] = "nil",
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

local function call_name(f) return f.method and f.name:gsub("%.([%w_]+)$", ":%1") or f.name end

--- The LuaLS meta file's text.
function M.meta()
  local out =
    { "---@meta", "-- " .. HEADER, "-- Point LuaLS at this directory (`workspace.library`) to complete `paw.*`.", "" }
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
      for _, line in ipairs(f.doc or {}) do
        if not line:match("^@") then add("--- " .. line) end
      end
      for _, p in ipairs(f.params) do
        if p ~= "..." and not (f.doc and table.concat(f.doc, "\n"):find("@param " .. p .. "%f[^%w_]")) then
          add("---@param " .. p .. " any")
        end
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
      for _, line in ipairs(k.doc) do
        if not line:match("^@") then add("--- " .. line) end
      end
      for i, p in ipairs(k.params) do
        add("---@param " .. p .. " " .. lua_type(k.types[i] or "LuaValue"))
      end
      add("function paw.api." .. name .. "(" .. table.concat(k.params, ", ") .. ") end")
    else
      add("---@type fun(...): any")
      add("paw.api." .. name .. " = nil")
    end
    add("")
  end
  return table.concat(out, "\n")
end

local function signature(f) return call_name(f) .. "(" .. table.concat(f.params or {}, ", ") .. ")" end

--- The `:help` page's Markdown.
function M.page()
  local out = {
    "# Lua API reference",
    "",
    "<!-- " .. HEADER .. " -->",
    "",
    "Each public function of the `paw` modules, module by module, with the",
    "comment from its source. [Scripts](scripting.md) and",
    "[Extensions](extensions.md) tell how the functions work together. The",
    "functions of the kernel (`paw.api`, plain data in and out) are at the end.",
    "`runtime/types/paw.lua` contains the same data for editors (LuaLS).",
    "",
  }
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
              for _, line in ipairs(run) do
                add("  " .. line)
              end
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
    for _, line in ipairs(k and k.doc or {}) do
      if not line:match("^@") then prose[#prose + 1] = line end
    end
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
--   from api/: the Rust type of each parameter, or a `// @param name T`
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
-- `paw.Untyped` in a file of its own: a module of the runtime in Teal is a
-- part of the `paw` global, so it cannot name the global in its types (the
-- global requires the module). It takes the Lua that is not ported yet as
-- `local type Untyped = require("paw.untyped")`.
M.TEAL_UNTYPED = "runtime/types/paw/untyped.d.tl"
M.ANY = "runtime/types/any-allowed.txt"
-- The parts of the modules in Lua that their doc comments type (`@type`),
-- for a module of the runtime in Teal, which cannot name the global:
-- `local type partial = require("paw.partial")`.
M.TEAL_PARTIAL = "runtime/types/paw/partial.d.tl"
-- The options that the runtime defines, each with its type: `paw.opt`.
M.TEAL_OPTS = "runtime/types/paw/opts.d.tl"
-- The files of records whose `any` count as the kernel's do, by the name
-- that a declaration gives the module.
M.RECORDS = { { "types", "runtime/lua/paw/types.tl" }, { "contracts", "runtime/lua/paw/contracts.tl" } }

local RUST_TEAL = {
  String = "string",
  f64 = "number",
  f32 = "number",
  i64 = "integer",
  u64 = "integer",
  u32 = "integer",
  i32 = "integer",
  usize = "integer",
  u8 = "integer",
  u16 = "integer",
  Id = "integer",
  bool = "boolean",
  LuaValue = "any",
  Table = "{any:any}",
  Function = "function(...: any): any...",
  LuaString = "string",
  LuaText = "string",
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
for word in
  ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch(
    "%a+"
  )
do
  KEYWORDS[word] = true
end

--- The Teal types of a kernel function, from api/: a list, of one type,
--- or of each `// @type function(...)` line of its comment, which give the
--- whole type of each form of a function whose result follows from its
--- arguments (`track_get(id)` and `track_get(id, key)`).
local function kernel_sig(k)
  local typed, rets, forms = {}, nil, {}
  for _, line in ipairs(k.doc) do
    local form = line:match("^@type%s+(function.+)$")
    if form then forms[#forms + 1] = form end
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
  if #forms > 0 then return forms end
  local ret = rets == nil and ": any..." or (rets == "nil" and "" or ": " .. rets)
  return { "function(" .. table.concat(params, ", ") .. ")" .. ret }
end

--- The modules of the runtime written in Teal, by name: `{ name, module,
--- file, hidden }`. A module that is no value of `paw` itself is `hidden`:
--- its values are (`paw.Track` and `paw.tracks` of paw.objects).
function M.teal_modules()
  local out, seen = {}, {}
  local function teal_file(module)
    local file = "runtime/lua/" .. module:gsub("%.", "/")
    for _, candidate in ipairs({ file .. ".tl", file .. "/init.tl" }) do
      if read(candidate) then return candidate end
    end
  end
  for _, mod in ipairs(M.modules()) do
    -- Under any name: `paw.option` is the module paw.options.
    local file = mod.module and teal_file(mod.module)
    if file then
      out[#out + 1] = { name = mod.name, module = mod.module, file = file }
      seen[mod.module] = true
    end
  end
  -- A module in Teal that is a value of a module in Lua (`paw.ui.Buf`, the
  -- module paw.buf, of paw/ui.tl) is no field of the record of `paw`, which
  -- types that module as partial.d.tl does: it is left out until its parent
  -- is in Teal too.
  local teal_name = {}
  for _, mod in ipairs(out) do
    teal_name[mod.name] = true
  end
  for i = #out, 1, -1 do
    local parent = out[i].name:match("^(.+)%.[^.]+$")
    if parent and parent ~= "paw" and not teal_name[parent] then table.remove(out, i) end
  end
  -- The values of `paw`, to find the hidden modules that give some.
  local of_paw = {}
  for _, v in pairs(paw) do
    of_paw[v] = true
  end
  local function gives(value)
    for _, v in pairs(value) do
      if type(v) ~= "string" and type(v) ~= "number" and type(v) ~= "boolean" and of_paw[v] then return true end
    end
  end
  for module, value in pairs(package.loaded) do
    local file = type(value) == "table"
      and module:match("^paw%.")
      and not seen[module]
      and gives(value)
      and teal_file(module)
    if file then out[#out + 1] = { name = module, module = module, file = file, hidden = true } end
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
    for name in text:gmatch("\n%s+type ([%w_]+) =") do
      exported[name] = true
    end
    local record = text:match("\nlocal record M\n(.-)\nend\n") or ""
    -- A record of the module's own (`record Track` in `local record M`):
    -- a type, and its value the table of the record (`paw.Track`).
    local records = {}
    for name in ("\n" .. record):gmatch("\n  record ([%w_]+)") do
      exported[name], records[name] = true, true
    end
    local function qualify(t)
      -- The module's own types, `M.Event`, are the alias's.
      t = t:gsub("%f[%w_.]M%.", alias .. ".")
      return (
        t:gsub("%f[%w_.][%a_][%w_]*%f[^%w_]", function(word) return exported[word] and alias .. "." .. word or word end)
      )
    end
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
          -- A function written on one line: its type in the module's record.
          t = t or ("\n" .. record):match("\n  " .. name .. ": (function[^\n]+)")
        elseif records[name] and v == value[name] then
          t = "type " .. name
        else
          -- A field of the module's record, not of a record in it.
          t = ("\n" .. record):match("\n  " .. name .. ": ([^\n]+)")
            or record:match("\n%s+" .. name .. ": ([^\n]+)")
            or record:match("^%s+" .. name .. ": ([^\n]+)")
        end
        if t and not out[v] then out[v] = t:match("^type ") and "type " .. alias .. "." .. name or qualify(t) end
      end
    end
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

--- The forms of a function in Lua (`@type` lines) and its call (`@call`).
local function lua_forms(fn, key)
  local doc = lua_doc(fn, key)
  local forms, call = {}, nil
  for _, line in ipairs(doc or {}) do
    local t = line:match("^@type%s+(function.+)$")
    if t then forms[#forms + 1] = t end
    call = call or line:match("^@call%s+(function.+)$")
  end
  return forms, call
end

--- The types of the values of a module in Lua, by key: each line that sets
--- one (`M.key =`, `paw.key =`, or `key =` in the table that makes the
--- module) under a `--- @type T` comment. A value that is nil until later
--- (`M.current = nil`) is found too.
local function lua_value_types(file)
  sources[file] = sources[file] or lines_of(file) or {}
  local lines, out = sources[file], {}
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

--- A record's name for a module: `paw.track_kinds` is `TrackKinds`.
local function record_name(name)
  return (name:gsub("^paw%.", ""):gsub("[._](%l)", string.upper):gsub("^%l", string.upper))
end

--- Whether a type in the source of a module in Teal can be written in
--- partial.d.tl, which names only `types.X`, `contracts.X` and the type's
--- own generic parameters: not a type of the module's own, nor of another
--- module in Teal (which requires partial.d.tl).
local function partial_safe(t)
  if type(t) ~= "string" then return false end
  local params = {}
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
      if head ~= "types" and head ~= "contracts" then return false end
    elseif word:match("^%u") and not params[word] then
      return false
    end
  end
  return true
end

--- `function<T>(a: A): R` as a metamethod of `self`: `function<T>(self, a: A): R`.
local function with_self(form, self)
  local generics, rest = form:match("^function(<[^>]*>)%((.*)$")
  if not generics then
    generics, rest = "", form:match("^function%((.*)$")
  end
  return "function" .. generics .. "(" .. self .. (rest:match("^%)") and "" or ", ") .. rest
end

--- What the doc comments of the modules in Lua type: `{ records, forms,
--- top }`. `records` is a list of `{ name, table, record, lines, call }`
--- for each module of `paw` in Lua that types something (`record` its name
--- in partial.d.tl, `lines` its fields as `{ key, type }`, `call` the type
--- of a call of the module); `forms[fn]` are the forms of each typed
--- function, by the function, so that another name of it has its type;
--- `top[key]` the types of the typed values and functions of `paw` itself.
local function lua_types(teal_mods, teal_typed)
  local is_teal = {}
  for _, mod in ipairs(teal_mods) do
    is_teal[mod.name] = true
  end
  local out = { records = {}, forms = {}, top = {} }
  local function file_of(module)
    local file = "runtime/lua/" .. module:gsub("%.", "/")
    return read(file .. ".lua") and file .. ".lua" or file .. "/init.lua"
  end
  local function members(t, module)
    local lines, keys, valued = {}, {}, lua_value_types(file_of(module))
    for k in pairs(t) do
      if type(k) == "string" and k:match("^%a[%w_]*$") and not KEYWORDS[k] then keys[#keys + 1] = k end
    end
    for k in pairs(valued) do
      if t[k] == nil and not KEYWORDS[k] then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local call
    for _, k in ipairs(keys) do
      local v = t[k]
      if type(v) == "function" then
        local forms, c = lua_forms(v, k)
        -- A function of a module in Teal under another name
        -- (`paw.ui.role` is `paw.roles.define`): the type in its source.
        if #forms == 0 and partial_safe(teal_typed[v]) then forms = { teal_typed[v] } end
        if #forms > 0 then out.forms[v] = forms end
        for _, form in ipairs(forms) do
          lines[#lines + 1] = { k, form }
        end
        call = call or c
      elseif valued[k] then
        lines[#lines + 1] = { k, valued[k] }
      elseif type(v) == "table" and partial_safe(teal_typed[v]) and not teal_typed[v]:match("^type ") then
        lines[#lines + 1] = { k, teal_typed[v] }
      end
    end
    return lines, call
  end
  for _, mod in ipairs(M.modules()) do
    local depth = select(2, mod.name:gsub("%.", ""))
    if depth == 1 and mod.module and not is_teal[mod.name] and not mod.name:match("^paw%.%u") then
      local lines, call = members(mod.table, mod.module)
      if #lines > 0 then
        out.records[#out.records + 1] =
          { name = mod.name, table = mod.table, record = record_name(mod.name), lines = lines, call = call }
      end
    end
  end
  -- `paw` itself: its functions, and the values that init.lua types.
  for _, line in ipairs((members(paw, "paw"))) do
    out.top[line[1]] = out.top[line[1]] or {}
    table.insert(out.top[line[1]], line[2])
  end
  return out
end

--- The text of runtime/types/paw.d.tl, the text of
--- runtime/types/paw/api.d.tl (the kernel's functions, as the module
--- `paw.api` that a module in Teal requires), their `any` by the name
--- of what has them: `{ [name] = count }`, and the text of
--- runtime/types/paw/untyped.d.tl.
function M.teal()
  local anys = {}
  local function count(name, text)
    local n = 0
    for _ in text:gmatch("%f[%w_]any%f[^%w_]") do
      n = n + 1
    end
    for _ in text:gmatch("%f[%w_]Untyped%f[^%w_]") do
      n = n + 1
    end
    if n > 0 then anys[name] = (anys[name] or 0) + n end
    return text
  end
  local out = {
    "-- " .. HEADER,
    "-- The `paw` global for the files written in Teal (tlconfig.lua's",
    "-- global_env_def): the kernel's functions, and the modules of the runtime",
    "-- that are written in Teal.",
    "",
  }
  local mods = M.teal_modules()
  out[#out + 1] = 'local type Api = require("paw.api")'
  out[#out + 1] = 'local type UntypedLua = require("paw.untyped")'
  out[#out + 1] = 'local type Partial = require("paw.partial")'
  out[#out + 1] = 'local type types = require("paw.types")'
  out[#out + 1] = 'local type contracts = require("paw.contracts")'
  local tree = { children = {}, order = {}, lines = {} }
  local function alias_of(mod) return record_name(mod.name) .. "Module" end
  local values = teal_values(mods, alias_of)
  -- The modules in Lua, and what of them their comments type.
  local lua = lua_types(mods, values)
  local partial_of = {}
  local pout = {
    "-- " .. HEADER,
    "-- The parts of the modules of the runtime in Lua that their doc comments",
    "-- type (`@type`): a module of the runtime in Teal takes the global as",
    "-- `partial.Paw`. What a module does not type is `paw.Untyped`.",
    "",
    'local type types = require("paw.types")',
    'local type contracts = require("paw.contracts")',
    'local type Untyped = require("paw.untyped")',
    "",
    "local record partial",
  }
  local paw_fields = {}
  for _, rec in ipairs(lua.records) do
    partial_of[rec.table] = rec.record
    pout[#pout + 1] = "   record " .. rec.record
    for _, line in ipairs(rec.lines) do
      pout[#pout + 1] = "      " .. count(rec.name .. "." .. line[1], line[1] .. ": " .. line[2])
    end
    if rec.call then pout[#pout + 1] = "      metamethod __call: " .. with_self(rec.call, rec.record) end
    pout[#pout + 1] = "      " .. count(rec.name, "metamethod __index: function(" .. rec.record .. ", string): Untyped")
    pout[#pout + 1] = "   end"
    paw_fields[#paw_fields + 1] = rec.name:match("^paw%.(.*)$") .. ": " .. rec.record
  end
  for k, list in pairs(lua.top) do
    for _, t in ipairs(list) do
      paw_fields[#paw_fields + 1] = k .. ": " .. t
    end
  end
  table.sort(paw_fields)
  pout[#pout + 1] = "   --- The global `paw`, as far as the modules in Lua type it."
  pout[#pout + 1] = "   interface Paw"
  for _, line in ipairs(paw_fields) do
    pout[#pout + 1] = "      " .. line
  end
  pout[#pout + 1] = "   end"
  pout[#pout + 1] = "end"
  pout[#pout + 1] = ""
  pout[#pout + 1] = "return partial"
  pout[#pout + 1] = ""
  local in_teal = {}
  for _, mod in ipairs(mods) do
    in_teal[mod.name] = true
  end
  for _, mod in ipairs(mods) do
    -- A module in Teal that holds others (`paw.harmony` holds
    -- `paw.harmony.read`) declares them in its own record.
    local nested = false
    for prefix in mod.name:gmatch("()%.") do
      if prefix > 4 and in_teal[mod.name:sub(1, prefix - 1)] then nested = true end
    end
    if nested then goto next_module end
    local alias = alias_of(mod)
    out[#out + 1] = "local type " .. alias .. ' = require("' .. mod.module .. '")'
    if not mod.hidden then
      local node = tree
      local parts = {}
      for part in mod.name:gmatch("[^.]+") do
        parts[#parts + 1] = part
      end
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
    ::next_module::
  end
  out[#out + 1] = ""
  out[#out + 1] = "global record paw"
  out[#out + 1] = "   api: Api"
  local kout = {
    "-- " .. HEADER,
    "-- The functions of the kernel, written in Rust (crates/paw-core/src/api/):",
    '-- `local api = require("paw.api")` in a module written in Teal.',
    "",
  }
  if read("runtime/lua/paw/types.tl") then
    kout[#kout + 1] = 'local type types = require("paw.types")'
    kout[#kout + 1] = 'local type kernel_events = require("paw.events.kernel")'
    kout[#kout + 1] = ""
  end
  kout[#kout + 1] = "local record api"
  kout[#kout + 1] = "   version: string"
  -- The kernel's other plain values (`limit_async`), by their Lua type.
  local plain = {}
  for name, v in pairs(api) do
    if name ~= "version" and (type(v) == "boolean" or type(v) == "string" or type(v) == "number") then
      plain[#plain + 1] = "   " .. name .. ": " .. (type(v) == "number" and "number" or type(v))
    end
  end
  table.sort(plain)
  for _, line in ipairs(plain) do
    kout[#kout + 1] = line
  end
  local kernel = M.kernel_functions()
  local names = {}
  for name, fn in pairs(api) do
    if type(fn) == "function" then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local sigs = kernel[name] and kernel_sig(kernel[name]) or { "function(...: any): any..." }
    for _, sig in ipairs(sigs) do
      kout[#kout + 1] = "   " .. count("paw.api." .. name, name .. ": " .. sig)
    end
  end
  -- The records of the data that crosses `paw.api` count too: an `any`
  -- moved from a signature into a record is still one.
  local stack = {}
  for _, records in ipairs(M.RECORDS) do
    for _, line in ipairs(lines_of(records[2]) or {}) do
      local code = line:gsub("%-%-.*$", "")
      local record = code:match("^%s*record%s+([%w_]+)")
        or code:match("^%s*local%s+record%s+([%w_]+)")
        or code:match("^%s*interface%s+([%w_]+)")
      if record then
        stack[#stack + 1] = record
      elseif code:match("^%s*enum%s") then
        stack[#stack + 1] = false
      elseif code:match("^%s*end%s*$") then
        stack[#stack] = nil
      else
        local field = code:match("^%s*type%s+([%w_]+)%s*=") or code:match('^%s*%[?"?([%w_]+)"?%]?%s*:')
        if field then
          local path = {}
          for i = 2, #stack do
            path[#path + 1] = stack[i]
          end
          path[#path + 1] = field
          count(records[1] .. "." .. table.concat(path, "."), code)
        end
      end
    end
  end
  kout[#kout + 1] = "end"
  kout[#kout + 1] = ""
  kout[#kout + 1] = "return api"
  kout[#kout + 1] = ""
  -- What is still written in Lua: `paw.Untyped`, which any use takes and
  -- whose value is cast (`paw.cursor.track_id() as integer`). Each one is
  -- on the allow-list until its module is ported.
  out[#out + 1] = "   type Untyped = UntypedLua"
  local uout = {
    "-- " .. HEADER,
    "-- What is still written in Lua: `paw.Untyped`. A module of the runtime in",
    '-- Teal names it `local type Untyped = require("paw.untyped")`, as it cannot',
    "-- name the `paw` global that requires it.",
    "",
    "local record Untyped",
    "   " .. count("paw.Untyped", "metamethod __call: function(Untyped, ...: any): Untyped"),
    "   " .. count("paw.Untyped", "metamethod __index: function(Untyped, any): Untyped"),
    "end",
    "",
    "return Untyped",
    "",
  }
  -- Another name of a kernel function (`paw.wait`) has its type, where the
  -- type has no `any`.
  local kernel_forms = {}
  for name, fn in pairs(api) do
    if type(fn) == "function" and kernel[name] then
      local forms = kernel_sig(kernel[name])
      if not table.concat(forms, " "):find("%f[%w_]any%f[^%w_]") then kernel_forms[fn] = forms end
    end
  end
  local function untyped(node, path, value)
    local taken = { api = path == "paw" or nil }
    for _, key in ipairs(node.order) do
      taken[key] = true
    end
    for _, line in ipairs(node.lines) do
      taken[line:match("^type ([%w_]+) =") or line:match("^([%w_]+)")] = true
    end
    local keys = {}
    for k in pairs(type(value) == "table" and value or {}) do
      if type(k) == "string" and k:match("^%a[%w_]*$") and not KEYWORDS[k] and not taken[k] then keys[#keys + 1] = k end
    end
    for _, k in ipairs(keys) do
      local v = value[k]
      -- Another name of a value of a module in Teal has its type.
      local typed = values[v]
      -- What the comments of a module in Lua type: a function by its forms,
      -- a module by its record of partial.d.tl, a value of `paw` by its type.
      local forms = lua.forms[v] or kernel_forms[v] or (path == "paw" and lua.top[k])
      if typed and typed:match("^type ") then
        -- A record of a module in Teal: its type, and its table as a value.
        node.lines[#node.lines + 1] = "type " .. k .. " = " .. typed:sub(6)
      elseif typed then
        node.lines[#node.lines + 1] = k .. ": " .. typed
      elseif forms then
        for _, form in ipairs(forms) do
          node.lines[#node.lines + 1] = count(path .. "." .. k, k .. ": " .. form)
        end
      elseif partial_of[v] then
        node.lines[#node.lines + 1] = k .. ": Partial." .. partial_of[v]
      else
        node.lines[#node.lines + 1] = count(path .. "." .. k, k .. ": Untyped")
      end
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
    for _, line in ipairs(node.lines) do
      out[#out + 1] = pad .. line
    end
  end
  emit(tree, 1, "paw", paw)
  out[#out + 1] = "end"
  out[#out + 1] = ""
  return table.concat(out, "\n"),
    table.concat(kout, "\n"),
    anys,
    table.concat(uout, "\n"),
    table.concat(pout, "\n"),
    M.opts()
end

-- Options ------------------------------------------------------------------------------

--- The Teal type of an option: of its spec's `type` (a type or a list of
--- them), or of its default; `integer` for a whole number.
local function option_type(default, spec)
  local list = spec and spec.type or type(default)
  if type(list) == "string" then list = { list } end
  local out = {}
  for _, t in ipairs(list) do
    if t == "number" then
      out[#out + 1] = spec and spec.integer and "integer" or "number"
    elseif t == "table" then
      out[#out + 1] = "{string | number}"
    else
      out[#out + 1] = t
    end
  end
  return table.concat(out, " | ")
end

--- The text of runtime/types/paw/opts.d.tl: `paw.opt`, each option that
--- the runtime defines by its type, and any other by its name.
function M.opts()
  local out = {
    "-- " .. HEADER,
    "-- `paw.opt`: each option that the runtime defines (`paw.option.list`), by",
    "-- the type of its default and its spec, and any other option by its name.",
    "",
    "local record Opts",
    "   --- What an option holds: text, a number, true or false, or a list.",
    "   type Value = string | number | boolean | {string | number}",
    "",
  }
  for _, info in ipairs(paw.option.list()) do
    out[#out + 1] = "   " .. info.name .. ": " .. option_type(info.default, paw.option.spec(info.name))
  end
  out[#out + 1] = "   metamethod __index: function(Opts, string): Value"
  out[#out + 1] = "   metamethod __newindex: function(Opts, string, Value)"
  out[#out + 1] = "end"
  out[#out + 1] = ""
  out[#out + 1] = "return Opts"
  out[#out + 1] = ""
  return table.concat(out, "\n")
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
  while out[#out] == "" do
    out[#out] = nil
  end
  return table.concat(out, "\n") .. "\n"
end

-- Records from Rust ---------------------------------------------------------------------
--
-- The data the kernel sends as it is in Rust: the events of the kernel
-- (crates/paw-core/src/events.rs) and the properties of the roles that the
-- window paints (crates/paw-scene/src/props.rs). Each `pub struct` of such a
-- file becomes a Teal record, with its `///` comment; a field that holds a
-- `Value` names its record in a `/// @type T` line.

M.EVENTS_RS = "crates/paw-core/src/events.rs"
M.EVENTS_TL = "runtime/lua/paw/events/kernel.tl"
M.PROPS_RS = "crates/paw-scene/src/props.rs"
M.PROPS_TL = "runtime/types/paw/role_props.d.tl"

local RUST_FIELD = {
  String = "string",
  PathBuf = "string",
  ["&'a str"] = "string",
  f64 = "number",
  f32 = "number",
  i64 = "integer",
  u64 = "integer",
  u32 = "integer",
  i32 = "integer",
  usize = "integer",
  u8 = "integer",
  Id = "integer",
  bool = "boolean",
}

--- The Teal type of a field's Rust type: nil for one that has none.
local function field_teal(rust, structs)
  rust = rust:gsub("^%s+", ""):gsub("%s+$", "")
  local inner = rust:match("^Option<(.*)>$")
  if inner then return field_teal(inner, structs) end
  local vec = rust:match("^Vec<(.*)>$") or rust:match("^&'a %[(.*)%]$")
  if vec then
    local t = field_teal(vec, structs)
    return t and "{" .. t .. "}"
  end
  -- A tuple is a list of its parts in Lua: a tuple of Teal too.
  local tuple = rust:match("^%((.*)%)$")
  if tuple then
    local parts = {}
    for i, p in ipairs(split_top(tuple)) do
      parts[i] = field_teal(p, structs)
      if not parts[i] then return nil end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  local name = rust:match("^([%w_]+)") or rust
  if structs[name] then return name end
  return RUST_FIELD[rust]
end

--- The `pub struct`s of a Rust file, in order: `{ name, doc, fields }`, each
--- field `{ name, rust, doc, type }`; and the variants of its `pub enum`s:
--- `{ name, rust, doc, type, serde }`, by the enum's name.
function M.rust_records(path)
  local structs, enums, order = {}, {}, {}
  local doc, serde, derive = {}, nil, ""
  local current, enum
  for _, line in ipairs(lines_of(path) or {}) do
    local comment = line:match("^%s*///%s?(.*)$")
    if comment then
      doc[#doc + 1] = comment
    elseif line:match("^%s*#%[") then
      serde = line:match('rename%s*=%s*"([^"]+)"') or serde
      derive = line:match("^%s*#%[derive%((.*)%)%]") or derive
    else
      local name, rest = line:match("^pub struct ([%w_]+)[^{]*{(.*)$")
      local ename = line:match("^pub enum ([%w_]+)")
      if name then
        -- Only what crosses to Lua: a struct that serde writes or reads.
        current = { name = name, doc = doc, fields = {} }
        if derive:match("Serialize") or derive:match("Deserialize") then
          structs[name] = current
          order[#order + 1] = current
        end
        if rest:match("}") then current = nil end
      elseif ename then
        enum = {}
        enums[ename] = enum
      elseif line:match("^}") then
        current, enum = nil, nil
      elseif current then
        local fname, rust = line:match("^%s+pub ([%w_]+): (.-),?%s*$")
        if fname then current.fields[#current.fields + 1] = { name = serde or fname, rust = rust, doc = doc } end
      elseif enum then
        local vname, rust = line:match("^%s+([%w_]+)%((.-)%),%s*$")
        if vname then enum[#enum + 1] = { name = vname, rust = rust, doc = doc, serde = serde } end
      end
      doc, serde = {}, nil
      if not line:match("^%s*$") then derive = "" end
    end
  end
  -- What a `/// @type T` line names, else the type the Rust type has.
  local function typed(item)
    local prose = {}
    for _, line in ipairs(item.doc) do
      local t = line:match("^@type%s+(.+)$")
      if t then
        item.type = t
      else
        prose[#prose + 1] = line
      end
    end
    item.doc = prose
    item.type = item.type or field_teal(item.rust, structs)
  end
  for _, s in ipairs(order) do
    for _, f in ipairs(s.fields) do
      typed(f)
    end
  end
  for _, list in pairs(enums) do
    for _, v in ipairs(list) do
      typed(v)
    end
  end
  return order, enums
end

--- The fields of a record, at `pad`, into `out`; an error for a field
--- whose Rust type has no Teal type.
local function record_fields(out, record, pad, path)
  for _, f in ipairs(record.fields) do
    for _, line in ipairs(f.doc) do
      out[#out + 1] = pad .. "--- " .. line
    end
    if not f.type then
      error(
        path
          .. ": "
          .. record.name
          .. "."
          .. f.name
          .. " ("
          .. f.rust
          .. ") has no Teal type: give it a `/// @type` line"
      )
    end
    out[#out + 1] = pad .. (KEYWORDS[f.name] and '["' .. f.name .. '"]' or f.name) .. ": " .. f.type
  end
end

--- The text of runtime/lua/paw/events/kernel.tl: the payload of each event
--- of the kernel as a record, and a descriptor for each event.
function M.kernel_events()
  local structs, enums = M.rust_records(M.EVENTS_RS)
  local events = enums.KernelEvent or {}
  local out = {
    "-- " .. HEADER,
    "-- Made from " .. M.EVENTS_RS .. ": the events of the kernel, each a descriptor",
    "-- with the type of its payload, for `paw.on` and `paw.emit` in Teal:",
    "--",
    '--   local kernel = require("paw.events.kernel")',
    "--   paw.on(kernel.project_saved, function(p: kernel.Saved) print(p.path) end)",
    "",
    -- A value: each descriptor declares its name (`paw.events.event`).
    'local events = require("paw.events")',
    'local type types = require("paw.types")',
    "",
    "local record kernel",
    "   --- What every payload of the kernel may have: `restored` is true for a",
    "   --- change that undo or redo put back, which a handler that answers",
    "   --- edits with edits leaves alone.",
    "   interface Payload",
    "      restored: boolean",
    "   end",
  }
  for _, s in ipairs(structs) do
    out[#out + 1] = ""
    for _, line in ipairs(s.doc) do
      out[#out + 1] = "   --- " .. line
    end
    out[#out + 1] = "   record " .. s.name .. " is Payload"
    record_fields(out, s, "      ", M.EVENTS_RS)
    out[#out + 1] = "   end"
  end
  out[#out + 1] = ""
  out[#out + 1] = "   --- An event as `paw.api.events_take` gives it."
  out[#out + 1] = "   record KernelEvent"
  out[#out + 1] = "      name: string"
  out[#out + 1] = "      payload: Payload"
  out[#out + 1] = "   end"
  out[#out + 1] = ""
  local values = {}
  for _, v in ipairs(events) do
    if not v.type then error(M.EVENTS_RS .. ": " .. v.name .. " (" .. v.rust .. ") has no Teal type") end
    local key = v.serde:gsub("%.", "_")
    for _, line in ipairs(v.doc) do
      out[#out + 1] = "   --- " .. line
    end
    out[#out + 1] = "   " .. key .. ": events.Event<" .. v.type .. ">"
    values[#values + 1] = "kernel." .. key .. ' = events.event("' .. v.serde .. '")'
  end
  out[#out + 1] = "end"
  out[#out + 1] = ""
  for _, line in ipairs(values) do
    out[#out + 1] = line
  end
  out[#out + 1] = ""
  out[#out + 1] = "return kernel"
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

--- The text of runtime/types/paw/role_props.d.tl: the props of each role
--- that the window paints, as it reads them.
function M.role_props()
  local structs = M.rust_records(M.PROPS_RS)
  local out = {
    "-- " .. HEADER,
    "-- Made from " .. M.PROPS_RS .. ": the props of each role that the",
    "-- window paints, as it reads them (`paw.api.scene_open`'s `props`).",
    "",
    "local record role_props",
    "   --- The props of a role: each record of this file is one.",
    "   interface Props",
    "   end",
  }
  for _, s in ipairs(structs) do
    out[#out + 1] = ""
    for _, line in ipairs(s.doc) do
      out[#out + 1] = "   --- " .. line
    end
    out[#out + 1] = "   record " .. s.name .. " is Props"
    record_fields(out, s, "      ", M.PROPS_RS)
    out[#out + 1] = "   end"
  end
  out[#out + 1] = "end"
  out[#out + 1] = ""
  out[#out + 1] = "return role_props"
  out[#out + 1] = ""
  return table.concat(out, "\n")
end

-- The events of the runtime -------------------------------------------------------------
--
-- The module that sends an event exports its descriptor (paw/events.tl): a
-- field of the module's record, `changed: events.Event<Changed>`, under a
-- comment `--- The event `option.changed`: when it comes.`. The rows
-- between the two marks of docs/reference/events.md come from these
-- fields and from the fields of their payload records.

M.EVENTS_PAGE = "docs/reference/events.md"
local EVENTS_BEGIN = "<!-- The rows below come from tools/apidoc.lua: change the descriptors, not the rows. -->"
local EVENTS_END = "<!-- The end of the rows from tools/apidoc.lua. -->"

-- The file of a record type as a module names it: its own, types.tl or
-- the kernel's events. Nil for the empty payload of paw/events.tl.
local function record_file(type_name, path)
  local qualifier, name = type_name:match("^([%w_]+)%.([%w_]+)$")
  if not qualifier then return path, type_name end
  if qualifier == "types" then return "runtime/lua/paw/types.tl", name end
  if qualifier == "kernel" then return M.EVENTS_TL, name end
  if qualifier == "events" and name == "Payload" then return nil end
  error(path .. ": the payload type " .. type_name .. " is in no file that tools/apidoc.lua reads")
end

--- The names of the fields of the record `name` in the file `path`, in
--- order: the fields one level in from the line `record name`.
local function record_field_names(path, name)
  local lines = lines_of(path) or {}
  for i, line in ipairs(lines) do
    local indent = line:match("^(%s*)local record " .. name .. "%f[^%w_]")
      or line:match("^(%s*)record " .. name .. "%f[^%w_]")
    if indent then
      local fields, inner = {}, nil
      for j = i + 1, #lines do
        local l = lines[j]
        if l:match("^" .. indent .. "end%s*$") then break end
        local pad = l:match("^(%s+)%S")
        inner = inner or (pad and not l:match("^%s*%-%-") and pad)
        local field = pad == inner and l:match("^%s+([%w_]+)%??:%s")
        if field then fields[#fields + 1] = field end
      end
      return fields
    end
  end
  error(path .. ": no record " .. name .. " for the payload of an event")
end

--- The descriptors that the runtime's modules export, sorted by the name
--- of the event: `{ event, payload, when, teal }`. A descriptor whose
--- comment does not say which event it is and when it comes is an error.
function M.runtime_events()
  -- The shortest name from `paw` of each module, for the column "In Teal".
  local reached = {}
  for _, m in ipairs(M.modules()) do
    if m.module and not reached[m.module] then reached[m.module] = m.name end
  end
  local rows = {}
  for module, value in pairs(package.loaded) do
    local base = type(value) == "table" and module:match("^paw%.") and "runtime/lua/" .. module:gsub("%.", "/")
    local path = base and ((read(base .. ".tl") and base .. ".tl") or (read(base .. "/init.tl") and base .. "/init.tl"))
    local lines = path and lines_of(path) or {}
    for i, line in ipairs(lines) do
      -- paw/events.tl names its own type `Event`, the others `events.Event`.
      local key, payload = line:match("^  ([%w_]+): events%.Event<([%w_.]+)>%s*$")
      if not key and path == "runtime/lua/paw/events.tl" then
        key, payload = line:match("^  ([%w_]+): Event<([%w_.]+)>%s*$")
      end
      if key then
        local doc = {}
        local n = i - 1
        while lines[n] and lines[n]:match("^%s*%-%-%-") do
          table.insert(doc, 1, (lines[n]:gsub("^%s*%-%-%- ?", "")))
          n = n - 1
        end
        local event, when = table.concat(doc, " "):match("^The event `([^`]+)`: (.-)%.?$")
        local descriptor = value[key]
        if not event then
          error(path .. ":" .. i .. ": say `--- The event `name`: when it comes.` over the descriptor " .. key)
        end
        if type(descriptor) ~= "table" or descriptor.name ~= event then
          error(path .. ":" .. i .. ": the descriptor " .. key .. " is not the event `" .. event .. "`")
        end
        local file, record = record_file(payload, path)
        local fields = file and record_field_names(file, record) or {}
        rows[#rows + 1] = {
          event = event,
          payload = #fields == 0 and "{}" or "{ " .. table.concat(fields, ", ") .. " }",
          when = when,
          teal = (reached[module] or 'require("' .. module .. '")') .. "." .. key,
        }
      end
    end
  end
  table.sort(rows, function(a, b) return a.event < b.event end)
  return rows
end

--- The text of docs/reference/events.md, with the rows of the runtime's
--- descriptors between its marks.
function M.events_page()
  local text = read(M.EVENTS_PAGE) or ""
  local head, tail =
    text:match("^(.-" .. EVENTS_BEGIN:gsub("%p", "%%%0") .. "\n).-(" .. EVENTS_END:gsub("%p", "%%%0") .. ".*)$")
  if not head then error(M.EVENTS_PAGE .. ": the marks of the generated rows are missing") end
  local out = { head, "\n", "| Event | Payload | When | In Teal |\n", "| --- | --- | --- | --- |\n" }
  for _, row in ipairs(M.runtime_events()) do
    out[#out + 1] = string.format("| `%s` | `%s` | %s | `%s` |\n", row.event, row.payload, row.when, row.teal)
  end
  out[#out + 1] = "\n"
  out[#out + 1] = tail
  return table.concat(out)
end

--- What is out of date: a list of the files whose text differs.
function M.stale()
  local out = {}
  if read(M.META) ~= M.meta() then out[#out + 1] = M.META end
  if read(M.PAGE) ~= M.page() then out[#out + 1] = M.PAGE end
  local teal, kernel, anys, untyped, partial, opts = M.teal()
  if read(M.TEAL) ~= teal then out[#out + 1] = M.TEAL end
  if read(M.TEAL_API) ~= kernel then out[#out + 1] = M.TEAL_API end
  if read(M.TEAL_UNTYPED) ~= untyped then out[#out + 1] = M.TEAL_UNTYPED end
  if read(M.TEAL_PARTIAL) ~= partial then out[#out + 1] = M.TEAL_PARTIAL end
  if read(M.TEAL_OPTS) ~= opts then out[#out + 1] = M.TEAL_OPTS end
  if read(M.ANY) ~= M.lowered(anys) then out[#out + 1] = M.ANY end
  if read(M.EVENTS_TL) ~= M.kernel_events() then out[#out + 1] = M.EVENTS_TL end
  if read(M.PROPS_TL) ~= M.role_props() then out[#out + 1] = M.PROPS_TL end
  if read(M.EVENTS_PAGE) ~= M.events_page() then out[#out + 1] = M.EVENTS_PAGE end
  return out
end

function M.write()
  os.execute("mkdir -p runtime/types/paw runtime/lua/paw/events")
  local teal, kernel, anys, untyped, partial, opts = M.teal()
  for path, text in pairs({
    [M.META] = M.meta(),
    [M.PAGE] = M.page(),
    [M.TEAL] = teal,
    [M.TEAL_API] = kernel,
    [M.TEAL_UNTYPED] = untyped,
    [M.TEAL_PARTIAL] = partial,
    [M.TEAL_OPTS] = opts,
    [M.ANY] = M.lowered(anys),
    [M.EVENTS_TL] = M.kernel_events(),
    [M.PROPS_TL] = M.role_props(),
    [M.EVENTS_PAGE] = M.events_page(),
  }) do
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
  for _, gap in ipairs(gaps) do
    print("undocumented: " .. gap)
  end
  for _, path in ipairs(stale) do
    print("out of date: " .. path .. " (run tools/apidoc.lua)")
  end
  for _, line in ipairs(loose) do
    print(line)
  end
  api.quit((#gaps == 0 and #stale == 0 and #loose == 0) and 0 or 1)
else
  M.write()
  print("wrote " .. table.concat({
    M.META,
    M.PAGE,
    M.TEAL,
    M.TEAL_API,
    M.TEAL_UNTYPED,
    M.TEAL_PARTIAL,
    M.TEAL_OPTS,
    M.EVENTS_TL,
    M.PROPS_TL,
    M.EVENTS_PAGE,
    M.ANY,
  }, ", "))
  api.quit(0)
end
