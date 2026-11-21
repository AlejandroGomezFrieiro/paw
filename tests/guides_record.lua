-- The how-to guides of the user guide about recording, each driven with the
-- keys that it gives (docs/how-to/record-*.md, use-the-metronome.md).
-- Loaded by tests/suite.lua with its helpers.
local T = ...
local test, eq, fresh = T.test, T.eq, T.fresh
local api = paw.api
local keys, until_, until_beat = T.keys, T.until_, T.until_beat

--- A fresh project in a saved file, with the test input of the null backend:
--- input channel 1 has a sine at 440 Hz, channel 2 at 880 Hz, and a MIDI
--- port `Keys A`.
local function studio(name)
  fresh()
  api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 }, test_midi = { "Keys A" } })
  T.after(function() api.engine_restart({ backend = "null" }) end)
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do paw.ui.close() end
  paw.ui.focus("arrange")
  T.after(function()
    paw.opt.count_in = 0
    paw.transport.metronome = false
  end)
  paw.project.tempo = 120
  paw.project.save(T.scratch .. "/" .. name .. ".json")
end


--- The bottom lines of the terminal screen.
local function status()
  local lines = api.ui_snapshot(120, 30)
  return lines[#lines - 1] .. "\n" .. lines[#lines]
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() end
  return f ~= nil
end

test("guide: record a guitar or a bass through an audio interface", function()
  studio("guitar")
  keys("o")
  keys("grnGuitar<CR>")
  local gtr = paw.tracks()[1]
  eq(gtr.name, "Guitar", "grn names the track")
  keys("Isignal 1<CR>")
  eq(gtr.input, "1", "I chooses one input channel, for a guitar")
  keys("r")
  eq(gtr.armed, true, "r arms the track")
  until_(function() return paw.audio.levels()[1] > 0.1 end, "the input level on the header")
  keys(":tuner<CR>")
  local tuner = gtr:device("tuner")
  eq(tuner ~= nil, true, ":tuner adds a tuner to the track")
  until_(function()
    local p = paw.params.read(tuner, "pitch")
    return p and p.note == "A4"
  end, "the tuner to hear the A")
  keys("<Space>dd")
  eq(paw.ui.focused, "arrange", "Space dd hides the device panel again")
  keys(":audio.buffer 128<CR>")
  keys("R")
  until_(function() return paw.transport.recording and paw.transport.playing end, "the recording")
  until_beat(paw.transport.position + 2)
  keys("<Space><Space>")
  paw.flush()
  local clips = gtr:clips()
  eq(#clips, 1, "the take is a clip on the track")
  eq(clips[1].kind, "audio", "of audio")
  eq(file_exists(clips[1]:get().file), true, "in a file")
  eq(clips[1]:get().file:find(T.scratch .. "/media/", 1, true) == 1, true, "in media next to the project")
end)

test("guide: record vocals with a count-in and a click", function()
  studio("vocals")
  keys("o")
  keys("grnVocal<CR>")
  local vox = paw.tracks()[1]
  keys("Isignal 1<CR>")
  keys("r")
  keys("gm")
  eq(paw.transport.metronome, true, "gm starts the metronome")
  eq(status():find("click", 1, true) ~= nil, true, "the status line shows the click")
  keys(":countin 1<CR>")
  eq(paw.opt.count_in, 1, ":countin 1 counts one bar")
  keys("2|")
  keys("R")
  until_(function() return paw.transport.counting > 0 end, "the count")
  eq(status():find("count", 1, true) ~= nil, true, "the status line shows the count")
  eq(paw.transport.position, 4, "the playhead waits for the count")
  until_(function() return paw.transport.counting == 0 and paw.transport.position > 4 end, "the take after the count")
  until_beat(5.6)
  keys("<Space><Space>")
  paw.flush()
  eq(#vox:clips(), 1, "the take is a clip")
  eq(vox:clips()[1].start, 4, "that starts at the playhead, after the count")
end)

test("guide: use the metronome", function()
  studio("metronome")
  keys("gm")
  eq(paw.transport.metronome, true, "gm starts the metronome")
  eq(status():find("click", 1, true) ~= nil, true, "the status line shows the click")
  local tone = T.tone("tone", 4)
  tone.mute = true
  eq(T.render({ tail = 0 }).peak, 0, "a rendered file has no click")
  keys("grt90<CR>")
  eq(paw.project.tempo, 90, "grt types the tempo")
  keys("gm")
  eq(paw.transport.metronome, false, "gm again stops it")
  keys("gM")
  eq(paw.opt.count_in, 1, "gM counts one bar in")
  eq(status():find("count 1", 1, true) ~= nil, true, "the status line shows the count-in")
  keys(":countin 2<CR>")
  eq(paw.opt.count_in, 2, ":countin 2 counts two bars")
  keys("gM")
  eq(paw.opt.count_in, 0, "gM again stops the count-in")
  keys(":countin 1<CR>")
  keys(":countin off<CR>")
  eq(paw.opt.count_in, 0, ":countin off stops it too")

  -- The sound of the click.
  T.after(function() paw.opt.click_level, paw.opt.click_accent, paw.opt.click_output = 0, true, 0 end)
  keys(":click level=-6<CR>")
  eq(api.transport_get().click_level, -6, ":click level=-6 makes it quieter")
  keys(":click accent=off<CR>")
  eq(api.transport_get().click_accent, false, ":click accent=off plays the same click on each beat")
  keys(":click accent=on<CR>")
  keys(":click output=3<CR>")
  eq(api.transport_get().click_output, 3, ":click output=3 plays it on outputs 3 and 4")
  keys(":click output=song<CR>")
  eq(api.transport_get().click_output, 0, ":click output=song puts it back")
  keys(":click<CR>")
  eq(paw.ui.messages[#paw.ui.messages].text, "click at -6 dB, the first beat higher, with the song", ":click shows the settings")

  -- Esc cancels a count.
  keys("gM")
  keys("R")
  until_(function() return paw.transport.counting > 0 end, "the count")
  keys("<Esc>")
  until_(function() return paw.transport.counting == 0 and not paw.transport.playing end, "the count to stop")
  eq(paw.transport.recording, false, "Esc cancels the count and the recording")
end)

test("guide: record MIDI from a keyboard", function()
  studio("keys")
  keys("o")
  keys("aSynth<CR>")
  local t = paw.tracks()[1]
  eq(t:devices()[1].kind, "synth", "a adds an instrument")
  keys("IKeys A<CR>")
  eq(paw.audio.label(t:get()), "MIDI · Keys A", "I chooses the port of the keyboard")
  keys("r")
  local function play(pitch, after)
    keys("R")
    until_(function() return paw.transport.recording and paw.transport.playing end, "the recording")
    -- At 120 bpm, a beat is 500 ms.
    until_beat(8 + after / 500)
    paw.midi.inject({ type = "note_on", pitch = pitch, velocity = 100, port = "Keys A", channel = 1 })
    until_beat(8 + after / 500 + 0.6)
    paw.midi.inject({ type = "note_off", pitch = pitch, port = "Keys A", channel = 1 })
    until_beat(8 + after / 500 + 1)
    keys("<Space><Space>")
    paw.flush()
  end
  keys("3|")
  play(60, 100)
  eq(#t:clips(), 1, "the take is a clip")
  eq(t:clips()[1].start, 8, "where the cursor was")
  eq(#t:clips()[1]:notes(), 1, "with the note played")

  -- A second take over the first, merged into it.
  keys("3|")
  play(64, 400)
  eq(#t:clips(), 2, "a new take is a new clip, over the first")
  keys("J")
  eq(#t:clips(), 1, "J merges the clips over each other")
  eq(#t:clips()[1]:notes(), 2, "with the notes of both")
  keys("u")
  keys(":3j<CR>")
  eq(#t:clips(), 1, ":3j merges the clips of bar 3")
  -- Overdub: the next take joins the clip by itself.
  keys(":set midi_record merge<CR>")
  T.after(function() paw.opt.midi_record = "new" end)
  keys("3|")
  play(67, 300)
  eq(#t:clips() .. " " .. #t:clips()[1]:notes(), "1 3", "with midi_record merge, the take joins the clip")
  keys("u")
  eq(#t:clips() .. " " .. #t:clips()[1]:notes(), "1 2", "u undoes the take and the merge")
  keys(":set midi_record new<CR>")

  -- Over a loop: every time round is a take.
  paw.project.tempo = 240
  keys("5|")
  keys("gl1W")
  eq(paw.transport.loop_enabled, true, "gl1W loops a bar")
  eq(paw.transport.loop_start .. "-" .. paw.transport.loop_end, "16-20", "the bar of the cursor")
  keys("R")
  until_(function() return paw.transport.recording and paw.transport.playing end, "the recording")
  for round, pitch in ipairs({ 67, 69 }) do
    until_beat(16.8, round == 1 and 0 or 1)
    paw.midi.inject({ type = "note_on", pitch = pitch, velocity = 100, port = "Keys A", channel = 1 })
    until_beat(17.6)
    paw.midi.inject({ type = "note_off", pitch = pitch, port = "Keys A", channel = 1 })
  end
  until_beat(16.8, 1)
  keys("<Space><Space>")
  paw.flush()
  local looped = t:clip_at(16)
  eq(looped.start .. "+" .. looped.length, "16+4", "one clip over the loop")
  eq(paw.takes.count(looped.id) >= 2, true, "with a take for each time round")
  eq(looped:notes()[1].pitch, 69, "the last take plays")
end)
