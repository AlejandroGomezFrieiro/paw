-- Tests of the engine and the core API that came after the first suite:
-- fades, sends before the fader, delay compensation.
local T = ...
local test, eq, near, fresh, render = T.test, T.eq, T.near, T.fresh, T.render
local paw = require("paw")
local api = paw.api
local until_, until_beat, next_block = T.until_, T.until_beat, T.next_block

local write_wav, samples = T.write_wav, T.samples

--- A file of `seconds` of a steady level, and one of silence with a single
--- sample at `at` seconds.
local function steady(name, seconds, level)
  local s = {}
  for i = 1, math.floor(seconds * 48000) do
    s[i] = level
  end
  return write_wav(T.scratch .. "/" .. name .. ".wav", s)
end
local function impulse(name, seconds, at, level)
  local s = {}
  for i = 1, math.floor(seconds * 48000) do
    s[i] = 0
  end
  s[math.floor(at * 48000) + 1] = level
  return write_wav(T.scratch .. "/" .. name .. ".wav", s)
end

test("audio clips fade in and out, and a cut edge does not click", function()
  fresh()
  local file = steady("steady", 4, 0.5)
  local t = paw.add_track()
  -- At 120 bpm a beat is half a second, 24000 frames.
  local clip = t:add_clip({ file = file, start = 0, length = 4 })
  local s = samples(render({ tail = 0, bits = 16 }))
  near(s[1], 0.5, 0.001, "a clip that starts where its file does starts at full level")
  clip.fade_in, clip.fade_out = 1, 2
  eq(clip.fade_in .. "/" .. clip.fade_out, "1/2", "fades read back")
  s = samples(render({ tail = 0, bits = 16 }))
  near(s[1], 0, 0.001, "a fade in starts from silence")
  near(s[12001], 0.5 * math.sin(math.pi / 4), 0.002, "halfway it is at half power")
  near(s[30000], 0.5, 0.001, "then full level")
  near(s[72001], 0.5 * math.sin(math.pi / 4), 0.002, "halfway through the fade out")
  near(s[95990], 0, 0.002, "and silence at the end")
  T.fails(function() clip.fade_in = -1 end, "fade", "a negative fade")
  local midi = t:add_clip({ start = 8, length = 4 })
  T.fails(function() midi.fade_in = 1 end, "fade_in", "MIDI clips do not fade")
  midi:remove()

  -- A clip that starts or ends inside its file is a cut, and gets a few
  -- milliseconds of fade whether asked for or not.
  clip.fade_in, clip.fade_out = 0, 0
  clip.offset, clip.length = 0.5, 2
  s = samples(render({ tail = 0, bits = 16 }))
  near(s[1], 0, 0.01, "a cut edge starts from silence")
  near(s[73], 0.5 * math.sin(math.pi / 4), 0.02, "is halfway up after a millisecond and a half")
  near(s[200], 0.5, 0.001, "and at full level after three")
  near(s[47990], 0, 0.06, "and comes down at the other cut")

  -- Fades survive saving, and cutting a clip keeps each with its own edge.
  clip.offset, clip.length, clip.fade_in, clip.fade_out = 0, 4, 1, 1
  local path = paw.project.save(T.scratch .. "/fades.json")
  fresh()
  paw.project.load(path)
  t = paw.tracks()[1]
  eq(t:clips()[1].fade_out, 1, "saved and loaded")
  paw.cursor.set_track(t)
  paw.cursor.set_beat(2)
  paw.ui.focus("arrange")
  paw.keymap.feed("<Esc>S")
  local a, b = t:clips()[1], t:clips()[2]
  eq(
    a.fade_in .. "," .. a.fade_out .. " " .. b.fade_in .. "," .. b.fade_out,
    "1,0 0,1",
    "a split keeps the fades at the outer edges"
  )

  paw.commands.exec("clip.fade 0")
  paw.cursor.set_beat(0)
  paw.commands.exec("clip.crossfade 1")
  a, b = t:clips()[1], t:clips()[2]
  eq(a.length .. " " .. a.fade_out .. " " .. b.fade_in, "3 1 1", "a crossfade runs the first clip on under the second")
  s = samples(render({ tail = 0, bits = 16 }))
  near(s[60001], 0.5 * 2 * math.sin(math.pi / 4), 0.003, "both are at half power in the middle of it")
  near(s[40000], 0.5, 0.001, "and alone before it")
end)

test("a send can be taken before the fader", function()
  fresh()
  local file = steady("level", 2, 0.5)
  local source = paw.add_track({ name = "Source" })
  local bus = paw.add_track({ name = "Bus" })
  source:add_clip({ file = file, start = 0, length = 4 })
  source:send(bus, -6)
  eq(source.sends[1].pre, nil, "sends follow the fader unless told otherwise")
  near(samples(render({ tail = 0, bits = 16 }))[1000], 0.5 + 0.25, 0.002, "the track and its send")
  source.volume = -120
  near(samples(render({ tail = 0, bits = 16 }))[1000], 0, 0.001, "an ordinary send goes down with the fader")
  source.sends = { { target = bus.id, level = -6, pre = true } }
  eq(source.sends[1].pre, true, "pre reads back")
  near(samples(render({ tail = 0, bits = 16 }))[1000], 0.25, 0.002, "one from before the fader does not")
  source.pan = 1
  near(samples(render({ tail = 0, bits = 16 }))[1000], 0.25, 0.002, "nor with the pan")
  source.mute = true
  near(samples(render({ tail = 0, bits = 16 }))[1000], 0, 0.001, "but muting the track silences it")
  source.mute = false
  local path = paw.project.save(T.scratch .. "/pre.json")
  fresh()
  paw.project.load(path)
  eq(paw.tracks()[1].sends[1].pre, true, "saved and loaded")
  local copy = paw.tracks()[1]:duplicate()
  eq(copy.sends[1].pre, true, "and kept by a copy of the track")
end)

test("the limiter holds its ceiling and reports how far it looks ahead", function()
  fresh()
  local t = paw.add_track()
  t:add_clip({ file = steady("loud", 2, 0.9), start = 0, length = 4 })
  near(render({ tail = 0.1 }).peak, 0.9, 0.001, "loud to begin with")
  paw.master:add_device("limiter", { ceiling = -12 })
  local peak = render({ tail = 0.1 }).peak
  eq(peak <= 10 ^ (-12 / 20) + 0.0005, true, "nothing above the ceiling: " .. peak)
  eq(peak > 10 ^ (-12 / 20) * 0.9, true, "and close under it")
  near(api.engine_get().latency, 5, 0.01, "the engine says how far behind the output is")
end)

test("tracks whose devices look ahead are lined up with the rest", function()
  fresh()
  local file = impulse("click", 1, 0.25, 0.2)
  local a = paw.add_track({ name = "Late" })
  local b = paw.add_track({ name = "Plain" })
  a:add_clip({ file = file, start = 0, length = 2 })
  b:add_clip({ file = file, start = 0, length = 2 })
  local function peaks()
    local s, out = samples(render({ tail = 0, bits = 16 })), {}
    for i, v in ipairs(s) do
      if math.abs(v) > 0.05 then out[#out + 1] = string.format("%d:%.2f", i - 1, v) end
    end
    return table.concat(out, " ")
  end
  eq(peaks(), "12000:0.40", "two copies of a click land on one sample")
  local limiter = a:add_device("limiter", { ceiling = 0 })
  eq(peaks(), "12000:0.40", "and still do when one track is 5 ms late: the other waits")
  limiter.bypass = true
  eq(peaks(), "12000:0.40", "a bypassed device holds nothing back")
  limiter.bypass = false
  -- Through a bus that is late as well, and a send that is not.
  local bus = paw.add_track({ name = "Bus" })
  bus:add_device("limiter", { ceiling = 0 })
  a.output = bus
  b:send(bus, 0)
  eq(peaks(), "12000:0.60", "every path arrives together: both tracks, and the send into the bus")
  paw.master:add_device("limiter", { ceiling = 0 })
  eq(peaks(), "12000:0.60", "a late master moves nothing either")
  paw.flush()
  near(api.engine_get().latency, 15, 0.01, "three devices in a row are 15 ms")
end)

--- A track with the built-in synth set to a plain sine, so that its pitch
--- can be read from the render.
local function sine_track()
  local t = paw.add_track({ name = "Sine" })
  t:add_device("synth", { wave = 0, attack = 0.001, release = 0.02, sustain = 1 })
  return t
end

test("MIDI clips hold controller moves, and the synth follows the wheel and the pedal", function()
  fresh()
  local t = sine_track()
  local clip = t:add_clip({ start = 0, length = 8, notes = { { pitch = "A3", start = 0, length = 4 } } })
  near(T.frequency(render({ tail = 0, bits = 16 }), 0.2, 1.8), 220, 1.5, "A3 as written")
  clip:set_controls({ { start = 2, type = "bend", value = 1 } })
  eq(clip.control_count, 1, "the clip counts its controller moves")
  local info = render({ tail = 0, bits = 16 })
  near(T.frequency(info, 0.2, 0.9), 220, 2, "before the wheel moves")
  near(T.frequency(info, 1.2, 1.9), 220 * 2 ^ (2 / 12), 2, "bent up two semitones after it")
  near(
    T.frequency(render({ start = 3, tail = 0, bits = 16 }), 0.1, 0.4),
    220 * 2 ^ (2 / 12),
    3,
    "playing from later still starts bent"
  )

  -- The sustain pedal holds a short note until it comes up.
  clip:set_notes({ { pitch = "A3", start = 0, length = 0.5 } })
  clip:set_controls({})
  info = render({ tail = 0, bits = 16 })
  local quiet = T.channel_peaks(info, 1.0, 1.9)
  eq(quiet < 0.001, true, "a short note is over after a beat")
  clip:set_controls({
    { start = 0, type = "cc", number = 64, value = 1 },
    { start = 4, type = "cc", number = 64, value = 0 },
  })
  info = render({ tail = 0, bits = 16 })
  eq(T.channel_peaks(info, 1.0, 1.9) > 0.05, true, "with the pedal down it sounds on")
  eq(T.channel_peaks(info, 2.5, 3.9) < 0.001, true, "and stops when the pedal comes up")

  -- What a clip takes, and what it refuses.
  clip:set_controls({
    { start = 1, type = "pressure", value = 0.5 },
    { start = 0, type = "program", program = 12, bank = 258 },
    { start = 0.5, type = "registered", bank = 0, index = 6, value = 0.25 },
    { start = 2, type = "bend", key = "A3", value = 0.01 },
    { start = 3, type = "cc", number = 74, key = 57, value = 0.123456789 },
  })
  local moves = clip:controls()
  eq(#moves .. moves[1].type .. moves[2].type, "5programregistered", "kept in the order they happen")
  eq(moves[1].program .. "/" .. moves[1].bank, "12/258", "a program with its bank")
  eq(moves[4].key, 57, "a move can belong to one note")
  eq(moves[5].value, 0.123456789, "values are fractions, not seven-bit steps")
  T.fails(function() clip:set_controls({ { start = 0, type = "bend", value = 2 } }) end, "range", "a bend past the end")
  T.fails(
    function() clip:set_controls({ { start = 0, type = "cc", number = 200, value = 0 } }) end,
    "127",
    "a controller that does not exist"
  )
  T.fails(function() clip:set_controls({ { start = 0, type = "wobble", value = 0 } }) end, "wobble", "an unknown kind")
  T.fails(
    function() clip:set_controls({ { start = 0, type = "program", program = 1, key = 60 } }) end,
    "channel",
    "a program for one note"
  )

  -- They survive undo, saving, copying and cutting.
  api.undo_checkpoint()
  clip:set_controls({})
  api.undo_checkpoint()
  paw.undo()
  eq(#clip:controls(), 5, "undo brings them back")
  local path = paw.project.save(T.scratch .. "/controls.json")
  fresh()
  paw.project.load(path)
  t = paw.tracks()[1]
  clip = t:clips()[1]
  eq(clip:controls()[5].value, 0.123456789, "saved and loaded exactly")
  local copy = clip:duplicate()
  eq(#copy:controls(), 5, "a copy has them")
  copy:remove()
  paw.cursor.set_track(t)
  paw.cursor.set_beat(1.5)
  paw.ui.focus("arrange")
  paw.keymap.feed("<Esc>S")
  local left, right = t:clips()[1], t:clips()[2]
  eq(#left:controls() .. " " .. #right:controls(), "3 2", "a split gives each half the moves in it")
  eq(right:controls()[1].start, 0.5, "counted from its own start")
  paw.cursor.set_beat(0)
  paw.keymap.feed("J")
  eq(#t:clips() .. " " .. #t:clips()[1]:controls(), "1 5", "and a join puts them together again")
end)

test("a note has controllers of its own, as in MIDI 2.0", function()
  fresh()
  local t = sine_track()
  local clip = t:add_clip({
    start = 0,
    length = 8,
    notes = {
      { pitch = "A3", start = 0, length = 2 },
      { pitch = "A3", start = 4, length = 2 },
    },
  })
  -- One semitone of the 48 a note's own bend spans.
  clip:set_controls({ { start = 0, type = "bend", key = "A3", value = 1 / 48 } })
  local info = render({ tail = 0, bits = 16 })
  near(T.frequency(info, 0.2, 0.9), 220 * 2 ^ (1 / 12), 2, "the note is bent by its own controller")
  near(T.frequency(info, 2.2, 2.9), 220, 2, "the next note on the same key starts unbent")
  clip:set_controls({ { start = 0, type = "bend", key = "C5", value = 1 / 48 } })
  near(T.frequency(render({ tail = 0, bits = 16 }), 0.2, 0.9), 220, 2, "a bend for another key leaves this one alone")
end)

test("MIDI input reaches scripts, at the resolution it came in", function()
  fresh()
  local seen = {}
  local handler = paw.on("midi.in", function(event) seen[#seen + 1] = event end)
  paw.midi.inject({ type = "note_on", pitch = "C4", velocity = 100, channel = 2 })
  paw.midi.inject({ type = "cc", number = 1, value = 0.5 })
  paw.midi.inject({ type = "bend", value = -0.25, channel = 3 })
  paw.midi.inject({ type = "pressure", key = "E4", value = 0.75 })
  paw.flush()
  eq(#seen, 4, "one event per message")
  eq(seen[1].type .. seen[1].pitch .. "/" .. seen[1].velocity .. "/" .. seen[1].channel, "note_on60/100/2", "a note")
  eq(seen[2].type .. seen[2].number .. "/" .. seen[2].value, "cc1/0.5", "a controller")
  eq(seen[3].type .. seen[3].value .. "/" .. seen[3].channel, "bend-0.25/3", "the wheel")
  eq(seen[4].type .. seen[4].key .. "/" .. seen[4].value, "pressure64/0.75", "one note's pressure")

  -- Universal MIDI Packets, both ways.
  local words = paw.midi.ump({ type = "cc", number = 74, value = 1, channel = 2 })
  eq(string.format("%08x %08x", words[1], words[2]), "40b14a00 ffffffff", "an event as a MIDI 2.0 packet")
  words = paw.midi.ump({ type = "bend", key = "C4", value = 0 })
  eq(string.format("%08x %08x", words[1], words[2]), "40603c00 80000000", "a note's own bend, at rest")
  seen = {}
  eq(paw.midi.inject_ump({ 0x40b14a00, 0x12345678 }), true, "a MIDI 2.0 packet is taken")
  eq(paw.midi.inject_ump({ 0x20903c60 }), true, "and a MIDI 1.0 one")
  eq(paw.midi.inject_ump({ 0x10000000 }), false, "what is not a channel message is not")
  paw.flush()
  near(seen[1].value, 0x12345678 / 0xffffffff, 1e-12, "all 32 bits of the value arrive")
  eq(seen[1].number .. "/" .. seen[1].channel, "74/2", "with its controller and channel")
  eq(seen[2].type .. seen[2].pitch, "note_on60", "the MIDI 1.0 note")
  paw.off(handler)
end)

test("recording keeps controller moves, and can be moved earlier to line up", function()
  fresh()
  api.engine_restart({ backend = "null" })
  local keys = paw.add_track({ name = "keys" })
  keys:add_device("synth")
  keys.armed = true
  paw.flush()
  paw.transport.record_offset = 0
  api.undo_checkpoint()
  paw.transport.record()
  until_beat(0.4)
  paw.midi.note_on("C4", 90)
  paw.midi.inject({ type = "cc", number = 1, value = 0.5 })
  until_beat(0.7)
  paw.midi.inject({ type = "bend", value = 0.5 })
  paw.midi.inject({ type = "pressure", key = "C4", value = 0.25 })
  paw.midi.note_off("C4")
  until_beat(0.9)
  T.stop()
  local clip = keys:clips()[1]
  local moves = clip:controls()
  eq(#moves, 3, "three controller moves in the take")
  eq(moves[1].type .. moves[1].number .. "/" .. moves[1].value, "cc1/0.5", "the wheel, where it was moved to")
  eq(moves[3].key, 60, "and the note's own pressure")
  near(moves[1].start, clip:notes()[1].start, 0.05, "beside the note they were played with")
  local first = clip:notes()[1].start

  -- With an offset, what is recorded lands that much earlier.
  paw.undo()
  paw.transport.record_offset = 100
  eq(paw.transport.record_offset, 100, "the offset reads back")
  paw.transport.seek(0)
  paw.transport.record()
  until_beat(0.4)
  paw.midi.note_on("C4", 90)
  until_beat(0.7)
  paw.midi.note_off("C4")
  T.stop()
  local shifted = keys:clips()[1]:notes()[1].start
  -- 100 ms at 120 bpm is 0.2 beats; the two takes were played at the same
  -- beat, a few hundredths of a beat apart.
  near(first - shifted, 0.2, 0.08, "100 ms earlier")
  paw.transport.record_offset = 0
end)

test("unsaved work is copied aside, and offered again after a session that ended badly", function()
  fresh()
  local autosave = paw.autosave
  local dir = T.scratch .. "/recovery"
  autosave.dir = dir
  local t = paw.add_track({ name = "Idea" })
  t:add_clip({ start = 0, length = 4, name = "riff" })
  api.undo_checkpoint()
  eq(#api.read_dir(dir), 0, "nothing is copied while it is turned off")
  paw.opt.autosave = 0.05
  local file = autosave.file()
  T.advance_until(function() return io.open(file) end, "a changed project to be copied after a while", 60000)
  eq(api.project_get().path, nil, "without becoming the project's file")
  eq(paw.project.modified, true, "or counting as saved")
  local before = T.read_file(file)
  T.advance(150) -- three times the autosave interval
  eq(T.read_file(file), before, "and not copied again until it changes")
  eq(#autosave.left_behind(), 0, "a running session's copy is not offered")

  -- As if that session had died: its copy names a process that is gone.
  local orphan = dir .. "/orphan.json"
  T.write_file(orphan, (before:gsub('"pid":%d+', '"pid":999999999')))
  local list = autosave.left_behind()
  eq(#list .. list[1].name, "1untitled", "what it left is found")
  paw.project.new()
  paw.commands.exec("recover 1")
  eq(paw.tracks()[1].name .. "/" .. paw.tracks()[1]:clips()[1].name, "Idea/riff", "and opens as it was")
  eq(paw.project.modified, true, "still unsaved")
  eq(io.open(orphan), nil, "the copy is used up")

  -- Saving makes the copy unnecessary.
  paw.tracks()[1].volume = -3
  api.undo_checkpoint()
  local mine = autosave.file()
  T.advance_until(function()
    local f = io.open(mine)
    if f then f:close() end
    return f ~= nil
  end, "the project to be copied again", 60000)
  -- An open question: a save at once after the copy was made has left
  -- the copy behind. The test waits as it did before.
  T.advance(150)
  paw.project.save(T.scratch .. "/kept.json")
  paw.flush()
  eq(io.open(mine), nil, "and removed once saved")
  paw.opt.autosave = 0

  -- Quitting is refused while there is unsaved work.
  paw.tracks()[1].volume = -6
  api.undo_checkpoint()
  local before = paw.ui.messages[#paw.ui.messages]
  paw.commands.exec("quit")
  local said = paw.ui.messages[#paw.ui.messages]
  eq(said ~= before and said.text:find("unsaved", 1, true) ~= nil, true, "quit says why it will not")
end)

test("scripts can wait while timers fire", function()
  fresh()
  local fired = 0
  local every = paw.every(10, function() fired = fired + 1 end)
  local once = false
  paw.defer(function() once = true end, 30)
  T.settle()
  eq(fired .. tostring(once), "0false", "a timer waits for its time")
  T.advance_until(function() return fired >= 4 and once end, "waiting to let the timers run", 1000)
  paw.cancel(every)
end)

test("a script can start more timers than Lua has stack slots, and the API still answers", function()
  fresh()
  -- Each timer used to hold its function in a slot of a stack with room
  -- for about 8000: past that, every call that made a list failed.
  local handles = {}
  for i = 1, 9000 do
    handles[i] = paw.defer(function() end, 60000)
  end
  local t = paw.add_track({ name = "T" })
  for i = 1, 3 do
    t:add_clip({ start = i * 4, length = 4 })
  end
  paw.flush()
  eq(#api.clip_list(t.id), 3, "a list is made")
  for _, h in ipairs(handles) do
    paw.cancel(h)
  end
end)

test("clip events name each clip added, changed, moved to another track and removed, also among many", function()
  fresh()
  local a, b = paw.add_track({ name = "A" }), paw.add_track({ name = "B" })
  local clips = {}
  for i = 1, 300 do
    clips[i] = a:add_clip({ start = i * 4, length = 4 })
  end
  paw.flush()
  local seen = {}
  local handle = paw.on("clip.*", function(e, name) seen[#seen + 1] = name:sub(6) .. ":" .. e.id .. "@" .. e.track end)
  local function step(fn)
    seen = {}
    fn()
    paw.flush()
    table.sort(seen)
    return table.concat(seen, " ")
  end
  eq(
    step(function() clips[150].start = clips[150].start + 1 end),
    "changed:" .. clips[150].id .. "@" .. a.id,
    "moved in time"
  )
  local new
  eq(
    step(function() new = a:add_clip({ start = 2, length = 1 }) end),
    "added:" .. new.id .. "@" .. a.id,
    "added among many"
  )
  eq(step(function() api.clip_remove(clips[7].id) end), "removed:" .. clips[7].id .. "@" .. a.id, "removed among many")
  eq(
    step(function() api.clip_set(clips[9].id, "track", b.id) end),
    "changed:" .. clips[9].id .. "@" .. b.id,
    "to another track"
  )
  local both = { "removed:" .. clips[1].id .. "@" .. a.id, "removed:" .. clips[2].id .. "@" .. a.id }
  table.sort(both)
  eq(
    step(function()
      api.clip_remove(clips[1].id)
      api.clip_remove(clips[2].id)
    end),
    table.concat(both, " "),
    "two removed"
  )
  paw.off(handle)
end)

test("api.track_get and api.project_get with a key give that entry of the table", function()
  fresh()
  local t = paw.add_track({ name = "Keys", volume = -6, pan = 0.5 })
  t:add_clip({ start = 0, length = 4 })
  api.track_set(t.id, "meta", { kind = "x" })
  local whole = api.track_get(t.id)
  for key, value in pairs(whole) do
    eq(paw.inspect(api.track_get(t.id, key)), paw.inspect(value), key)
  end
  eq(api.track_get(t.id, "nothing"), nil, "a key that is not there")
  eq(pcall(api.track_get, 9999, "volume"), false, "a track that is not there")
  eq(t.volume, -6, "a track's field reads its entry")
  local project = api.project_get()
  for key, value in pairs(project) do
    eq(paw.inspect(api.project_get(key)), paw.inspect(value), "project " .. key)
  end
  eq(paw.project.edits, project.edits, "paw.project reads one entry")
end)

test("edits in a script that never waits leave no timers behind", function()
  fresh()
  local t = paw.add_track({ name = "T" })
  paw.flush()
  api.undo_checkpoint()
  local function count()
    local n = 0
    for _ in pairs(paw.timers) do
      n = n + 1
    end
    return n
  end
  local before = count()
  for i = 1, 50 do
    t:add_clip({ start = i * 4, length = 4 })
    paw.flush()
    api.undo_checkpoint()
  end
  eq(count() - before <= 1, true, "timers left by 50 edits: " .. (count() - before))
end)

test("an LV2 plugin that follows the song's tempo is told it", function()
  local kind
  for _, info in ipairs(paw.device_types()) do
    if info.format == "lv2" and info.kind:find("slap_delay_mono", 1, true) then kind = info.kind end
  end
  if not kind then return "skipped: test plugins not found" end
  fresh()
  local t = paw.add_track()
  t:add_clip({ file = impulse("tick", 4, 0.25, 0.5), start = 0, length = 4 })
  -- One echo a quarter of a bar after the sound, and nothing of the sound itself.
  local delay = t:add_device(kind, { dm0 = 3, df0 = 0.25, ds0 = 4, dry = 0, wet = 1 })
  local function echo()
    local s, best, at = samples(render({ ["end"] = 8, tail = 0, bits = 16 })), 0, 0
    for i, v in ipairs(s) do
      if math.abs(v) > best then
        best, at = math.abs(v), i - 1
      end
    end
    return at / 48000 - 0.25
  end
  delay:set("sync", 0)
  paw.project.tempo = 120
  local own = echo()
  eq(own > 0.05, true, "there is an echo: " .. own)
  paw.project.tempo = 60
  near(echo(), own, 0.005, "left to itself it keeps its own tempo")
  delay:set("sync", 1)
  local slow = echo()
  paw.project.tempo = 120
  local fast = echo()
  near(slow / fast, 2, 0.05, "following the song, half the tempo is twice the delay")
end)

test("a render can be one track, dithered, or brought to a level", function()
  fresh()
  local a = paw.add_track({ name = "Left" })
  local b = paw.add_track({ name = "Right/odd" })
  a:add_clip({ file = steady("a", 2, 0.25), start = 0, length = 4 })
  b:add_clip({ file = steady("b", 2, 0.5), start = 0, length = 4 })
  near(render({ tail = 0 }).peak, 0.75, 0.001, "the mix is both")
  near(render({ tail = 0, tracks = { a.id } }).peak, 0.25, 0.001, "a render of one track is that track")
  T.fails(function() render({ tracks = { 999 } }) end, "999", "a track that is not there")
  eq(a.solo or b.solo, false, "and nothing in the project is changed by it")

  local function stems(words)
    paw.export.run(paw.export.plan(words .. " each=track tail=0 bits=16 wait=true"))
    local files = {}
    for i, r in ipairs(paw.export.last().results) do
      files[i] = r.path
    end
    return files
  end
  local files = stems(T.scratch .. "/stems/")
  eq(#files, 2, "one stem per track")
  eq(files[2]:match("[^/]+$"), "Right_odd.wav", "named after it, safely")
  local sum = samples({ path = files[1] })[1000] + samples({ path = files[2] })[1000]
  near(sum, 0.75, 0.001, "the stems add up to the mix")
  b.mute = true
  eq(#stems(T.scratch .. "/stems2/"), 1, "muted tracks are left out")
  b.mute = false

  local info = render({ tail = 0, normalize = -6, bits = 16 })
  near(info.peak, 10 ^ (-6 / 20), 0.001, "normalizing brings the peak to a level")
  near(samples(info)[1000], 10 ^ (-6 / 20), 0.001, "in the file")
  near(info.gain, 20 * math.log10(10 ^ (-6 / 20) / 0.75), 0.01, "and says by how much")
  T.fails(function() render({ normalize = 3 }) end, "normalize", "above full scale")
  T.fails(function() render({ gain = -6, normalize = -1 }) end, "gain is a fixed level", "gain and normalize")

  -- Dither: a level between two 16-bit steps comes out as one of them
  -- without it, and as a mix of both, the same every time, with it.
  a:clips()[1]:remove()
  b:clips()[1].gain = -60
  local function steps(opts)
    local seen, s = {}, samples(render(paw.util.merge({ tail = 0, bits = 16 }, opts)))
    for i = 1000, 3000 do
      seen[s[i]] = true
    end
    local n = 0
    for _ in pairs(seen) do
      n = n + 1
    end
    return n, s
  end
  eq(steps({}), 1, "without dither every sample of a steady level is the same")
  local n, first = steps({ dither = true })
  eq(n > 1, true, "with it they vary")
  local _, second = steps({ dither = true })
  eq(first[2000] == second[2000] and first[2500] == second[2500], true, "the same way every time")
end)

test("a render listens at the point of the signal that tap names", function()
  fresh()
  -- Each device and fader on the way is -6 dB: a factor of g.
  local g = 10 ^ (-6 / 20)
  local group = paw.add_track({ name = "Group" })
  group:add_device("gain", { gain = -6 })
  group.volume = -6
  local member = paw.add_track({ name = "Member" })
  member:add_clip({ file = steady("tap-member", 2, 0.4), start = 0, length = 4 })
  member:add_device("gain", { gain = -6 })
  member.volume = -6
  member.output = group.id
  local ret = paw.add_track({ name = "Return" })
  local other = paw.add_track({ name = "Other" })
  other:add_clip({ file = steady("tap-other", 2, 0.2), start = 0, length = 4 })
  other:send(ret, -6)
  paw.master.volume = -6
  paw.flush()
  local function level(opts)
    opts.tail, opts.bits = 0, 16
    return samples(render(opts))[1000]
  end

  local member_at = { pre = 0.4 * g, post = 0.4 * g ^ 2, groups = 0.4 * g ^ 4, master = 0.4 * g ^ 5 }
  for tap, want in pairs(member_at) do
    near(level({ tracks = { member.id }, tap = tap }), want, 0.001, "the member at tap=" .. tap)
  end
  member.mute = true
  near(level({ tracks = { member.id }, tap = "pre" }), 0.4 * g, 0.001, "tap=pre is before the mute")
  near(level({ tracks = { member.id }, tap = "post" }), 0, 0.001, "tap=post is after it")
  member.mute = false

  for _, tap in ipairs({ "groups", "master" }) do
    local stems = level({ tracks = { group.id }, tap = tap }) + level({ tracks = { other.id }, tap = tap })
    near(stems, level({ tap = tap }), 0.001, "the stems at tap=" .. tap .. " add up to the mix")
  end
  near(level({}), (0.4 * g ^ 4 + 0.2 + 0.2 * g) * g, 0.001, "the mix is through the master")

  T.fails(function() render({ tap = "post" }) end, "name the tracks", "tap=post of the mix")
  T.fails(function() render({ tap = "master", master = false }) end, "disagree", "two words that disagree")
end)

test("moving a fader while the song plays writes automation", function()
  fresh()
  api.engine_restart({ backend = "null" })
  local t = T.tone("tone", 32)
  paw.transport.write = true
  eq(paw.transport.write, true, "write mode reads back")
  t.volume = -3
  paw.flush()
  eq(t:lane("volume"), nil, "nothing is written while stopped")
  paw.transport.seek(0)
  paw.transport.play()
  until_beat(0.3)
  eq(t:lane("volume"), nil, "or before anything is moved")
  local first = paw.transport.position
  t.volume = -12
  until_beat(first + 0.6)
  local second = paw.transport.position
  t.volume = -24
  until_beat(second + 0.4)
  T.stop()
  local last = paw.transport.position
  paw.flush()
  local lane = t:lane("volume")
  eq(lane ~= nil, true, "a lane was made")
  near(lane:value_at(0), -3, 0.001, "before the move the song keeps the level it had")
  near(lane:value_at(first + 0.1), -12, 0.001, "then it is where the fader was moved to")
  near(lane:value_at(second - 0.05), -12, 0.001, "and held there")
  near(lane:value_at(last), -24, 0.001, "until it was moved again")
  eq(#lane:points() <= 8, true, "a held value is two points, not one every tick: " .. #lane:points())
  -- A second pass writes over what the first left.
  paw.transport.seek(0)
  paw.transport.play()
  until_beat(0.1)
  t.volume = 0
  until_beat(second + 0.4)
  T.stop()
  paw.flush()
  near(lane:value_at(second), 0, 0.001, "the new pass replaces the old moves it passes")
  paw.transport.write = false
  paw.transport.play()
  local from = paw.transport.position
  until_beat(from + 0.1)
  local points = #lane:points()
  t.volume = -6
  until_beat(from + 0.3)
  T.stop()
  eq(#lane:points(), points, "with write off, a move writes nothing")
end)

test("a track is bounced to audio, and takes MIDI messages by hand", function()
  fresh()
  api.engine_restart({ backend = "null" })
  local t = sine_track()
  t:add_clip({ start = 0, length = 4, notes = { { pitch = "A3", start = 0, length = 4 } } })
  local before = render({ tail = 0 }).peak
  paw.cursor.set_track(t)
  paw.commands.exec("bounce")
  local bounced = paw.cursor.track()
  eq(bounced.name .. " " .. tostring(t.mute), "Sine (bounced) true", "a new track beside a muted original")
  local clip = bounced:clips()[1]
  eq(clip.kind .. " " .. clip.start, "audio 0", "holding the sound as audio")
  near(render({ tail = 0 }).peak, before, 0.01, "which plays as the track did")
  os.remove(clip.file)
  -- The same from a script, and the render is announced like any other.
  local heard = 0
  local handler = paw.on("render.before", function() heard = heard + 1 end)
  local again = paw.bounce(t, { name = "Sine (again)", tail = 0 })
  paw.off(handler)
  eq(again.name, "Sine (again)", "paw.bounce names the new track as asked")
  eq(heard, 1, "and renders through paw.render")
  os.remove(again:clips()[1].file)
  again:remove()

  -- The wheel moved by hand bends what is sounding.
  t.mute = false
  bounced:remove()
  t:note_on("A3", 100)
  until_(function() return T.level(t) > 0.01 end, "a note played by hand to sound")
  t:midi({ type = "bend", value = 1 })
  t:midi({ type = "cc", number = 64, value = 1 })
  t:note_off("A3")
  next_block(40) -- longer than the synth's release
  eq(T.level(t) > 0.01, true, "and the pedal, pressed by hand, holds it after the key is let go")
  t:midi({ type = "cc", number = 64, value = 0 })
  -- The meter falls slowly after the sound has gone.
  until_(function() return T.level(t) < 0.005 end, "the sound to stop when the pedal comes up")
  T.fails(function() t:midi({ type = "bend", value = 3 }) end, "range", "a bend out of range")
end, { live = "the release of the synth and the fall of the meter take real time" })

for _, format in ipairs({ "clap", "vst3", "lv2" }) do
  test(format .. " instruments follow the pitch wheel", function()
    local kind
    for _, info in ipairs(paw.device_types()) do
      if info.format == format and info.name == "Surge XT" then kind = info.kind end
    end
    if not kind then return "skipped: test plugins not found" end
    fresh()
    local t = paw.add_track({ name = "surge" })
    t:add_device(kind)
    local clip = t:add_clip({ start = 0, length = 4, notes = { { pitch = "A3", start = 0, length = 4 } } })
    local plain = T.frequency(render({ tail = 0, bits = 16 }), 0.5, 1.5)
    eq(plain > 100, true, "a note sounds: " .. plain)
    clip:set_controls({ { start = 0, type = "bend", value = 1 } })
    local bent = T.frequency(render({ tail = 0, bits = 16 }), 0.5, 1.5)
    -- Surge bends two semitones at the top of the wheel.
    near(bent / plain, 2 ^ (2 / 12), 0.02, "the wheel at its top raises the pitch")
    if format == "clap" then
      clip:set_controls({ { start = 0.5, type = "bend", key = "A3", value = 1 / 48 } })
      local own = T.frequency(render({ tail = 0, bits = 16 }), 0.5, 1.5)
      near(own / plain, 2 ^ (1 / 12), 0.02, "and a note's own bend reaches it as a note expression")
    end
  end)
end

test("one note is added, changed and removed without the others crossing over", function()
  fresh()
  local t = paw.add_track({ name = "notes" })
  local clip = t:add_clip({
    start = 0,
    length = 8,
    notes = {
      { pitch = "C4", start = 0, length = 1 },
      { pitch = "E4", start = 1, length = 1, meta = { lyric = "la" } },
      { pitch = "G4", start = 2, length = 2 },
    },
  })
  api.undo_checkpoint()

  eq(
    clip:add_note({ pitch = "D4", start = 1, length = 0.5, velocity = 90 }),
    2,
    "a new note goes where it starts, lower pitches first"
  )
  eq(clip:add_note({ pitch = "A4", start = 6, length = 1 }), 5, "or at the end")
  local notes = clip:notes()
  eq(#notes, 5, "the others are still there")
  eq(notes[2].pitch, 62, "the new one in its place")
  eq(notes[3].meta.lyric, "la", "and what a note carries stays with it")

  eq(clip:set_note(3, { velocity = 50 }), 3, "a change that does not move a note leaves its place")
  eq(clip:notes()[3].velocity, 50, "and is made")
  eq(clip:notes()[3].meta.lyric, "la", "fields left out stay as they were")
  eq(clip:set_note(1, { start = 5, pitch = "C5" }), 4, "a note that starts later moves back in the list")
  notes = clip:notes()
  eq(notes[4].start, 5, "to where it starts now")
  eq(notes[4].pitch, 72, "with a pitch given by name")
  eq(notes[1].pitch, 62, "and the others move up")

  local note, index = clip:note_at("G4", 3.5)
  eq(note and note.start, 2, "the note sounding at a beat is found")
  eq(index, 3, "with its place")
  eq(clip:note_at("G4", 4), nil, "up to, not including, where it ends")
  eq(clip:note_at("F4", 3), nil, "and nothing where there is none")

  local some, at = clip:notes({ from = 1, to = 3 })
  eq(#some, 3, "a range gives the notes sounding within it")
  eq(table.concat(at, " "), "1 2 3", "and their places")
  some, at = clip:notes({ low = "G4", high = "A4" })
  eq(table.concat(at, " "), "3 5", "pitches bound it too")
  eq(select("#", api.clip_notes(clip.id)), 1, "the whole list comes alone")

  clip:remove_note(2)
  eq(#clip:notes(), 4, "one note is removed")
  eq(clip:notes()[2].pitch, 67, "by its place")

  clip:edit_notes({
    set = { { index = 1, start = 7 }, { index = 2, velocity = 10 } },
    remove = { 4 },
    add = { { pitch = "C3", start = 0, length = 1 } },
  })
  notes = clip:notes()
  eq(#notes, 4, "several changes are one edit")
  eq(notes[1].pitch, 48, "the added note first")
  eq(notes[2].velocity, 10, "the changed one")
  eq(notes[4].start, 7, "the moved one last, by the place it had before the call")
  eq(notes[3].pitch, 72, "and the one not named untouched")

  T.fails(function() clip:set_note(9, { start = 0 }) end, "no note 9", "a place past the end")
  T.fails(function() clip:set_note(0, { start = 0 }) end, "from 1", "a place before the start")
  T.fails(function() clip:set_note(1, { length = 0 }) end, "length", "a note of no length")
  T.fails(function() clip:set_note(1, { colour = "red" }) end, "colour", "a field notes do not have")
  T.fails(function() clip:edit_notes({ remove = { 9 } }) end, "no note 9", "removing what is not there")
  eq(#clip:notes(), 4, "a refused edit changes nothing")

  api.undo_checkpoint()
  paw.undo()
  eq(#clip:notes(), 3, "and the lot is one undo step per turn")

  -- What the engine plays follows.
  fresh()
  local s = T.tone("a", 4)
  local c = s:clips()[1]
  c:set_note(1, { length = 1 })
  local info = render({ tail = 0, bits = 16 })
  eq(T.channel_peaks(info, 0.2, 0.4) > 0.05, true, "the note still sounds")
  eq(T.channel_peaks(info, 1.2, 1.9) < 0.001, true, "and ends where it was told to")
end)

test("tracks are processed on several threads, and sound the same", function()
  fresh()
  -- Sixteen voices into two buses, one of them through a late send from
  -- before the fader, so that there is something to get wrong.
  local a, b = paw.add_track({ name = "bus a" }), paw.add_track({ name = "bus b" })
  a:add_device("delay", { time = 110, mix = 0.4 })
  b:add_device("limiter")
  for i = 1, 16 do
    local t = paw.add_track({ name = "voice " .. i, pan = (i - 8) / 10 })
    t:add_device("synth", { wave = i % 4, attack = 0.002, release = 0.05 })
    if i % 2 == 0 then t:add_device("delay", { time = 50 * i, mix = 0.3 }) end
    local notes = {}
    for step = 0, 15 do
      notes[#notes + 1] = { pitch = 40 + (i * 5 + step * 3) % 36, start = step * 0.5, length = 0.4 }
    end
    t:add_clip({ start = 0, length = 8, notes = notes })
    t.output = i % 3 == 0 and a.id or i % 3 == 1 and b.id or nil
    if i % 4 == 0 then t:send(a, -6) end
    if i % 5 == 0 then t:send(b, -3, { pre = true }) end
    t:automate("volume"):set_points({ { 0, -9 }, { 8, -3 } })
  end
  paw.flush()
  local alone = render({ tail = 0.5, threads = 1 })
  eq(alone.threads, 1, "a render on one thread says so")
  eq(alone.peak > 0.05, true, "something sounds")
  local want = T.read_file(alone.path)
  for _, threads in ipairs({ 2, 5, 16 }) do
    local info = render({ tail = 0.5, threads = threads })
    eq(info.threads, threads, "a render on " .. threads .. " threads says so")
    eq(T.read_file(info.path) == want, true, "and writes the same file, byte for byte")
  end

  -- The live engine takes a number too, and 0 leaves it to the machine.
  local before = paw.opt.threads
  paw.opt.threads = 3
  until_(function() return api.engine_get().threads == 3 end, "the engine to run on as many threads as asked for")
  paw.transport.play()
  next_block(10)
  paw.opt.threads = 1
  until_(function() return api.engine_get().threads == 1 end, "the number to change while the song plays")
  eq(type(api.engine_get().shared_groups), "number", "the engine counts the groups it shared out")
  T.stop()
  paw.opt.threads = before
  next_block(5)
  eq(api.engine_get().threads >= 1, true, "and goes back")
  T.fails(function() api.engine_set_threads(1000) end, "too many", "an absurd number")
end)

test("devices at rest sleep through silence, and sound the same", function()
  fresh()
  -- Two bars of notes, eight of nothing, two bars again: the reverb's and
  -- the delay's tails die away in between.
  local t = paw.add_track({ name = "keys" })
  t:add_device("synth", { release = 0.1 })
  t:add_device("delay", { time = 250, mix = 0.4, feedback = 0.4 })
  t:add_device("reverb", { decay = 1, mix = 50 })
  for _, at in ipairs({ 0, 40 }) do
    local notes = {}
    for step = 0, 15 do
      notes[#notes + 1] = { pitch = 48 + step % 12, start = step * 0.5, length = 0.4 }
    end
    t:add_clip({ start = at, length = 8, notes = notes })
  end
  paw.flush()
  local awake = render({ tail = 1, sleep = false })
  eq(awake.peak > 0.05, true, "something sounds")
  eq(awake.device_sleeps, 0, "with sleep off, no device sleeps")
  local asleep = render({ tail = 1, sleep = true })
  eq(asleep.device_sleeps > asleep.device_runs / 2, true, "through the silence the devices sleep")
  eq(T.read_file(asleep.path) == T.read_file(awake.path), true, "and the file is the same, byte for byte")

  -- The live engine follows the option.
  eq(api.engine_get().device_sleep, true, "devices sleep unless told not to")
  paw.opt.device_sleep = false
  T.settle() -- the option's handler tells the engine
  next_block(2)
  eq(api.engine_get().device_sleep, false, "the option turns it off")
  local before = api.engine_get().device_sleeps
  next_block(20)
  eq(api.engine_get().device_sleeps, before, "and nothing sleeps then")
  paw.opt.device_sleep = true
  until_(
    function() return api.engine_get().device_sleeps > before end,
    "stopped and silent, the devices to sleep again"
  )
end)

-- Choosing devices and inputs ---------------------------------------------------
-- The null backend offers its test input as a device, and test MIDI ports.

local test_level = 10 ^ (-12 / 20) -- the test input's peak

local function with_test_input(fn, midi)
  api.engine_restart({ backend = "null", test_input = { frequency = 440, level = -12, channels = 2 }, test_midi = midi })
  local ok, err = xpcall(fn, debug.traceback)
  api.engine_restart({ backend = "null" })
  if not ok then error(err, 0) end
end

test("the audio devices are listed, and a name that matches none is refused", function()
  with_test_input(function()
    fresh()
    local list = paw.audio.devices()
    eq(#list.inputs, 1, "the test input is the one input device")
    eq(list.inputs[1].name .. " " .. list.inputs[1].channels, "test signal 2", "with its name and channels")
    eq(list.input, "test signal", "and it is the one open")
    local ok, err = pcall(paw.audio.use, { input = "Steinberg" })
    eq(ok, false, "an input that is not there is refused")
    eq(tostring(err):find("test signal", 1, true) ~= nil, true, "saying what there is: " .. tostring(err))
    eq(api.engine_get().input_device, "test signal", "and nothing changes")
    paw.audio.use({ input = "test", buffer = 256 })
    eq(api.engine_get().buffer_size, 256, "a part of the name and a block size are taken")
    eq(api.engine_get().input_channels, 2, "the input is open again")
    eq(paw.audio.summary(), "null · 48 kHz", "the engine in a few words")
  end)
end)

test("each input channel is metered whether or not a track hears it", function()
  with_test_input(function()
    fresh()
    local t = paw.add_track({ name = "guitar" })
    t.input = "2"
    paw.flush()
    until_(function() return math.abs(paw.audio.levels()[1] - test_level) < 0.01 end, "channel 1 to arrive")
    local levels = paw.audio.levels()
    eq(#levels, 2, "a level for each channel of the device")
    near(levels[1], test_level, 0.01, "channel 1 arrives")
    near(paw.audio.level(t:get()), test_level, 0.01, "the track's input level, not armed and not monitored")
    eq(T.level(t), 0, "while the track itself is silent")
    local state = paw.frontend.state(-1)
    near(state.inputs[1], test_level, 0.01, "the frontend is told it with the meters")
    eq(state.tracks[1].input_label, "test signal · 2", "and what the track takes in, in words")
    eq(state.inputs[#state.inputs], 0, "the master has no input")
  end)
end)

test("a track takes MIDI from one port and channel, playing and recording", function()
  with_test_input(function()
    fresh()
    local ports = {}
    for i, p in ipairs(paw.midi.inputs()) do
      ports[i] = p.name
    end
    eq(table.concat(ports, ", "), "Keys A, Keys B", "the ports to choose from")
    local a, any = paw.add_track({ name = "a" }), paw.add_track({ name = "any" })
    for _, t in ipairs({ a, any }) do
      t:add_device("synth")
      t.armed = true
    end
    a.midi_input = { port = "Keys A", channel = 2 }
    eq(a.midi_input.port .. "/" .. a.midi_input.channel, "Keys A/2", "the choice reads back")
    paw.flush()
    paw.midi.inject({ type = "note_on", pitch = 60, velocity = 100, port = "Keys B", channel = 2 })
    until_(function() return T.level(any) > 0.01 end, "a track that takes every port to hear another port")
    eq(T.level(a), 0, "another port is not heard")
    paw.midi.inject({ type = "note_off", pitch = 60, port = "Keys B", channel = 2 })
    paw.midi.inject({ type = "note_on", pitch = 62, velocity = 100, port = "Keys A", channel = 1 })
    next_block(10)
    eq(T.level(a), 0, "nor another channel")
    paw.midi.inject({ type = "note_off", pitch = 62, port = "Keys A", channel = 1 })
    paw.midi.inject({ type = "note_on", pitch = 64, velocity = 100, port = "Keys A", channel = 2 })
    until_(function() return T.level(a) > 0.01 end, "the port and channel chosen to be heard")
    paw.midi.inject({ type = "note_off", pitch = 64, port = "Keys A", channel = 2 })

    paw.transport.record()
    until_beat(paw.transport.position + 0.2)
    for _, n in ipairs({ { 65, "Keys A", 2 }, { 67, "Keys B", 2 }, { 69, "Keys A", 3 } }) do
      paw.midi.inject({ type = "note_on", pitch = n[1], velocity = 100, port = n[2], channel = n[3] })
      next_block(3)
      paw.midi.inject({ type = "note_off", pitch = n[1], port = n[2], channel = n[3] })
    end
    next_block(3)
    T.stop()
    local pitches = function(t)
      local out = {}
      for i, n in ipairs(t:clips()[1]:notes()) do
        out[i] = n.pitch
      end
      return table.concat(out, " ")
    end
    eq(pitches(a), "65", "a take keeps only what the track hears")
    eq(pitches(any), "65 67 69", "and one from every port keeps everything")

    local path = T.scratch .. "/midi-input.json"
    paw.project.save(path)
    paw.project.load(path)
    local loaded = paw.track("a")
    eq(loaded.midi_input.port .. "/" .. loaded.midi_input.channel, "Keys A/2", "saved with the project by port name")
    loaded.midi_input = nil
    eq(loaded.midi_input, nil, "and back to every port")
  end, { "Keys A", "Keys B" })
end)

test("a whole first session: input, monitoring, an effect, a take that plays back through it", function()
  with_test_input(function()
    fresh()
    local gtr = paw.add_track({ name = "Guitar" })
    -- Chosen the way a menu or the picker chooses it.
    local choice
    for _, c in ipairs(paw.audio.choices(gtr)) do
      if c.label == "test signal · 1/2" then choice = c end
    end
    eq(choice ~= nil, true, "the pair is offered by name")
    paw.audio.choose(gtr, choice)
    eq(gtr.input, "1/2", "and taken")
    gtr.monitor = true
    gtr:add_device("gain", { gain = -6 })
    paw.flush()
    -- The meter falls slowly from where it was.
    until_(
      function() return math.abs(T.level(gtr) - test_level / 2) < 0.01 end,
      "the input to be heard through the effect"
    )
    gtr.armed = true
    paw.transport.record()
    until_beat(paw.transport.position + 1.6)
    T.stop()
    paw.flush()
    local clips = gtr:clips()
    eq(#clips, 1, "the take is a clip")
    local c = clips[1]:get()
    eq(c.kind, "audio", "of audio")
    -- Played back, offline: no input reaches a render, only the clip.
    local info = render({ start = c.start, ["end"] = c.start + c.length, tail = 0, bits = 16 })
    local file = assert(io.open(info.path, "rb"))
    local data = file:read("*a")
    file:close()
    local at, peak = data:find("data", 1, true) + 8, 0
    for frame = math.floor(info.sample_rate * 0.05), math.floor(info.sample_rate * (info.seconds - 0.05)) do
      local lo, hi = data:byte(at + frame * 4, at + frame * 4 + 1)
      if not hi then break end
      local v = lo + hi * 256
      if v >= 32768 then v = v - 65536 end
      peak = math.max(peak, math.abs(v) / 32768)
    end
    near(peak, test_level / 2, 0.01, "the take plays back through the effect")
  end)
end)

test("old projects keep their inputs", function()
  fresh()
  local path = T.scratch .. "/old-input.json"
  local t = paw.add_track({ name = "old" })
  t.input = "1/2"
  paw.project.save(path)
  local text = T.read_file(path)
  eq(text:find('"midi_input"', 1, true), nil, "nothing is written for MIDI from everywhere")
  paw.project.load(path)
  eq(paw.track("old").input, "1/2", "a pair as text loads as it was")
end)

test("an edit answered by a handler is one undo step, and undo is not answered again", function()
  fresh()
  local track = paw.add_track({ name = "Keys" })
  local clip = track:add_clip({ start = 0, length = 4 })
  local marker = track:add_clip({ start = 16, length = 1 })
  paw.flush()
  api.undo_checkpoint()
  local seen = {}
  -- A handler that keeps the marker one bar after the clip, as an extension
  -- keeps what belongs to a clip with it.
  local handler = paw.on("clip.changed", function(event)
    seen[#seen + 1] = event
    if event.restored or event.id ~= clip.id then return end
    marker.start = clip.start + 16
  end)
  clip.start = 8
  paw.flush()
  api.undo_checkpoint()
  eq(marker.start, 24, "the handler answered the edit")
  eq(seen[1].restored, nil, "an edit is not marked restored")
  seen = {}
  paw.undo()
  paw.flush()
  eq(clip.start .. "/" .. marker.start, "0/16", "one undo takes back the edit and the answer")
  eq(#seen > 0, true, "undo reports the change")
  for _, event in ipairs(seen) do
    eq(event.restored, true, "and marks it restored")
  end
  seen = {}
  paw.redo()
  paw.flush()
  eq(clip.start .. "/" .. marker.start, "8/24", "redo brings both back")
  eq(seen[1].restored, true, "redo is restored too")
  paw.off(handler)
end)

test("a device's meta goes with it when its track is copied", function()
  fresh()
  local track = paw.add_track({ name = "Lead" })
  local synth = track:add_device("synth")
  api.device_set(synth.id, "meta", { mine = { colour = "red" } })
  local copy = track:duplicate()
  local meta = api.device_get(copy:devices()[1].id).meta
  eq(meta.mine and meta.mine.colour, "red", "the copy's device keeps what an extension kept with it")
end)

test("a MIDI port of the program's own is one more input for a track to take", function()
  fresh()
  T.fails(function() paw.midi.open_port("") end, "name", "a port with no name")
  paw.midi.open_port("Guitar to MIDI")
  paw.midi.open_port("Guitar to MIDI")
  local own = {}
  for _, p in ipairs(paw.midi.inputs()) do
    if p.own then own[#own + 1] = p.name .. (p.open and " open" or " closed") end
  end
  eq(table.concat(own, ", "), "Guitar to MIDI open", "it is listed once among the inputs, as our own")
  local track = paw.add_track({ name = "Pad" })
  track:add_device("synth")
  local offered
  for _, choice in ipairs(paw.audio.choices(track.id)) do
    if choice.group == "midi" and choice.label == "Guitar to MIDI" then offered = choice end
  end
  eq(offered ~= nil, true, "and offered where a track's input is chosen")
  paw.audio.choose(track.id, offered.value)
  eq(track.midi_input.port, "Guitar to MIDI", "choosing it there is choosing the port by name")
  track.armed = true
  paw.flush()
  paw.midi.inject({ type = "note_on", pitch = 60, velocity = 100 })
  next_block(10)
  eq(T.level(track), 0, "what other ports send is not heard")
  paw.midi.inject({ type = "note_off", pitch = 60 })
  paw.midi.inject({ type = "note_on", pitch = 64, velocity = 100, port = "Guitar to MIDI" })
  until_(function() return T.level(track) > 0.01 end, "what arrives at the port to be heard")
  paw.midi.inject({ type = "note_off", pitch = 64, port = "Guitar to MIDI" })
  eq(paw.midi.close_port("Guitar to MIDI"), true, "the port is taken away")
  eq(paw.midi.close_port("Guitar to MIDI"), false, "once")
  for _, p in ipairs(paw.midi.inputs()) do
    eq(p.own, false, "and no longer listed")
  end
end)

test("JSON goes to text and back, and a helper process is asked to finish", function()
  local text = paw.json.encode({ name = "Guitar", gain = 1.5, on = true, split = { { pitch = 52, channel = 2 } } })
  local back = paw.json.decode(text)
  eq(
    back.name .. " " .. back.gain .. " " .. tostring(back.on) .. " " .. back.split[1].pitch,
    "Guitar 1.5 true 52",
    "a table survives the trip"
  )
  eq(paw.json.encode({ a = 1 }, true):find("\n") ~= nil, true, "pretty text is on several lines")
  local value, why = paw.json.decode("{ not json")
  eq(value == nil and type(why) == "string", true, "what is not JSON gives nil and the reason")

  -- A helper that would run for a minute is asked to finish, and does.
  local proc = api.proc_spawn({ "sleep", "60" }, {})
  eq(api.proc_status(proc).running, true, "the helper runs")
  api.proc_stop(proc)
  until_(function() return not api.proc_status(proc).running end, "the helper to finish when asked")
  api.proc_kill(proc)
  T.fails(function() api.proc_stop(proc) end, "no process", "a process that was forgotten")
end)

test("a sound file is brought in on a track of its own, from a command, a path or a list of files", function()
  fresh()
  -- Something to import: two seconds of a tone, rendered.
  local source = paw.add_track({ name = "tone" })
  source:add_device("synth")
  source:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 4 } } })
  os.execute("mkdir -p '" .. T.scratch .. "/sounds/more'")
  local file = T.scratch .. "/sounds/My take.wav"
  paw.render(file, { ["end"] = 4, tail = 0 })
  fresh()
  eq(
    paw.is_audio_file("a/b/Take.MP3") and paw.is_audio_file("x.flac") and not paw.is_audio_file("song.json"),
    true,
    "sound files are told by their ending"
  )

  paw.cursor.set_beat(8)
  paw.cmd("import", { file })
  local track = paw.tracks()[1]
  local clip = track:clips()[1]
  eq(
    track.name .. " " .. clip.kind .. " " .. clip.start,
    "My take audio 8",
    "the file is a clip on a new track named after it, at the cursor"
  )
  near(clip.length, 4, 0.05, "as long as it sounds")
  eq(paw.cursor.track_id(), track.id, "and the cursor is on the track")
  eq(render({ tail = 0 }).peak > 0.01, true, "it plays")
  local before = #paw.tracks()
  paw.cmd("import", { T.scratch .. "/sounds/nothing.wav" })
  eq(#paw.tracks(), before, "a file that is not there leaves no empty track behind")

  paw.cmd("import", { "tests/fixtures/tone-stereo-44k.mp3" })
  eq(
    paw.tracks()[#paw.tracks()].name .. " " .. paw.tracks()[#paw.tracks()]:clips()[1].kind,
    "tone-stereo-44k audio",
    "an mp3 comes in the same way"
  )

  -- From the command line a sound file starts the project.
  fresh()
  paw.open(file)
  eq(paw.tracks()[1]:clips()[1].start, 0, "opened as a file, it starts at the beginning")

  -- The list of files: directories first, only sound files, Enter walks in.
  fresh()
  local other = io.open(T.scratch .. "/sounds/notes.txt", "w")
  other:write("x")
  other:close()
  paw.cmd("import", {})
  eq(paw.ui.float ~= nil, true, "with no path the command opens the list")
  paw.keymap.feed("<Esc>")
  local chosen
  paw.pick.file({ dir = T.scratch .. "/sounds", extensions = { "wav" }, on_choose = function(path) chosen = path end })
  local lines = table.concat(api.ui_snapshot(100, 30), "\n")
  eq(
    lines:find("more/", 1, true) ~= nil and lines:find("My take.wav", 1, true) ~= nil,
    true,
    "directories and sound files are listed"
  )
  eq(lines:find("notes.txt", 1, true), nil, "other files are not")
  paw.keymap.feed("My<CR>")
  eq(chosen, file, "choosing a file gives its path")
end)

test("tracks are grouped: members sound through the group, stand under it, and fold away", function()
  fresh()
  local names = { "Drums", "Violins", "Violas", "Cellos", "Bass" }
  local t = {}
  for i, name in ipairs(names) do
    t[i] = paw.add_track({ name = name })
    t[i]:add_device("synth")
    t[i]:add_clip({ start = 0, length = 2, notes = { { pitch = 48 + i, start = 0, length = 2 } } })
  end
  local groups = paw.groups
  local function order()
    local out = {}
    for i, track in ipairs(paw.tracks()) do
      out[i] = string.rep(">", groups.depth(track.id)) .. track.name
    end
    return table.concat(out, " ")
  end
  local function rows()
    local out = {}
    for i, id in ipairs(groups.rows()) do
      out[i] = api.track_get(id).name
    end
    return table.concat(out, " ")
  end
  local alone = render({ tail = 0.2 }).peak

  local strings = groups.make({ t[2], t[4] }, "Strings")
  eq(
    order(),
    "Drums Strings >Violins >Cellos Violas Bass",
    "a group stands above its members, which come together under it"
  )
  eq(t[2].output .. " " .. t[4].output, strings.id .. " " .. strings.id, "the members sound through the group")
  groups.add(t[3], strings)
  eq(order(), "Drums Strings >Violins >Cellos >Violas Bass", "a track put into the group joins its rows")
  eq(
    #groups.members(strings)
      .. " "
      .. tostring(groups.is_group(strings))
      .. " "
      .. tostring(groups.of(t[3]) == strings.id),
    "3 true true",
    "the group knows its members and they their group"
  )
  near(render({ tail = 0.2 }).peak, alone, 0.02, "everything still sounds")
  strings.mute = true
  eq(render({ tail = 0.2 }).peak < alone * 0.75, true, "muting the group mutes its members")
  strings.mute = false

  -- Folding.
  groups.fold(strings, true)
  eq(rows(), "Drums Strings Bass", "a folded group's members are not among the rows that are drawn")
  local state = paw.frontend.state(-1)
  eq(
    #state.tracks .. " " .. tostring(state.tracks[2].folded) .. " " .. state.tracks[2].members,
    "4 true 3",
    "a frontend is given the rows, and told the group is folded and how many it holds"
  )
  local clip_rows = {}
  for _, clip in ipairs(state.clips) do
    clip_rows[#clip_rows + 1] = clip.track
  end
  table.sort(clip_rows)
  eq(table.concat(clip_rows, " "), "0 2", "and no clips of tracks that are out of sight")
  paw.cursor.set_track(t[1])
  paw.keymap.feed("j")
  eq(paw.cursor.track().name, "Strings", "the cursor steps over what is folded away")
  paw.keymap.feed("j")
  eq(paw.cursor.track().name, "Bass", "to the next row")
  paw.cursor.set_track(strings)
  paw.keymap.feed("za")
  eq(rows(), "Drums Strings Violins Cellos Violas Bass", "za opens the group again")
  paw.cursor.set_track(t[3])
  paw.keymap.feed("za")
  eq(paw.cursor.track().name, "Strings", "folding from a member leaves the cursor on the group")
  paw.keymap.feed("zR")

  -- Colour: a member is in its group's.
  strings.color = "#123456"
  eq(paw.draw.track_colour(t[3]:get()), "#123456", "members take the group's colour")
  t[3].color = "#abcdef"
  eq(paw.draw.track_colour(t[3]:get()), "#abcdef", "unless they have their own")

  -- A group inside a group, and no loops.
  local section = groups.make({ strings, t[5] }, "Orchestra")
  eq(order(), "Drums Orchestra >Strings >>Violins >>Cellos >>Violas >Bass", "a group holds groups")
  T.fails(function() groups.add(section, strings) end, "inside itself", "a group put into one of its own")

  -- Out again.
  groups.remove(t[3])
  eq(order(), "Drums Orchestra >Strings >>Violins >>Cellos >Violas >Bass", "a track taken out goes up a level")
  eq(t[3].output, section.id, "and sounds where its old group sounds")
  paw.cursor.set_track(strings)
  paw.cmd("track.ungroup", {})
  eq(
    order(),
    "Drums Orchestra >Violins >Cellos >Violas >Bass",
    "a dissolved group, empty of its own, goes; its members stay a level up"
  )
  api.undo_checkpoint()
  section:remove()
  api.undo_checkpoint()
  eq(order(), "Drums Violins Cellos Violas Bass", "members of a group that is removed stand free")
  paw.undo()
  eq(
    order(),
    "Drums Orchestra >Violins >Cellos >Violas >Bass",
    "and undo puts the group and its members back as one step"
  )

  -- The commands on a selection.
  fresh()
  for i = 1, 3 do
    paw.add_track({ name = "T" .. i })
  end
  paw.cursor.set_track(paw.tracks()[2])
  paw.keymap.feed("Vj")
  paw.cmd("track.group", { "Pair" })
  eq(order(), "T1 Pair >T2 >T3", "track.group groups the selected tracks")
  paw.cursor.set_track(paw.tracks()[1])
  paw.cmd("track.into", { "pai" })
  eq(order(), "Pair >T1 >T2 >T3", "track.into moves a track into a group by name")
end)
