-- Arranging by section: moving, duplicating, deleting and inserting whole
-- stretches of the song on every track at once, clips and automation alike.
--
-- Everything here is one operation, `rebuild(plan)`, which lays the timeline
-- out again from pieces of the old one. A plan is a list of pieces, each
-- either a stretch of the old timeline put somewhere,
--   { from = 0, to = 16, at = 32 }        (`to` may be math.huge)
-- or a register value put somewhere,
--   { value = value, at = 16 }
-- Whatever no piece takes is dropped and a piece may be used more than once.
-- Clips reaching across a piece's edges are cut there first, so every clip
-- belongs to one piece; it keeps its id (and `meta`) when it is used once.
-- Automation is cut the same way: each piece takes the lane's values at its
-- edges with it as points, so a moved stretch sounds as it did, with a step
-- where it meets a different neighbour. Section markers go with their piece.
--
-- Called from a key or a command, a rebuild is one undo step like any edit.
local api = paw.api
local S = require("sections")
local M = {}
local EPS = 1e-9
local INF = math.huge

-- Clips ------------------------------------------------------------------------------

--- The part of a clip between two beats as a snapshot for `paw.restore_clip`,
--- starting where it starts on the timeline; nil when there is none. Notes
--- belong to the part they start in and are shortened to fit it.
local function piece(c, notes, from, to)
  local a, b = math.max(c.start, from), math.min(c.start + c.length, to)
  if b - a <= EPS then return nil end
  local snap = { name = c.name, start = a, length = b - a, kind = c.kind, muted = c.muted, meta = c.meta }
  if c.kind == "midi" then
    snap.notes = {}
    for _, n in ipairs(notes) do
      local start = c.start + n.start
      if start >= a - EPS and start < b - EPS then
        snap.notes[#snap.notes + 1] = paw.util.merge(n, { start = start - a, length = math.min(n.length, b - start) })
      end
    end
  else
    snap.file, snap.gain = c.file, c.gain
    snap.offset = c.offset + paw.time.seconds(a - c.start, c.start)
  end
  return snap
end

local function notes_of(c)
  return c.kind == "midi" and api.clip_notes(c.id) or nil
end

--- Put a clip snapshot on a track, `meta` included.
local function restore(snap, track)
  local meta = snap.meta
  local copy = paw.util.merge(snap, {})
  copy.meta = nil
  local clip = paw.restore_clip(copy, track)
  if type(meta) == "table" and next(meta) ~= nil then api.clip_set(clip.id, "meta", meta) end
  return clip
end

--- Cut the clips of a track that reach across a beat in two there.
local function cut(track, at)
  for _, c in ipairs(api.clip_list(track)) do
    if c.start < at - EPS and c.start + c.length > at + EPS then
      local notes = notes_of(c)
      local left, right = piece(c, notes, c.start, at), piece(c, notes, at, c.start + c.length)
      api.clip_set(c.id, "length", left.length)
      if notes then api.clip_set_notes(c.id, left.notes) end
      restore(right, track)
    end
  end
end

--- What a track holds between two beats, counting from `from`.
local function copy_clips(track, from, to)
  local out = {}
  for _, c in ipairs(api.clip_list(track)) do
    local p = piece(c, notes_of(c), from, to)
    if p then
      p.start = p.start - from
      out[#out + 1] = p
    end
  end
  return out
end

-- Automation ------------------------------------------------------------------------

local function lerp(p, q, x)
  if q[1] - p[1] < EPS then return q[2] end
  return p[2] + (q[2] - p[2]) * (x - p[1]) / (q[1] - p[1])
end

--- A lane's value just before a beat, and at it (they differ at a step).
local function before(points, x)
  local prev, nxt
  for _, p in ipairs(points) do
    if p[1] < x - EPS then prev = p elseif not nxt then nxt = p end
  end
  if not prev then return nxt[2] end
  if not nxt then return prev[2] end
  return lerp(prev, nxt, x)
end

local function after(points, x)
  local prev, nxt
  for _, p in ipairs(points) do
    if p[1] <= x + EPS then prev = p elseif not nxt then nxt = p end
  end
  if not prev then return nxt[2] end
  if not nxt or math.abs(prev[1] - x) < EPS then return prev[2] end
  return lerp(prev, nxt, x)
end

--- A stretch of a lane as points counting from `from`, with its values at
--- both edges.
local function segment(points, from, to)
  if #points == 0 then return {} end
  local out = { { 0, after(points, from) } }
  for _, p in ipairs(points) do
    if p[1] > from + EPS and p[1] < to - EPS then out[#out + 1] = { p[1] - from, p[2] } end
  end
  if to < INF then out[#out + 1] = { to - from, before(points, to) } end
  return out
end

--- Drop points that change nothing: repeats, and points inside a level
--- stretch. At least one point stays.
local function simplify(points)
  local dedup = {}
  for _, p in ipairs(points) do
    local last = dedup[#dedup]
    if not (last and math.abs(last[1] - p[1]) < EPS and last[2] == p[2]) then dedup[#dedup + 1] = p end
  end
  local out = {}
  for i, p in ipairs(dedup) do
    local prev, nxt = dedup[i - 1], dedup[i + 1]
    local same_before = not prev or prev[2] == p[2]
    local same_after = not nxt or nxt[2] == p[2]
    if not (same_before and same_after) then out[#out + 1] = p end
  end
  if #out == 0 and dedup[1] then out[1] = dedup[1] end
  return out
end

--- What identifies a lane on its track, the same after the track is copied.
local function lane_key(lane)
  local index = ""
  if lane.device then
    local ok, d = pcall(api.device_get, lane.device)
    index = ok and d.index or lane.device
  end
  return string.format("%s|%s|%s", lane.target, lane.param or "", index)
end

--- Every track with its row (0 for the master track) and lanes.
local function all_tracks()
  local out = { { id = 0, row = 0 } }
  for row, id in ipairs(api.track_list()) do out[#out + 1] = { id = id, row = row } end
  return out
end

-- Registers -------------------------------------------------------------------------

--- A stretch of every track as a register value. It is an ordinary "range"
--- that `p` and `P` can paste from the first track, with automation and the
--- sections in it added for `insert`.
function M.yank_range(from, to)
  local value = { kind = "range", length = to - from, rows = {}, lanes = {}, sections = {} }
  for _, t in ipairs(all_tracks()) do
    if t.row > 0 then value.rows[t.row] = copy_clips(t.id, from, to) end
    local lanes = {}
    for _, lane in ipairs(api.lane_list(t.id)) do
      if lane.point_count > 0 then lanes[lane_key(lane)] = segment(api.lane_points(lane.id), from, to) end
    end
    value.lanes[t.row] = lanes
  end
  for _, s in ipairs(S.list()) do
    if s.start >= from - EPS and s.start < to - EPS then
      value.sections[#value.sections + 1] = { name = s.name, start = s.start - from }
    end
  end
  return value
end

-- Rebuilding ---------------------------------------------------------------------------

local function covers(p, beat)
  return not p.value and beat >= p.from - EPS and beat < p.to - EPS
end

--- Lay the timeline out again from a plan; see the top of this file.
function M.rebuild(plan)
  -- In the order they land, so that a lane's points come out in order, and
  -- at a beat where two pieces meet the earlier piece's point comes first.
  local sorted = {}
  for _, p in ipairs(plan) do
    if p.value or p.to - p.from > EPS then sorted[#sorted + 1] = p end
  end
  table.sort(sorted, function(a, b) return a.at < b.at end)
  plan = sorted

  -- Cut every clip at every edge of a piece of the old timeline.
  local edges = {}
  for _, p in ipairs(plan) do
    if not p.value then
      if p.from > EPS then edges[#edges + 1] = p.from end
      if p.to < INF then edges[#edges + 1] = p.to end
    end
  end
  local tracks = all_tracks()

  for _, t in ipairs(tracks) do
    if t.row > 0 then
      for _, edge in ipairs(edges) do cut(t.id, edge) end
      local clips = api.clip_list(t.id)
      local copies = {}
      for _, c in ipairs(clips) do
        local used = false
        for _, p in ipairs(plan) do
          if covers(p, c.start) then
            local start = c.start - p.from + p.at
            if not used then
              used = true
              api.clip_set(c.id, "start", start)
            else
              local snap = piece(c, notes_of(c), c.start, c.start + c.length)
              snap.start = start
              copies[#copies + 1] = snap
            end
          end
        end
        if not used then api.clip_remove(c.id) end
      end
      for _, p in ipairs(plan) do
        local rows = p.value and p.value.rows
        for _, snap in ipairs(rows and rows[t.row] or {}) do
          copies[#copies + 1] = paw.util.merge(snap, { start = p.at + snap.start })
        end
      end
      for _, snap in ipairs(copies) do restore(snap, t.id) end
    end
  end

  for _, t in ipairs(tracks) do
    for _, lane in ipairs(api.lane_list(t.id)) do
      local key, points = lane_key(lane), api.lane_points(lane.id)
      local out, any = {}, false
      for _, p in ipairs(plan) do
        local part
        if p.value then
          part = p.value.lanes and p.value.lanes[t.row] and p.value.lanes[t.row][key]
        elseif #points > 0 then
          part = segment(points, p.from, p.to)
        end
        for _, q in ipairs(part or {}) do
          -- Rounded, so that where two pieces meet their points share a beat exactly.
          out[#out + 1] = { math.floor((q[1] + p.at) * 1e9 + 0.5) / 1e9, q[2] }
          any = true
        end
      end
      if any then api.lane_set_points(lane.id, simplify(out)) end
    end
  end

  -- Section markers.
  local list = {}
  local old = S.list()
  for _, p in ipairs(plan) do
    if p.value then
      for _, s in ipairs(p.value.sections or {}) do list[#list + 1] = { name = s.name, start = p.at + s.start } end
    else
      for _, s in ipairs(old) do
        if covers(p, s.start) then list[#list + 1] = { name = s.name, start = s.start - p.from + p.at } end
      end
    end
  end
  S.write(list)
end

-- What a section can do -----------------------------------------------------------------

--- The section and its neighbour `by` places along (1 the next, -1 the one before).
local function neighbour(which, by)
  local s = S.need(which)
  local other = S.list()[s.index + by]
  return s, other
end

--- Move a section past its neighbour, later (`by` 1) or earlier (-1), on
--- every track. Further with a larger `by`. Returns the section where it is now.
function M.move(which, by)
  by = by or 1
  local s = S.need(which)
  for _ = 1, math.abs(by) do
    local dir = by > 0 and 1 or -1
    local _, other = neighbour(s, dir)
    if not other then break end
    local first, second = s, other
    if dir < 0 then first, second = other, s end
    local a, b, c = first.start, second.start, second.finish
    M.rebuild({
      { from = 0, to = a, at = 0 },
      { from = b, to = c, at = a },
      { from = a, to = b, at = a + c - b },
      { from = c, to = INF, at = c },
    })
    s = S.at(dir > 0 and a + c - b or a)
  end
  return s
end

--- Put a copy of a section right after it, pushing the rest of the song
--- along. Returns the copy.
function M.duplicate(which)
  local s = S.need(which)
  local a, b = s.start, s.finish
  M.rebuild({
    { from = 0, to = b, at = 0 },
    { from = a, to = b, at = b },
    { from = b, to = INF, at = b + b - a },
  })
  return S.at(b)
end

--- A section as a register value, with its marker.
function M.yank(which)
  local s = S.need(which)
  return M.yank_range(s.start, s.finish)
end

--- Remove a section from every track and close the gap. Returns what it
--- held, as `yank` does.
function M.delete(which)
  local s = S.need(which)
  local value = M.yank(s)
  M.rebuild({
    { from = 0, to = s.start, at = 0 },
    { from = s.finish, to = INF, at = s.start },
  })
  return value
end

--- Insert a register value at a beat on every track, pushing what follows
--- along. A value from `yank` or `delete` brings its sections and
--- automation; a plain "range" goes onto the tracks from the first down.
function M.insert(value, at)
  if not value or value.kind ~= "range" then error("nothing to insert: yank a section first", 0) end
  at = math.max(0, at)
  M.rebuild({
    { from = 0, to = at, at = 0 },
    { value = value, at = at },
    { from = at, to = INF, at = at + value.length },
  })
  return S.at(at)
end

--- Insert a copy of a section at a beat. Returns the copy.
function M.copy(which, at)
  return M.insert(M.yank(which), at)
end

return M
