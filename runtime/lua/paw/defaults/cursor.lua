-- The default commands and keys: cursor. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
--
-- The motions follow the rules of paw/motion.tl: `h` `l` go to the grid's
-- lines (rule 1), the others to the exact place of a thing (rule 2), and
-- `j` `k` keep the time that the cursor wants (rule 3, paw/cursor.tl).
local api = paw.api
local util = paw.util
local command = paw.command
local cursor, transport, motion, timegrid = paw.cursor, paw.transport, paw.motion, paw.timegrid

command("cursor.down", function(ctx) cursor.move_part(ctx.count or 1) end, { desc = "Next part" })
command("cursor.up", function(ctx) cursor.move_part(-(ctx.count or 1)) end, { desc = "Previous part" })
-- From off the grid, the first step goes to the line next to the cursor.
command(
  "cursor.right",
  function(ctx) cursor.set_tick(motion.grid(1, ctx.count or 1)) end,
  { desc = "Right to the next grid line" }
)
command(
  "cursor.left",
  function(ctx) cursor.set_tick(motion.grid(-1, ctx.count or 1)) end,
  { desc = "Left to the grid line before" }
)
command(
  "cursor.next_bar",
  function(ctx) cursor.set_beat(paw.time.bar_start(paw.time.bar_of(cursor.beat) + (ctx.count or 1))) end,
  { desc = "Start of the next bar" }
)
command("cursor.prev_bar", function(ctx)
  -- From inside a bar, its own start is the first one back.
  local bar = paw.time.bar_of(cursor.beat) - (ctx.count or 1) + (paw.tempo.is_bar_line(cursor.beat) and 0 or 1)
  cursor.set_beat(paw.time.bar_start(math.max(1, bar)))
end, { desc = "Start of the previous bar" })
command("cursor.start", function() cursor.set_tick(0) end, { desc = "Start of the project" })

--- Where the clips on the cursor's part start or end, in ticks, in order.
local function clip_edges(which)
  local part, out = cursor.part(), {}
  for _, c in ipairs(part and api.clip_list(part.id) or {}) do
    out[#out + 1] = timegrid.tick(which == "end" and c.start + c.length or c.start)
  end
  table.sort(out)
  return out
end

command("cursor.end", function()
  local ends = clip_edges("end")
  cursor.set_tick(ends[#ends] or 0)
end, { desc = "End of the part's last clip" })
command(
  "cursor.first_clip",
  function() cursor.set_tick(clip_edges("start")[1] or 0) end,
  { desc = "Start of the part's first clip" }
)
command("cursor.next_clip", function(ctx)
  -- After the last clip there is only the end of it to go to.
  local ends = clip_edges("end")
  local list = clip_edges("start")
  list[#list + 1] = ends[#ends]
  local to = motion.object(list, 1, ctx.count or 1)
  if to then cursor.set_tick(to) end
end, { desc = "Start of the next clip on the part" })
command("cursor.prev_clip", function(ctx)
  local list = clip_edges("start")
  list[#list + 1] = 0
  local to = motion.object(list, -1, ctx.count or 1)
  if to then cursor.set_tick(to) end
end, { desc = "Start of the clip under the cursor, or of the one before" })
command("cursor.clip_end", function(ctx)
  local to = motion.object(clip_edges("end"), 1, ctx.count or 1)
  if to then cursor.set_tick(to) end
end, { desc = "End of the clip under the cursor, or of the next one" })
command("cursor.bar", function(ctx)
  -- In a scope with time, its own bars: bar 1 is where it starts.
  cursor.set_beat(paw.time.bar_start(paw.scope.song_bar(ctx.count or tonumber(ctx.args[1]) or 1)))
end, { desc = "Start of a bar: `cursor.bar 9` (in a scope with time, its bar 9)" })
command("cursor.first_part", function(ctx)
  local list = paw.scope.parts()
  if #list > 0 then cursor.set_part(list[util.clamp(ctx.count or 1, 1, #list)]) end
end, { desc = "First part, or part number N" })
command("cursor.last_part", function(ctx)
  local list = paw.scope.parts()
  if #list > 0 then cursor.set_part(list[util.clamp(ctx.count or #list, 1, #list)]) end
end, { desc = "Last part, or part number N" })
-- Exact, as an object motion: `h` or `l` then go to a line.
command(
  "cursor.to_playhead",
  function() cursor.set_beat(transport.position) end,
  { desc = "Move the cursor to the playhead" }
)
