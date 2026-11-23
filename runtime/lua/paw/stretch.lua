-- Stretching, pitch shifting and looping clips: `paw.stretch`.
--
-- An audio clip plays its file `clip.stretch` times as long (2 is half
-- speed) and `clip.pitch` semitones higher, each without changing the
-- other. The stretched sound is made once, apart, and played when it is
-- ready; until then the clip is silent and says so (`clip.stretching`).
-- `clip.offset` stays in seconds of the file, so a second of the clip is
-- `1 / stretch` seconds of the file (`M.file_seconds`), unless warp
-- markers stretch its parts differently (`M.warp_add`): each is a moment
-- of the file pinned to a place in the clip, `{ source, target, beat }`
-- in `clip.warp`, and moving one stretches the sound between it and its
-- neighbours alone. The sound is made a part at a time, from its start,
-- and plays as far as it is made: a long file is heard at once.
--
-- A clip in the "stretch" timebase keeps its start and its length on their
-- beats when the tempo changes: its stretch follows, from the tempo its
-- sound is at (`clip.source_tempo`, which recordings know).
--
-- Any clip can loop (`clip.repeat`): it repeats what it plays from
-- `clip.loop_start` (beats from its start, 0 or less) for
-- `clip.loop_length` beats, again and again to its end. Trimming its start
-- turns the loop round rather than running out of it; a cut gives both
-- pieces the same loop, each from where it begins.
local api = paw.api
local M = {}

local EPS = 1e-9

--- A clip's warp markers as a map from its file's seconds to its seconds
--- before its stretch: through each marker, at the file's own speed past
--- the first and the last. With `back`, the other way.
local function unstretched(warp, x, back)
  local from, to = "source", "target"
  if back then
    from, to = to, from
  end
  local n = #warp
  if x <= warp[1][from] then return warp[1][to] + x - warp[1][from] end
  for i = 2, n do
    local a, b = warp[i - 1], warp[i]
    if x <= b[from] then return a[to] + (x - a[from]) * (b[to] - a[to]) / (b[from] - a[from]) end
  end
  return warp[n][to] + x - warp[n][from]
end

--- The time in the file of an audio clip that plays `by` beats after its
--- start. It obeys the stretch, the warp markers and the bend of the clip
--- along the tempo (`clip.bent`, when it follows a tempo that changes in it).
function M.file_at(c, by)
  local warp = c.warp or {}
  if #warp == 0 and not c.bent then return c.offset + paw.time.seconds(by, c.start) / (c.stretch or 1) end
  local played = c.bent and by * 60 / c.source_tempo or paw.time.seconds(by, c.start) / (c.stretch or 1)
  if #warp == 0 then return c.offset + played end
  return unstretched(warp, unstretched(warp, c.offset) + played, true)
end

--- Seconds of an audio clip's file that `beats` beats of it from beat `at`
--- (its start when left out) play.
function M.file_seconds(c, beats, at)
  if #(c.warp or {}) == 0 and not c.bent then return paw.time.seconds(beats, at or c.start) / (c.stretch or 1) end
  local from = (at or c.start) - c.start
  return M.file_at(c, from + beats) - M.file_at(c, from)
end

--- The seconds of its file that an audio clip would play before its start,
--- if it were longer at the start. This is the part of the first `offset`
--- seconds of the file that plays.
function M.lead(c)
  local warp = c.warp or {}
  local u = #warp > 0 and unstretched(warp, c.offset) - unstretched(warp, 0) or c.offset
  if c.bent then
    local beats = u * c.source_tempo / 60
    return paw.time.seconds(beats, c.start - beats)
  end
  return u * (c.stretch or 1)
end

--- The play position of a clip after its start moves `by` beats later
--- (earlier below 0), while its sound stays at the same time. For sound,
--- it is `offset`. For a looped clip, it is also `loop_start`, kept in one
--- repeat. `shift` is how far its notes move (counted from the new start).
function M.moved(c, by)
  local out = { shift = -by }
  local turns = 0
  if c.loop and c.loop_length then
    local ls = (c.loop_start or 0) - by
    turns = math.floor(-ls / c.loop_length + EPS)
    out.loop_start = ls + turns * c.loop_length
    out.shift = out.shift + turns * c.loop_length
  end
  if c.kind == "audio" then
    out.offset = math.max(0, c.offset + M.file_seconds(c, by - turns * (c.loop_length or 0)))
  end
  return out
end

--- Move what a looped clip plays as `M.moved` says, in the project: its
--- offset or notes (and other takes' notes), and where its loop begins.
function M.move_content(id, by)
  local c = api.clip_get(id)
  local m = M.moved(c, by)
  if c.kind == "audio" then
    api.clip_set(id, "offset", m.offset)
  elseif math.abs(m.shift) > EPS then
    local notes = api.clip_notes(id)
    for _, n in ipairs(notes) do
      n.start = n.start + m.shift
    end
    api.clip_set_notes(id, notes)
    if c.control_count > 0 then
      local controls = api.clip_controls(id)
      for _, move in ipairs(controls) do
        move.start = move.start + m.shift
      end
      api.clip_set_controls(id, controls)
    end
    paw.takes.shift(id, m.shift)
  end
  if m.loop_start then api.clip_set(id, "loop_start", m.loop_start) end
end

--- Give `snap` the playback values of `c`. `snap` is the snapshot of a
--- piece of clip `c` that starts `by` beats into it. The values are its
--- stretch, shift and timebase, and its loop from the start of the piece.
--- Returns `M.moved(c, by)`.
function M.carry(c, snap, by)
  local m = M.moved(c, by)
  if c.kind == "audio" then
    snap.timebase, snap.stretch, snap.pitch = c.timebase, c.stretch, c.pitch
    snap.stretch_mode, snap.source_tempo = c.stretch_mode, c.source_tempo
    snap.warp, snap.formants = M.markers(c), c.formants or nil
  end
  snap.loop, snap.loop_length = c.loop or nil, c.loop_length
  snap.loop_start = m.loop_start or c.loop_start
  return m
end

local function need_audio(c)
  if c.kind ~= "audio" then error("only audio clips are stretched or shifted", 3) end
end

--- Make what a clip plays `k` times as long: its length, fades and loop
--- with it, from its start. With `set`, its stretch too.
local function scale(c, k, set)
  if set then api.clip_set(c.id, "stretch", c.stretch * k) end
  local seconds = paw.time.seconds(c.length, c.start) * k
  local length = paw.time.to_beat(paw.time.to_seconds(c.start) + seconds) - c.start
  api.clip_set(c.id, "length", length)
  local ratio = length / c.length
  api.clip_set(c.id, "fade_in", math.min(c.fade_in * ratio, length))
  api.clip_set(c.id, "fade_out", math.min(c.fade_out * ratio, length))
  if c.loop_length then
    api.clip_set(c.id, "loop_length", c.loop_length * ratio)
    api.clip_set(c.id, "loop_start", (c.loop_start or 0) * ratio)
  end
end

--- Stretch an audio clip to play its file `ratio` times as long, with the
--- same sound. It becomes longer or shorter from its start by the same ratio.
function M.set(id, ratio)
  local c = api.clip_get(id)
  need_audio(c)
  if math.abs(ratio - c.stretch) > EPS then scale(c, ratio / c.stretch, true) end
end

--- Stretch an audio clip. Its current sound then lasts `beats` beats.
function M.to(id, beats)
  local c = api.clip_get(id)
  need_audio(c)
  if beats <= 0 then error("a clip lasts more than 0 beats", 2) end
  local k = paw.time.seconds(beats, c.start) / paw.time.seconds(c.length, c.start)
  scale(c, k, true)
end

--- Stretch an audio clip over beats `from` to `to`. It starts at `from`,
--- continues until `to`, and plays its current sound.
function M.fit(id, from, to)
  api.clip_set(id, "start", math.max(0, from))
  M.to(id, to - from)
end

--- Play an audio clip's file at its own speed again, at its own length,
--- without warp markers.
function M.reset(id)
  if #(api.clip_get(id).warp or {}) > 0 then api.clip_set(id, "warp", {}) end
  M.set(id, 1)
end

--- A clip's warp markers as they are saved (`{ source, target }` each),
--- nil for none.
function M.markers(c)
  if #(c.warp or {}) == 0 then return nil end
  local out = {}
  for i, m in ipairs(c.warp) do
    out[i] = { source = m.source, target = m.target }
  end
  return out
end

--- Put a warp marker on an audio clip at `beat`. It pins the time of its
--- file that plays there (nothing moves). Returns its index.
function M.warp_add(id, beat)
  need_audio(api.clip_get(id))
  return api.clip_warp_add(id, beat)
end

--- Move warp marker `index` of a clip to play at `beat`. The sound between
--- it and the markers next to it stretches, and the start and the end of
--- the clip do not move. The stretch on each side stays between 0.25 and 4.
--- Returns its index, which can be different.
function M.warp_move(id, index, beat) return api.clip_warp_move(id, index, beat) end

--- Take warp marker `index` off a clip.
function M.warp_remove(id, index) api.clip_warp_remove(id, index) end

--- The index of a clip's warp marker nearest `beat`, and how far it is.
function M.warp_near(c, beat)
  local best, dist
  for i, m in ipairs(c.warp or {}) do
    local d = math.abs(m.beat - beat)
    if not dist or d < dist then
      best, dist = i, d
    end
  end
  return best, dist
end

--- Move every warp marker of a clip onto the nearest line of a grid of
--- `step` beats (`paw.timegrid.step()` when left out), from the first on.
function M.warp_snap(id, step)
  step = step or paw.timegrid.step()
  local n = #(api.clip_get(id).warp or {})
  local i = 1
  while i <= n do
    local m = api.clip_get(id).warp[i]
    local to = math.floor(m.beat / step + 0.5) * step
    i = M.warp_move(id, i, to) + 1
    n = #api.clip_get(id).warp
  end
end

--- Shift an audio clip's pitch to `semitones` (fractions allowed) above its file's.
function M.pitch(id, semitones)
  need_audio(api.clip_get(id))
  api.clip_set(id, "pitch", semitones)
end

--- Make an audio clip follow the tempo, with its sound at `bpm`. If `bpm`
--- is not given, it is the tempo at the start of the clip, for its current
--- stretch. With `bpm` false, the clip keeps its time again. Its length
--- changes with its stretch, so it plays the same sound.
function M.follow(id, bpm)
  local c = api.clip_get(id)
  need_audio(c)
  if bpm == false then return api.clip_set(id, "timebase", "time") end
  api.clip_set(id, "timebase", "stretch")
  if bpm then
    api.clip_set(id, "source_tempo", bpm)
    local now = api.clip_get(id).stretch
    if math.abs(now - c.stretch) > EPS then scale(c, now / c.stretch, false) end
  end
end

--- Loop a clip (`on` true), or stop its loop (false). `beats`, when given,
--- is the length of the part that repeats.
function M.loop(id, on, beats)
  if beats then api.clip_set(id, "loop_length", beats) end
  api.clip_set(id, "loop", on)
end

--- Where a looped clip's repeats begin, in beats from its start, past the
--- first: where its notches are drawn. At most `limit` (256) of them.
function M.repeats(c, limit)
  local out = {}
  if not (c.loop and c.loop_length and c.loop_length > EPS) then return out end
  local at = (c.loop_start or 0) % c.loop_length
  if at < EPS then at = c.loop_length end
  while at < c.length - EPS and #out < (limit or 256) do
    out[#out + 1] = at
    at = at + c.loop_length
  end
  return out
end

--- The `notes` of a MIDI clip as they sound, counted from its start. For a
--- looped clip, these are the notes of its repeated range again and again,
--- each cut at the end of its repeat. At most `limit` of them.
function M.sounding(c, notes, limit)
  if not (c.loop and c.loop_length and c.loop_length > EPS) then return notes end
  local out, period, from = {}, c.loop_length, c.loop_start or 0
  local base = from % period
  base = base > EPS and base - period or 0
  while base < c.length - EPS and #out < (limit or math.huge) do
    for _, n in ipairs(notes) do
      if n.start >= from - EPS and n.start < from + period - EPS then
        local at = base + n.start - from
        if at >= -EPS and at < c.length - EPS and #out < (limit or math.huge) then
          local note = paw.util.merge(n, { start = at, length = math.min(n.length, base + period - at) })
          out[#out + 1] = note
        end
      end
    end
    base = base + period
  end
  table.sort(out, function(a, b) return a.start < b.start end)
  return out
end

--- The stretch, shift and loop of a clip in a few characters, for its
--- label: "×1.5 +3st ↻". `stretching…` shows while paw makes its sound. Nil
--- for a clip with none of these.
function M.badge(c)
  local ascii = paw.opt.ascii
  local parts = {}
  if c.stretching then parts[#parts + 1] = ascii and "stretching~" or "stretching…" end
  if c.stretch and math.abs(c.stretch - 1) > EPS then
    parts[#parts + 1] = string.format(ascii and "x%.3g" or "×%.3g", c.stretch)
  end
  if c.pitch and math.abs(c.pitch) > EPS then parts[#parts + 1] = string.format("%+.3gst", c.pitch) end
  -- Following the tempo, and looping.
  if c.timebase == "stretch" then parts[#parts + 1] = ascii and "bpm" or "♩" end
  if c.loop then parts[#parts + 1] = ascii and "loop" or "↻" end
  return #parts > 0 and table.concat(parts, " ") or nil
end

return M
