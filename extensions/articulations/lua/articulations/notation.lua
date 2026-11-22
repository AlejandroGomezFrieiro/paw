-- The score and the articulations, both ways, when the notation extension
-- is loaded: a note's articulation shows as its mark (`mark = "staccato"`
-- in the map) and a run of notes starts with its technique text (`text =
-- "pizz."`, and `ord.` where the default comes back); writing a mark or a
-- technique in the score sets the attribute of the notes when the track's
-- map has an articulation for it (`paw.opt.art_from_notation`).
local art = require("articulations")
local marks = require("notation.marks")

local M = {}

-- The marks notation draws on a chord.
local DRAWN = { staccato = true, staccatissimo = true, accent = true, tenuto = true, marcato = true }

local function key(pitch, beat) return pitch .. "@" .. string.format("%.3f", beat) end

--- What the score shows of a clip's articulations: the marks on its notes,
--- and technique text where a run of notes changes articulation.
function M.extra(clip)
  local c = clip:get()
  local map = art.map_of(c.track)
  if not map then return nil end
  local default = art.default_of(c.track, map)
  local by_note, texts = {}, {}
  local last
  for _, n in ipairs(clip:notes()) do
    local a = art.attr_of(n) and art.resolve(map, art.attr_of(n)) or default
    by_note[key(n.pitch, n.start)] = a
    if a ~= last then
      local text = a and a.text
      if not text and last and last.text then text = default and default.text or "ord." end
      if text then texts[#texts + 1] = { at = n.start, kind = "technique", value = text } end
      last = a
    end
  end
  return {
    art = function(pitch, beat)
      local a = by_note[key(pitch, beat)]
      if a and a.mark and DRAWN[a.mark] then return { [a.mark] = true } end
    end,
    marks = texts,
  }
end

marks.extra("articulations", M.extra)

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

marks.listen(function(what)
  if not paw.opt.art_from_notation or not what.clip then return end
  local c = what.clip:get()
  local map = art.map_of(c.track)
  if not map then return end
  local places = {}
  local choice
  if what.kind == "art" then
    local a = by_mark(map, what.mark)
    if not a then return end
    local had = {}
    for _, n in ipairs(what.before or {}) do
      local own = marks.art_of(n)
      if n.id then had[n.id] = own[what.mark] and true or false end
    end
    for place, n in ipairs(what.clip:notes()) do
      local now = marks.art_of(n)[what.mark] and true or false
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
    for place, n in ipairs(what.clip:notes()) do
      if n.start >= what.from - 1e-9 and (not what.to or n.start < what.to - 1e-9) then
        places[#places + 1] = { clip = c.id, place = place }
      end
    end
    art.set(places, choice)
  end
end)

return M
