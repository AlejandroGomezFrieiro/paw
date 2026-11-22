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
-- program. Loading checks the types, with the declarations built into the
-- program, as `tl gen` does: in some places the Lua depends on them
-- (`x is F`, where `F` names a function type). A file with type errors
-- loads all the same (as TypeScript's compiler gives its output on an
-- error): paw says the errors once, when it compiles the file, and
-- `:checkhealth teal` lists them.
--
-- This module is written in Teal too: the build compiles it to Lua, so it
-- does not need itself to load.
local api = require("paw.api")
local limit = require("paw.limit")

--- A language: `compile(source, path)` gives the Lua of a file's text, or
--- nil and an error; and a list of problems that do not stop the file
--- (type errors) as a third value. Or `command` is a shell command that
--- writes the Lua, with `%s` for the file. `name` names it in errors, and
--- `version` goes into the cache's key.
local record Spec
  name: string
  version: string
  compile: function(string, string): string, string, {string}
  command: string
end

--- Files compiled in this run, and files taken from the cache.
local record Stats
  compiled: integer
  cached: integer
end

--- What `check` found: a place in a file, the message, and its kind,
--- "error" or "warning".
local record Problem
  file: string
  line: integer
  col: integer
  msg: string
  kind: string
end

--- What `check` takes besides the files.
local record CheckOptions
  root: string
  include: {string}
end

--- The Teal configuration of a source tree (tlconfig.lua).
local record Config
  include_dir: {string}
  global_env_def: string
end

-- Lua 5.1's function that Teal's library leaves out.
local record Lua51
  loadstring: function(string, ?string): function, string
end
local loadstring = (_G as Lua51).loadstring

local record M
  type Spec = Spec
  type Stats = Stats
  type Problem = Problem
  type CheckOptions = CheckOptions
  type Config = Config

  compilers: {string: Spec}
  stats: Stats
  problems: {string: {string}}
end

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
function M.add(ext: string, spec: Spec)
  assert(
    ext is string and ext:match("^[%w_]+$") and ext ~= "lua",
    "paw.lang.add: an extension such as \"tl\", without the dot"
  )
  assert(spec is Spec and (spec.compile ~= nil or spec.command ~= nil), "paw.lang.add: give compile or command")
  M.compilers[ext] = spec
end

--- The extension of `path` when a registered language has it, else nil.
function M.of(path: string): string
  local ext = tostring(path):match("%.([%w_]+)$")
  return ext and M.compilers[ext] and ext or nil
end

--- The extensions a source file may have: "lua" first, then each
--- registered one, sorted.
function M.extensions(): {string}
  local out: {string} = {}
  for ext in pairs(M.compilers) do
    out[#out + 1] = ext
  end
  table.sort(out)
  table.insert(out, 1, "lua")
  return out
end

local function read(path: string): string
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

local function shell_quote(s: string): string
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

--- The directory the compiled Lua is kept in: `$XDG_CACHE_HOME/paw/lang`.
function M.cache_dir(): string
  local base = os.getenv("XDG_CACHE_HOME")
  if not base or base == "" then
    base = (os.getenv("HOME") or os.getenv("TMPDIR") or "/tmp") .. "/.cache"
  end
  return base .. "/paw/lang"
end

-- The cache's key for a text: two CRC-32s (of the text and of the text
-- backwards) and the length. A file is found by what it contains, so a copy
-- or a file moved back and forth compiles once.
local function key(text: string): string
  return string.format("%08x%08x-%x", api.crc32(text), api.crc32(text:reverse()), #text)
end

local made: {string: boolean} = {} -- cache directories made in this run

--- Statistics of this run: files compiled and files taken from the cache.
M.stats = {compiled = 0, cached = 0}

--- The problems of each file loaded in this run that did not stop it (type
--- errors), by its path: each `line:col: message`. The cache keeps them
--- with the Lua.
M.problems = {}

-- What the cache keeps after the Lua: a comment with the problems.
local PROBLEMS = "\n--[==[paw.lang problems\n"

local record Paw
  notify: function(string, string)
end

-- Keep the problems of `path`, and say them when they are new.
local function problems(path: string, list: {string}, new: boolean)
  M.problems[path] = #list > 0 and list or nil
  local paw = (_G as {string: Paw}).paw
  if new and #list > 0 and paw and paw.notify then
    paw.notify(
      string.format(
        "%s: %d type error%s, the first %s (:checkhealth teal)", path, #list, #list == 1 and "" or "s", list[1]
      ),
      "warn"
    )
  end
end

--- The Lua of a file in a registered language, compiled or from the cache.
--- `source` is the file's text when it is read already. Returns the Lua,
--- or nil and an error that names the file.
function M.compile(path: string, source?: string): string, string
  local ext = M.of(path)
  if not ext then
    return nil, path .. ": no language for this kind of file"
  end
  local spec = M.compilers[ext]
  source = source or read(path)
  if not source then
    return nil, "cannot open " .. path
  end
  local dir = M.cache_dir() .. "/" .. ext
  local tag = (spec.name or ext) .. " " .. tostring(spec.version or spec.command or "")
  local cached = dir .. "/" .. key(tag .. "\0" .. source) .. ".lua"
  local code = read(cached)
  if code then
    M.stats.cached = M.stats.cached + 1
    local at = code:find(PROBLEMS, 1, true)
    local list: {string} = {}
    if at then
      for line in code:sub(at + #PROBLEMS):gmatch("[^\n]+") do
        if line ~= "]==]" then
          list[#list + 1] = line
        end
      end
    end
    problems(path, list, false)
    return code
  end
  local err: string
  local found: {string} = {}
  if spec.compile then
    local ok, got, why, more = pcall(spec.compile, source, path)
    if ok then
      code, err, found = got, why, more or {}
    else
      err = got
    end
  else
    local pipe = io.popen(spec.command:gsub("%%s", (shell_quote(path):gsub("%%", "%%%%"))) .. " 2>&1")
    local out = pipe and pipe:read("*a") or ""
    local ok = pipe and pipe:close()
    if ok then
      code = out
    else
      err = out
    end
  end
  if not code then
    return nil, path .. ": " .. tostring(err or "does not compile")
  end
  M.stats.compiled = M.stats.compiled + 1
  problems(path, found, true)
  if #found > 0 then
    code = code .. PROBLEMS .. (table.concat(found, "\n"):gsub("%]==%]", "] ==]")) .. "\n]==]\n"
  end
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
function M.find(base: string): string
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
function M.loadfile(path: string): function, string
  if not M.of(path) then
    return loadfile(path)
  end
  local code, err = M.compile(path)
  if not code then
    return nil, err
  end
  return loadstring(code, "@" .. path)
end

--- The file of module `name` in a registered language along `path` (by
--- default `package.path`): each `?.lua` template with the language's
--- extension. Nil and the files it tried when there is none.
function M.searchpath(name: string, path?: string): string, string
  local tried: {string} = {}
  local slashed = name:gsub("%.", "/")
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
local function searcher(name: string): function | string
  local file, tried = M.searchpath(name)
  if not file then
    return tried
  end
  local chunk, err = M.loadfile(file)
  if not chunk then
    error(err, 0)
  end
  return chunk
end
table.insert(package.loaders as {function(string): (function | string)}, searcher)

-- Teal -----------------------------------------------------------------------------

-- The parts of Teal's compiler (runtime/lua/tl.lua) that this module uses.
-- The compiler is a Lua file with no declarations of its own here.
local record Node
end
local record Opaque
end
local record TealEnv
  modules: {string: Opaque}
  module_filenames: {string: string}
  loaded: {string: CheckResult}
  loaded_order: {string}
  globals: {string: Opaque}
  defaults: EnvDefaults
end
local record TealError
  filename: string
  y: integer
  x: integer
  msg: string
end
local record EnvDefaults
  feat_lax: string
  feat_arity: string
  gen_target: string
  gen_compat: string
end
local record EnvOptions
  defaults: EnvDefaults
  predefined_modules: {string}
end
local record CheckResult
  ast: Node
  syntax_errors: {TealError}
  type_errors: {TealError}
  warnings: {TealError}
end
local record File
  read: function(File, string): string
  close: function(File)
end
local record TL
  path: string
  parse: function(string, string): Node, {TealError}
  generate: function(Node, string): string, string
  new_env: function(EnvOptions): TealEnv, string
  check_file: function(string, TealEnv): CheckResult, string
  check_string: function(string, TealEnv, string): CheckResult
  search_module: function(string, boolean): string, File
end

local tl: TL -- the compiler, loaded the first time a `.tl` file is not in the cache

local function teal(): TL
  tl = tl or (require as function(string): TL)("tl")
  return tl
end

-- Lua 5.1 as LuaJIT runs it, without the compatibility code for 5.3.
local record Gen
  gen_target: string
  gen_compat: string
end
local GEN: Gen = {gen_target = "5.1", gen_compat = "off"}

-- Where a check finds a module: along `package.path` (an extension's own
-- modules, the user's), then in the runtime built into the program, which
-- has the declarations of runtime/types. In the order of `tl`: declarations
-- (`.d.tl`) first, then `.tl`, then Lua (which has no types).
local function search(name: string, all: boolean): string, File
  local slashed = name:gsub("%.", "/")
  local function built(file: string): string, File
    local text = api.runtime_file(file)
    if not text then
      return nil
    end
    local f: File = {read = function(): string return text end, close = function() end}
    return "runtime/" .. file, f
  end
  for _, kind in ipairs(all and {".d.tl", ".tl", ".lua"} or {".tl"}) do
    for template in package.path:gmatch("[^;]+") do
      local file = template:gsub("%.lua$", kind):gsub("%?", slashed)
      local f = io.open(file, "rb")
      if f then
        return file, f as File
      end
    end
    local dir = kind == ".d.tl" and "types/" or "lua/"
    local file, f = built(dir .. slashed .. kind)
    if not file then
      file, f = built(dir .. slashed .. "/init" .. kind)
    end
    if file then
      return file, f
    end
  end
  return nil
end

-- Run `fn` with `search` as the compiler's way to find modules.
local function searching<T>(compiler: TL, fn: function(): T): T
  local saved = compiler.search_module
  compiler.search_module = search
  local ok, got = pcall(fn)
  compiler.search_module = saved
  if not ok then
    error(got, 0)
  end
  return got as T
end

local base: TealEnv -- the global `paw` and the runtime's modules, checked once in a run

-- An environment for one file: a copy of `base`, so that what one file
-- declares does not stay for the next.
local function environment(compiler: TL): TealEnv
  base = base
    or searching(
      compiler,
      function(): TealEnv
        return assert(
          compiler.new_env(
            {
              defaults = {
                feat_lax = "off", feat_arity = "on", gen_target = GEN.gen_target, gen_compat = GEN.gen_compat
              },
              predefined_modules = {"paw"},
            }
          )
        )
      end
    )
  local function copy<K, V>(t: {K: V}): {K: V}
    local out: {K: V} = {}
    for k, v in pairs(t) do
      out[k] = v
    end
    return out
  end
  local order: {string} = {}
  for i, f in ipairs(base.loaded_order) do
    order[i] = f
  end
  return {
    modules = copy(base.modules),
    module_filenames = copy(base.module_filenames),
    loaded = copy(base.loaded),
    loaded_order = order,
    globals = copy(base.globals),
    defaults = base.defaults,
  }
end

local function at(e: TealError): string
  return string.format("%d:%d: %s", e.y, e.x, e.msg)
end

M.add(
  "tl",
  {
    name = "teal",
    -- The version of runtime/lua/tl.lua, of what this file asks of it, and
    -- of the types of the runtime that a check reads.
    version = "0.24.8/2/" .. tostring(api.env().teal_types),
    compile = function(source: string, path: string): string, string, {string}
      local compiler = teal()
      -- The first check in a run reads the types of the whole runtime (half a
      -- second): work that ends, so not counted in the time limit.
      local ok, result = pcall(
        limit.unhurried,
        function(): CheckResult
          local env = environment(compiler)
          return searching(compiler, function(): CheckResult return compiler.check_string(source, env, path) end)
        end
      )
      if not ok then
        -- No check (the declarations do not load): the Lua without the types.
        local ast, errors = compiler.parse(source, path)
        if #errors > 0 then
          return nil, at(errors[1])
        end
        local code, err = compiler.generate(ast, GEN.gen_target)
        return code, err, {"1:1: the types were not checked: " .. tostring(result)}
      end
      if #result.syntax_errors > 0 then
        return nil, at(result.syntax_errors[1])
      end
      local code, err = compiler.generate(result.ast, GEN.gen_target)
      local found: {string} = {}
      for i, e in ipairs(result.type_errors) do
        found[i] = at(e)
      end
      return code, err, found
    end,
  }
)

--- The Teal configuration of the source tree (tlconfig.lua): the
--- directories with declarations and modules (`include_dir`), and the file
--- that declares the global names (`global_env_def`).
function M.tlconfig(root?: string): Config
  local chunk = loadfile((root or ".") .. "/tlconfig.lua")
  local ok, config = pcall(chunk or function(): Config return {} end)
  return ok and config is Config and config or {}
end

--- Check the types of `.tl` files, as `tl check` does with the source
--- tree's tlconfig.lua. `opts.include` adds directories to look for
--- modules in. Returns a list of `{ file, line, col, msg, kind }`, kind
--- "error" or "warning", sorted by file and line: empty when all is well.
function M.check(files: {string}, opts?: CheckOptions): {Problem}
  opts = opts or {}
  local compiler = teal()
  local config = M.tlconfig(opts.root)
  local dirs: {string} = {}
  for _, dir in ipairs(config.include_dir or {}) do
    dirs[#dirs + 1] = dir
  end
  for _, dir in ipairs(opts.include or {}) do
    dirs[#dirs + 1] = dir
  end
  local path: {string} = {}
  for _, dir in ipairs(dirs) do
    path[#path + 1] = dir .. "/?.lua"
    path[#path + 1] = dir .. "/?/init.lua"
  end
  local saved = compiler.path
  compiler.path = table.concat(path, ";")
  local out: {Problem} = {}
  local seen: {string: boolean} = {}
  -- On an error, `done` is its message.
  local ok, done = pcall(
    function(): boolean
      local env = assert(
        compiler.new_env(
          {
            defaults = {feat_lax = "off", feat_arity = "on", gen_target = GEN.gen_target, gen_compat = GEN.gen_compat},
            predefined_modules = config.global_env_def and {config.global_env_def} or nil,
          }
        )
      )
      for _, file in ipairs(files) do
        local result, why = compiler.check_file(file, env)
        if not result then
          out[#out + 1] = {file = file, line = 1, col = 1, msg = tostring(why), kind = "error"}
        else
          for _, list in ipairs(
            {{result.syntax_errors, "error"}, {result.type_errors, "error"}, {result.warnings, "warning"}}
          ) do
            for _, e in ipairs(list[1] or {}) do
              -- A module two files require is checked once, and said once.
              local item: Problem = {file = e.filename or file, line = e.y, col = e.x, msg = e.msg, kind = list[2]}
              local id = item.file .. ":" .. item.line .. ":" .. item.col .. ":" .. item.msg
              if not seen[id] then
                seen[id] = true
                out[#out + 1] = item
              end
            end
          end
        end
      end
      return true
    end
  )
  compiler.path = saved
  if not ok then
    out[#out + 1] = {file = files[1] or "?", line = 1, col = 1, msg = tostring(done), kind = "error"}
  end
  table.sort(
    out,
    function(a: Problem, b: Problem): boolean
      if a.file ~= b.file then
        return a.file < b.file
      end
      return a.line < b.line
    end
  )
  return out
end

return M
