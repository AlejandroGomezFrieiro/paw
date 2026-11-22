-- Real-time headroom: per-callback processing time while the project plays
-- on the null backend, which calls the engine on a real-time schedule.
--   paw --clean --no-plugins -l bench/blocks.lua <tracks> <audio|midi> <fx 0|1> <automation 0|1> <buffer> <seconds> [edit|play] [threads]
-- With `edit`, the script edits the project (moves a clip, changes a
-- volume) every 20 ms while it plays, as a user dragging things would.
-- `threads` 0 or left out plays on one thread per core.
local paw = require("paw")
local api = paw.api
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local tracks, kind, fx, automation, buffer, seconds, edit, threads = ...
tracks, buffer, seconds = tonumber(tracks) or 10, tonumber(buffer) or 256, tonumber(seconds) or 10
kind = kind or "midi"

api.engine_restart({ backend = "null", buffer_size = buffer, sample_rate = 48000 })
-- Builds from before the engine used several threads have no such call.
if api.engine_set_threads then api.engine_set_threads(tonumber(threads) or 0) end
local ids = B.build({ tracks = tracks, kind = kind, fx = fx == "1", automation = automation == "1", bars = 16 })
paw.transport.loop_start, paw.transport.loop_end = 0, 64
paw.transport.loop_enabled = true
paw.transport.play()
paw.flush()
api.sleep(200)
api.engine_reset_stats()
local edits = 0
local deadline = api.now() + seconds * 1000
while api.now() < deadline do
  if edit == "edit" then
    local id = ids[edits % #ids + 1]
    local clip = api.clip_list(id)[1]
    api.clip_set(clip.id, "start", clip.start == 0 and 0.25 or 0)
    api.track_set(id, "volume", -(edits % 6))
    paw.flush()
    api.undo_checkpoint()
    edits = edits + 1
    api.sleep(20)
  else
    api.sleep(100)
  end
end
local info = api.engine_get()
paw.transport.stop()
local b = info.blocks
B.emit({
  workload = "blocks",
  tracks = tracks,
  kind = kind,
  fx = fx == "1" and 1 or 0,
  automation = automation == "1" and 1 or 0,
  buffer = buffer,
  seconds = seconds,
  edits = edits,
  blocks = b.count,
  budget_ms = b.budget,
  mean_ms = b.mean,
  p50_ms = b.p50,
  p99_ms = b.p99,
  p999_ms = b.p999,
  max_ms = b.max,
  max_load = b.max / b.budget,
  xruns = info.xruns,
  leaked = info.leaked,
  threads = info.threads or 1,
})
api.quit(0)
