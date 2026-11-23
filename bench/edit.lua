-- Editing at scale. Every edit is one "turn" as the UI makes it: the call,
-- then `paw.flush()` (sync to the engine, deliver events), then an undo step.
--   paw --clean --no-plugins -l bench/edit.lua clips <n>     add, move, delete n clips; undo and redo all
--   paw --clean --no-plugins -l bench/edit.lua notes <n>     add, move, delete n notes in one clip
--   paw --clean --no-plugins -l bench/edit.lua scale <parts> one small edit, undo and redo in a big project
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
  local t = api.real_ms()
  fn(...)
  if not nosync then paw.flush() end
  api.undo_checkpoint()
  return api.real_ms() - t
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
  local part = api.part_add({ name = "T" })
  paw.flush()
  api.undo_checkpoint()
  local ids, add, move, del = {}, {}, {}, {}
  for i = 1, n do
    add[i] = turn(function() ids[i] = api.clip_add(part, { start = (i - 1) * 4, length = 4 }) end)
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
  local ok, list = pcall(api.clip_list, part)
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
  local part = api.part_add({ name = "T" })
  local clip = api.clip_add(part, { start = 0, length = n + 4 })
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
  -- n parts, each a synth and a delay playing one 16-bar clip.
  local build_ms, ids = B.time(B.build, { parts = n, kind = "midi", fx = true, bars = 16 })
  local vol, clipmove, undo, redo = {}, {}, {}, {}
  for i = 1, 50 do
    local id = ids[(i * 7) % #ids + 1]
    vol[i] = turn(api.part_set, id, "volume", -(i % 12))
    local clip = api.clip_list(id)[1].id
    clipmove[i] = turn(api.clip_set, clip, "start", i % 4)
    local t = api.real_ms()
    api.undo()
    paw.flush()
    undo[i] = api.real_ms() - t
    t = api.real_ms()
    api.redo()
    paw.flush()
    redo[i] = api.real_ms() - t
  end
  local add_part = turn(api.part_add, { name = "one more" })
  local sv, sc, su, sr = B.stats(vol), B.stats(clipmove), B.stats(undo), B.stats(redo)
  B.emit({
    workload = "scale",
    parts = n,
    build_ms = build_ms,
    volume_ms = sv.p50,
    volume_max_ms = sv.max,
    clip_move_ms = sc.p50,
    clip_move_max_ms = sc.max,
    undo_ms = su.p50,
    undo_max_ms = su.max,
    redo_ms = sr.p50,
    redo_max_ms = sr.max,
    part_add_ms = add_part,
    rss_kb = B.rss(),
  })
elseif mode == "turn" then
  -- The end of a turn alone, in a project of n synth parts: the kernel's
  -- `close_turn` (events, hooks, scenes, the frontend state) and the undo step.
  -- A request of a connection pays it once, with nothing changed
  -- (a read) or after its edit.
  local _, ids = B.time(B.build, { parts = n, kind = "midi", fx = true, bars = 16 })
  local function finish()
    paw._kernel.close_turn()
    api.undo_checkpoint()
  end
  finish()
  local empty, edited = {}, {}
  for i = 1, 200 do
    local t = api.real_ms()
    finish()
    empty[i] = api.real_ms() - t
    api.part_set(ids[(i * 7) % #ids + 1], "volume", -(i % 12))
    t = api.real_ms()
    finish()
    edited[i] = api.real_ms() - t
  end
  local se, sd = B.stats(empty), B.stats(edited)
  B.emit({
    workload = "turn",
    parts = n,
    empty_ms = se.p50,
    empty_max_ms = se.max,
    edited_ms = sd.p50,
    edited_max_ms = sd.max,
  })
else
  error("usage: edit.lua clips|notes|scale|turn <n>")
end
api.quit(0)
