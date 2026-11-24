-- Editing a clip through a drum map: what the keys of the terminal grid and
-- the pointer in the window both do. Everything is plain calls on clips, and
-- each function is one edit, so one undo step.
--
-- A hit is a note. It sits in the cell of its row whose step it starts in;
-- rows are the places in a list from `drums.rows`, and a region from
-- `paw.keymap` has rows `r0` to `r1` in that list and beats `c0` up to `c1`
-- from the start of the clip: "char" is a stretch of time on every row,
-- "block" only on some rows, "line" whole rows.
local util = paw.util
local drums = require("drums")
local EPS = 1e-6

local E = {}

--- The steps a grid can have, as `{ beats, label }`, coarse to fine.
E.steps = {
  { 1, "1/4" },
  { 1 / 2, "1/8" },
  { 1 / 3, "1/8T" },
  { 1 / 4, "1/16" },
  { 1 / 6, "1/16T" },
  { 1 / 8, "1/32" },
  { 1 / 12, "1/32T" },
}

function E.step_label(step)
  for _, s in ipairs(E.steps) do
    if math.abs(s[1] - step) < EPS then return s[2] end
  end
  return string.format("%g", step)
end

--- Whether a step is a triplet one, and the step it is a triplet of or has.
local triplet_of = { [2] = 3, [4] = 6, [8] = 12 }
function E.toggle_triplet(step)
  local per = math.floor(1 / step + 0.5)
  if triplet_of[per] then return 1 / triplet_of[per] end
  for straight, tri in pairs(triplet_of) do
    if tri == per then return 1 / straight end
  end
  return step
end

--- The next finer (`dir` 1) or coarser (-1) step, staying straight or triplet.
function E.next_step(step, dir)
  local tri = math.floor(1 / step + 0.5) % 3 == 0
  local list = {}
  for _, s in ipairs(E.steps) do
    if (math.floor(1 / s[1] + 0.5) % 3 == 0) == tri then list[#list + 1] = s[1] end
  end
  for i, s in ipairs(list) do
    if math.abs(s - step) < EPS then return list[util.clamp(i + dir, 1, #list)] end
  end
  return step
end

local function clip_of(clip)
  if type(clip) == "number" then return paw.clip(clip) end
  return clip
end

--- The cell a beat falls in.
function E.cell(beat, step) return math.floor(beat / step + EPS) end

--- The hit of a pitch in the step that starts at `beat`: the note and its
--- place among the clip's notes.
function E.hit(clip, pitch, beat, step)
  clip = clip_of(clip)
  local found, at = clip:notes({ from = beat - EPS, to = beat + step - EPS, low = pitch, high = pitch })
  for i, n in ipairs(found) do
    if n.start >= beat - EPS and n.start < beat + step - EPS then return n, at[i] end
  end
end

--- A hit's length: a step, but never past the end of the clip.
local function hit_length(clip, beat, step) return math.max(EPS * 10, math.min(step, clip.length - beat)) end

--- Put a hit in, or take it out. `on` nil toggles. Returns whether there is
--- a hit there afterwards.
function E.set(clip, pitch, beat, step, on, velocity)
  clip = clip_of(clip)
  local note, index = E.hit(clip, pitch, beat, step)
  if on == nil then on = not note end
  if on and not note then
    if beat >= clip.length - EPS then return false end
    clip:add_note({
      pitch = pitch,
      start = beat,
      length = hit_length(clip, beat, step),
      velocity = drums.clamp_velocity(velocity or paw.opt.drums_velocity),
    })
  elseif not on and note then
    clip:remove_note(index)
  elseif on and note and velocity and note.velocity ~= velocity then
    clip:set_note(index, { velocity = drums.clamp_velocity(velocity) })
  end
  return on
end

--- Change how hard a hit is by `by`, or set it with `to`. Returns the new
--- velocity, or nil when there is no hit there.
function E.velocity(clip, pitch, beat, step, by, to)
  clip = clip_of(clip)
  local note, index = E.hit(clip, pitch, beat, step)
  if not note then return nil end
  local v = drums.clamp_velocity(to or note.velocity + (by or 0))
  if v ~= note.velocity then clip:set_note(index, { velocity = v }) end
  return v
end

--- The pitches of rows `r0` to `r1` of a list of rows.
local function pitches(rows, r0, r1)
  local set = {}
  for r = math.max(1, r0), math.min(#rows, r1) do
    set[rows[r].note] = r
  end
  return set
end

--- The notes of a region, with their places in the clip, and the row of each.
function E.notes(clip, rows, region)
  clip = clip_of(clip)
  local of_row = region.kind ~= "char" and pitches(rows, region.r0, region.r1) or nil
  local row_of = pitches(rows, 1, #rows)
  local notes, places, in_rows = {}, {}, {}
  for i, n in ipairs(clip:notes()) do
    local time = region.kind == "line" or (n.start >= region.c0 - EPS and n.start < region.c1 - EPS)
    if time and (not of_row or of_row[n.pitch]) then
      notes[#notes + 1], places[#places + 1], in_rows[#in_rows + 1] = n, i, row_of[n.pitch]
    end
  end
  return notes, places, in_rows
end

--- A region as a value for a register. Hits keep their pitch and how far
--- their row is from the region's first row, so that a block pasted on
--- other rows lands on those rows.
function E.yank(clip, rows, region)
  local notes, _, in_rows = E.notes(clip, rows, region)
  local out = {}
  for i, n in ipairs(notes) do
    out[i] = util.merge(n, {
      start = region.kind == "line" and n.start or n.start - region.c0,
      row = in_rows[i] and in_rows[i] - region.r0 or nil,
    })
  end
  return { kind = "drums", shape = region.kind, length = region.c1 - region.c0, notes = out }
end

--- Remove a region's hits and return them, for a register.
function E.delete(clip, rows, region)
  clip = clip_of(clip)
  local value = E.yank(clip, rows, region)
  local _, places = E.notes(clip, rows, region)
  if #places > 0 then clip:edit_notes({ remove = places }) end
  return value
end

--- Change every hit of a region with `fn(note)`.
function E.each(clip, rows, region, fn)
  clip = clip_of(clip)
  local notes, places = E.notes(clip, rows, region)
  local set = {}
  for i, n in ipairs(notes) do
    fn(n)
    set[i] = {
      index = places[i],
      start = n.start,
      length = n.length,
      pitch = n.pitch,
      velocity = n.velocity,
      meta = n.meta or {},
    }
  end
  if #set > 0 then clip:edit_notes({ set = set }) end
  return #set
end

--- Put a register's hits in a clip at a beat, with the first row of a block
--- at `row`. A stretch of time keeps its pitches; a piano roll's notes paste
--- the same way. Hits already in the cells pasted over give way, and the
--- clip grows a bar at a time if they reach past its end. Returns where the
--- pasted stretch ends.
function E.paste(clip, rows, value, row, beat, step)
  clip = clip_of(clip)
  if not value then return paw.notify("nothing to paste yet", "warn") end
  if value.kind ~= "drums" and value.kind ~= "notes" then
    return paw.notify("that register holds " .. tostring(value.kind) .. ", not hits", "warn")
  end
  local add, finish = {}, beat
  for _, n in ipairs(value.notes) do
    local note = {
      pitch = n.pitch,
      start = n.start,
      length = n.length,
      velocity = n.velocity,
      lyric = n.lyric,
      meta = n.meta,
      attr = n.attr,
    }
    if value.shape ~= "line" then note.start = beat + n.start end
    if value.kind == "drums" and value.shape ~= "char" and n.row then
      local target = rows[row + n.row]
      note.pitch = target and target.note or nil
    end
    if note.pitch then
      add[#add + 1] = note
      finish = math.max(finish, note.start + math.min(note.length, step))
    end
  end
  if value.shape ~= "line" then finish = math.max(finish, beat + (value.length or 0)) end
  local remove, taken = {}, {}
  for _, new in ipairs(add) do
    taken[new.pitch .. ":" .. E.cell(new.start, step)] = true
  end
  for index, old in ipairs(clip:notes()) do
    if taken[old.pitch .. ":" .. E.cell(old.start, step)] then remove[#remove + 1] = index end
  end
  local bar = paw.time.bar()
  if finish > clip.length + EPS then clip.length = math.ceil((finish - EPS) / bar) * bar end
  if #add > 0 or #remove > 0 then clip:edit_notes({ remove = remove, add = add }) end
  return value.shape == "line" and beat or finish
end

--- Copy the bar that `beat` is in over the bars after it: `times` bars, or
--- to the end of the clip when nil. The clip grows to hold them.
function E.repeat_bar(clip, beat, times)
  clip = clip_of(clip)
  local bar = paw.time.bar()
  local b0 = math.floor(beat / bar + EPS) * bar
  local last = times and b0 + bar * (times + 1) or math.max(b0 + bar, math.ceil(clip.length / bar - EPS) * bar)
  if last <= b0 + bar + EPS then last = b0 + 2 * bar end
  local source, remove, add = {}, {}, {}
  for index, n in ipairs(clip:notes()) do
    if n.start >= b0 - EPS and n.start < b0 + bar - EPS then
      source[#source + 1] = n
    elseif n.start >= b0 + bar - EPS and n.start < last - EPS then
      remove[#remove + 1] = index
    end
  end
  for at = b0 + bar, last - bar + EPS, bar do
    for _, n in ipairs(source) do
      add[#add + 1] = util.merge(n, { start = n.start - b0 + at })
    end
  end
  if last > clip.length + EPS then clip.length = last end
  clip:edit_notes({ remove = remove, add = add })
  return (last - b0) / bar - 1
end

--- Move the hits of a region by `steps` steps; never before the clip's start.
function E.shift(clip, rows, region, by)
  return E.each(clip, rows, region, function(n) n.start = math.max(0, n.start + by) end)
end

--- Swing: every other step of a region comes later by `amount` of a step
--- (0.33 is a triplet feel; 0 puts them back on the grid). Hits are counted
--- from the start of the clip, and only those on the grid or swung already
--- are moved, so swinging twice does not add up.
function E.swing(clip, rows, region, amount, step)
  local by = util.clamp(amount, 0, 0.75) * step
  return E.each(clip, rows, region, function(n)
    local pair = math.floor(n.start / (2 * step) + EPS)
    local offbeat = pair * 2 * step + step
    local within = n.start - offbeat
    if within > -EPS and within < 0.75 * step + EPS then n.start = offbeat + by end
  end)
end

--- The clip's hits by cell: `cells[pitch][cell] = { velocity, off }` where
--- `off` says the hit is not on the step's start. Only `from` to `to`.
function E.cells(clip, step, from, to)
  clip = clip_of(clip)
  local out = {}
  for _, n in ipairs(clip:notes({ from = (from or 0) - EPS, to = to or clip.length })) do
    local cell = E.cell(n.start, step)
    local row = out[n.pitch] or {}
    out[n.pitch] = row
    local old = row[cell]
    if not old or n.velocity > old.velocity then
      row[cell] = { velocity = n.velocity, off = math.abs(n.start - cell * step) > 1e-4 }
    end
  end
  return out
end

--- Set a clip's length to whole bars, at least one.
function E.set_bars(clip, bars)
  clip = clip_of(clip)
  bars = math.max(1, math.floor(bars + 0.5))
  clip.length = bars * paw.time.bar()
  return bars
end

return E
