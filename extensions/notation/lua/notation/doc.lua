-- The written score: the document the notation view shows and edits, and
-- every edit made to it. A clip's score is made from its MIDI notes and
-- what notation keeps beside them (`notation.midi`), each edit changes it,
-- and what changed is written back as MIDI edits; the page is laid out from
-- it (`notation.layout`). Plain Lua tables.
--
--   score = {
--     version = 1, rev,          -- rev changes with every edit
--     origin = { n, d },         -- where measure 1 starts, from the clip's start (0 or less)
--     staves = { { id, clef } }, -- a grand staff is two staves of one clip
--     measures = { { id, v, meter? = { num, den }, groups? = { 3, 3, 2 }, barline? = "||" | "|." | ":|",
--                    repeat_start?, volta? = n, rehearsal? = "A", key? = { fifths, name },
--                    clef? = { [staff id] = clef }, voices = { { staff, voice, events } } } },
--     marks = { { id, kind, staff?, from = ref, to? = ref, value? } }, next,
--     layout? = { breaks = { { id, measure = id, kind = "break" | "join" } }, per_system? },
--   }
--   event = { id, kind = "chord" | "rest", dur = { n, d }, dots, tuplet? = { id, actual, normal },
--             notes = { { id, step = 0..6, alter, octave, tie? } }, grace? = "acciaccatura" | "appoggiatura",
--             art? = { staccato, ... }, arpeggio? = "up" | "down", beam? = "break", stem? = "up" | "down", lyric? }
--   ref = { measure = id, at = { n, d } } or, for a slur, { measure = id, event = id }
--   mark kinds: dynamic (value, subito?), hairpin (value "cresc" | "dim", to, niente?), slur, text,
--             tempo (value = the text, bpm?, change? = "rit." | "accel." | "a tempo"), chord (value),
--             technique (value)
--   event marks: art = { staccato, ..., fermata }, orn? = "trill" | "mordent" | "turn" | ...,
--             lyric (verse 1), lyrics? = { [n] = text } for verses after it ("" where none)
--
-- Durations are fractions of a whole note, `dur` the undotted value. Inside
-- this module time is counted in ticks, whole numbers of 1/40320 of a whole
-- note, which divides every value from a whole note to a 128th in duplets,
-- triplets, quintuplets and septuplets, so nothing drifts. A voice's events
-- fill its measure in order; a voice 1 with no events is a whole bar's rest,
-- and a voice 2 that is only rests is no voice at all. `v` on a measure is a
-- token that changes when the measure does, for the caches by measure.
local model = require("notation.model")

local M = {}

local W = 40320 -- ticks in a whole note
local Q = W / 4 -- in a quarter, a beat
M.W, M.Q = W, Q

local floor, abs = math.floor, math.abs

local function gcd(a, b)
  a, b = abs(a), abs(b)
  while b ~= 0 do
    a, b = b, a % b
  end
  return a
end

--- Ticks of a fraction of a whole note.
function M.ticks(r) return floor(r[1] * W / r[2] + 0.5) end
--- A fraction of a whole note, lowest terms, for ticks.
function M.ratio(t)
  local g = gcd(t, W)
  if g == 0 then return { 0, 1 } end
  return { t / g, W / g }
end
function M.beats(t) return t / Q end
function M.from_beats(b) return floor(b * Q + 0.5) end

local LETTER_PC = { [0] = 0, 2, 4, 5, 7, 9, 11 }

--- The MIDI pitch a spelled note sounds.
function M.pitch(n) return (n.octave + 1) * 12 + LETTER_PC[n.step] + (n.alter or 0) end
--- The diatonic step from C-1 (C4 is 35) of a spelled note.
function M.diatonic(n) return (n.octave + 1) * 7 + n.step end
--- A spelled note from a model spelling (`letter`, `alter`, `octave`).
function M.spelled(sp, id) return { id = id, step = sp.letter, alter = sp.alter, octave = sp.octave } end

-- Identity and versions -----------------------------------------------------------------------

local serial = 0
--- A token that differs from every other made in this run and before it.
local function token()
  serial = serial + 1
  return string.format(
    "%x.%x",
    floor((paw and paw.api and paw.api.now() or os.clock() * 1000) * 1000) % 0xfffffff,
    serial
  )
end
M.token = token

function M.id(score, prefix)
  local n = score.next or 1
  score.next = n + 1
  return prefix .. n
end

--- Mark a measure changed.
function M.touch(score, mi)
  local m = score.measures[mi]
  if m then m.v = token() end
  score.rev = token()
end

-- The page's layout --------------------------------------------------------------------------------

-- What the score asks of its page (`score.layout`), which the engraver
-- breaks systems by (`notation.breaks`): a system break before a measure,
-- a measure kept on the system before, and how many measures to a system.

--- The break the score asks for before a measure (by id): "break",
--- "join" or nil.
function M.break_at(score, measure)
  for _, b in ipairs(score.layout and score.layout.breaks or {}) do
    if b.measure == measure then return b.kind end
  end
end

--- Ask for a break (`kind` "break" or "join") before a measure, or for
--- none with nil.
function M.set_break(score, measure, kind)
  local own = score.layout or {}
  local list = {}
  for _, b in ipairs(own.breaks or {}) do
    if b.measure ~= measure then list[#list + 1] = b end
  end
  if kind then list[#list + 1] = { id = M.id(score, "l"), measure = measure, kind = kind } end
  own.breaks = list
  score.layout = own
  score.rev = token()
end

--- Measures to a system, or as they fit with nil.
function M.set_per_system(score, n)
  score.layout = score.layout or { breaks = {} }
  score.layout.per_system = n
  score.rev = token()
end

-- Measures ---------------------------------------------------------------------------------------

--- Each measure's meter, start and length in ticks from measure 1, and the
--- index of each measure id. Kept on the score table until it is changed.
function M.frame(score)
  local f = score._frame
  if f and f.count == #score.measures and f.rev == score.rev then return f end
  f = { meters = {}, starts = {}, lengths = {}, index = {}, count = #score.measures, rev = score.rev }
  local meter, at = { 4, 4 }, 0
  for i, m in ipairs(score.measures) do
    -- Read without copying a measure of a copied score (see `M.copy`).
    local own, groups = M.peek(m, "meter"), M.peek(m, "groups")
    if own then meter = groups and { own[1], own[2], groups = groups } or own end
    f.meters[i], f.starts[i], f.lengths[i], f.index[m.id] = meter, at, meter[1] * W / meter[2], i
    at = at + f.lengths[i]
  end
  f.finish = at
  score._frame = f
  return f
end

function M.origin(score) return M.ticks(score.origin or { 0, 1 }) end

--- A new, empty score: a measure for each bar (`{ start, num, den }` in clip
--- beats) and the staves' clefs.
function M.new(bars, clefs)
  local score = { version = 1, staves = {}, measures = {}, marks = {}, style = {}, next = 1 }
  for i, clef in ipairs(clefs) do
    score.staves[i] = { id = "s" .. i, clef = clef }
  end
  score.next = #clefs + 1
  local origin = bars[1] and bars[1].start or 0
  score.origin = M.ratio(M.from_beats(origin))
  local last
  for _, b in ipairs(bars) do
    local m = { id = M.id(score, "m"), voices = {} }
    if not last or last[1] ~= b.num or last[2] ~= b.den then m.meter = { b.num, b.den } end
    last = { b.num, b.den }
    m.v = token()
    score.measures[#score.measures + 1] = m
  end
  score.rev = token()
  return score
end

--- Make sure measure `mi` exists, adding measures in the last one's meter.
function M.ensure(score, mi)
  while #score.measures < mi do
    score.measures[#score.measures + 1] = { id = M.id(score, "m"), voices = {}, v = token() }
    score.rev = token()
  end
end

--- The measure and the ticks into it of a place in ticks from measure 1.
function M.locate(score, t)
  local f = M.frame(score)
  if t < 0 then return 1, 0 end
  for i = 1, f.count do
    if t < f.starts[i] + f.lengths[i] then return i, t - f.starts[i] end
  end
  -- Past the end: in measures yet to be made, in the last one's meter.
  local len = f.count > 0 and f.lengths[f.count] or W
  local over = t - f.finish
  local k = floor(over / len)
  return f.count + 1 + k, over - k * len
end

function M.staff_index(score, id)
  for i, s in ipairs(score.staves) do
    if s.id == id then return i end
  end
end

--- The events of a voice of a staff in a measure, or nil; with `create`, an
--- empty voice is made.
function M.voice(m, staff, v, create)
  for _, e in ipairs(m.voices) do
    if e.staff == staff and e.voice == v then return e end
  end
  if create then
    local e = { staff = staff, voice = v, events = {} }
    m.voices[#m.voices + 1] = e
    return e
  end
end

-- Lengths and values -----------------------------------------------------------------------------

--- How long an event lasts, in ticks: a grace note takes none.
function M.length(ev)
  if ev.grace then return 0 end
  local base = M.ticks(ev.dur)
  local len, add = base, base
  for _ = 1, ev.dots or 0 do
    add = add / 2
    len = len + add
  end
  if ev.tuplet then len = len * ev.tuplet.normal / ev.tuplet.actual end
  return floor(len + 0.5)
end

function M.meter(num, den, groups) return model.meter_of(num, den, groups) end

local BASES = {}
for _, b in ipairs(model.BASES) do
  BASES[#BASES + 1] = M.from_beats(b)
end

--- Written values for a stretch `a` to `b` (ticks into a measure) as the
--- metre divides it: `{ { s, len, dur, dots } }`. `rest` writes silence.
function M.values(a, b, meter, rest)
  local out = {}
  local mo = M.meter(meter[1], meter[2], meter.groups)
  for _, p in ipairs(model.split(a / Q, b / Q, mo, rest)) do
    local s, e = M.from_beats(p[1]), M.from_beats(p[2])
    local base, dots = model.value_of((e - s) / Q, 2)
    if base then
      out[#out + 1] = { s = s, len = e - s, dur = M.ratio(M.from_beats(base)), dots = dots }
    else
      -- Below a 32nd, or not a single value: the largest that fit.
      local t = s
      while e - t > 0 do
        local step
        for _, v in ipairs(BASES) do
          if v <= e - t then
            step = v
            break
          end
        end
        step = step or (e - t)
        out[#out + 1] = { s = t, len = step, dur = M.ratio(step), dots = 0 }
        t = t + step
      end
    end
  end
  return out
end

--- Written values for a stretch inside a tuplet, longest first.
local function tuplet_values(a, b, tp)
  local out = {}
  local written = (b - a) * tp.actual / tp.normal
  local t = a
  while written > 0 do
    local pick, dots
    for _, v in ipairs(BASES) do
      if v * 1.5 <= written then
        pick, dots = v, 1
        break
      end
      if v <= written then
        pick, dots = v, 0
        break
      end
    end
    pick, dots = pick or written, dots or 0
    local w = pick * (dots == 1 and 1.5 or 1)
    local len = floor(w * tp.normal / tp.actual + 0.5)
    out[#out + 1] = { s = t, len = len, dur = M.ratio(pick), dots = dots }
    t, written = t + len, written - w
  end
  return out
end

-- A voice as a line of items ----------------------------------------------------------------------

--- The items of a voice in a measure: `{ ev, s, e }` in ticks, graces with
--- no length before the event they lead to. A voice 1 with nothing is a
--- whole bar's rest.
function M.line(score, mi, staff, v)
  local f = M.frame(score)
  local m = score.measures[mi]
  local entry = M.voice(m, staff, v)
  local items, t = {}, 0
  if entry and #entry.events > 0 then
    for _, ev in ipairs(entry.events) do
      local len = M.length(ev)
      items[#items + 1] = { ev = ev, s = t, e = t + len }
      t = t + len
    end
  end
  -- What does not fill the bar is shown as rests.
  if t < f.lengths[mi] then
    for _, p in ipairs(M.values(t, f.lengths[mi], f.meters[mi], true)) do
      items[#items + 1] =
        { ev = { id = M.id(score, "e"), kind = "rest", dur = p.dur, dots = p.dots }, s = p.s, e = p.s + p.len }
    end
  end
  return items
end

local function copy_notes(score, notes, tie, keep)
  local out = {}
  for i, n in ipairs(notes) do
    out[i] =
      { id = keep and n.id or M.id(score, "n"), step = n.step, alter = n.alter, octave = n.octave, tie = tie or nil }
  end
  return out
end

--- Pieces of an event cut to the stretch `a` to `b`: a chord's as tied
--- values (the first keeps its ids), a rest's as rests.
local function pieces(score, item, a, b, meter, rest)
  local ev = item.ev
  local tp = ev.tuplet
  local vals = tp and tuplet_values(a, b, tp) or M.values(a, b, meter, rest or ev.kind == "rest")
  local out = {}
  for k, p in ipairs(vals) do
    local piece
    if rest or ev.kind == "rest" then
      piece = {
        id = (k == 1 and not rest) and ev.id or M.id(score, "e"),
        kind = "rest",
        dur = p.dur,
        dots = p.dots,
        tuplet = tp,
      }
    else
      local last = k == #vals
      piece = {
        id = k == 1 and ev.id or M.id(score, "e"),
        kind = "chord",
        dur = p.dur,
        dots = p.dots,
        tuplet = tp,
        art = k == 1 and ev.art or nil,
        arpeggio = k == 1 and ev.arpeggio or nil,
        beam = k == 1 and ev.beam or nil,
        stem = ev.stem,
        orn = k == 1 and ev.orn or nil,
        lyric = k == 1 and ev.lyric or nil,
        lyrics = k == 1 and ev.lyrics or nil,
      }
      if k == 1 then
        piece.notes = {}
        for i, n in ipairs(ev.notes) do
          piece.notes[i] = { id = n.id, step = n.step, alter = n.alter, octave = n.octave, tie = (not last) or nil }
        end
      else
        piece.notes = copy_notes(score, ev.notes, not last)
      end
    end
    out[#out + 1] = { ev = piece, s = p.s, e = p.s + p.len }
  end
  return out
end

--- The tuplets of a line: `{ [id] = { s, e, tuplet } }`.
local function tuplets_of(items)
  local out = {}
  for _, it in ipairs(items) do
    local tp = it.ev.tuplet
    if tp and not it.ev.grace then
      local span = out[tp.id]
      if span then
        span.e = it.e
      else
        out[tp.id] = { s = it.s, e = it.e, tuplet = tp }
      end
    end
  end
  return out
end

--- Write the stretch `a` to `b` of a voice in measure `mi`: what was there
--- gives way (a chord cut by it keeps what is before, tied; what is after
--- is a rest), and `new` (events filling the stretch exactly, or nothing
--- for a rest) goes in. A tuplet the stretch only partly covers becomes a
--- rest first, unless the new events are of that tuplet. Then the voice's
--- rests are merged as the metre divides the bar.
function M.splice(score, mi, staff, v, a, b, new)
  M.ensure(score, mi)
  local f = M.frame(score)
  local meter = f.meters[mi]
  local items = M.line(score, mi, staff, v)
  local inside = new and new[1] and new[1].tuplet and new[1].tuplet.id
  for id, span in pairs(tuplets_of(items)) do
    local partly = span.s < b and span.e > a and not (span.s >= a and span.e <= b)
    if partly and id ~= inside then
      -- The whole tuplet becomes silence.
      local kept = {}
      local placed = false
      for _, it in ipairs(items) do
        if it.ev.tuplet and it.ev.tuplet.id == id then
          if not placed then
            for _, p in ipairs(M.values(span.s, span.e, meter, true)) do
              kept[#kept + 1] =
                { ev = { id = M.id(score, "e"), kind = "rest", dur = p.dur, dots = p.dots }, s = p.s, e = p.s + p.len }
            end
            placed = true
          end
        else
          kept[#kept + 1] = it
        end
      end
      items = kept
    end
  end
  local out, put = {}, false
  local function insert()
    if put then return end
    put = true
    if new then
      local t = a
      for _, ev in ipairs(new) do
        local len = M.length(ev)
        out[#out + 1] = { ev = ev, s = t, e = t + len }
        t = t + len
      end
    else
      for _, p in ipairs(M.values(a, b, meter, true)) do
        out[#out + 1] =
          { ev = { id = M.id(score, "e"), kind = "rest", dur = p.dur, dots = p.dots }, s = p.s, e = p.s + p.len }
      end
    end
  end
  for _, it in ipairs(items) do
    local graced = it.s == it.e
    if graced then
      -- Grace notes where the stretch starts lead into what is written there.
      if it.s <= a or it.s >= b then
        if it.s >= b then insert() end
        out[#out + 1] = it
      end
    elseif it.e <= a then
      out[#out + 1] = it
    elseif it.s >= b then
      insert()
      out[#out + 1] = it
    else
      if it.s < a then
        for _, p in ipairs(pieces(score, it, it.s, a, meter)) do
          -- What is cut short is no longer tied on.
          if p.e == a and p.ev.notes then
            for _, n in ipairs(p.ev.notes) do
              n.tie = nil
            end
          end
          out[#out + 1] = p
        end
      end
      insert()
      if it.e > b then
        for _, p in ipairs(pieces(score, it, b, it.e, meter, true)) do
          out[#out + 1] = p
        end
      end
    end
  end
  insert()
  local entry = M.voice(score.measures[mi], staff, v, true)
  entry.events = {}
  for _, it in ipairs(out) do
    entry.events[#entry.events + 1] = it.ev
  end
  M.normalize(score, mi, staff, v)
  M.touch(score, mi)
end

--- A run of rests (`{ s, e, ids }`, or nil) put in `out` as the metre
--- divides it, keeping their ids. Returns nil, the run done. Made once,
--- not in the loop that uses it: LuaJIT does not compile a loop that makes
--- a function.
local function rests_of(score, run, meter, out)
  if not run then return nil end
  for k, p in ipairs(M.values(run.s, run.e, meter, true)) do
    out[#out + 1] = { id = run.ids[k] or M.id(score, "e"), kind = "rest", dur = p.dur, dots = p.dots }
  end
  return nil
end

--- Merge a voice's rests as the metre divides the bar; a tuplet of rests
--- alone is a plain rest; a voice 1 of rests is empty, and any other voice
--- of rests is taken away.
function M.normalize(score, mi, staff, v)
  local m = score.measures[mi]
  local entry = M.voice(m, staff, v)
  if not entry then return end
  local f = M.frame(score)
  local items = M.line(score, mi, staff, v)
  -- Tuplets of nothing but rests.
  local silent = {}
  for id in pairs(tuplets_of(items)) do
    silent[id] = true
  end
  for _, it in ipairs(items) do
    if it.ev.tuplet and it.ev.kind ~= "rest" then silent[it.ev.tuplet.id] = nil end
  end
  local out, run = {}, nil
  local any = false
  for _, it in ipairs(items) do
    local ev = it.ev
    local plain_rest = ev.kind == "rest" and (not ev.tuplet or silent[ev.tuplet.id]) and not ev.grace
    if plain_rest then
      if run then
        run.e = it.e
      else
        run = { s = it.s, e = it.e, ids = {} }
      end
      run.ids[#run.ids + 1] = ev.id
    else
      run = rests_of(score, run, f.meters[mi], out)
      out[#out + 1] = ev
      any = true
    end
  end
  rests_of(score, run, f.meters[mi], out)
  if not any then
    if v == 1 then
      entry.events = {}
    else
      for i, e in ipairs(m.voices) do
        if e == entry then
          table.remove(m.voices, i)
          break
        end
      end
    end
  else
    entry.events = out
  end
end

-- Moving along a voice ----------------------------------------------------------------------------

--- Every event of a voice across the score in order, `{ ev, mi, s, e }`
--- with ticks from measure 1; graces have no length.
function M.sequence(score, staff, v, from, to)
  local f = M.frame(score)
  local out = {}
  for mi = from or 1, math.min(to or f.count, f.count) do
    local entry = M.voice(score.measures[mi], staff, v)
    local t = f.starts[mi]
    for _, ev in ipairs(entry and entry.events or {}) do
      local len = M.length(ev)
      out[#out + 1] = { ev = ev, mi = mi, s = t, e = t + len }
      t = t + len
    end
  end
  return out
end

--- Keep only ties that reach a note of the same pitch in the next chord of
--- the voice, measures `from` to `to` (and into the one after).
function M.fix_ties(score, staff, v, from, to)
  local seq = M.sequence(score, staff, v, math.max(1, from), to + 1)
  for i, it in ipairs(seq) do
    local ev = it.ev
    if ev.kind == "chord" and not ev.grace then
      local k = i + 1
      while seq[k] and seq[k].ev.grace do
        k = k + 1
      end
      local nxt = seq[k]
      local pitches = {}
      if nxt and nxt.ev.kind == "chord" and nxt.s == it.e then
        for _, n in ipairs(nxt.ev.notes) do
          pitches[M.pitch(n)] = true
        end
      end
      for _, n in ipairs(ev.notes) do
        if n.tie and not pitches[M.pitch(n)] and it.mi <= to then
          n.tie = nil
          M.touch(score, it.mi)
        end
      end
    end
  end
end

-- Writing notes ---------------------------------------------------------------------------------------

--- Put a chord of `notes` (spelled; the first written keeps their ids if
--- they have them) `len` ticks long at `at` ticks into measure `mi` of a
--- voice: tied over barlines and as the metre divides each bar. `extra`
--- is put on the first event (its `id`, `art`, `arpeggio`). Returns it.
function M.put_chord(score, mi, staff, v, at, len, notes, extra)
  local first
  local remaining = len
  while remaining > 0 do
    M.ensure(score, mi)
    local f = M.frame(score)
    local seg = math.min(remaining, f.lengths[mi] - at)
    local vals = M.values(at, at + seg, f.meters[mi], false)
    local evs = {}
    for k, p in ipairs(vals) do
      local last = remaining - seg <= 0 and k == #vals
      local ev = {
        id = M.id(score, "e"),
        kind = "chord",
        dur = p.dur,
        dots = p.dots,
        notes = copy_notes(score, notes, not last, not first),
      }
      if not first then
        first = ev
        for key, value in pairs(extra or {}) do
          ev[key] = value
        end
      end
      evs[#evs + 1] = ev
    end
    M.splice(score, mi, staff, v, at, at + seg, evs)
    remaining = remaining - seg
    mi, at = mi + 1, 0
  end
  return first
end

--- Find the tuplet of a voice around `at` (ticks into measure `mi`).
function M.tuplet_at(score, mi, staff, v, at)
  for id, span in pairs(tuplets_of(M.line(score, mi, staff, v))) do
    if at >= span.s and at < span.e then return span, id end
  end
end

--- A note of a tuplet: in the tuplet of that kind already there, or a new
--- one of `actual` rests in the time of `normal`, starting at `at`. `value`
--- is the written value in ticks. Returns the event, or nil and why not.
function M.put_tuplet_chord(score, mi, staff, v, at, value, actual, normal, notes)
  M.ensure(score, mi)
  local f = M.frame(score)
  local span = M.tuplet_at(score, mi, staff, v, at)
  local len = floor(value * normal / actual + 0.5)
  if not (span and span.tuplet.actual == actual and span.tuplet.normal == normal) then
    -- A new tuplet from here: the note, then rests to fill it.
    local width = value * normal
    if at + width > f.lengths[mi] then return nil, "no room for the tuplet before the barline" end
    local tp = { id = M.id(score, "t"), actual = actual, normal = normal }
    local ev = {
      id = M.id(score, "e"),
      kind = "chord",
      dur = M.ratio(value),
      dots = 0,
      tuplet = tp,
      notes = copy_notes(score, notes),
    }
    local evs = { ev }
    for k = 2, actual do
      evs[k] = { id = M.id(score, "e"), kind = "rest", dur = M.ratio(value), dots = 0, tuplet = tp }
    end
    M.splice(score, mi, staff, v, at, at + width, evs)
    return ev
  end
  local b = math.min(at + len, span.e)
  local ev = {
    id = M.id(score, "e"),
    kind = "chord",
    dur = M.ratio(value),
    dots = 0,
    tuplet = span.tuplet,
    notes = copy_notes(score, notes),
  }
  M.splice(score, mi, staff, v, at, b, { ev })
  return ev
end

--- Where an event is: its measure, voice entry, place in the events, and
--- the ticks into the measure it starts at.
function M.find(score, eid)
  for mi, m in ipairs(score.measures) do
    -- Looked for without copying (see `M.copy`), then in the measure itself.
    for _, entry in ipairs(M.peek(m, "voices")) do
      for _, ev in ipairs(entry.events) do
        if ev.id == eid then return M.find_in(score, mi, eid) end
      end
    end
  end
end

--- Where an event of measure `mi` is, as `M.find` says.
function M.find_in(score, mi, eid)
  for _, entry in ipairs(score.measures[mi].voices) do
    local t = 0
    for k, ev in ipairs(entry.events) do
      if ev.id == eid then return mi, entry, k, t, ev end
      t = t + M.length(ev)
    end
  end
end

--- The note with an id among a measure's voices: it, its event, voice
--- entry and place in the chord.
local function note_in(voices, nid)
  for _, entry in ipairs(voices) do
    for _, ev in ipairs(entry.events) do
      for k, n in ipairs(ev.notes or {}) do
        if n.id == nid then return n, ev, entry, k end
      end
    end
  end
end

--- The note of a chord with an id, and its event.
function M.find_note(score, nid)
  for mi, m in ipairs(score.measures) do
    -- Looked for without copying (see `M.copy`), then in the measure itself.
    if note_in(M.peek(m, "voices"), nid) then
      local n, ev, entry, k = note_in(score.measures[mi].voices, nid)
      return n, ev, mi, entry, k
    end
  end
end

--- The notes a tie joins to note `nid` along a voice's items (as
--- `M.sequence` gives them), and whether the ties go on past the last.
local function ties_along(seq, nid)
  local out = {}
  local current, pitch
  for i, it in ipairs(seq) do
    for _, n in ipairs(it.ev.notes or {}) do
      if n.id == nid then
        current, pitch = it, M.pitch(n)
      end
    end
    if current == it then
      local cur_note
      for _, n in ipairs(it.ev.notes) do
        if n.id == nid then cur_note = n end
      end
      local k = i
      while cur_note and cur_note.tie do
        local nxt = seq[k + 1]
        if not nxt then return out, true end
        if nxt.ev.kind ~= "chord" then break end
        local found
        for _, n in ipairs(nxt.ev.notes) do
          if M.pitch(n) == pitch then found = n end
        end
        if not found then break end
        out[#out + 1] = { note = found, item = nxt }
        cur_note, k = found, k + 1
      end
      return out, false
    end
  end
  return out, false
end

--- The notes a tie joins to `nid`, forwards: the ids of the tied-on ones.
function M.tied_on(score, staff, v, nid)
  local _, _, from = M.find_note(score, nid)
  if not from then return {} end
  -- From the note's measure on, as many measures as the ties reach.
  local count, to = M.frame(score).count, from
  while true do
    local out, open = ties_along(M.sequence(score, staff, v, from, to), nid)
    if not open or to >= count then return out end
    to = math.min(count, to + (to - from + 1))
  end
end

--- Take a note out of its chord; a chord left with none is a rest. The
--- note tied into it from before is tied no more.
function M.remove_note(score, nid)
  local n, ev, mi, entry, k = M.find_note(score, nid)
  if not n then return false end
  table.remove(ev.notes, k)
  if #ev.notes == 0 then
    ev.kind, ev.notes, ev.art, ev.arpeggio, ev.beam, ev.stem = "rest", nil, nil, nil, nil, nil
    ev.orn, ev.lyric, ev.lyrics = nil, nil, nil
    if ev.grace then
      for i, other in ipairs(entry.events) do
        if other == ev then
          table.remove(entry.events, i)
          break
        end
      end
    end
  end
  M.normalize(score, mi, entry.staff, entry.voice)
  M.fix_ties(score, entry.staff, entry.voice, math.max(1, mi - 1), mi)
  M.touch(score, mi)
  return true
end

--- Change a note's spelling (and so its pitch), with every note tied on from it.
function M.respell(score, nid, step, alter, octave)
  local n, _, mi, entry = M.find_note(score, nid)
  if not n then return false end
  local chain = M.tied_on(score, entry.staff, entry.voice, nid)
  n.step, n.alter, n.octave = step, alter, octave
  M.touch(score, mi)
  for _, c in ipairs(chain) do
    c.note.step, c.note.alter, c.note.octave = step, alter, octave
    M.touch(score, c.item.mi)
  end
  M.fix_ties(score, entry.staff, entry.voice, math.max(1, mi - 1), mi)
  return true
end

--- Every chord and rest event, with where it is: `{ ev, mi, staff, voice, s, e }`.
function M.each(score, fn)
  local f = M.frame(score)
  for mi, m in ipairs(score.measures) do
    for _, entry in ipairs(m.voices) do
      local t = f.starts[mi]
      for _, ev in ipairs(entry.events) do
        local len = M.length(ev)
        fn(ev, mi, entry.staff, entry.voice, t, t + len)
        t = t + len
      end
    end
  end
end

-- A score copied to be changed copies each of its measures when the
-- measure is first read: a measure not yet copied is an empty table that
-- stands for the one it was copied from (`lazy`), answering what is read
-- of it that is not a table from that one, and made a copy of it at the
-- first table read from it or anything written to it.
local lazy = setmetatable({}, { __mode = "k" })
local Lazy = {}
local copy

--- Make a measure that stands for another the copy of it.
local function materialize(m)
  local from = lazy[m]
  if not from then return m end
  lazy[m] = nil
  setmetatable(m, nil)
  for k, x in next, from do
    if type(x) == "table" then
      m[k] = copy(x)
    else
      m[k] = x
    end
  end
  return m
end

Lazy.__index = function(m, k)
  local x = lazy[m][k]
  if type(x) ~= "table" then return x end
  return materialize(m)[k]
end
Lazy.__newindex = function(m, k, v) rawset(materialize(m), k, v) end

copy = function(v)
  if lazy[v] then materialize(v) end
  local out = {}
  for k, x in next, v do
    if type(x) == "table" then
      out[k] = copy(x)
    else
      out[k] = x
    end
  end
  return out
end

--- What a measure has for `k`, without copying it if it stands for another
--- (see above): to read only.
function M.peek(m, k)
  local from = lazy[m]
  if from then return from[k] end
  return m[k]
end

--- A deep copy, without what is cached on the table. With `lazily`, of a
--- score that is not changed after (as a clip's score is not), its
--- measures are copied as they are read.
function M.copy(v, lazily)
  if type(v) ~= "table" then return v end
  if lazy[v] then materialize(v) end
  local out = {}
  for k, x in pairs(v) do
    if lazily and k == "measures" and type(x) == "table" then
      local list = {}
      for i, m in ipairs(x) do
        list[i] = setmetatable({}, Lazy)
        lazy[list[i]] = lazy[m] or m
      end
      out[k] = list
    elseif k ~= "_frame" and k ~= "_transcribed" then
      if type(x) == "table" then
        out[k] = copy(x)
      else
        out[k] = x
      end
    end
  end
  return out
end

-- Scores kept the old way -----------------------------------------------------------------------
--
-- A clip written in notation before notation was a view of MIDI kept its
-- score in `clip.meta.score`, each measure as JSON text. `notation.midi`
-- reads such a score to keep what it says as notation data.

--- A score in Lua tables from what a clip kept, or nil.
function M.decode(stored)
  if type(stored) ~= "table" or type(stored.measures) ~= "table" then return nil end
  local score = {}
  for k, v in pairs(stored) do
    if k ~= "measures" and k ~= "feel" then score[k] = M.copy(v) end
  end
  score.measures = {}
  for i, text in ipairs(stored.measures) do
    local m = type(text) == "string" and paw.api.json_decode(text) or M.copy(text)
    m.voices = m.voices or {}
    for _, entry in ipairs(m.voices) do
      entry.events = entry.events or {}
    end
    score.measures[i] = m
  end
  score.marks = score.marks or {}
  score.staves = score.staves or {}
  return score
end

return M
