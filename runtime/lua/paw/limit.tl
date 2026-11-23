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
-- The budget (`paw.opt.budget_ms`, 0: off) is a far shorter time that a
-- callback should take: a key handler, an event handler, a timer, a
-- command, drawing. A callback over it is named once in `:messages`
-- (`slow: the key j 12 ms (budget 5 ms)`). It costs two looks at the wall clock (`paw.api.real_ms`)
-- for each callback, and nothing when it is off. A slow callback inside
-- another is named, not the one around it. Time spent waiting in the kernel
-- (`unhurried`) does not count.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. The
-- functions that call another (`guard`, `call`, `named`, `unhurried`) pass
-- on arguments of one type: give a closure for more.
local api = require("paw.api")
local events = require("paw.events")
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

local type Fn = function(...: Value): Value...
local type Body<A> = function(A...): (Value...)
local type Call<A> = function(Body<A>, A...): (Value...)

local record M
  --- A callback that took longer than `paw.opt.budget_ms`: its name, how
  --- many milliseconds it took the first time (`ms`) and the last time
  --- (`last`), and how many times it went over the budget.
  record Slow
    name: string
    ms: number
    last: number
    times: integer
  end
  wrapped: boolean
  --- Each callback that went over the budget, once for each name, in the
  --- order of the first time (`paw.opt.budget_ms`).
  slow: {Slow}
end
M.slow = {}

-- What this module reads of `paw`, which paw/init.lua makes. A module of the
-- runtime in Teal does not see the global `paw`: runtime/types/paw.d.tl
-- declares it from these modules.
local record Paw
  try: Fn
  notify: function(string, string)
end
local paw = (_G as {string:Paw}).paw

local CHECK_EVERY = 100000  -- instructions between looks at the clock

local deadline: number     -- when the running callback must have returned, or nil
local what: {string} = {}  -- a stack of what is running, for the error
local budget: number       -- the milliseconds of a shorter limit (`within`), or nil

options.define("lua_limit", 2000, { min = 0 })
local opt = options.opt

local async = api.limit_async == true

-- The budget of a callback, `paw.opt.budget_ms`, kept here so that a
-- callback reads no option: 0 is off.
options.define("budget_ms", 0, { min = 0 })
local slow_ms: number = 0
local inner_slow = false  -- a call inside the running one went over the budget
local paused = 0.0        -- the milliseconds spent waiting in the kernel, in all
local warned: {string: M.Slow} = {}

events.on(
  options.changed,
  function(e: options.Changed)
    if e.name == "budget_ms" then
      slow_ms = (opt.budget_ms as number) or 0
    end
  end
)

--- Name a callback that went over the budget, once, and count it each
--- time. A timer has no name: the place of its function in the code names it.
local function report(name: string, fn: function, ms: number)
  if not name then
    local info = debug.getinfo(fn, "S")
    name = string.format("a timer (%s:%d)", info.short_src:match("[^/]*/?[^/]*$"), info.linedefined)
  end
  local seen = warned[name]
  if seen then
    seen.last, seen.times = ms, seen.times + 1
    return
  end
  seen = { name = name, ms = ms, last = ms, times = 1 }
  warned[name] = seen
  M.slow[#M.slow + 1] = seen
  paw.notify(string.format("slow: %s %d ms (budget %g ms)", name, math.floor(ms + 0.5), slow_ms), "warn")
end

--- The end of a call timed against the budget: what it returned, passed on.
local function finish<R>(name: string, fn: function, saved: boolean, t0: number, p0: number, ...: R): R...
  local ms = api.real_ms() - t0 - (paused - p0)
  local slow = slow_ms > 0 and ms > slow_ms
  if slow and not inner_slow then
    report(name, fn, ms)
  end
  inner_slow = saved or slow
  return ...
end

--- Time spent waiting in the kernel, which the budget does not count.
local function resume<R>(before: number, ...: R): R...
  paused = paused + (api.real_ms() - before)
  return ...
end

--- Set when the running call must have returned (nil: it has).
local function set(to: number)
  deadline = to
  if async then api.limit_watch(to) end
end

local function hook()
  if not deadline then return end
  if api.real_ms() > deadline then
    local name = what[#what] or "a callback"
    local ms = budget or opt.lua_limit or 2000
    -- Another full stretch for whatever runs after the error, such as the
    -- handler that reports it.
    set(api.real_ms() + ms)
    error(string.format("%s ran for more than %g s without returning, and was stopped", name, ms / 1000), 2)
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
  set(api.real_ms() + opt.lua_limit)
  what = { name }
  if not async then debug.sethook(hook, "", CHECK_EVERY) end
  local result = { call(fn, ...) }
  if not async then (debug.sethook as function())() end
  set(nil)
  what = {}
  return result
end

--- Call `fn(...)` against the budget of a callback (`paw.opt.budget_ms`):
--- if it takes longer, paw names it as `name` once in `:messages`. A nil
--- `name` is a timer, named by where `fn` is in the code. Returns what
--- `fn` returns.
function M.timed<A, R>(name: string, fn: function(A...): (R...), ...: A): R...
  if slow_ms <= 0 then
    return fn(...)
  end
  local saved = inner_slow
  inner_slow = false
  return finish(name, fn as function, saved, api.real_ms(), paused, fn(...))
end

local function guarded<A, R>(name: string, fn: function(A...): (R...), ...: A): boolean, R...
  if deadline or (opt.lua_limit or 0) <= 0 then return (paw.try as function(function(A...): (R...), A...): (boolean, R...))(fn, ...) end
  return (lua51.unpack as function(Results): (boolean, R...))(limited(name, paw.try as Call<A>, fn as Body<A>, ...))
end

--- Call `fn(...)` under the time limit for Lua (`paw.opt.lua_limit`). paw
--- stops a call that runs too long, and reports it as `name`. paw reports
--- errors and does not raise them. Returns the results of `fn`.
function M.guard<A, R>(name: string, fn: function(A...): (R...), ...: A): boolean, R...
  if slow_ms <= 0 then
    return guarded(name, fn, ...)
  end
  local saved = inner_slow
  inner_slow = false
  local t0, p0 = api.real_ms(), paused
  return (finish as function(string, function, boolean, number, number, boolean, R...): (boolean, R...))(
    name, fn as function, saved, t0, p0, guarded(name, fn, ...))
end

--- Call `fn(...)` with the time limit as `guard` does, but give its error
--- to the caller and do not report it. Use it for a call whose caller must
--- know the problem, for example a request on the control socket.
function M.call<A, R>(name: string, fn: function(A...): (R...), ...: A): R...
  if deadline or (opt.lua_limit or 0) <= 0 then return M.timed(name, fn, ...) end
  local result = limited(name, pcall as Call<A>, M.timed as Body<A>, name as A, fn as A, ...)
  if not result[1] then error(result[2], 0) end
  return (lua51.unpack as function(Results, integer, integer): R...)(result, 2, maxn(result))
end

--- Name what runs inside the limited call, for the error should it run away:
--- `paw.limit.named("command `x`", fn, ...)`.
function M.named<A, R>(name: string, fn: function(A...): (R...), ...: A): R...
  if not deadline then return M.timed(name, fn, ...) end
  local depth = #what
  what[depth + 1] = name
  local result = { M.timed(name, fn, ...) }
  for i = #what, depth + 1, -1 do what[i] = nil end
  return lua51.unpack(result)
end

--- Call `fn(...)` with at most `ms` milliseconds, as `call` does: its
--- error goes to the caller. Inside a limited call, the shorter of the two
--- limits holds, and the rest of the outer one goes on after. Use it for
--- code of an extension that must be fast, as a kind of clip's `compile`
--- (`paw.opt.clip_kind_limit`).
function M.within<A, R>(ms: number, name: string, fn: function(A...): (R...), ...: A): R...
  if (opt.lua_limit or 0) <= 0 or ms <= 0 then return fn(...) end
  local outer, was, depth = deadline, budget, #what
  local mine = api.real_ms() + ms
  if outer and outer <= mine then return M.named(name, fn, ...) end
  budget = ms
  what[depth + 1] = name
  set(mine)
  if not outer and not async then debug.sethook(hook, "", CHECK_EVERY) end
  local result = { (pcall as Call<A>)(fn as Body<A>, ...) }
  if not outer and not async then (debug.sethook as function())() end
  for i = #what, depth + 1, -1 do what[i] = nil end
  budget = was
  set(outer)
  if not result[1] then error(result[2], 0) end
  return (lua51.unpack as function(Results, integer, integer): R...)(result, 2, maxn(result))
end

--- Give the current call more time, as `:lua` does: `ms` from now.
function M.extend(ms: number)
  if deadline then set(math.max(deadline, api.real_ms() + ms)) end
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
  if not deadline then
    if slow_ms <= 0 then return fn(...) end
    return resume(api.real_ms(), fn(...))
  end
  local was, names, before = deadline, what, api.real_ms()
  set(nil)
  what = {}
  local result = { (pcall as Call<A>)(fn as Body<A>, ...) }
  what = names
  local waited = api.real_ms() - before
  paused = paused + waited
  set(was + waited)
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
