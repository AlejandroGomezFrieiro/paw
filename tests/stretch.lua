-- Tests of stretched, pitch-shifted, tempo-following and looped clips
-- (`paw.stretch`, docs/reference/stretch.md). Loaded by
-- tests/suite.lua with its helpers.
local T = ...
local test, eq, near, fails, fresh, render = T.test, T.eq, T.near, T.fails, T.fresh, T.render
local api = paw.api

local function start()
  fresh()
  api.engine_restart({ backend = "null" })
  paw.keymap.feed("<Esc><Esc>")
  while paw.ui.float do
    paw.ui.close()
  end
  paw.ui.focus("arrange")
  paw.project.tempo = 120
end

--- A sound file of a held tone at `pitch` (A3, 220 Hz, by default), `beats`
--- long at 120 BPM, rendered at 16 bits.
local function tone_file(beats, pitch)
  start()
  T.tone("source", beats, pitch)
  local info = render({ tail = 0, bits = 16 })
  start()
  return info.path
end

--- The 16-bit samples of a rendered WAV file's left channel, from frame
--- `from` for `count` frames.
local function samples(info, from, count)
  local data = T.read_file(info.path)
  local at = data:find("data", 1, true) + 8
  local out = {}
  for i = 0, count - 1 do
    local p = at + (from + i) * 4
    local lo, hi = data:byte(p, p + 1)
    if not hi then break end
    local v = lo + hi * 256
    out[#out + 1] = v >= 32768 and v - 65536 or v
  end
  return out
end

--- Whether two runs of samples are the same, and where they first differ.
local function same(a, b)
  if #a ~= #b then return false, "lengths " .. #a .. " and " .. #b end
  for i = 1, #a do
    if a[i] ~= b[i] then return false, "frame " .. i .. ": " .. a[i] .. " and " .. b[i] end
  end
  return true
end

--- Wait until no clip is being stretched any more.
local function settled()
  for _ = 1, 1500 do
    local busy = false
    for _, t in ipairs(paw.tracks()) do
      for _, c in ipairs(api.clip_list(t.id)) do
        busy = busy or c.stretching or false
      end
    end
    if not busy then return end
    paw.wait(10)
  end
  error("the stretched clips were never made")
end

-- Stretching and shifting ---------------------------------------------------------

test("a stretched clip renders at its new length with the pitch of its file", function()
  local file = tone_file(8)
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  near(clip.length, 8, 1e-6, "the file's length")
  paw.stretch.set(clip.id, 1.5)
  near(clip.length, 12, 1e-6, "half as long again")
  near(clip.stretch, 1.5, 1e-12, "the ratio")
  paw.flush()
  eq(clip.stretching, true, "it is being made")
  local info = render({ tail = 0, bits = 16 })
  near(info.seconds or info.frames / info.sample_rate, 6, 0.01, "six seconds rendered")
  near(T.frequency(info, 1, 5), 220, 220 * 0.005, "at the file's pitch")
  local left = T.channel_peaks(info, 5.6, 5.9)
  eq(left > 0.1, true, "sounding to its new end")
  settled()
  eq(clip.stretching, nil, "made")
  -- The waveform drawn is what it plays: as loud all along its new length.
  local peaks = clip:peaks(16)
  eq(peaks[2][2] > 0.1 and peaks[15][2] > 0.1, true, "a waveform over the whole clip")
  -- Played live, the stretched sound is heard.
  paw.transport.seek(4)
  paw.transport.play()
  paw.wait(300)
  local level = t:meter()
  paw.transport.stop()
  eq(level > 0.05, true, "heard while playing")
end)

test("a clip plays a rough preview until its stretch is made, then the stretch", function()
  local file = tone_file(16)
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  paw.transport.seek(8)
  paw.stretch.set(clip.id, 1.5)
  paw.flush()
  paw.transport.play()
  paw.wait(60)
  local level = t:meter()
  -- A bake starts 150 ms after it is asked for at the soonest.
  eq(clip.preview, true, "still the preview")
  eq(level > 0.05, true, "the preview is heard, not silence")
  settled()
  eq(clip.preview, nil, "the stretch plays")
  paw.wait(100)
  level = t:meter()
  paw.transport.stop()
  eq(level > 0.05, true, "heard after the swap")
end)

test("a pitch shift moves the pitch and keeps the length", function()
  local file = tone_file(8)
  local clip = paw.add_track({ name = "audio" }):add_clip({ file = file, start = 0 })
  paw.stretch.pitch(clip.id, 12)
  near(clip.length, 8, 1e-6, "as long")
  local info = render({ tail = 0, bits = 16 })
  near(T.frequency(info, 0.5, 3.5), 440, 440 * 0.005, "an octave up")
  clip.pitch = -0.5
  info = render({ tail = 0, bits = 16 })
  near(T.frequency(info, 0.5, 3.5), 220 * 2 ^ (-0.5 / 12), 1.5, "a quarter tone down")
  -- Both at once, and each mode.
  paw.stretch.set(clip.id, 0.8)
  for _, mode in ipairs({ "tonal", "percussive", "auto" }) do
    clip.stretch_mode = mode
    info = render({ tail = 0, bits = 16 })
    near(info.frames / info.sample_rate, 3.2, 0.01, mode .. ": shorter")
    near(T.frequency(info, 0.5, 2.5), 220 * 2 ^ (-0.5 / 12), 1.5, mode .. ": and still shifted")
  end
  fails(function() clip.stretch = 9 end, "between", "a ratio out of range")
  fails(function() clip.pitch = 30 end, "semitones", "a shift out of range")
  local midi = paw.add_track({ name = "midi" }):add_clip({ start = 0, length = 4 })
  fails(function() midi.stretch = 2 end, "audio", "MIDI is not stretched")
end)

test("the stretch commands set what they say, and are undone", function()
  local file = tone_file(4)
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(1)
  api.undo_checkpoint()
  paw.commands.exec("clip.stretch 2")
  near(clip.length, 8, 1e-6, "clip.stretch 2")
  api.undo_checkpoint()
  paw.commands.exec("clip.stretch to=6")
  near(clip.length, 6, 1e-6, "clip.stretch to=6: the length")
  near(clip.stretch, 1.5, 1e-9, "clip.stretch to=6: the ratio")
  api.undo_checkpoint()
  paw.commands.exec("clip.pitch -0.5")
  eq(clip.pitch, -0.5, "clip.pitch -0.5")
  paw.commands.exec("clip.stretch_mode percussive")
  eq(clip.stretch_mode, "percussive", "clip.stretch_mode")
  api.undo_checkpoint()
  paw.commands.exec("clip.stretch reset")
  near(clip.length, 4, 1e-6, "reset: its own length")
  eq(clip.stretch, 1, "reset: its own speed")
  api.undo_checkpoint()
  paw.undo()
  near(clip.stretch, 1.5, 1e-9, "undo brings the stretch back")
  near(clip.length, 6, 1e-6, "and the length")
  paw.undo()
  eq(clip.pitch, 0, "and before that the shift")
  -- To the loop.
  paw.transport.loop_start, paw.transport.loop_end = 2, 4
  paw.commands.exec("clip.stretch loop")
  eq(clip.start, 2, "starts at the loop")
  near(clip.length, 2, 1e-6, "lasts the loop")
end)

-- Following the tempo ----------------------------------------------------------------

test("a clip following the tempo keeps its beats and its pitch when the tempo changes", function()
  local file = tone_file(8)
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 2 })
  local plain = t:add_clip({ file = file, start = 12 })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(3)
  paw.commands.exec("clip.tempo")
  eq(clip.timebase, "stretch", "the timebase")
  eq(clip.source_tempo, 120, "its sound's tempo, from the project's")
  paw.project.tempo = 60
  eq(clip.start, 2, "the same start beat")
  near(clip.length, 8, 1e-6, "the same beats")
  near(clip.stretch, 2, 1e-9, "stretched to fit")
  near(plain.length, 4, 1e-6, "a clip keeping time is half as many beats")
  plain:remove()
  local info = render({ tail = 0, bits = 16 })
  near(T.frequency(info, 3, 9), 220, 220 * 0.005, "at its pitch")
  near(info.frames / info.sample_rate, 10, 0.01, "lasting its beats at the new tempo")
  paw.project.tempo = 120
  near(clip.stretch, 1, 1e-9, "back at its own tempo, at its own speed")
  -- Told its sound's tempo: a loop at 100 BPM fits 120.
  paw.commands.exec("clip.tempo 100")
  near(clip.stretch, 100 / 120, 1e-9, "played faster")
  near(clip.length, 8 * 100 / 120, 1e-6, "in fewer beats")
  paw.commands.exec("clip.tempo off")
  eq(clip.timebase, "time", "keeps time again")
end)

test("a recording knows the tempo it was made at", function()
  start()
  api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })
  paw.project.tempo = 96
  paw.project.save(T.scratch .. "/recorded.json")
  local t = paw.add_track({ name = "Voice" })
  t.input, t.armed = "1", true
  paw.transport.seek(0)
  paw.transport.record()
  T.until_beat(1.4)
  paw.transport.stop()
  paw.flush()
  local clip = t:clips()[1]
  api.engine_restart({ backend = "null" })
  eq(clip ~= nil, true, "a take")
  eq(clip.source_tempo, 96, "its tempo")
end)

-- Looping ---------------------------------------------------------------------------

--- A sound file of two beats at 120 BPM: notes that start and end in
--- silence, so that it repeats without a seam.
local function phrase_file()
  start()
  local t = paw.add_track({ name = "source" })
  t:add_device("synth", { attack = 0.001, release = 0.01 })
  t:add_clip({
    start = 0,
    length = 2,
    notes = {
      { pitch = "A3", start = 0.25, length = 0.5 },
      { pitch = "E4", start = 1, length = 0.5 },
    },
  })
  local info = render({ tail = 0, bits = 16 })
  start()
  return info.path
end

test("a looped audio clip repeats its sound exactly", function()
  local file = phrase_file()
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  near(clip.length, 2, 1e-6, "two beats")
  paw.cursor.set_track(t)
  paw.cursor.set_beat(0.5)
  paw.commands.exec("clip.repeat")
  eq(clip.loop, true, "looping")
  near(clip.loop_length, 2, 1e-6, "its whole file")
  paw.frontend.act.trim_clips(clip.id, "end", 4, false, false)
  near(clip.length, 6, 1e-6, "dragged out over two more repeats")
  local info = render({ tail = 0, bits = 16 })
  local first, second, third = samples(info, 0, 48000), samples(info, 48000, 48000), samples(info, 96000, 48000)
  local ok, why = same(first, second)
  eq(ok, true, "the second repeat is the first (" .. tostring(why) .. ")")
  eq(same(first, third), true, "and so is the third")
  -- The window marks each repeat, and so does the terminal's label.
  local state = paw.frontend.state(-1)
  local shown
  for _, c in ipairs(state.clips) do
    if c.id == clip.id then shown = c end
  end
  eq(#shown.notches, 2, "two notches")
  near(shown.notches[1], 2, 1e-9, "at the second repeat")
  eq(shown.name:find("↻", 1, true) ~= nil, true, "a mark in its name")
  -- Its waveform repeats too.
  local peaks = clip:peaks(30)
  eq(peaks[3][2], peaks[13][2], "the waveform repeats")
  -- Turned off, it is silent past its file.
  paw.commands.exec("clip.repeat")
  eq(clip.loop, false, "off")
  info = render({ tail = 0, bits = 16 })
  local left = T.channel_peaks(info, 2.1, 2.9)
  eq(left, 0, "silent past its sound")
end)

test("a looped MIDI clip repeats its notes exactly, cut at the loop's end", function()
  start()
  local t = paw.add_track({ name = "keys" })
  t:add_device("synth", { attack = 0.001, release = 0.01 })
  local clip = t:add_clip({
    start = 0,
    length = 2,
    notes = {
      { pitch = "A3", start = 0, length = 0.5 },
      { pitch = "C4", start = 1, length = 1.5 },
    },
  })
  paw.stretch.loop(clip.id, true)
  near(clip.loop_length, 2, 1e-9, "the clip's length")
  clip.length = 6
  -- At this tempo a frame is 2^-15 beats, so that a note's beat falls on
  -- the very frame it should at every repeat: at others the engine's
  -- rounding of beats to frames can put one a frame off.
  paw.project.tempo = 87.890625
  local info = render({ tail = 0, bits = 16 })
  -- The first repeat starts from silence; the others with the end of the
  -- note cut before them dying away.
  local second, third = samples(info, 65536, 65536), samples(info, 131072, 65536)
  local ok, why = same(second, third)
  eq(ok, true, "the third repeat is the second (" .. tostring(why) .. ")")
  -- The note reaching past the loop's end is cut there, so the window's
  -- picture shows it cut, three times.
  local flat = paw.frontend.preview(clip.id)
  eq(#flat, 18, "six notes over three repeats")
  near(flat[5], 1, 1e-9, "the second note is cut at the end of the repeat")
  -- A shorter loop than the clip held.
  paw.stretch.loop(clip.id, true, 1)
  near(clip.loop_length, 1, 1e-9, "a beat repeats")
  flat = paw.frontend.preview(clip.id)
  eq(#flat, 18, "the first beat six times")
end)

test("splitting, trimming and moving what plays in a looped clip keep what it plays", function()
  start()
  local t = paw.add_track({ name = "keys" })
  t:add_device("synth", { attack = 0.001, release = 0.01 })
  local clip = t:add_clip({
    start = 0,
    length = 2,
    notes = {
      { pitch = "A3", start = 0, length = 0.5 },
      { pitch = "C4", start = 1, length = 0.5 },
    },
  })
  paw.stretch.loop(clip.id, true)
  clip.length = 8
  local before = T.read_file(render({ tail = 0, bits = 16 }).path)
  -- Cut in the middle of a repeat: both pieces carry on the same.
  paw.cursor.set_track(t)
  paw.cursor.set_beat(3)
  api.undo_checkpoint()
  paw.commands.exec("clip.split")
  api.undo_checkpoint()
  eq(#t:clips(), 2, "two pieces")
  local right = t:clips()[2]
  eq(right.loop, true, "the right piece loops")
  near(right.loop_start, -1, 1e-9, "from a beat before its start")
  eq(T.read_file(render({ tail = 0, bits = 16 }).path) == before, true, "the same sound")
  -- Trimmed at its start: what is left plays where it did.
  local was5 = T.read_file(render({ start = 5, tail = 0, bits = 16 }).path)
  paw.frontend.act.trim_clips(right.id, "start", 2, false, false)
  api.undo_checkpoint()
  eq(right.start, 5, "trimmed")
  near(right.loop_start, -1, 1e-9, "three beats in is a beat into a repeat")
  local from5 = T.read_file(render({ start = 5, tail = 0, bits = 16 }).path)
  eq(from5 == was5, true, "the trimmed piece sounds as it did there")
  paw.undo()
  eq(right.start, 3, "undone")
  -- Trimmed back out past where it was cut: the repeats come back.
  t:clips()[1]:remove()
  paw.frontend.act.trim_clips(right.id, "start", -3, false, false)
  eq(right.start, 0, "dragged out to the start")
  near(right.loop_start, 0, 1e-9, "its repeats from its start")
  local whole = T.read_file(render({ tail = 0, bits = 16 }).path)
  eq(whole == before, true, "and the sound it had")
  -- Slipped with Alt: the pattern turns round inside the clip, and comes
  -- back round after a whole repeat.
  paw.frontend.act.trim_clips(right.id, "start", 1, false, true)
  near(right.loop_start, -1, 1e-9, "a beat round")
  eq(T.read_file(render({ tail = 0, bits = 16 }).path) == before, false, "sounding otherwise")
  paw.frontend.act.trim_clips(right.id, "start", 1, false, true)
  near(right.loop_start, 0, 1e-9, "a whole turn")
  eq(T.read_file(render({ tail = 0, bits = 16 }).path) == before, true, "as it was")
end)

test("a looped, stretched audio clip cut, trimmed, faded and copied plays the same", function()
  local file = phrase_file()
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  paw.stretch.set(clip.id, 2)
  paw.stretch.loop(clip.id, true)
  near(clip.loop_length, 4, 1e-6, "the stretched file's length")
  clip.length = 12
  clip.fade_out = 1
  local info = render({ tail = 0, bits = 16 })
  local before = samples(info, 0, info.frames)
  paw.cursor.set_track(t)
  paw.cursor.set_beat(6)
  paw.commands.exec("clip.split")
  local right = t:clips()[2]
  eq(right.stretch, 2, "the right piece is stretched")
  near(right.loop_start, -2, 1e-6, "and loops from where it was")
  eq(right.fade_out, 1, "and has the fade out")
  local after = samples(render({ tail = 0, bits = 16 }), 0, info.frames)
  -- A cut in the middle of a sound is faded out and in over 3 ms, as any is.
  local cut = 3 * 48000
  for i = 1, #before do
    if math.abs(i - cut) > 150 and before[i] ~= after[i] then
      error("the pieces sound otherwise at frame " .. i .. ": " .. before[i] .. " against " .. after[i])
    end
  end
  -- Copied: the copy plays as the original does.
  local copy = paw.restore_clip(right:snapshot(), t)
  copy.start = 12
  eq(copy.loop and copy.stretch == 2, true, "the copy loops, stretched")
  near(copy.loop_start, right.loop_start, 1e-9, "from the same place")
end)

-- Takes ---------------------------------------------------------------------------------

test("the other takes of a stretched clip are stretched as it is", function()
  local low = tone_file(4, "A3")
  local high = tone_file(4, "E4")
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = low, start = 0 })
  paw.takes.new(clip.id)
  clip.file = high
  paw.stretch.set(clip.id, 1.5)
  local info = render({ tail = 0, bits = 16 })
  near(T.frequency(info, 0.5, 2.5), 329.6, 2, "the second take, stretched, at its pitch")
  paw.takes.select(clip.id, 1)
  eq(clip.stretch, 1.5, "the first take is stretched as much")
  info = render({ tail = 0, bits = 16 })
  near(info.frames / info.sample_rate, 3, 0.01, "as long")
  near(T.frequency(info, 0.5, 2.5), 220, 1.5, "at its pitch")
  local tracks = paw.takes.explode(clip.id)
  eq(tracks[1]:clips()[1].stretch, 1.5, "a take put on a track of its own is stretched as the clip was")
end)

test("the terminal marks a stretched, shifted, following or looped clip in its label", function()
  local file = tone_file(4)
  local clip = paw.add_track({ name = "audio" }):add_clip({ file = file, start = 0 })
  eq(paw.stretch.badge(clip:get()), nil, "nothing on a plain clip")
  paw.stretch.set(clip.id, 1.5)
  clip.pitch = 3
  paw.stretch.follow(clip.id)
  paw.stretch.loop(clip.id, true)
  paw.flush()
  eq(paw.stretch.badge(clip:get()), "stretching… ×1.5 +3st ♩ ↻", "while it is made")
  settled()
  eq(paw.stretch.badge(clip:get()), "×1.5 +3st ♩ ↻", "once it is made")
  paw.opt.ascii = true
  eq(paw.stretch.badge(clip:get()), "x1.5 +3st bpm loop", "in plain characters")
  paw.opt.ascii = false
end)

-- The project file --------------------------------------------------------------------

test("stretch, shift and loops are saved, and a project without them saves as before", function()
  local file = tone_file(4)
  local t = paw.add_track({ name = "audio" })
  local plain = t:add_clip({ file = file, start = 0 })
  local midi = t:add_clip({ start = 4, length = 2, notes = { { pitch = 60, start = 0, length = 1 } } })
  local path = T.scratch .. "/plain.json"
  paw.project.save(path)
  local text = T.read_file(path)
  local saved = paw.json.decode(text)
  for _, track in ipairs(saved.project.tracks) do
    for _, c in ipairs(track.clips) do
      for _, key in ipairs({ "stretch", "pitch", "stretch_mode", "loop", "source_tempo", "loop_length", "loop_start" }) do
        eq(c[key], nil, "no " .. key .. " in a clip without any")
      end
    end
  end
  paw.project.load(path)
  paw.project.save(path)
  eq(T.read_file(path) == text, true, "loaded and saved again, the same bytes")
  t = paw.tracks()[1]
  plain, midi = t:clips()[1], t:clips()[2]
  paw.stretch.set(plain.id, 1.25)
  plain.pitch = 2
  plain.stretch_mode = "tonal"
  paw.stretch.follow(plain.id)
  paw.stretch.loop(midi.id, true, 1)
  paw.project.save(path)
  paw.project.load(path)
  t = paw.tracks()[1]
  plain, midi = t:clips()[1], t:clips()[2]
  eq(plain.stretch, 1.25, "the stretch")
  eq(plain.pitch, 2, "the shift")
  eq(plain.stretch_mode, "tonal", "the mode")
  eq(plain.timebase, "stretch", "the timebase")
  eq(plain.source_tempo, 150, "the tempo")
  eq(midi.loop, true, "the loop")
  eq(midi.loop_length, 1, "its length")
end)

-- The window --------------------------------------------------------------------------

test("in the window an end dragged with Alt and Shift stretches, and the menu fits a clip to the loop", function()
  local file = tone_file(4)
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  paw.frontend.act.trim_clips(clip.id, "end", 2.1, true, true)
  near(clip.length, 6, 1e-6, "the end on the grid")
  near(clip.stretch, 1.5, 1e-9, "the sound stretched to it")
  paw.flush()
  local function shown()
    for _, c in ipairs(paw.frontend.state(-1).clips) do
      if c.id == clip.id then return c end
    end
  end
  eq(shown().name:find("stretching", 1, true) ~= nil, true, "shown as being stretched")
  local key = shown().waveform
  settled()
  eq(shown().name:find("stretching", 1, true), nil, "and then not")
  eq(shown().waveform ~= key, true, "the waveform is fetched again once it is made")
  paw.transport.loop_start, paw.transport.loop_end = 8, 16
  paw.frontend.act.stretch_clip(clip.id, "loop")
  eq(clip.start, 8, "moved to the loop")
  near(clip.length, 8, 1e-6, "over it")
  near(clip.stretch, 2, 1e-9, "twice as long as its file")
  paw.frontend.act.stretch_clip(clip.id, "reset")
  eq(clip.stretch, 1, "reset")
  -- Without Shift, Alt alone still slips.
  local offset = clip.offset
  paw.frontend.act.trim_clips(clip.id, "start", -1, false, true)
  eq(clip.offset > offset, true, "slipped")
end)

-- Comping -----------------------------------------------------------------------------

test("comping a stretched clip keeps every piece stretched, and joins them back", function()
  local low = tone_file(8, "A3")
  local high = tone_file(8, "E4")
  local t = paw.add_track({ name = "vox" })
  local clip = t:add_clip({ file = low, start = 0 })
  paw.takes.new(clip.id)
  clip.file = high
  paw.stretch.set(clip.id, 1.5)
  clip.pitch = 1
  near(clip.length, 12, 1e-6, "twelve beats")
  local act = paw.frontend.act
  eq(act.take_lanes(t.id), true, "the take lanes are shown")
  api.undo_checkpoint()
  eq(act.comp(t.id, 1, 4, 8, false), 1, "take 1 over the middle")
  local clips = t:clips()
  eq(#clips, 3, "three pieces")
  for i, c in ipairs(clips) do
    eq(c.stretch .. " " .. c.pitch, "1.5 1", "piece " .. i .. " is stretched and shifted")
  end
  near(clips[2].offset, 4 / 1.5 * 0.5, 1e-9, "take 1 lined up in its file, in seconds of the file")
  near(clips[3].offset, 8 / 1.5 * 0.5, 1e-9, "and take 2 after it")
  local info = render({ tail = 0, bits = 16 })
  near(T.frequency(info, 2.2, 3.8), 220 * 2 ^ (1 / 12), 2, "the middle at take 1's pitch, shifted")
  near(T.frequency(info, 4.2, 5.8), 329.63 * 2 ^ (1 / 12), 3, "the end at take 2's")
  -- The window draws each take as it would play.
  local rows = paw.frontend.state(-1).clips[1].take_rows
  eq(#rows, 2, "two lanes")
  eq(#paw.frontend.take_preview(clips[1].id, 1, 64) >= 3, true, "a picture of the take that is not playing")
  act.comp(t.id, 2, 0, 12, false)
  clips = t:clips()
  eq(#clips, 1, "one take over all of it: one clip again")
  near(clips[1].length, 12, 1e-6, "as long as before")
  eq(clips[1].stretch, 1.5, "stretched as before")
  -- Pieces stretched otherwise are not joined.
  act.comp(t.id, 1, 4, 8, false)
  t:clips()[2].stretch = 1.25
  act.comp(t.id, 2, 0, 12, false)
  eq(#t:clips() > 1, true, "a piece stretched otherwise stays a piece")
end)

test("comping a looped clip keeps the loop on every piece, and joins pieces that carry it on", function()
  start()
  local t = paw.add_track({ name = "keys" })
  t:add_device("synth", { attack = 0.001, release = 0.01 })
  local clip = t:add_clip({
    start = 0,
    length = 2,
    notes = {
      { pitch = "A3", start = 0, length = 0.5 },
      { pitch = "C4", start = 1, length = 0.5 },
    },
  })
  paw.stretch.loop(clip.id, true)
  clip.length = 8
  paw.takes.new(clip.id)
  clip:set_notes({ { pitch = "E4", start = 0, length = 0.5 }, { pitch = "G4", start = 1, length = 0.5 } })
  local before = T.read_file(render({ tail = 0, bits = 16 }).path)
  local act = paw.frontend.act
  act.take_lanes(t.id)
  eq(act.comp(t.id, 1, 3, 5, false), 1, "take 1 over the middle")
  local clips = t:clips()
  eq(#clips, 3, "three pieces")
  for i, c in ipairs(clips) do
    eq(c.loop, true, "piece " .. i .. " loops")
  end
  near(clips[2].loop_start, -1, 1e-9, "the middle piece a beat into a repeat")
  local flat = paw.frontend.preview(clips[2].id)
  eq(flat[3], 60, "it plays take 1's second note first")
  act.comp(t.id, 2, 3, 5, false)
  eq(#t:clips(), 1, "take 2 back: the pieces carry the loop on, and are one clip again")
  eq(T.read_file(render({ tail = 0, bits = 16 }).path) == before, true, "sounding as before")
end)
