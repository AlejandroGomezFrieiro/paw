-- What edit quality saves while paw plays: N audio parts, each with a
-- saturation at 4x, played live on the null backend on one thread, with
-- `paw.opt.quality` at "full" and at "edit" in turn, for `rounds` pairs.
--   paw --clean --no-plugins -l bench/quality.lua [parts] [seconds] [rounds] [kind]
-- `kind` (default saturation) is the device on each part, with the
-- settings of `settings` below; `none` measures the parts alone. A build
-- without edit quality measures "full" only.
-- Each line gives the processor time of the audio thread (from
-- /proc/self/task/*/schedstat: it does not count the time that other
-- programs have the processor) and the engine's own time per block.
local paw = require("paw")
local api = paw.api
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local parts, seconds, rounds, kind = ...
parts, seconds, rounds = tonumber(parts) or 16, tonumber(seconds) or 5, tonumber(rounds) or 5
kind = kind or "saturation"

-- Settings that keep each device busy, and the saturation at 4x.
local settings = {
  saturation = { oversample = 1, drive = 12 },
  compressor = { threshold = -30, lookahead = 2 },
}

local stat = assert(io.open("/proc/self/stat"))
local main = stat:read("*l"):match("^(%d+)")
stat:close()

--- Nanoseconds on the processor of each thread of paw but the main one
--- (the kernel), by thread id.
local function thread_ns()
  local out = {}
  for _, e in ipairs(api.read_dir("/proc/self/task")) do
    if e.name ~= main then
      local f = io.open("/proc/self/task/" .. e.name .. "/schedstat")
      if f then
        out[e.name] = tonumber(f:read("*l"):match("^(%d+)"))
        f:close()
      end
    end
  end
  return out
end

api.engine_restart({ backend = "null", buffer_size = 256, sample_rate = 48000 })
api.engine_set_threads(1)
local ids = B.build({ parts = parts, kind = "audio", bars = 16 })
for _, id in ipairs(ids) do
  if kind ~= "none" then api.device_add(id, kind, { params = settings[kind] or {} }) end
end
paw.flush()
paw.transport.loop_start, paw.transport.loop_end = 0, 64
paw.transport.loop_enabled = true
paw.transport.play()

local qualities = api.engine_set_quality and { "full", "edit" } or { "full" }
for round = 1, rounds do
  for _, quality in ipairs(qualities) do
    if api.engine_set_quality then paw.opt.quality = quality end
    paw.flush()
    api.sleep(300)
    api.engine_reset_stats()
    local before = thread_ns()
    api.sleep(seconds * 1000)
    local after = thread_ns()
    -- The audio thread is the one that ran the most.
    local busiest = 0
    for tid, ns in pairs(after) do
      busiest = math.max(busiest, ns - (before[tid] or ns))
    end
    local blocks = api.engine_get().blocks
    B.emit({
      workload = "quality",
      kind = kind,
      quality = quality,
      round = round,
      parts = parts,
      seconds = seconds,
      audio_core_percent = busiest / (seconds * 1e9) * 100,
      blocks = blocks.count,
      mean_ms = blocks.mean,
      p99_ms = blocks.p99,
      budget_ms = blocks.budget,
      load = B.load(),
    })
  end
end
paw.transport.stop()
api.quit(0)
