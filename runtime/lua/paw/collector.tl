-- The Lua garbage collector between keys. LuaJIT collects in steps while
-- Lua allocates: a key pays for steps of the cycle under way, and the key
-- in which a cycle ends pays for its last steps (the atomic step and the
-- sweep, several milliseconds on a large project). The slow callback that
-- `paw.opt.budget_ms` then names is an event handler or a frame that did
-- not cause the work (bench/RESULTS.md).
--
-- So each cycle runs between keys, as the job `collector` of paw.slices:
-- after a turn in which the heap grew to `grow` times its size after the
-- last cycle, the job steps the collector until the cycle ends. LuaJIT's
-- own pause (`PAUSE`) is longer, so a cycle starts inside a turn only when
-- that turn alone makes more garbage than the room between the two. The
-- cycles come as often as with LuaJIT's default pause (200): the work
-- moves, and does not grow.
--
-- Between two slices of the job the collector is stopped. Else each turn
-- in between (a key, a frame) pays for steps as it allocates, and what it
-- leaves owed makes the next slice run long. A turn that makes the heap
-- pass LuaJIT's pause starts the collector again (`turn`).
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.
local api = require("paw.api")
local slices = require("paw.slices")

local record M
  --- When the job starts a cycle: the size of the heap, as a multiple of
  --- its size after the last cycle (`base`).
  grow: number
  --- The size of the heap in KB after the last cycle.
  base: number
  --- How many cycles the job ended.
  cycles: integer
end

-- LuaJIT starts a cycle by itself when the heap is PAUSE percent of its
-- size after the last cycle: past `grow`, so that the job comes first.
local PAUSE = 300
-- The most milliseconds that one slice of the job steps the collector.
-- The atomic step of a cycle is one step, and can take longer.
local SLICE_MS = 2

M.grow = 2
M.cycles = 0
M.base = collectgarbage("count")

collectgarbage("setpause", PAUSE)

-- True while the job stopped the collector between two of its slices.
local stopped = false

local function restart()
  if stopped then
    collectgarbage("restart")
    stopped = false
  end
end

--- True when the heap passed the size at which LuaJIT collects by itself.
local function past_pause(): boolean
  return collectgarbage("count") >= M.base * PAUSE / 100
end

-- One slice of the job: steps of the collector until the cycle ends (true)
-- or the slice is over. A step of LuaJIT gives true when it ended a cycle.
local function step(ms: number): boolean
  restart()
  -- A budget of work: on the wall clock.
  local deadline = api.real_ms() + ms
  repeat
    if collectgarbage("step", 0) as boolean then
      M.cycles = M.cycles + 1
      M.base = collectgarbage("count")
      return true
    end
  until api.real_ms() >= deadline
  if not past_pause() then
    collectgarbage("stop")
    stopped = true
  end
  return false
end

--- The end of a turn (the kernel's `close_turn`): start the job when the heap
--- grew to `grow` times `base`. It reads only the size of the heap.
function M.turn()
  if slices.job("collector") then
    -- A turn between two slices that made much garbage: LuaJIT collects
    -- again as it allocates.
    if stopped and past_pause() then
      restart()
    end
    return
  end
  -- The job ended in another way (an error, `paw.slices.stop`).
  restart()
  local kb = collectgarbage("count")
  -- A cycle that LuaJIT ended by itself left a smaller heap.
  if kb < M.base then
    M.base = kb
  end
  if kb >= M.base * M.grow then
    slices.run("collector", step, {ms = SLICE_MS, idle = true})
  end
end

return M
