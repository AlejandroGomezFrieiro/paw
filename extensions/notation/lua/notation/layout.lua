-- Between the written score (`notation.doc`) and the page: `M.layout`
-- lays a score out in the shape `notation.model` gives a transcription
-- (measures, staves, written events with their notes, ties, tuplets,
-- accidentals, stems and beams), which the terminal and the engraver draw;
-- `M.import` makes a score of such a layout, which is how a clip's notes
-- are written as a score (`notation.midi`): the transcription is the
-- importer.
local model = require("notation.model")
local D = require("notation.doc")

local M = {}
local Q = D.Q

local ARPEGGIO = { up = 1, down = -1 }

local function by_start_voice(a, b)
  if math.abs(a.start - b.start) > 1e-9 then return a.start < b.start end
  return a.voice < b.voice
end

--- How many measures a clip `length` beats long shows: the score's, and
--- empty ones after them to its end, in the last one's meter. Never fewer
--- than the score has within the clip.
local function shown(score, length)
  local f = D.frame(score)
  local origin = D.origin(score)
  local starts, lengths, meters = {}, {}, {}
  local count = 0
  for i = 1, f.count do
    if origin + f.starts[i] < D.from_beats(length) or i == 1 then
      count = i
      starts[i], lengths[i], meters[i] = f.starts[i], f.lengths[i], f.meters[i]
    end
  end
  local meter = f.meters[f.count] or { 4, 4 }
  local at = f.count > 0 and f.finish or 0
  if count == f.count then
    while origin + at < D.from_beats(length) - 1 do
      count = count + 1
      starts[count], lengths[count], meters[count] = at, meter[1] * D.W / meter[2], meter
      at = at + lengths[count]
    end
  end
  return count, starts, lengths, meters
end

--- Measures laid out before, by what they depend on: themselves, the
--- measures on either side (ties, the bar's accidentals), the staves, the
--- key and where they are.
local kept, kept_count = {}, 0
local rebind
M.stats = { measures = 0 }

--- Point the events of a measure laid out before at the score's own
--- events, by the ids they had then. The same measure (by its token) may
--- come back in another score object, after an undo or a trial taken back,
--- while the objects the events were made from have been changed in place
--- by an edit since (`notation.view`'s `lift` gives a moved chord's old
--- place a new id): what reads `source` must find this score's.
rebind = function(staves, sm)
  if not sm then return end
  local by = {}
  for _, entry in ipairs(sm.voices) do
    for _, sev in ipairs(entry.events) do
      by[sev.id] = sev
    end
  end
  for _, evs in ipairs(staves) do
    for _, ev in ipairs(evs) do
      if ev.sid and by[ev.sid] then ev.source = by[ev.sid] end
      for _, g in ipairs(ev.grace or {}) do
        if g.sid and by[g.sid] then g.source = by[g.sid] end
      end
    end
  end
end

--- The page's layout of a score. `opts`: `length` (the clip's, in beats),
--- `fifths`, `grid`, `number` (the bar number of the first measure).
--- Measures, staves and events as `notation.model.layout` returns them;
--- each event also has `source` (the score's event), `mi` (its measure),
--- `at` (ticks into it) and `staff_id`; each note its `id`. Only measures
--- that changed are laid out again.
function M.layout(score, opts)
  opts = opts or {}
  local origin = D.origin(score)
  local count, starts, lengths, meters = shown(score, opts.length or 0)
  local staves, ids = {}, {}
  for i, s in ipairs(score.staves) do
    staves[i], ids[s.id] = s.clef, i
  end
  local clefs = table.concat(staves, ",") .. ":" .. (opts.fifths or 0) .. ":" .. origin
  local measures, built = {}, {}
  local tuplet_serial = 0
  local function add(m, s, v, sev, t, len, extra)
    local ev = {
      kind = sev.kind == "chord" and "note" or "rest",
      start = (origin + starts[m.index] + t) / Q,
      length = len / Q,
      base = D.ticks(sev.dur) / Q,
      dots = sev.dots or 0,
      measure = m.index,
      staff = s,
      voice = v,
      source = sev,
      sid = sev.id,
      mi = m.index,
      at = t,
      staff_id = score.staves[s].id,
    }
    for k, x in pairs(extra or {}) do
      ev[k] = x
    end
    if sev.kind == "chord" then
      ev.notes = {}
      for k, n in ipairs(sev.notes) do
        ev.notes[k] = {
          pitch = D.pitch(n),
          id = n.id,
          letter = n.step,
          alter = n.alter,
          octave = n.octave,
          spelled = true,
          tie = n.tie,
        }
      end
      ev.arpeggio = ARPEGGIO[sev.arpeggio or ""]
      ev.art = sev.art and next(sev.art) and sev.art or nil
      ev.staccato = ev.art and ev.art.staccato or nil
      ev.lyric = sev.lyric
    end
    table.insert(m.staves[s], ev)
    return ev
  end
  -- One measure's events, voice by voice.
  local function build(m, i)
    local sm = score.measures[i]
    local entries = {}
    for _, e in ipairs(sm and sm.voices or {}) do
      if ids[e.staff] and #e.events > 0 then entries[#entries + 1] = e end
    end
    for s = 1, #staves do
      local has1 = false
      for _, e in ipairs(entries) do
        if ids[e.staff] == s and e.voice == 1 then has1 = true end
      end
      if not has1 then
        local ev = add(m, s, 1, { kind = "rest", dur = { 1, 1 }, dots = 0, id = "" }, 0, lengths[i])
        ev.whole, ev.base = true, 4
      end
    end
    table.sort(entries, function(a, b) return a.voice < b.voice end)
    for _, e in ipairs(entries) do
      local s, v = ids[e.staff], e.voice
      local t, graces, tuplets = 0, nil, {}
      for _, sev in ipairs(e.events) do
        if sev.grace then
          graces = graces or {}
          for _, n in ipairs(sev.notes or {}) do
            graces[#graces + 1] = {
              pitch = D.pitch(n),
              id = n.id,
              letter = n.step,
              alter = n.alter,
              octave = n.octave,
              spelled = true,
              source = sev,
              sid = sev.id,
            }
          end
        else
          local len = D.length(sev)
          local extra = { grace = sev.kind == "chord" and graces or nil }
          if sev.tuplet then
            local tp = tuplets[sev.tuplet.id]
            if not tp then
              tuplet_serial = tuplet_serial + 1
              tp = {
                s = (origin + starts[i] + t) / Q,
                n = sev.tuplet.actual,
                ratio = sev.tuplet.actual / sev.tuplet.normal,
                id = tuplet_serial,
                staff = s,
                voice = v,
              }
              tuplets[sev.tuplet.id] = tp
            end
            tp.e = (origin + starts[i] + t + len) / Q
            extra.tuplet = tp
          end
          local ev = add(m, s, v, sev, t, len, extra)
          if sev.kind == "chord" then graces = nil end
          if v == 1 and sev.kind == "rest" and t == 0 and len == lengths[i] and not sev.tuplet then
            ev.whole, ev.base, ev.dots = true, 4, 0
          end
          t = t + len
        end
      end
      -- A voice that does not fill its bar: the rest of it is silence, and
      -- the bar is incomplete, which is said, not mended.
      if t < lengths[i] then
        m.incomplete = true
        for _, p in ipairs(D.values(t, lengths[i], meters[i], true)) do
          add(m, s, v, { kind = "rest", dur = p.dur, dots = p.dots, id = "" }, p.s, p.len)
        end
      elseif t > lengths[i] then
        m.overfull = true
      end
    end
    for s = 1, #staves do
      table.sort(m.staves[s], by_start_voice)
    end
  end
  -- The key and the clefs in force, as measures change them.
  local fifths, in_force = opts.fifths or 0, {}
  for k, clef in ipairs(staves) do
    in_force[k] = clef
  end
  for i = 1, count do
    local meter = D.meter(meters[i][1], meters[i][2], meters[i].groups)
    local sm, before, after = score.measures[i], score.measures[i - 1], score.measures[i + 1]
    local key_change, clef_change, key_from = nil, nil, fifths
    if sm and sm.key and sm.key.fifths then
      key_change = sm.key.fifths ~= fifths or i == 1
      fifths = sm.key.fifths
    end
    if sm and sm.clef then
      for id, clef in pairs(sm.clef) do
        local k = ids[id]
        if k and in_force[k] ~= clef then
          clef_change = clef_change or {}
          clef_change[k], in_force[k] = clef, clef
        end
      end
    end
    local now = table.concat(in_force, ",")
    local key = table.concat({
      i,
      tostring(sm and sm.v),
      tostring(before and before.v),
      tostring(after and after.v),
      clefs,
      starts[i],
      lengths[i],
      i == count and "last" or "",
      fifths,
      now,
    }, "|")
    local m = {
      number = (opts.number or 1) + i - 1,
      index = i,
      start = (origin + starts[i]) / Q,
      length = lengths[i] / Q,
      meter = meter,
      staves = {},
      id = sm and sm.id,
      v = sm and sm.v,
      fifths = fifths,
      key_change = key_change or nil,
      key_from = key_change and key_from or nil,
      clef_change = clef_change,
    }
    if now ~= table.concat(staves, ",") then
      m.clefs = {}
      for k, clef in ipairs(in_force) do
        m.clefs[k] = clef
      end
    end
    if sm then
      m.repeat_start, m.repeat_end = sm.repeat_start, sm.barline == ":|"
      m.barline, m.volta, m.rehearsal, m.key_name = sm.barline, sm.volta, sm.rehearsal, sm.key and sm.key.name
    end
    local hit = kept[key]
    if hit then
      m.staves, m.incomplete, m.overfull = hit.staves, hit.incomplete, hit.overfull
      rebind(hit.staves, sm)
    else
      for s = 1, #staves do
        m.staves[s] = {}
      end
      build(m, i)
      built[i] = true
      M.stats.measures = M.stats.measures + 1
      if kept_count > 2000 then
        kept, kept_count = {}, 0
      end
      kept[key], kept_count = { staves = m.staves, incomplete = m.incomplete, overfull = m.overfull }, kept_count + 1
    end
    measures[i] = m
  end
  -- Ties: each to the next event of its voice, over barlines too.
  local lines = {}
  for _, m in ipairs(measures) do
    for s, evs in ipairs(m.staves) do
      for _, ev in ipairs(evs) do
        local key = s .. ":" .. ev.voice
        lines[key] = lines[key] or {}
        table.insert(lines[key], ev)
      end
    end
  end
  for _, line in pairs(lines) do
    for k, ev in ipairs(line) do
      local nxt = line[k + 1]
      ev.next = nil
      if nxt and math.abs(nxt.start - (ev.start + ev.length)) < 1e-6 then ev.next = nxt end
      if ev.notes and nxt and nxt.notes and ev.next == nxt then
        for _, n in ipairs(ev.notes) do
          if n.tie then
            for _, o in ipairs(nxt.notes) do
              if o.pitch == n.pitch then
                o.tied, o.head = true, n.head or n.id
              end
            end
          end
        end
      end
      if ev.notes then
        for _, n in ipairs(ev.notes) do
          if n.tie and not (ev.next and ev.next.notes) then n.tie = nil end
        end
      end
    end
  end
  local result = {
    measures = measures,
    staves = staves,
    meter = measures[1].meter,
    fifths = measures[1].fifths or opts.fifths or 0,
    grid = opts.grid or 0.25,
    origin = origin / Q,
    score = score._transcribed or { events = {} },
    doc = score,
  }
  -- Accidentals and stems of the measures laid out now, each run of them
  -- after the measure before it, which says what its bar left altered.
  local i = 1
  while i <= count do
    if built[i] then
      local run, fresh = {}, {}
      if i > 1 then run[1] = measures[i - 1] end
      while built[i] do
        run[#run + 1] = measures[i]
        fresh[#fresh + 1] = measures[i]
        i = i + 1
      end
      model.spell_all(setmetatable({ measures = run }, { __index = result }))
      model.stems_and_beams(setmetatable({ measures = fresh }, { __index = result }))
    else
      i = i + 1
    end
  end
  return result
end

-- From a transcription ---------------------------------------------------------------------------------

local function normal_of(tp) return math.floor(tp.n / tp.ratio + 0.5) end

--- A score from a layout made by `notation.model.layout` (a transcription
--- of played notes): its measures and their meters, staves, every written
--- value, tie, tuplet, voice, grace note, arpeggio and articulation, and
--- spelling. Returns the score and, by the place of each played note in
--- the list the layout was made from, the id of the note that writes it.
---
--- `opts.keep` names the notes by place (`keep[i]` the id of the note that
--- writes played note `i`); with it every id is made from where things
--- are, not counted, so that the same notes always give the same ids
--- (a chord is named after its first note, a rest after its place).
--- `opts.next` is where the ids counted from then on start.
function M.import(layout, opts)
  opts = opts or {}
  local bars = {}
  for i, m in ipairs(layout.measures) do
    bars[i] = { start = m.start, num = m.meter.num, den = m.meter.den }
  end
  local score = D.new(bars, layout.staves)
  score.next = math.max(score.next, opts.next or 1)
  local keep = opts.keep
  -- How many written notes each played note has had, and the ids given.
  local st = { keep = keep or {}, stable = keep ~= nil, used = {}, pieces = {}, written = {} }
  for i, m in ipairs(layout.measures) do
    M.import_measure(score, i, m, st)
  end
  -- A second voice that is only rests is none.
  for i in ipairs(score.measures) do
    M.normalize_measure(score, i)
  end
  return score, st.written
end

--- An event's id: after its first note's, or its place, `at` saying where
--- (`i` the measure, `s` the staff, `serial` the staff's events so far).
--- Made once, not in the loop that uses it: LuaJIT does not compile a loop
--- that makes a function.
local function event_id(score, at, ev, prefix, note)
  if not at.stable then return D.id(score, prefix == "r" and "e" or prefix) end
  if note then return prefix .. note.id:sub(2) end
  at.serial = at.serial + 1
  return prefix .. at.i .. "." .. at.s .. "." .. ev.voice .. "." .. at.serial
end

--- A note written of played note `n` (a layout's), with `st` as
--- `M.import_measure` has it.
local function note_of(n, st, score)
  local id = n.index and st.keep[n.index]
  if id and st.stable then
    local k = (st.pieces[n.index] or 0) + 1
    st.pieces[n.index] = k
    if k > 1 then id = id .. "." .. k end
  elseif n.tied then
    id = nil
  end
  if not id or st.used[id] then id = D.id(score, "n") end
  st.used[id] = true
  if n.index and not n.tied then st.written[n.index] = id end
  return { id = id, step = n.letter, alter = n.alter, octave = n.octave }
end

--- Write measure `i` of a layout (`m`) into the score's measure `i`. `st`
--- is what goes from measure to measure: `keep` (the id of the note that
--- writes each played note, by its place) and `stable` (ids made from
--- where things are, see `M.import`), the ids `used`, how many written
--- notes each played note has had (`pieces`), and the id each was
--- written with (`written`).
function M.import_measure(score, i, m, st)
  local sm = score.measures[i]
  if m.repeat_start then sm.repeat_start = true end
  if m.repeat_end then sm.barline = ":|" end
  local stable = st.stable
  if stable then sm.id = "m" .. i end
  for s, evs in ipairs(m.staves) do
    local staff = score.staves[s].id
    local tuplets = {}
    local at = { stable = stable, i = i, s = s, serial = 0 }
    for _, ev in ipairs(evs) do
      local entry = D.voice(sm, staff, ev.voice, true)
      for _, g in ipairs(ev.grace or {}) do
        local note = note_of(g, st, score)
        entry.events[#entry.events + 1] = {
          id = event_id(score, at, ev, "g", note),
          kind = "chord",
          grace = "acciaccatura",
          dur = { 1, 8 },
          dots = 0,
          notes = { note },
        }
      end
      if not (ev.whole and ev.voice == 1) then
        -- A stretch no single value can write (shorter than a 32nd, off its
        -- grid) is written as long as it is.
        local base = ev.base or ev.length * (ev.tuplet and ev.tuplet.ratio or 1)
        local sev =
          { kind = ev.kind == "note" and "chord" or "rest", dur = D.ratio(D.from_beats(base)), dots = ev.dots or 0 }
        if ev.whole then
          sev.dur, sev.dots = D.ratio(D.from_beats(m.length)), 0
        end
        if ev.tuplet then
          local tp = tuplets[ev.tuplet]
          if not tp then
            tp = {
              id = stable and event_id(score, at, ev, "t") or D.id(score, "t"),
              actual = ev.tuplet.n,
              normal = normal_of(ev.tuplet),
            }
            tuplets[ev.tuplet] = tp
          end
          sev.tuplet = tp
        end
        if ev.kind == "note" then
          sev.notes = {}
          for k, n in ipairs(ev.notes) do
            sev.notes[k] = note_of(n, st, score)
            sev.notes[k].tie = n.tie or nil
            local own = n.meta and type(n.meta.notation) == "table" and n.meta.notation
            if own and own.beam == "break" and not n.tied then sev.beam = "break" end
          end
          sev.id = event_id(score, at, ev, "e", sev.notes[1])
          local art = {}
          for k, x in pairs(ev.art or {}) do
            art[k] = x
          end
          if ev.staccato then art.staccato = true end
          sev.art = next(art) and art or nil
          sev.arpeggio = ev.arpeggio == 1 and "up" or ev.arpeggio == -1 and "down" or nil
          sev.lyric = ev.lyric
        else
          sev.id = event_id(score, at, ev, "r")
        end
        entry.events[#entry.events + 1] = sev
      end
    end
  end
  if not stable then return end
  -- What a voice leaves of its bar is silence, named by its place too (a
  -- whole bar's rest of the first voice is no event).
  local f = D.frame(score)
  for _, entry in ipairs(sm.voices) do
    local t = 0
    for _, ev in ipairs(entry.events) do
      t = t + D.length(ev)
    end
    if t < f.lengths[i] then
      for k, p in ipairs(D.values(t, f.lengths[i], f.meters[i], true)) do
        entry.events[#entry.events + 1] = {
          id = "r" .. i .. "." .. D.staff_index(score, entry.staff) .. "." .. entry.voice .. ".f" .. k,
          kind = "rest",
          dur = p.dur,
          dots = p.dots,
        }
      end
    end
  end
end

--- Merge each voice's rests in measure `i` as the metre divides it; a
--- second voice that is only rests is none.
function M.normalize_measure(score, i)
  for _, st in ipairs(score.staves) do
    for v = 1, 4 do
      D.normalize(score, i, st.id, v)
    end
  end
end

return M
