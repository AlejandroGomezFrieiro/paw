-- The score and the articulations, both ways, through paw and not through
-- the modules of the notation extension, so that each works without the
-- other: a note's articulation is a note mark (`paw.query.marks`), which the
-- score draws as its mark (`mark = "staccato"` in the map) and as its
-- technique text where a run of notes changes it (`text = "pizz."`, and
-- `ord.` where the default comes back). A mark or a technique written in the
-- score (the event `notation.marked`) sets the attribute of the notes when
-- the part's map has an articulation for it (`paw.opt.art_from_notation`).
local art = require("articulations")

local M = {}

--- The marks of a note's articulation: its mark, and its technique text.
--- A note with no articulation of its own has the default's.
function M.marks_of(note, clip)
  local map = art.map_of(clip.part)
  if not map then return nil end
  local a = art.attr_of(note) and art.resolve(map, art.attr_of(note)) or art.default_of(clip.part, map)
  if not a then return nil end
  return { art = a.mark and { a.mark } or nil, text = a.text }
end

paw.query.marks:put("articulations", M.marks_of)

--- The marks that the score has on a note, as a set: the notation
--- extension's entry of the note marks, when it is loaded.
local function score_marks(note)
  local of = paw.query.marks:get("notation")
  local out = {}
  for _, mark in ipairs(of and (of(note) or {}).art or {}) do
    out[mark] = true
  end
  return out
end

--- The map's articulation written as a mark, or with a technique's text.
local function by_mark(map, mark)
  for _, a in ipairs(map.arts) do
    if a.mark == mark then return a end
  end
end

local function plain(text) return tostring(text or ""):lower():gsub("%.$", ""):gsub("^%s+", ""):gsub("%s+$", "") end

local RETURNS = { arco = true, ord = true, ordinario = true, off = true, [""] = true, nat = true, normale = true }

local function by_text(map, text)
  local want = plain(text)
  for _, a in ipairs(map.arts) do
    if a.text and plain(a.text) == want then return a end
  end
end

-- The name of the event is the notation extension's: named here too, so
-- that it is known while notation is not loaded.
local marked = paw.events.event("notation.marked")

paw.on(marked, function(what)
  if not paw.opt.art_from_notation or not what.clip then return end
  local clip = paw.clip(what.clip)
  local c = clip:get()
  local map = art.map_of(c.part)
  if not map then return end
  local places = {}
  local choice
  if what.kind == "art" then
    local a = by_mark(map, what.mark)
    if not a then return end
    local had = {}
    for _, n in ipairs(what.before or {}) do
      local own = score_marks(n)
      if n.id then had[n.id] = own[what.mark] and true or false end
    end
    for place, n in ipairs(clip:notes()) do
      local now = score_marks(n)[what.mark] and true or false
      if n.id and had[n.id] ~= nil and had[n.id] ~= now then
        local current = art.attr_of(n) and art.resolve(map, art.attr_of(n))
        -- Taking the mark away takes away only the articulation it set.
        if now or current == a then places[#places + 1] = { clip = c.id, place = place, gain = now } end
      end
    end
    local on, off = {}, {}
    for _, p in ipairs(places) do
      if p.gain then
        on[#on + 1] = p
      else
        off[#off + 1] = p
      end
    end
    if #on > 0 then art.set(on, { attr = a.attr }) end
    if #off > 0 then art.set(off, false) end
    return
  elseif what.kind == "technique" then
    local a = by_text(map, what.text)
    if a then
      choice = { attr = a.attr }
    elseif RETURNS[plain(what.text)] then
      choice = false
    else
      return
    end
    for place, n in ipairs(clip:notes()) do
      if n.start >= what.from - 1e-9 and (not what.to or n.start < what.to - 1e-9) then
        places[#places + 1] = { clip = c.id, place = place }
      end
    end
    art.set(places, choice)
  end
end)

return M
