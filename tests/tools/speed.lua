-- How fast the tests' own code runs, measured as processor time, with a
-- limit that grows on a loaded machine. Shared by tests/suite.lua and the
-- end-to-end scenarios (tests/e2e). See docs/how-to/run-the-tests.md.
--- Milliseconds of processor time that this thread has used. A test of
--- speed measures this, not the time on the clock: on a loaded machine the
--- clock runs on while other programs have the processor, and this does
--- not.
local ffi = require("ffi")
pcall(ffi.cdef, "struct paw_timespec { long tv_sec; long tv_nsec; }; int clock_gettime(int, struct paw_timespec *);")
local cpu_now = ffi.new("struct paw_timespec")
local function cpu_ms()
  ffi.C.clock_gettime(3, cpu_now) -- CLOCK_THREAD_CPUTIME_ID
  return tonumber(cpu_now.tv_sec) * 1000 + tonumber(cpu_now.tv_nsec) / 1e6
end

--- How many times more work there is than processors (1 at least): the
--- load average of the last minute over the processors.
local function overload()
  local f = io.open("/proc/loadavg")
  local load = f and tonumber(f:read("*l"):match("^(%S+)")) or 0
  if f then f:close() end
  local p = io.popen("nproc 2>/dev/null")
  local cpus = p and tonumber(p:read("*l") or "") or 1
  if p then p:close() end
  return math.max(1, load / cpus)
end

--- A fixed piece of work with tables, strings and arithmetic, like the
--- work that the speed tests measure.
local function reference_work()
  local t, n = {}, 0
  for i = 1, 20000 do
    t[i] = { i, tostring(i) }
  end
  for i = 1, #t do
    n = n + #t[i][2] + t[i][1] % 7
  end
  table.sort(t, function(x, y) return x[2] < y[2] end)
  return n
end

--- Processor time of `reference_work` on an idle machine, in ms (the
--- smallest of many runs).
local REFERENCE_IDLE_MS = 8.0

--- How many times slower this thread runs now than on an idle machine
--- (1 at least, 8 at most): the best of three runs of `reference_work`
--- against its time on an idle machine. Contention for the caches and the
--- memory inflates processor time, and the load average does not show it.
local function slowdown()
  local best = math.huge
  for _ = 1, 3 do
    local t0 = cpu_ms()
    reference_work()
    best = math.min(best, cpu_ms() - t0)
  end
  return math.min(8, math.max(1, best / REFERENCE_IDLE_MS))
end

--- Check that `ms` of processor time (`cpu_ms`) is under `limit`. Programs
--- that share the processor's caches and memory make the same work take
--- more processor time: the limit grows with the overload of the machine
--- and with the slowdown of a fixed piece of work (at most 8 times).
local function quick(ms, limit, what)
  local over = overload()
  local slow = slowdown()
  local allowed = limit * math.max(over, slow)
  if ms >= allowed then
    error(
      string.format(
        "%s: %.0f ms of processor time, the limit %.0f ms (%d ms times %.1f: overload %.1f, slowdown %.1f)",
        what,
        ms,
        allowed,
        limit,
        math.max(over, slow),
        over,
        slow
      ),
      2
    )
  end
end

return { cpu_ms = cpu_ms, overload = overload, slowdown = slowdown, quick = quick }
