-- Snippets on the selected notes, as LuaSnip's work on the selected text.
local H = paw.harmony

--- The selection's notes in chords: those starting within a sixteenth.
local function groups(notes)
  local sorted = {}
  for i, n in ipairs(notes) do
    sorted[i] = n
  end
  table.sort(sorted, function(a, b) return a.start < b.start or (a.start == b.start and a.pitch < b.pitch) end)
  local out = {}
  for _, n in ipairs(sorted) do
    local last = out[#out]
    if last and math.abs(n.start - last.start) < 1 / 16 then
      last.notes[#last.notes + 1] = n
    else
      out[#out + 1] = { start = n.start, notes = { n } }
    end
  end
  return out
end

return {
  {
    name = "harmonize",
    desc = "a second voice for the selected notes, a third or a sixth away in the key",
    choices = { { name = "interval", values = { "third below", "sixth below", "third above", "sixth above" } } },
    expand = function(ctx)
      if not ctx.selection or #ctx.selection == 0 then return nil, "select the notes to harmonize first" end
      local steps = ({ ["third below"] = -2, ["sixth below"] = -5, ["third above"] = 2, ["sixth above"] = 5 })[ctx.values.interval or "third below"]
      local notes = {}
      for _, n in ipairs(ctx.selection) do
        -- The key at the note, so a modulation is followed.
        local p = H.step(ctx.harmony.key(n.start), n.pitch, steps)
        if p >= 0 and p <= 127 then
          notes[#notes + 1] = { pitch = p, start = n.start, length = n.length, velocity = n.velocity }
        end
      end
      return { notes = notes }
    end,
  },
  {
    name = "voice-lead",
    desc = "the selected chords voiced again to move as little as they can, each the same chord",
    choices = {
      { name = "bass", values = { "keep", "free" } },
      { name = "voicing", values = { "smooth", "close", "drop2", "open" } },
    },
    expand = function(ctx)
      if not ctx.selection or #ctx.selection == 0 then return nil, "select the chords to voice first" end
      local notes, prev = {}, nil
      for i, g in ipairs(groups(ctx.selection)) do
        local pcs, seen = {}, {}
        for _, n in ipairs(g.notes) do
          if not seen[n.pitch % 12] then
            seen[n.pitch % 12] = true
            pcs[#pcs + 1] = n.pitch % 12
          end
        end
        -- Chord order, root first, as the reading names it when it can.
        local here = ctx.harmony.at(g.start)
        if here then
          local ordered = {}
          for _, t in ipairs(here.tones) do
            if seen[t] then
              ordered[#ordered + 1] = t
              seen[t] = nil
            end
          end
          for _, pc in ipairs(pcs) do
            if seen[pc] then ordered[#ordered + 1] = pc end
          end
          pcs = ordered
        end
        local pitches
        if i == 1 then
          pitches = {}
          for k, n in ipairs(g.notes) do
            pitches[k] = n.pitch
          end
        else
          pitches = ctx:voice(pcs, {
            prev = prev,
            next = false,
            count = #g.notes,
            low = ctx.range.low,
            high = ctx.range.high,
            bass = ctx.values.bass ~= "free" and g.notes[1].pitch % 12 or nil,
          })
        end
        local length = g.notes[1].length
        for k, p in ipairs(pitches or {}) do
          local source = g.notes[math.min(k, #g.notes)]
          notes[#notes + 1] =
            { pitch = p, start = g.start, length = source.length or length, velocity = source.velocity }
        end
        prev = pitches or prev
      end
      return { notes = notes, remove = ctx.selection }
    end,
  },
}
