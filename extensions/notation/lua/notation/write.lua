-- What the popovers write (`notation.popover`), each as an Ex command that
-- takes a range, so that a popover, `:` and `:5,8` say the same thing:
--
--   notation.dyn      mp, sfz, fp, p subito, mp<f, <, >, niente<
--   notation.tempo    Allegro q=132, q.=60, rit., accel., a tempo
--   notation.meter    6/8, 3+3+2/8, C, ¢
--   notation.key      Eb, f#m, D dorian, off
--   notation.clef     treble, treble8, bass, bass8, alto, tenor
--   notation.bar      ||, |., |:, :|, :|:, 1., 2., off
--   notation.rehearsal A (or nothing: the next letter); also a song marker
--   notation.chord    Cmaj7, G/B, N.C., off
--   notation.lyric    a syllable, "-" after it a hyphen, "_" an extender; verse=2
--   notation.orn      tr, mordent, turn, fermata, off
--   notation.tech     pizz., arco, con sord., off
--   notation.interval 3, -6, 8, m3, P5
--   notation.tuplet   3, 5:4, off
--   notation.voice    1 to 4
--
-- Everything is written in the score (`notation.doc`), which keeps it with
-- the clip and its notes (`notation.midi`): key and clef changes, the
-- beats' grouping, barlines, endings and rehearsal marks at bars; tempo,
-- chord symbols and techniques as marks; ornaments and lyrics on the
-- notes. Tempo marks also write the song's tempo map, and time signatures
-- the song's signatures, so they play.
local api = paw.api
local util = paw.util
local view = require("notation")
local model = require("notation.model")
local D = require("notation.doc")
local midi = require("notation.midi")
local marks = require("notation.marks")
local keymap, command = paw.keymap, paw.command

local W = {}
local EPS = 1e-6

-- Where a command works ----------------------------------------------------------------------

--- The region a command works on: its range of bars, else the selection.
local function region(ctx)
  local clip = view:clip()
  local range = ctx and ctx.range
  if clip and range and range.bars then
    local c = clip:get()
    return { view = "notation", kind = "char", r0 = 0, r1 = 127, c0 = math.max(0, range.from - c.start), c1 = math.min(c.length, range.to - c.start) }
  end
  return view:selection()
end
W.region = region

--- The stretch a mark covers: the region's, or the cursor's place to the
--- end of its bar. The second value says whether a region gave it.
local function span(ctx)
  local r = region(ctx)
  if r then return math.max(0, r.c0), r.c1, true end
  local m = view:measure_at(view.beat)
  return view.beat, m and (m.start + m.length) or (view.beat + 4), false
end

--- The first and last measures (of the layout) a command works on.
local function measures(ctx)
  local r = region(ctx)
  local first = view:measure_at(r and math.max(0, r.c0) or view.beat)
  local last = r and view:measure_at(math.max(r.c0, r.c1 - EPS)) or first
  return first, last, r ~= nil
end

--- The chords (score event ids) a command works on: the region's, or the
--- chord under the cursor.
local function chords(ctx)
  local clip = view:editable()
  local r = region(ctx)
  if r and clip then
    local _, places = paw.edit.roll.notes(clip, r)
    return view:events_of(places)
  end
  return view:chord_indices()
end

local function words(ctx)
  local out = {}
  for _, a in ipairs(ctx.args or {}) do out[#out + 1] = tostring(a) end
  return (table.concat(out, " "):match("^%s*(.-)%s*$"))
end

local function need_clip()
  if view:clip() then return true end
  paw.notify("no clip open as notation", "warn")
  return false
end

--- A mark of `kind` at a beat of the clip, in place of one of its kind
--- there (`fields` false takes it away). `same(mark)` narrows what is
--- replaced. Inside `view:write`.
local function put_mark(sc, beat, kind, fields, same)
  local ref, mi = marks.ref(sc, beat)
  local f = D.frame(sc)
  local t = midi.at_of(sc, f, ref)
  local list = {}
  for _, mk in ipairs(sc.marks or {}) do
    if not (mk.kind == kind and midi.at_of(sc, f, mk.from) == t and (not same or same(mk))) then list[#list + 1] = mk end
  end
  local new
  if fields then
    new = { id = D.id(sc, "k"), kind = kind, from = ref }
    for k, v in pairs(fields) do new[k] = v end
    list[#list + 1] = new
  end
  sc.marks = list
  D.touch(sc, mi)
  return new
end
W.put_mark = put_mark

--- The measure of the score at a beat of the clip, made if need be.
local function measure(sc, beat)
  local mi = view.where(sc, beat + EPS)
  D.ensure(sc, mi)
  return sc.measures[mi], mi
end

-- Dynamics -----------------------------------------------------------------------------------

W.DYNAMICS = { "pppp", "ppp", "pp", "p", "mp", "mf", "f", "ff", "fff", "ffff", "sf", "sfz", "sffz", "fz", "rfz", "sfp", "fp", "niente" }
local DYN = {}
for _, d in ipairs(W.DYNAMICS) do DYN[d] = true end
DYN.n = true

--- Read a dynamics popover's text: `{ from, pin, to, subito }`, or nil and why.
function W.parse_dynamic(text)
  text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
  local subito = false
  text = text:gsub("%s*sub%.?i?t?o?$", function()
    subito = true
    return ""
  end)
  local from, pin, to = text:match("^(%a*)%s*([<>]?)%s*(%a*)$")
  if not from then return nil, "a dynamic, a hairpin, or both: mp, mp<f, <, >, niente<" end
  if from == "n" then from = "niente" end
  if to == "n" then to = "niente" end
  if from ~= "" and not DYN[from] then return nil, "`" .. from .. "` is not a dynamic" end
  if to ~= "" and not DYN[to] then return nil, "`" .. to .. "` is not a dynamic" end
  if pin == "" and to ~= "" then return nil, "two dynamics need a hairpin between them: " .. from .. "<" .. to end
  if from == "" and pin == "" then return nil, "a dynamic, a hairpin, or both: mp, mp<f, <, >, niente<" end
  return { from = from ~= "" and from or nil, pin = pin ~= "" and pin or nil, to = to ~= "" and to or nil, subito = subito or nil }
end

--- The next dynamic written after a beat of the clip, or nil.
local function next_dynamic(sc, beat)
  local f = D.frame(sc)
  local origin = D.origin(sc)
  local best
  for _, mk in ipairs(sc.marks or {}) do
    if mk.kind == "dynamic" then
      local t = midi.at_of(sc, f, mk.from)
      local b = t and (origin + t) / D.Q
      if b and b > beat + EPS and (not best or b < best) then best = b end
    end
  end
  return best
end

function W.dynamic(ctx)
  if not need_clip() then return end
  local text = words(ctx)
  local a, b, ranged = span(ctx)
  if text == "off" then
    view:write(function(sc) put_mark(sc, a, "dynamic", false) end)
    return paw.notify("no dynamic here")
  end
  local d, why = W.parse_dynamic(text)
  if not d then return paw.notify(why, "warn") end
  view:write(function(sc)
    local finish = b
    -- A hairpin with nowhere said to go reaches the next dynamic.
    if d.pin and not d.to and not ranged then finish = next_dynamic(sc, a) or b end
    if d.from then put_mark(sc, a, "dynamic", { value = d.from, subito = d.subito }) end
    if d.pin then
      local niente = d.from == "niente" or d.to == "niente" or nil
      put_mark(sc, a, "hairpin", { value = d.pin == "<" and "cresc" or "dim", to = (marks.ref(sc, finish)), niente = niente })
    end
    if d.to then put_mark(sc, finish, "dynamic", { value = d.to }) end
  end)
  local said = {}
  if d.from then said[#said + 1] = d.from .. (d.subito and " subito" or "") end
  if d.pin then said[#said + 1] = (d.pin == "<" and "crescendo" or "diminuendo") .. (d.to and (" to " .. d.to) or "") end
  paw.notify(table.concat(said, ", "))
end

-- Tempo ----------------------------------------------------------------------------------------

-- The tempos the words name when no number is given (quarters a minute).
W.TEMPOS = {
  Grave = 40, Largo = 50, Larghetto = 63, Lento = 52, Adagio = 70, Adagietto = 76, Andante = 92, Andantino = 100,
  Moderato = 112, Allegretto = 120, Allegro = 132, Vivace = 160, Vivacissimo = 172, Presto = 180, Prestissimo = 208,
}
local UNITS = { ["q"] = 1, ["q."] = 1.5, ["h"] = 2, ["h."] = 3, ["e"] = 0.5, ["e."] = 0.75, ["w"] = 4, ["♩"] = 1, ["♩."] = 1.5 }
local CHANGES = { ["rit."] = "rit.", rit = "rit.", ritardando = "rit.", ["rall."] = "rit.", rall = "rit.", rallentando = "rit.",
  ["accel."] = "accel.", accel = "accel.", accelerando = "accel.", ["a tempo"] = "a tempo", ["tempo i"] = "a tempo",
  ["tempo primo"] = "a tempo" }

--- Read a tempo popover's text: `{ text, bpm (quarters a minute), unit,
--- per (the number written), change }`, or nil and why.
function W.parse_tempo(text)
  text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
  if text == "" then return nil, "a tempo: Allegro, q=132, Allegro q=132, rit., accel., a tempo" end
  local change = CHANGES[text:lower()]
  if change then return { text = text, change = change } end
  local before, unit, per = text:match("^(.-)%s*([qhew♩]%.?)%s*=%s*(%d+%.?%d*)$")
  local out = { text = text }
  if unit then
    out.unit, out.per = unit, tonumber(per)
    out.bpm = out.per * UNITS[unit]
    out.words = before ~= "" and before or nil
  else
    out.words = text
  end
  if not out.bpm and out.words then
    local first = out.words:match("^(%a+)")
    local named = first and W.TEMPOS[first:sub(1, 1):upper() .. first:sub(2):lower()]
    if named then out.bpm = named end
  end
  return out
end

function W.tempo(ctx)
  if not need_clip() then return end
  local clip = view:clip()
  local c = clip:get()
  local text = words(ctx)
  local a, b = span(ctx)
  if text == "off" then
    view:write(function(sc) put_mark(sc, a, "tempo", false) end)
    pcall(paw.tempo.remove, c.start + a)
    return paw.notify("no tempo mark here")
  end
  local t, why = W.parse_tempo(text)
  if not t then return paw.notify(why, "warn") end
  local song = c.start + a
  view:write(function(sc)
    put_mark(sc, a, "tempo", { value = t.text, bpm = t.bpm, change = t.change })
  end)
  -- The mark plays: the song's tempo map follows it.
  if t.bpm then
    paw.tempo.set(song, t.bpm)
    return paw.notify(t.text .. ": " .. util.round(t.bpm, 0.1) .. " beats a minute from here")
  end
  local now = paw.tempo.at(song)
  if t.change == "a tempo" then
    -- Back to the last tempo a mark said, or to what held before the change.
    local sc = view.score_of(c)
    local f, origin = D.frame(sc), D.origin(sc)
    local back, at = nil, -math.huge
    for _, mk in ipairs(sc.marks) do
      local mt = mk.kind == "tempo" and midi.at_of(sc, f, mk.from)
      local beat = mt and (origin + mt) / D.Q
      if beat and beat < a - EPS and beat > at then
        if mk.bpm then
          back, at = mk.bpm, beat
        elseif mk.change and mk.change ~= "a tempo" then
          back, at = paw.tempo.at(c.start + beat - EPS), beat
        end
      end
    end
    back = back or paw.tempo.at(c.start)
    paw.tempo.set(song, back)
    return paw.notify("a tempo: " .. util.round(back, 0.1) .. " beats a minute")
  end
  -- rit. and accel. ramp to a fifth slower or faster by the end of the stretch.
  local to = t.change == "rit." and now * 0.8 or now * 1.2
  paw.tempo.set(song, now, { ramp = true })
  paw.tempo.set(c.start + b, to)
  paw.notify(string.format("%s: %g to %g beats a minute", t.change, util.round(now, 0.1), util.round(to, 0.1)))
end

-- Metre ---------------------------------------------------------------------------------------

--- Read a metre: `{ num, den, groups }`, or nil and why.
function W.parse_meter(text)
  text = text:gsub("%s+", "")
  if text == "C" or text == "c" or text == "common" then return { num = 4, den = 4, symbol = "common" } end
  if text == "¢" or text == "cut" or text == "C|" then return { num = 2, den = 2, symbol = "cut" } end
  local top, den = text:match("^([%d%+]+)/(%d+)$")
  if not top then return nil, "a time signature: 6/8, 3/4, 3+3+2/8, C, ¢" end
  den = tonumber(den)
  if not ({ [1] = true, [2] = true, [4] = true, [8] = true, [16] = true, [32] = true })[den] then return nil, "the lower number is 2, 4, 8, 16 or 32" end
  local groups, num = {}, 0
  for g in top:gmatch("%d+") do
    groups[#groups + 1] = tonumber(g)
    num = num + tonumber(g)
  end
  if num < 1 or num > 64 then return nil, "between 1 and 64 beats" end
  return { num = num, den = den, groups = #groups > 1 and groups or nil }
end

--- A time signature from the cursor's bar: the song's signature there, so
--- that its notes stay where they are in time and are written in the new
--- bars (tied over the new barlines), with the beats' grouping and a
--- symbol kept with the clip.
function W.meter(ctx)
  if not need_clip() then return end
  local m, why = W.parse_meter(words(ctx))
  if not m then return paw.notify(why, "warn") end
  local first = measures(ctx)
  local clip = view:clip()
  local c = clip:get()
  local beat = c.start + first.start
  paw.tempo.set_signature(paw.time.bar_of(beat + EPS), m.num, m.den)
  view.cache = nil
  view:write(function(sc)
    local sm, mi = measure(sc, first.start)
    sm.groups, sm.meter_symbol = m.groups, m.symbol
    sm.meter = { m.num, m.den }
    sc._frame = nil
    D.touch(sc, mi)
  end)
  paw.notify(m.num .. "/" .. m.den .. (m.groups and (" (" .. table.concat(m.groups, "+") .. ")") or "") .. " from bar " .. first.number)
end

-- Key -------------------------------------------------------------------------------------

local MODES = { major = true, minor = true, dorian = true, phrygian = true, lydian = true, mixolydian = true, locrian = true,
  ionian = true, aeolian = true }

--- Read a key: `{ root, scale, fifths, name }`, or nil and why. A capital
--- letter is major and a small one minor (Eb, f#m, c), or the mode is said.
function W.parse_key(text)
  text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
  local letter, acc, rest = text:match("^([A-Ga-g])([#b♯♭]?)%s*(.-)$")
  if not letter then return nil, "a key: Eb, f#m, D dorian, Bb minor, off" end
  acc = acc:gsub("♯", "#"):gsub("♭", "b")
  local scale
  rest = rest:lower()
  if rest == "" then
    scale = letter:match("%l") and "minor" or "major"
  elseif rest == "m" or rest == "min" then
    scale = "minor"
  elseif rest == "maj" or rest == "M" then
    scale = "major"
  else
    scale = MODES[rest] and rest or nil
    if scale == "ionian" then scale = "major" elseif scale == "aeolian" then scale = "minor" end
  end
  if not scale then return nil, "`" .. rest .. "` is not a mode: major, minor, dorian, phrygian, lydian, mixolydian, locrian" end
  local root = letter:upper() .. acc
  return { root = root, scale = scale, fifths = model.fifths_of(root, scale), name = root .. " " .. scale }
end

function W.key(ctx)
  local text = words(ctx)
  local clip = view:clip()
  -- Without a score open, the project's key, as before scores.
  if not (clip and (paw.ui.focused == "notation" or ctx.range)) then return false end
  local first = measures(ctx)
  if text == "off" then
    view:write(function(sc)
      local m, mi = measure(sc, first.start)
      m.key = nil
      D.touch(sc, mi)
    end)
    return paw.notify("no key change at bar " .. first.number)
  end
  local k, why = W.parse_key(text)
  if not k then return paw.notify(why, "warn") end
  local at_start
  view:write(function(sc)
    local m, mi = measure(sc, first.start)
    m.key = { fifths = k.fifths, name = k.name }
    at_start = mi == 1
    D.touch(sc, mi)
  end)
  -- The key the piece starts in is the project's too, which harmony reads.
  if at_start then pcall(paw.harmony.set_key, k.name) end
  paw.notify(k.name .. " from bar " .. first.number .. " (" .. math.abs(k.fifths) .. (k.fifths >= 0 and " sharps)" or " flats)"))
  return true
end

-- Clef ------------------------------------------------------------------------------------

--- A clef change at the cursor's bar on its staff. False when this is not
--- for a score's bar after the first (the staff's own clef is set then).
function W.clef(ctx, want)
  local clip = view:clip()
  if not (clip and paw.ui.focused == "notation") then return false end
  local first = measures(ctx)
  if first.index == 1 then return false end
  local staff_index = view:cursor_staff()
  view:write(function(sc)
    local m, mi = measure(sc, first.start)
    local st = (sc.staves[staff_index] or sc.staves[1]).id
    local clef = util.merge(m.clef or {}, {})
    clef[st] = want ~= "off" and want or nil
    m.clef = next(clef) and clef or nil
    D.touch(sc, mi)
  end)
  paw.notify(want == "off" and ("no clef change at bar " .. first.number) or (want .. " clef from bar " .. first.number))
  return true
end

-- Barlines, repeats, endings, rehearsal marks ------------------------------------------------------

W.BARLINES = { ["|"] = "a plain barline", ["||"] = "a double barline", ["|."] = "the final barline", ["|:"] = "a repeat starts",
  [":|"] = "a repeat ends", [":|:"] = "a repeat ends and another starts", ["1."] = "first ending", ["2."] = "second ending",
  ["3."] = "third ending", off = "plain barlines, no repeats or endings" }

function W.bar(ctx)
  if not need_clip() then return end
  local what = words(ctx)
  if not W.BARLINES[what] then return paw.notify("a barline: ||, |., |:, :|, :|:, 1., 2., off", "warn") end
  local first, last, ranged = measures(ctx)
  -- The barline the cursor is at: before its bar when it is at the bar's
  -- start, else at the bar's end.
  local at_start = not ranged and math.abs(view.beat - first.start) < EPS and first.index > 1
  view:write(function(sc)
    local _, a = measure(sc, first.start)
    local _, b = measure(sc, last.start)
    local ending = at_start and a - 1 or b
    local function set(mi, key, value)
      D.ensure(sc, mi)
      sc.measures[mi][key] = value
      D.touch(sc, mi)
    end
    local volta = tonumber(what:match("^(%d)%.$"))
    if volta then
      for mi = a, b do set(mi, "volta", volta) end
    elseif what == "|:" then
      set(a, "repeat_start", true)
    elseif what == "|" then
      set(ending, "barline", nil)
    elseif what == ":|:" then
      set(ending, "barline", ":|")
      set(ending + 1, "repeat_start", true)
    elseif what == "off" then
      for mi = a, b do
        set(mi, "barline", nil)
        set(mi, "repeat_start", nil)
        set(mi, "volta", nil)
      end
    else
      set(ending, "barline", what)
    end
  end)
  paw.notify(W.BARLINES[what])
end

local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

function W.rehearsal(ctx)
  if not need_clip() then return end
  local clip = view:clip()
  local c = clip:get()
  local name = words(ctx)
  local first = measures(ctx)
  local beat = c.start + math.max(0, first.start)
  local old
  view:write(function(sc)
    local m, mi = measure(sc, first.start)
    old = m.rehearsal
    if name == "" then
      -- The letter after the last one written before here.
      local used = 0
      for k = 1, mi - 1 do
        local r = sc.measures[k].rehearsal
        local at = r and LETTERS:find(r, 1, true)
        if at and #r == 1 then used = math.max(used, at) end
      end
      name = LETTERS:sub(used + 1, used + 1)
    end
    m.rehearsal = name ~= "off" and name or nil
    D.touch(sc, mi)
  end)
  -- The song's marker of the same name, so that the arrangement and the
  -- score share their sections.
  for _, mk in ipairs(paw.markers.list()) do
    if math.abs(mk.beat - beat) < EPS and (mk.name == old or mk.name == name) then paw.markers.remove(mk.id) end
  end
  if name == "off" then return paw.notify("no rehearsal mark at bar " .. first.number) end
  paw.markers.add(beat, name)
  paw.notify("rehearsal mark " .. name .. " at bar " .. first.number .. ", and a marker in the song")
end

-- Chord symbols ----------------------------------------------------------------------------

--- Whether text is a chord symbol: a root, any quality, a bass; or N.C.
function W.is_chord(text)
  if text == "N.C." or text == "NC" or text == "N.C" then return true end
  return text:match("^[A-G][#b]?[%w#b+°ø%(%)%-,]*/?[A-G]?[#b]?$") ~= nil and not text:match("/$")
end

function W.chord(ctx)
  if not need_clip() then return end
  local text = words(ctx)
  local a = span(ctx)
  if text == "off" or text == "" then
    view:write(function(sc) put_mark(sc, a, "chord", false) end)
    return paw.notify("no chord symbol here")
  end
  if not W.is_chord(text) then return paw.notify("a chord symbol: C, Cmaj7, F#m7b5, G/B, N.C.", "warn") end
  if text == "NC" or text == "N.C" then text = "N.C." end
  view:write(function(sc) put_mark(sc, a, "chord", { value = text }) end)
  paw.notify(text)
end

--- Chord symbols to offer at a beat of the clip: what the harmony reads
--- of the notes sounding there first, then the common ones on the root
--- typed.
function W.chord_candidates(typed)
  local clip = view:clip()
  local out, seen = {}, {}
  local function add(text, desc)
    if not seen[text] and text:sub(1, #typed) == typed then
      seen[text] = true
      out[#out + 1] = { text = text, desc = desc }
    end
  end
  if clip then
    local beat = clip:get().start + view.beat
    local ok, here = pcall(paw.harmony.at, beat)
    if ok and here then add(here.name, "what sounds here") end
    local ok2, list = pcall(paw.harmony.chords, beat, beat + 8)
    for _, ch in ipairs(ok2 and list or {}) do add(ch.name, "sounds at " .. paw.time.format(ch.at)) end
  end
  local root = typed:match("^([A-G][#b]?)")
  if root then
    for _, q in ipairs({ "", "m", "7", "maj7", "m7", "m7b5", "dim", "dim7", "aug", "sus4", "sus2", "6", "m6", "9", "add9", "7b9", "7#11" }) do
      add(root .. q)
    end
  end
  add("N.C.", "no chord")
  return out
end

-- Lyrics -----------------------------------------------------------------------------------

--- The chords of the cursor's staff and voice, from the cursor on: the
--- one there, and the next one. `{ ev, beat }`, from the layout.
local function chord_from(beat, after)
  local layout = view:layout()
  if not layout then return nil end
  local staff = view:cursor_staff(layout)
  local voice = view:cursor_voice()
  local best
  for _, ev in ipairs(model.events(layout)) do
    if ev.staff == staff and ev.voice == voice and ev.kind == "note" and ev.source and not ev.notes[1].tied then
      local ok = after and ev.start > beat + EPS or (not after and ev.start + ev.length > beat + EPS)
      if ok and (not best or ev.start < best.start) then best = ev end
    end
  end
  return best
end
W.chord_from = chord_from

--- Put a syllable under the chord at the cursor (`text` "" takes it away),
--- in a verse. A syllable ending in "-" is joined to the next by a hyphen,
--- one ending in "_" held under the notes after it.
function W.lyric(ctx)
  if not need_clip() then return end
  local text = words(ctx)
  local verse = 1
  text = text:gsub("^verse=(%d+)%s*", function(n)
    verse = math.max(1, tonumber(n))
    return ""
  end)
  local ev = chord_from(view.beat)
  if not (ev and ev.start <= view.beat + EPS) then return paw.notify("no note here for a syllable", "warn") end
  local id = ev.source.id
  view:write(function(sc)
    local mi, _, _, _, sev = D.find(sc, id)
    if not sev then return false end
    if verse == 1 then
      sev.lyric = text ~= "" and text or nil
    else
      local list = {}
      for i = 1, math.max(#(sev.lyrics or {}), verse - 1) do list[i] = (sev.lyrics or {})[i] or "" end
      list[verse - 1] = text
      while #list > 0 and list[#list] == "" do list[#list] = nil end
      sev.lyrics = #list > 0 and list or nil
    end
    D.touch(sc, mi)
  end)
end

-- Ornaments and techniques ---------------------------------------------------------------------------

W.ORNAMENTS = { tr = "trill", trill = "trill", mordent = "mordent", mord = "mordent", prall = "prall", ["inverted mordent"] = "prall",
  turn = "turn", ["inverted turn"] = "turn_inverted", fermata = "fermata", ["fermata short"] = "fermata_short",
  ["fermata long"] = "fermata_long", tremolo = "tremolo", trem = "tremolo", off = "off" }

function W.ornament(ctx)
  if not need_clip() then return end
  local text = words(ctx):lower()
  local kind = W.ORNAMENTS[text]
  if not kind then return paw.notify("an ornament: tr, mordent, prall, turn, fermata, trem, off", "warn") end
  local ids = chords(ctx)
  if #ids == 0 then return paw.notify("no chord here for an ornament", "warn") end
  view:write(function(sc)
    for _, id in ipairs(ids) do
      local mi, _, _, _, ev = D.find(sc, id)
      if ev and ev.kind == "chord" then
        local art = util.merge(ev.art or {}, {})
        art.fermata, art.fermata_short, art.fermata_long = nil, nil, nil
        if kind == "off" then
          ev.orn = nil
        elseif kind:match("^fermata") then
          art[kind] = true
        else
          ev.orn = kind
        end
        if kind == "off" then art = {} end
        ev.art = next(art) and art or nil
        D.touch(sc, mi)
      end
    end
  end)
  paw.notify(kind == "off" and "no ornaments" or (text .. " on " .. #ids .. (#ids == 1 and " chord" or " chords")))
end

W.TECHNIQUES = { "pizz.", "arco", "con sord.", "senza sord.", "trem.", "harm.", "col legno", "sul pont.", "sul tasto", "ord.",
  "l.v.", "palm mute", "let ring", "mute", "open", "legato", "non vib.", "vib." }

function W.technique(ctx)
  if not need_clip() then return end
  local text = words(ctx)
  local a, b, ranged = span(ctx)
  view:write(function(sc) put_mark(sc, a, "technique", (text ~= "" and text ~= "off") and { value = text } or false) end)
  marks.tell({ kind = "technique", text = text, from = a, to = ranged and b or nil, clip = view:clip() })
  paw.notify(text ~= "" and text ~= "off" and text or "no technique here")
end

-- Intervals, tuplets, voices ----------------------------------------------------------------------

local SEMIS = { 0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24 }
local PERFECT = { [1] = true, [4] = true, [5] = true, [8] = true, [11] = true, [12] = true, [15] = true }

--- Read an interval: `{ steps (signed, 1 a unison), quality? }`, or nil and why.
function W.parse_interval(text)
  local sign, quality, n = text:gsub("%s+", ""):match("^([%+%-]?)([mMPAd]?)(%d+)$")
  n = tonumber(n)
  if not n or n < 1 or n > 15 then return nil, "an interval from 2 to 15, below with a minus: 3, -6, 8, m3, P5" end
  if quality == "P" and not PERFECT[n] then return nil, "a " .. n .. " is major or minor, not perfect" end
  if (quality == "M" or quality == "m") and PERFECT[n] then return nil, "a " .. n .. " is perfect" end
  return { steps = sign == "-" and -(n - 1) or (n - 1), size = n, quality = quality ~= "" and quality or nil }
end

--- The note an interval from `n` (a score note), in the key `fifths`.
function W.interval_note(n, iv, fifths)
  local step = D.diatonic(n) + iv.steps
  local pitch = model.key_pitch(step, fifths)
  local sp = model.spell(pitch, fifths)
  if sp.step ~= step then
    -- The key's spelling of that pitch names another letter: keep the letter.
    sp = { letter = step % 7, octave = math.floor(step / 7) - 1, alter = 0 }
    sp.alter = pitch - D.pitch({ step = sp.letter, alter = 0, octave = sp.octave })
  end
  local out = { step = sp.letter, alter = sp.alter, octave = sp.octave }
  if iv.quality then
    -- The quality said: the size in semitones, the letter kept.
    local want = SEMIS[iv.size] + (iv.quality == "m" and -1 or iv.quality == "A" and 1 or iv.quality == "d" and (PERFECT[iv.size] and -1 or -2) or 0)
    local have = math.abs(D.pitch(out) - D.pitch(n))
    out.alter = out.alter + (want - have) * (iv.steps < 0 and -1 or 1)
  end
  return out
end

function W.interval(ctx)
  if not need_clip() then return end
  local iv, why = W.parse_interval(words(ctx))
  if not iv then return paw.notify(why, "warn") end
  local ids = chords(ctx)
  if #ids == 0 then return paw.notify("no chord here to add to", "warn") end
  local added = 0
  view:write(function(sc)
    local layout = view:layout()
    for _, id in ipairs(ids) do
      local mi, _, _, _, ev = D.find(sc, id)
      if ev and ev.kind == "chord" and #ev.notes > 0 then
        local lm = layout.measures[mi]
        local fifths = lm and lm.fifths or layout.fifths
        -- From the top note up, from the lowest down.
        local from = ev.notes[1]
        for _, n in ipairs(ev.notes) do
          if (iv.steps >= 0 and D.pitch(n) > D.pitch(from)) or (iv.steps < 0 and D.pitch(n) < D.pitch(from)) then from = n end
        end
        local note = W.interval_note(from, iv, fifths)
        local pitch = D.pitch(note)
        if pitch >= 0 and pitch <= 127 then
          note.id = D.id(sc, "n")
          if view.join_chord(sc, id, note) == note.id then added = added + 1 end
        end
      end
    end
    if added == 0 then return false end
  end)
  paw.notify(added == 1 and "1 note added" or added .. " notes added")
end

--- Read a tuplet: `{ actual, normal }`, or false for none, or nil and why.
function W.parse_tuplet(text)
  text = text:gsub("%s+", "")
  if text == "off" or text == "1" or text == "0" then return false end
  local a, n = text:match("^(%d+):(%d+)$")
  a, n = tonumber(a or text:match("^(%d+)$")), tonumber(n)
  if not a or a < 2 or a > 15 then return nil, "a tuplet: 3, 5, 5:4, 6:4, 7:8, off" end
  if not n then
    -- As many as the power of two below: 3 in the time of 2, 5 of 4, 7 of 4.
    n = 1
    while n * 2 < a do n = n * 2 end
    if a == 2 then n = 3 end
  end
  return { actual = a, normal = n }
end

--- The notes of a stretch of one measure written again as a tuplet of
--- `actual` in the time of `normal`, in order, a rest in each place left.
local function make_tuplet(a, b, actual, normal)
  local layout = view:layout()
  local ev = view:event_at(view.beat, view.step)
  local v = ev and ev.voice or view.voice or 1
  local staff_index = ev and ev.staff or view:staff_of_step(view.step, layout)
  return view:write(function(sc)
    local staff = (sc.staves[staff_index] or sc.staves[1]).id
    local mi, at = view.where(sc, a)
    local f = D.frame(sc)
    local finish = math.min(f.lengths[mi], at + D.from_beats(b - a))
    local width = finish - at
    if width <= 0 or width % normal ~= 0 then
      paw.notify("that stretch does not divide into " .. normal, "warn")
      return false
    end
    local found = {}
    for _, it in ipairs(D.line(sc, mi, staff, v)) do
      if it.ev.kind == "chord" and not it.ev.grace and it.s < finish and it.e > at then
        if it.s < at or it.e > finish then
          paw.notify("a note goes over the edge of the stretch: shorten it first", "warn")
          return false
        end
        found[#found + 1] = it
      end
    end
    if #found > actual then
      paw.notify("more notes than the tuplet has places", "warn")
      return false
    end
    local value = width / normal
    local tp = { id = D.id(sc, "t"), actual = actual, normal = normal }
    local evs = {}
    for k = 1, actual do
      local it = found[k]
      if it then
        local x = { id = it.ev.id, kind = "chord", notes = it.ev.notes, art = it.ev.art, arpeggio = it.ev.arpeggio, orn = it.ev.orn,
          lyric = it.ev.lyric, lyrics = it.ev.lyrics, dur = D.ratio(value), dots = 0, tuplet = tp }
        for _, n in ipairs(x.notes) do n.tie = nil end
        evs[k] = x
      else
        evs[k] = { id = D.id(sc, "e"), kind = "rest", dur = D.ratio(value), dots = 0, tuplet = tp }
      end
    end
    D.splice(sc, mi, staff, v, at, finish, evs)
    D.fix_ties(sc, staff, v, math.max(1, mi - 1), mi)
  end)
end

function W.tuplet(ctx)
  if not need_clip() then return end
  local tp, why = W.parse_tuplet(words(ctx))
  if tp == nil then return paw.notify(why, "warn") end
  if W.entering or keymap.mode == "i" then
    -- Entering: the values typed next are of that tuplet.
    view.tuplet, view.triplets = tp and { tp.actual, tp.normal } or nil, false
    api.ui_redraw()
    return paw.notify(tp and ("entering " .. tp.actual .. ":" .. tp.normal) or "entering plain values")
  end
  local a, b, ranged = span(ctx)
  if not tp then
    -- On a beat that is a tuplet: plain values again.
    local ev = not ranged and view:event_at(view.beat, view.step)
    if ev and ev.tuplet then
      if view:toggle_tuplet() == false then paw.notify("plain values") end
      return
    end
    return paw.notify("a tuplet is taken away by writing its notes again: select them and `notation.tuplet 2:2`", "warn")
  end
  if not ranged then
    -- The beat under the cursor.
    local m = view:measure_at(view.beat)
    local beat = m.meter.beat
    a = m.start + math.floor((view.beat - m.start) / beat + EPS) * beat
    b = a + beat
  end
  if make_tuplet(a, b, tp.actual, tp.normal) ~= false then paw.notify(tp.actual .. ":" .. tp.normal) end
end

--- The chords of the region into voice `v`, each where it is, where that
--- voice is silent.
function W.voice(ctx)
  local v = tonumber(words(ctx))
  if not v then return false end
  if v < 1 or v > 4 then
    paw.notify("a voice is 1 to 4", "warn")
    return true
  end
  v = math.floor(v)
  view.voice = v
  local r = region(ctx)
  if not r or not view:clip() then return false end
  local ids = chords(ctx)
  local moved = 0
  view:write(function(sc)
    local f = D.frame(sc)
    for _, id in ipairs(ids) do
      local mi, entry, _, at = D.find(sc, id)
      if entry and entry.voice ~= v then
        local t = f.starts[mi] + at
        local was = view.lift(sc, id)
        local clear = true
        for _, it in ipairs(D.sequence(sc, was.staff, v)) do
          if it.ev.kind == "chord" and it.s < t + was.len and it.e > t then clear = false end
        end
        if clear then
          view.drop(sc, was, t, was.len, was.staff, v)
          moved = moved + 1
        else
          view.drop(sc, was, t, was.len)
        end
      end
    end
    if moved == 0 then return false end
  end)
  paw.notify(moved .. (moved == 1 and " chord" or " chords") .. " into voice " .. v .. "; entering in voice " .. v)
  return true
end

-- Commands ----------------------------------------------------------------------------------

local function cmd(name, fn, desc, complete)
  command(name, fn, { range = true, raw = true, desc = desc, complete = complete })
end

local function list_of(items)
  return function(text)
    local out = {}
    for _, it in ipairs(items) do
      local t = type(it) == "table" and it[1] or it
      if t:sub(1, #text) == text then out[#out + 1] = { text = t, desc = type(it) == "table" and it[2] or nil } end
    end
    return out
  end
end
W.list_of = list_of

cmd("notation.tempo", W.tempo, "A tempo mark at the cursor, which the song's tempo follows: `notation.tempo Allegro q=132`, `rit.` over the range, `a tempo`, `off`")
cmd("notation.meter", W.meter, "The time signature from the cursor's bar, the music written again in its bars: `notation.meter 6/8`, `3+3+2/8`, `C`")
cmd("notation.bar", W.bar, "A barline at the cursor (or the range's end): `||`, `|.`, `|:`, `:|`, `:|:`; endings `1.` `2.` over the range; `off`")
cmd("notation.rehearsal", W.rehearsal, "A rehearsal mark at the cursor's bar (the next letter when none is given), and a song marker")
cmd("notation.chord", W.chord, "A chord symbol at the cursor: `notation.chord Cmaj7`, `G/B`, `N.C.`, `off`")
cmd("notation.lyric", W.lyric, "A syllable under the note at the cursor: `notation.lyric la-`; `verse=2` for the second verse")
cmd("notation.orn", W.ornament, "An ornament on the chord or the range: `tr`, `mordent`, `prall`, `turn`, `fermata`, `trem`, `off`")
cmd("notation.tech", W.technique, "A playing technique at the cursor (written): `pizz.`, `arco`, `con sord.`, `off`")
cmd("notation.interval", W.interval, "Add a note an interval above (or below) each chord of the range: `notation.interval 3`, `-6`, `8`, `m3`")
cmd("notation.tuplet", W.tuplet, "The beat (or the range) as a tuplet: `notation.tuplet 3`, `5:4`; in insert mode, enter in it (`off` plain)")

view.write_cmds = W
return W
