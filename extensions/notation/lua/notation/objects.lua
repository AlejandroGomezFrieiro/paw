-- Text objects and motions over the written score: notes, chords, beats,
-- bars, phrases, voices, staves, tuplets and slurs, found in the score
-- (`notation.doc`) rather than among notes in time. A text object gives
-- the keymap a region in the shape it takes (`c0`, `c1` in clip beats,
-- `r0`, `r1` pitches) with `score`, a selection of the score:
--
--   sel = { from, to,              ticks from measure 1, the end not included
--           staff?, voice?,        one staff (its id) and voice, or every one
--           events?,               { [event id] = true }: these and no others
--           notes?, pitches?,      some notes of the chords: by id, or { low, high }
--           measures?,             { first, last }: whole measures, barlines and all
--           slur? }                the id of a slur mark that goes with them
--
-- A region without `score` (a motion, a visual selection) is read as a
-- selection by `O.of_region`. The operators (`notation.operators`) work on
-- selections, so each of them works on every object and motion.
local view = require("notation")
local model = require("notation.model")
local D = require("notation.doc")
local midi = require("notation.midi")

local O = {}
local EPS = 1e-6

-- The score and the cursor --------------------------------------------------------------------

--- The open clip's score, to read: what its notes are written as, with the
--- ids an edit of it finds.
function O.score()
  local clip = view:clip()
  if not clip then return nil end
  return view.score_of(clip:get()), clip
end

--- Ticks from measure 1 of a beat of the clip, and back.
function O.ticks(sc, beat) return D.from_beats(beat) - D.origin(sc) end
function O.beat(sc, t) return (D.origin(sc) + t) / D.Q end

--- Where the cursor is in a score: `{ t, staff (id), staff_index, voice,
--- step }`; the staff and voice of the note under it, else of its line
--- and the voice chosen for entering.
function O.cursor(sc)
  local layout = view:layout()
  local ev, n = view:event_at(view.beat, view.step)
  local si = (ev and n and ev.staff) or view:staff_of_step(view.step, layout)
  local st = sc.staves[si] or sc.staves[1]
  return {
    t = math.max(0, O.ticks(sc, view.beat)),
    staff = st.id,
    staff_index = D.staff_index(sc, st.id),
    voice = (ev and n and ev.voice) or view.voice or 1,
    step = view.step,
  }
end

--- The item of a voice (`D.sequence`'s) sounding at `t`, not a grace note.
function O.item_at(sc, staff, v, t)
  local seq = D.sequence(sc, staff, v)
  for i, it in ipairs(seq) do
    if it.s <= t and t < it.e then return it, i, seq end
  end
  return nil, nil, seq
end

--- The chord under the cursor and the note of it on the cursor's line.
function O.chord_here(sc, cur)
  cur = cur or O.cursor(sc)
  local it, i, seq = O.item_at(sc, cur.staff, cur.voice, cur.t)
  if not (it and it.ev.kind == "chord") then return nil, nil, cur end
  local note
  for _, n in ipairs(it.ev.notes) do
    if D.diatonic(n) == cur.step then note = n end
  end
  return it, note, cur, i, seq
end

--- The ids of the notes tied on from a note, and of those tied into it.
local function tie_chain(sc, staff, v, nid)
  local seq = D.sequence(sc, staff, v)
  local ids = { [nid] = true }
  -- Back to the note the chain starts on.
  local head = nid
  local found = true
  while found do
    found = false
    for i, it in ipairs(seq) do
      for _, n in ipairs(it.ev.notes or {}) do
        if n.id == head and i > 1 then
          local before = seq[i - 1]
          if before.ev.kind == "chord" and before.e == it.s then
            for _, b in ipairs(before.ev.notes) do
              if b.tie and D.pitch(b) == D.pitch(n) then
                head, found = b.id, true
              end
            end
          end
        end
      end
    end
  end
  ids[head] = true
  for _, c in ipairs(D.tied_on(sc, staff, v, head)) do
    ids[c.note.id] = true
  end
  return ids
end
O.tie_chain = tie_chain

--- The ids of the notes of a voice that a tie from the chord before continues.
function O.continuations(sc, staff, v)
  local out = {}
  local seq = D.sequence(sc, staff, v)
  for i = 2, #seq do
    local a, b = seq[i - 1], seq[i]
    if a.ev.kind == "chord" and b.ev.kind == "chord" and not b.ev.grace and a.e == b.s then
      for _, n in ipairs(a.ev.notes) do
        if n.tie then
          for _, o in ipairs(b.ev.notes) do
            if D.pitch(o) == D.pitch(n) then out[o.id] = true end
          end
        end
      end
    end
  end
  return out
end

-- Selections and regions ----------------------------------------------------------------------

--- The keymap's region for a selection.
function O.region(sc, sel)
  local pitch = view:cursor_pitch()
  return {
    view = "notation",
    kind = "char",
    r0 = pitch,
    r1 = pitch,
    c0 = math.max(0, O.beat(sc, sel.from)),
    c1 = O.beat(sc, sel.to),
    score = sel,
  }
end

--- The selection a region names: its own, else the stretch of time it
--- covers: a motion's in the cursor's staff and voice, a selection's in
--- every one (its rows, for a block or whole rows). An `f` or `t` motion
--- reaches over the note it found.
function O.of_region(sc, region)
  if region.score then return region.score end
  if
    region.visual
    and O.visual
    and math.abs(O.visual.c0 - region.c0) < EPS
    and math.abs(O.visual.c1 - region.c1) < EPS
  then
    return O.visual.sel
  end
  local f = D.frame(sc)
  if region.kind == "line" then
    return {
      from = 0,
      to = math.max(f.finish, O.ticks(sc, view:clip() and view:clip():get().length or 0)),
      pitches = { region.r0, region.r1 },
    }
  end
  local c1 = region.c1
  local reach = O.reach
  if not region.visual and reach and math.abs(reach.at - c1) < EPS then c1 = reach.to end
  local sel = { from = math.max(0, O.ticks(sc, region.c0)), to = O.ticks(sc, c1) }
  if region.kind == "block" then
    sel.pitches = { region.r0, region.r1 }
  elseif not region.visual then
    local cur = O.cursor(sc)
    sel.staff, sel.voice = cur.staff, cur.voice
  end
  return sel
end

--- The events (and notes) a selection holds, in each staff and voice in
--- time order: `{ ev, mi, staff, voice, s, e, notes, whole }`, where
--- `notes` are the chord's notes chosen and `whole` says they are all of
--- them. Rests come too, unless notes are chosen by id or pitch.
function O.items(sc, sel)
  local out = {}
  local by_note = sel.notes or sel.pitches
  for _, st in ipairs(sc.staves) do
    if not sel.staff or sel.staff == st.id then
      for v = 1, 4 do
        if not sel.voice or sel.voice == v then
          for _, it in ipairs(D.sequence(sc, st.id, v)) do
            local inside
            -- Chosen events or notes are chosen wherever they are.
            if sel.events then
              inside = sel.events[it.ev.id]
            else
              inside = sel.notes ~= nil or (it.s >= sel.from and it.s < sel.to)
            end
            if inside then
              local notes
              if it.ev.kind == "chord" then
                notes = {}
                for _, n in ipairs(it.ev.notes) do
                  local p = D.pitch(n)
                  if
                    (not sel.notes or sel.notes[n.id])
                    and (not sel.pitches or (p >= sel.pitches[1] and p <= sel.pitches[2]))
                  then
                    notes[#notes + 1] = n
                  end
                end
              end
              if not ((it.ev.kind == "rest" and by_note) or (notes and #notes == 0)) then
                out[#out + 1] = {
                  ev = it.ev,
                  mi = it.mi,
                  staff = st.id,
                  voice = v,
                  s = it.s,
                  e = it.e,
                  notes = notes,
                  whole = notes ~= nil and #notes == #it.ev.notes,
                }
              end
            end
          end
        end
      end
    end
  end
  return out
end

--- The notes of a selection whose pitch is their own: not those a tie
--- continues from a note that is chosen too. `{ note, item }` each.
function O.heads(sc, sel)
  local items = O.items(sc, sel)
  local chosen, conts = {}, {}
  for _, it in ipairs(items) do
    for _, n in ipairs(it.notes or {}) do
      chosen[n.id] = true
    end
    local key = it.staff .. ":" .. it.voice
    conts[key] = conts[key] or O.continuations(sc, it.staff, it.voice)
  end
  local out = {}
  for _, it in ipairs(items) do
    local cont = conts[it.staff .. ":" .. it.voice]
    for _, n in ipairs(it.notes or {}) do
      if not cont[n.id] then
        out[#out + 1] = { note = n, item = it }
      else
        -- A continuation whose head is not chosen stands for itself.
        local head_chosen = false
        for id in pairs(tie_chain(sc, it.staff, it.voice, n.id)) do
          if id ~= n.id and chosen[id] then head_chosen = true end
        end
        if not head_chosen then out[#out + 1] = { note = n, item = it } end
      end
    end
  end
  return out
end

-- Text objects ----------------------------------------------------------------------------------

local function span_of(items)
  local a, b = math.huge, -math.huge
  for _, it in ipairs(items) do
    a, b = math.min(a, it.s), math.max(b, it.e)
  end
  return a, b
end

--- The written note under the cursor; `around` with every note its ties join.
function O.note(sc, around)
  local it, note, cur = O.chord_here(sc)
  if not note then return nil end
  local ids = around and tie_chain(sc, cur.staff, cur.voice, note.id) or { [note.id] = true }
  local sel = { from = it.s, to = it.e, staff = cur.staff, voice = cur.voice, notes = ids }
  if around then
    local items = O.items(sc, sel)
    sel.from, sel.to = span_of(items)
  end
  return sel
end

--- The chord under the cursor, and `count - 1` after it in its voice;
--- `around` with the grace notes before it and the chords its ties join.
function O.chord(sc, around, count)
  local it, _, cur, i, seq = O.chord_here(sc)
  if not it then return nil end
  local events, last = {}, it
  local k, taken = i, 0
  while seq[k] and taken < (count or 1) do
    local x = seq[k]
    if x.ev.kind == "chord" and not x.ev.grace then
      events[x.ev.id] = true
      last = x
      taken = taken + 1
      if around then
        local j = k - 1
        while seq[j] and seq[j].ev.grace do
          events[seq[j].ev.id] = true
          j = j - 1
        end
        for _, link in ipairs(view.chain(sc, x.ev.id)) do
          events[link.ev.id] = true
          local f = D.frame(sc)
          local e = f.starts[link.mi] + link.at + D.length(link.ev)
          if e > last.e then last = { e = e } end
        end
      end
    end
    k = k + 1
  end
  return { from = it.s, to = last.e, staff = cur.staff, voice = cur.voice, events = events }
end

--- The beat under the cursor and `count - 1` after it: in the cursor's
--- voice, or (`around`) in every staff and voice.
function O.beat_of(sc, around, count)
  local cur = O.cursor(sc)
  local f = D.frame(sc)
  local mi, at = D.locate(sc, cur.t)
  if mi > f.count then return nil end
  local meter = f.meters[mi]
  local beats = model.score.beats_of({ start = 0, num = meter[1], den = meter[2] })
  for k, b in ipairs(beats) do
    local s, e = D.from_beats(b.s), D.from_beats(b.e)
    if at >= s and at < e then
      local last = beats[math.min(#beats, k + (count or 1) - 1)]
      local sel = { from = f.starts[mi] + s, to = f.starts[mi] + D.from_beats(last.e) }
      if not around then
        sel.staff, sel.voice = cur.staff, cur.voice
      end
      return sel
    end
  end
end

--- The cursor's bar and `count - 1` after it; `around` the measures
--- themselves, which deleting takes out and pasting puts in.
function O.bar(sc, around, count)
  local cur = O.cursor(sc)
  local f = D.frame(sc)
  local mi = D.locate(sc, cur.t)
  if mi > f.count then return nil end
  local last = math.min(f.count, mi + (count or 1) - 1)
  local sel = { from = f.starts[mi], to = f.starts[last] + f.lengths[last] }
  if around then sel.measures = { mi, last } end
  return sel
end

--- The slur over the cursor's chord on its staff: the mark and its span.
local function slur_here(sc, cur)
  local f = D.frame(sc)
  local it = O.chord_here(sc, cur)
  local t = it and it.s or cur.t
  for _, mk in ipairs(sc.marks or {}) do
    if mk.kind == "slur" and mk.staff == cur.staff then
      local s, e = midi.at_of(sc, f, mk.from), midi.at_of(sc, f, mk.to)
      if s and e and t >= s and t <= e then return mk, s, e end
    end
  end
end

--- The notes under the slur the cursor is under; `around` the slur too.
function O.slur(sc, around)
  local cur = O.cursor(sc)
  local mk, s, e = slur_here(sc, cur)
  if not mk then return nil end
  local sel = { from = s, to = e + 1, staff = cur.staff, voice = cur.voice }
  local items = O.items(sc, sel)
  if #items > 0 then
    sel.from, sel.to = span_of(items)
  end
  if around then sel.slur = mk.id end
  return sel
end

--- The phrase the cursor is in, in its voice: the notes under its slur,
--- else the notes between the rests before and after; `around` with the
--- rests after it. `count` phrases.
function O.phrase(sc, around, count)
  local cur = O.cursor(sc)
  local by_slur = O.slur(sc, false)
  if by_slur and not around and (count or 1) == 1 then return by_slur end
  local seq = D.sequence(sc, cur.staff, cur.voice)
  local k
  for i, it in ipairs(seq) do
    if it.s <= cur.t and cur.t < it.e then k = i end
  end
  if not k then return nil end
  -- From a rest: the phrase after it.
  while seq[k] and seq[k].ev.kind == "rest" do
    k = k + 1
  end
  if not seq[k] then return nil end
  local a = k
  while seq[a - 1] and seq[a - 1].ev.kind == "chord" do
    a = a - 1
  end
  local function run_end(i)
    while seq[i + 1] and seq[i + 1].ev.kind == "chord" do
      i = i + 1
    end
    return i
  end
  local function rests_end(i)
    while seq[i + 1] and seq[i + 1].ev.kind == "rest" do
      i = i + 1
    end
    return i
  end
  local b = run_end(k)
  for _ = 2, count or 1 do
    local r = rests_end(b)
    if not seq[r + 1] then break end
    b = run_end(r + 1)
  end
  if around then b = rests_end(b) end
  return { from = seq[a].s, to = seq[b].e, staff = cur.staff, voice = cur.voice }
end

--- The cursor's voice in its bar and `count - 1` after; `around` the voice
--- through the whole score.
function O.voice(sc, around, count)
  local cur = O.cursor(sc)
  local sel = around and { from = 0, to = math.huge } or O.bar(sc, false, count)
  if not sel then return nil end
  sel.staff, sel.voice = cur.staff, cur.voice
  if around then sel.to = D.frame(sc).finish end
  return sel
end

--- Every voice of the cursor's staff in its bar and `count - 1` after;
--- `around` the staff through the whole score.
function O.staff(sc, around, count)
  local cur = O.cursor(sc)
  local sel = around and { from = 0, to = D.frame(sc).finish } or O.bar(sc, false, count)
  if not sel then return nil end
  sel.staff = cur.staff
  return sel
end

--- The tuplet the cursor is in: its notes, or (`around`) all of it, rests too.
function O.tuplet(sc, around)
  local cur = O.cursor(sc)
  local it = O.item_at(sc, cur.staff, cur.voice, cur.t)
  local tp = it and it.ev.tuplet
  if not tp then return nil end
  local events, a, b = {}, math.huge, -math.huge
  for _, x in ipairs(D.sequence(sc, cur.staff, cur.voice)) do
    if x.ev.tuplet and x.ev.tuplet.id == tp.id then
      a, b = math.min(a, x.s), math.max(b, x.e)
      if around or x.ev.kind == "chord" then events[x.ev.id] = true end
    end
  end
  local sel = { from = a, to = b, staff = cur.staff, voice = cur.voice }
  if not around then sel.events = events end
  return sel
end

--- The whole score, every staff and voice.
function O.all(sc)
  local f = D.frame(sc)
  return { from = 0, to = math.max(f.finish, 1) }
end

-- Motions ----------------------------------------------------------------------------------------

--- Every chord of the cursor's staff and voice from the score, in order.
local function chords(sc, cur)
  local out = {}
  for _, it in ipairs(D.sequence(sc, cur.staff, cur.voice)) do
    if it.ev.kind == "chord" and not it.ev.grace then out[#out + 1] = it end
  end
  return out
end

--- The `count`th chord of the cursor's voice after it (`dir` 1) or before
--- it (-1) with a note of a letter (0 C .. 6 B): the item and the note.
function O.find_letter(sc, letter, dir, count)
  local cur = O.cursor(sc)
  local list = chords(sc, cur)
  local found, note
  local left = count or 1
  local first, last, step = 1, #list, 1
  if dir < 0 then
    first, last, step = #list, 1, -1
  end
  for i = first, last, step do
    local it = list[i]
    if (dir > 0 and it.s > cur.t) or (dir < 0 and it.s < cur.t) then
      local hit
      for _, n in ipairs(it.ev.notes) do
        if
          n.step == letter and (not hit or math.abs(D.diatonic(n) - cur.step) < math.abs(D.diatonic(hit) - cur.step))
        then
          hit = n
        end
      end
      if hit then
        left = left - 1
        if left == 0 then
          found, note = it, hit
          break
        end
      end
    end
  end
  return found, note, list
end

--- The chord before or after an item among `list`.
function O.neighbour(list, it, dir)
  for i, x in ipairs(list) do
    if x == it then return list[i + dir] end
  end
end

--- The start of the `count`th phrase after (`dir` 1) or before (-1) the
--- cursor in its voice: a chord after a rest, or the first.
function O.phrase_start(sc, dir, count)
  local cur = O.cursor(sc)
  local seq = D.sequence(sc, cur.staff, cur.voice)
  local starts = {}
  for i, it in ipairs(seq) do
    if it.ev.kind == "chord" and not it.ev.grace and (i == 1 or seq[i - 1].ev.kind == "rest") then
      starts[#starts + 1] = it
    end
  end
  local left, found = count or 1, nil
  if dir > 0 then
    for _, it in ipairs(starts) do
      if it.s > cur.t then
        left = left - 1
        if left == 0 then
          found = it
          break
        end
      end
    end
  else
    for i = #starts, 1, -1 do
      if starts[i].s < cur.t then
        left = left - 1
        if left == 0 then
          found = starts[i]
          break
        end
      end
    end
  end
  return found
end

--- The staves and voices that have music, in order: `{ staff, voice }`.
function O.voices(sc)
  local out = {}
  for _, st in ipairs(sc.staves) do
    for v = 1, 4 do
      local has = v == 1
      for _, m in ipairs(sc.measures) do
        local e = D.voice(m, st.id, v)
        if e and #e.events > 0 then has = true end
      end
      if has then out[#out + 1] = { staff = st.id, voice = v } end
    end
  end
  return out
end

return O
