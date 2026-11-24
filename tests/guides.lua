-- The guides of the user guide, driven with the keys that they give. Each
-- test opens the practice project of a guide, types its steps as a person
-- does, and checks what the guide says that the learner gets.
--
-- Where a guide saves or renders into the folder that paw started in, the
-- test gives a path in the suite's scratch folder instead. Where a guide
-- asks for a MIDI keyboard or a guitar, the null backend gives a test port
-- and a test signal. The keys are otherwise those of the guide.
local T = ...
local paw = require("paw")
local api = paw.api
local test, eq = T.test, T.eq

-- "Make music with paw" (docs/tutorials/make-music) --------------------------

--- Type the keys of a step, each item as one key at the keyboard: the
--- kernel closes the undo step after each.
local function step(...)
  for _, text in ipairs({ ... }) do
    paw.keymap.feed(text)
    api.undo_checkpoint()
    paw.flush()
  end
end

--- Open a practice project as the lessons say: `:example make-music/<name>`.
local function open(script)
  T.fresh()
  paw.keymap.feed("<Esc><Esc>")
  if script then
    step(":example make-music/" .. script:gsub("%.lua$", "") .. "<CR>")
    eq(
      paw.ui.message.text:find("opened the example", 1, true) ~= nil,
      true,
      ":example opens " .. script .. ": " .. paw.ui.message.text
    )
  end
  paw.flush()
end

--- The notes of a clip as "pitch@start+length", by start, then pitch.
local function melody(clip)
  local notes = clip:notes()
  table.sort(notes, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.pitch < b.pitch
  end)
  local out = {}
  for _, n in ipairs(notes) do
    out[#out + 1] = string.format("%d@%g+%g", n.pitch, n.start, n.length)
  end
  return table.concat(out, " ")
end

--- Press `<Space><Space>`, let the playhead move a beat, and press
--- `<Space><Space>` again. Gives the loudest sample of the bar from where
--- the song started, rendered offline: what the learner hears there.
local function listen()
  local from = paw.transport.position
  step("<Space><Space>")
  eq(paw.transport.playing, true, "Space Space plays")
  T.until_beat(from + 1)
  step("<Space><Space>")
  eq(paw.transport.playing, false, "Space Space stops")
  return T.render({ start = from, ["end"] = from + 4, tail = 0 }).peak
end

local function params(device) return device:get().params end

local function file_size(path)
  local file = io.open(path, "rb")
  if not file then return 0 end
  local size = file:seek("end")
  file:close()
  return size
end

--- Wait for a file that a render writes.
local function until_rendered(path)
  T.until_(function() return file_size(path) > 0 end, "the render of " .. path)
end

test("make music 1: the first song has drums, bass and keys in a loop of four bars, and is saved", function()
  open()
  step(":tempo 100<CR>")
  step("o", "grn", "<C-u>", "Drums<CR>")
  step("a", "drums", "<CR>")
  step("i", "m", "<CR>", "<Esc>")
  eq(paw.ui.focused, "pianoroll", "i m Enter opens the new clip in the piano roll")
  step("<C-d>", "<C-d>", "<CR>", "8l", "<CR>")
  step("2k", "4h", "<CR>", "8l", "<CR>")
  step("4k", "0", "i", "l")
  for _ = 1, 7 do
    step("<Space>", "l")
  end
  step("<Esc>")
  step("<C-w>p", "&", "&", "&")
  local drums = paw.part("Drums")
  eq(#drums:clips(), 4, "four bars of drums")
  eq(
    melody(drums:clips()[4]),
    "36@0+0.25 42@0+0.25 42@0.5+0.25 38@1+0.25 42@1+0.25 42@1.5+0.25 36@2+0.25 42@2+0.25 42@2.5+0.25 38@3+0.25 42@3+0.25 42@3.5+0.25",
    "kick, snare and hi-hats in each bar"
  )

  step("o", "grn", "<C-u>", "Bass<CR>", "a", "synth", "<CR>", "0")
  step("i", "<CR>", "J", "3-", "16l", "<CR>", "4-", "16l", "<CR>", "7+", "16l", "<CR>", "5-", "16l", "<Esc>")
  step("<C-w>p")
  eq(melody(paw.part("Bass"):clips()[1]), "45@0+4 41@4+4 48@8+4 43@12+4", "the bass plays A F C G")
  eq(paw.part("Bass"):clips()[1].length, 16, "the clip ends with the notes, at the end of bar 4")

  step("o", "grn", "<C-u>", "Keys<CR>", "a", "synth", "<CR>", "0")
  step("i", "<CR>", "3-", "c", "vi<CR>", "16l", "<CR>")
  step("c", "IV6<CR>", "16l", "<CR>")
  step("c", "I64<CR>", "16l", "<CR>")
  step("c", "V<CR>", "16l", "<Esc>")
  step("<C-w>p")
  eq(
    melody(paw.part("Keys"):clips()[1]),
    "57@0+4 60@0+4 64@0+4 57@4+4 60@4+4 65@4+4 55@8+4 60@8+4 64@8+4 55@12+4 59@12+4 62@12+4",
    "the chords Am F C G"
  )

  step("gg", "0", "gl4W")
  eq(
    paw.transport.loop_enabled and paw.transport.loop_start == 0 and paw.transport.loop_end == 16,
    true,
    "the loop is bars 1 to 4"
  )
  step("gs")
  eq(listen() > 0.01, true, "the song plays")

  local file = T.scratch .. "/first-song"
  step(":w " .. file .. "<CR>")
  eq(file_size(file .. "/project.toml") > 0, true, "the project is saved")
  eq(paw.project.path, file .. "/project.toml", "paw works in the saved folder")
end)

test("make music 2: a lead played on a MIDI keyboard is recorded over the loop and quantized", function()
  api.engine_restart({ test_midi = { "Keystation 49" } })
  T.after(function() api.engine_restart({}) end)
  open("2-midi-keyboard.lua")
  step("G", "o", "grn", "<C-u>", "Lead<CR>", "a", "synth", "<CR>")
  step("I", "Keystation", "<CR>")
  local lead = paw.part("Lead")
  eq(lead.midi_input and lead.midi_input.port, "Keystation 49", "the lead takes MIDI from the keyboard")
  step("r")
  eq(lead.armed, true, "the lead is armed")

  local function key(pitch, on)
    paw.midi.inject({ type = on and "note_on" or "note_off", pitch = pitch, velocity = 100, port = "Keystation 49" })
  end

  -- Record: the notes come a little late, as a person plays them.
  step("0", "R")
  for i, pitch in ipairs({ "E5", "C5", "A4", "C5" }) do
    T.until_beat(i - 1 + 0.08)
    key(pitch, true)
    T.until_beat(i - 1 + 0.5)
    key(pitch, false)
  end
  step("R", "<Space><Space>")
  T.until_recorded()
  eq(paw.transport.recording or paw.transport.playing, false, "the recording stopped")
  local clip = lead:clips()[1]
  eq(clip ~= nil and clip.kind, "midi", "the take is a MIDI clip")
  local played = melody(clip)
  eq(#clip:notes(), 4, "the take has the notes")
  eq(played:find("76@0+", 1, true), nil, "the notes are late, as played")

  step("<CR>")
  eq(paw.ui.focused, "pianoroll", "Enter opens the take")
  step("=ie")
  local quantized = melody(clip)
  for _, n in ipairs(clip:notes()) do
    eq(n.start % 0.25, 0, "each note starts on the grid")
  end
  step("u")
  eq(melody(clip), played, "u gives back the notes as played")
  step("<C-r>")
  eq(melody(clip), quantized, "Ctrl-r quantizes again")

  step("<C-w>p", "r")
  eq(lead.armed, false, "the lead is not armed")
  step("gs")
  eq(listen() > 0.01, true, "the song plays with the lead")
  step(":w " .. T.scratch .. "/with-lead<CR>")
  eq(file_size(T.scratch .. "/with-lead/project.toml") > 0, true, "the song is saved")
end)

test("make music 3: a guitar through an amp chain is recorded in two takes and comped, with a fade", function()
  api.engine_restart({ test_input = { frequency = 220, level = -12, channels = 2 } })
  T.after(function() api.engine_restart({}) end)
  open("3-guitar.lua")
  step("G", "o", "grn", "<C-u>", "Guitar<CR>")
  step("I", "· 1", "<CR>")
  local guitar = paw.part("Guitar")
  eq(guitar.input, "1", "the guitar takes input 1")
  step("<A-i>")
  eq(guitar.monitor, true, "we hear the input")

  step("a", "saturation", "<CR>")
  step("<Space>dd")
  eq(paw.ui.focused, "inspector", "Space dd opens the device panel")
  step("j", "12+", "j", "+")
  local saturation = guitar:devices()[1]
  eq(params(saturation).drive > 10, true, "more drive")
  eq(params(saturation).curve, 1, "the tube curve")
  step("a", "eq", "<CR>", "w", "c", "fizz", "<CR>")
  local eq_device = guitar:devices()[2]
  eq(eq_device and eq_device:get().kind, "eq", "an equalizer after the saturation")
  eq(params(eq_device).b8_on, 1, "the preset cuts the highs")
  step("<C-w>p")
  eq(paw.ui.focused, "arrange", "back in the arrange view")

  step("0", "gl2W")
  eq(paw.transport.loop_start == 0 and paw.transport.loop_end == 8, true, "the loop is bars 1 and 2")
  step("r", "R")
  -- Two times round the loop: stop when the playhead returns to bar 1 the third time.
  T.until_beat(0, 2)
  step("<Space><Space>")
  T.until_recorded()
  local clip = guitar:clips()[1]
  eq(clip and clip.kind, "audio", "the takes are an audio clip")
  eq(paw.takes.count(clip), 2, "two takes")

  step("zt")
  step("0", "W", "v", "W", ":take 1<CR>")
  local clips = guitar:clips()
  eq(#clips, 2, "the clip is cut at bar 2")
  eq(paw.takes.count(clips[2]), 2, "each piece keeps both takes")
  eq(clips[1].meta.takes.active, 2, "bar 1 plays take 2")
  eq(clips[2].meta.takes.active, 1, "bar 2 plays take 1")
  eq(
    clips[1].name:match("%.2$") ~= nil and clips[2].name:match("%.1$") ~= nil,
    true,
    "each piece is named after the take it plays: " .. clips[1].name .. ", " .. clips[2].name
  )
  eq(listen() > 0.01, true, "the comp plays")

  step("0", "w", ":clip.fade out=2<CR>")
  eq(guitar:clips()[2].fade_out, 2, "the last piece fades out over two beats")
  step("r", "<A-i>")
  eq(guitar.armed or guitar.monitor, false, "the guitar is no longer armed or monitored")
  step("gs")
  eq(listen() > 0.01, true, "the song plays with the guitar")
  step(":w " .. T.scratch .. "/with-guitar<CR>")
  eq(file_size(T.scratch .. "/with-guitar/project.toml") > 0, true, "the song is saved")
end)

test("make music 4: the song is arranged into verse and chorus, with markers, a new tempo and a jump", function()
  open("4-arrange.lua")
  step(":1,4co 5<CR>")
  eq(#paw.part("Drums"):clips(), 8, "eight bars of drums")
  step("/Lead<CR>", "0", "x", "j", "x")
  eq(#paw.part("Lead"):clips(), 1, "the lead plays only in the chorus")
  eq(paw.part("Lead"):clips()[1].start, 16, "from bar 5")
  step("5|", "8L")
  eq(paw.part("Guitar"):clips()[1].start, 24, "the guitar answers in bar 7")
  step(":1,8co 9<CR>")
  eq(#paw.part("Drums"):clips(), 16, "sixteen bars of drums")
  eq(#paw.part("Lead"):clips(), 2, "two choruses")

  step(
    "0",
    ":marker Verse<CR>",
    "5|",
    ":marker Chorus<CR>",
    "9|",
    ":marker Second verse<CR>",
    "13|",
    ":marker Last chorus<CR>"
  )
  local markers = {}
  for _, m in ipairs(paw.markers.list()) do
    markers[#markers + 1] = m.name .. "@" .. m.beat
  end
  eq(table.concat(markers, " "), "Verse@0 Chorus@16 Second verse@32 Last chorus@48", "four markers")

  step(":tempo 104<CR>")
  eq(paw.project.tempo, 104, "the new tempo")
  step("gL")
  eq(paw.transport.loop_enabled, false, "the loop is off")
  step("gs")
  eq(listen() > 0.01, true, "the song plays")

  step('g"', "last", "<CR>")
  eq(paw.cursor.beat, 48, "the cursor is at the last chorus")
  step("['")
  eq(paw.cursor.beat, 32, "[' goes to the marker before")
  step("<Space>ft", "Bass", "<CR>")
  eq(paw.cursor.part().name, "Bass", "the part picker goes to the bass")
  step("gp")
  eq(paw.transport.position, 32, "the playhead is at the cursor")
  eq(listen() > 0.01, true, "the song plays from the second verse")
  step(":w " .. T.scratch .. "/arranged<CR>")
  eq(file_size(T.scratch .. "/arranged/project.toml") > 0, true, "the song is saved")
end)

test("make music 5: the song is mixed, rendered to WAV and MP3, and the file plays", function()
  open("5-mix.lua")
  step("<Space>mm")
  eq(paw.ui.focused, "mixer", "Space mm opens the mixer")
  step("V", "$", "6-", "<Esc>")
  for _, part in ipairs(paw.parts()) do
    eq(part.volume, -6, part.name .. " is 6 dB lower")
  end
  step("0", "l", "3-")
  eq(paw.part("Bass").volume, -9, "the bass is 3 dB lower again")
  step("l", "j", "3-")
  T.near(paw.part("Keys").pan, -0.3, 1e-6, "the keys are on the left")
  step("2l", "3+")
  T.near(paw.part("Guitar").pan, 0.3, 1e-6, "the guitar is on the right")
  step("<C-w>c")

  step("/Bass<CR>", "<Space>dd", "a", "eq", "<CR>", "gg", "w", "c", "tighten", "<CR>", "<Space>dd")
  local bass_eq = paw.part("Bass"):devices()[2]
  eq(bass_eq and bass_eq:get().kind, "eq", "the bass has an equalizer")
  eq(params(bass_eq).b1_on, 1, "with the preset")
  step("/Drums<CR>", "<Space>dd", "a", "compressor", "<CR>", "gg", "w", "c", "glue", "<CR>", "<Space>dd")
  local compressor = paw.part("Drums"):devices()[2]
  eq(compressor and compressor:get().kind, "compressor", "the drums have a compressor")
  eq(params(compressor).ratio, 2, "with the preset")
  eq(paw.ui.focused, "arrange", "back in the arrange view")

  step("G", ":part.add Reverb<CR>", "<Space>dd", "a", "reverb", "<CR>", "gg", "c", "on a send", "<CR>", "<Space>dd")
  local reverb = paw.part("Reverb")
  eq(reverb and params(reverb:devices()[1]).mix, 100, "the reverb part has a reverb set for a send")
  step("/Keys<CR>", ":send Reverb -9<CR>", "/Lead<CR>", ":send Reverb -12<CR>")
  local function send_level(name)
    for _, send in ipairs(api.part_get(paw.part(name).id).sends) do
      if send.target == reverb.id then return send.level end
    end
  end
  eq(send_level("Keys"), -9, "the keys send to the reverb")
  eq(send_level("Lead"), -12, "the lead sends to the reverb")
  step("gs")
  eq(listen() > 0.01, true, "the mix plays")

  step("5|", "A", "<C-u>", "-20<CR>", "W", "A", "<C-u>", "0<CR>")
  local points = paw.part("Lead"):lane("volume"):points()
  eq(#points, 2, "two points of volume automation")
  eq(
    points[1][1] == 16 and points[1][2] == -20 and points[2][1] == 20 and points[2][2] == 0,
    true,
    "the lead comes up in bar 5"
  )

  local folder = T.scratch .. "/my-songs"
  os.execute("mkdir -p '" .. folder .. "'")
  step(":w " .. folder .. "/my-song<CR>")
  -- A name alone goes into the folder renders of the song.
  step(":export my-song.wav<CR>")
  -- The WAV file is in the folder renders of the song.
  until_rendered(folder .. "/my-song/renders/my-song.wav")
  local said = T.until_(function()
    for _, m in ipairs(paw.ui.messages) do
      if m.text:find("^wrote renders/my%-song%.wav") then return m.text end
    end
  end, "the message of the render")
  eq(said:find("(clips)", 1, true), nil, "the render does not clip: " .. said)
  if paw.health and paw.health.executable and not paw.health.executable("ffmpeg") then
    print("      (no ffmpeg: the MP3 step is not checked)")
  else
    step(":export my-song.mp3<CR>")
    until_rendered(folder .. "/my-song/renders/my-song.mp3")
  end

  step(":e renders<CR>", "/my-song.wav<CR>", "gh")
  T.until_(function()
    local now = paw.audition.state()
    return not (now and now.state == "loading")
  end, "the rendered file to load")
  local state = paw.audition.state() or {}
  eq(state.file, folder .. "/my-song/renders/my-song.wav", "gh plays the rendered file")
  eq(state.state, "playing", "and it plays")
  step("gh")
  eq((paw.audition.state() or {}).state ~= "playing", true, "gh again stops it")
  step("<C-^>")
  eq(paw.ui.focused, "arrange", "Ctrl-^ returns to the arrange view")
end)
