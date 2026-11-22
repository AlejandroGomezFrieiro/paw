-- Model tests.
local T = ...
local test, eq, fails, fresh, render, tone = T.test, T.eq, T.fails, T.fresh, T.render, T.tone
local until_, scratch, read_file, write_file = T.until_, T.scratch, T.read_file, T.write_file
local paw = require("paw")
local api = paw.api

test("tracks have properties that read back", function()
  fresh()
  local t = paw.add_track({ name = "Bass", volume = -3 })
  eq(t.name, "Bass", "name")
  eq(t.volume, -3, "volume")
  t.pan = 0.5
  t.mute = true
  eq(t.pan, 0.5, "pan")
  eq(t.mute, true, "mute")
  eq(#paw.tracks(), 1, "track count")
  eq(paw.track("Bass"), t, "lookup by name")
  eq(t.index, 1, "index")
  t.volume = 100
  eq(t.volume, 24, "volume is clamped")
end)

test("bad input is rejected with a useful message", function()
  fresh()
  local t = paw.add_track()
  fails(function() paw.add_track({ nmae = "typo" }) end, "nmae", "unknown option")
  fails(function() t:add_device("nope") end, "nope", "unknown device")
  fails(function() t:add_device("synth", { cutof = 1 }) end, "cutof", "unknown parameter")
  fails(function() t.colour = "red" end, "colour", "unknown field")
  fails(function() paw.master:remove() end, "master", "removing the master")
  fails(function() t:add_clip({ file = scratch .. "/missing.wav" }) end, "missing.wav", "missing file")
  fails(function() paw.track(999).name = "x" end, "999", "missing track")
end)

test("tracks insert at an index and move", function()
  fresh()
  local a, b = paw.add_track({ name = "a" }), paw.add_track({ name = "b" })
  local c = paw.add_track({ name = "c", index = 1 })
  eq(c.index, 1, "inserted first")
  eq(a.index, 2, "a pushed down")
  b:move(1)
  eq(b.index, 1, "moved first")
  eq(#paw.tracks(), 3, "count")
end)

test("devices keep parameters, clamp them and reorder", function()
  fresh()
  local t = paw.add_track()
  local synth = t:add_device("synth", { cutoff = 900 })
  local delay = t:add_device("delay")
  eq(synth.params.cutoff, 900, "given parameter")
  eq(synth.params.sustain, synth:info().params[4].default, "default parameter")
  synth:set("cutoff", 99999)
  eq(synth.params.cutoff, 20000, "clamped")
  eq(t:devices()[2], delay, "order")
  delay:move(1)
  eq(t:devices()[1], delay, "moved first")
  eq(t:device("synth"), synth, "lookup by kind")
  delay:remove()
  eq(#t:devices(), 1, "removed")
  eq(delay:exists(), false, "exists")
end)

test("clips hold notes, sorted, with names for pitches", function()
  fresh()
  local t = paw.add_track()
  local clip = t:add_clip({ start = 4, notes = { { pitch = "E4", start = 2 }, { pitch = "C4", start = 0 } } })
  eq(clip.length, 4, "length defaults to whole bars")
  local notes = clip:notes()
  eq(notes[1].pitch, 60, "sorted by start")
  eq(notes[2].pitch, 64, "name converted")
  eq(notes[1].velocity, 100, "default velocity")
  clip:add_note({ pitch = 67, start = 1, length = 0.5 })
  eq(#clip:notes(), 3, "note added")
  eq(clip:notes()[2].pitch, 67, "kept sorted")
  eq(t:clip_at(5), clip, "clip_at inside")
  eq(t:clip_at(8), nil, "clip_at outside")
  local copy = clip:duplicate()
  eq(copy.start, 8, "duplicate follows the original")
  eq(#copy:notes(), 3, "duplicate has the notes")
  eq(paw.project.length, 12, "project length")
end)

test("a setter takes a table of changes as one undo step; the key form clears an entry", function()
  fresh()
  local a, b = paw.add_track({ name = "a" }), paw.add_track({ name = "b" })
  api.undo_checkpoint()
  api.track_set(a.id, { name = "lead", volume = -6, output = b.id })
  api.undo_checkpoint()
  local t = api.track_get(a.id)
  eq(t.name .. " " .. t.volume .. " " .. t.output, "lead -6 " .. b.id, "each entry set")
  api.track_set(a.id, "output", nil)
  eq(api.track_get(a.id).output, nil, "cleared")
  paw.undo()
  paw.undo()
  eq(api.track_get(a.id).name, "a", "the patch is undone at once")
end)

test("undo and redo step through edits", function()
  fresh()
  api.undo_checkpoint()
  local t = paw.add_track({ name = "one" })
  api.undo_checkpoint()
  t.name = "two"
  t:add_device("synth")
  api.undo_checkpoint()
  eq(paw.undo(), true, "undo")
  eq(t.name, "one", "rename undone")
  eq(#t:devices(), 0, "device undone with it")
  eq(paw.undo(), true, "undo again")
  eq(#paw.tracks(), 0, "track undone")
  eq(paw.redo(), true, "redo")
  eq(paw.redo(), true, "redo again")
  eq(t.name, "two", "redone")
  eq(paw.redo(), false, "nothing left to redo")
end)

test("events report what changed", function()
  fresh()
  local seen = {}
  -- (What changed, said again as addresses, is paw.address's business: tests/address.lua.)
  local handle = paw.on("*", function(payload, name)
    if name ~= "address.changed" then seen[#seen + 1] = name .. ":" .. tostring(payload.id or "") end
  end)
  local t = paw.add_track()
  local d = t:add_device("gain")
  paw.flush()
  eq(table.concat(seen, " "), string.format("track.added:%d device.added:%d changed:", t.id, d.id), "after adding")
  seen = {}
  t.volume = -3
  paw.flush()
  eq(table.concat(seen, " "), string.format("track.changed:%d changed:", t.id), "after a change")
  seen = {}
  api.undo_checkpoint()
  t.volume = -9
  paw.flush()
  seen = {}
  paw.undo()
  paw.flush()
  eq(seen[1], "track.changed:" .. t.id, "undo reports changes too")
  seen = {}
  paw.off(handle)
  t.volume = -4
  paw.flush()
  eq(#seen, 0, "no events after paw.off")

  local family = 0
  local id = paw.on("track.*", function() family = family + 1 end)
  T.after(function() paw.off(id) end)
  paw.emit("track.custom")
  paw.emit("other.custom")
  eq(family, 1, "family pattern")
end)

test("projects save and load", function()
  fresh()
  local t = paw.add_track({ name = "Keys", pan = -0.25 })
  t:add_device("synth", { wave = 2 })
  t:add_clip({ start = 2, notes = { { pitch = 72, start = 0.5, length = 0.25, velocity = 64 } } })
  paw.project.tempo = 97
  paw.project.meta = { my_extension = { answer = 42 } }
  paw.transport.loop_start, paw.transport.loop_end = 4, 12
  local path = paw.project.save(scratch .. "/song.json")
  fresh()
  eq(#paw.tracks(), 0, "new project is empty")
  paw.project.load(path)
  local loaded = paw.tracks()[1]
  eq(loaded.name, "Keys", "name")
  eq(loaded.pan, -0.25, "pan")
  eq(loaded:device("synth").params.wave, 2, "device parameter")
  local note = loaded:clips()[1]:notes()[1]
  eq(note.pitch .. "/" .. note.start .. "/" .. note.length .. "/" .. note.velocity, "72/0.5/0.25/64", "note")
  eq(paw.project.tempo, 97, "tempo")
  eq(paw.project.meta.my_extension.answer, 42, "extension data")
  eq(paw.transport.loop_end, 12, "loop")
  -- Ids handed out after loading must not collide with loaded ones.
  local another = paw.add_track()
  eq(another.id > loaded:clips()[1].id, true, "fresh ids")
end)

test("notes carry extension data through edits, undo and saving", function()
  fresh()
  local t = paw.add_track({ name = "Words" })
  local clip = t:add_clip({
    start = 0,
    length = 4,
    notes = {
      { pitch = 60, start = 1, length = 1, meta = { lyric = "la", extra = { 1, 2 } } },
      { pitch = 62, start = 0, length = 1 },
    },
  })
  local notes = clip:notes()
  eq(notes[1].meta, nil, "a note without data has no meta")
  eq(notes[2].meta.lyric, "la", "the data is kept, and stays with its note when the list is sorted")
  api.undo_checkpoint()
  -- Changing a note the way the piano roll does keeps its data.
  notes[2].start = 2
  clip:set_notes(notes)
  eq(clip:notes()[2].meta.extra[2], 2, "kept when the note moves")
  paw.undo()
  eq(clip:notes()[2].start, 1, "undone")
  eq(clip:notes()[2].meta.lyric, "la", "and the data with it")
  local path = paw.project.save(scratch .. "/words.json")
  eq(read_file(path):find('"lyric": "la"', 1, true) ~= nil, true, "saved in the project file")
  fresh()
  paw.project.load(path)
  eq(paw.tracks()[1]:clips()[1]:notes()[2].meta.lyric, "la", "loaded")
end)

test("saving and loading keeps every number exactly", function()
  fresh()
  local t = paw.add_track({ pan = 0.123456789012345678 })
  -- Found by the fuzzer: these came back from a saved file one bit off.
  t:add_clip({
    start = 1.3859882354736328,
    length = 3.9661864042282104,
    notes = { { pitch = 60, start = 0.15935707092285156, length = 1.9014935493469238 } },
  })
  local before = t:clips()[1]
  local note = before:notes()[1]
  paw.project.load(paw.project.save(scratch .. "/exact.json"))
  local after = paw.tracks()[1]:clips()[1]
  local loaded = after:notes()[1]
  eq(loaded.length, note.length, "note length")
  eq(loaded.start, note.start, "note start")
  eq(after.start, before.start, "clip start")
  eq(after.length, before.length, "clip length")
  eq(paw.tracks()[1].pan, t.pan, "pan")
end)

test("numbers that are not finite are refused, so that a save always loads", function()
  fresh()
  local nan, inf = 0 / 0, 1 / 0
  local t = paw.add_track()
  local synth = t:add_device("synth")
  fails(function() paw.add_track({ volume = nan }) end, "finite", "volume NaN")
  fails(function() paw.add_track({ pan = inf }) end, "finite", "pan infinite")
  fails(function() synth:set("cutoff", nan) end, "finite", "parameter NaN")
  fails(function() t:add_clip({ notes = { { pitch = 60, start = inf, length = 1 } } }) end, "finite", "note start")
  fails(function() t:add_clip({ notes = { { pitch = 60, start = 0, length = nan } } }) end, "length", "note length NaN")
  -- A note-off before its note-on would leave the note sounding.
  fails(function() t:add_clip({ notes = { { pitch = 60, start = 0, length = -1 } } }) end, "length", "negative length")
  fails(function() t:add_clip({ notes = { { pitch = 200, start = 0, length = 1 } } }) end, "127", "pitch 200")
  local clip = t:add_clip({ start = 0, length = 4 })
  fails(function() clip:set_notes({ { pitch = 60, start = 0, length = 0 } }) end, "length", "zero length")
  fails(function() t:add_clip({ file = "tests/fixtures/shape.wav", gain = nan }) end, "finite", "clip gain NaN")
  fails(function() t:add_clip({ file = "tests/fixtures/shape.wav", offset = -inf }) end, "offset", "clip offset")
  fails(function() api.note_on(t.id, 60, nan) end, "velocity", "live velocity NaN")
  fails(function() api.midi_inject({ type = "note_on", pitch = 60, velocity = inf }) end, "velocity", "MIDI velocity")
  paw.project.load(paw.project.save(scratch .. "/finite.json"))
  eq(#paw.tracks(), 1, "the project saved and loaded")
end)

test("note lists read and write the same through either path", function()
  fresh()
  local clip = paw.add_track():add_clip({ start = 0, length = 8 })
  local notes = {
    { pitch = 60, start = 0.5, length = 0.25 },
    { pitch = 64, start = 0, length = 1.5, velocity = 7, extra = "ignored" },
  }
  api.clip_set_notes(clip.id, notes)
  local got = api.clip_notes(clip.id)
  eq(#got, 2, "count")
  eq(
    got[1].pitch .. "/" .. got[1].start .. "/" .. got[1].length .. "/" .. got[1].velocity,
    "64/0/1.5/7",
    "sorted, fields"
  )
  eq(got[2].velocity, 100, "default velocity")
  eq(got[1].extra, nil, "unknown fields are not kept")
  api.clip_add_notes(clip.id, {})
  eq(#api.clip_notes(clip.id), 2, "adding nothing")
  -- Not plain note tables: the general path decides, with its own messages.
  fails(function() api.clip_set_notes(clip.id, { { pitch = "C4", start = 0, length = 1 } }) end, "u8", "a pitch name")
  fails(function() api.clip_set_notes(clip.id, { { pitch = 300, start = 0, length = 1 } }) end, "300", "pitch 300")
  fails(function() api.clip_set_notes(clip.id, { { pitch = 60, length = 1 } }) end, "start", "no start")
  fails(
    function() api.clip_set_notes(clip.id, { { pitch = 60.5, start = 0, length = 1 } }) end,
    nil,
    "a fractional pitch"
  )
  fails(function() api.clip_set_notes(clip.id, "notes") end, nil, "not a table")
  api.clip_set_notes(clip.id, { [1] = { pitch = 1, start = 0, length = 1 }, x = 1 })
  eq(#api.clip_notes(clip.id), 1, "a list with another key goes through the general path")
end)

test("a device brought back by undo reads as loaded at once", function()
  fresh()
  local t = paw.add_track()
  api.undo_checkpoint()
  local synth = t:add_device("synth", { cutoff = 900 })
  api.undo_checkpoint()
  synth:remove()
  paw.flush()
  api.undo_checkpoint()
  paw.undo()
  -- No flush after the undo: found by the fuzzer.
  local view = api.device_get(synth.id)
  eq(view.missing, false, "not missing")
  eq(view.params.cutoff, 900, "its parameters")
end)

test("a refused edit leaves no undo step behind", function()
  fresh()
  local t = paw.add_track()
  api.undo_checkpoint()
  t.volume = -6
  api.undo_checkpoint()
  fails(function() api.track_set(t.id, "volume", "loud") end, "volume", "bad value")
  api.undo_checkpoint()
  paw.undo()
  eq(t.volume, 0, "one undo undoes the last edit that went through")
end)

test("a damaged project file is refused whole", function()
  fresh()
  local t = paw.add_track({ name = "kept" })
  t:add_device("synth")
  t:add_clip({ start = 0, length = 4, notes = { { pitch = 60, start = 0, length = 1 } } })
  local good = read_file(paw.project.save(scratch .. "/good.json"))
  local function load(text, pattern, what)
    write_file(scratch .. "/bad.json", text)
    fails(function() paw.project.load(scratch .. "/bad.json") end, pattern, what)
    eq(paw.tracks()[1].name, "kept", what .. ": the open project is untouched")
  end
  load(good:gsub('"tempo": 120.0', '"tempo": 0.0'), "tempo", "tempo 0, which made renders never end")
  load(good:gsub('"sig_den": 4', '"sig_den": 0'), "denominator", "time signature")
  load(good:gsub('"length": 4.0', '"length": -4.0', 1), "length", "negative clip length")
  load(good:gsub('"length": 1.0', '"length": -1.0', 1), "note", "negative note length")
  load(good:gsub('"volume": 0.0', '"volume": 1e300', 1), "volume", "volume out of range")
  local id = t.id
  -- The master track comes first in the file; the second output is the track's.
  local n = 0
  local looped = good:gsub('"output": null', function()
    n = n + 1
    if n == 2 then return '"output": ' .. id end
  end)
  load(looped, "routed", "a track routed into itself")
  local dup = good:gsub('"id": ' .. t:clips()[1].id, '"id": ' .. id, 1)
  load(dup, "twice", "two things with one id")
end)

test("levels are kept within range, so that nothing turns into infinity", function()
  fresh()
  local t = paw.add_track()
  local clip = t:add_clip({ start = 0, length = 1, file = "tests/fixtures/shape.wav", gain = 1e9 })
  eq(clip.gain, 24, "clip gain at add")
  clip.gain = -1e9
  eq(clip.gain, -120, "clip gain set")
  clip.gain = 1e9
  local bus = paw.add_track()
  api.track_set(t.id, "sends", { { target = bus.id, level = 1e9 } })
  eq(t.sends[1].level, 24, "send level")
  eq(render({ ["end"] = 1, tail = 0, bits = 32 }).nonfinite, 0, "the render is finite")
  -- Found by the fuzzer: a send level saved out of range made a file that does not load.
  paw.project.load(paw.project.save(scratch .. "/levels.json"))
  eq(#paw.tracks(), 2, "saved and loaded")
  -- Values in a file are kept within the device's range too.
  fresh()
  local g = paw.add_track()
  g:add_clip({ start = 0, length = 1, file = "tests/fixtures/shape.wav" })
  g:add_device("gain")
  local text =
    read_file(paw.project.save(scratch .. "/param.json")):gsub('"params": {}', '"params": { "gain": 1e300 }', 1)
  write_file(scratch .. "/param.json", text)
  paw.project.load(scratch .. "/param.json")
  local info = render({ ["end"] = 1, tail = 0, bits = 32 })
  eq(info.nonfinite, 0, "a parameter of 1e300 in a file")
  eq(info.peak > 0, true, "still sounds")
  local lane = g:automate("volume")
  lane:add(0, 0)
  text = read_file(paw.project.save(scratch .. "/lane.json")):gsub("%[%s*0%.0,%s*0%.0%s*%]", "[0.0, 1e300]", 1)
  write_file(scratch .. "/lane.json", text)
  fails(function() paw.project.load(scratch .. "/lane.json") end, "lane", "a volume point of 1e300")
end)

test("sends cannot make a loop either", function()
  fresh()
  local a, b, c = paw.add_track(), paw.add_track(), paw.add_track()
  a:send(b, -6)
  b:send(c, -6)
  fails(function() c:send(a, -6) end, "loop", "a loop through sends")
  fails(function() c.output = a end, "loop", "a loop through a send and an output")
end)

test("renders and engines refuse sizes and rates they cannot do", function()
  fresh()
  tone("t", 2)
  fails(function() render({ tail = 1e12 }) end, "tail is at most", "a tail longer than any sound rings")
  fails(function() render({ ["end"] = 1e15 }) end, "WAV", "an end no file can hold")
  fails(function() render({ tail = 1 / 0 }) end, "finite", "an infinite tail")
  fails(function() render({ sample_rate = 0 }) end, "sample rate", "0 Hz")
  fails(function() render({ sample_rate = 4000000000 }) end, "sample rate", "4 GHz")
  fails(function() api.engine_restart({ backend = "null", sample_rate = 0 }) end, "sample rate", "engine at 0 Hz")
  fails(function() api.engine_restart({ backend = "null", buffer_size = 1000000000 }) end, "buffer", "a huge buffer")
  eq(render({ ["end"] = 2, tail = 0 }).peak > 0.01, true, "still renders")
end)

test("a track the engine had no room for sounds once there is room", function()
  fresh()
  local tracks = {}
  for i = 1, 1030 do
    tracks[i] = api.track_add({ name = "t" .. i })
  end
  -- Sync without handing the warnings to the notifier, to read them here.
  api.events_take()
  local warnings = api.warnings()
  eq(#warnings > 0 and warnings[1]:find("too many tracks") ~= nil, true, "a warning for the tracks over the limit")
  for i = 1, 20 do
    api.track_remove(tracks[i])
  end
  paw.flush()
  local last = paw.track(tracks[1030])
  last:add_device("synth")
  last:note_on(60, 100)
  until_(function() return last:meter() > 0 end, "the last track to play")
  last:note_off(60)
  fresh()
end)

test("a render leaves denormal numbers working for Lua", function()
  fresh()
  tone("t", 1)
  render({ tail = 0 })
  eq(1e-310 * 0.5 > 0, true, "denormals are not flushed to zero on the main thread")
end)
