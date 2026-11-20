-- Tests of the full score and the parts (`notation.parts`): orchestral
-- order and brackets, transposition, multi-measure rests, cues, page
-- turns at rests, condensed staves, and what is exported. Loaded by
-- tests.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation"), require("notation.parts")
end

local function ok(cond, what) eq(cond and true or false, true, what) end

local function N(pitch, start, length) return { pitch = pitch, start = start, length = length or 1, velocity = 80 } end

--- A bar of four quarters from `pitch` up the C major scale.
local function bar(notes, b, pitch)
  local scale = { 0, 2, 4, 5 }
  for k = 0, 3 do notes[#notes + 1] = N(pitch + scale[k + 1], b * 4 + k, 1) end
end

--- A quartet in the track order a score would not keep: the cello first.
--- Flutes 1 and 2 play the same in bar 1, flute 1 alone in bar 2,
--- different lines in bar 3; the clarinet in B flat plays bars 1 and 6;
--- the cello rests from bar 2 to 5.
local function quartet(bars)
  fresh()
  local view, P = load()
  bars = bars or 8
  local fl1, fl2, cl, vc = {}, {}, {}, {}
  bar(fl1, 0, 72) bar(fl2, 0, 72)
  bar(fl1, 1, 74)
  bar(fl1, 2, 76) bar(fl2, 2, 67)
  bar(cl, 0, 60) bar(cl, 5, 62)
  bar(vc, 0, 48) bar(vc, 5, 48)
  for b = 6, bars - 1 do bar(vc, b, 48) end
  local tracks = {}
  for _, spec in ipairs({ { "Violoncello", vc }, { "Flute 1", fl1 }, { "Flute 2", fl2 }, { "Clarinet in Bb", cl } }) do
    local track = paw.add_track({ name = spec[1] })
    track:add_clip({ start = 0, length = bars * 4, name = spec[1], notes = spec[2] })
    tracks[spec[1]] = track
  end
  paw.flush()
  api.undo_checkpoint()
  return view, P, tracks
end

local function pitches(evs)
  local out = {}
  for _, ev in ipairs(evs) do
    if ev.kind == "note" then
      for _, n in ipairs(ev.notes) do out[#out + 1] = require("notation.model").name(n) end
    end
  end
  return table.concat(out, " ")
end

test("the full score orders instruments as an orchestra does, a bracket over each family", function()
  local _, P = quartet()
  local names = {}
  for i, e in ipairs(P.instruments()) do names[i] = e.name end
  eq(table.concat(names, ", "), "Flute 1, Flute 2, Clarinet in Bb, Violoncello", "woodwinds before strings, the flutes before the clarinet")
  local layout = P.score_layout()
  eq(#layout.staves, 4, "a staff each")
  eq(layout.labels[1].full .. " / " .. layout.labels[1].short, "Flute 1 / Fl. 1", "a full name and a short one")
  eq(layout.labels[3].short, "Cl.", "the clarinet's short name")
  eq(#layout.brackets, 2, "two families bracketed")
  eq(layout.brackets[1][1] .. "-" .. layout.brackets[1][2], "1-3", "the woodwinds' bracket")
  eq(#layout.spans, 2, "the barlines stop between the families")
  eq(pitches(layout.measures[1].staves[3]), "C4 D4 E4 F4", "the score is at concert pitch")
end)

test("a part for an instrument in B flat is written a major second up, in its key", function()
  local _, P, tracks = quartet()
  local iv = P.interval("Bb")
  eq(iv.steps .. "," .. iv.semis .. "," .. iv.fifths, "1,2,2", "B flat: a second, two semitones, two sharps")
  iv = P.interval("Eb up")
  eq(iv.steps .. "," .. iv.semis .. "," .. iv.fifths, "-2,-3,3", "an E flat clarinet is written a minor third down: C major as A major")
  iv = P.interval("F")
  eq(iv.steps .. "," .. iv.semis .. "," .. iv.fifths, "4,7,1", "a horn in F a fifth up")
  eq(P.interval("Bb octave").semis, 14, "a tenor sax a ninth up")
  eq(P.interval("C"), nil, "in C is not transposed")
  local id = tracks["Clarinet in Bb"].id
  eq(P.transposition(id).name, "Bb", "the name says the key")
  local layout = P.part_layout(id)
  eq(layout.fifths, 2, "D major's two sharps")
  eq(pitches(layout.measures[1].staves[1]), "D4 E4 F#4 G4", "each note a tone up, spelled in the key")
  eq(layout.part_name, "Clarinet in Bb", "the part is named")
  paw.commands.exec("part Clarinet")
  paw.commands.exec("part.transpose A")
  eq(pitches(P.part_layout(id).measures[1].staves[1]), "Eb4 F4 G4 Ab4", "in A a minor third up")
  paw.commands.exec("part.transpose off")
  eq(pitches(P.part_layout(id).measures[1].staves[1]), "C4 D4 E4 F4", "off: as it sounds")
end)

test("bars of rest in a part are one multi-measure rest, numbered on after it", function()
  local _, P, tracks = quartet()
  local layout = P.part_layout(tracks["Violoncello"].id)
  eq(#layout.measures, 5, "bar 1, the rest, bars 6, 7 and 8")
  eq(layout.measures[2].multirest, 4, "four bars counted")
  eq(layout.measures[2].staves[1][1].multirest, 4, "a rest that says so")
  eq(layout.measures[3].number, 6, "the bar after it is bar 6")
  eq(layout.measures[3].index, 3, "measures numbered again in order")
  -- A rehearsal mark breaks the rest where it is.
  local view = require("notation")
  view:edit(tracks["Flute 1"]:clips()[1])
  view:write(function(sc)
    sc.measures[4].rehearsal = "B"
    require("notation.doc").touch(sc, 4)
  end)
  layout = P.part_layout(tracks["Violoncello"].id)
  eq(layout.measures[2].multirest, 2, "two bars before the mark")
  eq(layout.measures[3].rehearsal, "B", "the score's rehearsal mark is in every part")
  eq(layout.measures[3].multirest, 2, "two after it")
end)

test("a cue writes another instrument's notes small in a part's rests", function()
  local view, P, tracks = quartet()
  view:edit(tracks["Violoncello"]:clips()[1])
  paw.commands.exec("part Violoncello")
  paw.commands.exec("2,3part.cue Flute 1")
  local own = P.own(tracks["Violoncello"].id)
  eq(#own.cues, 1, "kept with the track's part")
  local layout = P.part_layout(tracks["Violoncello"].id)
  local cue = layout.measures[2].staves[1]
  local small = 0
  for _, ev in ipairs(cue) do
    if ev.cue and ev.kind == "note" then small = small + 1 end
  end
  eq(small, 4, "the flute's four notes of bar 2")
  eq(pitches({ cue[1] }), "D5", "as the flute plays them")
  eq(layout.measures[2].marks[1].value, "Fl. 1", "named over them")
  eq(layout.measures[4].multirest, 2, "the rest after the cue counts on")
  paw.commands.exec("2,3part.cue off")
  eq(P.own(tracks["Violoncello"].id).cues, nil, "taken away")
end)

test("a part's pages turn where it rests", function()
  fresh()
  local _, P = load()
  local engrave, page = require("notation.engrave"), require("notation.page")
  -- A long part with a bar of rest every eleventh, where it can turn.
  local notes = {}
  for b = 0, 159 do
    if b % 11 ~= 10 then bar(notes, b, 48) end
  end
  local track = paw.add_track({ name = "Violoncello" })
  track:add_clip({ start = 0, length = 160 * 4, name = "cello", notes = notes })
  paw.flush()
  local layout = P.part_layout(track.id)
  local st = engrave.style({ space = 10, cell = { w = 1, h = 1 }, ink = "#000000", paper = "#ffffff", accent = "#000000" })
  local geo = page.geometry(10)
  local eng = page.systems(layout, st, geo, geo.width)
  ok(#eng.pages >= 3, "a part of several pages")
  -- Laid out without regard to turns, a page would end mid-phrase.
  do
    local turns, asked = layout.turns, layout.asked
    layout.turns, layout.asked = nil, { breaks = {}, joins = {} }
    local e2 = page.systems(layout, st, geo, geo.width)
    local bad = 0
    for i = 1, #e2.pages - 1, 2 do
      local list = e2.pages[i].systems
      if not turns[list[#list].measures[#list[#list].measures].m.index] then bad = bad + 1 end
    end
    eq(bad, 1, "without turns, one turn falls in the music")
    layout.turns, layout.asked = turns, asked
  end
  for i = 1, #eng.pages - 1, 2 do
    local list = eng.pages[i].systems
    local last = list[#list].measures[#list[#list].measures].m
    eq(layout.turns[last.index] == true, true, "page " .. i .. " ends in a bar of rest, to turn")
  end
end)

test("a condensed score puts two flutes on one staff: a2, 1., and two voices", function()
  local _, P = quartet()
  local layout = P.score_layout({ condensed = true })
  eq(#layout.staves, 3, "the flutes share a staff")
  eq(layout.labels[1].full, "Flute 1.2", "named for both")
  eq(layout.labels[1].short, "Fl. 1.2", "and short")
  local m1, m2, m3 = layout.measures[1], layout.measures[2], layout.measures[3]
  local function texts(m)
    local out = {}
    for _, mk in ipairs(m.marks) do
      if mk.kind == "text" and mk.staff == 1 then out[#out + 1] = mk.value end
    end
    return table.concat(out, " ")
  end
  eq(texts(m1), "a2", "the same notes: a2")
  eq(pitches(m1.staves[1]), "C5 D5 E5 F5", "written once")
  eq(texts(m2), "1.", "the first alone")
  local up, down = 0, 0
  for _, ev in ipairs(m3.staves[1]) do
    if ev.kind == "note" and ev.voice == 1 and ev.stem == 1 then up = up + 1 end
    if ev.kind == "note" and ev.voice == 2 and ev.stem == -1 then down = down + 1 end
  end
  eq(up .. " " .. down, "4 4", "different lines: two voices, stems apart")
  paw.commands.exec("part.condense")
end)

test("parts and the score export as PDF pages and MusicXML with parts", function()
  local view, P, tracks = quartet()
  view:edit(tracks["Flute 1"]:clips()[1])
  local dir = T.scratch .. "/parts"
  os.execute("mkdir -p " .. dir)
  paw.commands.exec("part Flute 1")
  local wrote, pages = paw.commands.get("part.export").run({ args = { dir .. "/q.pdf", "all" } })
  eq(#wrote, 4, "a file for each part")
  eq(pages, 4, "each part on one page")
  local f = io.open(dir .. "/q-Clarinet_in_Bb.pdf", "rb")
  local pdf = f:read("*a")
  f:close()
  local _, count = pdf:gsub("/Type%s*/Page[^s]", "")
  eq(count, 1, "the clarinet's part is one page")
  wrote, pages = paw.commands.get("part.export").run({ args = { dir .. "/score.pdf", "score" } })
  eq(#wrote == 1 and pages >= 1, true, "the score in a file")
  local n = P.musicxml(dir .. "/score.musicxml")
  eq(n, 4, "four parts")
  local xml = io.open(dir .. "/score.musicxml"):read("*a")
  ok(xml:find("<transpose><diatonic>-1</diatonic><chromatic>-2</chromatic></transpose>", 1, true), "the clarinet says how it sounds")
  ok(xml:find('<part-group type="start" number="1"><group-name>Woodwinds', 1, true), "the woodwinds bracketed")
  ok(xml:find("<part-abbreviation>Fl. 1</part-abbreviation>", 1, true), "short names")
  -- Read back, the clarinet is at concert pitch again.
  local file = require("notation.musicxml").read(dir .. "/score.musicxml")
  eq(file.parts[3].name, "Clarinet in Bb", "the clarinet")
  local first = file.parts[3].score.measures[1].voices[1].events[1].notes[1]
  eq(require("notation.doc").pitch(first), 60, "C4 as it sounds")
end)

test("the terminal's cell view draws the score's names and a part's multi-measure rest", function()
  local view, P, tracks = quartet()
  view:edit(tracks["Violoncello"]:clips()[1])
  paw.ui.focus("notation")
  paw.keymap.set_mode("n")
  paw.keymap.feed("\\Ps")
  api.undo_checkpoint()
  eq(view.parts and view.parts.kind, "score", "\\Ps shows the score")
  local text = table.concat(api.ui_snapshot(140, 60), "\n")
  ok(text:find("Flute 1", 1, true), "the first flute named")
  ok(text:find("the full score, staff 4 of 4", 1, true), "the info line says what is shown, and the cello's staff is the active one")
  paw.commands.exec("part Violoncello")
  text = table.concat(api.ui_snapshot(140, 60), "\n")
  ok(text:find("━━ 4 ━━", 1, true), "the cello's four bars of rest as one")
  ok(text:find("part: Violoncello", 1, true), "the part named")
  paw.keymap.feed("\\Pn")
  api.undo_checkpoint()
  eq(view.parts.track, P.instruments()[1].id, "\\Pn goes round to the first part")
  paw.keymap.feed("\\Po")
  api.undo_checkpoint()
  eq(view.parts, nil, "\\Po: the clip alone again")
end)

test(":help notation-parts finds the parts' section", function()
  load()
  local tag = paw.help.lookup("notation-parts")
  eq(tag and (tag.source.name .. " " .. tag.name), "notation/doc/reference.md notation-parts", "the reference's section")
end)
