-- Languages that compile to Lua. A configuration, an extension or a module
-- on the `require` path may be written in one of them: paw compiles the file
-- when it loads it, and keeps the Lua it made in its cache, by the file's
-- content, so the next start does not compile it again.
--
--   paw.lang.add("fnl", { name = "fennel", command = "fennel --compile %s" })
--   require("mine.util")        -- finds lua/mine/util.fnl as well as util.lua
--
-- Teal (`.tl`, https://teal-language.org) is one entry of the registry, the
-- one that comes with paw: its compiler (runtime/lua/tl.lua) is in the
-- program. Loading does not check the types (as a TypeScript transpiler
-- does not): `paw.lang.check` does, and the test suite runs it over every
-- `.tl` file of the source tree.
local api = paw.api
local M = {}

--- The languages by the extension of their files, without the dot: each
--- `{ name, version, compile, command }`. `paw.lang.add` adds one.
M.compilers = {}

--- Add a language whose files end in `.<ext>`. `spec.compile(source, path)`
--- returns the Lua for the text of a file, or nil and an error. Or
--- `spec.command` is a shell command that writes the Lua to its output,
--- with `%s` for the file. `spec.name` names the language in errors, and
--- `spec.version` goes into the cache's key: change it when the compiler
--- changes what it makes.
---   paw.lang.add("fnl", { name = "fennel", command = "fennel --compile %s", version = "1.5" })
function M.add(ext, spec)
  assert(type(ext) == "string" and ext:match("^[%w_]+$") and ext ~= "lua", "paw.lang.add: an extension such as \"tl\", without the dot")
  assert(type(spec) == "table" and (spec.compile or spec.command), "paw.lang.add: give compile or command")
  M.compilers[ext] = spec
end

--- The extension of `path` when a registered language has it, else nil.
function M.of(path)
  local ext = tostring(path):match("%.([%w_]+)$")
  return ext and M.compilers[ext] and ext or nil
end

--- The extensions a source file may have: "lua" first, then each
--- registered one, sorted.
function M.extensions()
  local out = {}
  for ext in pairs(M.compilers) do out[#out + 1] = ext end
  table.sort(out)
  table.insert(out, 1, "lua")
  return out
end

local function read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

--- The directory the compiled Lua is kept in: `$XDG_CACHE_HOME/paw/lang`.
function M.cache_dir()
  local base = os.getenv("XDG_CACHE_HOME")
  if not base or base == "" then base = (os.getenv("HOME") or os.getenv("TMPDIR") or "/tmp") .. "/.cache" end
  return base .. "/paw/lang"
end

-- The cache's key for a text: two CRC-32s (of the text and of the text
-- backwards) and the length. A file is found by what it contains, so a copy
-- or a file moved back and forth compiles once.
local function key(text)
  return string.format("%08x%08x-%x", api.crc32(text), api.crc32(text:reverse()), #text)
end

local made = {}   -- cache directories made in this run

--- Statistics of this run: files compiled and files taken from the cache.
M.stats = { compiled = 0, cached = 0 }

--- The Lua of a file in a registered language, compiled or from the cache.
--- `source` is the file's text when it is read already. Returns the Lua,
--- or nil and an error that names the file.
function M.compile(path, source)
  local ext = M.of(path)
  if not ext then return nil, path .. ": no language for this kind of file" end
  local spec = M.compilers[ext]
  source = source or read(path)
  if not source then return nil, "cannot open " .. path end
  local dir = M.cache_dir() .. "/" .. ext
  local tag = (spec.name or ext) .. " " .. tostring(spec.version or spec.command or "")
  local cached = dir .. "/" .. key(tag .. "\0" .. source) .. ".lua"
  local code = read(cached)
  if code then
    M.stats.cached = M.stats.cached + 1
    return code
  end
  local err
  if spec.compile then
    local ok, got, why = pcall(spec.compile, source, path)
    if ok then code, err = got, why else err = got end
  else
    local pipe = io.popen(spec.command:gsub("%%s", (shell_quote(path):gsub("%%", "%%%%"))) .. " 2>&1")
    local out = pipe and pipe:read("*a") or ""
    local ok = pipe and pipe:close()
    if ok then code = out else err = out end
  end
  if not code then return nil, path .. ": " .. tostring(err or "does not compile") end
  M.stats.compiled = M.stats.compiled + 1
  if not made[dir] then
    os.execute("mkdir -p " .. shell_quote(dir))
    made[dir] = true
  end
  -- Written beside, then moved: two programs that start together never
  -- read half a file.
  local tmp = cached .. "." .. api.env().pid
  local file = io.open(tmp, "wb")
  if file then
    file:write(code)
    file:close()
    os.rename(tmp, cached)
  end
  return code
end

--- The first file that is there of `base` with each extension of
--- `paw.lang.extensions()`: `find("init")` gives init.lua, or init.tl when
--- there is no init.lua. Nil when there is none.
function M.find(base)
  for _, ext in ipairs(M.extensions()) do
    local f = io.open(base .. "." .. ext, "r")
    if f then
      f:close()
      return base .. "." .. ext
    end
  end
end

--- Load a file of Lua or of a registered language as a function, as
--- `loadfile` does. Its errors and `debug.getinfo` name the file itself, so
--- an extension written in another language owns what it registers.
function M.loadfile(path)
  if not M.of(path) then return loadfile(path) end
  local code, err = M.compile(path)
  if not code then return nil, err end
  return loadstring(code, "@" .. path)
end

--- The file of module `name` in a registered language along `path` (by
--- default `package.path`): each `?.lua` template with the language's
--- extension. Nil and the files it tried when there is none.
function M.searchpath(name, path)
  local tried, slashed = {}, name:gsub("%.", "/")
  for template in (path or package.path):gmatch("[^;]+") do
    if template:match("%.lua$") then
      for ext in pairs(M.compilers) do
        local file = template:gsub("%.lua$", "." .. ext):gsub("%?", slashed)
        local f = io.open(file, "r")
        if f then
          f:close()
          return file
        end
        tried[#tried + 1] = "\n\tno file '" .. file .. "'"
      end
    end
  end
  return nil, table.concat(tried)
end

-- `require`: after Lua's own searchers and the modules built into the
-- program, so finding those costs nothing more.
local function searcher(name)
  local file, tried = M.searchpath(name)
  if not file then return tried end
  local chunk, err = M.loadfile(file)
  if not chunk then error(err, 0) end
  return chunk
end
table.insert(package.loaders, searcher)

-- Teal -----------------------------------------------------------------------------

local tl   -- the compiler, loaded the first time a `.tl` file is not in the cache

local function teal()
  tl = tl or require("tl")
  return tl
end

-- Lua 5.1 as LuaJIT runs it, without the compatibility code for 5.3.
local GEN = { gen_target = "5.1", gen_compat = "off" }

M.add("tl", {
  name = "teal",
  -- The version of runtime/lua/tl.lua; and of what this file asks of it.
  version = "0.24.8/1",
  compile = function(source, path)
    local compiler = teal()
    local ast, errors = compiler.parse(source, path)
    if #errors > 0 then
      local e = errors[1]
      return nil, string.format("%d:%d: %s", e.y, e.x, e.msg)
    end
    return compiler.generate(ast, GEN.gen_target)
  end,
})

--- The Teal configuration of the source tree (tlconfig.lua): the
--- directories with declarations and modules (`include_dir`), and the file
--- that declares the globals (`global_env_def`).
function M.tlconfig(root)
  local chunk = loadfile((root or ".") .. "/tlconfig.lua")
  local ok, config = pcall(chunk or function() return {} end)
  return ok and type(config) == "table" and config or {}
end

--- Check the types of `.tl` files, as `tl check` does with the source
--- tree's tlconfig.lua. `opts.include` adds directories to look for
--- modules in. Returns a list of `{ file, line, col, msg, kind }`, kind
--- "error" or "warning", sorted by file and line: empty when all is well.
function M.check(files, opts)
  opts = opts or {}
  local compiler = teal()
  local config = M.tlconfig(opts.root)
  local dirs = {}
  for _, dir in ipairs(config.include_dir or {}) do dirs[#dirs + 1] = dir end
  for _, dir in ipairs(opts.include or {}) do dirs[#dirs + 1] = dir end
  local path = {}
  for _, dir in ipairs(dirs) do
    path[#path + 1] = dir .. "/?.lua"
    path[#path + 1] = dir .. "/?/init.lua"
  end
  local saved = compiler.path
  compiler.path = table.concat(path, ";")
  local out, seen = {}, {}
  local ok, err = pcall(function()
    local env = assert(compiler.new_env({
      defaults = { feat_lax = "off", feat_arity = "on", gen_target = GEN.gen_target, gen_compat = GEN.gen_compat },
      predefined_modules = config.global_env_def and { config.global_env_def } or nil,
    }))
    for _, file in ipairs(files) do
      local result, why = compiler.check_file(file, env)
      if not result then
        out[#out + 1] = { file = file, line = 1, col = 1, msg = tostring(why), kind = "error" }
      else
        for _, list in ipairs({ { result.syntax_errors, "error" }, { result.type_errors, "error" }, { result.warnings, "warning" } }) do
          for _, e in ipairs(list[1] or {}) do
            -- A module two files require is checked once, and said once.
            local item = { file = e.filename or file, line = e.y, col = e.x, msg = e.msg, kind = list[2] }
            local id = item.file .. ":" .. item.line .. ":" .. item.col .. ":" .. item.msg
            if not seen[id] then
              seen[id] = true
              out[#out + 1] = item
            end
          end
        end
      end
    end
  end)
  compiler.path = saved
  if not ok then out[#out + 1] = { file = files[1] or "?", line = 1, col = 1, msg = tostring(err), kind = "error" } end
  table.sort(out, function(a, b)
    if a.file ~= b.file then return a.file < b.file end
    return a.line < b.line
  end)
  return out
end

return M
