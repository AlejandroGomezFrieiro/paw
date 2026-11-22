-- LilyPond source from score documents (`notation.doc`): each part's
-- staves and voices, values, dots, ties, tuplets, grace notes, a pickup,
-- key, clef and time changes, barlines, repeats and endings, rehearsal
-- marks, tempo marks, dynamics (subito, niente), hairpins, slurs, text,
-- techniques and chord symbols (as text over the staff), articulations,
-- fermatas, ornaments, arpeggios, beams broken by hand, and lyrics in
-- verses with their hyphens and extenders.
--
--   lilypond.write(parts, opts)   -- parts = { { name, score, fifths, key_name } }; opts: title, composer
local D = require("notation.doc")

local M = {}

local W = D.W
local floor = math.floor

local LETTERS = { [0] = "c", "d", "e", "f", "g", "a", "b" }
local ALTER = { [-2] = "eses", [-1] = "es", [0] = "", [1] = "is", [2] = "isis" }
local VALUES = {
  [2 * W] = "\\breve",
  [W] = "1",
  [W / 2] = "2",
  [W / 4] = "4",
  [W / 8] = "8",
  [W / 16] = "16",
  [W / 32] = "32",
  [W / 64] = "64",
  [W / 128] = "128",
}
local CLEFS =
  { treble = "treble", bass = "bass", alto = "alto", tenor = "tenor", treble8 = '"treble_8"', bass8 = '"bass_8"' }
local ART = {
  staccato = "-.",
  staccatissimo = "-!",
  accent = "->",
  tenuto = "--",
  marcato = "-^",
  fermata = "\\fermata",
  fermata_short = "\\shortfermata",
  fermata_long = "\\longfermata",
}
local ART_ORDER =
  { "accent", "marcato", "staccato", "staccatissimo", "tenuto", "fermata", "fermata_short", "fermata_long" }
local ORN =
  { trill = "\\trill", mordent = "\\mordent", prall = "\\prall", turn = "\\turn", turn_inverted = "\\reverseturn" }
local UNITS = { q = "4", ["q."] = "4.", h = "2", ["h."] = "2.", e = "8", ["e."] = "8.", w = "1" }

local function pitch(n)
  local name = LETTERS[n.step] .. (ALTER[n.alter or 0] or "")
  local o = n.octave - 3
  return name .. (o > 0 and string.rep("'", o) or string.rep(",", -o))
end

local function value(ev) return (VALUES[D.ticks(ev.dur)] or "4") .. string.rep(".", ev.dots or 0) end

local function quote(text) return '"' .. tostring(text):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"' end

--- A key's name ("Eb major") as LilyPond's `\key`.
local function key_of(name, fifths)
  local root, mode = tostring(name or ""):match("^([A-G][#b]?)%s+(%a+)$")
  if not root then
    local major = {
      [-7] = "ces",
      [-6] = "ges",
      [-5] = "des",
      [-4] = "aes",
      [-3] = "ees",
      [-2] = "bes",
      [-1] = "f",
      [0] = "c",
      [1] = "g",
      [2] = "d",
      [3] = "a",
      [4] = "e",
      [5] = "b",
      [6] = "fis",
      [7] = "cis",
    }
    return "\\key " .. (major[fifths or 0] or "c") .. " \\major"
  end
  local letter = root:sub(1, 1):lower()
  local acc = root:sub(2)
  local lily = letter
    .. (acc == "#" and "is" or acc == "b" and ((letter == "e" or letter == "a") and "s" or "es") or "")
  return "\\key " .. lily .. " \\" .. mode
end

--- A length in ticks as `\partial`'s duration.
local function partial(ticks, den)
  local unit = W / den
  if ticks % unit ~= 0 then
    den, unit = 32, W / 32
  end
  return "\\partial " .. den .. "*" .. floor(ticks / unit + 0.5)
end

--- One part: its staves' music and the lyrics under its voices.
local function part_text(part, pi, first_part)
  local sc = part.score
  local f = D.frame(sc)
  local origin = D.origin(sc)
  local midi = require("notation.midi")
  local write_cmds = require("notation.write")
  -- A pickup when the first bar holds only rests before the clip starts.
  local cut = origin < 0 and -origin or 0
  for _, entry in ipairs(sc.measures[1] and sc.measures[1].voices or {}) do
    local t = 0
    for _, ev in ipairs(entry.events) do
      if t < cut and (ev.kind ~= "rest" or ev.grace or t + D.length(ev) > cut) then cut = 0 end
      t = t + D.length(ev)
    end
  end
  -- The events of every voice in time, and which notes are tied into.
  local voices, tied_in = {}, {}
  for s, st in ipairs(sc.staves) do
    for v = 1, 4 do
      local seq = D.sequence(sc, st.id, v)
      local has = false
      for _, it in ipairs(seq) do
        has = has or it.ev.kind == "chord"
      end
      if has or v == 1 then voices[#voices + 1] = { staff = s, id = st.id, v = v, seq = seq } end
      local prev
      for _, it in ipairs(seq) do
        if it.ev.kind == "chord" and not it.ev.grace then
          if prev and prev.e == it.s then
            local all = true
            for _, n in ipairs(it.ev.notes) do
              local found = false
              for _, p in ipairs(prev.ev.notes) do
                found = found or (p.tie and D.pitch(p) == D.pitch(n))
              end
              all = all and found
            end
            tied_in[it.ev.id] = all
          end
          prev = it
        elseif it.ev.kind == "rest" then
          prev = nil
        end
      end
    end
  end
  -- What is put after a chord (`post`) or before it (`pre`), by event id.
  local post, pre = {}, {}
  local function add(tbl, id, text)
    tbl[id] = tbl[id] or {}
    table.insert(tbl[id], text)
  end
  local top = voices[1]
  --- The event of a voice at a place: the one starting there, else the
  --- one sounding there (`after`: the next to start).
  local function event_at(voice, t, after)
    local best
    for _, it in ipairs(voice.seq) do
      if not it.ev.grace then
        if it.s == t then return it end
        if after and it.s > t then return it end
        if not after and it.s < t then best = it end
      end
    end
    return best or voice.seq[#voice.seq]
  end
  for _, mk in ipairs(sc.marks or {}) do
    local t = midi.at_of(sc, f, mk.from)
    local it = t and event_at(top, t)
    if it then
      local id = it.ev.id
      if mk.kind == "dynamic" then
        if mk.value == "niente" then
          add(post, id, '_\\markup { \\italic "niente" }')
        else
          add(post, id, "\\" .. mk.value)
        end
        if mk.subito then add(post, id, '_\\markup { \\italic "subito" }') end
      elseif mk.kind == "hairpin" then
        add(post, id, mk.value == "dim" and "\\>" or "\\<")
        local e = midi.at_of(sc, f, mk.to)
        local stop = e and event_at(top, e, true)
        if stop and stop ~= it then add(post, stop.ev.id, "\\!") end
      elseif mk.kind == "text" or mk.kind == "technique" then
        add(post, id, "^\\markup { \\italic " .. quote(mk.value or "") .. " }")
      elseif mk.kind == "chord" then
        add(post, id, "^\\markup { " .. quote(mk.value or "") .. " }")
      elseif mk.kind == "tempo" then
        local tp = write_cmds.parse_tempo(tostring(mk.value or "")) or {}
        if tp.change or not (tp.unit or mk.bpm) then
          add(post, id, "^\\markup { \\italic " .. quote(mk.value or "") .. " }")
        elseif tp.unit and UNITS[tp.unit] then
          add(
            pre,
            id,
            "\\tempo "
              .. (tp.words and (quote(tp.words) .. " ") or "")
              .. UNITS[tp.unit]
              .. " = "
              .. string.format("%g", tp.per)
          )
        else
          add(pre, id, "\\tempo " .. quote(tp.words or mk.value or "") .. " 4 = " .. string.format("%g", mk.bpm))
        end
      elseif mk.kind == "slur" then
        local e = midi.at_of(sc, f, mk.to)
        for _, voice in ipairs(voices) do
          if voice.id == (mk.staff or sc.staves[1].id) then
            local a, b
            for _, x in ipairs(voice.seq) do
              if x.ev.kind == "chord" and not x.ev.grace and not tied_in[x.ev.id] and x.s >= t and e and x.s <= e then
                a = a or x
                b = x
              end
            end
            if a and b and a ~= b then
              add(post, a.ev.id, "(")
              add(post, b.ev.id, ")")
              break
            end
          end
        end
      end
    end
  end
  for _, voice in ipairs(voices) do
    local words = {}
    local function w(x) words[#words + 1] = x end
    local is_top = voice == top
    local first_of_staff = voice.v == 1
    if first_of_staff then
      w("\\clef " .. (CLEFS[sc.staves[voice.staff].clef] or "treble"))
      local m1 = sc.measures[1]
      w(key_of(m1 and m1.key and m1.key.name or part.key_name, m1 and m1.key and m1.key.fifths or part.fifths))
      w("\\numericTimeSignature")
    end
    if #voices > 1 and sc.staves[voice.staff] then
      local count = 0
      for _, other in ipairs(voices) do
        if other.staff == voice.staff then count = count + 1 end
      end
      if count > 1 then w(({ "\\voiceOne", "\\voiceTwo", "\\voiceThree", "\\voiceFour" })[voice.v]) end
    end
    local by_measure = {}
    for _, it in ipairs(voice.seq) do
      by_measure[it.mi] = by_measure[it.mi] or {}
      table.insert(by_measure[it.mi], it)
    end
    for mi, m in ipairs(sc.measures) do
      local meter = f.meters[mi]
      local len = f.lengths[mi]
      local skip = mi == 1 and cut or 0
      if first_of_staff then
        if mi == 1 and skip > 0 then w(partial(len - skip, meter[2])) end
        if m.key and mi > 1 then w(key_of(m.key.name, m.key.fifths)) end
        if m.clef and m.clef[voice.id] and mi > 1 then w("\\clef " .. (CLEFS[m.clef[voice.id]] or "treble")) end
        if mi == 1 or m.meter then
          if m.meter_symbol then
            w("\\defaultTimeSignature")
          elseif mi > 1 then
            w("\\numericTimeSignature")
          end
          w(
            "\\time "
              .. (meter.groups and (table.concat(meter.groups, ",") .. " ") or "")
              .. meter[1]
              .. "/"
              .. meter[2]
          )
        end
      end
      if is_top and first_part then
        if m.rehearsal then w("\\mark " .. quote(m.rehearsal)) end
        local before = sc.measures[mi - 1]
        if m.volta and not (before and before.volta == m.volta) then
          w("\\set Score.repeatCommands = #'((volta \"" .. m.volta .. '."))')
        end
        if m.repeat_start and not (before and before.barline) then w('\\bar ".|:"') end
      end
      local items = by_measure[mi]
      if not items or #items == 0 then
        w(voice.v == 1 and ("R1*" .. meter[1] .. "/" .. meter[2]) or ("s1*" .. meter[1] .. "/" .. meter[2]))
      else
        local open_tuplet, graces = nil, {}
        for _, it in ipairs(items) do
          local ev = it.ev
          local at = it.s - f.starts[mi]
          if not (skip > 0 and at + D.length(ev) <= skip and not ev.grace) then
            if open_tuplet and (not ev.tuplet or ev.tuplet.id ~= open_tuplet) and not ev.grace then
              w("}")
              open_tuplet = nil
            end
            if ev.grace then
              graces[#graces + 1] = ev
            else
              if ev.tuplet and ev.tuplet.id ~= open_tuplet then
                w("\\tuplet " .. ev.tuplet.actual .. "/" .. ev.tuplet.normal .. " {")
                open_tuplet = ev.tuplet.id
              end
              if #graces > 0 then
                local g = {}
                for _, ge in ipairs(graces) do
                  local ps = {}
                  for i, n in ipairs(ge.notes) do
                    ps[i] = pitch(n)
                  end
                  g[#g + 1] = (#ps > 1 and ("<" .. table.concat(ps, " ") .. ">") or ps[1]) .. value(ge)
                end
                w(
                  (graces[1].grace == "appoggiatura" and "\\appoggiatura" or "\\acciaccatura")
                    .. " { "
                    .. table.concat(g, " ")
                    .. " }"
                )
                graces = {}
              end
              for _, x in ipairs(pre[ev.id] or {}) do
                w(x)
              end
              if ev.kind == "rest" then
                w("r" .. value(ev) .. table.concat(post[ev.id] or {}))
              else
                local ps = {}
                local all_tied = #ev.notes > 0
                for i, n in ipairs(ev.notes) do
                  ps[i] = pitch(n) .. ((n.tie and #ev.notes > 1) and "~" or "")
                  all_tied = all_tied and n.tie
                end
                if ev.arpeggio then w(ev.arpeggio == "down" and "\\arpeggioArrowDown" or "\\arpeggioArrowUp") end
                local text = (#ps > 1 and ("<" .. table.concat(ps, " ") .. ">") or ps[1]) .. value(ev)
                if ev.orn == "tremolo" then text = text .. ":32" end
                if #ev.notes == 1 and ev.notes[1].tie then text = text .. "~" end
                if ev.beam == "break" then text = text .. "\\noBeam" end
                for _, a in ipairs(ART_ORDER) do
                  if ev.art and ev.art[a] then text = text .. ART[a] end
                end
                if ev.orn and ORN[ev.orn] then text = text .. ORN[ev.orn] end
                if ev.arpeggio then text = text .. "\\arpeggio" end
                w(text .. table.concat(post[ev.id] or {}))
              end
            end
          end
        end
        if open_tuplet then w("}") end
      end
      if is_top and first_part then
        local after = sc.measures[mi + 1]
        local ends_volta = m.volta and not (after and after.volta == m.volta)
        local bar = m.barline
        if bar == ":|" and after and after.repeat_start then
          w('\\bar ":|.|:"')
        elseif bar == ":|" then
          w('\\bar ":|."')
        elseif bar == "||" or bar == "|." then
          w('\\bar "' .. bar .. '"')
          if after and after.repeat_start then w('\\bar ".|:"') end
        end
        if ends_volta then w("\\set Score.repeatCommands = #'((volta #f))") end
      end
      w("|")
    end
    voice.text = table.concat(words, " ")
    -- Lyrics, a verse at a time, a syllable to each chord not tied into.
    voice.verses = {}
    local most = 0
    for _, it in ipairs(voice.seq) do
      if it.ev.kind == "chord" and not it.ev.grace then
        if it.ev.lyric and it.ev.lyric ~= "" then most = math.max(most, 1) end
        for k, text in ipairs(it.ev.lyrics or {}) do
          if text ~= "" then most = math.max(most, k + 1) end
        end
      end
    end
    for verse = 1, most do
      local syl = {}
      for _, it in ipairs(voice.seq) do
        local ev = it.ev
        if
          ev.kind == "chord"
          and not ev.grace
          and not tied_in[ev.id]
          and not (cut > 0 and it.mi == 1 and it.s < cut)
        then
          local text = verse == 1 and ev.lyric or (ev.lyrics or {})[verse - 1]
          if not text or text == "" then
            syl[#syl + 1] = "_"
          elseif text:sub(-1) == "-" then
            syl[#syl + 1] = quote(text:sub(1, -2)) .. " --"
          elseif text:sub(-1) == "_" then
            syl[#syl + 1] = quote(text:sub(1, -2)) .. " __"
          else
            syl[#syl + 1] = quote(text)
          end
        end
      end
      voice.verses[verse] = table.concat(syl, " ")
    end
  end
  -- Staves of voices, lyrics under the voice they follow.
  local staves = {}
  for s in ipairs(sc.staves) do
    local lines = {}
    local lyric_lines = {}
    for _, voice in ipairs(voices) do
      if voice.staff == s then
        local name = "p" .. pi .. "s" .. s .. "v" .. voice.v
        local melisma = #voice.verses > 0 and "\\set melismaBusyProperties = #'(tieMelismaBusy) " or ""
        lines[#lines + 1] = '      \\new Voice = "' .. name .. '" { ' .. melisma .. voice.text .. " }"
        for _, text in ipairs(voice.verses) do
          lyric_lines[#lyric_lines + 1] = '    \\new Lyrics \\lyricsto "' .. name .. '" { ' .. text .. " }"
        end
      end
    end
    local with = (#sc.staves == 1 and part.name) and (" \\with { instrumentName = " .. quote(part.name) .. " }") or ""
    staves[#staves + 1] = "    \\new Staff" .. with .. " <<\n" .. table.concat(lines, "\n") .. "\n    >>"
    for _, l in ipairs(lyric_lines) do
      staves[#staves + 1] = l
    end
  end
  if #sc.staves > 1 then
    return "  \\new PianoStaff"
      .. (part.name and (" \\with { instrumentName = " .. quote(part.name) .. " }") or "")
      .. " <<\n"
      .. table.concat(staves, "\n")
      .. "\n  >>"
  end
  return table.concat(staves, "\n")
end

--- LilyPond source for score parts (as `notation.musicxml.write` takes
--- them). `opts`: `title`, `composer`.
function M.write(parts, opts)
  opts = opts or {}
  local body = {}
  for i, p in ipairs(parts) do
    body[#body + 1] = part_text(p, i, i == 1)
  end
  return '\\version "2.24.0"\n\\header { title = '
    .. quote(opts.title or "")
    .. " composer = "
    .. quote(opts.composer or "")
    .. " tagline = ##f }\n\n\\score {\n  <<\n"
    .. table.concat(body, "\n")
    .. "\n  >>\n  \\layout { }\n}\n"
end

return M
