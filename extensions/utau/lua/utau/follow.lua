-- The curves under a vocal clip go where the clip goes.
--
-- Curves are automation lanes on the parameters of the part's `utau` device
-- (see utau.notes), so they belong to the part's timeline, not to the clip.
-- This module answers every clip edit on a vocal part, inside the edit's
-- undo step, by moving the curves along:
--
--   * a clip moved, on its part or to another vocal part: the curves
--     under it move with it, and the place it left is cleared;
--   * a clip copied, duplicated or pasted: the copy gets the curves of the
--     clip it is a copy of;
--   * a clip deleted, or moved off the vocal parts: its curves go, and are
--     kept for this session, so pasting the clip back brings them;
--   * a clip split, trimmed or lengthened: nothing moves.
--
-- A copy knows its original by `clip.meta.utau_clip`, the id of the clip it
-- was made from: every vocal clip carries its own id there, and the core
-- copies a clip's meta with whole-clip copies. A copy of a clip that has no
-- such mark yet is recognised by having the same notes and length.
--
-- Changes the core reports as `restored` (undo, redo, opening a project)
-- already hold the curves where they belong; they are only taken note of.
local api = paw.api
local notes = require("utau.notes")

local M = {
  known = {}, -- clip id -> { id, part, start, length, stamp, notes } as of the last turn
  kept = {}, -- clip id -> a segment, for clips that left the vocal parts
}

local EPS = 1e-9
local EDGE = 1 / 960 -- half an OpenUtau tick: where a written stretch meets the rest

local function utau() return package.loaded["utau"] or require("utau") end

--- The curve parameters of a vocal device: every parameter but `voice`.
function M.params(device)
  local out = {}
  for _, info in ipairs(api.device_get(device).param_info) do
    if info.key ~= "voice" then out[#out + 1] = info end
  end
  return out
end

--- The MIDI clips of every vocal part, by id.
local function scan()
  local out = {}
  for _, vocal in ipairs(utau().vocal_parts()) do
    for _, c in ipairs(api.clip_list(vocal.part)) do
      if c.kind == "midi" then
        out[c.id] = {
          id = c.id,
          part = vocal.part,
          device = vocal.device,
          start = c.start,
          length = c.length,
          stamp = c.stamp,
          notes = c.note_count or 0,
          mark = type(c.meta) == "table" and tonumber(c.meta.utau_clip) or nil,
        }
      end
    end
  end
  return out
end

local function part_exists(id) return id and pcall(api.part_get, id) end

local function lanes_of(part, device)
  local out = {}
  if not part_exists(part) then return out end
  for _, lane in ipairs(api.lane_list(part)) do
    if lane.target == "param" and lane.device == device then out[lane.param] = lane.id end
  end
  return out
end

--- What a curve holds at a beat: its lane's points, else the parameter.
local function held(points, beat, value)
  if not points or #points == 0 then return value end
  return notes.value_at(points, beat, value)
end

--- The curves between two beats of a vocal part, relative to `from`:
--- `{ from, length, curves = { abbr = { constant = v } or { points = ... } } }`.
function M.extract(part, device, from, length)
  local seg = { from = from, length = length, curves = {} }
  if not (part_exists(part) and device and pcall(api.device_get, device)) then return seg end
  local lanes = lanes_of(part, device)
  local params = api.device_get(device).params
  for _, info in ipairs(M.params(device)) do
    local value = params[info.key] or info.default
    local lane = lanes[info.key]
    local points = lane and api.lane_points(lane) or {}
    if #points == 0 then
      seg.curves[info.key] = { constant = value }
    else
      local to = from + length
      local out = { { 0, held(points, from, value) } }
      for _, p in ipairs(points) do
        if p[1] > from + EPS and p[1] < to - EPS then out[#out + 1] = { p[1] - from, p[2] } end
      end
      -- Both ends as the engine reads them for the clip (utau.snapshot).
      out[#out + 1] = { length, held(points, to, value) }
      seg.curves[info.key] = { points = out }
    end
  end
  return seg
end

--- Set a stretch of a lane to `fill` points (absolute beats), keeping the
--- curve exactly as it was outside `from - EDGE` .. `to + EDGE`. With no
--- `fill` the stretch becomes a straight line between its edges.
local function splice(lane, value, from, to, fill)
  local points = api.lane_points(lane)
  local before, after = held(points, from - EDGE, value), held(points, to + EDGE, value)
  local out = {}
  for _, p in ipairs(points) do
    if p[1] < from - EDGE - EPS or p[1] > to + EDGE + EPS then out[#out + 1] = p end
  end
  if from - EDGE >= 0 then out[#out + 1] = { from - EDGE, before } end
  for _, p in ipairs(fill or {}) do
    out[#out + 1] = p
  end
  out[#out + 1] = { to + EDGE, after }
  table.sort(out, function(a, b) return a[1] < b[1] end)
  api.lane_set_points(lane, out)
end

--- Whether a lane already holds a segment's curve over a stretch.
local function same(points, value, from, curve)
  local list = curve.points or { { 0, curve.constant } }
  for _, p in ipairs(list) do
    if math.abs(held(points, from + p[1], value) - p[2]) > 1e-6 then return false end
  end
  for _, p in ipairs(points) do
    local rel = p[1] - from
    if rel > EPS and rel < (list[#list][1] - EPS) then
      local want = curve.constant or notes.value_at(list, rel, 0)
      if math.abs(p[2] - want) > 1e-6 then return false end
    end
  end
  return true
end

--- Write a segment's curves onto a vocal part from `at`, over `length` beats.
function M.write(part, device, seg, at, length)
  if not (part_exists(part) and device) then return end
  length = length or seg.length
  local lanes = lanes_of(part, device)
  local params = api.device_get(device).params
  for _, info in ipairs(M.params(device)) do
    local curve = seg.curves[info.key]
    local value = params[info.key] or info.default
    local lane = lanes[info.key]
    local points = lane and api.lane_points(lane) or {}
    if
      curve
      and not (curve.constant and #points == 0 and math.abs(curve.constant - value) < 1e-9)
      and not same(points, value, at, curve)
    then
      lane = lane or notes.lane(part, device, info.key, true)
      local fill = {}
      if curve.constant then
        fill[1], fill[2] = { at, curve.constant }, { at + length, curve.constant }
      else
        for _, p in ipairs(curve.points) do
          if p[1] <= length + EPS then fill[#fill + 1] = { at + p[1], p[2] } end
        end
        if curve.points[#curve.points][1] > length + EPS then
          fill[#fill + 1] = { at + length, notes.value_at(curve.points, length, value) }
        end
      end
      splice(lane, value, at, at + length, fill)
    end
  end
end

--- Clear the curves of a vocal part between two beats: each becomes a
--- straight line between what is on either side.
function M.clear(part, device, from, to)
  if not part_exists(part) then return end
  local params = api.device_get(device).params
  for _, info in ipairs(M.params(device)) do
    local lane = lanes_of(part, device)[info.key]
    if lane and api.lane_get(lane).point_count > 0 then splice(lane, params[info.key] or info.default, from, to) end
  end
end

--- The stretches of `from`..`to` that no clip of `others` on `part` covers.
local function uncovered(part, from, to, others)
  local spans = { { from, to } }
  for _, c in pairs(others) do
    if c.part == part then
      local next_spans = {}
      for _, s in ipairs(spans) do
        local a, b = c.start, c.start + c.length
        if b <= s[1] + EPS or a >= s[2] - EPS then
          next_spans[#next_spans + 1] = s
        else
          if a > s[1] + EPS then next_spans[#next_spans + 1] = { s[1], a } end
          if b < s[2] - EPS then next_spans[#next_spans + 1] = { b, s[2] } end
        end
      end
      spans = next_spans
    end
  end
  return spans
end

--- How far a clip's content moved: the clip's own move, unless only its
--- left edge did (a trim, which leaves the notes where they were).
local function shift(old, new)
  local by = new.start - old.start
  if math.abs(by) < EPS then return 0 end
  if math.abs(new.length - old.length) > EPS then return 0 end
  return by
end

--- Take note of where every vocal clip is, without changing anything.
function M.refresh() M.known = scan() end

local busy = false

--- Bring the curves after the clip edits made since the last turn.
function M.follow()
  if busy then return end
  busy = true
  local ok, err = pcall(function()
    local now = scan()
    local moves, gone, copies, marks = {}, {}, {}, {}
    for id, old in pairs(M.known) do
      local new = now[id]
      if not new then
        gone[#gone + 1] = old
      else
        local by = shift(old, new)
        if new.part ~= old.part or by ~= 0 then moves[#moves + 1] = { old = old, new = new, by = by } end
      end
    end
    for id, new in pairs(now) do
      if not M.known[id] then
        local source = new.mark and new.mark ~= id and new.mark or nil
        if not source and not new.mark and new.notes > 0 then
          -- A copy of a clip that had no mark: the same notes and length.
          for _, old in pairs(M.known) do
            if old.stamp == new.stamp and math.abs(old.length - new.length) < EPS and old.notes == new.notes then
              source = old.id
              break
            end
          end
        end
        if source or (new.mark == id and M.kept[id]) then copies[#copies + 1] = { new = new, source = source or id } end
      end
      if new.mark ~= id then marks[#marks + 1] = new end
    end

    -- Everything is read before anything is written, so that clips that
    -- trade places take their own curves.
    for _, m in ipairs(moves) do
      m.seg = M.extract(m.old.part, m.old.device, m.old.start, m.old.length)
    end
    for _, old in ipairs(gone) do
      local seg = M.extract(old.part, old.device, old.start, old.length)
      if next(seg.curves) then M.kept[old.id] = seg end
    end
    for _, c in ipairs(copies) do
      local src = M.known[c.source]
      if src and now[c.source] then
        c.seg = M.extract(src.part, src.device, src.start, src.length)
      else
        c.seg = M.kept[c.source]
      end
    end

    -- Clear where clips were, except under clips that are there now.
    local function vacate(old)
      if not M.known[old.id] then return end
      for _, span in ipairs(uncovered(old.part, old.start, old.start + old.length, now)) do
        if span[2] - span[1] > EPS and part_exists(old.part) and utau().device_of(old.part) == old.device then
          M.clear(old.part, old.device, span[1], span[2])
        end
      end
    end
    for _, m in ipairs(moves) do
      vacate(m.old)
    end
    for _, old in ipairs(gone) do
      vacate(old)
    end

    for _, m in ipairs(moves) do
      M.write(m.new.part, m.new.device, m.seg, m.old.start + m.by, m.old.length)
      M.kept[m.new.id] = nil
    end
    for _, c in ipairs(copies) do
      if c.seg then M.write(c.new.part, c.new.device, c.seg, c.new.start, math.min(c.seg.length, c.new.length)) end
      if c.source == c.new.id then M.kept[c.new.id] = nil end
    end
    for _, c in ipairs(marks) do
      local meta = api.clip_get(c.id).meta
      if type(meta) ~= "table" then meta = {} end
      meta.utau_clip = c.id
      api.clip_set(c.id, "meta", meta)
    end
    M.known = scan()
  end)
  busy = false
  if not ok then error(err, 0) end
end

function M.attach()
  if M.attached then return end
  M.attached = true
  local function on_change(event)
    if event and event.restored then return M.refresh() end
    M.follow()
  end
  paw.on("clip.*", on_change)
  paw.on("part.*", on_change)
  paw.on("device.*", on_change)
  paw.on("project.loaded", function()
    M.kept = {}
    M.refresh()
  end)
  M.refresh()
end

return M
