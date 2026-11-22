-- From notes to notation, in plain Lua with no drawing.
--
-- `M.layout(notes, opts)` turns a clip's notes into measures of notated
-- events: what a person reading the part would expect to see written. The
-- notes themselves are never changed; every event only refers back to the
-- notes it shows, by their place in the list it was given.
--
-- Times are in beats (quarter notes) from the start of the clip, as clip
-- notes are. Measures follow the project's bars, so a clip that starts in
-- the middle of a bar begins with rests.
--
-- What it decides, in order:
--   clef      treble, bass, or a grand staff when the range needs both
--   score     what was played, interpreted as a musician would write it
--             (`notation.score`: chords, strums, grids, voices, hands,
--             grace notes, swing, lengths), or in the raw view each note
--             rounded to a grid
--   values    each stretch of sound or silence split at barlines and, inside a
--             bar, where the metre says (a syncopation is tied over the beat,
--             a note does not hide the middle of a 4/4 bar, dots where a
--             dotted value is the usual way to write it), tied together;
--             beats divided in three are tuplets
--   spelling  each pitch by the key, with sharps or flats as the key leans,
--             accidentals with the bar's memory and a reminder in the next bar
--   stems     up or down by the note furthest from the middle line, or by
--             the voice when a staff has two
--   beams     eighths and shorter grouped by the beat (by half bars in 4/4
--             when four eighths fill one), and within a tuplet
local M = {}

local EPS = 1e-6
local floor, abs = math.floor, math.abs

local function near(a, b) return abs(a - b) < EPS end

-- Values ------------------------------------------------------------------------------

M.BASES = { 4, 2, 1, 0.5, 0.25, 0.125 }
M.NAMES = { [4] = "whole", [2] = "half", [1] = "quarter", [0.5] = "eighth", [0.25] = "16th", [0.125] = "32nd" }

--- The written value of a duration: its base (4 a whole note, 1 a quarter)
--- and how many dots, or nil when one value cannot show it.
local values = { {}, {} } -- what value_of found, by the dots allowed and the duration
local value_count = 0
function M.value_of(d, max_dots)
  local memo = values[(max_dots or 1) >= 2 and 2 or 1]
  -- Kept by a key that is never a whole number (one for each duration):
  -- LuaJIT does not compile looking up a whole number among other keys,
  -- and every loop that writes a value would run uncompiled.
  local key = d * 7 + 0.1
  local hit = memo[key]
  if hit then return hit[1], hit[2] end
  local base, dots
  for _, b in ipairs(M.BASES) do
    if near(d, b) then
      base, dots = b, 0
      break
    end
    if near(d, b * 1.5) then
      base, dots = b, 1
      break
    end
    if (max_dots or 1) >= 2 and near(d, b * 1.75) then
      base, dots = b, 2
      break
    end
  end
  value_count = value_count + 1
  if value_count > 20000 then
    values, value_count = { {}, {} }, 0
  end
  memo[key] = { base, dots }
  return base, dots
end

--- How many flags or beams a value has.
function M.flags(base)
  if base >= 1 then return 0 end
  if base >= 0.5 then return 1 end
  if base >= 0.25 then return 2 end
  return 3
end

-- Metre -------------------------------------------------------------------------------

--- The metrical tree of a bar: nested spans of the bar, each split where the
--- metre divides it. A node at the level of the beat or below is `free`:
--- inside a beat any single value may stand.
function M.meter(num, den, groups)
  local unit = 4 / den
  local bar = num * unit
  local MIN = 0.125
  local function binary(s, len)
    local node = { s = s, e = s + len, free = true }
    if len / 2 >= MIN - EPS then node.children = { binary(s, len / 2), binary(s + len / 2, len / 2) } end
    return node
  end
  if groups and #groups > 1 then
    -- An additive metre (3+3+2/8): a beat for each group, of its units.
    local beats, s = {}, 0
    for _, g in ipairs(groups) do
      local node = { s = s, e = s + g * unit, free = true, children = {}, beat = true }
      for k = 0, g - 1 do
        node.children[k + 1] = binary(s + k * unit, unit)
      end
      beats[#beats + 1] = node
      s = s + g * unit
    end
    return {
      root = { s = 0, e = bar, children = beats },
      bar = bar,
      beat = unit,
      beats = beats,
      compound = false,
      unit = unit,
      num = num,
      den = den,
      groups = groups,
    }
  end
  local compound = den >= 8 and num % 3 == 0 and num > 3
  local beat_len = compound and 3 * unit or unit
  local beats = {}
  for i = 0, (compound and num / 3 or num) - 1 do
    local s = i * beat_len
    local node
    if compound then
      node = { s = s, e = s + beat_len, free = true, children = {} }
      for k = 0, 2 do
        node.children[k + 1] = binary(s + k * unit, unit)
      end
    else
      node = binary(s, beat_len)
    end
    node.beat = true
    beats[#beats + 1] = node
  end
  local root = { s = 0, e = bar, children = beats }
  -- Four beats are heard as two halves.
  if #beats == 4 then
    root.children = {
      { s = 0, e = 2 * beat_len, children = { beats[1], beats[2] } },
      { s = 2 * beat_len, e = 4 * beat_len, children = { beats[3], beats[4] } },
    }
  end
  return {
    root = root,
    bar = bar,
    beat = beat_len,
    beats = beats,
    compound = compound,
    unit = unit,
    num = num,
    den = den,
  }
end

--- Where a click `t` beats into a bar lands when notes of `value` beats are
--- entered, as one counting the bar would put them: on a multiple of the
--- value from the start of the beat the click is in (on a beat when the
--- value is longer than one), and never later than the last such place.
function M.snap(meter, t, value)
  local beat = meter.beat
  local step = math.min(value, beat)
  local from = floor(t / beat + EPS) * beat
  local at = from + floor((t - from) / step + 0.5) * step
  if from + beat - t < abs(at - t) then at = from + beat end
  local last = floor((meter.bar - EPS) / beat) * beat
  last = last + floor((meter.bar - last) / step - EPS) * step
  return math.max(0, math.min(at, last))
end

local function on_child_boundary(node, t)
  if near(t, node.s) or near(t, node.e) then return true end
  for _, c in ipairs(node.children or {}) do
    if near(t, c.s) or near(t, c.e) then return true end
  end
  return false
end

local function emit(out, a, b) out[#out + 1] = { a, b } end

--- `a` to `b` of the division `node` of a bar, written into `out`: what
--- `M.split` does, made once rather than for every call (LuaJIT does not
--- compile what makes a function).
local function split_in(out, a, b, node, rest)
  local len = b - a
  if len < EPS then return end
  local base, dots = M.value_of(len)
  if base then
    if node.free and not (rest and dots > 0 and not node.beat and not near(a, node.s)) then return emit(out, a, b) end
    if on_child_boundary(node, a) then
      if on_child_boundary(node, b) then return emit(out, a, b) end
      -- A dot may carry a value into the next part of the bar.
      if dots == 1 and not rest and on_child_boundary(node, a + base) then return emit(out, a, b) end
    end
  end
  local children = node.children
  if not children then
    -- Below the smallest division: the largest values that fit.
    local t = a
    while b - t > EPS do
      local step
      for _, v in ipairs(M.BASES) do
        if v <= b - t + EPS then
          step = v
          break
        end
      end
      step = step or (b - t)
      emit(out, t, t + step)
      t = t + step
    end
    return
  end
  for _, c in ipairs(children) do
    if a >= c.s - EPS and a < c.e - EPS then
      if b <= c.e + EPS then return split_in(out, a, b, c, rest) end
      split_in(out, a, c.e, c, rest)
      return split_in(out, c.e, b, node, rest)
    end
  end
  emit(out, a, b)
end

--- Split the stretch `s` to `e` of a bar (beats from the bar's start) into
--- written values, as `{ { start, length }, ... }`. `rest` writes silence,
--- which is never dotted across a division of the bar.
function M.split(s, e, meter, rest)
  local out = {}
  split_in(out, s, e, meter.root, rest)
  return out
end

-- Pitch -------------------------------------------------------------------------------

local LETTER_PC = { [0] = 0, 2, 4, 5, 7, 9, 11 } -- C D E F G A B
local LETTER_FIFTHS = { [0] = 0, 2, 4, -1, 1, 3, 5 }
M.LETTERS = { [0] = "C", "D", "E", "F", "G", "A", "B" }
local SHARP_ORDER = { 3, 0, 4, 1, 5, 2, 6 } -- F C G D A E B
local FLAT_ORDER = { 6, 2, 5, 1, 4, 0, 3 } -- B E A D G C F

--- How the key alters a letter: 1 sharp, -1 flat, 0 neither.
function M.key_alter(letter, fifths)
  if fifths > 0 then
    for i = 1, fifths do
      if SHARP_ORDER[i] == letter then return 1 end
    end
  elseif fifths < 0 then
    for i = 1, -fifths do
      if FLAT_ORDER[i] == letter then return -1 end
    end
  end
  return 0
end

--- Spell a pitch in a key: `letter` (0 is C, 6 is B), `alter` in semitones,
--- `octave`, and `step`, the diatonic step counted from C-1 (C4 is 35).
--- Notes of the key take its letters; the others lean the way the key
--- does, as written music usually has them (C#, Eb, F#, G#, Bb in C major).
local spellings = {} -- by key and pitch class: { letter, alter }
function M.spell(pitch, fifths)
  fifths = fifths or 0
  local pc = pitch % 12
  local by_key = spellings[fifths]
  if not by_key then
    by_key = {}
    spellings[fifths] = by_key
  end
  local hit = by_key[pc]
  if hit then return M.spelled(hit[1], hit[2], pitch) end
  local best, best_d, best_f
  for letter = 0, 6 do
    for alter = -2, 2 do
      if (LETTER_PC[letter] + alter) % 12 == pc then
        local f = LETTER_FIFTHS[letter] + 7 * alter
        local d = abs(f - (fifths + 2))
        if not best or d < best_d - EPS or (near(d, best_d) and f > best_f) then
          best, best_d, best_f = { letter = letter, alter = alter }, d, f
        end
      end
    end
  end
  by_key[pc] = { best.letter, best.alter }
  return M.spelled(best.letter, best.alter, pitch)
end

--- A spelling with its octave and step, for a letter and alteration known
--- to sound as `pitch`.
function M.spelled(letter, alter, pitch)
  local octave = floor((pitch - alter) / 12) - 1
  return { letter = letter, alter = alter, octave = octave, step = (octave + 1) * 7 + letter, pitch = pitch }
end

--- The pitch written at a diatonic step with an alteration.
function M.pitch_of(step, alter)
  local octave = floor(step / 7)
  local letter = step - octave * 7
  return octave * 12 + LETTER_PC[letter] + (alter or 0)
end

--- The pitch at a step in a key: the letter as the key alters it.
function M.key_pitch(step, fifths)
  local letter = step % 7
  return M.pitch_of(step, M.key_alter(letter, fifths or 0))
end

--- Name of a spelled pitch: "F#4", "Bb3".
function M.name(sp)
  local acc = sp.alter == 1 and "#" or sp.alter == -1 and "b" or sp.alter == 2 and "x" or sp.alter == -2 and "bb" or ""
  return M.LETTERS[sp.letter] .. acc .. sp.octave
end

--- A key as a number of sharps (positive) or flats (negative), from a root
--- such as "D", "F#" or "Bb" and a scale or mode name.
local MODE_DEGREE = {
  major = 0,
  ionian = 0,
  pentatonic = 0,
  dorian = 2,
  phrygian = 4,
  lydian = -1,
  mixolydian = 1,
  minor = 3,
  aeolian = 3,
  harmonic_minor = 3,
  melodic_minor = 3,
  minor_pentatonic = 3,
  blues = 3,
  locrian = 5,
}
function M.fifths_of(root, scale)
  local letter, acc = tostring(root or "C"):match("^([A-Ga-g])([#b]*)$")
  if not letter then return 0 end
  local index
  for i = 0, 6 do
    if M.LETTERS[i] == letter:upper() then index = i end
  end
  local alter = (acc == "#" and 1) or (acc == "##" and 2) or (acc == "b" and -1) or (acc == "bb" and -2) or 0
  local f = LETTER_FIFTHS[index] + 7 * alter - (MODE_DEGREE[scale or "major"] or 0)
  if scale == "chromatic" or scale == "whole_tone" then return 0 end
  if f > 6 then
    f = f - 12
  elseif f < -6 then
    f = f + 12
  end
  return f
end

-- Staves ------------------------------------------------------------------------------

--- The step of each clef's bottom line: E4 for treble, G2 for bass.
M.CLEF_BOTTOM = {
  treble = 4 * 7 + 2 + 7,
  bass = 2 * 7 + 4 + 7,
  treble8 = 3 * 7 + 2 + 7,
  bass8 = 1 * 7 + 4 + 7,
  alto = 3 * 7 + 3 + 7,
  tenor = 3 * 7 + 1 + 7,
}
M.CLEFS = { "treble", "treble8", "bass", "bass8", "alto", "tenor" }

-- Where a key signature's sharps and flats go on the treble staff, in order.
local SHARP_POS = { 8, 5, 9, 6, 3, 7, 4 }
local FLAT_POS = { 4, 7, 3, 6, 2, 5, 1 }
local KEY_SHIFT = { treble = 0, treble8 = 0, bass = -2, bass8 = -2, alto = -1, tenor = 1 }

--- The staff positions of a key signature's signs on a clef, in order.
function M.key_positions(fifths, clef)
  local out = {}
  local list = fifths > 0 and SHARP_POS or FLAT_POS
  for i = 1, math.abs(fifths) do
    local pos = list[i] + (KEY_SHIFT[clef] or 0)
    -- The tenor clef's sharps would climb off the staff: an octave down.
    if pos > 9 then pos = pos - 7 end
    out[i] = pos
  end
  return out
end

--- Which staves a set of pitches is best written on: `{ "treble" }`,
--- `{ "bass" }` or `{ "treble", "bass" }`.
function M.choose_clef(pitches, fixed)
  if fixed and M.CLEF_BOTTOM[fixed] then return { fixed } end
  if fixed == "grand" then return { "treble", "bass" } end
  if #pitches == 0 then return { "treble" } end
  local low, high, sorted = 127, 0, {}
  for i, p in ipairs(pitches) do
    low, high = math.min(low, p), math.max(high, p)
    sorted[i] = p
  end
  table.sort(sorted)
  -- Within two ledger lines of the staff, and no further.
  local treble = low >= 57
  local bass = high <= 64
  if treble and bass then return { sorted[floor((#sorted + 1) / 2)] >= 60 and "treble" or "bass" } end
  if treble then return { "treble" } end
  if bass then return { "bass" } end
  return { "treble", "bass" }
end

-- Layout ------------------------------------------------------------------------------

local score_layer = require("notation.score")
M.score = score_layer

--- The bars a clip covers when one signature holds: `{ start, num, den,
--- number }` in clip beats, from the bar the clip starts in.
function M.even_bars(offset, length, num, den)
  local bar = num * 4 / den
  local first_bar = floor(offset / bar + EPS)
  local origin = first_bar * bar - offset
  local count = math.max(1, math.ceil((offset + math.max(length, EPS)) / bar - EPS) - first_bar)
  local out = {}
  for i = 1, count do
    out[i] = { start = origin + (i - 1) * bar, num = num, den = den, number = first_bar + i }
  end
  return out
end

local meters = {}
local function meter_of(num, den, groups)
  local key = num .. "/" .. den .. (groups and #groups > 1 and (":" .. table.concat(groups, "+")) or "")
  meters[key] = meters[key] or M.meter(num, den, groups)
  return meters[key]
end
M.meter_of = meter_of

--- Whether a place in a beat is written without a tuplet: on a 32nd.
local function plain(rel)
  local v = rel * 8
  return abs(v - floor(v + 0.5)) < 1e-4
end
local function multiple(rel, of)
  local v = rel / of
  return abs(v - floor(v + 0.5)) < 1e-4
end

--- The written length a tuplet of `n` takes the time of: the power of two
--- below it (3 in the time of 2, 5 of 4), and a duplet in the time of 3.
function M.tuplet_normal(n)
  if n == 2 then return 3 end
  local normal = 1
  while normal * 2 < n do
    normal = normal * 2
  end
  return normal
end

local function by_s(a, b) return a.s < b.s end

--- The tuplets voice `voice` of staff `staff` needs in a measure: the user's (`user`, `{ start,
--- length, n, normal, staff?, voice? }` in clip beats, or `plain` for none), and beats whose
--- divisions are not plain, as `{ s, e, n, ratio }` (written = played *
--- ratio). Two triplet beats in quarter-note triplets are one tuplet.
local function tuplet_spans(m, bounds, user, staff, voice)
  local spans = {}
  local bar = { start = m.start, num = m.meter.num, den = m.meter.den }
  local beats = score_layer.beats_of(bar)
  local said = {}
  for _, tp in ipairs(user or {}) do
    local mine = (not tp.staff or tp.staff == staff) and (not tp.voice or tp.voice == voice)
    if mine and tp.start < m.start + m.length - EPS and tp.start + tp.length > m.start + EPS then
      if not tp.plain then
        local normal = tp.normal or M.tuplet_normal(tp.n)
        spans[#spans + 1] = { s = tp.start, e = tp.start + tp.length, n = tp.n, ratio = tp.n / normal, user = true }
      end
      for bi, b in ipairs(beats) do
        if b.s >= tp.start - EPS and b.e <= tp.start + tp.length + EPS then said[bi] = true end
      end
    end
  end
  for bi, b in ipairs(beats) do
    local need, fits3, fits2, fits4 = false, true, true, true
    local fits5, fits6, fits7, sixths, halves = true, true, true, false, true
    local inner, on_eighth = 0, false
    for _, x in ipairs(bounds) do
      if x > b.s + EPS and x < b.e - EPS then
        local rel = x - b.s
        inner = inner + 1
        if multiple(rel, b.len / 3) then
          on_eighth = true
        else
          sixths = true
        end
        if not plain(rel) then need = true end
        if not multiple(rel, b.len / 12) then fits3 = false end
        if not multiple(rel, b.len / 6) then fits6 = false end
        if not multiple(rel, b.len / 20) then fits5 = false end
        if not multiple(rel, b.len / 28) then fits7 = false end
        if not multiple(rel, b.len / 2) then halves = false end
        if not multiple(rel, b.len / 4) then fits2 = false end
        if not multiple(rel, b.len / 8) then fits4 = false end
      end
    end
    -- In 6/8 a beat halved is a duplet, not two dotted eighths.
    if b.compound and inner > 0 and fits2 and not on_eighth then need = true end
    if need and not said[bi] then
      if not b.compound and fits6 and sixths then
        -- Sixteenths in sixes: a sextuplet.
        spans[#spans + 1] = { s = b.s, e = b.e, n = 6, ratio = 1.5 }
      elseif not b.compound and fits3 then
        spans[#spans + 1] = { s = b.s, e = b.e, n = 3, ratio = 1.5 }
      elseif not b.compound and fits5 then
        spans[#spans + 1] = { s = b.s, e = b.e, n = 5, ratio = 1.25 }
      elseif not b.compound and fits7 then
        spans[#spans + 1] = { s = b.s, e = b.e, n = 7, ratio = 1.75 }
      elseif b.compound and fits2 and halves then
        -- Two in the time of three eighths.
        spans[#spans + 1] = { s = b.s, e = b.e, n = 2, ratio = 2 / 3 }
      elseif b.compound and fits4 then
        -- Four eighths (or sixteenths) in the time of three.
        spans[#spans + 1] = { s = b.s, e = b.e, n = 4, ratio = 4 / 3 }
      end
    end
  end
  -- Quarter-note triplets over two beats.
  table.sort(spans, by_s)
  local out, i = {}, 1
  while i <= #spans do
    local a, b = spans[i], spans[i + 1]
    local joined = false
    if b and a.n == 3 and b.n == 3 and near(a.e, b.s) and not a.user and not b.user then
      local len = b.e - a.s
      local all = true
      for _, x in ipairs(bounds) do
        if x > a.s + EPS and x < b.e - EPS and not multiple(x - a.s, len / 3) then all = false end
      end
      if all then
        out[#out + 1] = { s = a.s, e = b.e, n = 3, ratio = 1.5 }
        i = i + 2
        joined = true
      end
    end
    if not joined then
      out[#out + 1] = a
      i = i + 1
    end
  end
  return out
end

-- Values a tuplet's notes are written with, longest first.
local TUPLET_VALUES = {}
for _, base in ipairs(M.BASES) do
  TUPLET_VALUES[#TUPLET_VALUES + 1] = base * 1.5
  TUPLET_VALUES[#TUPLET_VALUES + 1] = base
end
table.sort(TUPLET_VALUES, function(a, b) return a > b end)

--- Split a stretch inside a tuplet into written values.
local function split_tuplet(a, b, span)
  local out = {}
  local t, w1 = (a - span.s) * span.ratio, (b - span.s) * span.ratio
  while w1 - t > EPS do
    local step
    for _, v in ipairs(TUPLET_VALUES) do
      if v <= w1 - t + EPS then
        step = v
        break
      end
    end
    step = step or (w1 - t)
    out[#out + 1] = { span.s + t / span.ratio, span.s + (t + step) / span.ratio }
    t = t + step
  end
  return out
end

--- Lay notes out as measures. `notes` as a clip gives them (`pitch`,
--- `start`, `length`, optional `velocity` and `meta`); `opts`:
---   length    the clip's length in beats
---   offset    where the clip starts in the project, for where bars fall (0)
---   num, den  the time signature (4/4), when `bars` is not given
---   bars      the bars the clip covers: `{ { start, num, den, number } }` in
---             clip beats, where the signature changes along the song
---   fifths    the key: sharps above 0, flats below (0)
---   clef      "treble", "bass", "grand", or nil to choose
---   tempo     beats a minute (120), for the transcription's windows
---   settings  the transcription's settings (`notation.score`), with
---             `mode = "raw"` for every note as played, rounded to `grid`
---   tuplets   the user's tuplets, `{ { start, length, n } }`
---   grid      the raw view's grid, and where a pointer lands (a sixteenth)
---   stems     false leaves out stems and beams (for a score made of it)
--- Returns `{ measures, staves, meter, fifths, grid, origin, score }`; each
--- measure has `number` (the project's bar, from 1), `start` and `length`
--- in clip beats, its `meter`, and `staves[i]`, a list of events by time:
---   kind     "note" or "rest"; `voice` 1 or 2
---   start, length, base, dots; `tuplet` the tuplet it is in, if any
---   notes    for a note: `{ pitch, index, letter, alter, octave, step, pos,
---            acc (the accidental shown, or nil), courtesy, tie (to the next
---            event), tied (from the one before) }`, lowest first
---   next     the event a tie goes to; `grace`, notes before it; `arpeggio`;
---            `staccato`; `source` the score event it writes
---   stem     1 up, -1 down, nil for none; `beam` a group number or nil;
---            `flags` the number of beams or flags; `whole` a whole-bar rest
function M.layout(notes, opts)
  local sc, o = M.transcription(notes, opts)
  return M.engrave_score(sc, o)
end

--- The transcription of notes (`notation.score`'s events) with what
--- `M.engrave_score` writes it with: `{ bars, staves, fifths, grid,
--- tuplets, stems }`. `opts` as `M.layout`'s.
function M.transcription(notes, opts)
  opts = opts or {}
  local bars = opts.bars
  if not bars or #bars == 0 then
    bars = M.even_bars(opts.offset or 0, opts.length or 0, opts.num or 4, opts.den or 4)
  end
  local fifths = opts.fifths or 0
  local finish = bars[#bars].start + bars[#bars].num * 4 / bars[#bars].den

  local pitches = {}
  for i, n in ipairs(notes) do
    pitches[i] = n.pitch
  end
  local staves = M.choose_clef(pitches, opts.clef)

  local settings = score_layer.settings(opts.settings)
  if opts.grid and not (opts.settings and opts.settings.grid) then settings.grid = opts.grid end
  local ctx = {
    bars = bars,
    finish = finish,
    tempo = opts.tempo or 120,
    staves = staves,
    settings = settings,
    tuplets = opts.tuplets,
    debug = opts.debug,
  }
  local sc = settings.mode == "raw" and score_layer.raw(notes, ctx) or score_layer.transcribe(notes, ctx)
  return sc,
    {
      bars = bars,
      staves = staves,
      fifths = fifths,
      grid = opts.grid or settings.grid or 0.25,
      tuplets = settings.mode ~= "raw" and opts.tuplets or nil,
      stems = opts.stems,
    }
end

--- The empty measures of bars (`{ start, num, den, number }`), each with a
--- list of events for each of `staves` staves.
function M.measures_of(bars, staves)
  local measures = {}
  for i, b in ipairs(bars) do
    local meter = meter_of(b.num, b.den)
    local m = { number = b.number or i, index = i, start = b.start, length = meter.bar, meter = meter, staves = {} }
    for s = 1, staves do
      m.staves[s] = {}
    end
    measures[i] = m
  end
  return measures
end

local function by_start(a, b) return a.start < b.start end

--- The lines a transcription (`sc`) is written in on measures: for each
--- staff `s` and voice `v`, `lines[s][v] = { segments, pieces }`. A segment
--- is a stretch of sound (`chord`, a score event) or silence, `{ s, e,
--- chord? }`; `pieces[mi]` are the parts of segments in measure `mi`,
--- `{ a, b, seg }` (a voice other than the first is silent only in the
--- measures it sounds in).
function M.lines(sc, measures, staves)
  local origin = measures[1].start
  local finish = measures[#measures].start + measures[#measures].length
  local function measure_at(t)
    local lo, hi = 1, #measures
    while lo < hi do
      local mid = floor((lo + hi + 1) / 2)
      if measures[mid].start <= t + EPS then
        lo = mid
      else
        hi = mid - 1
      end
    end
    return lo
  end
  local lines = {}
  for s = 1, staves do
    local voices = {}
    for _, ev in ipairs(sc.events) do
      if ev.staff == s and ev.start < finish - EPS then
        voices[ev.voice or 1] = voices[ev.voice or 1] or {}
        table.insert(voices[ev.voice or 1], ev)
      end
    end
    voices[1] = voices[1] or {}
    lines[s] = {}
    for v, list in pairs(voices) do
      table.sort(list, by_start)
      -- Sound and silence.
      local segments, t = {}, origin
      local touched = {}
      for i, c in ipairs(list) do
        local e = math.min(c.start + c.length, finish)
        if list[i + 1] then e = math.min(e, list[i + 1].start) end
        if e > c.start + EPS then
          if c.start > t + EPS then segments[#segments + 1] = { s = t, e = c.start } end
          segments[#segments + 1] = { s = c.start, e = e, chord = c }
          for mi = measure_at(c.start), measure_at(e - 1e-3) do
            touched[mi] = true
          end
          t = e
        end
      end
      if finish > t + EPS then segments[#segments + 1] = { s = t, e = finish } end
      -- Pieces of each segment, measure by measure.
      local pieces = {}
      for _, seg in ipairs(segments) do
        local a = seg.s
        seg.pieces = {}
        while a < seg.e - EPS do
          local mi = measure_at(a)
          local m = measures[mi]
          local b = math.min(seg.e, m.start + m.length)
          if seg.chord or v == 1 or touched[mi] then
            pieces[mi] = pieces[mi] or {}
            table.insert(pieces[mi], { a = a, b = b, seg = seg })
          end
          a = b
        end
      end
      lines[s][v] = { segments = segments, pieces = pieces }
    end
  end
  return lines
end

--- The written events of the pieces (as `M.lines` gives them) of staff `s`
--- and voice `v` in measure `m`, each added to `m.staves[s]` and to its
--- segment's `pieces` (and to the piece's `evs`, if it has that list), in
--- time order within each piece. `tuplets` are the user's (see `M.layout`).
function M.write_pieces(m, s, v, pieces, tuplets)
  local bounds = {}
  for _, p in ipairs(pieces) do
    bounds[#bounds + 1] = p.a
    bounds[#bounds + 1] = p.b
  end
  local spans = tuplet_spans(m, bounds, tuplets, s, v)
  for k, sp in ipairs(spans) do
    sp.id = s * 100000 + v * 10000 + m.index * 10 + k
    sp.staff, sp.voice = s, v
  end
  for _, p in ipairs(pieces) do
    local rest = not p.seg.chord
    local out = {}
    if rest and v == 1 and near(p.a, m.start) and near(p.b, m.start + m.length) then
      out[1] = { p.a, p.b, whole = true }
    else
      -- Cut at the tuplets' edges; inside a tuplet by its values, outside by the metre.
      local cuts = { p.a }
      for _, sp in ipairs(spans) do
        if sp.s > p.a + EPS and sp.s < p.b - EPS then cuts[#cuts + 1] = sp.s end
        if sp.e > p.a + EPS and sp.e < p.b - EPS then cuts[#cuts + 1] = sp.e end
      end
      table.sort(cuts)
      cuts[#cuts + 1] = p.b
      for k = 1, #cuts - 1 do
        local a, b = cuts[k], cuts[k + 1]
        local inside
        for _, sp in ipairs(spans) do
          if a >= sp.s - EPS and b <= sp.e + EPS then inside = sp end
        end
        if inside then
          for _, piece in ipairs(split_tuplet(a, b, inside)) do
            out[#out + 1] = { piece[1], piece[2], tuplet = inside }
          end
        else
          for _, piece in ipairs(M.split(a - m.start, b - m.start, m.meter, rest)) do
            out[#out + 1] = { m.start + piece[1], m.start + piece[2] }
          end
        end
      end
    end
    for _, piece in ipairs(out) do
      local len = piece[2] - piece[1]
      local base, dots = M.value_of(piece.tuplet and len * piece.tuplet.ratio or len, 2)
      local ev = {
        kind = rest and "rest" or "note",
        start = piece[1],
        length = len,
        base = base,
        dots = dots or 0,
        measure = m.index,
        staff = s,
        voice = v,
        tuplet = piece.tuplet,
        source = p.seg.chord,
      }
      if piece.whole then
        ev.whole, ev.base, ev.dots = true, 4, 0
      end
      table.insert(p.seg.pieces, ev)
      table.insert(m.staves[s], ev)
      if p.evs then p.evs[#p.evs + 1] = ev end
    end
  end
end

--- Tie written piece `ev` of a segment of chord `c` (or silence): `k` of
--- `count` pieces the segment is written in.
function M.tie_piece(ev, c, k, count)
  if not c then return end
  ev.notes = {}
  for j, n in ipairs(c.notes) do
    ev.notes[j] = { pitch = n.pitch, index = n.index, meta = n.meta, tie = k < count, tied = k > 1 }
  end
  if k == 1 then
    ev.arpeggio, ev.staccato = c.arpeggio, c.staccato
    if c.grace then
      ev.grace = {}
      for j, n in ipairs(c.grace) do
        ev.grace[j] = { pitch = n.pitch, index = n.index, meta = n.meta }
      end
    end
  end
end

local function by_start_voice(a, b)
  if not near(a.start, b.start) then return a.start < b.start end
  return a.voice < b.voice
end

--- Put a measure's events of each staff in time order, voice by voice.
function M.order(m)
  for _, evs in ipairs(m.staves) do
    table.sort(evs, by_start_voice)
  end
end

--- Measures of written events from score events (see `notation.score`).
function M.engrave_score(sc, o)
  local bars, staves = o.bars, o.staves
  local measures = M.measures_of(bars, #staves)
  local lines = M.lines(sc, measures, #staves)
  for s, voices in ipairs(lines) do
    for v, line in pairs(voices) do
      for mi, pieces in pairs(line.pieces) do
        M.write_pieces(measures[mi], s, v, pieces, o.tuplets)
      end
      -- Ties from piece to piece of one segment.
      for _, seg in ipairs(line.segments) do
        table.sort(seg.pieces, by_start)
        for k, ev in ipairs(seg.pieces) do
          ev.next = seg.pieces[k + 1]
          M.tie_piece(ev, seg.chord, k, #seg.pieces)
        end
      end
    end
  end
  for _, m in ipairs(measures) do
    M.order(m)
  end
  local result = {
    measures = measures,
    staves = staves,
    meter = measures[1].meter,
    fifths = o.fifths or 0,
    grid = o.grid or 0.25,
    origin = bars[1].start,
    score = sc,
  }
  M.spell_all(result)
  if o.stems ~= false then M.stems_and_beams(result) end
  return result
end

--- Spell every note and decide which accidentals are shown.
function M.spell_all(layout)
  for s, clef in ipairs(layout.staves) do
    local before = {} -- steps left altered against the key by the last bar
    for _, m in ipairs(layout.measures) do
      before = M.spell_measure(m, s, clef, m.fifths or layout.fifths, before)
    end
  end
end

--- Spell a note of a measure, with `state` (the bar's alterations so far),
--- `reminded` and `before` (what the bar before left altered).
local function spell_note(n, tied, fifths, bottom, state, reminded, before)
  local sp
  local want = n.meta and n.meta.notation
  if n.spelled then
    -- Written in a score: spelled as it is kept.
    sp = M.spelled(n.letter, n.alter, n.pitch)
  elseif type(want) == "table" and want.pitch == n.pitch and want.letter and want.alter then
    sp = M.spelled(want.letter, want.alter, n.pitch)
  else
    sp = M.spell(n.pitch, fifths)
  end
  n.letter, n.alter, n.octave, n.step = sp.letter, sp.alter, sp.octave, sp.step
  n.pos = sp.step - bottom
  if not tied then
    local current = state[sp.step]
    if current == nil then current = M.key_alter(sp.letter, fifths) end
    if sp.alter ~= current then
      n.acc = sp.alter
    elseif before[sp.step] and not reminded[sp.step] and state[sp.step] == nil then
      -- The bar before altered this note: say it is back.
      n.acc, n.courtesy = sp.alter, true
    end
    state[sp.step] = sp.alter
    reminded[sp.step] = true
  end
end

local function by_step(a, b) return a.step < b.step or (a.step == b.step and a.pitch < b.pitch) end

--- Spell the notes of staff `s` of a measure and decide which accidentals
--- are shown, `before` being the steps the bar before left altered against
--- the key (`{ [step] = true }`). Returns the steps this bar leaves altered.
function M.spell_measure(m, s, clef, fifths, before)
  -- A score's measures may change clef.
  local bottom = M.CLEF_BOTTOM[m.clefs and m.clefs[s] or clef]
  local state, reminded = {}, {}
  for _, ev in ipairs(m.staves[s]) do
    for _, n in ipairs(ev.grace or {}) do
      spell_note(n, false, fifths, bottom, state, reminded, before)
    end
    for _, n in ipairs(ev.notes or {}) do
      spell_note(n, n.tied, fifths, bottom, state, reminded, before)
    end
    if ev.notes then table.sort(ev.notes, by_step) end
  end
  local out = {}
  for step, alter in pairs(state) do
    if alter ~= M.key_alter(step % 7, fifths) then out[step] = true end
  end
  return out
end

local function stem_for(events)
  local high, low = -math.huge, math.huge
  for _, ev in ipairs(events) do
    for _, n in ipairs(ev.notes) do
      high, low = math.max(high, n.pos), math.min(low, n.pos)
    end
  end
  -- The note furthest from the middle line decides; on the line, down.
  return (high - 4) >= (4 - low) and -1 or 1
end

--- The span of the bar that eighths starting at `t` are beamed within.
local function beam_group(meter, t)
  local m = meter
  if m.unit < 1 and not m.compound then return 0, m.bar end
  for _, b in ipairs(m.beats) do
    if t >= b.s - EPS and t < b.e - EPS then return b.s, b.e end
  end
  return 0, m.bar
end

local function breaks_beam(ev)
  if ev.source and ev.source.beam == "break" then return true end
  for _, n in ipairs(ev.notes or {}) do
    local own = n.meta and n.meta.notation
    if type(own) == "table" and own.beam == "break" then return true end
  end
  return false
end

--- How far a rest of voice `v` moves from the middle line, in staff
--- positions, with another voice on its staff: the upper voice's up and the
--- lower's down, by whole spaces, and further when the other voice's notes
--- sounding meanwhile would touch it (a rest reaches about three positions
--- above and below its middle).
local function rest_shift(evs, rest, v)
  local shift = v == 1 and 2 or -4
  local e = rest.start + rest.length
  for _, other in ipairs(evs) do
    if other.voice ~= v and other.notes and other.start < e - EPS and other.start + other.length > rest.start + EPS then
      for _, n in ipairs(other.notes) do
        if v == 1 then
          shift = math.max(shift, math.ceil(n.pos / 2) * 2)
        else
          shift = math.min(shift, floor((n.pos - 9) / 2) * 2)
        end
      end
    end
  end
  return shift
end

--- Whether a beam group of measure `m` is two plain eighths on the beat.
local function plain_pair(g, m)
  if #g.events ~= 2 then return false end
  for _, ev in ipairs(g.events) do
    if ev.base ~= 0.5 or ev.dots ~= 0 or ev.tuplet then return false end
  end
  return near(g.events[1].start - m.start, g.g0) and near(g.events[2].start - m.start, g.g0 + 0.5)
end

--- Stems, flags and beams; with two voices on a staff, the first's stems up
--- and the second's down, and their rests out of each other's way.
function M.stems_and_beams(layout)
  local next_beam = 0
  for s = 1, #layout.staves do
    for _, m in ipairs(layout.measures) do
      local meter = m.meter
      local evs = m.staves[s]
      local voices = {}
      for _, ev in ipairs(evs) do
        voices[ev.voice] = voices[ev.voice] or {}
        table.insert(voices[ev.voice], ev)
      end
      local two = false
      for v in pairs(voices) do
        if v > 1 then two = true end
      end
      for v, list in pairs(voices) do
        local forced = two and (v == 1 and 1 or -1) or nil
        -- Runs of beamable notes inside one beat group.
        local groups, current = {}, nil
        for _, ev in ipairs(list) do
          local rel = ev.start - m.start
          local g0, g1 = beam_group(meter, rel)
          if ev.tuplet then
            g0, g1 = ev.tuplet.s - m.start, ev.tuplet.e - m.start
          end
          local beamable = ev.kind == "note" and ev.base and ev.base <= 0.5 and rel + ev.length <= g1 + EPS
          if beamable and current and near(current.g0, g0) and not breaks_beam(ev) then
            current.events[#current.events + 1] = ev
          elseif beamable then
            current = { g0 = g0, g1 = g1, events = { ev } }
            groups[#groups + 1] = current
          else
            current = nil
          end
        end
        -- In 4/4, four eighths filling half the bar share one beam.
        if meter.num == 4 and meter.den == 4 then
          local merged = {}
          local i = 1
          while i <= #groups do
            local a, b = groups[i], groups[i + 1]
            if
              b
              and near(a.g1, b.g0)
              and (near(a.g0, 0) or near(a.g0, 2))
              and plain_pair(a, m)
              and plain_pair(b, m)
              and not breaks_beam(b.events[1])
            then
              merged[#merged + 1] =
                { g0 = a.g0, g1 = b.g1, events = { a.events[1], a.events[2], b.events[1], b.events[2] } }
              i = i + 2
            else
              merged[#merged + 1] = a
              i = i + 1
            end
          end
          groups = merged
        end
        for _, g in ipairs(groups) do
          if #g.events >= 2 then
            next_beam = next_beam + 1
            local dir = forced or stem_for(g.events)
            for _, ev in ipairs(g.events) do
              ev.beam, ev.stem = next_beam, dir
            end
          end
        end
        for _, ev in ipairs(list) do
          if ev.kind == "note" then
            ev.flags = M.flags(ev.base or 1)
            if ev.base and ev.base >= 4 then
              ev.stem = nil
            elseif not ev.beam then
              ev.stem = forced or stem_for({ ev })
            end
          elseif two then
            ev.shift = rest_shift(evs, ev, v)
          end
        end
      end
    end
  end
end

-- Spacing ---------------------------------------------------------------------------------

--- Give each measure its places across: a slot for every time something
--- starts on any staff, each as wide as `o.unit(d)` for the `d` beats until
--- the next, with `o.acc` more in front of a slot where an accidental is
--- shown (or an arpeggio sign), `o.grace` for each grace note, `o.lead`
--- before the first and `o.tail` after the last. Sets `m.slots` (`{ t, x }`,
--- the last one the measure's end) and `m.width`.
---
--- With `o.room(ev)` (what an event reaches left and right of its time:
--- accidentals, grace notes and the arpeggio on the left, heads, dots and
--- flags on the right) space is added only where it does not fit, as
--- Gould has it: each slot at least `o.gap` clear of the one before and of
--- the barline; `o.acc` and `o.grace` are then not used.
function M.space(layout, o)
  local room = o.room
  for _, m in ipairs(layout.measures) do
    local times, acc, graces, left, right = {}, {}, {}, {}, {}
    for _, evs in ipairs(m.staves) do
      for _, ev in ipairs(evs) do
        local key = floor(ev.start * 4096 + 0.5)
        times[key] = ev.start
        if room then
          local l, r = room(ev)
          left[key], right[key] = math.max(left[key] or 0, l), math.max(right[key] or 0, r)
        else
          for _, n in ipairs(ev.notes or {}) do
            if n.acc then acc[key] = true end
          end
          if ev.arpeggio then acc[key] = true end
          if ev.grace then graces[key] = math.max(graces[key] or 0, #ev.grace) end
        end
      end
    end
    local keys = {}
    for k in pairs(times) do
      keys[#keys + 1] = k
    end
    table.sort(keys)
    local slots, x = {}, o.lead
    for i, k in ipairs(keys) do
      if room then
        local before = keys[i - 1]
        x = math.max(x, (before and slots[i - 1].x + right[before] or 0) + o.gap + left[k])
      end
      if acc[k] then x = x + o.acc end
      if graces[k] then x = x + (o.grace or o.acc) * graces[k] end
      slots[i] = { t = times[k], x = x }
      local nxt = keys[i + 1] and times[keys[i + 1]] or (m.start + m.length)
      x = x + o.unit(nxt - times[k])
    end
    slots[#slots + 1] = { t = m.start + m.length, x = x }
    local width = x + o.tail
    -- What stands right of the last event (a lyric) stays inside the measure.
    local last = keys[#keys]
    if room and last then width = math.max(width, slots[#keys].x + right[last] + o.gap) end
    m.slots, m.width = slots, width
  end
end

--- Where a beat falls across a spaced measure.
function M.x_of(m, t)
  local slots = m.slots
  if t <= slots[1].t then return slots[1].x end
  for i = 1, #slots - 1 do
    local a, b = slots[i], slots[i + 1]
    if t < b.t + EPS then return a.x + (b.x - a.x) * (t - a.t) / math.max(EPS, b.t - a.t) end
  end
  return slots[#slots].x
end

--- The beat at a place across a spaced measure.
function M.t_of(m, x)
  local slots = m.slots
  if x <= slots[1].x then return slots[1].t end
  for i = 1, #slots - 1 do
    local a, b = slots[i], slots[i + 1]
    if x < b.x then return a.t + (b.t - a.t) * (x - a.x) / math.max(EPS, b.x - a.x) end
  end
  return slots[#slots].t
end

local function by_start_staff_voice(a, b)
  if not near(a.start, b.start) then return a.start < b.start end
  if a.staff ~= b.staff then return a.staff < b.staff end
  return a.voice < b.voice
end

-- The events of each layout, by staff (0 for all), as last sorted: the
-- cursor's every move reads them, and a clip of thousands of notes takes a
-- while to sort.
local sorted_events = setmetatable({}, { __mode = "k" })

--- Every event of a layout, with its measure, staff by staff in time order.
--- To read: the list is kept for the next call while the layout holds the
--- same events.
function M.events(layout, staff)
  local out = {}
  for _, m in ipairs(layout.measures) do
    for s, evs in ipairs(m.staves) do
      if not staff or staff == s then
        for _, ev in ipairs(evs) do
          out[#out + 1] = ev
        end
      end
    end
  end
  local kept = sorted_events[layout]
  local was = kept and kept[staff or 0]
  if was and #was == #out then
    local same = {}
    for _, ev in ipairs(was) do
      same[ev] = true
    end
    local all = true
    for _, ev in ipairs(out) do
      if not same[ev] then
        all = false
        break
      end
    end
    -- And still in order, should an event have moved.
    for i = 2, all and #was or 0 do
      if by_start_staff_voice(was[i], was[i - 1]) then
        all = false
        break
      end
    end
    if all then return was end
  end
  -- Measure by measure, which is quicker than sorting them all; measures
  -- follow each other in time, else they are sorted all together.
  out = {}
  local one = {}
  for _, m in ipairs(layout.measures) do
    for s, evs in ipairs(m.staves) do
      if not staff or staff == s then
        for _, ev in ipairs(evs) do
          one[#one + 1] = ev
        end
      end
    end
    table.sort(one, by_start_staff_voice)
    for i, ev in ipairs(one) do
      out[#out + 1] = ev
      one[i] = nil
    end
  end
  for i = 2, #out do
    if by_start_staff_voice(out[i], out[i - 1]) then
      table.sort(out, by_start_staff_voice)
      break
    end
  end
  kept = kept or {}
  kept[staff or 0] = out
  sorted_events[layout] = kept
  return out
end

--- A short text of a staff's events, for tests and for reading at a
--- glance: "q C4 | e. D4 s E4 | h~ G4". Values: w h q e s t (whole to 32nd),
--- a dot each, `~` tied to the next, `r` a rest, `R` a whole-bar rest,
--- chords in brackets, accidentals shown as # b n; a tuplet as `3{ ... }`,
--- grace notes in brackets before their note (`[D5]E5`), `'` a staccato,
--- `^` or `v` an arpeggio up or down. `voice` picks one voice (the first
--- unless told; 0 for all).
local LETTER_OF = { [4] = "w", [2] = "h", [1] = "q", [0.5] = "e", [0.25] = "s", [0.125] = "t" }
local function acc_text(n)
  local acc = n.acc
      and ((n.acc == 1 and "#") or (n.acc == -1 and "b") or (n.acc == 0 and "n") or (n.acc == 2 and "x") or "bb")
    or ""
  if n.courtesy then acc = "(" .. acc .. ")" end
  return M.LETTERS[n.letter] .. acc .. n.octave
end
function M.text(layout, staff, voice)
  voice = voice or 1
  local bars = {}
  for _, m in ipairs(layout.measures) do
    local words = {}
    local open
    for _, ev in ipairs(m.staves[staff or 1]) do
      if voice == 0 or ev.voice == voice then
        if open and ev.tuplet ~= open then
          words[#words] = words[#words] .. "}"
          open = nil
        end
        local prefix = ""
        if ev.tuplet and ev.tuplet ~= open then
          prefix = ev.tuplet.n .. "{"
          open = ev.tuplet
        end
        if ev.whole then
          words[#words + 1] = "R"
        else
          local value = (LETTER_OF[ev.base] or "?") .. string.rep(".", ev.dots)
          if ev.kind == "rest" then
            words[#words + 1] = prefix .. value .. "r"
          else
            local names = {}
            for i, n in ipairs(ev.notes) do
              names[i] = acc_text(n)
            end
            local tie = ev.notes[1].tie and "~" or ""
            local grace = ""
            if ev.grace then
              local g = {}
              for i, n in ipairs(ev.grace) do
                g[i] = acc_text(n)
              end
              grace = "[" .. table.concat(g, " ") .. "]"
            end
            local body = #names > 1 and "<" .. table.concat(names, " ") .. ">" or names[1]
            local marks = (ev.arpeggio == 1 and "^" or ev.arpeggio == -1 and "v" or "") .. (ev.staccato and "'" or "")
            words[#words + 1] = prefix .. value .. tie .. " " .. grace .. body .. marks
          end
        end
      end
    end
    if open then words[#words] = words[#words] .. "}" end
    bars[#bars + 1] = table.concat(words, " ")
  end
  return table.concat(bars, " | ")
end

return M
