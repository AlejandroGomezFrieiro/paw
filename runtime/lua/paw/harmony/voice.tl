-- Voicings: which pitches play a chord, inside a range, moving as little as
-- they can from the chord before (and into the chord after).
--
--   voice.voice({ 7, 11, 2, 5 }, { low = 48, high = 84, prev = { 60, 64, 67 }, style = "smooth" })
--     --> { 55, 59, 62, 65 } or whichever G7 lies closest to the C major given
--
-- `tones` are pitch classes in chord order, root first (`{ root, third,
-- fifth, seventh, ... }`). Styles: "close" (every tone in one octave),
-- "drop2" (the second voice from the top an octave down), "open" (every
-- other voice down: the triad as root, fifth, tenth), "spread" (the root an
-- octave under a close chord), and "smooth": whichever of those leads best.
--
-- Written in Teal (paw/lang.tl): the build compiles it to Lua.

--- The options of `voice` and `candidates`.
local record Options
  low: integer
  high: integer
  count: integer
  style: string
  prev: {number}
  next: {number}
  bass: integer
  center: number
end

--- A voicing: its pitches, low to high, and its style.
local record Candidate
  pitches: {integer}
  style: string
end

local record M
  styles: {string}
end

M.styles = { "smooth", "close", "drop2", "open", "spread" }

--- The tones to voice in `count` voices: the root doubled when there are
--- more voices than tones; the fifth, then the root, left out when fewer.
local function fitted(tones: {integer}, count: integer): {integer}
  local list: {integer} = {}
  for i, t in ipairs(tones) do list[i] = t end
  while #list > count do
    local fifth: integer
    for i, t in ipairs(list) do
      if i > 1 and (t - list[1]) % 12 == 7 then fifth = i end
    end
    table.remove(list, fifth or 1)
  end
  local i = 1
  while #list < count do
    list[#list + 1] = tones[(i - 1) % #tones + 1]
    i = i + 1
  end
  return list
end

--- Every close voicing of `list` (pitch classes) with its lowest note from
--- `low` up to `high`: each rotation, stacked upwards in each octave.
local function closes(list: {integer}, low: integer, high: integer): {{integer}}
  local out: {{integer}} = {}
  for r = 1, #list do
    local order: {integer} = {}
    for k = 0, #list - 1 do order[#order + 1] = list[(r - 1 + k) % #list + 1] end
    local first = order[1] + 12 * math.floor((low - order[1]) / 12)
    if first < low then first = first + 12 end
    for base = first, high, 12 do
      local pitches, p = { base }, base
      for k = 2, #order do
        p = p + ((order[k] - p) % 12)
        if p == pitches[#pitches] then p = p + 12 end
        pitches[#pitches + 1] = p
      end
      out[#out + 1] = pitches
    end
  end
  return out
end

local function sorted<T>(list: {T}): {T}
  table.sort(list)
  return list
end

--- A voicing in `style` made from a close one.
local function restyle(close: {integer}, style: string): {integer}
  local p: {integer} = {}
  for i, v in ipairs(close) do p[i] = v end
  local n = #p
  if style == "drop2" and n >= 3 then
    p[n - 1] = p[n - 1] - 12
  elseif style == "open" and n >= 3 then
    for i = n - 1, 1, -2 do p[i] = p[i] - 12 end
  elseif style == "spread" then
    p[1] = p[1] - 12
  end
  return sorted(p)
end

local function copy(list: {number}): {number}
  local out: {number} = {}
  for i, v in ipairs(list) do out[i] = v end
  return out
end

--- How far voices move from `a` to `b`. When the chords have the same number
--- of voices, it measures voice by voice. If not, it measures each note to
--- the nearest note of the other chord, in the two directions, and halves
--- the sum.
function M.distance(a: {number}, b: {number}): number
  if not a or not b or #a == 0 or #b == 0 then return 0 end
  local x, y = sorted(copy(a)), sorted(copy(b))
  if #x == #y then
    local d: number = 0
    for i = 1, #x do d = d + math.abs(x[i] - y[i]) end
    return d
  end
  local function near(from: {number}, to: {number}): number
    local d: number = 0
    for _, p in ipairs(from) do
      local best = math.huge
      for _, q in ipairs(to) do best = math.min(best, math.abs(p - q)) end
      d = d + best
    end
    return d
  end
  return (near(x, y) + near(y, x)) / 2
end

--- Each voicing of the chord in the range of the options, `{ pitches, style }`.
function M.candidates(tones: {integer}, opts: Options): {Candidate}
  opts = opts or {}
  local low, high = opts.low or 48, opts.high or 84
  local count = opts.count or #tones
  local list = fitted(tones, count)
  local styles = (opts.style == nil or opts.style == "smooth") and { "close", "drop2", "open" } or { opts.style }
  local out: {Candidate} = {}
  for _, style in ipairs(styles) do
    -- A dropped voice lands up to two octaves lower: start the close chords higher.
    for _, close in ipairs(closes(list, low, high + (style == "close" and 0 or 24))) do
      local p = restyle(close, style)
      local ok = p[1] >= low and p[#p] <= high
      if ok and opts.bass then ok = p[1] % 12 == opts.bass end
      if ok then out[#out + 1] = { pitches = p, style = style } end
    end
  end
  return out
end

--- The best voicing of `tones` (pitch classes, root first). The options are
--- `low` and `high` (48 and 84), `count` (the number of voices, by default
--- the number of tones) and `style` ("smooth"). `prev` and `next` are the
--- pitches of the chords around it, to lead from and into. `bass` is the
--- pitch class that must be the lowest. `center` is a pitch to stay near
--- when there is no chord before. Nil when nothing fits the range.
function M.voice(tones: {integer}, opts: Options): {integer}
  opts = opts or {}
  local list = M.candidates(tones, opts)
  if #list == 0 and opts.bass then
    -- The same options without the bass.
    list = M.candidates(tones, { low = opts.low, high = opts.high, count = opts.count, style = opts.style })
  end
  local center = opts.center or ((opts.low or 48) + (opts.high or 84)) / 2
  local best: {integer}
  local cost: number
  for _, c in ipairs(list) do
    local p = c.pitches
    local mid = (p[1] + p[#p]) / 2
    local k = M.distance(opts.prev, p) + 0.5 * M.distance(p, opts.next) + 0.1 * math.abs(mid - center)
    -- In close position the root at the bottom reads best, other things equal.
    if p[1] % 12 ~= tones[1] then k = k + 0.5 end
    if not cost or k < cost - 1e-9 then best, cost = p, k end
  end
  return best
end

return M
