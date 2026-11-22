-- Sound tests.
local T = ...
local test, eq, near, fails, fresh, render, tone = T.test, T.eq, T.near, T.fails, T.fresh, T.render, T.tone
local until_, scratch, read_file, write_file, frequency, channel_peaks = T.until_, T.scratch, T.read_file, T.write_file, T.frequency, T.channel_peaks
local paw = require("paw")
local api = paw.api
local fixtures = "tests/fixtures/"

test("a note renders, and silence renders as silence", function()
  fresh()
  local t = tone("tone", 2)
  local info = render({ tail = 0.2 })
  eq(info.peak > 0.05, true, "audible")
  near(info.seconds, 1.2, 0.01, "length: 2 beats at 120 bpm plus the tail")
  t.mute = true
  eq(render().peak, 0, "muted")
  t.mute = false
  t:clips()[1].muted = true
  eq(render().peak, 0, "clip muted")
end)

test("playback that starts inside a note sounds that note", function()
  fresh()
  local t = tone("held", 8)
  eq(render({ start = 3, ["end"] = 4, tail = 0 }).peak > 0.05, true, "render from the middle of the note")
  eq(render({ start = 9, ["end"] = 10, tail = 0 }).peak < 0.001, true, "nothing after the note ends")
  -- The same in real time, and after jumping while playing.
  paw.project.tempo = 240
  paw.transport.seek(2)
  paw.transport.play()
  until_(function() return select(1, t:meter()) > 0.01 end, "playing from inside the note")
  paw.transport.seek(40)
  until_(function() return select(1, t:meter()) < 0.005 end, "jumping past the note to stop it")
  paw.transport.seek(4)
  until_(function() return select(1, t:meter()) > 0.01 end, "jumping back into the note to start it")
  paw.transport.stop()
end)

test("the fader and pan do what they say", function()
  fresh()
  local t = tone("tone", 2)
  local unity = render().peak
  t.volume = -6
  near(render().peak / unity, 0.501, 0.01, "-6 dB halves the level")
  t.volume = 0
  t.pan = -1
  local left, right = channel_peaks(render({ bits = 16 }))
  eq(left > 0.05, true, "hard left has left")
  eq(right < 0.001, true, "hard left has no right")
  t.pan = 0
  left, right = channel_peaks(render({ bits = 16 }))
  near(left, right, 0.001, "centre is equal")
  near(left, unity, 0.005, "centre is unity gain")
end)

test("solo silences the others but not what a soloed track feeds", function()
  fresh()
  local a, b = tone("a", 2, "A3"), tone("b", 2, "E4")
  local bus = paw.add_track({ name = "bus" })
  a.output = bus
  local both = render().peak
  b.solo = true
  local only_b = render().peak
  eq(only_b < both * 0.8, true, "soloing b drops a")
  b.solo = false
  a.solo = true
  local only_a = render().peak
  eq(only_a > 0.05, true, "a is still heard through its bus")
  bus.mute = true
  a.solo = false
  near(render().peak, only_b, 0.01, "muting the bus mutes a")
end)

test("routing refuses loops and survives removing a bus", function()
  fresh()
  local a = tone("a", 2)
  local bus, bus2 = paw.add_track({ name = "bus" }), paw.add_track({ name = "bus2" })
  a.output = bus
  bus.output = bus2
  fails(function() bus2.output = a end, "loop", "output loop")
  fails(function() bus2:send(a, 0) end, "loop", "send loop")
  local before = render().peak
  bus.volume = -6
  near(render().peak / before, 0.501, 0.01, "bus fader applies")
  bus:remove()
  eq(a.output, nil, "falls back to the master")
  near(render().peak, before, 0.005, "still sounds")
end)

test("sends add signal to their target", function()
  fresh()
  local a = tone("a", 2)
  local fx = paw.add_track({ name = "fx" })
  local dry = render().peak
  a:send(fx, 0)
  near(render().peak / dry, 2, 0.02, "an equal send doubles the level")
end)

test("effects run in chain order and can be bypassed", function()
  fresh()
  local t = tone("tone", 1)
  local dry = render({ tail = 0 }).peak
  local gain = t:add_device("gain", { gain = -12 })
  near(render({ tail = 0 }).peak / dry, 0.251, 0.01, "gain device")
  gain.bypass = true
  near(render({ tail = 0 }).peak, dry, 0.005, "bypassed")
  gain:remove()
  local delay = t:add_device("delay", { time = 600, feedback = 0, mix = 1 })
  -- The note lasts one beat (0.5 s), so a 600 ms echo of it sounds from 0.6 to 1.1 s.
  local wet = render({ tail = 1, bits = 16 })
  near(channel_peaks(wet, 0.6, 1.1), dry, 0.02, "the echo is as loud as the note")
  eq(channel_peaks(wet, 0.52, 0.58) < 0.01, true, "silence between the note and its echo")
  delay.bypass = true
  eq(channel_peaks(render({ tail = 1, bits = 16 }), 0.7, 1.0) < 0.001, true, "no echo when bypassed")
end)

test("audio clips play back what was rendered", function()
  fresh()
  tone("tone", 2)
  local source = render({ tail = 0, bits = 24 })
  fresh()
  local t = paw.add_track({ name = "audio" })
  local clip = t:add_clip({ start = 1, file = source.path })
  eq(clip.kind, "audio", "kind")
  near(clip.length, 2, 0.01, "length follows the file")
  local out = render({ tail = 0 })
  near(out.peak, source.peak, 0.01, "same level")
  eq(paw.render(scratch .. "/gap.wav", { start = 0, ["end"] = 0.9, tail = 0 }).peak < 0.001, true, "silent before the clip")
  clip.gain = -6
  near(render({ tail = 0 }).peak / source.peak, 0.501, 0.02, "clip gain")
  -- A different sample rate must not change the pitch or length.
  near(render({ tail = 0, sample_rate = 44100 }).peak, source.peak * 0.501, 0.02, "resampled")
end)

test("audio clips load WAV, AIFF, FLAC, MP3 and Ogg Vorbis", function()
  -- Each fixture is 0.25 s of 440 Hz at 0.5 (-6 dB); the stereo ones are at
  -- 0.25 on the right. See tests/fixtures/make.sh. The lossy ones come back
  -- a few percent off.
  for _, f in ipairs({
    { "tone-mono-8k.wav", 0.5, 0.005 },
    { "tone-mono-11k.aiff", 0.5, 0.005 },
    { "tone-stereo-11k.flac", 0.25, 0.005 },
    { "tone-stereo-44k.mp3", 0.25, 0.05 },
    { "tone-stereo-48k.ogg", 0.25, 0.05 },
  }) do
    local name, right, tolerance = f[1], f[2], f[3]
    fresh()
    local clip = paw.add_track():add_clip({ start = 0, file = fixtures .. name })
    eq(clip.kind, "audio", name .. " kind")
    near(clip.length, 0.5, 0.001, name .. " length: 0.25 s at 120 bpm")
    -- Each file plays at its own rate whatever the engine runs at.
    for _, rate in ipairs({ 48000, 44100 }) do
      local out = render({ tail = 0, bits = 16, sample_rate = rate })
      near(out.seconds, 0.25, 0.002, name .. " renders for the clip's length")
      local l, r = channel_peaks(out, 0.02, 0.23)
      near(l, 0.5, tolerance, name .. " left level at " .. rate)
      near(r, right, tolerance, name .. " right level at " .. rate .. (right == 0.5 and ", mono on both sides" or ""))
      near(frequency(out, 0.02, 0.23), 440, 10, name .. " pitch at " .. rate)
    end
  end
end)

test("unreadable audio files say what is wrong", function()
  fresh()
  local t = paw.add_track()
  local function add(path) return function() t:add_clip({ start = 0, file = path }) end end
  write_file(scratch .. "/notes.wav", "a text file named like a sound\n")
  fails(add(scratch .. "/notes.wav"), "notes%.wav is not an audio file", "text")
  write_file(scratch .. "/cut.wav", read_file(fixtures .. "tone-mono-8k.wav"):sub(1, 3000))
  fails(add(scratch .. "/cut.wav"), "cut%.wav is truncated", "truncated WAV")
  write_file(scratch .. "/cut.mp3", read_file(fixtures .. "tone-stereo-44k.mp3"):sub(1, 1300))
  fails(add(scratch .. "/cut.mp3"), "cut%.mp3 is truncated", "truncated MP3")
  write_file(scratch .. "/cut.ogg", read_file(fixtures .. "tone-stereo-48k.ogg"):sub(1, 3000))
  fails(add(scratch .. "/cut.ogg"), "cut%.ogg is truncated", "truncated Ogg")
  fails(add(fixtures .. "tone-mono-48k.opus"), "opus uses an audio codec that is not supported", "Opus")
  eq(#t:clips(), 0, "no clips were added")
end)

test("audio clips report their waveform", function()
  fresh()
  local t = paw.add_track({ name = "shape" })
  -- 0.25 s in four equal parts: silence, a sine peaking at 0.5, one peaking at
  -- 0.75, and -0.25 held.
  local clip = t:add_clip({ start = 0, file = fixtures .. "shape.wav" })
  local function check(peaks, want, what)
    eq(#peaks, #want, what .. ": count")
    for i, p in ipairs(peaks) do
      near(p[1], want[i][1], 1e-4, what .. ": min " .. i)
      near(p[2], want[i][2], 1e-4, what .. ": max " .. i)
    end
  end
  local parts = { { 0, 0 }, { -0.5, 0.5 }, { -0.75, 0.75 }, { -0.25, -0.25 } }
  check(clip:peaks(4), parts, "whole file")
  local loud = clip:peaks(4)
  near(loud[1][3], 0, 1e-6, "silence has no loudness")
  near(loud[2][3], 0.5 / math.sqrt(2), 0.01, "a sine is as loud as its peak over the root of two")
  near(loud[4][3], 0.25, 1e-4, "a held level is as loud as it reaches")
  check(clip:peaks(8), { parts[1], parts[1], parts[2], parts[2], parts[3], parts[3], parts[4], parts[4] }, "finer")
  check(clip:peaks(1), { { -0.75, 0.75 } }, "one point")
  eq(#clip:peaks(5000), 5000, "more points than samples")

  -- The arrange view draws it under the name, over the rows a track has
  -- left, from each column's lowest to highest sample around the middle (the
  -- waveform's own tests are in tests/waves.lua).
  paw.opt.zoom, paw.opt.track_height = 8, 3
  paw.cursor.set_track(t)
  local text = table.concat(api.ui_snapshot(100, 30), "\n")
  paw.opt.zoom, paw.opt.track_height = 2, "auto"
  local rows = paw.draw.waveform(clip:peaks(8), 2)
  eq(rows[1], "  ▄▄▆▆  ", "silence draws nothing, a column reaches as far as the wave does: " .. rows[1])
  eq(rows[2], "  ▄▄▂▂──", "below the middle, drawn in reverse so the glyph is what is left, and a level held below it is a line: " .. rows[2])
  eq(text:find("▄▆", 1, true) ~= nil, true, "waveform on screen, at four columns for the clip")

  -- Only the part the clip plays, and silence past the end of the file.
  clip.offset, clip.length = 0.0625, 0.25
  check(clip:peaks(2), { parts[2], parts[3] }, "offset and length")
  clip.offset = 0.1875
  check(clip:peaks(2), { parts[4], { 0, 0 } }, "past the end")
  paw.project.tempo = 60
  check(clip:peaks(2), { parts[4], { 0, 0 } }, "a slower tempo plays more of the file")
  paw.project.tempo = 120
  clip.gain = -6.0206
  check(clip:peaks(2), { { -0.125, -0.125 }, { 0, 0 } }, "clip gain")

  local flat = paw.frontend.peaks(clip.id)
  eq(#flat, 3 * paw.frontend.peak_points, "frontend peaks are flat: the reach each way and the loudness")
  eq(#paw.frontend.peaks(clip.id, 512), 3 * 512, "at as many points as the frontend draws")

  local state = paw.frontend.state(-1)
  eq(type(state.clips[1].waveform), "string", "frontend state says when the waveform changes")
  local before = state.clips[1].waveform
  clip.gain = 0
  eq(paw.frontend.state(-1).clips[1].waveform ~= before, true, "and it changes with the clip")
  fails(function() t:add_clip({ start = 2, length = 1 }):peaks(4) end, "only audio clips", "MIDI clip")
end)

test("drums respond to the General MIDI drum notes", function()
  fresh()
  local t = paw.add_track({ name = "drums" })
  t:add_device("drums")
  t:add_clip({ start = 0, length = 4, notes = { { pitch = 36, start = 0, length = 0.25 }, { pitch = 42, start = 1, length = 0.25 } } })
  eq(paw.render(scratch .. "/kick.wav", { start = 0, ["end"] = 0.5, tail = 0 }).peak > 0.1, true, "kick")
  eq(paw.render(scratch .. "/hat.wav", { start = 1, ["end"] = 1.2, tail = 0 }).peak > 0.02, true, "hat")
  eq(paw.render(scratch .. "/rest.wav", { start = 3, ["end"] = 4, tail = 0 }).peak < 0.001, true, "rest")
end)
