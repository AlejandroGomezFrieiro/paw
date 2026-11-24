-- Chords that lead somewhere: dominants, their substitutes and approaches,
-- suspensions and cadences. Each is written from the cursor up to the next
-- chord the song has (on any pitched part), voiced in the part's range
-- and led smoothly from what this clip plays before.
local S = require("snippets")
local H = paw.harmony

local KINDS = { name = "kind", values = { "7", "9", "7b9", "7sus4", "triad" } }

return {
  {
    name = "dominant",
    desc = "the dominant seventh of the next chord, from here up to it (a count chains dominants back)",
    count = true,
    choices = { S.voicings, KINDS, S.lengths },
    expand = function(ctx)
      local target, why = S.next_chord(ctx)
      if not target then return nil, why end
      local to = S.until_(ctx, target.at)
      -- With a count, a chain back from the target: 2 is V7/V then V7.
      local n = math.max(1, ctx.count)
      local bounds = S.split(
        ctx,
        ctx.at,
        to,
        (function()
          local w = {}
          for i = 1, n do
            w[i] = 1
          end
          return w
        end)()
      )
      local chords = {}
      for i = 1, n do
        local root = (target.root + 7 * (n - i + 1)) % 12
        chords[i] = { tones = S.dominant_tones(root, ctx.values.kind), from = bounds[i], to = bounds[i + 1] }
      end
      return { notes = S.progression(ctx, chords) }
    end,
  },
  {
    name = "secondary",
    desc = "V7 of a chord of the key (the next chord's by default), from here up to the next chord",
    choices = {
      S.voicings,
      { name = "of", values = { "next chord", "ii", "iii", "IV", "V", "vi" } },
      KINDS,
    },
    expand = function(ctx)
      local target, why = S.next_chord(ctx)
      if not target then return nil, why end
      local of = ctx.values.of or "next chord"
      local root = target.root
      if of ~= "next chord" then
        local degree = ({ ii = 1, iii = 2, IV = 3, V = 4, vi = 5 })[of]
        root = H.degree_pitch(ctx.key, degree) % 12
      end
      local chords = { { tones = S.dominant_tones((root + 7) % 12, ctx.values.kind), from = ctx.at, to = target.at } }
      return { notes = S.progression(ctx, chords) }
    end,
  },
  {
    name = "two-five",
    desc = "ii7 then V7 into the next chord, sharing the time up to it (iiø7 and V7b9 before a minor chord)",
    choices = { S.voicings, { name = "split", values = { "half", "3:1", "1:3" } } },
    expand = function(ctx)
      local target, why = S.next_chord(ctx)
      if not target then return nil, why end
      local minor = target.quality == "min"
        or target.quality == "m7"
        or target.quality == "m6"
        or target.quality == "m9"
      local parts = ({ half = { 1, 1 }, ["3:1"] = { 3, 1 }, ["1:3"] = { 1, 3 } })[ctx.values.split or "half"]
      local b = S.split(ctx, ctx.at, target.at, parts)
      local two = (target.root + 2) % 12
      local five = (target.root + 7) % 12
      return {
        notes = S.progression(ctx, {
          { tones = H.tones(two, minor and "m7b5" or "m7"), from = b[1], to = b[2] },
          { tones = S.dominant_tones(five, minor and "7b9" or "7"), from = b[2], to = b[3] },
        }),
      }
    end,
  },
  {
    name = "tritone",
    desc = "the tritone substitute (bII7) of the next chord's dominant, up to it",
    choices = { S.voicings, { name = "kind", values = { "7", "9", "triad" } } },
    expand = function(ctx)
      local target, why = S.next_chord(ctx)
      if not target then return nil, why end
      local root = (target.root + 1) % 12
      return {
        notes = S.progression(
          ctx,
          { { tones = S.dominant_tones(root, ctx.values.kind), from = ctx.at, to = target.at } }
        ),
      }
    end,
  },
  {
    name = "passing-dim",
    desc = "a diminished seventh passing into the next chord: on its leading note, or on its root (common tone)",
    choices = { S.voicings, { name = "kind", values = { "leading", "common tone" } }, S.lengths },
    expand = function(ctx)
      local target, why = S.next_chord(ctx)
      if not target then return nil, why end
      local root = ctx.values.kind == "common tone" and target.root or (target.root - 1) % 12
      local chords = { { tones = H.tones(root, "dim7"), from = ctx.at, to = S.until_(ctx, target.at) } }
      return { notes = S.progression(ctx, chords) }
    end,
  },
  {
    name = "sus",
    desc = "the next chord suspended from here, resolving when it comes",
    choices = {
      S.voicings,
      { name = "sus", values = { "sus4", "sus2", "7sus4" } },
      { name = "resolve", values = { "1 beat", "2 beats", "the whole chord" } },
    },
    expand = function(ctx)
      local target, why = S.next_chord(ctx)
      if not target then return nil, why end
      local resolve = ctx.values.resolve
      local finish = resolve == "1 beat" and target.at + 1
        or resolve == "2 beats" and target.at + 2
        or target.at + target.length
      finish = math.min(finish, target.at + target.length)
      local plain = target.tones
      local suspended = H.tones(target.root, ctx.values.sus or "sus4")
      return {
        notes = S.progression(ctx, {
          { tones = suspended, from = ctx.at, to = target.at },
          { tones = plain, from = target.at, to = finish },
        }),
      }
    end,
  },
  {
    name = "cadence",
    desc = "an authentic cadence to the key's tonic, a bar for each chord from here",
    choices = {
      S.voicings,
      { name = "kind", values = { "V-I", "IV-V-I", "ii-V-I", "IV-I" } },
      { name = "each", values = { "1 bar", "2 beats", "2 bars" } },
    },
    expand = function(ctx)
      local key = ctx.key
      local minor = key.scale == "minor" or key.scale == "harmonic_minor" or key.scale == "dorian"
      local tonic = key.root
      local each = ctx.values.each == "2 beats" and 2
        or ctx.values.each == "2 bars" and 2 * paw.time.bar(ctx.at)
        or paw.time.bar(ctx.at)
      local plan = ({
        ["V-I"] = { "V", "I" },
        ["IV-V-I"] = { "IV", "V", "I" },
        ["ii-V-I"] = { "ii", "V", "I" },
        ["IV-I"] = { "IV", "I" },
      })[ctx.values.kind or "V-I"]
      local chords, at = {}, ctx.at
      for _, degree in ipairs(plan) do
        local tones
        if degree == "V" then
          tones = H.tones((tonic + 7) % 12, "7")
        elseif degree == "IV" then
          tones = H.tones((tonic + 5) % 12, minor and "min" or "maj")
        elseif degree == "ii" then
          tones = H.tones((tonic + 2) % 12, minor and "m7b5" or "m7")
        else
          tones = H.tones(tonic, minor and "min" or "maj")
        end
        chords[#chords + 1] = { tones = tones, from = at, to = at + each }
        at = at + each
      end
      return { notes = S.progression(ctx, chords) }
    end,
  },
}
