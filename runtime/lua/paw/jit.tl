-- The parameters of LuaJIT's trace compiler, set before the runtime loads.
--
-- LuaJIT keeps at most `maxtrace` traces (1000 by default) and `maxmcode`
-- KB of machine code (2048). When a new trace does not fit, it throws all
-- traces away (a flush), and each hot path compiles again. The runtime and
-- a large project make more than 1000 traces: the start alone made about
-- 1 000, and the keys of a scope 2 700 more. With the defaults, paw flushed
-- during the start and two or three times in the keys of
-- bench/profile.md's scenario `scope`, and the trace compiler was 20 to
-- 60 percent of a key that ran code for the first time. A larger cache
-- keeps the traces: bench/RESULTS.md has the numbers.
--
-- The other parameters stay at LuaJIT's defaults: `hotloop` and `hotexit`
-- higher did not change the cost of a first key.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua. The kernel
-- loads it from paw/init.lua, before any other module of the runtime.

local record Opt
  start: function(...: string)
end
local record Jit
  opt: Opt
end
local record Globals
  jit: Jit
end

-- The number of traces (LuaJIT allows up to 65 535) and the KB of
-- machine code. A long session can still fill them; then LuaJIT flushes
-- as before.
local MAX_TRACES = 8000
local MAX_MCODE_KB = 16384

-- PUC Lua (paw/portable.lua) has no `jit`; LuaJIT without the compiler has
-- no `jit.opt`.
local jit = (_G as Globals).jit
if jit and jit.opt then
  jit.opt.start("maxtrace=" .. MAX_TRACES, "maxmcode=" .. MAX_MCODE_KB)
end
