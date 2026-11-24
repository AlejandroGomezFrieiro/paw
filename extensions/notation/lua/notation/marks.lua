-- Marks besides the notes: articulations on chords (staccato,
-- staccatissimo, tenuto, accent, marcato), and along the score dynamics,
-- hairpins, slurs, text and repeat signs. They are written in the score
-- (`notation.doc`: `event.art`, `score.marks`, `measure.repeat_start` and
-- `barline`), which keeps them with the notes and the clip
-- (`notation.midi`). The ones that play write MIDI when they are written:
-- a staccato shortens its notes and a tenuto holds them, an accent makes
-- them louder, a dynamic sets the loudness of the notes it reaches and a
-- hairpin ramps it. Slurs, text and repeat signs are written only.
local util = paw.util
local view = require("notation")
local D = require("notation.doc")
local midi = require("notation.midi")

local M = {}
local EPS = 1e-6

M.DYNAMICS = midi.DYNAMICS
M.ORDER = midi.ORDER
M.ARTICULATIONS = midi.ARTICULATIONS

--- The articulations a clip's note carries.
function M.art_of(note)
  local own = note and note.meta and type(note.meta.notation) == "table" and note.meta.notation.art
  return type(own) == "table" and own or {}
end

-- Other extensions' part in the marks goes through paw, not through this
-- module, so that each extension works without the other:
-- - `paw.query.marks` (a registry of the core): what gives the marks of a
--   note. This extension puts its own ("notation", below). The score draws
--   the marks that the others give (the articulations extension: the mark
--   and the technique text of each note's articulation), and writes none.
-- - The event `notation.marked`, after a mark is written in the score:
--   `{ kind = "art", mark, on, clip, before }` (`clip` an id, `before` the
--   clip's notes before), or `{ kind = "technique", text, from, to, clip }`
--   (`to` nil: to the end).
local marked = paw.events.event("notation.marked")

--- Tell the other extensions that a mark was written (`notation.marked`).
function M.tell(what)
  what.clip = type(what.clip) == "table" and what.clip.id or what.clip
  paw.emit(marked, what)
end

-- The marks written in the score, for `:select`, `:vimgrep` and the pickers.
paw.query.marks:put("notation", function(note)
  local out = {}
  for name, on in pairs(M.art_of(note)) do
    if on then out[#out + 1] = tostring(name) end
  end
  table.sort(out)
  return { art = out }
end)

--- Toggle an articulation on chords of the score, by their event ids (the
--- chord under the cursor's, a selection's): on for all unless all have it.
--- Returns whether it is on.
function M.toggle_art(kind, ids)
  if #ids == 0 then return nil end
  local on
  local clip = view:clip()
  local before = clip and paw.events.listened("notation.marked") and clip:notes() or nil
  view:write(function(sc)
    local evs = {}
    for _, id in ipairs(ids) do
      local mi, _, _, _, ev = D.find(sc, id)
      if ev and ev.kind == "chord" then evs[#evs + 1] = { ev = ev, mi = mi } end
    end
    if #evs == 0 then return false end
    on = false
    for _, x in ipairs(evs) do
      if not (x.ev.art and x.ev.art[kind]) then on = true end
    end
    for _, x in ipairs(evs) do
      local art = util.merge(x.ev.art or {}, {})
      art[kind] = on or nil
      x.ev.art = next(art) and art or nil
      D.touch(sc, x.mi)
    end
  end)
  if before and on ~= nil then M.tell({ kind = "art", mark = kind, on = on, clip = clip, before = before }) end
  return on
end

-- Marks along the score -----------------------------------------------------------------------

--- A place in the score for a beat of the clip: `{ measure, at }`.
function M.ref(sc, beat)
  local mi, at = view.where(sc, beat)
  D.ensure(sc, mi)
  return { measure = sc.measures[mi].id, at = D.ratio(at) }, mi
end

local KINDS = { dyn = "dynamic", cresc = "hairpin", dim = "hairpin", text = "text", slur = "slur" }

--- Put a mark at a beat of the open clip, replacing one of its kind there,
--- or take it away with `value` false: `{ at, kind = "dyn" | "cresc" |
--- "dim" | "text" | "repeat", value, to }`. (`clip` is the open clip.)
function M.put(_, mark)
  view:write(function(sc)
    if mark.kind == "repeat" then
      local mi, at = view.where(sc, mark.at)
      D.ensure(sc, mi)
      if mark.value == "start" or (mark.value == false and at == 0) then
        sc.measures[mi].repeat_start = mark.value and true or nil
      end
      local before = at == 0 and sc.measures[mi - 1] or nil
      if before and (mark.value == "end" or mark.value == false) then before.barline = mark.value and ":|" or nil end
      D.touch(sc, mi)
      if before then D.touch(sc, mi - 1) end
      return
    end
    local kind = KINDS[mark.kind]
    local ref, mi = M.ref(sc, mark.at)
    local list = {}
    local f = D.frame(sc)
    local t = midi.at_of(sc, f, ref)
    for _, mk in ipairs(sc.marks or {}) do
      local same = mk.kind == kind and midi.at_of(sc, f, mk.from) == t
      if not same then list[#list + 1] = mk end
    end
    if mark.value ~= false then
      local new = { id = D.id(sc, "k"), kind = kind, from = ref }
      if kind == "dynamic" or kind == "text" then new.value = mark.value end
      if kind == "hairpin" then
        new.value, new.to = mark.kind, M.ref(sc, mark.to)
      end
      list[#list + 1] = new
    end
    sc.marks = list
    D.touch(sc, mi)
  end)
  paw.ui.poke()
end

--- A slur over the notes written from `from` to `to` (clip beats) on a
--- staff (by its index), or none there if one starts there. Returns
--- whether there is one now.
function M.slur(_, from, to, staff)
  local on = false
  view:write(function(sc)
    local st = (sc.staves[staff or 1] or sc.staves[1]).id
    local ref, mi = M.ref(sc, from)
    local f = D.frame(sc)
    local t = midi.at_of(sc, f, ref)
    local list, removed = {}, false
    for _, mk in ipairs(sc.marks or {}) do
      if mk.kind == "slur" and mk.staff == st and midi.at_of(sc, f, mk.from) == t then
        removed = true
      else
        list[#list + 1] = mk
      end
    end
    if not removed then
      list[#list + 1] = { id = D.id(sc, "k"), kind = "slur", staff = st, from = ref, to = M.ref(sc, to) }
      on = true
    end
    sc.marks = list
    D.touch(sc, mi)
  end)
  return on
end

-- On the layout --------------------------------------------------------------------------------

local XML_WEDGE = { cresc = "crescendo", dim = "diminuendo" }

--- Marks of the score as the layout draws them: `{ at, kind = "dyn" |
--- "cresc" | "dim" | "text" | "tempo" | "chord" | "technique", value, to }`
--- in clip beats, and slurs `{ from, to, staff }`. `marks` are the
--- score's (`score.marks`) with `beat(ref)` their places, or a clip's
--- `meta.notation.marks` (in beats) for a layout made without a score.
local function drawn(list, beat, staff_of)
  local marks, slurs = {}, {}
  -- What a popover would write is drawn as a ghost until it is written.
  local ghost = view.ghost and view.ghost.marks or {}
  for _, mk in ipairs(list) do
    local at = beat(mk.from or mk.at)
    if at then
      local first = #marks
      local to = mk.to and beat(mk.to) or at
      if mk.kind == "dynamic" or mk.kind == "dyn" then
        marks[#marks + 1] = { at = at, kind = "dyn", value = mk.value, subito = mk.subito }
      elseif mk.kind == "hairpin" or mk.kind == "cresc" or mk.kind == "dim" then
        local kind = mk.kind == "hairpin" and mk.value or mk.kind
        marks[#marks + 1] = { at = at, kind = kind == "dim" and "dim" or "cresc", to = to, niente = mk.niente }
      elseif mk.kind == "tempo" or mk.kind == "chord" or mk.kind == "technique" then
        marks[#marks + 1] = { at = at, kind = mk.kind, value = mk.value, bpm = mk.bpm, change = mk.change }
      elseif mk.kind == "text" or mk.kind == "repeat" then
        marks[#marks + 1] = { at = at, kind = mk.kind, value = mk.value }
      elseif mk.kind == "slur" then
        slurs[#slurs + 1] = { from = at, to = to, staff = staff_of(mk.staff) }
      end
      if mk.id and ghost[mk.id] and marks[first + 1] then marks[first + 1].ghost = true end
    end
  end
  table.sort(marks, function(a, b) return a.at < b.at end)
  return marks, slurs
end

-- The marks that the score draws over its notes: the others give these names.
local DRAWN = { staccato = true, staccatissimo = true, accent = true, tenuto = true, marcato = true }

--- What the other sources of `paw.query.marks` give of a clip's notes:
--- `{ art = { ["pitch@beat"] = { staccato = true } }, marks = { technique
--- texts } }`, or nil when no other source gives anything. A technique
--- text shows where a run of notes changes it, and `ord.` where a text
--- stops.
local function others_marks(clip)
  local sources = {}
  for name, fn in pairs(paw.query.marks:entries()) do
    if name ~= "notation" then sources[#sources + 1] = { name = name, fn = fn } end
  end
  if #sources == 0 then return nil end
  table.sort(sources, function(a, b) return a.name < b.name end)
  local c = clip:get()
  local art, texts, any = {}, {}, false
  for _, source in ipairs(sources) do
    local last
    for _, n in ipairs(clip:notes()) do
      local ok, got = pcall(source.fn, n, c)
      if not ok then
        paw.api.log("notation marks of " .. source.name .. ": " .. tostring(got), "warn")
        break
      end
      got = got or {}
      local key = n.pitch .. "@" .. string.format("%.3f", n.start)
      for _, mark in ipairs(got.art or {}) do
        if DRAWN[mark] then
          art[key] = art[key] or {}
          art[key][mark], any = true, true
        end
      end
      if got.text ~= last then
        local text = got.text or (last and "ord.")
        if text then
          texts[#texts + 1], any = { at = n.start, kind = "technique", value = text }, true
        end
        last = got.text
      end
    end
  end
  return any and { art = art, marks = texts } or nil
end

local function marks_of(layout, c)
  local sc = layout.doc
  if not sc then
    local own = view.own(c)
    local list = {}
    for _, mk in ipairs(own.marks or {}) do
      list[#list + 1] = mk
    end
    for _, sl in ipairs(own.slurs or {}) do
      list[#list + 1] = { kind = "slur", at = sl.from, to = sl.to, staff = sl.staff }
    end
    return drawn(list, function(x) return x end, function(s) return s or 1 end)
  end
  return drawn(
    sc.marks or {},
    function(ref) return midi.beat_of(sc, ref) end,
    function(s) return D.staff_index(sc, s) or 1 end
  )
end

--- Put the marks on a layout's measures and events, for drawing and export:
--- `ev.art`, `ev.lyric`, `ev.slurs` ("start", "stop"), `m.marks`,
--- `m.directions` (MusicXML), `m.repeat_start`, `m.repeat_end`.
function M.decorate(layout, clip)
  local c = clip:get()
  local marks, slurs = marks_of(layout, c)
  -- What other extensions draw over the notes and along the score.
  local extras = others_marks(clip)
  for _, mk in ipairs(extras and extras.marks or {}) do
    marks[#marks + 1] = mk
  end
  if extras then table.sort(marks, function(a, b) return a.at < b.at end) end
  for _, m in ipairs(layout.measures) do
    m.marks, m.directions = {}, {}
    local e = m.start + m.length
    for _, mk in ipairs(marks) do
      if mk.at >= m.start - EPS and mk.at < e - EPS then
        m.marks[#m.marks + 1] = mk
        if mk.kind == "dyn" then
          m.directions[#m.directions + 1] = { start = mk.at, xml = "<dynamics><" .. mk.value .. "/></dynamics>" }
        elseif XML_WEDGE[mk.kind] then
          m.directions[#m.directions + 1] = { start = mk.at, xml = '<wedge type="' .. XML_WEDGE[mk.kind] .. '"/>' }
        elseif mk.kind == "text" or mk.kind == "technique" or (mk.kind == "tempo" and not mk.bpm) then
          m.directions[#m.directions + 1] =
            { start = mk.at, xml = "<words>" .. tostring(mk.value):gsub("&", "&amp;"):gsub("<", "&lt;") .. "</words>" }
        end
        if mk.kind == "repeat" and mk.value == "start" then m.repeat_start = true end
      end
      if XML_WEDGE[mk.kind] and mk.to and mk.to > m.start + EPS and mk.to <= e + EPS then
        m.directions[#m.directions + 1] = { start = math.min(mk.to, e), xml = '<wedge type="stop"/>' }
      end
      if mk.kind == "repeat" and mk.value == "end" and math.abs(mk.at - e) < 1e-3 then m.repeat_end = true end
      if
        mk.kind == "repeat"
        and mk.value == "end"
        and mk.at >= m.start - EPS
        and mk.at < e - EPS
        and math.abs(mk.at - m.start) < 1e-3
      then
        local before = layout.measures[m.index - 1]
        if before then before.repeat_end = true end
      end
    end
    if not layout.doc then
      -- Articulations and lyrics a MIDI clip's notes carry.
      for _, evs in ipairs(m.staves) do
        for _, ev in ipairs(evs) do
          if ev.kind == "note" and not ev.notes[1].tied then
            local art = {}
            for _, n in ipairs(ev.notes) do
              for k, v in pairs(M.art_of(n)) do
                art[k] = v
              end
              if not ev.lyric and n.lyric and n.lyric ~= "" then ev.lyric = n.lyric end
            end
            ev.art = next(art) and art or nil
          end
        end
      end
    end
    if extras then
      for _, evs in ipairs(m.staves) do
        for _, ev in ipairs(evs) do
          if ev.kind == "note" and not ev.notes[1].tied then
            -- A score's events are laid out once: what they had of their own is kept apart.
            if not layout.doc or ev.own_art == nil then ev.own_art = ev.art or false end
            local art = util.merge(ev.own_art or {}, {})
            for _, n in ipairs(ev.notes) do
              for k in pairs(extras.art[n.pitch .. "@" .. string.format("%.3f", ev.start)] or {}) do
                art[k] = true
              end
            end
            ev.art = next(art) and art or nil
          end
        end
      end
    end
  end
  -- Slurs: from the first note at or after their start to the last before
  -- their end. A score's measures are laid out once and kept, so what was
  -- put on their events before is taken off first.
  if layout.doc then
    for _, m in ipairs(layout.measures) do
      for _, evs in ipairs(m.staves) do
        for _, ev in ipairs(evs) do
          ev.slurs, ev.slur_to = nil, nil
        end
      end
    end
  end
  for _, sl in ipairs(slurs) do
    local first, last
    for _, m in ipairs(layout.measures) do
      for _, ev in ipairs(m.staves[sl.staff] or {}) do
        if ev.kind == "note" and not ev.notes[1].tied and ev.start >= sl.from - EPS and ev.start <= sl.to + EPS then
          first = first or ev
          last = ev
        end
      end
    end
    if first and last and first ~= last then
      first.slurs = first.slurs or {}
      table.insert(first.slurs, "start")
      last.slurs = last.slurs or {}
      table.insert(last.slurs, "stop")
      first.slur_to = last
    end
  end
end

table.insert(view.decorators, M.decorate)
view.marks = M
return M
