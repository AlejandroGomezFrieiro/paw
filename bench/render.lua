-- Offline render throughput.
--   paw --clean --no-plugins -l bench/render.lua <tracks> <audio|midi> <fx 0|1> <automation 0|1> [bars] [threads]
-- `threads` 0 or left out renders on one thread per core.
local paw = require("paw")
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local tracks = tonumber(arg and arg[1] or select(1, ...)) or 10
local args = { ... }
tracks = tonumber(args[1]) or tracks
local kind = args[2] or "midi"
local fx = args[3] == "1"
local automation = args[4] == "1"
local bars = tonumber(args[5]) or 16
local threads = tonumber(args[6]) or 0

local build_ms = B.time(B.build, { tracks = tracks, kind = kind, fx = fx, automation = automation, bars = bars })
local out = B.tmp .. "/render.wav"
local opts = { start = 0, ["end"] = bars * 4, tail = 0 }
-- Builds from before renders used several threads take no such option.
if threads > 0 then opts.threads = threads end
local wall, info = B.time(paw.render, out, opts)
local rss = B.rss()
-- Builds from before the engine reported its own timing give wall time only.
info.elapsed = info.elapsed or wall
info.blocks = info.blocks or {}
B.emit({
  workload = "render",
  tracks = tracks,
  kind = kind,
  fx = fx and 1 or 0,
  automation = automation and 1 or 0,
  threads = info.threads or 1,
  bars = bars,
  audio_seconds = info.seconds,
  build_ms = build_ms,
  render_ms = info.elapsed,
  processing_ms = info.processing,
  wall_ms = wall,
  realtime_x = info.seconds * 1000 / info.elapsed,
  block_p50_ms = info.blocks.p50,
  block_p99_ms = info.blocks.p99,
  block_max_ms = info.blocks.max,
  block_budget_ms = info.blocks.budget,
  peak = info.peak,
  rss_kb = rss,
})
os.remove(out)
paw.api.quit(0)
