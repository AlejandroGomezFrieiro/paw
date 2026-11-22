-- From what was played to what a musician would write: the score layer.
--
-- `M.transcribe(notes, ctx)` reads a clip's performed notes and returns
-- score events: chords on a staff and in a voice, each at a written place
-- and with a written length, each naming the performed notes it stands for.
-- It is a pure function; nothing it is given is changed. The performance
-- keeps everything the score does not show: each note's offset from its
-- written place, its real length, its velocity.
--
-- What it decides, in order:
--   grace     a very short note just before a main note is a grace note
--   chords    onsets close together are one chord: a strum or a roll (each
--             string after the last, low to high or high to low, while the
--             earlier ones still ring) up to a span, with an arpeggio sign
--             when it is slow enough to hear as one
--   hands     on a grand staff, which notes each hand plays, by a line that
--             follows the music rather than a fixed middle C
--   swing     eighths played long-short are recognised and written straight
--   onsets    each beat is written on the simplest grid that explains its
--             onsets, duple or triplet, chosen by fit with a penalty for
--             complexity; the player's drift from the grid (a ritardando, a
--             part played ahead of the beat) is followed beat by beat
--   voices    a note held under (or over) moving ones is a second voice
--   lengths   a chord is written to the next onset in its voice when the
--             silence before it is articulation, not a rest; a short
--             detached note gets a staccato mark; an overlap is legato
--
-- Notes drawn exactly on the grid (in the piano roll, say) are written as
-- they are: the interpretation is for what was played.
local M = {}

local EPS = 1e-6
local floor, abs, max, min = math.floor, math.abs, math.max, math.min

--- The settings and their defaults: what makes a played part readable.
M.DEFAULTS = {
  mode = "score", -- "score": interpreted; "raw": every note as it is, to the grid
  chord = 35, -- ms: onsets this close are one chord, in any order
  strum = 70, -- ms between the strings of a strum or a roll (0: off)
  strum_span = 450, -- ms: the longest strum
  arpeggio = 160, -- ms: a strum at least this long is marked with an arpeggio sign (0: never)
  triplets = true, -- whether a beat may be written in triplets (duplets and quadruplets in 6/8)
  tuplets = true, -- whether a beat may be written as a quintuplet or a septuplet
  finest = 0.25, -- the shortest duple subdivision written, in beats: 0.25 a sixteenth
  simplicity = 1, -- how strongly simple grids are preferred (0 none, 2 strongly)
  gap = 0.3, -- a silence shorter than this share of the time to the next onset is articulation
  staccato = true, -- a note much shorter than its written value is written with a staccato mark
  grace = 100, -- ms: a note this short just before another is a grace note (0: off)
  swing = "auto", -- "auto", "off", or the long eighth's share of the beat (0.5 straight, 0.67 triplet swing)
  voices = true, -- a held note under or over moving ones is a second voice
  split = "auto", -- "auto", or the pitch at which a grand staff's hands are split
  follow = true, -- follow the player's drift from the grid (rubato, ritardando)
  grid = 0.25, -- raw view only: the grid notes are rounded to
}

M.ORDER = {
  "mode",
  "chord",
  "strum",
  "strum_span",
  "arpeggio",
  "triplets",
  "tuplets",
  "finest",
  "simplicity",
  "gap",
  "staccato",
  "grace",
  "swing",
  "voices",
  "split",
  "follow",
  "grid",
}

--- The settings in force: the defaults under what a clip keeps.
function M.settings(own)
  local out = {}
  for k, v in pairs(M.DEFAULTS) do
    out[k] = v
  end
  for k, v in pairs(own or {}) do
    if M.DEFAULTS[k] ~= nil then out[k] = v end
  end
  return out
end

-- Metre ------------------------------------------------------------------------------------

--- The beats of a bar: compound metres (6/8, 9/8, 12/8) beat in dotted quarters.
function M.beats_of(bar)
  local unit = 4 / bar.den
  local compound = bar.den >= 8 and bar.num % 3 == 0 and bar.num > 3
  local len = compound and 3 * unit or unit
  local out = {}
  local count = compound and bar.num / 3 or bar.num
  for i = 0, count - 1 do
    out[#out + 1] =
      { s = bar.start + i * len, e = bar.start + (i + 1) * len, len = len, compound = compound, bar = bar }
  end
  return out
end

--- Whether a time is drawn rather than played: on a 1/24-beat grid.
local function exact(x)
  local v = x * 24
  return abs(v - floor(v + 0.5)) < 1e-3
end
M.exact = exact

-- Candidate grids for a beat, with their complexity: the number of parts
-- the beat is divided into; a triplet's (3, 6, and in compound metre the
-- duplet's and quadruplet's) or another tuplet's, written in the time of
-- that many parts (a quintuplet or septuplet of sixteenths, in the time of
-- four).
local SIMPLE = {
  { 1, 0 },
  { 2, 0.02 },
  { 4, 0.07 },
  { 8, 0.3 },
  { 3, 0.1, "triplet" },
  { 6, 0.3, "triplet" },
  { 5, 0.3, "tuplet", 4 },
  { 7, 0.4, "tuplet", 4 },
}
local COMPOUND = { { 1, 0 }, { 3, 0.02 }, { 6, 0.08 }, { 12, 0.35 }, { 2, 0.15, "triplet" }, { 4, 0.3, "triplet" } }
local FIT = 40 -- weight of the squared error (in beats) against the complexity
-- And of each onset by where it falls: the beat, its half, its quarter...
-- by the denominator of its place in the beat.
local PLACE = {
  [1] = 0,
  [2] = 0.05,
  [4] = 0.15,
  [8] = 0.45,
  [3] = 0.15,
  [6] = 0.45,
  [12] = 0.6,
  [24] = 0.8,
  [5] = 0.35,
  [7] = 0.45,
}
local PLACE_COMPOUND = { [1] = 0, [3] = 0.05, [6] = 0.15, [12] = 0.45, [2] = 0.2, [4] = 0.35, [24] = 0.8 }
local function gcd(a, b)
  while b ~= 0 do
    a, b = b, a % b
  end
  return a
end

-- Swing ----------------------------------------------------------------------------------------

--- Where a share `p` of a beat lands once a swing of `ratio` is taken out.
local function unswing(p, ratio)
  if not ratio or p <= 0 or p >= 1 then return p end
  if p < ratio then return p * 0.5 / ratio end
  return 0.5 + (p - ratio) * 0.5 / (1 - ratio)
end
M.unswing = unswing

--- Recognise swing: beats with an onset on the beat and one between 0.56
--- and 0.78 of it, and few straight off-beats. Returns the ratio or nil.
local function detect_swing(onsets, beats)
  local swung, straight, shares = 0, 0, {}
  local bi = 1
  local per = {}
  for _, t in ipairs(onsets) do
    while beats[bi] and t >= beats[bi].e - beats[bi].len * 0.1 do
      bi = bi + 1
    end
    local b = beats[bi]
    if not b then break end
    if not b.compound then
      local p = (t - b.s) / b.len
      per[bi] = per[bi] or {}
      table.insert(per[bi], p)
    end
  end
  for _, list in pairs(per) do
    local off = {}
    for _, p in ipairs(list) do
      if p > 0.12 and p < 0.9 then off[#off + 1] = p end
    end
    if #off == 1 then
      if off[1] >= 0.56 and off[1] <= 0.78 then
        swung = swung + 1
        shares[#shares + 1] = off[1]
      elseif abs(off[1] - 0.5) < 0.05 then
        straight = straight + 1
      end
    elseif #off > 1 then
      straight = straight + 1
    end
  end
  if swung >= 3 and swung >= 2 * straight then
    table.sort(shares)
    return shares[floor((#shares + 1) / 2)]
  end
end

-- Hands ------------------------------------------------------------------------------------

--- What playing pitches `from` to `to` of a chord (lowest first) costs a
--- hand centred on `centre` that last played `last`, at ease between
--- `low_ok` and `high_ok`.
local function hand_cost(pitches, from, to, centre, last, low_ok, high_ok)
  if to < from then return 0 end
  local c = 0
  for i = from, to do
    local p = pitches[i]
    c = c + 0.5 * abs(p - centre) / 12
    if last then c = c + abs(p - last) / 12 end
    if p < low_ok then c = c + (low_ok - p) * 0.25 end
    if p > high_ok then c = c + (p - high_ok) * 0.25 end
  end
  local span = pitches[to] - pitches[from]
  if span > 12 then c = c + (span - 12) * 0.5 end
  return c
end

--- Split a chord's pitches (lowest first) between the hands: how many go to
--- the left. `state` carries where each hand has been.
local function split_hands(pitches, state)
  local best, best_k
  for k = 0, #pitches do
    local cost = hand_cost(pitches, 1, k, state.lh, state.lh_last, 0, 64)
      + hand_cost(pitches, k + 1, #pitches, state.rh, state.rh_last, 53, 127)
    if not best or cost < best - 1e-9 then
      best, best_k = cost, k
    end
  end
  return best_k
end

--- Of a written length `len` (with `penalty`) for a chord at `start` and
--- the best so far, the one nearer what was played (`played` long), by
--- proportion, of those that end by `limit`.
local function nearer(len, penalty, start, limit, played, best, best_cost)
  if start + len <= limit + EPS then
    local r = math.log(len / played)
    local cost = (r > 0 and 0.6 * r or -r) + penalty
    if not best_cost or cost < best_cost - 1e-9 then return len, cost end
  end
  return best, best_cost
end

--- Whether item `i` steps on to item `b` as evenly as it came from the two
--- onsets before it (chords' notes `win` apart are one onset), at least
--- an eighth of a beat apart: a note of a run, such as a fast tuplet's,
--- and not a grace note.
local function in_run(items, i, b, win)
  local step = b.s - items[i].s
  if step < 0.125 then return false end
  local at, count = items[i].s, 0
  for k = i - 1, 1, -1 do
    local x = items[k]
    if at - x.s > win then
      if abs((at - x.s) - step) > 0.2 * step then return false end
      at, count = x.s, count + 1
      if count == 2 then return true end
    end
  end
  return false
end

-- Orders, made once.
local function by_pitch(a, b) return a.pitch < b.pitch or (a.pitch == b.pitch and a.index < b.index) end
local function by_first(a, b) return a.first < b.first end
local function by_s_pitch(a, b) return a.s < b.s or (a.s == b.s and a.pitch < b.pitch) end
local function by_onset(a, b)
  if abs(a.s - b.s) > EPS then return a.s < b.s end
  return a.pitch < b.pitch
end
local function by_q_staff(a, b)
  if abs(a.q - b.q) > EPS then return a.q < b.q end
  return a.staff < b.staff
end
local function by_q_staff_voice(a, b)
  if abs(a.q - b.q) > EPS then return a.q < b.q end
  if a.staff ~= b.staff then return a.staff < b.staff end
  return a.voice < b.voice
end

--- Sort a list as `table.sort` would, but short lists in place here, where
--- the compiler can follow.
local function sort(list, less)
  local n = #list
  if n > 12 then return table.sort(list, less) end
  for i = 2, n do
    local x = list[i]
    local j = i - 1
    while j >= 1 and less(x, list[j]) do
      list[j + 1] = list[j]
      j = j - 1
    end
    list[j + 1] = x
  end
end

-- Transcription ------------------------------------------------------------------------------

--- Performed notes to score events. `notes` as a clip gives them (`pitch`,
--- `start`, `length`, `velocity`, `meta`); `ctx`:
---   bars      `{ { start, num, den } ... }` in clip beats, covering the clip
---   finish    where the last bar ends
---   tempo     beats a minute, for the windows given in milliseconds
---   staves    `{ "treble" }` or `{ "treble", "bass" }`
---   settings  as `M.settings` gives them
---   tuplets   the user's tuplets: `{ { start, length, n, normal } ... }` in written
---             beats; `{ start, length, plain = true }` a stretch with none (the
---             grid is the beat's for every voice; which voice a tuplet is
---             written in, `staff` and `voice`, is the engraving's to read)
--- Returns `{ events, swing }`: each event `{ start, length, staff, voice,
--- notes = { { index, pitch, meta, velocity, offset, played } }, grace,
--- arpeggio (1 low to high, -1 high to low), staccato }`, by start.
function M.transcribe(notes, ctx)
  local set = ctx.settings or M.settings()
  local bars = ctx.bars
  local origin, finish = bars[1].start, ctx.finish
  local beat_ms = 60000 / (ctx.tempo or 120)
  local function ms(v) return (v or 0) / beat_ms end
  local two = #ctx.staves == 2

  local beats = {}
  for _, bar in ipairs(bars) do
    for _, b in ipairs(M.beats_of(bar)) do
      beats[#beats + 1] = b
    end
  end
  local function beat_at(t)
    if t < beats[1].s then return beats[1], 1 end
    local lo, hi = 1, #beats
    while lo < hi do
      local mid = floor((lo + hi + 1) / 2)
      if beats[mid].s <= t + EPS then
        lo = mid
      else
        hi = mid - 1
      end
    end
    return beats[lo], lo
  end

  -- The notes, with what the user has said about each.
  local items = {}
  for index, n in ipairs(notes) do
    local own = n.meta and type(n.meta.notation) == "table" and n.meta.notation or {}
    -- A note before 0 is hidden by a trim of its clip's start, but for a
    -- grace note leading to the first beat.
    local from = own.grace and math.max(-0.5, origin - 0.5) or 0
    if n.start >= from and n.start >= origin - 0.25 - (own.grace and 0.25 or 0) and n.start < finish - EPS then
      -- Notation made the note shorter (or longer) than it is written, as
      -- a staccato plays: written as long as it says, while the note is as
      -- long as notation made it.
      local written = tonumber(own.len) and tonumber(own.sounding) and abs(n.length - own.sounding) < 1e-6 and own.len
        or nil
      items[#items + 1] = {
        index = index,
        pitch = n.pitch,
        s = n.start,
        e = n.start + n.length,
        len = n.length,
        velocity = n.velocity,
        meta = n.meta,
        own = own,
        written = written,
        exact = exact(n.start) and (written ~= nil or exact(n.start + n.length)),
      }
    end
  end
  sort(items, by_onset)
  -- A played note lands on the grid by chance now and then (one in four
  -- hundred at 480 ticks a beat): it counts as drawn when notation wrote
  -- it, when most of the notes are drawn, or when one beside it is too.
  local drawn = 0
  for _, a in ipairs(items) do
    if a.exact then drawn = drawn + 1 end
  end
  if drawn < 0.5 * #items then
    local was = {}
    for i, a in ipairs(items) do
      was[i] = a.exact
    end
    for i, a in ipairs(items) do
      a.exact = was[i] and (a.own.letter ~= nil or was[i - 1] or was[i + 1]) or false
    end
  end

  -- Grace notes: short, just before a longer note of another pitch, and
  -- let go by the time it sounds.
  local gmax = math.min(ms(set.grace), 0.15)
  for i, a in ipairs(items) do
    local forced = a.own.grace
    -- Not the last string of a strum: nothing began just before it.
    local in_strum = false
    for k = i - 1, 1, -1 do
      if a.s - items[k].s > math.max(ms(set.strum), ms(set.chord)) then break end
      if items[k].e > a.s then in_strum = true end
    end
    if forced ~= false and (forced or (set.grace or 0) > 0 and not a.exact and a.len <= gmax and not in_strum) then
      for j = i + 1, #items do
        local b = items[j]
        if b.s - a.s > (forced and 1 or gmax) then break end
        if
          b.s > a.s + EPS
          and b.pitch ~= a.pitch
          and (forced or (a.e <= b.s + 0.6 * gmax and b.len > 2 * a.len and not in_run(items, i, b, ms(set.chord))))
        then
          a.grace_of = b
          break
        end
      end
    end
  end
  for _, a in ipairs(items) do
    -- A run of grace notes leads to the first note that is not one.
    local main = a.grace_of
    while main and main.grace_of do
      main = main.grace_of
    end
    a.grace_of = main
  end

  -- Chords: near-simultaneous onsets, and strums.
  local win, gap_s, span_s = ms(set.chord), ms(set.strum), ms(set.strum_span)
  local groups = {}
  local g
  for _, x in ipairs(items) do
    if not x.grace_of then
      local joins = false
      if g and not g.pitches[x.pitch] then
        if x.s - g.first <= win + EPS then
          joins = true
        elseif (set.strum or 0) > 0 and x.s - g.last <= gap_s and x.s - g.first <= span_s then
          -- Every string so far still rings, and the order holds.
          local rings = true
          for _, y in ipairs(g.items) do
            if y.e < x.s + 0.02 then rings = false end
          end
          local dir = x.pitch > g.last_pitch and 1 or -1
          if rings and (not g.dir or g.dir == dir) then
            joins = true
            g.dir = g.dir or dir
          end
        end
      end
      if joins then
        g.items[#g.items + 1] = x
        g.pitches[x.pitch] = true
        g.last, g.last_pitch = x.s, x.pitch
      else
        g = { items = { x }, pitches = { [x.pitch] = true }, first = x.s, last = x.s, last_pitch = x.pitch }
        groups[#groups + 1] = g
      end
      x.group = g
    end
  end
  -- The user's chords: notes marked with one chord id are one chord.
  local by_id = {}
  for _, gr in ipairs(groups) do
    for _, x in ipairs(gr.items) do
      local id = x.own.chord
      if id then
        local into = by_id[id]
        if into and into ~= gr then
          for _, y in ipairs(gr.items) do
            into.items[#into.items + 1] = y
            y.group = into
          end
          into.first = min(into.first, gr.first)
          gr.items, gr.dead = {}, true
          break
        else
          by_id[id] = gr
        end
      end
    end
  end
  local live = {}
  for _, gr in ipairs(groups) do
    if not gr.dead and #gr.items > 0 then
      sort(gr.items, by_pitch)
      local first, last = math.huge, -math.huge
      for _, x in ipairs(gr.items) do
        first, last = min(first, x.s), max(last, x.s)
      end
      gr.first, gr.span = first, last - first
      -- An arpeggio sign for a strum slow enough to hear as one.
      local strum
      for _, x in ipairs(gr.items) do
        if x.own.strum then strum = x.own.strum end
      end
      if strum == "up" then
        gr.arpeggio = 1
      elseif strum == "down" then
        gr.arpeggio = -1
      elseif strum ~= "none" and (set.arpeggio or 0) > 0 and #gr.items >= 2 and gr.span >= ms(set.arpeggio) - EPS then
        local lo, hi = gr.items[1], gr.items[#gr.items]
        gr.arpeggio = lo.s <= hi.s and 1 or -1
      end
      live[#live + 1] = gr
    end
  end
  sort(live, by_first)
  groups = live

  -- Swing, then onsets beat by beat.
  local ratio
  if type(set.swing) == "number" and set.swing > 0.5 then
    ratio = set.swing
  elseif set.swing == "auto" then
    local onsets = {}
    for _, gr in ipairs(groups) do
      onsets[#onsets + 1] = gr.first
    end
    ratio = detect_swing(onsets, beats)
  end

  -- The user's tuplets, and beats said to be plain: written on their grids.
  local forced = {}
  for _, tp in ipairs(ctx.tuplets or {}) do
    for bi, b in ipairs(beats) do
      if b.s >= tp.start - EPS and b.e <= tp.start + tp.length + EPS then
        if tp.plain then
          forced[bi] = b.compound and { 1, 3, 6, 12 } or { 1, 2, 4, 8 }
        else
          local d = tp.n * b.len / tp.length
          forced[bi] = { d, 2 * d }
        end
      end
    end
  end

  local finest = set.finest or 0.25

  --- One pass over the beats: each beat's onsets written on its best grid,
  --- with `drift_of(bi, t)` how far behind the grid the player is at `t`.
  --- `after(bi, res, count)` hears how far off the beat's onsets were.
  --- Returns the offsets seen: `{ t, off }` per onset that fit well.
  local tuplet_cost = 0 -- more when the rest of the part is plainly duple
  local function pass(drift_of, after)
    local seen = {}
    local gi = 1
    for bi, b in ipairs(beats) do
      local margin = b.len / 8
      local list = {}
      while groups[gi] and groups[gi].first - drift_of(bi, groups[gi].first) < b.e - margin do
        list[#list + 1] = groups[gi]
        gi = gi + 1
      end
      if #list > 0 then
        -- Where in the beat an onset is, the drift and the swing taken out.
        local sw = (not b.compound) and ratio or nil
        local cands = {}
        if forced[bi] then
          for _, d in ipairs(forced[bi]) do
            cands[#cands + 1] = { d, 0 }
          end
        else
          for _, c in ipairs(b.compound and COMPOUND or SIMPLE) do
            local d = c[1]
            local tuplet = c[3]
            local ok
            if tuplet == "tuplet" then
              -- Its notes are written no shorter than the finest value.
              ok = set.tuplets and b.len / c[4] >= finest - EPS
            else
              ok = b.len / d >= (tuplet and finest * 0.66 or finest) - EPS
              if tuplet and not set.triplets then ok = false end
            end
            if tuplet and ratio then ok = false end
            if ok then cands[#cands + 1] = { d, (c[2] + (tuplet and tuplet_cost or 0)) * (set.simplicity or 1) } end
          end
        end
        local best, best_d
        for _, c in ipairs(cands) do
          local d, cost = c[1], c[2]
          local used = {}
          for _, gr in ipairs(list) do
            local u = unswing(((gr.first - drift_of(bi, gr.first)) - b.s) / b.len, sw)
            local k = math.max(0, math.min(d, floor(u * d + 0.5)))
            local err = (u - k / d) * b.len
            local den = d / gcd(k, d)
            cost = cost + FIT * err * err + ((b.compound and PLACE_COMPOUND or PLACE)[den] or 1) * (set.simplicity or 1)
            if used[k] then cost = cost + 5 end
            used[k] = true
          end
          if not best or cost < best - 1e-9 then
            best, best_d = cost, c[1]
          end
        end
        b.d = best_d
        local res, count = 0, 0
        for _, gr in ipairs(list) do
          local u = unswing(((gr.first - drift_of(bi, gr.first)) - b.s) / b.len, sw)
          local k = math.max(0, math.min(best_d, floor(u * best_d + 0.5)))
          gr.q = math.max(origin, b.s + k / best_d * b.len)
          -- How far the player is from the grid.
          local swung_q = b.s + (ratio and not b.compound and k / best_d == 0.5 and ratio or k / best_d) * b.len
          local off = gr.first - swung_q
          if abs(off - drift_of(bi, gr.first)) < 0.4 * b.len / math.max(1, best_d / 2) then
            res = res + off - drift_of(bi, gr.first)
            count = count + 1
            seen[#seen + 1] = { t = gr.first, off = off }
          end
        end
        if after then after(bi, res, count) end
      else
        b.d = 1
        if after then after(bi, 0, 0) end
      end
    end
    return seen
  end

  local fits = {} -- per beat: the drift at its start and how it grows
  local function fitted(bi, t)
    local f = fits[bi]
    if not f then return 0 end
    return f[1] + f[2] * (t - beats[bi].s)
  end
  if set.follow then
    -- First, follow the player beat by beat; then fit a line through the
    -- offsets around each beat and write the beats again against it.
    local drift, rate = 0, 0
    local current = {}
    local seen = pass(function(bi, t)
      if not current[bi] then
        drift = drift + rate
        current[bi] = drift
      end
      return current[bi]
    end, function(_, res, count)
      if count > 0 then
        res = res / count
        drift = drift + 0.7 * res
        rate = math.max(-0.2, math.min(0.2, rate + 0.35 * res))
      else
        rate = rate * 0.9
      end
    end)
    -- How much of the part is in triplets and other tuplets: a lone
    -- tuplet among duple beats needs more to convince.
    local duple, triple = 0, 0
    for _, b in ipairs(beats) do
      local d = b.d or 1
      if b.compound then
        if d % 2 == 0 and d % 3 ~= 0 then
          triple = triple + 1
        elseif d > 1 then
          duple = duple + 1
        end
      else
        if d % 3 == 0 or d == 5 or d == 7 then
          triple = triple + 1
        elseif d > 1 then
          duple = duple + 1
        end
      end
    end
    if duple + triple > 0 then tuplet_cost = 0.3 * math.max(0, duple - triple) / (duple + triple) end
    local si = 1
    for bi, b in ipairs(beats) do
      local lo, hi = b.s - 2 * b.len, b.e + 2 * b.len
      while seen[si] and seen[si].t < lo do
        si = si + 1
      end
      local sw, sx, sy, sxx, sxy = 0, 0, 0, 0, 0
      local j = si
      while seen[j] and seen[j].t < hi do
        local x = seen[j].t - b.s
        local w = 1 / (1 + abs(x - 0.5 * b.len) / b.len)
        sw, sx, sy = sw + w, sx + w * x, sy + w * seen[j].off
        sxx, sxy = sxx + w * x * x, sxy + w * x * seen[j].off
        j = j + 1
      end
      if sw > 0 then
        local mx, my = sx / sw, sy / sw
        local var = sxx / sw - mx * mx
        local slope = var > 1e-4 and (sxy / sw - mx * my) / var or 0
        slope = math.max(-0.25, math.min(0.25, slope))
        fits[bi] = { my - slope * mx, slope }
      else
        fits[bi] = fits[bi - 1] and { fitted(bi - 1, b.s), 0 } or { 0, 0 }
      end
    end
  end
  pass(fitted)
  if ctx.debug then
    for bi, f in pairs(fits) do
      print("fit", bi, f[1], f[2])
    end
  end
  for _, gr in ipairs(groups) do
    if not gr.q then gr.q = math.max(origin, math.min(finish, gr.first)) end
  end

  -- Where a performed time is written: the drift taken out.
  local function warp(t)
    local _, bi = beat_at(t)
    return t - fitted(bi, t)
  end
  --- The grid of the beat a written time is in, for rounding a release.
  local function release_grid(t)
    local b = beat_at(t)
    local d = b.d or 1
    if b.compound then
      d = math.max(d, 3)
    else
      d = math.max(d, 2)
    end
    return b.len / d, b
  end

  local chords = {}
  local hands = { lh = 48, rh = 67 }
  local split_at = tonumber(set.split)
  for _, gr in ipairs(groups) do
    local parts = { {}, {} }
    if two then
      local free, pitches = {}, {}
      for _, x in ipairs(gr.items) do
        if x.own.staff == 1 or x.own.staff == 2 then
          table.insert(parts[x.own.staff], x)
        elseif split_at then
          table.insert(parts[x.pitch < split_at and 2 or 1], x)
        else
          free[#free + 1] = x
          pitches[#pitches + 1] = x.pitch
        end
      end
      if #free > 0 then
        local k = split_hands(pitches, hands)
        local lh_sum, rh_sum = 0, 0
        for i, x in ipairs(free) do
          if i <= k then
            table.insert(parts[2], x)
            lh_sum = lh_sum + x.pitch
          else
            table.insert(parts[1], x)
            rh_sum = rh_sum + x.pitch
          end
        end
        if k > 0 then
          hands.lh = 0.7 * hands.lh + 0.3 * lh_sum / k
          hands.lh_last = free[k].pitch
        end
        if k < #free then
          hands.rh = 0.7 * hands.rh + 0.3 * rh_sum / (#free - k)
          hands.rh_last = free[k + 1].pitch
        end
      end
    else
      parts[1] = gr.items
    end
    for s = 1, 2 do
      if #parts[s] > 0 then
        sort(parts[s], by_pitch)
        chords[#chords + 1] = { q = gr.q, staff = s, items = parts[s], arpeggio = gr.arpeggio, group = gr }
      end
    end
  end
  sort(chords, by_q_staff)
  -- Two chords on a staff written at one place are one chord.
  local merged, last_on = {}, {}
  for _, c in ipairs(chords) do
    local prev = last_on[c.staff]
    if prev and abs(prev.q - c.q) < EPS then
      for _, x in ipairs(c.items) do
        prev.items[#prev.items + 1] = x
      end
      sort(prev.items, by_pitch)
    else
      merged[#merged + 1] = c
      last_on[c.staff] = c
    end
  end
  chords = merged

  -- Each note's written release.
  for _, c in ipairs(chords) do
    for _, x in ipairs(c.items) do
      x.rel = (x.written and c.q + x.written) or (x.exact and x.e) or warp(x.e)
    end
  end

  -- Voices: a note held well past the next onset on its staff, under or
  -- over notes that move, is a voice of its own.
  local per_staff = { {}, {} }
  for _, c in ipairs(chords) do
    table.insert(per_staff[c.staff], c)
  end
  local out_chords = {}
  for s = 1, 2 do
    local list = per_staff[s]
    local active = {} -- held notes still sounding: { rel, voice, pitch }
    for i, c in ipairs(list) do
      local nxt = list[i + 1]
      local beat_len = beat_at(c.q).len
      local keep = {}
      for _, a in ipairs(active) do
        if a.rel > c.q + 0.25 * beat_len then keep[#keep + 1] = a end
      end
      active = keep
      local held, moving = {}, {}
      for _, x in ipairs(c.items) do
        local is_held = false
        if set.voices and nxt then
          local over = x.rel - nxt.q
          is_held = over >= math.max(0.5 * beat_len, 0.5 * (nxt.q - c.q)) - EPS
        end
        if is_held then
          held[#held + 1] = x
        else
          moving[#moving + 1] = x
        end
      end
      local voice_of = {}
      if #held > 0 and #moving > 0 then
        if held[#held].pitch < moving[1].pitch then
          for _, x in ipairs(held) do
            voice_of[x] = 2
          end
        elseif held[1].pitch > moving[#moving].pitch then
          for _, x in ipairs(moving) do
            voice_of[x] = 2
          end
        end
      elseif #held > 0 and nxt then
        local nlow, nhigh = math.huge, -math.huge
        for _, y in ipairs(nxt.items) do
          nlow, nhigh = min(nlow, y.pitch), max(nhigh, y.pitch)
        end
        if nlow > held[#held].pitch then
          for _, x in ipairs(held) do
            voice_of[x] = 2
          end
        end
      elseif #active > 0 then
        local alow, ahigh = math.huge, -math.huge
        local avoice
        for _, a in ipairs(active) do
          alow, ahigh, avoice = min(alow, a.pitch), max(ahigh, a.pitch), a.voice
        end
        if avoice == 1 and c.items[#c.items].pitch < alow then
          for _, x in ipairs(c.items) do
            voice_of[x] = 2
          end
        end
      end
      for _, x in ipairs(c.items) do
        local v = tonumber(x.own.voice) or voice_of[x] or 1
        x.voice = v
      end
      for _, x in ipairs(held) do
        active[#active + 1] = { rel = x.rel, voice = x.voice, pitch = x.pitch }
      end
      -- A chord whose notes are in two voices is two chords.
      local by_voice = {}
      for _, x in ipairs(c.items) do
        by_voice[x.voice] = by_voice[x.voice] or {}
        table.insert(by_voice[x.voice], x)
      end
      for v, xs in pairs(by_voice) do
        out_chords[#out_chords + 1] =
          { q = c.q, staff = s, voice = v, items = xs, arpeggio = c.arpeggio, group = c.group }
      end
    end
  end
  sort(out_chords, by_q_staff_voice)

  -- Lengths, voice by voice.
  local seqs = {}
  for _, c in ipairs(out_chords) do
    local key = c.staff * 10 + c.voice
    seqs[key] = seqs[key] or {}
    table.insert(seqs[key], c)
  end
  for _, seq in pairs(seqs) do
    for i, c in ipairs(seq) do
      local nxt = seq[i + 1]
      local q_next = nxt and nxt.q or math.huge
      local rel, played, all_exact, marked = -math.huge, 0, true, false
      for _, x in ipairs(c.items) do
        rel = max(rel, x.rel)
        played = max(played, x.e - x.s)
        if not x.exact then all_exact = false end
        if type(x.own.art) == "table" and x.own.art.staccato and not x.written then marked = true end
      end
      local beat, beat_i = beat_at(c.q)
      local beat_len = beat.len
      -- The last note of a voice: to the next beat when it ends near it.
      if not nxt then
        local after = beats[beat_i + 1]
        local bound = after and after.s or (beat.s + beat_len)
        if rel <= bound + 0.1 * beat_len then q_next = bound end
      end
      local ioi = q_next - c.q
      local e
      if marked and q_next < math.huge and ioi <= 2 * beat_len + EPS then
        -- Marked staccato by hand: written to the next onset, played short.
        e = q_next
      elseif all_exact then
        e = min(rel, q_next)
      else
        local gap = q_next - rel
        if q_next < math.huge and (set.gap or 0) > 0 and gap <= (set.gap or 0) * ioi + EPS then
          e = q_next
        elseif q_next < math.huge and set.staccato and ioi <= beat_len + EPS and (rel - c.q) <= 0.55 * ioi then
          e = q_next
          c.staccato = true
        else
          -- The value nearest what was played, by proportion: a long note
          -- let go a little early is still a long note.
          local g0 = release_grid(c.q)
          local played_w = math.max(rel - c.q, 0.01)
          local best, best_cost
          for k = 1, floor(beat_len / g0 + 0.5) do
            best, best_cost = nearer(k * g0, k % 2 == 0 and 0 or 0.02, c.q, q_next, played_w, best, best_cost)
          end
          for k = 2, 32 do
            best, best_cost = nearer(k * beat_len / 2, k % 2 == 0 and 0 or 0.05, c.q, q_next, played_w, best, best_cost)
          end
          e = c.q + (best or g0)
          if set.staccato and q_next < math.huge and played_w <= 0.55 * (e - c.q) and (e - c.q) <= beat_len + EPS then
            c.staccato = true
          end
          e = min(e, q_next)
        end
      end
      e = min(e, finish)
      if e <= c.q + EPS then e = min(finish, c.q + release_grid(c.q)) end
      c.e = e
      c.played = played
    end
  end

  -- Grace notes go with the chord of their main note.
  local chord_of = {}
  for _, c in ipairs(out_chords) do
    for _, x in ipairs(c.items) do
      chord_of[x] = c
    end
  end
  for _, x in ipairs(items) do
    if x.grace_of then
      local c = chord_of[x.grace_of]
      if c then
        c.grace = c.grace or {}
        table.insert(c.grace, x)
      end
    end
  end

  local events = {}
  for _, c in ipairs(out_chords) do
    local ev = {
      start = c.q,
      length = c.e - c.q,
      staff = c.staff,
      voice = c.voice,
      arpeggio = c.arpeggio,
      staccato = c.staccato,
      notes = {},
    }
    for j, x in ipairs(c.items) do
      ev.notes[j] =
        { index = x.index, pitch = x.pitch, meta = x.meta, velocity = x.velocity, offset = x.s - c.q, played = x.len }
    end
    if c.grace then
      sort(c.grace, by_s_pitch)
      ev.grace = {}
      for j, x in ipairs(c.grace) do
        ev.grace[j] =
          { index = x.index, pitch = x.pitch, meta = x.meta, velocity = x.velocity, offset = x.s - c.q, played = x.len }
      end
    end
    events[#events + 1] = ev
  end
  return { events = events, swing = ratio }
end

--- The raw view: every note rounded to `grid`, notes starting together a
--- chord lasting until the next starts, one voice a staff, middle C and
--- above on the treble staff of a grand staff.
function M.raw(notes, ctx)
  local grid = (ctx.settings and ctx.settings.grid) or 0.25
  local origin, finish = ctx.bars[1].start, ctx.finish
  local two = #ctx.staves == 2
  local function round_to(x) return origin + floor((x - origin) / grid + 0.5) * grid end
  local by_staff = { {}, {} }
  for index, n in ipairs(notes) do
    local qs, qe = round_to(n.start), round_to(n.start + n.length)
    if qe - qs < grid - EPS then qe = qs + grid end
    if n.start >= 0 and qs < finish - EPS and qs >= origin - EPS then
      local s = (two and n.pitch < 60) and 2 or 1
      table.insert(
        by_staff[s],
        {
          index = index,
          pitch = n.pitch,
          meta = n.meta,
          velocity = n.velocity,
          s = qs,
          e = math.min(qe, finish),
          start = n.start,
          len = n.length,
        }
      )
    end
  end
  local events = {}
  for s = 1, 2 do
    local list = by_staff[s]
    table.sort(list, function(a, b)
      if abs(a.s - b.s) > EPS then return a.s < b.s end
      return a.pitch < b.pitch
    end)
    local chords = {}
    for _, n in ipairs(list) do
      local last = chords[#chords]
      if last and abs(last.s - n.s) < EPS then
        last.notes[#last.notes + 1] = n
        last.e = max(last.e, n.e)
      else
        chords[#chords + 1] = { s = n.s, e = n.e, notes = { n } }
      end
    end
    for i, c in ipairs(chords) do
      if chords[i + 1] then c.e = min(c.e, chords[i + 1].s) end
      local ev = { start = c.s, length = c.e - c.s, staff = s, voice = 1, notes = {} }
      for j, n in ipairs(c.notes) do
        ev.notes[j] = {
          index = n.index,
          pitch = n.pitch,
          meta = n.meta,
          velocity = n.velocity,
          offset = n.start - c.s,
          played = n.len,
        }
      end
      events[#events + 1] = ev
    end
  end
  table.sort(events, function(a, b) return a.start < b.start or (a.start == b.start and a.staff < b.staff) end)
  return { events = events }
end

return M
