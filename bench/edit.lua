-- Editing at scale. Every edit is one "turn" as the UI makes it: the call,
-- then `paw.flush()` (sync to the engine, deliver events), then an undo step.
--   paw --clean --no-plugins -l bench/edit.lua clips <n>     add, move, delete n clips; undo and redo all
--   paw --clean --no-plugins -l bench/edit.lua notes <n>     add, move, delete n notes in one clip
--   paw --clean --no-plugins -l bench/edit.lua scale <tracks> one small edit, undo and redo in a big project
local paw = require("paw")
local api = paw.api
local B = dofile(debug.getinfo(1, "S").source:sub(2):match("(.*)/") .. "/lib.lua")

local mode, n, nosync = ...
n = tonumber(n) or 1000
-- `nosync`: leave out the sync to the engine and the change events, as
-- Tracktion's own edit calls do (it rebuilds its playback graph later, on its
-- message loop). The model edit and the undo step remain.
nosync = nosync == "nosync"

local function turn(fn, ...)
  local t = api.now()
  fn(...)
  if not nosync then paw.flush() end
  api.undo_checkpoint()
  return api.now() - t
end

--- Total time, and the mean per op of the first and last tenth: a ratio well
--- above 1 means each op gets slower as the project grows.
local function summary(times)
  local total, tenth = 0, math.max(1, math.floor(#times / 10))
  local first, last = 0, 0
  for i, t in ipairs(times) do
    total = total + t
    if i <= tenth then first = first + t end
    if i > #times - tenth then last = last + t end
  end
  local s = B.stats(times)
  return total, first / tenth, last / tenth, s.p99, s.max
end

if mode == "clips" then
  local track = api.track_add({ name = "T" })
  paw.flush()
  api.undo_checkpoint()
  local ids, add, move, del = {}, {}, {}, {}
  for i = 1, n do
    add[i] = turn(function() ids[i] = api.clip_add(track, { start = (i - 1) * 4, length = 4 }) end)
  end
  for i = 1, n do
    move[i] = turn(api.clip_set, ids[i], "start", (i - 1) * 4 + 2)
  end
  for i = 1, n do
    del[i] = turn(api.clip_remove, ids[i])
  end
  local undo_ms, undone = B.time(function()
    local k = 0
    -- The undo history keeps 1000 states and always the first, so undoing
    -- further than that jumps back to the empty project: stop short of it.
    for _ = 1, math.min(3 * n, 998) do
      if not api.undo() then break end
      if not nosync then paw.flush() end
      k = k + 1
    end
    return k
  end)
  local ok, list = pcall(api.clip_list, track)
  local after = ok and #list or nil
  local redo_ms, redone = B.time(function()
    local k = 0
    while api.redo() do
      if not nosync then paw.flush() end
      k = k + 1
    end
    return k
  end)
  local a, a1, a2 = summary(add)
  local m, m1, m2 = summary(move)
  local d, d1, d2 = summary(del)
  B.emit({
    workload = nosync and "edit_nosync" or "edit",
    clips = n,
    add_ms = a,
    move_ms = m,
    delete_ms = d,
    undo_ms = undo_ms,
    undo_steps = undone,
    redo_ms = redo_ms,
    redo_steps = redone,
    clips_after_undo = after,
    add_first_ms = a1,
    add_last_ms = a2,
    move_first_ms = m1,
    move_last_ms = m2,
    delete_first_ms = d1,
    delete_last_ms = d2,
    rss_kb = B.rss(),
  })
elseif mode == "notes" then
  local track = api.track_add({ name = "T" })
  local clip = api.clip_add(track, { start = 0, length = n + 4 })
  paw.flush()
  api.undo_checkpoint()
  local add, move, del = {}, {}, {}
  for i = 1, n do
    add[i] = turn(
      api.clip_add_notes,
      clip,
      { { pitch = 36 + (i - 1) % 48, start = (i - 1) * 0.25, length = 0.25, velocity = 100 } }
    )
  end
  -- One note at a time, as the piano roll does it. Builds from before there
  -- was a call for one note (and `list`, to compare) read the notes, change
  -- one and write them all back.
  local one = api.clip_note_set and select(4, ...) ~= "list"
  for i = 1, n do
    move[i] = turn(function()
      if one then
        api.clip_note_set(clip, i, { start = (i - 1) * 0.25 + 0.125 })
      else
        local notes = api.clip_notes(clip)
        notes[i].start = notes[i].start + 0.125
        api.clip_set_notes(clip, notes)
      end
    end)
  end
  for i = 1, n do
    del[i] = turn(function()
      if one then
        api.clip_note_remove(clip, n - i + 1)
      else
        local notes = api.clip_notes(clip)
        table.remove(notes)
        api.clip_set_notes(clip, notes)
      end
    end)
  end
  local a, a1, a2 = summary(add)
  local m, m1, m2 = summary(move)
  local d, d1, d2 = summary(del)
  B.emit({
    workload = nosync and "notes_nosync" or "notes",
    notes = n,
    add_ms = a,
    move_ms = m,
    delete_ms = d,
    add_first_ms = a1,
    add_last_ms = a2,
    move_first_ms = m1,
    move_last_ms = m2,
    delete_first_ms = d1,
    delete_last_ms = d2,
    rss_kb = B.rss(),
  })
elseif mode == "scale" then
  -- n tracks, each a synth and a delay playing one 16-bar clip.
  local build_ms, ids = B.time(B.build, { tracks = n, kind = "midi", fx = true, bars = 16 })
  local vol, clipmove, undo, redo = {}, {}, {}, {}
  for i = 1, 50 do
    local id = ids[(i * 7) % #ids + 1]
    vol[i] = turn(api.track_set, id, "volume", -(i % 12))
    local clip = api.clip_list(id)[1].id
    clipmove[i] = turn(api.clip_set, clip, "start", i % 4)
    local t = api.now()
    api.undo()
    paw.flush()
    undo[i] = api.now() - t
    t = api.now()
    api.redo()
    paw.flush()
    redo[i] = api.now() - t
  end
  local add_track = turn(api.track_add, { name = "one more" })
  local sv, sc, su, sr = B.stats(vol), B.stats(clipmove), B.stats(undo), B.stats(redo)
  B.emit({
    workload = "scale",
    tracks = n,
    build_ms = build_ms,
    volume_ms = sv.p50,
    volume_max_ms = sv.max,
    clip_move_ms = sc.p50,
    clip_move_max_ms = sc.max,
    undo_ms = su.p50,
    undo_max_ms = su.max,
    redo_ms = sr.p50,
    redo_max_ms = sr.max,
    track_add_ms = add_track,
    rss_kb = B.rss(),
  })
else
  error("usage: edit.lua clips|notes|scale <n>")
end
api.quit(0)
