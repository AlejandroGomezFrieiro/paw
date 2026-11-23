-- Musical edits as pure functions on lists of notes.
--
-- Every function takes a list of notes `{ pitch, start, length, velocity,
-- meta }` and a table of options, and returns a new list sorted by start and
-- pitch. The notes given are not changed. Each note keeps its `meta` (and any
-- other field it carries); notes that an edit adds copy the `meta` of the note
-- they come from. Results are kept playable: pitches 0..127, whole
-- velocities 1..127, starts not before 0, lengths of at least `MIN_LENGTH`.
--
--   local mo = require("musicops")
--   clip:set_notes(mo.humanize(clip:notes(), { timing = 0.02, velocity = 8, seed = 7 }))
local scale = require("musicops.scale")

local M = { scale = scale }
local EPS = 1e-9
M.MIN_LENGTH = 1 / 64

-- Helpers ---------------------------------------------------------------------

local function copy(n)
  local out = {}
  for k, v in pairs(n) do
    out[k] = v
  end
  return out
end

local deep = paw.util.copy

local clamp = paw.util.clamp

local round = paw.util.round

local function by_time(a, b)
  if math.abs(a.start - b.start) > EPS then return a.start < b.start end
  return a.pitch < b.pitch
end

--- Copies of the notes, sorted by start and pitch.
local function sorted(notes)
  local out = {}
  for i, n in ipairs(notes) do
    out[i] = copy(n)
    out[i].velocity = out[i].velocity or 100
    out[i].length = out[i].length or 1
  end
  table.sort(out, by_time)
  return out
end

--- Make notes playable and put them in order.
local function finish(notes)
  for _, n in ipairs(notes) do
    n.pitch = clamp(round(n.pitch), 0, 127)
    n.velocity = clamp(round(n.velocity or 100), 1, 127)
    n.start = math.max(0, n.start)
    n.length = math.max(M.MIN_LENGTH, n.length)
  end
  table.sort(notes, by_time)
  return notes
end
M.finish = finish

--- The first start and the last end of a list of notes.
function M.span(notes)
  local s0, e1 = math.huge, -math.huge
  for _, n in ipairs(notes) do
    s0, e1 = math.min(s0, n.start), math.max(e1, n.start + n.length)
  end
  return s0, e1
end

--- Notes grouped into chords: notes that start within `tolerance` beats of
--- the first note of the group (default 1/16 beat). Each group is a list of
--- copies in the order of `notes`'s starts; `groups[i].start` is its first start.
function M.chords(notes, tolerance)
  tolerance = tolerance or 1 / 16
  local list = {}
  for i, n in ipairs(notes) do
    list[i] = copy(n)
    list[i]._order = i
  end
  table.sort(list, function(a, b)
    if math.abs(a.start - b.start) > EPS then return a.start < b.start end
    return a._order < b._order
  end)
  local groups, current = {}, nil
  for _, n in ipairs(list) do
    if not current or n.start - current.start > tolerance + EPS then
      current = { start = n.start }
      groups[#groups + 1] = current
    end
    current[#current + 1] = n
  end
  for _, g in ipairs(groups) do
    for _, n in ipairs(g) do
      n._order = nil
    end
  end
  return groups
end

--- Phrases: runs of notes with no rest longer than `rest` beats between
--- them (default 0.5). Returns a list of { start, finish, notes }, where
--- `finish` is where the last of its notes ends.
function M.phrases(notes, rest)
  rest = rest or 0.5
  local out, current = {}, nil
  for _, n in ipairs(sorted(notes)) do
    if not current or n.start - current.finish > rest + EPS then
      current = { start = n.start, finish = n.start + n.length, notes = {} }
      out[#out + 1] = current
    end
    current.notes[#current.notes + 1] = n
    current.finish = math.max(current.finish, n.start + n.length)
  end
  return out
end

--- The notes sounding at `beat`: started at or before it and not yet ended.
function M.sounding(notes, beat)
  local out = {}
  for _, n in ipairs(sorted(notes)) do
    if n.start <= beat + EPS and n.start + n.length > beat + EPS then out[#out + 1] = n end
  end
  return out
end

--- A random number generator that gives the same numbers for the same seed
--- on every machine: Park and Miller's, in plain floating point. `rng()`
--- returns a number in [0, 1).
function M.random(seed)
  local state = math.floor(math.abs(tonumber(seed) or 1)) % 2147483646 + 1
  return function()
    state = (state * 16807) % 2147483647
    return (state - 1) / 2147483646
  end
end

-- Time --------------------------------------------------------------------------

--- Push notes off the grid, as a player would: each start moves by up to
--- `timing` beats either way (default 0.02), each velocity by up to
--- `velocity` (default 8), and with `length` each length by up to that
--- fraction (default 0). The same `seed` (default 1) gives the same result.
function M.humanize(notes, opts)
  opts = opts or {}
  local timing, velocity, length = opts.timing or 0.02, opts.velocity or 8, opts.length or 0
  local rng = M.random(opts.seed or 1)
  local out = sorted(notes)
  for _, n in ipairs(out) do
    local dt, dv, dl = rng() * 2 - 1, rng() * 2 - 1, rng() * 2 - 1
    n.start = n.start + dt * timing
    n.velocity = n.velocity + round(dv * velocity)
    n.length = n.length * (1 + dl * length)
  end
  return finish(out)
end

--- Snap starts to a grid of `grid` beats (default 0.25). `strength` from 0
--- to 1 says how far they move (default 1, all the way). `swing` delays
--- every second grid line by that fraction of a grid step: 1/3 turns even
--- eighths (grid 0.5) into triplet swing. With `lengths` the lengths are
--- snapped to the grid too, never shorter than one step.
function M.quantize(notes, opts)
  opts = opts or {}
  -- The rule is the core's (`paw.notes.quantize`), so that the keys of
  -- paw and of musicops snap a note to the same place.
  return finish(paw.notes.quantize(sorted(notes), {
    grid = opts.grid or 0.25,
    strength = opts.strength or 1,
    swing = opts.swing or 0,
    lengths = opts.lengths,
  }))
end

--- Hold each note until the next note starts, less `gap` beats (default 0).
--- The notes of a chord all reach the next chord; the last notes keep their
--- length.
function M.legato(notes, opts)
  opts = opts or {}
  local gap = opts.gap or 0
  local out = sorted(notes)
  -- The notes are in order of start, so the next start is found walking
  -- back from the end: one pass, not one per note.
  local next_start, later = nil, nil
  for i = #out, 1, -1 do
    local n = out[i]
    if later and later > n.start + EPS then next_start = later end
    later = n.start
    if next_start then n.length = next_start - n.start - gap end
  end
  return finish(out)
end

--- Shorten each note to `factor` of its length (default 0.5).
function M.staccato(notes, opts)
  opts = opts or {}
  local factor = opts.factor or 0.5
  local out = sorted(notes)
  for _, n in ipairs(out) do
    n.length = n.length * factor
  end
  return finish(out)
end

--- Set every length to `length` beats (default 0.25).
function M.set_length(notes, opts)
  opts = opts or {}
  local out = sorted(notes)
  for _, n in ipairs(out) do
    n.length = opts.length or 0.25
  end
  return finish(out)
end

--- Play the passage backwards: each note ends where the mirror of its start
--- is, within the stretch from the first start to the last end.
function M.reverse(notes)
  local out = sorted(notes)
  local s0, e1 = M.span(out)
  for _, n in ipairs(out) do
    n.start = s0 + e1 - (n.start + n.length)
  end
  return finish(out)
end

--- Scale time around `anchor` (default: the first start) by `factor`.
function M.stretch(notes, opts)
  opts = opts or {}
  local factor = opts.factor or 1
  local out = sorted(notes)
  local anchor = opts.anchor or M.span(out)
  for _, n in ipairs(out) do
    n.start = anchor + (n.start - anchor) * factor
    n.length = n.length * factor
  end
  return finish(out)
end

--- Twice as fast: starts and lengths halved from `anchor` (default: the first start).
function M.double_time(notes, opts) return M.stretch(notes, { factor = 0.5, anchor = opts and opts.anchor }) end

--- Half as fast: starts and lengths doubled from `anchor`.
function M.half_time(notes, opts) return M.stretch(notes, { factor = 2, anchor = opts and opts.anchor }) end

-- Chords ------------------------------------------------------------------------

--- Spread the notes of each chord out in time, `step` beats apart (default
--- 0.05), from the lowest up (`dir` "up", the default) or the highest down
--- ("down"), as a strummed guitar. Each note still ends where it did.
function M.strum(notes, opts)
  opts = opts or {}
  local step, down = opts.step or 0.05, opts.dir == "down"
  local out = {}
  for _, chord in ipairs(M.chords(notes, opts.tolerance)) do
    table.sort(chord, function(a, b)
      if down then return a.pitch > b.pitch end
      return a.pitch < b.pitch
    end)
    for k, n in ipairs(chord) do
      local finish_at = n.start + n.length
      n.start = chord.start + (k - 1) * step
      n.length = finish_at - n.start
      out[#out + 1] = n
    end
  end
  return finish(out)
end

local function arp_order(chord, mode)
  local seq = {}
  if mode == "played" then
    for i, n in ipairs(chord) do
      seq[i] = n
    end
    return seq
  end
  local asc = {}
  for i, n in ipairs(chord) do
    asc[i] = n
  end
  table.sort(asc, function(a, b) return a.pitch < b.pitch end)
  if mode == "down" then
    for i = #asc, 1, -1 do
      seq[#seq + 1] = asc[i]
    end
  elseif mode == "updown" then
    for _, n in ipairs(asc) do
      seq[#seq + 1] = n
    end
    for i = #asc - 1, 2, -1 do
      seq[#seq + 1] = asc[i]
    end
  else
    seq = asc
  end
  return seq
end

--- Play each chord as a broken chord: one note every `step` beats (default
--- 0.25) for as long as the chord lasts, each `gate` of a step long (default
--- 1). `mode` is "up" (the default), "down", "updown" (up, then down without
--- repeating the top and bottom) or "played" (in the order the notes of the
--- chord began, as they were played). A lone note stays as it is.
function M.arpeggiate(notes, opts)
  opts = opts or {}
  local step, gate, mode = opts.step or 0.25, opts.gate or 1, opts.mode or "up"
  local out = {}
  for _, chord in ipairs(M.chords(notes, opts.tolerance)) do
    if #chord < 2 then
      out[#out + 1] = chord[1]
    else
      local finish_at = -math.huge
      for _, n in ipairs(chord) do
        finish_at = math.max(finish_at, n.start + n.length)
      end
      local seq = arp_order(chord, mode)
      local i, t = 0, chord.start
      while t < finish_at - EPS do
        local src = seq[i % #seq + 1]
        local n = copy(src)
        n.meta = deep(src.meta)
        n.start, n.length = t, math.min(step * gate, finish_at - t)
        out[#out + 1] = n
        i, t = i + 1, chord.start + (i + 1) * step
      end
    end
  end
  return finish(out)
end

--- Invert each chord `times` times (default 1): upwards (`dir` 1, the
--- default) the lowest note goes up by octaves until it is the highest;
--- downwards (-1) the highest goes below the lowest. A note that would
--- leave 0..127 stays where it is.
function M.invert(notes, opts)
  opts = opts or {}
  local dir, times = opts.dir or 1, opts.times or 1
  local out = {}
  for _, chord in ipairs(M.chords(notes, opts.tolerance)) do
    for _ = 1, #chord > 1 and times or 0 do
      local lo, hi = chord[1], chord[1]
      for _, n in ipairs(chord) do
        if n.pitch < lo.pitch then lo = n end
        if n.pitch > hi.pitch then hi = n end
      end
      -- The bounds are taken before moving: with every pitch the same, the
      -- lowest note and the highest are one note.
      local bottom, top = lo.pitch, hi.pitch
      if dir > 0 then
        local p = bottom
        while p <= top do
          p = p + 12
        end
        if p <= 127 then lo.pitch = p end
      else
        local p = top
        while p >= bottom do
          p = p - 12
        end
        if p >= 0 then hi.pitch = p end
      end
    end
    for _, n in ipairs(chord) do
      out[#out + 1] = n
    end
  end
  return finish(out)
end

--- Add a copy of every note `by` semitones away (default 12, an octave up).
function M.add_octave(notes, opts)
  local by = opts and opts.by or 12
  local out = sorted(notes)
  for i = 1, #out do
    local n = copy(out[i])
    n.meta = deep(out[i].meta)
    n.pitch = n.pitch + by
    if n.pitch >= 0 and n.pitch <= 127 then out[#out + 1] = n end
  end
  return finish(out)
end

-- Pitch -------------------------------------------------------------------------

--- Move every note `semitones` up (or down when negative).
function M.transpose(notes, semitones)
  local out = sorted(notes)
  for _, n in ipairs(out) do
    n.pitch = n.pitch + (semitones or 0)
  end
  return finish(out)
end

--- Move every note `degrees` steps along the scale of `key` (a key or its
--- name; default the project's). Notes outside the key keep their distance
--- from the scale note below them.
function M.transpose_scale(notes, degrees, key)
  key = scale.parse(key or scale.current())
  local out = sorted(notes)
  for _, n in ipairs(out) do
    n.pitch = scale.step(key, n.pitch, degrees or 0)
  end
  return finish(out)
end

--- Move notes outside `key` to the nearest pitch in it (`opts.dir`
--- "nearest", "up" or "down").
function M.snap_scale(notes, key, opts)
  key = scale.parse(key or scale.current())
  local out = sorted(notes)
  for _, n in ipairs(out) do
    n.pitch = scale.snap(key, n.pitch, opts and opts.dir)
  end
  return finish(out)
end

--- Turn the melody upside down around `axis` (default: the pitch of the
--- first note). With `key` the mirror is taken in scale steps, so the result
--- stays in the key; without, in semitones.
function M.mirror(notes, opts)
  opts = opts or {}
  local out = sorted(notes)
  if #out == 0 then return out end
  local axis = opts.axis and paw.music.pitch(opts.axis) or out[1].pitch
  if opts.key then
    local key = scale.parse(opts.key)
    local da = scale.degree(key, axis)
    for _, n in ipairs(out) do
      local d, offset = scale.degree(key, n.pitch)
      n.pitch = scale.pitch(key, 2 * da - d) + offset
    end
  else
    for _, n in ipairs(out) do
      n.pitch = 2 * axis - n.pitch
    end
  end
  return finish(out)
end

-- Velocity ----------------------------------------------------------------------

--- Set velocities along a straight line in time, from `from` at the first
--- start to `to` at the last.
function M.ramp(notes, opts)
  opts = opts or {}
  local out = sorted(notes)
  if #out == 0 then return out end
  local from, to = opts.from or 40, opts.to or 110
  local t0, t1 = out[1].start, out[#out].start
  for _, n in ipairs(out) do
    local f = t1 - t0 > EPS and (n.start - t0) / (t1 - t0) or 0
    n.velocity = from + (to - from) * f
  end
  return finish(out)
end

--- Louder and louder: each velocity rises by up to `amount` (default 30),
--- nothing at the first start and all of it at the last, so the accents
--- already there stay.
function M.crescendo(notes, opts)
  local amount = opts and opts.amount or 30
  local out = sorted(notes)
  if #out == 0 then return out end
  local t0, t1 = out[1].start, out[#out].start
  for _, n in ipairs(out) do
    local f = t1 - t0 > EPS and (n.start - t0) / (t1 - t0) or 0
    n.velocity = n.velocity + amount * f
  end
  return finish(out)
end

--- Softer and softer: a crescendo by `-amount`.
function M.diminuendo(notes, opts) return M.crescendo(notes, { amount = -(opts and opts.amount or 30) }) end

--- Bring velocities closer to `center` (default their average) by `ratio`
--- (default 0.5: half as far). A ratio above 1 spreads them out instead.
function M.compress(notes, opts)
  opts = opts or {}
  local out = sorted(notes)
  if #out == 0 then return out end
  local center = opts.center
  if not center then
    local sum = 0
    for _, n in ipairs(out) do
      sum = sum + n.velocity
    end
    center = sum / #out
  end
  local ratio = opts.ratio or 0.5
  for _, n in ipairs(out) do
    n.velocity = center + (n.velocity - center) * ratio
  end
  return finish(out)
end

--- Set every velocity to `velocity`, or with none to their average.
function M.set_velocity(notes, opts) return M.compress(notes, { ratio = 0, center = opts and opts.velocity }) end

--- Make the notes on every `grid`-th beat (default 1, each beat; `offset`
--- moves the grid) louder by `amount` (default 20).
function M.accent(notes, opts)
  opts = opts or {}
  local grid, amount, offset = opts.grid or 1, opts.amount or 20, opts.offset or 0
  local out = sorted(notes)
  for _, n in ipairs(out) do
    local k = (n.start - offset) / grid
    if math.abs(k - math.floor(k + 0.5)) * grid < 1e-6 then n.velocity = n.velocity + amount end
  end
  return finish(out)
end

--- Remove notes of the same pitch that overlap: the earlier one is cut where
--- the later one starts, and of notes starting together on a pitch only
--- the longest stays.
function M.remove_overlaps(notes)
  local out, keep = sorted(notes), {}
  -- Of notes that start together on a pitch, the longest stays.
  table.sort(out, function(a, b)
    if math.abs(a.start - b.start) > EPS then return a.start < b.start end
    if a.pitch ~= b.pitch then return a.pitch < b.pitch end
    return a.length > b.length
  end)
  for i, n in ipairs(out) do
    local dupe = false
    for j = i + 1, #out do
      local m = out[j]
      if m.pitch == n.pitch and m.start > n.start + EPS and m.start < n.start + n.length - EPS then
        n.length = m.start - n.start
      end
    end
    for j = 1, #keep do
      if keep[j].pitch == n.pitch and math.abs(keep[j].start - n.start) < EPS then dupe = true end
    end
    if not dupe then keep[#keep + 1] = n end
  end
  return finish(keep)
end

return M
