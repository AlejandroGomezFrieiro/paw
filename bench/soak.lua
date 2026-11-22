-- Soak: play for several minutes on the null backend while editing all the
-- time, and watch for dropouts, slow blocks, leaks and memory growth.
--   paw --clean --no-plugins -l bench/soak.lua <minutes> [tracks]
local paw = require("paw")
local api = paw.api
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local minutes, tracks = ...
minutes, tracks = tonumber(minutes) or 3, tonumber(tracks) or 40

api.engine_restart({ backend = "null", buffer_size = 256, sample_rate = 48000 })
local ids = B.build({ tracks = tracks, kind = "midi", fx = true, automation = true, bars = 16 })
paw.transport.loop_start, paw.transport.loop_end = 0, 64
paw.transport.loop_enabled = true
paw.transport.play()
paw.flush()
api.sleep(500)
api.engine_reset_stats()

local seed = 7
local function rand(n)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed % n + 1
end

local deadline = api.now() + minutes * 60000
local edits, samples = 0, {}
local rss_start = B.rss()
local next_sample = api.now() + 10000
while api.now() < deadline do
  local id = ids[rand(#ids)]
  local what = rand(8)
  if what == 1 then
    local clip = api.clip_list(id)[1]
    if clip then api.clip_set(clip.id, "start", rand(4) - 1) end
  elseif what == 2 then
    api.track_set(id, "volume", -rand(12))
  elseif what == 3 then
    local clip = api.clip_list(id)[1]
    if clip then
      local notes = api.clip_notes(clip.id)
      if #notes > 0 then
        notes[rand(#notes)].pitch = 36 + rand(48)
        api.clip_set_notes(clip.id, notes)
      end
    end
  elseif what == 4 then
    local dev = api.track_get(id).devices[1]
    if dev then api.device_set_param(dev, "cutoff", 200 + rand(8000)) end
  elseif what == 5 then
    api.undo()
  elseif what == 6 then
    api.redo()
  elseif what == 7 then
    -- Replace a track entirely now and then: a new one in its place.
    local i = rand(#ids)
    api.track_remove(ids[i])
    paw.flush()
    local t = api.track_add({ name = "new" })
    api.device_add(t, "synth")
    api.device_add(t, "delay")
    api.clip_add(t, { start = 0, length = 64, notes = B.bar_notes(rand(16) - 1, i) })
    ids[i] = t
  else
    local lane = api.lane_list(id)[1]
    if lane then api.lane_add_point(lane.id, rand(64) - 1, -rand(20)) end
  end
  paw.flush()
  api.undo_checkpoint()
  -- Undo may have brought back removed tracks, or taken away new ones.
  if what == 5 or what == 6 then ids = api.track_list() end
  edits = edits + 1
  if api.now() > next_sample then
    samples[#samples + 1] = B.rss()
    next_sample = api.now() + 10000
  end
  api.sleep(10)
end
local info = api.engine_get()
paw.transport.stop()
local half = math.max(1, math.floor(#samples / 2))
B.emit({
  workload = "soak", minutes = minutes, tracks = tracks, edits = edits, blocks = info.blocks.count,
  budget_ms = info.blocks.budget, p99_ms = info.blocks.p99, max_ms = info.blocks.max, xruns = info.xruns,
  leaked = info.leaked, rss_start_kb = rss_start, rss_end_kb = B.rss(),
  rss_samples_kb = samples,
  rss_growth_kb_per_min = #samples > 1 and (samples[#samples] - samples[half]) / ((#samples - half) * 10 / 60) or 0,
})
api.quit(0)
