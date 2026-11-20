-- MusicXML in and out of score documents (`notation.doc`): what MuseScore,
-- Dorico, Sibelius and Finale write, read into scores, and scores written
-- out so that reading them back gives the same score.
--
--   local file = musicxml.parse(text)  -- { title, composer, parts, skipped }, or nil and why
--   file.parts[i] = { id, name, program, channel, drums, score, tempos, rehearsals }
--   musicxml.read(path)                -- the same from a .musicxml, .xml or .mxl file
--   musicxml.write(parts, opts)        -- the text of a file: parts = { { name, score, fifths, program, drums } }
--
-- A part is one score: its staves (a grand staff is one part of two),
-- each staff's voices (MuseScore's 1 to 4 and 5 to 8 both become 1 to 4),
-- chords and rests with their written values (dots, tuplets from the time
-- modification), ties, grace notes, spelling, key, clef and time changes,
-- barlines, repeats and endings, rehearsal marks, tempo marks (the sound
-- tempo is the bpm), dynamics, hairpins, slurs, text, techniques, chord
-- symbols, articulations, fermatas, ornaments, arpeggios and lyrics in
-- verses with their hyphens and extenders. A pickup is the score's origin.
-- What a score cannot hold is counted in `skipped`, by element name.
local xml = paw.xml
local D = require("notation.doc")

local M = {}

M.extensions = { "musicxml", "mxl", "xml" }

local W, Q = D.W, D.Q
local floor, abs = math.floor, math.abs
local EPS = 1e-6

--- Whether a path names a MusicXML file, by its ending.
function M.is_file(path)
  local ext = (tostring(path):match("%.([^./]+)$") or ""):lower()
  for _, known in ipairs(M.extensions) do
    if ext == known then return true end
  end
  return false
end

local TYPES = { maxima = { 8, 1 }, long = { 4, 1 }, breve = { 2, 1 }, whole = { 1, 1 }, half = { 1, 2 }, quarter = { 1, 4 },
  eighth = { 1, 8 }, ["16th"] = { 1, 16 }, ["32nd"] = { 1, 32 }, ["64th"] = { 1, 64 }, ["128th"] = { 1, 128 },
  ["256th"] = { 1, 256 } }
local TYPE_OF = {}
for name, r in pairs(TYPES) do TYPE_OF[D.ticks(r)] = name end

local STEPS = { C = 0, D = 1, E = 2, F = 3, G = 4, A = 5, B = 6 }
local LETTERS = { [0] = "C", "D", "E", "F", "G", "A", "B" }

local CLEFS = { G2 = "treble", F4 = "bass", C3 = "alto", C4 = "tenor", ["G2-1"] = "treble8", ["F4-1"] = "bass8" }
local CLEF_SIGN = { treble = { "G", 2 }, bass = { "F", 4 }, alto = { "C", 3 }, tenor = { "C", 4 }, treble8 = { "G", 2, -1 }, bass8 = { "F", 4, -1 } }

-- Keys: the root by fifths, and where each mode's root lies from the major's.
local ROOTS = { "Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#", "E#", "B#" }
local MODE_FIFTHS = { major = 0, ionian = 0, minor = 3, aeolian = 3, dorian = 2, phrygian = 4, lydian = -1, mixolydian = 1, locrian = 5 }

--- A key's name as the score keeps it ("Eb major", "D dorian").
function M.key_name(fifths, mode)
  mode = MODE_FIFTHS[mode or ""] and mode or "major"
  if mode == "ionian" then mode = "major" elseif mode == "aeolian" then mode = "minor" end
  local root = ROOTS[fifths + MODE_FIFTHS[mode] + 8]
  return root and (root .. " " .. mode) or nil
end

-- Marks: the names MusicXML gives what the score keeps.
local DYNAMICS = {}
for _, d in ipairs({ "pppp", "ppp", "pp", "p", "mp", "mf", "f", "ff", "fff", "ffff", "sf", "sfz", "sffz", "fz", "rfz", "sfp", "fp" }) do
  DYNAMICS[d] = d
end
DYNAMICS.n, DYNAMICS.niente = "niente", "niente"
DYNAMICS.ppppp, DYNAMICS.pppppp, DYNAMICS.fffff, DYNAMICS.ffffff = "pppp", "pppp", "ffff", "ffff"
DYNAMICS.rf, DYNAMICS.sfpp, DYNAMICS.sfzp = "rfz", "sfp", "sfp"
local ARTICULATIONS = { staccato = "staccato", staccatissimo = "staccatissimo", spiccato = "staccatissimo", accent = "accent",
  ["strong-accent"] = "marcato", tenuto = "tenuto" }
local XML_ART = { staccato = "staccato", staccatissimo = "staccatissimo", accent = "accent", marcato = "strong-accent", tenuto = "tenuto" }
local ORNAMENTS = { ["trill-mark"] = "trill", mordent = "mordent", ["inverted-mordent"] = "prall", turn = "turn",
  ["delayed-turn"] = "turn", ["inverted-turn"] = "turn_inverted", tremolo = "tremolo" }
local XML_ORN = { trill = "trill-mark", mordent = "mordent", prall = "inverted-mordent", turn = "turn", turn_inverted = "inverted-turn",
  tremolo = "tremolo" }
local UNITS = { whole = "w", half = "h", quarter = "q", eighth = "e" }
-- Words that change the tempo, as the tempo popover reads them.
local CHANGES = { ["rit."] = "rit.", rit = "rit.", ritardando = "rit.", ["rall."] = "rit.", rall = "rit.", rallentando = "rit.",
  ["accel."] = "accel.", accel = "accel.", accelerando = "accel.", ["a tempo"] = "a tempo", ["tempo i"] = "a tempo",
  ["tempo primo"] = "a tempo" }
local UNIT_XML = { w = "whole", h = "half", q = "quarter", e = "eighth" }
local UNIT_BEATS = { w = 4, h = 2, q = 1, e = 0.5 }

-- Chord symbols: MusicXML's kinds and the suffixes written for them.
local KINDS = {
  major = "", minor = "m", augmented = "aug", diminished = "dim", dominant = "7", ["major-seventh"] = "maj7",
  ["minor-seventh"] = "m7", ["diminished-seventh"] = "dim7", ["augmented-seventh"] = "aug7", ["half-diminished"] = "m7b5",
  ["major-minor"] = "m(maj7)", ["major-sixth"] = "6", ["minor-sixth"] = "m6", ["dominant-ninth"] = "9", ["major-ninth"] = "maj9",
  ["minor-ninth"] = "m9", ["dominant-11th"] = "11", ["major-11th"] = "maj11", ["minor-11th"] = "m11", ["dominant-13th"] = "13",
  ["major-13th"] = "maj13", ["minor-13th"] = "m13", ["suspended-second"] = "sus2", ["suspended-fourth"] = "sus4", power = "5",
  ["Neapolitan"] = "", ["Italian"] = "", ["French"] = "", ["German"] = "", pedal = "", Tristan = "",
}
local KIND_OF = {}
for kind, suffix in pairs(KINDS) do
  if not KIND_OF[suffix] or #kind < #KIND_OF[suffix] then KIND_OF[suffix] = kind end
end
KIND_OF[""] = "major"

--- The MusicXML kind closest to a chord symbol's suffix.
local function kind_of(suffix)
  if KIND_OF[suffix] then return KIND_OF[suffix] end
  local s = suffix:gsub("%(.*%)", "")
  if KIND_OF[s] then return KIND_OF[s] end
  if s:match("^m7b5") or s:match("^ø") then return "half-diminished" end
  if s:match("^dim7") or s:match("^°7") then return "diminished-seventh" end
  if s:match("^dim") or s:match("^°") then return "diminished" end
  if s:match("^aug") or s:match("^%+") then return "augmented" end
  if s:match("^maj") or s:match("^M") or s:match("^Δ") then return "major-seventh" end
  if s:match("^m") or s:match("^min") or s:match("^%-") then return "minor" end
  if s:match("^sus2") then return "suspended-second" end
  if s:match("^sus") then return "suspended-fourth" end
  if s:match("^13") then return "dominant-13th" end
  if s:match("^11") then return "dominant-11th" end
  if s:match("^9") then return "dominant-ninth" end
  if s:match("^7") then return "dominant" end
  if s:match("^6") then return "major-sixth" end
  return "major"
end

local function gcd(a, b)
  a, b = abs(a), abs(b)
  while b ~= 0 do a, b = b, a % b end
  return a
end

-- Reading ------------------------------------------------------------------------------------------

local function int(v) return v and floor(v + 0.5) end

--- The clef a `<clef>` element names, or nil.
local function clef_of(el)
  local sign, line, oct = xml.text(el, "sign"), xml.number(el, "line"), xml.number(el, "clef-octave-change")
  if sign == "G" and not line then line = 2 end
  if sign == "F" and not line then line = 4 end
  if sign == "C" and not line then line = 3 end
  local key = tostring(sign) .. tostring(line) .. ((oct and oct ~= 0) and tostring(oct) or "")
  return CLEFS[key], sign
end

--- Text of a lyric or words element, the parts of an elision joined.
local function texts(el, name)
  local out = {}
  for _, t in ipairs(xml.children(el, name)) do out[#out + 1] = t.text or "" end
  return table.concat(out, "‿")
end

--- A chord symbol's text from a `<harmony>` element, or nil.
local function harmony_text(h, count)
  local root = xml.child(h, "root")
  local kind = xml.child(h, "kind")
  local kind_name = kind and (kind.text or ""):match("^%s*(.-)%s*$") or "major"
  if kind_name == "none" then return "N.C." end
  if not root then
    count(xml.child(h, "function") and "<function>" or "<harmony> without a root")
    return nil
  end
  local function named(step, alter)
    local a = tonumber(alter or "") or 0
    return step .. (a > 0 and string.rep("#", a) or a < 0 and string.rep("b", -a) or "")
  end
  local text = named(xml.text(root, "root-step") or "C", xml.text(root, "root-alter"))
  if kind and kind.attr.text then
    text = text .. kind.attr.text
  else
    text = text .. (KINDS[kind_name] or "")
    if KINDS[kind_name] == nil then count("<kind>" .. kind_name) end
    for _, dg in ipairs(xml.children(h, "degree")) do
      local value, alter, typ = xml.text(dg, "degree-value"), tonumber(xml.text(dg, "degree-alter") or "") or 0, xml.text(dg, "degree-type")
      local acc = alter > 0 and "#" or alter < 0 and "b" or ""
      if typ == "add" then
        text = text .. "add" .. acc .. value
      elseif typ == "subtract" then
        text = text .. "no" .. value
      else
        text = text .. acc .. value
      end
    end
  end
  local bass = xml.child(h, "bass")
  if bass then text = text .. "/" .. named(xml.text(bass, "bass-step") or "C", xml.text(bass, "bass-alter")) end
  return text
end

--- One `<measure>` read: its notes, directions, chord symbols, barlines and
--- attributes, at places in ticks from its start. `st` is what holds from
--- the measures before (divisions, staves, transposition, instruments).
local function read_measure(el, st, count)
  local rec = { notes = {}, dirs = {}, harmonies = {}, barlines = {}, clefs = {}, implicit = el.attr.implicit == "yes", number = el.attr.number }
  local pos, reach = 0, 0
  local last
  local function ticks(d) return (d or 0) * Q / st.divisions end
  for _, k in ipairs(el.children) do
    local name = k.name
    if name == "attributes" then
      for _, a in ipairs(k.children) do
        local an = a.name
        if an == "divisions" then
          st.divisions = math.max(1, tonumber(a.text or "") or 1)
        elseif an == "key" then
          if a.attr.number and a.attr.number ~= "1" then
            -- A key for one staff of several: the part's key is the first's.
          elseif xml.child(a, "fifths") then
            local fifths = int(xml.number(a, "fifths") or 0)
            -- A transposing part's written key, at concert pitch.
            if st.transpose then fifths = fifths + 7 * st.transpose.chromatic - 12 * st.transpose.diatonic end
            while fifths > 7 do fifths = fifths - 12 end
            while fifths < -7 do fifths = fifths + 12 end
            local mode = xml.text(a, "mode")
            rec.key = { fifths = fifths, mode = MODE_FIFTHS[mode or ""] and mode or "major" }
          else
            count("<key> without fifths")
          end
        elseif an == "time" then
          if xml.child(a, "senza-misura") then
            count("<senza-misura>")
          else
            local beats, kinds = xml.children(a, "beats"), xml.children(a, "beat-type")
            if #beats > 1 then count("<time> of several signatures") end
            local top, den = (beats[1] and beats[1].text or "4"), tonumber(kinds[1] and kinds[1].text or "4") or 4
            local groups, num = {}, 0
            for g in top:gmatch("%d+") do
              groups[#groups + 1] = tonumber(g)
              num = num + tonumber(g)
            end
            if num > 0 then
              rec.time = { num = num, den = den, groups = #groups > 1 and groups or nil,
                symbol = (a.attr.symbol == "common" or a.attr.symbol == "cut") and a.attr.symbol or nil }
            end
          end
        elseif an == "staves" then
          st.staves = math.max(st.staves, tonumber(a.text or "") or 1)
        elseif an == "clef" then
          local staff = tonumber(a.attr.number or "1") or 1
          local clef, sign = clef_of(a)
          if sign == "TAB" then
            st.tab[staff] = true
          elseif sign == "percussion" then
            st.percussion = true
            rec.clefs[#rec.clefs + 1] = { staff = staff, clef = "treble", t = pos }
          elseif clef then
            rec.clefs[#rec.clefs + 1] = { staff = staff, clef = clef, t = pos }
          else
            count("clefs of other kinds")
          end
        elseif an == "transpose" then
          local c, d, o = xml.number(a, "chromatic") or 0, xml.number(a, "diatonic") or 0, xml.number(a, "octave-change") or 0
          st.transpose = (c ~= 0 or d ~= 0 or o ~= 0) and { chromatic = c + 12 * o, diatonic = d + 7 * o } or nil
          if st.transpose and not st.transposed then
            st.transposed = true
            count("transposing parts, written at concert pitch")
          end
        elseif an ~= "measure-style" and an ~= "staff-details" and an ~= "instruments" and an ~= "part-symbol" and an ~= "footnote" then
          count("<" .. an .. ">")
        end
      end
    elseif name == "note" then
      local n = { staff = tonumber(xml.text(k, "staff") or "1") or 1, voice = xml.text(k, "voice") or "1", order = #rec.notes }
      if xml.child(k, "cue") then
        count("cue notes")
      else
        local grace = xml.child(k, "grace")
        local chord = xml.child(k, "chord") ~= nil
        local dur = ticks(tonumber(xml.text(k, "duration") or "") or 0)
        if grace then
          n.grace = grace.attr.slash == "yes" and "acciaccatura" or "appoggiatura"
          dur = 0
        end
        if chord and last then
          n.start, n.chord, n.len = last.start, true, last.len
        else
          n.start, n.len = pos, dur
        end
        local rest = xml.child(k, "rest")
        if rest then
          n.rest, n.measure_rest = true, rest.attr.measure == "yes"
        else
          local p, un = xml.child(k, "pitch"), xml.child(k, "unpitched")
          if p then
            local step, alter, octave = STEPS[xml.text(p, "step") or "C"] or 0, tonumber(xml.text(p, "alter") or "") or 0, int(xml.number(p, "octave") or 4)
            if alter ~= floor(alter) then
              count("microtonal alterations (rounded)")
              alter = int(alter)
            end
            n.pitch = { step = step, alter = alter, octave = octave }
            local tp = st.transpose
            if tp then
              local written = D.pitch(n.pitch)
              local diatonic = D.diatonic(n.pitch) + tp.diatonic
              local s = diatonic % 7
              local o = floor(diatonic / 7) - 1
              n.pitch = { step = s, alter = written + tp.chromatic - D.pitch({ step = s, alter = 0, octave = o }), octave = o }
            end
          elseif un then
            -- A drum's note: where its instrument plays, which the drum kit hears.
            local inst = xml.child(k, "instrument")
            local key = inst and st.unpitched[inst.attr.id or ""]
            if key then
              local sp = require("notation.model").spell(key, 0)
              n.pitch = { step = sp.letter, alter = sp.alter, octave = sp.octave }
            else
              n.pitch = { step = STEPS[xml.text(un, "display-step") or "E"] or 2, alter = 0, octave = int(xml.number(un, "display-octave") or 4) }
            end
          else
            n.rest = true
          end
        end
        n.type = TYPES[xml.text(k, "type") or ""]
        if xml.child(k, "type") and not n.type then count("<type>" .. tostring(xml.text(k, "type"))) end
        n.dots = #xml.children(k, "dot")
        local tm = xml.child(k, "time-modification")
        if tm then
          n.tm = { actual = int(xml.number(tm, "actual-notes") or 1), normal = int(xml.number(tm, "normal-notes") or 1),
            normal_type = TYPES[xml.text(tm, "normal-type") or ""], normal_dots = #xml.children(tm, "normal-dot") }
          if n.tm.actual == n.tm.normal then n.tm = nil end
        end
        for _, t in ipairs(xml.children(k, "tie")) do
          if t.attr.type == "start" then n.tie = true end
        end
        local beam = xml.child(k, "beam")
        for _, b in ipairs(xml.children(k, "beam")) do
          if (b.attr.number or "1") == "1" then beam = b end
        end
        n.beam = beam and (beam.text or ""):match("^%s*(.-)%s*$") or nil
        st.beams = st.beams or beam ~= nil
        local nots = xml.children(k, "notations")
        n.slurs, n.art, n.dyns = {}, {}, {}
        for _, no in ipairs(nots) do
          for _, x in ipairs(no.children) do
            local xn = x.name
            if xn == "tied" then
              if x.attr.type == "start" then n.tie = true end
            elseif xn == "slur" then
              n.slurs[#n.slurs + 1] = { type = x.attr.type, number = x.attr.number or "1" }
            elseif xn == "tuplet" then
              if x.attr.type == "start" then n.tuplet_start = true end
              if x.attr.type == "stop" then n.tuplet_stop = true end
            elseif xn == "articulations" then
              for _, a in ipairs(x.children) do
                if ARTICULATIONS[a.name] then
                  n.art[ARTICULATIONS[a.name]] = true
                elseif a.name == "detached-legato" then
                  n.art.tenuto, n.art.staccato = true, true
                else
                  count("<" .. a.name .. ">")
                end
              end
            elseif xn == "fermata" then
              local shape = (x.text or ""):match("^%s*(.-)%s*$")
              n.art[shape == "angled" and "fermata_short" or shape == "square" and "fermata_long" or "fermata"] = true
            elseif xn == "ornaments" then
              for _, o in ipairs(x.children) do
                if ORNAMENTS[o.name] and not (o.name == "tremolo" and o.attr.type and o.attr.type ~= "single") then
                  n.orn = ORNAMENTS[o.name]
                elseif o.name ~= "wavy-line" then
                  count("<" .. o.name .. ">")
                end
              end
            elseif xn == "arpeggiate" then
              n.arpeggio = x.attr.direction == "down" and "down" or "up"
            elseif xn == "dynamics" then
              for _, d in ipairs(x.children) do n.dyns[#n.dyns + 1] = d.name == "other-dynamics" and (d.text or "") or d.name end
            elseif xn == "technical" then
              for _, t in ipairs(x.children) do count("<" .. t.name .. ">") end
            else
              count("<" .. xn .. ">")
            end
          end
        end
        n.lyrics = {}
        for _, ly in ipairs(xml.children(k, "lyric")) do
          local number = ly.attr.number or ly.attr.name or "1"
          local verse = st.verses[number]
          if not verse then
            verse = tonumber(number) and floor(tonumber(number)) or nil
            if not verse or verse < 1 then
              st.verse_count = st.verse_count + 1
              verse = st.verse_count
            end
            st.verses[number] = verse
            st.verse_count = math.max(st.verse_count, verse)
          end
          local text = texts(ly, "text")
          local syl = xml.text(ly, "syllabic")
          if syl == "begin" or syl == "middle" then text = text .. "-" end
          if xml.child(ly, "extend") and (xml.child(ly, "extend").attr.type or "start") == "start" then text = text .. "_" end
          if text ~= "" then n.lyrics[#n.lyrics + 1] = { verse = verse, text = text } end
        end
        rec.notes[#rec.notes + 1] = n
        last = n
        if not chord and not n.grace then pos = pos + dur end
        reach = math.max(reach, pos, n.start + (n.len or 0))
      end
    elseif name == "backup" then
      pos = math.max(0, pos - ticks(xml.number(k, "duration")))
    elseif name == "forward" then
      pos = pos + ticks(xml.number(k, "duration"))
      reach = math.max(reach, pos)
    elseif name == "direction" then
      local t = pos + ticks(xml.number(k, "offset") or 0)
      local dir = { t = t, words = {}, dyns = {}, staff = tonumber(xml.text(k, "staff") or "1") or 1 }
      for _, dt in ipairs(xml.children(k, "direction-type")) do
        for _, x in ipairs(dt.children) do
          local xn = x.name
          if xn == "words" then
            local w = (x.text or ""):match("^%s*(.-)%s*$")
            if w ~= "" then dir.words[#dir.words + 1] = w end
          elseif xn == "dynamics" then
            for _, d in ipairs(x.children) do dir.dyns[#dir.dyns + 1] = d.name == "other-dynamics" and (d.text or "") or d.name end
          elseif xn == "wedge" then
            dir.wedges = dir.wedges or {}
            dir.wedges[#dir.wedges + 1] = { type = x.attr.type, number = x.attr.number or "1", niente = x.attr.niente == "yes" }
          elseif xn == "metronome" then
            local unit = xml.text(x, "beat-unit")
            if xml.child(x, "per-minute") then
              dir.unit = UNITS[unit or ""] and (UNITS[unit] .. (xml.child(x, "beat-unit-dot") and "." or "")) or nil
              dir.per = tonumber((xml.text(x, "per-minute") or ""):match("[%d%.]+") or "")
              dir.unit_beats = TYPES[unit or ""] and D.ticks(TYPES[unit]) / Q * (xml.child(x, "beat-unit-dot") and 1.5 or 1) or 1
            else
              count("metric modulations")
            end
          elseif xn == "rehearsal" then
            rec.rehearsal = rec.rehearsal or (x.text or ""):match("^%s*(.-)%s*$")
          else
            count("<" .. xn .. ">")
          end
        end
      end
      local sound = xml.child(k, "sound")
      dir.tempo = sound and tonumber(sound.attr.tempo or "")
      rec.dirs[#rec.dirs + 1] = dir
    elseif name == "harmony" then
      local text = harmony_text(k, count)
      if text then rec.harmonies[#rec.harmonies + 1] = { t = pos + ticks(xml.number(k, "offset") or 0), value = text } end
    elseif name == "barline" then
      rec.barlines[#rec.barlines + 1] = k
    elseif name == "sound" then
      if tonumber(k.attr.tempo or "") then rec.dirs[#rec.dirs + 1] = { t = pos, words = {}, dyns = {}, tempo = tonumber(k.attr.tempo), silent = true } end
    elseif name == "print" then
      if k.attr["new-system"] == "yes" or k.attr["new-page"] == "yes" then rec.new_system = true end
    else
      count("<" .. name .. ">")
    end
  end
  rec.length = reach
  return rec
end

--- How a part's voices on each staff are numbered in the score: MuseScore's
--- 5 to 8 on a second staff are 1 to 4 there, as are Finale's 1 to 4 on
--- every staff; any other numbering is taken in order.
local function voice_maps(recs, count)
  local seen = {}
  for _, rec in ipairs(recs) do
    for _, n in ipairs(rec.notes) do
      seen[n.staff] = seen[n.staff] or {}
      seen[n.staff][n.voice] = true
    end
  end
  local maps = {}
  for staff, set in pairs(seen) do
    local list = {}
    for v in pairs(set) do list[#list + 1] = v end
    table.sort(list, function(a, b)
      local x, y = tonumber(a), tonumber(b)
      if x and y then return x < y end
      return tostring(a) < tostring(b)
    end)
    local map, used, plain = {}, {}, true
    for _, v in ipairs(list) do
      local n = tonumber(v)
      local local_v = n and ((floor(n) - 1) % 4) + 1
      if not local_v or used[local_v] then plain = false end
      if local_v then used[local_v] = true end
      map[v] = local_v
    end
    if not plain or not used[1] then
      map = {}
      for i, v in ipairs(list) do
        if i <= 4 then map[v] = i else count("voices past the fourth on a staff") end
      end
    end
    maps[staff] = map
  end
  return maps
end

--- The written value of a note: `dur`, `dots`, from its type, or from how
--- long it lasts when it has no type (or one that does not fit it).
local function value_of(n, count)
  local dur, dots = n.type, n.dots
  local function length(r, d)
    local base = D.ticks(r)
    local len, add = base, base
    for _ = 1, d do
      add = add / 2
      len = len + add
    end
    if n.tm then len = len * n.tm.normal / n.tm.actual end
    return len
  end
  if n.grace then return dur or { 1, 8 }, dots end
  if dur and abs(length(dur, dots) - n.len) <= 2 then return dur, dots end
  local written = n.tm and n.len * n.tm.actual / n.tm.normal or n.len
  local base, d = require("notation.model").value_of(written / Q, 2)
  if base then
    if dur then count("notes whose type and duration differ (the duration kept)") end
    return D.ratio(D.from_beats(base)), d
  end
  count("values no single note shows")
  return D.ratio(int(written)), 0
end

--- Build the voices of one measure of the score from its notes.
local function build_voices(sc, m, rec, staves, maps, len, meter, out)
  local groups = {}
  local by_key = {}
  for _, n in ipairs(rec.notes) do
    local staff = staves[n.staff]
    local v = maps[n.staff] and maps[n.staff][n.voice]
    if staff and v and not out.tab[n.staff] then
      local key = staff .. ":" .. v
      local g = by_key[key]
      if not g then
        g = { staff = staff, voice = v, notes = {} }
        by_key[key] = g
        groups[#groups + 1] = g
      end
      g.notes[#g.notes + 1] = n
    elseif out.tab[n.staff] then
      out.count("notes on tablature staves (the staff above has them)")
    end
  end
  table.sort(groups, function(a, b)
    if a.staff ~= b.staff then return a.staff < b.staff end
    return a.voice < b.voice
  end)
  for _, g in ipairs(groups) do
    -- Events in time, a chord's notes joined, grace notes before their note.
    table.sort(g.notes, function(a, b)
      if abs(a.start - b.start) > EPS then return a.start < b.start end
      if (a.grace ~= nil) ~= (b.grace ~= nil) then return a.grace ~= nil end
      return a.order < b.order
    end)
    local evs = {}
    local open   -- the tuplet being filled: { tp, filled, span }
    for _, n in ipairs(g.notes) do
      local prev = evs[#evs]
      if n.chord and prev and not prev.rest and abs(prev.start - n.start) < EPS and (prev.grace ~= nil) == (n.grace ~= nil) and n.pitch then
        prev.ev.notes[#prev.ev.notes + 1] = { id = D.id(sc, "n"), step = n.pitch.step, alter = n.pitch.alter, octave = n.pitch.octave, tie = n.tie }
        prev.srcs[#prev.srcs + 1] = n
      elseif n.measure_rest or (n.rest and not n.grace and not n.tm and abs(n.start) < EPS and abs(n.len - len) <= 2 and not n.type) then
        -- A whole bar's rest is the voice's silence.
        open = nil
      else
        local dur, dots = value_of(n, out.count)
        local ev = { id = D.id(sc, "e"), kind = n.rest and "rest" or "chord", dur = dur, dots = dots > 0 and dots or 0 }
        if n.grace then ev.grace = n.grace end
        if n.tm and not n.grace then
          local fresh = n.tuplet_start or not open or open.tp.actual ~= n.tm.actual or open.tp.normal ~= n.tm.normal or open.filled >= open.span - 2
          if fresh then
            local unit = n.tm.normal_type and D.ticks(n.tm.normal_type) * (n.tm.normal_dots > 0 and 1.5 or 1) or D.ticks(dur) * (dots > 0 and 1.5 or 1)
            open = { tp = { id = D.id(sc, "t"), actual = n.tm.actual, normal = n.tm.normal }, filled = 0, span = n.tm.normal * unit }
          end
          ev.tuplet = open.tp
        elseif not n.grace then
          open = nil
        end
        if n.pitch and not n.rest then ev.notes = { { id = D.id(sc, "n"), step = n.pitch.step, alter = n.pitch.alter, octave = n.pitch.octave, tie = n.tie } } end
        local item = { ev = ev, start = n.start, rest = n.rest, grace = n.grace, srcs = { n } }
        evs[#evs + 1] = item
        if ev.tuplet then
          open.filled = open.filled + D.length(ev)
          if n.tuplet_stop then open = nil end
        end
      end
    end
    -- Rests where nothing is written, and what overlaps dropped.
    local list, t = {}, 0
    local any = false
    for _, it in ipairs(evs) do
      local s = int(it.start)
      local function rests_to(b)
        for _, p in ipairs(D.values(t, b, meter, true)) do list[#list + 1] = { id = D.id(sc, "e"), kind = "rest", dur = p.dur, dots = p.dots } end
        t = b
      end
      if (it.grace and s < t) or (not it.grace and s < t - 2) then
        out.count("notes overlapping others in their voice")
      else
        if s > t + (it.grace and 0 or 2) then rests_to(s) end
        list[#list + 1] = it.ev
        it.at = math.max(s, t)
        t = it.at + D.length(it.ev)
        any = any or it.ev.kind == "chord"
        out.placed[#out.placed + 1] = it
      end
    end
    if any then
      if t < len - 2 then rests_to(len) end
      m.voices[#m.voices + 1] = { staff = g.staff, voice = g.voice, events = list }
    end
  end
end

--- Read one part's measures into a score.
local function read_part(part_el, info, count)
  local st = { divisions = 1, staves = 1, tab = {}, unpitched = info.unpitched or {}, verses = {}, verse_count = 0 }
  local recs = {}
  for _, mel in ipairs(xml.children(part_el, "measure")) do recs[#recs + 1] = read_measure(mel, st, count) end
  local maps = voice_maps(recs, count)
  local sc = { version = 1, staves = {}, measures = {}, marks = {}, style = {}, next = 1 }
  -- Staves and their clefs where the part starts.
  local first_clef = {}
  for _, c in ipairs(recs[1] and recs[1].clefs or {}) do
    if c.t < EPS and not first_clef[c.staff] then first_clef[c.staff] = c.clef end
  end
  local staves, count_staves = {}, 0
  for s = 1, st.staves do
    if not st.tab[s] then
      count_staves = count_staves + 1
      local id = "s" .. count_staves
      sc.staves[count_staves] = { id = id, clef = first_clef[s] or (s == 2 and "bass" or "treble") }
      staves[s] = id
    else
      count("tablature staves (the staff above has their notes)")
    end
  end
  if count_staves == 0 then
    sc.staves[1] = { id = "s1", clef = "treble" }
    staves[1] = "s1"
  end
  sc.next = count_staves + 1
  for i in ipairs(recs) do
    sc.measures[i] = { id = D.id(sc, "m"), voices = {}, v = D.token() }
  end
  -- Each measure's length: its time signature's, or a pickup's (the
  -- score's origin), or one of its own for a bar shorter or longer.
  local meter, written, key_now, clefs_now = { num = 4, den = 4 }, nil, nil, {}
  for s, id in pairs(staves) do clefs_now[s] = first_clef[s] or (s == 2 and "bass" or "treble") end
  local origin = 0
  local out = { count = count, placed = {}, tab = st.tab }
  local pending_clefs = {}
  local tempos, rehearsals = {}, {}
  local wedges, slurs = {}, {}
  local f_starts, at = {}, 0
  for i, rec in ipairs(recs) do
    local m = sc.measures[i]
    if rec.time then
      meter = rec.time
      if rec.time.symbol then m.meter_symbol = rec.time.symbol end
    end
    local nominal = meter.num * W / meter.den
    local len, num, den = nominal, meter.num, meter.den
    local shift = 0
    if rec.length > EPS and abs(rec.length - nominal) > 2 then
      if i == 1 and rec.length < nominal then
        -- A pickup: the bar starts before the clip.
        shift = nominal - int(rec.length)
        origin = -shift
      elseif not (i == #recs and rec.length < nominal) then
        -- A bar of another length, given a time signature of its own.
        len = int(rec.length)
        den = meter.den
        while (len * den) % W ~= 0 and den < 256 do den = den * 2 end
        num = floor(len * den / W + 0.5)
        count("bars of other lengths than their time signature's, given their own")
      end
    end
    local want = { num, den, groups = (num == meter.num and den == meter.den) and meter.groups or nil }
    if not written or written[1] ~= want[1] or written[2] ~= want[2] or tostring(written.groups and table.concat(written.groups, "+")) ~= tostring(want.groups and table.concat(want.groups, "+")) then
      m.meter, m.groups = { num, den }, want.groups
      written = want
    end
    sc._frame = nil
    local mt = { num, den, groups = want.groups }
    f_starts[i] = at
    -- Everything in the bar moves by a pickup's empty start.
    if shift > 0 then
      for _, n in ipairs(rec.notes) do n.start = n.start + shift end
      for _, d in ipairs(rec.dirs) do d.t = d.t + shift end
      for _, h in ipairs(rec.harmonies) do h.t = h.t + shift end
      for _, c in ipairs(rec.clefs) do c.t = c.t + shift end
    end
    if rec.key then
      if i == 1 or not key_now or key_now.fifths ~= rec.key.fifths or key_now.mode ~= rec.key.mode then
        m.key = { fifths = rec.key.fifths, name = M.key_name(rec.key.fifths, rec.key.mode) }
      end
      key_now = rec.key
    end
    for _, c in ipairs(pending_clefs) do
      local id = staves[c.staff]
      if id and clefs_now[c.staff] ~= c.clef then
        m.clef = m.clef or {}
        m.clef[id], clefs_now[c.staff] = c.clef, c.clef
      end
    end
    pending_clefs = {}
    for _, c in ipairs(rec.clefs) do
      if c.t >= len - 2 and i < #recs then
        -- A clef at the end of a bar is the next one's.
        pending_clefs[#pending_clefs + 1] = c
      elseif i > 1 or c.t > shift + EPS then
        if c.t > shift + EPS then count("clef changes inside a bar (written at its start)") end
        local id = staves[c.staff]
        if id and clefs_now[c.staff] ~= c.clef then
          m.clef = m.clef or {}
          m.clef[id], clefs_now[c.staff] = c.clef, c.clef
        end
      end
    end
    -- Barlines, repeats and endings.
    for _, b in ipairs(rec.barlines) do
      local loc = b.attr.location or "right"
      local style = xml.text(b, "bar-style")
      local rep = xml.child(b, "repeat")
      local ending = xml.child(b, "ending")
      if rep and rep.attr.direction == "forward" then m.repeat_start = true end
      if rep and rep.attr.direction == "backward" then
        m.barline = ":|"
      elseif loc == "right" and style == "light-light" then
        m.barline = "||"
      elseif loc == "right" and style == "light-heavy" then
        m.barline = "|."
      elseif style and style ~= "regular" and not (loc == "left" and style == "heavy-light") and not (loc == "right" and style == "light-heavy") then
        count("barlines of style " .. style)
      end
      if ending then
        local number = tonumber((ending.attr.number or ""):match("%d+") or "")
        if (ending.attr.number or ""):match("%d+%D+%d") then count("endings of several numbers (the first kept)") end
        if ending.attr.type == "start" and number then
          out.volta = { from = i, number = number }
        elseif (ending.attr.type == "stop" or ending.attr.type == "discontinue") and out.volta then
          for k = out.volta.from, i do sc.measures[k].volta = out.volta.number end
          out.volta = nil
        end
      end
    end
    if rec.rehearsal and rec.rehearsal ~= "" then
      m.rehearsal = rec.rehearsal
      rehearsals[#rehearsals + 1] = { t = at, name = rec.rehearsal }
    end
    if rec.new_system and i > 1 then
      sc.layout = sc.layout or { breaks = {} }
      sc.layout.breaks[#sc.layout.breaks + 1] = { id = D.id(sc, "l"), measure = m.id, kind = "break" }
    end
    out.placed = {}
    build_voices(sc, m, rec, staves, maps, len, mt, out)
    local function ref(t) return { measure = m.id, at = D.ratio(math.max(0, math.min(len, int(t)))) } end
    for _, it in ipairs(out.placed) do
      local n0 = it.srcs[1]
      local staff = staves[n0.staff]
      local ev = it.ev
      local art, lyrics = {}, {}
      for _, n in ipairs(it.srcs) do
        for k in pairs(n.art or {}) do art[k] = true end
        if n.orn then ev.orn = n.orn end
        if n.arpeggio then ev.arpeggio = n.arpeggio end
        for _, ly in ipairs(n.lyrics or {}) do lyrics[ly.verse] = lyrics[ly.verse] or ly.text end
        for _, d in ipairs(n.dyns or {}) do
          if DYNAMICS[d] then
            sc.marks[#sc.marks + 1] = { id = D.id(sc, "k"), kind = "dynamic", from = ref(it.at), value = DYNAMICS[d] }
          else
            count("dynamics of other kinds")
          end
        end
        for _, sl in ipairs(n.slurs or {}) do
          local key = staff .. ":" .. sl.number
          if sl.type == "start" then
            slurs[key] = { staff = staff, from = ref(it.at) }
          elseif sl.type == "stop" and slurs[key] then
            sc.marks[#sc.marks + 1] = { id = D.id(sc, "k"), kind = "slur", staff = staff, from = slurs[key].from, to = ref(it.at) }
            slurs[key] = nil
          elseif sl.type == "stop" then
            count("slurs with no start")
          end
        end
      end
      if ev.kind == "chord" then
        if next(art) then ev.art = art end
        local most = 0
        for verse in pairs(lyrics) do most = math.max(most, verse) end
        if lyrics[1] then ev.lyric = lyrics[1] end
        if most > 1 then
          ev.lyrics = {}
          for verse = 2, most do ev.lyrics[verse - 1] = lyrics[verse] or "" end
        end
        -- The beam the file gives it, for `beam_breaks`.
        if not it.grace then it.ev._xbeam = n0.beam or "none" end
      elseif next(art) then
        count("fermatas on rests")
      end
    end
    -- Directions: dynamics, hairpins, text, techniques, tempo.
    local write_cmds = require("notation.write")
    for _, d in ipairs(rec.dirs) do
      local words = table.concat(d.words, " ")
      local lower = words:lower()
      local subito = false
      for _, dy in ipairs(d.dyns) do
        if DYNAMICS[dy] then
          subito = lower == "subito" or lower == "sub." or lower == "sub"
          sc.marks[#sc.marks + 1] = { id = D.id(sc, "k"), kind = "dynamic", from = ref(d.t), value = DYNAMICS[dy], subito = subito or nil }
        else
          count("dynamics of other kinds")
        end
      end
      if subito then words = "" end
      for _, w in ipairs(d.wedges or {}) do
        local key = w.number
        if w.type == "crescendo" or w.type == "diminuendo" then
          wedges[key] = { from = ref(d.t), value = w.type == "crescendo" and "cresc" or "dim", niente = w.niente }
        elseif w.type == "stop" and wedges[key] then
          local h = wedges[key]
          sc.marks[#sc.marks + 1] = { id = D.id(sc, "k"), kind = "hairpin", from = h.from, to = ref(d.t), value = h.value,
            niente = (h.niente or w.niente) or nil }
          wedges[key] = nil
        end
      end
      local change = CHANGES[lower]
      local first_word = words:match("^(%a+)")
      local named = first_word and write_cmds.TEMPOS[first_word:sub(1, 1):upper() .. first_word:sub(2):lower()]
      if d.silent then
        tempos[#tempos + 1] = { t = at + d.t, bpm = d.tempo }
      elseif d.per or d.tempo or change or named then
        local text = words
        if d.unit and d.per then text = (text ~= "" and (text .. " ") or "") .. d.unit .. "=" .. (d.per == floor(d.per) and string.format("%d", d.per) or tostring(d.per)) end
        local bpm = d.tempo or (d.per and d.per * (d.unit_beats or 1)) or nil
        if text == "" and bpm then text = "q=" .. string.format("%g", bpm) end
        sc.marks[#sc.marks + 1] = { id = D.id(sc, "k"), kind = "tempo", from = ref(d.t), value = text, bpm = bpm, change = change }
        if bpm then tempos[#tempos + 1] = { t = at + d.t, bpm = bpm } end
      elseif words ~= "" then
        local technique
        for _, tq in ipairs(write_cmds.TECHNIQUES) do
          if tq:lower() == lower then technique = tq end
        end
        sc.marks[#sc.marks + 1] = { id = D.id(sc, "k"), kind = technique and "technique" or "text", from = ref(d.t), value = words }
      end
    end
    for _, h in ipairs(rec.harmonies) do
      sc.marks[#sc.marks + 1] = { id = D.id(sc, "k"), kind = "chord", from = ref(h.t), value = h.value }
    end
    at = at + len
  end
  for _ in pairs(slurs) do count("slurs with no end") end
  for _ in pairs(wedges) do count("hairpins with no end") end
  sc.origin = D.ratio(origin)
  sc._frame = nil
  for _, s in ipairs(sc.staves) do
    for v = 1, 4 do D.fix_ties(sc, s.id, v, 1, #sc.measures) end
  end
  sc.rev = D.token()
  return sc, { tempos = tempos, rehearsals = rehearsals, percussion = st.percussion, beams = st.beams }
end

--- Beams as the file has them where they break what the metre would join:
--- a `beam = "break"` on each chord whose beam starts afresh in the file
--- but continues on the page.
local function beam_breaks(sc, beamed)
  local L = require("notation.layout")
  local length = (D.origin(sc) + D.frame(sc).finish) / Q
  for _ = 1, beamed and 3 or 0 do
    local changed = false
    local layout = L.layout(sc, { length = length })
    for _, m in ipairs(layout.measures) do
      for _, evs in ipairs(m.staves) do
        local prev = {}
        for _, ev in ipairs(evs) do
          if ev.kind == "note" and ev.source then
            local before = prev[ev.voice]
            local x = ev.source._xbeam
            if before and ev.beam and before.beam == ev.beam and (x == "begin" or x == "none") and ev.source.beam ~= "break" then
              ev.source.beam = "break"
              changed = true
            end
            prev[ev.voice] = ev
          elseif ev.kind == "rest" then
            prev[ev.voice] = nil
          end
        end
      end
    end
    if not changed then break end
    for _, m in ipairs(sc.measures) do m.v = D.token() end
    sc.rev = D.token()
  end
  for _, m in ipairs(sc.measures) do
    for _, entry in ipairs(m.voices) do
      for _, ev in ipairs(entry.events) do ev._xbeam = nil end
    end
  end
end

--- Read the text of a MusicXML file (partwise or timewise). Returns
--- `{ title, composer, parts, skipped }`, or nil and why.
function M.parse(text)
  local root, err = xml.decode(text)
  if not root then return nil, "not XML: " .. tostring(err) end
  if root.name == "score-timewise" then
    -- Measures of parts into parts of measures.
    local parts, order = {}, {}
    for _, mel in ipairs(xml.children(root, "measure")) do
      for _, p in ipairs(xml.children(mel, "part")) do
        local id = p.attr.id or "P1"
        if not parts[id] then
          parts[id] = { name = "part", attrs = { id = id }, kids = {} }
          order[#order + 1] = parts[id]
        end
        local copy = { name = "measure", attrs = mel.attr, kids = p.children }
        table.insert(parts[id].children, copy)
      end
    end
    local kids = {}
    for _, k in ipairs(root.children) do
      if k.name ~= "measure" then kids[#kids + 1] = k end
    end
    for _, p in ipairs(order) do kids[#kids + 1] = p end
    root = { name = "score-partwise", attrs = root.attr, kids = kids }
  end
  if root.name ~= "score-partwise" then return nil, "not a MusicXML score (its root is <" .. root.name .. ">)" end
  local file = { parts = {}, skipped = {} }
  local function count(what) file.skipped[what] = (file.skipped[what] or 0) + 1 end
  file.title = xml.text(xml.child(root, "work"), "work-title") or xml.text(root, "movement-title")
  for _, c in ipairs(xml.children(xml.child(root, "identification"), "creator")) do
    if c.attr.type == "composer" then file.composer = (c.text or ""):match("^%s*(.-)%s*$") end
  end
  if file.title == "" then file.title = nil end
  local infos = {}
  for _, sp in ipairs(xml.children(xml.child(root, "part-list"), "score-part")) do
    local info = { id = sp.attr.id, name = xml.text(sp, "part-name"), unpitched = {} }
    if not info.name or info.name == "" then info.name = xml.text(sp, "part-abbreviation") end
    local inst = xml.child(sp, "score-instrument")
    if (not info.name or info.name == "") and inst then info.name = xml.text(inst, "instrument-name") end
    for _, mi in ipairs(xml.children(sp, "midi-instrument")) do
      info.channel = info.channel or xml.number(mi, "midi-channel")
      info.program = info.program or xml.number(mi, "midi-program")
      local key = xml.number(mi, "midi-unpitched")
      if key and mi.attr.id then info.unpitched[mi.attr.id] = int(key) - 1 end
    end
    infos[info.id or ""] = info
  end
  for i, p in ipairs(xml.children(root, "part")) do
    local info = infos[p.attr.id or ""] or { id = p.attr.id, unpitched = {} }
    local sc, extra = read_part(p, info, count)
    -- A file with no beams at all leaves them to the metre.
    beam_breaks(sc, extra.beams)
    file.parts[#file.parts + 1] = {
      id = info.id, name = (info.name and info.name ~= "") and info.name or ("Part " .. i), score = sc,
      program = info.program and int(info.program) - 1 or nil, channel = info.channel and int(info.channel) or nil,
      drums = info.channel == 10 or extra.percussion or false, tempos = extra.tempos, rehearsals = extra.rehearsals,
    }
  end
  if #file.parts == 0 then return nil, "there are no parts in it" end
  return file
end

--- The text of a .musicxml, .xml or .mxl file (unzipped), or nil and why.
function M.read_text(path)
  local f, err = io.open(path, "rb")
  if not f then return nil, (tostring(err):gsub("^[^:]*: ", "")) end
  local data = f:read("*a")
  f:close()
  if data:sub(1, 4) ~= "PK\3\4" then return data end
  local files, why = paw.zip.read(data)
  if not files then return nil, why end
  -- The score the container names, else the first that is not the container.
  local container = files["META-INF/container.xml"]
  local root = container and xml.decode(container)
  if root then
    for _, rf in ipairs(xml.children(xml.child(root, "rootfiles"), "rootfile")) do
      local name = rf.attr["full-path"]
      if name and files[name] and (rf.attr["media-type"] or "application/vnd.recordare.musicxml+xml"):match("musicxml") then return files[name] end
    end
  end
  local names = {}
  for name in pairs(files) do
    if not name:match("^META%-INF/") and name:lower():match("%.x?m?l?$") and (name:lower():match("%.musicxml$") or name:lower():match("%.xml$")) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  if names[1] then return files[names[1]] end
  return nil, "no score in the archive"
end

--- Read a MusicXML file from disk: as `parse`, or nil and why.
function M.read(path)
  local text, why = M.read_text(path)
  if not text then return nil, why end
  return M.parse(text)
end

--- What was left out of a file, as one line, or nil.
function M.skipped_text(file)
  local list = {}
  for what, n in pairs(file.skipped) do list[#list + 1] = n .. " " .. what end
  table.sort(list)
  return #list > 0 and table.concat(list, ", ") or nil
end

-- Writing ------------------------------------------------------------------------------------------

local esc = xml.escape

--- The type and dots MusicXML names a written value by, or nil.
local function type_of(dur) return TYPE_OF[D.ticks(dur)] end

--- Every tick count a score's file has to say: what its divisions must divide.
local function divisions_of(scores)
  local g = Q
  for _, sc in ipairs(scores) do
    local f = D.frame(sc)
    g = gcd(g, D.origin(sc))
    for i = 1, f.count do g = gcd(g, f.lengths[i]) end
    D.each(sc, function(ev, _, _, _, s, e)
      g = gcd(g, e - s)
      g = gcd(g, s)
    end)
    for _, mk in ipairs(sc.marks or {}) do
      for _, key in ipairs({ "from", "to" }) do
        local r = mk[key]
        if r and r.at then g = gcd(g, D.ticks(r.at)) end
      end
    end
  end
  if g == 0 then g = Q end
  return Q / g, g
end

--- Beam values of a measure's staff, by level: begin, continue, end, or a
--- hook for a part beam (the layout's beams).
local function beam_values(evs)
  local groups, out = {}, {}
  for _, ev in ipairs(evs) do
    if ev.beam then
      groups[ev.beam] = groups[ev.beam] or {}
      table.insert(groups[ev.beam], ev)
    end
  end
  for _, list in pairs(groups) do
    for i, ev in ipairs(list) do
      local levels = {}
      for level = 1, ev.flags or 0 do
        local prev = list[i - 1] and (list[i - 1].flags or 0) >= level
        local nxt = list[i + 1] and (list[i + 1].flags or 0) >= level
        if prev and nxt then
          levels[level] = "continue"
        elseif nxt then
          levels[level] = "begin"
        elseif prev then
          levels[level] = "end"
        else
          levels[level] = list[i + 1] and "forward hook" or "backward hook"
        end
      end
      out[ev.sid] = levels
    end
  end
  return out
end

--- A chord symbol's `<harmony>`.
local function harmony_xml(text)
  if text == "N.C." then return '<root><root-step>C</root-step></root><kind text="N.C.">none</kind>' end
  local root, acc, rest = text:match("^([A-G])([#b]*)(.*)$")
  if not root then return nil end
  local bass_step, bass_acc
  local before, b, ba = rest:match("^(.*)/([A-G])([#b]*)$")
  if before then rest, bass_step, bass_acc = before, b, ba end
  local function alter(a)
    local n = select(2, a:gsub("#", "")) - select(2, a:gsub("b", ""))
    return n ~= 0 and ("<root-alter>" .. n .. "</root-alter>") or ""
  end
  local out = "<root><root-step>" .. root .. "</root-step>" .. alter(acc) .. "</root>"
    .. '<kind text="' .. esc(rest) .. '">' .. kind_of(rest) .. "</kind>"
  if bass_step then out = out .. "<bass><bass-step>" .. bass_step .. "</bass-step>" .. alter(bass_acc):gsub("root", "bass") .. "</bass>" end
  return out
end

--- One part's measures as MusicXML lines.
local function part_xml(w, part, pid, divisions, g)
  local sc = part.score
  local f = D.frame(sc)
  local origin = D.origin(sc)
  local L = require("notation.layout")
  local layout = L.layout(sc, { length = (origin + f.finish) / Q, fifths = part.fifths or 0 })
  local write_cmds = require("notation.write")
  local nstaves = #sc.staves
  local function dv(t) return floor(t / g + 0.5) end
  -- What the layout decided: accidentals, stems, beams, by score ids.
  local shown, notes_shown = {}, {}
  for mi, lm in ipairs(layout.measures) do
    for _, evs in ipairs(lm.staves) do
      local beams = beam_values(evs)
      for _, ev in ipairs(evs) do
        if ev.sid and ev.sid ~= "" then shown[ev.sid] = { stem = ev.stem, beams = beams[ev.sid] } end
        for _, n in ipairs(ev.notes or {}) do notes_shown[n.id] = n end
        for _, gn in ipairs(ev.grace or {}) do notes_shown[gn.id] = gn end
      end
    end
  end
  -- Ties into each note, through each voice.
  local tied_in = {}
  for _, s in ipairs(sc.staves) do
    for v = 1, 4 do
      local seq = D.sequence(sc, s.id, v)
      local prev
      for _, it in ipairs(seq) do
        if it.ev.kind == "chord" and not it.ev.grace then
          if prev and prev.e == it.s then
            for _, n in ipairs(it.ev.notes) do
              for _, p in ipairs(prev.ev.notes) do
                if p.tie and D.pitch(p) == D.pitch(n) then tied_in[n.id] = true end
              end
            end
          end
          prev = it
        elseif it.ev.kind == "rest" then
          prev = nil
        end
      end
    end
  end
  -- Slurs: from the first chord at or after their start to the last at or
  -- before their end, on their staff, as the page draws them; numbered so
  -- that slurs that overlap differ.
  local chords_by_staff = {}
  D.each(sc, function(ev, _, staff, voice, s)
    if ev.kind == "chord" and not ev.grace then
      local tied = true
      for _, n in ipairs(ev.notes) do tied = tied and tied_in[n.id] or false end
      if not tied then
        chords_by_staff[staff] = chords_by_staff[staff] or {}
        table.insert(chords_by_staff[staff], { ev = ev, s = s, voice = voice })
      end
    end
  end)
  local midi = require("notation.midi")
  local slur_start, slur_stop = {}, {}
  local slur_list = {}
  for _, mk in ipairs(sc.marks or {}) do
    if mk.kind == "slur" then
      local a, b = midi.at_of(sc, f, mk.from), midi.at_of(sc, f, mk.to)
      -- It ends in the voice it starts in, when that voice has a chord there.
      local first, last
      local list = chords_by_staff[mk.staff or sc.staves[1].id] or {}
      for _, c in ipairs(list) do
        if a and b and c.s >= a and c.s <= b and (not first or c.s < first.s or (c.s == first.s and c.voice < first.voice)) then first = c end
      end
      for _, c in ipairs(list) do
        if first and c.s >= a and c.s <= b and (not last or c.s > last.s or (c.s == last.s and c.voice == first.voice)) then last = c end
      end
      if first and last and first ~= last then slur_list[#slur_list + 1] = { first = first, last = last } end
    end
  end
  table.sort(slur_list, function(x, y) return x.first.s < y.first.s end)
  local ends = {}
  for _, sl in ipairs(slur_list) do
    local number = 1
    while ends[number] and ends[number] >= sl.first.s do number = number + 1 end
    ends[number] = sl.last.s
    slur_start[sl.first.ev.id] = slur_start[sl.first.ev.id] or {}
    table.insert(slur_start[sl.first.ev.id], number)
    slur_stop[sl.last.ev.id] = slur_stop[sl.last.ev.id] or {}
    table.insert(slur_stop[sl.last.ev.id], number)
  end
  -- Directions and chord symbols, by measure: `{ t, xml, harmony }`.
  local dirs = {}
  local function put(mi, t, text, harmony)
    dirs[mi] = dirs[mi] or {}
    table.insert(dirs[mi], { t = t, xml = text, harmony = harmony, order = #dirs[mi] })
  end
  local staff_tag = nstaves > 1 and "<staff>1</staff>" or ""
  local pin_ends = {}
  local pins = {}
  for _, mk in ipairs(sc.marks or {}) do
    if mk.kind == "hairpin" then pins[#pins + 1] = mk end
  end
  table.sort(pins, function(x, y) return (midi.at_of(sc, f, x.from) or 0) < (midi.at_of(sc, f, y.from) or 0) end)
  local pin_number = {}
  for _, mk in ipairs(pins) do
    local a, b = midi.at_of(sc, f, mk.from), midi.at_of(sc, f, mk.to)
    if a and b then
      local number = 1
      while pin_ends[number] and pin_ends[number] >= a do number = number + 1 end
      pin_ends[number] = b
      pin_number[mk] = number
    end
  end
  for _, mk in ipairs(sc.marks or {}) do
    local mi = mk.from and f.index[mk.from.measure]
    local t = mi and D.ticks(mk.from.at or { 0, 1 })
    if mi then
      if mk.kind == "dynamic" then
        local name = mk.value == "niente" and "n" or mk.value
        put(mi, t, '<direction placement="below"><direction-type><dynamics><' .. name .. "/></dynamics></direction-type>"
          .. (mk.subito and "<direction-type><words>subito</words></direction-type>" or "") .. "%OFFSET%" .. staff_tag
          .. (midi.DYNAMICS[mk.value] and ('<sound dynamics="' .. floor(midi.DYNAMICS[mk.value] / 0.9 + 0.5) .. '"/>') or "") .. "</direction>")
      elseif mk.kind == "hairpin" and pin_number[mk] then
        local number = pin_number[mk]
        local cresc = mk.value ~= "dim"
        put(mi, t, '<direction placement="below"><direction-type><wedge type="' .. (cresc and "crescendo" or "diminuendo") .. '" number="' .. number .. '"'
          .. ((mk.niente and cresc) and ' niente="yes"' or "") .. "/></direction-type>%OFFSET%" .. staff_tag .. "</direction>")
        local mj = f.index[mk.to.measure] or mi
        put(mj,D.ticks(mk.to.at or { 0, 1 }), '<direction placement="below"><direction-type><wedge type="stop" number="' .. number .. '"'
          .. ((mk.niente and not cresc) and ' niente="yes"' or "") .. "/></direction-type>%OFFSET%" .. staff_tag .. "</direction>")
      elseif mk.kind == "text" or mk.kind == "technique" then
        put(mi, t, '<direction placement="above"><direction-type><words>' .. esc(mk.value or "") .. "</words></direction-type>%OFFSET%" .. staff_tag .. "</direction>")
      elseif mk.kind == "tempo" then
        local tp = write_cmds.parse_tempo(tostring(mk.value or "")) or {}
        local body = ""
        if tp.change or not tp.unit then
          body = "<direction-type><words>" .. esc(mk.value or "") .. "</words></direction-type>"
        else
          if tp.words then body = "<direction-type><words>" .. esc(tp.words) .. "</words></direction-type>" end
          local unit = tp.unit:gsub("♩", "q")
          body = body .. "<direction-type><metronome><beat-unit>" .. UNIT_XML[unit:sub(1, 1)] .. "</beat-unit>"
            .. (unit:sub(2, 2) == "." and "<beat-unit-dot/>" or "") .. "<per-minute>" .. string.format("%g", tp.per) .. "</per-minute></metronome></direction-type>"
        end
        put(mi, t, '<direction placement="above">' .. body .. "%OFFSET%" .. staff_tag
          .. (mk.bpm and ('<sound tempo="' .. string.format("%g", mk.bpm) .. '"/>') or "") .. "</direction>")
      elseif mk.kind == "chord" then
        local h = harmony_xml(tostring(mk.value or ""))
        if h then put(mi, t, "<harmony>" .. h .. "%OFFSET%" .. staff_tag .. "</harmony>", true) end
      end
    end
  end
  for mi, m in ipairs(sc.measures) do
    if m.rehearsal then
      put(mi, -1, '<direction placement="above"><direction-type><rehearsal>' .. esc(m.rehearsal) .. "</rehearsal></direction-type>" .. staff_tag .. "</direction>")
    end
  end
  for _, list in pairs(dirs) do
    table.sort(list, function(x, y)
      if x.t ~= y.t then return x.t < y.t end
      return x.order < y.order
    end)
  end
  -- A pickup: the first bar written from where the clip starts, when what
  -- is before it there is rests.
  local cut = 0
  if origin < 0 and f.count > 0 then
    cut = -origin
    for _, entry in ipairs(sc.measures[1].voices) do
      local t = 0
      for _, ev in ipairs(entry.events) do
        if t < cut and (ev.kind ~= "rest" or ev.grace or t + D.length(ev) > cut) then cut = 0 end
        t = t + D.length(ev)
      end
    end
  end
  local breaks = {}
  for _, b in ipairs(sc.layout and sc.layout.breaks or {}) do
    if b.kind == "break" then breaks[b.measure] = true end
  end
  -- Endings: a run of bars with one number.
  local function volta_edges(mi)
    local m = sc.measures[mi]
    if not m.volta then return nil, nil end
    local before, after = sc.measures[mi - 1], sc.measures[mi + 1]
    local starts = not (before and before.volta == m.volta)
    local stops = not (after and after.volta == m.volta)
    return starts, stops
  end
  local lyric_open = {}
  w('  <part id="' .. pid .. '">')
  for mi, m in ipairs(sc.measures) do
    local len = f.lengths[mi]
    local skip = mi == 1 and cut or 0
    local number = cut > 0 and (mi - 1) or mi
    w('    <measure number="' .. number .. '"' .. ((mi == 1 and cut > 0) and ' implicit="yes"' or "") .. ">")
    if breaks[m.id] then w('      <print new-system="yes"/>') end
    local vs, ve = volta_edges(mi)
    if m.repeat_start or vs then
      w('      <barline location="left">' .. (m.repeat_start and "<bar-style>heavy-light</bar-style>" or "")
        .. (vs and ('<ending number="' .. m.volta .. '" type="start">' .. m.volta .. ".</ending>") or "")
        .. (m.repeat_start and '<repeat direction="forward"/>' or "") .. "</barline>")
    end
    local attrs = {}
    local meter = f.meters[mi]
    if mi == 1 then
      attrs[#attrs + 1] = "<divisions>" .. divisions .. "</divisions>"
      -- The score's key, else the project's; a score with neither says none.
      local k = m.key or (part.fifths and { fifths = part.fifths, name = part.key_name })
      local mode = k and k.name and k.name:match("%s(%a+)$")
      if k then attrs[#attrs + 1] = "<key><fifths>" .. k.fifths .. "</fifths>" .. (mode and ("<mode>" .. mode .. "</mode>") or "") .. "</key>" end
    elseif m.key then
      local mode = m.key.name and m.key.name:match("%s(%a+)$")
      attrs[#attrs + 1] = "<key><fifths>" .. m.key.fifths .. "</fifths>" .. (mode and ("<mode>" .. mode .. "</mode>") or "") .. "</key>"
    end
    if mi == 1 or m.meter then
      local top = meter.groups and table.concat(meter.groups, "+") or tostring(meter[1])
      attrs[#attrs + 1] = "<time" .. (m.meter_symbol and (' symbol="' .. m.meter_symbol .. '"') or "") .. "><beats>" .. top .. "</beats><beat-type>" .. meter[2] .. "</beat-type></time>"
    end
    if mi == 1 and nstaves > 1 then attrs[#attrs + 1] = "<staves>" .. nstaves .. "</staves>" end
    if mi == 1 and part.transpose then
      -- Written at an interval from how it sounds: what takes the written
      -- notes to sounding ones, an octave apart from the rest.
      local iv = part.transpose
      local octave = iv.steps >= 0 and floor(iv.steps / 7) or -floor(-iv.steps / 7)
      attrs[#attrs + 1] = "<transpose><diatonic>" .. -(iv.steps - 7 * octave) .. "</diatonic><chromatic>" .. -(iv.semis - 12 * octave)
        .. "</chromatic>" .. (octave ~= 0 and ("<octave-change>" .. -octave .. "</octave-change>") or "") .. "</transpose>"
    end
    for s, st in ipairs(sc.staves) do
      local clef = mi == 1 and st.clef or (m.clef and m.clef[st.id])
      local sign = clef and CLEF_SIGN[clef]
      if sign then
        attrs[#attrs + 1] = "<clef" .. (nstaves > 1 and (' number="' .. s .. '"') or "") .. "><sign>" .. sign[1] .. "</sign><line>" .. sign[2] .. "</line>"
          .. (sign[3] and ("<clef-octave-change>" .. sign[3] .. "</clef-octave-change>") or "") .. "</clef>"
      end
    end
    if #attrs > 0 then w("      <attributes>" .. table.concat(attrs) .. "</attributes>") end
    -- Voices, staff by staff; the bar's directions go in its first.
    local entries = {}
    for _, e in ipairs(m.voices) do
      if #e.events > 0 and D.staff_index(sc, e.staff) then entries[#entries + 1] = e end
    end
    for s, st in ipairs(sc.staves) do
      local has1 = false
      for _, e in ipairs(entries) do
        if e.staff == st.id and e.voice == 1 then has1 = true end
      end
      if not has1 then entries[#entries + 1] = { staff = st.id, voice = 1, events = {}, empty = true } end
    end
    table.sort(entries, function(a, b)
      local x, y = D.staff_index(sc, a.staff), D.staff_index(sc, b.staff)
      if x ~= y then return x < y end
      return a.voice < b.voice
    end)
    local pos = 0
    local mdirs = dirs[mi] or {}
    local di = 1
    for ei, e in ipairs(entries) do
      local s = D.staff_index(sc, e.staff)
      if pos > 0 then w("      <backup><duration>" .. dv(pos) .. "</duration></backup>") end
      pos = 0
      local voice = tostring((s - 1) * 4 + e.voice)
      local staff = nstaves > 1 and ("<staff>" .. s .. "</staff>") or ""
      local function flush(upto, anchor)
        -- The directions up to `upto`, before the event at `anchor`.
        while ei == 1 and mdirs[di] and mdirs[di].t <= upto do
          local d = mdirs[di]
          local off = math.max(0, d.t - anchor)
          local text = d.xml:gsub("%%OFFSET%%", off > 0 and ("<offset>" .. dv(off) .. "</offset>") or "")
          w("      " .. text)
          di = di + 1
        end
      end
      if e.empty then
        flush(len, skip)
        w('      <note><rest measure="yes"/><duration>' .. dv(len - skip) .. "</duration><voice>" .. voice .. "</voice>" .. staff .. "</note>")
        pos = len - skip
      else
        -- Each event's start, so that what is before an event goes before it.
        local items, t = {}, 0
        for _, ev in ipairs(e.events) do
          items[#items + 1] = { ev = ev, s = t }
          t = t + D.length(ev)
        end
        for k, it in ipairs(items) do
          local ev = it.ev
          -- A pickup's leading rests are not written.
          local written = not (skip > 0 and it.s + D.length(ev) <= skip and not ev.grace)
          if written and (k == 1 or not items[k - 1].ev.grace) then
            -- The bar's directions from here to the next chord or rest go
            -- before this one (or the grace notes leading into it).
            local main, nxt = nil, nil
            for j = k, #items do
              if not items[j].ev.grace then
                if not main then main = items[j] elseif not nxt then nxt = items[j] end
              end
            end
            flush(nxt and nxt.s - 1 or len, it.s)
          end
          if written then
            local dur = D.length(ev)
            local typ = type_of(ev.dur)
            local tm = ""
            local tnot = {}
            if ev.tuplet and not ev.grace then
              local span, first, last = 0, nil, nil
              for j, other in ipairs(items) do
                if other.ev.tuplet and other.ev.tuplet.id == ev.tuplet.id and not other.ev.grace then
                  span = span + D.length(other.ev)
                  first, last = first or j, j
                end
              end
              local unit = span / ev.tuplet.normal
              local ntype = TYPE_OF[floor(unit + 0.5)]
              local ndot = not ntype and TYPE_OF[floor(unit / 1.5 + 0.5)]
              tm = "<time-modification><actual-notes>" .. ev.tuplet.actual .. "</actual-notes><normal-notes>" .. ev.tuplet.normal .. "</normal-notes>"
                .. (ntype and ("<normal-type>" .. ntype .. "</normal-type>") or ndot and ("<normal-type>" .. ndot .. "</normal-type><normal-dot/>") or "")
                .. "</time-modification>"
              if k == first then tnot[#tnot + 1] = '<tuplet type="start"/>' end
              if k == last then tnot[#tnot + 1] = '<tuplet type="stop"/>' end
            end
            local typetag = (typ and ("<type>" .. typ .. "</type>") or "") .. string.rep("<dot/>", ev.dots or 0)
            local look = shown[ev.id] or {}
            if ev.kind == "rest" then
              w("      <note><rest/><duration>" .. dv(dur) .. "</duration><voice>" .. voice .. "</voice>" .. typetag .. tm .. staff
                .. (#tnot > 0 and ("<notations>" .. table.concat(tnot) .. "</notations>") or "") .. "</note>")
            else
              for i, n in ipairs(ev.notes) do
                -- The note's id goes out with it: `n41` is the clip's MIDI note 41.
                local id = type(n.id) == "string" and n.id:match("^n[%d.]+$")
                local parts = { id and ('      <note id="' .. id .. '">') or "      <note>" }
                if ev.grace then parts[#parts + 1] = ev.grace == "acciaccatura" and '<grace slash="yes"/>' or "<grace/>" end
                if i > 1 then parts[#parts + 1] = "<chord/>" end
                parts[#parts + 1] = "<pitch><step>" .. LETTERS[n.step] .. "</step>" .. ((n.alter or 0) ~= 0 and ("<alter>" .. n.alter .. "</alter>") or "")
                  .. "<octave>" .. n.octave .. "</octave></pitch>"
                if not ev.grace then parts[#parts + 1] = "<duration>" .. dv(dur) .. "</duration>" end
                if tied_in[n.id] then parts[#parts + 1] = '<tie type="stop"/>' end
                if n.tie and not ev.grace then parts[#parts + 1] = '<tie type="start"/>' end
                parts[#parts + 1] = "<voice>" .. voice .. "</voice>" .. typetag
                local ns = notes_shown[n.id]
                if ns and ns.acc then
                  local ACC = { [-2] = "flat-flat", [-1] = "flat", [0] = "natural", [1] = "sharp", [2] = "double-sharp" }
                  if ACC[ns.acc] then parts[#parts + 1] = "<accidental" .. (ns.courtesy and ' cautionary="yes"' or "") .. ">" .. ACC[ns.acc] .. "</accidental>" end
                end
                parts[#parts + 1] = tm
                if ev.grace then
                  parts[#parts + 1] = "<stem>up</stem>"
                elseif look.stem then
                  parts[#parts + 1] = "<stem>" .. (look.stem > 0 and "up" or "down") .. "</stem>"
                end
                parts[#parts + 1] = staff
                if i == 1 then
                  for level, value in ipairs(look.beams or {}) do parts[#parts + 1] = '<beam number="' .. level .. '">' .. value .. "</beam>" end
                end
                local nots = {}
                if tied_in[n.id] then nots[#nots + 1] = '<tied type="stop"/>' end
                if n.tie and not ev.grace then nots[#nots + 1] = '<tied type="start"/>' end
                if i == 1 then
                  for _, num in ipairs(slur_stop[ev.id] or {}) do nots[#nots + 1] = '<slur type="stop" number="' .. num .. '"/>' end
                  for _, num in ipairs(slur_start[ev.id] or {}) do nots[#nots + 1] = '<slur type="start" number="' .. num .. '"/>' end
                  for _, x in ipairs(tnot) do nots[#nots + 1] = x end
                  local art = ev.art or {}
                  local arts = {}
                  for _, a in ipairs({ "accent", "marcato", "staccato", "staccatissimo", "tenuto" }) do
                    if art[a] then arts[#arts + 1] = "<" .. XML_ART[a] .. "/>" end
                  end
                  if #arts > 0 then nots[#nots + 1] = "<articulations>" .. table.concat(arts) .. "</articulations>" end
                  if art.fermata then nots[#nots + 1] = '<fermata type="upright"/>' end
                  if art.fermata_short then nots[#nots + 1] = '<fermata type="upright">angled</fermata>' end
                  if art.fermata_long then nots[#nots + 1] = '<fermata type="upright">square</fermata>' end
                  if ev.orn and XML_ORN[ev.orn] then
                    nots[#nots + 1] = "<ornaments><" .. XML_ORN[ev.orn] .. (ev.orn == "tremolo" and ' type="single">3</tremolo>' or "/>") .. "</ornaments>"
                  end
                end
                if ev.arpeggio then nots[#nots + 1] = '<arpeggiate direction="' .. ev.arpeggio .. '"/>' end
                if #nots > 0 then parts[#parts + 1] = "<notations>" .. table.concat(nots) .. "</notations>" end
                if i == 1 and not ev.grace then
                  local verses = { ev.lyric }
                  for v2, text in ipairs(ev.lyrics or {}) do verses[v2 + 1] = text end
                  for verse = 1, math.max(#(ev.lyrics or {}) + 1, 1) do
                    local text = verses[verse]
                    if text and text ~= "" then
                      local key = e.staff .. ":" .. e.voice .. ":" .. verse
                      local hyphen = text:sub(-1) == "-"
                      local extend = text:sub(-1) == "_"
                      local word = (hyphen or extend) and text:sub(1, -2) or text
                      local syl = lyric_open[key] and (hyphen and "middle" or "end") or (hyphen and "begin" or "single")
                      lyric_open[key] = hyphen
                      parts[#parts + 1] = '<lyric number="' .. verse .. '"><syllabic>' .. syl .. "</syllabic><text>" .. esc(word) .. "</text>"
                        .. (extend and "<extend/>" or "") .. "</lyric>"
                    end
                  end
                end
                parts[#parts + 1] = "</note>"
                w(table.concat(parts))
              end
            end
            if not ev.grace then pos = math.max(0, it.s + dur - skip) end
          end
        end
        flush(len, pos + skip)
      end
    end
    -- What did not find a place (a bar with no events) goes last.
    while mdirs[di] do
      local d = mdirs[di]
      w("      " .. d.xml:gsub("%%OFFSET%%", ""))
      di = di + 1
    end
    if m.barline or ve then
      local style = m.barline == "||" and "light-light" or "light-heavy"
      local stop = ve and ('<ending number="' .. m.volta .. '" type="' .. (m.barline == ":|" and "stop" or "discontinue") .. '"/>') or ""
      w('      <barline location="right">' .. ((m.barline and m.barline ~= "|") and ("<bar-style>" .. style .. "</bar-style>") or "") .. stop
        .. (m.barline == ":|" and '<repeat direction="backward"/>' or "") .. "</barline>")
    end
    w("    </measure>")
  end
  w("  </part>")
end

--- A MusicXML document (partwise, 4.0) of score parts: `parts` =
--- `{ { name, score, fifths (the key where the score says none), program, drums } }`,
--- and for a full score each part's `short` name, `transpose` (the
--- interval it is written at, `notation.parts`), `group` (`{ name, number }`
--- on a family's first part: a bracket from it) and `group_end` (that
--- number, on the family's last part);
--- `opts`: `title`, `composer`.
function M.write(parts, opts)
  opts = opts or {}
  local out = {}
  local function w(line) out[#out + 1] = line end
  w('<?xml version="1.0" encoding="UTF-8" standalone="no"?>')
  w('<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">')
  w('<score-partwise version="4.0">')
  if opts.title and opts.title ~= "" then w("  <work><work-title>" .. esc(opts.title) .. "</work-title></work>") end
  w("  <identification>" .. ((opts.composer and opts.composer ~= "") and ('<creator type="composer">' .. esc(opts.composer) .. "</creator>") or "")
    .. "<encoding><software>paw</software></encoding></identification>")
  w("  <part-list>")
  local scores = {}
  for i, p in ipairs(parts) do
    scores[i] = p.score
    local pid = "P" .. i
    -- Channels 1 to 16 in turn, 10 kept for drums.
    local channel = (i - 1) % 15 + 1
    if channel >= 10 then channel = channel + 1 end
    if p.group then
      w('    <part-group type="start" number="' .. p.group.number .. '"><group-name>' .. esc(p.group.name)
        .. "</group-name><group-symbol>bracket</group-symbol><group-barline>yes</group-barline></part-group>")
    end
    w('    <score-part id="' .. pid .. '"><part-name>' .. esc(p.name or ("Part " .. i)) .. "</part-name>"
      .. (p.short and ("<part-abbreviation>" .. esc(p.short) .. "</part-abbreviation>") or "")
      .. '<score-instrument id="' .. pid .. '-I1"><instrument-name>' .. esc(p.name or ("Part " .. i)) .. "</instrument-name></score-instrument>"
      .. '<midi-instrument id="' .. pid .. '-I1"><midi-channel>' .. (p.drums and 10 or channel) .. "</midi-channel>"
      .. "<midi-program>" .. ((p.program or 0) + 1) .. "</midi-program></midi-instrument></score-part>")
    if p.group_end then w('    <part-group type="stop" number="' .. p.group_end .. '"/>') end
  end
  w("  </part-list>")
  local divisions, g = divisions_of(scores)
  for i, p in ipairs(parts) do part_xml(w, p, "P" .. i, divisions, g) end
  w("</score-partwise>")
  return table.concat(out, "\n") .. "\n"
end

--- A compressed MusicXML file (.mxl) of a document's text.
function M.mxl(text, name)
  name = (name or "score") .. ".musicxml"
  local container = '<?xml version="1.0" encoding="UTF-8"?>\n<container><rootfiles><rootfile full-path="' .. esc(name)
    .. '" media-type="application/vnd.recordare.musicxml+xml"/></rootfiles></container>\n'
  return paw.zip.write({ { name = "mimetype", data = "application/vnd.recordare.musicxml" }, { name = "META-INF/container.xml", data = container }, { name = name, data = text } })
end

return M
