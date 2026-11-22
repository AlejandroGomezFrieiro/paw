-- Tablature for a track marked as guitar or bass: the strings and their
-- tuning are kept in `track.meta.notation.tab` (`{ tuning = { 40, 45, ... } }`,
-- lowest string first), and every written note gets a string and a fret,
-- chosen so a chord's notes are on different strings within a hand's reach
-- and the hand moves as little as it can. `meta.notation.string` on a note
-- fixes its string.
local api = paw.api
local util = paw.util
local view = require("notation")

local M = {}

M.TUNINGS = {
  guitar = { 40, 45, 50, 55, 59, 64 },
  dropd = { 38, 45, 50, 55, 59, 64 },
  dadgad = { 38, 45, 50, 55, 57, 62 },
  ["7string"] = { 35, 40, 45, 50, 55, 59, 64 },
  bass = { 28, 33, 38, 43 },
  bass5 = { 23, 28, 33, 38, 43 },
}
M.FRETS = 24

--- The tablature a track asks for: `{ tuning, capo }`, or nil.
function M.of_track(track_id)
  local ok, t = pcall(api.track_get, track_id)
  local own = ok and t.meta and type(t.meta.notation) == "table" and t.meta.notation.tab
  if type(own) == "table" and type(own.tuning) == "table" and #own.tuning > 0 then return own end
end

--- Whether a tuning is a bass's: its highest string below middle C's octave.
function M.is_bass(tuning) return tuning[#tuning] < 48 end

--- Strings and frets for the notes of each written chord, in order. Sets
--- `n.string` (1 the highest string, as tablature counts) and `n.fret` on
--- the notes of note events; a note no string reaches gets neither.
function M.assign(layout, tab)
  local tuning, capo = tab.tuning, tab.capo or 0
  local count = #tuning
  local hand = nil -- where the hand was: the mean fret of the last chord
  local function options(pitch, forced)
    local out = {}
    for i, open in ipairs(tuning) do
      local fret = pitch - open - capo
      local string_no = count - i + 1
      if fret >= 0 and fret <= M.FRETS and (not forced or forced == string_no) then
        out[#out + 1] = { string = string_no, fret = fret }
      end
    end
    return out
  end
  local chords = {}
  for _, m in ipairs(layout.measures) do
    for _, evs in ipairs(m.staves) do
      for _, ev in ipairs(evs) do
        if ev.kind == "note" then chords[#chords + 1] = ev end
      end
    end
  end
  table.sort(chords, function(a, b) return a.start < b.start end)
  for _, ev in ipairs(chords) do
    -- A tied note keeps the string it started on.
    local notes = {}
    for _, n in ipairs(ev.notes) do
      notes[#notes + 1] = n
    end
    table.sort(notes, function(a, b) return a.pitch > b.pitch end)
    local best, best_cost
    local used, pick = {}, {}
    local function search(k)
      if k > #notes then
        local lo, hi, sum, fretted = math.huge, -math.huge, 0, 0
        for _, p in pairs(pick) do
          if p.fret > 0 then
            lo, hi = math.min(lo, p.fret), math.max(hi, p.fret)
            sum, fretted = sum + p.fret, fretted + 1
          end
        end
        local cost = 0
        if fretted > 0 then
          local span = hi - lo
          if span > 4 then cost = cost + (span - 4) * 3 end
          local mean = sum / fretted
          cost = cost + mean * 0.15 + (hand and math.abs(mean - hand) * 0.4 or 0)
        end
        if not best_cost or cost < best_cost then
          best_cost = cost
          best = {}
          for i, p in pairs(pick) do
            best[i] = p
          end
        end
        return
      end
      local n = notes[k]
      local own = n.meta and type(n.meta.notation) == "table" and n.meta.notation or {}
      local any = false
      for _, o in ipairs(options(n.pitch, tonumber(own.string))) do
        if not used[o.string] then
          used[o.string], pick[k] = true, o
          search(k + 1)
          used[o.string], pick[k] = nil, nil
          any = true
        end
      end
      if not any then search(k + 1) end
    end
    search(1)
    local sum, fretted = 0, 0
    for k, n in ipairs(notes) do
      local p = best and best[k]
      n.string, n.fret = p and p.string or nil, p and p.fret or nil
      if p and p.fret > 0 then
        sum, fretted = sum + p.fret, fretted + 1
      end
    end
    if fretted > 0 then hand = sum / fretted end
  end
  -- Tied notes keep their string.
  for _, ev in ipairs(chords) do
    local nxt = ev.next
    if nxt and nxt.notes then
      for i, n in ipairs(ev.notes) do
        if n.tie and nxt.notes[i] then
          nxt.notes[i].string, nxt.notes[i].fret = n.string, n.fret
        end
      end
    end
  end
  layout.tab = { tuning = tuning, capo = capo, strings = count }
end

function M.decorate(layout, clip)
  local tab = M.of_track(clip:get().track)
  if tab then M.assign(layout, tab) end
end
table.insert(view.decorators, M.decorate)

--- Mark a track's part as guitar or bass, with a tuning by name or by its
--- notes from the lowest string ("E2 A2 D3 G3 B3 E4"), or take the tab away.
function M.set(track, words)
  local meta = util.merge(track.meta or {}, {})
  local own = type(meta.notation) == "table" and util.merge(meta.notation, {}) or {}
  local first = words[1]
  if first == "off" then
    own.tab = nil
    if own.clef == "treble8" then own.clef = nil end
  else
    local tuning
    if M.TUNINGS[first or "guitar"] then
      tuning = util.merge(M.TUNINGS[first or "guitar"], {})
    else
      tuning = {}
      for _, w in ipairs(words) do
        local ok, p = pcall(paw.music.pitch, w)
        if not ok then return nil, "not a note: " .. tostring(w) end
        tuning[#tuning + 1] = p
      end
      table.sort(tuning)
    end
    own.tab = { tuning = tuning }
    if not own.clef then own.clef = M.is_bass(tuning) and "bass" or "treble8" end
  end
  meta.notation = next(own) and own or nil
  track.meta = meta
  return own.tab
end

view.tab = M
return M
