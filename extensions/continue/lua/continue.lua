-- Continue the phrase: suggestions made from the notes just before the
-- cursor, without any knowledge but the key. The last bar again, the last
-- bar a step higher or lower in the key (a sequence), and the last motif
-- rising through the key. Plain functions of a context, so that they can
-- be tested without a piano roll.
local M = {}

local SCALES = {
  major = { 0, 2, 4, 5, 7, 9, 11 },
  minor = { 0, 2, 3, 5, 7, 8, 10 },
}
local NAMES = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }
local EPS = 1e-6

--- The key the notes are most likely in: `{ tonic = 0..11, mode, name }`.
--- Each pitch class weighs as long as it sounds; the key whose scale holds
--- the most weight wins. Between keys that hold the same, the one whose
--- tonic the music starts on (its first note, the lowest of a chord), then
--- the one whose tonic sounds longest, major before minor.
function M.guess_key(notes)
  local weight, first = {}, nil
  for pc = 0, 11 do
    weight[pc] = 0
  end
  for _, n in ipairs(notes) do
    local pc = n.pitch % 12
    weight[pc] = weight[pc] + n.length
    if
      not first
      or n.start < first.start - EPS
      or (math.abs(n.start - first.start) < EPS and n.pitch < first.pitch)
    then
      first = n
    end
  end
  local function rank(tonic, mode)
    local score = 0
    for _, step in ipairs(SCALES[mode]) do
      score = score + weight[(tonic + step) % 12]
    end
    return score, (first and first.pitch % 12 == tonic) and 1 or 0, weight[tonic]
  end
  local best, best_rank
  for _, mode in ipairs({ "major", "minor" }) do
    for tonic = 0, 11 do
      local r = { rank(tonic, mode) }
      local better = not best_rank
      for i = 1, 3 do
        if better or r[i] < best_rank[i] - EPS then break end
        if r[i] > best_rank[i] + EPS then better = true end
      end
      if better then
        best, best_rank = { tonic = tonic, mode = mode }, r
      end
    end
  end
  best.name = NAMES[best.tonic + 1] .. " " .. best.mode
  return best
end

--- `pitch` moved `steps` degrees along the key's scale. A note outside
--- the scale keeps its distance from the degree below it.
function M.shift(pitch, steps, key)
  local scale = SCALES[key.mode] or SCALES.major
  local rel = pitch - key.tonic
  local octave, within = math.floor(rel / 12), rel % 12
  local degree = 1
  for i, step in ipairs(scale) do
    if step <= within then degree = i end
  end
  local offset = within - scale[degree]
  local index = degree - 1 + steps
  local o, d = math.floor(index / 7), index % 7
  return key.tonic + (octave + o) * 12 + scale[d + 1] + offset
end

local function moved(notes, by, steps, key)
  local out = {}
  for i, n in ipairs(notes) do
    local pitch = steps == 0 and n.pitch or M.shift(n.pitch, steps, key)
    if pitch < 0 or pitch > 127 then return nil end
    out[i] = { pitch = pitch, start = n.start + by, length = n.length, velocity = n.velocity }
  end
  return out
end

local function signature(notes)
  local parts = {}
  for i, n in ipairs(notes) do
    parts[i] = string.format("%d@%.4f+%.4f", n.pitch, n.start, n.length)
  end
  table.sort(parts)
  return table.concat(parts, " ")
end

--- The suggestions for a completion context: `ctx.notes` (the clip's),
--- `ctx.at` (where to go on from, in the clip's beats), `ctx.bar` (the
--- length of a bar there) and optionally `ctx.key` (a key as
--- `paw.harmony.key` gives it; guessed from the notes without one).
function M.suggest(ctx)
  local at, bar = ctx.at, ctx.bar or 4
  local phrase = {}
  for _, n in ipairs(ctx.notes) do
    if n.start >= at - bar - EPS and n.start < at - EPS then phrase[#phrase + 1] = n end
  end
  if #phrase == 0 then return {} end
  local given = ctx.key and ctx.key.tonic and ctx.key or M.guess_key(ctx.notes)
  -- A mode without a scale here (dorian, say) is taken as major.
  local key = { tonic = given.tonic, mode = SCALES[given.mode] and given.mode or "major" }
  local name = given.name or (NAMES[key.tonic + 1] .. " " .. key.mode)
  local items, seen = {}, {}
  local function add(label, notes, detail)
    if not notes or #notes == 0 then return end
    local sig = signature(notes)
    if seen[sig] then return end
    seen[sig] = true
    items[#items + 1] = { label = label, detail = detail, notes = notes }
  end
  -- The phrase sits where it was; it is moved on by the time it covered.
  add("the bar again", moved(phrase, bar, 0, key), #phrase .. " notes")
  add("a step higher", moved(phrase, bar, 1, key), "in " .. name)
  add("a step lower", moved(phrase, bar, -1, key), "in " .. name)
  -- The last motif: the notes of the last half bar, twice, rising a step each time.
  local half = bar / 2
  local motif = {}
  for _, n in ipairs(phrase) do
    if n.start >= at - half - EPS then motif[#motif + 1] = n end
  end
  if #motif > 0 and #motif < #phrase then
    local first, second = moved(motif, half, 1, key), moved(motif, 2 * half, 2, key)
    if first and second then
      for _, n in ipairs(second) do
        first[#first + 1] = n
      end
      add("the motif, rising", first, "in " .. name)
    end
  end
  return items
end

return M
