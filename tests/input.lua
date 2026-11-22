-- Input and recording tests.
local T = ...
local test, eq, near, fails, fresh, render = T.test, T.eq, T.near, T.fails, T.fresh, T.render
local until_, next_block, scratch = T.until_, T.next_block, T.scratch
local paw = require("paw")
local api = paw.api

-- The null backend can generate input: channel n carries a sine at n times the
-- given frequency.

local function with_input(fn)
  api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 } })
  local ok, err = xpcall(fn, debug.traceback)
  api.engine_restart({ backend = "null" })
  if not ok then error(err, 0) end
end

--- Peak and frequency (from rising zero crossings) of the left channel of a
--- 16-bit WAV file written by `paw.render`, between two times in seconds.
local function pitch_and_peak(info, from, to)
  local file = assert(io.open(info.path, "rb"))
  local data = file:read("*a")
  file:close()
  local at = data:find("data", 1, true) + 8
  local first, last = math.floor(from * info.sample_rate), math.floor(to * info.sample_rate)
  local peak, crossings, prev = 0, 0, 0
  for frame = first, last - 1 do
    local lo, hi = data:byte(at + frame * 4, at + frame * 4 + 1)
    if not hi then break end
    local v = lo + hi * 256
    if v >= 32768 then v = v - 65536 end
    if prev < 0 and v >= 0 then crossings = crossings + 1 end
    peak, prev = math.max(peak, math.abs(v) / 32768), v
  end
  return peak, crossings / ((last - first) / info.sample_rate)
end

local level = 10 ^ (-12 / 20) -- the test input's peak

test("input is heard through the track's devices when armed or monitored", function()
  with_input(function()
    fresh()
    local e = api.engine_get()
    eq(e.input_channels .. " " .. e.input_device, "2 test signal", "the engine reports its input")
    local t = paw.add_track({ name = "guitar" })
    t.input = 1
    eq(t.input, "1", "inputs read back as text")
    next_block(10)
    eq(select(1, t:meter()), 0, "not heard while neither armed nor monitored")
    -- The meters fall slowly: wait until each settles at its new level.
    local function settles(want, what, side)
      until_(function() return math.abs(select(side or 1, t:meter()) - want) < 0.01 end, what)
    end
    t.monitor = true
    settles(level, "monitoring to reach the meter at the input's level")
    t:add_device("gain", { gain = -6 })
    settles(level / 2, "the input to go through the devices")
    t.input = "1/2"
    settles(level / 2, "a pair: left")
    settles(level / 2, "a pair: right", 2)
    t.monitor = false
    t.armed = true
    paw.flush()
    next_block(10)
    near(select(1, t:meter()), level / 2, 0.01, "armed tracks are heard")
    t.armed = false
    until_(function() return select(1, t:meter()) < 0.005 end, "a disarmed track to be silent")
    fails(function() t.input = "1/3" end, "1/3", "a pair must be neighbours")
    fails(function() paw.master.input = "1" end, "master", "the master has no input")
  end)
end)

test("recording the input makes a clip where recording began", function()
  with_input(function()
    fresh()
    paw.project.save(scratch .. "/rec.json")
    local mic = paw.add_track({ name = "mic" })
    mic.input, mic.armed = "2", true
    local idle = paw.add_track({ name = "idle" })
    idle.input = "1"
    local added = 0
    local handle = paw.on("clip.added", function() added = added + 1 end)
    paw.transport.seek(4)
    api.undo_checkpoint()
    paw.transport.record()
    eq(paw.transport.recording, true, "record mode")
    -- Takes are counted over the session: the number is the next one.
    eq(type(paw.transport.take), "number", "a take is under way")
    api.sleep(1000) -- real time is the point: a take of about a second
    T.stop()
    local stopped = paw.transport.position
    paw.flush()
    paw.off(handle)
    eq(paw.transport.take, nil, "the take is over")
    eq(added, 1, "one clip.added event")
    eq(#idle:clips(), 0, "an unarmed track records nothing")
    local clips = mic:clips()
    eq(#clips, 1, "the armed track has a clip")
    local c = clips[1]:get()
    eq(c.kind, "audio", "kind")
    eq(c.start, 4, "it starts where recording began")
    near(c.start + c.length, stopped, 0.03, "it ends where recording stopped")
    eq(c.file:sub(1, #scratch + 7), scratch .. "/media/", "the file is beside the project")

    paw.transport.loop_enabled = false
    local info = render({ start = c.start, ["end"] = c.start + c.length, tail = 0, bits = 16 })
    local peak, freq = pitch_and_peak(info, 0.05, info.seconds - 0.05)
    near(peak, level, 0.01, "the recording has the input's level")
    near(freq, 880, 5, "and its pitch: input 2 carries twice the frequency")

    eq(paw.undo(), true, "undo")
    eq(#mic:clips(), 0, "undo removes the take")
    eq(mic.armed, true, "and nothing else")
    paw.redo()
    eq(#mic:clips(), 1, "redo brings it back")
  end)
end)

test("recordings of an unsaved project move beside it when it is saved", function()
  with_input(function()
    fresh()
    local t = paw.add_track({ name = "draft" })
    t.input, t.armed = "1", true
    paw.transport.record()
    api.sleep(300) -- real time is the point: a short take
    T.stop()
    local before = t:clips()[1].file
    eq(before:find("/paw/recordings/", 1, true) ~= nil, true, "unsaved takes go to the data directory, got " .. before)
    paw.project.save(scratch .. "/later.json")
    local after = t:clips()[1].file
    eq(after, scratch .. "/media/" .. before:match("[^/]+$"), "saving brings the take beside the project")
    eq(io.open(after, "rb") ~= nil, true, "the file is there")
    os.remove(before)
    near(render({ tail = 0 }).peak, level, 0.01, "and still plays")
  end)
end)

test("MIDI input plays armed tracks and records into a clip", function()
  with_input(function()
    fresh()
    paw.project.save(scratch .. "/midi.json")
    local keys = paw.add_track({ name = "keys" })
    keys:add_device("synth", { attack = 0.001, release = 0.01 })
    keys.armed = true
    local other = paw.add_track({ name = "other" })
    other:add_device("synth")
    local mic = paw.add_track({ name = "mic" })
    mic.input, mic.armed = "1", true
    paw.flush()

    paw.midi.note_on("A3", 100)
    until_(function() return select(1, keys:meter()) > 0.01 end, "an armed track to play the note")
    eq(select(1, other:meter()), 0, "an unarmed one does not")
    keys.armed = false
    until_(function() return select(1, keys:meter()) < 0.005 end, "disarming to release held notes")
    keys.armed = true

    paw.transport.seek(8)
    api.undo_checkpoint()
    paw.transport.record()
    -- Real time is the point: notes played at times that are read back.
    api.sleep(250)
    local c4 = paw.transport.position
    paw.midi.note_on("C4", 90)
    api.sleep(500)
    local c4_off = paw.transport.position
    paw.midi.note_off("C4")
    api.sleep(100)
    local e4 = paw.transport.position
    paw.midi.inject({ type = "note_on", pitch = 64, velocity = 80, channel = 2 })
    api.sleep(250)
    T.stop()
    local stopped = paw.transport.position

    eq(#other:clips(), 0, "the unarmed track records nothing")
    local clip = keys:clips()[1]
    eq(clip.kind .. "@" .. clip.start, "midi@8", "a MIDI clip where recording began")
    near(clip.start + clip.length, stopped, 0.03, "ending where recording stopped")
    local notes = clip:notes()
    eq(#notes, 2, "two notes")
    eq(notes[1].pitch .. "/" .. notes[1].velocity, "60/90", "first note")
    near(notes[1].start, c4 - 8, 0.05, "first note's position")
    near(notes[1].length, c4_off - c4, 0.05, "first note's length")
    eq(notes[2].pitch .. "/" .. notes[2].velocity, "64/80", "second note")
    near(notes[2].start, e4 - 8, 0.05, "second note's position")
    near(notes[2].start + notes[2].length, clip.length, 0.001, "a note held at stop ends there")
    eq(#mic:clips() .. " " .. mic:clips()[1].kind, "1 audio", "the audio of the same take, and no notes there")
    local info = render({ start = clip.start + notes[1].start, ["end"] = clip.start + notes[1].start + 0.5, tail = 0 })
    eq(info.peak > 0.05, true, "the recorded notes play")

    paw.undo()
    eq(#keys:clips() + #mic:clips(), 0, "one undo step removes the whole take")
    fails(function() paw.midi.inject({ type = "note_on" }) end, "pitch", "a note needs a pitch")
  end)
end)

test("the status line shows recording", function()
  fresh()
  local function status()
    for _, line in ipairs(api.ui_snapshot(100, 30)) do
      if line:find("bpm", 1, true) then return line end
    end
  end
  eq(status():find("rec", 1, true), nil, "the rec flag shows only when it is on")
  paw.transport.recording = true
  eq(status():find("rec", 1, true) ~= nil, true, "and then it is there")
  paw.transport.play()
  eq(status():find("●", 1, true) ~= nil, true, "the transport shows it is recording")
  T.stop()
  paw.transport.recording = false
  eq(status():find("●", 1, true), nil, "and stops showing it")
end)
