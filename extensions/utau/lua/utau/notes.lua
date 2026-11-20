-- Editing what a vocal track sings: lyrics and properties on notes, and the
-- singing curves, which are automation lanes on the track's `utau` device.
-- Everything goes through `paw.api`, so each change is an ordinary edit.
local api = paw.api

local M = {}

local copy = paw.util.copy
M.copy = copy

--- The notes of a clip, in time order (the order the kernel keeps them in).
function M.list(clip_id)
  return api.clip_notes(clip_id)
end

--- Whether a lyric is a rest, which is not sung (UTAU's `R`).
function M.is_rest(lyric)
  return lyric == "R" or lyric == "r"
end

function M.lyric(note)
  return note.meta and note.meta.lyric or nil
end

--- Change some notes of a clip with `fn(note, index)`, which returns true for
--- each note it changed. One edit for all of them. Returns how many changed.
function M.change(clip_id, fn, which)
  local notes = api.clip_notes(clip_id)
  local changed = 0
  for index, note in ipairs(notes) do
    if not which or which[index] then
      note.meta = note.meta or {}
      if fn(note, index) then changed = changed + 1 end
      if next(note.meta) == nil then note.meta = nil end
    end
  end
  if changed > 0 then api.clip_set_notes(clip_id, notes) end
  return changed
end

--- Set the lyric of the note at `index`.
function M.set_lyric(clip_id, index, lyric)
  return M.change(clip_id, function(note)
    if note.meta.lyric == lyric then return false end
    note.meta.lyric = lyric ~= "" and lyric or nil
    return true
  end, { [index] = true })
end

--- Change the utau properties (`note.meta.utau`) of notes with `fn(props, note)`.
function M.change_props(clip_id, fn, which)
  return M.change(clip_id, function(note, index)
    local props = copy(note.meta.utau) or {}
    local changed = fn(props, note, index)
    if changed then note.meta.utau = next(props) and props or nil end
    return changed
  end, which)
end

--- The note at `pitch` covering `beat` (clip beats), and its index.
function M.at(clip_id, pitch, beat)
  for index, note in ipairs(api.clip_notes(clip_id)) do
    if note.pitch == pitch and beat >= note.start - 1e-9 and beat < note.start + note.length - 1e-9 then
      return note, index
    end
  end
end

--- The note sounding at `beat`, else the last one before it, and its index.
function M.near(clip_id, beat)
  local best, best_index
  for index, note in ipairs(api.clip_notes(clip_id)) do
    if note.start <= beat + 1e-9 then
      best, best_index = note, index
      if beat < note.start + note.length then return note, index end
    end
  end
  return best, best_index
end

--- `near` for a list of notes in hand, asked for beats that only go up:
--- a function of a beat. Drawing a roll asks once a column.
function M.walker(list)
  local j = 0
  return function(beat)
    while list[j + 1] and list[j + 1].start <= beat + 1e-9 do j = j + 1 end
    for k = j, math.max(1, j - 8), -1 do
      local n = list[k]
      if beat < n.start + n.length then return n, k end
    end
    return list[j], j > 0 and j or nil
  end
end

-- Curves ---------------------------------------------------------------------------

--- `value_at` for beats that only go up: a function of a beat.
function M.sampler(points, default)
  local i = 1
  return function(beat)
    if #points == 0 then return default end
    if beat <= points[1][1] then return points[1][2] end
    while points[i + 1] and points[i + 1][1] <= beat do i = i + 1 end
    local a, b = points[i], points[i + 1]
    if not b then return a[2] end
    if b[1] <= a[1] then return b[2] end
    return a[2] + (b[2] - a[2]) * (beat - a[1]) / (b[1] - a[1])
  end
end

--- The lane of a curve on a vocal device, made when `create` is set.
function M.lane(track_id, device_id, abbr, create)
  for _, lane in ipairs(api.lane_list(track_id)) do
    if lane.target == "param" and lane.device == device_id and lane.param == abbr then return lane.id end
  end
  if create then return api.lane_add(track_id, { target = "param", device = device_id, param = abbr }) end
end

--- The value of a list of `{ beat, value }` points at a beat, as lanes join them.
function M.value_at(points, beat, default)
  if #points == 0 then return default end
  if beat <= points[1][1] then return points[1][2] end
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    if beat < b[1] then
      if b[1] <= a[1] then return b[2] end
      return a[2] + (b[2] - a[2]) * (beat - a[1]) / (b[1] - a[1])
    end
  end
  return points[#points][2]
end

--- The default of a curve, from the device's parameter.
function M.default(device_id, abbr)
  for _, info in ipairs(api.device_get(device_id).param_info) do
    if info.key == abbr then return info.default, info.min, info.max end
  end
  return 0, -1e9, 1e9
end

--- The value of a curve at an absolute beat.
function M.curve_at(track_id, device_id, abbr, beat)
  local lane = M.lane(track_id, device_id, abbr)
  local default = M.default(device_id, abbr)
  if not lane then return api.device_get(device_id).params[abbr] or default end
  return M.value_at(api.lane_points(lane), beat, default)
end

--- Write `samples` (`{ beat, value }`, absolute beats, sorted) into a curve,
--- replacing what was between the first and the last and leaving the curve
--- as it was on either side.
function M.stroke(track_id, device_id, abbr, samples)
  if #samples == 0 then return end
  local default, min, max = M.default(device_id, abbr)
  local lane = M.lane(track_id, device_id, abbr, true)
  local points = api.lane_points(lane)
  local from, to = samples[1][1], samples[#samples][1]
  local edge = 1 / 960
  local out = {}
  for _, p in ipairs(points) do
    if p[1] < from - 1e-9 or p[1] > to + 1e-9 then out[#out + 1] = p end
  end
  local before, after = M.value_at(points, from - edge, default), M.value_at(points, to + edge, default)
  if from - edge >= 0 then out[#out + 1] = { from - edge, before } end
  out[#out + 1] = { to + edge, after }
  for _, s in ipairs(samples) do
    out[#out + 1] = { s[1], math.max(min, math.min(max, s[2])) }
  end
  table.sort(out, function(a, b) return a[1] < b[1] end)
  api.lane_set_points(lane, out)
end

--- Bend a curve by `delta` at a beat, as a peak `width` beats wide each way.
function M.bend(track_id, device_id, abbr, beat, delta, width)
  local default, min, max = M.default(device_id, abbr)
  local lane = M.lane(track_id, device_id, abbr, true)
  local points = api.lane_points(lane)
  local around = {}
  for _, b in ipairs({ beat - width, beat + width }) do
    local exists = false
    for _, p in ipairs(points) do
      if math.abs(p[1] - b) < 1e-9 then exists = true end
    end
    if b >= 0 and not exists then around[#around + 1] = { b, M.value_at(points, b, default) } end
  end
  local value = math.max(min, math.min(max, M.value_at(points, beat, default) + delta))
  local out = {}
  for _, p in ipairs(points) do
    if math.abs(p[1] - beat) > 1e-9 then out[#out + 1] = p end
  end
  for _, p in ipairs(around) do out[#out + 1] = p end
  out[#out + 1] = { beat, value }
  table.sort(out, function(a, b) return a[1] < b[1] end)
  api.lane_set_points(lane, out)
  return value
end

--- Put a curve back to its default between two absolute beats.
function M.reset(track_id, device_id, abbr, from, to)
  local lane = M.lane(track_id, device_id, abbr)
  if not lane then return end
  local default = M.default(device_id, abbr)
  M.stroke(track_id, device_id, abbr, { { from, default }, { to, default } })
end

return M
