-- The default commands and keys: cursor. Loaded by paw/defaults.lua;
-- like it, it uses nothing but the public `paw` module.
local api = paw.api
local util = paw.util
local command = paw.command
local cursor, transport = paw.cursor, paw.transport

command("cursor.down", function(ctx) cursor.move_track(ctx.count or 1) end, { desc = "Next track" })
command("cursor.up", function(ctx) cursor.move_track(-(ctx.count or 1)) end, { desc = "Previous track" })
command(
  "cursor.right",
  function(ctx) cursor.set_beat(cursor.step(cursor.beat, ctx.count or 1)) end,
  { desc = "Move right one grid step" }
)
command(
  "cursor.left",
  function(ctx) cursor.set_beat(cursor.step(cursor.beat, -(ctx.count or 1))) end,
  { desc = "Move left one grid step" }
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
command("cursor.start", function() cursor.set_beat(0) end, { desc = "Start of the project" })

--- Where the clips on the cursor's track start or end, in order.
local function clip_edges(which)
  local track, out = cursor.track(), {}
  for _, c in ipairs(track and api.clip_list(track.id) or {}) do
    out[#out + 1] = which == "end" and c.start + c.length or c.start
  end
  table.sort(out)
  return out
end

command("cursor.end", function()
  local ends = clip_edges("end")
  cursor.set_beat(ends[#ends] or 0)
end, { desc = "End of the track's last clip" })
command(
  "cursor.first_clip",
  function() cursor.set_beat(clip_edges("start")[1] or 0) end,
  { desc = "Start of the track's first clip" }
)
command("cursor.next_clip", function(ctx)
  for _ = 1, ctx.count or 1 do
    local to
    for _, beat in ipairs(clip_edges("start")) do
      if beat > cursor.beat + 1e-9 then
        to = beat
        break
      end
    end
    -- After the last clip there is only the end of it to go to.
    if not to then
      local ends = clip_edges("end")
      to = ends[#ends]
    end
    if not to or to <= cursor.beat then return end
    cursor.set_beat(to)
  end
end, { desc = "Start of the next clip on the track" })
command("cursor.prev_clip", function(ctx)
  for _ = 1, ctx.count or 1 do
    local to = 0
    for _, beat in ipairs(clip_edges("start")) do
      if beat < cursor.beat - 1e-9 then to = beat end
    end
    cursor.set_beat(to)
  end
end, { desc = "Start of the clip under the cursor, or of the one before" })
command("cursor.clip_end", function(ctx)
  for _ = 1, ctx.count or 1 do
    for _, beat in ipairs(clip_edges("end")) do
      if beat > cursor.beat + 1e-9 then
        cursor.set_beat(beat)
        break
      end
    end
  end
end, { desc = "End of the clip under the cursor, or of the next one" })
command("cursor.bar", function(ctx)
  -- In a scope with time, its own bars: bar 1 is where it starts.
  cursor.set_beat(paw.time.bar_start(paw.scope.song_bar(ctx.count or tonumber(ctx.args[1]) or 1)))
end, { desc = "Start of a bar: `cursor.bar 9` (in a scope with time, its bar 9)" })
command("cursor.first_track", function(ctx)
  local list = paw.scope.tracks()
  if #list > 0 then cursor.set_track(list[util.clamp(ctx.count or 1, 1, #list)]) end
end, { desc = "First track, or track number N" })
command("cursor.last_track", function(ctx)
  local list = paw.scope.tracks()
  if #list > 0 then cursor.set_track(list[util.clamp(ctx.count or #list, 1, #list)]) end
end, { desc = "Last track, or track number N" })
command(
  "cursor.to_playhead",
  function() cursor.set_beat(cursor.snap(transport.position)) end,
  { desc = "Move the cursor to the playhead" }
)
