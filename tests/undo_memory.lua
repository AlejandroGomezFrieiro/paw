-- Tests of what the undo history keeps: a step on a big clip costs what it
-- changed, and the history's limits are options. Loaded by tests/suite.lua
-- with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api

--- A part with one clip of `count` notes, as an undo step of its own.
local function big_clip(count)
  fresh()
  local part = api.part_add({ name = "Big" })
  local clip = api.clip_add(part, { start = 0, length = count / 4 })
  local notes = {}
  for i = 1, count do
    notes[i] = { start = (i - 1) / 4, length = 0.25, pitch = 36 + i % 48, velocity = 90 }
  end
  api.clip_set_notes(clip, notes)
  paw.flush()
  api.undo_checkpoint()
  return clip
end

--- What the last `steps` steps added to the history, in bytes each.
local function per_step(fn, steps)
  local before = api.undo_tree().bytes
  for i = 1, steps do
    fn(i)
    paw.flush()
    api.undo_checkpoint()
  end
  return (api.undo_tree().bytes - before) / steps
end

test("a one-note edit to a clip of many notes costs the undo history a few kilobytes, not the clip", function()
  local count = 50000
  local clip = big_clip(count)
  -- The clip itself is about 50,000 notes of some 60 bytes.
  local whole = per_step(function(i) api.clip_note_set(clip, 1 + i * 997 % count, { velocity = 1 + i }) end, 20)
  eq(whole < 64 * 1024, true, string.format("one note set: %d bytes a step", whole))
  local added = per_step(
    function(i) api.clip_note_add(clip, { start = i * 997 % count / 4, length = 0.25, pitch = 100 }) end,
    20
  )
  eq(added < 64 * 1024, true, string.format("one note added: %d bytes a step", added))
  local removed = per_step(function(i) api.clip_note_remove(clip, 1 + i * 997 % count) end, 20)
  eq(removed < 64 * 1024, true, string.format("one note removed: %d bytes a step", removed))
  -- The whole list read, one note changed and written back, as scripts do.
  local list = api.clip_notes(clip)
  local resent = per_step(function(i)
    list[100 * i].velocity = 5
    api.clip_set_notes(clip, list)
  end, 5)
  eq(resent < 64 * 1024, true, string.format("the whole list sent back: %d bytes a step", resent))

  -- And every step undoes and redoes to what it was.
  local now = api.clip_notes(clip)
  for _ = 1, 65 do
    api.undo()
  end
  paw.flush()
  eq(#api.clip_notes(clip), count, "undone to the clip as it was made")
  eq(api.clip_notes(clip)[1 + 997 % count].velocity, 90, "and the first note set is as it was")
  for _ = 1, 65 do
    api.redo()
  end
  paw.flush()
  local again = api.clip_notes(clip)
  eq(#again, #now, "redone")
  for i = 1, #now, 997 do
    eq(
      again[i].velocity == now[i].velocity and again[i].start == now[i].start and again[i].id == now[i].id,
      true,
      "note " .. i .. " as it was"
    )
  end
end)

test("a clip moved on a part of thousands of clips costs what it moved, and undo and redo are exact", function()
  fresh()
  local part = api.part_add({ name = "Many" })
  local ids = {}
  for i = 1, 3000 do
    ids[i] = api.clip_add(part, { start = (i - 1) * 4, length = 4, notes = { { start = 0, length = 1, pitch = 60 } } })
  end
  paw.flush()
  api.undo_checkpoint()
  local changed, added, removed = {}, 0, 0
  local on = {
    paw.on("clip.changed", function(e) changed[#changed + 1] = e.id end),
    paw.on("clip.added", function() added = added + 1 end),
    paw.on("clip.removed", function() removed = removed + 1 end),
  }
  -- A step holds about a run of the part's clips, not a pointer to each.
  local moved = per_step(function(i) api.clip_set(ids[i * 97], "start", (i * 97 - 1) * 4 + 1) end, 30)
  eq(moved < 8 * 1024, true, string.format("one clip moved: %d bytes a step", moved))
  eq(#changed, 30, "each move says which clip changed")
  eq(changed[30], ids[30 * 97])
  local gone = per_step(function(i) api.clip_remove(ids[i * 13]) end, 10)
  eq(gone < 8 * 1024, true, string.format("one clip removed: %d bytes a step", gone))
  eq(removed, 10, "each removal is said")
  api.clip_add(part, { start = 2, length = 1 })
  paw.flush()
  api.undo_checkpoint()
  eq(added, 1)
  for _, id in ipairs(on) do
    paw.off(id)
  end

  local function starts()
    local out = {}
    for _, c in ipairs(api.clip_list(part)) do
      out[#out + 1] = c.id .. "@" .. c.start
    end
    return table.concat(out, " ")
  end
  local now = starts()
  for _ = 1, 41 do
    api.undo()
  end
  paw.flush()
  eq(#api.clip_list(part), 3000, "undone to the clips as they were made")
  eq(api.clip_get(ids[97]).start, 96 * 4, "and where they were")
  for _ = 1, 41 do
    api.redo()
  end
  paw.flush()
  eq(starts(), now, "redone to every clip where it was")
end)

test("the undo history keeps as many steps and as much memory as its options say", function()
  fresh()
  local tree = api.undo_tree()
  eq(tree.limit, paw.opt.undo_steps, "the history keeps what the option says")
  eq(tree.byte_limit, paw.opt.undo_memory * 1024 * 1024, "in bytes")
  local t = paw.add_part({ name = "Steps" })
  for i = 1, 30 do
    t.name = "Step " .. i
    api.undo_checkpoint()
  end
  eq(#api.undo_tree().states, 31, "the first state and thirty steps")
  T.keys(":set undo_steps=10<CR>")
  eq(paw.opt.undo_steps, 10, "set from the command line")
  eq(#api.undo_tree().states, 10, "the oldest steps go at once")
  eq(api.undo_tree().limit, 10)
  T.keys(":set undo_steps=abc<CR>")
  eq(paw.opt.undo_steps, 10, "a value it does not take is refused")
  T.fails(function() paw.opt.undo_steps = 2.5 end, "undo_steps takes a whole number from 10")
  T.fails(function() paw.opt.undo_memory = 1 end, "undo_memory takes a number from 16")
  paw.opt.undo_memory = 16
  eq(api.undo_tree().byte_limit, 16 * 1024 * 1024)
  -- A new project keeps the limits.
  api.project_new()
  eq(api.undo_tree().limit, 10, "the limits outlast the project")
  paw.opt.undo_steps = 1000
  paw.opt.undo_memory = 1024
  eq(api.undo_tree().limit, 1000)
end)
