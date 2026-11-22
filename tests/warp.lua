-- Tests of stretched sound made as it plays, warp markers, clips bent along
-- the tempo and formants kept (`paw.stretch`,
-- docs/reference/stretch.md). Loaded by tests/suite.lua with its helpers.
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

--- A sound file rendered at 16 bits from a synth playing `notes` over
--- `beats` at 120 BPM.
local function sound_file(beats, notes)
  start()
  local t = paw.add_track({ name = "source" })
  t:add_device("synth", { attack = 0.001, release = 0.01 })
  t:add_clip({ start = 0, length = beats, notes = notes })
  local info = render({ tail = 0, bits = 16 })
  start()
  return info.path
end

--- The 16-bit samples of a rendered WAV file's left channel, as numbers
--- from -1 to 1.
local function samples(info)
  local data = T.read_file(info.path)
  local at = data:find("data", 1, true) + 8
  local out = {}
  for p = at, #data - 3, 4 do
    local lo, hi = data:byte(p, p + 1)
    local v = lo + hi * 256
    out[#out + 1] = (v >= 32768 and v - 65536 or v) / 32768
  end
  return out
end

--- Where sounds begin in a rendered file, in seconds: a sample above
--- `level` after 30 ms of quiet.
local function onsets(info, level)
  local s, rate = samples(info), info.sample_rate
  local out, quiet = {}, rate
  for i, v in ipairs(s) do
    if math.abs(v) > level then
      if quiet >= rate * 0.03 then out[#out + 1] = (i - 1) / rate end
      quiet = 0
    else
      quiet = quiet + 1
    end
  end
  return out
end

--- Wait until no clip is being stretched any more.
local function settled()
  for _ = 1, 3000 do
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

-- Made as it plays ----------------------------------------------------------------

test("a long stretched clip is heard at once, while its sound is still being made", function()
  -- Two minutes of tone, stretched to four.
  local file = sound_file(240, { { pitch = "A3", start = 0, length = 240 } })
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  paw.stretch.set(clip.id, 2)
  paw.transport.seek(0)
  paw.transport.play()
  local heard
  for _ = 1, 1000 do
    paw.wait(10)
    if t:meter() > 0.05 then
      heard = api.clip_get(clip.id)
      break
    end
  end
  paw.transport.stop()
  eq(heard ~= nil, true, "heard")
  eq(heard.stretching, true, "while it is being made")
  -- The rough preview first, then what is made.
  eq(heard.made < 1, true, "before all of it is made: " .. tostring(heard.made))
  -- The playhead far past what is made: silent there, not broken.
  paw.transport.seek(400)
  paw.transport.play()
  paw.wait(100)
  paw.transport.stop()
  settled()
  eq(clip.stretching, nil, "made in the end")
  paw.transport.seek(400)
  paw.transport.play()
  local level = 0
  for _ = 1, 100 do
    paw.wait(10)
    level = math.max(level, t:meter())
    if level > 0.05 then break end
  end
  paw.transport.stop()
  eq(level > 0.05, true, "and heard there once it is made")
end)

test("a render made while a stretch is being made waits for it, and is the same on any number of threads", function()
  local file = sound_file(16, {
    { pitch = "A3", start = 0, length = 3 },
    { pitch = "E4", start = 4, length = 6 },
    { pitch = "C4", start = 11, length = 4 },
  })
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  paw.stretch.set(clip.id, 1.3)
  clip.pitch = 2
  paw.flush()
  eq(clip.stretching, true, "being made")
  local first = samples(render({ tail = 0, bits = 16, threads = 1 }))
  settled()
  for _, threads in ipairs({ 1, 3 }) do
    local again = samples(render({ tail = 0, bits = 16, threads = threads }))
    eq(#again, #first, threads .. " threads: as long")
    local differ
    for i = 1, #first do
      if first[i] ~= again[i] then
        differ = i
        break
      end
    end
    eq(differ, nil, threads .. " threads: the same samples")
  end
end)

-- Warp markers ----------------------------------------------------------------------

--- Two seconds of A3 and then six of A4 at 120 BPM: the change at beat 2.
local function two_tone_file()
  return sound_file(8, { { pitch = "A3", start = 0, length = 2 }, { pitch = "A4", start = 2, length = 6 } })
end

test("a warp marker pins a moment of the file, and moved stretches the sound on either side", function()
  local file = two_tone_file()
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  clip.stretch_mode = "tonal"
  api.undo_checkpoint()
  local i = paw.stretch.warp_add(clip.id, 2)
  eq(i, 1, "the first marker")
  local m = clip.warp[1]
  near(m.source, 1, 1e-9, "a second into the file")
  near(m.beat, 2, 1e-9, "at beat 2")
  eq(clip.stretching, nil, "nothing moved, nothing to make")
  -- Moved two beats later: the file's first second fills four beats, the
  -- rest of it the four after, and the clip starts and ends where it did,
  -- each pinned with a marker of its own.
  api.undo_checkpoint()
  i = paw.stretch.warp_move(clip.id, 1, 4)
  local w = clip.warp
  eq(#w .. " " .. i, "3 2", "the clip's start and end pinned too")
  near(w[1].beat, 0, 1e-9, "the start where it was")
  near(w[i].beat, 4, 1e-9, "the marker at beat 4")
  near(w[3].beat, 8, 1e-9, "the end where it was")
  near(clip.length, 8, 1e-9, "as long")
  local info = render({ tail = 0, bits = 16 })
  near(info.frames / info.sample_rate, 4, 0.01, "four seconds")
  near(T.frequency(info, 0.2, 1.8), 220, 2, "the low tone over the first four beats")
  near(T.frequency(info, 2.2, 3.8), 440, 4, "the high one over the last four")
  -- Not past a stretch of four on either side.
  api.undo_checkpoint()
  paw.stretch.warp_move(clip.id, i, 7.9)
  eq(clip.warp[i].beat < 7.9, true, "held back: " .. clip.warp[i].beat)
  -- Undone and taken off.
  api.undo_checkpoint()
  paw.undo()
  near(clip.warp[i].beat, 4, 1e-9, "undone, at beat 4 again")
  paw.undo()
  eq(#clip.warp, 1, "and before the move, one marker")
  near(clip.warp[1].beat, 2, 1e-9, "at beat 2")
  paw.stretch.warp_remove(clip.id, 1)
  eq(clip.warp, nil, "none")
  fails(function() paw.stretch.warp_add(clip.id, 12) end, "inside", "a marker outside the clip")
  local midi = t:add_clip({ start = 20, length = 2 })
  fails(function() paw.stretch.warp_add(midi.id, 21) end, "audio", "nor on MIDI")
end)

test("warp markers are saved, copied with the clip, and kept by a cut", function()
  local file = two_tone_file()
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  paw.stretch.warp_move(clip.id, paw.stretch.warp_add(clip.id, 2), 3)
  local path = T.scratch .. "/warped.json"
  paw.project.save(path)
  paw.project.load(path)
  clip = paw.tracks()[1]:clips()[1]
  eq(#clip.warp, 3, "three markers, the clip's ends pinned")
  near(clip.warp[2].beat, 3, 1e-9, "where it was moved")
  local copy = clip:duplicate()
  near(copy.warp[2].beat, copy.start + 3, 1e-9, "the copy's, where they are in it")
  paw.cursor.set_track(paw.tracks()[1])
  paw.cursor.set_beat(5)
  paw.commands.exec("clip.split")
  local left, right = paw.tracks()[1]:clips()[1], paw.tracks()[1]:clips()[2]
  near(left.warp[2].beat, 3, 1e-9, "the left piece's marker stays put")
  near(right.start, 5, 1e-9, "the right piece")
  local info = render({ tail = 0, bits = 16 })
  near(T.frequency(info, 0.1, 1.4), 220, 2, "the low tone still over three beats")
  near(T.frequency(info, 1.6, 3.9), 440, 4, "and the high after")
end)

test("the warp commands and keys put, move, snap and take off markers", function()
  local file = two_tone_file()
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(2)
  paw.keymap.feed("gw")
  eq(#clip.warp, 1, "gw puts one at the cursor")
  near(clip.warp[1].beat, 2, 1e-9, "at beat 2")
  paw.cursor.set_beat(3)
  paw.commands.exec("clip.warp move")
  near(clip.warp[2].beat, 3, 1e-9, "move pulls the nearest to the cursor, the clip's ends pinned")
  paw.commands.exec("clip.warp move 2 2.6")
  near(clip.warp[2].beat, 2.6, 1e-9, "or to a beat")
  paw.commands.exec("clip.warp snap")
  local g = paw.opt.grid
  near(clip.warp[2].beat, math.floor(2.6 / g + 0.5) * g, 1e-9, "onto the grid")
  near(clip.warp[3].beat, 8, 1e-9, "the end's where it was")
  paw.cursor.set_beat(2.4)
  paw.keymap.feed("gW")
  eq(#clip.warp, 2, "gW takes off the nearest: the clip's ends are left")
  paw.commands.exec("clip.warp clear")
  eq(clip.warp, nil, "clear takes off all")
  -- Drawn in the terminal down the clip, on the cell's left edge.
  paw.cmd("view.only")
  local function edges()
    paw.flush()
    local n = 0
    for _ in table.concat(api.ui_snapshot(150, 36), "\n"):gmatch("▏") do
      n = n + 1
    end
    return n
  end
  local before = edges()
  paw.stretch.warp_add(clip.id, 4)
  eq(edges() > before, true, "a line where the marker is")
end)

test(
  "in the window a double click on an audio clip's top band puts a warp marker, its handle drags, its menu takes it off",
  function()
    local file = two_tone_file()
    local t = paw.add_track({ name = "audio" })
    local clip = t:add_clip({ file = file, start = 0 })
    local function shown()
      for _, c in ipairs(paw.frontend.state(-1).clips) do
        if c.id == clip.id then return c end
      end
    end
    eq(#shown().warps, 0, "no markers shown")
    local key = shown().waveform
    paw.frontend.act.warp_add(clip.id, 2.03)
    eq(#clip.warp, 1, "a marker")
    near(shown().warps[1], 2.03, 1e-9, "shown where it was put, from the clip's start")
    paw.frontend.act.warp_move(clip.id, 1, 3.1, false)
    near(clip.warp[2].beat, 3, 1e-9, "dragged, onto the grid, the clip's ends pinned")
    eq(#shown().warps, 3, "all three shown")
    eq(shown().waveform ~= key, true, "the waveform drawn again")
    paw.frontend.act.warp_move(clip.id, 2, 3.1, true)
    near(clip.warp[2].beat, 3.1, 1e-9, "with Shift, off it")
    paw.frontend.act.warp_remove(clip.id, 2)
    eq(#clip.warp, 2, "taken off: the ends' are left")
    paw.frontend.act.warp_add(clip.id, 40)
    eq(#clip.warp, 2, "outside the clip: refused, not raised")
  end
)

-- Bent along the tempo ----------------------------------------------------------------

test("a clip following the tempo is bent along a ramp inside it, each beat on its beat", function()
  -- A short note on each beat of eight.
  local notes = {}
  for k = 0, 7 do
    notes[#notes + 1] = { pitch = "A4", start = k, length = 0.1 }
  end
  local file = sound_file(8, notes)
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  clip.stretch_mode = "percussive"
  paw.stretch.follow(clip.id)
  -- From 120 BPM down to 80 over the clip.
  paw.tempo.set(0, 120, { ramp = true })
  paw.tempo.set(8, 80)
  near(clip.length, 8, 1e-9, "still eight beats")
  eq(clip.bent, true, "bent")
  local info = render({ tail = 0, bits = 16 })
  local got = onsets(info, 0.05)
  eq(#got, 8, "eight notes: " .. table.concat(got, " "))
  local worst, even = 0, 0
  local total = paw.tempo.seconds_between(0, 8)
  for k = 0, 7 do
    worst = math.max(worst, math.abs(got[k + 1] - paw.tempo.seconds_between(0, k)))
    even = math.max(even, math.abs(total * k / 8 - paw.tempo.seconds_between(0, k)))
  end
  eq(worst < 0.006, true, "each note on its beat, the worst " .. worst * 1000 .. " ms off")
  eq(even > 0.05, true, "where evenly they would be " .. even * 1000 .. " ms off")
  -- Without the ramp it is stretched evenly, as before.
  paw.tempo.set(0, 120, { ramp = false })
  eq(clip.bent, nil, "even again")
end)

-- Formants -----------------------------------------------------------------------------

test("a shift can keep the formants, saved with the clip", function()
  local file = sound_file(4, { { pitch = "A3", start = 0, length = 4 } })
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ file = file, start = 0 })
  paw.cursor.set_track(t)
  paw.cursor.set_beat(1)
  clip.pitch = 5
  paw.commands.exec("clip.formants on")
  eq(clip.formants, true, "on")
  local info = render({ tail = 0, bits = 16 })
  near(T.frequency(info, 0.3, 1.7), 220 * 2 ^ (5 / 12), 3, "the pitch moves all the same")
  local path = T.scratch .. "/formants.json"
  paw.project.save(path)
  paw.project.load(path)
  eq(paw.tracks()[1]:clips()[1].formants, true, "saved")
  paw.cursor.set_track(paw.tracks()[1])
  paw.commands.exec("clip.formants")
  eq(paw.tracks()[1]:clips()[1].formants, nil, "turned over")
end)
