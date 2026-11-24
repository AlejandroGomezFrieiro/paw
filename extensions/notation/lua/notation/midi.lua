-- Between a clip's MIDI and its score. The MIDI is the truth: its notes are
-- what plays and what every view edits, with this extension loaded or not.
-- The score is a view of them, as REAPER's notation is: transcribed
-- (`notation.score`) and written as a score document (`notation.doc`, by
-- `notation.layout`'s import) with what was decided in notation, which is
-- kept beside the MIDI as data the core carries and never reads:
--
--   on each note, `meta.notation`:
--     letter, alter, pitch   its spelling, while the note has that pitch
--     voice, staff           its voice (1 to 4), its staff of a grand staff
--     grace                  "acciaccatura" or "appoggiatura": a grace note
--     strum, chord, beam     an arpeggio sign, notes made one chord, a beam broken before it
--     art, orn, stem         its chord's articulations, ornament, stem
--     lyrics                 verses after the first (the first is `meta.lyric`)
--     len, sounding          written `len` beats long while it is `sounding` beats long
--     wrote                  what marks wrote: { velocity = { { v, from }, ... }, length = { v, from } },
--                            each velocity a mark wrote over the one before
--   on the clip, `meta.notation`, in beats from the clip's start:
--     version                the layout of all this, `M.VERSION`, for the
--                            clip and its notes; none is the layout before
--                            there was one (marks as `dyn`, `cresc`, `slurs`)
--     settings, tuplets      how it is transcribed; tuplets said (or `plain`)
--     staves                 the clefs notation wrote on, where the notes would choose others
--     marks                  { id, kind, at, to?, staff?, value, ... }: dynamics, hairpins,
--                            slurs, text, tempo marks, chord symbols, techniques
--     bars                   { at, barline?, repeat_start?, volta?, rehearsal?, key?, clef?, groups? }
--     layout                 { breaks = { { at, kind } }, per_system }
--
-- An edit in notation changes the score document `view:write` hands it,
-- and `M.sync` then writes what changed as ordinary MIDI edits, one undo
-- step: a note taken out or added; moved, lengthened or repitched by what
-- its written form moved; the decisions of the notes it changed; the
-- clip's marks. A note the edit did not change is not touched. Marks that
-- play write MIDI when they are written: a dynamic sets the velocities of
-- the notes it reaches, a hairpin ramps them, an accent or a marcato adds
-- to a note's, a staccato, staccatissimo or tenuto sets its length. That
-- is all: the MIDI is then free to change, and the mark stays a label.
-- Taking a mark away puts back what it wrote only where the note is still
-- as the mark left it.
local api = paw.api
local util = paw.util
local D = require("notation.doc")
local L = require("notation.layout")
local model = require("notation.model")

local M = {}
local Q = D.Q

-- The layout of what notation keeps (see above); written with every clip
-- it writes, read as the layout before it where a clip has none.
M.VERSION = 1
local EPS = 1e-6

M.DYNAMICS =
  { ppp = 25, pp = 38, p = 52, mp = 66, mf = 80, f = 96, ff = 112, fff = 124, pppp = 16, ffff = 127, niente = 8 }
-- Dynamics of one moment: louder by `add` over what holds, or at `level`,
-- for the notes that start there; `after` holds from just after it.
M.MOMENTS = {
  sf = { add = 24 },
  sfz = { add = 30 },
  sffz = { add = 36 },
  fz = { add = 24 },
  rfz = { add = 18 },
  fp = { level = 96, after = "p" },
  sfp = { add = 30, after = "p" },
}
M.ORDER = { "ppp", "pp", "p", "mp", "mf", "f", "ff", "fff" }
M.ARTICULATIONS = { staccato = true, staccatissimo = true, accent = true, tenuto = true, marcato = true }
-- How long a note marked so is played, of its written length.
M.GATE = { staccatissimo = 0.25, staccato = 0.5, tenuto = 1, fermata = 1, fermata_short = 1, fermata_long = 1 }
M.ACCENT = { accent = 20, marcato = 30 }
local GRACE = Q / 8 -- a grace note sounds a 32nd before its note

-- The keys of a note's `meta.notation` that the score decides.
local DECIDED =
  { "letter", "alter", "pitch", "voice", "staff", "grace", "strum", "chord", "beam", "art", "orn", "stem", "lyrics" }

local function clamp_vel(v) return math.max(1, math.min(127, math.floor(v + 0.5))) end

--- The MIDI note a written note is (its id), from the written note's id.
function M.midi_id(id) return tonumber(type(id) == "string" and id:match("^n(%d+)$") or nil) end

--- The data a value stands for, as text with its keys in order, to compare.
local function serial(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do
    out[#out + 1] = tostring(k) .. "=" .. serial(v[k])
  end
  return "{" .. table.concat(out, ",") .. "}"
end
M.serial = serial

local function own_of(n)
  local own = n and type(n.meta) == "table" and n.meta.notation
  return type(own) == "table" and own or {}
end

-- Places -------------------------------------------------------------------------------------------

--- Where a mark's place is, in ticks from measure 1, or nil.
function M.at_of(score, f, ref)
  if not ref then return nil end
  local mi = f.index[ref.measure]
  if not mi then return nil end
  if ref.event then
    local t = f.starts[mi]
    for _, entry in ipairs(score.measures[mi].voices) do
      local x = t
      for _, ev in ipairs(entry.events) do
        if ev.id == ref.event then return x end
        x = x + D.length(ev)
      end
    end
    return nil
  end
  return f.starts[mi] + D.ticks(ref.at or { 0, 1 })
end

--- A beat of the clip as a place in the score: `{ measure, at }`, the
--- measure made if need be.
function M.ref(sc, beat)
  local mi, at = D.locate(sc, D.from_beats(beat) - D.origin(sc))
  D.ensure(sc, mi)
  return { measure = sc.measures[mi].id, at = D.ratio(at) }, mi
end

--- The beat of the clip a place in the score is at, or nil.
function M.beat_of(sc, ref)
  local t = M.at_of(sc, D.frame(sc), ref)
  return t and (D.origin(sc) + t) / Q
end

-- What is written ----------------------------------------------------------------------------------

--- Whether the chord before item `k` of a voice ties a note of `pitch` into it.
local function tied_into(seq, k, pitch)
  local j = k - 1
  while seq[j] and seq[j].ev.grace do
    j = j - 1
  end
  local prev = seq[j]
  if not (prev and prev.ev.kind == "chord" and prev.e == seq[k].s) then return false end
  for _, n in ipairs(prev.ev.notes) do
    if n.tie and D.pitch(n) == pitch then return true end
  end
  return false
end

--- The notes a score writes, by id: `{ pitch, s, len, staff, voice, ev,
--- grace, mi, note }` with `s` in ticks from measure 1 and tied notes one note.
--- Grace notes are placed before their note, a 32nd each. With `from` and
--- `to`, those of measures `from` to `to` only (a tie is followed no further).
function M.written(sc, from, to)
  local out = {}
  for _, st in ipairs(sc.staves) do
    for v = 1, 4 do
      local seq = D.sequence(sc, st.id, v, from, to)
      local graces = {}
      for k, it in ipairs(seq) do
        local ev = it.ev
        if ev.grace and ev.kind == "chord" then
          graces[#graces + 1] = it
        elseif ev.kind == "chord" then
          for j, g in ipairs(graces) do
            for _, n in ipairs(g.ev.notes) do
              out[n.id] = {
                pitch = D.pitch(n),
                s = it.s - (#graces - j + 1) * GRACE,
                len = GRACE,
                staff = st.id,
                voice = v,
                ev = g.ev,
                grace = g.ev.grace,
                mi = g.mi,
                note = n,
              }
            end
          end
          graces = {}
          for _, n in ipairs(ev.notes) do
            local pitch = D.pitch(n)
            if not tied_into(seq, k, pitch) then
              local e, cur, at = it.e, n, k
              while cur.tie do
                local nxt = seq[at + 1]
                if not (nxt and nxt.ev.kind == "chord" and not nxt.ev.grace and nxt.s == e) then break end
                local found
                for _, o in ipairs(nxt.ev.notes) do
                  if D.pitch(o) == pitch then found = o end
                end
                if not found then break end
                e, cur, at = nxt.e, found, at + 1
              end
              out[n.id] =
                { pitch = pitch, s = it.s, len = e - it.s, staff = st.id, voice = v, ev = ev, mi = it.mi, note = n }
            end
          end
        else
          graces = {}
        end
      end
    end
  end
  return out
end

--- What notation decided about each written note: `{ [id] = meta.notation's
--- decided keys }`, and verse 1 of its lyric; each made when it is asked for.
function M.decisions(sc, written)
  local two = #sc.staves == 2
  return setmetatable({}, {
    __index = function(out, id)
      local w = written[id]
      if not w then return nil end
      local ev, note = w.ev, w.note
      local d = { voice = w.voice, letter = note.step, alter = note.alter, pitch = w.pitch }
      if two then d.staff = D.staff_index(sc, w.staff) end
      if ev.grace then d.grace = ev.grace end
      d.strum = ev.arpeggio
      d.art = ev.art and next(ev.art) and util.merge(ev.art, {}) or nil
      d.orn, d.stem = ev.orn, ev.stem
      -- The first note written of a chord carries what is the chord's.
      local first
      for _, n in ipairs(ev.notes) do
        if written[n.id] and (not first or tostring(n.id) < tostring(first)) then first = n.id end
      end
      if first == id then
        d.beam = ev.beam
        d.lyric, d.lyrics = ev.lyric, ev.lyrics
      end
      out[id] = d
      return d
    end,
  })
end

--- Whether what notation decided about a written note is the same in two
--- scores (`a` and `b`, from `M.written`), without making the decisions.
local function decided_alike(a, b)
  local ea, eb = a.ev, b.ev
  return a.voice == b.voice
    and a.staff == b.staff
    and a.pitch == b.pitch
    and a.note.step == b.note.step
    and a.note.alter == b.note.alter
    and ea.grace == eb.grace
    and ea.arpeggio == eb.arpeggio
    and ea.orn == eb.orn
    and ea.stem == eb.stem
    and ea.beam == eb.beam
    and ea.lyric == eb.lyric
    and #ea.notes == #eb.notes
    and M.same(ea.art, eb.art)
    and M.same(ea.lyrics, eb.lyrics)
end

-- Loudness -------------------------------------------------------------------------------------

--- The marks of a score that play, in ticks: dynamics, hairpins, moments.
function M.resolve(sc)
  local f = D.frame(sc)
  local out = { dyns = {}, pins = {}, moments = {} }
  for _, mk in ipairs(sc.marks or {}) do
    local s = M.at_of(sc, f, mk.from)
    if s then
      if mk.kind == "dynamic" and M.DYNAMICS[mk.value] then
        out.dyns[#out.dyns + 1] = { t = s, level = M.DYNAMICS[mk.value] }
      elseif mk.kind == "dynamic" and M.MOMENTS[mk.value] then
        local mo = M.MOMENTS[mk.value]
        out.moments[#out.moments + 1] = { t = s, add = mo.add, level = mo.level }
        if mo.after then out.dyns[#out.dyns + 1] = { t = s + 1, level = M.DYNAMICS[mo.after] } end
      elseif mk.kind == "hairpin" then
        local e = M.at_of(sc, f, mk.to)
        if e and e > s then
          out.pins[#out.pins + 1] = { s = s, e = e, kind = mk.value == "dim" and "dim" or "cresc" }
        end
      end
    end
  end
  table.sort(out.dyns, function(a, b) return a.t < b.t end)
  return out
end

--- The velocity the marks ask of a note starting at `t` with articulations
--- `art`, or nil when no mark says how loud. `have` is the note's own, which
--- an accent adds to when nothing else is said. The second value names the
--- marks along the score that decide it, `|` between them.
function M.velocity(res, t, art, have)
  local why = {}
  local function at(x)
    local v, key
    for _, d in ipairs(res.dyns) do
      if d.t <= x then
        v, key = d.level, "d" .. d.t .. ":" .. d.level
      end
    end
    return v, key
  end
  local v
  for _, h in ipairs(res.pins) do
    -- A dynamic inside a hairpin ends it there, as it is drawn (the
    -- soft half of an `fp` at its start, a tick after it, starts it).
    local e = h.e
    for _, d in ipairs(res.dyns) do
      if d.t > h.s + 1 and d.t < e then e = d.t end
    end
    if t >= h.s and t < e then
      local from, key = at(h.s)
      from = from or M.DYNAMICS.mf
      local to, to_key
      for _, d in ipairs(res.dyns) do
        if not to and d.t >= e then
          to, to_key = d.level, "d" .. d.t .. ":" .. d.level
        end
      end
      to = to or (from + (h.kind == "cresc" and 24 or -24))
      v = from + (to - from) * (t - h.s) / math.max(1, e - h.s)
      why = { "h" .. h.s .. ":" .. e .. ":" .. h.kind }
      why[#why + 1] = key
      why[#why + 1] = to_key
    end
  end
  if not v then
    local key
    v, key = at(t)
    why = { key }
  end
  for _, mo in ipairs(res.moments) do
    if mo.t == t then
      v = mo.level or ((v or have) + mo.add)
      why[#why + 1] = "m" .. mo.t .. ":" .. tostring(mo.level or mo.add)
    end
  end
  for kind, add in pairs(M.ACCENT) do
    if art and art[kind] then v = (v or have) + add end
  end
  return v and clamp_vel(v) or nil, table.concat(why, "|")
end

--- The names of every mark along a score that plays (as `M.velocity` gives
--- them), as a set.
local function sources(res)
  local out = {}
  for _, d in ipairs(res.dyns) do
    out["d" .. d.t .. ":" .. d.level] = true
  end
  for _, h in ipairs(res.pins) do
    out["h" .. h.s .. ":" .. h.e .. ":" .. h.kind] = true
  end
  for _, mo in ipairs(res.moments) do
    out["m" .. mo.t .. ":" .. tostring(mo.level or mo.add)] = true
  end
  return out
end

--- Whether `why` names a mark that `known` does not have: a mark this edit wrote.
local function written_now(why, known)
  for key in why:gmatch("[^|]+") do
    if not known[key] then return true end
  end
  return false
end

--- Whether a set of articulations has an accent or a marcato.
local function accented(art) return art ~= nil and (art.accent or art.marcato) and true or false end

--- How much of its written length a note with articulations `art` plays,
--- or nil when they do not say.
function M.gate(art)
  if not art then return nil end
  for _, kind in ipairs({ "staccatissimo", "staccato", "tenuto", "fermata", "fermata_short", "fermata_long" }) do
    if art[kind] then return M.GATE[kind] end
  end
end

--- What the marks of a score ask of a note `n` that is written as `w`
--- (`M.written`), as a change `{ velocity, length, meta }` to write, or nil
--- when it plays as they say. `res` is `M.resolve` of the score. What is
--- written is noted on the note, so that taking a mark away puts back only
--- what is still as the mark left it.
function M.marked(res, w, n)
  local own = own_of(n)
  local meta = util.merge(own, {})
  local wrote = type(meta.wrote) == "table" and util.merge(meta.wrote, {}) or {}
  local change, any = {}, false
  local stack = type(wrote.velocity) == "table" and util.merge(wrote.velocity, {}) or {}
  local top = stack[#stack]
  -- A note still as a mark left it is asked again from what it was before,
  -- so that an accent is not added twice.
  local untouched = top and top.v == n.velocity
  local va = M.velocity(res, w.s, w.ev.art, untouched and top.from or n.velocity)
  if va and va ~= n.velocity then
    if not untouched then stack = {} end
    stack[#stack + 1] = { v = va, from = n.velocity }
    wrote.velocity, change.velocity, any = stack, va, true
  end
  local gate = M.gate(w.ev.art)
  if gate and not w.grace then
    local length = math.max(1 / 64, w.len / Q * gate)
    if math.abs(length - n.length) > EPS then
      local was = wrote.length
      local from = (was and math.abs(was.v - n.length) < EPS) and was.from or n.length
      wrote.length, change.length, any = { v = length, from = from }, length, true
      meta.len, meta.sounding = w.len / Q, length
    end
  end
  if not any then return nil end
  meta.wrote = next(wrote) and wrote or nil
  local all = util.merge(n.meta or {}, {})
  all.notation = next(meta) and meta or nil
  change.meta = all
  return change
end

-- What the clip keeps ---------------------------------------------------------------------------

local BAR_KEYS = { "barline", "repeat_start", "volta", "rehearsal", "key", "groups", "meter_symbol" }

--- What a score says that the clip keeps (`meta.notation`'s marks, bars
--- and layout), in beats of the clip.
function M.clip_part(sc)
  local f = D.frame(sc)
  local origin = D.origin(sc)
  local function beat(ref)
    local t = M.at_of(sc, f, ref)
    return t and (origin + t) / Q
  end
  local marks = {}
  for _, mk in ipairs(sc.marks or {}) do
    local at = beat(mk.from)
    if at then
      local out = { at = at }
      for k, v in pairs(mk) do
        if k ~= "from" and k ~= "to" and k ~= "staff" then out[k] = v end
      end
      if mk.to then out.to = beat(mk.to) or at end
      if mk.staff then out.staff = D.staff_index(sc, mk.staff) end
      marks[#marks + 1] = out
    end
  end
  table.sort(marks, function(a, b)
    if a.at ~= b.at then return a.at < b.at end
    return tostring(a.id) < tostring(b.id)
  end)
  local bars = {}
  for i, m in ipairs(sc.measures) do
    local b
    for _, k in ipairs(BAR_KEYS) do
      if m[k] ~= nil then
        b = b or {}
        b[k] = m[k]
      end
    end
    if m.clef then
      b = b or {}
      b.clef = {}
      for sid, clef in pairs(m.clef) do
        b.clef[D.staff_index(sc, sid) or 1] = clef
      end
    end
    if b then
      b.at = (origin + f.starts[i]) / Q
      bars[#bars + 1] = b
    end
  end
  local layout
  if sc.layout and ((sc.layout.breaks and #sc.layout.breaks > 0) or sc.layout.per_system) then
    layout = { breaks = {}, per_system = sc.layout.per_system }
    for _, br in ipairs(sc.layout.breaks or {}) do
      local mi = f.index[br.measure]
      if mi then layout.breaks[#layout.breaks + 1] = { at = (origin + f.starts[mi]) / Q, kind = br.kind } end
    end
    table.sort(layout.breaks, function(a, b) return a.at < b.at end)
  end
  return { marks = #marks > 0 and marks or nil, bars = #bars > 0 and bars or nil, layout = layout }
end

--- The tuplets of a score, in beats of the clip: `{ [key] = { start,
--- length, n, normal, staff, voice } }`, `staff` by its index; with `from`
--- and `to`, those of measures `from` to `to` only.
local function tuplets_of(sc, from, to)
  local out = {}
  local origin = D.origin(sc)
  local f = D.frame(sc)
  for mi = from or 1, math.min(to or f.count, f.count) do
    for _, entry in ipairs(sc.measures[mi].voices) do
      local s = f.starts[mi]
      for _, ev in ipairs(entry.events) do
        local e = s + D.length(ev)
        local tp = ev.tuplet
        if tp and not ev.grace then
          local key = entry.staff .. ":" .. entry.voice .. ":" .. tp.id
          local span = out[key]
          if span then
            span.e = math.max(span.e, e)
          else
            out[key] = {
              s = s,
              e = e,
              n = tp.actual,
              normal = tp.normal,
              staff = D.staff_index(sc, entry.staff) or 1,
              voice = entry.voice,
            }
          end
        end
        s = e
      end
    end
  end
  local list = {}
  for _, span in pairs(out) do
    local tp = {
      start = (origin + span.s) / Q,
      length = (span.e - span.s) / Q,
      n = span.n,
      normal = span.normal,
      staff = span.staff,
      voice = span.voice,
    }
    list[string.format("%.6f:%.6f:%d:%d:%d:%d", tp.start, tp.length, tp.n, tp.normal, tp.staff, tp.voice)] = tp
  end
  return list
end

-- The score of a clip --------------------------------------------------------------------------------

--- The marks a clip kept before scores were kept this way (`kind` "dyn",
--- "cresc", "dim", "text", "repeat", and `slurs`) as marks and bars now.
local function legacy(own)
  local marks, bars = {}, {}
  local old = own.version == nil
  for _, mk in ipairs(own.marks or {}) do
    if not old then
      marks[#marks + 1] = mk
    elseif mk.kind == "dyn" then
      marks[#marks + 1] = { kind = "dynamic", at = mk.at, value = mk.value }
    elseif mk.kind == "cresc" or mk.kind == "dim" then
      marks[#marks + 1] = { kind = "hairpin", at = mk.at, to = mk.to or mk.at, value = mk.kind }
    elseif mk.kind == "repeat" then
      bars[#bars + 1] = mk.value == "start" and { at = mk.at, repeat_start = true } or { at = mk.at, close = true }
    else
      marks[#marks + 1] = mk
    end
  end
  for _, sl in ipairs(own.slurs or {}) do
    marks[#marks + 1] = { kind = "slur", at = sl.from, to = sl.to, staff = sl.staff }
  end
  for _, b in ipairs(own.bars or {}) do
    bars[#bars + 1] = b
  end
  return marks, bars
end

--- Put what a clip keeps (`own`, its `meta.notation`) on a score just
--- transcribed: marks at their places, the bars' signs, the page's breaks.
local function put_clip_part(sc, own)
  local marks, bars = legacy(own)
  for _, mk in ipairs(marks) do
    local out = { id = mk.id or D.id(sc, "k") }
    for k, v in pairs(mk) do
      if k ~= "at" and k ~= "to" and k ~= "staff" and k ~= "id" then out[k] = v end
    end
    out.from = M.ref(sc, mk.at)
    if mk.to then out.to = M.ref(sc, mk.to) end
    if mk.staff or out.kind == "slur" then out.staff = (sc.staves[mk.staff or 1] or sc.staves[1]).id end
    sc.marks[#sc.marks + 1] = out
  end
  local f = D.frame(sc)
  for _, b in ipairs(bars) do
    local mi, at = D.locate(sc, D.from_beats(b.at) - D.origin(sc))
    if b.close then
      -- A repeat closing where a bar starts: the barline before it.
      if at == 0 and sc.measures[mi - 1] then sc.measures[mi - 1].barline = ":|" end
    elseif sc.measures[mi] then
      local m = sc.measures[mi]
      for _, k in ipairs(BAR_KEYS) do
        if b[k] ~= nil then m[k] = b[k] end
      end
      if m.groups and not m.meter then m.meter = { f.meters[mi][1], f.meters[mi][2] } end
      if type(b.clef) == "table" then
        m.clef = {}
        for k, clef in pairs(b.clef) do
          local st = sc.staves[tonumber(k) or 1]
          if st then m.clef[st.id] = clef end
        end
      end
    end
  end
  sc._frame = nil
  if type(own.layout) == "table" then
    sc.layout = { breaks = {}, per_system = own.layout.per_system }
    for _, br in ipairs(own.layout.breaks or {}) do
      local mi = D.locate(sc, D.from_beats(br.at) - D.origin(sc))
      if sc.measures[mi] then
        sc.layout.breaks[#sc.layout.breaks + 1] = { id = D.id(sc, "l"), measure = sc.measures[mi].id, kind = br.kind }
      end
    end
  end
end

--- Put what each note says (its chord's marks, ornament, stem, lyrics, a
--- grace note's kind) on a chord of a score just transcribed.
local function put_note_part(ev, by_id)
  if ev.kind ~= "chord" then return end
  local art = ev.art and util.merge(ev.art, {}) or {}
  for _, n in ipairs(ev.notes) do
    local note = by_id[n.id]
    if note then
      local own = own_of(note)
      if type(own.art) == "table" then
        for k, v in pairs(own.art) do
          art[k] = v
        end
      end
      ev.orn = ev.orn or own.orn
      ev.stem = ev.stem or own.stem
      if own.grace == "appoggiatura" and ev.grace then ev.grace = "appoggiatura" end
      local lyric = note.meta and note.meta.lyric
      if not ev.lyric and type(lyric) == "string" and lyric ~= "" then ev.lyric = lyric end
      if not ev.lyrics and type(own.lyrics) == "table" then ev.lyrics = own.lyrics end
    end
  end
  ev.art = next(art) and art or nil
end

--- A measure's voices as text, which changes when they do. Its pieces are
--- joined with `..` rather than gathered in a table to concatenate: it is
--- made for every measure of a score, and that is quicker.
local function voices_token(m)
  local out = {}
  for _, entry in ipairs(m.voices) do
    out[#out + 1] = "|" .. entry.staff .. ":" .. entry.voice
    for _, ev in ipairs(entry.events) do
      local tp = ev.tuplet
      out[#out + 1] = ev.id
        .. ","
        .. ev.kind
        .. ","
        .. ev.dur[1]
        .. ","
        .. ev.dur[2]
        .. ","
        .. (ev.dots or 0)
        .. ","
        .. (tp and (tp.id .. "/" .. tp.actual .. "/" .. tp.normal) or "")
        .. ","
        .. (ev.grace or "")
        .. ","
        .. (ev.arpeggio or "")
        .. ","
        .. (ev.beam or "")
        .. ","
        .. (ev.stem or "")
        .. ","
        .. (ev.orn or "")
        .. ","
        .. (ev.lyric or "")
        .. ","
        .. (ev.art and serial(ev.art) or "")
        .. ","
        .. (ev.lyrics and serial(ev.lyrics) or "")
      for _, n in ipairs(ev.notes or {}) do
        out[#out + 1] = n.id .. "," .. n.step .. "," .. n.alter .. "," .. n.octave .. (n.tie and "~" or "")
      end
    end
  end
  return table.concat(out, ";")
end

--- A measure's music as text, which changes when it does: what the caches
--- by measure go by. `voices` is its voices' (`voices_token`), if known.
local function token_of(m, voices)
  local out = { m.id }
  for _, k in ipairs(BAR_KEYS) do
    if m[k] ~= nil then out[#out + 1] = k .. "=" .. serial(m[k]) end
  end
  if m.meter then out[#out + 1] = "meter=" .. m.meter[1] .. "/" .. m.meter[2] end
  if m.clef then out[#out + 1] = "clef=" .. serial(m.clef) end
  out[#out + 1] = voices or voices_token(m)
  return table.concat(out, ";")
end

-- Written measures --------------------------------------------------------------------------------
--
-- A clip's score is written measure by measure from its transcription
-- (`notation.model`'s lines of sound and silence, values, ties, tuplets,
-- spelling, then the score's events and what the notes say of them), and
-- what each measure is written as is kept by everything it is written from:
-- its bar, the staves and key, the transcribed chords and silences in it
-- with their notes and what notation keeps on them, the tuplets said in it,
-- and what comes in from the measures before (the accidentals the bar
-- before left, how many written notes a held chord has had). An edit
-- writes again only the measures whose key changed; the rest are as they
-- were, and the score is the same as one written whole (`M.memo = false`
-- writes every measure, for the tests to compare).

M.memo = true
local written_memo, written_count = {}, 0
M.stats = { measures = 0 } -- measures written, not found in the memo

local function num(x) return string.format("%.17g", x) end

--- What the written measures read of a played note (a transcription's):
--- its id, pitch, spelling, beam, articulations, ornament, stem, grace
--- kind and lyrics.
local function note_key(n, keep)
  local meta = n.meta
  local own = type(meta) == "table" and type(meta.notation) == "table" and meta.notation or nil
  local lyric = type(meta) == "table" and meta.lyric or nil
  if not own then return (keep[n.index] or "?") .. "," .. n.pitch .. "," .. (lyric and serial(lyric) or "") end
  return table.concat({
    keep[n.index] or "?",
    n.pitch,
    lyric and serial(lyric) or "",
    tostring(own.letter),
    tostring(own.alter),
    tostring(own.pitch),
    tostring(own.beam),
    tostring(own.orn),
    tostring(own.stem),
    tostring(own.grace),
    own.art ~= nil and serial(own.art) or "",
    own.lyrics ~= nil and serial(own.lyrics) or "",
  }, ",")
end

--- A transcribed chord as text, for the keys of the measures it is in;
--- each made once, in `known`.
local function chord_key(c, keep, known)
  local hit = known[c]
  if hit then return hit end
  local out = { tostring(c.arpeggio), tostring(c.staccato) }
  for _, n in ipairs(c.notes) do
    out[#out + 1] = note_key(n, keep)
  end
  out[#out + 1] = "/"
  for _, n in ipairs(c.grace or {}) do
    out[#out + 1] = note_key(n, keep)
  end
  hit = table.concat(out, ";")
  known[c] = hit
  return hit
end

-- Functions are made once, outside the loops that use them: LuaJIT does
-- not compile a loop that makes one.
local function by_start(a, b) return a.start < b.start end

local function sorted_keys(t)
  local out = {}
  for k in pairs(t) do
    out[#out + 1] = k
  end
  table.sort(out)
  return out
end

--- Write a transcription (`tr`, with `o` as `notation.model.transcription`
--- gives them) as a score, measure by measure, each from the memo where
--- what it is written from has not changed. `keep` names the played notes
--- (see `notation.layout`'s import), `next` is where counted ids start.
--- Returns nil where only writing the whole score at once can give the
--- same ids (a note without an id, an id counted).
local function write_measures(tr, o, keep, next_id, by_id)
  local measures = model.measures_of(o.bars, #o.staves)
  local lines = model.lines(tr, measures, #o.staves)
  local bars = {}
  for i, m in ipairs(measures) do
    bars[i] = { start = m.start, num = m.meter.num, den = m.meter.den }
  end
  local score = D.new(bars, o.staves)
  score.next = math.max(score.next, next_id)
  local voices_of = {}
  for s, voices in ipairs(lines) do
    voices_of[s] = sorted_keys(voices)
  end
  local head = table.concat(o.staves, ",") .. "|" .. tostring(o.fifths)
  local before = {} -- by staff: the steps the bar before left altered
  for s = 1, #o.staves do
    before[s] = {}
  end
  local count = {} -- by segment: the written pieces it has had
  local tokens, known = {}, {}
  for i, m in ipairs(measures) do
    local stop = m.start + m.length
    -- The key: everything measure `i` is written from.
    local key = { i, num(m.start), m.meter.num, m.meter.den, head }
    for _, tp in ipairs(o.tuplets or {}) do
      if tp.start < stop + 1e-3 and tp.start + tp.length > m.start - 1e-3 then
        key[#key + 1] = table.concat({
          "t",
          num(tp.start),
          num(tp.length),
          tostring(tp.n),
          tostring(tp.normal),
          tostring(tp.staff),
          tostring(tp.voice),
          tostring(tp.plain),
        }, ",")
      end
    end
    for s = 1, #o.staves do
      key[#key + 1] = "a" .. table.concat(sorted_keys(before[s]), ",")
      for _, v in ipairs(voices_of[s]) do
        local pieces = lines[s][v].pieces[i]
        if pieces then
          key[#key + 1] = "v" .. s .. ":" .. v
          for _, p in ipairs(pieces) do
            local c = p.seg.chord
            key[#key + 1] = num(p.a)
              .. ","
              .. num(p.b)
              .. ","
              .. (count[p.seg] or 0)
              .. ","
              .. (p.seg.e > stop + 1e-6 and "~" or "")
              .. ","
              .. (c and chord_key(c, keep, known) or "r")
          end
        end
      end
    end
    key = table.concat(key, "|")
    local hit = written_memo[key]
    if not hit then
      local mark = score.next
      for s = 1, #o.staves do
        for _, v in ipairs(voices_of[s]) do
          local pieces = lines[s][v].pieces[i]
          if pieces then
            for _, p in ipairs(pieces) do
              p.evs = {}
            end
            model.write_pieces(m, s, v, pieces, o.tuplets)
          end
        end
      end
      -- Ties within the measure, and to the measures either side.
      local st = { keep = keep, stable = true, used = {}, pieces = {}, written = {} }
      local made = {}
      for s = 1, #o.staves do
        for _, v in ipairs(voices_of[s]) do
          for _, p in ipairs(lines[s][v].pieces[i] or {}) do
            local c, had = p.seg.chord, count[p.seg] or 0
            table.sort(p.evs, by_start)
            local total = had + #p.evs + (p.seg.e > stop + 1e-6 and 1 or 0)
            for k, ev in ipairs(p.evs) do
              model.tie_piece(ev, c, had + k, total)
            end
            if c and had > 0 then
              for _, n in ipairs(c.notes) do
                st.pieces[n.index] = had
              end
            end
            made[#made + 1] = #p.evs
          end
        end
      end
      model.order(m)
      local spelled = {}
      for s, clef in ipairs(o.staves) do
        spelled[s] = model.spell_measure(m, s, clef, o.fifths or 0, before[s])
      end
      L.import_measure(score, i, m, st)
      L.normalize_measure(score, i)
      if score.next ~= mark then return nil end
      local sm = score.measures[i]
      for _, entry in ipairs(sm.voices) do
        for _, ev in ipairs(entry.events) do
          put_note_part(ev, by_id)
        end
      end
      hit = { voices = sm.voices, token = voices_token(sm), before = spelled, made = made }
      M.stats.measures = M.stats.measures + 1
      if written_count > 4000 then
        written_memo, written_count = {}, 0
      end
      written_memo[key], written_count = hit, written_count + 1
    end
    local sm = score.measures[i]
    sm.id, sm.voices = "m" .. i, hit.voices
    tokens[i] = hit.token
    before = hit.before
    local k = 0
    for s = 1, #o.staves do
      for _, v in ipairs(voices_of[s]) do
        for _, p in ipairs(lines[s][v].pieces[i] or {}) do
          k = k + 1
          count[p.seg] = (count[p.seg] or 0) + hit.made[k]
        end
      end
    end
  end
  return score, tokens
end

--- The score of a clip: transcribed from its notes (`notes`, as the clip
--- gives them), with what notation decided, kept on the notes and with the
--- clip (`own`). `opts` are the layout's (`view.layout_opts`). Every
--- written note's id is its MIDI note's (`n41` writes note 41), every
--- chord's its first note's, so the same notes give the same score.
function M.derive(notes, own, opts)
  local tr, o = model.transcription(notes, util.merge(opts, { stems = false }))
  local keep, top = {}, 0
  local by_id = {}
  local named = true
  for i, n in ipairs(notes) do
    if n.id then
      keep[i] = "n" .. n.id
      by_id[keep[i]] = n
      top = math.max(top, n.id)
    else
      named = false
    end
  end
  for _, mk in ipairs(own.marks or {}) do
    local k = tonumber(tostring(mk.id or ""):match("(%d+)$"))
    if k then top = math.max(top, k) end
  end
  local sc, tokens
  if M.memo and named then
    sc, tokens = write_measures(tr, o, keep, top + 1, by_id)
  end
  if not sc then
    sc = L.import(model.engrave_score(tr, o), { keep = keep, next = top + 1 })
    D.each(sc, function(ev) put_note_part(ev, by_id) end)
    tokens = {}
  end
  -- The transcription itself, for what reads it from the layout (`layout.score`).
  sc._transcribed = tr
  sc.layout = { breaks = {} }
  put_clip_part(sc, own)
  for i, m in ipairs(sc.measures) do
    m.v = token_of(m, tokens[i])
  end
  sc.rev = D.token()
  sc._frame = nil
  return sc, by_id
end

--- Mark a derived score's measures by their content again, after a change.
function M.retoken(sc)
  for _, m in ipairs(sc.measures) do
    m.v = token_of(m)
  end
  sc._frame = nil
end

-- Writing a change ---------------------------------------------------------------------------------

--- Whether two values hold the same data.
local function same(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not same(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end
M.same = same

--- A note's `meta.notation` with the decided keys of `d` in place of its own.
local function with_decisions(own, d)
  local out = {}
  for k, v in pairs(own) do
    out[k] = v
  end
  for _, k in ipairs(DECIDED) do
    out[k] = d[k]
  end
  return out
end

--- Write a score's change as MIDI: the score was `before` (derived from the
--- clip) and an edit made it `after`. Only notes whose written form or
--- decisions changed are touched. `own` is what the clip keeps for notation,
--- `fixed` the clef the part fixes, if any. Returns the MIDI ids the
--- score's new notes were given, by their written ids.
function M.sync(clip_id, before, after, own, fixed)
  local notes = api.clip_notes(clip_id)
  local place, top = {}, 0
  for i, n in ipairs(notes) do
    if n.id then
      place[n.id] = i
      top = math.max(top, n.id)
    end
  end
  local rb, ra = M.resolve(before), M.resolve(after)
  local known = sources(rb)
  local marks_changed = not same(known, sources(ra))
  -- The measures the edit touched, and those either side, and back over
  -- what is tied into them: the notes anywhere else are as they were
  -- (unless a mark that plays changed, which reaches any of them).
  local from, to
  if not marks_changed and #before.measures == #after.measures and D.origin(before) == D.origin(after) then
    for i, m in ipairs(after.measures) do
      if m.v ~= before.measures[i].v then
        from, to = from or i, i
      end
    end
    if from then
      from, to = math.max(1, from - 1), math.min(#after.measures, to + 1)
      local function tied_out(sc, mi)
        for _, entry in ipairs(sc.measures[mi].voices) do
          local last = entry.events[#entry.events]
          for _, n in ipairs(last and last.notes or {}) do
            if n.tie then return true end
          end
        end
        return false
      end
      while from > 1 and (tied_out(before, from - 1) or tied_out(after, from - 1)) do
        from = from - 1
      end
    else
      from, to = 1, 0
    end
  end
  local wb, wa = M.written(before, from, to), M.written(after, from, to)
  local db, da = M.decisions(before, wb), M.decisions(after, wa)
  local ob, oa = D.origin(before), D.origin(after)
  local default = paw.opt.velocity or 100
  local set, remove, add, named = {}, {}, {}, {}
  for id in pairs(wb) do
    local i = place[M.midi_id(id) or -1]
    if i and not wa[id] then remove[#remove + 1] = i end
  end
  -- New notes keep the number they were written with when it is free.
  local taken = {}
  local function new_id(id)
    local k = M.midi_id(id)
    if not k or place[k] or taken[k] or k <= top then
      top = math.max(top, k or 0) + 1
      while place[top] or taken[top] do
        top = top + 1
      end
      k = top
    end
    taken[k] = true
    return k
  end
  local adding = {}
  for id, w in pairs(wa) do
    local b = wb[id]
    local i = b and place[M.midi_id(id) or -1]
    local art = w.ev.art
    local decided = b and not decided_alike(b, w) and not same(db[id], da[id])
    -- A note the edit did not change, nor any mark that plays: not touched.
    local alike = b
      and w.pitch == b.pitch
      and w.s == b.s
      and w.len == b.len
      and ob == oa
      and not decided
      and not marks_changed
    local d = (not alike or not i) and da[id]
    if i and not alike then
      local n = notes[i]
      local own_n = own_of(n)
      local meta_now = util.merge(own_n, {})
      local change, any = { index = i }, false
      if w.pitch ~= b.pitch then
        change.pitch, any = w.pitch, true
      end
      local ds = (oa + w.s) - (ob + b.s)
      if ds ~= 0 then
        change.start, any = math.max(0, n.start + ds / Q), true
      end
      local length = n.length
      if w.len ~= b.len then
        length = math.max(1 / 64, n.length + (w.len - b.len) / Q)
        change.length, any = length, true
      end
      local wrote = type(meta_now.wrote) == "table" and util.merge(meta_now.wrote, {}) or {}
      -- What the marks ask of its loudness: a mark written now sets it; a
      -- mark taken away puts back what was there, if the note is still as
      -- the marks left it.
      local vb = M.velocity(rb, b.s, b.ev.art, n.velocity)
      local va, why = M.velocity(ra, w.s, art, n.velocity)
      -- What each mark wrote is kept in turn, the last on top, so that one
      -- taken away puts back what the one before it wrote.
      if va ~= vb then
        local stack = type(wrote.velocity) == "table" and util.merge(wrote.velocity, {}) or {}
        local top = stack[#stack]
        local untouched = top and top.v == n.velocity
        -- A note moved in notation takes what the marks ask where it lands.
        if va and (written_now(why, known) or (accented(art) and not accented(b.ev.art)) or ds ~= 0) then
          if not untouched then stack = {} end
          stack[#stack + 1] = { v = va, from = n.velocity }
          change.velocity, any = va, true
        elseif untouched then
          stack[#stack] = nil
          change.velocity, any = top.from, true
        end
        wrote.velocity = #stack > 0 and stack or nil
      end
      -- And of its length, of what is written.
      local gb, ga = M.gate(b.ev.art), M.gate(art)
      if ga and (ga ~= gb or w.len ~= b.len) then
        local was = wrote.length
        local from = (was and math.abs(was.v - n.length) < EPS) and was.from or n.length
        length = math.max(1 / 64, w.len / Q * ga)
        change.length, any = length, true
        wrote.length = { v = length, from = from }
        meta_now.len, meta_now.sounding = w.len / Q, length
      elseif gb and not ga then
        local was = wrote.length
        if was and math.abs(was.v - n.length) < EPS then
          change.length, any = was.from, true
        end
        wrote.length, meta_now.len, meta_now.sounding = nil, nil, nil
      elseif meta_now.len and w.len ~= b.len then
        meta_now.len, meta_now.sounding = w.len / Q, length
      end
      meta_now.wrote = next(wrote) and wrote or nil
      -- What was decided of it, when the edit changed that.
      local notation = decided and with_decisions(meta_now, d) or meta_now
      local lyric_changed = decided and (db[id] or {}).lyric ~= d.lyric
      if not same(notation, own_n) or lyric_changed then
        local meta = util.merge(n.meta or {}, {})
        meta.notation = next(notation) and notation or nil
        if lyric_changed then meta.lyric = d.lyric end
        change.meta, any = meta, true
      end
      if any then set[#set + 1] = change end
    elseif not b then
      adding[#adding + 1] = id
    end
  end
  -- The notes the score did not have, added as written, in time order.
  table.sort(adding, function(a, b) return wa[a].s < wa[b].s or (wa[a].s == wa[b].s and tostring(a) < tostring(b)) end)
  for _, id in ipairs(adding) do
    local w, d = wa[id], da[id]
    local art = w.ev.art
    local k = new_id(id)
    named[id] = k
    local length = w.len / Q
    local g = M.gate(art)
    local meta_n = with_decisions({}, d)
    if g and not w.grace then
      length = math.max(1 / 64, length * g)
      meta_n.len, meta_n.sounding = w.len / Q, length
    end
    local meta = { notation = meta_n }
    if d.lyric then meta.lyric = d.lyric end
    -- A grace note before the clip's first beat starts before the clip.
    local start = (oa + w.s) / Q
    if not w.grace then start = math.max(0, start) end
    add[#add + 1] = {
      id = k,
      pitch = w.pitch,
      start = start,
      length = length,
      velocity = M.velocity(ra, w.s, art, default) or default,
      meta = meta,
    }
  end
  if #set > 0 or #remove > 0 or #add > 0 then
    api.clip_notes_edit(clip_id, { set = set, remove = remove, add = add })
  end
  -- What the clip keeps. The staves stay as notation wrote on them where
  -- the notes now would be given others (a treble staff after a note is
  -- taken a little under it, say); where the part fixes them, the part's.
  local staves = own.staves
  if not fixed then
    -- The pitches the clip has now.
    local gone, pitches = {}, {}
    for _, i in ipairs(remove) do
      gone[i] = true
    end
    for _, ch in ipairs(set) do
      if ch.pitch then
        gone[ch.index], pitches[#pitches + 1] = true, ch.pitch
      end
    end
    for i, n in ipairs(notes) do
      if not gone[i] then pitches[#pitches + 1] = n.pitch end
    end
    for _, n in ipairs(add) do
      pitches[#pitches + 1] = n.pitch
    end
    local clefs = {}
    for i, st in ipairs(after.staves) do
      clefs[i] = st.clef
    end
    staves = not same(model.choose_clef(pitches), clefs) and clefs or nil
  end
  local pb, pa = M.clip_part(before), M.clip_part(after)
  local tb, ta = tuplets_of(before, from, to), tuplets_of(after, from, to)
  local tuplets_changed = false
  for key in pairs(ta) do
    if not tb[key] then tuplets_changed = true end
  end
  for key in pairs(tb) do
    if not ta[key] then tuplets_changed = true end
  end
  local stamped = own.version == M.VERSION or (#set == 0 and #add == 0)
  if
    not same(pb, pa)
    or tuplets_changed
    or not same(staves, own.staves)
    or own.slurs
    or M.is_legacy(own)
    or not stamped
  then
    local mine = util.merge(own, {})
    mine.marks, mine.bars, mine.layout, mine.slurs, mine.staves = pa.marks, pa.bars, pa.layout, nil, staves
    mine.version = M.VERSION
    if tuplets_changed then mine.tuplets = M.tuplets_kept(own.tuplets, tb, ta) end
    local c = api.clip_get(clip_id)
    local meta = util.merge(c.meta or {}, {})
    meta.notation = next(mine) and mine or nil
    meta.score = nil
    api.clip_set(clip_id, "meta", meta)
  end
  return named
end

--- Whether a clip's `meta.notation` keeps marks the old way.
function M.is_legacy(own)
  if own.version then return false end
  for _, mk in ipairs(own.marks or {}) do
    if mk.kind == "dyn" or mk.kind == "cresc" or mk.kind == "dim" or mk.kind == "repeat" then return true end
  end
  return false
end

--- The tuplets a clip keeps after an edit: those it kept, less the ones the
--- edit took away (a beat said to be plain where nothing kept it a
--- tuplet), and the ones it made.
function M.tuplets_kept(kept, before, after)
  local function key(tp) return string.format("%.6f:%.6f:%d:%d", tp.start, tp.length, tp.staff or 1, tp.voice or 1) end
  local out, gone, made = {}, {}, {}
  for k, tp in pairs(before) do
    if not after[k] then gone[key(tp)] = tp end
  end
  for k, tp in pairs(after) do
    if not before[k] then made[key(tp)] = tp end
  end
  for _, tp in ipairs(kept or {}) do
    local k = key(tp)
    if gone[k] then
      gone[k] = false
    elseif not made[k] then
      out[#out + 1] = tp
    end
  end
  for _, tp in pairs(gone) do
    if tp then
      out[#out + 1] = { start = tp.start, length = tp.length, plain = true, staff = tp.staff, voice = tp.voice }
    end
  end
  for _, tp in pairs(made) do
    out[#out + 1] = tp
  end
  table.sort(out, function(a, b) return a.start < b.start end)
  return #out > 0 and out or nil
end

-- Scores kept the old way ----------------------------------------------------------------------------

--- A clip kept as a score before notation was a view of MIDI
--- (`meta.score`, its notes rendered from it, each with `meta.score.n`):
--- the notes with what the score said of them, and the clip's
--- `meta.notation` with the score's marks. Nothing is written; the first
--- edit in notation writes them, and drops `meta.score`.
function M.legacy_notes(c, notes)
  local stored = type(c.meta) == "table" and c.meta.score
  local sc = type(stored) == "table" and D.decode(stored)
  if not sc then return notes, nil end
  local written = M.written(sc)
  local dec = M.decisions(sc, written)
  local out = {}
  for i, n in ipairs(notes) do
    local tag = type(n.meta) == "table" and n.meta.score
    local wid = type(tag) == "table" and tag.n
    local d = wid and dec[wid]
    if d then
      local meta = util.merge(n.meta, {})
      meta.score = nil
      local own = with_decisions(own_of(n), d)
      local w = written[wid]
      -- Rendered shorter than written (90%, or as marked): written as long as it is.
      if math.abs(w.len / Q - n.length) > EPS then
        own.len, own.sounding = w.len / Q, n.length
      end
      meta.notation = own
      if d.lyric then meta.lyric = d.lyric end
      out[i] = util.merge(n, { meta = meta })
    else
      out[i] = n
    end
  end
  local part = M.clip_part(sc)
  local own = util.merge(type(c.meta.notation) == "table" and c.meta.notation or {}, {})
  own.marks, own.bars, own.layout, own.version = part.marks, part.bars, part.layout, M.VERSION
  local tuplets = {}
  for _, tp in pairs(tuplets_of(sc)) do
    tuplets[#tuplets + 1] = tp
  end
  table.sort(tuplets, function(a, b) return a.start < b.start end)
  own.tuplets = #tuplets > 0 and tuplets or own.tuplets
  return out, own
end

--- Write a clip kept the old way as MIDI and notation data: its notes get
--- what the score said of them, the clip its marks, and `meta.score` goes.
--- Returns whether there was anything to do.
function M.migrate(clip_id)
  local c = api.clip_get(clip_id)
  if not (type(c.meta) == "table" and type(c.meta.score) == "table") then return false end
  local notes = api.clip_notes(clip_id)
  local now, own = M.legacy_notes(c, notes)
  local set = {}
  for i, n in ipairs(now) do
    if n ~= notes[i] or (type(n.meta) == "table" and n.meta.score) then
      local meta = util.merge(n.meta or {}, {})
      meta.score = nil
      set[#set + 1] = { index = i, meta = next(meta) and meta or {} }
    end
  end
  if #set > 0 then api.clip_notes_edit(clip_id, { set = set, remove = {}, add = {} }) end
  local meta = util.merge(c.meta, {})
  meta.score = nil
  meta.notation = own and next(own) and own or nil
  api.clip_set(clip_id, "meta", meta)
  return true
end

return M
