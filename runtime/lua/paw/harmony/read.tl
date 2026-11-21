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
local type Weights = {integer:number}

local record M
  type Quality = Quality
  type Note = Note
  type Chord = Chord
  type Key = Key
  type ChordOptions = ChordOptions
  qualities: {Quality}
  by_quality: {string:Quality}
  MAJOR: {number}
  MINOR: {number}
  fit: function(w: Weights, bass: integer, total: number, root: integer, q: Quality): number
  correlate: function(h: Weights, profile: {number}, tonic: integer): number
end

-- Qualities: steps above the root. `cost` is what it takes to prefer it to a
-- plainer chord with fewer tones; `minor` makes its Roman numeral lower case.
M.qualities = {
  { name = "maj", steps = { 0, 4, 7 }, suffix = "", roman = "", cost = 0 },
  { name = "min", steps = { 0, 3, 7 }, suffix = "m", roman = "", minor = true, cost = 0 },
  { name = "dim", steps = { 0, 3, 6 }, suffix = "dim", roman = "°", minor = true, cost = 0.02 },
  { name = "aug", steps = { 0, 4, 8 }, suffix = "aug", roman = "+", cost = 0.04 },
  { name = "sus4", steps = { 0, 5, 7 }, suffix = "sus4", roman = "sus4", cost = 0.03 },
  { name = "sus2", steps = { 0, 2, 7 }, suffix = "sus2", roman = "sus2", cost = 0.04 },
  { name = "5", steps = { 0, 7 }, suffix = "5", roman = "5", cost = 0.05 },
  { name = "7", steps = { 0, 4, 7, 10 }, suffix = "7", roman = "7", cost = 0.01 },
  { name = "maj7", steps = { 0, 4, 7, 11 }, suffix = "maj7", roman = "maj7", cost = 0.02 },
  { name = "m7", steps = { 0, 3, 7, 10 }, suffix = "m7", roman = "7", minor = true, cost = 0.01 },
  { name = "m7b5", steps = { 0, 3, 6, 10 }, suffix = "m7b5", roman = "ø7", minor = true, cost = 0.02 },
  { name = "dim7", steps = { 0, 3, 6, 9 }, suffix = "dim7", roman = "°7", minor = true, cost = 0.02 },
  { name = "mmaj7", steps = { 0, 3, 7, 11 }, suffix = "m(maj7)", roman = "(maj7)", minor = true, cost = 0.05 },
  { name = "6", steps = { 0, 4, 7, 9 }, suffix = "6", roman = "6", cost = 0.04 },
  { name = "m6", steps = { 0, 3, 7, 9 }, suffix = "m6", roman = "6", minor = true, cost = 0.04 },
  { name = "7sus4", steps = { 0, 5, 7, 10 }, suffix = "7sus4", roman = "7sus4", cost = 0.03 },
  { name = "add9", steps = { 0, 2, 4, 7 }, suffix = "add9", roman = "add9", cost = 0.04 },
  { name = "9", steps = { 0, 2, 4, 7, 10 }, suffix = "9", roman = "9", cost = 0.02 },
  { name = "maj9", steps = { 0, 2, 4, 7, 11 }, suffix = "maj9", roman = "maj9", cost = 0.03 },
  { name = "m9", steps = { 0, 2, 3, 7, 10 }, suffix = "m9", roman = "9", minor = true, cost = 0.02 },
}
M.by_quality = {}
for _, q in ipairs(M.qualities) do M.by_quality[q.name] = q end

local EXTRA = 0.06     -- each tone past three
local MISSING = 0.12   -- each tone of the chord that does not sound
local MISSING_FIFTH = 0.04
local MISSING_ROOT = 0.2
local ROOT_IN_BASS = 0.2
local CHANGE = 0.45    -- what a change of chord costs, in beats of a perfect fit
local NONE = -0.5      -- "no chord" where something sounds

--- Weights of the twelve pitch classes between `from` and `to`, the bass's
--- pitch class, and the total. `notes` sorted by start; those before
--- `first` have ended before `from`.
local function weigh(notes: {Note}, from: number, to: number, first?: integer): Weights, integer, number
  local w: Weights = {}
  local total: number = 0
  for pc = 0, 11 do w[pc] = 0 end
  local record Low
    a: number
    b: number
    pitch: integer
  end
  local lows: {Low} = {}   -- the lowest pitch sounding over each piece of the window
  for i = first or 1, #notes do
    local n = notes[i]
    if n.start >= to then break end
    local a, b = math.max(from, n.start), math.min(to, n.start + n.length)
    if b > a then
      local off_beat = math.abs(n.start - math.floor(n.start + 0.5)) > 1e-6
      local amount = (b - a) * ((off_beat and n.length < 0.5) and 0.5 or 1)
      w[n.pitch % 12] = w[n.pitch % 12] + amount
      total = total + amount
      lows[#lows + 1] = { a = a, b = b, pitch = n.pitch }
    end
  end
  if total == 0 then return w, nil, 0 end
  -- The bass: of the lowest pitches over time, the class that lasts longest.
  local cuts: {number} = { from, to }
  for _, l in ipairs(lows) do cuts[#cuts + 1] = l.a cuts[#cuts + 1] = l.b end
  table.sort(cuts)
  -- The lowest pitch over each piece between two cuts: piece `i` is from
  -- `cuts[i]` to `cuts[i + 1]`, and a low covers the pieces in one run.
  -- The lows from the lowest up each take the pieces of their run that no
  -- lower one took; `skip` leads past the pieces taken (with its paths
  -- made short as they are walked), so that each piece is looked at about
  -- once rather than once for each low.
  local pieces = #cuts - 1
  local by_pitch: {Low} = {}
  for i, l in ipairs(lows) do by_pitch[i] = l end
  table.sort(by_pitch, function(x: Low, y: Low): boolean return x.pitch < y.pitch end)
  local low_of: {integer} = {}
  local skip: {integer} = {}
  local function untaken(i: integer): integer
    local j = i
    while skip[j] do j = skip[j] end
    while skip[i] do
      local after = skip[i]
      skip[i] = j
      i = after
    end
    return j
  end
  for _, l in ipairs(by_pitch) do
    -- The first piece with `l.a <= cuts[i] + 1e-9` and the last with
    -- `l.b >= cuts[i + 1] - 1e-9`: the tests of a low that covers a piece.
    local lo, hi = 1, pieces + 1
    while lo < hi do
      local mid = (lo + hi) // 2
      if l.a <= cuts[mid] + 1e-9 then hi = mid else lo = mid + 1 end
    end
    local from_piece = lo
    lo, hi = 0, pieces
    while lo < hi do
      local mid = (lo + hi + 1) // 2
      if l.b >= cuts[mid + 1] - 1e-9 then lo = mid else hi = mid - 1 end
    end
    local to_piece = lo
    local i = untaken(from_piece)
    while i <= to_piece do
      low_of[i] = l.pitch
      skip[i] = i + 1
      i = untaken(i + 1)
    end
  end
  local held: Weights = {}
  for i = 1, pieces do
    local a, b = cuts[i], cuts[i + 1]
    local low = low_of[i]
    if b - a > 1e-9 and low then held[low % 12] = (held[low % 12] or 0) + (b - a) end
  end
  local bass: integer
  local most: number = 0
  for pc, d in pairs(held) do
    if d > most or (d == most and bass and pc < bass) then bass, most = pc, d end
  end
  -- An arpeggio's bass sounds a moment and leaves the others to it: the
  -- lowest pitch of all is the bass when it sounds an eighth of the time.
  local lowest: integer
  local lasts: number = 0
  for _, l in ipairs(lows) do
    if not lowest or l.pitch < lowest then lowest, lasts = l.pitch, 0 end
    if l.pitch == lowest then lasts = lasts + (l.b - l.a) end
  end
  if lowest and lowest % 12 ~= bass and lasts >= (to - from) / 8 then bass, most = lowest % 12, lasts end
  if bass then
    w[bass] = w[bass] + most * 0.5
    total = total + most * 0.5
  end
  return w, bass, total
end

--- How many pitch classes weigh something (a twentieth of the total) in `w`.
local function classes(w: Weights, total: number): integer
  local n = 0
  for pc = 0, 11 do
    if w[pc] > 0.05 * total then n = n + 1 end
  end
  return n
end

--- How well the chord `root` `quality` fits weights `w` with `bass` and `total`.
local function fit(w: Weights, bass: integer, total: number, root: integer, q: Quality): number
  local inside: number = 0
  local member: {integer:integer} = {}
  for _, s in ipairs(q.steps) do
    local pc = (root + s) % 12
    member[pc] = s
    inside = inside + w[pc]
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
  if bass == root then score = score + ROOT_IN_BASS end
  return score
end
M.fit = fit

--- Chords over notes in project beats, from `from` to `to` (the notes'
--- span when nil), in windows of `step` beats (0.5). Each chord:
--- `{ at, length, root, quality, bass, tones }` with pitch classes 0..11.
function M.chords(notes: {Note}, opts?: ChordOptions): {Chord}
  opts = opts or {}
  local step = opts.step or 0.5
  local sorted: {Note} = {}
  for i, n in ipairs(notes) do sorted[i] = n end
  table.sort(sorted, function(a: Note, b: Note): boolean return a.start < b.start end)
  if #sorted == 0 then return {} end
  local first, last = math.huge, -math.huge
  for _, n in ipairs(sorted) do
    first, last = math.min(first, n.start), math.max(last, n.start + n.length)
  end
  local from = math.floor((opts.from or first) / step + 1e-9) * step
  local to = math.min(opts.to or last, last)
  if to <= from then return {} end

  local record Label
    root: integer
    q: Quality
  end
  local record Window
    at: number
    length: number
    w: Weights
    bass: integer
    total: number
  end
  local labels: {Label} = {}
  for root = 0, 11 do
    for _, q in ipairs(M.qualities) do labels[#labels + 1] = { root = root, q = q } end
  end
  local NL = #labels + 1   -- the last is "no chord"
  local windows: {Window} = {}
  local prev: {number}
  local back: {{integer}} = {}
  local quiet: number = 0  -- beats since something last sounded
  local longest: number = 0
  for _, n in ipairs(sorted) do longest = math.max(longest, n.length) end
  local i, lo = 0, 1
  local at = from
  while at < to - 1e-9 do
    i = i + 1
    local len = math.min(step, to - at)
    while lo <= #sorted and sorted[lo].start + longest < at do lo = lo + 1 end
    local w, bass, total = weigh(sorted, at, at + len, lo)
    windows[i] = { at = at, length = len, w = w, bass = bass, total = total }
    local scores: {number} = {}
    -- One pitch alone is no chord: it is weighed with the rest of its beat
    -- (an arpeggio's notes come one at a time), and if the beat has no
    -- other either (a melody alone) it says nothing, and the chord before
    -- holds over it.
    local ew, ebass, etotal = w, bass, total
    if total > 1e-9 and classes(w, total) < 2 and step < 1 then
      local beat = math.floor(at + 1e-9)
      ew, ebass, etotal = weigh(sorted, beat, beat + 1, lo)
    end
    if total > 1e-9 and classes(ew, etotal) < 2 then
      quiet = 0
      for l = 1, NL - 1 do scores[l] = 0 end
      scores[NL] = 1e-6   -- with nothing to go on, no chord rather than the first there is
    elseif total > 1e-9 then
      quiet = 0
      for l, label in ipairs(labels) do scores[l] = fit(ew, ebass, etotal, label.root, label.q) * len end
      scores[NL] = NONE * len
    else
      quiet = quiet + len
      -- Silence lets the chord before hold over it, unless it lasts a bar.
      local gap = quiet >= (opts.bar or 4) - 1e-9
      for l = 1, NL - 1 do scores[l] = gap and -math.huge or 0 end
      scores[NL] = 1e-6
    end
    local cur: {number} = {}
    local from_l: {integer} = {}
    if not prev then
      for l = 1, NL do cur[l], from_l[l] = scores[l], l end
    else
      local best, best_l = -math.huge, 1
      for l = 1, NL do
        if prev[l] > best then best, best_l = prev[l], l end
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
    at = at + step
  end

  -- Walk back from the best end.
  local path: {integer} = {}
  local best, best_l = -math.huge, NL
  for l = 1, NL do
    if prev[l] > best then best, best_l = prev[l], l end
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
    while j < #windows and path[j + 1] == l do j = j + 1 end
    if l ~= NL then
      local label = labels[l]
      local a, b = windows[k].at, windows[j].at + windows[j].length
      if j == #windows or path[j + 1] == NL then
        local t = j
        while t >= k and windows[t].total <= 1e-9 do
          b = windows[t].at
          t = t - 1
        end
      end
      if b > a then
        -- The bass over the whole chord, weighed again.
        local _, bass = weigh(sorted, a, b)
        local tones: {integer} = {}
        for t, s in ipairs(label.q.steps) do tones[t] = (label.root + s) % 12 end
        out[#out + 1] = { at = a, length = b - a, root = label.root, quality = label.q.name, bass = bass or label.root, tones = tones }
      end
    end
    k = j + 1
  end
  return out
end

-- Keys ---------------------------------------------------------------------------

-- Krumhansl and Kessler's probe-tone profiles, from the tonic up.
M.MAJOR = { 6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 }
M.MINOR = { 6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 }
local MODULATION = 1     -- what a change of key costs, in correlation: a few bars' worth
local OUTSIDE = 1.5      -- what a bar loses for the share of it outside the key's scale
local LEAN = 0.3         -- how much each bar leans to the song's overall key
local NEAR: {integer:number} = { [-2] = 0.25, [-1] = 0.5, [1] = 0.5, [2] = 0.25 }   -- neighbouring bars, heard with each
-- The pitch classes of a major key, and of a minor one with its raised
-- sixth and seventh (melodic and harmonic minor are still the key).
local SCALE: {string:{integer:boolean}} = {
  major = { [0] = true, [2] = true, [4] = true, [5] = true, [7] = true, [9] = true, [11] = true },
  minor = { [0] = true, [2] = true, [3] = true, [5] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true },
}

--- How well a histogram of pitch classes fits a key's profile from `tonic`,
--- from -1 to 1 (Pearson's correlation).
local function correlate(h: Weights, profile: {number}, tonic: integer): number
  local hm, pm: number, number = 0, 0
  for pc = 0, 11 do hm, pm = hm + h[pc], pm + profile[pc + 1] end
  hm, pm = hm / 12, pm / 12
  local num, dh, dp: number, number, number = 0, 0, 0
  for pc = 0, 11 do
    local x, y = h[pc] - hm, profile[(pc - tonic) % 12 + 1] - pm
    num, dh, dp = num + x * y, dh + x * x, dp + y * y
  end
  if dh == 0 then return 0 end
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
  if n < 1 then return {} end
  local hist: {integer:Weights} = {}
  for b = 1, n do
    hist[b] = {}
    for pc = 0, 11 do hist[b][pc] = 0 end
  end
  local function add(pc: integer, s: number, e: number, weight: number)
    for b = 1, n do
      local a, z = math.max(s, bars[b]), math.min(e, bars[b + 1])
      if z > a then hist[b][pc] = hist[b][pc] + (z - a) * weight end
    end
  end
  for _, note in ipairs(notes) do add(note.pitch % 12, note.start, note.start + note.length, 1) end
  for _, c in ipairs(chords or {}) do
    add(c.root, c.at, c.at + c.length, 1)
    add(c.bass or c.root, c.at, c.at + c.length, 0.5)
  end
  local record Candidate
    tonic: integer
    mode: string
    profile: {number}
    scale: {integer:boolean}
  end
  local candidates: {Candidate} = {}
  for tonic = 0, 11 do
    candidates[#candidates + 1] = { tonic = tonic, mode = "major", profile = M.MAJOR, scale = SCALE.major }
    candidates[#candidates + 1] = { tonic = tonic, mode = "minor", profile = M.MINOR, scale = SCALE.minor }
  end
  -- The song as a whole leans each bar towards its overall key, so that a
  -- few bars that fit another key equally well are not a modulation.
  local whole: Weights = {}
  for pc = 0, 11 do
    whole[pc] = 0
    for b = 1, n do whole[pc] = whole[pc] + hist[b][pc] end
  end
  local lean: {number} = {}
  for c, cand in ipairs(candidates) do lean[c] = LEAN * correlate(whole, cand.profile, cand.tonic) end
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
        if prev[c] > best then best, best_c = prev[c], c end
      end
    end
    local total: number = 0
    for pc = 0, 11 do total = total + h[pc] end
    for c, cand in ipairs(candidates) do
      local score: number = 0
      if sum > 0 then
        -- How well the profile fits, less what sounds outside the scale.
        local outside: number = 0
        for pc = 0, 11 do
          if not cand.scale[(pc - cand.tonic) % 12] then outside = outside + h[pc] end
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
    if prev[c] > best then best, best_c = prev[c], c end
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
        out[#out + 1] = { at = bars[b], length = bars[b + 1] - bars[b], tonic = cand.tonic, mode = cand.mode }
      end
    elseif out[#out] then
      -- A silent bar keeps the key before it.
      out[#out].length = bars[b + 1] - out[#out].at
    end
  end
  return out
end

return M
