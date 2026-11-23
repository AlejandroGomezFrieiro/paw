-- Parts made of the chords already there: a pedal, an arpeggio, a bass line.
local S = require("snippets")

--- The chords from `from` to `to`, each cut to that stretch.
local function chords_between(ctx, from, to)
  local out = {}
  for _, c in ipairs(ctx.harmony.chords(from, to)) do
    local a, b = math.max(from, c.at), math.min(to, c.at + c.length)
    if b > a + 1e-9 then out[#out + 1] = { chord = c, from = a, to = b } end
  end
  return out
end

--- Where a part made of the chords runs: over the selection, else from the
--- cursor for `count` bars (one), or as the `length` choice says.
local function span(ctx)
  if ctx.region then return ctx.region.from, ctx.region.to end
  local v = ctx.values.length
  if v == "to the next chord" then
    local here = ctx.harmony.at(ctx.at)
    local nxt = ctx.harmony.next(ctx.at)
    return ctx.at, (here and here.at + here.length) or (nxt and nxt.at) or ctx.at + paw.time.bar(ctx.at)
  end
  local bars = v == "2 bars" and 2 or v == "4 bars" and 4 or 1
  local finish = ctx.at
  for _ = 1, bars * math.max(1, ctx.count) do
    finish = finish + paw.time.bar(finish)
  end
  return ctx.at, finish
end

--- The pitch of pitch class `pc` nearest to `near` within the range.
local function place(pc, near, low, high)
  local best
  for p = low, high do
    if p % 12 == pc and (not best or math.abs(p - near) < math.abs(best - near)) then best = p end
  end
  return best
end

local LENGTHS = { name = "length", values = { "1 bar", "2 bars", "4 bars", "to the next chord" } }

return {
  {
    name = "pedal",
    desc = "a held pedal note under the span: the key's tonic, its dominant or the chord's root",
    count = true,
    choices = { { name = "note", values = { "tonic", "dominant", "chord root" } }, LENGTHS },
    expand = function(ctx)
      local from, to = span(ctx)
      local pc = ctx.key.root
      if ctx.values.note == "dominant" then pc = (pc + 7) % 12 end
      if ctx.values.note == "chord root" then
        local c = ctx.harmony.at(from) or ctx.harmony.next(from)
        if not c then return nil, "no chord here" end
        pc = c.root
      end
      local pitch = place(pc, ctx.range.low + 6, ctx.range.low, ctx.range.high)
      if not pitch then return nil, "the part's range is too narrow" end
      return { notes = { { pitch = pitch, start = from, length = to - from } } }
    end,
  },
  {
    name = "arp",
    desc = "the chord at the cursor, arpeggiated over its length on the grid",
    choices = {
      { name = "pattern", values = { "up", "down", "up-down", "broken" } },
      { name = "rate", values = { "grid", "1/8", "1/16", "1/4" } },
      S.voicings,
    },
    expand = function(ctx)
      local c = ctx.harmony.at(ctx.at) or ctx.harmony.next(ctx.at)
      if not c then return nil, "no chord here" end
      local from = math.max(ctx.at, c.at)
      local to = c.at + c.length
      if ctx.region then
        from, to = ctx.region.from, ctx.region.to
      end
      local rate = ({ grid = ctx.grid, ["1/8"] = 0.5, ["1/16"] = 0.25, ["1/4"] = 1 })[ctx.values.rate or "grid"]
      local _, pitches = ctx:chord(c.tones, from, to, { count = math.max(3, #c.tones) })
      if not pitches then return nil, "the chord does not fit the part's range" end
      local order = {}
      for i, p in ipairs(pitches) do
        order[i] = p
      end
      local pattern = ctx.values.pattern
      if pattern == "down" then
        table.sort(order, function(a, b) return a > b end)
      elseif pattern == "up-down" then
        for i = #pitches - 1, 2, -1 do
          order[#order + 1] = pitches[i]
        end
      elseif pattern == "broken" then
        -- Low, high, middle, high: as an Alberti bass.
        order = { pitches[1], pitches[#pitches], pitches[math.max(1, #pitches - 1)], pitches[#pitches] }
      end
      local notes, i, at = {}, 0, from
      while at < to - 1e-9 do
        notes[#notes + 1] = { pitch = order[i % #order + 1], start = at, length = math.min(rate, to - at) }
        i, at = i + 1, at + rate
      end
      return { notes = notes }
    end,
  },
  {
    name = "bass",
    desc = "a bass line under the chords: root and fifth, roots alone, or octaves",
    count = true,
    choices = { { name = "pattern", values = { "root-fifth", "roots", "octaves" } }, LENGTHS },
    expand = function(ctx)
      local from, to = span(ctx)
      local parts = chords_between(ctx, from, to)
      if #parts == 0 then return nil, "no chords under the span" end
      local low, high = ctx.range.low, math.min(ctx.range.high, ctx.range.low + 19)
      local notes, last = {}, nil
      for _, part in ipairs(parts) do
        local c = part.chord
        local root = place(c.bass or c.root, last or (low + 7), low, high) or place(c.root, low + 7, low, high)
        local fifth = place((c.root + 7) % 12, root + 5, low, high)
        local len = part.to - part.from
        local pattern = ctx.values.pattern
        if pattern == "roots" or len < 2 - 1e-9 then
          notes[#notes + 1] = { pitch = root, start = part.from, length = len }
        else
          -- A note a beat long, alternating, for as long as the chord lasts.
          local at, k = part.from, 0
          while at < part.to - 1e-9 do
            local p = root
            if k % 2 == 1 then
              p = pattern == "octaves" and (root + 12 <= 127 and root + 12 or root) or (fifth or root)
            end
            notes[#notes + 1] = { pitch = p, start = at, length = math.min(1, part.to - at) }
            at, k = at + 1, k + 1
          end
        end
        last = root
      end
      return { notes = notes }
    end,
  },
}
