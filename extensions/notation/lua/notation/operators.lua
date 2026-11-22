-- Operators of the notation view, and the entry modes that go with them:
-- each works on the written score (`notation.doc`) of a selection
-- (`notation.objects`), so `d`, `y`, `c`, `p`, `>`, `<` and the musical
-- operators (`gU` `gu` steps of the key, `g+` `g-` semitones, `g~`
-- enharmonics, `s` a slur, `g?` retrograde or inversion, `!` a filter, `gq`
-- tidy) are exact on every object and motion, and each is one undo step.
--
-- What is yanked is a fragment of the score (`value.score`) with the notes
-- it plays (`value.notes`), so a register pastes into notation as written
-- and into the piano roll as played.
local api = paw.api
local util = paw.util
local view = require("notation")
local model = require("notation.model")
local D = require("notation.doc")
local O = require("notation.objects")

local P = {}
local floor = math.floor

-- Writing a stretch of a voice -------------------------------------------------------------------

--- Silence a voice from `a` to `b` (ticks from measure 1), grace notes
--- there too: what is cut keeps what is before it, tied as the metre has it.
function P.clear(sc, staff, v, a, b)
  local f = D.frame(sc)
  b = math.min(b, f.finish)
  local t = a
  while t < b do
    local mi, at = D.locate(sc, t)
    f = D.frame(sc)
    local e = math.min(f.lengths[mi], at + b - t)
    local entry = D.voice(sc.measures[mi], staff, v)
    if entry and #entry.events > 0 then
      D.splice(sc, mi, staff, v, at, e, nil)
      -- Grace notes leading into the stretch go with it.
      entry = D.voice(sc.measures[mi], staff, v)
      if entry then
        local x, kept = 0, {}
        for _, ev in ipairs(entry.events) do
          if not (ev.grace and x >= at and x < e) then kept[#kept + 1] = ev end
          x = x + D.length(ev)
        end
        if #kept ~= #entry.events then
          entry.events = kept
          D.normalize(sc, mi, staff, v)
          D.touch(sc, mi)
        end
      end
    end
    t = t + (e - at)
  end
  local m0 = D.locate(sc, a)
  D.fix_ties(sc, staff, v, math.max(1, m0 - 1), D.locate(sc, math.max(a, b - 1)))
end

--- Entries in time order with each tie chain made one entry, as long as
--- all of it: copies, so that they can be changed.
local function merged(entries)
  local out = {}
  for _, e in ipairs(entries) do
    local prev = out[#out]
    local joins = prev
      and prev.kind == "chord"
      and e.kind == "chord"
      and not prev.tuplet
      and not e.tuplet
      and not prev.grace
      and not e.grace
      and prev.at + prev.len == e.at
      and #prev.notes == #e.notes
    if joins then
      for k, n in ipairs(prev.notes) do
        if not (n.tie and D.pitch(e.notes[k]) == D.pitch(n)) then joins = false end
      end
    end
    if joins then
      prev.len = prev.len + e.len
      for k, n in ipairs(prev.notes) do
        n.tie = e.notes[k].tie
      end
    else
      local copy = util.merge(e, {})
      if e.notes then copy.notes = D.copy(e.notes) end
      out[#out + 1] = copy
    end
  end
  return out
end
P.merged = merged

local function notes_of(sc, notes, keep)
  local out = {}
  for i, n in ipairs(notes) do
    out[i] = { id = keep and n.id or D.id(sc, "n"), step = n.step, alter = n.alter, octave = n.octave, tie = n.tie }
  end
  return out
end

local function event_of(sc, e, keep, tp)
  return {
    id = keep and e.id or D.id(sc, "e"),
    kind = e.kind,
    dur = e.dur,
    dots = e.dots or 0,
    tuplet = tp,
    notes = e.notes and notes_of(sc, e.notes, keep) or nil,
    art = e.art,
    arpeggio = e.arpeggio,
    beam = e.beam,
    stem = e.stem,
    grace = e.grace,
    lyric = e.lyric,
  }
end

--- Write entries (a fragment's line: `{ at, len, kind, notes, ... }`, `at`
--- from `t0`) into a voice from `t0`, over `length` ticks: what is there
--- gives way. Tie chains are written again as the metre divides the bars
--- they land in; a tuplet that fits in its bar stays a tuplet. With `keep`
--- the events and notes keep their ids (a move), else they are new (a copy).
function P.lay(sc, staff, v, t0, entries, length, keep)
  P.clear(sc, staff, v, t0, t0 + length)
  local list = merged(entries)
  local graces = {}
  local k = 1
  while k <= #list do
    local e = list[k]
    local t = t0 + e.at
    if e.grace then
      graces[#graces + 1] = { t = t, e = e }
      k = k + 1
    elseif e.tuplet then
      local group = { e }
      while
        list[k + #group]
        and list[k + #group].tuplet
        and list[k + #group].tuplet.id == e.tuplet.id
        and not list[k + #group].grace
      do
        group[#group + 1] = list[k + #group]
      end
      local span = group[#group].at + group[#group].len - e.at
      local mi, at = D.locate(sc, t)
      D.ensure(sc, mi)
      local f = D.frame(sc)
      if at + span <= f.lengths[mi] then
        local tp = { id = D.id(sc, "t"), actual = e.tuplet.actual, normal = e.tuplet.normal }
        local evs = {}
        for i, g in ipairs(group) do
          evs[i] = event_of(sc, g, keep, tp)
        end
        D.splice(sc, mi, staff, v, at, at + span, evs)
      else
        for _, g in ipairs(group) do
          if g.kind == "chord" then P.put(sc, staff, v, t0 + g.at, g.len, g, keep) end
        end
      end
      k = k + #group
    else
      if e.kind == "chord" then P.put(sc, staff, v, t, e.len, e, keep) end
      k = k + 1
    end
  end
  for _, g in ipairs(graces) do
    local mi, at = D.locate(sc, g.t)
    local entry = sc.measures[mi] and D.voice(sc.measures[mi], staff, v)
    if entry then
      local x = 0
      for i, ev in ipairs(entry.events) do
        if x == at and not ev.grace then
          table.insert(entry.events, i, event_of(sc, g.e, keep))
          D.touch(sc, mi)
          break
        end
        x = x + D.length(ev)
      end
    end
  end
  local m0 = D.locate(sc, t0)
  D.fix_ties(sc, staff, v, math.max(1, m0 - 1), D.locate(sc, t0 + math.max(0, length - 1)))
end

--- Write one chord entry `len` ticks long at `t`, tied over barlines.
function P.put(sc, staff, v, t, len, e, keep)
  local mi, at = D.locate(sc, t)
  local notes = {}
  for i, n in ipairs(e.notes) do
    notes[i] = { id = keep and n.id or nil, step = n.step, alter = n.alter, octave = n.octave }
  end
  return D.put_chord(
    sc,
    mi,
    staff,
    v,
    at,
    len,
    notes,
    { id = keep and e.id or nil, art = e.art, arpeggio = e.arpeggio, beam = e.beam }
  )
end

-- Fragments: what is yanked ----------------------------------------------------------------------

--- A selection as a fragment of the score: lines of entries (one per staff
--- and voice: `{ staff_index, voice, entries }`), `base` (ticks from
--- measure 1 its entries count from) and `length`; or whole measures.
function P.fragment(sc, sel)
  local f = D.frame(sc)
  if sel.measures then
    local ms = {}
    for i = sel.measures[1], sel.measures[2] do
      local m = D.copy(sc.measures[i])
      m.meter = f.meters[i]
      ms[#ms + 1] = m
    end
    local staves = {}
    for i, st in ipairs(sc.staves) do
      staves[i] = st.id
    end
    return { measures = ms, staves = staves, base = sel.from, length = sel.to - sel.from }
  end
  local items = O.items(sc, sel)
  local base = sel.from
  if sel.events or sel.notes then
    base = math.huge
    for _, it in ipairs(items) do
      base = math.min(base, it.s)
    end
    if base == math.huge then base = sel.from end
  end
  local lines, order, finish = {}, {}, sel.to
  for _, it in ipairs(items) do
    local key = it.staff .. ":" .. it.voice
    local line = lines[key]
    if not line then
      line = { staff_index = D.staff_index(sc, it.staff), voice = it.voice, entries = {} }
      lines[key] = line
      order[#order + 1] = line
    end
    local ev = it.ev
    local e = {
      at = it.s - base,
      len = it.e - it.s,
      kind = ev.kind,
      id = ev.id,
      dur = ev.dur,
      dots = ev.dots,
      grace = ev.grace,
      art = ev.art,
      arpeggio = ev.arpeggio,
      beam = ev.beam,
      stem = ev.stem,
      lyric = ev.lyric,
      tuplet = ev.tuplet and { id = ev.tuplet.id, actual = ev.tuplet.actual, normal = ev.tuplet.normal } or nil,
    }
    if it.notes then e.notes = D.copy(it.notes) end
    line.entries[#line.entries + 1] = e
    finish = math.max(finish, it.e)
  end
  if finish == math.huge then finish = f.finish end
  return { lines = order, base = base, length = math.max(0, finish - base) }
end

--- A fragment as a register's value: the clip's notes it writes too, as
--- they play and with what they keep, for the piano roll.
function P.value(sc, frag)
  local ids = {}
  for _, line in ipairs(frag.lines or {}) do
    for _, e in ipairs(line.entries) do
      for _, n in ipairs(e.notes or {}) do
        ids[n.id] = true
      end
    end
  end
  for _, m in ipairs(frag.measures or {}) do
    for _, entry in ipairs(m.voices) do
      for _, ev in ipairs(entry.events) do
        for _, n in ipairs(ev.notes or {}) do
          ids[n.id] = true
        end
      end
    end
  end
  local from = O.beat(sc, frag.base)
  local notes, top = {}, 0
  local clip = view:clip()
  for _, n in ipairs(clip and clip:notes() or {}) do
    if n.id and ids["n" .. n.id] then
      notes[#notes + 1] = {
        pitch = n.pitch,
        start = n.start - from,
        length = n.length,
        velocity = n.velocity,
        meta = n.meta,
        attr = n.attr,
      }
      top = math.max(top, n.pitch)
    end
  end
  return { kind = "notes", shape = "char", top = top, length = frag.length / D.Q, notes = notes, score = frag }
end

-- Measures ----------------------------------------------------------------------------------------

--- Take measures `a` to `b` out of the score: the music after them closes
--- up; marks in them go with them. Every measure taken empties them instead.
function P.remove_measures(sc, a, b)
  local f = D.frame(sc)
  if a == 1 and b >= f.count then
    for i = a, b do
      sc.measures[i].voices = {}
      D.touch(sc, i)
    end
    return
  end
  local after = sc.measures[b + 1]
  if after and not after.meter then after.meter = f.meters[b + 1] end
  local gone = {}
  for i = a, b do
    gone[sc.measures[i].id] = true
  end
  local marks = {}
  for _, mk in ipairs(sc.marks or {}) do
    if not (gone[mk.from and mk.from.measure] or (mk.to and gone[mk.to.measure])) then marks[#marks + 1] = mk end
  end
  sc.marks = marks
  for i = b, a, -1 do
    table.remove(sc.measures, i)
  end
  sc._frame = nil
  for i = a, #sc.measures do
    D.touch(sc, i)
  end
  for _, st in ipairs(sc.staves) do
    for v = 1, 4 do
      D.fix_ties(sc, st.id, v, math.max(1, a - 1), math.min(#sc.measures, a))
    end
  end
end

--- Put copies of measures (a fragment's) in before measure `at`, their
--- staves by place, everything in them with ids of its own.
function P.insert_measures(sc, at, frag)
  local f = D.frame(sc)
  local follow = sc.measures[at]
  if follow and not follow.meter then follow.meter = f.meters[at] end
  local staff_of = {}
  for i, id in ipairs(frag.staves or {}) do
    staff_of[id] = sc.staves[i] and sc.staves[i].id
  end
  for k, m in ipairs(frag.measures) do
    local copy = D.copy(m)
    copy.id = D.id(sc, "m")
    local voices, tuplets = {}, {}
    for _, entry in ipairs(copy.voices) do
      entry.staff = staff_of[entry.staff]
      if entry.staff then
        for _, ev in ipairs(entry.events) do
          ev.id = D.id(sc, "e")
          for _, n in ipairs(ev.notes or {}) do
            n.id = D.id(sc, "n")
          end
          if ev.tuplet then
            tuplets[ev.tuplet.id] = tuplets[ev.tuplet.id]
              or { id = D.id(sc, "t"), actual = ev.tuplet.actual, normal = ev.tuplet.normal }
            ev.tuplet = tuplets[ev.tuplet.id]
          end
        end
        voices[#voices + 1] = entry
      end
    end
    copy.voices = voices
    table.insert(sc.measures, at + k - 1, copy)
  end
  sc._frame = nil
  for i = at, #sc.measures do
    D.touch(sc, i)
  end
end

-- Deleting, moving and pasting ----------------------------------------------------------------------

--- Take a selection out: whole measures out of the score, chosen notes out
--- of their chords, chosen chords (with their ties and grace notes) or a
--- stretch of time made rests; a slur chosen with them goes too.
function P.delete(sc, sel)
  if sel.measures then
    P.remove_measures(sc, sel.measures[1], sel.measures[2])
  elseif sel.notes or sel.pitches then
    for _, it in ipairs(O.items(sc, sel)) do
      for _, n in ipairs(it.notes) do
        if D.find_note(sc, n.id) then D.remove_note(sc, n.id) end
      end
    end
  elseif sel.events then
    for _, it in ipairs(O.items(sc, sel)) do
      if it.ev.kind == "chord" and not it.ev.grace and D.find(sc, it.ev.id) then view.lift(sc, it.ev.id) end
    end
  else
    for _, st in ipairs(sc.staves) do
      if not sel.staff or sel.staff == st.id then
        for v = 1, 4 do
          if not sel.voice or sel.voice == v then P.clear(sc, st.id, v, sel.from, sel.to) end
        end
      end
    end
  end
  if sel.slur then
    local kept = {}
    for _, mk in ipairs(sc.marks or {}) do
      if mk.id ~= sel.slur then kept[#kept + 1] = mk end
    end
    sc.marks = kept
  end
end

--- Where a fragment's line goes: one line goes to the cursor's staff and
--- voice, several to their own.
local function target(sc, frag, line, cur)
  if #frag.lines == 1 then return cur.staff, cur.voice end
  local st = sc.staves[line.staff_index] or sc.staves[#sc.staves]
  return st.id, line.voice
end

--- Write a fragment at `t` (ticks from measure 1); whole measures go in
--- before measure `t`'s, or after it with `after`.
function P.put_fragment(sc, frag, t, cur, keep, after)
  if frag.measures then
    local mi = D.locate(sc, t)
    P.insert_measures(sc, after and mi + 1 or mi, frag)
    return
  end
  for _, line in ipairs(frag.lines) do
    local staff, v = target(sc, frag, line, cur)
    P.lay(sc, staff, v, t, line.entries, frag.length, keep)
  end
end

--- Move a selection by `by` ticks: written again there, with its ids (and
--- so their notes and marks), what is there giving way.
function P.shift(sc, sel, by)
  local frag = P.fragment(sc, sel)
  if not frag.lines or #frag.lines == 0 then return false end
  local to = math.max(0, frag.base + by)
  P.delete(sc, sel)
  for _, line in ipairs(frag.lines) do
    local st = sc.staves[line.staff_index] or sc.staves[1]
    P.lay(sc, st.id, line.voice, to, line.entries, frag.length, true)
  end
  return to
end

-- Pitches ---------------------------------------------------------------------------------------------

local function key() return (view.key()) end

--- Each chosen note's own pitch changed by `fn(note) -> spelling` (as
--- `notation.model` spells: letter, alter, pitch), ties carried along.
--- Returns how many changed.
function P.repitch(sc, sel, fn)
  local count = 0
  for _, h in ipairs(O.heads(sc, sel)) do
    local sp = fn(h.note, h.item)
    if sp and sp.pitch >= 0 and sp.pitch <= 127 and math.abs(sp.alter) <= 2 then
      D.respell(sc, h.note.id, sp.letter, sp.alter, sp.octave)
      count = count + 1
    end
  end
  return count
end

--- A note `steps` steps of the key up (or down), keeping how far it is
--- from the key (a C sharp in C major goes up to a D sharp).
function P.step_note(n, steps, fifths)
  local d = D.diatonic(n) + steps
  local letter = d % 7
  local alter = model.key_alter(letter, fifths) + (n.alter - model.key_alter(n.step, fifths))
  alter = util.clamp(alter, -2, 2)
  return model.spelled(letter, alter, model.pitch_of(d, alter))
end

--- A note `by` semitones away, spelled as the key has it (an octave keeps its spelling).
function P.shift_note(n, by, fifths)
  local pitch = D.pitch(n) + by
  if by % 12 == 0 then return model.spelled(n.step, n.alter, pitch) end
  return model.spell(pitch, fifths)
end

--- The next name of a note's pitch, in turn: G sharp, A flat, G sharp; E,
--- F flat; F, E sharp. Double sharps and flats only where nothing simpler
--- names it otherwise (D, C double sharp, E double flat).
function P.enharmonic(n)
  local pitch = D.pitch(n)
  local all, simple = {}, {}
  for letter = 0, 6 do
    for alter = -2, 2 do
      local sp = model.spelled(letter, alter, pitch)
      if model.pitch_of(sp.step, alter) == pitch then
        all[#all + 1] = sp
        if math.abs(alter) <= 1 then simple[#simple + 1] = sp end
      end
    end
  end
  local options = #simple > 1 and simple or all
  table.sort(options, function(a, b)
    if math.abs(a.alter) ~= math.abs(b.alter) then return math.abs(a.alter) < math.abs(b.alter) end
    return a.step < b.step
  end)
  for i, sp in ipairs(options) do
    if sp.letter == n.step and sp.alter == n.alter then return options[i % #options + 1] end
  end
  return options[1]
end

--- Retrograde: each line of the selection backwards, rhythm and pitches,
--- grace notes with the chord they lead to.
function P.retrograde(sc, sel)
  local frag = P.fragment(sc, sel)
  if not frag.lines or #frag.lines == 0 then return false end
  for _, line in ipairs(frag.lines) do
    local units = {}
    local graces = {}
    for _, e in ipairs(merged(line.entries)) do
      if e.grace then
        graces[#graces + 1] = e
      else
        units[#units + 1] = { main = e, graces = graces }
        graces = {}
      end
    end
    local out = {}
    for _, u in ipairs(units) do
      u.main.at = frag.length - (u.main.at + u.main.len)
      if u.main.notes then
        for _, n in ipairs(u.main.notes) do
          n.tie = nil
        end
      end
      for _, g in ipairs(u.graces) do
        g.at = u.main.at
      end
    end
    for k = #units, 1, -1 do
      for _, g in ipairs(units[k].graces) do
        out[#out + 1] = g
      end
      out[#out + 1] = units[k].main
    end
    local st = sc.staves[line.staff_index] or sc.staves[1]
    P.lay(sc, st.id, line.voice, frag.base, out, frag.length, true)
  end
end

--- Inversion: every chosen note mirrored, in the key, about the first one.
function P.invert(sc, sel)
  local heads = O.heads(sc, sel)
  if #heads == 0 then return 0 end
  local axis = D.diatonic(heads[1].note)
  local fifths = key()
  return P.repitch(sc, sel, function(n) return P.step_note(n, 2 * (axis - D.diatonic(n)), fifths) end)
end

--- Tidy: notes spelled as the key has them, beams as the metre has them,
--- and the values written again as the metre divides the bars.
function P.tidy(sc, sel)
  local fifths = key()
  P.repitch(sc, sel, function(n)
    local sp = model.spell(D.pitch(n), fifths)
    if sp.letter ~= n.step or sp.alter ~= n.alter then return sp end
  end)
  if sel.notes or sel.pitches then return end
  for _, it in ipairs(O.items(sc, sel)) do
    if it.ev.beam then
      it.ev.beam = nil
      D.touch(sc, it.mi)
    end
  end
  local frag = P.fragment(sc, sel)
  for _, line in ipairs(frag.lines or {}) do
    local st = sc.staves[line.staff_index] or sc.staves[1]
    P.lay(sc, st.id, line.voice, frag.base, line.entries, frag.length, true)
  end
end

-- Filters: `!` ----------------------------------------------------------------------------------------
--
-- A filter changes the music of a line: a list of `{ len (ticks), notes =
-- { { step, alter, octave } } }` (no notes is a rest), returned changed.
-- Named filters are Lua functions (`P.filter(name, fn, desc)`); any other
-- name runs as a command of the shell, which reads the line as text, an
-- event a line ("1/4 C4 E4", "1/8 r", lengths as parts of a whole note),
-- and writes it back so.

P.filters = {}

--- Add a filter for `!`: `fn(events, args)` returns the events changed.
function P.filter(name, fn, desc) P.filters[name] = { fn = fn, desc = desc or "" } end

P.filter("reverse", function(events)
  local out = {}
  for k = #events, 1, -1 do
    out[#out + 1] = events[k]
  end
  return out
end, "the line backwards: a retrograde")
P.filter("transpose", function(events, args)
  local by = tonumber(args[1]) or 0
  local fifths = key()
  for _, e in ipairs(events) do
    for k, n in ipairs(e.notes or {}) do
      local sp = P.shift_note(n, by, fifths)
      e.notes[k] = { step = sp.letter, alter = sp.alter, octave = sp.octave }
    end
  end
  return events
end, "every note by semitones: `transpose -12`")
P.filter("rhythm", function(events, args)
  -- Every note the same value: `rhythm 1/8`.
  local a, b = tostring(args[1] or "1/4"):match("^(%d+)/(%d+)$")
  local len = a and D.ticks({ tonumber(a), tonumber(b) }) or D.Q
  for _, e in ipairs(events) do
    e.len = len
  end
  return events
end, "every event one value: `rhythm 1/8`")

local LETTER = { c = 0, d = 1, e = 2, f = 3, g = 4, a = 5, b = 6 }

--- An event as a line of text, and back.
local function event_text(e)
  local r = D.ratio(e.len)
  local words = { r[1] .. "/" .. r[2] }
  if not e.notes or #e.notes == 0 then
    words[2] = "r"
  else
    for _, n in ipairs(e.notes) do
      words[#words + 1] = model.name({ letter = n.step, alter = n.alter, octave = n.octave })
    end
  end
  return table.concat(words, " ")
end

local function text_event(line)
  local words = {}
  for w in line:gmatch("%S+") do
    words[#words + 1] = w
  end
  if #words == 0 then return nil end
  local a, b = words[1]:match("^(%d+)/(%d+)$")
  if not a or tonumber(b) == 0 then return nil, "`" .. line .. "`: an event starts with its length, `1/4`" end
  local e = { len = D.ticks({ tonumber(a), tonumber(b) }) }
  if words[2] ~= "r" then
    e.notes = {}
    for k = 2, #words do
      local letter, acc, octave = words[k]:match("^([A-Ga-g])([#bx]*)(%-?%d+)$")
      if not letter then return nil, "`" .. words[k] .. "` is not a note, such as C#4" end
      local alter = acc == "x" and 2 or (acc:gsub("b", "") == "" and -#acc) or #acc
      e.notes[#e.notes + 1] = { step = LETTER[letter:lower()], alter = alter, octave = tonumber(octave) }
    end
  end
  return e
end

--- Run a shell command over events as text; the events it writes back, or nil and why not.
local function shell(cmd, events)
  local lines = {}
  for i, e in ipairs(events) do
    lines[i] = event_text(e)
  end
  local path = os.tmpname()
  local fh = io.open(path, "w")
  if not fh then return nil, "no room for the filter's input" end
  fh:write(table.concat(lines, "\n"), "\n")
  fh:close()
  local pipe = io.popen("(" .. cmd .. ") < '" .. path:gsub("'", "'\\''") .. "' 2>&1")
  local out = pipe and pipe:read("*a") or ""
  if pipe then pipe:close() end
  os.remove(path)
  local back = {}
  for line in out:gmatch("[^\n]+") do
    local e, why = text_event(line)
    if why then return nil, cmd .. ": " .. why end
    if e then back[#back + 1] = e end
  end
  if #back == 0 and #events > 0 then return nil, cmd .. " wrote nothing back" end
  return back
end

--- Filter a selection through `line` (a filter's name and its words, or a
--- shell command): each staff and voice of it written again from what
--- comes back. Nil and why on failure.
function P.run_filter(sc, sel, line)
  local words = {}
  for w in line:gmatch("%S+") do
    words[#words + 1] = w
  end
  if #words == 0 then return nil, "a filter: " .. P.filter_names() .. ", or a shell command" end
  local named = P.filters[words[1]]
  local frag = P.fragment(sc, sel)
  if not frag.lines or #frag.lines == 0 then return nil, "nothing there to filter" end
  for _, ln in ipairs(frag.lines) do
    local events, prev_end = {}, 0
    for _, e in ipairs(merged(ln.entries)) do
      if not e.grace then
        -- Time before an entry that nothing fills is a rest.
        if e.at > prev_end then events[#events + 1] = { len = e.at - prev_end } end
        local notes
        if e.kind == "chord" then
          notes = {}
          for k, n in ipairs(e.notes) do
            notes[k] = { step = n.step, alter = n.alter, octave = n.octave }
          end
        end
        events[#events + 1] = { len = e.len, notes = notes }
        prev_end = e.at + e.len
      end
    end
    local back, why
    if named then
      local ok, res = pcall(named.fn, events, { unpack(words, 2) })
      if not ok then return nil, words[1] .. ": " .. tostring(res) end
      back = res
    else
      back, why = shell(line, events)
      if not back then return nil, why end
    end
    local entries, at = {}, 0
    for _, e in ipairs(back) do
      if e.len and e.len > 0 then
        entries[#entries + 1] =
          { at = at, len = e.len, kind = e.notes and #e.notes > 0 and "chord" or "rest", notes = e.notes }
        at = at + e.len
      end
    end
    local st = sc.staves[ln.staff_index] or sc.staves[1]
    P.clear(sc, st.id, ln.voice, frag.base, frag.base + frag.length)
    P.lay(sc, st.id, ln.voice, frag.base, entries, at, false)
  end
  return true
end

function P.filter_names()
  local names = {}
  for name in pairs(P.filters) do
    names[#names + 1] = name
  end
  table.sort(names)
  return table.concat(names, ", ")
end

-- Running an operator --------------------------------------------------------------------------------

--- Change the score over a region (if one is given) with `fn(sc, sel,
--- clip)`, as one edit of its notes.
--- `fn` returning false changes nothing.
function P.on(region, fn)
  if not view:editable() then return end
  local result
  view:write(function(sc, clip)
    result = fn(sc, region and O.of_region(sc, region), clip)
    if result == false then return false end
  end)
  O.reach = nil
  return result
end

--- What a selection holds, to say: "3 notes".
local function counted(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

--- Yank a region into a register.
function P.yank(region, register)
  local sc = O.score()
  if not sc then return end
  local value = P.value(sc, P.fragment(sc, O.of_region(sc, region)))
  paw.keymap.setreg(value, register, true)
  O.reach = nil
  paw.notify("yanked " .. counted(#value.notes, "note"))
end

--- Delete a region, keeping it in a register.
function P.delete_region(region, register)
  P.on(region, function(sc, sel)
    paw.keymap.setreg(P.value(sc, P.fragment(sc, sel)), register)
    P.delete(sc, sel)
  end)
end

--- Paste a register at the cursor (`before`), or after the note under it;
--- `count` times, one after another. A register of notes from the piano
--- roll goes in as played. Returns where the paste ends, in clip beats.
function P.paste(value, before, count)
  local clip = view:clip()
  if not clip then return end
  if not value then return paw.notify("nothing to paste yet", "warn") end
  if not value.score then
    local at = view.beat
    if not before then
      local note, index = view:note()
      if note then at = select(2, view:written_span(index)) or (note.start + note.length) end
    end
    local start, finish = at, at
    for _ = 1, count or 1 do
      start = finish
      finish = paw.edit.roll.paste(clip, value, view:cursor_pitch(), finish)
      if not finish then return end
    end
    view:set(nil, start)
    return finish
  end
  local frag = value.score
  local finish
  P.on(nil, function(sc)
    local cur = O.cursor(sc)
    cur.voice = view:cursor_voice()
    local t = cur.t
    if frag.measures then
      for _ = 1, count or 1 do
        P.put_fragment(sc, frag, t, cur, false, not before)
      end
      local mi = D.locate(sc, t)
      local f = D.frame(sc)
      local first = before and mi or mi + 1
      view.beat = math.max(0, O.beat(sc, f.starts[first] or f.finish))
      return
    end
    if not before then
      local it = O.chord_here(sc, cur)
      if it then
        local links = view.chain(sc, it.ev.id)
        local last = links[#links]
        t = D.frame(sc).starts[last.mi] + last.at + D.length(last.ev)
      end
    end
    local start = t
    for _ = 1, count or 1 do
      P.put_fragment(sc, frag, t, cur, false)
      t = t + frag.length
    end
    view.beat = math.max(0, O.beat(sc, start))
    finish = O.beat(sc, t)
  end)
  return finish
end

-- Entry modes -----------------------------------------------------------------------------------------

--- Push-insert: what a voice has from `t` on moves `len` ticks later.
function P.push_on(sc, staff, v, t, len)
  local f = D.frame(sc)
  local sel = { from = t, to = f.finish, staff = staff, voice = v }
  local frag = P.fragment(sc, sel)
  if not frag.lines[1] then return end
  P.clear(sc, staff, v, t, f.finish)
  P.lay(sc, staff, v, t + len, frag.lines[1].entries, frag.length, true)
end
view.push_on = P.push_on

local LETTER_STEP = LETTER

--- The step of a letter nearest a step (within a fourth).
function P.nearest(letter, from)
  local l = LETTER_STEP[letter]
  local step = floor(from / 7) * 7 + l
  if step - from > 3 then
    step = step - 7
  elseif from - step > 3 then
    step = step + 7
  end
  return step
end

--- The spelling of a letter at a step, as the key alters it.
local function key_spelling(step, fifths)
  local letter = step % 7
  return model.spelled(letter, model.key_alter(letter, fifths), model.key_pitch(step, fifths))
end
P.key_spelling = key_spelling

--- Re-pitch the note under the cursor (or the chord's top note) to a
--- letter, in the octave nearest it, and the next `count - 1` chords of its
--- voice: their rhythm stays.
function P.repitch_letter(letter, count)
  local fifths = key()
  local moved
  P.on(nil, function(sc)
    local it, note, cur, i, seq = O.chord_here(sc)
    if not it then
      paw.notify("no note here to re-pitch", "warn")
      return false
    end
    local left = count or 1
    local k = i
    while seq[k] and left > 0 do
      local x = seq[k]
      if x.ev.kind == "chord" and not x.ev.grace then
        local n = (k == i and note) or x.ev.notes[#x.ev.notes]
        if k ~= i then
          local best
          for _, o in ipairs(x.ev.notes) do
            if not best or math.abs(D.diatonic(o) - cur.step) < math.abs(D.diatonic(best) - cur.step) then best = o end
          end
          n = best
        end
        local sp = key_spelling(P.nearest(letter, D.diatonic(n)), fifths)
        D.respell(sc, n.id, sp.letter, sp.alter, sp.octave)
        moved = moved or sp.step
        left = left - 1
        -- Over the notes its ties join.
        local links = view.chain(sc, x.ev.id)
        k = k + #links
      else
        k = k + 1
      end
    end
  end)
  if moved then view:set(moved, nil) end
end

--- In re-pitch mode (`R`), a letter: the chord at the cursor in the voice
--- entered becomes that note, rhythm kept, and the cursor goes on to the
--- next chord; with `add`, the note joins the chord re-pitched last.
function P.repitch_enter(letter, add)
  local fifths = key()
  local last = view.last
  local done
  P.on(nil, function(sc)
    local from = last and last.step or view.step
    local sp = key_spelling(P.nearest(letter, from), fifths)
    local note = { step = sp.letter, alter = sp.alter, octave = sp.octave }
    if add then
      if not (last and last.event and D.find(sc, last.event)) then return false end
      note.id = D.id(sc, "n")
      view.join_chord(sc, last.event, note)
      done = { step = sp.step, event = last.event, pitch = sp.pitch }
      return
    end
    local cur = O.cursor(sc)
    cur.voice = view.voice or 1
    local seq = D.sequence(sc, cur.staff, cur.voice)
    local target
    for _, x in ipairs(seq) do
      if not target and x.ev.kind == "chord" and not x.ev.grace and x.e > cur.t then target = x end
    end
    if not target then
      paw.notify("no more notes to re-pitch in this voice", "warn")
      return false
    end
    local ev = target.ev
    local keep = ev.notes[1]
    for k = #ev.notes, 2, -1 do
      local n = ev.notes[k]
      for _, c in ipairs(D.tied_on(sc, cur.staff, cur.voice, n.id)) do
        D.remove_note(sc, c.note.id)
      end
      D.remove_note(sc, n.id)
    end
    D.respell(sc, keep.id, note.step, note.alter, note.octave)
    local links = view.chain(sc, ev.id)
    local tail = links[#links]
    local f = D.frame(sc)
    view.beat = O.beat(sc, f.starts[tail.mi] + tail.at + D.length(tail.ev))
    done = { step = sp.step, event = ev.id, pitch = sp.pitch }
  end)
  if done then
    view.last = { id = nil, step = done.step, pitch = done.pitch, beat = view.beat, event = done.event }
    view.step = done.step
    view:audition(done.pitch)
    api.ui_redraw()
  end
end

--- Put a grace note (`kind` acciaccatura or appoggiatura, `sp` a model
--- spelling) before the chord of a voice starting `at` ticks into measure
--- `mi`. Returns whether there was one; a grace note leads only to a note.
function P.put_grace(sc, mi, staff, v, at, kind, sp)
  local entry = D.voice(sc.measures[mi], staff, v)
  local x = 0
  for i, ev in ipairs(entry and entry.events or {}) do
    if x == at and not ev.grace then
      if ev.kind ~= "chord" then return false end
      table.insert(
        entry.events,
        i,
        {
          id = D.id(sc, "e"),
          kind = "chord",
          grace = kind,
          dur = { 1, 8 },
          dots = 0,
          notes = { { id = D.id(sc, "n"), step = sp.letter, alter = sp.alter, octave = sp.octave } },
        }
      )
      D.touch(sc, mi)
      return true
    end
    x = x + D.length(ev)
  end
  return false
end

--- A grace note (`view.grace`: acciaccatura or appoggiatura) of a letter
--- before the note at the cursor, in the voice entered; the cursor stays.
--- Where no note starts yet, it goes in with the note entered there next.
function P.grace_enter(letter)
  local fifths = key()
  local kind = view.grace
  view.grace = nil
  local from = view.last and view.last.step or view.step
  local sp = key_spelling(P.nearest(letter, from), fifths)
  local ok = P.on(nil, function(sc)
    local mi, at = view.where(sc, view.beat)
    D.ensure(sc, mi)
    if P.put_grace(sc, mi, view:staff_id(sc, sp.pitch), view.voice or 1, at, kind, sp) then return true end
    view.pending_grace = { kind = kind, sp = sp, beat = view.beat }
    paw.notify("the " .. kind .. " goes in before the note entered here next")
    return false
  end)
  if ok ~= nil then
    view.last = { step = sp.step, pitch = sp.pitch, beat = view.beat }
    view.step = sp.step
    view:audition(sp.pitch)
  end
end

return P
