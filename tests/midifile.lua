-- Tests of Standard MIDI Files: reading them (paw.midifile), opening one as
-- a project, bringing one into a project, and writing one. The files are
-- made here, byte by byte. Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fresh = T.test, T.eq, T.near, T.fresh
local api = paw.api
local smf = paw.midifile

-- The tabs and windows the suite started with: `:e roll` and the piano roll
-- opened here change them, and the tests after these expect them as they were.
local initial = paw.layout.capture()

local function start()
  fresh()
  api.engine_restart({})
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.layout.restore(initial)
  paw.ui.focus("arrange")
  T.after(function()
    paw.keymap.feed("<Esc><Esc>")
    while paw.ui.float do
      paw.ui.close()
    end
    paw.layout.restore(initial)
    paw.ui.focus("arrange")
  end)
end

-- Bytes ------------------------------------------------------------------------

local function vlq(n)
  local bytes = { string.char(n % 128) }
  n = math.floor(n / 128)
  while n > 0 do
    table.insert(bytes, 1, string.char(128 + n % 128))
    n = math.floor(n / 128)
  end
  return table.concat(bytes)
end
local function u16(n) return string.char(math.floor(n / 256) % 256, n % 256) end
local function u32(n) return u16(math.floor(n / 65536)) .. u16(n % 65536) end
local function chunk(id, body) return id .. u32(#body) .. body end
local function header(format, ntracks, division) return chunk("MThd", u16(format) .. u16(ntracks) .. u16(division)) end
--- An event: its delta time, then its bytes (a status byte left out is running status).
local function ev(delta, ...) return vlq(delta) .. string.char(...) end
local function meta(delta, kind, body) return vlq(delta) .. "\255" .. string.char(kind) .. vlq(#body) .. body end
local function tempo(delta, bpm)
  local us = math.floor(60000000 / bpm + 0.5)
  return meta(delta, 0x51, string.char(math.floor(us / 65536), math.floor(us / 256) % 256, us % 256))
end
local function track(...) return chunk("MTrk", table.concat({ ... }) .. "\0\255\47\0") end

local folder = 0
local function file(name, bytes)
  folder = folder + 1
  local dir = T.scratch .. "/midifile" .. folder
  os.execute("mkdir -p '" .. dir .. "'")
  T.write_file(dir .. "/" .. name, bytes)
  return dir .. "/" .. name
end

--- Format 0 at 96 ticks a beat: a melody on channel 1 and drums on channel
--- 10, in one track, with running status, controllers, a tempo change, a
--- time signature, a marker, a lyric and a sysex.
local function format0()
  return header(0, 1, 96)
    .. track(
      meta(0, 0x03, "Demo song"),
      tempo(0, 100),
      meta(0, 0x58, string.char(3, 2, 24, 8)), -- 3/4
      meta(0, 0x06, "Verse"),
      ev(0, 0xC0, 5), -- program 5 on channel 1
      ev(0, 0xB0, 7, 100), -- volume
      meta(0, 0x05, "la"),
      ev(0, 0x90, 60, 100), -- C4 on
      ev(0, 64, 90), -- E4 on, running status
      ev(0, 0x99, 36, 120), -- kick on channel 10
      ev(48, 0x89, 36, 0),
      ev(0, 0xE0, 0, 96), -- bend up, 0x3000
      ev(0, 0xD0, 64), -- channel pressure
      vlq(0) .. "\240\3\65\16\247", -- sysex
      ev(48, 0x80, 60, 0), -- C4 off: a beat long
      ev(0, 0x90, 64, 0), -- E4 off by velocity 0
      tempo(96, 150), -- at beat 2
      ev(0, 0x90, 67, 80),
      ev(192, 0x80, 67, 0)
    ) -- G4: two beats
end

--- Format 1 at 480 ticks a beat: a conductor track and two named tracks,
--- one striking a key again before letting it go.
local function format1()
  return header(1, 3, 480)
    .. track(meta(0, 0x03, "Conductor"), tempo(0, 90), meta(0, 0x58, string.char(4, 2, 24, 8)), tempo(1920, 120))
    .. track(
      meta(0, 0x03, "Bass"),
      ev(0, 0x91, 40, 100),
      ev(240, 0x91, 40, 90), -- struck again half a beat in
      ev(240, 0x81, 40, 0),
      ev(480, 0x81, 40, 0), -- the first ends at 1, the second at 2
      ev(0, 0xB1, 1, 64)
    ) -- mod wheel at beat 2
    .. track(meta(0, 0x03, "Lead"), ev(1920, 0x92, 72, 110), ev(960, 0x82, 72, 0)) -- bar 2, two beats
end

local function names()
  local out = {}
  for _, t in ipairs(paw.parts()) do
    out[#out + 1] = t.name
  end
  return table.concat(out, ",")
end

local function control(list, kind, number)
  for _, c in ipairs(list) do
    if c.type == kind and (number == nil or c.number == number) then return c end
  end
end

local function screen(w, h) return table.concat(api.ui_snapshot(w or 120, h or 30), "\n") end

-- Reading ----------------------------------------------------------------------

test("a format 0 MIDI file is read with running status, controllers, tempo, metre, markers and lyrics", function()
  local f = assert(smf.parse(format0()))
  eq(f.format, 0, "format")
  eq(f.ppq, 96, "ticks a beat")
  eq(#f.tracks, 1, "one track")
  local notes = f.tracks[1].notes
  eq(#notes, 4, "four notes")
  eq(notes[2].pitch, 60, "C4 second, after the kick at the same tick")
  eq(notes[2].length, 96, "C4 is a beat long")
  eq(notes[3].pitch, 64, "E4 by running status")
  eq(notes[3].length, 96, "a note-on of velocity 0 ends it")
  eq(notes[1].channel, 9, "the kick is on channel 10")
  eq(notes[2].lyric, "la", "the lyric is on the note it starts, not on the drum's")
  eq(#f.tempos, 2, "two tempos")
  near(f.tempos[2].bpm, 150, 0.01, "the second tempo")
  eq(f.tempos[2].tick, 192, "at beat 2")
  eq(f.signatures[1].num .. "/" .. f.signatures[1].den, "3/4", "the time signature")
  eq(f.markers[1].text, "Verse", "the marker")
  eq(f.tracks[1].name, "Demo song", "the track's name")
  eq(f.skipped.sysex, 1, "the sysex is skipped, and counted")
  local c = f.tracks[1].controls
  eq(control(c, "bend").value, 0x3000, "pitch bend in 14 bits")
  eq(control(c, "program").program, 5, "the program change")
  eq(control(c, "cc", 7).value, 100, "the volume controller")
end)

test("a format 1 MIDI file pairs a key struck again first on, first off", function()
  local f = assert(smf.parse(format1()))
  eq(#f.tracks, 3, "three tracks")
  local bass = f.tracks[2].notes
  eq(#bass, 2, "two notes on one key")
  eq(bass[1].length, 480, "the first ends at the first note-off")
  eq(bass[2].tick .. "+" .. bass[2].length, "240+720", "the second at the second")
  eq(#f.tempos, 2, "the conductor's tempos")
end)

test("format 2, frame timing, a cut-off file and something not MIDI are read or refused in words", function()
  local f = assert(
    smf.parse(
      header(2, 2, 96)
        .. track(ev(0, 0x90, 60, 100), ev(96, 0x80, 60, 0))
        .. track(ev(0, 0x90, 62, 100), ev(96, 0x80, 62, 0))
    )
  )
  eq(f.tracks[2].notes[1].tick, 96, "format 2's tracks follow one another")
  -- 25 frames a second, 40 ticks a frame: a thousand ticks a second.
  f = assert(smf.parse(header(0, 1, 0xE728) .. track(tempo(0, 60), ev(0, 0x90, 60, 100), ev(1000, 0x80, 60, 0))))
  near(f.tracks[1].notes[1].length / f.ppq, 2, 1e-9, "a second of frames is two beats at 120")
  near(f.tempos[1].bpm, 120, 1e-9, "at 120")
  local whole = format1()
  f = assert(smf.parse(whole:sub(1, #whole - 7)))
  eq(
    f.skipped["a track cut short"] ~= nil or f.skipped["notes without an end (held to the end)"] ~= nil,
    true,
    "a cut-off file reads what is there"
  )
  local none, why = smf.parse("RIFF....WAVEfmt ")
  eq(none, nil, "a wav is not MIDI")
  eq(why, "not a MIDI file", "and says so")
end)

test("a MIDI file written and read again keeps its notes, controls, tempo map and markers", function()
  local f = assert(smf.parse(format0()))
  local again = assert(smf.parse(smf.encode({
    format = 1,
    ppq = f.ppq,
    tempos = f.tempos,
    signatures = f.signatures,
    markers = f.markers,
    tracks = { {}, f.tracks[1] },
  })))
  eq(#again.tracks[2].notes, 4, "the notes")
  for i, n in ipairs(f.tracks[1].notes) do
    local m = again.tracks[2].notes[i]
    eq(
      m.tick .. ":" .. m.length .. ":" .. m.pitch .. ":" .. m.velocity .. ":" .. m.channel .. ":" .. tostring(m.lyric),
      n.tick .. ":" .. n.length .. ":" .. n.pitch .. ":" .. n.velocity .. ":" .. n.channel .. ":" .. tostring(n.lyric),
      "note " .. i
    )
  end
  eq(#again.tracks[2].controls, #f.tracks[1].controls, "the controls")
  eq(#again.tempos, 2, "the tempos")
  eq(again.signatures[1].num, 3, "the metre")
  eq(again.markers[1].text, "Verse", "the marker")
end)

test("a lyric goes on the note at its tick or the next one, and the report names each moved or dropped", function()
  local f = assert(smf.parse(header(0, 1, 96) .. track(
    meta(0, 0x05, "a"),
    ev(0, 0x90, 60, 100),
    meta(48, 0x05, "b"), -- half a beat in: no note starts there
    ev(48, 0x80, 60, 0),
    ev(0, 0x90, 62, 100),
    ev(96, 0x80, 62, 0),
    meta(96, 0x05, "c") -- after the last note
  )))
  local notes = f.tracks[1].notes
  eq(notes[1].lyric .. " " .. notes[2].lyric, "a b", "on the note at its tick, and on the next one")
  eq(f.skipped, {
    ['lyric "b" of beat 1.5 moved to the next note, at beat 2'] = 1,
    ['lyric "c" of beat 4 dropped: no note at or after it'] = 1,
  }, "the report")
end)

test(":export writes the lyric of each note, and the file opens with it on the note", function()
  start()
  paw.add_part({ name = "Voice" }):add_clip({
    start = 0,
    length = 2,
    notes = { { pitch = 60, start = 0, length = 1, lyric = "la" }, { pitch = 62, start = 1, length = 1, lyric = "li" } },
  })
  local path = T.scratch .. "/lyrics.mid"
  T.keys(":export " .. path .. "<CR>")
  local f = assert(smf.read(path))
  eq(f.tracks[2].notes[1].lyric .. " " .. f.tracks[2].notes[2].lyric, "la li", "a lyric event at each note")
  smf.open(path)
  local notes = paw.parts()[1]:clips()[1]:notes()
  eq(notes[1].lyric .. " " .. notes[2].lyric, "la li", "and back on the notes")
end)

-- Opening ----------------------------------------------------------------------

test(
  ":open with a MIDI file makes a project of it: a part a channel, clips, controls, tempo map, nothing to undo",
  function()
    start()
    paw.add_part({ name = "Old" })
    api.undo_checkpoint()
    local path = file("demo.mid", format0())
    T.keys(":open! " .. path .. "<CR>")
    eq(names(), "Channel 1,Channel 10", "a format 0 file is split by channel")
    local p = api.project_get()
    eq(p.path, nil, "the project has no file: saving asks for one")
    eq(p.name, "demo", "it is named after the file")
    eq(p.modified, false, "nothing is changed yet")
    eq(paw.undo(), false, "and nothing is to be undone")
    local melody, drums = paw.parts()[1], paw.parts()[2]
    eq(#melody:devices(), 0, "a melody part has no instrument, as a new part has none")
    eq(drums:devices()[1].kind, "drums", "channel 10 plays the drum kit")
    local clip = melody:clips()[1]
    eq(clip.start, 0, "the clip starts at the bar of its first note")
    near(clip.length, 6, 1e-9, "and spans whole 3/4 bars")
    local notes = clip:notes()
    eq(#notes, 3, "the melody's notes")
    near(notes[3].start, 2, 1e-9, "G4 at beat 2")
    near(notes[3].length, 2, 1e-9, "for two beats")
    eq(notes[1].lyric, "la", "the lyric stays with its note")
    local controls = clip:controls()
    near(control(controls, "cc", 7).value, 100 / 127, 1e-9, "the volume controller as a clip control")
    near(control(controls, "bend").value, 0.5, 1e-9, "the pitch bend, -1 to 1")
    near(control(controls, "pressure").value, 64 / 127, 1e-9, "the channel pressure")
    eq(control(controls, "program").program, 5, "the program change")
    near(paw.tempo.at(0), 100, 0.01, "the first tempo")
    near(paw.tempo.at(3), 150, 0.01, "the tempo change")
    eq(table.concat({ paw.tempo.signature_at(0) }, "/"), "3/4", "the time signature")
    eq(paw.markers.list()[1].name, "Verse", "the marker")
    eq(
      paw.ui.message.text:find("4 notes on 2 parts", 1, true) ~= nil,
      true,
      "the status line says what came: " .. paw.ui.message.text
    )
    eq(paw.ui.message.text:find("1 sysex", 1, true) ~= nil, true, "and what was left out")
  end
)

test("a format 1 file opens with a part each, named, and the arrange view and piano roll show the notes", function()
  start()
  local path = file("song.mid", format1())
  T.keys(":e " .. path .. "<CR>")
  eq(names(), "Bass,Lead", "parts with notes, by their names; the conductor has none")
  local lead = paw.parts()[2]:clips()[1]
  eq(lead.start, 4, "the lead's clip starts at bar 2")
  near(lead:notes()[1].start, 0, 1e-9, "its note at the clip's start")
  near(paw.tempo.at(5), 120, 0.01, "the conductor's tempo change")
  local bass = paw.parts()[1]:clips()[1]
  near(control(bass:controls(), "cc", 1).value, 64 / 127, 1e-9, "the mod wheel")
  local arrange = screen()
  eq(
    arrange:find("Bass", 1, true) ~= nil and arrange:find("Lead", 1, true) ~= nil,
    true,
    "the arrange view shows the parts:\n" .. arrange
  )
  paw.cursor.set_part(paw.parts()[1])
  paw.cursor.beat = 0
  paw.ui.views:get("pianoroll"):edit(bass)
  paw.ui.focus("pianoroll")
  local roll = screen()
  eq(roll:find("E2", 1, true) ~= nil, true, "the piano roll shows the bass notes' key:\n" .. roll)
end)

test(":e names a buffer before a file, and saving over a MIDI file is refused", function()
  start()
  T.keys(":e roll<CR>")
  eq(paw.ui.focused, "pianoroll", "a buffer's name still shows the buffer")
  paw.ui.focus("arrange")
  T.keys(":w " .. T.scratch .. "/x.mid<CR>")
  eq(io.open(T.scratch .. "/x.mid") == nil, true, "nothing written")
  eq(paw.ui.message.text:find(":export", 1, true) ~= nil, true, "it points to :export")
end)

test("a MIDI file that will not read leaves the project alone", function()
  start()
  paw.add_part({ name = "Keep" })
  api.undo_checkpoint()
  T.keys(":open! " .. file("bad.mid", "not midi at all") .. "<CR>")
  eq(names(), "Keep", "the project is as it was")
  eq(paw.ui.message.text:find("not a MIDI file", 1, true) ~= nil, true, "and says why")
end)

-- Importing --------------------------------------------------------------------

test(":import brings a MIDI file's parts in at the cursor in one undo step, leaving the tempo map", function()
  start()
  paw.project.tempo = 128
  paw.add_part({ name = "Drums" })
  paw.add_part({ name = "Last" })
  api.undo_checkpoint()
  paw.cursor.set_part(paw.parts()[1])
  paw.cursor.beat = 8
  T.keys(":import " .. file("in.mid", format1()) .. "<CR>")
  eq(names(), "Drums,Bass,Lead,Last", "new parts below the cursor's")
  eq(paw.parts()[2]:clips()[1].start, 8, "the file's start at the cursor")
  eq(paw.parts()[3]:clips()[1].start, 12, "and its bars after it")
  near(paw.tempo.at(20), 128, 1e-9, "the tempo map is not the file's")
  eq(paw.undo(), true, "undo")
  eq(names(), "Drums,Last", "takes the whole import back in one step")
end)

test(":import tempo=yes takes the file's tempo map from the cursor on, and clip.import makes one clip", function()
  start()
  paw.project.tempo = 128
  paw.add_part({ name = "A" })
  paw.cursor.set_part(paw.parts()[1])
  paw.cursor.beat = 4
  api.undo_checkpoint()
  T.keys(":import " .. file("t.mid", format1()) .. " tempo=yes<CR>")
  near(paw.tempo.at(0), 128, 1e-9, "the project's before the cursor")
  near(paw.tempo.at(4), 90, 0.01, "the file's from it")
  near(paw.tempo.at(9), 120, 0.01, "and its change")
  paw.cursor.set_part(paw.parts()[1])
  paw.cursor.beat = 32
  local clip = paw.cmd("clip.import", { file("riff.mid", format1()) })
  eq(clip:part().name, "A", "on the cursor's part")
  eq(#clip:notes(), 3, "every note of the file in one clip")
  eq(clip.name, "riff", "named after the file")
end)

test("import completes and lists MIDI files beside sound files, and a dropped MIDI file is imported", function()
  start()
  local path = file("drop.mid", format1())
  local dir = path:match("^(.*)/")
  local found = false
  for _, c in ipairs(paw.commands.complete("import " .. dir .. "/dr")) do
    if c.text:find("drop.mid", 1, true) then found = true end
  end
  eq(found, true, "import offers the MIDI file")
  found = false
  for _, c in ipairs(paw.commands.complete("e " .. dir .. "/dr")) do
    if c.text:find("drop.mid", 1, true) then found = true end
  end
  eq(found, true, ":e offers it too")
  T.after(function() paw.files.cd(false) end)
  paw.files.cd(dir)
  T.keys(":import<CR>")
  eq(paw.ui.float ~= nil, true, "the list is open")
  eq(screen():find("drop.mid", 1, true) ~= nil, true, "and shows the MIDI file")
  paw.keymap.feed("<Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  local out = paw.frontend.act.drop({ path }, nil, 0)
  eq(#out.clips, 2, "the dropped file's clips")
  eq(names(), "Bass,Lead", "on parts of their own")
end)

-- Writing ----------------------------------------------------------------------

test(":export writes the project as a format 1 MIDI file with its tempo map, and a clip alone", function()
  start()
  paw.project.tempo = 100
  paw.tempo.set_signature(1, 6, 8)
  paw.tempo.set(6, 140)
  local t = paw.add_part({ name = "Keys" })
  t:add_clip({
    start = 3,
    length = 6,
    notes = { { pitch = 60, start = 0, length = 1, velocity = 90 }, { pitch = 64, start = 2, length = 0.5 } },
    controls = { { start = 1, type = "cc", number = 64, value = 1 } },
  })
  local d = paw.add_part({ name = "Beat" })
  d:add_device("drums")
  d:add_clip({ start = 0, length = 3, notes = { { pitch = 36, start = 0, length = 0.25 } } })
  paw.markers.add(3, "In")
  local path = T.scratch .. "/export.mid"
  T.keys(":export " .. path .. "<CR>")
  local f = assert(smf.read(path))
  eq(f.format, 1, "format 1")
  eq(#f.tracks, 3, "a conductor and a track for each part")
  eq(f.tracks[2].name, "Keys", "named")
  eq(f.tracks[2].notes[1].tick, 3 * f.ppq, "at the clip's place")
  eq(f.tracks[2].notes[2].length, f.ppq / 2, "lengths")
  eq(f.tracks[2].controls[1].value, 127, "the pedal")
  eq(f.tracks[3].notes[1].channel, 9, "the drum kit's part on channel 10")
  near(f.tempos[2].bpm, 140, 0.01, "the tempo change")
  eq(f.signatures[1].num .. "/" .. f.signatures[1].den, "6/8", "the metre")
  eq(f.markers[1].text, "In", "the marker")
  -- And opened again, it is the same song.
  smf.open(path)
  eq(names(), "Keys,Beat", "opened again")
  local again = paw.parts()[1]:clips()[1]:notes()
  near(paw.parts()[1]:clips()[1].start + again[2].start, 5, 1e-9, "the notes where they were")
  paw.cursor.set_part(paw.parts()[1])
  paw.cursor.beat = paw.parts()[1]:clips()[1].start
  T.keys(":export clip " .. T.scratch .. "/clip.mid<CR>")
  f = assert(smf.read(T.scratch .. "/clip.mid"))
  eq(#f.tracks, 2, "a clip alone")
end)

test(
  ":export of MIDI takes the range, each=part and each=clip, writes .midi2 as kept, and refuses words of sound",
  function()
    start()
    local dir = T.scratch .. "/midi-grammar"
    paw.project.save(dir .. "/song")
    local keys_ = paw.add_part({ name = "Keys" })
    keys_:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
    keys_:add_clip({
      start = 8,
      length = 4,
      notes = { { pitch = 62, start = 1, length = 1 }, { pitch = 64, start = 2, length = 1 } },
    })
    local bass = paw.add_part({ name = "Bass" })
    bass:add_clip({ start = 0, length = 8, notes = { { pitch = 36, start = 4, length = 2 } } })
    paw.flush()
    --- The tracks of a file and their notes: "Keys:3 Bass:1".
    local function held(path)
      local out = {}
      for _, part in ipairs(smf.parts(assert(smf.read(path)))) do
        out[#out + 1] = part.name .. ":" .. #part.notes
      end
      return table.concat(out, " ")
    end
    local renders = dir .. "/song/renders/"
    -- One file of type 1, one track of the file for each part of the range.
    T.keys(":export song.mid<CR>")
    eq(held(renders .. "song.mid"), "Keys:3 Bass:1", "the song, a part each, in renders/")
    eq(smf.read(renders .. "song.mid").format, 1, "type 1")
    T.keys(":t/Bass/export bass.mid<CR>")
    eq(held(renders .. "bass.mid"), "Bass:1", "a range of parts")
    T.keys(":3,4export later.mid<CR>")
    eq(held(renders .. "later.mid"), "Keys:2", "a range of time: the notes that start in bars 3 and 4")
    T.keys(":export parts.mid each=part<CR>")
    eq(held(renders .. "parts Keys.mid") .. " " .. held(renders .. "parts Bass.mid"), "Keys:3 Bass:1", "each=part")
    T.keys(":t/Keys/export riff.mid each=clip<CR>")
    eq(held(renders .. "riff Keys 01.mid") .. " " .. held(renders .. "riff Keys 02.mid"), "Keys:1 Keys:2", "each=clip")
    -- A clip file holds the clip as the project keeps it.
    paw.cursor.set_part(keys_)
    paw.cursor.set_beat(9)
    T.keys(":export clip riff.midi2<CR>")
    local kept = api.midi2_read(renders .. "riff.midi2")
    eq(
      #kept.notes .. " " .. kept.notes[1].start .. " " .. kept.length,
      "2 1 4",
      "the clip at the cursor, in its own beats"
    )
    -- A word of sound on a MIDI file is refused by name.
    T.expect_error("is MIDI")
    T.keys(":export song.mid tap=post<CR>")
    eq(paw.ui.message.text, "tap= is for sound; song.mid is MIDI", "tap=")
    T.expect_error("holds one clip")
    T.keys(":export song.midi2<CR>")
    eq(paw.ui.message.text:find("holds one clip", 1, true) ~= nil, true, "a clip file takes one clip")
    T.keys(":export " .. dir .. "/out.mid<CR>")
    T.expect_error("is there")
    T.keys(":export " .. dir .. "/out.mid<CR>")
    eq(paw.ui.message.text, dir .. "/out.mid is there: `:export!` replaces it", "a file outside renders/ is kept")
  end
)
