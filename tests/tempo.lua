-- The tempo map: tempo and time signature changes along the song, and
-- everything that converts with them.
local T = ...
local advance = T.advance
local test, eq, near, fresh, fails = T.test, T.eq, T.near, T.fresh, T.fails
local paw = require("paw")
local api = paw.api

--- 4/4 at 120, a ramp from 120 to 90 over bars 3 and 4, 6/8 from bar 9.
local function song()
  fresh()
  paw.project.tempo = 120
  paw.tempo.set(8, 120, { ramp = true })
  paw.tempo.set(16, 90)
  paw.tempo.set_signature(9, 6, 8)
end

test("tempo: conversions follow the map", function()
  song()
  near(paw.tempo.beats_to_seconds(8), 4, 1e-9, "two bars at 120")
  -- Linear in time: the ramp averages 105 BPM.
  near(paw.tempo.beats_to_seconds(16), 4 + 8 * 60 / 105, 1e-9, "through the ramp")
  near(paw.tempo.seconds_to_beats(paw.tempo.beats_to_seconds(13.7)), 13.7, 1e-9, "and back")
  eq(paw.tempo.at(20), 90, "after the ramp")
  eq(paw.tempo.bar_of(32), 9, "bar 9 starts the 6/8")
  eq(paw.tempo.bar_start(10), 35, "6/8 bars are three beats")
  eq(paw.time.format(33.5), "9.4.00", "the fourth eighth of bar 9")
  eq(paw.time.bar(33), 3, "bar length at a beat")
  eq(paw.time.bar(), 4, "the first bar's length")
  local num, den = paw.tempo.signature_at(40)
  eq(num .. "/" .. den, "6/8", "signature at a beat")
  near(paw.time.seconds(8, 16), 8 * 60 / 90, 1e-9, "a length from a beat")
  eq(paw.project.tempo, 120, "the project's tempo is the start's")
  local lines = paw.tempo.lines(30, 36)
  eq(#lines, 2 + 8, "two quarter beats of 4/4, then six eighths and two")
  eq(lines[3].beat, 32, "a bar line")
  eq(lines[3].index, 0, "marked as the bar's first")
end)

test("tempo: a signature change inside a bar cuts it short", function()
  fresh()
  api.signature_set(6, 3, 4)
  eq(paw.tempo.bar_of(5), 2, "the cut bar")
  eq(paw.tempo.bar_of(6), 3, "a new bar at the change")
  eq(paw.time.bar(5), 2, "two beats long")
  eq(paw.tempo.bar_start(4), 9, "then bars of three")
end)

test("tempo: one tempo saves as before; a map saves and loads", function()
  fresh()
  paw.project.tempo = 97
  local path = T.scratch .. "/one-tempo.json"
  paw.project.save(path)
  local text = T.read_file(path)
  eq(text:find("tempo_changes", 1, true), nil, "no list of changes for one tempo")
  eq(text:find("sig_changes", 1, true), nil, "nor of signatures")
  song()
  path = T.scratch .. "/map.json"
  paw.project.save(path)
  fresh()
  paw.project.load(path)
  eq(#paw.tempo.points(), 3, "the tempo points come back")
  eq(paw.tempo.points()[2].ramp, true, "with their ramp")
  eq(paw.tempo.bar_of(32), 9, "and the signature")
end)

test("tempo: commands set, ramp, list and remove changes, each one undo step", function()
  fresh()
  local function run(line)
    paw.commands.exec(line)
    api.undo_checkpoint()
  end
  run("tempo 100")
  eq(paw.project.tempo, 100, "`tempo 100` sets the start")
  run("tempo 80 at 5")
  eq(paw.tempo.at(16), 80, "`tempo 80 at 5` from bar 5")
  paw.cursor.set_beat(8)
  run("tempo 90 here")
  eq(paw.tempo.at(8), 90, "at the cursor")
  run("tempo.ramp")
  eq(paw.tempo.points()[2].ramp, true, "the change at the cursor ramps")
  run("timesig 6/8")
  eq(paw.tempo.bar_start(3), 8, "6/8 from the cursor's bar")
  eq(paw.tempo.bar_start(4), 11, "bars of three beats")
  local lines = paw.commands.exec("tempo.list")
  eq(#lines, 5, "three tempos and two signatures listed")
  paw.cursor.set_beat(9)
  run("tempo.remove")
  eq(#paw.tempo.points(), 2, "the change before the cursor is gone")
  paw.undo()
  eq(#paw.tempo.points(), 3, "undo brings it back")
  paw.undo()
  local num = paw.tempo.signature_at(9)
  eq(num, 4, "undo takes the signature away")
  paw.undo()
  eq(paw.tempo.points()[2].ramp, false, "and the ramp")
  fails(function() paw.commands.exec("timesig 6-8") end, "6/8", "a bad signature")
  fails(function() api.tempo_set(4, 0) end, "between 1 and 999", "a bad tempo")
end)

test("tempo: tap tempo sets the tempo from the taps", function()
  fresh()
  paw.commands.exec("tempo.tap")
  advance(250)
  paw.commands.exec("tempo.tap")
  advance(250)
  paw.commands.exec("tempo.tap")
  near(paw.project.tempo, 240, 30, "taps a quarter second apart")
end)

test("tempo: a render's notes fall where the map puts them", function()
  song()
  -- A short note on every beat of the signature, through the 6/8 and the ramp.
  local lines = paw.tempo.lines(0, 44)
  local notes = {}
  for i, line in ipairs(lines) do
    notes[i] = { pitch = 81, start = line.beat, length = 0.05 }
  end
  local track = paw.add_track()
  track:add_device("synth", { attack = 0, release = 0.001 })
  track:add_clip({ start = 0, length = 44, notes = notes })
  local info = T.render({ start = 0, ["end"] = 44, tail = 0, bits = 16 })
  local s = T.samples(info)
  local onsets, silent = {}, 100
  for i, v in ipairs(s) do
    if v == 0 then
      silent = silent + 1
    else
      if silent >= 50 then onsets[#onsets + 1] = i - 1 end
      silent = 0
    end
  end
  eq(#onsets, #lines, "a note for each beat of the signature")
  local worst = 0
  for i, line in ipairs(lines) do
    local want = paw.tempo.beats_to_seconds(line.beat) * 48000
    worst = math.max(worst, math.abs(onsets[i] - want))
  end
  eq(worst <= 2, true, "every note within two frames of the map's time (worst " .. worst .. ")")
  near(info.seconds, paw.tempo.beats_to_seconds(44), 1e-3, "the render lasts as long as the map says")
end)

test("tempo: audio clips keep their length in time when the tempo changes", function()
  fresh()
  -- A file with a click every second.
  local left = {}
  for i = 1, 48000 * 4 do
    left[i] = 0
  end
  for k = 0, 3 do
    left[k * 48000 + 101] = 0.9
  end
  local file = T.write_wav(T.scratch .. "/clicks.wav", left)
  local track = paw.add_track()
  local clip = track:add_clip({ file = file, start = 8 })
  eq(clip.length, 8, "four seconds at 120")
  -- Slower before it: in time, its start stays at 4 s, which is now fewer beats.
  paw.project.tempo = 60
  near(clip.start, 4, 1e-9, "the start keeps its time")
  near(clip.length, 4, 1e-9, "four seconds at 60")
  -- A ramp under it: its length in beats follows the map.
  api.tempo_set(5, 60, true)
  api.tempo_set(9, 180)
  near(
    paw.tempo.beats_to_seconds(clip.start + clip.length) - paw.tempo.beats_to_seconds(clip.start),
    4,
    1e-9,
    "still four seconds long"
  )
  -- Every sample at the right time.
  local start_s = paw.tempo.beats_to_seconds(clip.start)
  local s = T.samples(T.render({ start = 0, ["end"] = clip.start + clip.length, tail = 0, bits = 16 }))
  local heard = {}
  for i, v in ipairs(s) do
    if math.abs(v) > 0.5 then heard[#heard + 1] = i - 1 end
  end
  eq(#heard, 4, "four clicks")
  for k, at in ipairs(heard) do
    near(at, start_s * 48000 + (k - 1) * 48000 + 100, 1.01, "click " .. k .. " on time")
  end
  -- Kept on its beat instead.
  clip.timebase = "beats"
  local beat = clip.start
  paw.project.tempo = 100
  near(clip.start, beat, 1e-9, "a clip in beats keeps its beat")
  near(
    paw.tempo.beats_to_seconds(clip.start + clip.length) - paw.tempo.beats_to_seconds(clip.start),
    4,
    1e-9,
    "and its length in time"
  )
  -- A MIDI clip stays on its beats.
  local midi = track:add_clip({ start = 20, length = 4 })
  paw.project.tempo = 140
  eq(midi.start, 20, "MIDI follows beats")
  eq(midi.length, 4, "and keeps its length in beats")
end)

test("tempo: the window gets the map's lines and flags, and moves and removes them", function()
  song()
  local state = paw.frontend.state(-1)
  local labels = {}
  for _, line in ipairs(state.project.lines) do
    if line.label ~= "" then labels[line.label] = line.beat end
  end
  eq(labels["9"], 32, "bar 9 where the 6/8 starts")
  eq(labels["10"], 35, "and bars of three beats after it")
  local marks = state.project.marks
  eq(#marks, 3, "two tempo changes and a signature change flagged")
  eq(marks[3].text, "6/8", "the signature's flag")
  eq(state.tempo, 120, "the tempo at the playhead")
  paw.transport.seek(33)
  paw.flush()
  state = paw.frontend.state(-1)
  eq(state.signature, "6/8", "the signature at the playhead")
  eq(state.tempo, 90, "the tempo at the playhead")
  local act = paw.frontend.act
  act.tempo_mark("move", "tempo", 16, 20.2)
  near(paw.tempo.points()[3].beat, 20, 1e-9, "a tempo flag dragged lands on the grid")
  act.tempo_mark("move", "signature", 32, 28.8)
  local num = paw.tempo.signature_at(29)
  eq(num, 6, "a signature flag dragged lands on the nearest bar line")
  act.tempo_mark("remove", "tempo", 20, 0)
  eq(#paw.tempo.points(), 2, "removed from its menu")
  act.tempo_mark("edit", "tempo", 8, 0)
  eq(type(paw.frontend.state(-1).modal.prompt), "table", "a double click asks for the value")
  act.keys("<C-u>95<CR>")
  eq(paw.tempo.at(8), 95, "and takes it")
end)

test("tempo: grt sets the tempo in force at the cursor; commands complete", function()
  song()
  paw.cursor.set_beat(12)
  paw.commands.exec("tempo.set")
  paw.frontend.act.keys("<C-u>100<CR>")
  eq(paw.tempo.points()[3].bpm, 90, "the change after the cursor stays")
  eq(paw.tempo.points()[2].bpm, 100, "the change in force at the cursor takes the value")
  eq(paw.project.tempo, 120, "the start keeps its tempo")
  local found = false
  for _, c in ipairs(paw.commands.complete("timesig ")) do
    if c.label == "6/8" or c.text:find("6/8", 1, true) then found = true end
  end
  eq(found, true, "`timesig` offers common signatures")
  eq(paw.commands.label(paw.commands.get("timesig")), "Set the time signature", "its undo step reads well")
end)
