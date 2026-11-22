-- Writing the notation out: MusicXML (opens in MuseScore, Finale, Sibelius,
-- Dorico) and LilyPond source. Both are made from the same layout the views
-- draw, so what is exported is what is shown.
local model = require("notation.model")
local M = {}

local DIVISIONS = 24 -- per quarter: a 32nd is three, a triplet sixteenth two

-- LilyPond -------------------------------------------------------------------------------------

local LY_ALTER = { [-2] = "eses", [-1] = "es", [0] = "", [1] = "is", [2] = "isis" }
local LY_MAJOR = {
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
local LY_MINOR = {
  [-7] = "aes",
  [-6] = "ees",
  [-5] = "bes",
  [-4] = "f",
  [-3] = "c",
  [-2] = "g",
  [-1] = "d",
  [0] = "a",
  [1] = "e",
  [2] = "b",
  [3] = "fis",
  [4] = "cis",
  [5] = "gis",
  [6] = "dis",
  [7] = "ais",
}
local MINORISH =
  { minor = true, aeolian = true, harmonic_minor = true, melodic_minor = true, minor_pentatonic = true, blues = true }

local function ly_pitch(n)
  local name = model.LETTERS[n.letter]:lower() .. LY_ALTER[n.alter]
  local o = n.octave - 3
  return name .. (o > 0 and string.rep("'", o) or string.rep(",", -o))
end

local function ly_value(ev) return tostring(math.floor(4 / ev.base + 0.5)) .. string.rep(".", ev.dots) end

local function ly_events(evs, meter_of_m)
  local words = {}
  local open
  for _, ev in ipairs(evs) do
    if open and ev.tuplet ~= open then
      words[#words + 1] = "}"
      open = nil
    end
    if ev.tuplet and ev.tuplet ~= open then
      local t = ev.tuplet
      words[#words + 1] = string.format("\\tuplet %d/%d {", t.n, math.floor(t.n / t.ratio + 0.5))
      open = t
    end
    if ev.whole then
      words[#words + 1] = "R1*" .. meter_of_m.num .. "/" .. meter_of_m.den
    elseif ev.kind == "rest" then
      words[#words + 1] = "r" .. ly_value(ev)
    else
      if ev.grace then
        local g = {}
        for i, n in ipairs(ev.grace) do
          g[i] = ly_pitch(n) .. "8"
        end
        words[#words + 1] = "\\acciaccatura { " .. table.concat(g, " ") .. " }"
      end
      local pitches = {}
      for i, n in ipairs(ev.notes) do
        pitches[i] = ly_pitch(n) .. ((n.acc and n.courtesy) and "?" or "")
      end
      local tie = ev.notes[1].tie and "~" or ""
      local marks = (ev.staccato and "-." or "") .. (ev.arpeggio and "\\arpeggio" or "")
      if ev.arpeggio then words[#words + 1] = ev.arpeggio > 0 and "\\arpeggioArrowUp" or "\\arpeggioArrowDown" end
      words[#words + 1] = (#pitches > 1 and ("<" .. table.concat(pitches, " ") .. ">") or pitches[1])
        .. ly_value(ev)
        .. tie
        .. marks
    end
  end
  if open then words[#words + 1] = "}" end
  return table.concat(words, " ")
end

--- LilyPond source for a layout. `opts`: `title`, `scale` (for a minor key).
function M.lilypond(layout, opts)
  opts = opts or {}
  local fifths = layout.fifths
  local key = MINORISH[opts.scale or ""] and ("\\key " .. LY_MINOR[fifths] .. " \\minor")
    or ("\\key " .. LY_MAJOR[fifths] .. " \\major")
  local staves = {}
  for s, clef in ipairs(layout.staves) do
    local two = false
    for _, m in ipairs(layout.measures) do
      for _, ev in ipairs(m.staves[s]) do
        if ev.voice == 2 then two = true end
      end
    end
    local function voice_text(v)
      local bars = {}
      local meter
      for _, m in ipairs(layout.measures) do
        local evs = {}
        for _, ev in ipairs(m.staves[s]) do
          if ev.voice == v then evs[#evs + 1] = ev end
        end
        local prefix = ""
        if m.meter ~= meter then
          prefix = "\\time " .. m.meter.num .. "/" .. m.meter.den .. " "
          meter = m.meter
        end
        local body = #evs > 0 and ly_events(evs, m.meter) or ("s1*" .. m.meter.num .. "/" .. m.meter.den)
        bars[#bars + 1] = "    " .. prefix .. body .. " |"
      end
      return table.concat(bars, "\n")
    end
    local head = string.format("\\clef %s %s", clef == "treble8" and '"treble_8"' or clef, key)
    if two then
      staves[s] = string.format(
        "  \\new Staff <<\n    %s\n    \\new Voice { \\voiceOne\n%s\n    }\n    \\new Voice { \\voiceTwo\n%s\n    }\n  >>",
        head,
        voice_text(1),
        voice_text(2)
      )
    else
      staves[s] = string.format("  \\new Staff {\n    %s\n%s\n  }", head, voice_text(1))
    end
  end
  local body = #staves == 1 and staves[1] or ("  \\new PianoStaff <<\n" .. table.concat(staves, "\n") .. "\n  >>")
  return string.format(
    '\\version "2.24.0"\n\\header { title = "%s" tagline = ##f }\n\n\\score {\n%s\n  \\layout { }\n}\n',
    (opts.title or ""):gsub('"', "'"),
    body
  )
end

-- MusicXML -----------------------------------------------------------------------------------

local XML_TYPE = { [4] = "whole", [2] = "half", [1] = "quarter", [0.5] = "eighth", [0.25] = "16th", [0.125] = "32nd" }
local XML_ACC = { [-2] = "flat-flat", [-1] = "flat", [0] = "natural", [1] = "sharp", [2] = "double-sharp" }

local function escape(text)
  return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

--- Beam values for each event of a measure's staff, by level: begin,
--- continue, end, or a hook for a part beam.
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
      out[ev] = levels
    end
  end
  return out
end

--- A MusicXML document (partwise, 4.0) for a layout. `opts`: `title`, `part`.
function M.musicxml(layout, opts)
  opts = opts or {}
  local out = {}
  local function w(line) out[#out + 1] = line end
  w('<?xml version="1.0" encoding="UTF-8" standalone="no"?>')
  w(
    '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">'
  )
  w('<score-partwise version="4.0">')
  w("  <work><work-title>" .. escape(opts.title or "") .. "</work-title></work>")
  w(
    '  <part-list><score-part id="P1"><part-name>'
      .. escape(opts.part or "Part")
      .. "</part-name></score-part></part-list>"
  )
  w('  <part id="P1">')
  local meter_now
  for mi, m in ipairs(layout.measures) do
    w('    <measure number="' .. mi .. '">')
    if mi == 1 or m.meter ~= meter_now then
      w("      <attributes>")
      if mi == 1 then
        w("        <divisions>" .. DIVISIONS .. "</divisions>")
        w("        <key><fifths>" .. layout.fifths .. "</fifths></key>")
      end
      w("        <time><beats>" .. m.meter.num .. "</beats><beat-type>" .. m.meter.den .. "</beat-type></time>")
      if mi == 1 then
        if #layout.staves > 1 then w("        <staves>" .. #layout.staves .. "</staves>") end
        for s, clef in ipairs(layout.staves) do
          local number = #layout.staves > 1 and (' number="' .. s .. '"') or ""
          w(
            "        <clef"
              .. number
              .. ">"
              .. (clef == "bass" and "<sign>F</sign><line>4</line>" or clef == "treble8" and "<sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change>" or "<sign>G</sign><line>2</line>")
              .. "</clef>"
          )
        end
        if opts.tab then
          w(
            '        <staff-details number="'
              .. (#layout.staves + 1)
              .. '"><staff-lines>'
              .. #opts.tab
              .. "</staff-lines></staff-details>"
          )
        end
      end
      w("      </attributes>")
      meter_now = m.meter
    end
    local bar_divisions = math.floor(m.length * DIVISIONS + 0.5)
    for _, d in ipairs(m.directions or {}) do
      local offset = math.floor((d.start - m.start) * DIVISIONS + 0.5)
      w(
        '      <direction placement="below"><direction-type>'
          .. d.xml
          .. "</direction-type>"
          .. (offset > 0 and ("<offset>" .. offset .. "</offset>") or "")
          .. "</direction>"
      )
    end
    local first_chunk = true
    for s in ipairs(layout.staves) do
      local voices = {}
      for _, ev in ipairs(m.staves[s]) do
        voices[ev.voice] = voices[ev.voice] or {}
        table.insert(voices[ev.voice], ev)
      end
      local order = {}
      for v in pairs(voices) do
        order[#order + 1] = v
      end
      table.sort(order)
      for _, v in ipairs(order) do
        local evs = voices[v]
        if not first_chunk then w("      <backup><duration>" .. bar_divisions .. "</duration></backup>") end
        first_chunk = false
        local voice = tostring((s - 1) * 4 + v)
        local staff = #layout.staves > 1 and ("<staff>" .. s .. "</staff>") or ""
        local beams = beam_values(evs)
        local t = m.start
        for k, ev in ipairs(evs) do
          if ev.start > t + 1e-6 then
            w(
              "      <forward><duration>"
                .. math.floor((ev.start - t) * DIVISIONS + 0.5)
                .. "</duration><voice>"
                .. voice
                .. "</voice>"
                .. staff
                .. "</forward>"
            )
          end
          t = ev.start + ev.length
          local duration = math.floor(ev.length * DIVISIONS + 0.5)
          local tm, tnot = "", {}
          if ev.tuplet then
            local normal = math.floor(ev.tuplet.n / ev.tuplet.ratio + 0.5)
            tm = "<time-modification><actual-notes>"
              .. ev.tuplet.n
              .. "</actual-notes><normal-notes>"
              .. normal
              .. "</normal-notes></time-modification>"
            if evs[k - 1] == nil or evs[k - 1].tuplet ~= ev.tuplet then
              tnot[#tnot + 1] = '<tuplet type="start" bracket="yes"/>'
            end
            if evs[k + 1] == nil or evs[k + 1].tuplet ~= ev.tuplet then tnot[#tnot + 1] = '<tuplet type="stop"/>' end
          end
          if ev.kind == "rest" then
            if ev.whole then
              w(
                '      <note><rest measure="yes"/><duration>'
                  .. duration
                  .. "</duration><voice>"
                  .. voice
                  .. "</voice>"
                  .. staff
                  .. "</note>"
              )
            else
              w(
                "      <note><rest/><duration>"
                  .. duration
                  .. "</duration><voice>"
                  .. voice
                  .. "</voice><type>"
                  .. XML_TYPE[ev.base]
                  .. "</type>"
                  .. string.rep("<dot/>", ev.dots)
                  .. tm
                  .. staff
                  .. (#tnot > 0 and ("<notations>" .. table.concat(tnot) .. "</notations>") or "")
                  .. "</note>"
              )
            end
          else
            for _, g in ipairs(ev.grace or {}) do
              w(
                '      <note><grace slash="yes"/>'
                  .. "<pitch><step>"
                  .. model.LETTERS[g.letter]
                  .. "</step>"
                  .. (g.alter ~= 0 and ("<alter>" .. g.alter .. "</alter>") or "")
                  .. "<octave>"
                  .. g.octave
                  .. "</octave></pitch><voice>"
                  .. voice
                  .. "</voice><type>eighth</type>"
                  .. (g.acc and ("<accidental>" .. XML_ACC[g.acc] .. "</accidental>") or "")
                  .. "<stem>up</stem>"
                  .. staff
                  .. "</note>"
              )
            end
            for i, n in ipairs(ev.notes) do
              local parts = { "      <note>" }
              if i > 1 then parts[#parts + 1] = "<chord/>" end
              parts[#parts + 1] = "<pitch><step>"
                .. model.LETTERS[n.letter]
                .. "</step>"
                .. (n.alter ~= 0 and ("<alter>" .. n.alter .. "</alter>") or "")
                .. "<octave>"
                .. n.octave
                .. "</octave></pitch>"
              parts[#parts + 1] = "<duration>" .. duration .. "</duration>"
              if n.tied then parts[#parts + 1] = '<tie type="stop"/>' end
              if n.tie then parts[#parts + 1] = '<tie type="start"/>' end
              parts[#parts + 1] = "<voice>"
                .. voice
                .. "</voice><type>"
                .. XML_TYPE[ev.base]
                .. "</type>"
                .. string.rep("<dot/>", ev.dots)
              if n.acc then
                parts[#parts + 1] = "<accidental"
                  .. (n.courtesy and ' cautionary="yes"' or "")
                  .. ">"
                  .. XML_ACC[n.acc]
                  .. "</accidental>"
              end
              parts[#parts + 1] = tm
              if ev.stem then parts[#parts + 1] = "<stem>" .. (ev.stem > 0 and "up" or "down") .. "</stem>" end
              parts[#parts + 1] = staff
              if i == 1 then
                for level, value in ipairs(beams[ev] or {}) do
                  parts[#parts + 1] = '<beam number="' .. level .. '">' .. value .. "</beam>"
                end
              end
              local nots = {}
              if n.tied then nots[#nots + 1] = '<tied type="stop"/>' end
              if n.tie then nots[#nots + 1] = '<tied type="start"/>' end
              if i == 1 then
                for _, x in ipairs(tnot) do
                  nots[#nots + 1] = x
                end
                local arts = {}
                if ev.staccato or (ev.art and ev.art.staccato) then arts[#arts + 1] = "<staccato/>" end
                if ev.art and ev.art.accent then arts[#arts + 1] = "<accent/>" end
                if ev.art and ev.art.tenuto then arts[#arts + 1] = "<tenuto/>" end
                if ev.art and ev.art.marcato then arts[#arts + 1] = "<strong-accent/>" end
                if #arts > 0 then nots[#nots + 1] = "<articulations>" .. table.concat(arts) .. "</articulations>" end
                for _, sl in ipairs(ev.slurs or {}) do
                  nots[#nots + 1] = '<slur type="' .. sl .. '"/>'
                end
              end
              if ev.arpeggio then
                nots[#nots + 1] = '<arpeggiate direction="' .. (ev.arpeggio > 0 and "up" or "down") .. '"/>'
              end
              if n.string then
                nots[#nots + 1] = "<technical><string>"
                  .. n.string
                  .. "</string><fret>"
                  .. n.fret
                  .. "</fret></technical>"
              end
              if #nots > 0 then parts[#parts + 1] = "<notations>" .. table.concat(nots) .. "</notations>" end
              if i == 1 and ev.lyric then
                parts[#parts + 1] = '<lyric number="1"><syllabic>single</syllabic><text>'
                  .. escape(ev.lyric)
                  .. "</text></lyric>"
              end
              parts[#parts + 1] = "</note>"
              w(table.concat(parts))
            end
          end
        end
      end
    end
    w("    </measure>")
  end
  w("  </part>")
  w("</score-partwise>")
  return table.concat(out, "\n") .. "\n"
end

-- What to export -------------------------------------------------------------------------------

--- The layout of a whole track: its MIDI clips' notes on one timeline, from
--- the start of the project to the end of the last clip.
function M.track_layout(track, opts, bars_of)
  local notes, finish = {}, 0
  for _, clip in ipairs(track:clips()) do
    local c = clip:get()
    if c.kind == "midi" then
      finish = math.max(finish, c.start + c.length)
      for _, n in ipairs(clip:notes()) do
        if n.start >= 0 and n.start < c.length then
          local copy = paw.util.merge(n, { start = c.start + n.start, length = math.min(n.length, c.length - n.start) })
          notes[#notes + 1] = copy
        end
      end
    end
  end
  table.sort(notes, function(a, b) return a.start < b.start or (a.start == b.start and a.pitch < b.pitch) end)
  return model.layout(
    notes,
    paw.util.merge(opts, { length = finish, offset = 0, bars = bars_of and bars_of(0, finish) or nil })
  )
end

--- Write a file; returns nil and the error when it cannot be written.
function M.write(path, text)
  local file, err = io.open(path, "wb")
  if not file then return nil, err end
  file:write(text)
  file:close()
  return true
end

return M
