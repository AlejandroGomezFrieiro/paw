-- MIDI output: a track sends what it plays to a port (crates/paw-engine/src/midi_out.rs).
-- Read back through a port of the program's own MIDI input, on the null
-- audio backend with the sequencer opened anyway.
local T = ...
local test, eq, near, fails, fresh = T.test, T.eq, T.near, T.fails, T.fresh
local api = paw.api

-- Our port's name, told apart from those of other instances running the
-- suite at the same time, which a route by name could otherwise reach.
local LOOP = "Loop" .. math.floor(api.now()) % 1000000

--- Wait, with the session looked after, until `ready()` or `ms` pass.
local function wait_for(ready, ms)
  local deadline = api.now() + (ms or 10000)
  while not ready() and api.now() < deadline do
    paw.wait(10)
  end
  return ready()
end

local function output_named(name)
  for _, port in ipairs(paw.midi.outputs()) do
    if port.name == name then return port end
  end
end

--- Run `fn` with the sequencer open and a port of ours, "Loop", that the
--- tracks can send to and the test hears from. Nil and the reason when the
--- sequencer cannot be opened here.
local function with_loop(fn)
  api.engine_restart({ backend = "null", midi = true })
  paw.midi.open_port(LOOP)
  local ok, err
  if wait_for(function() return output_named("paw: " .. LOOP) end, 4000) then
    ok, err = xpcall(fn, debug.traceback)
  else
    ok, err = true, "skipped: no ALSA sequencer to send MIDI through"
  end
  paw.midi.close_port(LOOP)
  api.engine_restart({ backend = "null" })
  if not ok then error(err, 0) end
  return err
end

test("a track sends its clip's notes to a MIDI port, on its channel, in order and in time", function()
  fresh()
  return with_loop(function()
    paw.project.tempo = 120
    local t = paw.add_track({ name = "Hardware" })
    t:add_clip({
      start = 0,
      length = 8,
      notes = {
        { pitch = "C4", start = 0, length = 0.5 },
        { pitch = "E4", start = 1, length = 0.5 },
        { pitch = "G4", start = 2, length = 0.5 },
        { pitch = "C5", start = 3, length = 4 },
      },
    })
    t.midi_output = { port = "paw: " .. LOOP, channel = 3 }
    eq(t.midi_output.port .. " " .. t.midi_output.channel, "paw: " .. LOOP .. " 3", "the track names its output")
    -- What comes back is recorded on a track that takes channel 3 of "Loop"
    -- alone: the notes are where they arrived, in beats.
    local keys = paw.add_track({ name = "Keys" })
    keys.midi_input = { port = LOOP, channel = 3 }
    keys.armed = true
    paw.transport.record_offset = 0
    paw.transport.record()
    wait_for(function() return paw.transport.position >= 8.2 end, 15000)
    paw.transport.stop()
    local clip = keys:clips()[1]
    eq(clip ~= nil, true, "what the track sent came back on its channel")
    local notes = clip:notes()
    table.sort(notes, function(a, b) return a.start < b.start end)
    local pitches = {}
    for i, n in ipairs(notes) do
      pitches[i] = n.pitch
    end
    eq(table.concat(pitches, " "), "60 64 67 72", "the notes, in their order")
    for i, n in ipairs(notes) do
      -- A block or two late, where a busy machine wakes the reader late.
      near(clip.start + n.start, i - 1, 0.12, "note " .. i .. " where it was played")
    end
    near(notes[3].length, 0.5, 0.12, "a note's end goes out in time too")
  end)
end)

test("removing a track that sends MIDI ends the notes it left sounding", function()
  fresh()
  return with_loop(function()
    paw.project.tempo = 120
    local t = paw.add_track({ name = "Hardware" })
    t:add_clip({ start = 0, length = 8, notes = { { pitch = "C5", start = 0, length = 8 } } })
    t.midi_output = { port = "paw: " .. LOOP }
    local keys = paw.add_track({ name = "Keys" })
    keys.midi_input = { port = LOOP }
    keys.armed = true
    paw.transport.record_offset = 0
    paw.transport.record()
    wait_for(function() return paw.transport.position >= 2 end, 10000)
    t:remove()
    wait_for(function() return paw.transport.position >= 4 end, 10000)
    paw.transport.stop()
    local clip = keys:clips()[1]
    eq(clip ~= nil and #clip:notes(), 1, "the note came back")
    near(clip:notes()[1].length, 2, 0.3, "and ended when its track went, not when the song stopped")
  end)
end)

test("MIDI output: a track's port and channel are checked, saved and taken away with it", function()
  fresh()
  local t = paw.add_track({ name = "Hardware" })
  fails(function() t.midi_output = { port = "x", channel = 17 } end, "1 to 16", "a channel past 16")
  fails(function() t.midi_output = { channel = 2 } end, nil, "no port")
  t.midi_output = "Some synth"
  eq(
    t.midi_output.port .. " " .. tostring(t.midi_output.channel),
    "Some synth nil",
    "a port by name, each message on its own channel"
  )
  api.undo_checkpoint()
  t.midi_output = { port = "Some synth", channel = 10 }
  api.undo_checkpoint()
  paw.undo()
  eq(t.midi_output.channel, nil, "undo takes a change of MIDI output back")
  paw.redo()
  eq(t.midi_output.channel, 10, "and redo brings it again")
  local path = T.scratch .. "/midi_out.json"
  paw.project.save(path)
  paw.project.load(path)
  eq(paw.track("Hardware").midi_output.channel, 10, "saved and loaded")
  local copy = paw.track("Hardware"):duplicate()
  eq(copy.midi_output.port, "Some synth", "a copy sends where the original does")
  paw.track("Hardware").midi_output = "none"
  eq(paw.track("Hardware").midi_output, nil, "none takes it away")
  fresh()
  paw.add_track({ name = "Plain" })
  paw.project.save(path)
  eq(T.read_file(path):find("midi_output", 1, true), nil, "a project without it is written as before")
end)

test("the terminal and the window choose a track's MIDI output", function()
  fresh()
  return with_loop(function()
    paw.midi.open_output("To synth")
    eq(
      wait_for(function() return output_named("To synth") end, 4000) ~= nil,
      true,
      "a port of ours for others to read is listed"
    )
    local t = paw.add_track({ name = "Hardware" })
    paw.cursor.set_track(t)
    paw.commands.exec("track.midi_out To synth 5")
    eq(t.midi_output.port .. " " .. t.midi_output.channel, "To synth 5", ":track.midi_out sets port and channel")
    paw.commands.exec("track.midi_out none")
    eq(t.midi_output, nil, ":track.midi_out none takes it away")
    local menu = paw.frontend.input_menu(t.id)
    local labels = {}
    for i, entry in ipairs(menu.midi_out) do
      labels[i] = entry.label
    end
    eq(labels[1], "None", "the input menu has the outputs, none first")
    local at
    for i, label in ipairs(labels) do
      if label == "To synth" then at = i end
    end
    eq(at ~= nil, true, "and our own port")
    paw.frontend.act.choose_input(t.id, "midi_out", at)
    eq(t.midi_output.port, "To synth", "choosing one sends there")
    paw.frontend.act.choose_input(t.id, "midi_out_channel", 3)
    eq(t.midi_output.channel, 2, "and on a channel")
    paw.frontend.act.choose_input(t.id, "midi_out", 1)
    eq(t.midi_output, nil, "None takes it away")
    paw.midi.close_output("To synth")
  end)
end)

test("a script that waits hears what is played into a port", function()
  fresh()
  return with_loop(function()
    paw.project.tempo = 120
    local heard = {}
    local handler = paw.on("midi.in", function(event)
      if event.type == "note_on" then heard[#heard + 1] = event.pitch .. "@" .. tostring(event.port) end
    end)
    local t = paw.add_track({ name = "Hardware" })
    t:add_clip({
      start = 0,
      length = 2,
      notes = {
        { pitch = "C4", start = 0, length = 0.5 },
        { pitch = "E4", start = 1, length = 0.5 },
      },
    })
    t.midi_output = { port = "paw: " .. LOOP }
    paw.transport.play()
    local got = wait_for(function() return #heard >= 2 end, 8000)
    paw.transport.stop()
    paw.off(handler)
    eq(got, true, "the notes arrived while the script waited")
    eq(table.concat(heard, " "), ("60@%s 64@%s"):format(LOOP, LOOP), "as events that name the port they came in on")
  end)
end)
