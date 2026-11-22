-- The full score and its parts: every track with MIDI as an instrument,
-- in orchestral order, and each instrument's part to play from.
--
-- The score has every instrument's staves in the order of an orchestra
-- (woodwinds, brass, percussion, keyboards and harp, voices, strings: by
-- the group a track is in, `paw.groups`, else by its name), a bracket over
-- each family with the barlines through it, a brace over an instrument of
-- two staves, the names in full on the first system and short after. It
-- is written at concert pitch. Condensed (`:part.condense`), two players
-- of an instrument share a staff: `a2` where they play the same, `1.` or
-- `2.` where one rests, two voices where they part.
--
-- A part is one instrument written for its player: transposed (a track's
-- `meta.notation.transpose`, or "in Bb" in its name), bars of rest as
-- multi-measure rests, the score's rehearsal marks and tempo marks, cues
-- from other instruments (`:part.cue`), systems that end in rests where a
-- page turns, and system breaks of its own. What a part keeps is the
-- track's `meta.notation.part`; what it shows is made from the MIDI each
-- time (`notation.files`' parts, one aligned score per track), so a part
-- is never out of date and never owns music of its own.
local api = paw.api
local util = paw.util
local view = require("notation")
local D = require("notation.doc")
local L = require("notation.layout")

local floor, abs = math.floor, math.abs
local EPS = 1e-6

local P = {}

-- Instruments ------------------------------------------------------------------------------------

--- The families in score order.
P.FAMILIES = { "woodwinds", "brass", "percussion", "keyboards", "voices", "strings" }

--- The words that name an instrument, by family, in score order within
--- it, with their short names. The longest word found in a name decides
--- ("bass clarinet" before "clarinet", "english horn" before "horn").
P.WORDS = {
  woodwinds = {
    { "piccolo", "Picc." },
    { "flute", "Fl." },
    { "alto flute", "A. Fl." },
    { "oboe", "Ob." },
    { "english horn", "E. Hn." },
    { "cor anglais", "C. A." },
    { "clarinet", "Cl." },
    { "bass clarinet", "B. Cl." },
    { "bassoon", "Bsn." },
    { "contrabassoon", "Cbsn." },
    { "soprano sax", "S. Sax." },
    { "alto sax", "A. Sax." },
    { "tenor sax", "T. Sax." },
    { "baritone sax", "Bar. Sax." },
    { "saxophone", "Sax." },
    { "recorder", "Rec." },
    { "woodwinds", "Ww." },
    { "winds", "Wi." },
  },
  brass = {
    { "horn", "Hn." },
    { "french horn", "Hn." },
    { "trumpet", "Tpt." },
    { "cornet", "Cnt." },
    { "flugelhorn", "Flg." },
    { "trombone", "Tbn." },
    { "bass trombone", "B. Tbn." },
    { "euphonium", "Euph." },
    { "tuba", "Tba." },
    { "brass", "Br." },
  },
  percussion = {
    { "timpani", "Timp." },
    { "percussion", "Perc." },
    { "drums", "Dr." },
    { "drum", "Dr." },
    { "snare", "S. D." },
    { "cymbal", "Cym." },
    { "triangle", "Tri." },
    { "glockenspiel", "Glock." },
    { "xylophone", "Xyl." },
    { "vibraphone", "Vib." },
    { "marimba", "Mar." },
    { "tubular bells", "T. B." },
  },
  keyboards = {
    { "harp", "Hp." },
    { "guitar", "Gtr." },
    { "bass guitar", "B. Gtr." },
    { "celesta", "Cel." },
    { "piano", "Pno." },
    { "harpsichord", "Hpd." },
    { "organ", "Org." },
    { "keyboard", "Kbd." },
    { "synth", "Syn." },
  },
  voices = {
    { "soprano", "S." },
    { "mezzo", "Mez." },
    { "alto", "A." },
    { "tenor", "T." },
    { "baritone", "Bar." },
    { "voice", "V." },
    { "vocals", "Voc." },
    { "choir", "Ch." },
    { "chorus", "Ch." },
  },
  strings = {
    { "violin", "Vln." },
    { "viola", "Vla." },
    { "violoncello", "Vc." },
    { "cello", "Vc." },
    { "double bass", "Cb." },
    { "contrabass", "Cb." },
    { "bass", "Cb." },
    { "strings", "Str." },
  },
}

--- The family, the place in it and the short name of a name, or nil.
function P.family(name)
  local low = tostring(name or ""):lower()
  local best
  for fi, family in ipairs(P.FAMILIES) do
    for rank, w in ipairs(P.WORDS[family]) do
      local at = low:find(w[1], 1, true)
      if at and (not best or #w[1] > #best.word) then best = { family = fi, rank = rank, word = w[1], short = w[2] } end
    end
  end
  return best
end

--- A short name for an instrument: its family word's abbreviation with
--- the player's number, else the name's first letters.
function P.short(name)
  name = tostring(name or "")
  local found = P.family(name)
  local number = name:match("%s+(%d+)%s*$") or name:match("%s+([IV]+)%s*$")
  if found then return found.short .. (number and (" " .. number) or "") end
  local word = name:match("^%s*(%S+)") or ""
  if #word <= 4 then return name end
  return word:sub(1, 3) .. "." .. (number and (" " .. number) or "")
end

--- What a track keeps for its part: `meta.notation.part`.
function P.own(track_id)
  local ok, t = pcall(api.track_get, track_id)
  local meta = ok and type(t.meta) == "table" and type(t.meta.notation) == "table" and t.meta.notation or {}
  return type(meta.part) == "table" and meta.part or {}, meta
end

--- Keep something for a track's part: `fn(part, notation)` changes copies
--- of `meta.notation.part` and `meta.notation`, written back as one edit.
function P.keep(track_id, fn)
  local t = api.track_get(track_id)
  local meta = util.merge(t.meta or {}, {})
  local own = type(meta.notation) == "table" and util.merge(meta.notation, {}) or {}
  local part = type(own.part) == "table" and util.merge(own.part, {}) or {}
  fn(part, own)
  own.part = next(part) and part or nil
  meta.notation = next(own) and own or nil
  api.track_set(track_id, "meta", meta)
  api.undo_checkpoint()
end

-- Transposition ----------------------------------------------------------------------------------

local LETTER = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }
local PC = { [0] = 0, 2, 4, 5, 7, 9, 11 }
local SIGNS = { { "♭", -1, "b" }, { "♯", 1, "#" }, { "b", -1, "b" }, { "#", 1, "#" } }

--- A key's letter and sign at the start of `text`: the letter, the
--- sign's alteration and how it is typed, and what follows.
local function key_of(text)
  local letter, rest = tostring(text):match("^%s*([A-Ga-g])(.*)$")
  if not letter then return nil end
  for _, sign in ipairs(SIGNS) do
    if rest:sub(1, #sign[1]) == sign[1] then return letter:upper(), sign[2], sign[3], rest:sub(#sign[1] + 1) end
  end
  return letter:upper(), 0, "", rest
end

--- The fifths an interval moves a key by: `f` with `4f` steps and `7f`
--- semitones, the nearest to none.
local function fifths_of(steps, semis)
  local best
  for f = -11, 11 do
    if (4 * f - steps) % 7 == 0 and (7 * f - semis) % 12 == 0 and (not best or abs(f) < abs(best)) then best = f end
  end
  return best or 0
end

--- The interval a part is written at from how it sounds, `{ steps,
--- semis, fifths, name }`, from what a track says: `Bb` (an instrument in
--- B flat, sounding that far below C: written a major second up), `Eb up`
--- (sounding above: an E flat clarinet, written a minor third down),
--- `octave` after either for an octave more (`Bb octave`, a tenor sax;
--- `C up octave`, a piccolo), `off`. Nil for none.
function P.interval(spec)
  local letter, alter, acc, rest = key_of(spec or "")
  if not letter then return nil end
  rest = rest:match("^%s*(.-)%s*$")
  local l = LETTER[letter]
  local pc = (PC[l] + alter) % 12
  local up = rest:find("up", 1, true) ~= nil
  local steps, semis
  if up then
    steps, semis = -l, -pc
  else
    steps, semis = (7 - l) % 7, (12 - pc) % 12
  end
  if rest:find("octave", 1, true) then
    steps, semis = steps + (up and -7 or 7), semis + (up and -12 or 12)
  end
  if steps == 0 and semis == 0 then return nil end
  return {
    steps = steps,
    semis = semis,
    fifths = fifths_of(steps, semis),
    name = letter .. acc .. (rest ~= "" and (" " .. rest) or ""),
  }
end

--- The interval a track's part is written at: its `meta.notation.transpose`,
--- else "in Bb" (or A, F, Eb...) in its name.
function P.transposition(track_id)
  local _, meta = P.own(track_id)
  if meta.transpose == "off" then return nil end
  if meta.transpose then return P.interval(meta.transpose) end
  local ok, t = pcall(api.track_get, track_id)
  local after = ok and tostring(t.name):match("%f[%a]in%s+([A-G].*)$")
  if not after then return nil end
  local letter, _, acc, rest = key_of(after)
  if rest:match("^%w") then return nil end
  return P.interval(letter .. acc)
end

--- The steps, semitones and fifths a part is written at from a key of
--- `fifths`: the interval's, or the enharmonic interval where the key would
--- pass seven sharps or flats (a diminished third for a major second).
function P.written(iv, fifths)
  local steps, semis, f = iv.steps, iv.semis, iv.fifths
  local new = (fifths or 0) + f
  if abs(new) > 7 then
    f = f - 12 * (new > 0 and 1 or -1)
    local delta = (4 * f - steps) % 7
    if delta > 3 then delta = delta - 7 end
    steps = steps + delta
  end
  return steps, semis, f
end

--- A score written at an interval (in place): each note moved by its
--- steps and spelled to sound its semitones away, and the keys moved by
--- its fifths (see `P.written`). Returns the fifths the keys moved by.
function P.transpose_score(sc, iv, fifths)
  local steps, semis, f = P.written(iv, fifths)
  local function move(n)
    local d = D.diatonic(n) + steps
    local pitch = D.pitch(n) + semis
    n.octave, n.step = floor(d / 7) - 1, d % 7
    n.alter = pitch - D.pitch({ octave = n.octave, step = n.step, alter = 0 })
  end
  for mi, m in ipairs(sc.measures) do
    for _, entry in ipairs(m.voices or {}) do
      for _, ev in ipairs(entry.events) do
        for _, n in ipairs(ev.notes or {}) do
          move(n)
        end
      end
    end
    if m.key then m.key = { fifths = m.key.fifths + f } end
    D.touch(sc, mi)
  end
  return f
end

-- The instruments and their scores ---------------------------------------------------------------

--- Every instrument of the score in its order: each track with a MIDI
--- clip with notes, `{ id, track, clips, clip, name, short, family, rank,
--- order, transpose, group }`, `clips` its MIDI clips with notes in the
--- order they start, `clip` the first. `opts.tracks` (ids) keeps those
--- tracks alone; `opts.from`, `opts.to` (beats of the song) take each
--- track's clips that reach into that stretch.
function P.instruments(opts)
  opts = opts or {}
  local wanted
  if opts.tracks then
    wanted = {}
    for _, id in ipairs(opts.tracks) do
      wanted[id] = true
    end
  end
  local out = {}
  for order, track in ipairs(paw.tracks()) do
    local clips = {}
    if not wanted or wanted[track.id] then
      for _, c in ipairs(track:clips()) do
        local g = c:get()
        local inside = not opts.from or (g.start < opts.to and g.start + g.length > opts.from)
        if g.kind == "midi" and g.note_count > 0 and inside then clips[#clips + 1] = c end
      end
      table.sort(clips, function(a, b) return a:get().start < b:get().start end)
    end
    local clip = clips[1]
    if clip then
      local t = track:get()
      local own = P.own(t.id)
      local group = paw.groups and paw.groups.of(t.id)
      local found = P.family(t.name)
      -- A track in a group named for a family ("Strings", "Flutes") is of that family.
      local by_group = group and P.family(api.track_get(group, "name"))
      local family = (by_group and by_group.family) or (found and found.family) or #P.FAMILIES + 1
      out[#out + 1] = {
        id = t.id,
        track = track,
        clip = clip,
        clips = clips,
        name = own.name or t.name,
        short = own.short or P.short(t.name),
        family = family,
        rank = found and found.family == family and found.rank or 0,
        order = order,
        transpose = P.transposition(t.id),
        group = group,
      }
    end
  end
  table.sort(out, function(a, b)
    if a.family ~= b.family then return a.family < b.family end
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.order < b.order
  end)
  return out
end

--- The instrument of a track, from a list, or nil.
local function find(list, id)
  for i, e in ipairs(list) do
    if e.id == id then return e, i end
  end
end

--- A track's clips written on staves of one shape: where its clips would
--- choose different clefs (one high, one low), all of them on a grand
--- staff (`view.track_clefs`, which the view's own layouts take too).
local function one_clef(e)
  view.track_clefs[e.id] = nil
  if #e.clips < 2 then return end
  local seen
  for _, clip in ipairs(e.clips) do
    local sc = view.score_of(clip:get())
    local shape = {}
    for k, st in ipairs(sc.staves) do
      shape[k] = tostring(st.clef)
    end
    shape = table.concat(shape, "+")
    if seen and shape ~= seen then
      view.track_clefs[e.id] = "grand"
      return
    end
    seen = shape
  end
end

--- Prefix the ids of a measure's events (and their tuplets'), so that
--- measures of several clips' scores stand together in one.
local function own_ids(m, prefix)
  m.id = prefix .. m.id
  for _, entry in ipairs(m.voices or {}) do
    for _, ev in ipairs(entry.events) do
      ev.id = prefix .. ev.id
      if ev.tuplet then ev.tuplet = util.merge(ev.tuplet, { id = prefix .. tostring(ev.tuplet.id) }) end
    end
  end
end

--- One score of a track's clips, each aligned on the timeline (their
--- `notation.files` parts): each measure from the clip that plays then (the
--- one starting latest, where clips overlap), with its marks; a measure no
--- clip plays is a bar of rest. `owners[mi]` is the clip of measure mi.
local function compose(group, first)
  local base = group[1]
  local owners = {}
  local f = D.frame(base.score)
  for mi in ipairs(base.score.measures) do
    local at = first + (D.origin(base.score) + f.starts[mi]) / D.Q
    for k, p in ipairs(group) do
      local c = p.clip:get()
      if at >= c.start - EPS and at < c.start + c.length - EPS then owners[mi] = k end
    end
  end
  if #group > 1 then
    local sc = base.score
    local taken, marks, index = {}, {}, {}
    for mi, m in ipairs(sc.measures) do
      index[m.id] = mi
    end
    for _, mk in ipairs(sc.marks or {}) do
      local mi = mk.from and index[mk.from.measure]
      if not mi or (owners[mi] or 1) == 1 then marks[#marks + 1] = mk end
    end
    for mi, k in pairs(owners) do
      if k > 1 then
        local src = group[k].score
        local m = D.copy(src.measures[mi])
        local old = m.id
        own_ids(m, "c" .. k .. ".")
        sc.measures[mi] = m
        taken[old .. "@" .. k] = m.id
      end
    end
    -- The marks of the measures taken, pointing at them under their new ids.
    for k = 2, #group do
      for _, mk in ipairs(group[k].score.marks or {}) do
        local from = mk.from and taken[tostring(mk.from.measure) .. "@" .. k]
        if from then
          local copy = D.copy(mk)
          copy.id = "c" .. k .. "." .. tostring(mk.id)
          copy.from.measure = from
          if copy.from.event then copy.from.event = "c" .. k .. "." .. copy.from.event end
          if copy.to and copy.to.measure then
            copy.to.measure = taken[tostring(copy.to.measure) .. "@" .. k] or copy.to.measure
            if copy.to.event then copy.to.event = "c" .. k .. "." .. copy.to.event end
          end
          marks[#marks + 1] = copy
        end
      end
    end
    sc.marks = marks
    sc._frame = nil
  end
  local out = base
  out.owners = {}
  for mi in ipairs(base.score.measures) do
    out.owners[mi] = group[owners[mi] or 1].clip
  end
  return out
end

--- Each instrument's score, all on one timeline and as many bars long
--- (`notation.files`' parts), made of every clip of its track (see
--- `compose`): concert pitch, or as each is written with `written`. Each
--- score is a copy, its measures laid out afresh.
local function scores(list, written)
  local clips, of = {}, {}
  for i, e in ipairs(list) do
    one_clef(e)
    for _, c in ipairs(e.clips) do
      clips[#clips + 1] = c
      of[#clips] = i
    end
  end
  local all = view.files.parts(clips)
  local first = math.huge
  for _, p in ipairs(all) do
    first = math.min(first, p.beat)
  end
  local groups = {}
  for k, p in ipairs(all) do
    p.clip = clips[k]
    groups[of[k]] = groups[of[k]] or {}
    table.insert(groups[of[k]], p)
  end
  local parts = {}
  for i, group in ipairs(groups) do
    local p = compose(group, first)
    parts[i] = p
    p.entry = list[i]
    for mi in ipairs(p.score.measures) do
      D.touch(p.score, mi)
    end
    if written and list[i].transpose then
      p.fifths = (p.fifths or 0) + P.transpose_score(p.score, list[i].transpose, p.fifths)
    end
  end
  return parts, first
end
P.scores = scores

--- A part's score laid out over the whole timeline, its marks on it. Each
--- written note knows the note that plays it by its place among its
--- clip's notes (`index`), as the view's own layout does, so that a staff
--- of the score is edited as its clip is.
local function lay(p, number)
  local sc = p.score
  local f = D.frame(sc)
  local layout = L.layout(
    sc,
    { length = (D.origin(sc) + f.finish) / D.Q, fifths = p.fifths or 0, grid = paw.opt.notation_grid, number = number }
  )
  -- Each measure's notes are its clip's (`p.owners`), and say so (`clip`).
  local places = {}
  for mi, m in ipairs(layout.measures) do
    local clip = p.owners and p.owners[mi] or p.entry.clip
    local place = places[clip.id]
    if not place then
      place = {}
      for i, n in ipairs(view.notes_of(clip:get())) do
        if n.id then place["n" .. n.id] = i end
      end
      places[clip.id] = place
    end
    for _, evs in ipairs(m.staves) do
      for _, ev in ipairs(evs) do
        ev.clip = clip.id
        for _, n in ipairs(ev.notes or {}) do
          n.index = place[n.head or n.id]
        end
        for _, n in ipairs(ev.grace or {}) do
          n.index = place[n.id]
        end
      end
    end
  end

  view.decorate(layout, p.entry.clip)
  return layout
end

--- The bar number the timeline starts at.
local function first_number(beat)
  local bars = view.bars(beat, 1)
  return bars[1] and bars[1].number or 1
end

--- Rehearsal marks and tempo marks belong to the whole score: what any
--- instrument has is given to every layout, on its top staff.
local function share(layouts)
  for i = 1, #layouts[1].measures do
    local rehearsal, tempos, seen = nil, {}, {}
    for _, lay_ in ipairs(layouts) do
      local mm = lay_.measures[i]
      rehearsal = rehearsal or (mm and mm.rehearsal)
      for _, mk in ipairs(mm and mm.marks or {}) do
        local key = mk.kind == "tempo" and (mk.at .. ":" .. tostring(mk.value))
        if key and not seen[key] then
          seen[key] = true
          tempos[#tempos + 1] = mk
        end
      end
    end
    for _, lay_ in ipairs(layouts) do
      local mm = lay_.measures[i]
      if mm then
        mm.rehearsal = rehearsal
        local list = {}
        for _, mk in ipairs(mm.marks or {}) do
          if mk.kind ~= "tempo" then list[#list + 1] = mk end
        end
        for _, mk in ipairs(tempos) do
          list[#list + 1] = util.merge(mk, { staff = 1 })
        end
        mm.marks = list
      end
    end
  end
end

-- Multi-measure rests and page turns -------------------------------------------------------------

--- Whether a measure is only rests, with nothing but a tempo mark
--- written in it.
local function resting(m)
  for _, mk in ipairs(m.marks or {}) do
    if mk.kind ~= "tempo" then return false end
  end
  for _, evs in ipairs(m.staves) do
    for _, ev in ipairs(evs) do
      if ev.kind ~= "rest" then return false end
    end
  end
  return true
end
P.resting = resting

--- Whether something is written at a measure's start that a player must
--- see: a multi-measure rest starts again there.
local function starts(m)
  return m.rehearsal or m.key_change or m.clef_change or m.repeat_start or m.volta or #(m.marks or {}) > 0
end

--- Bars of rest in a row as one measure that counts them (`multirest`),
--- broken where a rehearsal mark, a tempo mark, a key, clef or time
--- signature, a repeat or another barline is written. Returns the layout,
--- its measures numbered again.
function P.multirests(layout)
  local list, out = layout.measures, {}
  local i, n = 1, #layout.measures
  local function same_meter(a, b) return a.meter.num == b.meter.num and a.meter.den == b.meter.den end
  while i <= n do
    local m = list[i]
    local j = i
    if resting(m) then
      while
        j < n
        and not (list[j].repeat_end or list[j].barline)
        and resting(list[j + 1])
        and not starts(list[j + 1])
        and same_meter(list[j + 1], m)
      do
        j = j + 1
      end
    end
    local index = #out + 1
    if j > i then
      local length = list[j].start + list[j].length - m.start
      local count = j - i + 1
      m.multirest, m.length, m.staves = count, length, {}
      m.repeat_end, m.barline = list[j].repeat_end, list[j].barline
      for k = 1, #layout.staves do
        m.staves[k] = {
          {
            kind = "rest",
            whole = true,
            multirest = count,
            start = m.start,
            length = length,
            base = 4,
            dots = 0,
            voice = 1,
            staff = k,
            measure = index,
          },
        }
      end
    else
      for _, evs in ipairs(m.staves) do
        for _, ev in ipairs(evs) do
          ev.measure = index
        end
      end
    end
    m.index = index
    out[index] = m
    i = j + 1
  end
  layout.measures = out
  return layout
end

-- Cues -------------------------------------------------------------------------------------------

--- Another instrument's notes written small in a part's bars of rest over
--- a stretch, to come in by: as this part is written, on its clef, the
--- other's short name over them. `cue = { from = track id, at, to }` in
--- beats of the timeline.
local function put_cue(layout, cue, source)
  local named = false
  for i, m in ipairs(layout.measures) do
    local sm = source.measures[i]
    if sm and m.start >= cue.at - EPS and m.start < cue.to - EPS and resting(m) then
      local evs = {}
      for _, ev in ipairs(sm.staves[1] or {}) do
        if ev.voice == 1 and not ev.whole then
          evs[#evs + 1] = setmetatable(
            { cue = true, beam = false, stem = ev.stem and 1 or nil, shift = ev.kind == "rest" and 2 or nil },
            { __index = ev }
          )
        end
      end
      if #evs > 0 then
        -- The bar's own rest stays, out of the way under the cue.
        local own = m.staves[1][1]
        evs[#evs + 1] = setmetatable({ shift = -4 }, { __index = own })
        m.staves[1] = evs
        if not named then
          m.marks = m.marks or {}
          table.insert(m.marks, { at = m.start, kind = "text", value = source.cue_name, staff = 1 })
          named = true
        end
      end
    end
  end
end

-- Laying out ------------------------------------------------------------------------------------

--- The bar numbers a part asks to start a system at, as measure indices.
local function part_breaks(layout, own)
  local by_number = {}
  for i, m in ipairs(layout.measures) do
    by_number[m.number] = i
  end
  local breaks, joins = {}, {}
  for _, b in ipairs(own.breaks or {}) do
    if by_number[b] then breaks[by_number[b]] = true end
  end
  for _, b in ipairs(own.joins or {}) do
    if by_number[b] then joins[by_number[b]] = true end
  end
  return breaks, joins
end

--- The part of a track, as its player reads it. `opts.concert` leaves it
--- at concert pitch.
function P.part_layout(track_id, opts)
  opts = opts or {}
  local list = P.instruments()
  local entry = find(list, track_id)
  if not entry then return nil, "no MIDI on that track" end
  local parts, first = scores(list, not opts.concert)
  local number = first_number(first)
  local layouts, mine = {}, nil
  for i, p in ipairs(parts) do
    layouts[i] = lay(p, number)
    if p.entry == entry then mine = i end
  end
  share(layouts)
  local layout = layouts[mine]
  local own = P.own(track_id)
  local concert = #(own.cues or {}) > 0 and scores(list, false)
  for _, cue in ipairs(own.cues or {}) do
    local src, si = find(list, cue.from)
    if src then
      -- The other instrument written as this one is, on this one's clef.
      local sc = D.copy(concert[si].score)
      if not opts.concert and entry.transpose then P.transpose_score(sc, entry.transpose, concert[si].fifths) end
      sc.staves = { { id = sc.staves[1].id, clef = layout.staves[1] } }
      local source =
        L.layout(sc, { length = (D.origin(sc) + D.frame(sc).finish) / D.Q, fifths = layout.fifths, number = number })
      source.cue_name = src.short
      put_cue(layout, { at = cue.at - first, to = cue.to - first }, source)
    end
  end
  P.multirests(layout)
  local turns = {}
  for i, m in ipairs(layout.measures) do
    if m.multirest or resting(m) then turns[i] = true end
  end
  local breaks, joins = part_breaks(layout, own)
  layout.turns = turns
  layout.asked = { breaks = breaks, joins = joins, per = own.per_system, rests = turns }
  layout.tracks = { track_id }
  -- How far the written notes stand from the sounding ones, for the
  -- cursor, which goes by the clip's.
  if not opts.concert and entry.transpose then
    local steps, _, f = P.written(entry.transpose, (view.key()))
    layout.written = { steps = steps, fifths = f }
  end
  local ids = {}
  for k, c in ipairs(entry.clips) do
    ids[k] = c.id
  end
  layout.units = {
    {
      first = 1,
      last = #layout.staves,
      tracks = { track_id },
      clips = ids,
      players = { ids },
      family = entry.family,
      group = entry.group,
      name = entry.name,
    },
  }
  -- "Clarinet in B♭" over the part, unless its name says so already.
  local key = entry.transpose and entry.transpose.name:match("^%S+"):gsub("^(%u)b$", "%1♭"):gsub("^(%u)#$", "%1♯")
  layout.part_name = entry.name .. ((key and not entry.name:find(" in ", 1, true)) and (" in " .. key) or "")
  layout.start_beat = first
  return layout
end

--- Two instruments of one name, one staff each on the same clef ("Flute 1"
--- and "Flute 2"), share a staff in a condensed score.
local function base_name(e) return (e.name:gsub("%s+%d+%s*$", ""):gsub("%s+[IV]+%s*$", "")) end
local function pairs_with(a, b, la, lb)
  return a.family == b.family
    and base_name(a) == base_name(b)
    and base_name(a) ~= a.name
    and #la.staves == 1
    and #lb.staves == 1
    and la.staves[1] == lb.staves[1]
end

--- Whether two staves' events in a bar are the same: rhythm and pitches.
local function same(ea, eb)
  if #ea ~= #eb then return false end
  for i, a in ipairs(ea) do
    local b = eb[i]
    if
      a.kind ~= b.kind
      or abs(a.start - b.start) > EPS
      or abs(a.length - b.length) > EPS
      or #(a.notes or {}) ~= #(b.notes or {})
    then
      return false
    end
    for k, n in ipairs(a.notes or {}) do
      if n.pitch ~= b.notes[k].pitch then return false end
    end
  end
  return true
end

local function only_rests(evs)
  for _, ev in ipairs(evs) do
    if ev.kind ~= "rest" then return false end
  end
  return true
end

--- Two players' events as two voices of a staff: the first's stems up,
--- the second's down, rests out of each other's way.
local function voices(ea, eb)
  local out = {}
  for k, list in ipairs({ ea, eb }) do
    local dir = k == 1 and 1 or -1
    for _, ev in ipairs(list) do
      out[#out + 1] = setmetatable({
        voice = k,
        player = k,
        stem = ev.stem and dir or nil,
        beam = ev.beam and (k .. ":" .. tostring(ev.beam)) or nil,
        shift = ev.kind == "rest" and 2 * dir or nil,
      }, { __index = ev })
    end
  end
  table.sort(
    out,
    function(a, b) return a.start < b.start - EPS or (abs(a.start - b.start) < EPS and a.voice < b.voice) end
  )
  return out
end

--- The second player's events, said to be theirs.
local function seconds(list)
  local out = {}
  for i, ev in ipairs(list) do
    out[i] = setmetatable({ player = 2 }, { __index = ev })
  end
  return out
end

--- The bars (by number) a condensed pair is written apart in, though they
--- play the same there: `:score.split`, kept with the first player's track
--- (`meta.notation.part.split`).
function P.split_bars(track_id)
  local set = {}
  for _, n in ipairs(P.own(track_id).split or {}) do
    set[n] = true
  end
  return set
end

--- Two players condensed onto one staff, bar by bar: the same music once
--- (`a2`), one player's alone (`1.` or `2.`), or both as two voices; the
--- label written where it changes. The bars numbered in `split` are two
--- voices even where they are the same. Each event says whose it is
--- (`player`, 1 or 2; an `a2` event is the first's and stands for both).
function P.condense(la, lb, split)
  split = split or {}
  local out = setmetatable({ measures = {} }, { __index = la })
  local state
  for i, ma in ipairs(la.measures) do
    local mb = lb.measures[i] or ma
    local ea, eb = ma.staves[1] or {}, mb.staves[1] or {}
    local ra, rb = only_rests(ea), only_rests(eb)
    local evs, now
    if ra and rb then
      evs = ea
    elseif rb then
      evs, now = ea, "1."
    elseif ra then
      evs, now = seconds(eb), "2."
    elseif same(ea, eb) and not split[ma.number] then
      evs, now = ea, "a2"
    else
      evs, now = voices(ea, eb), "div."
    end
    local marks, seen = {}, {}
    for _, mk in ipairs(ma.marks or {}) do
      marks[#marks + 1] = mk
      seen[mk.kind .. ":" .. mk.at .. ":" .. tostring(mk.value)] = true
    end
    for _, mk in ipairs(mb.marks or {}) do
      if not seen[mk.kind .. ":" .. mk.at .. ":" .. tostring(mk.value)] then marks[#marks + 1] = mk end
    end
    if now and now ~= state and now ~= "div." then
      marks[#marks + 1] = { at = ma.start, kind = "text", value = now, staff = 1 }
    end
    if now then state = now end
    out.measures[i] = setmetatable({ staves = { evs }, marks = marks, condensed = now }, { __index = ma })
  end
  return out
end

--- The full score at concert pitch: every instrument's staves in order,
--- named, bracketed by family. `opts.condensed` puts two players of an
--- instrument on one staff; `opts.tracks`, `opts.from` and `opts.to` say
--- which instruments, as for `P.instruments`. `units` lists what stands
--- on the page, in order: `{ first, last, tracks, clips, players, family,
--- group, name, condensed }`, its staves and the tracks and clips they show
--- (every MIDI clip of its tracks, and each player's, two on a condensed
--- staff, which says how each bar is written, by measure).

function P.score_layout(opts)
  opts = opts or {}
  local list = P.instruments(opts)
  if #list == 0 then return nil, opts.tracks and "none of those tracks has MIDI" or "no track has MIDI" end
  local parts, first = scores(list, false)
  local number = first_number(first)
  local layouts = {}
  for i, p in ipairs(parts) do
    layouts[i] = lay(p, number)
  end
  share(layouts)
  -- What goes on the page: an instrument, or two condensed.
  local units = {}
  local i = 1
  while i <= #list do
    local a, b = list[i], list[i + 1]
    if opts.condensed and b and pairs_with(a, b, layouts[i], layouts[i + 1]) then
      local base = base_name(a)
      local na, nb = a.name:match("(%S+)%s*$"), b.name:match("(%S+)%s*$")
      units[#units + 1] = {
        layout = P.condense(layouts[i], layouts[i + 1], P.split_bars(a.id)),
        entry = a,
        entries = { a, b },
        tracks = { a.id, b.id },
        full = base .. " " .. na .. "." .. nb,
        short = (P.short(base):gsub("%s+%S+$", "")) .. " " .. na .. "." .. nb,
      }
      i = i + 2
    else
      units[#units + 1] =
        { layout = layouts[i], entry = a, entries = { a }, tracks = { a.id }, full = a.name, short = a.short }
      i = i + 1
    end
  end
  local top = layouts[1]
  local out = setmetatable({
    staves = {},
    tracks = {},
    labels = {},
    brackets = {},
    braces = {},
    spans = {},
    units = {},
    asked = { breaks = {}, joins = {} },
  }, { __index = top })
  out.measures = {}
  for mi, m in ipairs(top.measures) do
    out.measures[mi] = setmetatable({ staves = {}, marks = {}, rehearsal = m.rehearsal }, { __index = m })
  end
  local run
  for _, u in ipairs(units) do
    local base = #out.staves
    for k, clef in ipairs(u.layout.staves) do
      out.staves[base + k] = clef
      out.tracks[base + k] = u.tracks[1]
      for mi, m in ipairs(u.layout.measures) do
        out.measures[mi].staves[base + k] = m.staves[k]
      end
    end
    local count = #u.layout.staves
    for mi, m in ipairs(u.layout.measures) do
      for _, mk in ipairs(m.marks or {}) do
        -- Tempo marks once, over the score.
        if mk.kind ~= "tempo" or base == 0 then
          out.measures[mi].marks[#out.measures[mi].marks + 1] = setmetatable(
            { staff = base + (mk.staff or 1) },
            { __index = mk }
          )
        end
      end
    end
    out.labels[#out.labels + 1] = { first = base + 1, last = base + count, full = u.full, short = u.short }
    -- Every clip of the staff's tracks, and each player's own.
    local clips, players = {}, {}
    for k, e in ipairs(u.entries) do
      players[k] = {}
      for _, c in ipairs(e.clips) do
        clips[#clips + 1] = c.id
        table.insert(players[k], c.id)
      end
    end
    -- A condensed staff says how each bar is written: "a2", "1.", "2.", "div.".
    local condensed
    if #u.tracks > 1 then
      condensed = {}
      for mi, m in ipairs(u.layout.measures) do
        condensed[mi] = m.condensed or false
      end
    end
    out.units[#out.units + 1] = {
      first = base + 1,
      last = base + count,
      tracks = u.tracks,
      clips = clips,
      players = players,
      family = u.entry.family,
      group = u.entry.group,
      name = u.full,
      condensed = condensed,
    }
    if count == 2 then out.braces[#out.braces + 1] = { base + 1, base + 2 } end
    -- A family's barlines run through it, and a bracket goes over it.
    local family = u.entry.family
    if run and run.family == family then
      run.span[2] = base + count
    else
      run = { family = family, span = { base + 1, base + count } }
      out.spans[#out.spans + 1] = run.span
      if family <= #P.FAMILIES then out.brackets[#out.brackets + 1] = run.span end
    end
  end
  out.start_beat = first
  return out
end

-- In the notation view ---------------------------------------------------------------------------

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

--- What the view shows instead of its clip: `view.parts` is `{ kind =
--- "score" | "part", track, condensed }`. Made again when a clip, a track
--- or the song changes.
function P.view_layout(v)
  local shown = v.parts
  -- A score that follows the scope shows the tracks of the scope of the window.
  local tracks = shown.tracks
  local scope = shown.scope and rawget(paw, "scope")
  if scope and scope.limits_tracks() then tracks = scope.tracks() end
  local p = api.project_get()
  local stamp = {
    shown.kind,
    tostring(shown.track),
    tostring(shown.condensed),
    tostring(paw.opt.notation_grid),
    table.concat(tracks or {}, ","),
    tostring(shown.from),
    tostring(shown.to),
  }
  -- The view asks for its layout many times a key: while nothing was
  -- edited or undone since, it is the one made last.
  local quick = table.concat(stamp, ":") .. ":" .. tostring(p.edits) .. ":" .. tostring(api.undo_current())
  if v.score_cache and v.score_cache.quick == quick then return v.score_cache.layout end
  for _, t in ipairs(paw.tracks()) do
    local tt = t:get()
    stamp[#stamp + 1] = tt.id .. "/" .. tostring(tt.name) .. "/" .. serial(tt.meta)
    for _, c in ipairs(t:clips()) do
      local g = c:get()
      stamp[#stamp + 1] = g.id .. "/" .. tostring(g.stamp) .. "/" .. g.start .. "/" .. g.length
    end
  end
  stamp[#stamp + 1] = serial(p.meta) .. tostring(p.tempo) .. tostring(p.sig_num) .. tostring(p.sig_den)
  stamp = table.concat(stamp, ":")
  if v.score_cache and v.score_cache.stamp == stamp then
    v.score_cache.quick = quick
    return v.score_cache.layout
  end

  local layout, err
  if shown.kind == "part" then
    layout, err = P.part_layout(shown.track)
  else
    layout, err = P.score_layout({ condensed = shown.condensed, tracks = tracks, from = shown.from, to = shown.to })
  end
  if not layout then
    paw.notify(err, "warn")
    v.parts = nil
    return nil
  end
  v.score_cache = { stamp = stamp, layout = layout, quick = quick }
  return layout
end

view.parts_of = P
return P
