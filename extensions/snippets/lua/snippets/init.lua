-- What the snippets of this set share: where a snippet ends, the chords of
-- the dominant family, and spans of time split into parts on the grid.
local H = paw.harmony
local M = {}

M.voicings = { name = "voicing", values = { "smooth", "close", "drop2", "open", "spread" } }
M.lengths = { name = "length", values = { "to the chord", "1 beat", "2 beats", "1 bar" } }

--- The end of a span from the cursor towards `to`, as the `length` choice
--- says: all the way, or a beat, two, a bar, whichever ends first.
function M.until_(ctx, to)
  local v = ctx.values.length
  local want = v == "1 beat" and 1 or v == "2 beats" and 2 or v == "1 bar" and paw.time.bar(ctx.at) or nil
  if want then return math.min(to, ctx.at + want) end
  return to
end

--- The tones of a dominant on `root` of the `kind` the choice names.
function M.dominant_tones(root, kind)
  if kind == "9" then return { root, (root + 4) % 12, (root + 7) % 12, (root + 10) % 12, (root + 2) % 12 } end
  if kind == "7b9" then return { root, (root + 4) % 12, (root + 7) % 12, (root + 10) % 12, (root + 1) % 12 } end
  if kind == "7sus4" then return H.tones(root, "7sus4") end
  if kind == "triad" then return H.tones(root, "maj") end
  return H.tones(root, "7")
end

--- Cut `from`..`to` into `parts` (weights, `{ 1, 1 }` for halves), each
--- boundary on the grid when it can be. Returns the boundaries.
function M.split(ctx, from, to, parts)
  local total = 0
  for _, p in ipairs(parts) do
    total = total + p
  end
  local out, acc = { from }, 0
  for i = 1, #parts - 1 do
    acc = acc + parts[i]
    local at = from + (to - from) * acc / total
    local g = ctx.grid
    local snapped = math.floor(at / g + 0.5) * g
    if snapped > out[#out] + 1e-9 and snapped < to - 1e-9 then at = snapped end
    out[#out + 1] = at
  end
  out[#out + 1] = to
  return out
end

--- A list of chords `{ tones, from, to, bass }` as notes, each voiced from
--- the one before (the first from what comes before the cursor), the last
--- into what follows.
function M.progression(ctx, chords, opts)
  opts = opts or {}
  local notes, prev = {}, nil
  for i, c in ipairs(chords) do
    -- Only the last leads into what follows; the first leads from what
    -- came before.
    local nxt, from_before = nil, nil
    if i < #chords then nxt = false end
    if i > 1 then from_before = prev end
    local _, voiced = ctx:chord(c.tones, c.from, c.to, { prev = from_before, bass = c.bass, next = nxt })
    for _, p in ipairs(voiced or {}) do
      notes[#notes + 1] = { pitch = p, start = c.from, length = c.to - c.from, velocity = opts.velocity }
    end
    prev = voiced or prev
  end
  return notes
end

--- The chord the cursor leads into: the next one, or nil and why not.
function M.next_chord(ctx)
  local target = ctx.harmony.next(ctx.at)
  if not target then return nil, "no chord after the cursor" end
  return target
end

return M
