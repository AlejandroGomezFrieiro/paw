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

--- One window of the chord reading (`window`): what sounds in it, and the
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

local record M
  type Quality = Quality
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
  key_path: function(notes_hist: {Weights}, bars: {number}, chords?: {Chord}): {Key}
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
for _, q in ipairs(M.qualities) do
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

-- The work tables of `weigh`, kept from one call to the next: a reading
-- weighs hundreds of windows of hundreds of notes each, and new tables for
-- each window were most of what the collector had to do. Each call writes
-- what it reads, or clears it first.
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

--- Weights of the twelve pitch classes between `from` and `to`, the bass's
--- pitch class, the total, and what the bass was read from (nil in
--- silence). `notes` sorted by start; those before `first` have ended
--- before `from`.
local function weigh(notes: {Note}, from: number, to: number, first?: integer): Weights, integer, number, Bass
  local w: Weights = {}
  local total: number = 0
  for pc = 0, 11 do
    w[pc] = 0
  end
  -- What sounds in the window, note by note: from `la` to `lb`, pitch `lp`
  -- (the starts in order, as the notes are). `ends` are the ends before `to`.
  local count, stops, low_pitch, high_pitch = 0, 0, math.huge, -math.huge
  for i = first or 1, #notes do
    local n = notes[i]
    if n.start >= to then
      break
    end
    local a, b = math.max(from, n.start), math.min(to, n.start + n.length)
    if b > a then
      local off_beat = math.abs(n.start - math.floor(n.start + 0.5)) > 1e-6
      local amount = (b - a) * ((off_beat and n.length < 0.5) and 0.5 or 1)
      w[n.pitch % 12] = w[n.pitch % 12] + amount
      total = total + amount
      count = count + 1
      la[count], lb[count], lp[count] = a, b, n.pitch
      low_pitch, high_pitch = math.min(low_pitch, n.pitch), math.max(high_pitch, n.pitch)
      if b < to then
        stops = stops + 1
        ends[stops] = b
      end
    end
  end
  if total == 0 then
    return w, nil, 0
  end
  -- What the last call left after the ends of this one goes, so that the
  -- sort sees only these.
  for i = stops + 1, ends_used do
    ends[i] = nil
  end
  ends_used = stops
  -- The bass: of the lowest pitches over time, the class that lasts longest.
  -- Time is cut at each start and end: the starts come in order, so only
  -- the ends are sorted, and the two are merged.
  table.sort(ends)
  local ncuts = 0
  do
    local i, j, starts = 0, 1, count
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
        x = i <= starts and la[i] or nil
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
      local lo, hi = 1, pieces + 1
      while lo < hi do
        local mid = (lo + hi) // 2
        if a <= cuts[mid] + 1e-9 then
          hi = mid
        else
          lo = mid + 1
        end
      end
      local from_piece = lo
      lo, hi = 0, pieces
      while lo < hi do
        local mid = (lo + hi + 1) // 2
        if b >= cuts[mid + 1] - 1e-9 then
          lo = mid
        else
          hi = mid - 1
        end
      end
      local to_piece = lo
      local i = untaken(from_piece)
      while i <= to_piece do
        low_of[i] = pitch
        skip[i] = i + 1
        i = untaken(i + 1)
      end
      k = next_of[k]
    end
  end
  local held: Weights = {}
  for i = 1, pieces do
    local a, b = cuts[i], cuts[i + 1]
    local low = low_of[i]
    if b - a > 1e-9 and low then
      held[low % 12] = (held[low % 12] or 0) + (b - a)
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
  local summary: Bass = {held = held, lowest = lowest, lasts = lasts}
  local bass, most = choose(summary, to - from)
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
  for _, s in ipairs(q.steps) do
    inside = inside + w[(root + s) % 12]
  end
  local score = (2 * inside - total) / total
  for _, s in ipairs(q.steps) do
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
  for _, q in ipairs(M.qualities) do
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

--- The first of `sorted` (notes sorted by start) that can sound at `at`:
--- the ones before it start more than `longest` beats before it.
function M.first(sorted: {Note}, longest: number, at: number): integer
  local lo, hi = 1, #sorted + 1
  while lo < hi do
    local mid = (lo + hi) // 2
    if sorted[mid].start + longest < at then
      lo = mid + 1
    else
      hi = mid
    end
  end
  return lo
end

--- One window of the chord reading, from `at`, `length` beats long:
--- `sorted` are the notes sorted by start, `longest` the longest of them,
--- `step` the length of a window.
function M.window(sorted: {Note}, longest: number, at: number, length: number, step: number): Window
  local lo = M.first(sorted, longest, at)
  local w, bass, total, low = weigh(sorted, at, at + length, lo)
  local win: Window = {at = at, length = length, total = total, bass = low}
  -- One pitch alone is no chord: it is weighed with the rest of its beat
  -- (an arpeggio's notes come one at a time), and if the beat has no
  -- other either (a melody alone) it says nothing, and the chord before
  -- holds over it.
  local ew, ebass, etotal = w, bass, total
  if total > 1e-9 and classes(w, total) < 2 and step < 1 then
    local beat = math.floor(at + 1e-9)
    -- From the first note that can sound at `at`, as it always was: so
    -- this window, alone of all, depends on the longest note.
    ew, ebass, etotal = weigh(sorted, beat, beat + 1, lo)
    win.beat = true
  end
  if total > 1e-9 and classes(ew, etotal) < 2 then
    win.flat = true
  elseif total > 1e-9 then
    local scores: {number} = {}
    for l, label in ipairs(LABELS) do
      scores[l] = fit(ew, ebass, etotal, label.root, label.q) * length
    end
    scores[NL] = NONE * length
    win.scores = scores
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

--- The chords of a run of windows (`window` makes each, one after another
--- with no gap): a chord holds across windows unless the next is better by
--- more than what a change costs. Silence of `bar` beats ends a chord.
function M.decode(windows: {Window}, bar: number): {Chord}
  if #windows == 0 then
    return {}
  end
  local prev: {number}
  local back: {{integer}} = {}
  local quiet: number = 0 -- beats since something last sounded
  for i, win in ipairs(windows) do
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
    local cur: {number} = {}
    local from_l: {integer} = {}
    if not prev then
      for l = 1, NL do
        cur[l], from_l[l] = scores[l], l
      end
    else
      local best, best_l = -math.huge, 1
      for l = 1, NL do
        if prev[l] > best then
          best, best_l = prev[l], l
        end
      end
      for l = 1, NL do
        -- A change costs a little more in silence, so that the chord
        -- before holds over a rest rather than the next one starting early.
        local stay, change = prev[l], best - CHANGE - (total > 1e-9 and 0 or 0.01)
        if stay >= change then
          cur[l], from_l[l] = stay + scores[l], l
        else
          cur[l], from_l[l] = change + scores[l], best_l
        end
      end
    end
    back[i], prev = from_l, cur
  end

  -- Walk back from the best end.
  local path: {integer} = {}
  local best, best_l = -math.huge, NL
  for l = 1, NL do
    if prev[l] > best then
      best, best_l = prev[l], l
    end
  end
  for k = #windows, 1, -1 do
    path[k] = best_l
    best_l = back[k][best_l]
  end

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
        for t, s in ipairs(label.q.steps) do
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
  for i, n in ipairs(notes) do
    sorted[i] = n
  end
  table.sort(sorted, function(a: Note, b: Note): boolean return a.start < b.start end)
  if #sorted == 0 then
    return {}
  end
  local first, last = math.huge, -math.huge
  local longest: number = 0
  for _, n in ipairs(sorted) do
    first, last = math.min(first, n.start), math.max(last, n.start + n.length)
    longest = math.max(longest, n.length)
  end
  local from = math.floor((opts.from or first) / step + 1e-9) * step
  local to = math.min(opts.to or last, last)
  local windows: {Window} = {}
  local at = from
  while at < to - 1e-9 do
    windows[#windows + 1] = M.window(sorted, longest, at, math.min(step, to - at), step)
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
local NEAR: {integer: number} = {[-2] = 0.25, [-1] = 0.5, [1] = 0.5, [2] = 0.25} -- neighbouring bars, heard with each
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
  for _, note in ipairs(notes) do
    add(hist, bars, note.pitch % 12, note.start, note.start + note.length, 1)
  end
  return M.key_path(hist, bars, chords)
end

--- How long each pitch class sounds from `from` to `to`, of `sorted`
--- (notes sorted by start, the longest `longest` beats).
function M.bar_weights(sorted: {Note}, longest: number, from: number, to: number): Weights
  local h: Weights = {}
  for pc = 0, 11 do
    h[pc] = 0
  end
  for i = M.first(sorted, longest, from), #sorted do
    local note = sorted[i]
    if note.start >= to then
      break
    end
    local a, z = math.max(note.start, from), math.min(note.start + note.length, to)
    if z > a then
      h[note.pitch % 12] = h[note.pitch % 12] + (z - a)
    end
  end
  return h
end

--- The keys from the pitch classes of each bar (`hist`, as `bar_weights`
--- gives them, which it leaves as they are) and the chords, as `keys`.
function M.key_path(notes_hist: {Weights}, bars: {number}, chords?: {Chord}): {Key}
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
  for c, cand in ipairs(candidates) do
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
      for d, weight in pairs(NEAR) do
        h[pc] = h[pc] + weight * ((hist[b + d] or {})[pc] or 0)
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
    for c, cand in ipairs(candidates) do
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
