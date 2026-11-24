-- The built-in reading of harmony: which chord sounds when, and in which key,
-- from notes alone. Pure functions on note sets in project beats
-- `{ pitch, start, length, velocity }`; `paw.harmony` feeds them the song.
--
-- Chords. Time is cut into windows (`step` beats). Each window weighs its
-- pitch classes by how long they sound in it, a short note off the beat
-- counting half, and the lowest sounding pitch half again. Every chord
-- template (twelve roots times the qualities below) is scored against that:
-- the weight of its tones less the weight of the rest, less something for
-- each tone missing (little for a fifth), less a little for each tone past
-- three, plus a bonus when the bass is its root. A chord then holds across
-- windows unless the next is better by more than what a change costs, so a
-- passing note does not make a chord of its own (a dynamic programme, as
-- Viterbi's, over the windows).
--
-- Keys. Each bar's pitch classes, with half of their neighbours', are
-- correlated with Krumhansl and Kessler's major and minor profiles for all
-- twelve tonics; a key holds over bars unless another fits better by more
-- than a modulation costs.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.

--- A chord quality: steps above the root, its names, and what it costs.
local record Quality
  name: string
  steps: {integer}
  suffix: string
  roman: string
  minor: boolean
  cost: number
end

--- A note in project beats: what the reading reads of it (`paw.harmony.notes`
--- gives more).
local interface Note
  pitch: integer
  start: number
  length: number
  velocity: number
end

--- A chord that `chords` reads: pitch classes 0..11.
local record Chord
  at: number
  length: number
  root: integer
  quality: string
  bass: integer
  tones: {integer}
end

--- A key that `keys` reads.
local record Key
  at: number
  length: number
  tonic: integer
  mode: string
end

--- The options of `chords`.
local record ChordOptions
  step: number
  from: number
  to: number
  bar: number
end

-- Weights of the twelve pitch classes, by pitch class.
local type Weights = {integer: number}

--- What the bass of a stretch of time is read from: for each pitch class,
--- how long it is the lowest that sounds (`held`), and the lowest pitch of
--- all with how long it sounds (`lowest`, `lasts`). Two stretches side by
--- side add up, so a chord's bass comes from the windows it covers.
local record Bass
  held: Weights
  lowest: integer
  lasts: number
end

--- One window of the chord reading (`finish`): what sounds in it, and the
--- score of each chord there. `flat` is a window where too little sounds to
--- name a chord; `scores` is nil then and in silence. `beat` is true when
--- the window was weighed with the rest of its beat.
local record Window
  at: number
  length: number
  total: number
  flat: boolean
  beat: boolean
  scores: {number}
  bass: Bass
end

--- The notes of one clip as the song's reading keeps them: lists of
--- their starts, lengths, pitches and velocities, sorted by start, with
--- the longest note (`run`).
local record Run
  start: {number}
  length: {number}
  pitch: {integer}
  velocity: {number}
  n: integer
  longest: number
end

--- What sounds over a stretch of time, before its bass is chosen
--- (`part`), in one list of numbers: the weights of the twelve pitch
--- classes (1 to 12), their total (13), the lowest pitch (14, `math.huge`
--- in silence) and how long it sounds (15), then from 16 the lowest pitch
--- over time, three numbers for each piece: from, to and the pitch, in
--- order. The parts of one stretch, or of stretches side by side, merge
--- into one (`merge`): the song's reading keeps a portion for each part and
--- window, and adds up those of a window.
local type Portion = {number}
local TOTAL, LOWEST, LASTS, PIECES = 13, 14, 15, 16

--- What `finish` calls for the part of a window's whole beat.
local type BeatOf = function(): Portion

local record M
  type Quality = Quality
  type Run = Run
  type Portion = Portion
  EMPTY: Portion
  type Note = Note
  type Chord = Chord
  type Key = Key
  type ChordOptions = ChordOptions
  type Weights = Weights
  type Bass = Bass
  type Window = Window
  qualities: {Quality}
  by_quality: {string: Quality}
  MAJOR: {number}
  MINOR: {number}
  fit: function(w: Weights, bass: integer, total: number, root: integer, q: Quality): number
  correlate: function(h: Weights, profile: {number}, tonic: integer): number
  key_path: function(notes_hist: {Weights}, bars: {number}, chords?: {Chord}, pause?: function()): {Key}
end

-- Qualities: steps above the root. `cost` is what it takes to prefer it to a
-- plainer chord with fewer tones; `minor` makes its Roman numeral lower case.
M.qualities = {
  {name = "maj", steps = {0, 4, 7}, suffix = "", roman = "", cost = 0},
  {name = "min", steps = {0, 3, 7}, suffix = "m", roman = "", minor = true, cost = 0},
  {name = "dim", steps = {0, 3, 6}, suffix = "dim", roman = "°", minor = true, cost = 0.02},
  {name = "aug", steps = {0, 4, 8}, suffix = "aug", roman = "+", cost = 0.04},
  {name = "sus4", steps = {0, 5, 7}, suffix = "sus4", roman = "sus4", cost = 0.03},
  {name = "sus2", steps = {0, 2, 7}, suffix = "sus2", roman = "sus2", cost = 0.04},
  {name = "5", steps = {0, 7}, suffix = "5", roman = "5", cost = 0.05},
  {name = "7", steps = {0, 4, 7, 10}, suffix = "7", roman = "7", cost = 0.01},
  {name = "maj7", steps = {0, 4, 7, 11}, suffix = "maj7", roman = "maj7", cost = 0.02},
  {name = "m7", steps = {0, 3, 7, 10}, suffix = "m7", roman = "7", minor = true, cost = 0.01},
  {name = "m7b5", steps = {0, 3, 6, 10}, suffix = "m7b5", roman = "ø7", minor = true, cost = 0.02},
  {name = "dim7", steps = {0, 3, 6, 9}, suffix = "dim7", roman = "°7", minor = true, cost = 0.02},
  {name = "mmaj7", steps = {0, 3, 7, 11}, suffix = "m(maj7)", roman = "(maj7)", minor = true, cost = 0.05},
  {name = "6", steps = {0, 4, 7, 9}, suffix = "6", roman = "6", cost = 0.04},
  {name = "m6", steps = {0, 3, 7, 9}, suffix = "m6", roman = "6", minor = true, cost = 0.04},
  {name = "7sus4", steps = {0, 5, 7, 10}, suffix = "7sus4", roman = "7sus4", cost = 0.03},
  {name = "add9", steps = {0, 2, 4, 7}, suffix = "add9", roman = "add9", cost = 0.04},
  {name = "9", steps = {0, 2, 4, 7, 10}, suffix = "9", roman = "9", cost = 0.02},
  {name = "maj9", steps = {0, 2, 4, 7, 11}, suffix = "maj9", roman = "maj9", cost = 0.03},
  {name = "m9", steps = {0, 2, 3, 7, 10}, suffix = "m9", roman = "9", minor = true, cost = 0.02},
}
M.by_quality = {}
for i_q = 1, #M.qualities do
  local q = M.qualities[i_q]
  M.by_quality[q.name] = q
end

local EXTRA = 0.06 -- each tone past three
local MISSING = 0.12 -- each tone of the chord that does not sound
local MISSING_FIFTH = 0.04
local MISSING_ROOT = 0.2
local ROOT_IN_BASS = 0.2
local CHANGE = 0.45 -- what a change of chord costs, in beats of a perfect fit
local NONE = -0.5 -- "no chord" where something sounds

--- The bass of a stretch `span` beats long, by what it is read from: of
--- the lowest pitches over time, the class that lasts longest, and how long.
local function choose(b: Bass, span: number): integer, number
  local bass: integer
  local most: number = 0
  for pc, d in pairs(b.held) do
    if d > most or (d == most and bass and pc < bass) then
      bass, most = pc, d
    end
  end
  -- An arpeggio's bass sounds a moment and leaves the others to it: the
  -- lowest pitch of all is the bass when it sounds an eighth of the time.
  if b.lowest and b.lowest % 12 ~= bass and b.lasts >= span / 8 then
    bass, most = b.lowest % 12, b.lasts
  end
  return bass, most
end

-- The work tables of `part`, kept from one call to the next: a reading
-- weighs thousands of stretches of a few notes each, and new tables for
-- each were most of what the collector had to do. Each call writes what
-- it reads, or clears it first.
local la: {number} = {}
local lb: {number} = {}
local lp: {integer} = {}
local ends: {number} = {}
local ends_used = 0 -- how much of `ends` the last call filled
local cuts: {number} = {}
local first_of: {integer: integer} = {}
local next_of: {integer} = {}
local low_of: {integer} = {}
local skip: {integer} = {}

--- The first piece from `i` that no lower pitch took: `skip` leads past
--- the pieces taken, its paths made short as they are walked.
local function untaken(i: integer): integer
  local j = i
  while skip[j] do
    j = skip[j]
  end
  while skip[i] do
    local after = skip[i]
    skip[i] = j
    i = after
  end
  return j
end

--- Notes as a `Run`: `notes` sorted by start, in their order.
function M.run(notes: {Note}): Run
  local run: Run = {start = {}, length = {}, pitch = {}, velocity = {}, n = #notes, longest = 0}
  for i = 1, #notes do
    local n = notes[i]
    run.start[i], run.length[i], run.pitch[i], run.velocity[i] = n.start, n.length, n.pitch, n.velocity
    if n.length > run.longest then
      run.longest = n.length
    end
  end
  return run
end

-- A stretch where nothing sounds. It is shared: no one changes a part.
local EMPTY: Portion = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, math.huge, 0}

-- LuaJIT's `table.new`: a list made at its size. A part grown one piece at
-- a time would take up to twice its room, and the reading keeps thousands.
local record Globals
  require: function(string): function(integer, integer): Portion
end
local new_list = (_G as Globals).require("table.new")

-- Where `part` and `merge` make a part before it is copied at its size.
local work: Portion = {}

local function start_work()
  for k = 1, 12 do
    work[k] = 0
  end
  work[TOTAL], work[LOWEST], work[LASTS] = 0, math.huge, 0
end

--- The first `n` numbers of `work` as a part of its own.
local function copy_work(n: integer): Portion
  local p = new_list(n, 0)
  for k = 1, n do
    p[k] = work[k]
  end
  return p
end
M.EMPTY = EMPTY

--- What the notes of `run`, `offset` beats later, sound from `from` to
--- `to` (a `Part`). A note counts for how long it sounds there, a short
--- note off the beat half; the lowest pitch over time is cut where a note
--- starts or ends.
function M.portion(run: Run, offset: number, from: number, to: number): Portion
  local starts, lengths, pitches = run.start, run.length, run.pitch
  -- The first note that can sound at `from`.
  local lo, hi = 1, run.n + 1
  while lo < hi do
    local mid = (lo + hi) // 2
    if offset + starts[mid] + run.longest < from - 1e-9 then
      lo = mid + 1
    else
      hi = mid
    end
  end
  start_work()
  local p = work
  local total: number = 0
  -- What sounds in the stretch, note by note: from `la` to `lb`, pitch `lp`
  -- (the starts in order, as the notes are). `ends` are the ends before `to`.
  local count, stops, low_pitch, high_pitch = 0, 0, math.huge, -math.huge
  for i = lo, run.n do
    local s = offset + starts[i]
    if s >= to then
      break
    end
    local length = lengths[i]
    local a, b = math.max(from, s), math.min(to, s + length)
    if b > a then
      local pitch = pitches[i]
      local off_beat = math.abs(s - math.floor(s + 0.5)) > 1e-6
      local amount = (b - a) * ((off_beat and length < 0.5) and 0.5 or 1)
      local pc = pitch % 12 + 1
      p[pc] = p[pc] + amount
      total = total + amount
      count = count + 1
      la[count], lb[count], lp[count] = a, b, pitch
      low_pitch, high_pitch = math.min(low_pitch, pitch), math.max(high_pitch, pitch)
      if b < to then
        stops = stops + 1
        ends[stops] = b
      end
    end
  end
  if count == 0 then
    return EMPTY
  end
  p[TOTAL] = total
  -- What the last call left after the ends of this one goes, so that the
  -- sort sees only these.
  for i = stops + 1, ends_used do
    ends[i] = nil
  end
  ends_used = stops
  -- Time is cut at each start and end: the starts come in order, so only
  -- the ends are sorted, and the two are merged.
  table.sort(ends)
  local ncuts = 0
  do
    local i, j = 0, 1
    -- `from`, then the starts; the ends, then `to` for each note that lasts to it.
    local x = from
    while true do
      local y = j <= stops and ends[j] or (j <= count + 1 and to or nil)
      if not x and not y then
        break
      end
      ncuts = ncuts + 1
      if y and (not x or y < x) then
        cuts[ncuts] = y
        j = j + 1
      else
        cuts[ncuts] = x
        i = i + 1
        x = i <= count and la[i] or nil
      end
    end
  end
  -- The lowest pitch over each piece between two cuts: piece `i` is from
  -- `cuts[i]` to `cuts[i + 1]`, and a low covers the pieces in one run.
  -- The lows from the lowest up each take the pieces of their run that no
  -- lower one took; `skip` leads past the pieces taken, so that each piece
  -- is looked at about once rather than once for each low.
  local pieces = ncuts - 1
  for i = 1, pieces + 1 do
    low_of[i], skip[i] = nil, nil
  end
  -- The notes by pitch: a list for each pitch, through `next_of`.
  for k = count, 1, -1 do
    next_of[k] = first_of[lp[k]]
    first_of[lp[k]] = k
  end
  for pitch = math.floor(low_pitch), math.floor(high_pitch) do
    local k = first_of[pitch]
    first_of[pitch] = nil
    while k do
      -- The first piece with `a <= cuts[i] + 1e-9` and the last with
      -- `b >= cuts[i + 1] - 1e-9`: the tests of a low that covers a piece.
      local a, b = la[k], lb[k]
      local lo2, hi2 = 1, pieces + 1
      while lo2 < hi2 do
        local mid = (lo2 + hi2) // 2
        if a <= cuts[mid] + 1e-9 then
          hi2 = mid
        else
          lo2 = mid + 1
        end
      end
      local from_piece = lo2
      lo2, hi2 = 0, pieces
      while lo2 < hi2 do
        local mid = (lo2 + hi2 + 1) // 2
        if b >= cuts[mid + 1] - 1e-9 then
          lo2 = mid
        else
          hi2 = mid - 1
        end
      end
      local to_piece = lo2
      local i = untaken(from_piece)
      while i <= to_piece do
        low_of[i] = pitch
        skip[i] = i + 1
        i = untaken(i + 1)
      end
      k = next_of[k]
    end
  end
  -- The pieces, those side by side with one low made one.
  local n = PIECES - 1
  for i = 1, pieces do
    local a, b = cuts[i], cuts[i + 1]
    local low = low_of[i]
    if b - a > 1e-9 and low then
      if n >= PIECES and p[n - 1] == a and p[n] == low then
        p[n - 1] = b
      else
        p[n + 1], p[n + 2], p[n + 3] = a, b, low
        n = n + 3
      end
    end
  end
  local lowest: integer
  local lasts: number = 0
  for k = 1, count do
    local pitch = lp[k]
    if not lowest or pitch < lowest then
      lowest, lasts = pitch, 0
    end
    if pitch == lowest then
      lasts = lasts + (lb[k] - la[k])
    end
  end
  p[LOWEST], p[LASTS] = lowest, lasts
  return copy_work(n)
end

-- Two lists of pieces made one with the lower pitch where both sound
-- (`merge`), kept from one call to the next.
local scratch_a: {number} = {}
local scratch_b: {number} = {}

--- The pieces of `a` (from `ai`, before `an`) and of `b` (from `bi`,
--- before `bn`), each in order, as one list in `out` from 1, with the
--- lower pitch where both sound and pieces side by side with one pitch
--- made one. Returns how much of `out` it wrote.
local function lower(
  a: {number}, ai: integer, an: integer, b: {number}, bi: integer, bn: integer, out: {number}
): integer
  local n = 0
  local t = -math.huge -- the time written so far
  while ai < an or bi < bn do
    if ai < an and a[ai + 1] <= t then
      ai = ai + 3
    elseif bi < bn and b[bi + 1] <= t then
      bi = bi + 3
    else
      local fa = ai < an and math.max(a[ai], t) or math.huge
      local fb = bi < bn and math.max(b[bi], t) or math.huge
      local s = math.min(fa, fb)
      local e, p: number, number
      if fa <= s and fb <= s then
        e, p = math.min(a[ai + 1], b[bi + 1]), math.min(a[ai + 2], b[bi + 2])
      elseif fa <= s then
        e, p = math.min(a[ai + 1], fb), a[ai + 2]
      else
        e, p = math.min(b[bi + 1], fa), b[bi + 2]
      end
      if n > 0 and out[n - 1] == s and out[n] == p then
        out[n - 1] = e
      else
        out[n + 1], out[n + 2], out[n + 3] = s, e, p
        n = n + 3
      end
      t = e
    end
  end
  return n
end

--- The portions of one stretch of time, or of stretches side by side, as
--- one portion: the weights add up, and the lowest pitch over time is the
--- lowest of theirs. One portion that sounds gives that portion.
function M.merge(portions: {Portion}): Portion
  local first: Portion
  local more = false
  for i_q = 1, #portions do
    local q = portions[i_q]
    if q[TOTAL] > 0 then
      if first then
        more = true
        break
      end
      first = q
    end
  end
  if not first then
    return EMPTY
  end
  if not more then
    return first
  end
  start_work()
  local p = work
  local cur, cur_i, cur_n = first, PIECES, #first + 1
  local into = scratch_a
  for i_q = 1, #portions do
    local q = portions[i_q]
    if q[TOTAL] > 0 then
      for k = 1, 12 do
        p[k] = p[k] + q[k]
      end
      p[TOTAL] = p[TOTAL] + q[TOTAL]
      if q[LOWEST] < p[LOWEST] then
        p[LOWEST], p[LASTS] = q[LOWEST], q[LASTS]
      elseif q[LOWEST] == p[LOWEST] then
        p[LASTS] = p[LASTS] + q[LASTS]
      end
      if q ~= first then
        local n = lower(cur, cur_i, cur_n, q, PIECES, #q + 1, into)
        cur, cur_i, cur_n = into, 1, n + 1
        into = into == scratch_a and scratch_b or scratch_a
      end
    end
  end
  for k = cur_i, cur_n - 1 do
    p[PIECES + k - cur_i] = cur[k]
  end
  return copy_work(PIECES - 1 + cur_n - cur_i)
end

--- The weights of a part with the bass's share, the bass, the total, and
--- what the bass was read from (nil in silence). `span` is how long the
--- stretch is.
local function weights_of(p: Portion, span: number): Weights, integer, number, Bass
  local w: Weights = {}
  for pc = 0, 11 do
    w[pc] = p[pc + 1]
  end
  local total = p[TOTAL]
  if total == 0 then
    return w, nil, 0
  end
  local held: Weights = {}
  for k = PIECES, #p, 3 do
    local a, b = p[k], p[k + 1]
    if b - a > 1e-9 then
      local pc = math.floor(p[k + 2]) % 12
      held[pc] = (held[pc] or 0) + (b - a)
    end
  end
  local summary: Bass = {held = held, lowest = math.floor(p[LOWEST]), lasts = p[LASTS]}
  local bass, most = choose(summary, span)
  if bass then
    w[bass] = w[bass] + most * 0.5
    total = total + most * 0.5
  end
  return w, bass, total, summary
end

--- How many pitch classes weigh something (a twentieth of the total) in `w`.
local function classes(w: Weights, total: number): integer
  local n = 0
  for pc = 0, 11 do
    if w[pc] > 0.05 * total then
      n = n + 1
    end
  end
  return n
end

--- How well the chord `root` `quality` fits weights `w` with `bass` and `total`.
local function fit(w: Weights, bass: integer, total: number, root: integer, q: Quality): number
  local inside: number = 0
  for i_s = 1, #q.steps do
    local s = q.steps[i_s]
    inside = inside + w[(root + s) % 12]
  end
  local score = (2 * inside - total) / total
  for i_s = 1, #q.steps do
    local s = q.steps[i_s]
    if w[(root + s) % 12] < 0.08 * total then
      -- A triad may lose its fifth; a bigger chord without it is too often
      -- another triad in another inversion (F A D is D minor, not F6).
      score = score - (s == 0 and MISSING_ROOT or (s == 7 and #q.steps == 3) and MISSING_FIFTH or MISSING)
    end
  end
  score = score - math.max(0, #q.steps - 3) * EXTRA - q.cost
  if bass == root then
    score = score + ROOT_IN_BASS
  end
  return score
end
M.fit = fit

-- Every chord a window may hold: twelve roots times the qualities. The
-- label after the last is "no chord".
local record Label
  root: integer
  q: Quality
end
local LABELS: {Label} = {}
for root = 0, 11 do
  for i_q = 1, #M.qualities do
    local q = M.qualities[i_q]
    LABELS[#LABELS + 1] = {root = root, q = q}
  end
end
local NL = #LABELS + 1
-- The scores of a window where nothing names a chord: no chord, unless the
-- chord before holds (`FLAT`), and after a bar of silence no chord at all
-- (`GAP`).
local FLAT: {number} = {}
local GAP: {number} = {}
for l = 1, NL - 1 do
  FLAT[l], GAP[l] = 0, -math.huge
end
FLAT[NL], GAP[NL] = 1e-6, 1e-6

-- The qualities as `scores_of` reads them, one list for each of five
-- steps: a step (from the root), and what it costs when it does not
-- sound. A quality with fewer steps has the step 24, where nothing
-- weighs, at no cost. So the loop over the labels has no inner loop and
-- no branch: LuaJIT leaves a short inner loop, and a branch that goes one
-- way and then the other, at a cost each time.
local S1, S2, S3, S4, S5: {integer}, {integer}, {integer}, {integer}, {integer} = {}, {}, {}, {}, {}
local C1, C2, C3, C4, C5: {number}, {number}, {number}, {number}, {number} = {}, {}, {}, {}, {}
local REST_OF: {number} = {} -- for each quality, what its tones past three and its kind cost
do
  local steps_lists, costs_lists = {S1, S2, S3, S4, S5}, {C1, C2, C3, C4, C5}
  for i = 1, #M.qualities do
    local q = M.qualities[i]
    for k = 1, 5 do
      local s = q.steps[k]
      steps_lists[k][i] = s or 24
      costs_lists[k][i] = s and (s == 0 and MISSING_ROOT or (s == 7 and #q.steps == 3) and MISSING_FIFTH or MISSING)
        or 0
    end
    REST_OF[i] = math.max(0, #q.steps - 3) * EXTRA + q.cost
  end
end
local NQ = #M.qualities
-- The weights from 1, two octaves of them so that no step wraps, then 0;
-- and 1 where a weight is too small to count as sounding (0 else).
local twice: {number} = {}
local silent: {number} = {}
for k = 1, 48 do
  twice[k], silent[k] = 0, 0
end

--- The score of each label (`LABELS`, then no chord) for weights `w` with
--- `bass` and `total`, times `length`: what `fit` gives each, in one pass.
--- Into the list `into` when given.
local function scores_of(w: Weights, bass: integer, total: number, length: number, into?: {number}): {number}
  local low = 0.08 * total
  for pc = 0, 11 do
    local v = w[pc]
    local off = v < low and 1 or 0
    twice[pc + 1], twice[pc + 13], silent[pc + 1], silent[pc + 13] = v, v, off, off
  end
  for k = 25, 36 do
    silent[k] = 1
  end
  local scores = into or new_list(NL, 0)
  local l = 0
  for root = 1, 12 do
    local in_bass = bass == root - 1 and ROOT_IN_BASS or 0
    for q = 1, NQ do
      local i1, i2, i3, i4, i5 = root + S1[q], root + S2[q], root + S3[q], root + S4[q], root + S5[q]
      local inside = twice[i1] + twice[i2] + twice[i3] + twice[i4] + twice[i5]
      local missing = silent[i1] * C1[q] + silent[i2] * C2[q] + silent[i3] * C3[q] + silent[i4] * C4[q] + silent[i5] * C5[q]
      l = l + 1
      scores[l] = ((2 * inside - total) / total - missing - REST_OF[q] + in_bass) * length
    end
  end
  scores[NL] = NONE * length
  return scores
end

--- One window of the chord reading from what sounds in it (`p`, a part):
--- from `at`, `length` beats long, with windows of `step` beats. `beat`
--- gives the part of the window's whole beat, when the window needs it.
--- `old`, a window that no one reads any more, gives its lists to the new one.
function M.finish(p: Portion, at: number, length: number, step: number, beat: BeatOf, old?: Window): Window
  local w, bass, total, low = weights_of(p, length)
  local win: Window = {at = at, length = length, total = total, bass = low}
  -- One pitch alone is no chord: it is weighed with the rest of its beat
  -- (an arpeggio's notes come one at a time), and if the beat has no
  -- other either (a melody alone) it says nothing, and the chord before
  -- holds over it.
  local ew, ebass, etotal = w, bass, total
  if total > 1e-9 and classes(w, total) < 2 and step < 1 then
    ew, ebass, etotal = weights_of(beat(), 1)
    win.beat = true
  end
  if total > 1e-9 and classes(ew, etotal) < 2 then
    win.flat = true
  elseif total > 1e-9 then
    win.scores = scores_of(ew, ebass, etotal, length, old and old.scores)
  end
  return win
end

--- The bass over windows `k` to `j`, `span` beats: nil if nothing sounds.
local function bass_over(windows: {Window}, k: integer, j: integer, span: number): integer
  local held: Weights = {}
  local lowest: integer
  local lasts: number = 0
  local any = false
  for t = k, j do
    local b = windows[t].bass
    if b then
      any = true
      for pc, d in pairs(b.held) do
        held[pc] = (held[pc] or 0) + d
      end
      if b.lowest then
        if not lowest or b.lowest < lowest then
          lowest, lasts = b.lowest, b.lasts
        elseif b.lowest == lowest then
          lasts = lasts + b.lasts
        end
      end
    end
  end
  if not any then
    return nil
  end
  return (choose({held = held, lowest = lowest, lasts = lasts}, span))
end

--- The chords of a run of windows (`finish` makes each, one after another
--- with no gap): a chord holds across windows unless the next is better by
--- more than what a change costs. Silence of `bar` beats ends a chord.
--- `pause`, if given, is called after each 64 windows, so that a reading
--- in slices can stop there (paw/harmony/song.tl). `rows`, if given, keeps
--- the work rows for the next call: a caller that decodes often gives its
--- own.
function M.decode(windows: {Window}, bar: number, pause?: function(), rows?: {{number}}): {Chord}
  local n = #windows
  if n == 0 then
    return {}
  end
  -- Row `i` is the best score of a path that ends in each label at window
  -- `i`. A label holds from the row before (`stay`), or changes from the
  -- best label of that row (`firsts[i]`) for `changes[i]`: the walk back
  -- tells which from the row before, so the rows need not keep it.
  rows = rows or {}
  local firsts: {integer} = {}
  local changes: {number} = {}
  local prev: {number}
  local quiet: number = 0 -- beats since something last sounded
  for i = 1, n do
    local win = windows[i]
    local total = win.total
    local scores: {number}
    if total > 1e-9 then
      quiet = 0
      scores = win.scores or FLAT
    else
      quiet = quiet + win.length
      -- Silence lets the chord before hold over it, unless it lasts a bar.
      scores = quiet >= bar - 1e-9 and GAP or FLAT
    end
    local cur = rows[i]
    if not cur then
      cur = new_list(NL, 0)
      rows[i] = cur
    end
    if not prev then
      for l = 1, NL do
        cur[l] = scores[l]
      end
    else
      local best = -math.huge
      for l = 1, NL do
        best = math.max(best, prev[l])
      end
      local best_l = 1
      for l = 1, NL do
        if prev[l] == best and best > -math.huge then
          best_l = l
          break
        end
      end
      -- A change costs a little more in silence, so that the chord
      -- before holds over a rest rather than the next one starting early.
      local change = best - CHANGE - (total > 1e-9 and 0 or 0.01)
      for l = 1, NL do
        cur[l] = math.max(prev[l], change) + scores[l]
      end
      firsts[i], changes[i] = best_l, change
    end
    prev = cur
    if pause and i % 64 == 0 then
      pause()
    end
  end

  -- Walk back from the best end.
  local path: {integer} = {}
  local best, best_l = -math.huge, NL
  for l = 1, NL do
    if prev[l] > best then
      best, best_l = prev[l], l
    end
  end
  for k = n, 2, -1 do
    path[k] = best_l
    if rows[k - 1][best_l] < changes[k] then
      best_l = firsts[k]
    end
  end
  path[1] = best_l

  -- Runs of one label are chords. A chord holds over a rest up to the next
  -- chord; with nothing after it, it ends where the last of its notes does.
  local out: {Chord} = {}
  local k = 1
  while k <= #windows do
    local l, j = path[k], k
    while j < #windows and path[j + 1] == l do
      j = j + 1
    end
    if l ~= NL then
      local label = LABELS[l]
      local a, b = windows[k].at, windows[j].at + windows[j].length
      if j == #windows or path[j + 1] == NL then
        local t = j
        while t >= k and windows[t].total <= 1e-9 do
          b = windows[t].at
          t = t - 1
        end
      end
      if b > a then
        -- The bass over the whole chord: what its windows read of it.
        local bass = bass_over(windows, k, j, b - a)
        local tones: {integer} = {}
        for t = 1, #label.q.steps do
          local s = label.q.steps[t]
          tones[t] = (label.root + s) % 12
        end
        out[#out + 1] = {
          at = a, length = b - a, root = label.root, quality = label.q.name, bass = bass or label.root, tones = tones
        }
      end
    end
    k = j + 1
  end
  return out
end

--- Chords over notes in project beats, from `from` to `to` (the notes'
--- span when nil), in windows of `step` beats (0.5). Each chord:
--- `{ at, length, root, quality, bass, tones }` with pitch classes 0..11.
function M.chords(notes: {Note}, opts?: ChordOptions): {Chord}
  opts = opts or {}
  local step = opts.step or 0.5
  local sorted: {Note} = {}
  for i = 1, #notes do
    local n = notes[i]
    sorted[i] = n
  end
  table.sort(sorted, function(a: Note, b: Note): boolean return a.start < b.start end)
  if #sorted == 0 then
    return {}
  end
  local first, last = math.huge, -math.huge
  for i_n = 1, #sorted do
    local n = sorted[i_n]
    first, last = math.min(first, n.start), math.max(last, n.start + n.length)
  end
  local run = M.run(sorted)
  local from = math.floor((opts.from or first) / step + 1e-9) * step
  local to = math.min(opts.to or last, last)
  local windows: {Window} = {}
  local at = from
  while at < to - 1e-9 do
    local beat = math.floor(at + 1e-9)
    local length = math.min(step, to - at)
    windows[#windows + 1] = M.finish(
      M.portion(run, 0, at, at + length),
      at,
      length,
      step,
      function(): Portion return M.portion(run, 0, beat, beat + 1) end
    )
    at = at + step
  end
  return M.decode(windows, opts.bar or 4)
end

-- Keys ---------------------------------------------------------------------------

-- Krumhansl and Kessler's probe-tone profiles, from the tonic up.
M.MAJOR = {6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88}
M.MINOR = {6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17}
local MODULATION = 1 -- what a change of key costs, in correlation: a few bars' worth
local OUTSIDE = 1.5 -- what a bar loses for the share of it outside the key's scale
local LEAN = 0.3 -- how much each bar leans to the song's overall key
-- The neighbouring bars, heard with each: how far, and how much.
local NEAR: {integer} = {-2, -1, 1, 2}
local NEAR_WEIGHT: {number} = {0.25, 0.5, 0.5, 0.25}
-- The pitch classes of a major key, and of a minor one with its raised
-- sixth and seventh (melodic and harmonic minor are still the key).
local SCALE: {string: {integer: boolean}} = {
  major = {[0] = true, [2] = true, [4] = true, [5] = true, [7] = true, [9] = true, [11] = true},
  minor = {
    [0] = true, [2] = true, [3] = true, [5] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true
  },
}

--- Add pitch class `pc` from `s` to `e` to the bars it sounds in, times
--- `weight`.
local function add(hist: {integer: Weights}, bars: {number}, pc: integer, s: number, e: number, weight: number)
  -- The first bar that ends after `s`.
  local lo, hi = 1, #bars
  while lo < hi do
    local mid = (lo + hi) // 2
    if bars[mid + 1] > s then
      hi = mid
    else
      lo = mid + 1
    end
  end
  for b = lo, #bars - 1 do
    if bars[b] >= e then
      break
    end
    local a, z = math.max(s, bars[b]), math.min(e, bars[b + 1])
    if z > a then
      hist[b][pc] = hist[b][pc] + (z - a) * weight
    end
  end
end

--- How well a histogram of pitch classes fits a key's profile from `tonic`,
--- from -1 to 1 (Pearson's correlation).
local function correlate(h: Weights, profile: {number}, tonic: integer): number
  local hm, pm: number, number = 0, 0
  for pc = 0, 11 do
    hm, pm = hm + h[pc], pm + profile[pc + 1]
  end
  hm, pm = hm / 12, pm / 12
  local num, dh, dp: number, number, number = 0, 0, 0
  for pc = 0, 11 do
    local x, y = h[pc] - hm, profile[(pc - tonic) % 12 + 1] - pm
    num, dh, dp = num + x * y, dh + x * x, dp + y * y
  end
  if dh == 0 then
    return 0
  end
  return num / math.sqrt(dh * dp)
end
M.correlate = correlate

--- Keys over notes in project beats, bar by bar. `bars` is a list of bar
--- starts, with the end after the last bar. When `chords` (as `chords`
--- gives them) are given, their roots and basses count two times. The
--- harmony tells more about the tonic than the notes of a melody. Each key
--- is `{ at, length, tonic, mode }`, with mode "major" or "minor".
function M.keys(notes: {Note}, bars: {number}, chords?: {Chord}): {Key}
  local n = #bars - 1
  if n < 1 then
    return {}
  end
  local hist: {Weights} = {}
  for b = 1, n do
    hist[b] = {}
    for pc = 0, 11 do
      hist[b][pc] = 0
    end
  end
  for i_note = 1, #notes do
    local note = notes[i_note]
    add(hist, bars, note.pitch % 12, note.start, note.start + note.length, 1)
  end
  return M.key_path(hist, bars, chords)
end

--- Add to `h` how long each pitch class of `run`, `offset` beats later,
--- sounds from `from` to `to`.
function M.bar_part(run: Run, offset: number, from: number, to: number, h: Weights)
  local starts, lengths, pitches = run.start, run.length, run.pitch
  local lo, hi = 1, run.n + 1
  while lo < hi do
    local mid = (lo + hi) // 2
    if offset + starts[mid] + run.longest < from - 1e-9 then
      lo = mid + 1
    else
      hi = mid
    end
  end
  for i = lo, run.n do
    local s = offset + starts[i]
    if s >= to then
      break
    end
    local a, z = math.max(s, from), math.min(s + lengths[i], to)
    if z > a then
      local pc = pitches[i] % 12
      h[pc] = h[pc] + (z - a)
    end
  end
end

--- The keys from the pitch classes of each bar (`hist`, as `bar_part`
--- gives them, which it leaves as they are) and the chords, as `keys`.
--- `pause`, if given, is called after each 16 bars, as `decode` does.
function M.key_path(notes_hist: {Weights}, bars: {number}, chords?: {Chord}, pause?: function()): {Key}
  local n = #bars - 1
  if n < 1 then
    return {}
  end
  local hist: {integer: Weights} = {}
  for b = 1, n do
    hist[b] = {}
    for pc = 0, 11 do
      hist[b][pc] = notes_hist[b][pc]
    end
  end
  for _, c in ipairs(chords or {}) do
    add(hist, bars, c.root, c.at, c.at + c.length, 1)
    add(hist, bars, c.bass or c.root, c.at, c.at + c.length, 0.5)
  end
  local record Candidate
    tonic: integer
    mode: string
    profile: {number}
    scale: {integer: boolean}
  end
  local candidates: {Candidate} = {}
  for tonic = 0, 11 do
    candidates[#candidates + 1] = {tonic = tonic, mode = "major", profile = M.MAJOR, scale = SCALE.major}
    candidates[#candidates + 1] = {tonic = tonic, mode = "minor", profile = M.MINOR, scale = SCALE.minor}
  end
  -- The song as a whole leans each bar towards its overall key, so that a
  -- few bars that fit another key equally well are not a modulation.
  local whole: Weights = {}
  for pc = 0, 11 do
    whole[pc] = 0
    for b = 1, n do
      whole[pc] = whole[pc] + hist[b][pc]
    end
  end
  local lean: {number} = {}
  for c = 1, #candidates do
    local cand = candidates[c]
    lean[c] = LEAN * correlate(whole, cand.profile, cand.tonic)
  end
  local prev: {number}
  local back: {{integer}} = {}
  local sounding: {boolean} = {}
  for b = 1, n do
    local h: Weights = {}
    local sum: number = 0
    for pc = 0, 11 do
      h[pc] = hist[b][pc]
      for k = 1, 4 do
        local near = hist[b + NEAR[k]]
        if near then
          h[pc] = h[pc] + NEAR_WEIGHT[k] * near[pc]
        end
      end
      sum = sum + hist[b][pc]
    end
    sounding[b] = sum > 0
    local cur: {number} = {}
    local from: {integer} = {}
    local best, best_c = -math.huge, 1
    if prev then
      for c = 1, #candidates do
        if prev[c] > best then
          best, best_c = prev[c], c
        end
      end
    end
    local total: number = 0
    for pc = 0, 11 do
      total = total + h[pc]
    end
    for c = 1, #candidates do
      local cand = candidates[c]
      local score: number = 0
      if sum > 0 then
        -- How well the profile fits, less what sounds outside the scale.
        local outside: number = 0
        for pc = 0, 11 do
          if not cand.scale[(pc - cand.tonic) % 12] then
            outside = outside + h[pc]
          end
        end
        score = correlate(h, cand.profile, cand.tonic) - OUTSIDE * outside / total + lean[c]
      end
      if not prev then
        cur[c], from[c] = score, c
      elseif prev[c] >= best - MODULATION then
        cur[c], from[c] = prev[c] + score, c
      else
        cur[c], from[c] = best - MODULATION + score, best_c
      end
    end
    back[b], prev = from, cur
    if pause and b % 16 == 0 then
      pause()
    end
  end
  local path: {integer} = {}
  local best, best_c = -math.huge, 1
  for c = 1, #candidates do
    if prev[c] > best then
      best, best_c = prev[c], c
    end
  end
  for b = n, 1, -1 do
    path[b] = best_c
    best_c = back[b][best_c]
  end
  local out: {Key} = {}
  for b = 1, n do
    if sounding[b] then
      local cand = candidates[path[b]]
      local last = out[#out]
      if last and last.tonic == cand.tonic and last.mode == cand.mode then
        last.length = bars[b + 1] - last.at
      else
        out[#out + 1] = {at = bars[b], length = bars[b + 1] - bars[b], tonic = cand.tonic, mode = cand.mode}
      end
    elseif out[#out] then
      -- A silent bar keeps the key before it.
      out[#out].length = bars[b + 1] - out[#out].at
    end
  end
  return out
end

return M
