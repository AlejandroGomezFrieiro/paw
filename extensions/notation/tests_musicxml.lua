-- Tests of MusicXML in and out: hand-written files as MuseScore, Dorico,
-- Sibelius and Finale write them, read into scores, written out and read
-- back to the same score; `:open` and `:import` of them; what the score
-- then plays. Loaded by tests.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation.musicxml"), require("notation.doc")
end

local HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
  .. '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">\n'

-- A piano piece: two staves, two voices on the upper, a tie over the
-- barline, a slur, a hairpin between dynamics, a tempo mark.
local PIANO = HEAD .. [[
<score-partwise version="4.0">
  <work><work-title>Little Piece</work-title></work>
  <identification><creator type="composer">A. Composer</creator></identification>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name>
      <score-instrument id="P1-I1"><instrument-name>Piano</instrument-name></score-instrument>
      <midi-instrument id="P1-I1"><midi-channel>1</midi-channel><midi-program>1</midi-program></midi-instrument>
    </score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>2</divisions><key><fifths>2</fifths><mode>major</mode></key>
        <time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves>
        <clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef></attributes>
      <direction placement="above"><direction-type><words>Andante</words></direction-type>
        <direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>72</per-minute></metronome></direction-type>
        <staff>1</staff><sound tempo="72"/></direction>
      <direction placement="below"><direction-type><dynamics><p/></dynamics></direction-type><staff>1</staff></direction>
      <note><pitch><step>F</step><alter>1</alter><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type>
        <stem>up</stem><staff>1</staff><notations><slur type="start" number="1"/></notations></note>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice><type>eighth</type><staff>1</staff>
        <beam number="1">begin</beam></note>
      <note><pitch><step>D</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice><type>eighth</type><staff>1</staff>
        <beam number="1">end</beam></note>
      <direction placement="below"><direction-type><wedge type="crescendo" number="1"/></direction-type><staff>1</staff></direction>
      <note><pitch><step>A</step><octave>5</octave></pitch><duration>4</duration><tie type="start"/><voice>1</voice><type>half</type>
        <staff>1</staff><notations><tied type="start"/><slur type="stop" number="1"/></notations></note>
      <backup><duration>8</duration></backup>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>4</duration><voice>2</voice><type>half</type><stem>down</stem><staff>1</staff></note>
      <note><pitch><step>B</step><octave>4</octave></pitch><duration>4</duration><voice>2</voice><type>half</type><stem>down</stem><staff>1</staff></note>
      <backup><duration>8</duration></backup>
      <note><pitch><step>D</step><octave>3</octave></pitch><duration>4</duration><voice>5</voice><type>half</type><staff>2</staff></note>
      <note><chord/><pitch><step>A</step><octave>3</octave></pitch><duration>4</duration><voice>5</voice><type>half</type><staff>2</staff></note>
      <note><pitch><step>G</step><octave>2</octave></pitch><duration>2</duration><voice>5</voice><type>quarter</type><staff>2</staff>
        <notations><articulations><staccato/></articulations></notations></note>
      <note><rest/><duration>2</duration><voice>5</voice><type>quarter</type><staff>2</staff></note>
    </measure>
    <measure number="2">
      <note><pitch><step>A</step><octave>5</octave></pitch><duration>2</duration><tie type="stop"/><voice>1</voice><type>quarter</type>
        <staff>1</staff><notations><tied type="stop"/></notations></note>
      <direction placement="below"><direction-type><wedge type="stop" number="1"/></direction-type><staff>1</staff></direction>
      <direction placement="below"><direction-type><dynamics><f/></dynamics></direction-type><staff>1</staff></direction>
      <note><pitch><step>G</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type><staff>1</staff>
        <notations><articulations><accent/></articulations></notations></note>
      <note><pitch><step>F</step><alter>1</alter><octave>5</octave></pitch><duration>4</duration><voice>1</voice><type>half</type><staff>1</staff>
        <notations><fermata type="upright"/></notations></note>
      <backup><duration>8</duration></backup>
      <note><pitch><step>D</step><octave>2</octave></pitch><duration>8</duration><voice>5</voice><type>whole</type><staff>2</staff></note>
      <barline location="right"><bar-style>light-heavy</bar-style></barline>
    </measure>
  </part>
</score-partwise>
]]

-- A lead sheet in 3/4 with a pickup: chord symbols (with and without the
-- kind's text, a bass, an offset, N.C.), lyrics in two verses with
-- hyphens and an extender, a rehearsal mark and text.
local LEAD = HEAD .. [[
<score-partwise version="3.1">
  <part-list><score-part id="P1"><part-name>Voice</part-name></score-part></part-list>
  <part id="P1">
    <measure number="0" implicit="yes">
      <attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>3</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef></attributes>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type>
        <lyric number="1"><syllabic>single</syllabic><text>Oh</text></lyric><lyric number="2"><syllabic>single</syllabic><text>And</text></lyric></note>
    </measure>
    <measure number="1">
      <direction placement="above"><direction-type><rehearsal>A</rehearsal></direction-type></direction>
      <harmony><root><root-step>C</root-step></root><kind text="">major</kind></harmony>
      <direction placement="above"><direction-type><words>dolce</words></direction-type></direction>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type>
        <lyric number="1"><syllabic>begin</syllabic><text>hap</text></lyric><lyric number="2"><syllabic>begin</syllabic><text>sing</text></lyric></note>
      <note><pitch><step>B</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type>
        <lyric number="1"><syllabic>end</syllabic><text>py</text></lyric><lyric number="2"><syllabic>end</syllabic><text>ing</text></lyric></note>
      <harmony><root><root-step>A</root-step></root><kind>minor-seventh</kind></harmony>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type>
        <lyric number="1"><syllabic>single</syllabic><text>day</text><extend/></lyric><lyric number="2"><syllabic>single</syllabic><text>now</text></lyric></note>
    </measure>
    <measure number="2">
      <harmony><root><root-step>F</root-step></root><kind text="">major</kind><bass><bass-step>A</bass-step></bass></harmony>
      <harmony><root><root-step>G</root-step></root><kind>dominant</kind><offset>2</offset></harmony>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>half</type></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type>
        <lyric number="1"><syllabic>single</syllabic><text>the</text></lyric></note>
    </measure>
    <measure number="3">
      <harmony><root><root-step>C</root-step></root><kind>none</kind></harmony>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>3</duration><voice>1</voice><type>half</type><dot/>
        <lyric number="1"><syllabic>single</syllabic><text>end</text></lyric></note>
      <barline location="right"><bar-style>light-heavy</bar-style></barline>
    </measure>
  </part>
</score-partwise>
]]

-- Key, clef and time signature changes: C (common time), Eb in 3/4, a
-- bass clef written at the end of the bar before (as MuseScore does), C
-- minor in 6/8, the guitar's clef in 3+3+2/8.
local CHANGES = HEAD .. [[
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Cello</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>2</divisions><key><fifths>0</fifths></key><time symbol="common"><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef></attributes>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>8</duration><voice>1</voice><type>whole</type></note>
    </measure>
    <measure number="2">
      <attributes><key><fifths>-3</fifths><mode>major</mode></key><time><beats>3</beats><beat-type>4</beat-type></time></attributes>
      <note><pitch><step>E</step><alter>-1</alter><octave>5</octave></pitch><duration>6</duration><voice>1</voice><type>half</type><dot/></note>
      <attributes><clef><sign>F</sign><line>4</line></clef></attributes>
    </measure>
    <measure number="3">
      <note><pitch><step>C</step><octave>3</octave></pitch><duration>6</duration><voice>1</voice><type>half</type><dot/></note>
    </measure>
    <measure number="4">
      <attributes><key><fifths>-3</fifths><mode>minor</mode></key><time><beats>6</beats><beat-type>8</beat-type></time></attributes>
      <note><pitch><step>C</step><octave>3</octave></pitch><duration>3</duration><voice>1</voice><type>quarter</type><dot/></note>
      <note><pitch><step>G</step><octave>2</octave></pitch><duration>3</duration><voice>1</voice><type>quarter</type><dot/></note>
    </measure>
    <measure number="5">
      <attributes><time><beats>3+3+2</beats><beat-type>8</beat-type></time><clef><sign>G</sign><line>2</line><clef-octave-change>-1</clef-octave-change></clef></attributes>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>3</duration><voice>1</voice><type>quarter</type><dot/></note>
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>3</duration><voice>1</voice><type>quarter</type><dot/></note>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>2</duration><voice>1</voice><type>quarter</type></note>
    </measure>
  </part>
</score-partwise>
]]

-- Repeats with first and second endings, a double and a final barline.
local REPEATS = HEAD .. [[
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Flute</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <barline location="left"><bar-style>heavy-light</bar-style><repeat direction="forward"/></barline>
      <attributes><divisions>1</divisions><time><beats>2</beats><beat-type>4</beat-type></time></attributes>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>half</type></note>
    </measure>
    <measure number="2">
      <barline location="left"><ending number="1" type="start">1.</ending></barline>
      <note><pitch><step>D</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>half</type></note>
      <barline location="right"><bar-style>light-heavy</bar-style><ending number="1" type="stop"/><repeat direction="backward"/></barline>
    </measure>
    <measure number="3">
      <barline location="left"><ending number="2" type="start">2.</ending></barline>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>half</type></note>
      <barline location="right"><ending number="2" type="discontinue"/></barline>
    </measure>
    <measure number="4">
      <note><pitch><step>F</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>half</type></note>
      <barline location="right"><bar-style>light-light</bar-style></barline>
    </measure>
    <measure number="5">
      <note><pitch><step>G</step><octave>5</octave></pitch><duration>2</duration><voice>1</voice><type>half</type></note>
      <barline location="right"><bar-style>light-heavy</bar-style></barline>
    </measure>
  </part>
</score-partwise>
]]

-- Tuplets, grace notes and the marks on chords: a triplet, a quintuplet,
-- an acciaccatura and an appoggiatura, ornaments, an arpeggio, sfz, p
-- subito, a diminuendo to nothing; a pedal and a fingering are not kept.
local TUPLETS = HEAD .. [[
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Violin</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes><divisions>60</divisions><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>20</duration><voice>1</voice><type>eighth</type>
        <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>
        <beam number="1">begin</beam><notations><tuplet type="start" bracket="no"/></notations></note>
      <note><pitch><step>D</step><octave>5</octave></pitch><duration>20</duration><voice>1</voice><type>eighth</type>
        <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification><beam number="1">continue</beam></note>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>20</duration><voice>1</voice><type>eighth</type>
        <time-modification><actual-notes>3</actual-notes><normal-notes>2</normal-notes></time-modification>
        <beam number="1">end</beam><notations><tuplet type="stop"/></notations></note>
      <note><pitch><step>F</step><octave>5</octave></pitch><duration>12</duration><voice>1</voice><type>16th</type>
        <time-modification><actual-notes>5</actual-notes><normal-notes>4</normal-notes></time-modification><notations><tuplet type="start"/></notations></note>
      <note><pitch><step>G</step><octave>5</octave></pitch><duration>12</duration><voice>1</voice><type>16th</type>
        <time-modification><actual-notes>5</actual-notes><normal-notes>4</normal-notes></time-modification></note>
      <note><pitch><step>A</step><octave>5</octave></pitch><duration>12</duration><voice>1</voice><type>16th</type>
        <time-modification><actual-notes>5</actual-notes><normal-notes>4</normal-notes></time-modification></note>
      <note><pitch><step>B</step><octave>5</octave></pitch><duration>12</duration><voice>1</voice><type>16th</type>
        <time-modification><actual-notes>5</actual-notes><normal-notes>4</normal-notes></time-modification></note>
      <note><pitch><step>C</step><octave>6</octave></pitch><duration>12</duration><voice>1</voice><type>16th</type>
        <time-modification><actual-notes>5</actual-notes><normal-notes>4</normal-notes></time-modification><notations><tuplet type="stop"/></notations></note>
      <note><grace slash="yes"/><pitch><step>D</step><octave>5</octave></pitch><voice>1</voice><type>eighth</type></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>60</duration><voice>1</voice><type>quarter</type>
        <notations><ornaments><trill-mark/></ornaments><technical><fingering>3</fingering></technical></notations></note>
      <note><grace/><pitch><step>B</step><octave>4</octave></pitch><voice>1</voice><type>eighth</type></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>60</duration><voice>1</voice><type>quarter</type>
        <notations><ornaments><mordent/></ornaments></notations></note>
    </measure>
    <measure number="2">
      <direction placement="below"><direction-type><dynamics><sfz/></dynamics></direction-type></direction>
      <direction placement="below"><direction-type><pedal type="start"/></direction-type></direction>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>60</duration><voice>1</voice><type>quarter</type>
        <notations><arpeggiate direction="up"/><articulations><accent/></articulations></notations></note>
      <note><chord/><pitch><step>E</step><octave>4</octave></pitch><duration>60</duration><voice>1</voice><type>quarter</type><notations><arpeggiate/></notations></note>
      <note><chord/><pitch><step>G</step><octave>4</octave></pitch><duration>60</duration><voice>1</voice><type>quarter</type><notations><arpeggiate/></notations></note>
      <direction placement="below"><direction-type><dynamics><p/></dynamics></direction-type><direction-type><words>subito</words></direction-type></direction>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>60</duration><voice>1</voice><type>quarter</type>
        <notations><ornaments><inverted-mordent/></ornaments><articulations><tenuto/></articulations></notations></note>
      <direction placement="below"><direction-type><wedge type="diminuendo" number="1"/></direction-type></direction>
      <note><pitch><step>G</step><octave>5</octave></pitch><duration>60</duration><voice>1</voice><type>quarter</type>
        <notations><articulations><strong-accent type="up"/><staccatissimo/></articulations></notations></note>
      <direction placement="below"><direction-type><wedge type="stop" number="1" niente="yes"/></direction-type></direction>
      <note><pitch><step>C</step><octave>6</octave></pitch><duration>60</duration><voice>1</voice><type>quarter</type>
        <notations><ornaments><turn/></ornaments><fermata type="upright">angled</fermata></notations></note>
    </measure>
  </part>
</score-partwise>
]]

-- A zip from Python's zipfile, deflated: fourteen bars of half notes.
local DEFLATED = ""
  .. "504b03041400000008008b28715d9076213e5d00000075000000160000004d4554412d494e462f636f6e7461696e65722e786d6cb3b1afc8cd51284b"
  .. "2d2acecccfb35532d433505248cd4bce4fc9cc4bb7550a0d71d3b550b2b7b349cecf2b49cccc4b2db2b329cacf2f49cbcc492d463015d24a7372740b"
  .. "124b326c958a93f38b52f580862ae9dbd9e82329d647980100504b03041400000008008b28715d5eefda4b41010000190900000900000073636f7265"
  .. "2e786d6ccd96c94ec3301086ef7d8a28f7e0bab450a4a92bb670e5000fe02403b5944df624c0dbe3d481b4c2679c9367c6b37c73f82dc3feb32aa31e"
  .. "b5514dbd8bf9c5328eb0ce9b42d5efbbf8f5254db6f15e2cc0e48dc6a4959a3e94c1a9606d0b040cf1a45486c44962a48a5dfccc7fae6b59a148cb8e"
  .. "10d81400361588f1c2353a6f51a1349dc6a8eeaa0cb505b53149a455661b1a0185ead5406404073639406a1892a1242356c09c71f413fa6a51ac5dcc"
  .. "39c05c3a3bed5c376443ada2fc60b7236cc5bd851e4e6872923d8a0db0d1b20bb8bca2d3922cc130f3d786be51390e80ce80e3d0832cdfec6037df0d"
  .. "63e3b67fd75ec53ea0877040975ea0c770406b2f501a0e68e3057a0a0774e505ba0d0774ed05ba0b07b4f5020594fdcddc64cf9773d33de773133ef7"
  .. "3fd60195cffdaf7540e973ff73fd8fda67e3cfe3fc832316df504b010214031400000008008b28715d9076213e5d0000007500000016000000000000"
  .. "00000000008001000000004d4554412d494e462f636f6e7461696e65722e786d6c504b010214031400000008008b28715d5eefda4b41010000190900"
  .. "0009000000000000000000000080019100000073636f72652e786d6c504b050600000000020002007b000000f90100000000"

--- A score said in plain lines, ids left out: what two scores must share
--- to be the same score.
local function describe(sc)
  local D = require("notation.doc")
  local midi = require("notation.midi")
  local LET = { [0] = "C", "D", "E", "F", "G", "A", "B" }
  local f = D.frame(sc)
  local out = { "origin " .. D.origin(sc) }
  local index = {}
  for i, st in ipairs(sc.staves) do
    index[st.id] = i
    out[#out + 1] = "staff " .. i .. " " .. st.clef
  end
  local function keys(t)
    local list = {}
    for k in pairs(t or {}) do list[#list + 1] = k end
    table.sort(list)
    return table.concat(list, ",")
  end
  for mi, m in ipairs(sc.measures) do
    local line = { "m" .. mi }
    if m.meter then line[#line + 1] = "meter " .. m.meter[1] .. "/" .. m.meter[2] .. (m.groups and ("(" .. table.concat(m.groups, "+") .. ")") or "") end
    if m.meter_symbol then line[#line + 1] = m.meter_symbol end
    if m.key then line[#line + 1] = "key " .. m.key.fifths .. " " .. tostring(m.key.name) end
    if m.clef then
      for id, clef in pairs(m.clef) do line[#line + 1] = "clef " .. index[id] .. "=" .. clef end
    end
    for _, k in ipairs({ "barline", "repeat_start", "volta", "rehearsal" }) do
      if m[k] then line[#line + 1] = k .. " " .. tostring(m[k]) end
    end
    out[#out + 1] = table.concat(line, " ")
    local entries = {}
    for _, e in ipairs(m.voices) do entries[#entries + 1] = e end
    table.sort(entries, function(a, b)
      if index[a.staff] ~= index[b.staff] then return index[a.staff] < index[b.staff] end
      return a.voice < b.voice
    end)
    for _, e in ipairs(entries) do
      local evs, tuplets = {}, {}
      for _, ev in ipairs(e.events) do
        local s = ev.kind == "rest" and "r" or ""
        for i, n in ipairs(ev.notes or {}) do
          local acc = (n.alter or 0) > 0 and string.rep("#", n.alter) or string.rep("b", -(n.alter or 0))
          s = s .. (i > 1 and "+" or "") .. LET[n.step] .. acc .. n.octave .. (n.tie and "~" or "")
        end
        s = s .. "/" .. ev.dur[1] .. ":" .. ev.dur[2] .. string.rep(".", ev.dots or 0)
        if ev.tuplet then
          tuplets[ev.tuplet.id] = tuplets[ev.tuplet.id] or (#evs + 1)
          s = s .. "{" .. ev.tuplet.actual .. ":" .. ev.tuplet.normal .. "#" .. tuplets[ev.tuplet.id] .. "}"
        end
        if ev.grace then s = s .. " g" .. ev.grace end
        if ev.art then s = s .. " [" .. keys(ev.art) .. "]" end
        for _, k in ipairs({ "orn", "arpeggio", "beam", "lyric" }) do
          if ev[k] then s = s .. " " .. k .. "=" .. tostring(ev[k]) end
        end
        if ev.lyrics then s = s .. " lyrics=" .. table.concat(ev.lyrics, "|") end
        evs[#evs + 1] = s
      end
      out[#out + 1] = "  s" .. index[e.staff] .. "v" .. e.voice .. ": " .. table.concat(evs, "  ")
    end
  end
  local marks = {}
  for _, mk in ipairs(sc.marks or {}) do
    local parts = { mk.kind, tostring(midi.at_of(sc, f, mk.from)) }
    if mk.to then parts[#parts + 1] = "to " .. tostring(midi.at_of(sc, f, mk.to)) end
    for _, k in ipairs({ "value", "subito", "niente", "bpm", "change" }) do
      if mk[k] ~= nil then parts[#parts + 1] = k .. "=" .. tostring(mk[k]) end
    end
    if mk.staff then parts[#parts + 1] = "staff " .. tostring(index[mk.staff]) end
    marks[#marks + 1] = table.concat(parts, " ")
  end
  table.sort(marks)
  for _, s in ipairs(marks) do out[#out + 1] = "mark " .. s end
  for _, b in ipairs(sc.layout and sc.layout.breaks or {}) do out[#out + 1] = "break " .. tostring(f.index[b.measure]) .. " " .. b.kind end
  return table.concat(out, "\n")
end

--- Read a file's text, write its parts out and read that back: the two
--- scores, the text written, and the file read first.
local function round(text)
  local mx = load()
  local file = assert(mx.parse(text))
  local parts = {}
  for i, p in ipairs(file.parts) do parts[i] = { name = p.name, score = p.score, program = p.program, drums = p.drums } end
  local out = mx.write(parts, { title = file.title, composer = file.composer })
  local again = assert(mx.parse(out))
  return file.parts[1].score, again.parts[1].score, out, file, again
end

local function write_file(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

local function read_file(path)
  local f = io.open(path, "rb")
  local data = f and f:read("*a") or ""
  if f then f:close() end
  return data
end

-- Reading -------------------------------------------------------------------------------------

test("musicxml: the XML reader takes a DOCTYPE, comments, CDATA, entities and attributes with > in them", function()
  load()
  local xml = require("notation.xml")
  local root = assert(xml.parse('\239\187\191<?xml version="1.0"?><!DOCTYPE x [ <!ENTITY a "b"> ]><!-- c --><a k="1 > 0" j=\'q\'>'
    .. "<b>x &amp; y &#233; &#x263A;</b><![CDATA[<raw>]]><c/></a>"))
  eq(root.name, "a", "the root")
  eq(root.attrs.k .. "|" .. root.attrs.j, "1 > 0|q", "attributes, a > inside quotes")
  eq(xml.text(root, "b"), "x & y é ☺", "entities as UTF-8")
  eq(root.text, "<raw>", "CDATA as text")
  eq(#xml.children(root), 2, "two child elements")
  eq(select(2, xml.parse("<a><b></a>")) ~= nil, true, "a tag closed by the wrong one is an error")
end)

test("musicxml: a piano piece reads as two staves, voices, a tie, a slur, a hairpin and a tempo mark", function()
  local mx = load()
  local file = assert(mx.parse(PIANO))
  eq(file.title .. " / " .. file.composer, "Little Piece / A. Composer", "the title and the composer")
  local part = file.parts[1]
  eq(part.name .. " " .. tostring(part.program), "Piano 0", "the part's name and its MIDI program, from 0")
  local text = describe(part.score)
  eq(text:find("staff 1 treble\nstaff 2 bass", 1, true) ~= nil, true, "a grand staff:\n" .. text)
  eq(text:find("m1 meter 4/4 key 2 D major", 1, true) ~= nil, true, "time and key in the first bar")
  eq(text:find("  s1v1: F#5/1:4  E5/1:8  D5/1:8  A5~/1:2", 1, true) ~= nil, true, "the upper voice, tied into bar 2")
  eq(text:find("  s1v2: A4/1:2  B4/1:2", 1, true) ~= nil, true, "the second voice")
  eq(text:find("  s2v1: D3+A3/1:2  G2/1:4 [staccato]  r/1:4", 1, true) ~= nil, true, "MuseScore's voice 5 is the lower staff's first")
  eq(text:find("  s2v1: D2/1:1", 1, true) ~= nil, true, "a whole note in bar 2")
  eq(text:find("m2 barline |.", 1, true) ~= nil, true, "the final barline")
  eq(text:find("mark slur 0 to 20160 staff 1", 1, true) ~= nil, true, "the slur, to the A")
  eq(text:find("mark hairpin 20160 to 50400 value=cresc", 1, true) ~= nil, true, "the hairpin, to the f")
  eq(text:find("mark dynamic 50400 value=f", 1, true) ~= nil, true, "the f")
  eq(text:find("mark tempo 0 value=Andante q=72 bpm=72", 1, true) ~= nil, true, "the tempo mark with its bpm")
  eq(mx.skipped_text(file), nil, "nothing left out")
end)

test("musicxml: a lead sheet keeps its pickup, chord symbols, lyrics in verses, rehearsal mark and text", function()
  local mx, D = load()
  local file = assert(mx.parse(LEAD))
  local sc = file.parts[1].score
  local text = describe(sc)
  eq(D.origin(sc), -2 * D.Q, "a pickup of one beat in 3/4: the bar starts two beats before the clip")
  eq(text:find("  s1v1: r/1:2  G4/1:4 lyric=Oh lyrics=And", 1, true) ~= nil, true, "the pickup's note after the bar's empty start:\n" .. text)
  eq(text:find("C5/1:4 lyric=hap- lyrics=sing-  B4/1:4 lyric=py lyrics=ing  A4/1:4 lyric=day_ lyrics=now", 1, true) ~= nil, true, "hyphens and an extender, two verses")
  eq(text:find("m2 rehearsal A", 1, true) ~= nil, true, "the rehearsal mark")
  for _, want in ipairs({ "mark chord 30240 value=C", "mark chord 50400 value=Am7", "mark chord 60480 value=F/A",
    "mark chord 80640 value=G7", "mark chord 90720 value=N.C.", "mark text 30240 value=dolce" }) do
    eq(text:find(want, 1, true) ~= nil, true, want)
  end
end)

test("musicxml: key, clef and time signature changes are on their bars", function()
  local mx = load()
  local text = describe(assert(mx.parse(CHANGES)).parts[1].score)
  eq(text:find("m1 meter 4/4 common key 0 C major", 1, true) ~= nil, true, "common time in C:\n" .. text)
  eq(text:find("m2 meter 3/4 key -3 Eb major", 1, true) ~= nil, true, "Eb major in 3/4")
  eq(text:find("m3 clef 1=bass", 1, true) ~= nil, true, "the clef written at the end of bar 2 is bar 3's")
  eq(text:find("m4 meter 6/8 key -3 C minor", 1, true) ~= nil, true, "C minor in 6/8")
  eq(text:find("m5 meter 8/8(3+3+2) clef 1=treble8", 1, true) ~= nil, true, "3+3+2/8 in the guitar's clef")
end)

test("musicxml: repeats, first and second endings, double and final barlines", function()
  local mx = load()
  local text = describe(assert(mx.parse(REPEATS)).parts[1].score)
  eq(text:find("m1 meter 2/4 repeat_start true", 1, true) ~= nil, true, "the repeat starts:\n" .. text)
  eq(text:find("m2 barline :| volta 1", 1, true) ~= nil, true, "the first ending, the repeat ends")
  eq(text:find("m3 volta 2", 1, true) ~= nil, true, "the second ending")
  eq(text:find("m4 barline ||", 1, true) ~= nil, true, "a double barline")
  eq(text:find("m5 barline |.", 1, true) ~= nil, true, "the final barline")
end)

test("musicxml: tuplets, grace notes, ornaments and dynamics; what cannot be kept is counted", function()
  local mx = load()
  local file = assert(mx.parse(TUPLETS))
  local text = describe(file.parts[1].score)
  eq(text:find("C5/1:8{3:2#1}  D5/1:8{3:2#1}  E5/1:8{3:2#1}  F5/1:16{5:4#4}", 1, true) ~= nil, true, "a triplet and a quintuplet:\n" .. text)
  eq(text:find("D5/1:8 gacciaccatura  C5/1:4 orn=trill  B4/1:8 gappoggiatura  A4/1:4 orn=mordent", 1, true) ~= nil, true, "grace notes and ornaments")
  eq(text:find("C4+E4+G4/1:4 [accent] arpeggio=up  E5/1:4 [tenuto] orn=prall  G5/1:4 [marcato,staccatissimo]  C6/1:4 [fermata_short] orn=turn", 1, true) ~= nil, true, "marks on chords")
  eq(text:find("mark dynamic 40320 value=sfz", 1, true) ~= nil, true, "sfz")
  eq(text:find("mark dynamic 50400 value=p subito=true", 1, true) ~= nil, true, "p subito")
  eq(text:find("mark hairpin 60480 to 70560 value=dim niente=true", 1, true) ~= nil, true, "a diminuendo to nothing")
  eq(mx.skipped_text(file), "1 <fingering>, 1 <pedal>", "the pedal and the fingering said, not kept")
end)

-- Round trips -----------------------------------------------------------------------------------

for name, fixture in pairs({ piano = PIANO, ["lead sheet"] = LEAD, changes = CHANGES, repeats = REPEATS, tuplets = TUPLETS }) do
  test("musicxml: the " .. name .. " written out and read back is the same score", function()
    local mx = load()
    local a, b, out = round(fixture)
    eq(describe(b), describe(a), "the score again")
    local twice = mx.write({ { name = "x", score = b } }, {})
    local once = mx.write({ { name = "x", score = a } }, {})
    eq(twice, once, "and written again, the same file")
    eq(out:find("<score-partwise", 1, true) ~= nil, true, "a partwise file")
  end)
end

test("musicxml: a slur written out ends on a chord of the voice it starts in", function()
  local _, _, out = round(PIANO)
  local stop = out:match("<note[^>\n]*>[^\n]-slur type=\"stop\"[^\n]-</note>")
  eq(stop and stop:find("<voice>1</voice>", 1, true) ~= nil and stop:find("<step>A</step>", 1, true) ~= nil, true, tostring(stop))
end)

test("musicxml: a .mxl, zipped as MuseScore writes it (deflated), reads as the score inside", function()
  local mx = load()
  -- A stored archive written here, and deflate streams of fixed and
  -- dynamic codes from zlib.
  local path = T.scratch .. "/mx-stored.mxl"
  write_file(path, mx.mxl(REPEATS, "repeats"))
  local file = assert(mx.read(path))
  eq(describe(file.parts[1].score), describe(assert(mx.parse(REPEATS)).parts[1].score), "the stored archive")
  local bytes = DEFLATED:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)
  path = T.scratch .. "/mx-deflated.mxl"
  write_file(path, bytes)
  local text = describe(assert(mx.read(path)).parts[1].score)
  eq(text:find("  s1v1: B5/1:2", 1, true) ~= nil and text:find("m14", 1, true) ~= nil, true, "dynamic codes: all fourteen bars, the last a B:\n" .. text)
end)

-- The project ----------------------------------------------------------------------------------

test("musicxml: :open makes a project of the file, its tempo, title, key and marker; the score plays what it says", function()
  fresh()
  load()
  local path = T.scratch .. "/mx-piano.musicxml"
  write_file(path, PIANO)
  paw.commands.exec("open! " .. path)
  local tracks = paw.tracks()
  eq(#tracks, 1, "a track for the part")
  eq(tracks[1].name, "Piano", "named after it")
  eq(api.project_get("name"), "mx-piano", "the project is named after the file")
  eq(api.project_get("path"), nil, "and has no file of its own")
  eq(api.project_get().meta.title, "Little Piece", "the title for the page")
  eq(math.floor(paw.tempo.at(0) + 0.5), 72, "the tempo mark's bpm is the song's tempo")
  local clip = tracks[1]:clips()[1]
  local view = require("notation")
  eq((clip:notes()[1].meta or {}).notation ~= nil, true, "a MIDI clip whose notes keep what the score decided")
  local found
  for _, n in ipairs(clip:notes()) do
    if n.pitch == 81 then
      eq(found, nil, "the tied A is one note")
      found = n
    end
  end
  eq(found and math.floor(found.start * 1000 + 0.5) / 1000, 2, "it starts on beat 3")
  eq(found and math.floor(found.length * 1000 + 0.5) / 1000, 3, "and lasts the half and the quarter tied")
  eq(clip:notes()[1].velocity, 52, "p")
  local programs = 0
  for _, k in ipairs(clip:controls()) do
    if k.type == "program" and k.program == 0 then programs = programs + 1 end
  end
  eq(programs, 1, "the part's program as a program change")
end)

test("musicxml: grace notes play before the beat or on it, and a pickup's clip starts at its note", function()
  fresh()
  load()
  local path = T.scratch .. "/mx-tuplets.musicxml"
  write_file(path, TUPLETS)
  paw.cursor.set_beat(8)
  paw.commands.exec("import " .. path)
  local track = paw.tracks()[1]
  local clip = track:clips()[1]
  eq(clip:get().start, 8, "the first bar at the cursor")
  local at = {}
  for _, n in ipairs(clip:notes()) do at[#at + 1] = string.format("%s@%g+%g", paw.music.name(n.pitch), math.floor(n.start * 1e4 + 0.5) / 1e4, math.floor(n.length * 1e4 + 0.5) / 1e4) end
  local text = table.concat(at, " ")
  eq(text:find("D5@1.875+0.125", 1, true) ~= nil, true, "the acciaccatura a 32nd before beat 3: " .. text)
  eq(text:find("B4@2.875+0.125", 1, true) ~= nil and text:find("A4@3+", 1, true) ~= nil, true, "the appoggiatura a 32nd before beat 4, its note on the beat: " .. text)
  eq(text:find("D5@0.3333+", 1, true) ~= nil, true, "the triplet's second note a third of a beat in")
  fresh()
  path = T.scratch .. "/mx-lead.musicxml"
  write_file(path, LEAD)
  paw.cursor.set_beat(0)
  paw.commands.exec("import " .. path .. " tempo=yes")
  clip = paw.tracks()[1]:clips()[1]
  eq(clip:get().start, 2, "the pickup's note on beat 3 of the first bar")
  eq(clip:notes()[1].start, 0, "where the clip starts")
  local names = {}
  for _, m in ipairs(require("paw.markers").list()) do names[#names + 1] = m.name .. "@" .. m.beat end
  eq(table.concat(names, " "), "A@3", "a marker at the rehearsal mark")
  local num, den = paw.tempo.signature_at(1)
  eq(num .. "/" .. den, "3/4", "the time signature with tempo=yes")
end)

test("musicxml: :notation.export writes the score clip back, and `all` every track as a part", function()
  fresh()
  local mx = load()
  local path = T.scratch .. "/mx-changes.musicxml"
  write_file(path, CHANGES)
  paw.commands.exec("open! " .. path)
  local track = paw.tracks()[1]
  paw.cursor.set_track(track)
  paw.cursor.set_beat(0)
  local out = T.scratch .. "/mx-changes-out.musicxml"
  paw.commands.exec("notation.export " .. out)
  local again = assert(mx.read(out))
  eq(describe(again.parts[1].score), describe(assert(mx.parse(CHANGES)).parts[1].score), "the score as it came in")
  local other = paw.add_track({ name = "Bass" })
  other:add_clip({ start = 0, length = 4, notes = { { pitch = 40, start = 0, length = 4, velocity = 80 } } })
  paw.flush()
  paw.commands.exec("notation.export " .. T.scratch .. "/mx-all.mxl all")
  local both = assert(mx.read(T.scratch .. "/mx-all.mxl"))
  eq(#both.parts, 2, "two parts")
  eq(both.parts[2].name, "Bass", "the plain MIDI clip's track too, written as a score")
  eq(#both.parts[2].score.measures, #both.parts[1].score.measures, "as many bars as the longest part")
  eq(describe(both.parts[2].score):find("s1v1: E2/1:1", 1, true) ~= nil, true, "the bass's whole note")
end)

test("musicxml: LilyPond is written from the score with its changes, endings, tuplets, graces and lyrics", function()
  local mx = load()
  local ly = require("notation.lilypond")
  local function lily(text)
    local file = assert(mx.parse(text))
    return ly.write({ { name = file.parts[1].name, score = file.parts[1].score } }, { title = "t" })
  end
  local a = lily(CHANGES)
  for _, want in ipairs({ "\\key es \\major", "\\time 3/4", "\\clef bass", "\\key c \\minor", "\\time 3,3,2 8/8", '\\clef "treble_8"', "\\defaultTimeSignature" }) do
    eq(a:find(want, 1, true) ~= nil, true, want .. " in\n" .. a)
  end
  local b = lily(REPEATS)
  for _, want in ipairs({ '\\bar ".|:"', '\\bar ":|."', "(volta \"1.\")", "(volta \"2.\")", '\\bar "||"', '\\bar "|."' }) do
    eq(b:find(want, 1, true) ~= nil, true, want .. " in\n" .. b)
  end
  local c = lily(TUPLETS)
  for _, want in ipairs({ "\\tuplet 3/2 {", "\\tuplet 5/4 {", "\\acciaccatura { d''8 }", "\\appoggiatura { b'8 }", "\\trill", "\\sfz",
    "\\arpeggio", "\\shortfermata", "\\>", "\\!" }) do
    eq(c:find(want, 1, true) ~= nil, true, want .. " in\n" .. c)
  end
  local d = lily(LEAD)
  for _, want in ipairs({ "\\partial 4*1", '\\mark "A"', '\\lyricsto "p1s1v1" { "Oh" "hap" -- "py" "day" __', '"And" "sing" -- "ing" "now"', '^\\markup { "Am7" }' }) do
    eq(d:find(want, 1, true) ~= nil, true, want .. " in\n" .. d)
  end
  local e = lily(PIANO)
  for _, want in ipairs({ "\\new PianoStaff", "\\voiceTwo", '\\tempo "Andante" 4 = 72', "a''2~", "\\p", "\\<", "\\f" }) do
    eq(e:find(want, 1, true) ~= nil, true, want .. " in\n" .. e)
  end
end)
