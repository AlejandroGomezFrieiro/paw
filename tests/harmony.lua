-- Tests of `paw.harmony`: chords and keys read from real and constructed
-- music, the theory around them, providers, and the chord row of the piano
-- roll. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local H = paw.harmony
local music = paw.music

--- The chords read over the song as "at:name" words.
local function reading(from, to, how)
  local out = {}
  for _, c in ipairs(H.chords(from, to)) do
    out[#out + 1] = string.format("%g:%s", c.at, how == "roman" and c.roman or c.name)
  end
  return table.concat(out, " ")
end

local function keys()
  local out = {}
  for _, k in ipairs(H.keys()) do
    out[#out + 1] = string.format("%g:%s", k.at, k.name)
  end
  return table.concat(out, " ")
end

--- A track playing chords: each `{ "C4 E4 G4", beats }` one after another,
--- or `{ "C4 E4 G4", beats, at = beat }`.
local function chords(name, list, opts)
  opts = opts or {}
  local track = paw.add_track({ name = name })
  local notes, at = {}, opts.start or 0
  for _, entry in ipairs(list) do
    at = entry.at or at
    for word in entry[1]:gmatch("%S+") do
      notes[#notes + 1] = { pitch = music.pitch(word), start = at, length = entry[2] * (opts.gate or 1), velocity = 90 }
    end
    at = at + entry[2]
  end
  track:add_clip({ start = 0, length = math.max(4, math.ceil(at / 4) * 4), notes = notes })
  return track
end

--- A melody track: `{ "E5", beats }` one after another.
local function line(name, list, start)
  local track = paw.add_track({ name = name })
  local notes, at = {}, start or 0
  for _, entry in ipairs(list) do
    if entry[1] ~= "r" then
      notes[#notes + 1] = { pitch = music.pitch(entry[1]), start = at, length = entry[2], velocity = 90 }
    end
    at = at + entry[2]
  end
  track:add_clip({ start = 0, length = math.max(4, math.ceil(at / 4) * 4), notes = notes })
  return track
end

test("harmony: block chords in C major are named, numbered and in C major", function()
  fresh()
  chords("Piano", {
    { "C3 C4 E4 G4", 4 },
    { "A2 A3 C4 E4", 4 },
    { "D3 D4 F4 A4", 4 },
    { "G2 G3 B3 D4 F4", 4 },
    { "C3 C4 E4 G4", 4 },
  })
  paw.flush()
  eq(reading(), "0:C 4:Am 8:Dm 12:G7 16:C", "the names")
  eq(reading(nil, nil, "roman"), "0:I 4:vi 8:ii 12:V7 16:I", "the numerals")
  eq(keys(), "0:C major", "the key")
  eq(H.at(13).name, "G7", "the chord at a beat")
  eq(H.next(12).name, "C", "the next chord starts after the beat")
  eq(H.next(11.5).name, "G7", "even from inside the chord before")
  eq(H.prev(13).name, "Dm", "the previous chord")
  eq(H.next(16), nil, "nothing after the last")
  eq(H.at(13).length, 4, "a chord lasts until the next")
  eq(H.at(16).length, 4, "the last until its notes end")
  eq(reading(5, 9), "4:Am 8:Dm", "a stretch: the chords sounding in it")
end)

test("harmony: inversions are read from the bass and written as slash chords", function()
  fresh()
  chords("Piano", {
    { "E3 G3 C4", 4 },
    { "F3 A3 C4", 4 },
    { "B2 F3 G3 D4", 4 },
    { "C3 E3 G3 C4", 4 },
    { "F2 A3 D4", 4 },
    { "G2 B3 D4 F4", 4 },
    { "E3 G#3 B3 D4", 4 },
    { "A2 E3 A3 C4", 4 },
  })
  paw.flush()
  eq(reading(), "0:C/E 4:F 8:G7/B 12:C 16:Dm/F 20:G7 24:E7 28:Am", "inversions and their bass")
end)

test("harmony: sevenths, half-diminished and diminished chords", function()
  fresh()
  chords("Keys", {
    { "C3 E3 G3 B3", 4 },
    { "A2 C3 E3 G3", 4 },
    { "D3 F3 A3 C4", 4 },
    { "G2 B2 D3 F3", 4 },
    { "B2 D3 F3 A3", 4 },
    { "E3 G#3 B3 D4", 4 },
    { "G#2 B2 D3 F3", 4 },
    { "A2 C3 E3 A3", 4 },
    { "F3 A3 C4 E4", 4 },
    { "C3 E3 G3 A3", 4 },
    { "G2 C3 D3 F3", 4 },
    { "C3 G3 C4", 4 },
  })
  paw.flush()
  eq(
    reading(),
    "0:Cmaj7 4:Am7 8:Dm7 12:G7 16:Bm7b5 20:E7 24:G#dim7 28:Am 32:Fmaj7 36:C6 40:G7sus4 44:C5",
    "every quality"
  )
end)

test("harmony: a chord holds across the melody's passing notes", function()
  fresh()
  chords("Piano", { { "C3 E3 G3", 4 }, { "F3 A3 C4", 4 }, { "G2 B2 D3", 4 }, { "C3 E3 G3", 4 } })
  -- Stepwise eighths and sixteenths, half of them outside the chord.
  line("Flute", {
    { "C5", 0.5 },
    { "D5", 0.5 },
    { "E5", 0.5 },
    { "F5", 0.5 },
    { "G5", 1 },
    { "E5", 0.5 },
    { "D5", 0.5 },
    { "C5", 0.5 },
    { "D5", 0.25 },
    { "E5", 0.25 },
    { "F5", 1 },
    { "A5", 0.5 },
    { "G5", 0.5 },
    { "F5", 1 },
    { "D5", 0.5 },
    { "E5", 0.5 },
    { "F5", 1 },
    { "B4", 0.5 },
    { "C5", 0.5 },
    { "D5", 1 },
    { "E5", 0.5 },
    { "D5", 0.25 },
    { "C5", 0.25 },
    { "C5", 3 },
  })
  paw.flush()
  eq(reading(), "0:C 4:F 8:G 12:C", "the chords, not the passing notes")
end)

test("harmony: a melody alone names no chords, an arpeggio in eighths does", function()
  fresh()
  line("Flute", { { "C5", 1 }, { "D5", 1 }, { "E5", 1 }, { "G5", 1 } })
  paw.flush()
  eq(reading(), "", "do re mi sol is no chord")
  eq(keys(), "0:C major", "but is in C major")
  fresh()
  line("Harp", {
    { "C4", 0.5 },
    { "E4", 0.5 },
    { "G4", 0.5 },
    { "E4", 0.5 },
    { "C4", 0.5 },
    { "E4", 0.5 },
    { "G4", 0.5 },
    { "E4", 0.5 },
    { "A3", 0.5 },
    { "C4", 0.5 },
    { "F4", 0.5 },
    { "C4", 0.5 },
    { "A3", 0.5 },
    { "C4", 0.5 },
    { "F4", 0.5 },
    { "C4", 0.5 },
  })
  paw.flush()
  eq(reading(), "0:C 4:F/A", "the chords the notes spell out one at a time")
end)

test("harmony: a modulation from C major to G major is found", function()
  fresh()
  chords("Strings", {
    { "C3 E3 G3", 4 },
    { "F3 A3 C4", 4 },
    { "G2 B2 D3 F3", 4 },
    { "C3 E3 G3", 4 },
    { "A2 C3 E3", 4 },
    { "D3 F3 A3", 4 },
    { "G2 B2 D3", 4 },
    { "C3 E3 G3", 4 },
    -- The pivot (Am, ii in G), then D7 and G with their F sharps.
    { "A2 C3 E3", 4 },
    { "D3 F#3 A3 C4", 4 },
    { "G2 B2 D3", 4 },
    { "E3 G3 B3", 4 },
    { "C3 E3 G3", 4 },
    { "A2 C3 E3 G3", 4 },
    { "D3 F#3 A3 C4", 4 },
    { "G2 B2 D3", 4 },
  })
  paw.flush()
  -- The pivot belongs to both keys and is heard in the old one: the new key
  -- begins with its dominant, where its F sharp first sounds.
  eq(keys(), "0:C major 36:G major", "the keys")
  eq(reading(32, 64, "roman"), "32:vi 36:V7 40:I 44:vi 48:IV 52:ii7 56:V7 60:I", "numerals in the new key")
  eq(reading(0, 32, "roman"), "0:I 4:IV 8:V7 12:I 16:vi 20:ii 24:V 28:I", "and in the old")
  eq(H.key(10).name, "C major", "the key at a beat")
  eq(H.key(50).name, "G major", "after the modulation")
end)

test("harmony: the demo song", function()
  fresh()
  dofile("examples/demo-song.lua")
  paw.flush()
  -- The drums are left out; the bass, the keys and the lead are read
  -- together: Am F C E twice, the second time with the keys' phrase in two
  -- voices and the melody over it.
  eq(reading(), "0:Am 4:F 8:C 12:E 16:Am 20:F 24:C 28:E", "the chords")
  eq(keys(), "0:A minor", "the key")
  eq(reading(nil, nil, "roman"), "0:i 4:bVI 8:bIII 12:V 16:i 20:bVI 24:bIII 28:V", "the numerals")
end)

test("harmony: drum tracks, muted tracks and muted clips are left out", function()
  fresh()
  chords("Piano", { { "C3 E3 G3", 4 } })
  local kit = chords("Kit", { { "C#3 D#3 F#3", 4 } })
  paw.flush()
  eq(reading(), "0:C", "a drum track by its name")
  kit.name = "Perc 2"
  local pad = chords("Pad", { { "D3 F#3 A3", 4 } })
  paw.flush()
  eq(reading() ~= "0:C", true, "a pitched track is heard")
  pad.mute = true
  paw.flush()
  eq(reading(), "0:C", "a muted track is not")
  pad.mute = false
  pad:clips()[1].muted = true
  paw.flush()
  eq(reading(), "0:C", "nor a muted clip")
  local meta = pad.meta or {}
  meta.drums = { map = "gm", rows = { { note = 36, name = "Kick" } } }
  pad:clips()[1].muted = false
  pad.meta = meta
  paw.flush()
  eq(reading(), "0:C", "nor a track with a drum map")
end)

test("harmony: the reading is cached, follows edits and undo, and says when it changes", function()
  fresh()
  local t = chords("Piano", { { "C3 E3 G3", 4 } })
  paw.flush()
  api.undo_checkpoint()
  local changes = 0
  local id = paw.on("harmony.changed", function() changes = changes + 1 end)
  eq(reading(), "0:C", "read")
  local first = H.chords()
  eq(H.chords()[1], first[1], "the same reading while nothing changes")
  t:clips()[1]:add_note({ pitch = music.pitch("Bb3"), start = 0, length = 4 })
  paw.flush()
  api.undo_checkpoint()
  eq(reading(), "0:C7", "an edit is read at once")
  for _ = 1, 200 do
    if changes > 0 then break end
    paw.wait(25)
  end
  eq(changes >= 1, true, "and heard of")
  paw.undo()
  paw.flush()
  eq(reading(), "0:C", "and undone")
  paw.off(id)
end)

test(
  "harmony: an edit reads again where it changed the notes, and a view draws the reading before it until then",
  function()
    fresh()
    local piano = chords("Piano", { { "C3 E3 G3", 4 }, { "F3 A3 C4", 4 } })
    local pad = chords("Pad", { { "A2 C3 E3", 4, at = 16 } })
    paw.flush()
    eq(reading(), "0:C 4:F 16:Am", "read")
    local clip = pad:clips()[1]
    api.clip_set_notes(clip.id, {
      { pitch = music.pitch("D3"), start = 16, length = 4, velocity = 90 },
      { pitch = music.pitch("F3"), start = 16, length = 4, velocity = 90 },
      { pitch = music.pitch("A3"), start = 16, length = 4, velocity = 90 },
    })
    paw.flush()
    eq(reading(), "0:C 4:F 16:Dm", "the edited clip is read again, the other kept")
    piano:clips()[1]:add_note({ pitch = music.pitch("Bb3"), start = 0, length = 4 })
    paw.flush()
    local function shown()
      local out = {}
      for _, c in ipairs(H.chords(nil, nil, true)) do
        out[#out + 1] = string.format("%g:%s", c.at, c.name)
      end
      return table.concat(out, " ")
    end
    eq(shown(), "0:C 4:F 16:Dm", "a view gets the reading before the edit at once")
    for _ = 1, 200 do
      if H.fresh() then break end
      paw.wait(10)
    end
    eq(shown(), "0:C7 4:F 16:Dm", "and the new one once it is read")
  end
)

test("harmony: the project's key wins over the one read, and is kept in the project", function()
  fresh()
  chords("Piano", { { "A2 C3 E3", 4 }, { "D3 F3 A3", 4 }, { "E3 G#3 B3", 4 }, { "A2 C3 E3", 4 } })
  paw.flush()
  eq(H.key(0).name, "A minor", "read")
  eq(reading(nil, nil, "roman"), "0:i 4:iv 8:V 12:i", "numerals in A minor")
  H.set_key("C major")
  paw.flush()
  eq(H.key(0).name, "C major", "set")
  eq(api.project_get().key, "C major", "kept as the project's key")
  eq(reading(nil, nil, "roman"), "0:vi 4:ii 8:III 12:vi", "numerals in the key set")
  eq(keys(), "0:C major", "the only key")
  H.set_key(nil)
  paw.flush()
  eq(H.project_key(), nil, "cleared")
  eq(H.key(0).name, "A minor", "read again")
end)

test(
  "harmony: a key marker is the key from its beat, over the project's key, and moving it does not read the notes again",
  function()
    fresh()
    local song = require("paw.harmony.song")
    chords("Piano", { { "C3 E3 G3", 4 }, { "F3 A3 C4", 4 }, { "Bb2 D3 F3", 4 }, { "F3 A3 C4", 4 } })
    H.set_key("C major")
    local m = paw.markers.add(paw.time.bar_start(3), "key D minor")
    paw.flush()
    eq(H.key(paw.time.bar_start(2) + 1).name, "C major", "before the marker: the project's key")
    eq(H.key(paw.time.bar_start(4)).name, "D minor", "from the marker")
    eq(keys(), "0:C major 8:D minor", "two spans")
    local stamp = song.stamp()
    paw.markers.set(m.id, { beat = paw.time.bar_start(4) })
    paw.flush()
    eq(keys(), "0:C major 12:D minor", "the marker moved")
    eq(H.key(paw.time.bar_start(3)).name, "C major", "key() follows it")
    eq(song.stamp(), stamp, "the notes were not read again")
  end
)

test("harmony: with no project key a marker at the start spells the chords in its key", function()
  fresh()
  chords("Piano", { { "F#3 A#3 C#4", 4 }, { "B2 D#3 F#3", 4 } })
  paw.markers.add(0, "key G major")
  paw.flush()
  eq(H.key(0).name, "G major", "the marked key")
  eq(reading(), "0:F# 4:B", "F#, not Gb")
end)

test("harmony: a region with a key is in that key over its time", function()
  fresh()
  chords("Piano", { { "C3 E3 G3", 16 } })
  H.set_key("C major")
  paw.markers.add(8, "Verse", { length = 8, key = "E minor" })
  paw.flush()
  eq(H.key(9).name, "E minor", "inside the region")
  eq(H.key(4).name, "C major", "before it")
  eq(H.key(17).name, "C major", "after it")
  paw.markers.add(10, "key A minor")
  paw.flush()
  eq(H.key(11).name, "A minor", "a marker inside it changes the key")
  eq(H.marked_key(0), nil, "nothing is written at the start")
end)

test("harmony: theory: keys, spelling, degrees, chord symbols", function()
  local d = H.parse_key("D minor")
  eq(d.root, 2, "root")
  eq(d.tonic, 2, "tonic")
  eq(d.mode, "minor", "mode")
  eq(H.key_name("bb"), "Bb major", "spelled with flats")
  eq(H.key_name("F# Harmonic Minor"), "F# harmonic_minor", "forgiving names")
  eq(H.key_name("D# minor"), "Eb minor", "as it is usually written")
  eq(H.pc_name(10, "F major"), "Bb", "a flat key's black key")
  eq(H.pc_name(6, "E major"), "F#", "a sharp key's")
  eq(H.pc_name(10), "Bb", "without a key")
  eq(H.in_key("C major", 66), false, "F# is not in C")
  eq(H.snap("C major", 61), 62, "C# goes up to D")
  eq(H.step("C major", 60, 2), 64, "two steps up from C")
  eq(H.step("A minor", 72, -2), 69, "two down from C in A minor")
  eq(H.degree_pitch("C major", 35), 60, "C4 is the 36th degree")
  local c = H.parse_chord("F#m7b5/C")
  eq(c.root .. " " .. c.quality .. " " .. c.bass, "6 m7b5 0", "a symbol read")
  eq(table.concat(H.tones(7, "7"), " "), "7 11 2 5", "the tones of G7")
  eq(H.chord_name({ root = 10, quality = "maj7", bass = 2 }, "F major"), "Bbmaj7/D", "a name in a key")
  eq(H.chord_roman({ root = 11, quality = "m7b5" }, "C major"), "viiø7", "a numeral")
  eq(H.chord_roman({ root = 10, quality = "maj" }, "C major"), "bVII", "borrowed")
  eq(H.parse_chord("H7"), nil, "not a chord")
end)

test("harmony: voicings fit the range and lead smoothly", function()
  local V = H.voice
  local g7 = H.tones(7, "7")
  local p = V.voice(g7, { low = 48, high = 84, prev = { 60, 64, 67 } })
  eq(#p, 4, "four voices")
  for _, x in ipairs(p) do
    eq(x >= 48 and x <= 84, true, "within the range")
  end
  eq(V.distance({ 60, 64, 67 }, p) <= 5, true, "close to the C major before: " .. table.concat(p, " "))
  local into = V.voice(g7, { low = 48, high = 84, next = { 60, 64, 67, 72 } })
  eq(V.distance(into, { 60, 64, 67, 72 }) <= 5, true, "close to the C after: " .. table.concat(into, " "))
  local bass = V.voice(H.tones(0, "maj"), { low = 28, high = 55, count = 3, bass = 4 })
  eq(bass[1] % 12, 4, "the bass asked for is lowest")
  eq(bass[3] <= 55, true, "within a bass's range")
  local drop = V.voice(H.tones(0, "maj7"), { low = 40, high = 84, style = "drop2", center = 60 })
  eq(drop[2] - drop[1] > 4, true, "drop 2 opens the bottom: " .. table.concat(drop, " "))
  eq(V.voice(g7, { low = 60, high = 62 }), nil, "nothing fits a range too narrow")
end)

test("harmony: an instrument's range is guessed from the track", function()
  fresh()
  local bass = paw.add_track({ name = "Bass" })
  eq(H.range(bass).low, 28, "a bass")
  eq(H.range(paw.add_track({ name = "Lead Guitar" })).name, "guitar", "a guitar")
  eq(H.range(paw.add_track({ name = "Track 3" })).low, 48, "else C3")
  eq(H.range(paw.add_track({ name = "Track 4" })).high, 84, "to C6")
  local own = paw.add_track({ name = "Odd" })
  own.meta = { range = { low = 50, high = 70 } }
  eq(H.range(own).high, 70, "or the track's own")
end)

test("harmony: a provider answers instead of the reading", function()
  fresh()
  chords("Piano", { { "C3 E3 G3", 4 } })
  paw.flush()
  eq(H.provider(), "builtin", "the built-in reading")
  H.provide(
    "server",
    function(from, to)
      return { { at = 0, length = 2, root = 2, quality = "m7" }, { at = 2, length = 2, root = 7, quality = "7" } }, {
        { at = 0, length = 4, tonic = 0, mode = "major" },
      }
    end,
    100
  )
  eq(reading(), "0:Dm7 2:G7", "the provider's chords")
  eq(reading(nil, nil, "roman"), "0:ii7 2:V7", "named in its key")
  eq(H.provider(), "server", "said")
  H.provide("silent", function() return nil end, 200)
  eq(H.provider(), "server", "one that does not answer is passed over")
  H.provide(
    "server",
    function() return { { at = 0, length = 2, root = 2, quality = "min7", ["function"] = "S" } }, {} end,
    50
  )
  eq(reading(), "0:Dm7 2:C", "the built-in reading fills in what a provider's answer does not cover")
  eq(H.at(0)["function"], "S", "a provider's own fields are kept, and its names for qualities understood")
  H.provide("server", nil)
  H.provide("silent", nil)
  eq(reading(), "0:C", "removed")
end)

test("harmony: chord symbols in the piano roll's ruler", function()
  fresh()
  chords("Piano", { { "C3 E3 G3", 4 }, { "A2 C3 E3", 4 }, { "G2 B2 D3 F3", 4 }, { "C3 E3 G3", 4 } })
  paw.flush()
  local roll = paw.ui.views.pianoroll
  roll:edit(paw.tracks()[1]:clips()[1])
  paw.opt.note_zoom = 4
  -- The view draws the reading as it stands: read the chords first.
  paw.harmony.chords()
  local function chord_row()
    local lines = api.ui_snapshot(100, 30)
    for _, l in ipairs(lines) do
      if l:find("Am") then return l end
    end
  end
  paw.opt.chords = "names"
  local row = chord_row()
  eq(row ~= nil and row:find("C") ~= nil and row:find("G7") ~= nil, true, "the names: " .. tostring(row))
  paw.opt.chords = "roman"
  local function has(text)
    for _, l in ipairs(api.ui_snapshot(100, 30)) do
      if l:find(text, 1, true) then return true end
    end
  end
  eq(has("vi") and has("V7"), true, "the numerals")
  paw.opt.chords = false
  eq(chord_row(), nil, "and none")
  paw.opt.chords = "names"
  paw.opt.note_zoom = 8
  paw.ui.focus("arrange")
end)

test("harmony: the chords MIDI LSP's engine hears flow into the reading and the terminal's chord row", function()
  -- Only with the engine named: the extension's own tests load it otherwise.
  if not os.getenv("MIDI_LSP_ENGINE") then return "no MIDI LSP engine: set $MIDI_LSP_ENGINE to run this" end
  paw.opt.midilsp_autostart = false
  if not paw.ext.loaded.midilsp then paw.ext.load("extensions/midilsp") end
  local midilsp = require("midilsp")
  fresh()
  dofile("examples/demo-song.lua")
  paw.flush()
  local keys = paw.tracks()[3]
  paw.ui.views.pianoroll:edit(keys:clips()[1])
  local ok, err = pcall(function()
    midilsp.start(true)
    local deadline = api.now() + 30000
    while H.provider() ~= "lsp" do
      if api.now() > deadline then error("waited in vain for the engine's analysis", 0) end
      paw.wait(20)
    end
    local first = H.at(0)
    eq(first.name, "Am", "the engine hears A minor at the start")
    eq(first["function"] ~= nil, true, "with its function: " .. tostring(first["function"]))
    eq(reading(8), "8:F/C 12:Fadd9/G 16:Am7 24:Cmaj9 28:G", "the built-in reading fills in past the clip it was sent")
    local row
    for _, line in ipairs(api.ui_snapshot(140, 48)) do
      if line:find("▏Am", 1, true) then row = line end
    end
    eq(row ~= nil, true, "the terminal's chord row shows it")
  end)
  paw.lsp.stop()
  paw.ui.focus("arrange")
  if not ok then error(err, 0) end
end)
