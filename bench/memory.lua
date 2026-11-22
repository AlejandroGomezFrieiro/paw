-- Resident memory.
--   paw --clean --no-plugins -l bench/memory.lua project <tracks> <clips per track> <undo steps>
--       a large project (as in saveload.lua), then a long undo history of
--       one-note edits on its first clip, as in the Tracktion driver's `memory`
--   paw --clean --no-plugins -l bench/memory.lua churn <rounds>
--       build, edit, render, undo and clear the same project over and over:
--       resident memory should level off rather than keep growing
--   paw --clean --no-plugins -l bench/memory.lua bigclip <notes> <steps> <adds>
--       one clip of many notes, `steps` one-note edits as undo steps (what
--       each costs the undo history, and how long it takes), undo and redo
--       them all, then `adds` notes added one at a time
local paw = require("paw")
local api = paw.api
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local mode, a, b, c = ...

if mode == "bigclip" then
  local count, steps, adds = tonumber(a) or 200000, tonumber(b) or 100, tonumber(c) or 2000
  local track = api.track_add({ name = "T" })
  local clip = api.clip_add(track, { start = 0, length = count / 4 })
  local notes = {}
  for i = 1, count do
    notes[i] = { start = (i - 1) / 4, length = 0.25, pitch = 36 + i % 48, velocity = 90 }
  end
  api.clip_set_notes(clip, notes)
  notes = nil -- luacheck: ignore 311 (dropped for the collector)
  paw.flush()
  api.undo_checkpoint()
  collectgarbage()
  local bytes_before = api.undo_tree().bytes
  local rss_before = B.rss()
  local times = {}
  for i = 1, steps do
    local t = api.now()
    api.clip_note_set(clip, 1 + (i * 7919) % count, { velocity = 1 + i % 126 })
    paw.flush()
    api.undo_checkpoint()
    times[i] = api.now() - t
  end
  collectgarbage()
  local tree = api.undo_tree()
  local rss_after = B.rss()
  local undo_ms = B.time(function()
    for _ = 1, steps do api.undo() paw.flush() end
  end)
  local redo_ms = B.time(function()
    for _ = 1, steps do api.redo() paw.flush() end
  end)
  local add_ms = B.time(function()
    for i = 1, adds do
      api.clip_note_add(clip, { start = (i * 7919) % count / 4, length = 0.25, pitch = 100, velocity = 90 })
      paw.flush()
      api.undo_checkpoint()
    end
  end)
  local s = B.stats(times)
  B.emit({
    workload = "bigclip", notes = count, steps = steps,
    -- Builds from before the history told its size leave this out.
    history_bytes_per_step = tree.bytes and (tree.bytes - bytes_before) / steps,
    rss_kb_per_step = (rss_after - rss_before) / steps,
    edit_p50_ms = s.p50, edit_max_ms = s.max,
    undo_ms_per_step = undo_ms / steps, redo_ms_per_step = redo_ms / steps,
    adds_per_second = adds / (add_ms / 1000),
  })
elseif mode == "project" then
  local tracks, clips, steps = tonumber(a) or 100, tonumber(b) or 8, tonumber(c) or 1000
  local rss_start = B.rss()
  local first
  for i = 0, tracks - 1 do
    local id = api.track_add({ name = "T" .. i })
    api.device_add(id, "synth", { params = { wave = 1 } })
    api.device_add(id, "delay")
    for k = 0, clips - 1 do
      local clip = api.clip_add(id, { start = k * 4, length = 4, notes = B.bar_notes(0, i) })
      first = first or clip
    end
  end
  api.undo_checkpoint()
  paw.flush()
  -- Let the engine run for a moment so that device buffers are touched.
  api.sleep(500)
  local rss_built = B.rss()
  for i = 1, steps do
    local notes = api.clip_notes(first)
    local n = notes[(i - 1) % #notes + 1]
    n.velocity = 1 + i % 126
    api.clip_set_notes(first, notes)
    paw.flush()
    api.undo_checkpoint()
  end
  local rss_undo = B.rss()
  B.emit({
    workload = "memory", tracks = tracks, clips_per_track = clips, undo_steps = steps,
    rss_start_kb = rss_start, rss_built_kb = rss_built, rss_undo_kb = rss_undo,
  })
elseif mode == "churn" then
  local rounds = tonumber(a) or 20
  local samples = {}
  for round = 1, rounds do
    api.project_new()
    paw.flush()
    B.build({ tracks = 20, kind = "midi", fx = true, automation = true, bars = 4 })
    for _, id in ipairs(api.track_list()) do
      api.track_set(id, "volume", -3)
      paw.flush()
      api.undo_checkpoint()
    end
    for _ = 1, 10 do api.undo() end
    paw.flush()
    paw.render(B.tmp .. "/churn.wav", { tail = 0 })
    api.project_save(B.tmp .. "/churn.json")
    api.project_load(B.tmp .. "/churn.json")
    paw.flush()
    samples[round] = B.rss()
  end
  os.remove(B.tmp .. "/churn.wav")
  os.remove(B.tmp .. "/churn.json")
  local half = math.floor(rounds / 2)
  B.emit({
    workload = "churn", rounds = rounds, rss_first_kb = samples[1], rss_mid_kb = samples[half],
    rss_last_kb = samples[rounds],
    -- Growth per round over the second half, in kB: near 0 when nothing leaks.
    growth_kb_per_round = (samples[rounds] - samples[half]) / math.max(1, rounds - half),
  })
else
  error("usage: memory.lua project <tracks> <clips> <steps> | churn <rounds>")
end
api.quit(0)
