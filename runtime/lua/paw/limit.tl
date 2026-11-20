-- A time limit on Lua that runs away. A key handler, a command, an event
-- handler, a timer, a view or a request on the control socket that runs for more than `paw.opt.lua_limit`
-- milliseconds (2000) without returning is stopped with an error naming it,
-- instead of freezing the program.
--
-- How: while the kernel is in Lua for a key, a timer, events or drawing, it
-- knows when that call must have returned. Nothing looks at the clock while
-- the call runs. A thread in the kernel does, and only when the time is up
-- does it set a hook from outside, which the kernel's LuaJIT is built to
-- notice inside compiled loops as well (`crates/paw-core/src/watchdog.rs`).
-- So everything is compiled, extensions included, and the limit costs
-- nothing until it is needed.
--
-- A kernel built against a LuaJIT without that (`paw.api.limit_async` is
-- false) does it the old way: a count hook looks at the clock every few
-- thousand instructions, and since LuaJIT does not call hooks from compiled
-- code, code that is not the runtime's own (extensions, the user's
-- `init.lua` and modules, `:lua`) is kept out of the compiler.
--
-- `-l` scripts and `paw.wait` run outside any limit; `:lua` gets a minute.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. The
-- functions that call another (`guard`, `call`, `named`, `unhurried`) pass
-- on arguments of one type: give a closure for more.
local api = require("paw.api")
local options = require("paw.options")

--- A value this module passes on and never reads.
local record Value
end

--- Results as `{ f(...) }` keeps them.
local type Results = {Value}

-- Lua 5.1's and LuaJIT's functions that Teal's library leaves out.
local record Lua51
  unpack: function<T>({T}, ? integer, ? integer): T...
end
local record LuaTable
  maxn: function<T>({T}): integer
end
local record Jit
  off: function(function, boolean)
end
local record Globals
  jit: Jit
end
local lua51 = _G as Lua51
local maxn = (table as LuaTable).maxn
local jit = (_G as Globals).jit

-- The fields of the kernel's table besides its functions.
local record Kernel
  limit_async: boolean
end

local type Fn = function(...: Value): Value...
local type Body<A> = function(A...): (Value...)
local type Call<A> = function(Body<A>, A...): (Value...)

local record M
  wrapped: boolean
end

local CHECK_EVERY = 100000  -- instructions between looks at the clock

local deadline: number     -- when the running callback must have returned, or nil
local what: {string} = {}  -- a stack of what is running, for the error

options.define("lua_limit", 2000, { min = 0 })
local opt = options.opt

local async = (api as Kernel).limit_async == true

--- Set when the running call must have returned (nil: it has).
local function set(to: number)
  deadline = to
  if async then api.limit_watch(to) end
end

local function hook()
  if not deadline then return end
  if api.now() > deadline then
    local name = what[#what] or "a callback"
    -- Another full stretch for whatever runs after the error, such as the
    -- handler that reports it.
    set(api.now() + (opt.lua_limit or 2000))
    error(string.format("%s ran for more than %g s without returning, and was stopped", name,
      (opt.lua_limit or 2000) / 1000), 2)
  end
  -- Called early (the limit moved after the kernel's thread looked): the
  -- thread is told again.
  set(deadline)
end
if async then api.limit_hook(hook) end

--- Call `fn(...)` as `paw.try` does (an error becomes a message), with the
--- time limit. The kernel's ways into Lua go through here. Inside a call
--- that is limited already, it is `paw.try`.
local function limited<A>(name: string, call: Call<A>, fn: Body<A>, ...: A): Results
  set(api.now() + opt.lua_limit)
  what = { name }
  if not async then debug.sethook(hook, "", CHECK_EVERY) end
  local result = { call(fn, ...) }
  if not async then (debug.sethook as function())() end
  set(nil)
  what = {}
  return result
end

--- Call `fn(...)` under the time limit for Lua (`paw.opt.lua_limit`). paw
--- stops a call that runs too long, and reports it as `name`. paw reports
--- errors and does not raise them. Returns the results of `fn`.
function M.guard<A, R>(name: string, fn: function(A...): (R...), ...: A): boolean, R...
  if deadline or (opt.lua_limit or 0) <= 0 then return (paw.try as function(function(A...): (R...), A...): (boolean, R...))(fn, ...) end
  return (lua51.unpack as function(Results): (boolean, R...))(limited(name, paw.try as Call<A>, fn as Body<A>, ...))
end

--- Call `fn(...)` with the time limit as `guard` does, but give its error
--- to the caller and do not report it. Use it for a call whose caller must
--- know the problem, for example a request on the control socket.
function M.call<A, R>(name: string, fn: function(A...): (R...), ...: A): R...
  if deadline or (opt.lua_limit or 0) <= 0 then return fn(...) end
  local result = limited(name, pcall as Call<A>, fn as Body<A>, ...)
  if not result[1] then error(result[2], 0) end
  return (lua51.unpack as function(Results, integer, integer): R...)(result, 2, maxn(result))
end

--- Name what runs inside the limited call, for the error should it run away:
--- `paw.limit.named("command `x`", fn, ...)`.
function M.named<A, R>(name: string, fn: function(A...): (R...), ...: A): R...
  if not deadline then return fn(...) end
  local depth = #what
  what[depth + 1] = name
  local result = { fn(...) }
  for i = #what, depth + 1, -1 do what[i] = nil end
  return lua51.unpack(result)
end

--- Give the current call more time, as `:lua` does: `ms` from now.
function M.extend(ms: number)
  if deadline then set(math.max(deadline, api.now() + ms)) end
end

--- Mark a function that the runtime did not write. Where the limit can stop
--- compiled code, this does nothing. Where it cannot, the JIT compiler does
--- not compile the function and each function made inside it. So the
--- limit can stop their loops (unless `paw.opt.lua_limit = 0` disables the
--- limit before paw loads the code).
function M.untrusted<F>(fn: F): F
  if not async and fn is function and jit and jit.off and (opt.lua_limit or 0) > 0 then
    jit.off(fn as function, true)
  end
  return fn
end

--- Run `fn(...)` with its time not counted, for work that is known to be
--- long and to end: `paw.limit.unhurried(synthesise, phrase)`. Callbacks
--- the kernel makes meanwhile (timers during a wait) get a limit of their
--- own.
function M.unhurried<A, R>(fn: function(A...): (R...), ...: A): R...
  if not deadline then return fn(...) end
  local was, names, before = deadline, what, api.now()
  set(nil)
  what = {}
  local result = { (pcall as Call<A>)(fn as Body<A>, ...) }
  what = names
  set(was + (api.now() - before))
  if not async then debug.sethook(hook, "", CHECK_EVERY) end
  if not result[1] then error(result[2], 0) end
  return (lua51.unpack as function(Results, integer, integer): R...)(result, 2, maxn(result))
end

-- Waiting in the kernel is not Lua running away: a render, a project being
-- read, a plugin being made, a wait.
local kernel = api as {string:Fn}
for _, name in ipairs({ "wait", "render", "project_load", "project_save", "device_add", "device_restart",
  "device_editor", "engine_restart", "import_audio", "clip_import" }) do
  local inner = kernel[name]
  if inner is Fn then
    kernel[name] = function(...: Value): Value... return M.unhurried(inner, ...) end
  end
end

-- Modules found on disk (extensions' `lua/` directories, the user's own)
-- are untrusted, unless they are the runtime's files.
do
  local loaders = package.loaders as {function(string): (function | string)}
  local disk = loaders[2]
  if disk and not M.wrapped then
    M.wrapped = true
    loaders[2] = function(name: string): function | string
      local chunk = disk(name)
      if chunk is function then
        local source = debug.getinfo(chunk, "S").source or ""
        if not source:find("runtime/lua/paw/", 1, true) then M.untrusted(chunk) end
      end
      return chunk
    end
  end
end

return M
