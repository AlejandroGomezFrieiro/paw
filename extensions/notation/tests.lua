-- Tests for the notation extension; run by tests/suite.lua.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local paw = require("paw")
local api = paw.api

local function load()
  if not package.loaded["notation.keys"] then paw.ext.load("extensions/notation") end
  return require("notation"), require("notation.model")
end

local function N(pitch, start, length) return { pitch = pitch, start = start, length = length } end

--- The model's text for some notes: "q. C4 e D4 h E4 | ...".
local function written(notes, opts)
  local _, model = load()
  opts = opts or {}
  opts.length = opts.length or 4
  return model.text(model.layout(notes, opts), opts.staff)
end

-- From notes to notation --------------------------------------------------------------------

test("notation: a dotted quarter and an eighth are written so", function()
  eq(written({ N(60, 0, 1.5), N(62, 1.5, 0.5), N(64, 2, 2) }), "q. C4 e D4 h E4", "dotted quarter, eighth, half")
end)

test("notation: a note across a barline is tied over it", function()
  eq(written({ N(67, 3, 2), N(65, 5, 3) }, { length = 8 }), "hr qr q~ G4 | q G4 q~ F4 h F4",
    "G tied into the next bar; F from beat two tied to a half on beat three")
end)

test("notation: a syncopation is split at the beat it hides", function()
  eq(written({ N(60, 0, 0.5), N(62, 0.5, 1), N(64, 1.5, 0.5), N(65, 2, 2) }), "e C4 e~ D4 e D4 e E4 h F4",
    "the quarter off the beat is two tied eighths")
  eq(written({ N(60, 0, 1), N(62, 1, 2), N(64, 3, 1) }), "q C4 q~ D4 q D4 q E4", "a half on beat two does not hide the middle of a 4/4 bar")
  eq(written({ N(60, 0, 1), N(62, 1, 2) }, { length = 3, num = 3, den = 4 }), "q C4 h D4", "but stands on beat two of 3/4")
end)

test("notation: rests fill the bar, a bar of silence is one whole rest", function()
  eq(written({ N(60, 1, 1) }, { length = 8 }), "qr q C4 hr | R", "rests before, after, and a whole empty bar")
  eq(written({ N(60, 0, 0.5), N(62, 2, 2) }), "e C4 er qr h D4", "an eighth rest, then a quarter rest to beat three")
end)

test("notation: notes hidden before a trimmed clip's start are not written", function()
  eq(written({ N(55, -1, 1), N(60, 0, 1), N(62, 1, 1), N(64, 2, 2) }), "q C4 q D4 h E4", "the note before 0 is left out")
end)

test("notation: notes that start together are a chord", function()
  eq(written({ N(60, 0, 2), N(64, 0, 2), N(67, 0, 2), N(72, 2, 2) }), "h <C4 E4 G4> h C5", "a C major triad, then C5")
end)

test("notation: accidentals follow the key and the bar's memory", function()
  -- D major: F# is in the key; F natural needs a sign, once a bar.
  eq(written({ N(66, 0, 1), N(65, 1, 1), N(65, 2, 1), N(66, 3, 1), N(65, 4, 1), N(66, 5, 1) }, { length = 8, fifths = 2 }),
    "q F4 q Fn4 q F4 q F#4 | q Fn4 q F#4 hr", "naturals and sharps as the bar remembers them, and the barline forgets")
  -- In C, a C# in one bar is reminded back in the next.
  eq(written({ N(60, 0, 1), N(61, 1, 3), N(60, 4, 1), N(60, 5, 1) }, { length = 8 }), "q C4 q~ C#4 h C4 | q C(n)4 q C4 hr",
    "a tied note keeps its sharp without a sign; the next bar says the C is natural again, once")
end)

test("notation: chromatic notes lean the way the key does", function()
  local _, model = load()
  local function names(fifths)
    local out = {}
    for _, p in ipairs({ 61, 63, 66, 68, 70 }) do out[#out + 1] = model.name(model.spell(p, fifths)) end
    return table.concat(out, " ")
  end
  eq(names(0), "C#4 Eb4 F#4 G#4 Bb4", "in C major")
  eq(names(-3), "Db4 Eb4 Gb4 Ab4 Bb4", "in E flat major")
  eq(names(4), "C#4 D#4 F#4 G#4 A#4", "in E major")
  eq(model.fifths_of("A", "minor"), 0, "A minor has no sharps")
  eq(model.fifths_of("Bb", "major"), -2, "B flat major two flats")
  eq(model.fifths_of("C#", "major"), -5, "C sharp major as D flat: five flats")
  eq(model.fifths_of("G", "dorian"), -1, "G dorian one flat")
end)

test("notation: beams follow the beat, by half bars in 4/4 and by three eighths in 6/8", function()
  local _, model = load()
  local function beams(notes, opts)
    local layout = model.layout(notes, opts)
    local out = {}
    for _, ev in ipairs(layout.measures[1].staves[1]) do out[#out + 1] = ev.kind == "rest" and "r" or tostring(ev.beam or "-") end
    return table.concat(out, " ")
  end
  local eighths = {}
  for i = 0, 7 do eighths[#eighths + 1] = N(72, i * 0.5, 0.5) end
  eq(beams(eighths, { length = 4 }), "1 1 1 1 2 2 2 2", "eight eighths in 4/4: two beams of four")
  eq(beams({ N(72, 0, 0.5), N(72, 0.5, 0.5), N(72, 1, 1), N(72, 2, 0.5), N(72, 2.5, 0.25), N(72, 2.75, 0.25), N(72, 3, 1) }, { length = 4 }),
    "1 1 - 2 2 2 -", "pairs within a beat; quarters stand alone")
  local six = {}
  for i = 0, 5 do six[#six + 1] = N(72, i * 0.5, 0.5) end
  eq(beams(six, { length = 3, num = 6, den = 8 }), "1 1 1 2 2 2", "6/8: two groups of three")
  eq(written({ N(60, 0, 2), N(62, 2, 1) }, { length = 3, num = 6, den = 8 }), "q.~ C4 e C4 q D4", "6/8: a half note is split at the dotted quarter")
  local layout = model.layout({ N(72, 0, 0.5), N(74, 0.5, 0.5), N(60, 1, 0.5), N(62, 1.5, 0.5) }, { length = 2, num = 2, den = 4 })
  local evs = layout.measures[1].staves[1]
  eq(evs[1].stem, -1, "high notes: stems down")
  eq(evs[3].stem, 1, "low notes: stems up")
  eq(evs[1].flags, 1, "an eighth has one beam")
end)

test("notation: the clef is chosen by the notes, or fixed by the track", function()
  local _, model = load()
  eq(table.concat(model.layout({ N(72, 0, 1), N(64, 1, 1) }, { length = 4 }).staves, " "), "treble", "a melody above middle C")
  eq(table.concat(model.layout({ N(40, 0, 1), N(48, 1, 1) }, { length = 4 }).staves, " "), "bass", "a bass line")
  eq(table.concat(model.layout({ N(36, 0, 1), N(79, 0, 1) }, { length = 4 }).staves, " "), "treble bass", "both: a grand staff")
  eq(table.concat(model.layout({ N(72, 0, 1) }, { length = 4, clef = "bass" }).staves, " "), "bass", "a fixed clef wins")
  eq(written({ N(48, 0, 4), N(72, 0, 1), N(74, 1, 3) }, { staff = 2 }), "w C3", "the low C goes to the bass staff")
end)

test("notation: what was played loosely is written to the grid, and the notes stay as played", function()
  local _, model = load()
  local notes = { N(60, 0.03, 0.46), N(62, 0.52, 0.47), N(64, 0.98, 1.05) }
  eq(written(notes), "e C4 e D4 q E4 hr", "rounded to sixteenths")
  eq(notes[1].start, 0.03, "the notes themselves are not touched")
  eq(written({ N(60, 0, 1) }, { offset = 2 }), "hr q C4 qr | R", "a clip starting on beat three begins with rests")
end)

-- The score layer: what was played, written as a musician would ----------------------------

-- Clean scores, played: a seeded random, jitter, strums, swing, rubato.
local seed = 1
local function rand()
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed / 2147483648
end
local function spread(x) return (rand() * 2 - 1) * x end

--- Notes from text: "C4+E4 0 1, G4 1 0.5" (pitches, start, length).
local function clean(text)
  local out = {}
  for item in text:gmatch("[^,]+") do
    local p, st, l = item:match("(%S+)%s+(%S+)%s+(%S+)")
    for name in p:gmatch("[^+]+") do out[#out + 1] = { pitch = paw.music.pitch(name), start = tonumber(st), length = tonumber(l), velocity = 90 } end
  end
  table.sort(out, function(a, b) return a.start < b.start or (a.start == b.start and a.pitch < b.pitch) end)
  return out
end

--- Play clean notes: `jitter` ms either way, lengths `legato` of written
--- (0.9) give or take `release` ms, chords strummed `strum` ms a string
--- (`dir` 1 low first, -1 high first, "alt"), `swing` the long eighth's
--- share, `ahead` ms early, `rit` beats late by the end (growing with the
--- square), `overlap` beats past the written end, `graces` { name, main's
--- start, ms before, ms long }.
local function play(notes, o)
  local beat_ms = 60000 / (o.tempo or 120)
  local function ms(v) return v / beat_ms end
  local by, starts = {}, {}
  for _, n in ipairs(notes) do
    if not by[n.start] then starts[#starts + 1] = n.start end
    by[n.start] = by[n.start] or {}
    table.insert(by[n.start], n)
  end
  table.sort(starts)
  local last = notes[#notes].start + notes[#notes].length
  local function warp(t)
    local x = t
    if o.swing and math.abs(t - math.floor(t) - 0.5) < 1e-6 then x = math.floor(t) + o.swing end
    if o.rit then x = x + o.rit * (t / last) ^ 2 end
    return x
  end
  local out = {}
  for ci, st in ipairs(starts) do
    local chord = by[st]
    local dir = o.dir or 1
    if dir == "alt" then dir = ci % 2 == 1 and 1 or -1 end
    local base = warp(st) + ms(spread(o.jitter or 0)) - ms(o.ahead or 0)
    for k, n in ipairs(chord) do
      local order = dir == 1 and (k - 1) or (#chord - k)
      local start = math.max(0, base + (#chord > 1 and ms((o.strum or 0) * order) or 0))
      local finish = warp(n.start + n.length) - (1 - (o.legato or 0.9)) * n.length + ms(spread(o.release or 0))
      if o.overlap then finish = warp(n.start + n.length) + o.overlap end
      out[#out + 1] = { pitch = n.pitch, start = start, length = math.max(0.02, finish - start), velocity = 70 + math.floor(rand() * 40) }
    end
  end
  for _, g in ipairs(o.graces or {}) do
    out[#out + 1] = { pitch = paw.music.pitch(g[1]), start = g[2] - ms(g[3]), length = ms(g[4]), velocity = 70 }
  end
  table.sort(out, function(a, b) return a.start < b.start or (a.start == b.start and a.pitch < b.pitch) end)
  return out
end

--- What is written for the clean score and for it played.
local function both(text, how, opts, staff, voice)
  local _, model = load()
  opts = opts or {}
  opts.length = opts.length or 4
  local function copy() return paw.util.merge(opts, {}) end
  return model.text(model.layout(clean(text), copy()), staff, voice), model.text(model.layout(play(clean(text), how), copy()), staff, voice)
end

local MELODY = "C4 0 0.5, D4 0.5 0.5, E4 1 1, G4 2 0.5, F4 2.5 0.5, E4 3 0.75, D4 3.75 0.25, C4 4 2, G4 6 1, C5 7 1"

test("score: a melody played loosely is written as the clean score", function()
  for s = 1, 6 do
    seed = s
    local want, got = both(MELODY, { jitter = 20, release = 25 }, { length = 8 })
    eq(got, want, "seed " .. s .. ": onsets within 20 ms and releases within 25 ms of the score")
  end
  eq(select(1, both(MELODY, {}, { length = 8 })), "e C4 e D4 q E4 e G4 e F4 e. E4 s D4 | h C4 q G4 q C5", "the clean score itself")
end)

test("score: a part played ahead of the beat, legato, or slowing down is written straight", function()
  seed = 3
  local want, got = both(MELODY, { jitter = 10, ahead = 40 }, { length = 8 })
  eq(got, want, "40 ms ahead of the beat throughout")
  want, got = both(MELODY, { jitter = 15, overlap = 0.15 }, { length = 8 })
  eq(got, want, "every note held into the next: legato, no ties")
  want, got = both(MELODY, { jitter = 10, rit = 0.4 }, { length = 8 })
  eq(got, want, "a ritardando against the grid, the last note almost half a beat late")
  local run = "C4 0 0.5, D4 0.5 0.5, E4 1 0.5, F4 1.5 0.5, G4 2 0.5, A4 2.5 0.5, B4 3 0.5, C5 3.5 0.5, D5 4 1, C5 5 0.5, B4 5.5 0.5, "
    .. "A4 6 0.5, G4 6.5 0.5, F4 7 0.5, E4 7.5 0.5, D4 8 0.5, C4 8.5 0.5, D4 9 0.5, E4 9.5 0.5, F4 10 0.5, E4 10.5 0.5, D4 11 0.5, B3 11.5 0.5, C4 12 4"
  for s = 1, 3 do
    seed = 30 + s
    want, got = both(run, { jitter = 12, rit = 1.2 }, { length = 16 })
    eq(got, want, "eighths slowing until they are more than a beat behind, seed " .. s)
  end
end)

local CHORDS = "E3+G#3+B3+E4 0 1, E3+G#3+B3+E4 1 1, A3+C#4+E4+A4 2 0.5, A3+C#4+E4+A4 2.5 0.5, B3+D#4+F#4+B4 3 1"

test("score: strums are chords on the beat, in either direction, at any speed", function()
  seed = 7
  for _, case in ipairs({ { 8, 1 }, { 12, -1 }, { 18, "alt" }, { 25, 1 } }) do
    local want, got = both(CHORDS, { jitter = 15, strum = case[1], dir = case[2] }, { clef = "treble" })
    eq(got, want, case[1] .. " ms a string, direction " .. tostring(case[2]))
  end
  local _, got = both(CHORDS, { jitter = 10, strum = 60, dir = 1 }, { clef = "treble" })
  eq(got, "q <E3 G#3 B3 E4>^ q <E3 G3 B3 E4>^ e <A3 C#4 E4 A4>^ e <A3 C4 E4 A4>^ q <B3 Eb4 F#4 B4>^",
    "a slow roll (180 ms across four strings) is marked with an arpeggio sign")
  _, got = both(CHORDS, { jitter = 10, strum = 60, dir = -1 }, { clef = "treble" })
  eq(got:find("q <E3 G#3 B3 E4>v", 1, true), 1, "high to low, the arrow points down")
  local _, model = load()
  local slow = play(clean(CHORDS), { strum = 60, tempo = 60 })
  local layout = model.layout(slow, { length = 4, clef = "treble", tempo = 60, settings = { strum = 20 } })
  eq(model.text(layout):find("q <E3 G#3 B3 E4>", 1, true), nil, "with a window of 20 ms, strings 60 ms apart are not one chord")
  layout = model.layout(slow, { length = 4, clef = "treble", tempo = 60 })
  eq(model.text(layout):find("q <E3 G#3 B3 E4>^", 1, true), 1, "by default they are, with an arpeggio sign")
end)

test("score: swing is written as straight eighths", function()
  local text = "C4 0 0.5, D4 0.5 0.5, E4 1 0.5, F4 1.5 0.5, G4 2 0.5, A4 2.5 0.5, G4 3 1, E4 4 0.5, D4 4.5 0.5, C4 5 0.5, D4 5.5 0.5, E4 6 2"
  seed = 9
  for _, ratio in ipairs({ 0.6, 0.66, 0.7 }) do
    local want, got = both(text, { jitter = 8, swing = ratio }, { length = 8 })
    eq(got, want, "long-short eighths at " .. ratio .. " of the beat")
  end
  local _, model = load()
  local swung = play(clean(text), { swing = 0.66 })
  eq(model.layout(swung, { length = 8 }).score.swing ~= nil, true, "the swing is recognised")
  local straight = model.text(model.layout(swung, { length = 8, settings = { swing = "off" } }))
  eq(straight:find("3{", 1, true) ~= nil, true, "with swing off, the same notes are triplets")
end)

test("score: triplets, quarter-note triplets and 6/8", function()
  seed = 11
  local want, got = both("C4 0 0.5, D4 0.5 0.5, E4 1 0.3333333333, F4 1.3333333333 0.3333333333, G4 1.6666666667 0.3333333333, A4 2 1, G4 3 1", { jitter = 12 })
  eq(want, "e C4 e D4 3{e E4 e F4 e G4} q A4 q G4", "a beat of triplet eighths among straight eighths")
  eq(got, want, "played")
  want, got = both("C5 0 0.6666666667, B4 0.6666666667 0.6666666667, A4 1.3333333333 0.6666666667, G4 2 2", { jitter = 12 })
  eq(want, "3{q C5 q B4 q A4} h G4", "quarter-note triplets over two beats")
  eq(got, want, "played")
  seed = 13
  want, got = both("C4 0 1.5, D4 1.5 0.5, E4 2 0.5, F4 2.5 0.5, G4 3 1, A4 4 0.5, G4 4.5 1.5", { jitter = 18, tempo = 160 }, { num = 6, den = 8, length = 6, tempo = 160 })
  eq(want, "q. C4 e D4 e E4 e F4 | q G4 e A4 q. G4", "6/8 in dotted quarters")
  eq(got, want, "played")
  want = both("C4 0 0.75, D4 0.75 0.75, E4 1.5 1.5", {}, { num = 6, den = 8, length = 3 })
  eq(want, "2{e C4 e D4} q. E4", "a duplet in 6/8")
end)

test("score: quintuplets, sextuplets, septuplets, and quadruplets in 6/8, from where the notes fall", function()
  local function beat_of(n, names)
    local out = { "C4 0 0.5, D4 0.5 0.5" }
    for k = 0, n - 1 do out[#out + 1] = string.format("%s %.10f %.10f", names[k + 1], 1 + k / n, 1 / n) end
    out[#out + 1] = "C5 2 1, G4 3 1"
    return table.concat(out, ", ")
  end
  local names = { "E4", "F4", "G4", "A4", "B4", "A4", "G4" }
  for _, case in ipairs({ { 5, "5{s E4 s F4 s G4 s A4 s B4}" }, { 6, "6{s E4 s F4 s G4 s A4 s B4 s A4}" },
    { 7, "7{s E4 s F4 s G4 s A4 s B4 s A4 s G4}" } }) do
    seed = 40 + case[1]
    local want, got = both(beat_of(case[1], names), { jitter = 8 })
    eq(want, "e C4 e D4 " .. case[2] .. " q C5 q G4", case[1] .. " in a beat")
    eq(got, want, case[1] .. " in a beat, played")
  end
  seed = 47
  local want, got = both("C4 0 0.375, D4 0.375 0.375, E4 0.75 0.375, F4 1.125 0.375, G4 1.5 1.5", { jitter = 8 },
    { num = 6, den = 8, length = 3 })
  eq(want, "4{e C4 e D4 e E4 e F4} q. G4", "four eighths in the time of three in 6/8")
  eq(got, want, "played")
end)

test("score: a straight part played loosely is never written in tuplets", function()
  local sixteenths = {}
  for k = 0, 15 do sixteenths[#sixteenths + 1] = string.format("%s %g 0.25", ({ "C4", "D4", "E4", "F4", "G4" })[k % 5 + 1], k * 0.25) end
  sixteenths = table.concat(sixteenths, ", ")
  for s = 1, 6 do
    seed = 60 + s
    local want, got = both(MELODY, { jitter = 20, release = 25 }, { length = 8 })
    eq(got, want, "a melody within 20 ms, seed " .. s)
    want, got = both(sixteenths, { jitter = 18 })
    eq(got, want, "sixteenths within 18 ms, seed " .. s)
    eq(got:find("{", 1, true), nil, "no tuplet")
    want, got = both("C4 0 0.5, D4 0.5 0.5, E4 1 0.5, F4 1.5 0.5, G4 2 0.5, A4 2.5 0.5", { jitter = 25, tempo = 150 },
      { num = 6, den = 8, length = 3, tempo = 150 })
    eq(got, want, "eighths in 6/8 within 25 ms, seed " .. s)
  end
end)

test("score: a tuplet said in notation wins over the guess, and other tuplets can be turned off", function()
  local _, model = load()
  local five = clean("C4 0 1, E4 1 0.2, F4 1.2 0.2, G4 1.4 0.2, A4 1.6 0.2, B4 1.8 0.2, C5 2 2")
  local said = model.text(model.layout(five, { length = 4, tuplets = { { start = 1, length = 1, plain = true } } }))
  eq(said:find("5{", 1, true), nil, "a beat said to be plain: no quintuplet, " .. said)
  local four = clean("C4 0 1, E4 1 0.25, F4 1.25 0.25, G4 1.5 0.25, A4 1.75 0.25, C5 2 2")
  said = model.text(model.layout(four, { length = 4, tuplets = { { start = 1, length = 1, n = 5, normal = 4 } } }))
  eq(said:find("5{", 1, true) ~= nil, true, "straight sixteenths said to be a quintuplet: one, " .. said)
  local off = model.text(model.layout(five, { length = 4, settings = { tuplets = false } }))
  eq(off:find("5{", 1, true), nil, "with tuplets off, no quintuplet: " .. off)
end)

test("score: grace notes, staccato, and a held note as a second voice", function()
  seed = 15
  local _, got = both("C5 0 1, E5 1 1, G5 2 2", { jitter = 8, graces = { { "D5", 1, 50, 35 }, { "F#5", 2, 45, 30 } } })
  eq(got, "q C5 q [D5]E5 h [F#5]G5", "a short note just before another is its grace note")
  seed = 19
  _, got = both("C5 0 1, D5 1 1, E5 2 1, C5 3 1", { jitter = 10, legato = 0.3 })
  eq(got, "q C5' q D5' q E5' q C5'", "quarters played short are staccato quarters, not sixteenths and rests")
  seed = 17
  local held = "E4 0 2, G4 0 0.5, A4 0.5 0.5, B4 1 0.5, C5 1.5 0.5, D5 2 1, C5 3 1"
  _, got = both(held, { jitter = 10 }, {}, 1, 1)
  eq(got, "e G4 e A4 e B4 e C5 q D5 q C5", "the melody is the first voice")
  _, got = both(held, { jitter = 10 }, {}, 1, 2)
  eq(got, "h E4 hr", "the held E under it the second")
  local _, model = load()
  local layout = model.layout(clean(held), { length = 4 })
  local evs = layout.measures[1].staves[1]
  eq(evs[1].stem, 1, "first voice: stems up")
  local second
  for _, ev in ipairs(evs) do
    if ev.voice == 2 and ev.kind == "note" then second = ev end
  end
  eq(second.stem, -1, "second voice: stems down")
end)

test("score: a grand staff's hands follow the music, not middle C", function()
  local piano = "C3+E3+G3+C5 0 1, B4 1 1, A4 2 0.5, G4 2.5 0.5, F4 3 0.5, E4 3.5 0.5, D4 4 0.5, C4 4.5 0.5, B3 5 1, C4 6 2, C3 4 4"
  seed = 21
  local _, rh = both(piano, { jitter = 10 }, { length = 8, clef = "grand" }, 1)
  eq(rh, "q C5 q B4 e A4 e G4 e F4 e E4 | e D4 e C4 q B3 h C4", "the melody goes on below middle C in the right hand")
  local _, lh = both(piano, { jitter = 10 }, { length = 8, clef = "grand" }, 2)
  eq(lh, "q <C3 E3 G3> qr hr | w C3", "the chord and the held C in the left")
end)

test("score: the performance is untouched and every written note knows its notes", function()
  local _, model = load()
  seed = 5
  local played = play(clean(CHORDS), { jitter = 15, strum = 25 })
  local before = {}
  for i, n in ipairs(played) do before[i] = n.start .. "/" .. n.length .. "/" .. n.velocity end
  local layout = model.layout(played, { length = 4, clef = "treble" })
  for i, n in ipairs(played) do eq(n.start .. "/" .. n.length .. "/" .. n.velocity, before[i], "note " .. i .. " as played") end
  local seen = {}
  for _, ev in ipairs(layout.score.events) do
    for _, n in ipairs(ev.notes) do
      seen[n.index] = true
      eq(math.abs(played[n.index].start - (ev.start + n.offset)) < 1e-9, true, "the offset from the written place is the played one")
    end
  end
  local count = 0
  for _ in pairs(seen) do count = count + 1 end
  eq(count, #played, "each played note is in one written chord")
  local raw = model.text(model.layout(played, { length = 4, clef = "treble", settings = { mode = "raw" } }))
  eq(raw ~= model.text(layout), true, "the raw view writes the strums note for note")
end)

-- Editing ----------------------------------------------------------------------------------

local function song(notes, length)
  fresh()
  local view = load()
  local track = paw.add_track({ name = "Lead" })
  track:add_device("synth")
  local clip = track:add_clip({ start = 0, length = length or 4, name = "tune", notes = notes or {} })
  paw.flush()
  paw.keymap.set_mode("n")
  view:edit(clip)
  view.value, view.dot = 1, false
  return view, clip, track
end

local keys = T.keys

--- The clip's notes as "C4@0+1 D4@1+0.5".
local function notes_of(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do out[#out + 1] = string.format("%s@%g+%g", paw.music.name(n.pitch), n.start, n.length) end
  return table.concat(out, " ")
end

local function model_text_has(view, text)
  local _, model = load()
  return model.text((view:layout())):find(text, 1, true) ~= nil
end

test("notation: the piano roll opened from the notation view takes its clip", function()
  local _, clip = song({ N(67, 1, 1) })
  local roll = paw.ui.views.pianoroll
  roll.clip_id = nil
  paw.ui.hide("pianoroll")
  paw.ui.focus("notation")
  -- (`,p` is the popover for pitch in the notation view: the toggle is the command.)
  paw.cmd("view.toggle", { "pianoroll" })
  eq(roll.clip_id, clip.id, "the toggle opens the notation view's clip")
  paw.ui.hide("pianoroll")
  roll.clip_id = nil
  paw.ui.focus("notation")
  paw.cmd("vs", { "pianoroll" })
  eq(roll.clip_id, clip.id, "so does a split")
  eq(paw.layout.find(paw.ui.layout, "pianoroll") ~= nil, true, "and it is in a window")
end)

test("notation: :notation opens the clip under the cursor, with the keyboard", function()
  local view, clip, track = song({ N(67, 1, 1) })
  paw.ui.focus("arrange")
  view.clip_id = nil
  paw.cursor.set_track(track)
  paw.cursor.beat = 0
  paw.cmd("notation")
  eq(view.clip_id, clip.id, "the clip is open")
  eq(paw.ui.focused, "notation", "and has the keyboard")
  eq(view.step, 39, "the cursor on the first note's line (G4)")
  eq(view.beat, 1, "at its time")
  local found
  for _, entry in ipairs(paw.frontend.menus.clip) do
    if entry.command == "notation.open" then found = entry end
  end
  eq(found and found.only, "midi", "the clip menu offers it for MIDI clips")
  local mapped
  for _, m in ipairs(paw.keymap.list("n", "arrange")) do
    if m.lhs == "<localleader>n" then mapped = m.rhs end
  end
  eq(mapped, "notation", "and the arrange view has a key for it")
end)

test("notation: insert mode enters notes by letter, nearest the note before", function()
  local view, clip = song()
  keys("icdeb")
  eq(notes_of(clip), "C4@0+1 D4@1+1 E4@2+1 B3@3+1", "quarters by letter, B below C rather than above (each as long as its value)")
  keys("<Esc>")
  view:set(39, 0)
  keys("i4ga'")
  eq(notes_of(clip), "G4@0+0.5 A5@0.5+0.5 D4@1+1 E4@2+1 B3@3+1", "eighths replace what was there; ' lifts the last an octave")
end)

test("notation: entering in a key takes its sharps and flats; + and - change the last note", function()
  local view, clip = song()
  paw.cmd("notation.key", { "D", "major" })
  api.undo_checkpoint()
  keys("if")
  eq(notes_of(clip), "F#4@0+1", "f is F sharp in D major")
  keys("+c-")
  eq(notes_of(clip), "G4@0+1 C4@1+1", "+ raises the F sharp to G; c is C sharp, and - lowers it to C natural")
  eq(model_text_has(view, "q G4 q Cn4"), true, "written as a C with a natural sign")
end)

test("notation: chords with capitals, rests, dots and the value keys", function()
  local view, clip = song(nil, 8)
  keys("iCEg")
  eq(notes_of(clip), "C4@0+1 E4@0+1 G4@0+1", "C and E stay, g steps on")
  keys("6.c")
  eq(notes_of(clip), "C4@0+1 E4@0+1 G4@0+1 C5@1+3", "a dotted half")
  keys("r")
  eq(view.beat, 7, "a rest steps on by the value")
  keys("<BS><BS>")
  eq(notes_of(clip), "C4@0+1 E4@0+1 G4@0+1", "backspace steps back and removes")
end)

test("notation: normal keys move by lines and spaces and edit the note under the cursor", function()
  local view, clip = song({ N(64, 0, 1), N(67, 3, 1) })
  view:set(37, 0)
  keys("k")
  eq(view.step, 38, "k: up a line or space")
  keys("j<C-a>")
  eq(notes_of(clip), "F4@0+1 G4@3+1", "Ctrl-a sharpens the E: E sharp")
  keys("<C-x><A-k>")
  eq(view:note() and select(3, view:note()).alter, 0, "spelled F natural")
  eq(notes_of(clip), "F4@0+1 G4@3+1", "flatten back, then up a step of the key")
  keys("}")
  eq(notes_of(clip), "F5@0+1 G4@3+1", "up an octave")
  keys("<A-l>")
  eq(notes_of(clip), "F5@0+2 G4@3+1", "lengthened by the chosen quarter: a half note")
  keys("g.")
  eq(notes_of(clip), "F5@0+3 G4@3+1", "dotted")
  keys("x")
  eq(notes_of(clip), "G4@3+1", "deleted")
  keys("u")
  eq(notes_of(clip), "F5@0+3 G4@3+1", "and back with undo")
end)

test("notation: a note played loosely keeps its timing when it is edited", function()
  local view, clip = song({ { pitch = 64, start = 0.02, length = 0.95, velocity = 77 } })
  view:set(37, 0)
  keys("<A-k>")
  local n = clip:notes()[1]
  eq(n.start, 0.02, "moving it up a step keeps when it was played")
  keys("<A-l>")
  n = clip:notes()[1]
  eq(n.start, 0.02, "lengthened, it still starts as played")
  eq(math.abs(n.length - 1.95) < 1e-9, true, "and played as much longer as it is written longer")
  eq(n.velocity, 77, "as loud as it was")
  eq(model_text_has(view, "h F4"), true, "written a half note")
end)

local function played(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do out[#out + 1] = string.format("%s@%.3f+%.3f/%d", paw.music.name(n.pitch), n.start, n.length, n.velocity) end
  return table.concat(out, " ")
end

test("score editing: a chord moved, lengthened or deleted moves its played notes", function()
  local strum = {
    { pitch = 52, start = 1.01, length = 0.9, velocity = 90 }, { pitch = 56, start = 1.04, length = 0.85, velocity = 80 },
    { pitch = 59, start = 1.07, length = 0.8, velocity = 70 }, { pitch = 72, start = 5.0, length = 1, velocity = 64 },
  }
  local view, clip = song(strum, 8)
  paw.cmd("notation.clef", { "treble" })
  view.cache = nil
  eq(view:layout().score.events[1].start, 1, "the strum is written on beat two")
  view:set(37, 1)
  keys("L")
  eq(played(clip), "E3@2.010+0.900/90 G#3@2.040+0.850/80 B3@2.070+0.800/70 C5@5.000+1.000/64",
    "a beat later, strummed and as loud as before")
  eq(view.beat, 2, "the cursor goes with it")
  keys("<A-l>")
  eq(played(clip):find("E3@2.010+1.900/90 G#3@2.040+1.850/80 B3@2.070+1.800/70", 1, true) ~= nil, true,
    "a half note: each played a quarter longer, as much shorter than written as it was")
  keys("X")
  eq(played(clip), "C5@5.000+1.000/64", "the chord deleted, all of it")
  keys("u")
  eq(#clip:notes(), 4, "and back")
end)

test("score editing: a note put in goes exactly on the grid, as loud as the dynamic there", function()
  local view, clip = song({ { pitch = 60, start = 0.03, length = 0.9, velocity = 50 }, { pitch = 62, start = 1.02, length = 0.9, velocity = 54 } })
  view:set(37, 2)
  keys("<CR>")
  local n = clip:notes()[3]
  eq(n.start, 2, "on beat three exactly")
  eq(n.velocity, paw.opt.velocity, "as loud as the piano roll enters notes, where no dynamic is written")
  view:set(35, 0)
  keys("i")
  keys("e")
  keys("<Esc>")
  eq(played(clip):sub(1, 18), string.format("E4@0.000+1.000/%d", paw.opt.velocity):sub(1, 18), "entering over a loosely played C replaces it")
end)

test("score editing: quantize to the notation, and write again from the playing", function()
  local view, clip = song({ { pitch = 60, start = 0.03, length = 0.4, velocity = 80 }, { pitch = 62, start = 0.52, length = 0.45, velocity = 80 },
    { pitch = 64, start = 0.98, length = 1.9, velocity = 80 } })
  api.undo_checkpoint()
  paw.cmd("notation.quantize")
  api.undo_checkpoint()
  eq(notes_of(clip), "C4@0+0.5 D4@0.5+0.5 E4@1+2", "each note where it is written and as long")
  keys("u")
  eq(clip:notes()[1].start, 0.03, "undone")
  view:set(35, 0)
  keys("=in")
  eq(clip:notes()[1].start, 0, "= on the note under the cursor")
  eq(clip:notes()[2].start, 0.52, "and on that one only")
end)

test("score editing: voices, triplets, and writing again from the playing", function()
  local view, clip = song({ N(64, 0, 2), N(67, 0, 0.5), N(69, 0.5, 0.5), N(71, 1, 0.5), N(72, 1.5, 0.5), N(74, 2, 2) })
  local _, model = load()
  eq(model.text(view:layout(), 1, 2), "h E4 hr", "the held E is a second voice")
  view:set(37, 0)
  keys("gV")
  eq(model.text(view:layout(), 1, 2), "h E4 hr", "voice 1 has other notes there: the E stays")
  view:set(43, 2)
  keys("gV")
  eq(model.text(view:layout(), 1, 1), "e G4 e A4 e B4 e C5 hr", "the D leaves voice 1")
  eq(model.text(view:layout(), 1, 2), "h E4 h D5", "for voice 2, where it was silent")
  -- An edit elsewhere: the voices stay as written.
  view:set(39, 0)
  keys("<C-a>")
  eq(model.text(view:layout(), 1, 2), "h E4 h D5", "still in voice 2")
  view:set(41, 1)
  keys("<localleader>33<CR>")
  eq(model.text(view:layout(), 1, 1):find("3{", 1, true) ~= nil, true, "beat two in triplets")
  keys("<localleader>3off<CR>")
  eq(model.text(view:layout(), 1, 1):find("3{", 1, true), nil, "and not")
  paw.cmd("notation.retranscribe")
  api.undo_checkpoint()
  eq(model.text(view:layout(), 1, 2), "h E4 hr", "written again from the playing: the held E is voice 2, the D voice 1")
end)

test("score editing: grace notes, strums, beams and spelling by key", function()
  local view, clip = song({ N(72, 0, 0.5), N(74, 0.5, 0.5), N(76, 1, 0.5), N(77, 1.5, 0.5), N(60, 2, 1), N(64, 2, 1), N(67, 2, 1) })
  local _, model = load()
  view:set(43, 0.5)
  keys("gb")
  eq(view:layout().measures[1].staves[1][1].beam, nil, "the beam broken before the D: the C stands alone")
  view:set(43, 0.5)
  keys("gG")
  eq(model.text((view:layout())):find("[D5]E5", 1, true) ~= nil, true, "the D a grace note of the E")
  view:set(35, 2)
  keys("gs")
  eq(model.text((view:layout())):find("<C4 E4 G4>^", 1, true) ~= nil, true, "an arpeggio sign on the chord")
  view:set(45, 1.5)
  keys("g~in")
  eq(model.text((view:layout())):find("E#5", 1, true) ~= nil, true, "F respelled as E sharp")
end)

test("notation: Enter adds a note of the chosen value at the cursor and takes it away", function()
  local view, clip = song()
  view:set(39, 2)
  keys("g4<CR>")
  eq(notes_of(clip), "G4@2+0.5", "an eighth at the cursor")
  keys("<CR>")
  eq(notes_of(clip), "", "and gone")
end)

test("notation: operators and visual mode work on notes as in the piano roll", function()
  local view, clip = song({ N(60, 0, 1), N(62, 1, 1), N(64, 2, 1), N(65, 3, 1) })
  view:set(35, 0)
  keys("dw")
  eq(notes_of(clip), "D4@1+1 E4@2+1 F4@3+1", "dw deletes up to the next note")
  view:set(36, 1)
  keys("vll<A-k>")
  eq(notes_of(clip), "E4@1+1 F4@2+1 G4@3+1", "a selection from beat two to the note under the cursor on beat four, both in, up a step of the key")
  view:set(38, 2)
  keys("v<C-a>")
  eq(notes_of(clip), "E4@1+1 F#4@2+1 G4@3+1", "Ctrl-a on a selection of the note under the cursor alone")
  view:set(39, 3)
  keys("yinP")
  eq(#clip:notes(), 3, "yank and paste over itself")
end)

test("notation: w, b and W move by what is written", function()
  local view = song({ N(60, 0, 1.5), N(62, 1.5, 0.5), N(64, 2, 2), N(65, 4, 4) }, 8)
  view:set(35, 0)
  keys("w")
  eq(view.beat, 1.5, "w: the next note")
  keys("w")
  eq(view.beat, 2, "and the next")
  keys("b")
  eq(view.beat, 1.5, "b: back")
  keys("W")
  eq(view.beat, 4, "W: the next bar")
end)

test("notation: :notation.key and :notation.clef keep the key with the project and the clef with the track", function()
  local view, clip, track = song({ N(72, 0, 1) })
  paw.cmd("notation.key", { "Eb", "major" })
  api.undo_checkpoint()
  eq(api.project_get().key, "Eb major", "the key is the project's")
  eq(view:layout().fifths, -3, "three flats")
  paw.cmd("notation.clef", { "bass" })
  api.undo_checkpoint()
  eq(track.meta.notation.clef, "bass", "the clef is the track's")
  eq(view:layout().staves[1], "bass", "and the notation follows")
  keys("u")
  eq(view:layout().staves[1], "treble", "undone like any edit")
end)

test("notation: the terminal draws the staff, clef, key, heads, stems and beams", function()
  local view = song({ N(72, 0, 0.5), N(74, 0.5, 0.5), N(76, 1, 1), N(65, 2, 2) })
  paw.cmd("notation.key", { "D", "major" })
  local text = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(text:find("│●┼╮", 1, true) ~= nil, true, "a treble clef, curled round its G line")
  eq(select(2, text:gsub("♯", "")) >= 2, true, "two sharps in the key signature")
  eq(select(2, text:gsub("██", "")) + select(2, text:gsub("▄▄", "")) >= 3, true, "filled heads for the eighths and the quarter")
  eq(text:find("╭┤", 1, true) ~= nil, true, "an open head for the half note, in its space, with its stem")
  eq(text:find("♮", 1, true) ~= nil, true, "F natural against the key")
  eq(text:find("━", 1, true) ~= nil, true, "a beam over the eighths")
  eq(text:find("tune", 1, true) ~= nil and text:find("D major", 1, true) ~= nil, true, "the title says the clip and the key")
end)

test("score: the clip keeps its settings, and the view reads the song's bars", function()
  local view, clip = song(clean("C4 0 0.5, D4 0.5 0.5"), 8)
  paw.cmd("notation.set", { "voices", "off" })
  api.undo_checkpoint()
  eq(clip.meta.notation.settings.voices, false, "kept in clip.meta.notation")
  eq(view.settings_of(clip:get()).voices, false, "and read back")
  paw.cmd("notation.raw")
  api.undo_checkpoint()
  eq(view:layout().score.swing, nil, "raw")
  eq(clip.meta.notation.settings.mode, "raw", "the raw view is a setting of the clip")
  keys("u")
  eq(clip.meta.notation.settings.mode, nil, "undone like any edit")
  local was = paw.time.signature_at
  paw.time.signature_at = function(beat) if beat < 4 then return 4, 4 end return 3, 4 end
  view.cache = nil
  local layout = view:layout()
  paw.time.signature_at = was
  eq(#layout.measures, 3, "a bar of 4/4 and two of 3/4 in eight beats")
  eq(layout.measures[2].meter.num, 3, "the second bar in 3/4")
  view.cache = nil
end)

test("marks: articulations are written and played", function()
  local view, clip = song({ N(72, 0, 1), N(74, 1, 1), N(76, 2, 1), N(77, 3, 1) })
  view:set(42, 0)
  keys("g'")
  eq(clip:notes()[1].length, 0.5, "staccato: played half its written length")
  local ev = view:layout().measures[1].staves[1][1]
  eq(ev.art.staccato, true, "the written note carries it")
  eq(model_text_has(view, "q C5"), true, "still written a quarter")
  keys("g'")
  eq(clip:notes()[1].length, 1, "taken away: as long as before the mark")
  view:set(43, 1)
  local before = clip:notes()[2].velocity
  keys("g>")
  eq(clip:notes()[2].velocity, before + 20, "an accent: louder")
  keys("g>")
  eq(clip:notes()[2].velocity, before, "and back")
  view:set(44, 2)
  keys("vlg_")
  eq(view:layout().measures[1].staves[1][3].art.tenuto, true, "on a selection")
end)

test("marks: dynamics set the loudness, hairpins ramp it, slurs join the notes", function()
  local notes = {}
  for i = 0, 7 do notes[#notes + 1] = { pitch = 72, start = i, length = 0.5, velocity = 60 + (i % 2) * 10 } end
  local view, clip = song(notes, 8)
  view:set(42, 0)
  paw.cmd("notation.dyn", { "f" })
  api.undo_checkpoint()
  local v = {}
  for i, n in ipairs(clip:notes()) do v[i] = n.velocity end
  eq(v[1] .. " " .. v[2], "96 96", "f: the notes from there as loud as f")
  eq(view.score_of(clip:get()).marks[1].value, "f", "the dynamic is written in the score")
  view:set(42, 0)
  paw.cmd("notation.dyn", { "p" })
  view:set(42, 4)
  paw.cmd("notation.dyn", { "f" })
  view:set(42, 0)
  keys("vlll")
  paw.cmd("notation.cresc")
  keys("<Esc>")
  for i, n in ipairs(clip:notes()) do v[i] = n.velocity end
  eq(v[1] < v[3] and v[3] < v[5] and v[2] < v[4], true, "a crescendo from p to f: louder beat by beat")
  eq(v[5], 96, "reaching the f")
  local m = view:layout().measures[1]
  eq(#m.marks >= 2, true, "the hairpin is on the measure, to be drawn")
  paw.cmd("notation.slur")
  local xml = require("notation.export").musicxml(view:layout(), {})
  eq(xml:find("<dynamics><f/></dynamics>", 1, true) ~= nil, true, "MusicXML carries the dynamic")
  eq(xml:find('<wedge type="crescendo"/>', 1, true) ~= nil, true, "and the hairpin")
end)

test("tablature: a guitar track gets strings and frets, and the guitar's clef", function()
  local view, clip, track = song(clean("E2+B2+E3+G#3+B3+E4 0 1, A2 1 1, C4 2 1, G2+B2+D3+G3+B3+G4 3 1"), 4)
  paw.cmd("notation.tab", { "guitar" })
  api.undo_checkpoint()
  eq(track.meta.notation.tab.tuning[1], 40, "standard tuning kept with the track, low E first")
  view.cache = nil
  local layout = view:layout()
  eq(layout.staves[1], "treble8", "written in the guitar's treble clef, an octave up")
  local frets = {}
  for _, ev in ipairs(layout.measures[1].staves[1]) do
    if ev.kind == "note" then
      local out = {}
      for _, n in ipairs(ev.notes) do out[#out + 1] = (n.string or "?") .. ":" .. (n.fret or "?") end
      frets[#frets + 1] = table.concat(out, " ")
    end
  end
  eq(frets[1], "6:0 5:2 4:2 3:1 2:0 1:0", "an open E chord as a guitarist plays it")
  eq(frets[2], "5:0", "the open A string")
  eq(frets[3], "2:1", "C on the B string, first fret, near where the hand is")
  eq(frets[4], "6:3 5:2 4:0 3:0 2:0 1:3", "an open G chord")
  local text = table.concat(api.ui_snapshot(120, 40), "\n")
  eq(text:find("E ─", 1, true) ~= nil or text:find("E─", 1, true) ~= nil, true, "the terminal draws the strings, named")
  paw.cmd("notation.tab", { "off" })
  view.cache = nil
  eq(view:layout().tab, nil, "and takes them away")
end)

test("several tracks: a staff each, the open clip's the one edited; lyrics under the notes", function()
  local view, clip, track = song({ { pitch = 72, start = 0, length = 1, velocity = 90, meta = { lyric = "la" } }, N(74, 1, 1) }, 4)
  local bass = paw.add_track({ name = "Bass" })
  local low = bass:add_clip({ start = 0, length = 4, notes = { N(40, 0, 2), N(43, 2, 2) } })
  paw.flush()
  local ev = view:layout().measures[1].staves[1][1]
  eq(ev.lyric, "la", "the note's lyric is written under it")
  local xml = require("notation.export").musicxml(view:layout(), {})
  eq(xml:find("<text>la</text>", 1, true) ~= nil, true, "and exported")
  keys("zS")
  local layout = view:frame().layout
  eq(#layout.staves, 2, "two staves: the clip's track and the bass")
  eq(layout.labels[1].full .. ", " .. layout.labels[2].full, "Bass, Lead", "each named, in the score's order")
  local _, model = load()
  eq(model.text(layout, 1), "h E2 h G2", "the bass's notes on its staff")
  eq(view:frame().base, 1, "the lead's staff, the second, is the active one")
  eq(view.clip_id, clip.id, "the open clip's staff is the active one")
  view:set(42, 0)
  keys("x")
  eq(#clip:notes(), 1, "x deletes the note under the cursor, in the active staff's clip")
  eq(#low:notes(), 2, "and nothing of the bass")
  keys("u")
  keys("zS")
  eq(view.parts, nil, "and back to the clip alone")
end)

-- The pointer in the terminal ----------------------------------------------------------------

local function shot() return api.ui_snapshot(120, 40) end

local function m(kind, x, y, button, mods)
  paw.ui.mouse({ kind = kind, x = x, y = y, button = button or "left", mods = mods or "" })
  api.undo_checkpoint()
end

--- The screen cell of a beat and staff step in the terminal view, after a snapshot.
local function cell(view, beat, step)
  local model = require("notation.model")
  local rect
  for _, r in ipairs(paw.ui.rects) do if r.name == "notation" then rect = r end end
  local g = view.geometry
  for _, sys in ipairs(g.systems) do
    for _, placed in ipairs(sys.measures) do
      local mm = placed.m
      if beat >= mm.start and beat < mm.start + mm.length then
        return rect.x + placed.x + math.floor(model.x_of(mm, beat) + 0.5),
          rect.y + sys.row_of(1, step - model.CLEF_BOTTOM[g.staves[1]])
      end
    end
  end
end

local function terminal_song(notes)
  local view, clip = song(notes, 4)
  paw.opt.mouse = true
  paw.mouse.forget()
  paw.ui.focus("notation")
  shot()
  return view, clip
end

test("notation terminal: a click chooses, a drag moves a note, a right click opens a menu", function()
  local view, clip = terminal_song({ N(67, 1, 0.5) })
  local x, y = cell(view, 2, 39)
  m("down", x, y) m("up", x, y)
  eq(notes_of(clip), "G4@1+0.5", "a click on the paper adds nothing")
  eq(view.beat .. " " .. view.step, "2 39", "it puts the cursor on that line and time")
  paw.mouse.forget()
  local hx, hy = cell(view, 1, 39)
  local tx, ty = cell(view, 2, 41)
  m("down", hx, hy)
  eq(view.beat, 1, "a click on a note puts the cursor on it")
  m("drag", hx + 1, hy - 1)
  m("drag", tx, ty)
  m("up", tx, ty)
  eq(notes_of(clip), "B4@2+0.5", "dragged two steps up and a beat later")
  shot()
  paw.mouse.forget()
  local rx, ry = cell(view, 2, 41)
  m("down", rx, ry, "right")
  eq(require("paw.menu").is_open(), true, "a right click opens a menu")
  eq(table.concat(shot(), "\n"):find("Delete the note", 1, true) ~= nil, true, "of what can be done to the note")
  keys("<CR>")
  eq(notes_of(clip), "", "its first entry deletes the note")
end)

test("notation terminal: Shift-click extends a selection, a drag on the paper selects a block", function()
  local view = terminal_song({ N(60, 0, 1), N(62, 1, 1), N(64, 2, 1), N(65, 3, 1) })
  local x, y = cell(view, 0, 35)
  m("down", x, y) m("up", x, y)
  paw.mouse.forget()
  local x2, y2 = cell(view, 2, 37)
  m("down", x2, y2, "left", "S") m("up", x2, y2, "left", "S")
  local sel = paw.keymap.selection()
  eq(sel and sel.c0, 0, "a selection from the cursor")
  eq(sel and sel.c1 >= 2, true, "to the note clicked with Shift")
  keys("<Esc>")
  shot()
  paw.mouse.forget()
  local ax, ay = cell(view, 1.5, 33)
  local bx, by = cell(view, 3.5, 40)
  m("down", ax, ay)
  m("drag", ax + 1, ay)
  m("drag", bx, by)
  m("up", bx, by)
  sel = paw.keymap.selection()
  eq(sel and sel.kind, "block", "a box drawn on the paper selects a block")
  keys("<Esc>")
end)

test("notation terminal: a double click enters notes; in insert mode a click enters one and the shadow note follows the pointer", function()
  local view, clip = terminal_song(nil)
  view.value = 0.5
  local x, y = cell(view, 1, 39)
  m("down", x, y) m("up", x, y)
  m("down", x, y) m("up", x, y)
  eq(paw.keymap.mode, "i", "a double click enters notes")
  eq(notes_of(clip), "", "and enters nothing itself")
  local hx, hy = cell(view, 2, 41)
  m("move", hx, hy, "")
  local screen = shot()
  eq(screen[hy + 1]:find("██", 1, true) ~= nil, true, "the note to enter is drawn where the pointer is")
  eq(view.cell_hover and view.cell_hover.step, 41, "the shadow note follows the pointer")
  paw.mouse.forget()
  m("down", x, y) m("up", x, y)
  eq(notes_of(clip), "G4@1+0.5", "a click enters an eighth G on beat two")
  keys("<Esc>")
end)

test("notation terminal: off a note the cursor is the note Enter would put there", function()
  local view = terminal_song(nil)
  view:set(39, 1)
  local x, y = cell(view, 1, 39)
  local screen = shot()
  local row = screen[y + 1]
  local col = 0
  for ch in row:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if col == x then eq(ch, "█", "a quarter's head at the cursor") break end
    col = col + 1
  end
  view.value = 2
  screen = shot()
  eq(screen[y + 1]:find("()", 1, true) ~= nil, true, "a half note's when halves are chosen")
end)

-- The staff in cells -----------------------------------------------------------------------------

--- The notation panel of a snapshot: its rows (from 0) of characters (from 1).
local function panel(w, h)
  local screen = api.ui_snapshot(w, h)
  local rect
  for _, r in ipairs(paw.ui.rects) do if r.name == "notation" then rect = r end end
  local rows = {}
  for y = rect.y, rect.y + rect.h - 1 do
    local chars, col = {}, 0
    for ch in (screen[y + 1] or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      if col >= rect.x and col < rect.x + rect.w then chars[#chars + 1] = ch end
      col = col + 1
    end
    rows[y - rect.y] = chars
  end
  return rows, rect
end

--- The first event of a measure's staff that `pred` holds for.
local function find_event(view, mi, pred)
  for _, ev in ipairs(view:layout().measures[mi].staves[1]) do
    if pred(ev) then return ev end
  end
end

test("notation terminal: staff lines run unbroken from the clef to the end, the barlines join them", function()
  local view = song({ N(67, 0, 1), N(69, 1, 1), N(71, 2, 1), N(72, 3, 1) }, 8)
  paw.ui.focus("notation")
  local rows = panel(120, 40)
  local sys = view.geometry.systems[1]
  eq(view.geometry.dense, true, "dense at the usual zoom")
  local first, last = sys.measures[1], sys.measures[#sys.measures]
  local x_end = last.x + last.m.width
  for pos = 0, 8, 2 do
    local r = rows[sys.row_of(1, pos)]
    for x = 0, x_end do
      eq(r[x + 1] ~= " ", true, "the line at step " .. pos .. " has no gap at column " .. x)
    end
    eq(rows[sys.row_of(1, pos) + 1][x_end + 1] ~= "─", true, "and each line has a row of its own")
  end
  local bx = first.x + first.m.width
  eq(rows[sys.row_of(1, 8)][bx + 1] .. rows[sys.row_of(1, 4)][bx + 1] .. rows[sys.row_of(1, 0)][bx + 1], "┬┼┴",
    "a barline joins the lines it crosses")
  eq(rows[sys.row_of(1, 8)][x_end + 1] .. rows[sys.row_of(1, 0)][x_end + 1], "┐┘", "the system's last barline closes them")
  eq(rows[sys.row_of(1, 8)][1] .. rows[sys.row_of(1, 0)][1], "┌└", "and its first opens them")
  eq(sys.row_of(1, 0) - sys.row_of(1, 8), 4, "five lines in five rows")
end)

test("notation terminal: heads show their value, a quarter has a stem, an eighth a flag, rests look like rests", function()
  -- q G4, quarter rest, e G4, eighth rest, q G4 | whole rest | h D5 (stem down), half rest
  local view = song({ N(67, 0, 1), N(67, 2, 0.5), N(67, 3, 1), N(74, 8, 2) }, 12)
  paw.ui.focus("notation")
  view:set(30, 11)
  local rows = panel(160, 45)
  local sys = view.geometry.systems[1]
  local function at(mi, beat) for _, p in ipairs(sys.measures) do if p.m.index == mi then return p.x + math.floor(require("notation.model").x_of(p.m, beat) + 0.5) end end end
  local function ch(x, pos) return rows[sys.row_of(1, pos)][x + 1] end
  -- The quarter G4: a filled head on the second line, its stem up from its right side.
  local x = at(1, 0)
  eq(ch(x, 2) .. ch(x + 1, 2), "██", "a quarter's head is filled, two cells wide")
  for y = sys.row_of(1, 8), sys.row_of(1, 2) - 1 do
    eq(rows[y][x + 2] == "│" or rows[y][x + 2] == "┼", true, "its stem runs up from the head (row " .. y .. ")")
  end
  -- The eighth: a flag at the stem's tip.
  local e = at(1, 2)
  eq(ch(e + 2, 8), "╲", "an eighth alone has a flag")
  -- Rests.
  local q = find_event(view, 1, function(ev) return ev.kind == "rest" and ev.base == 1 end)
  local qx = at(1, q.start)
  eq(ch(qx, 6) .. rows[sys.row_of(1, 6) + 1][qx + 1] .. rows[sys.row_of(1, 6) + 2][qx + 1], "╲╱╲", "a quarter rest zigzags down the staff")
  local r8 = find_event(view, 1, function(ev) return ev.kind == "rest" and ev.base == 0.5 end)
  eq(ch(at(1, r8.start), 4), "7", "an eighth rest is a flag on a stroke")
  local whole = table.concat(rows[sys.row_of(1, 6)], "", at(2, 4) + 1, at(2, 4) + sys.measures[2].m.width)
  eq(whole:find("▄▄", 1, true) ~= nil, true, "an empty bar's whole rest hangs from the fourth line")
  local h2 = at(3, 8)
  eq(ch(h2, 6) .. ch(h2 + 1, 6), "()", "a half note's head is open")
  eq(ch(h2, 4) == "│" or ch(h2, 4) == "┼", true, "its stem goes down from its left side, above the middle line")
  local hr = find_event(view, 3, function(ev) return ev.kind == "rest" and ev.base == 2 end)
  eq(ch(at(3, hr.start), 4), "▀", "a half rest sits on the middle line")
end)

test("notation terminal: a head in a space lies across two rows; accidentals before heads, ties as arcs", function()
  -- F#4 in the first space; G4 from beat four tied over the barline.
  local view = song({ N(66, 0, 1), N(67, 3, 2) }, 8)
  paw.ui.focus("notation")
  view:set(30, 6)
  local rows = panel(160, 45)
  local sys = view.geometry.systems[1]
  local R = sys.rows[1]
  local model = require("notation.model")
  local p1, p2 = sys.measures[1], sys.measures[2]
  local fx = p1.x + math.floor(model.x_of(p1.m, 0) + 0.5)
  eq(rows[R.above(1)][fx + 1] .. rows[R.above(1)][fx + 2], "▄▄", "F4 in the first space: the lower half of the row above")
  eq(rows[R.below(1)][fx + 1] .. rows[R.below(1)][fx + 2], "▀▀", "and the upper half of the row below")
  eq(rows[R.above(1)][fx], "♯", "its sharp before it")
  local gx = p1.x + math.floor(model.x_of(p1.m, 3) + 0.5)
  local nx = p2.x + math.floor(model.x_of(p2.m, 4) + 0.5)
  local arc = table.concat(rows[R.below(1)], "", gx + 3, nx)
  eq(arc:gsub("─", ""), "╰╯", "a tie under the G, over the barline to the next G: " .. arc)
end)

test("notation terminal: a grand staff fits in eighteen rows; zoomed in, every line and space has a row", function()
  -- The view with the arrange view alone, whatever other tests left open.
  paw.cmd("view.only")
  local view = song({ N(36, 0, 1), N(43, 1, 1), N(76, 0, 1), N(79, 1, 1) }, 4)
  paw.ui.focus("notation")
  local rows, rect = panel(120, 50)
  eq(rect.h >= 20, true, "a panel of twenty rows or more: " .. rect.h)
  local g = view.geometry
  eq(#g.staves, 2, "both staves are drawn")
  local sys = g.systems[1]
  eq(sys.row_of(2, 0) - sys.row_of(1, 8) + 1 <= 14, true, "from the treble's top line to the bass's bottom one in fourteen rows or fewer")
  eq(g.staff_rows * 2 <= 18, true, "the whole system, with room for ledger lines and stems, in eighteen")
  eq(rows[sys.row_of(1, 8)][1], "⎧", "a brace before the system")
  -- The keys zoom the window's page too.
  T.after(function() view.zoom, view.space = 1, nil end)
  keys("zi")
  rows = panel(120, 50)
  g = view.geometry
  eq(g.dense, false, "zoomed in, the staff is open")
  sys = g.systems[1]
  eq(sys.row_of(1, 0) - sys.row_of(1, 8), 8, "nine rows from the top line to the bottom one")
  eq(rows[sys.row_of(1, 1)][sys.measures[1].x + 1] ~= "─", true, "a space has a row between the lines")
  keys("zo")
  eq(view.dense(), true, "and back")
end)

test("notation terminal: the staff is drawn only in characters the common monospace fonts have", function()
  load()
  -- Checked against DejaVu Sans Mono, JetBrains Mono, Fira Code and Noto
  -- Sans Mono; the accidentals are the one exception (cells.lua says why).
  local common = "─━│┆┌┐└┘├┤┬┳┴┻┼║╭╮╯╰╱╲╵╷╸╺▀▄█●·–•⎧⎨⎩⎪" .. "♯♭♮"
  local seen = {}
  local function walk(v)
    if type(v) == "table" then for _, x in pairs(v) do walk(x) end return end
    if type(v) ~= "string" then return end
    for ch in v:gmatch("[\194-\244][\128-\191]*") do
      if not common:find(ch, 1, true) then seen[#seen + 1] = ch end
    end
  end
  local cells = require("notation.cells")
  walk(cells.unicode)
  for _, clef in ipairs({ "treble", "bass" }) do walk(cells.clef(clef, true)) end
  eq(table.concat(seen, " "), "", "characters outside the common set")
  seen = {}
  local function ascii(v)
    if type(v) == "table" then for _, x in pairs(v) do ascii(x) end return end
    if type(v) == "string" and v:find("[\128-\255]") then seen[#seen + 1] = v end
  end
  ascii(cells.ascii)
  eq(table.concat(seen, " "), "", "the ASCII set is ASCII")
end)

test("notation terminal: with paw.opt.ascii the staff is drawn in plain ASCII", function()
  local view = song({ N(67, 0, 0.5), N(69, 0.5, 0.5), N(71, 1, 1), N(66, 2, 2) }, 8)
  paw.ui.focus("notation")
  T.after(function() paw.opt.ascii = false end)
  paw.opt.ascii = true
  local rows = panel(120, 40)
  paw.opt.ascii = false
  local text = {}
  for y = 1, #rows do text[#text + 1] = table.concat(rows[y]) end
  text = table.concat(text, "\n")
  eq(text:find("[\128-\255]"), nil, "no character outside ASCII:\n" .. text)
  eq(view.geometry.dense, false, "open: ASCII has no half blocks")
  eq(text:find("@@", 1, true) ~= nil and text:find("()", 1, true) ~= nil, true, "filled and open heads")
  eq(text:find("&", 1, true) ~= nil, true, "a treble clef")
end)

-- The window -----------------------------------------------------------------------------------

local function paint(view)
  return paw.canvas.paint("notation", 1100, 560)
end

local function pointer(kind, x, y, extra)
  paw.canvas.pointer("notation", paw.util.merge({ kind = kind, x = x, y = y, button = "left" }, extra or {}))
  api.undo_checkpoint()
end

--- Where a beat and staff step are in the window, after a paint.
local function spot(view, beat, step)
  local model = require("notation.model")
  local engrave = require("notation.engrave")
  local gui = view.gui
  local eng = gui.engraved
  local layout = view:layout()
  for _, sys in ipairs(eng.systems) do
    for _, placed in ipairs(sys.measures) do
      local m = placed.m
      if beat >= m.start and beat < m.start + m.length then
        local pos = step - model.CLEF_BOTTOM[layout.staves[1]]
        return placed.x + model.x_of(placed.p, beat) - (view.galley and gui.hscroll or 0),
          engrave.y_of(eng.style, sys, 1, pos) + gui.area.top - gui.scroll
      end
    end
  end
end

test("notation window: it engraves notes, stems, beams and the clef with the music font", function()
  local view = song({ N(72, 0, 0.5), N(74, 0.5, 0.5), N(76, 1, 1), N(67, 2, 2) })
  local drawing = paw.canvas.paint("notation", 1100, 560, { glyphs = true })
  local glyphs, layers, cuts = {}, {}, 0
  for _, op in ipairs(drawing.ops) do
    if op[1] == "g" and layers[#layers] == "ink" then glyphs[op[5]] = (glyphs[op[5]] or 0) + 1 end
    if op[1] == "layer" then layers[#layers + 1] = op[2] end
    if op[1] == "cut" then cuts = cuts + 1 end
  end
  eq(glyphs[0xE0A4], 3, "three black note heads (Leland's noteheadBlack)")
  eq(glyphs[0xE0A3], 1, "a half note's head")
  eq(glyphs[0xE050], 1, "a treble clef")
  eq(table.concat(layers, " "), "ink selection ghost diagnostic caret playhead", "the page's ink, then what moves over it, as layers")
  eq(cuts >= 1, true, "and where a frontend may cut it at a barline")
  eq(#view.gui.heads, 4, "four note heads, each remembered for the pointer")
  local paths = 0
  for _, op in ipairs(paint(view).ops) do
    if op[1] == "g" then error("a frontend that does not draw glyphs is given none") end
    if op[1] == "p" then paths = paths + 1 end
  end
  eq(paths > 10, true, "the window is given each glyph as a path from the font's outline")
end)

test("notation window: staff lines, stems and barlines are on whole pixels, systems whole cell rows", function()
  local view = song({ N(72, 0, 0.5), N(74, 0.5, 0.5), N(76, 1, 1), N(67, 2, 2), N(60, 4, 4), N(64, 8, 1) }, 16)
  local drawing = paw.canvas.paint("notation", 1053, 600, { glyphs = true, surface = true, cell = { w = 13, h = 27 }, colors = { fg = "#cdd6f4", bg = "#1e1e2e" } })
  local whole = true
  for _, op in ipairs(drawing.ops) do
    if op[1] == "r" then
      for i = 2, 5 do whole = whole and op[i] == math.floor(op[i]) end
    end
    eq(op[1] ~= "t" or op[4] ~= "midi", true, "no toolbar on a terminal's surface")
  end
  eq(whole, true, "every rectangle on whole pixels")
  eq(drawing.ops[1][1], "layer", "no background: the terminal's own shows")
  local eng = view.gui.engraved
  eq(eng.style.sp, 9, "a staff space of a third of a 27 px cell")
  for _, sys in ipairs(eng.systems) do
    eq(sys.height % 27, 0, "each system whole rows of cells high")
    for _, placed in ipairs(sys.measures) do eq(placed.x % 13, 0, "each measure starting on a whole column") end
  end
  eq(eng.systems[1].height <= 6 * 27, true, "a single staff in no more than six rows")
end)

test("notation window: in normal mode a click chooses, a drag moves a note, a right click opens a menu", function()
  local view, clip = song({ N(67, 1, 0.5) }, 4)
  paw.ui.focus("notation")
  paint(view)
  local x, y = spot(view, 2, 39)
  pointer("down", x, y)
  pointer("up", x, y)
  eq(notes_of(clip), "G4@1+0.5", "a click on the paper adds nothing")
  eq(view.beat, 2, "it puts the cursor there")
  paint(view)
  local hx, hy = spot(view, 1, 39)
  local tx, ty = spot(view, 2, 41)
  pointer("down", hx, hy)
  eq(view.beat, 1, "a click on a note puts the cursor on it")
  pointer("move", (hx + tx) / 2, (hy + ty) / 2)
  pointer("move", tx, ty)
  pointer("up", tx, ty)
  eq(notes_of(clip), "B4@2+0.5", "dragged two steps up and a beat later")
  paint(view)
  local rx, ry = spot(view, 2, 41)
  pointer("down", rx, ry, { button = "right" })
  eq(require("paw.menu").is_open(), true, "a right click opens a menu")
  keys("<CR>")
  eq(notes_of(clip), "", "its first entry deletes the note")
end)

test("notation window: Shift extends a selection, a drag on the paper selects a box", function()
  local view = song({ N(60, 0, 1), N(62, 1, 1), N(64, 2, 1), N(65, 3, 1) }, 4)
  paw.ui.focus("notation")
  paint(view)
  local x, y = spot(view, 0, 35)
  pointer("down", x, y)
  pointer("up", x, y)
  local x2, y2 = spot(view, 2, 37)
  pointer("down", x2, y2, { shift = true })
  local sel = paw.keymap.selection()
  eq(sel and sel.c0, 0, "a selection from the cursor")
  eq(sel and sel.c1 >= 2, true, "to the note clicked with Shift")
  keys("<Esc>")
  paint(view)
  local ax, ay = spot(view, 1, 33)
  local bx, by = spot(view, 3, 40)
  pointer("down", ax, ay)
  pointer("move", bx, by)
  pointer("up", bx, by)
  sel = paw.keymap.selection()
  eq(sel and sel.kind, "block", "a box drawn on the paper selects a block")
  keys("<Esc>")
end)

test("notation window: a double click enters notes there; in insert mode a click enters a note and the note to enter follows the pointer", function()
  local view, clip = song(nil, 4)
  paw.ui.focus("notation")
  paint(view)
  view.value = 0.5
  local x, y = spot(view, 1, 39)
  pointer("double", x, y)
  eq(paw.keymap.mode, "i", "a double click enters notes")
  pointer("down", x, y)
  pointer("up", x, y)
  eq(notes_of(clip), "", "the double click's own second press enters nothing")
  local hx, hy = spot(view, 2, 41)
  paw.canvas.pointer("notation", { kind = "hover", x = hx, y = hy })
  eq(view.gui.hover and view.gui.hover.step, 41, "the note to enter follows the pointer")
  local drawing = paw.canvas.paint("notation", 1100, 560, { glyphs = true })
  local in_caret, heads = false, 0
  for _, op in ipairs(drawing.ops) do
    if op[1] == "layer" then in_caret = op[2] == "caret" end
    if in_caret and op[1] == "g" and op[5] == 0xE0A4 then heads = heads + 1 end
  end
  eq(heads, 1, "drawn half transparent in the caret's layer")
  pointer("down", x, y)
  pointer("up", x, y)
  eq(notes_of(clip), "G4@1+0.5", "a click enters an eighth G on beat two")
  keys("<Esc>")
end)

test("notation window: the toolbar chooses the value, the accidental and rests", function()
  local view, clip = song({ N(64, 0, 4) }, 4)
  paint(view)
  local function press(label)
    for _, b in ipairs(view.gui.buttons) do
      if b.label == label then return pointer("down", b.x + 4, b.y + 4) end
    end
    error("no button " .. label)
  end
  press("half")
  eq(view.value, 2, "half notes")
  press("sharp")
  keys("i")
  paint(view)
  local x, y = spot(view, 2, 38)
  pointer("down", x, y)
  pointer("up", x, y)
  eq(notes_of(clip), "E4@0+2 F#4@2+2", "an F sharp half note; the E is written a half note, and played two beats shorter")
  press("rest")
  paint(view)
  x, y = spot(view, 2, 38)
  pointer("down", x, y)
  eq(notes_of(clip), "E4@0+2", "a rest clears it")
  view.gui.rest, view.gui.accidental = false, nil
end)

test("notation window: the toolbar's buttons are one height, labels centred, and wrap instead of overlapping", function()
  local view = song({ N(64, 0, 4) }, 4)
  for _, width in ipairs({ 1100, 520, 380 }) do
    local drawing = paw.canvas.paint("notation", width, 560)
    local rows, labelled = {}, 0
    for i, a in ipairs(view.gui.buttons) do
      eq(a.h, 28, "every button is as high as the others")
      eq(a.x >= 0 and a.x + a.w <= width, true, "inside the window at " .. width)
      rows[a.y] = true
      for j = i + 1, #view.gui.buttons do
        local b = view.gui.buttons[j]
        eq(a.x + a.w <= b.x or b.x + b.w <= a.x or a.y + a.h <= b.y or b.y + b.h <= a.y, true,
          a.label .. " and " .. b.label .. " do not overlap at " .. width)
      end
      if a.label == "rest" or a.label == "mf" then
        for _, op in ipairs(drawing.ops) do
          if op[1] == "t" and op[4] == a.label and op[8] == "center" then
            labelled = labelled + 1
            eq(op[2], a.x + a.w / 2, a.label .. " is centred on its button")
          end
        end
      end
    end
    eq(labelled, 2, "rest and mf are drawn centred at " .. width)
    local count = 0
    for _ in pairs(rows) do count = count + 1 end
    eq(view.gui.bar_h, count * 36 + 8, "the toolbar is as high as its rows at " .. width)
    eq(count > 1, width < 800, "the buttons wrap onto more rows only when the window is narrow")
  end
end)

--- The ops of a layer of a drawing.
local function layer_ops(drawing, name)
  local out, current = {}, nil
  for _, op in ipairs(drawing.ops) do
    if op[1] == "layer" then current = op[2] elseif current == name then out[#out + 1] = op end
  end
  return out
end

local function surface_paint()
  return paw.canvas.paint("notation", 1053, 800, { glyphs = true, surface = true, cell = { w = 13, h = 27 } })
end

test("notation page: the selection, suggestions, diagnostics and the playhead are layers over the ink", function()
  local view, clip = song({ N(60, 0, 1), N(62, 1, 1), N(64, 2, 1), N(65, 3, 1) }, 8)
  paw.ui.focus("notation")
  view:set(35, 0)
  keys("vl")
  local d = surface_paint()
  local sel = layer_ops(d, "selection")
  eq(sel[1] and sel[1][1], "r", "a faint band over the selection")
  eq(#sel >= 2, true, "and its notes again in the accent")
  keys("<Esc>")
  paw.complete.show({ { label = "next", notes = { { pitch = 67, start = 4, length = 1 } } } }, { clip = clip.id, keys = false })
  local ghosts = 0
  for _, op in ipairs(layer_ops(surface_paint(), "ghost")) do
    if op[1] == "g" then ghosts = ghosts + 1 end
  end
  eq(ghosts, 1, "a suggested note laid out where it would be written")
  paw.complete.dismiss()
  paw.diagnostic.set("test", clip.id, { { notes = { 2 }, severity = "warning", message = "a leap" } })
  local diag = layer_ops(surface_paint(), "diagnostic")
  local wave, tinted = false, false
  for _, op in ipairs(diag) do
    if op[1] == "p" then wave = true end
    if op[1] == "g" then tinted = true end
  end
  eq(wave and tinted, true, "a wavy line under the staff and the note tinted")
  view:set(37, 1)
  eq(view:status_text(), "a leap", "its message on the cursor's note")
  view:set(35, 0)
  keys("]d")
  eq(view.beat .. " " .. view.step, "1 36", "]d goes to it in the notation view")
  local here = paw.ui.location("notation")
  eq(here and here.uri:match("/note/") ~= nil, true, "the view says which note is under its cursor")
  paw.diagnostic.reset("test", clip.id)
  api.transport_seek(2)
  local play = layer_ops(surface_paint(), "playhead")
  eq(play[1] and play[1][4], 2, "a 2 px playhead")
end)

test("notation in a window: the playhead is a mark the live values move, and the scene stays while it stays in its system", function()
  local view = song({ N(60, 0, 1), N(62, 1, 1), N(64, 2, 1), N(65, 3, 1) }, 8)
  paw.ui.focus("notation")
  api.transport_seek(1.5)
  local marks = {}
  local d = paw.canvas.paint("notation", 1053, 800, { glyphs = true, cell = { w = 13, h = 27 }, marks = marks })
  local without = paw.canvas.paint("notation", 1053, 800, { glyphs = true, cell = { w = 13, h = 27 } })
  eq(#layer_ops(without, "playhead") - #layer_ops(d, "playhead"), 1, "not in the page")
  local mark = marks[1]
  eq(mark and mark.role .. " " .. mark.props.bind, "playhead position", "a mark, bound to the position")
  -- Where the window puts it at beat 1.5 is where the page draws it.
  local x
  for _, s in ipairs(mark.props.segments) do
    if 1.5 >= s[1] and 1.5 < s[2] then x = s[3] + (s[4] - s[3]) * (1.5 - s[1]) / (s[2] - s[1]) end
  end
  local drawn = layer_ops(without, "playhead")[1]
  T.near(x - 1, drawn[2], 1, "at the x of the page's playhead")
  -- Its key stays while the playhead stays in its system.
  api.transport_play()
  local key = view:scene_key()
  api.transport_seek(2.5)
  eq(view:scene_key(), key, "the same system: the same scene")
  api.transport_stop()
end)

test("notation page: a cursor move draws the page from what was engraved; an edit engraves only the measures it changed", function()
  local view, clip = song({ N(60, 0, 1), N(62, 4, 1), N(64, 8, 1), N(65, 12, 1) }, 16)
  paw.ui.focus("notation")
  surface_paint()
  local cache = view.gui.measures
  local made = cache.count
  view:move(1, 0)
  surface_paint()
  eq(cache.count, made, "moving the cursor engraves nothing")
  clip:set_note(2, { pitch = 65 })
  surface_paint()
  eq(cache.count, made + 1, "an edit in one bar engraves that bar again")
  local bench = require("notation.bench")
  local r = bench.run(16, { glyphs = true, surface = true, cell = { w = 13, h = 27 } }, 5)
  -- Loose bounds, for a busy machine: the targets are 8 and 30 ms.
  eq(r.cursor < 80, true, "a cursor move paints quickly (" .. string.format("%.1f", r.cursor) .. " ms)")
  eq(r.edit < 300, true, "an edit paints quickly (" .. string.format("%.1f", r.edit) .. " ms)")
end)

test("notation page: the galley is one long system that keeps the cursor in view", function()
  local notes = {}
  for i = 0, 63 do notes[#notes + 1] = N(60 + i % 12, i, 1) end
  local view = song(notes, 64)
  paw.ui.focus("notation")
  keys("zg")
  eq(view.galley, true, "zg: one long system")
  surface_paint()
  eq(#view.gui.engraved.systems, 1, "every measure in one system")
  view:set(nil, 60)
  surface_paint()
  local _, x = view.gui.at_beat(view.gui.engraved, 60)
  local shown = x - view.gui.hscroll
  eq(shown > 0 and shown < 1053, true, "scrolled sideways to the cursor")
  keys("zg")
  eq(view.galley, false, "and back to wrapped systems")
end)

test("notation insert: an interval above, a tie, triplets and the last chord again", function()
  local view, clip = song(nil, 4)
  keys("i")
  keys("C<A-3><A-3>")
  eq(notes_of(clip), "C4@0+1 E4@0+1 G4@0+1", "Alt-3 twice: a third above, and a third above that, a chord")
  keys("<Space>")
  eq(view.beat, 1, "Space steps on")
  keys("R")
  eq(notes_of(clip), "C4@0+1 E4@0+1 G4@0+1 C4@1+1 E4@1+1 G4@1+1", "R: the chord again")
  keys("e~")
  eq(notes_of(clip):match("E4@2%+2") ~= nil, true, "~ holds the note just entered on by the value: one note, tied")
  eq(view.beat, 4, "and steps on")
  keys("<Esc>")
  local view2, clip2 = song(nil, 4)
  keys("i4tcde<Esc>")
  local _ = view2
  eq(notes_of(clip2), "C4@0+0.333333 D4@0.333333+0.333333 E4@0.666667+0.333333", "t: eighth triplets")
end)

-- The pointer's place in time ----------------------------------------------------------------

test("notation pointer: a click lands on the chosen value within the beat", function()
  local _, model = load()
  local four, six = model.meter(4, 4), model.meter(6, 8)
  eq(model.snap(four, 1.2, 0.5), 1, "an eighth: to the eighth before")
  eq(model.snap(four, 1.3, 0.5), 1.5, "or after")
  eq(model.snap(four, 1.4, 1 / 3), 4 / 3, "a triplet eighth: to a third of the beat")
  eq(model.snap(four, 2.6, 2), 3, "a half: to a beat, not only to the bar's halves")
  eq(model.snap(four, 3.95, 1), 3, "never past the last place in the bar")
  eq(model.snap(four, 3.95, 0.25), 3.75, "nor for a sixteenth")
  eq(model.snap(six, 0.7, 0.5), 0.5, "6/8: eighths in the dotted quarter's beat")
  eq(model.snap(six, 1.3, 1), 1.5, "a quarter in 6/8 counts from each dotted quarter")
end)

test("notation pointer: in the terminal a click and an insert-mode click snap to the value, so typing after stays on the beat", function()
  local notes = {}
  for i = 0, 7 do notes[#notes + 1] = N(60, i * 0.25, 0.25) end
  local view, clip = terminal_song(notes)
  local x, y = cell(view, 2.75, 39)
  m("down", x, y) m("up", x, y)
  eq(view.beat, 3, "a quarter chosen: a click off the beat puts the cursor on the beat")
  keys("ig")
  eq(notes_of(clip):match("G4@3%+1") ~= nil, true, "a G typed there is a quarter on beat four, not tied eighths")
  keys("<Esc>")
  shot()
  paw.mouse.forget()
  view.value = 0.5
  keys("i")
  local x2, y2 = cell(view, 2.4, 37)
  m("down", x2, y2) m("up", x2, y2)
  eq(notes_of(clip):match("E4@2%.5%+0%.5") ~= nil, true, "in insert mode a click enters an eighth on an eighth")
  keys("<Esc>")
end)

test("notation pointer: in the window a click snaps to the value, Alt-click to the grid", function()
  local view, clip = song(nil, 4)
  paw.ui.focus("notation")
  view.value = 0.5
  paint(view)
  local x, y = spot(view, 1.2, 39)
  pointer("down", x, y)
  pointer("up", x, y)
  eq(view.beat, 1, "an eighth chosen: the cursor on the eighth before")
  x, y = spot(view, 1.3, 39)
  pointer("down", x, y)
  pointer("up", x, y)
  eq(view.beat, 1.5, "or after")
  pointer("down", x, y, { alt = true })
  pointer("up", x, y, { alt = true })
  eq(view.beat, 1.25, "Alt-click: on the sixteenths' grid")
  keys("i")
  x, y = spot(view, 2.2, 39)
  pointer("down", x, y)
  pointer("up", x, y)
  eq(notes_of(clip), "G4@2+0.5", "in insert mode a click enters an eighth on beat three")
  view.triplets = true
  x, y = spot(view, 0.4, 39)
  pointer("down", x, y)
  pointer("up", x, y)
  eq(notes_of(clip):match("G4@0%.333333%+0%.333333") ~= nil, true, "in triplets, on a third of the beat")
  view.triplets = false
  keys("<Esc>")
end)

-- Engraving detail (Gould, Behind Bars) --------------------------------------------------------

--- A song painted in the window: the view, the engraving, and each
--- measure's ink with its note heads (from the measure's left edge and the
--- system's top).
local function engraved(notes, length, width)
  local view = song(notes, length)
  paw.ui.focus("notation")
  paw.canvas.paint("notation", width or 1100, 560)
  local eng = view.gui.engraved
  local engrave = require("notation.engrave")
  local measures = {}
  for _, sys in ipairs(eng.systems) do
    for _, placed in ipairs(sys.measures) do
      measures[#measures + 1] = { ink = engrave.measure(view.gui.measures, eng.style, view:layout(), sys, placed), sys = sys, placed = placed }
    end
  end
  return view, eng, measures
end

--- A glyph op's box, from the font's bounding box: x0, y0, x1, y1, and
--- the glyph's name.
local glyph_names
local function glyph_box(st, op)
  local font = require("notation.smufl").font()
  if not glyph_names then
    glyph_names = {}
    for name, cp in pairs(api.smufl(font.name).glyphs) do glyph_names[cp] = name end
  end
  local name = glyph_names[op[5]]
  local bb = name and font.glyphs[name].bbox
  if not bb then return end
  local k = st.sp * op[4] / (4 * st.sp)
  return op[2] + bb[1] * k, op[3] - bb[4] * k, op[2] + bb[3] * k, op[3] - bb[2] * k, name
end

local function overlap(a, b)
  -- Boxes that only touch do not overlap.
  return a[1] < b[3] - 0.5 and b[1] < a[3] - 0.5 and a[2] < b[4] - 0.5 and b[2] < a[4] - 0.5
end

test("notation page: accidentals, courtesy ones too, never touch a stem or a head", function()
  -- Sixteenths up and down the staff with sharps, then a bar that reminds
  -- of the naturals in parentheses, and a chord with a second.
  local p = { 60, 61, 62, 63, 64, 65, 66, 67, 72, 73, 74, 75, 76, 77, 78, 79, 72, 60, 74, 61, 62, 73, 72, 75 }
  local notes = {}
  for i, pitch in ipairs(p) do notes[i] = N(pitch, (i - 1) * 0.25, 0.25) end
  for _, pitch in ipairs({ 65, 67, 68, 72 }) do notes[#notes + 1] = N(pitch, 7, 1) end
  local _, eng, measures = engraved(notes, 8)
  local st = eng.style
  local signs, courtesy = 0, 0
  for _, mi in ipairs(measures) do
    local obstacles, accs = {}, {}
    for _, op in ipairs(mi.ink.ops) do
      if op[1] == "r" and op[4] == st.stem and op[5] > st.sp then
        obstacles[#obstacles + 1] = { op[2], op[3], op[2] + op[4], op[3] + op[5] }
      elseif op[1] == "g" then
        local x0, y0, x1, y1, name = glyph_box(st, op)
        if name and name:match("^notehead") then obstacles[#obstacles + 1] = { x0, y0, x1, y1 } end
        if name and name:match("^accidental") then
          accs[#accs + 1] = { x0, y0, x1, y1, name = name }
          if name:match("Parens") then courtesy = courtesy + 1 end
        end
      end
    end
    for _, a in ipairs(accs) do
      signs = signs + 1
      for _, o in ipairs(obstacles) do
        if overlap(a, o) then
          error(string.format("%s at %.0f,%.0f touches what is at %.0f,%.0f to %.0f,%.0f", a.name, a[1], a[2], o[1], o[2], o[3], o[4]))
        end
      end
    end
  end
  eq(signs > 12, true, "many accidentals checked")
  eq(courtesy >= 2, true, "courtesy ones among them, in parentheses")
end)

test("notation page: a beamed tuplet has its number on the beam's side; an unbeamed one a bracket from its first note to its last", function()
  local t = 1 / 3
  local _, eng, measures = engraved({
    N(77, 0, t), N(79, t, t), N(81, 2 * t, t),   -- eighths high up: stems and beam below
    N(60, 1, t), N(62, 1 + t, t), N(64, 1 + 2 * t, t),   -- low: stems and beam above
    N(67, 2, 2 * t), N(69, 2 + 2 * t, 2 * t), N(71, 2 + 4 * t, 2 * t),   -- quarters: no beam
  }, 4)
  local st = eng.style
  local mi = measures[1].ink
  local numbers, brackets = {}, {}
  for _, op in ipairs(mi.ops) do
    if op[1] == "g" then
      local _, y0, _, y1, name = glyph_box(st, op)
      if name == "tuplet3" then numbers[#numbers + 1] = { x = op[2], y0 = y0, y1 = y1 } end
    elseif op[1] == "r" and op[6] == st.faint then
      brackets[#brackets + 1] = op
    end
  end
  eq(#numbers, 3, "three numbers")
  table.sort(numbers, function(a, b) return a.x < b.x end)
  local heads = mi.heads
  table.sort(heads, function(a, b) return a.start < b.start end)
  local function ys(from, to)
    local lo, hi = math.huge, -math.huge
    for i = from, to do lo, hi = math.min(lo, heads[i].y), math.max(hi, heads[i].y) end
    return lo, hi
  end
  local _, low1 = ys(1, 3)
  eq(numbers[1].y0 > low1 + 3 * st.sp, true, "stems down: the number under the beam, past it")
  local high2 = ys(4, 6)
  eq(numbers[2].y1 < high2 - 3 * st.sp, true, "stems up: the number over the beam")
  local x0, x1 = math.huge, -math.huge
  for _, r in ipairs(brackets) do x0, x1 = math.min(x0, r[2]), math.max(x1, r[2] + r[4]) end
  eq(#brackets, 4, "one bracket: two hooks and a line in two halves around its number")
  eq(x0 <= heads[7].gx + 0.5 and x1 >= heads[9].gx + 2 * (heads[9].x - heads[9].gx) - 1, true,
    "the bracket from the first head's left edge to the last head's right edge")
  eq(numbers[3].x > x0 and numbers[3].x < x1, true, "with its number inside it")
end)

--- The tie paths of some ink: each its ends and how high its outer curve's
--- control points stand over them, as parts of a staff space, and how far in
--- they are from the ends, as a part of its length.
local function ties(ops, sp)
  local out = {}
  for _, op in ipairs(ops) do
    local c = op[1] == "P" and op[2]
    if c and c[4] == "C" then
      local x0, y0, ax, ay, x1 = c[2], c[3], c[5], c[6], c[9]
      out[#out + 1] = { x0 = x0, x1 = x1, y = y0, rise = math.abs(ay - y0) * 0.75 / sp, inset = (ax - x0) / (x1 - x0) }
    end
  end
  return out
end

test("notation page: ties are flat and close to the heads, in a bar, over a barline and over a system break", function()
  local notes = {}
  -- Halves tied over every barline, for eight bars: they break onto systems.
  for k = 0, 6 do notes[#notes + 1] = N(72, 2 + 4 * k, 4) end
  -- A half on beat two: two quarters tied inside the bar.
  notes[#notes + 1] = N(76, 33, 2)
  local _, eng, measures = engraved(notes, 36, 700)
  local engrave = require("notation.engrave")
  local st = eng.style
  eq(#eng.systems >= 2, true, "more than one system")
  local all = {}
  for _, mi in ipairs(measures) do
    for _, t in ipairs(ties(mi.ink.ops, st.sp)) do all[#all + 1] = t end
  end
  local inside = #all
  for _, sys in ipairs(eng.systems) do
    for _, t in ipairs(ties(sys.spans, st.sp)) do all[#all + 1] = t end
  end
  eq(inside >= 1, true, "ties inside bars")
  eq(#all - inside >= 7, true, "ties over barlines and system breaks")
  for _, t in ipairs(all) do
    eq(t.rise <= engrave.TIE_HEIGHT + st.tie_mid / st.sp / 2 + 0.01, true, string.format("a tie rises no more than %.1f of a space (%.2f)", engrave.TIE_HEIGHT, t.rise))
    eq(t.inset <= 0.15, true, "flat: its curve turns near its ends")
  end
  -- Each tie in a bar starts at a head of its own, no more than a space from its middle.
  for _, mi in ipairs(measures) do
    for _, t in ipairs(ties(mi.ink.ops, st.sp)) do
      local near = false
      for _, h in ipairs(mi.ink.heads) do
        if math.abs(h.y - t.y) <= st.sp and t.x0 >= h.gx - st.sp and t.x0 <= h.gx + 2 * st.sp then near = true end
      end
      eq(near, true, "a tie starts at its head")
    end
  end
end)

test("notation page: secondary beams stand the font's beam spacing from the primary", function()
  local _, eng, measures = engraved({ N(72, 0, 0.25), N(72, 0.25, 0.25), N(72, 0.5, 0.5), N(60, 1, 0.25), N(60, 1.25, 0.25), N(60, 1.5, 0.5) }, 4)
  local st = eng.style
  local d = require("notation.smufl").font().defaults
  eq(st.beam_gap, math.max(1, math.floor(d.beamSpacing * st.sp + 0.5)), "the gap is the font's beamSpacing, in whole pixels")
  -- Each beam is drawn note to note; flat ones share their top.
  local tops, seen = {}, {}
  for _, op in ipairs(measures[1].ink.ops) do
    local c = op[1] == "P" and op[2]
    if c and c[4] == "L" and #c == 13 and not seen[c[3]] then
      seen[c[3]] = true
      tops[#tops + 1] = c[3]
    end
  end
  table.sort(tops)
  eq(#tops, 4, "two groups, each a primary and a secondary beam, at four heights")
  for i = 1, 3, 2 do
    eq(tops[i], math.floor(tops[i]), "a flat beam on whole pixels")
    eq(tops[i + 1] - (tops[i] + st.beam), st.beam_gap, "the two beams the gap apart")
  end
end)

test("notation page: the last system never holds a bar alone when the one before can spare one", function()
  local notes = {}
  for i = 0, 55 do notes[#notes + 1] = N(60 + (i * 5) % 14, i * 0.5, 0.5) end
  local view = song(notes, 28)
  local engrave = require("notation.engrave")
  paw.ui.focus("notation")
  paw.canvas.paint("notation", 1100, 560)
  local layout, st = view:layout(), view.gui.engraved.style
  local seen = 0
  for width = 300, 4000, 25 do
    local systems = engrave.systems(layout, st, { width = width }).systems
    local last, before = systems[#systems], systems[#systems - 1]
    if before and #last.measures == 1 then
      eq(#before.measures <= 2, true, "a bar alone at " .. width .. " px only when the system before has none to spare")
    end
    if before and #last.measures == 2 and #before.measures >= 2 then seen = seen + 1 end
  end
  eq(seen > 0, true, "and widths where a bar was taken over")
end)

test("notation page: with two voices a rest keeps clear of the other voice's notes", function()
  local v2 = { notation = { voice = 2 } }
  local view = song({
    { pitch = 64, start = 0, length = 1 }, { pitch = 69, start = 1, length = 1, meta = v2 },   -- a low E4 over the lower voice's rest
    { pitch = 71, start = 2, length = 1, meta = v2 }, { pitch = 77, start = 3, length = 1 },    -- a B4 under the upper voice's rest
  }, 4)
  local rests = {}
  for _, ev in ipairs(view:layout().measures[1].staves[1]) do
    if ev.kind == "rest" then rests[ev.voice .. "@" .. ev.start] = ev end
  end
  local low, high = rests["2@0"], rests["1@2"]
  eq(low ~= nil and high ~= nil, true, "a rest in each voice")
  -- A rest reaches about three positions from its middle (4 + shift); a head one.
  eq(4 + low.shift + 3 <= 0 - 1, true, "the lower voice's rest under the E4 (the bottom line)")
  eq(4 + high.shift - 3 >= 4 + 1, true, "the upper voice's rest over the B4")
end)

-- Export -------------------------------------------------------------------------------------

test("notation export: LilyPond source writes what is shown", function()
  local _, model = load()
  local export = require("notation.export")
  local layout = model.layout({ N(74, 0, 1.5), N(73, 1.5, 0.5), N(71, 2, 3), N(48, 6, 1) }, { length = 8, fifths = 2 })
  local ly = export.lilypond(layout, { title = "tune" })
  eq(ly:find("\\key d \\major", 1) ~= nil, true, "the key")
  eq(ly:find("\\new PianoStaff", 1, true) ~= nil, true, "a grand staff for notes on both sides of middle C")
  eq(ly:find("d''4. cis''8 b'2~ |", 1, true) ~= nil, true, "values, octaves, sharps and the tie, bar by bar")
  eq(ly:find("R1*4/4", 1, true) ~= nil, true, "a whole bar's rest")
  eq(ly:find("c4 r4 |", 1, true) ~= nil, true, "the bass staff's C")
end)

test("notation export: MusicXML has the key, ties, beams and accidentals", function()
  local _, model = load()
  local export = require("notation.export")
  local layout = model.layout({ N(72, 0, 0.5), N(74, 0.5, 0.25), N(76, 0.75, 0.25), N(65, 1, 2), N(67, 3, 2) }, { length = 8, fifths = 2 })
  local xml = export.musicxml(layout, { title = "tune", part = "Lead" })
  eq(xml:find("<fifths>2</fifths>", 1, true) ~= nil, true, "two sharps")
  eq(xml:find("<accidental>natural</accidental>", 1, true) ~= nil, true, "F natural in D major")
  eq(xml:find('<beam number="1">begin</beam>', 1, true) ~= nil and xml:find('<beam number="2">end</beam>', 1, true) ~= nil, true, "beams with a second level")
  eq(xml:find('<tie type="start"/>', 1, true) ~= nil and xml:find('<tied type="stop"/>', 1, true) ~= nil, true, "a tie across the barline")
  eq(select(2, xml:gsub("<measure ", "")), 2, "two measures")
end)

test("notation export: :notation.export writes a file for the clip or the whole track", function()
  local _, clip, track = song({ N(72, 0, 1), N(74, 1, 1) })
  track:add_clip({ start = 8, length = 4, name = "more", notes = { N(76, 0, 4) } })
  local path = T.scratch .. "/notation-test.ly"
  paw.cmd("notation.export", { path, "track" })
  local f = io.open(path, "rb")
  local text = f and f:read("*a") or ""
  if f then f:close() end
  eq(text:find("c''4 d''4", 1, true) ~= nil, true, "the first clip")
  eq(text:find("e''1", 1, true) ~= nil, true, "and the second, in its bar")
end)

-- Modal editing to trust ----------------------------------------------------------------------

--- The clip's notes as a sorted list, for comparing whatever order they are kept in.
local function sorted_notes(clip)
  local out = {}
  for _, n in ipairs(clip:notes()) do out[#out + 1] = string.format("%s@%g+%g", paw.music.name(n.pitch), n.start, n.length) end
  table.sort(out)
  return table.concat(out, " ")
end

test("notation entry: a bass note entered under a melody leaves the melody alone", function()
  local view, clip = song({ N(67, 0, 1), N(69, 1, 1), N(71, 2, 1), N(74, 3, 1) })
  eq(#view:layout().staves, 1, "one staff before the bass")
  view:set(25, 0)
  keys("i7g<Esc>")
  eq(sorted_notes(clip), "A4@1+1 B4@2+1 D5@3+1 G2@0+4 G4@0+1", "the whole-note G2 is added and the melody of bar 1 kept")
  eq(#view:layout().staves, 2, "now a grand staff")
  view:set(25, 0)
  keys("i5d<Esc>")
  eq(sorted_notes(clip), "A4@1+1 B4@2+1 D2@0+1 D5@3+1 G4@0+1", "on the bass staff, entry still replaces what is there")
  view:set(25, 1)
  keys("ir<Esc>")
  eq(sorted_notes(clip), "A4@1+1 B4@2+1 D2@0+1 D5@3+1 G4@0+1", "a rest on the bass staff takes nothing from the treble")
end)

test("notation entry: a second voice under a first is left alone, and entered in on its own", function()
  local held = { voice = 2 }
  local view, clip = song({ N(76, 0, 1), N(77, 1, 1), N(79, 2, 1), N(77, 3, 1),
    { pitch = 72, start = 0, length = 2, meta = { notation = held } }, { pitch = 72, start = 2, length = 2, meta = { notation = held } } })
  view:set(44, 0)   -- E5, voice 1
  keys("i4ga<Esc>")
  eq(sorted_notes(clip), "A5@0.5+0.5 C5@0+2 C5@2+2 F5@1+1 F5@3+1 G5@0+0.5 G5@2+1",
    "eighths in voice 1 replace its E; the held C of voice 2 stays")
  view:set(42, 2)   -- C5 on beat three, voice 2
  keys("i6b<Esc>")
  eq(sorted_notes(clip), "A5@0.5+0.5 B4@2+2 C5@0+2 F5@1+1 F5@3+1 G5@0+0.5 G5@2+1",
    "entering on the voice-2 note replaces it alone, and the melody over it stays")
  eq(require("notation.model").text(view:layout(), 1, 2), "h C5 h B4", "the new note is written in voice 2")
end)

test("notation: Esc stays in the view; ,n, ZZ and :q leave it", function()
  local view = song({ N(60, 0, 1) })
  keys("<Esc>")
  eq(paw.ui.focused, "notation", "Esc in normal mode keeps the keyboard in the view")
  keys("2<Esc>")
  eq(paw.ui.focused, "notation", "and drops a count")
  keys("d<Esc>")
  eq(paw.keymap.mode, "n", "and a pending operator")
  eq(paw.ui.focused, "notation", "staying")
  keys("<localleader>n")
  eq(paw.ui.focused, "arrange", "\\n goes back to the arrange view")
  view:edit(view:clip())
  keys("ZZ")
  eq(paw.ui.focused, "arrange", "ZZ closes the notation")
  view:edit(view:clip())
  keys(":q<CR>")
  eq(paw.ui.focused, "arrange", ":q closes the notation, and the program runs on")
end)

test("notation: a visual selection takes in the note under the cursor", function()
  local view, clip = song({ N(60, 0, 1), N(62, 1, 1), N(64, 2, 1), N(65, 3, 1) })
  view:set(35, 0)
  keys("v3wg(")
  local evs = view:layout().measures[1].staves[1]
  eq(evs[1].slur_to ~= nil, true, "the slur starts on the first note")
  eq(evs[1].slur_to == evs[4], true, "and reaches over the fourth, under the cursor")
  view:set(35, 0)
  keys("v3wd")
  eq(notes_of(clip), "", "v3wd deletes the four notes")
end)

test("notation: : from a selection runs a command over it, and commands take bars", function()
  local view, clip = song({ N(60, 0, 1), N(62, 1, 1), N(64, 2, 1), N(65, 3, 1), N(67, 4, 4), N(69, 8, 4) }, 12)
  view:set(35, 0)
  keys("vw:")
  eq(require("paw.views.cmdline").state().before, "'<,'>", "the prompt starts with the selection's range")
  keys("notation.cresc<CR>")
  local mark = view:layout().measures[1].marks[1]
  eq(mark.kind, "cresc", "a crescendo")
  eq(mark.at == 0 and mark.to == 2, true, "over the two selected notes, the second under the cursor included")
  paw.commands.exec("2,3notation.transpose 2")
  eq(notes_of(clip), "C4@0+1 D4@1+1 E4@2+1 F4@3+1 A4@4+4 B4@8+4", "bars 2 and 3 a tone up")
  paw.commands.exec("1notation.transpose -1 steps")
  eq(notes_of(clip), "B3@0+1 C4@1+1 D4@2+1 E4@3+1 A4@4+4 B4@8+4", "bar 1 a step of the key down")
  paw.commands.exec("'<,'>notation.transpose 12")
  eq(notes_of(clip), "B4@0+1 C5@1+1 D4@2+1 E4@3+1 A4@4+4 B4@8+4", "'<,'> typed later names the last selection again")
end)

